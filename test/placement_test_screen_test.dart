import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/screens/tutor/placement_test_screen.dart';
import 'package:readflow/services/learner_model_store.dart';
import 'package:readflow/services/word_frequency.dart';

/// 词汇量测试页的行为回归。
///
/// 为什么值得测(而不是只有单测):
/// - 这一页是 2.0 的"测量入口",流程错一步(答完不落库 / 退出不确认 /
///   垃圾作答污染基线)用户就白做 100 题;
/// - 它把 UI 状态机(词汇→语法→阅读→结果)与外部依赖(assets 词表 + Hive)
///   串在一起,任何一环退化都要在提交前拦住。
///
/// 注意:测试**不能**替用户"正确作答"(哪些题是编造词在 UI 上不可见 ——
/// 那正是盲测的设计),所以这里验证的是流程与"该保存/不该保存"的判定,
/// 估计值本身的准确性由 vocab_estimator_test 覆盖。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_placement_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    await WordFrequency.ensureLoaded();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    hiveDir.deleteSync(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester, {required bool full}) async {
    await tester.pumpWidget(
      MaterialApp(home: PlacementTestScreen(full: full)),
    );
    await tester.pumpAndSettle();
  }

  /// 一直点同一个按钮,直到离开词汇阶段(带上限防止实现出错时死循环)
  Future<int> answerVocabAll(WidgetTester tester, {required String choice}) async {
    var taps = 0;
    while (taps < 400) {
      final btn = find.text(choice);
      if (btn.evaluate().isEmpty) break; // 已进入下一阶段
      await tester.tap(btn);
      await tester.pump(const Duration(milliseconds: 10));
      taps++;
    }
    await tester.pumpAndSettle();
    return taps;
  }

  testWidgets('速测:说明页 → 逐题作答 → 结果页', (tester) async {
    await pumpScreen(tester, full: false);

    // 说明页必须讲清"有编造词",否则用户会乱点
    expect(find.textContaining('编造'), findsOneWidget);
    expect(find.textContaining('尚未测过'), findsOneWidget);

    await tester.tap(find.text('开始速测'));
    await tester.pumpAndSettle();
    expect(find.text('认识'), findsOneWidget);
    expect(find.text('不认识'), findsOneWidget);
    expect(find.textContaining('/ 76'), findsOneWidget, reason: '速测应为 6 档 ×12 + 4 伪词 = 76 题');

    final taps = await answerVocabAll(tester, choice: '认识');
    expect(taps, greaterThan(50), reason: '速测应有 60+ 道题');

    expect(find.text('你的词汇量'), findsOneWidget);
    expect(find.textContaining('区间'), findsOneWidget);
    expect(find.textContaining('你在哪一档开始掉'), findsOneWidget);
    expect(find.textContaining('编造词'), findsWidgets);
  });

  testWidgets('全点"认识"→ 作答不可信 → 不写入模型(不污染基线)', (tester) async {
    await pumpScreen(tester, full: false);
    await tester.tap(find.text('开始速测'));
    await tester.pumpAndSettle();
    await answerVocabAll(tester, choice: '认识');
    await tester.pumpAndSettle();

    // 伪词误报率必然很高 → 结果页要明确说"没保存",而不是悄悄写进模型
    expect(find.textContaining('不可信'), findsOneWidget);
    expect(find.textContaining('没有保存'), findsOneWidget);
    expect(LearnerModelStore.load().vocabEstimate, isNull);
    expect(LearnerModelStore.load().lastPlacementAt, isNull);
  });

  testWidgets('作答中返回要确认,选"继续测试"回到题面;选放弃则不落库', (tester) async {
    await pumpScreen(tester, full: false);
    await tester.tap(find.text('开始速测'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('不认识'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('要放弃这次测试吗?'), findsOneWidget);

    await tester.tap(find.text('继续测试'));
    await tester.pumpAndSettle();
    expect(find.text('要放弃这次测试吗?'), findsNothing);
    expect(find.text('认识'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃退出'));
    await tester.pumpAndSettle();
    expect(LearnerModelStore.load().vocabEstimate, isNull);
  });

  testWidgets('完整版:词汇后进语法(带解析),再进阅读,最后给语法/阅读分', (tester) async {
    await pumpScreen(tester, full: true);
    expect(find.textContaining('约 10 分钟'), findsOneWidget);

    await tester.tap(find.text('开始完整版'));
    await tester.pumpAndSettle();
    final taps = await answerVocabAll(tester, choice: '认识');
    expect(taps, greaterThan(100), reason: '完整版应有 120+ 道词汇题');

    // ── 语法阶段 ──
    expect(find.textContaining('语法 · 1/5'), findsOneWidget);
    expect(find.text('下一题'), findsNothing, reason: '未作答时不该出现"下一题"');

    // 第 1 题:把四个选项都点一遍不现实,点正确项 live → 立刻出解析
    await tester.tap(find.text('live'));
    await tester.pumpAndSettle();
    expect(find.textContaining('现在完成时'), findsOneWidget);
    expect(find.text('下一题'), findsOneWidget);

    // 余下 4 道:每道先"下一题"翻页,再点第一个选项
    // (第 5 道答完按钮会变成"进入阅读",所以前 3 道用循环,最后一道单独走)
    for (var q = 0; q < 3; q++) {
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_firstOptionTextOf(q + 1)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('语法 · 5/5'), findsOneWidget);
    await tester.tap(find.text(_firstOptionTextOf(4)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进入阅读'));
    await tester.pumpAndSettle();

    // ── 阅读阶段 ──
    expect(find.text('The Cost of Convenience'), findsOneWidget);

    // 提交按钮在长列表底部(懒加载,未滚到就不会建),必须先滚过去
    final submitHint = find.textContaining('题未答');
    await tester.scrollUntilVisible(submitHint, 400);
    expect(submitHint, findsOneWidget);
    await tester.tap(submitHint);
    await tester.pumpAndSettle();
    expect(find.text('你的词汇量'), findsNothing, reason: '未答完不该出结果');

    // 三题各选第一个选项 → 提交
    for (final t in _readingFirstOptions()) {
      final option = find.text(t);
      await tester.scrollUntilVisible(option, 300);
      await tester.tap(option.first);
      await tester.pumpAndSettle();
    }
    final submit = find.text('提交,看结果');
    await tester.scrollUntilVisible(submit, 400);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    // ── 结果页:词汇部分不可信(全点认识)→ 不落库,但语法/阅读分照常给出 ──
    expect(find.text('你的词汇量'), findsOneWidget);
    // 语法/阅读卡在结果页下方(懒加载),先滚到可见
    final grammarCard = find.textContaining('语法与阅读');
    await tester.scrollUntilVisible(grammarCard, 300);
    expect(grammarCard, findsOneWidget);
    expect(find.textContaining('语法 '), findsWidgets);
    expect(LearnerModelStore.load().vocabEstimate, isNull);
  });
}

/// 语法题(第 1 题之后)的第一个选项文本
String _firstOptionTextOf(int questionIndex) => switch (questionIndex) {
      1 => 'a',
      2 => 'in',
      3 => 'was',
      4 => 'am',
      _ => 'a',
    };

/// 阅读三题的第一个选项
List<String> _readingFirstOptions() => const [
      'Technology has made daily life worse overall.',
      'avoid all new tools',
      'Cooks who order food online',
    ];
