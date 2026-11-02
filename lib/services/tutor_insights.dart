/// 助理逻辑层(v2.17 · 批 4 · 五维现状 + 可解释任务建议 + 复盘指标)。
///
/// ## 为什么要有这一层
/// 用户对"学习助理"的两次原话(2026-10-23 / 2026-11-01):
/// > "学习现状分析意义不大……而是分析更精准更专业想'词汇量 xxx''语法 xxx',
/// >  然后每个大现状问题下对应的才是具体问题表现"
/// > "学习任务也是死的……支持后,还要支持软件内部的数据追踪复盘与指导"
///
/// 旧实现(`tutor_engine.dart` 的 11 条规则)**全是行为债**(复习堆积/只输入不输出/
/// 材料偏难…),没有一条给出"词汇量多少、语法弱在哪"这样的能力值;任务也是
/// 模板句子。这一层把助理的**逻辑**重新组织成三块:
/// 1. [buildTutorInsights]:五维(vocab/grammar/reading/output/habit)现状,
///    每条带真实依据/严重度/动作语义;**没数据的维度写"待测 + 怎么测",
///    绝不编数字**(本文件里"待测"分支的文案刻意不含任何统计值);
/// 2. [suggestTutorTasks]:从真实数据推可解释任务(理由里带数字:到期词数、
///    输出次数、错误次数…),数据不足时给"先测词汇量"这类基础任务;
/// 3. [buildTutorReview]:任务复盘指标(完成率/计划vs实际/输出量),
///    口径写在注释与 metrics 键上,每条结论都带数字。
///
/// 纯逻辑:不碰 DB、不读时钟、不联网 —— 输入是 UI/服务组装好的
/// [InsightSource],因此所有规则都能被单测钉住。
library;

/// 五个维度 id(UI 排序/配色/图标按它映射,别用中文当 key)
class TutorDimensions {
  TutorDimensions._();

  static const String vocab = 'vocab';
  static const String grammar = 'grammar';
  static const String reading = 'reading';
  static const String output = 'output';
  static const String habit = 'habit';

  /// 顺序即 UI 默认展示顺序(词汇 → 语法 → 阅读 → 输出 → 习惯)
  static const List<String> ordered = <String>[
    vocab,
    grammar,
    reading,
    output,
    habit,
  ];

  static String labelOf(String dimension) => switch (dimension) {
        vocab => '词汇',
        grammar => '语法',
        reading => '阅读',
        output => '输出',
        habit => '习惯',
        _ => dimension,
      };
}

/// 动作跳转语义 id(**不硬编码页面类**)。
///
/// UI 拿到这些 id 自己路由;将来页面改名/拆分不影响逻辑层:
/// - `placement`:去测词汇量(完整版含语法小题);
/// - `review`:去复习/背词;
/// - `output`:去输出练习(写词/写句/写段/写篇);
/// - `reading`:去阅读(材料中心/阅读器);
/// - `prefs`:去设置偏好(目标/每日时长/黑名单)。
class TutorActionJumps {
  TutorActionJumps._();

  static const String placement = 'placement';
  static const String review = 'review';
  static const String output = 'output';
  static const String reading = 'reading';
  static const String prefs = 'prefs';

  static const List<String> all = <String>[
    placement,
    review,
    output,
    reading,
    prefs,
  ];
}

/// 任务归属维度(复盘时按它聚合完成率;`baseline` = 补基础数据)
class TutorGoalTags {
  TutorGoalTags._();

  static const String vocab = TutorDimensions.vocab;
  static const String grammar = TutorDimensions.grammar;
  static const String reading = TutorDimensions.reading;
  static const String output = TutorDimensions.output;
  static const String habit = TutorDimensions.habit;
  static const String baseline = 'baseline';

  static const List<String> all = <String>[
    vocab,
    grammar,
    reading,
    output,
    habit,
    baseline,
  ];
}

/// 现状分析的输入(**全部可选/可空**,由 UI 或快照服务组装)。
///
/// 为什么全用可空:`null` 表示"这个数据还没采到/采不到",与"确实是 0"是
/// 两件事 —— 逻辑层靠这个区别决定显示"0 次"还是"待测",绝不把 null 当 0。
class InsightSource {
  /// 词汇量估计(来自 vocab_estimator 的测量值;没测过 = null)
  final int? vocabEstimate;

  /// 估计区间半宽(如 ±350 词);测试结果里是 (high-low)/2
  final int? vocabCi;

  /// CEFR 粗估(词汇量映射;test 来源才有)
  final String? cefr;

  /// 今天到期的复习词数(word_review.due_at <= now)
  final int? dueWords;

  /// 复习留存率 0~1(如 1 - lapses/reps;没有复习历史 = null)
  final double? reviewRetention;

  /// 错误标签累计次数(tag → count,来自 error_tags;空 = 还没建过档)
  final Map<String, int> errorTagCounts;

  /// 实测阅读速度(词/分,reading_sessions.wpm 平均;没读过 = null)
  final double? readingWpm;

