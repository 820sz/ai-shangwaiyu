import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/material_channel_screen.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/material_channel.dart';
import 'package:readflow/services/material_taxonomy.dart';

/// 材料中心 · 频道页的**真实渲染图**(2026-11-06 修复后重出)。
///
/// 出 4 张(写进 `build/ui_real/`,由人工/脚本复制到 `docs/ui-preview/real/`):
/// 1. `channel-discover-p1.png` 发现第 1 页:顶部分类条(chips)在顶部、
///    10 条结果按类型分组、**无封面的卡片走文字版式**;
/// 2. `channel-discover-p2.png` 发现第 2 页:从第 1 页底部点「下一页」翻过去后
///    再滚到底 —— 页码控件显示「第 2 / 2 页」、上一页可用 / 下一页禁用,
///    顶部分类条已随滚动滚走、只留紧凑范围条;
/// 3. `channel-my-p1.png` 「我的」第 1 页:同一套页码控件(3 篇 → 第 1 / 1 页),
///    有真封面才显示真封面,否则标题 + 中文标题 + 来源/难度的文字版式;
/// 4. `channel-no-cover.png` 无封面卡片:3 条结果一屏放得下,能完整看清
///    "没有封面图时卡片长什么样"(文字版式 / 无渐变假封面 / 页码 1/1)。
///
/// 为什么要等 `runAsync`:频道页要读 Hive 快照 + FFI SQLite 材料库,
/// 这些都是真实异步 I/O,pumpAndSettle 的假时钟不会推进它们。
const String _fontFamily = 'PreviewCJK';

Future<void> _loadFont() async {
  for (final path in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes =
        Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
    await (FontLoader('Roboto')..addFont(bytes)).load();
    await (FontLoader(_fontFamily)..addFont(bytes)).load();
    return;
  }
}

Future<void> _loadIcons() async {
  for (final path in <String>[
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()))))
        .load();
    return;
  }
}

ThemeData _theme() {
  final base = AppTheme.lightTheme;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _fontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _fontFamily),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(
              fontFamily: _fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(fontFamily: _fontFamily, fontSize: 14),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(fontFamily: _fontFamily, fontSize: 14),
        ),
      ),
    ),
  );
}

Future<void> _capture(
    WidgetTester tester, GlobalKey key, String fileName) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/ui_real').createSync(recursive: true);
    File('build/ui_real/$fileName')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// 与频道页 topic 无子分类时的 id 一致（MaterialChannelScreen 注释里约定）
const String _channelId = 'topic:all';

/// 等真实的 Hive/SQLite 异步读完(假时钟推不动 I/O)。
///
/// **不用 `pumpAndSettle`**:页面里有入场动画(AppStagger)/淡入(AnimatedOpacity)
/// /封面图加载,任何一个"持续要帧"都会让 pumpAndSettle 死等(实测 2 分钟不返回,
/// 而且 --timeout 也不触发)。这里改成**有界 pump**:推固定帧数,能出图即可,
/// 不追求"完全静止"。
Future<void> _settle(WidgetTester tester, {int ms = 900}) async {
  await _pumpFrames(tester, frames: 6);
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await _pumpFrames(tester, frames: 10);
}

