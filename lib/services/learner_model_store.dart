import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import '../models/learner_model.dart';

/// 学习者模型持久化(v2.0)。
///
/// 为什么用 Hive 而不是立刻上 SQLite:
/// - 画像本身是**单行结构化配置**(几十个字段),Hive 的 KV 特性正好;
/// - 词级/材料级/会话级的**明细**才需要 SQL(它们是 2.0 的 `word_review` /
///   `materials` / `reading_sessions` 等表,随 dbVersion 11 落地);
/// - 这样拆的好处:词汇量测试结果现在就能落库并用起来,不必等整张模型表设计完。
class LearnerModelStore {
  /// Hive key(v2 与 v1.8 的 `learner_profile` 分开存:
  /// 老字段仍可读,避免升级时丢用户已填的自评信息)
  static const String key = 'learner_model_v2';
  static const String legacyKey = 'learner_profile';

  static Box get _box => Hive.box(AppConstants.hiveBoxSettings);

  /// 读取模型;首次读取时把 v1.8 的 `LearnerProfile` 迁移成 `self` 来源字段。
  static LearnerModel load() {
    final raw = _box.get(key);
    if (raw is Map) {
      try {
        return LearnerModel.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {
        // 坏数据不该让整页崩:退回空模型,由导师重新问
      }
    }
    return _migrateLegacy();
  }

  static Future<void> save(LearnerModel model) async {
    await _box.put(key, model.toJson());
  }

  /// 把 v1.8 的画像搬过来(只搬一次:写完 v2 后不再读老键)
  static LearnerModel _migrateLegacy() {
    final legacy = _box.get(legacyKey);
    if (legacy is! Map) return LearnerModel();
    final m = Map<String, dynamic>.from(legacy);
    final level = '${m['level'] ?? ''}';
    final goal = '${m['goal'] ?? ''}';
    final note = '${m['note'] ?? ''}';
    final interests = ((m['interests'] as List?) ?? const [])
        .map((e) => '$e')
        .where((e) => e.isNotEmpty)
        .toList();
    final migrated = LearnerModel(
      // v1.8 的"档位"是自报的 → source 标 self、置信度给低值(0.5),
      // 这正是 2.0 要修的:自评≠测量,界面必须能看出区别
      cefr: level.isEmpty
          ? null
          : ProfileField<String>(
              value: level,
              source: ProfileSource.self,
              confidence: 0.5,
            ),
      goal: goal.isEmpty
          ? null
          : ProfileField<String>(
              value: goal,
              source: ProfileSource.self,
              confidence: 0.6,
            ),
      interests: interests.isEmpty
          ? null
          : ProfileField<List<String>>(
              value: interests,
              source: ProfileSource.self,
              confidence: 0.6,
            ),
      extras: note.isEmpty ? const {} : {'legacy_note': note},
    );
    // 迁移结果落库(失败也不影响本次返回:下次还会再试)
    _box.put(key, migrated.toJson());
    return migrated;
  }

  /// 写入一次词汇量测试结果(2.0 的核心测量动作)
  static Future<LearnerModel> savePlacement({
    required int estimate,
    required int low,
    required int high,
    required String cefr,
    required double falseAlarmRate,
    required LearnerModel base,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final model = base.copyWith(
      vocabEstimate: ProfileField<int>(
        value: estimate,
        source: ProfileSource.test,
        // 伪词误报越低、测量越可信:0% → 0.9,≥40% → 0.5(自评明显不可信)
        confidence: (0.9 - falseAlarmRate.clamp(0.0, 0.4) * 1.0),
        updatedAt: now,
      ),
      vocabLow: low,
      vocabHigh: high,
      cefr: ProfileField<String>(
        value: cefr,
        source: ProfileSource.test,
        confidence: 0.85,
        updatedAt: now,
      ),
      lastPlacementAt: now,
      falseAlarmRate: falseAlarmRate,
    );
    await save(model);
    return model;
  }

  /// 用户手动纠正水平(自报覆盖测量值,但保留来源标记)
  ///
  /// 注意 [blockedTopics] / [blockedKeywords] 的语义(v2.0 黑名单 UI 依赖它):
  /// 传 `null` = 不改动现有列表;传 `[]` = 清空。因为 `copyWith` 用 `??` 兜底,
  /// 空列表能正常写入(不是 falsy),用户删光屏蔽项时能真的删掉。
  static Future<LearnerModel> saveSelfReported({
    required LearnerModel base,
    String? cefr,
    String? goal,
    int? dailyMinutes,
    int? maxNewWords,
    List<String>? interests,
    List<String>? blockedTopics,
    List<String>? blockedKeywords,
  }) async {
    final model = base.copyWith(
      cefr: (cefr == null || cefr.isEmpty)
          ? null
          : ProfileField<String>(
              value: cefr,
              source: ProfileSource.self,
              confidence: 0.5,
            ),
      clearCefr: cefr != null && cefr.isEmpty,
      goal: (goal == null || goal.isEmpty)
          ? null
          : ProfileField<String>(
              value: goal,
              source: ProfileSource.self,
              confidence: 0.6,
            ),
      clearGoal: goal != null && goal.isEmpty,
      dailyMinutes: (dailyMinutes == null || dailyMinutes <= 0)
          ? null
          : ProfileField<int>(
              value: dailyMinutes,
              source: ProfileSource.self,
              confidence: 0.7,
            ),
      clearDailyMinutes: dailyMinutes != null && dailyMinutes <= 0,
      maxNewWords: (maxNewWords == null || maxNewWords < 0)
          ? null
          : ProfileField<int>(
              value: maxNewWords,
              source: ProfileSource.self,
              confidence: 0.7,
            ),
      // 0 是合法值(今天不学新词),不算"清空" ✗ —— 只有负数才当未设置
      clearMaxNewWords: maxNewWords != null && maxNewWords < 0,
      interests: (interests == null || interests.isEmpty)
          ? null
          : ProfileField<List<String>>(
              value: interests,
              source: ProfileSource.self,
              confidence: 0.6,
            ),
      clearInterests: interests != null && interests.isEmpty,
      blockedTopics: blockedTopics,
      blockedKeywords: blockedKeywords,
    );
    await save(model);
    return model;
  }
}
