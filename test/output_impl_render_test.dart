/// 输出板块视觉 A 实施 · 逐屏真实渲染(8 屏)。
///
/// 与 `docs/OUTPUT-IMPLEMENT.md` 对照表配套:每个必须交付的屏各出一张 PNG,
/// 390×844 @3x(真字体 + 真图标),用**生产组件 + 假数据**渲染,
/// 不画示意图 —— 渲染出来的就是用户会看到的版面。
///
/// 出图(同时写 build/ui_real/ 与 docs/ui-preview/real/):
/// - output-impl-home.png            输出首页(入口果冻头图 + 四阶纸面清单)
/// - output-impl-practice-center.png 练习中心弹层(入口屏)
/// - output-impl-setup.png           四阶设置(纸面:标题 + 等级筛选 + 来源)
/// - output-impl-answer.png          答题页(进度 + 题干 + 作答 + rubric + 来源)
/// - output-impl-result.png          批改结果(分数环 + 维度 + 问题 + 参考)
/// - output-impl-history.png         题库(等级筛选 + 来源行 + 回填入口)
/// - output-impl-plan.png            旧计划页(练习中心)
/// - output-impl-write.png           写译工作台
///
/// 运行:`cd /d/readflow && bash tool/lockrun.sh test test/output_impl_render_test.dart --no-pub`
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/design_tokens.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/config/v4_theme.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/providers/bookmark_provider.dart';
import 'package:readflow/providers/vocab_provider.dart';
import 'package:readflow/screens/output/drill_plan_screen.dart';
import 'package:readflow/screens/output/output_home.dart';
import 'package:readflow/screens/output/practice_flow_screen.dart';
import 'package:readflow/screens/output/practice_history_screen.dart';
import 'package:readflow/screens/output/practice_setup_screen.dart';
import 'package:readflow/screens/output/widgets/paper_kit.dart';
import 'package:readflow/screens/output/widgets/practice_result_view.dart';
import 'package:readflow/screens/writing/write_review_screen.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/learner_model_store.dart';
import 'package:readflow/services/output_composer.dart';
import 'package:readflow/services/output_rubric.dart';

const String _fontFamily = 'PreviewCJK';

