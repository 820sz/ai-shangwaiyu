import 'package:flutter/foundation.dart';

import '../models/learner_model.dart';
import 'database.dart';
import 'learner_model_store.dart';

/// 死字段回写(v3 · 批 8 · C1-15)。
///
/// 背景:`LearnerContext`(难度分析 / 阅读器速度预估)一直在读
/// `LearnerModel.extras['reading_wpm']` 与 `extras['vocab_inferred']`,
/// 但**全仓没有任何地方写这两个键** —— 于是 extras 里永远是空的:
/// 阅读速度永远回落默认 200wpm、推断词汇量永远用不到(审计报告 C1-15)。
///
/// 这里只做"把真实数据写回去",**不改任何读取逻辑**:
/// - 数据来源必须真实:`reading_wpm` 取近 30 天阅读会话的 avg_wpm;
///   `vocab_inferred` 取**词汇量测试(test 来源)**的估计值 —— 没有测量基线
///   就不写(不拿收藏数瞎猜,那正是 v1.9 的错误)。
/// - 幂等:值没变不写盘。打开助理/统计页是高频动作,每次重新序列化整份
///   Hive 模型对象没有意义,也会放大"写一半"的风险。
class LearnerExtrasSync {
  LearnerExtrasSync._();

  /// `extras` 里阅读速度的键(与 [LearnerContext.wpmFor] 读取的键一致;
  /// 单一事实源:改这里必须同步改 `LearnerContext` 的读取处)
  static const String readingWpmKey = 'reading_wpm';

  /// `extras` 里推断词汇量的键(与 [LearnerContext.effectiveVocab] 一致)
  static const String vocabInferredKey = 'vocab_inferred';

  /// 合法阅读速度区间(与 `LearnerContext.wpmFor` 的 60..1000 一致)。
  ///
  /// 超出区间的"实测值"多半是坏会话(例如时长接近 0),写进去也只会被读取侧
  /// 忽略 —— 这里先挡住,避免 extras 里藏一个永远不生效的脏值。
  static const int minWpm = 60;
  static const int maxWpm = 1000;

  /// 回写 `reading_wpm`。
  ///
  /// [avgWpm] 可由调用方传入(打开助理时快照里已经算过,省一次查库);
  /// 不传则自己查近 [days] 天的 [DatabaseService.getReadingStats]。
  /// 返回是否真的写盘(false = 没数据 / 值没变 / 失败)。
  static Future<bool> syncReadingWpm({double? avgWpm, int days = 30}) async {
    try {
      var value = avgWpm;
      if (value == null) {
        final stats = await DatabaseService.getReadingStats(days: days);
        final raw = stats['avg_wpm'];
        value = raw is num ? raw.toDouble() : null;
      }
      // >0 才写:0 表示"没有任何带时长的阅读会话",不是"速度为 0"
      if (value == null || !value.isFinite || value <= 0) return false;
      final wpm = value.round();
      if (wpm < minWpm || wpm > maxWpm) return false;
      final model = LearnerModelStore.load();
      if (_sameNum(model.extras[readingWpmKey], wpm)) return false;
      final extras = Map<String, dynamic>.from(model.extras)
        ..[readingWpmKey] = wpm;
      await LearnerModelStore.save(model.copyWith(extras: extras));
      return true;
    } catch (e) {
      // 回写失败只影响"个性化精度",绝不能影响打开助理/统计页
      debugPrint('LearnerExtrasSync reading_wpm 回写失败(已忽略): $e');
      return false;
    }
  }

  /// 回写 `vocab_inferred`(只有 test 来源的测量基线才写)。
  ///
  /// [model] 可由调用方传入(助理快照里已有模型,省一次 Hive 读);
  /// 不传则自己 [LearnerModelStore.load]。
  static Future<bool> syncVocabInferred({LearnerModel? model}) async {
    try {
      final m = model ?? LearnerModelStore.load();
      final field = m.vocabEstimate;
      // 只写"测出来的":自报/已有的 inferred 值再写回 extras 是自我循环,
      // 还会把"我没测过"伪装成"系统推断过"
      if (field == null ||
          field.value <= 0 ||
          field.source != ProfileSource.test) {
        return false;
      }
      final estimate = field.value;
      if (_sameNum(m.extras[vocabInferredKey], estimate)) return false;
      final extras = Map<String, dynamic>.from(m.extras)
        ..[vocabInferredKey] = estimate;
      await LearnerModelStore.save(m.copyWith(extras: extras));
      return true;
    } catch (e) {
      debugPrint('LearnerExtrasSync vocab_inferred 回写失败(已忽略): $e');
      return false;
    }
  }

  /// 两个键一起回写(打开助理 / 统计页时调用;两块各自静默)。
  static Future<void> syncAll() async {
    await syncReadingWpm();
    await syncVocabInferred();
  }

  static bool _sameNum(Object? existing, int value) {
    if (existing is int) return existing == value;
    if (existing is num) return existing.toDouble() == value.toDouble();
    return false;
  }
}
