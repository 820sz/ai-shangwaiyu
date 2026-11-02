/// ═══════════════════════════════════════════════════════════════════════
/// 输出模块 · **评分标准层**(批 3 · P2)。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 为什么要有这一层(用户原话与侦察结论):
/// - 旧的写译批改是"模型自由给 0-100",没有维度、没有档位、没有依据项 ——
///   用户看不出"这 80 分扣在哪",也**无法跨两次评分对比**;
/// - 旧回译练习的判分是词袋重合 0.5(`drill_planner.dart:1101`),没有词形还原、
///   没有语序、没有语法维度;
/// - 项目已有"证据优先"的方法论(`tutor_engine.dart` / `weekly_report.dart`
///   都要求"无证据不下结论"),rubric 评分沿用同一条纪律:
///   **每个维度先写答案里的依据，再给分；没有依据不许打分。**
///
/// 本文件只做"评分标准 + 提示词 + 解析"(纯函数、可单测),不碰数据库、不碰 UI:
/// - [OutputRubric] 4 套内置(`cet4_writing` / `cet4_translation` /
///   `back_translation` / `summary`),id 与数据库 `rubrics` seed **同一口径**;
/// - [buildScoringPrompt] 生成"先依据、后分数"的评分提示词;
/// - [parseScoringResult] 把模型返回的 JSON 解析成 [ScoredOutput],全程容错,
///   **解析失败返回 null,绝不抛异常**(不能因为模型多说一句话就把批改页打崩)。
///
/// 数据库对应(docs/research/output-and-tutor.md:192):
/// `rubrics(id, type, scoring_mode, dimensions_json, bands_json, prompt_template)`
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════
// 基础结构
// ═══════════════════════════════════════════════════════════════════════

/// 评分方式(与数据库 `rubrics.scoring_mode` 对齐)。
///
/// - [objective]:客观题(选择题/排序/拼写),本地判分,不用 AI;
/// - [aiRubric]:开放输出(写作/翻译/回译/摘要),按 [OutputRubric] 调 AI 评分;
/// - [manual]:用户自评(以后"对照参考译文自评"用得上,先留值)。
enum ScoringMode {
  objective('objective'),
  aiRubric('ai_rubric'),
  manual('manual');

  const ScoringMode(this.id);

  /// 数据库里存的值
  final String id;

  /// 容错解析:未知值 → [aiRubric](绝大多数行都是这一档,静默回落比抛异常稳)
  static ScoringMode parse(Object? raw) {
    final text = '${raw ?? ''}'.trim().toLowerCase();
    for (final mode in ScoringMode.values) {
      if (mode.id == text) return mode;
    }
    return ScoringMode.aiRubric;
  }
}

/// 一个评分维度(如"内容切题/语言准确")。
///
/// [weight] 与 [maxScore] 同时保留:权重用于展示比例与未来"加权换算",
/// 满分用于**直接给用户看"这维度 25 分拿了几分"** —— 两者写作 0.25 / 25。
class RubricDimension {
  /// 维度 key(与模型返回的 `dimensions[].key` 对齐;英文,稳定不变)
  final String key;

  /// 中文名(界面展示唯一来源)
  final String label;

  /// 权重 0~1(同一 rubric 内权重和为 1)
  final double weight;

  /// 该维度满分(权重 × 总分)
  final double maxScore;

  /// 评分提示(告诉模型/用户"这一维看什么")
  final String hint;

  const RubricDimension({
    required this.key,
    required this.label,
    required this.weight,
    required this.maxScore,
    this.hint = '',
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'weight': weight,
    'max_score': maxScore,
    'hint': hint,
  };

  /// 容错解析:key 为空/权重非法 → 返回 null(调用方跳过这一维)
  static RubricDimension? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = '${raw['key'] ?? ''}'.trim();
    if (key.isEmpty) return null;
    final weight = _toDouble(raw['weight'], fallback: 0);
    final maxScore = _toDouble(raw['max_score'], fallback: 0);
    return RubricDimension(
      key: key,
      label: '${raw['label'] ?? key}'.trim(),
      weight: weight.clamp(0.0, 1.0),
      maxScore: maxScore < 0 ? 0 : maxScore,
      hint: '${raw['hint'] ?? ''}'.trim(),
    );
  }
}

