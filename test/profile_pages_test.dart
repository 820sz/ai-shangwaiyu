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
import 'package:readflow/models/vocabulary.dart';
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
import 'package:readflow/screens/tutor/tutor_interview_screen.dart';
import 'package:readflow/screens/tutor/tutor_review_screen.dart';
import 'package:readflow/screens/writing/writing_logs_screen.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/tutor_engine.dart';
import 'package:readflow/services/tutor_snapshot.dart';
import 'package:readflow/services/weekly_report.dart';

/// 「我的」链路 + 不依赖 app.dart 的助理内页:**逐屏真实渲染**。
///
/// 为什么不和 `test/tutor_pages_test.dart` 放一起:助理首页/任务详情要 import
/// `lib/app.dart`(用 AppTabs 跨 Tab 跳转),而 app.dart 会拖进全部屏幕 ——
/// 其他 agent 正在改输入/输出时,那个文件会被牵连编译失败。拆开后这一份
/// 只依赖各自屏 + 服务层,能独立跑、独立交付。
///
/// 产物:`build/ui_real/assist-mine-impl-*.png`(390×844 @3x)。

const String _ff = 'PreviewCJK';

Future<void> _loadFont() async {
  for (final String path in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
  ]) {
    final File f = File(path);
    if (!f.existsSync()) continue;
    // 同一个中文字体注册成多个族名:显式写了 fontFamily('monospace' 等)的
    // 控件(IPA、代码样式、按钮内置样式)在测试里才不会落回 Ahem 方块。
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
    // 按钮/chip/菜单/弹窗的文字样式来自主题时必须一起换字体族,
    // 否则测试环境落回 Ahem —— QA 看到的"成片方块字"就是这些控件。
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

final DateTime _now = DateTime(2026, 11, 6, 20, 30);
Directory? _tmp;
TutorDashboard? _dash;

Future<void> _seed() async {
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
    },
  );
  await DatabaseService.insertTutorTask(
    planDate: _now,
    kind: 'output',
    title: '回译昨天那句译文',
    targetMinutes: 7,
    origin: 'auto',
    goalTag: 'output',
    payload: <String, Object?>{'reason': '冠词错误最近出现 5 次', 'jump': 'output'},
  );
  await DatabaseService.updateTutorTaskStatus(id2, 'active');
  await DatabaseService.completeTutorTask(id1);

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
    } catch (_) {}
  }

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

  // 6) 生词本 60 条:统计页「累计词汇」与周报口径一致(不再是 0)
  for (var i = 0; i < 60; i++) {
    await DatabaseService.insertVocabulary(
      Vocabulary(
        word: 'sample$i',
        translation: '示例词 ${i + 1}',
        createdAt: _now.subtract(Duration(days: i % 7)),
      ),
    );
  }

  _dash = await TutorSnapshotService.load(now: _now);
}

/// 周报渲染用的注入数据:与顶部 KPI/7 天柱**同源**(新收词合计 38),
/// 避免"KPI 有数字、概览六格全 0"的假 0 图。
List<LearningRecord> _previewLogs() {
  const List<int> newWords = <int>[4, 9, 0, 12, 6, 3, 4];
  const List<int> reviewed = <int>[10, 18, 0, 26, 14, 5, 12];
  return <LearningRecord>[
    for (var i = 0; i < 7; i++)
      LearningRecord(
        date: DateTime(2026, 11, 1 + i),
        newWordsCount: newWords[i],
        reviewedCount: reviewed[i],
        exerciseCompleted: i.isEven ? 1 : 0,
        studyMinutes: 10 + i * 3,
      ),
  ];
}

