import '../models/learner_model.dart';
import '../models/vocabulary.dart';
import 'word_frequency.dart';

/// 学习者上下文(v2.0 粘合层)。
///
/// 作用:把「学习者模型 + 生词本」翻译成难度分析真正需要的入参。
/// 没有这一层,难度引擎只能拿一个空集合去算覆盖率 —— 那等于没算。
///
/// 三个关键判断(都要能向用户解释,不能是黑箱):
/// 1. **已知词怎么定**:名次 ≤ 词汇量估计的词 ⇒ 推定认识;
///    再加上生词本里「已掌握/学习中」的词(用户明确标记过的)。
/// 2. **没测过怎么办**:保守假定认识最高频的 [floorWhenUnmeasured] 个功能词
///    (the/of/and…),并明确返回"低置信度"标记,让 UI 显示"尚未测试"。
/// 3. **阅读速度**:优先用实测值(存在模型 extras 里),否则给通用默认值。
class LearnerContext {
  LearnerContext._();

  /// 未测词汇量时的保底:最高频的功能词几乎不可能不认识
  /// (若连这些都不认识,用户也读不到这一步)
  static const int floorWhenUnmeasured = 800;

  /// 通用阅读速度默认值(wpm)。实测值优先。
  static const int defaultWpm = 200;

  /// 有效词汇量:测量值 > 推断值 > 保底值
  static int effectiveVocab(LearnerModel model) {
    final v = model.vocabEstimate?.value ?? 0;
    if (v > 0) return v;
    final inferred = model.extras['vocab_inferred'];
    if (inferred is int && inferred > 0) return inferred;
    return floorWhenUnmeasured;
  }

  /// 是否已有"测量出来"的基线(自报不算 —— 这正是 v1.9 之前最大的问题)
  static bool hasMeasuredBaseline(LearnerModel model) =>
      (model.vocabEstimate?.value ?? 0) > 0 &&
      model.vocabEstimate!.source == ProfileSource.test;

  /// 一句话说明基线来源,直接给 UI 用(把"依据"摆在用户面前)
  static String describeBaseline(LearnerModel model) {
    final f = model.vocabEstimate;
    if (f != null && f.value > 0) {
      final range = (model.vocabLow != null && model.vocabHigh != null)
          ? '(${model.vocabLow}-${model.vocabHigh})'
          : '';
      final src = f.source == ProfileSource.test
          ? '词汇量测试'
          : (f.source == ProfileSource.self ? '你的自评' : '系统推断');
      final conf = f.confidence >= 0.8
          ? '较可信'
          : (f.confidence >= 0.6 ? '参考' : '仅供参考');
      return '按 $src:${f.value} 词$range($conf)';
    }
    return '尚未测词汇量,暂按最高频的 $floorWhenUnmeasured 词保守估计 —— '
        '建议先做一次词汇量测试(5 分钟)';
  }

  /// 已知词集合(供 [TextDifficultyAnalyzer.analyze] 的 `knownWords` 参数)
  ///
  /// [normalize] 传入难度引擎的词形归一函数(把 jumps→jump),让生词本里的
  /// 变形词也能对上;不传则用原始小写形式(保守,只会低估覆盖率)。
  static Set<String> knownWords({
    required LearnerModel model,
    List<Vocabulary> vocab = const [],
    String Function(String word)? normalize,
    int? vocabOverride,
  }) {
    final estimate = vocabOverride ?? effectiveVocab(model);
    final known = <String>{};
    // 关键:这里必须用**不过滤**的 rankedUpTo,而不是出题用的 bandWords。
    // bandWords 会滤掉 of/to/in 这类短词,而它们占英文文本近一半词次 ——
    // 拿它当"已知词"会把 the/of 都算成生词,覆盖率严重低估
    // (这条 bug 是被 learner_context_test 里的 10 词小表抓出来的)。
    for (final w in WordFrequency.rankedUpTo(estimate)) {
      known.add(w);
    }
    for (final v in vocab) {
      // 只把"用户认可自己会"的词算已知:已掌握(2) 与 学习中(1);
      // 新词(0) 不算 —— 那正是他要学的
      if (v.masteryLevel >= 1) {
        final w = (v.word).toLowerCase().trim();
        if (w.isEmpty) continue;
        known.add(normalize != null ? normalize(w) : w);
      }
    }
    return known;
  }

  /// 阅读速度(wpm):实测优先,否则通用默认
  static int wpmFor(LearnerModel model) {
    final v = model.extras['reading_wpm'];
    if (v is int && v >= 60 && v <= 1000) return v;
    if (v is num && v >= 60 && v <= 1000) return v.toInt();
    return defaultWpm;
  }

  /// 材料难度提示语(给"这份材料对你难不难"用),与 PLAN-2.0 §3.2 的
  /// i+1 阈值一致 —— 阈值写在一处,UI 与推荐引擎不要各写一份
  static String difficultyHint(double knownTokenRatio) {
    if (knownTokenRatio >= tooEasyTokenRatio) return '轻松泛读(几乎无生词)';
    if (knownTokenRatio >= comfortableMin) return '舒适精读(每 100 词 2-5 个生词)';
    if (knownTokenRatio >= tooHardTokenRatio) return '挑战精读(需要先预热生词)';
    return '偏难(生词过密,建议换更简单的材料)';
  }

  /// i+1 阈值(单一事实源:材料库、推荐、导师诊断、阅读器都读这几个常量)
  ///
  /// 依据:Nation(2006)与 Laufer & Ravenhorst-Kalovski(2010)的**词次覆盖率**
  /// 经验值(98% 可泛读、95% 可精读);这里算的是同一口径(词次,不是词形),
  /// 所以直接用文献阈值,不再额外下调。
  static const double tooEasyTokenRatio = 0.99;
  static const double comfortableMin = 0.95;
  static const double comfortableMax = 0.98;
  static const double tooHardTokenRatio = 0.90;

  /// 是否落在"舒适精读"区间(推荐材料时的默认目标)
  static bool isComfortable(double knownTokenRatio) =>
      knownTokenRatio >= comfortableMin && knownTokenRatio < comfortableMax;
}
