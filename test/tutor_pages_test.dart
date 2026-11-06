import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/models/learning_record.dart';
import 'package:readflow/models/writing_log.dart';
import 'package:readflow/providers/bookmark_provider.dart';
import 'package:readflow/providers/stats_provider.dart';
import 'package:readflow/providers/vocab_provider.dart';
import 'package:readflow/screens/profile/about_screen.dart';
import 'package:readflow/screens/profile/api_settings.dart';
import 'package:readflow/screens/profile/appearance_screen.dart';
import 'package:readflow/screens/profile/backup_screen.dart';
import 'package:readflow/screens/profile/error_archive_screen.dart';
import 'package:readflow/screens/profile/profile_home.dart';
import 'package:readflow/screens/profile/stats_page.dart';
import 'package:readflow/screens/profile/weekly_report_screen.dart';
import 'package:readflow/screens/profile/widget_settings_screen.dart';
import 'package:readflow/screens/tutor/placement_test_screen.dart';
import 'package:readflow/screens/tutor/tutor_chat_screen.dart';
import 'package:readflow/screens/tutor/tutor_home.dart';
import 'package:readflow/screens/tutor/tutor_interview_screen.dart';
import 'package:readflow/screens/tutor/tutor_review_screen.dart';
import 'package:readflow/screens/tutor/tutor_task_detail_screen.dart';
import 'package:readflow/screens/writing/writing_logs_screen.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/tutor_engine.dart';
import 'package:readflow/services/tutor_snapshot.dart';

/// 助理 / 我的 两板块 v5 实施的**逐屏真实渲染 + 交互测试**。
///
/// 为什么要真渲:用户验收口径是"不是一张代表图,而是每个屏都渲染出来自检"
/// (`docs/IMPLEMENT-PLAN-2026-11-06.md` §0.2)。这里用真的屏幕组件 +
/// 真的数据库(sqflite ffi)+ 真的 Hive + 真的中文字体渲染,和装到手机上的
/// 观感一致;唯一不同的是数据是播种的(不联网)。
///
/// 产物:`build/ui_real/assist-mine-impl-*.png`(390×844 @3x),
/// 由人工复制到 `docs/ui-preview/real/` 后给用户看。

const String _ff = 'PreviewCJK';

Future<void> _loadFont() async {
  for (final String path in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ]) {
    final File f = File(path);
    if (!f.existsSync()) continue;
    // 同一个中文字体注册成多个族名:显式写了 fontFamily('monospace' 等)的
    // 控件(按钮内置样式、IPA、代码样式)在测试里才不会落回 Ahem 方块。
    for (final String family in <String>[
      'Roboto',
      _ff,
      'monospace',
      'Noto Sans',
      'Noto Sans SC',
      'sans-serif',
    ]) {
      final Future<ByteData> bytes =
          Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
      await (FontLoader(family)..addFont(bytes)).load();
    }
    // IPA/音标需要 Latin 字形:把 Windows 自带字体也注册成兜底族
    for (final String lp in <String>[
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\arial.ttf',
    ]) {
      final File lf = File(lp);
      if (!lf.existsSync()) continue;
      final String family = lp.contains('segoeui') ? 'Segoe UI' : 'Arial';
      final Future<ByteData> bytes =
          Future<ByteData>.value(ByteData.sublistView(lf.readAsBytesSync()));
      await (FontLoader(family)..addFont(bytes)).load();
    }
    return;
  }
}

Future<void> _loadIcons() async {
  for (final String path in <String>[
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ]) {
    final File f = File(path);
    if (!f.existsSync()) continue;
    final FontLoader loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
    return;
  }
}

