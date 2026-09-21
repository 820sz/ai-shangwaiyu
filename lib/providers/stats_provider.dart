import 'package:flutter/material.dart';
import '../models/learning_record.dart';
import '../services/database.dart';

class StatsProvider extends ChangeNotifier {
  List<LearningRecord> _dailyLogs = [];
  int _streakDays = 0;
  int _totalVocab = 0;
  int _totalExercises = 0;
  bool _loading = false;
  String? _error;

  List<LearningRecord> get dailyLogs => _dailyLogs;
  int get streakDays => _streakDays;
  int get totalVocab => _totalVocab;
  int get totalExercises => _totalExercises;
  bool get loading => _loading;

  /// 加载失败原因(P2-30 三态):页面据此从"转圈"切到"可重试的错误态"
  String? get error => _error;

  /// 加载统计数据。
  ///
  /// P2-30:整段 try/catch + finally —— 此前任何一次 DB 读抛异常,
  /// `_loading` 就永久停在 true,统计页永远转圈且没有任何提示。
  Future<void> loadStats() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // 最近 365 天的记录
      final now = DateTime.now();
      _dailyLogs = await DatabaseService.getDailyLogsInRange(
        now.subtract(const Duration(days: 365)),
        now,
      );

      // 计算连续天数
      _streakDays = _calculateStreak(_dailyLogs);
      _totalVocab = await DatabaseService.getTotalVocabCount();
      _totalExercises = await DatabaseService.getTotalExerciseCount();
    } catch (e) {
      debugPrint('ReadFlow stats load: $e');
      _error = '统计数据加载失败：$e';
    } finally {
      // 复位放在 finally:中途失败也必须结束 loading,
      // 否则用户只能杀进程(与 P1-8 的 article_provider 同一类缺陷)
      _loading = false;
      notifyListeners();
    }
  }

  /// 计算连续学习天数
  int _calculateStreak(List<LearningRecord> records) {
    if (records.isEmpty) return 0;

    // 收集所有有活动的日期
    final activeDates = records
        .where((r) => r.totalActivity > 0)
        .map((r) => DateTime(r.date.year, r.date.month, r.date.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a)); // 降序

    if (activeDates.isEmpty) return 0;

    final today = DateTime(DateTime.now().year, DateTime.now().month,
        DateTime.now().day);
    final yesterday = today.subtract(const Duration(days: 1));

    // 必须今天或昨天有活动才计算
    if (!activeDates.contains(today) && !activeDates.contains(yesterday)) {
      return 0;
    }

    int streak = 0;
    var cursor = activeDates.first;
    for (final date in activeDates) {
      if (cursor.difference(date).inDays <= 1) {
        streak++;
        cursor = date;
      } else {
        break;
      }
    }

    return streak;
  }

  /// 按月份统计
  Map<String, int> getMonthlyStats() {
    final map = <String, int>{};
    for (final r in _dailyLogs) {
      final key = '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}';
      map[key] = (map[key] ?? 0) + r.newWordsCount;
    }
    return map;
  }
}