  /// 近 30 天读完的材料数
  final int? materialsFinished30d;

  /// 在读(有进度、未读完)的材料数
  final int? materialsReading;

  /// 近 30 天输出练习作答数(output_attempts;没有数据 = null)
  final int? outputAttempts30d;

  /// 输出均分(0~100 百分制;兼容 0~1 会 ×100;没有评分 = null)
  final double? outputAvgScore;

  /// 最近一次输出时间(没有 = null)
  final DateTime? outputLastAt;

  /// 近 30 天写译记录篇数(writing_logs;没有数据 = null)
  final int? writeLogs30d;

  /// 连续学习天数(daily_log;没有记录 = null)
  final int? streakDays;

  /// 每日可投入分钟数(learner_model.dailyMinutes;没设 = null)
  final int? dailyMinutes;

  /// 多选目标(来自输入偏好层,如 ['四六级','兴趣阅读'])
  final List<String> examGoals;

  /// 距目标词表还差多少词(需要外部词表对照;暂时没有 = null)
  final int? goalWordsGap;

  const InsightSource({
    this.vocabEstimate,
    this.vocabCi,
    this.cefr,
    this.dueWords,
    this.reviewRetention,
    this.errorTagCounts = const <String, int>{},
    this.readingWpm,
    this.materialsFinished30d,
    this.materialsReading,
    this.outputAttempts30d,
    this.outputAvgScore,
    this.outputLastAt,
    this.writeLogs30d,
    this.streakDays,
    this.dailyMinutes,
    this.examGoals = const <String>[],
    this.goalWordsGap,
  });

  /// 是否什么数据都没有(UI 可据此显示"先聊聊/先做一次速测")
  bool get isEmpty =>
      vocabEstimate == null &&
      vocabCi == null &&
      (cefr ?? '').trim().isEmpty &&
      dueWords == null &&
      reviewRetention == null &&
      errorTagCounts.isEmpty &&
      readingWpm == null &&
      materialsFinished30d == null &&
      materialsReading == null &&
      outputAttempts30d == null &&
      outputAvgScore == null &&
      outputLastAt == null &&
      writeLogs30d == null &&
      streakDays == null &&
      dailyMinutes == null &&
      examGoals.isEmpty &&
      goalWordsGap == null;
}

/// 一条五维现状。
///
/// 约定:
/// - [measured] = false 时,[valueText] 固定为「待测」、[evidence] 必须写清
///   "为什么现在测不了 + 怎么测",且**不许出现任何统计数字**(避免把缺失值
///   读成 0);
/// - [severity]:0 正常 / 1 注意(值得看一眼)/ 2 该动手;
/// - [actionJump] 只取 [TutorActionJumps] 里的语义 id,UI 自己路由。
class TutorInsight {
  /// 五维之一(见 [TutorDimensions])
  final String dimension;

  /// 标题(如「词汇量」「语法薄弱点」;待测时带「· 待测」)
  final String title;

  /// 主值(如「4,200 ±350 词」「时态 8 次 · 冠词 5 次」;待测时「待测」)
  final String valueText;

  /// 依据:必须能指回真实数据(来源 + 数字;待测时写"怎么测")
  final String evidence;

  /// 动作文案(可空;如「3 分钟速测词汇量」)
  final String? actionLabel;

  /// 动作语义 id(见 [TutorActionJumps];可空)
  final String? actionJump;

  /// 这个维度是否有真实测量/行为数据
  final bool measured;

  /// 0 正常 / 1 注意 / 2 该动手
  final int severity;

  const TutorInsight({
    required this.dimension,
    required this.title,
    required this.valueText,
    required this.evidence,
    this.actionLabel,
    this.actionJump,
    required this.measured,
    required this.severity,
  });

  @override
  String toString() =>
      'TutorInsight($dimension, measured=$measured, sev=$severity, $valueText)';
}

/// 一条可解释的任务建议。
class TaskSuggestion {
  /// 任务标题(带具体对象,如「复习 12 个到期词」)
  final String title;

  /// 为什么给你派这个任务 —— **必须来自真实数据**(数字/来源),不写空话
  final String reason;

  /// 预计分钟数(≥1;由真实口径估算:复习约 6 秒/词、写作约 10 分钟…)
  final int minutes;

  /// 跳转语义 id(见 [TutorActionJumps])
  final String action;

  /// 归属维度(见 [TutorGoalTags],复盘按它聚合)
  final String goalTag;

  const TaskSuggestion({
    required this.title,
    required this.reason,
    required this.minutes,
    required this.action,
    required this.goalTag,
  });

  @override
  String toString() => 'TaskSuggestion($title, ${minutes}min, $action)';
}

/// 复盘结果:结论行 + 指标(UI 画图用)。
class TutorReview {
  /// 2~4 条结论,每条都带数字
  final List<String> lines;

  /// 指标(键与口径见 [buildTutorReview] 注释)
  final Map<String, num> metrics;

  const TutorReview({required this.lines, required this.metrics});

