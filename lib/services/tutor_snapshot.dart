import 'dart:convert';

import '../models/learning_record.dart';
import 'database.dart';
import 'exam_vocab.dart';
import 'input_prefs.dart';
import 'learner_snapshot_loader.dart';
import 'output_feedback.dart';
import 'tutor_engine.dart';
import 'tutor_insights.dart';

/// 助理工作台的**数据组装层**(v3 · 批 4)。
///
/// 为什么要单独一层:助理首页要同时用到四类来源 ——
/// 1. `LearnerSnapshot`(词汇/复习/阅读/习惯,含批 3 收尾新加的输出字段);
/// 2. `InputPreferences`(多选目标/难度档/偏好,访谈与「我的需求」写的);
/// 3. `OutputFeedback.outputSnapshot`(rubric 作答聚合:次数/均分/错误热点);
/// 4. `taskCompletionStats` + 当日任务(复盘与任务列表)。
///
/// 以前这些查询散落在 `tutor_home.build()` 里、各查各的,于是①界面上出现的是
/// "11 条互相独立的行为债提醒"而不是"五维现状";②任何一处查询失败都可能
/// 让整页空白。现在统一在这一层组装:**每块都降级**,一块失败只少一块,
/// 页面永远能打开(用户要的是"看得出来我现在的状态",不是"页面能不能开")。
class TutorDashboard {
  final LearnerSnapshot snapshot;
  final InputPreferences prefs;

  /// 五维现状的输入(全部字段都可空,没有就不编)
  final InsightSource source;

  /// 排好序的五维现状
  final List<TutorInsight> insights;

  /// 可编辑任务建议(尚未落库;落库由用户在界面确认)
  final List<TaskSuggestion> suggestions;

  /// 近 7 天复盘
  final TutorReview review;

  /// 今天的任务(来自 tutor_tasks,已含状态机字段)
  final List<Map<String, Object?>> todayTasks;

  /// 复盘原始统计(UI 画小图表/兜底数字)
  final Map<String, Object?> reviewStats;

  /// 输出聚合原始数据(给任务理由/错误热点复用)
  final Map<String, Object?> outputStats;

  const TutorDashboard({
    required this.snapshot,
    required this.prefs,
    required this.source,
    required this.insights,
    required this.suggestions,
    required this.review,
    required this.todayTasks,
    required this.reviewStats,
    required this.outputStats,
  });

  /// 一个"今天该做什么"的入口:有建议就用建议,否则用任务表的未完成项。
  bool get hasAnyTask => todayTasks.isNotEmpty || suggestions.isNotEmpty;
}

class TutorSnapshotService {
  TutorSnapshotService._();

