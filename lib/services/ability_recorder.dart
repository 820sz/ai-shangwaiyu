import 'package:flutter/foundation.dart';

import 'database.dart';
import 'output_rubric.dart';

/// 能力快照记录器(v3 · 批 8 · E1-5)。
///
/// 为什么要有这一层(以前只有"打开助理"时 `TutorSnapshotService` 才写
/// `ability_snapshots`):
/// 1. 能力项时间序列的价值在于"**事件发生那一刻**就有记录" —— 词汇量测试、
///    写译批改、输出练习批改都是产生能力证据的时刻;只等用户打开助理才记,
///    不点助理就永远没有趋势(审计报告 E1-5 的缺口);
/// 2. 三个界面各自去拼 `insertAbilitySnapshot` 的参数,口径必然漂移
///    (value 的单位、confidence、evidence 结构各写一套) —— 收敛到一处;
/// 3. **失败必须静默**:能力快照是"加分项",用户点提交后最该看到的是批改
///    结果,不能因为一条统计写失败弹错误/卡住流程。
class AbilityRecorder {
  AbilityRecorder._();

  /// 测试注入点:验证"写库失败不抛、不影响用户操作"这条契约。
  ///
  /// 生产代码不传它;没有这个缝就只能靠"关掉数据库"来模拟失败,
  /// 那种测法会把别的用例一起弄脏。
  @visibleForTesting
  static Future<int> Function(Map<String, Object?> snapshot)? debugInsertOverride;

  /// 能力维度(与 DB 常量同一事实源,避免两处漂移)
  static const List<String> dimensions = DatabaseService.abilityDimensions;

  /// 能力来源(与 DB 常量同一事实源)
  static const List<String> sources = DatabaseService.abilitySources;

  /// 记录一条能力快照。
  ///
  /// [sameDayUpsert] = true 时把 `snapshot_at` 归一为**当天 0 点**,同一天内
  /// 多次写入会被 DB 层按 (dimension, snapshot_at) upsert 成一行 —— 适合
  /// "输出练习"这种一天可能批改很多次的来源(否则趋势图一天十几个锯齿点);
  /// false 时按真实时刻逐条保留 —— 适合"词汇量测试"这种一次性测量。
  static Future<int> record({
    required String dimension,
    required num value,
    String unit = '',
    String source = 'inferred',
    double? confidence,
    Map<String, Object?>? evidence,
    DateTime? at,
    bool sameDayUpsert = false,
  }) async {
    try {
      final dim = dimension.trim();
      // 维度/来源都按 DB 白名单校验:脏参数静默忽略,不写不可聚合的行
      if (!dimensions.contains(dim)) {
        debugPrint('AbilityRecorder 忽略非法能力维度: $dimension');
        return -1;
      }
      if (!value.isFinite) return -1;
      final src = sources.contains(source.trim()) ? source.trim() : 'inferred';
      final when = at ?? DateTime.now();
      final snapshot = <String, Object?>{
        'dimension': dim,
        'value': value,
        'unit': unit.trim().isEmpty ? null : unit.trim(),
        'source': src,
        'confidence': confidence?.clamp(0.0, 1.0).toDouble(),
        'snapshot_at': sameDayUpsert
            ? _dayStart(when).toIso8601String()
            : when.toIso8601String(),
        'evidence_json': ?evidence,
      };
      final insert =
          debugInsertOverride ?? DatabaseService.insertAbilitySnapshot;
      final id = await insert(snapshot);
      if (id < 0) {
        // DB 层已 debugPrint 过原因,这里不再重复刷屏
        debugPrint('AbilityRecorder 写入被 DB 层拒绝(已静默): $dim');
      }
      return id;
    } catch (e) {
      // 能力快照失败绝不能阻断用户正在做的事(批改/保存/出结果)
      debugPrint('AbilityRecorder 记录失败(已忽略): $e');
      return -1;
    }
  }