  /// 是否有已结算任务(没有时完成率类指标不存在,UI 显示"先做一次")
  bool get hasSettledTasks => (metrics['settled'] ?? 0) > 0;
}

// ═══════════════════════════════════════════════════════════════════════
// ① 五维现状
// ═══════════════════════════════════════════════════════════════════════

/// 生成五维现状(max 限制返回条数,默认 6 足以放满五维)。
///
/// 排序:**severity 降序 → 有数据的在前 → 维度固定顺序**。
/// 为什么"有数据"要单独作并列条件:待测维度 severity 一律 0(缺数据不是问题),
/// 若只按 severity 排,它会和"正常但有数据"的维度混在一起,用户看到的顺序
/// 就会飘;把 measured 放到第二排序键,数据完整的维度永远在待测之前。
List<TutorInsight> buildTutorInsights(InsightSource source, {int max = 6}) {
  if (max <= 0) return const <TutorInsight>[];
  final insights = <TutorInsight>[
    _vocabInsight(source),
    _grammarInsight(source),
    _readingInsight(source),
    _outputInsight(source),
    _habitInsight(source),
  ];
  insights.sort((a, b) {
    final bySeverity = b.severity.compareTo(a.severity);
    if (bySeverity != 0) return bySeverity;
    if (a.measured != b.measured) return a.measured ? -1 : 1;
    return TutorDimensions.ordered
        .indexOf(a.dimension)
        .compareTo(TutorDimensions.ordered.indexOf(b.dimension));
  });
  return List<TutorInsight>.unmodifiable(insights.take(max));
}

TutorInsight _vocabInsight(InsightSource s) {
  final estimate = s.vocabEstimate;
  final measured = estimate != null && estimate > 0;

  if (!measured) {
    // 待测分支:文案里不出现任何"用户统计数字" —— 只有"3 分钟"这种操作时长
    return const TutorInsight(
      dimension: TutorDimensions.vocab,
      title: '词汇量 · 待测',
      valueText: '待测',
      evidence: '还没有词汇量基线 —— 现在只能按最高频的 800 个词保守估计材料难度,'
          '给不出"词汇量 xxx";做一次 3 分钟速测(认词 + 伪词校准)就能得到带区间的估计',
      actionLabel: '3 分钟速测词汇量',
      actionJump: TutorActionJumps.placement,
      measured: false,
      severity: 0,
    );
  }

  final ci = s.vocabCi;
  final valueText = ci != null && ci > 0
      ? '${_formatInt(estimate)} ±${_formatInt(ci)} 词'
      : '${_formatInt(estimate)} 词';

  final evidenceParts = <String>[
    '来源:词汇量速测(认词 + 伪词校准)',
  ];
  final cefr = (s.cefr ?? '').trim();
  if (cefr.isNotEmpty) evidenceParts.add('粗估 CEFR $cefr');
  final gap = s.goalWordsGap;
  if (gap != null) {
    final goal = s.examGoals.isEmpty ? '目标' : s.examGoals.join('、');
    evidenceParts.add(gap > 0
        ? '距「$goal」词表还差 ${_formatInt(gap)} 词'
        : '已达到「$goal」词表要求');
  }
  final retention = s.reviewRetention;
  if (retention != null && retention.isFinite) {
    evidenceParts.add('复习留存 ${_pct(retention)}');
  }
  final due = s.dueWords;
  if (due != null && due > 0) {
    evidenceParts.add('今天 ${_formatInt(due)} 个词到期');
  }

  var severity = 0;
  String? actionJump = TutorActionJumps.review;
  String? actionLabel = '去复习加固';
  // 留存低 = 背了忘,是最该动手的词汇问题;其次才是"离目标词表还差很多"
  if (retention != null && retention < 0.7) {
    severity = 2;
    actionLabel = '去复习:留存只剩 ${_pct(retention)}';
  } else if (retention != null && retention < 0.85) {
    severity = 1;
    actionLabel = '去复习加固(留存 ${_pct(retention)})';
  } else if (gap != null && gap > 1500) {
    severity = 2;
    actionLabel = '去背目标词(还差 ${_formatInt(gap)})';
  } else if (gap != null && gap > 0) {
    severity = 1;
    actionLabel = '去背目标词(还差 ${_formatInt(gap)})';
  } else if (due != null && due > 0) {
    actionLabel = '复习 ${_formatInt(due)} 个到期词';
  } else {
    // 数据正常且没有待办:不给按钮(避免每个维度都挂一个"去…"显得吵)
    actionJump = null;
    actionLabel = null;
  }
  if (severity == 0 && estimate < 3000) {
    // 基础阶段:词汇量本身值得注意,但不至于"该动手"
    severity = 1;
  }

  return TutorInsight(
    dimension: TutorDimensions.vocab,
    title: '词汇量',
    valueText: valueText,
    evidence: evidenceParts.join(';'),
    actionLabel: actionLabel,
    actionJump: actionJump,
    measured: true,
    severity: severity,
  );
}