  /// 组装助理工作台。**任何一块失败都降级**,不抛异常。
  ///
  /// [vocab]/[dailyLogs] 可由调用方注入(页面里已有 Provider 数据时直接用,
  /// 省一次查库);不传就从数据库读 —— 这样后台/冷启动也能组装。
  static Future<TutorDashboard> load({
    DateTime? now,
    List<dynamic>? vocab,
    List<LearningRecord>? dailyLogs,
  }) async {
    final at = now ?? DateTime.now();

    // ① 学习者快照(它自己内部每块都已降级)
    var vocabList = vocab;
    if (vocabList == null) {
      try {
        vocabList = await DatabaseService.getVocabularies(limit: 1000);
      } catch (_) {
        vocabList = const [];
      }
    }
    var logs = dailyLogs;
    if (logs == null) {
      try {
        logs = await DatabaseService.getDailyLogsInRange(
          at.subtract(const Duration(days: 365)),
          at,
        );
      } catch (_) {
        logs = const <LearningRecord>[];
      }
    }
    final snapshot = await LearnerSnapshotLoader.load(
      vocab: vocabList,
      dailyLogs: logs,
      now: at,
    );

    // ② 输入偏好(读不到就用 empty,不会炸)
    var prefs = InputPreferences.load();

    // ③ 输出聚合
    Map<String, Object?> outputStats = const <String, Object?>{};
    try {
      outputStats = await OutputFeedback.outputSnapshot(now: at);
    } catch (_) {
      // 输出聚合失败:五维里的 output 维度会显示"待测",不编数字
    }

    // ④ 错误档案(active 优先;fixed 不算薄弱点)
    final errorCounts = <String, int>{};
    for (final tag in snapshot.errorTags) {
      if (tag.status == 'fixed') continue;
      errorCounts[tag.tag] = (errorCounts[tag.tag] ?? 0) + tag.count;
    }
    // 输出练习批改出来的错误也并进来(同一标签体系,合并计数)
    final outTags = outputStats['topErrorTags'];
    if (outTags is Map) {
      for (final entry in outTags.entries) {
        final tag = '${entry.key}';
        final n = entry.value is num ? (entry.value as num).toInt() : 0;
        if (tag.isEmpty || n <= 0) continue;
        errorCounts[tag] = (errorCounts[tag] ?? 0) + n;
      }
    }

    // ⑤ 近 30 天材料统计(读完/在读数)
    var finished30d = 0;
    var readingCount = 0;
    try {
      final rows = await DatabaseService.getRecentMaterials(limit: 20);
      final from = at.subtract(const Duration(days: 30));
      for (final row in rows) {
        final finishedRaw = '${row['finished_at'] ?? ''}'.trim();
        final percent = row['percent'] is num
            ? (row['percent'] as num).toDouble()
            : double.tryParse('${row['percent'] ?? ''}') ?? 0;
        if (finishedRaw.isNotEmpty) {
          final t = DateTime.tryParse(finishedRaw);
          if (t != null && t.isAfter(from)) finished30d++;
        } else if (percent > 0) {
          readingCount++;
        }
      }
    } catch (_) {
      // 材料统计失败:reading 维度退回只靠 wpm/在读数,仍可显示
    }

    final vocabEstimate = snapshot.model.vocabEstimate?.value;
    final vocabLow = snapshot.model.vocabLow;
    final vocabHigh = snapshot.model.vocabHigh;
    final vocabCi =
        (vocabLow != null && vocabHigh != null && vocabLow > 0 && vocabHigh > vocabLow)
            ? ((vocabHigh - vocabLow) / 2).round()
            : null;

    // 距目标词表还差多少词(批 7 · P1-3):需要"词表资产 + 词汇量基线"两者。
    // 词表加载失败/没有基线都退回 null(维度里就不出现这条依据),绝不编数字;
    // 单独 try/catch:词表问题不能把整页五维拖垮。
    int? goalWordsGap;
    try {
      await ExamVocab.ensureLoaded();
      goalWordsGap = ExamVocab.goalWordsGap(prefs.examGoals, vocabEstimate);
    } catch (_) {
      goalWordsGap = null;
    }

    final source = InsightSource(
      vocabEstimate: vocabEstimate,
      vocabCi: vocabCi,
      cefr: snapshot.model.cefr?.value,
      dueWords: snapshot.dueReviewCount,
      // 复习留存率:目前没有现成聚合口径,**不猜**(null → 维度里不出现这条依据)
      reviewRetention: null,
      errorTagCounts: errorCounts,
      readingWpm: (snapshot.avgWpm ?? 0) > 0 ? snapshot.avgWpm : null,
      materialsFinished30d: finished30d,
      materialsReading: readingCount > 0 ? readingCount : snapshot.materialsStarted,
      outputAttempts30d: snapshot.outputAttempts30d,
      outputAvgScore: snapshot.outputAvgScore,
      outputLastAt: snapshot.outputLastAt,
      writeLogs30d: snapshot.writeLogs30d,
      streakDays: snapshot.streakDays,
      dailyMinutes: (snapshot.model.dailyMinutes?.value ?? 0) > 0
          ? snapshot.model.dailyMinutes!.value
          : null,
      examGoals: prefs.examGoals,
      goalWordsGap: goalWordsGap,
    );

    final insights = buildTutorInsights(source);
    final suggestions = suggestTutorTasks(source);

    // ⑥ 近 7 天任务复盘(+ v3 批 8 的按时率/按类型产出/连续跳过)
    var reviewStats = const <String, Object?>{};
    TutorReview review;
    var recentTasks = const <Map<String, Object?>>[];
    try {
      recentTasks = await DatabaseService.listTutorTasks(limit: 100);
    } catch (_) {
      recentTasks = const <Map<String, Object?>>[];
    }
    try {
      reviewStats = await DatabaseService.taskCompletionStats(
        since: at.subtract(const Duration(days: 7)),
      );
    } catch (_) {
      reviewStats = const <String, Object?>{};
    }
    final planned = _int(reviewStats['planned']);
    final done = _int(reviewStats['done']);
    final skipped = _int(reviewStats['skipped']);
    final expired = _int(reviewStats['expired']);
    final avgActual = reviewStats['avgActualMinutes'];
    final avgActualMinutes =
        avgActual is num ? avgActual.toDouble() : null;

    // 按时率:近 7 天完成、且同时有目标时长与实际用时的任务。
    // 口径写清楚:实际 ≤ 目标 ×1.2 才算"按时"(留 20% 缓冲,不逼人卡秒)。
    var onTimeDone = 0;
    var doneWithTarget = 0;
    final doneByGoalTag = <String, int>{};
    final weekStart = at.subtract(const Duration(days: 7));
    for (final task in recentTasks) {
      final status =
          '${task['status'] ?? (task['done_at'] != null ? 'done' : 'pending')}';
      if (status != 'done') continue;
      final doneAt = DateTime.tryParse('${task['done_at'] ?? ''}');
      if (doneAt == null || doneAt.isBefore(weekStart)) continue;
      final tag = '${task['goal_tag'] ?? ''}'.trim();
      if (tag.isNotEmpty) {
        doneByGoalTag[tag] = (doneByGoalTag[tag] ?? 0) + 1;
      }
      final actual = _int(task['actual_minutes']);
      final target = _int(task['target_minutes']);
      if (actual > 0 && target > 0) {
        doneWithTarget++;
        if (actual <= target * 1.2) onTimeDone++;
      }
    }
    // 连续跳过:任务按新→旧排,数开头连续 skipped 的条数
    var skipStreak = 0;
    for (final task in recentTasks) {
      final status =
          '${task['status'] ?? (task['done_at'] != null ? 'done' : 'pending')}';
      if (status != 'skipped') break;
      skipStreak++;
    }

    review = buildTutorReview(
      planned: planned,
      done: done,
      skipped: skipped,
      expired: expired,
      // 总时长 = 平均分钟 × 完成条数(数据层只给平均);没有样本就 null
      actualMinutes:
          avgActualMinutes == null ? null : (avgActualMinutes * done).round(),
      plannedMinutes: null,
      outputCount: snapshot.outputAttempts30d > 0
          ? snapshot.outputAttempts30d
          : null,
      outputAvgScore: snapshot.outputAvgScore,
      onTimeDone: onTimeDone,
      doneWithTarget: doneWithTarget,
      skipStreak: skipStreak,
      doneByGoalTag: doneByGoalTag,
    );

    // ⑦ 今天的任务(日期用本地时区,和 plan_date 的写入口径一致)
    List<Map<String, Object?>> todayTasks = const [];
    try {
      todayTasks = await DatabaseService.listTutorTasks(
        planDate: _dateKey(at),
        limit: 30,
      );
    } catch (_) {
      // 任务列表失败:建议卡仍可显示(建议来自实时数据,不依赖任务表)
    }

    // ⑧ 能力快照落库(每次打开助理记一条;upsert 口径由 DB 层保证不重复)
    //    只记"确实有数据"的维度,避免用 0 覆盖历史。
    try {
      await _persistAbilities(source, at);
    } catch (_) {
      // 快照写失败不影响本次展示
    }

    return TutorDashboard(
      snapshot: snapshot,
      prefs: prefs,
      source: source,
      insights: insights,
      suggestions: suggestions,
      review: review,
      todayTasks: todayTasks,
      reviewStats: reviewStats,
      outputStats: outputStats,
    );
  }

