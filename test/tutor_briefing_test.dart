import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/learning_record.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/input_prefs.dart';
import 'package:readflow/services/tutor_briefing.dart';
import 'package:readflow/services/tutor_engine.dart';
import 'package:readflow/services/tutor_insights.dart';
import 'package:readflow/services/tutor_snapshot.dart';

/// 助理/我的两个首页的**简报文案生成器**单测。
///
/// 这一层是纯函数(不查库、不调 AI),所以能钉死三类最容易出事的东西:
/// 1. 数字是不是真的来自数据(不许编);
/// 2. 没有数据时会不会硬凑("待测"而不是 "0");
/// 3. 文案随机数相关的部分(日期/问候)在固定 now 下是不是确定。
TutorDashboard _dash({
  int dueWords = 0,
  int streakDays = 0,
  int totalVocab = 0,
  int mastered = 0,
  int vocabAdded7d = 0,
  List<Map<String, Object?>> todayTasks = const <Map<String, Object?>>[],
  List<TaskSuggestion> suggestions = const <TaskSuggestion>[],
  List<TutorInsight> insights = const <TutorInsight>[],
  Map<String, int> errorTagCounts = const <String, int>{},
  Map<String, num> metrics = const <String, num>{},
  List<String> reviewLines = const <String>[],
  DateTime? now,
}) {
  final DateTime at = now ?? DateTime(2026, 11, 6, 20, 30);
  return TutorDashboard(
    snapshot: LearnerSnapshot(
      model: LearnerModel(),
      now: at,
      totalVocab: totalVocab,
      dueReviewCount: dueWords,
      streakDays: streakDays,
      masteryMastered: mastered,
      vocabAddedLast7Days: vocabAdded7d,
      outputAttempts30d: 0,
    ),
    prefs: InputPreferences(),
    source: InsightSource(
      vocabEstimate: totalVocab > 0 ? totalVocab : null,
      dueWords: dueWords > 0 ? dueWords : null,
      errorTagCounts: errorTagCounts,
      streakDays: streakDays > 0 ? streakDays : null,
    ),
    insights: insights,
    suggestions: suggestions,
    review: TutorReview(lines: reviewLines, metrics: metrics),
    todayTasks: todayTasks,
    reviewStats: const <String, Object?>{},
    outputStats: const <String, Object?>{},
  );
}