TutorInsight _grammarInsight(InsightSource s) {
  final counts = <String, int>{
    for (final e in s.errorTagCounts.entries)
      if (e.key.trim().isNotEmpty && e.value > 0) e.key.trim(): e.value,
  };
  final total = counts.values.fold<int>(0, (sum, v) => sum + v);
  final measured = counts.isNotEmpty && total > 0;

  if (!measured) {
    return const TutorInsight(
      dimension: TutorDimensions.grammar,
      title: '语法 · 待测',
      valueText: '待测',
      evidence: '错误档案还是空的 —— 语法数据来自写译批改/回译/读后测验替用户'
          '记下的错误标签;写一段英文(哪怕三句)或做一次读后测验,就会自动建出'
          '"时态/冠词/搭配"这类具体薄弱点',
      actionLabel: '去写一段,自动建档',
      actionJump: TutorActionJumps.output,
      measured: false,
      severity: 0,
    );
  }

  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  final top = ranked.first;
  final valueText = ranked
      .take(2)
      .map((e) => '${e.key} ${_formatInt(e.value)} 次')
      .join(' · ');

  var severity = 0;
  if (total >= 10 || top.value >= 5) {
    severity = 2;
  } else if (total >= 3 || top.value >= 2) {
    severity = 1;
  }

  return TutorInsight(
    dimension: TutorDimensions.grammar,
    title: '语法薄弱点',
    valueText: valueText,
    evidence: '来源:错误档案(error_tags,由写译批改/回译/读后测验写入):'
        '共 ${_formatInt(ranked.length)} 类 ${_formatInt(total)} 次,'
        '最多的是「${top.key}」${_formatInt(top.value)} 次',
    actionLabel: severity > 0 ? '针对「${top.key}」练 5 句' : null,
    actionJump: severity > 0 ? TutorActionJumps.output : null,
    measured: true,
    severity: severity,
  );
}

TutorInsight _readingInsight(InsightSource s) {
  final wpm = s.readingWpm;
  final finished = s.materialsFinished30d;
  final reading = s.materialsReading;
  final measured = wpm != null || finished != null || reading != null;

  if (!measured) {
    return const TutorInsight(
      dimension: TutorDimensions.reading,
      title: '阅读能力 · 待测',
      valueText: '待测',
      evidence: '还没有阅读会话记录 —— 读任意一篇材料几分钟,系统就会记录'
          '阅读速度(wpm)、词数与阅读时长,再谈"读得快不快/难度合不合适"',
      actionLabel: '去读一篇(约 10 分钟)',
      actionJump: TutorActionJumps.reading,
      measured: false,
      severity: 0,
    );
  }

  final valueParts = <String>[];
  if (wpm != null && wpm > 0 && wpm.isFinite) {
    valueParts.add('${wpm.round()} 词/分');
  }
  if (finished != null) valueParts.add('近 30 天读完 ${_formatInt(finished)} 篇');
  if (valueParts.isEmpty) valueParts.add('在读 ${_formatInt(reading ?? 0)} 篇');
  final valueText = valueParts.join(' · ');

  final evidenceParts = <String>['来源:阅读会话(reading_sessions)实测'];
  if (finished != null) evidenceParts.add('近 30 天读完 ${_formatInt(finished)} 篇');
  if (reading != null) evidenceParts.add('在读 ${_formatInt(reading)} 篇');

  var severity = 0;
  var actionLabel = '去泛读 10 分钟(先不查词)';
  if (wpm != null && wpm > 0 && wpm < 100) {
    severity = 2;
  } else if (wpm != null && wpm > 0 && wpm < 120) {
    severity = 1;
  } else if (finished != null && finished == 0) {
    // 近 30 天一篇没读完:不是速度问题,是"没有完成",同样值得注意
    severity = 1;
    actionLabel = '读完一篇材料';
  }
  if (severity == 0) actionLabel = '';

  return TutorInsight(
    dimension: TutorDimensions.reading,
    title: '阅读能力',
    valueText: valueText,
    evidence: evidenceParts.join(';'),
    actionLabel: actionLabel.isEmpty ? null : actionLabel,
    actionJump: severity > 0 ? TutorActionJumps.reading : null,
    measured: true,
    severity: severity,
  );
}