/// 一个分档(如"90-100 优秀")。
///
/// 区间语义:**`minScore <= score < maxScore`**,最高档包含 [maxScore]
/// (即 100 分落最高档)。[bandOf] 已按这个语义实现,UI 不要再自己判断。
class RubricBand {
  final double minScore;
  final double maxScore;
  final String label;
  final String description;

  const RubricBand({
    required this.minScore,
    required this.maxScore,
    required this.label,
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
    'min_score': minScore,
    'max_score': maxScore,
    'label': label,
    'description': description,
  };

  static RubricBand? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final min = _toDouble(raw['min_score'] ?? raw['min'], fallback: -1);
    final max = _toDouble(raw['max_score'] ?? raw['max'], fallback: -1);
    final label = '${raw['label'] ?? ''}'.trim();
    if (min < 0 || max < 0 || max < min || label.isEmpty) return null;
    return RubricBand(
      minScore: min,
      maxScore: max,
      label: label,
      description: '${raw['description'] ?? raw['desc'] ?? ''}'.trim(),
    );
  }

  @override
  String toString() => '$label(${minScore.round()}~${maxScore.round()})';
}

/// 一套评分标准(对应数据库 `rubrics` 的一行)。
class OutputRubric {
  /// id(与 DB seed 对齐:`cet4_writing` / `cet4_translation` /
  /// `back_translation` / `summary`)
  final String id;

  /// 类型(写作 / 翻译 / 回译 / 摘要;用于挑提示词与 UI 分类)
  final String type;

  final ScoringMode scoringMode;

  /// 维度(顺序即展示顺序)
  final List<RubricDimension> dimensions;

  /// 分档(从高到低排;空表示不展示档位)
  final List<RubricBand> bands;

  /// 该 rubric 的额外评分口径(会拼进 [buildScoringPrompt];DB 里可自定义)
  final String promptTemplate;

  const OutputRubric({
    required this.id,
    required this.type,
    required this.scoringMode,
    required this.dimensions,
    required this.bands,
    this.promptTemplate = '',
  });

  /// 总分 = 各维度满分之和(内置都是 100;数据库里自定义可能是其它满分)
  double get totalScore =>
      dimensions.fold<double>(0, (sum, d) => sum + d.maxScore);