  /// 把这次读到的能力值写成时间序列(趋势图/复盘用)。
  ///
  /// 只写**真测到**的维度:用 `null` 表示"没采到"的字段这里直接跳过,
  /// 不能写成 0 —— 否则"从 4000 跌到 0"的假趋势会出现在统计里。
  static Future<void> _persistAbilities(
    InsightSource source,
    DateTime at,
  ) async {
    Future<void> put(String dimension, num? value, String unit,
        String sourceName, String evidence) async {
      if (value == null) return;
      await DatabaseService.insertAbilitySnapshot({
        'dimension': dimension,
        'value': value,
        'unit': unit,
        'source': sourceName,
        'confidence': sourceName == 'test' ? 0.9 : 0.6,
        'snapshot_at': at.toIso8601String(),
        'evidence_json': jsonEncode({'note': evidence}),
      });
    }

    if (source.vocabEstimate != null) {
      await put(
        'vocab',
        source.vocabEstimate,
        'words',
        'test',
        source.vocabCi != null
            ? '词频采样估算 ±${source.vocabCi}'
            : '词频采样估算',
      );
    }
    if (source.readingWpm != null) {
      await put('reading', source.readingWpm, 'wpm', 'inferred', '近 30 天阅读速度');
    }
    if (source.outputAvgScore != null) {
      await put('output', source.outputAvgScore, 'score', 'inferred', 'rubric 均分');
    }
    if (source.streakDays != null && source.streakDays! > 0) {
      await put('habit', source.streakDays, 'days', 'inferred', '连续学习天数');
    }
    if (source.errorTagCounts.isNotEmpty) {
      final total = source.errorTagCounts.values.fold<int>(0, (a, b) => a + b);
      await put('grammar', total, 'errors', 'inferred', '错误档案累计次数');
    }
  }

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static String _dateKey(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)}';
  }
}