TutorInsight _outputInsight(InsightSource s) {
  final attempts = s.outputAttempts30d;
  final logs = s.writeLogs30d;
  final avg = _normalizeScore(s.outputAvgScore);
  final lastAt = s.outputLastAt;
  // "有没有输入数据"决定零输出是"该动手的问题"还是"新用户引导"
  final hasInput = (s.readingWpm != null) ||
      (s.materialsFinished30d != null && s.materialsFinished30d! > 0) ||
      (s.materialsReading != null && s.materialsReading! > 0);

  final known = attempts != null || logs != null || lastAt != null;

  if (!known) {
    // 完全没采到输出数据:文案不许出现"0 次/0 篇"
    return TutorInsight(
      dimension: TutorDimensions.output,
      title: '输出能力 · 待测',
      valueText: '待测',
      evidence: hasInput
          ? '还没有输出记录 —— 阅读数据已经有了,但没有一次写/译练习,'
              '输入没有经过检验;写一句中译英就会产生第一次评分与错误标签'
          : '还没有输出练习记录 —— 从一句中译英回译开始(约 2 分钟),'
              '写完就能看到分数与具体错误点',
      actionLabel: '去写一句/一段',
      actionJump: TutorActionJumps.output,
      measured: false,
      // 有输入却没输出 = 该动手;全空的新用户 = 中性(缺数据不是问题,
      // 与其它待测维度同档,避免一上来就红卡)
      severity: hasInput ? 2 : 0,
    );
  }

  final produced = (attempts ?? 0) > 0 || (logs ?? 0) > 0;
  if (!produced) {
    // 明确知道"近 30 天没有输出":这不是待测,是测得 0 —— 直接给动作
    final valueParts = <String>[];
    if (attempts != null) valueParts.add('近 30 天 0 次练习');
    if (logs != null) valueParts.add('近 30 天 0 篇写译');
    return TutorInsight(
      dimension: TutorDimensions.output,
      title: '输出能力',
      valueText: valueParts.join(' · '),
      evidence: '来源:输出作答(output_attempts)与写译记录(writing_logs);'
          '近 30 天的记录为 0 —— 只有输入没有产出,输入到底有没有用检验不出来',
      actionLabel: '先写一段(约 10 分钟)',
      actionJump: TutorActionJumps.output,
      measured: true,
      severity: hasInput ? 2 : 1,
    );
  }

  final valueParts = <String>[];
  if (attempts != null && attempts > 0) {
    valueParts.add('近 30 天 ${_formatInt(attempts)} 次练习');
  }
  if (logs != null && logs > 0) {
    valueParts.add('${_formatInt(logs)} 篇写译');
  }
  if (avg != null) valueParts.add('均分 ${avg.round()}');
  final evidenceParts = <String>['来源:输出作答(output_attempts)与写译记录(writing_logs)'];
  if (lastAt != null) {
    evidenceParts.add('最近一次输出 ${_dateOf(lastAt)}');
  }

  var severity = 0;
  var actionLabel = '再写一段(约 10 分钟)';
  if (avg != null && avg < 60) {
    severity = 2;
  } else if (avg != null && avg < 75) {
    severity = 1;
  } else if (attempts != null && attempts < 4) {
    // 一周不到一次:输出频率偏低,值得注意(但不至于红卡)
    severity = 1;
    actionLabel = '本周再写一次';
  }
  if (severity == 0) actionLabel = '';

  return TutorInsight(
    dimension: TutorDimensions.output,
    title: '输出能力',
    valueText: valueParts.join(' · '),
    evidence: evidenceParts.join(';'),
    actionLabel: actionLabel.isEmpty ? null : actionLabel,
    actionJump: severity > 0 ? TutorActionJumps.output : null,
    measured: true,
    severity: severity,
  );
}

