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

/// W1a（2026-11-07 材料中心搜索逻辑整改）的**逐屏证据图**：
/// 1. `channel-form.png`：**按形式**频道首屏 —— 9 个子分类 chips（教材/书籍/外刊/
///    论文/四级真题/六级真题/全部真题/碎片文章/其他），验证"四级/六级真题"是否
///    一眼可辨、3 行 chips 是否过密；
/// 2. `channel-filtered.png`：跑完一轮后的**质量过滤汇总可见性** ——
///    顶部结果摘要行下会出现「已过滤 N 条质量不合格的候选（公告/报名页 x、
///    非英文 y、弱相关 z）」，证明过滤不是静默丢弃。
///
/// 出图：build/ui_real/ 与 docs/ui-preview/real/ 双写（390×844 @3x）。
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
    tmp = await Directory.systemTemp.createTemp('rf_w1a_render');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);

    // 按形式频道的上次结果(含四级/六级真题各一条 → 卡片来源胶囊带级标)
    await MaterialChannelStore.saveRun(
      'form:all',
      items: <Map<String, Object?>>[
        <String, Object?>{
          'title': 'CET-4 真题 2024 年 6 月阅读（附答案解析）',
          'url': 'https://example.com/cet4/2024-reading',
          'sourceLabel': 'DeepSeek 搜索 · 教育考试',
          'kind': 'exam',
          'snippet': '大学英语四级真题阅读部分，含答案解析与高频词。',
          'date': '2026-11-01',
        },
        <String, Object?>{
          'title': 'CET-6 真题 2023 年 12 月阅读',
          'url': 'https://example.com/cet6/2023-reading',
          'sourceLabel': 'DeepSeek 搜索 · 教育考试',
          'kind': 'exam',
          'snippet': '六级真题阅读，难度偏高，适合冲刺。',
          'date': '2026-10-28',
        },
        <String, Object?>{
          'title': 'New Concept English 3',
          'url': 'https://example.com/nce/3',
          'sourceLabel': 'DeepSeek 搜索',
          'kind': 'textbook',
          'snippet': '经典教材第三册，长难句密度高。',
        },
        <String, Object?>{
          'title': 'English Grammar in Use (Intermediate)',
          'url': 'https://example.com/grammar',
          'sourceLabel': 'DeepSeek 搜索',
          'kind': 'textbook',
          'snippet': '按语法点分章，补时态最直接。',
        },
        <String, Object?>{
          'title': 'A Christmas Carol',
          'url': 'https://www.gutenberg.org/ebooks/46',
          'sourceLabel': 'Project Gutenberg（公版书）',
          'kind': 'book',
          'snippet': 'Charles Dickens 经典短篇，公版原文全文可读。',
        },
        <String, Object?>{
          'title': 'The Future of Language Learning',
          'url': 'https://example.com/npr/learning',
          'sourceLabel': 'NPR News',
          'kind': 'news',
          'snippet': '外刊报道：AI 如何改变语言学习方式。',
        },
      ],
      apiRequests: 0,
      costCny: 0,
      queriesUsed: const <String>['CET-4 真题阅读', 'CET-6 真题阅读'],
    );
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

  testWidgets('按形式频道首屏：9 个分类 chips（含四级/六级真题）', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: const MaterialChannelScreen(direction: MaterialDirection.form),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('四级真题'), findsWidgets);
    expect(find.text('六级真题'), findsWidgets);
    await _capture(tester, key, 'channel-form.png');
  });

  testWidgets('质量过滤汇总可见：已过滤 N 条（公告/报名页 · 非英文 · 弱相关）',
      (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: MaterialChannelScreen(
            direction: MaterialDirection.form,
            // 仅渲染/质检测试注入：模拟"刚跑完一轮、质量过滤生效"的状态
            debugItems: <Map<String, Object?>>[
              <String, Object?>{
                'title': 'CET-4 真题 2024 年 6 月阅读（附答案解析）',
                'url': 'https://example.com/cet4/2024-reading',
                'sourceLabel': 'DeepSeek 搜索 · 教育考试',
                'kind': 'exam',
                'snippet': '大学英语四级真题阅读部分，含答案解析。',
                'date': '2026-11-01',
              },
              <String, Object?>{
                'title': 'CET-6 真题 2023 年 12 月阅读',
                'url': 'https://example.com/cet6/2023-reading',
                'sourceLabel': 'DeepSeek 搜索 · 教育考试',
                'kind': 'exam',
                'snippet': '六级真题阅读，难度偏高。',
                'date': '2026-10-28',
              },
              <String, Object?>{
                'title': 'New Concept English 3',
                'url': 'https://example.com/nce/3',
                'sourceLabel': 'DeepSeek 搜索',
                'kind': 'textbook',
                'snippet': '经典教材第三册，长难句密度高。',
              },
            ],
            debugNotes: const <String>[
              '已过滤 3 条质量不合格的候选(公告/报名页 1 条、非英文内容 1 条、与分类弱相关 1 条)。',
              '已过滤 4 条质量不合格的候选(公告/报名页 2 条、非英文内容 1 条、与分类弱相关 1 条)。',
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('已过滤'), findsWidgets);
    await _capture(tester, key, 'channel-filtered.png');
  });
}

// ═══════════════════════════════════════════════════════════════════════
// 渲染管线（与 test/material_channel_render_test.dart 同一套）
// ═══════════════════════════════════════════════════════════════════════

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
              fontFamily: _fontFamily, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(fontFamily: _fontFamily, fontSize: 13),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(fontFamily: _fontFamily, fontSize: 13),
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
    final data = bytes!.buffer.asUint8List();
    Directory('build/ui_real').createSync(recursive: true);
    File('build/ui_real/$fileName').writeAsBytesSync(data);
    Directory('docs/ui-preview/real').createSync(recursive: true);
    File('docs/ui-preview/real/$fileName').writeAsBytesSync(data);
    image.dispose();
  });
}
