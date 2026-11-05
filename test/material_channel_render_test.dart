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

    // ① 发现 Tab 的快照（12 条，覆盖 4 个分组 + 触发分页按钮）
    final items = <Map<String, Object?>>[
      for (var i = 0; i < 5; i++)
        <String, Object?>{
          'title': 'New Concept English ${i + 1}: Reading and Writing',
          'url': 'https://example.com/nce/${i + 1}',
          'sourceLabel': 'DeepSeek 搜索 · 外语教学',
          'kind': 'textbook',
          'snippet': '经典教材系列第 ${i + 1} 册，适合系统学习语法与表达。',
          'date': '2026-11-0${i + 1}',
        },
      for (var i = 0; i < 3; i++)
        <String, Object?>{
          'title': 'CET-4 历年真题 202${i + 3} 阅读',
          'url': 'https://example.com/cet4/${i + 1}',
          'sourceLabel': 'DeepSeek 搜索 · 教育考试',
          'kind': 'exam',
          'snippet': '四六级历年真题阅读部分，含答案解析与高频词。',
          'date': '2026-10-2$i',
        },
      for (var i = 0; i < 2; i++)
        <String, Object?>{
          'title': 'The Four Million',
          'url': 'https://www.gutenberg.org/ebooks/8962',
          'sourceLabel': 'Project Gutenberg',
          'kind': 'book',
          'snippet': 'O. Henry 的短篇小说集，公版原文全文可读。',
        },
      for (var i = 0; i < 2; i++)
        <String, Object?>{
          'title': 'AI and the future of language learning',
          'url': 'https://example.com/news/${i + 1}',
          'sourceLabel': 'NPR',
          'kind': 'news',
          'snippet': '外刊报道：AI 如何改变语言学习方式。',
        },
    ];
    await MaterialChannelStore.saveRun(
      _channelId,
      items: items,
      apiRequests: 3,
      costCny: 0.015,
      queriesUsed: const <String>['new concept english', 'cet-4 reading'],
    );

    // ② 我的 Tab 的材料：两条已保存 + 一条普通库材料（不在 saved 里）
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

  testWidgets('频道页(发现/我的)真实渲染', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: const MaterialChannelScreen(direction: MaterialDirection.topic),
      ),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('发现'), findsWidgets);
    await _capture(tester, key, 'material_channel_discover.png');

    // 我的 Tab
    await tester.tap(find.text('我的').first);
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
    await _capture(tester, key, 'material_channel_my.png');
  });
}