  /// 权重之和(内置必须为 1;容错数据可能不精确,UI 不要拿它当总分)
  double get weightSum =>
      dimensions.fold<double>(0, (sum, d) => sum + d.weight);

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'scoring_mode': scoringMode.id,
    'dimensions': [for (final d in dimensions) d.toJson()],
    'bands': [for (final b in bands) b.toJson()],
    'prompt_template': promptTemplate,
  };

  /// **容错解析**:id 为空或维度全坏 → null(视为"这条 rubric 不可用"),
  /// 单个字段坏不抛(数据库/模型给的 JSON 都可能脏)。
  static OutputRubric? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    final dims = <RubricDimension>[];
    final rawDims = raw['dimensions'] ?? raw['dimensions_json'];
    if (rawDims is List) {
      for (final d in rawDims) {
        final parsed = RubricDimension.fromJson(d);
        if (parsed != null) dims.add(parsed);
      }
    }
    if (dims.isEmpty) return null;
    final bands = <RubricBand>[];
    final rawBands = raw['bands'] ?? raw['bands_json'];
    if (rawBands is List) {
      for (final b in rawBands) {
        final parsed = RubricBand.fromJson(b);
        if (parsed != null) bands.add(parsed);
      }
    }
    bands.sort((a, b) => b.minScore.compareTo(a.minScore)); // 高→低
    return OutputRubric(
      id: id,
      type: '${raw['type'] ?? ''}'.trim(),
      scoringMode: ScoringMode.parse(raw['scoring_mode']),
      dimensions: dims,
      bands: bands,
      promptTemplate: '${raw['prompt_template'] ?? ''}'.trim(),
    );
  }

  /// 4 套内置 rubric —— **id 必须与数据库 seed 一致**,否则 UI 从
  /// `exercise_sets.rubric_id` 会找不到评分标准(这是本轮唯一的硬约束)。
  ///
  /// 维度依据(PLAN-V3 §2.3 "rubric 从哪来"):
  /// - 四六级写作:内容切题 / 组织连贯 / 语言准确 / 词汇丰富 / 句式多样;
  /// - 翻译:原文理解 / 译文准确 / 表达通顺;
  /// - 回译:还原英文原意(语义完整 / 用词 / 语法 / 地道);
  /// - 摘要:读后概括(要点覆盖 / 压缩 / 结构 / 语言)。
  static List<OutputRubric> builtin() => _builtin;

  /// 按 id 取内置 rubric(找不到返回 null,不抛 —— 数据库里可能存了个旧 id)
  static OutputRubric? byId(String id) {
    final key = id.trim();
    for (final rubric in _builtin) {
      if (rubric.id == key) return rubric;
    }
    return null;
  }

  static final List<OutputRubric> _builtin = <OutputRubric>[
    OutputRubric(
      id: 'cet4_writing',
      type: 'writing',
      scoringMode: ScoringMode.aiRubric,
      dimensions: const <RubricDimension>[
        RubricDimension(
          key: 'content',
          label: '内容切题',
          weight: 0.25,
          maxScore: 25,
          hint: '是否按题目要求展开?要点是否齐全、有没有跑题/漏要点?',
        ),
        RubricDimension(
          key: 'organization',
          label: '组织连贯',
          weight: 0.20,
          maxScore: 20,
          hint: '段落结构、衔接词、句间逻辑是否清楚?',
        ),
        RubricDimension(
          key: 'language',
          label: '语言准确',
          weight: 0.25,
          maxScore: 25,
          hint: '语法、拼写、标点是否正确?严重错误是否影响理解?',
        ),
        RubricDimension(
          key: 'vocabulary',
          label: '词汇丰富',
          weight: 0.15,
          maxScore: 15,
          hint: '用词是否准确、有变化?有没有中式表达/重复用词?',
        ),
        RubricDimension(
          key: 'sentence_variety',
          label: '句式多样',
          weight: 0.15,
          maxScore: 15,
          hint: '是否只有简单句?有没有从句/非谓语/倒装等有效变化?',
        ),
      ],
      bands: _cetWritingBands,
      promptTemplate:
          '按四六级写作 15 分制口径评分:内容切题、条理清楚、语言准确、'
          '词汇与句式有变化;折成 100 分制上报。',
    ),
    OutputRubric(
      id: 'cet4_translation',
      type: 'translation',
      scoringMode: ScoringMode.aiRubric,
      dimensions: const <RubricDimension>[
        RubricDimension(
          key: 'comprehension',
          label: '原文理解',
          weight: 0.30,
          maxScore: 30,
          hint: '是否读懂中文原句(含否定、限定、逻辑关系)?有没有理解错?',
        ),
        RubricDimension(
          key: 'accuracy',
          label: '译文准确',
          weight: 0.40,
          maxScore: 40,
          hint: '信息是否完整?有没有漏译、增译、误译?关键术语对不对?',
        ),
        RubricDimension(
          key: 'fluency',
          label: '表达通顺',
          weight: 0.30,
          maxScore: 30,
          hint: '英文是否自然连贯?有没有语法错误/中式英语/词性误用?',
        ),
      ],
      bands: _cetTranslationBands,
      promptTemplate:
          '按四六级翻译 15 分制口径评分:译文准确完整、通顺连贯、'
          '无重大语法错误;折成 100 分制上报。',
    ),
    OutputRubric(
      id: 'back_translation',
      type: 'back_translation',
      scoringMode: ScoringMode.aiRubric,
      dimensions: const <RubricDimension>[
        RubricDimension(
          key: 'fidelity',
          label: '忠实原意',
          weight: 0.35,
          maxScore: 35,
          hint: '用户回译是否还原了英文原句的意思(信息、限定、逻辑都算)?',
        ),
        RubricDimension(
          key: 'wording',
          label: '用词准确',
          weight: 0.25,
          maxScore: 25,
          hint: '关键词/固定搭配是否用对?有没有近义词误用?',
        ),
        RubricDimension(
          key: 'grammar',
          label: '语法正确',
          weight: 0.25,
          maxScore: 25,
          hint: '时态、语态、单复数、冠词、介词等是否正确?',
        ),
        RubricDimension(
          key: 'naturalness',
          label: '表达地道',
          weight: 0.15,
          maxScore: 15,
          hint: '语序与表达是否像母语者?有没有生硬直译?',
        ),
      ],
      bands: _backTranslationBands,
      promptTemplate:
          '评分目标是"还原英文原意":先看语义是否完整,再看用词/语法/'
          '地道程度;参考译文是**参照**不是唯一答案,同义表达也算对。',
    ),
    OutputRubric(
      id: 'summary',
      type: 'summary',
      scoringMode: ScoringMode.aiRubric,
      dimensions: const <RubricDimension>[
        RubricDimension(
          key: 'coverage',
          label: '要点覆盖',
          weight: 0.40,
          maxScore: 40,
          hint: '原文的主旨与关键支撑点是否都在?有没有把次要细节当重点?',
        ),
        RubricDimension(
          key: 'concision',
          label: '压缩概括',
          weight: 0.25,
          maxScore: 25,
          hint: '有没有照抄原句?是否用自己的话压缩到字数要求内?',
        ),
        RubricDimension(
          key: 'organization',
          label: '结构衔接',
          weight: 0.20,
          maxScore: 20,
          hint: '摘要本身是否连贯(先主旨、再要点)?衔接是否自然?',
        ),
        RubricDimension(
          key: 'language',
          label: '语言准确',
          weight: 0.15,
          maxScore: 15,
          hint: '语法/拼写/搭配是否准确?有没有因压缩导致句子不通?',
        ),
      ],
      bands: _summaryBands,
      promptTemplate:
          '评分目标是"读后概括":先看要点是否覆盖,再看压缩比、'
          '结构与语言;照抄原文过多要明显扣"压缩概括"分。',
    ),
  ];

  // 分档描述按类型分别写:同样 90 分,写作看"内容/结构/语言",翻译看"准确/通顺",
  // 摘要看"要点/压缩" —— 一套文案套所有类型,用户会觉得评分不走心。
  static const List<RubricBand> _cetWritingBands = <RubricBand>[
    RubricBand(
      minScore: 90,
      maxScore: 100,
      label: '优秀',
      description: '内容切题、结构清晰、语言基本无误、词汇与句式有明显变化(约 13~15 分档)',
    ),
    RubricBand(
      minScore: 75,
      maxScore: 90,
      label: '良好',
      description: '内容较切题、条理清楚,偶有语言错误但不影响理解(约 10~12 分档)',
    ),
    RubricBand(
      minScore: 60,
      maxScore: 75,
      label: '及格',
      description: '基本切题,语言错误较多但尚可理解,结构/词汇偏单一(约 7~9 分档)',
    ),
    RubricBand(
      minScore: 0,
      maxScore: 60,
      label: '待提高',
      description: '偏题或语言错误严重影响理解,篇幅明显不足(约 6 分及以下档)',
    ),
  ];

  static const List<RubricBand> _cetTranslationBands = <RubricBand>[
    RubricBand(
      minScore: 90,
      maxScore: 100,
      label: '优秀',
      description: '译文准确完整、通顺地道,几乎无语法错误(约 13~15 分档)',
    ),
    RubricBand(
      minScore: 75,
      maxScore: 90,
      label: '良好',
      description: '主要信息译出、表达基本通顺,有少量错误(约 10~12 分档)',
    ),
    RubricBand(
      minScore: 60,
      maxScore: 75,
      label: '及格',
      description: '基本译出但错误较多,部分表达生硬(约 7~9 分档)',
    ),
    RubricBand(
      minScore: 0,
      maxScore: 60,
      label: '待提高',
      description: '漏译/误译多,或大量中式英语导致难以理解(约 6 分及以下档)',
    ),
  ];

  static const List<RubricBand> _backTranslationBands = <RubricBand>[
    RubricBand(
      minScore: 90,
      maxScore: 100,
      label: '还原到位',
      description: '信息与限定完整、用词准确、语法基本无误、表达自然',
    ),
    RubricBand(
      minScore: 75,
      maxScore: 90,
      label: '基本还原',
      description: '主要意思对,但有 1~2 处用词/语法偏差',
    ),
    RubricBand(
      minScore: 60,
      maxScore: 75,
      label: '部分偏离',
      description: '大意能看出,但关键信息/限定丢失或句式明显错误',
    ),
    RubricBand(
      minScore: 0,
      maxScore: 60,
      label: '未还原',
      description: '意思偏离较大,或语法错误密集到影响理解',
    ),
  ];

  static const List<RubricBand> _summaryBands = <RubricBand>[
    RubricBand(
      minScore: 90,
      maxScore: 100,
      label: '优秀摘要',
      description: '要点齐全、高度压缩、结构清楚、语言准确',
    ),
    RubricBand(
      minScore: 75,
      maxScore: 90,
      label: '合格摘要',
      description: '主要要点在,略有冗余或个别要点遗漏',
    ),
    RubricBand(
      minScore: 60,
      maxScore: 75,
      label: '勉强可用',
      description: '要点不全或照抄原文较多,结构松散',
    ),
    RubricBand(
      minScore: 0,
      maxScore: 60,
      label: '需重写',
      description: '偏离原文主旨,或只是摘抄/篇幅严重不符',
    ),
  ];
}