ThemeData _theme() {
  final ThemeData base = AppTheme.lightTheme;
  const List<String> fallback = <String>[
    _ff,
    'Noto Sans',
    'Segoe UI',
    'Arial',
    'sans-serif',
  ];
  TextStyle cjk(TextStyle? s, {double? size, FontWeight? weight}) =>
      (s ?? const TextStyle()).copyWith(
        fontFamily: _ff,
        fontFamilyFallback: fallback,
        fontSize: size,
        fontWeight: weight,
      );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: _ff,
      fontFamilyFallback: fallback,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: _ff,
      fontFamilyFallback: fallback,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          cjk(base.textTheme.labelLarge, size: 14, weight: FontWeight.w700),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          cjk(base.textTheme.labelLarge, size: 14),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          cjk(base.textTheme.labelLarge, size: 14),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: cjk(base.textTheme.labelLarge, size: 13),
      secondaryLabelStyle: cjk(base.textTheme.labelSmall, size: 11),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      textStyle: cjk(base.textTheme.bodyMedium, size: 14),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      titleTextStyle: cjk(base.textTheme.titleLarge, weight: FontWeight.w700),
      contentTextStyle: cjk(base.textTheme.bodyMedium, size: 14),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      contentTextStyle: cjk(base.textTheme.bodyMedium, size: 13),
    ),
  );
}

/// 固定"现在",让渲染图与单测都可复现(2026-11-06 周五 20:30)
final DateTime _now = DateTime(2026, 11, 6, 20, 30);

Directory? _tmp;
TutorDashboard? _dash;
List<Map<String, Object?>> _taskRows = const <Map<String, Object?>>[];

Future<void> _seed() async {
  // 1) 今天的任务(3 条:待做 / 进行中 / 已完成)
  final int id1 = await DatabaseService.insertTutorTask(
    planDate: _now,
    kind: 'review',
    title: '复习 42 个到期词',
    targetMinutes: 12,
    origin: 'auto',
    goalTag: 'vocab',
    payload: <String, Object?>{
      'reason': '3 天内到期 · 复习准确率 82%',
      'jump': 'review',
      'jumpArg': null,
    },
  );
  final int id2 = await DatabaseService.insertTutorTask(
    planDate: _now,
    kind: 'reading',
    title: '精读《The Four Million》第二节',
    targetMinutes: 20,
    origin: 'auto',
    goalTag: 'reading',
    payload: <String, Object?>{
      'reason': '近 7 天只读完 1 篇 · 平均 148 wpm',
      'jump': 'reading',
      'jumpArg': null,
    },
  );
  await DatabaseService.insertTutorTask(
    planDate: _now,
    kind: 'output',
    title: '回译昨天那句译文',
    targetMinutes: 7,
    origin: 'auto',
    goalTag: 'output',
    payload: <String, Object?>{
      'reason': '冠词错误最近出现 5 次',
      'jump': 'output',
      'jumpArg': null,
    },
  );
  await DatabaseService.updateTutorTaskStatus(id2, 'active');
  await DatabaseService.completeTutorTask(id1);

  // 2) 近 7 天学习日志(让统计/周报/热力/柱状都有真实数据)
  final List<int> newWords = <int>[4, 9, 0, 12, 6, 3, 8];
  final List<int> reviewed = <int>[10, 18, 0, 26, 14, 5, 12];
  for (var i = 0; i < 7; i++) {
    await DatabaseService.upsertDailyLog(
      LearningRecord(
        date: _now.subtract(Duration(days: 6 - i)),
        newWordsCount: newWords[i],
        reviewedCount: reviewed[i],
        exerciseCompleted: i.isEven ? 1 : 0,
        studyMinutes: 10 + i * 3,
      ),
    );
  }

  // 3) 错误档案(让「错误档案」页有真实 7 类)
  final Database db = await DatabaseService.database;
  final List<List<Object?>> tags = <List<Object?>>[
    <Object?>['时态', 7, 'writing', '11-05'],
    <Object?>['冠词', 5, 'exercise', '11-04'],
    <Object?>['搭配', 4, 'review', '11-05'],
    <Object?>['拼写', 3, 'writing', '11-02'],
    <Object?>['语序', 2, 'reading_quiz', '10-30'],
    <Object?>['单复数', 1, 'review', '10-29'],
    <Object?>['标点', 1, 'writing', '11-01'],
  ];
  for (final List<Object?> t in tags) {
    try {
      await db.insert('error_tags', <String, Object?>{
        'tag': t[0],
        'count': t[1],
        'status': 'active',
        'source': t[2],
        'first_at': '2026-10-20T10:00:00',
        'last_at': '2026-${t[3]}T10:00:00',
        'evidence': '示例:He go to school yesterday.',
      });
    } catch (_) {
      // 列名若有差异不让渲染整体失败(错误档案会显示空态)
    }
  }

  // 4) 写译记录(让「我的」与写译记录页有真实条数)
  for (var i = 0; i < 3; i++) {
    await DatabaseService.insertWritingLog(
      WritingLog(
        sourceType: 'electronic',
        originalText: 'The city is very beautiful in autumn.',
        correctedText: 'The city is beautiful in autumn.',
        score: '${76 + i}',
        summary: '表达准确,冠词与介词可再打磨。',
        createdAt: _now.subtract(Duration(days: i + 1)),
      ),
    );
  }

  // 5) 在读材料(统计页「最近在读」)
  try {
    await db.insert('materials', <String, Object?>{
      'kind': 'book',
      'source': 'gutenberg',
      'title': 'The Four Million',
      'title_cn': '四百万',
      'word_count': 2400,
      'cefr': 'C1',
      'est_minutes': 11,
      'origin': 'browse',
      'percent': 62,
      'created_at': '2026-11-02T10:00:00',
    });
  } catch (_) {}

  _taskRows = await DatabaseService.listTutorTasks(limit: 20);
  _dash = await TutorSnapshotService.load(now: _now);
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String fileName) async {
  await tester.pump();
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 3);
    final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/ui_real').createSync(recursive: true);
    File('build/ui_real/$fileName').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// 渲染一屏:真实组件 + 真实 Provider + 固定尺寸;等真实异步(I/O)落地后截图。
