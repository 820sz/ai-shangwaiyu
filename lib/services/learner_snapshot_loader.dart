import 'package:flutter/foundation.dart';

import '../models/learner_model.dart';
import '../models/learning_record.dart';
import 'database.dart';
import 'learner_model_store.dart';
import 'tutor_engine.dart';

/// 快照加载器(v2.0):把 Hive 里的画像 + SQLite 里的行为明细拼成
/// [LearnerSnapshot]。导师诊断只认这个快照,不直接碰数据库 ——
/// 这样"数据 → 结论"的关系是可测的,也避免 UI 层散落 SQL。
///
/// 读取策略:任何一项失败都退化成 0/空,**绝不让导师页因为一处查询失败而白屏**;
/// 缺哪一块,对应诊断自然就不会触发(而不是报假结论)。
class LearnerSnapshotLoader {
  LearnerSnapshotLoader._();

  static const int sessionWindowDays = 30;
  static const int habitWindowDays = 30;

  static Future<LearnerSnapshot> load({
    required List<dynamic> vocab,
    List<LearningRecord> dailyLogs = const [],
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    // 这个文件开头承诺"任何一项失败都退化成 0/空,绝不让导师页白屏",
    // 而模型读取原来**不在** `_safe` 里:Hive 未打开/读坏时会直接抛出去
    // (2026-09-24 由整链路测试暴露 —— 测试环境没开 Hive 就炸).
    // 模型读不到就退回空模型:诊断会少几条结论,但页面照常打开。
    final model = _safeModel();

    // ── 词汇维度(直接用 provider 已加载的列表,不再查库) ──
    final dist = <int, int>{0: 0, 1: 0, 2: 0};
    for (final v in vocab) {
      final lvl = (v.masteryLevel as int?) ?? 0;
      dist[lvl] = (dist[lvl] ?? 0) + 1;
    }
    final addedLast7 = await _safe(
      () => DatabaseService.getVocabCountSince(
        at.subtract(const Duration(days: 7)),
      ),
      fallback: 0,
    );

    // ── 复习维度 ──
    final due = await _safe(() => DatabaseService.getDueReviewCount(at: at), fallback: 0);
    final tracked =
        await _safe(() => DatabaseService.getTrackedReviewCount(), fallback: 0);
    final buckets =
        await _safe(() => DatabaseService.getReviewBuckets(now: at), fallback: const <String, int>{});
    final overdue = buckets['overdue'] ?? 0;

    // ── 输入维度 ──
    final stats = await _safe(
      () => DatabaseService.getReadingStats(days: sessionWindowDays),
      fallback: const <String, Object?>{},
    );
    final recentRows = await _safe(
      () => DatabaseService.getRecentMaterials(limit: 5),
      fallback: const <Map<String, Object?>>[],
    );
    final finished = await _safe(() => DatabaseService.countMaterialsFinished(), fallback: 0);

    // ── 输出与反馈维度 ──
    final quizAcc = await _safe(
      () => DatabaseService.getQuizAccuracy(days: sessionWindowDays),
      fallback: const <String, double>{},
    );
    final errorRows = await _safe(
      () => DatabaseService.getErrorTags(status: 'active'),
      fallback: const <Map<String, Object?>>[],
    );

    // ── 习惯维度(用本地已有的 daily_log,和「学习统计」页同一份数据) ──
    final activeDays = dailyLogs
        .where((r) =>
            r.date.isAfter(at.subtract(Duration(days: habitWindowDays))) &&
            (r.newWordsCount > 0 ||
                r.reviewedCount > 0 ||
                r.exerciseCompleted > 0))
        .length;
    final streak = streakDays(dailyLogs, at);

    return LearnerSnapshot(
      model: model,
      now: at,
      totalVocab: vocab.length,
      masteryNew: dist[0] ?? 0,
      masteryLearning: dist[1] ?? 0,
      masteryMastered: dist[2] ?? 0,
      vocabAddedLast7Days: addedLast7,
      dueReviewCount: due,
      overdueCount: overdue,
      trackedReviewCount: tracked,
      readingSessions30d: _int(stats['sessions']),
      readingWords30d: _int(stats['words']),
      readingMinutes30d: _int(stats['minutes']),
      avgWpm: _double(stats['avg_wpm']),
      // v2.3.1:getRecentMaterials 已改成 LEFT JOIN(材料库里"入库但没打开过"的
      // 材料也要出现在书架),所以这里不能再拿行数当"在学份数" —— 只有真正
      // 有进度(读过 / 标记读完)的才算"在学"
      materialsStarted: recentRows
          .where((r) =>
              (_double(r['percent']) ?? 0) > 0 || r['finished_at'] != null)
          .length,
      materialsFinished: finished,
      recentMaterials: recentRows.map(_toRecentMaterial).toList(),
      quizAccuracy: quizAcc,
      errorTags: errorRows
          .map((r) => ErrorTagStat(
                tag: '${r['tag'] ?? ''}',
                count: _int(r['count']),
                status: '${r['status'] ?? 'active'}',
              ))
          .where((e) => e.tag.isNotEmpty)
          .toList(),
      streakDays: streak,
      activeDays30d: activeDays,
    );
  }

  /// 把 materials + progress 的 JOIN 行转成引擎认识的结构
  static RecentMaterial _toRecentMaterial(Map<String, Object?> row) {
    return RecentMaterial(
      id: _int(row['id']),
      title: '${row['title'] ?? '(未命名材料)'}',
      kind: '${row['kind'] ?? 'article'}',
      coverage: _double(row['coverage']),
      percent: _double(row['percent']) ?? 0,
    );
  }

  /// 连续天数:从今天(或昨天)往前数,遇到没有记录的一天就停。
  ///
  /// **公开**:桌面小组件也要显示"连续 N 天" —— 两个地方各写一份判断
  /// ("今天没学算不算断")必然会出现桌面和 App 显示不同数字的情况,
  /// 所以这是唯一实现,谁要显示就调它。
  static int streakDays(List<LearningRecord> logs, DateTime now) {
    final days = <String>{};
    for (final r in logs) {
      if (r.newWordsCount > 0 ||
          r.reviewedCount > 0 ||
          r.exerciseCompleted > 0) {
        days.add(_dayKey(r.date));
      }
    }
    if (days.isEmpty) return 0;
    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
    // 今天还没学不算断(否则每天早上打开 App 都会看到"连续 0 天")
    if (!days.contains(_dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(_dayKey(cursor))) return 0;
    }
    while (days.contains(_dayKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 任何查询失败都退化成 fallback(导师页不因一处失败白屏)
  static Future<T> _safe<T>(Future<T> Function() run, {required T fallback}) async {
    try {
      return await run();
    } catch (e) {
      debugPrint('ReadFlow 快照读取失败(已降级): $e');
      return fallback;
    }
  }

  /// 同步版(模型从 Hive 同步读)。只用于 [LearnerModelStore.load] ——
  /// 读失败就交回空模型,调用方(诊断)少几条结论但页面照常打开。
  static LearnerModel _safeModel() {
    try {
      return LearnerModelStore.load();
    } catch (e) {
      debugPrint('ReadFlow 学习者模型读取失败(已降级,用空模型): $e');
      return LearnerModel();
    }
  }

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static double? _double(Object? v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }
}