void main() {
  final DateTime now = DateTime(2026, 11, 6, 20, 30);

  group('TutorBriefing.build · 有数据', () {
    final List<LearningRecord> logs = <LearningRecord>[
      LearningRecord(
        date: DateTime(2026, 11, 4),
        newWordsCount: 12,
        reviewedCount: 30,
        exerciseCompleted: 1,
      ),
      LearningRecord(
        date: DateTime(2026, 11, 5),
        newWordsCount: 6,
        reviewedCount: 18,
      ),
    ];
    final TutorDashboard dash = _dash(
      dueWords: 42,
      streakDays: 6,
      totalVocab: 4200,
      mastered: 300,
      vocabAdded7d: 12,
      suggestions: const <TaskSuggestion>[
        TaskSuggestion(
          title: '复习 42 个到期词',
          reason: '3 天内到期,复习准确率 82%',
          minutes: 12,
          action: 'review',
          goalTag: 'vocab',
        ),
      ],
      insights: const <TutorInsight>[
        TutorInsight(
          dimension: 'vocab',
          title: '词汇量 4,200 词',
          valueText: '4,200',
          evidence: 'CEFR B1 · 距目标 800 词',
          measured: true,
          severity: 0,
        ),
        TutorInsight(
          dimension: 'output',
          title: '近 30 天还没写过',
          valueText: '待测',
          evidence: '写译记录为空',
          measured: false,
          severity: 1,
        ),
      ],
      errorTagCounts: const <String, int>{'时态': 7, '冠词': 3},
      metrics: const <String, num>{
        'planned': 4,
        'done': 3,
        'skipped': 1,
        'settled': 4,
        'completionRate': 0.75,
        'outputCount': 3,
        'outputAvgScore': 78.0,
      },
      reviewLines: const <String>['已结算 4 条:完成 3、跳过 1,完成率 75%'],
      now: now,
    );
    final Briefing b = TutorBriefing.build(dash, dailyLogs: logs, now: now);

    test('刊头/日期/问候在固定 now 下是确定的', () {
      expect(b.dateBig, '11 / 06');
      expect(b.weekday, '周五');
      expect(b.eyebrow.endsWith('BRIEF'), isTrue);
      expect(b.greeting, '晚上好。');
      expect(b.streakText, '连续 6 天');
    });

    test('一句话标题与时长来自今天真实任务(建议尚未落库时标「建议」)', () {
      expect(b.headline, contains('今天有 1 件事'));
      expect(b.headline, contains('42 个到期词'));
      expect(b.totalMinutes, 12);
      expect(b.today.length, 1);
      expect(b.today.first.title, '复习 42 个到期词');
      expect(b.today.first.status, 'suggestion');
      expect(b.todayNote, contains('助理建议'));
    });

    test('正文只用真实字段,且末尾接最贴近的一条结论(不贴内部口径)', () {
      expect(b.lead, contains('连续第 6 天'));
      expect(b.lead, contains('已掌握 300 个词'));
      expect(b.lead, contains('近 7 天新收 12 个词'));
      // 用 insight.title(人话)而不是 evidence(可能含表名/口径)
      expect(b.lead, contains('词汇量 4,200 词'));
      expect(b.lead, isNot(contains('error_tags')));
    });

    test('这周事实只取 metrics 里存在的键,并给出对应说明', () {
      expect(b.weekStats.map((BriefFact f) => f.value), contains('75%'));
      expect(b.weekStats.map((BriefFact f) => f.label), contains('任务完成率'));
      expect(b.weekStats.map((BriefFact f) => f.value), contains('3 次'));
      expect(b.weekNote, contains('输出均分 78 分'));
    });

    test('近 7 天柱按日期对齐,缺失的日期补 0(那天确实没有记录)', () {
      expect(b.weekBars.length, 7);
      // 索引 0 = 10-31 … 索引 4 = 11-04、索引 5 = 11-05、索引 6 = 今天
      expect(b.weekBars[4], 43); // 12 + 30 + 1
      expect(b.weekBars[5], 24); // 6 + 18
      expect(b.weekBars[6], 0);
      expect(b.weekBarsTotal, 67);
    });

    test('一句提醒来自最严重维度或错得最多的一类,不写空话', () {
      expect(b.reminder, isNotNull);
      expect(b.reminder!, contains('时态'));
    });

    test('没测到的维度单列出来(用中文维度名),并给「怎么测」', () {
      expect(b.pendingDimensions, contains('输出'));
      expect(b.pendingHint, contains('词汇量速测'));
      expect(b.pendingHint, isNot(contains('output')));
    });
  });

  group('TutorBriefing.build · 空数据(不编数字)', () {
    final TutorDashboard empty = _dash(now: now);
    final Briefing b = TutorBriefing.build(empty, now: now);

    test('没有任务时明说,不给假时间线', () {
      expect(b.headline, '今天还没有排任务。');
      expect(b.today, isEmpty);
      expect(b.totalMinutes, 0);
      expect(b.todayNote, isEmpty);
    });

    test('没有复盘数据时不出现完成率,只说明为什么', () {
      expect(b.weekStats, isEmpty);
      expect(b.weekNote, contains('还没有结算过的任务'));
    });

    test('没有依据时不出现「一句提醒」', () {
      expect(b.reminder, isNull);
    });

    test('没有五维数据时待测列表为空(不硬塞维度)', () {
      expect(b.pendingDimensions, isEmpty);
      expect(b.pendingHint, isEmpty);
    });

    test('正文给的是「从一件小事开始」而不是假数字', () {
      expect(b.lead, contains('还没有形成固定的学习节奏'));
      expect(b.lead, isNot(contains('0 个')));
      expect(b.headline, isNot(contains('大约')));
    });

    test('近 7 天没有日志时是 7 个 0(页面据此显示「暂无记录」)', () {
      final Briefing withEmptyLogs = TutorBriefing.build(
        empty,
        dailyLogs: const <LearningRecord>[],
        now: now,
      );
      expect(withEmptyLogs.weekBars.length, 7);
      expect(withEmptyLogs.weekBarsTotal, 0);
      expect(withEmptyLogs.weekNote, isNotEmpty);
    });
  });

  group('TutorBriefing.build · 今天任务(已落库)', () {
    final TutorDashboard dash = _dash(
      now: now,
      todayTasks: <Map<String, Object?>>[
        <String, Object?>{
          'id': 11,
          'title': '精读《The Four Million》',
          'status': 'pending',
          'target_minutes': 20,
          'payload': <String, Object?>{'reason': '近 7 天只读 1 篇', 'jump': 'reading'},
        },
        <String, Object?>{
          'id': 12,
          'title': '回译昨天那句',
          'status': 'done',
          'target_minutes': 7,
        },
      ],
    );
    final Briefing b = TutorBriefing.build(dash, now: now);

    test('已完成的任务不占时间线,但计入「今天已完成」的正文', () {
      expect(b.today.length, 1);
      expect(b.today.first.title, '精读《The Four Million》');
      expect(b.today.first.rawId, 11);
      expect(b.today.first.when, '20 分钟 · 待做');
      expect(b.today.first.detail, '近 7 天只读 1 篇');
      expect(b.doneToday, 1);
    });

    test('已落库任务不会被标成「建议」', () {
      expect(b.todayNote, isEmpty);
    });
  });

  group('MineBriefing.build', () {
    test('有数据:本周事实 + 词汇量区间 + 缺项清单', () {
      final MineBriefing b = MineBriefing.build(
        totalVocab: 4200,
        streakDays: 6,
        totalExercises: 120,
        dailyLogs: <LearningRecord>[
          LearningRecord(date: DateTime(2026, 11, 5), newWordsCount: 8, reviewedCount: 10),
          LearningRecord(date: DateTime(2026, 11, 4), newWordsCount: 4, reviewedCount: 6),
        ],
        activeErrorKinds: 7,
        writingLogCount: 3,
        cefr: 'B1',
        vocabEstimate: 4200,
        vocabLow: 3800,
        vocabHigh: 4600,
        now: now,
      );
      expect(b.dateBig, '11 / 06');
      expect(b.headline, contains('这周你有'));
      expect(b.headline, contains('连续 6 天'));
      expect(b.vocabText, contains('约 4200 词(3800-4600)'));
      expect(b.vocabText, contains('B1'));
      expect(b.lead, contains('待处理错误 7 类'));
      expect(b.lead, contains('写译记录 3 篇'));
      expect(b.gaps, isEmpty);
      expect(b.facts.map((BriefFact f) => f.label), contains('连续打卡'));
      expect(b.weekBarsTotal, 28);
    });

    test('空数据:明确写「还没有记录」与缺什么,不假装有基线', () {
      final MineBriefing b = MineBriefing.build(
        totalVocab: 0,
        streakDays: 0,
        totalExercises: 0,
        dailyLogs: const <LearningRecord>[],
        activeErrorKinds: 0,
        writingLogCount: 0,
        now: now,
      );
      expect(b.headline, '还没有学习记录 —— 从输入页收第一个词开始。');
      expect(b.vocabText, contains('尚未测量'));
      expect(b.gaps, contains('词汇量基线'));
      expect(b.gaps, contains('本周学习记录'));
      expect(b.facts, isEmpty);
      expect(b.weekBarsTotal, 0);
    });
  });
}