// ═══════════════════════════════════════════════════════════════════════
// 评分结果
// ═══════════════════════════════════════════════════════════════════════

/// 一个维度的评分结果。
///
/// [score] 为 null = **模型没有给这一维的分数**(或给了无法解析的值)——
/// 界面显示"未评"而不是 0,0 分是"有依据地判 0",两者含义不同。
class ScoredDimension {
  final String key;
  final String label;
  final double? score;
  final double maxScore;

  /// 评分依据:必须是答案里的原句片段(照抄);没有依据时为空串
  final String evidence;

  const ScoredDimension({
    required this.key,
    required this.label,
    required this.maxScore,
    this.score,
    this.evidence = '',
  });

  bool get isScored => score != null;

  /// 是否有可展示的依据(空串 = 模型没给依据,UI 应提示"此项无依据")
  bool get hasEvidence => evidence.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'score': score,
    'max_score': maxScore,
    'evidence': evidence,
  };
}

/// 一条具体问题(用于结果页"逐条批改",可点原文定位)。
class ScoredIssue {
  /// 问题所在的原文片段(**照抄**答案,便于 UI 定位;空串 = 模型没给 span)
  final String span;

  /// 类型:语法 / 用词 / 拼写 / 语序 / 中式英语 / 衔接 / 其他
  final String type;

