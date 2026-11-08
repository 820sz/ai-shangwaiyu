import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import '../models/learner_model.dart';
import 'database.dart';
import 'learner_model_store.dart';
import 'material_prefs.dart';

/// 输入偏好统一模型层(v2.14 · 批 2 · C1-18 / C1-2 前置)。
///
/// ## 为什么要有这个文件
/// 改版前的「输入偏好」散在三处,而且**三处口径不同**:
/// 1. `MaterialPrefs`(Hive `material_prefs`):难度档 + 来源类型 + 内容类型 +
///    题材自由文本 + 补充需求 —— 只服务"材料中心找资源";
/// 2. `LearnerModel`(Hive `learner_model_v2`):目标(单值 `goal` / 多选 `goals`)、
///    兴趣、题材黑名单、关键词黑名单、每日可投入时间 —— 服务导师与练习;
/// 3. 输入首页 / 材料中心 / 推荐逻辑各自在界面里现拼"目标 + 难度 + 黑名单"。
///
/// 结果是:同一件事在三个界面说法不一样(材料中心说"i+10"、导师只认得
/// "四六级(半年内)"这串复合文本、黑名单在推荐页生效但在公开源检索结果里
/// 没生效)。这一层把**读**收口成不可变值对象 [InputPreferences],把**判断**
/// 收口成纯函数([coverageInBand] / [suggestBand]),于是 UI 只做渲染,
/// 也能被单测钉住。批 4 的"写回"只先实现难度档([InputPreferences.saveBand]),
/// 其余字段继续由原有页面各写各的,不扩大改动面。
///
/// ## 与既有 `MaterialBand` 的关系
/// - **字符串完全沿用真实 Hive 取值**(`MaterialBand.name`:`i1`/`i10`/`i100`/`any`),
///   这样批 4 写回时老代码也读得懂,不产生"第二套存储";
/// - **覆盖率区间也直接复用 `MaterialBand`**(本文件不另立数字):区间是
///   材料推荐、难度标签、AI 检索提示共用的口径,项目里已有唯一事实源
///   `MaterialBand`(v2.7 起,材料中心 chip 与 `material_library` 的过滤/排序都读它)。
///   两处各写一套数字的结果一定是"材料中心说 i+1、推荐说 i+10"。

/// 难度档(用户语义:**i+1 舒适 / i+10 挑战 / i+100 快速正反馈**)
///
/// 区间与 [MaterialBand] 完全一致(v2.7 起在用,别再分叉):
/// - **i+1 舒适**:覆盖率 ≥0.98(每 100 词 ≤2 个生词,几乎全认识);
/// - **i+10 挑战**:覆盖率 0.90~0.98(每 100 词 2~10 个生词,够一够);
/// - **i+100 快反馈**:覆盖率 <0.90(每 100 词 >10 个生词,费劲但爽);
/// - **不限**:不做难度约束。
///
/// 边界归属:**0.98 归 i+1、0.90 归 i+10**(左闭右开,三档不重不漏)。
/// 本层只负责"用户语义 + 文案",`coverageMin/Max`、`coverageText`、`hintForAi`
/// 全部取自 [MaterialBand] —— 想改难度定义只改那一处。
enum DifficultyBand {
  /// i+1:几乎都认识,轻松读 —— 保持语感/泛读量最省力
  comfortable(
    'i+1 舒适',
    '几乎都认识,读起来轻松;适合保持语感、把泛读量做起来',
  ),

  /// i+10:每 100 词几个生词,够一够能读懂 —— 精读涨词最快的一档
  challenge(
    'i+10 挑战',
    '每 100 词有几个生词,够一够能读懂;精读涨词最快的一档',
  ),

  /// i+100:生词多、读着费劲但爽 —— 用户本人偏爱这档,文案不能写贬义
  fastGain(
    'i+100 快反馈',
    '生词多、读着费劲但爽;适合短期冲量,靠密集生词快速涨词',
  ),

  /// 不限:不做难度约束
  any('不限', '不做难度约束,按检索结果直接看');

  const DifficultyBand(this.label, this.description);

  /// 界面档位名(i+1 舒适 / i+10 挑战 / i+100 快反馈 / 不限)
  final String label;

  /// 一句用户能看懂的话(chip 的提示、降/升档建议的说明都用它)
  final String description;

  bool get isAny => this == DifficultyBand.any;

  /// 写回 Hive 用的真实字符串 —— **必须**与 `MaterialBand.name` 一致:
  /// 老代码(材料中心的 chip / AI 提示)读同一个 key,不能出现第二套编码。
  String get rawValue => materialBand.name;

