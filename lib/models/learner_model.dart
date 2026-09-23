/// 学习者模型(v2.0):一切个性化的地基。
///
/// 与 v1.8.0 的 `LearnerProfile` 的区别(这是 2.0 的核心修正):
/// 1. **每个字段都带来源与置信度** —— `self`(用户自报)/`test`(测量得到)/
///    `inferred`(系统从行为推断)。界面上必须能区分这三者,否则又会退化成
///    "软件瞎猜用户水平"(v1.9 之前用生词本收藏数当水平标尺就是这个错误)。
/// 2. **词汇量是测量出来的**(自适应 Yes/No 测试 + 伪词校准),不是数收藏数。
/// 3. **已知词集合不落库**:由 `vocabEstimate` + 词频表推导
///    (名次 ≤ 估计值 ⇒ 推定认识),省掉几万条词的存储与同步问题。
/// 4. 记录 `missingFields` —— 导师据此决定"该问用户什么",而不是凭空猜。
library;

/// 字段来源
enum ProfileSource {
  /// 用户自己填的(自评水平普遍偏差 1-2 级,所以权重低于测量)
  self,

  /// 测量得到(词汇量测试等)
  test,

  /// 系统从行为数据推断(阅读覆盖率、复习正确率、写译错误率…)
  inferred;

  static ProfileSource parse(Object? raw) {
    final s = '$raw';
    return ProfileSource.values.firstWhere(
      (e) => e.name == s,
      orElse: () => ProfileSource.self,
    );
  }
}

/// 带来源与置信度的画像字段
class ProfileField<T> {
  final T value;
  final ProfileSource source;

  /// 0..1;自报一般 0.4-0.6,测量 0.8+,推断随样本量增长
  final double confidence;
  final DateTime updatedAt;

  ProfileField({
    required this.value,
    required this.source,
    double confidence = 0.5,
    DateTime? updatedAt,
  })  : confidence = confidence.clamp(0, 1).toDouble(),
        updatedAt = updatedAt ?? DateTime.now();

  ProfileField<T> copyWith({T? value, ProfileSource? source, double? confidence}) =>
      ProfileField<T>(
        value: value ?? this.value,
        source: source ?? this.source,
        confidence: confidence ?? this.confidence,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'source': source.name,
        'confidence': confidence,
        'updated_at': updatedAt.toIso8601String(),
      };

  /// 解析:`parse` 负责把 JSON 里的原始值转成 T(缺字段/类型不符时返回 null)。
  /// `parse` 抛异常也一律当"没有该字段"处理 —— 历史库里一条类型不对的记录
  /// 不能让整页画像崩掉(2.0 的画像同时来自用户输入、测试结果与推断,脏数据
  /// 的概率比 v1 高得多)。
  static ProfileField<T>? fromJson<T>(
    Object? raw,
    T? Function(Object? value) parse,
  ) {
    if (raw is! Map) return null;
    final T? v;
    try {
      v = parse(raw['value']);
    } catch (_) {
      return null;
    }
    if (v == null) return null;
    return ProfileField<T>(
      value: v,
      source: ProfileSource.parse(raw['source']),
      confidence: (raw['confidence'] as num?)?.toDouble() ?? 0.5,
      updatedAt: DateTime.tryParse('${raw['updated_at']}') ?? DateTime.now(),
    );
  }
}

/// 学习者模型(Hive 单行 JSON 持久化)
class LearnerModel {
  /// 词汇量估计(认识词数)—— 来自测试;`inferred` 时是长期推断值
  final ProfileField<int>? vocabEstimate;

  /// 估计区间下界/上界(测试给得出;自报时为空)
  final int? vocabLow;
  final int? vocabHigh;

  /// 水平档位(A1..C2)—— 优先取测试映射值
  final ProfileField<String>? cefr;

  /// 上次词汇量测试的时间与质量(伪词误报率:越高说明自评越不可信)
  final DateTime? lastPlacementAt;
  final double? falseAlarmRate;

  /// 学习目的(应试/工作/原版书/口语/兴趣…)
  final ProfileField<String>? goal;

  /// 每日可投入分钟数
  final ProfileField<int>? dailyMinutes;

  /// 偏好题材
  final ProfileField<List<String>>? interests;

  /// 题材黑名单(v2.0 决策:支持自选,推荐与导师选材一律遵守)
  final List<String> blockedTopics;

  /// 关键词黑名单(自由词,命中即过滤)
  final List<String> blockedKeywords;

  /// 扩展位:后续维度(语法薄弱点、阅读速度 wpm 等)先放这里,避免频繁改表
  final Map<String, dynamic> extras;

  LearnerModel({
    this.vocabEstimate,
    this.vocabLow,
    this.vocabHigh,
    this.cefr,
    this.lastPlacementAt,
    this.falseAlarmRate,
    this.goal,
    this.dailyMinutes,
    this.interests,
    this.blockedTopics = const [],
    this.blockedKeywords = const [],
    this.extras = const {},
  });