TutorInsight _habitInsight(InsightSource s) {
  final streak = s.streakDays;
  final minutes = s.dailyMinutes;
  final measured = streak != null || minutes != null;

  if (!measured) {
    return const TutorInsight(
      dimension: TutorDimensions.habit,
      title: '学习习惯 · 待测',
      valueText: '待测',
      evidence: '还没有每日学习日志 —— 任何一次收词/复习/练习都会开始记录'
          '连续天数与每日投入,连续记录建立后再谈"节奏稳不稳"',
      actionLabel: '今天先学 5 分钟',
      actionJump: TutorActionJumps.reading,
      measured: false,
      severity: 0,
    );
  }

  final valueParts = <String>[];
  if (streak != null) valueParts.add('连续 ${_formatInt(streak)} 天');
  if (minutes != null && minutes > 0) valueParts.add('每天目标 ${_formatInt(minutes)} 分钟');
  final evidenceParts = <String>['来源:每日学习日志(daily_log)的连续天数'];
  if (minutes == null || minutes <= 0) {
    evidenceParts.add('每日可投入时间还没设,任务量只能按默认值估');
  }

  var severity = 0;
  var actionJump = TutorActionJumps.prefs;
  var actionLabel = '设置每天可投入时间';
  if (minutes == null || minutes <= 0) {
    severity = 1;
  } else if (streak != null && streak == 0) {
    severity = 1;
    actionJump = TutorActionJumps.reading;
    actionLabel = '今天先学 5 分钟,把节奏接回来';
  } else {
    actionJump = '';
    actionLabel = '';
  }

  return TutorInsight(
    dimension: TutorDimensions.habit,
    title: '学习习惯',
    valueText: valueParts.isEmpty ? '待测' : valueParts.join(' · '),
    evidence: evidenceParts.join(';'),
    actionLabel: actionLabel.isEmpty ? null : actionLabel,
    actionJump: actionJump.isEmpty ? null : actionJump,
    measured: true,
    severity: severity,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// ② 可解释任务建议
// ═══════════════════════════════════════════════════════════════════════

/// 由现状数据推 3~4 条今日任务(最多 [max] 条)。
///
/// 优先级(与用户"先清欠账、再补输出、再专项"的顺序一致):
/// 1. 到期词复习(有到期才给;分钟按约 6 秒/词估);
/// 2. 还没测词汇量 → 先测(基础任务,数据不足时也有可执行项);
/// 3. 输出缺失/偏少(30 天 0 次或不到 4 次);
/// 4. 薄弱语法(错误档案里 top 标签,出现 ≥2 次才给专项);
/// 5. 阅读(速度偏慢/没读完/有在读);
/// 6. 习惯(没设每日目标/连续中断);
/// 7. 目标导向阅读(有多选目标时);
/// 8. 兜底:不足 3 条时补"读一篇/写三句"这类**能产生第一份数据**的基础任务。
///
/// 硬规则:每条 reason 必须来自真实数据(数字/来源),不编造;数据不足分支
/// 只可以出现"约 X 分钟"这类操作时长。
List<TaskSuggestion> suggestTutorTasks(InsightSource source, {int max = 4}) {
  if (max <= 0) return const <TaskSuggestion>[];
  final tasks = <TaskSuggestion>[];
  final titles = <String>{};

  void add(TaskSuggestion task) {
    if (tasks.length >= max) return;
    if (!titles.add(task.title)) return;
    tasks.add(task);
  }

  final due = source.dueWords;
  final attempts = source.outputAttempts30d;
  final logs = source.writeLogs30d;
  final topError = _topErrorTag(source.errorTagCounts);

  // 1) 到期复习:复习债永远第一优先(不还,后面学什么都记不住)
  if (due != null && due > 0) {
    final minutes = _reviewMinutes(due);
    add(TaskSuggestion(
      title: '复习 ${_formatInt(due)} 个到期词',
      reason: '今天有 ${_formatInt(due)} 个词到期,按约 6 秒/词算约 $minutes 分钟;'
          '先清账再加新词',
      minutes: minutes,
      action: TutorActionJumps.review,
      goalTag: TutorGoalTags.vocab,
    ));
  }

  // 2) 没有词汇量基线:先测(其他维度的难度/题量都依赖它)
  if (source.vocabEstimate == null || source.vocabEstimate! <= 0) {
    add(const TaskSuggestion(
      title: '做一次词汇量速测',
      reason: '还没有词汇量基线 —— 速测约 3 分钟,测完材料难度与题量才按你的水平算',
      minutes: 3,
      action: TutorActionJumps.placement,
      goalTag: TutorGoalTags.baseline,
    ));
  }

  // 3) 输出:0 次/偏少都给,理由带真实次数
  final produced = (attempts ?? 0) > 0 || (logs ?? 0) > 0;
  if (!produced) {
    final hasKnownZero = attempts != null || logs != null;
    add(TaskSuggestion(
      title: '写一段:中译英回译或写 3 句',
      reason: hasKnownZero
          ? '近 30 天输出 0 次 —— 输入再多,不写就检验不出有没有学会'
          : '还没有输出练习记录 —— 先写一句中译英,能立刻看到分数与错误点',
      minutes: 10,
      action: TutorActionJumps.output,
      goalTag: TutorGoalTags.output,
    ));
  } else if (attempts != null && attempts < 4) {
    add(TaskSuggestion(
      title: '本周再写一次(约 10 分钟)',
      reason: '近 30 天只做了 ${_formatInt(attempts)} 次输出练习,'
          '还不到一周一次;再写一次就能形成节奏',
      minutes: 10,
      action: TutorActionJumps.output,
      goalTag: TutorGoalTags.output,
    ));
  }

  // 4) 薄弱语法:出现 ≥2 次才值得开专项(偶发一次不算薄弱)
  if (topError != null && topError.$2 >= 2) {
    add(TaskSuggestion(
      title: '针对「${topError.$1}」练 5 句改写',
      reason: '错误档案里「${topError.$1}」累计出现 ${_formatInt(topError.$2)} 次,'
          '是目前最集中的语法薄弱点',
      minutes: 10,
      action: TutorActionJumps.output,
      goalTag: TutorGoalTags.grammar,
    ));
  }

  // 5) 阅读:速度偏慢 / 没读完 / 有在读
  final wpm = source.readingWpm;
  final finished = source.materialsFinished30d;
  final reading = source.materialsReading;
  if (wpm != null && wpm > 0 && wpm < 120) {
    add(TaskSuggestion(
      title: '不查词泛读 10 分钟',
      reason: '实测阅读速度 ${wpm.round()} 词/分,低于 120 通常是在逐词翻译;'
          '先练"不回看"的速度',
      minutes: 10,
      action: TutorActionJumps.reading,
      goalTag: TutorGoalTags.reading,
    ));
  } else if (reading != null && reading > 0) {
    add(TaskSuggestion(
      title: '把在读的 ${_formatInt(reading)} 篇各读 10 分钟',
      reason: '有 ${_formatInt(reading)} 篇材料已经开始读但还没读完,'
          '接着读比再找新材料更容易启动',
      minutes: 15,
      action: TutorActionJumps.reading,
      goalTag: TutorGoalTags.reading,
    ));
  } else if (finished != null && finished == 0) {
    add(const TaskSuggestion(
      title: '读完一篇 10 分钟的材料',
      reason: '近 30 天读完 0 篇 —— 精读的收获要读到结尾才拿得到',
      minutes: 15,
      action: TutorActionJumps.reading,
      goalTag: TutorGoalTags.reading,
    ));
  }

  // 6) 习惯:每日目标没设 → 所有任务量都只能按默认值估
  if (source.dailyMinutes == null || source.dailyMinutes! <= 0) {
    add(const TaskSuggestion(
      title: '设置每天可投入时间',
      reason: '每日目标是任务量的计算依据 —— 没设时只能按默认 30 分钟估,'
          '容易过载或太少(约 1 分钟)',
      minutes: 1,
      action: TutorActionJumps.prefs,
      goalTag: TutorGoalTags.habit,
    ));
  } else if (source.streakDays != null && source.streakDays == 0) {
    add(const TaskSuggestion(
      title: '今天先学 5 分钟,把节奏接回来',
      reason: '连续学习天数是 0 —— 别定大目标,先让今天有记录',
      minutes: 5,
      action: TutorActionJumps.reading,
      goalTag: TutorGoalTags.habit,
    ));
  }

  // 7) 目标导向:有多选目标但阅读数据为空时,给一条"按目标读"
  if (source.examGoals.isNotEmpty && reading == null && (wpm == null)) {
    final goal = source.examGoals.join('、');
    add(TaskSuggestion(
      title: '按「${source.examGoals.first}」目标读 1 篇材料',
      reason: '你的目标是「$goal」—— 输入材料要对得上目标,才不是泛泛地读',
      minutes: 15,
      action: TutorActionJumps.reading,
      goalTag: TutorGoalTags.reading,
    ));
  }

  // 8) 兜底:不足 3 条时补"能产生第一份数据"的基础任务(不编数字)
  if (tasks.length < 3) {
    add(const TaskSuggestion(
      title: '读一篇 10 分钟的材料',
      reason: '先产生第一份阅读数据 —— 有了 wpm 与完成记录,助理才能判断难度',
      minutes: 10,
      action: TutorActionJumps.reading,
      goalTag: TutorGoalTags.reading,
    ));
  }
  if (tasks.length < 3) {
    add(const TaskSuggestion(
      title: '写 3 句并保存记录',
      reason: '写 3 句(约 5 分钟)就能建立错误档案,复盘时才有"薄弱点"可说',
      minutes: 5,
      action: TutorActionJumps.output,
      goalTag: TutorGoalTags.output,
    ));
  }
  if (tasks.length < 3) {
    add(const TaskSuggestion(
      title: '设置每日可投入时间',
      reason: '设置每天可投入多久(约 1 分钟),任务量才有依据',
      minutes: 1,
      action: TutorActionJumps.prefs,
      goalTag: TutorGoalTags.habit,
    ));
  }

  return List<TaskSuggestion>.unmodifiable(tasks);
}

/// (tag, 累计次数) 里的最高项;没有有效数据返回 null
(String, int)? _topErrorTag(Map<String, int> counts) {
  (String, int)? top;
  for (final entry in counts.entries) {
    final tag = entry.key.trim();
    if (tag.isEmpty || entry.value <= 0) continue;
    if (top == null || entry.value > top.$2) top = (tag, entry.value);
  }
  return top;
}

/// 复习时长估算:约 6 秒/词(与 tutor_engine 的口径一致),至少 1 分钟
int _reviewMinutes(int count) {
  final seconds = count * 6;
  final minutes = (seconds / 60).ceil();
  return minutes < 1 ? 1 : minutes;
}

// ═══════════════════════════════════════════════════════════════════════
// ③ 复盘
// ═══════════════════════════════════════════════════════════════════════

/// 任务复盘(2~4 条结论,每条都带数字)。
///
/// ## 口径(必须写清,否则"完成率"永远对不上 UI)
/// - `settled = done + skipped + expired`:**已结算**的任务数(跳过的、过期未做的
///   都算"没完成",所以进分母 —— 否则"跳过 10 条只做 1 条"会显示 100%);
/// - `completionRate = done / settled`(settled 为 0 时**不产生**该指标,
///   UI 显示"先做一次",不能用 0 冒充);
/// - `planRate = done / planned`(计划达成率;planned 为 0 时不产生);
/// - `pending = max(0, planned - settled)`:还没结算的(进行中/未到期);
/// - `timeRatio = actualMinutes / plannedMinutes`(计划vs实际;两者都 >0 才算);
/// - `outputAvgScore` 统一成 0~100(调用方传 0~1 会被 ×100)。
///
/// 结论行规则:完成情况必出;时长/输出有数据才出;最后一条是**下周指导**
/// (按完成率给"减量/保持/加输出"的建议,带数字)。总长度裁到 4 行。
TutorReview buildTutorReview({
  required int planned,
  required int done,
  required int skipped,
  required int expired,
  int? actualMinutes,
  int? plannedMinutes,
  int? outputCount,
  double? outputAvgScore,
}) {
  // 负数是脏数据:按 0 处理,别让完成率变成负数
  final p = planned < 0 ? 0 : planned;
  final d = done < 0 ? 0 : done;
  final s = skipped < 0 ? 0 : skipped;
  final e = expired < 0 ? 0 : expired;
  final settled = d + s + e;
  final pending = p > settled ? p - settled : 0;
  final completionRate = settled == 0 ? null : d / settled;
  final planRate = p == 0 ? null : d / p;
  final actualM = actualMinutes != null && actualMinutes >= 0 ? actualMinutes : null;
  final plannedM = plannedMinutes != null && plannedMinutes > 0 ? plannedMinutes : null;
  final outputN = outputCount != null && outputCount >= 0 ? outputCount : null;
  final avg = _normalizeScore(outputAvgScore);
  final timeRatio =
      (actualM != null && plannedM != null) ? actualM / plannedM : null;

  final metrics = <String, num>{
    'planned': p,
    'done': d,
    'skipped': s,
    'expired': e,
    'settled': settled,
    'pending': pending,
    'completionRate': ?completionRate,
    'planRate': ?planRate,
    'actualMinutes': ?actualM,
    'plannedMinutes': ?plannedM,
    'timeRatio': ?timeRatio,
    'outputCount': ?outputN,
    'outputAvgScore': ?avg,
  };

  final lines = <String>[];

  // ① 完成情况(必出)
  if (settled == 0) {
    lines.add('计划 $p 条,已结算 0 条(完成 0 / 跳过 0 / 过期 0)'
        '—— 完成或跳过任意一条后,这里才会出现完成率');
  } else {
    lines.add('已结算 $settled 条:完成 $d、跳过 $s、过期 $e,'
        '完成率 ${_pct(completionRate!)}'
        '${pending > 0 ? '(另有 $pending 条还在进行)' : ''}');
  }

  // ② 计划 vs 实际时长
  if (actualM != null && plannedM != null) {
    final ratio = actualM / plannedM;
    final diff = ((ratio - 1) * 100).round();
    lines.add('计划投入 $plannedM 分钟、实际 $actualM 分钟'
        '(偏差 ${diff > 0 ? '+' : ''}$diff%)');
  } else if (actualM != null) {
    lines.add('实际投入 $actualM 分钟(计划时长未记录,算不出偏差)');
  } else if (plannedM != null) {
    lines.add('计划投入 $plannedM 分钟、实际时长未记录'
        '(完成打勾不代表真的学了,建议记录用时)');
  }

  // ③ 输出产出
  if (outputN != null) {
    if (outputN > 0) {
      lines.add(avg != null
          ? '完成 $outputN 次输出练习,均分 ${avg.round()} 分'
          : '完成 $outputN 次输出练习(没有评分的作答不计均分)');
    } else {
      lines.add('输出练习 0 次 —— 只有输入没有产出,下周至少加 1 次写/译');
    }
  }

  // ④ 下周指导(必出;按完成率给可执行建议)
  if (completionRate == null) {
    lines.add('还没有已结算任务(0 条):先完成 1 条,复盘才有完成率与偏差可看');
  } else if (completionRate < 0.5) {
    final reduced = p <= 1 ? p : (p * 0.7).round().clamp(1, p);
    lines.add('完成率 ${_pct(completionRate)} 偏低:下周把计划减到 $reduced 条,'
        '先把节奏稳住再谈加量');
  } else if (completionRate >= 0.8) {
    lines.add('完成率 ${_pct(completionRate)} 很稳:下周可以加 1 条输出任务'
        '($p → ${p + 1} 条),把练习量往上抬');
  } else {
    lines.add('完成率 ${_pct(completionRate)} 处于正常区间:保持 $p 条计划,'
        '优先补最薄弱的那一维');
  }

  return TutorReview(
    lines: List<String>.unmodifiable(lines.take(4)),
    metrics: Map<String, num>.unmodifiable(metrics),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 内部工具
// ═══════════════════════════════════════════════════════════════════════

/// 千分位(「4,200」比「4200」在卡片上更好读,也避免用户数错位数)
String _formatInt(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return negative ? '-$buf' : buf.toString();
}

/// 比例 → 整数百分比(「81%」;不做小数,减少噪声)
String _pct(double ratio) => '${(ratio.clamp(0.0, 1.0) * 100).round()}%';

/// 分数统一成 0~100:兼容调用方传 0~1(如 rubric 归一化分)的情况
double? _normalizeScore(double? raw) {
  if (raw == null || !raw.isFinite) return null;
  final value = raw > 0 && raw <= 1.0 ? raw * 100 : raw;
  return value.clamp(0.0, 100.0);
}

/// 日期短格式(最近一次输出用;不用"X 天前"避免依赖当前时钟)
String _dateOf(DateTime at) =>
    '${at.year.toString().padLeft(4, '0')}-'
    '${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}';
