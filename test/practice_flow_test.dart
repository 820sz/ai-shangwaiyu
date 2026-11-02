import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/output/practice_flow_screen.dart';
import 'package:readflow/screens/output/widgets/practice_result_view.dart';
import 'package:readflow/services/output_composer.dart';
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
}
