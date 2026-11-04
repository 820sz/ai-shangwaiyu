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
import 'package:readflow/config/design_tokens.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/material_import_flow.dart';
import 'package:readflow/screens/input/material_library_screen.dart';
import 'package:readflow/screens/input/widgets/category_picker.dart';
import 'package:readflow/screens/input/widgets/fulltext_result_card.dart';
import 'package:readflow/services/database.dart';

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
    final loader = FontLoader('MaterialIcons')
      ..addFont(
          Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
    return;
  }
}

ThemeData _theme() {
  final base = AppTheme.lightTheme;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _fontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _fontFamily),
  );
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String fileName,
) async {
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

Future<void> _seedMaterials() async {
  final db = await DatabaseService.database;
  const rows = <Map<String, Object?>>[
    // 浏览记录:npr 来源
    {
      'kind': 'news',
      'source': 'npr',
      'title': 'For Ukraine\'s Kherson region, a short ceasefire',
      'title_cn': '对乌克兰赫尔松地区而言,短暂停火',
      'word_count': 1010,
      'cefr': 'C1',
      'coverage': 0.74,
      'est_minutes': 6,
      'origin': 'browse',
      'created_at': '2026-11-04T10:00:00',
    },
    {
      'kind': 'news',
      'source': 'npr',
      'title': 'A drag queen brings out the best in a small town',
      'title_cn': '变装皇后让小城看见更好的自己',
      'word_count': 382,
      'cefr': 'B2',
      'coverage': 0.9,
      'est_minutes': 2,
      'origin': 'browse',
      'created_at': '2026-11-03T09:00:00',
    },
    // 浏览记录:gutenberg 来源
    {
      'kind': 'book',
      'source': 'gutenberg',
      'title': 'The Great Gatsby',
      'title_cn': '了不起的盖茨比',
      'word_count': 48000,
      'cefr': 'B2',
      'coverage': 0.88,
      'est_minutes': 180,
      'origin': 'browse',
      'created_at': '2026-11-02T08:00:00',
    },
    // 外部导入:两个分组
    {
      'kind': 'book',
      'source': 'import',
      'title': 'New Horizon College English 2',
      'title_cn': '新视野大学英语 2',
      'word_count': 12000,
      'cefr': 'B1',
      'est_minutes': 60,
      'origin': 'import',
      'group_name': '新视野教材',
      'created_at': '2026-11-01T07:00:00',
    },
    {
      'kind': 'article',
      'source': 'import',
      'title': 'How to write a clear email',
      'title_cn': '如何写一封清楚的邮件',
      'word_count': 620,
      'cefr': 'B1',
      'coverage': 0.94,
      'est_minutes': 4,
      'origin': 'import',
      'group_name': '职场英语',
      'created_at': '2026-10-31T06:00:00',
    },
    {
      'kind': 'article',
      'source': 'import',
      'title': 'My scraped notes',
      'word_count': 300,
      'cefr': 'B2',
      'est_minutes': 2,
      'origin': 'import',
      'created_at': '2026-10-30T05:00:00',
    },
  ];
  for (final r in rows) {
    await db.insert('materials', r);
  }
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
    tmp = await Directory.systemTemp.createTemp('rf_ui_real_input');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    await _seedMaterials();
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

  testWidgets('材料库(浏览/导入分开管理)真实渲染', (tester) async {
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
          home: const MaterialLibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    // 真实 DB 是异步的:给一次真实等待让数据加载完,再截屏
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.text('我的材料库'), findsOneWidget);
    expect(find.textContaining('浏览记录'), findsOneWidget);
    await _capture(tester, key, 'material_library.png');
  });

  testWidgets('导入通道选择器真实渲染', (tester) async {
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
          home: const Scaffold(
            backgroundColor: Color(0xFFF6F6FD),
            body: Center(child: Text('材料中心')),
          ),
        ),
      ),
    );
    final ctx = tester.element(find.text('材料中心'));
    // 直接调生产入口(与点「导入」按钮同一条路径)
    final future = MaterialImportFlow.pickChannel(ctx);
    await tester.pumpAndSettle();
    expect(find.text('粘贴文本'), findsOneWidget);
    await _capture(tester, key, 'import_channel_picker.png');
    future.ignore();
  });

  testWidgets('分类选择弹层真实渲染', (tester) async {
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
          home: const Scaffold(
            backgroundColor: Color(0xFFF6F6FD),
            body: Center(child: Text('识图结果')),
          ),
        ),
      ),
    );
    final ctx = tester.element(find.text('识图结果'));
    final future = showCategoryPicker(ctx);
    await tester.pumpAndSettle();
    expect(find.text('选择保存分类'), findsOneWidget);
    await _capture(tester, key, 'category_picker.png');
    future.ignore();
  });

  testWidgets('全文翻译结果卡真实渲染', (tester) async {
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
          home: Scaffold(
            backgroundColor: const Color(0xFFF6F6FD),
            body: ListView(
              padding: const EdgeInsets.all(Gap.page),
              children: <Widget>[
                const FulltextResultCard(
                  index: 0,
                  original:
                      'The short ceasefire in Kherson region gave residents a '
                      'few hours to restock food and water.',
                  translation: '赫尔松地区的短暂停火让居民有几个小时补充食物和饮水。',
                  onAskExplain: _noop,
                ),
                const FulltextResultCard(
                  index: 1,
                  original:
                      'Officials warned that repair crews would need weeks to '
                      'restore power across the city.',
                  translation: '官员警告,维修人员需要数周时间才能恢复全城供电。',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('段落 1'), findsOneWidget);
    expect(find.text('AI 讲解'), findsOneWidget);
    await _capture(tester, key, 'fulltext_result_card.png');
  });
}

void _noop() {}