  /// 与本档对应的既有枚举(写回 [InputPreferences.saveBand] 要用)
  MaterialBand get materialBand => switch (this) {
        DifficultyBand.comfortable => MaterialBand.i1,
        DifficultyBand.challenge => MaterialBand.i10,
        DifficultyBand.fastGain => MaterialBand.i100,
        DifficultyBand.any => MaterialBand.any,
      };

  /// 覆盖率下/上界:**直接取 [MaterialBand]**,不在这里重复定义数字。
  double get coverageMin => materialBand.min;

  double get coverageMax => materialBand.max;

  /// 覆盖率的一句话(界面说明 / AI 提示共用,取 MaterialBand 的文案)
  String get coverageText => materialBand.description;

  /// 给 AI 检索规划的难度说明(取 MaterialBand 的提示词,避免两套口径)
  String get hintForAi => materialBand.hintForAi;

  /// 从 Hive 字符串还原。**脏值/空串一律回退 [comfortable]**(用户默认最安全:
  /// 宁可给简单材料,也不要把高估的难度硬塞给初学者)。
  ///
  /// 同时兼容本层枚举名(`comfortable`/`challenge`/`fastGain`)与大小写差异,
  /// 便于批 4 的写回/测试直传。
  static DifficultyBand bandOf(String raw) {
    final s = raw.trim().toLowerCase();
    for (final b in DifficultyBand.values) {
      if (b.rawValue == s || b.name.toLowerCase() == s) return b;
    }
    return DifficultyBand.comfortable;
  }

  /// 覆盖率 → 档位(用于"这份材料对我是哪档"的标注)。
  /// `any` 不在返回值里(它是"不约束",不是材料属性)。
  static DifficultyBand? ofCoverage(double coverage) {
    if (coverage.isNaN) return null;
    return switch (MaterialBand.of(coverage.clamp(0.0, 1.0))) {
      MaterialBand.i1 => DifficultyBand.comfortable,
      MaterialBand.i10 => DifficultyBand.challenge,
      MaterialBand.i100 => DifficultyBand.fastGain,
      MaterialBand.any => null,
    };
  }
}

/// 覆盖率是否落在某档(纯函数;`any` 恒真)
///
/// 为什么单独抽出来而不是写在 enum 里:UI 会拿它做"批量过滤公开源结果",
/// 纯函数能被单测;NaN/越界值也在这里收口(越界先夹到 [0,1],NaN 直接 false),
/// 保证过滤循环里不会因为一条脏数据抛异常。
///
/// 区间判定委托给 [MaterialBand.contains] —— 与材料中心的难度过滤**同一口径**,
/// 不允许这里再判一次边界(否则同一个覆盖率在两处会被标成不同档)。
bool coverageInBand(double coverage, DifficultyBand band) {
  if (coverage.isNaN) return false;
  final c = coverage.clamp(0.0, 1.0);
  if (band.isAny) return true;
  return band.materialBand.contains(c);
}

/// 一条难度建议(不猜:数据不足时 [suggestBand] 返回 null,不返回本对象)
class BandSuggestion {
  /// 建议切换到的档位
  final DifficultyBand band;

  /// 一句话原因(必须带真实数字 —— 与项目"无证据不下结论"同一纪律)
  final String text;

  const BandSuggestion({required this.band, required this.text});

  @override
  String toString() => 'BandSuggestion(${band.rawValue}: $text)';
}

/// 建议算法的阈值(**单一事实源**:UI 要解释"为什么建议降档"时直接引用)
class InputPrefsThresholds {
  InputPrefsThresholds._();

  /// 读完率低于它 = 读不下去(降档信号)
  static const double finishedRatioLow = 0.4;

  /// 读完率不低于它 = 轻松读完(升档信号)
  static const double finishedRatioHigh = 0.8;

  /// 每 100 词查词次数高于它 = 查得太频繁(降档信号)
  static const double lookupPer100High = 12;

  /// 每 100 词查词次数低于它 = 几乎不查词(升档信号)
  static const double lookupPer100Low = 3;

  /// 读后测验正确率低于它 = 没读懂(降档信号)
  static const double quizAccuracyLow = 0.5;

  /// 读后测验正确率不低于它 = 读得很顺(升档信号)
  static const double quizAccuracyHigh = 0.85;

  /// 至少要有几个真实指标才给建议(1 个指标就下结论 = 猜)
  static const int minMetrics = 2;
}

