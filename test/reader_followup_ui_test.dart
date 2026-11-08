// 阅读器专项交互 · 定向 widget 测试（2026-11-08 / task-21）
//
// 覆盖用户三条反馈的交互面（不出渲染图，按 Lead 要求省时）：
// A. 追问抽屉：阅读场景只留「梳理内容」「评价材料」两个快捷提问，
//    英英词典/逐句翻译等识图场景常置按钮不再出现；
// B. 丰富形式：点击后弹的是"选形式" sheet（不是静默滚到文末），且关闭后
//    阅读位置保持不动；
// C. 点右上角 % 胶囊 → 小菜单「回到顶部 / 跳到底部」，平滑滚动且进度照常更新。
//
// 用真库（sqflite_common_ffi）+ 生产页 `MaterialReaderScreen`，真实 I/O 一律
// 放 runAsync（fake-async zone 里 await 真实 I/O 会永不返回 —— 项目历史坑）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/material_reader_screen.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/reader_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  int? materialId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('readflow_reader_followup_ui_');
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    final dbPath = p.join(await getDatabasesPath(), AppConstants.dbName);
    try {
      await databaseFactory.deleteDatabase(dbPath);
    } catch (_) {}
    await DatabaseService.resetForTest();
  });

  tearDownAll(() async {
    try {
      await DatabaseService.resetForTest().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpReader(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    materialId ??= await tester.runAsync(() async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.clear();
      await box.put(ReaderSettings.keyReaderPaper, ReaderPaper.white.name);
      final db = await DatabaseService.database;
      final id = await db.insert('materials', <String, Object?>{
        'kind': 'article',
        'source': 'seed',
        'source_id': 'reader-followup-ui',
        'title': 'The Quiet Hour',
        'author': 'The Atlantic',
        'language': 'en',
        'word_count': 930,
        'cefr': 'C1',
        'est_minutes': 8,
        'created_at': DateTime.now().toIso8601String(),
      });
      final chunks = <String>[
        'For decades the office celebrated the busy generalist: the person '
            'who answers email during a call and edits a deck while replying '
            'to a message.',
        'The evidence is unusually consistent. What multitasking produces is '
            'not more output but a thinner, more distracted version of it.',
        'That is why a quiet hour can feel more productive than a crowded '
            'afternoon: the effort is simply continuous.',
        'The remedy is unglamorous. Protect one block of the day, close the '
            'inbox, and let attention settle into a single task for ninety '
            'minutes at a stretch.',
        'None of this requires heroics. It requires a decision about what not '
            'to do next.',
        'What gets measured gets repeated. If the only metric is response '
            'time, the quiet hour will never survive.',
      ];
      for (var i = 0; i < chunks.length; i++) {
        await db.insert('material_content', <String, Object?>{
          'material_id': id,
          'chunk_index': i,
          'title': 'Section ${i + 1}',
          'text': chunks[i],
        });
      }
      return id;
    });
    await tester.runAsync(() async {
      final db = await DatabaseService.database;
      await db.delete('material_progress',
          where: 'material_id = ?', whereArgs: [materialId]);
    });
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: MaterialReaderScreen(materialId: materialId!),
    ));
    // 真实 I/O（runAsync 轮转）+ 推帧，直到正文出来
    for (var i = 0; i < 16; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 24));
      });
      await tester.pump(const Duration(milliseconds: 80));
      if (find.text('上滑工具').evaluate().isNotEmpty) break;
    }
  }

  Future<void> disposeReader(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> openConsole(WidgetTester tester) async {
    await tester.tap(find.text('上滑工具'));
    await tester.pump(const Duration(milliseconds: 340));
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('A. 追问抽屉:阅读场景只剩「梳理内容」「评价材料」两个快捷提问',
      (tester) async {
    await pumpReader(tester);
    await openConsole(tester);
    // 控制台「学习 → 追问」→ 抽屉
    await tester.tap(find.text('追问'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('梳理内容'), findsOneWidget);
    expect(find.text('评价材料'), findsOneWidget);
    // 识图场景的常置按钮不应再出现在阅读追问里
    expect(find.text('英英词典'), findsNothing);
    expect(find.text('逐句翻译'), findsNothing);
    expect(find.text('考我一下'), findsNothing);
    await disposeReader(tester);
  });

  testWidgets('B. 丰富形式:打开的是选形式 sheet,不是滚到文末;关闭后阅读位置不变',
      (tester) async {
    await pumpReader(tester);
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    final pos = scrollable.position;
    pos.jumpTo(pos.maxScrollExtent * 0.4);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    final before = pos.pixels;
    expect(before, greaterThan(0));

    await openConsole(tester);
    // 控制台内容滚到底才看得到「丰富形式」
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -320),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('丰富形式'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));

    // sheet 真的弹出来了（不是滚到文末）
    expect(find.text('丰富阅读形式'), findsOneWidget);
    // 阅读位置没有被挪走
    expect((pos.pixels - before).abs(), lessThan(1.0));

    // 关掉 sheet：兜底逻辑也不应该把阅读位置改掉
    Navigator.of(tester.element(find.text('丰富阅读形式'))).pop();
    await tester.pump(const Duration(milliseconds: 340));
    await tester.pump(const Duration(milliseconds: 120));
    expect((pos.pixels - before).abs(), lessThan(1.0));
    await disposeReader(tester);
  });

  testWidgets('C. % 胶囊菜单:回到顶部 / 跳到底部 都生效(平滑滚动+进度更新)',
      (tester) async {
    await pumpReader(tester);
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    final pos = scrollable.position;
    final max = pos.maxScrollExtent;
    expect(max, greaterThan(0));
    // 初始 0%
    var badge = tester.widget<Text>(
      find.byKey(const ValueKey<String>('reader-rail-percent')),
    );
    expect(badge.data, '0%');

    // 点 % 胶囊 → 小菜单
    await tester.tap(find.byKey(const ValueKey<String>('reader-rail-percent')));
    await tester.pump(const Duration(milliseconds: 340));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('回到顶部'), findsOneWidget);
    expect(find.text('跳到底部'), findsOneWidget);

    // 跳到底部
    await tester.tap(find.text('跳到底部'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect((pos.pixels - max).abs(), lessThan(2.0));
    badge = tester.widget<Text>(
      find.byKey(const ValueKey<String>('reader-rail-percent')),
    );
    expect(badge.data, '99%');

    // 再开菜单 → 回到顶部
    await tester.tap(find.byKey(const ValueKey<String>('reader-rail-percent')));
    await tester.pump(const Duration(milliseconds: 340));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('回到顶部'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(pos.pixels, lessThan(2.0));
    badge = tester.widget<Text>(
      find.byKey(const ValueKey<String>('reader-rail-percent')),
    );
    expect(badge.data, '0%');
    await disposeReader(tester);
  });
}