  /// 词汇量测试完成 → `vocab`(test 来源,带区间证据)。
  ///
  /// value 用**估计值**而不是区间端点:趋势看的是中心估计;区间放进 evidence,
  /// 这样"这个数有多不确定"不会在时间序列里丢失。
  static Future<int> recordPlacement({
    required int estimate,
    required int low,
    required int high,
    String cefr = '',
    double? falseAlarmRate,
    bool full = false,
    DateTime? at,
  }) async {
    // 不可信作答(估计 0/伪词误报过半)调用方本就不会保存基线,
    // 这里再挡一道:0 值会把趋势画成"能力归零"
    if (estimate <= 0) return -1;
    // 置信度口径与 LearnerModelStore.savePlacement 保持一致:
    // 伪词误报 0% → 0.9,≥40% → 0.5(自评明显不可信)
    final alarm = (falseAlarmRate ?? 0).clamp(0.0, 0.4);
    return record(
      dimension: 'vocab',
      value: estimate,
      unit: 'words',
      source: 'test',
      confidence: (0.9 - alarm).clamp(0.5, 0.9).toDouble(),
      evidence: <String, Object?>{
        'low': low,
        'high': high,
        if (cefr.trim().isNotEmpty) 'cefr': cefr.trim(),
        'false_alarm_rate': ?falseAlarmRate,
        'mode': full ? 'full' : 'fast',
        'note': '词汇量测试估计值(区间 $low~$high)',
      },
      at: at,
    );
  }

  /// 写译批改完成 / 输出练习批改完成 → `output`(inferred 来源)。
  ///
  /// value 统一成 **0..100 百分比**:不同 rubric 满分不同(四六级写作/翻译
  /// 15 分、自定义 rubric 可能 100 分),只有百分比才能跨题型比较、画趋势。
  /// 原始分与折算档位进 evidence —— 趋势以外还要能回答"这次折到哪一档"。
  static Future<int> recordOutputScore({
    required double score,
    required double maxScore,
    String? rubricId,
    String? bandLabel,
    String? taskType,
    String? note,
    DateTime? at,
    bool sameDayUpsert = true,
  }) async {
    if (!score.isFinite || score < 0) return -1;
    final max = maxScore.isFinite && maxScore > 0 ? maxScore : 100.0;
    final percent = (score / max * 100).clamp(0.0, 100.0).toDouble();
    return record(
      dimension: 'output',
      value: percent,
      unit: 'score',
      source: 'inferred',
      // 推断值:单次批改的模型分,置信度给中等(不冒充"测出来的")
      confidence: 0.65,
      evidence: <String, Object?>{
        'raw_score': score,
        'max_score': max,
        'percent': percent,
        if (rubricId != null && rubricId.trim().isNotEmpty)
          'rubric_id': rubricId.trim(),
        if (bandLabel != null && bandLabel.trim().isNotEmpty)
          'band': bandLabel.trim(),
        if (taskType != null && taskType.trim().isNotEmpty)
          'task_type': taskType.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      at: at,
      sameDayUpsert: sameDayUpsert,
    );
  }

  /// 从一次 rubric 评分([ScoredOutput] + [OutputRubric])直接记 output 维度。
  ///
  /// 输出练习与写译批改都走它 —— 两条链路各写一份换算逻辑迟早会分叉。
  static Future<int> recordScoredOutput({
    required ScoredOutput scored,
    required OutputRubric rubric,
    String? taskType,
    DateTime? at,
    bool sameDayUpsert = true,
  }) {
    final max = rubric.totalScore;
    return recordOutputScore(
      score: scored.totalScore,
      maxScore: max <= 0 ? 100 : max,
      rubricId: rubric.id,
      bandLabel: scored.bandLabel,
      taskType: taskType,
      note: 'rubric 总分',
      at: at,
      sameDayUpsert: sameDayUpsert,
    );
  }

  static DateTime _dayStart(DateTime t) => DateTime(t.year, t.month, t.day);
}