Future<void> _loadFont() async {
  for (final path in <String>[
    'C:/Windows/Fonts/NotoSansSC-VF.ttf',
    'C:/Windows/Fonts/Deng.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes =
        Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
    await (FontLoader('Roboto')..addFont(bytes)).load();
    await (FontLoader(_fontFamily)..addFont(bytes)).load();
    // flutter_test 默认字体族是 'Ahem'(只有方块);把中文字体也注册到这个名字,
    // 任何"没有显式 fontFamily"的 Text(如 AppBar.titleTextStyle)也能显示中文。
    await (FontLoader('Ahem')..addFont(bytes)).load();
    return;
  }
}

Future<void> _loadIcons() async {
  for (final path in <String>[
    'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
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

// ═══════════════════════════════════════════════════════════════════
// 假数据(与生产无关,只用于视觉评审)
// ═══════════════════════════════════════════════════════════════════

/// 一份真实感的四级真题题组(来源/年份/套数/站点都齐)。
/// 用「写句·回译」题:作答框更矮,一屏能同时看到来源行 + rubric 预告。
OutputSetSpec _examSet() => const OutputSetSpec(
      title: '英语四级(CET-4) · 2023 年 12 月第 1 套 · 写作真题',
      tier: OutputTier.sentence,
      source: 'exam',
      examType: 'cet4',
      section: 'back_translation',
      paperYear: 2023,
      paperLabel: '2023 年 12 月 · 第 1 套',
      sourceSite: '中国教育考试网',
      sourceUrls: <String>['https://www.neea.edu.cn/html1/report/2312/1-1.htm'],
      verifyStatus: 'pending',
      rubricId: 'back_translation',
      tasks: <OutputTaskSpec>[
        OutputTaskSpec(
          tier: OutputTier.sentence,
          type: 'back_translation',
          promptZh: '把这句话译回英文：他直到深夜才意识到自己忘了带钥匙。',
          promptEn: 'He did not realise he had left his keys until late at night.',
          reference: 'He did not realise he had left his keys until late at night.',
          rubricId: 'back_translation',
          wordCount: 0,
          hint: '注意 not...until 的语序与过去完成时',
          sourceUrl: 'https://www.neea.edu.cn/html1/report/2312/1-1.htm',
        ),
      ],
    );

const OutputRubric _writingRubric = OutputRubric(
  id: 'cet4_writing',
  type: 'writing',
  scoringMode: ScoringMode.aiRubric,
  dimensions: <RubricDimension>[
    RubricDimension(key: 'content', label: '内容切题', weight: 0.4, maxScore: 40),
    RubricDimension(key: 'language', label: '语言准确', weight: 0.4, maxScore: 40),
    RubricDimension(key: 'structure', label: '结构连贯', weight: 0.2, maxScore: 20),
  ],
  bands: <RubricBand>[
    RubricBand(minScore: 85, maxScore: 101, label: '优秀', description: '约 13~15 分档'),
    RubricBand(minScore: 70, maxScore: 85, label: '良好', description: '约 10~12 分档'),
    RubricBand(minScore: 0, maxScore: 70, label: '待提高', description: '约 6~9 分档'),
  ],
);

ScoredOutput _scoredOutput() => const ScoredOutput(
      totalScore: 78,
      bandLabel: '良好',
      dimensions: <ScoredDimension>[
        ScoredDimension(
          key: 'content',
          label: '内容切题',
          maxScore: 40,
          score: 33,
          evidence: 'Write an essay on the importance of reading classics.',
        ),
        ScoredDimension(
          key: 'language',
          label: '语言准确',
          maxScore: 40,
          score: 30,
          evidence: 'Reading classics is benefit for our growth.',
        ),
        ScoredDimension(
          key: 'structure',
          label: '结构连贯',
          maxScore: 20,
          score: 15,
          evidence: 'First, ... Second, ...',
        ),
      ],
      issues: <ScoredIssue>[
        ScoredIssue(
          span: 'is benefit for',
          type: '用词',
          reason: 'benefit 是名词，此处应为 be beneficial to',
          suggestion: 'is beneficial to our growth',
        ),
        ScoredIssue(
          span: 'Reading classics is important',
          type: '语法',
          reason: '主语过长时建议用从句或形式主语',
          suggestion: 'It is important to read classics',
        ),
      ],
      correction: 'It is widely believed that reading classics is beneficial '
          'to our growth. First, classics help us understand history. '
          'Second, they improve our language sense.',
      summary: '观点明确、结构完整；用词与长句组织还能更准确。',
    );

/// 结果页宿主:直接渲染生产组件 [PracticeResultView](不复制一份 UI)
class _ResultHost extends StatelessWidget {
  const _ResultHost();

  @override
  Widget build(BuildContext context) {
    return PaperSkin(
      child: Builder(builder: (context) {
        final skin = V4Skin.of(context);
        return Scaffold(
          backgroundColor: skin.pageBg,
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Gap.page, Gap.md, Gap.page, Gap.xxl),
              children: <Widget>[
                Text(
                  '第 1 题 · 批改结果',
                  style: AppFont.tagStyle.copyWith(
                    color: skin.inkFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                PracticeResultView(
                  result: _scoredOutput(),
                  reference: 'Reading classics is beneficial to our growth.',
                  rubric: _writingRubric,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// 统一渲染:真字体 + 390×844 + 固定 pump(不用 pumpAndSettle,
/// 页面里有循环骨架动画,settle 会死等)。
Future<void> _render(
  WidgetTester tester,
  Widget screen,
  String fileName, {
  Future<void> Function(WidgetTester tester)? afterPump,
}) async {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MultiProvider(
        providers: <ChangeNotifierProvider<dynamic>>[
          ChangeNotifierProvider<BookmarkProvider>.value(
            value: BookmarkProvider(),
          ),
          ChangeNotifierProvider<VocabProvider>(
            create: (_) => VocabProvider(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: screen,
        ),
      ),
    ),
  );
  await _settle(tester);
  if (afterPump != null) {
    await afterPump(tester);
    await _settle(tester);
  }
  await _capture(tester, key, fileName);
}

/// 固定节奏 pump:让 post-frame 的异步加载(读库/Hive)有机会完成。
///
/// 不用 pumpAndSettle:首页/计划页里有循环骨架动画,settle 会死等;
/// 这里用"真时间片(runAsync)+ 帧"交替,直到异步 setState 落地。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.pump(const Duration(milliseconds: 400));
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
    tmp = await Directory.systemTemp.createTemp('rf_output_impl');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
    Hive.init(tmp.path);
    final settings = await Hive.openBox(AppConstants.hiveBoxSettings);
    // 学习目标:四级 + 考研(与新拆的四级/六级目标兼容)
    await LearnerModelStore.save(LearnerModel(
      goals: const <String>['四级', '考研'],
      cefr: ProfileField<String>(
        value: 'B1',
        source: ProfileSource.self,
        confidence: 0.5,
      ),
      vocabEstimate: ProfileField<int>(
        value: 4200,
        source: ProfileSource.test,
        confidence: 0.8,
      ),
      dailyMinutes: ProfileField<int>(
        value: 30,
        source: ProfileSource.self,
        confidence: 0.5,
      ),
    ));
    // 配置一个演示 Key:让"去抓真题出题"按钮处于可用态(不联网,只影响 UI)
    await settings.put(AppConstants.keyDeepseekApiKey, 'sk-render-preview');

    // ① 我的材料(四阶设置页的"从材料出题"列表;要带正文才算可出题素材)
    final db = await DatabaseService.database;
    for (var i = 0; i < 3; i++) {
      final materialId = await db.insert('materials', <String, Object?>{
        'kind': i == 0 ? 'book' : 'news',
        'source': 'import',
        'title':
            i == 0 ? 'The Four Million' : 'AI and language learning ${i + 1}',
        'title_cn': i == 0 ? '四百万' : 'AI 与语言学习',
        'word_count': 2400 + i * 300,
        'cefr': i == 0 ? 'C1' : 'B2',
        'est_minutes': 10,
        'origin': 'import',
        'created_at': '2026-11-0${i + 1}T10:00:00',
      });
      await db.insert('material_content', <String, Object?>{
        'material_id': materialId,
        'chunk_index': 0,
        'title': 'Chapter 1',
        'text': 'The Four Million is a collection of short stories about '
            'the lives of ordinary people in New York City at the beginning '
            'of the twentieth century. Each story is a small window into a '
            'different life, and the narrator watches the city with warmth '
            'and a quiet sense of humour.',
      });
    }

    // ② 题库:四级有卷面信息、六级缺卷面(验证来源行降级)、一个内置题组
    await DatabaseService.insertExerciseSet(<String, Object?>{
      'source': 'exam',
      'exam_type': 'cet4',
      'paper_year': 2023,
      'paper_label': '2023 年 12 月 · 第 1 套',
      'section': 'writing',
      'title': '英语四级(CET-4) · 2023 年 12 月第 1 套 · 写作真题',
      'rubric_id': 'cet4_writing',
      'license_note': '题目来自公开网页抓取'
          '(https://www.neea.edu.cn/html1/report/2312/1-1.htm),仅本地学习使用。',
      'verify_status': 'pending',
      'created_at': '2026-11-05T20:00:00',
    }, items: <Map<String, Object?>>[
      <String, Object?>{
        'type': 'exam_writing',
        'prompt_zh': 'Write an essay on the importance of reading classics.',
        'reference_answer': '',
        'rubric_id': 'cet4_writing',
        'word_count': 120,
        'source_span': '',
      },
    ]);
    await DatabaseService.insertExerciseSet(<String, Object?>{
      'source': 'exam',
      'exam_type': 'cet6',
      'section': 'translation',
      'title': '英语六级(CET-6) · 段落翻译真题',
      'rubric_id': 'cet4_translation',
      'license_note': '题目来自公开网页抓取(https://i.xdf.cn/cet6/1.html)。',
      'verify_status': 'verified',
      'created_at': '2026-11-04T20:00:00',
    }, items: <Map<String, Object?>>[
      <String, Object?>{
        'type': 'exam_translation',
        'prompt_zh': '将下面段落译成英文：中国茶文化历史悠久。',
        'reference_answer': '',
        'rubric_id': 'cet4_translation',
        'word_count': 0,
        'source_span': '',
      },
    ]);
    await DatabaseService.insertExerciseSet(<String, Object?>{
      'source': 'builtin',
      'exam_type': 'none',
      'section': 'back_translation',
      'title': '作文范文句 · 5 句回译',
      'rubric_id': 'back_translation',
      'verify_status': 'verified',
      'created_at': '2026-11-03T20:00:00',
    }, items: <Map<String, Object?>>[
      <String, Object?>{
        'type': 'back_translation',
        'prompt_zh': '把这句话译回英文。',
        'reference_answer': 'Reading makes a full man.',
        'rubric_id': 'back_translation',
        'word_count': 0,
        'source_span': 'Reading makes a full man.',
      },
    ]);
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    await Hive.close();
    try {
      await databaseFactory
          .deleteDatabase('${tmp.path}/${AppConstants.dbName}');
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('输出首页(入口借 B 头图)', (tester) async {
    await _render(tester, const OutputHomeScreen(), 'output-impl-home.png');
  });

  testWidgets('练习中心弹层', (tester) async {
    await _render(
      tester,
      const OutputHomeScreen(),
      'output-impl-practice-center.png',
      afterPump: (tester) async {
        await tester.tap(find.text('练习中心').first);
        await tester.pump();
      },
    );
  });

  testWidgets('四阶设置(写篇)', (tester) async {
    await _render(
      tester,
      const PracticeSetupScreen(tier: OutputTier.essay),
      'output-impl-setup.png',
    );
  });

  testWidgets('四阶设置(滚到底:底部 CTA 不遮挡最后一项)', (tester) async {
    await _render(
      tester,
      const PracticeSetupScreen(tier: OutputTier.essay),
      'output-impl-setup-bottom.png',
      afterPump: (tester) async {
        // 滚到底:验证列表底部留够 CTA 高度,最后一张材料卡完整可见
        await tester.drag(find.byType(ListView).first, const Offset(0, -2400));
        await tester.pump();
      },
    );
  });

  testWidgets('答题页(来源 + rubric 预告)', (tester) async {
    await _render(
      tester,
      PracticeFlowScreen(set: _examSet(), savedSetId: 1),
      'output-impl-answer.png',
    );
  });

  testWidgets('批改结果', (tester) async {
    await _render(tester, const _ResultHost(), 'output-impl-result.png');
  });

  testWidgets('题库(等级筛选 + 来源行)', (tester) async {
    await _render(
      tester,
      const PracticeHistoryScreen(),
      'output-impl-history.png',
    );
  });

  testWidgets('旧计划页(练习中心)', (tester) async {
    await _render(tester, const DrillPlanScreen(), 'output-impl-plan.png');
  });

  testWidgets('写译工作台', (tester) async {
    await _render(
      tester,
      const WriteReviewScreen(),
      'output-impl-write.png',
    );
  });
}

// 供 `docs/OUTPUT-IMPLEMENT.md` 对照表引用的渲染清单(避免文档里手抄文件名)
const List<String> outputImplRenderFiles = <String>[
  'output-impl-home.png',
  'output-impl-practice-center.png',
  'output-impl-setup.png',
  'output-impl-setup-bottom.png',
  'output-impl-answer.png',
  'output-impl-result.png',
  'output-impl-history.png',
  'output-impl-plan.png',
  'output-impl-write.png',
];