  /// 中文原因
  final String reason;

  /// 修改建议(英文;空串 = 无)
  final String suggestion;

  const ScoredIssue({
    required this.span,
    required this.type,
    required this.reason,
    this.suggestion = '',
  });

  Map<String, dynamic> toJson() => {
    'span': span,
    'type': type,
    'reason': reason,
    'suggestion': suggestion,
  };
}

/// 一次完整评分(对应数据库 `output_attempts.score_json`)。
class ScoredOutput {
  /// 总分:0 ~ [OutputRubric.totalScore](由各维度分相加得到,可解释)
  final double totalScore;

  /// 档位名(由 [bandOf] 按总分算,不信任模型自报的档位)
  final String bandLabel;

  final List<ScoredDimension> dimensions;
  final List<ScoredIssue> issues;

  /// 整段修改稿(模型只在"确实更优"时给;没有则 null)
  final String? correction;

  /// 中文总评(要求引用答案事实,不允许纯套话)
  final String summary;

  const ScoredOutput({
    required this.totalScore,
    required this.bandLabel,
    required this.dimensions,
    this.issues = const <ScoredIssue>[],
    this.correction,
    this.summary = '',
  });

  /// 有分数的维度数(UI 可据此显示"5 维中 4 维已评")
  int get ratedDimensionCount => dimensions.where((d) => d.isScored).length;