/// 按真实行为给"升/降档"建议(**不猜**:数据不足、信号冲突、已在端点都返回 null)。
///
/// 规则(每个阈值都能向用户解释,见 [InputPrefsThresholds]):
/// - 降档信号:读完率 <40% / 查词 >12 次每百词 / 测验正确率 <50%;
/// - 升档信号:读完率 ≥80% / 查词 <3 次每百词 / 测验正确率 ≥85%;
/// - 至少 [InputPrefsThresholds.minMetrics] 个指标有值;
/// - 同一方向至少 2 个信号且多于反方向,才给建议(1 个信号不足以推翻档位);
/// - `current == any` 无"当前档"可比,直接 null;已在最简单/最难档也 null。
BandSuggestion? suggestBand({
  required double? finishedRatio,
  required double? avgLookupPer100,
  required double? quizAccuracy,
  required DifficultyBand current,
}) {
  if (current.isAny) return null;

  final evidence = <String>[];
  var available = 0;
  var downSignals = 0;
  var upSignals = 0;

  if (finishedRatio != null && finishedRatio.isFinite) {
    available++;
    if (finishedRatio < InputPrefsThresholds.finishedRatioLow) {
      downSignals++;
      evidence.add('读完率 ${_pct(finishedRatio)}');
    } else if (finishedRatio >= InputPrefsThresholds.finishedRatioHigh) {
      upSignals++;
      evidence.add('读完率 ${_pct(finishedRatio)}');
    }
  }
  if (avgLookupPer100 != null && avgLookupPer100.isFinite) {
    available++;
    if (avgLookupPer100 > InputPrefsThresholds.lookupPer100High) {
      downSignals++;
      evidence.add('查词 ${_lookups(avgLookupPer100)} 次/100 词');
    } else if (avgLookupPer100 < InputPrefsThresholds.lookupPer100Low) {
      upSignals++;
      evidence.add('查词 ${_lookups(avgLookupPer100)} 次/100 词');
    }
  }
  if (quizAccuracy != null && quizAccuracy.isFinite) {
    available++;
    if (quizAccuracy < InputPrefsThresholds.quizAccuracyLow) {
      downSignals++;
      evidence.add('测验正确率 ${_pct(quizAccuracy)}');
    } else if (quizAccuracy >= InputPrefsThresholds.quizAccuracyHigh) {
      upSignals++;
      evidence.add('测验正确率 ${_pct(quizAccuracy)}');
    }
  }

  // 数据不足 = 不猜(只有一个指标也可能是偶然)
  if (available < InputPrefsThresholds.minMetrics) return null;

  final index = DifficultyBand.values.indexOf(current);

  if (downSignals >= 2 && downSignals > upSignals && index > 0) {
    final target = DifficultyBand.values[index - 1];
    return BandSuggestion(
      band: target,
      text: '${evidence.join('、')} —— 现在这档偏难,'
          '建议降到「${target.label}」,先读顺再往上加',
    );
  }
  // values 末尾是 any(不是"更难"的档),所以升档上限是 fastGain(index 2)
  if (upSignals >= 2 && upSignals > downSignals && index < 2) {
    final target = DifficultyBand.values[index + 1];
    return BandSuggestion(
      band: target,
      text: '${evidence.join('、')} —— 现在这档偏轻松,'
          '建议升到「${target.label}」,给自己加一点难度',
    );
  }
  // 信号冲突 / 都在中性区 / 已在端点:不硬给结论
  return null;
}

String _pct(double ratio) => '${(ratio * 100).round()}%';

String _lookups(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);

// ─────────────────────────────────────────────────────────────────────────
// 展示用(v3 批 7 · P1-2):把 suggestBand 的结论接到界面 —— 读真实信号、
// 给一条"可一键应用"的建议。算法/阈值仍然只在上面,不在这里分叉。
// ─────────────────────────────────────────────────────────────────────────

/// 三个行为信号(**读不到就是 null,suggestBand 自己会按"至少 2 个"防猜**)
class BandSignals {
  /// 读完率(0..1):最近读过的材料里,读完的比例
  final double? finishedRatio;

  /// 查词密度:每 100 词查几次词(越高越费劲)
  final double? avgLookupPer100;

  /// 读后测验正确率(0..1)
  final double? quizAccuracy;

  const BandSignals({
    this.finishedRatio,
    this.avgLookupPer100,
    this.quizAccuracy,
  });

  @override
  String toString() => 'BandSignals(finished: $finishedRatio, '
      'lookups/100: $avgLookupPer100, quiz: $quizAccuracy)';
}

/// 难度档辅助调整的**展示用**结果。
///
/// 为什么要有这层:UI 需要判断"显不显示/显示什么文案",而这件事有两条固定规则
/// (有建议 + 建议档≠当前档才显示;文案必须带上依据窗口),两屏各写一遍迟早
/// 一边显示"建议降到 i+1"、另一边不显示。这里把判断收口,UI 只渲染。
class BandAdvice {
  /// 当前难度档(建议相对它计算;用于"建议≠当前档"判断)
  final DifficultyBand current;