Future<void> _render(
  WidgetTester tester,
  String fileName,
  Widget screen, {
  bool providers = true,
}) async {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  final GlobalKey key = GlobalKey();
  final Widget app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    // 真机有状态栏:用 MediaQuery 兜一个 44px 顶部安全区(否则标题贴顶)
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(390, 844),
        padding: EdgeInsets.only(top: 44),
        viewPadding: EdgeInsets.only(top: 44),
        devicePixelRatio: 1,
      ),
      child: RepaintBoundary(key: key, child: screen),
    ),
  );
  final Widget wrapped = providers
      ? MultiProvider(
          providers: [
            ChangeNotifierProvider<StatsProvider>(
              create: (_) => StatsProvider(),
            ),
            ChangeNotifierProvider<VocabProvider>(
              create: (_) => VocabProvider(),
            ),
            ChangeNotifierProvider<BookmarkProvider>(
              create: (_) => BookmarkProvider(),
            ),
          ],
          child: app,
        )
      : app;
  await tester.pumpWidget(wrapped);
  await tester.pump();
  // 真实 I/O(DB/Hive/资源)在 fake-async 里 await 不会推进 —— 反复用 runAsync
  // 给真实事件循环时间,再 pump 让 setState 的帧落地。数据库首次建表较慢,
  // 单次 450ms 不够(会截到骨架屏),这里给足 6×300ms 并逐轮重绘。
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 80));
  }
  await _capture(tester, key, fileName);
  // 一些屏幕会挂短计时器(动画/防抖/刷新):拆掉树并把它们跑完,
  // 否则 teardown 会报 "A Timer is still pending"(与功能无关的假失败)。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _loadFont();
    await _loadIcons();
  });

  setUp(() async {
    _tmp = await Directory.systemTemp.createTemp('rf_brief_render');
    await databaseFactory.setDatabasesPath(_tmp!.path);
    await DatabaseService.resetForTest();
    Hive.init(_tmp!.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    await _seed();
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    await Hive.close();
    try {
      await databaseFactory.deleteDatabase(p.join(_tmp!.path, AppConstants.dbName));
    } catch (_) {}
    if (_tmp != null && _tmp!.existsSync()) _tmp!.deleteSync(recursive: true);
  });

  // ── 逐屏渲染(命名与 docs/ASSISTANT-MINE-IMPLEMENT.md 对照表一一对应)──
  testWidgets('render 助理首页(B 每日简报)', (WidgetTester tester) async {
    await _render(
      tester,
      'assist-mine-impl-assistant-home.png',
      TutorHomeScreen(previewDashboard: _dash, previewTasks: _taskRows),
    );
  });

  testWidgets('render 任务详情(A 诊断台)', (WidgetTester tester) async {
    await _render(
      tester,
      'assist-mine-impl-task-detail.png',
      TutorTaskDetailScreen(row: _taskRows.first),
      providers: false,
    );
  });

  testWidgets('render 现状与复盘(A 诊断台)', (WidgetTester tester) async {
    await _render(
      tester,
      'assist-mine-impl-review.png',
      TutorReviewScreen(dashboard: _dash!),
      providers: false,
    );
  });

  // 其余屏(我的/统计/周报/错误档案/设置类/关于/写译记录/访谈/聊天/测试)统一由
  // test/profile_pages_test.dart 渲染——同一次交付里一个屏只由一个测试出图,
  // 否则后跑的会覆盖先跑的(KPI 与概览不同源那类假图就是这么来的)。

  // ── 交互测试(真实写库,验证"点了真有反应")──
  testWidgets('任务详情:标记完成 → 写库为 done 并带 done_at', (WidgetTester tester) async {
    // 详情页比一屏高:把视口拉高,让按钮真的被 build 出来(tester.tap 点不到未构建的控件)
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    final Map<String, Object?> pending = _taskRows.firstWhere(
      (Map<String, Object?> r) => r['status'] == 'pending',
    );
    final int id = pending['id']! as int;
    bool refreshed = false;
    await tester.pumpWidget(MaterialApp(
      theme: _theme(),
      home: TutorTaskDetailScreen(
        row: pending,
        onChanged: () async => refreshed = true,
      ),
    ));
    await tester.pump();
    expect(find.text('待做'), findsOneWidget);
    await tester.tap(find.text('标记完成'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    final List<Map<String, Object?>> rows =
        await tester.runAsync(() => DatabaseService.listTutorTasks(limit: 50)) ??
            const <Map<String, Object?>>[];
    final Map<String, Object?> row =
        rows.firstWhere((Map<String, Object?> r) => r['id'] == id);
    expect('${row['status']}', 'done');
    expect(row['done_at'], isNotNull);
    expect(refreshed, isTrue);
    // setState 发生在 DB 回读之后:再给一次真实事件循环 + 一帧,让 UI 落地
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('任务详情:跳过 → 状态变 skipped(记进复盘)', (WidgetTester tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    final Map<String, Object?> active = _taskRows.firstWhere(
      (Map<String, Object?> r) => r['status'] == 'active',
    );
    final int id = active['id']! as int;
    await tester.pumpWidget(MaterialApp(
      theme: _theme(),
      home: TutorTaskDetailScreen(row: active),
    ));
    await tester.pump();
    await tester.tap(find.text('今天跳过(会记进复盘)'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    final List<Map<String, Object?>> rows =
        await tester.runAsync(() => DatabaseService.listTutorTasks(limit: 50)) ??
            const <Map<String, Object?>>[];
    expect(
      '${rows.firstWhere((Map<String, Object?> r) => r['id'] == id)['status']}',
      'skipped',
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.text('已跳过'), findsOneWidget);
  });

  testWidgets('复盘页:渲染 KPI/五维/复盘结论/今天任务', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: _theme(),
      home: TutorReviewScreen(dashboard: _dash!),
    ));
    await tester.pump();
    expect(find.text('五维现状'), findsOneWidget);
    // 页面比一屏长:向下滚,验证后面的「复盘结论 / 今天的任务」区块真的存在
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.text('复盘结论'), findsOneWidget);
    expect(find.text('今天的任务'), findsOneWidget);
    expect(find.text('复习 42 个到期词'), findsWidgets);
  });
}