/// 有界推帧(替代 pumpAndSettle,永不悬挂)
Future<void> _pumpFrames(
  WidgetTester tester, {
  int frames = 6,
  Duration step = const Duration(milliseconds: 80),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

/// 把当前 Tab 的列表拖到底部(用固定步数,不依赖具体内容高度)
Future<void> _dragToBottom(WidgetTester tester, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -400),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await _pumpFrames(tester, frames: 4);
}

Future<void> _pumpChannel(WidgetTester tester, GlobalKey key) async {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: const MaterialChannelScreen(direction: MaterialDirection.topic),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _loadFont();
    await _loadIcons();
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_channel_render');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    await Hive.close();
    try {
      await databaseFactory
          .deleteDatabase(p.join(tmp.path, AppConstants.dbName));
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 12 条发现结果(4 个分组):一页 10 条 → 2 页,且页内能看成分组
  Future<void> seedTwelve() async {
    final items = <Map<String, Object?>>[
      for (var i = 0; i < 5; i++)
        <String, Object?>{
          'title': 'New Concept English ${i + 1}: Reading and Writing',
          'url': 'https://example.com/nce/${i + 1}',
          'sourceLabel': 'DeepSeek 搜索 · 外语教学',
          'kind': 'textbook',
          'snippet': '经典教材系列第 ${i + 1} 册,适合系统学习语法与表达。',
          'date': '2026-11-0${i + 1}',
        },
      for (var i = 0; i < 3; i++)
        <String, Object?>{
          'title': 'CET-4 历年真题 202${i + 3} 阅读',
          'url': 'https://example.com/cet4/${i + 1}',
          'sourceLabel': 'DeepSeek 搜索 · 教育考试',
          'kind': 'exam',
          'snippet': '四六级历年真题阅读部分,含答案解析与高频词。',
          'date': '2026-10-2$i',
        },
      for (var i = 0; i < 2; i++)
        <String, Object?>{
          'title': 'The Four Million',
          'url': 'https://www.gutenberg.org/ebooks/8962',
          'sourceLabel': 'Project Gutenberg',
          'kind': 'book',
          'snippet': 'O. Henry 的短篇小说集,公版原文全文可读。',
        },
      for (var i = 0; i < 2; i++)
        <String, Object?>{
          'title': 'AI and the future of language learning',
          'url': 'https://example.com/news/${i + 1}',
          'sourceLabel': 'NPR',
          'kind': 'news',
          'snippet': '外刊报道:AI 如何改变语言学习方式。',
        },
    ];
    await MaterialChannelStore.saveRun(
      _channelId,
      items: items,
      apiRequests: 3,
      costCny: 0.015,
      queriesUsed: const <String>['new concept english', 'cet-4 reading'],
    );
  }

  /// 「我的」数据:两条已保存 + 一条普通库材料(不在 saved 里)
  Future<void> seedMine() async {
    final db = await DatabaseService.database;
    final id1 = await db.insert('materials', <String, Object?>{
      'kind': 'textbook',
      'source': 'import',
      'title': 'New Concept English 3',
      'title_cn': '新概念英语 第三册',
      'word_count': 12000,
      'cefr': 'B1',
      'est_minutes': 60,
      'origin': 'import',
      'created_at': '2026-11-04T10:00:00',
    });
    final id2 = await db.insert('materials', <String, Object?>{
      'kind': 'exam',
      'source': 'import',
      'title': 'CET-4 真题 2024',
      'title_cn': '四级真题 2024',
      'word_count': 8000,
      'cefr': 'B1',
      'est_minutes': 40,
      'origin': 'import',
      'created_at': '2026-11-03T10:00:00',
    });
    await db.insert('materials', <String, Object?>{
      'kind': 'book',
      'source': 'gutenberg',
      'title': 'The Four Million',
      'title_cn': '四百万',
      'word_count': 2400,
      'cefr': 'C1',
      'est_minutes': 11,
      'origin': 'browse',
      'created_at': '2026-11-02T10:00:00',
    });
    await MaterialChannelStore.addSavedMaterial(_channelId, id1);
    await MaterialChannelStore.addSavedMaterial(_channelId, id2);
  }

  testWidgets('频道页 发现第1页 / 发现第2页 / 我的第1页 真实渲染', (tester) async {
    debugPrint('STEP 1/5 seed data');
    // 注意:testWidgets 体里跑在 fake-async zone,直接 await Hive/SQLite 的真实
    // I/O 永远不会完成(实测卡死且 --timeout 不触发)。必须包进 runAsync,
    // 让真实事件循环转起来 —— 这也是原版渲染测试把 seed 放在 setUp 的原因。
    await tester.runAsync(() async {
      await seedTwelve();
      await seedMine();
    });
    debugPrint('STEP 2/5 pump channel');
    final key = GlobalKey();
    await _pumpChannel(tester, key);
    debugPrint('STEP 3/5 capture p1');
    // ① 发现第 1 页(顶部:分类条还在)
    expect(find.text('发现'), findsWidgets);
    expect(find.text('全部'), findsOneWidget);
    await _capture(tester, key, 'channel-discover-p1.png');
    debugPrint('STEP 4/5 paging to p2');
    // ①.5 顶部分类条滚走后:紧凑范围条顶替(需求 B 的可视证据)
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -260),
    );
    await _pumpFrames(tester, frames: 6);
    await _capture(tester, key, 'channel-collapsed.png');
    // 点「改范围」滚回顶部,继续翻页流程
    await tester.tap(find.text('改范围'));
    await _pumpFrames(tester, frames: 8);
    // ② 翻到第 2 页:先滚到底点「下一页」,新一页从顶部开始,再滚到底看页码
    await _dragToBottom(tester);
    await tester.tap(find.text('下一页'));
    await _pumpFrames(tester, frames: 8);
    expect(find.text('第 2 / 2 页'), findsOneWidget);
    await _dragToBottom(tester);
    await _capture(tester, key, 'channel-discover-p2.png');
    debugPrint('STEP 5/5 my tab');
    // ③ 「我的」第 1 页
    await tester.tap(find.text('我的').first);
    await _pumpFrames(tester, frames: 8);
    await _settle(tester, ms: 500);
    // 方向级保存关系里只有 seedMine 保存的 2 条(第 3 条只是库里的普通材料,
    // 没选子分类时不做"旧逻辑匹配",不该出现在「我的」)
    expect(find.text('频道材料 2 篇'), findsOneWidget);
    await _capture(tester, key, 'channel-my-p1.png');
    debugPrint('STEP done');
  });

  testWidgets('无封面卡片 真实渲染(3 条一屏,文字版式)', (tester) async {
    debugPrint('STEP no-cover seed');
    // 同上:真实 I/O 必须放在 runAsync 里,否则 fake-async zone 永远等不到完成
    await tester.runAsync(() async {
      await MaterialChannelStore.saveRun(
        _channelId,
        items: <Map<String, Object?>>[
          <String, Object?>{
            'title': 'How to Take Smart Notes',
            'url': 'https://example.com/smart-notes',
            'sourceLabel': 'Farnam Street',
            'kind': 'article',
          },
          <String, Object?>{
            'title': 'The Science of Sleep and Memory',
            'url': 'https://example.com/sleep-memory',
            'sourceLabel': 'NPR',
            'kind': 'article',
          },
          <String, Object?>{
            'title': 'Why We Read: The Case for Deep Reading',
            'url': 'https://example.com/why-we-read',
            'sourceLabel': 'The Atlantic',
            'kind': 'article',
          },
        ],
        apiRequests: 1,
        costCny: 0.005,
        queriesUsed: const <String>['reading'],
      );
    });

    debugPrint('STEP no-cover pump');
    final key = GlobalKey();
    await _pumpChannel(tester, key);
    debugPrint('STEP no-cover capture');
    // 3 条结果 = 1 页:页码控件与 3 张"无封面"卡片一屏内全部可见
    expect(find.text('第 1 / 1 页'), findsOneWidget);
    await _capture(tester, key, 'channel-no-cover.png');
    debugPrint('STEP no-cover done');
  });
}