  Map<String, dynamic> toJson() => {
    'total_score': totalScore,
    'band_label': bandLabel,
    'dimensions': [for (final d in dimensions) d.toJson()],
    'issues': [for (final i in issues) i.toJson()],
    'correction': correction ?? '',
    'summary': summary,
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 纯函数:评分提示词
// ═══════════════════════════════════════════════════════════════════════

/// 生成评分提示词。
///
/// **核心纪律(用户点名)**:先给依据项、再给分。
/// 所以提示词里把"每个维度必须先写 evidence(答案原句),再写 score"写成
/// 硬约束,并明确"找不到依据的维度给 0 或留空,不许脑补" —— 这是这一层和
/// 旧"自由 0-100 批改"最大的区别。
///
/// [task] 题目要求 / 原句(中文题面或中英混合都行);
/// [answer] 用户作答;
/// [notes] 可选补充说明(如"这是回译练习,参考译文仅供参考")。
String buildScoringPrompt({
  required OutputRubric rubric,
  required String task,
  required String answer,
  String? notes,
}) {
  final buffer = StringBuffer()
    ..writeln(
      '你是严谨的英语${_typeLabel(rubric.type)}评分员。请按下面的评分标准'
      '给用户的作答打分,并**逐条给出依据**。',
    )
    ..writeln()
    ..writeln('【题目 / 要求】')
    ..writeln(task.trim().isEmpty ? '(未提供题目要求)' : task.trim())
    ..writeln()
    ..writeln('【用户作答】')
    ..writeln(answer.trim())
    ..writeln()
    ..writeln('【评分标准】总分 ${_numText(rubric.totalScore)} 分');
  for (final dimension in rubric.dimensions) {
    buffer.writeln(
      '- ${dimension.label}(${dimension.key},满分 ${_numText(dimension.maxScore)} 分):'
      '${dimension.hint.isEmpty ? '按该维度常规标准判断' : dimension.hint}',
    );
  }
  if (rubric.bands.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('【分档参考】(最终档位由总分决定,不需要你输出档位名)');
    for (final band in rubric.bands) {
      buffer.writeln(
        '- ${_numText(band.minScore)}~${_numText(band.maxScore)} '
        '${band.label}:${band.description}',
      );
    }
  }
  if (rubric.promptTemplate.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('【本评分标准的额外口径】')
      ..writeln(rubric.promptTemplate.trim());
  }
  final extra = notes?.trim() ?? '';
  if (extra.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('【补充说明】')
      ..writeln(extra);
  }
  buffer
    ..writeln()
    ..writeln('【评分纪律——违反任何一条都算错】')
    ..writeln('1. **先依据、后分数**:每个维度都必须先写 evidence,再写 score。')
    ..writeln(
      '2. evidence 必须是**用户作答里原样出现的片段**(照抄,不改写、不翻译);'
      '找不到可引用依据的维度,score 记 0,evidence 写"作答中无对应内容"。',
    )
    ..writeln('3. 每条维度分必须在该维度满分以内(0~满分),不许给负分或超满分。')
    ..writeln(
      '4. **禁止无依据打分**:不许凭印象给分;summary 也必须引用作答里的事实,'
      '不许只写"整体不错/继续努力"这类套话。',
    )
    ..writeln('5. issues 里的 span 必须照抄作答原文;定位不到原文的问题不要写。')
    ..writeln('6. correction 只在整段改写确实明显更好时给出,不得改变原意。')
    ..writeln('7. 只输出 JSON,不要解释、不要 Markdown 围栏以外的文字。')
    ..writeln()
    ..writeln('【输出格式】')
    ..writeln(
      '{"dimensions":[{"key":"${rubric.dimensions.isEmpty ? 'content' : rubric.dimensions.first.key}",'
      '"score":22,"evidence":"作答原文片段"}],'
      '"issues":[{"span":"原文片段","type":"语法|用词|拼写|语序|中式英语|衔接|其他",'
      '"reason":"中文原因","suggestion":"建议改法"}],'
      '"correction":"整段修改稿(没有就空串)","summary":"引用作答事实的中文总评"}',
    );
  return buffer.toString();
}

// ═══════════════════════════════════════════════════════════════════════
// 纯函数:评分结果解析
// ═══════════════════════════════════════════════════════════════════════

/// 解析模型返回的评分 JSON。
///
/// 容错清单(每一项都对应实测/线上会遇到的情况):
/// - 前后夹带说明("好的,以下是评分:")、```json 围栏 → 由 [extractJsonObject] 处理;
/// - 坏 JSON / 不是对象 / `dimensions` 完全缺失 → **返回 null**(调用方显示"评分失败,可重试");
/// - 维度 key 对不上 rubric(模型改名/漏维度)→ 该维度 `score=null`,
///   UI 显示"未评",**不编造分数**;
/// - score 是字符串("22分"/"22/25")→ 抠数字;越界 → clamp 到 0~满分;
/// - issues 里非 Map 元素/空 span → 跳过,不让一条脏数据毁掉整页。
///
/// 总分口径:**各维度分相加**,不信任模型自报的 `total_score` ——
/// 否则会出现"维度分加起来 60、模型说 85"这种无法解释的结果。
ScoredOutput? parseScoringResult(
  String content, {
  required OutputRubric rubric,
}) {
  if (content.trim().isEmpty) return null;
  final jsonText = extractJsonObject(content);
  if (jsonText.isEmpty) return null;
  Map<String, dynamic>? map;
  try {
    final decoded = jsonDecode(jsonText);
    if (decoded is Map) map = Map<String, dynamic>.from(decoded);
  } catch (e) {
    debugPrint('ReadFlow 评分结果不是合法 JSON(已忽略): ${_short(e)}');
    return null;
  }
  if (map == null) return null;

  // 模型返回的维度先建成 key → map 索引(大小写不敏感)
  final rawDimensions = map['dimensions'];
  final byKey = <String, Map<dynamic, dynamic>>{};
  if (rawDimensions is List) {
    for (final item in rawDimensions) {
      if (item is! Map) continue;
      final key = '${item['key'] ?? item['name'] ?? ''}'.trim().toLowerCase();
      if (key.isNotEmpty) byKey[key] = item;
    }
  }

  final dimensions = <ScoredDimension>[];
  var ratedCount = 0;
  var sum = 0.0;
  for (final dimension in rubric.dimensions) {
    final raw = byKey[dimension.key.toLowerCase()];
    final score = raw == null
        ? null
        : clampScore(raw['score'], dimension.maxScore);
    if (score != null) {
      ratedCount++;
      sum += score;
    }
    dimensions.add(
      ScoredDimension(
        key: dimension.key,
        label: dimension.label,
        maxScore: dimension.maxScore,
        score: score,
        evidence: raw == null ? '' : '${raw['evidence'] ?? ''}'.trim(),
      ),
    );
  }
  // 一个维度都没给分 = 这份"评分"没有任何可展示的依据 → 视为解析失败
  if (ratedCount == 0) return null;

  final total = clampScore(sum, rubric.totalScore) ?? 0;
  final band = bandOf(total, rubric.bands);

  final issues = <ScoredIssue>[];
  final rawIssues = map['issues'];
  if (rawIssues is List) {
    for (final item in rawIssues) {
      if (item is! Map) continue;
      final span = '${item['span'] ?? item['original'] ?? ''}'.trim();
      final reason = '${item['reason'] ?? item['explanation'] ?? ''}'.trim();
      if (span.isEmpty && reason.isEmpty) continue;
      issues.add(
        ScoredIssue(
          span: span,
          type: '${item['type'] ?? '其他'}'.trim(),
          reason: reason,
          suggestion: '${item['suggestion'] ?? item['correction'] ?? ''}'
              .trim(),
        ),
      );
    }
  }

  final correction = '${map['correction'] ?? ''}'.trim();
  final summary = '${map['summary'] ?? ''}'.trim();
  return ScoredOutput(
    totalScore: total,
    bandLabel: band?.label ?? '',
    dimensions: dimensions,
    issues: issues,
    correction: correction.isEmpty ? null : correction,
    summary: summary,
  );
}

/// 从文本里抠出 JSON 对象(模型常带前置说明/```围栏)。
///
/// 返回空串 = 找不到 JSON(调用方按解析失败处理,**不要**把原文塞给
/// `jsonDecode` 撞异常)。会顺手去掉尾逗号这种模型高频小错。
String extractJsonObject(String content) {
  var text = content.trim();
  if (text.isEmpty) return '';

  // ① 优先取 ```json ... ``` / ``` ... ``` 围栏里的内容(可能有多段,取第一段)
  final fence = RegExp(r'```(?:json|JSON)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) text = (fence.group(1) ?? '').trim();

  // ② 直接是 JSON 对象
  if (text.startsWith('{')) {
    final candidate = _stripTrailingCommas(text);
    if (_looksLikeJson(candidate)) return candidate;
  }

  // ③ 夹在说明文字里:取第一个 { 到最后一个 }(模型总爱写"好的,以下是评分:")
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    final candidate = _stripTrailingCommas(text.substring(start, end + 1));
    if (_looksLikeJson(candidate)) return candidate;
  }
  return '';
}

String _stripTrailingCommas(String source) =>
    // 只处理"逗号后面紧跟 } 或 ]"这种模型高频小错;不碰字符串里的逗号。
    source.replaceAllMapped(
      RegExp(r',(\s*[}\]])'),
      (match) => match.group(1) ?? '',
    );

bool _looksLikeJson(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map || decoded is List;
  } catch (_) {
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 纯函数:分数/档位
// ═══════════════════════════════════════════════════════════════════════

/// 分数归一(纯函数):
/// - null / 解析不出数字 → null(**不是 0**:0 分是"有依据地判 0");
/// - 字符串 "22分" / "22/25" → 22;
/// - 越界 → clamp 到 `[0, maxScore]`;
/// - 保留 1 位小数(模型偶发 22.3333,UI 上太吵)。
double? clampScore(Object? raw, double maxScore) {
  final value = _toDouble(raw, fallback: double.nan);
  if (value.isNaN || value.isInfinite) return null;
  final max = maxScore < 0 ? 0.0 : maxScore;
  final clamped = value.clamp(0.0, max).toDouble();
  return (clamped * 10).roundToDouble() / 10;
}

/// 按总分找档位(纯函数)。
///
/// 区间语义:`min <= score < max`,最高档包含 max(100 分落"优秀");
/// [bands] 乱序也安全(内部按 minScore 从高到低匹配);空列表返回 null。
RubricBand? bandOf(double score, List<RubricBand> bands) {
  if (bands.isEmpty) return null;
  final sorted = List<RubricBand>.from(bands)
    ..sort((a, b) => b.minScore.compareTo(a.minScore));
  for (final band in sorted) {
    if (score >= band.minScore) return band;
  }
  // 比最低档下界还低(脏数据制造的缝隙):归最低档,避免 UI 出现"无档位"
  return sorted.last;
}

// ═══════════════════════════════════════════════════════════════════════
// 小工具
// ═══════════════════════════════════════════════════════════════════════

String _typeLabel(String type) => switch (type) {
  'writing' => '写作',
  'translation' => '翻译',
  'back_translation' => '回译',
  'summary' => '摘要',
  _ => '输出',
};

/// 分值展示:整数不带 .0(25 而不是 25.0),非整数保留小数
String _numText(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(1);

double _toDouble(Object? raw, {double fallback = 0}) {
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(raw);
    if (match != null) {
      return double.tryParse(match.group(0)!) ?? fallback;
    }
  }
  return fallback;
}

String _short(Object? error) {
  final flat = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length > 120 ? '${flat.substring(0, 120)}…' : flat;
}