WeeklyReport _previewWeekly() => WeeklyReport(
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 7, 23, 59, 59),
      activeDays: 6,
      wordsRead: 1240,
      minutesRead: 123,
      newWords: 38,
      reviewsDone: 116,
      materialsFinished: 2,
      quizAccuracy: 0.82,
      topErrors: const <String>['时态(7 次)', '冠词(5 次)'],
      outputAttempts: 3,
      outputAvgScore: 78,
      outputErrorTags: const <String>['冠词(3 次)'],
      outputLines: const <String>['完成 3 次写译批改,均分 78 分;冠词错误出现 3 次。'],
      highlights: const <String>[
        '近 7 天新收 38 个词,比上周多 9 个。',
        '复习 116 个词,正确率 82%。',
      ],
      suggestions: const <String>[
        '下周把 42 个到期词拆成每天 2 组。',
        '写译保持每周 3 次,重点改冠词。',
      ],
      forecast: const <String, int>{
        '0': 42,
        '1': 18,
        '2': 12,
        '3': 8,
        '4': 0,
        '5': 24,
        '6': 30,
      },
      isActive: true,
    );

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
    // 真机有状态栏:用 MediaQuery 兜一个 44px 顶部安全区,
    // 否则 AppBar/刊头会贴着渲染图顶边(验收观感"标题贴顶")
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
            ChangeNotifierProvider<StatsProvider>(create: (_) => StatsProvider()),
            ChangeNotifierProvider<VocabProvider>(create: (_) => VocabProvider()),
            ChangeNotifierProvider<BookmarkProvider>(
              create: (_) => BookmarkProvider(),
            ),
          ],
          child: app,
        )
      : app;
  await tester.pumpWidget(wrapped);
  await tester.pump();
  // 真实 I/O 在 fake-async 里不推进:反复 runAsync + pump(数据库建表/查询要时间,
  // 一次 450ms 会截到骨架屏 —— 见 v5 实施踩坑记录)
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 80));
  }
  await _capture(tester, key, fileName);
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
    _tmp = await Directory.systemTemp.createTemp('rf_mine_render');
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

  testWidgets('render 我的首页(B 每日简报)', (WidgetTester tester) async {
    await _render(tester, 'assist-mine-impl-mine-home.png', const ProfileHomeScreen());
  });

  testWidgets('render 学习统计(A 诊断台)', (WidgetTester tester) async {
    await _render(tester, 'assist-mine-impl-stats.png', const StatsPageScreen());
  });

  testWidgets('render 本周报告(A 诊断台)', (WidgetTester tester) async {
    await _render(
      tester,
      'assist-mine-impl-weekly.png',
      WeeklyReportScreen(
        previewReport: _previewWeekly(),
        previewDailyLogs: _previewLogs(),
      ),
    );
  });

  testWidgets('render 错误档案(A 诊断台)', (WidgetTester tester) async {
    await _render(tester, 'assist-mine-impl-error-archive.png', const ErrorArchiveScreen());
  });

  testWidgets('render API 设置(换 V4JellyAppBar)', (WidgetTester tester) async {
    await _render(tester, 'assist-mine-impl-api-settings.png', const ApiSettingsScreen());
  });

  testWidgets('render 外观(换 V4JellyAppBar)', (WidgetTester tester) async {
    await _render(tester, 'assist-mine-impl-appearance.png', const AppearanceScreen());
  });

  testWidgets('render 备份与导出(换 V4JellyAppBar)', (WidgetTester tester) async {
    await _render(tester, 'assist-mine-impl-backup.png', const BackupScreen());
  });

  testWidgets('render 桌面小组件(换 V4JellyAppBar)', (WidgetTester tester) async {
    await _render(
      tester,
      'assist-mine-impl-widget-settings.png',
      const WidgetSettingsScreen(),
    );
  });

  testWidgets('render 写译记录(新入口 + 换壳)', (WidgetTester tester) async {
    await _render(tester, 'assist-mine-impl-writing-logs.png', const WritingLogsScreen());
  });

  testWidgets('render 现状与复盘(A 诊断台,新页)', (WidgetTester tester) async {
    await _render(
      tester,
      'assist-mine-impl-review.png',
      TutorReviewScreen(dashboard: _dash!),
      providers: false,
    );
  });

  testWidgets('render 学习访谈(换 V4JellyAppBar)', (WidgetTester tester) async {
    await _render(
      tester,
      'assist-mine-impl-interview.png',
      const TutorInterviewScreen(),
      providers: false,
    );
  });

  testWidgets('render 与 AI 聊聊(换 V4JellyAppBar)', (WidgetTester tester) async {
    await _render(
      tester,
      'assist-mine-impl-chat.png',
      TutorChatScreen(snapshot: LearnerSnapshot(model: LearnerModel(), now: _now)),
      providers: false,
    );
  });

  testWidgets('render 词汇量测试(换 V4JellyAppBar)', (WidgetTester tester) async {
    await _render(
      tester,
      'assist-mine-impl-placement.png',
      const PlacementTestScreen(full: false),
      providers: false,
    );
  });

  testWidgets('复盘页:五维/复盘结论/今天任务三块都在', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: _theme(),
      home: TutorReviewScreen(dashboard: _dash!),
    ));
    await tester.pump();
    expect(find.text('五维现状'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.text('复盘结论'), findsOneWidget);
    expect(find.text('今天的任务'), findsOneWidget);
  });
}
