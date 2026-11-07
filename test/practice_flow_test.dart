import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/output/practice_flow_screen.dart';
import 'package:readflow/screens/output/widgets/practice_result_view.dart';
import 'package:readflow/services/output_composer.dart';
import 'package:readflow/services/output_draft.dart';
import 'package:readflow/services/output_rubric.dart';

/// 批 3 · 练习器/结果页的渲染回归。
///
/// 这一层不联网:
/// - [PracticeFlowScreen] 只渲染已生成好的题组(出题与批改走 API,不在本测试里);
/// - [PracticeResultView] 用一个假 [ScoredOutput] 渲染"总分 + 维度分 + 依据 + 错误"。
///
/// 守的是最容易在真机上炸的两件事:① 窄屏(360)下不 overflow;
/// ② "维度没评"显示"未评"而不是 0 分(评分纪律)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // 练习器 initState 会读偏好(Hive);测试里给它一个空 box,避免真盘 IO。
    Hive.init('build/test_hive_practice');
    await Hive.openBox('settings');
  });

  OutputSetSpec fakeSet() => const OutputSetSpec(
        title: '写句 · 回译练习',
        tier: OutputTier.sentence,
        source: 'ai',
        section: 'back_translation',
        rubricId: 'back_translation',
        tasks: [
          OutputTaskSpec(
            tier: OutputTier.sentence,
            type: 'back_translation',
            promptZh: '她花了整整一个下午才把那篇论文读完。',
            reference: 'It took her the whole afternoon to finish reading the paper.',
            rubricId: 'back_translation',
            abilityTags: ['词汇', '语法'],
            grammarPoints: ['时态'],
            wordCount: 10,
            sourceSpan: 'It took her the whole afternoon to read the paper.',
          ),
        ],
      );

  testWidgets('练习器:题面/进度/输入框都能渲染(360 宽不溢出)', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: PracticeFlowScreen(set: fakeSet(), savedSetId: 0),
      ),
    );
    await tester.pump();

    expect(find.text('第 1/1 题'), findsOneWidget);
    expect(find.textContaining('她花了整整一个下午'), findsOneWidget);
    expect(find.textContaining('不少于 10 词'), findsOneWidget);
    // 批 8 起四阶作答提示按阶不同(句子阶是"写出英文句子…"),断言按当前阶的文案
    expect(find.textContaining('写出英文句子'), findsOneWidget);
    expect(find.textContaining('提交批改'), findsOneWidget);
  });

  testWidgets('结果页:总分/维度分/依据/错误都能渲染,未评维度显示"未评"',
      (tester) async {
    tester.view.physicalSize = const Size(360, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final rubric = OutputRubric.byId('back_translation')!;
    final result = ScoredOutput(
      totalScore: 17.5,
      bandLabel: '中等偏上',
      dimensions: const [
        ScoredDimension(
          key: 'fidelity',
          label: '忠实原文',
          score: 8,
          maxScore: 10,
          evidence: 'the whole afternoon 译对了',
        ),
        ScoredDimension(
          key: 'grammar',
          label: '语法',
          score: null,
          maxScore: 25,
          evidence: '',
        ),
      ],
      issues: const [
        ScoredIssue(
          span: 'read the paper',
          type: '时态',
          reason: 'finish reading 更自然',
          suggestion: 'finish reading the paper',
        ),
      ],
      correction: 'It took her the whole afternoon to finish reading the paper.',
      summary: '整体翻译准确,注意动宾搭配。',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PracticeResultView(
              result: result,
              title: '第 1 题 · 批改结果',
              reference: rubric.id,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('中等偏上'), findsOneWidget);
    expect(find.textContaining('忠实原文'), findsOneWidget);
    expect(find.textContaining('依据：the whole afternoon'), findsOneWidget);
    expect(find.text('未评'), findsOneWidget);
    expect(find.textContaining('需要改的地方'), findsOneWidget);
    expect(find.textContaining('建议：finish reading the paper'), findsOneWidget);
  });

  // ── 2026-11-07 真机反馈第 6 条第 3 点:自由跳题(不强制顺序)──

  OutputSetSpec fakeSet3() => const OutputSetSpec(
        title: '六级写作真题',
        tier: OutputTier.sentence,
        source: 'exam',
        examType: 'cet6',
        section: 'back_translation',
        rubricId: 'cet6_writing',
        tasks: [
          OutputTaskSpec(
            tier: OutputTier.sentence,
            type: 'back_translation',
            promptZh: '第一题:把这句话译回英文。',
            reference: 'First sentence.',
            rubricId: 'cet6_writing',
            wordCount: 0,
          ),
          OutputTaskSpec(
            tier: OutputTier.sentence,
            type: 'back_translation',
            promptZh: '第二题:把这句话译回英文。',
            reference: 'Second sentence.',
            rubricId: 'cet6_writing',
            wordCount: 0,
          ),
          OutputTaskSpec(
            tier: OutputTier.sentence,
            type: 'back_translation',
            promptZh: '第三题:把这句话译回英文。',
            reference: 'Third sentence.',
            rubricId: 'cet6_writing',
            wordCount: 0,
          ),
        ],
      );

  testWidgets('答题卡:可跳到任意题,答题草稿随题切换不丢', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 草稿落盘(Hive)在测试里也要可用;清掉上一用例的残留。
    // 注意:Hive 写入内部用 Future.delayed(0),在 fake-async 的 testWidgets 里
    // 必须放进 runAsync 才会真正完成(直接 await 会挂到测试超时)。
    await tester.runAsync(() => OutputDraftStore.clear());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: PracticeFlowScreen(set: fakeSet3(), savedSetId: 0),
      ),
    );
    await tester.pump();
    expect(find.textContaining('第 1/3 题'), findsOneWidget);

    // 打开答题卡 → 跳到第 3 题
    await tester.tap(find.byIcon(Icons.grid_view_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('答题卡'), findsOneWidget);
    await tester.tap(find.text('3').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('第 3/3 题'), findsOneWidget);

    // 在第 3 题写草稿,跳回第 1 题,再跳回第 3 题 → 文本还在
    await tester.enterText(find.byType(TextField), 'third answer draft');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.grid_view_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('1').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('第 1/3 题'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.grid_view_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('3').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('第 3/3 题'), findsOneWidget);
    expect(find.text('third answer draft'), findsOneWidget);
  });

  testWidgets('继续上次练习:按草稿恢复题号与作答', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 模拟"上次练到第 2 题、第 1 题写了草稿"后退出。
    // setId 用 0:本用例只验证**草稿恢复**(Hive 同步路径),不触发读库;
    // 已批改结果的库内还原由 output_draft_test 的 loadScoredByIndex 用例覆盖。
    await tester.runAsync(() => OutputDraftStore.save(OutputDraft(
          setId: 0,
          title: '六级写作真题',
          index: 1,
          texts: const <int, String>{0: 'first question draft'},
          updatedAt: DateTime.now(),
        )));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: PracticeFlowScreen(set: fakeSet3(), savedSetId: 0),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.textContaining('第 2/3 题'), findsOneWidget,
        reason: '应恢复到上次停下的第 2 题');

    // 跳回第 1 题:草稿文本应还在
    await tester.tap(find.byIcon(Icons.grid_view_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('1').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('first question draft'), findsOneWidget);

    await tester.runAsync(() => OutputDraftStore.clear());
  });
}