  /// 建议(null = 数据不足 / 信号冲突 / 当前是不限 → **不显示,不占位**)
  final BandSuggestion? suggestion;

  /// 依据的时间窗口(天)。写进文案"按最近 N 天表现",不写死 30。
  final int days;

  const BandAdvice({required this.current, this.suggestion, this.days = 30});

  /// 是否值得出现在界面上:有建议,且建议档确实不同于当前档。
  /// (算法保证不同,但 UI 不依赖隐含保证 —— 同档建议等于白占一行。)
  bool get shouldShow => suggestion != null && suggestion!.band != current;

  /// 建议正文;不显示时 null(UI 可以直接 `if (advice.line != null)`)。
  String? get line =>
      shouldShow ? '按最近 $days 天表现：${suggestion!.text}' : null;

  /// 一键应用按钮文案;不显示时 null。
  String? get actionLabel => shouldShow ? '调到 ${suggestion!.band.label}' : null;

  @override
  String toString() => 'BandAdvice(current: ${current.rawValue}, '
      'show: $shouldShow, suggestion: $suggestion)';
}

/// 从真实使用数据算三个行为信号(只读;任一来源失败只丢那一项,不抛)。
///
/// 口径(与 [InputPrefsThresholds] 一一对应,UI 不得另算):
/// - [BandSignals.finishedRatio] = 最近 [materialLimit] 份**动过**的材料里读完的比例
///   (`material_progress.finished_at` 是事实源;入库但从没打开的材料不算分母 ——
///   否则"收藏了一堆没读"会被误读成"读不下去");
/// - [BandSignals.avgLookupPer100] = 累计查词 ÷ **估算已读词数** × 100。
///   已读词数按 `percent × word_count` 估算(percent 是阅读位置百分比);
///   样本 <200 词直接不给值 —— 读 3 个词查 1 次词会算出 33 次/100 词,那是噪声;
/// - [BandSignals.quizAccuracy] = 读后测验正确率;没有该 kind 时用非「词汇量测试」
///   类测验的平均(词汇量测试是水平测量,不代表材料难不难读)。
Future<BandSignals> loadBandSignals({
  int days = 30,
  int materialLimit = 20,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final cutoff = at.subtract(Duration(days: days <= 0 ? 30 : days));

  double? finishedRatio;
  double? avgLookupPer100;
  double? quizAccuracy;

  try {
    final rows = await DatabaseService.getRecentMaterials(limit: materialLimit);
    var started = 0;
    var finished = 0;
    var wordsRead = 0.0;
    var lookups = 0.0;
    for (final row in rows) {
      final percent = (row['percent'] as num?)?.toDouble() ?? 0;
      final finishedAt = DateTime.tryParse('${row['finished_at'] ?? ''}');
      final updatedAt = DateTime.tryParse('${row['updated_at'] ?? ''}');
      if (updatedAt == null || updatedAt.isBefore(cutoff)) continue;
      if (percent <= 0 && finishedAt == null) continue;
      started++;
      if (finishedAt != null) finished++;
      final id = (row['material_id'] as num?)?.toInt() ??
          (row['id'] as num?)?.toInt();
      final wordCount = (row['word_count'] as num?)?.toInt() ?? 0;
      if (id == null || wordCount <= 0) continue;
      // 查词累计在 material_progress.lookups(阅读器每查一个词 +=1),
      // getRecentMaterials 不返回这一列,所以按材料补一次读(最多 materialLimit 次)。
      final progress = await DatabaseService.getMaterialProgress(id);
      final materialLookups = (progress?['lookups'] as num?)?.toInt() ?? 0;
      if (materialLookups <= 0) continue;
      final effectivePercent =
          finishedAt != null ? 100.0 : percent.clamp(0.0, 100.0);
      wordsRead += wordCount * effectivePercent / 100;
      lookups += materialLookups;
    }
    if (started > 0) finishedRatio = finished / started;
    if (wordsRead >= 200) avgLookupPer100 = lookups / wordsRead * 100;
  } catch (e) {
    debugPrint('ReadFlow 计算读完率/查词密度失败(已降级): $e');
  }

  try {
    final accuracy =
        await DatabaseService.getQuizAccuracy(days: days <= 0 ? 30 : days);
    final reading = accuracy['reading_comprehension'];
    if (reading != null) {
      quizAccuracy = reading;
    } else {
      final values = [
        for (final entry in accuracy.entries)
          if (entry.key != 'vocab_placement') entry.value,
      ];
      if (values.isNotEmpty) {
        quizAccuracy = values.reduce((a, b) => a + b) / values.length;
      }
    }
  } catch (e) {
    debugPrint('ReadFlow 计算读后测验正确率失败(已降级): $e');
  }

  return BandSignals(
    finishedRatio: finishedRatio,
    avgLookupPer100: avgLookupPer100,
    quizAccuracy: quizAccuracy,
  );
}

/// 读当前难度档 + 真实信号,得到一条"要不要调档"的展示建议。
///
/// 为什么收在 service 而不是各屏自己拼:输入首页与材料中心必须给出**同一条**
/// 建议(用户会在两屏之间来回切),两处各读一遍数据必然出现"首页说可以升,
/// 材料中心没建议"。这里只读、**不写偏好** —— 应用动作由 UI 显式调用
/// [applyBandSuggestion],用户不点就什么都不改。
Future<BandAdvice> loadBandAdvice({
  int days = 30,
  int materialLimit = 20,
  DateTime? now,
}) async {
  final prefs = InputPreferences.load();
  // 「不限」没有"当前档"可比,suggestBand 也按同语义返回 null;
  // 提前返回还能省掉一轮 DB 查询(没选档的用户占大多数)。
  if (prefs.band.isAny) return BandAdvice(current: prefs.band, days: days);
  final signals = await loadBandSignals(
    days: days,
    materialLimit: materialLimit,
    now: now,
  );
  return BandAdvice(
    current: prefs.band,
    days: days,
    suggestion: suggestBand(
      finishedRatio: signals.finishedRatio,
      avgLookupPer100: signals.avgLookupPer100,
      quizAccuracy: signals.quizAccuracy,
      current: prefs.band,
    ),
  );
}

/// 一键应用一条难度建议(两个入口共用;写的就是 [MaterialPrefs.band] ——
/// [InputPreferences.load] 与输出/材料推荐读的是同一个 Hive key,不需要第二套写回)。
///
/// 返回是否写入成功;失败静默(false) —— UI 提示"保存失败"即可,不能因此崩。
Future<bool> applyBandSuggestion(BandSuggestion suggestion) async {
  try {
    final prefs = MaterialPrefs.load();
    await prefs.copyWith(band: suggestion.band.materialBand).save();
    return true;
  } catch (e) {
    debugPrint('ReadFlow 应用难度建议失败(已忽略): $e');
    return false;
  }
}

/// 输入偏好的**不可变值对象**(UI 只读,写走 [saveBand] 或原页面)
///
/// 字段来源:
/// - [examGoals] ← `LearnerModel.goals`(多选);空时回退解析 `goal` 单值
///   (访谈把它存成 `四六级(半年内)` 这种"目标+期限"复合串);
/// - [interests] ← `LearnerModel.interests` ∪ `MaterialPrefs.genres`(自由文本按顿号等拆分);
/// - [band] / [kinds] / [contentTypes] / [extraNeed] ← `MaterialPrefs`;
/// - [blockedTopics] / [blockedKeywords] ← `LearnerModel`;
/// - [dailyMinutes] ← `LearnerModel.dailyMinutes`(没填 = null)。
class InputPreferences {
  /// 目标需求(多选;已去掉空串与重复,保持原顺序)
  final List<String> examGoals;

  /// 兴趣/题材倾向(合并 LearnerModel.interests 与 MaterialPrefs.genres 并去重)
  final List<String> interests;

  /// 难度档(默认"不限",与 MaterialPrefs 默认一致)
  final DifficultyBand band;

  /// 来源类型偏好(MaterialPrefs.kinds 的 id:book/paper/news/podcast/wiki)
  final Set<String> kinds;

  /// 内容类型偏好(MaterialPrefs.contentTypes 的 id,如 science/literature)
  final Set<String> contentTypes;

  /// 补充/调整需求(自由文本,原样传给 AI)
  final String extraNeed;

  /// 题材黑名单(命中即过滤)
  final List<String> blockedTopics;

  /// 关键词黑名单(包含匹配,忽略大小写;命中标题/来源/题材即过滤)
  final List<String> blockedKeywords;

  /// 每天可投入分钟数(没填 = null,不硬编默认值)
  final int? dailyMinutes;

  InputPreferences({
    List<String> examGoals = const [],
    List<String> interests = const [],
    this.band = DifficultyBand.any,
    Set<String> kinds = const {},
    Set<String> contentTypes = const {},
    String extraNeed = '',
    List<String> blockedTopics = const [],
    List<String> blockedKeywords = const [],
    this.dailyMinutes,
  })  : examGoals = List.unmodifiable(_dedupe(examGoals)),
        interests = List.unmodifiable(_dedupe(interests)),
        kinds = Set.unmodifiable(kinds),
        contentTypes = Set.unmodifiable(contentTypes),
        extraNeed = extraNeed.trim(),
        blockedTopics = List.unmodifiable(_dedupe(blockedTopics)),
        blockedKeywords = List.unmodifiable(_dedupe(blockedKeywords));

  /// 从既有两个存储直读(UI 最常用)。
  ///
  /// 为什么所有读取都要包异常:Hive 未打开(测试/首启异常)、老版本坏 JSON、
  /// 字段类型不对 —— 任何一条都可能发生,而偏好读取失败**不应该影响打开页面**。
  /// 读不到就退回"无偏好"(band=any、无目标、无黑名单),页面照常可手动设置。
  static InputPreferences load() {
    LearnerModel model = LearnerModel();
    try {
      model = LearnerModelStore.load();
    } catch (e) {
      debugPrint('ReadFlow 读取学习者模型失败(输入偏好用空模型): $e');
    }
    MaterialPrefs prefs = MaterialPrefs.empty;
    try {
      prefs = MaterialPrefs.load();
    } catch (e) {
      debugPrint('ReadFlow 读取材料偏好失败(输入偏好当空处理): $e');
    }
    return InputPreferences.fromSources(model: model, prefs: prefs);
  }

  /// 直接传两个来源构造(单测/需要注入的场景;不碰 Hive)
  factory InputPreferences.fromSources({
    LearnerModel? model,
    MaterialPrefs? prefs,
  }) {
    final m = model ?? LearnerModel();
    final p = prefs ?? MaterialPrefs.empty;
    return InputPreferences(
      examGoals: _examGoalsOf(m),
      interests: _interestsOf(m, p),
      band: DifficultyBand.bandOf(p.band.name),
      kinds: p.kinds,
      contentTypes: p.contentTypes,
      extraNeed: p.extra,
      blockedTopics: m.blockedTopics,
      blockedKeywords: m.blockedKeywords,
      dailyMinutes: m.dailyMinutes?.value,
    );
  }

  /// 是否什么都没设置(UI 可用它显示"还没设置偏好")
  bool get isEmpty =>
      examGoals.isEmpty &&
      interests.isEmpty &&
      band.isAny &&
      kinds.isEmpty &&
      contentTypes.isEmpty &&
      extraNeed.isEmpty &&
      blockedTopics.isEmpty &&
      blockedKeywords.isEmpty &&
      dailyMinutes == null;

  /// 给 AI 检索规划的一句话(C1-14 的 prompt 直接拼这句)。
  ///
  /// 结构固定为"目标;难度;兴趣;避开;补充;时间" —— 顺序按"筛选力度"排:
  /// 先缩小考试范围,再定难度,再看兴趣,最后才是软约束(补充/时间)。
  /// 什么都没设置时也要给一句**可执行**的兜底,而不是空串(空串会让 AI 自由发挥)。
  String get promptHint {
    final parts = <String>[];
    if (examGoals.isNotEmpty) parts.add('目标:${examGoals.join('、')}');
    if (!band.isAny) {
      parts.add('难度:${band.label}(${band.coverageText})');
    }
    if (interests.isNotEmpty) parts.add('兴趣题材:${interests.join('、')}');
    final blocked = <String>[...blockedTopics, ...blockedKeywords];
    if (blocked.isNotEmpty) parts.add('避开:${blocked.join('、')}');
    if (extraNeed.isNotEmpty) parts.add('补充要求:$extraNeed');
    if (dailyMinutes != null && dailyMinutes! > 0) {
      parts.add('每天可投入 $dailyMinutes 分钟');
    }
    if (parts.isEmpty) {
      return '暂无个性化偏好:难度不限、题材不限,按普遍适合中级学习者的材料检索。';
    }
    return '${parts.join(';')}。';
  }

  /// 黑名单过滤(供公开源检索结果用,C1-14)。
  ///
  /// 匹配口径与「学习偏好」页的说明保持一致:**包含匹配 + 忽略大小写/首尾空白**。
  /// 命中范围 = 标题 / 来源 / 题材三者之一(关键词可能出现在任何一处:
  /// 标题里是中文词、来源里是媒体名、题材是 AI 返回的标签)。
  /// 没有黑名单时恒 true —— 过滤函数本身不该成为额外负担。
  bool allowsMaterial({
    required String title,
    required String? source,
    required List<String> genres,
  }) {
    if (blockedKeywords.isEmpty && blockedTopics.isEmpty) return true;
    final titleText = title.toLowerCase();
    final sourceText = (source ?? '').toLowerCase();
    final genreText = genres.map((g) => g.toLowerCase()).join(' ');

    bool hits(String raw) {
      final term = raw.toLowerCase().trim();
      if (term.isEmpty) return false;
      return titleText.contains(term) ||
          genreText.contains(term) ||
          sourceText.contains(term);
    }

    for (final k in blockedKeywords) {
      if (hits(k)) return false;
    }
    for (final t in blockedTopics) {
      if (hits(t)) return false;
    }
    return true;
  }

  /// 只换难度档的轻量副本(UI 切档时用;其它字段保持不变)。
  ///
  /// 为什么不做全量 `copyWith`:本层目前只承诺"难度档"这一项写回(批 4 再扩),
  /// 全量 copyWith 会把"哪些字段由谁写回"的边界搞糊;等批 4 统一时再加。
  InputPreferences withBand(DifficultyBand next) => InputPreferences(
        examGoals: examGoals,
        interests: interests,
        band: next,
        kinds: kinds,
        contentTypes: contentTypes,
        extraNeed: extraNeed,
        blockedTopics: blockedTopics,
        blockedKeywords: blockedKeywords,
        dailyMinutes: dailyMinutes,
      );

  /// 写回难度档(**批 4 的写回入口;本轮只做这一项**)。
  ///
  /// 为什么走 `MaterialPrefs` 而不是另开 Hive key:难度档的老家就是
  /// `material_prefs.band`,批 4 之后老界面/老 AI 提示也要能读到同一个值;
  /// 另开 key 只会制造"新界面改了、老界面不认"的分裂。
  /// 读旧值 → copyWith(band) → 走它的 save()(失败只记日志,不给用户抛)。
  Future<void> saveBand(DifficultyBand band) async {
    try {
      final prefs = MaterialPrefs.load();
      await prefs.copyWith(band: band.materialBand).save();
    } catch (e) {
      debugPrint('ReadFlow 保存输入难度档失败(已忽略): $e');
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InputPreferences &&
        listEquals(examGoals, other.examGoals) &&
        listEquals(interests, other.interests) &&
        band == other.band &&
        setEquals(kinds, other.kinds) &&
        setEquals(contentTypes, other.contentTypes) &&
        extraNeed == other.extraNeed &&
        listEquals(blockedTopics, other.blockedTopics) &&
        listEquals(blockedKeywords, other.blockedKeywords) &&
        dailyMinutes == other.dailyMinutes;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(examGoals),
        Object.hashAll(interests),
        band,
        Object.hashAll(kinds.toList()..sort()),
        Object.hashAll(contentTypes.toList()..sort()),
        extraNeed,
        Object.hashAll(blockedTopics),
        Object.hashAll(blockedKeywords),
        dailyMinutes,
      );

  @override
  String toString() => 'InputPreferences(band: ${band.rawValue}, '
      'goals: $examGoals, interests: $interests, '
      'blocked: ${[...blockedTopics, ...blockedKeywords]}, '
      'kinds: $kinds, contentTypes: $contentTypes, '
      'extra: "$extraNeed", dailyMinutes: $dailyMinutes)';

  // ── 内部:两个来源的字段解析 ──

  /// 目标:多选优先;没有多选时回退解析单值 `goal`。
  ///
  /// 访谈页把目标与期限拼成 `'四六级(半年内)'`(见 tutor_interview_screen),
  /// 所以先取括号前主体;老界面还可能用 `+`/`、` 拼多个目标,一并拆开。
  /// 拆分**不按 `/`**:`雅思/托福` 是一个完整档位名,拆开就变成两个假目标。
  static List<String> _examGoalsOf(LearnerModel model) {
    final multi = _dedupe(model.goals);
    if (multi.isNotEmpty) return multi;
    final raw = (model.goal?.value ?? '').trim();
    if (raw.isEmpty) return const [];
    var head = raw;
    final paren = head.indexOf(RegExp(r'[（(]'));
    if (paren > 0) head = head.substring(0, paren);
    final parts = head
        .split(RegExp(r'[+＋、]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    return _dedupe(parts);
  }

  /// 兴趣:LearnerModel.interests ∪ MaterialPrefs.genres(自由文本拆分后)
  ///
  /// 为什么 genres 要拆:它是**一段自由文本**("哲学散文、英式幽默"),
  /// 而 UI 需要逐条展示/逐条匹配;不拆空格,否则 "science fiction" 会被拆坏。
  static List<String> _interestsOf(LearnerModel model, MaterialPrefs prefs) {
    final out = <String>[...?model.interests?.value];
    for (final part in prefs.genres.split(RegExp(r'[、,，;；\n]+'))) {
      out.add(part);
    }
    return _dedupe(out);
  }

  /// 去空、去首尾空白、忽略大小写去重(保留首次出现的原始写法)
  static List<String> _dedupe(Iterable<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in raw) {
      final text = item.trim();
      if (text.isEmpty) continue;
      if (seen.add(text.toLowerCase())) out.add(text);
    }
    return out;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 「找材料」AI 思考强度(2026-11-08 用户要求:在哪看/调;搜索要发挥满 AI)
// ═══════════════════════════════════════════════════════════════════════

/// 找材料链路里"哪类 AI 任务"(同一档位在两类任务上映射不同)。
enum FindMaterialAiTask {
  /// 检索词规划 / 补救轮(输出很短,重思考纯浪费时延)
  plan,

  /// AI 改写学习版(要吐完整长文,不能漏字段)
  rewrite,
}

/// 用户可选的「AI 思考强度」三档(快 / 标准 / 深入)。
///
/// 为什么要包一层而不是直接把 disabled/low/high/max 摆给用户:
/// - 底层档位在两类任务上并**不对称**(规划是轻任务、改写是重任务);
/// - 用户要的是"快/标准/深入"这种可理解的选择;
/// - **标准 = 改造前的有效行为基线**(规划 low、改写 high),默认不变差;
/// - **深入**才把重任务拉到 max(用户点名"搜索有没有发挥满 AI 能力")。
///
/// 历史背景(2026-11-08 本轮修复):此前 `search_query_planner.dart` 两处把
/// `thinkingLevel` 写成任务名 `'output'`,而 `ApiEndpointConfig.buildThinkingParamsFor`
/// 遇到非法值会走 `_ => 'disabled'` —— 也就是说检索词规划一直在"不思考"跑。
/// 现在统一从 [AiThinkingLevel.load] 读**合法档位**,并在 AI 改写结果卡上
/// 显示本次实际使用的档位(让用户"看得见发挥了什么")。
enum AiThinkingLevel {
  fast(
    '快',
    '最快:规划不思考、改写轻思考;复杂书名/长需求可能不准',
    'disabled',
    'low',
  ),
  standard(
    '标准',
    '默认:规划轻思考、改写深思考(改造前质量基线)',
    'low',
    'high',
  ),
  deep(
    '深入',
    '质量优先:规划高思考、改写极致,每次多花几秒',
    'high',
    'max',
  );

  const AiThinkingLevel(
    this.label,
    this.description,
    this.planLevel,
    this.rewriteLevel,
  );

  /// 界面文案(快 / 标准 / 深入)
  final String label;

  /// 一句话说明(设置项下面只显示这一行)
  final String description;

  /// 检索词规划/补救轮用的 DeepSeek thinkingLevel(合法值:disabled/low/high/max)
  final String planLevel;

  /// AI 改写用的 DeepSeek thinkingLevel
  final String rewriteLevel;

  /// Hive key(与其它设置同一个 `settings` box,零 DB 迁移)
  static const String hiveKey = 'find_material_ai_thinking';

  /// 读不到/首次使用 → **标准**(与改造前的有效行为一致)
  static const AiThinkingLevel fallback = AiThinkingLevel.standard;

  /// 任务 → 真实 thinkingLevel(纯函数,可单测)
  String levelFor(FindMaterialAiTask task) =>
      task == FindMaterialAiTask.rewrite ? rewriteLevel : planLevel;

  /// 测试注入:设了就不读 Hive(渲染/单测不依赖 box)
  @visibleForTesting
  static AiThinkingLevel? debugOverride;

  /// 测试注入:用内存 map 代替 Hive,验证"保存后能读回"
  @visibleForTesting
  static Map<String, Object?>? debugStore;

  @visibleForTesting
  static void debugReset() {
    debugOverride = null;
    debugStore = null;
  }

  /// 字符串 → 档位(不认识 → 标准,绝不抛)
  static AiThinkingLevel parse(Object? raw) {
    final name = '$raw'.trim();
    for (final level in AiThinkingLevel.values) {
      if (level.name == name) return level;
    }
    return fallback;
  }

  /// 读用户设置(异常/未设置 → 标准;页面永远能开)
  static AiThinkingLevel load() {
    final override = debugOverride;
    if (override != null) return override;
    try {
      final raw = debugStore != null
          ? debugStore![hiveKey]
          : Hive.box(AppConstants.hiveBoxSettings).get(hiveKey);
      return parse(raw);
    } catch (e) {
      debugPrint('ReadFlow 读取 AI 思考强度失败(按标准): $e');
      return fallback;
    }
  }

  /// 写用户设置;返回是否真的写进 Hive(false = 存储不可用,UI 可提示但不必打断)
  static Future<bool> save(AiThinkingLevel level) async {
    final store = debugStore;
    if (store != null) {
      store[hiveKey] = level.name;
      return true;
    }
    try {
      await Hive.box(AppConstants.hiveBoxSettings).put(hiveKey, level.name);
      return true;
    } catch (e) {
      debugPrint('ReadFlow 保存 AI 思考强度失败: $e');
      return false;
    }
  }
}