  LearnerModel copyWith({
    ProfileField<int>? vocabEstimate,
    int? vocabLow,
    int? vocabHigh,
    ProfileField<String>? cefr,
    DateTime? lastPlacementAt,
    double? falseAlarmRate,
    ProfileField<String>? goal,
    ProfileField<int>? dailyMinutes,
    ProfileField<List<String>>? interests,
    List<String>? blockedTopics,
    List<String>? blockedKeywords,
    Map<String, dynamic>? extras,
    // 清空开关:copyWith 用 `??` 兜底,不显式给开关就**无法把字段改回空**
    // (用户在设置页清掉目标/题材时必须能真的清掉)
    bool clearVocabBaseline = false,
    bool clearCefr = false,
    bool clearGoal = false,
    bool clearDailyMinutes = false,
    bool clearInterests = false,
  }) =>
      LearnerModel(
        vocabEstimate:
            clearVocabBaseline ? null : (vocabEstimate ?? this.vocabEstimate),
        vocabLow: clearVocabBaseline ? null : (vocabLow ?? this.vocabLow),
        vocabHigh: clearVocabBaseline ? null : (vocabHigh ?? this.vocabHigh),
        cefr: clearCefr ? null : (cefr ?? this.cefr),
        lastPlacementAt: clearVocabBaseline
            ? null
            : (lastPlacementAt ?? this.lastPlacementAt),
        falseAlarmRate:
            clearVocabBaseline ? null : (falseAlarmRate ?? this.falseAlarmRate),
        goal: clearGoal ? null : (goal ?? this.goal),
        dailyMinutes:
            clearDailyMinutes ? null : (dailyMinutes ?? this.dailyMinutes),
        interests: clearInterests ? null : (interests ?? this.interests),
        blockedTopics: blockedTopics ?? this.blockedTopics,
        blockedKeywords: blockedKeywords ?? this.blockedKeywords,
        extras: extras ?? this.extras,
      );

  /// 是否还没有任何"有依据"的水平信息(导师据此决定先安排测试)
  bool get hasVocabBaseline => (vocabEstimate?.value ?? 0) > 0;

  int? get vocab => vocabEstimate?.value;

  /// 导师要问的缺口(顺序即建议提问顺序)
  List<String> get missingFields {
    final out = <String>[];
    if (!hasVocabBaseline) out.add('词汇量基线(建议做一次词汇量测试)');
    if ((goal?.value ?? '').isEmpty) out.add('学习目的');
    if ((dailyMinutes?.value ?? 0) <= 0) out.add('每天可投入时间');
    if ((interests?.value ?? const []).isEmpty) out.add('偏好题材');
    return out;
  }

  /// 给 AI 的人话摘要(**只给结构化数据,不给原文**,隐私默认收紧)
  String get summaryText {
    final parts = <String>[];
    final v = vocabEstimate;
    if (v != null) {
      parts.add('词汇量:约 ${v.value} 词'
          '${vocabLow != null && vocabHigh != null ? '($vocabLow-$vocabHigh)' : ''}'
          '[${v.source.name}]');
    }
    if ((cefr?.value ?? '').isNotEmpty) parts.add('水平:${cefr!.value}[${cefr!.source.name}]');
    if ((goal?.value ?? '').isNotEmpty) parts.add('目的:${goal!.value}');
    if ((dailyMinutes?.value ?? 0) > 0) parts.add('每日可投入:${dailyMinutes!.value} 分钟');
    if ((interests?.value ?? const []).isNotEmpty) {
      parts.add('偏好题材:${interests!.value.join('、')}');
    }
    if (blockedTopics.isNotEmpty) parts.add('屏蔽题材:${blockedTopics.join('、')}');
    if (blockedKeywords.isNotEmpty) parts.add('屏蔽关键词:${blockedKeywords.join('、')}');
    if (falseAlarmRate != null) {
      parts.add('测试自评偏差:${(falseAlarmRate! * 100).toStringAsFixed(0)}%');
    }
    return parts.isEmpty ? '(用户尚未建立学习画像)' : parts.join(';');
  }

  Map<String, dynamic> toJson() => {
        if (vocabEstimate != null) 'vocab_estimate': vocabEstimate!.toJson(),
        if (vocabLow != null) 'vocab_low': vocabLow,
        if (vocabHigh != null) 'vocab_high': vocabHigh,
        if (cefr != null) 'cefr': cefr!.toJson(),
        if (lastPlacementAt != null)
          'last_placement_at': lastPlacementAt!.toIso8601String(),
        if (falseAlarmRate != null) 'false_alarm_rate': falseAlarmRate,
        if (goal != null) 'goal': goal!.toJson(),
        if (dailyMinutes != null) 'daily_minutes': dailyMinutes!.toJson(),
        if (interests != null) 'interests': interests!.toJson(),
        'blocked_topics': blockedTopics,
        'blocked_keywords': blockedKeywords,
        'extras': extras,
      };

  factory LearnerModel.fromJson(Map<String, dynamic> json) => LearnerModel(
        vocabEstimate: ProfileField.fromJson<int>(
          json['vocab_estimate'],
          (v) => v is int ? v : int.tryParse('$v'),
        ),
        vocabLow: json['vocab_low'] is int ? json['vocab_low'] as int : null,
        vocabHigh: json['vocab_high'] is int ? json['vocab_high'] as int : null,
        cefr: ProfileField.fromJson<String>(
          json['cefr'],
          (v) => v is String && v.isNotEmpty ? v : null,
        ),
        lastPlacementAt: DateTime.tryParse('${json['last_placement_at']}'),
        falseAlarmRate: (json['false_alarm_rate'] as num?)?.toDouble(),
        goal: ProfileField.fromJson<String>(
          json['goal'],
          (v) => v is String && v.isNotEmpty ? v : null,
        ),
        dailyMinutes: ProfileField.fromJson<int>(
          json['daily_minutes'],
          (v) => v is int ? v : int.tryParse('$v'),
        ),
        interests: ProfileField.fromJson<List<String>>(
          json['interests'],
          (v) => v is List ? v.map((e) => '$e').toList() : null,
        ),
        blockedTopics: ((json['blocked_topics'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        blockedKeywords: ((json['blocked_keywords'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
        extras: (json['extras'] is Map)
            ? Map<String, dynamic>.from(json['extras'] as Map)
            : const {},
      );
}
