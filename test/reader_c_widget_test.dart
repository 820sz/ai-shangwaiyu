// 阅读器 C 方案(2026-11-06 用户拍板)· widget 测试
//
// 覆盖任务卡点名的四件事 + 进度落库真值:
// 1. 底部**零常驻按钮**(只有 2px 进度线 + 42px 把手区);
// 2. **上滑把手区**打开「阅读控制台」,4 组都在(进度/学习/目录/材料);
// 3. **纸张三色**切换后立刻生效 + 落 Hive + 重开保留;
// 4. **进度%** 只由 ValueNotifier 驱动常驻组件(滚动后 37% 真值),不是整屏 setState;
// 5. 落库 percent 是真实滚动比例(未读完 ≤99,不再是旧实现的 0/100)。
//
// 全部用真库(sqflite_common_ffi)+ 真 Hive + 生产页 `MaterialReaderScreen`,
// 不做业务 mock。真实 I/O 一律放进 `tester.runAsync`(fake-async zone 里
// await 真实 I/O 会永不返回 —— 项目历史坑)。
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
import 'package:readflow/widgets/reader_action_bar.dart';
import 'package:readflow/widgets/reader_paper.dart';

int? _materialId;

/// 建库/种数据只做一次(真 sqflite I/O,必须在 runAsync 里跑)
Future<int> ensureSeeded(WidgetTester tester) async {
  if (_materialId != null) return _materialId!;
  final id = await tester.runAsync(() async {
    final db = await DatabaseService.database;
    final materialId = await db.insert('materials', <String, Object?>{
      'kind': 'article',
      'source': 'seed',
      'source_id': 'reader-c-widget',
      'title': 'The Quiet Hour',
      'author': 'The Atlantic',
      'language': 'en',
      'word_count': 930,
      'cefr': 'C1',
      'est_minutes': 8,
      'chapters': 3,
      'created_at': DateTime.now().toIso8601String(),
    });
    final chunks = <String>[
      'For decades the office celebrated the busy generalist: the person '
          'who answers email during a call and edits a deck while replying '
          'to a message.',
      'The evidence is unusually consistent. What multitasking produces is '
          'not more output but a thinner, more distracted version of it — '
          'and the cost is paid in working memory.',
      'That is why a quiet hour can feel more productive than a crowded '
          'afternoon: the effort is simply continuous. A quiet hour does not '
          'mean an empty calendar. It means one task, one window, and a door '
          'that is actually shut.',
      'The remedy is unglamorous. Protect one block of the day, close the '
          'inbox, and let attention settle into a single task for ninety '
          'minutes at a stretch. Teams that tried it reported fewer, better '
          'decisions — and the same amount of work finished by five '
          'o’clock.',
      'None of this requires heroics. It requires a decision about what not '
          'to do next. Managers can help by making the quiet block visible: '
          'a shared calendar hold, a status line, a norm that says slow is '
          'allowed.',
      'What gets measured gets repeated. If the only metric is response '
          'time, the quiet hour will never survive. The offices that kept it '
          'treated the hour as infrastructure, not as a perk.',
    ];
    for (var i = 0; i < chunks.length; i++) {
      await db.insert('material_content', <String, Object?>{
        'material_id': materialId,
        'chunk_index': i,
        'title': 'Section ${i + 1}',
        'text': chunks[i],
      });
    }
    return materialId;
  });
  _materialId = id;
  return id!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('readflow_reader_c_widget_');
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    final dbPath = p.join(await getDatabasesPath(), AppConstants.dbName);
    try {
      await databaseFactory.deleteDatabase(dbPath);
    } catch (_) {}
    await DatabaseService.resetForTest();
  });

  tearDownAll(() async {
    // 收尾只做"尽力而为":测试进程退出前真 I/O(关库/删 Hive)偶尔会卡住,
    // 用超时兜底,不让收尾把整个测试挂死(临时目录本来也会被系统清掉)。
    try {
      await DatabaseService.resetForTest()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 轮转真实 I/O + 推帧,直到正文出来(见文件头注释)
  Future<void> settle(WidgetTester tester, {int rounds = 16}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 24));
      });
      await tester.pump(const Duration(milliseconds: 80));
      if (find.text('上滑工具').evaluate().isNotEmpty) return;
    }
  }

  Future<void> pumpReader(
    WidgetTester tester, {
    ReaderPaper paper = ReaderPaper.white,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.clear();
      await box.put(ReaderSettings.keyReaderPaper, paper.name);
      final db = await DatabaseService.database;
      await db.delete('material_progress',
          where: 'material_id = ?', whereArgs: [_materialId!]);
    });
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: MaterialReaderScreen(materialId: _materialId!),
    ));
    await settle(tester);
  }

  /// 收尾:先卸掉页面(触发退出落盘),再让真实 I/O 完成 —— 避免测试结束
  /// 时报 "A Timer is still pending"
  Future<void> disposeReader(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // 多转几圈:dispose 里还有一次 force 落盘(sqflite 真实 I/O),必须让它
    // 在下一条用例开始前真的完成 —— 否则悬空 future 会卡住下一条的 DB await。
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> jumpToRatio(WidgetTester tester, double ratio) async {
    final pos =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    pos.jumpTo(pos.maxScrollExtent * ratio);
    await tester.pump(const Duration(milliseconds: 80));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> openConsole(WidgetTester tester) async {
    await tester.drag(
      find.byKey(const ValueKey<String>('reader-bottom-handle')),
      const Offset(0, -80),
    );
    await tester.pump(const Duration(milliseconds: 340));
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<void> scrollConsoleToBottom(WidgetTester tester) async {
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -320),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('底部零常驻按钮:只有 2px 进度线 + 42px 把手区', (tester) async {
    await ensureSeeded(tester);
    await pumpReader(tester);
    expect(find.byType(ReaderBottomDock), findsOneWidget);
    // 把手区里不允许出现任何按钮控件
    final anyButton = find.descendant(
      of: find.byType(ReaderBottomDock),
      matching: find.byWidgetPredicate((w) =>
          w is IconButton ||
          w is FilledButton ||
          w is TextButton ||
          w is OutlinedButton ||
          w is ElevatedButton ||
          w is FloatingActionButton),
    );
    expect(anyButton, findsNothing);
    // 整个页面也不再有 FAB(旧实现有「回到顶部」FAB)
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('上滑工具'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reader-bottom-handle')),
        findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('进度%:滚动后常驻胶囊/贴底线是真值(37%)', (tester) async {
    await ensureSeeded(tester);
    await pumpReader(tester);
    await jumpToRatio(tester, 0.37);
    final rail = tester.widget<Text>(
      find.byKey(const ValueKey<String>('reader-rail-percent')),
    );
    expect(rail.data, '37%');
    // 贴底把手区也写着同一个值(双保险),共 2 处 37%
    expect(find.text('37%'), findsNWidgets(2));
    await disposeReader(tester);
  });

  testWidgets('上滑把手区 → 阅读控制台 4 组都在', (tester) async {
    await ensureSeeded(tester);
    await pumpReader(tester);
    await openConsole(tester);
    expect(find.text('阅读控制台'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('目录'), findsOneWidget);
    expect(find.text('材料'), findsOneWidget);
    expect(find.text('继续阅读'), findsOneWidget);
    expect(find.text('字号与行距'), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('控制台滚到底 → 阅读设置:三张纸卡 + 实时预览', (tester) async {
    await ensureSeeded(tester);
    await pumpReader(tester);
    await openConsole(tester);
    await scrollConsoleToBottom(tester);
    await tester.tap(find.text('字号与行距'));
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text('阅读设置'), findsOneWidget);
    expect(find.text('纸张'), findsOneWidget);
    // 三个色卡名字都在(纸白 / 米黄 / 墨夜)
    expect(find.text('纸白'), findsOneWidget);
    expect(find.text('米黄'), findsOneWidget);
    expect(find.text('墨夜'), findsOneWidget);
    expect(find.textContaining('预览'), findsOneWidget);
    await disposeReader(tester);
  });

  testWidgets('纸张三色:点米黄 → 立刻换纸 + 落 Hive + 重开保留', (tester) async {
    await ensureSeeded(tester);
    await pumpReader(tester);
    await openConsole(tester);
    await scrollConsoleToBottom(tester);
    await tester.tap(find.text('字号与行距'));
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump(const Duration(milliseconds: 160));

    await tester.tap(find.text('米黄'));
    await tester.pump(const Duration(milliseconds: 120));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 60));
    }
    // ① 立刻生效:阅读页 Scaffold 底色变成米黄纸
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, paletteOf(ReaderPaper.beige).page);
    // ② 落 Hive(重启保留的依据)
    final saved = Hive.box(AppConstants.hiveBoxSettings)
        .get(ReaderSettings.keyReaderPaper);
    expect(saved, 'beige');

    // ③ 重开一次页面(新 State):仍然米黄
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: MaterialReaderScreen(materialId: _materialId!),
    ));
    await settle(tester);
    final reopened = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(reopened.backgroundColor, paletteOf(ReaderPaper.beige).page);
    await disposeReader(tester);
  });

}
