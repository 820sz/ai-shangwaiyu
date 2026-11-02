import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/tutor_insights.dart';

/// 批 4 · 助理逻辑层回归测试。
///
/// 守的几条硬规则:
/// 1. **绝不编数字**:全空输入时五个维度 measured=false、都有"怎么测",
///    且文案里不出现 `0 词/0 次/0 篇/0%` 这类会被读成"用户真实成绩"的假值;
/// 2. **每条结论可回溯**:有数据时 valueText/evidence 必须带真实数字与来源;
/// 3. **排序可解释**:severity 降序 → 有数据的在前 → 维度固定顺序;
/// 4. **任务有理由**:每条任务 reason 非空、带真实依据,数量 ≤ max、不重复;
/// 5. **复盘每条都带数字**,且完成率分母按 research §2.4 的"已结算"口径
///    (done + skipped + expired),空数据不产生完成率指标。
void main() {
  group('常量与空输入', () {
    test('五维/动作/任务标签的常量齐全且不重复', () {
      expect(TutorDimensions.ordered, [
        'vocab',
        'grammar',
        'reading',
        'output',
        'habit',
      ]);
      expect(TutorActionJumps.all.toSet().length, TutorActionJumps.all.length);
      expect(TutorGoalTags.all.toSet().length, TutorGoalTags.all.length);
      for (final dimension in TutorDimensions.ordered) {
        expect(TutorDimensions.labelOf(dimension), isNotEmpty);
      }
    });

    test('InsightSource.isEmpty:全 null 为 true,任意一个字段有值为 false', () {
      expect(const InsightSource().isEmpty, isTrue);
      expect(const InsightSource(dueWords: 0).isEmpty, isFalse);
      expect(
        const InsightSource(errorTagCounts: {'时态': 1}).isEmpty,
        isFalse,
      );
    });

    test('全空 → 五维都 measured=false,且都有"怎么测"的动作', () {
      final insights = buildTutorInsights(const InsightSource());
      expect(insights.length, 5);
      expect(insights.map((i) => i.dimension).toSet(),
          TutorDimensions.ordered.toSet());
      for (final insight in insights) {
        expect(insight.measured, isFalse, reason: '${insight.dimension} 没有数据');
        expect(insight.valueText, '待测');
        expect(insight.actionLabel, isNotNull);
        expect(insight.actionLabel, isNotEmpty);
        expect(TutorActionJumps.all, contains(insight.actionJump));
      }
    });

    test('全空文案不出现伪造统计值(0 词 / 0 次 / 0 篇 / 0%)', () {
      final insights = buildTutorInsights(const InsightSource());
      for (final insight in insights) {
        final text = '${insight.valueText} ${insight.evidence}';
        expect(text.contains('0 词'), isFalse, reason: insight.dimension);
        expect(text.contains('0 次'), isFalse, reason: insight.dimension);
        expect(text.contains('0 篇'), isFalse, reason: insight.dimension);
        expect(text.contains('0%'), isFalse, reason: insight.dimension);
      }
    });

    test('全空时五维 severity 都是 0(缺数据不是问题,不制造焦虑)', () {
      final insights = buildTutorInsights(const InsightSource());
      for (final insight in insights) {
        expect(insight.severity, 0, reason: insight.dimension);
      }
    });

    test('max 生效:max=2 只回 2 条,max=0 返回空', () {
      expect(buildTutorInsights(const InsightSource(), max: 2).length, 2);
      expect(buildTutorInsights(const InsightSource(), max: 0), isEmpty);
    });
  });

  group('词汇维度', () {
    const base = InsightSource(
      vocabEstimate: 4200,
      vocabCi: 350,
      cefr: 'B2',
      dueWords: 12,
      reviewRetention: 0.81,
      goalWordsGap: 800,
      examGoals: ['四六级'],
    );

    test('有测量值时给区间值 + 真实依据', () {
      final vocab = buildTutorInsights(base)
          .firstWhere((i) => i.dimension == 'vocab');
      expect(vocab.measured, isTrue);
      expect(vocab.valueText, '4,200 ±350 词');
      expect(vocab.evidence, contains('留存 81%'));
      expect(vocab.evidence, contains('还差 800 词'));
      expect(vocab.evidence, contains('B2'));
      expect(vocab.severity, 1, reason: '离目标词表还差 800 词 → 注意');
      expect(vocab.actionJump, TutorActionJumps.review);
      expect(vocab.evidence, contains('800'));
      expect(vocab.actionLabel, contains('留存'), reason: '留存偏低优先提示复习加固');
    });

    test('留存低 → 该动手(severity 2),动作文案带留存数', () {
      final vocab = buildTutorInsights(
        const InsightSource(vocabEstimate: 5000, reviewRetention: 0.6),
      ).firstWhere((i) => i.dimension == 'vocab');
      expect(vocab.severity, 2);
      expect(vocab.actionLabel, contains('60%'));
    });

    test('目标词表差距大 → severity 2', () {
      final vocab = buildTutorInsights(
        const InsightSource(vocabEstimate: 2000, goalWordsGap: 2500),
      ).firstWhere((i) => i.dimension == 'vocab');
      expect(vocab.severity, 2);
    });

    test('没有区间时不显示 ±;基础词汇量(<3000)给注意', () {
      final vocab = buildTutorInsights(
        const InsightSource(vocabEstimate: 2500),
      ).firstWhere((i) => i.dimension == 'vocab');
      expect(vocab.valueText, '2,500 词');
      expect(vocab.severity, 1);
      expect(vocab.actionJump, isNull, reason: '没有待办时不用挂动作按钮');
    });
  });

  group('语法维度', () {
    test('错误标签给 top2 + 总数,次数多 → 该动手', () {
      final grammar = buildTutorInsights(
        const InsightSource(
          errorTagCounts: {'时态': 8, '冠词': 5, '词汇': 3},
        ),
      ).firstWhere((i) => i.dimension == 'grammar');
      expect(grammar.measured, isTrue);
      expect(grammar.valueText, '时态 8 次 · 冠词 5 次');
      expect(grammar.evidence, contains('3 类 16 次'));
      expect(grammar.severity, 2);
      expect(grammar.actionJump, TutorActionJumps.output);
      expect(grammar.actionLabel, contains('时态'));
    });

    test('只错一次 → 有数据但不算薄弱(severity 0、不给动作)', () {
      final grammar = buildTutorInsights(
        const InsightSource(errorTagCounts: {'冠词': 1}),
      ).firstWhere((i) => i.dimension == 'grammar');
      expect(grammar.measured, isTrue);
      expect(grammar.severity, 0);
      expect(grammar.actionJump, isNull);
    });

    test('没有错误标签 → 待测,动作是"去写一段自动建档"', () {
      final grammar = buildTutorInsights(const InsightSource())
          .firstWhere((i) => i.dimension == 'grammar');
      expect(grammar.measured, isFalse);
      expect(grammar.actionJump, TutorActionJumps.output);
      expect(grammar.evidence, contains('写'));
    });
  });

  group('阅读维度', () {
    test('wpm 偏慢 → severity 2,值带单位', () {
      final reading = buildTutorInsights(
        const InsightSource(readingWpm: 90),
      ).firstWhere((i) => i.dimension == 'reading');
      expect(reading.measured, isTrue);
      expect(reading.valueText, '90 词/分');
      expect(reading.severity, 2);
      expect(reading.actionJump, TutorActionJumps.reading);
    });

    test('正常速度 + 读完材料 → 正常且不给动作', () {
      final reading = buildTutorInsights(
        const InsightSource(readingWpm: 150, materialsFinished30d: 2),
      ).firstWhere((i) => i.dimension == 'reading');
      expect(reading.valueText, contains('150 词/分'));
      expect(reading.valueText, contains('读完 2 篇'));
      expect(reading.severity, 0);
      expect(reading.actionJump, isNull);
    });

    test('近 30 天一篇没读完 → 注意(severity 1)', () {
      final reading = buildTutorInsights(
        const InsightSource(materialsFinished30d: 0),
      ).firstWhere((i) => i.dimension == 'reading');
      expect(reading.valueText, contains('读完 0 篇'));
      expect(reading.severity, 1);
    });

    test('完全没有阅读数据 → 待测', () {
      final reading = buildTutorInsights(const InsightSource())
          .firstWhere((i) => i.dimension == 'reading');
      expect(reading.measured, isFalse);
      expect(reading.actionJump, TutorActionJumps.reading);
    });
  });

  group('输出维度', () {
    test('有练习与均分 → 值/依据完整,频率够则正常', () {
      final output = buildTutorInsights(
        const InsightSource(
          outputAttempts30d: 6,
          writeLogs30d: 2,
          outputAvgScore: 85,
          outputLastAt: null,
        ),
      ).firstWhere((i) => i.dimension == 'output');
      expect(output.measured, isTrue);
      expect(output.valueText, contains('6 次练习'));
      expect(output.valueText, contains('2 篇写译'));
      expect(output.valueText, contains('均分 85'));
      expect(output.severity, 0);
    });

    test('均分偏低(0~1 归一化也兼容) → 该动手', () {
      final output = buildTutorInsights(
        const InsightSource(outputAttempts30d: 5, outputAvgScore: 0.55),
      ).firstWhere((i) => i.dimension == 'output');
      expect(output.valueText, contains('均分 55'));
      expect(output.severity, 2);
    });

    test('输出次数少(1~3 次) → 注意', () {
      final output = buildTutorInsights(
        const InsightSource(outputAttempts30d: 2, outputAvgScore: 72),
      ).firstWhere((i) => i.dimension == 'output');
      expect(output.severity, 1);
    });

    test('明确知道近 30 天 0 次输出(有输入) → 实测 0 + 该动手', () {
      final output = buildTutorInsights(
        const InsightSource(
          outputAttempts30d: 0,
          writeLogs30d: 0,
          readingWpm: 150,
        ),
      ).firstWhere((i) => i.dimension == 'output');
      expect(output.measured, isTrue);
      expect(output.valueText, contains('0 次练习'));
      expect(output.valueText, contains('0 篇写译'));
      expect(output.severity, 2);
    });

    test('完全没采到输出数据 → 待测;有输入时提示更重', () {
      final newUser = buildTutorInsights(const InsightSource())
          .firstWhere((i) => i.dimension == 'output');
      expect(newUser.measured, isFalse);
      expect(newUser.severity, 0, reason: '新用户缺数据 = 中性,和其它待测维度同档');

      final readOnly = buildTutorInsights(
        const InsightSource(readingWpm: 150),
      ).firstWhere((i) => i.dimension == 'output');
      expect(readOnly.measured, isFalse);
      expect(readOnly.severity, 2, reason: '有输入没输出 = 该动手');
    });
  });

  group('习惯维度', () {
    test('连续天数 + 每日目标 → 正常', () {
      final habit = buildTutorInsights(
        const InsightSource(streakDays: 6, dailyMinutes: 30),
      ).firstWhere((i) => i.dimension == 'habit');
      expect(habit.measured, isTrue);
      expect(habit.valueText, contains('连续 6 天'));
      expect(habit.valueText, contains('每天目标 30 分钟'));
      expect(habit.severity, 0);
      expect(habit.actionJump, isNull);
    });

    test('没设每日目标 → 注意,动作去偏好页', () {
      final habit = buildTutorInsights(
        const InsightSource(streakDays: 3),
      ).firstWhere((i) => i.dimension == 'habit');
      expect(habit.severity, 1);
      expect(habit.actionJump, TutorActionJumps.prefs);
    });

    test('连续天数为 0 → 注意,动作是今天先学 5 分钟', () {
      final habit = buildTutorInsights(
        const InsightSource(streakDays: 0, dailyMinutes: 30),
      ).firstWhere((i) => i.dimension == 'habit');
      expect(habit.severity, 1);
      expect(habit.actionJump, TutorActionJumps.reading);
      expect(habit.actionLabel, contains('5 分钟'));
    });

    test('没有任何习惯数据 → 待测', () {
      final habit = buildTutorInsights(const InsightSource())
          .firstWhere((i) => i.dimension == 'habit');
      expect(habit.measured, isFalse);
      expect(habit.actionLabel, isNotNull);
    });
  });

  group('排序', () {
    test('severity 降序 → 有数据的在前 → 维度固定顺序', () {
      final insights = buildTutorInsights(const InsightSource(
        vocabEstimate: 4200,
        reviewRetention: 0.6, // vocab severity 2
        errorTagCounts: {'时态': 8}, // grammar severity 2
        readingWpm: 90, // reading severity 2
        outputAttempts30d: 0, // output severity 2(有输入)
        materialsFinished30d: 2,
        streakDays: 0,
        dailyMinutes: 30, // habit severity 1
      ));
      expect(insights.length, 5);
      expect(
        insights.take(4).map((i) => i.dimension).toList(),
        ['vocab', 'grammar', 'reading', 'output'],
        reason: '同样 severity=2 时按维度固定顺序',
      );
      expect(insights.last.dimension, 'habit');
      expect(insights.map((i) => i.severity).toList(),
          [2, 2, 2, 2, 1]);
    });

    test('有数据的维度排在待测维度之前(即使 severity 相同)', () {
      final insights = buildTutorInsights(
        const InsightSource(vocabEstimate: 8000),
      );
      expect(insights.first.dimension, 'vocab');
      expect(insights.first.measured, isTrue);
      expect(insights.where((i) => i.measured).length, 1);
    });
  });

  group('任务建议', () {
    const rich = InsightSource(
      vocabEstimate: 4200,
      dueWords: 12,
      outputAttempts30d: 2,
      errorTagCounts: {'时态': 8},
      materialsReading: 1,
      examGoals: ['四六级'],
      dailyMinutes: 30,
      streakDays: 3,
    );

    test('数据丰富时给出 3~4 条,每条都有真实理由/分钟/动作', () {
      final tasks = suggestTutorTasks(rich);
      expect(tasks.length, inInclusiveRange(3, 4));
      expect(tasks.length, lessThanOrEqualTo(4));
      final titles = tasks.map((t) => t.title).toSet();
      expect(titles.length, tasks.length, reason: '任务不能重复');
      for (final task in tasks) {
        expect(task.reason, isNotEmpty);
        expect(task.minutes, greaterThanOrEqualTo(1));
        expect(TutorActionJumps.all, contains(task.action));
        expect(TutorGoalTags.all, contains(task.goalTag));
      }
    });

    test('到期词/薄弱语法/输出偏少的理由里都带真实数字', () {
      final tasks = suggestTutorTasks(rich);
      expect(tasks.any((t) => t.title.contains('12')), isTrue);
      final review = tasks.firstWhere((t) => t.title.contains('12'));
      expect(review.reason, contains('12 个词'));

      final grammar = tasks.firstWhere((t) => t.title.contains('时态'));
      expect(grammar.reason, contains('8 次'));
      expect(grammar.goalTag, TutorGoalTags.grammar);

      final output = tasks.firstWhere((t) => t.goalTag == 'output');
      expect(output.reason, contains('2 次输出'));
    });

    test('有词汇量基线时不再派"速测"任务', () {
      final tasks = suggestTutorTasks(rich);
      expect(tasks.any((t) => t.title.contains('速测')), isFalse);
    });

    test('全空数据 → 给基础任务(先测词汇量),数量 3~4、理由不空', () {
      final tasks = suggestTutorTasks(const InsightSource());
      expect(tasks.length, inInclusiveRange(3, 4));
      expect(tasks.any((t) => t.title.contains('速测')), isTrue);
      expect(tasks.any((t) => t.action == TutorActionJumps.placement), isTrue);
      for (final task in tasks) {
        expect(task.reason, isNotEmpty);
        expect(task.minutes, greaterThanOrEqualTo(1));
      }
    });

    test('明确知道输出为 0 时,理由写"0 次"而不是编造', () {
      final tasks = suggestTutorTasks(
        const InsightSource(
          vocabEstimate: 5000,
          outputAttempts30d: 0,
          writeLogs30d: 0,
          dailyMinutes: 30,
          streakDays: 5,
        ),
      );
      final output = tasks.firstWhere((t) => t.goalTag == 'output');
      expect(output.reason, contains('0 次'));
    });

    test('max 生效且不重复:max=1 → 1 条;max=0 → 空', () {
      expect(suggestTutorTasks(rich, max: 1).length, 1);
      expect(suggestTutorTasks(rich, max: 0), isEmpty);
    });

    test('复习任务分钟按约 6 秒/词估(30 个词 → 3 分钟)', () {
      final tasks = suggestTutorTasks(
        const InsightSource(dueWords: 30, vocabEstimate: 5000),
      );
      final review = tasks.firstWhere((t) => t.goalTag == 'vocab');
      expect(review.minutes, 3);
    });
  });

  group('复盘', () {
    bool hasDigit(String line) => RegExp(r'\d').hasMatch(line);

    test('完成率按已结算口径:done/(done+skipped+expired)', () {
      final review = buildTutorReview(
        planned: 10,
        done: 6,
        skipped: 2,
        expired: 2,
      );
      expect(review.metrics['settled'], 10);
      expect(review.metrics['completionRate'], closeTo(0.6, 1e-9));
      expect(review.metrics['pending'], 0);
      expect(review.lines.length, inInclusiveRange(2, 4));
      for (final line in review.lines) {
        expect(hasDigit(line), isTrue, reason: '每条结论都必须带数字: $line');
      }
      expect(review.lines.any((l) => l.contains('60%')), isTrue);
    });

    test('未结算任务进 pending,不冒充完成率分母', () {
      final review = buildTutorReview(
        planned: 8,
        done: 2,
        skipped: 1,
        expired: 0,
      );
      expect(review.metrics['settled'], 3);
      expect(review.metrics['pending'], 5);
      expect((review.metrics['completionRate'] as num).toDouble(),
          closeTo(2 / 3, 1e-9));
      expect(review.lines.any((l) => l.contains('另有 5 条')), isTrue);
    });

    test('计划 vs 实际时长:timeRatio 与偏差百分比', () {
      final review = buildTutorReview(
        planned: 2,
        done: 2,
        skipped: 0,
        expired: 0,
        plannedMinutes: 120,
        actualMinutes: 150,
      );
      expect(review.metrics['timeRatio'], closeTo(1.25, 1e-9));
      expect(review.lines.any((l) => l.contains('+25%')), isTrue);
    });

    test('只有实际时长:不出 timeRatio,但结论仍带数字', () {
      final review = buildTutorReview(
        planned: 1,
        done: 1,
        skipped: 0,
        expired: 0,
        actualMinutes: 40,
      );
      expect(review.metrics.containsKey('timeRatio'), isFalse);
      expect(review.lines.any((l) => l.contains('实际投入 40 分钟')), isTrue);
      for (final line in review.lines) {
        expect(hasDigit(line), isTrue);
      }
    });

    test('输出产出:0 次与均分两种口径', () {
      final zero = buildTutorReview(
        planned: 3,
        done: 1,
        skipped: 2,
        expired: 0,
        outputCount: 0,
      );
      expect(zero.lines.any((l) => l.contains('输出练习 0 次')), isTrue);

      final scored = buildTutorReview(
        planned: 3,
        done: 3,
        skipped: 0,
        expired: 0,
        outputCount: 3,
        outputAvgScore: 0.82,
      );
      expect(scored.metrics['outputAvgScore'], 82);
      expect(scored.lines.any((l) => l.contains('均分 82')), isTrue);
    });

    test('全空复盘不产生完成率指标,但 2~4 条结论每条带数字', () {
      final review = buildTutorReview(
        planned: 0,
        done: 0,
        skipped: 0,
        expired: 0,
      );
      expect(review.hasSettledTasks, isFalse);
      expect(review.metrics['settled'], 0);
      expect(review.metrics.containsKey('completionRate'), isFalse);
      expect(review.lines.length, inInclusiveRange(2, 4));
      for (final line in review.lines) {
        expect(hasDigit(line), isTrue, reason: '空数据也不能写无数字的空话: $line');
      }
    });

    test('完成率低 → 建议减量(带具体条数);高 → 建议加输出', () {
      final low = buildTutorReview(
        planned: 4,
        done: 1,
        skipped: 3,
        expired: 0,
      );
      expect(low.lines.any((l) => l.contains('减到')), isTrue);
      expect(low.lines.any((l) => l.contains('25%')), isTrue);

      final high = buildTutorReview(
        planned: 4,
        done: 4,
        skipped: 0,
        expired: 0,
      );
      expect(high.lines.any((l) => l.contains('加 1 条输出任务')), isTrue);
      expect(high.lines.any((l) => l.contains('4 → 5 条')), isTrue);
    });
  });
}
