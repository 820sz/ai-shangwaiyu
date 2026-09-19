/// AI 学习材料推荐(v1.8.0):「其他输入材料」真正可用的核心数据。
///
/// 推荐清单与"学习内容"都落库,下次进入直接读缓存,不再每次重新识别;
/// 学习内容可整篇转成文章进阅读器学习。
class MaterialRecommendation {
  final int? id;

  /// 分类(教材/书籍/外刊/碎片文章/其他)
  final String category;
  final String title;
  final String summary;

  /// 难度/水平标签(如 B1、四级、雅思 6.5)
  final String level;

  /// AI 给出"为什么推荐给你"的理由(结合画像 + 生词数据)
  final String reason;
  final String keywords;

  /// 学习内容正文(首次打开该推荐时流式生成并缓存)
  final String content;

  /// 生成本次推荐时使用的学习画像快照(便于复盘推荐依据)
  final String profileSnapshot;
  final DateTime createdAt;

  const MaterialRecommendation({
    this.id,
    required this.category,
    required this.title,
    this.summary = '',
    this.level = '',
    this.reason = '',
    this.keywords = '',
    this.content = '',
    this.profileSnapshot = '',
    required this.createdAt,
  });

  bool get hasContent => content.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'category': category,
    'title': title,
    'summary': summary,
    'level': level,
    'reason': reason,
    'keywords': keywords,
    'content': content,
    'profile_snapshot': profileSnapshot,
    'created_at': createdAt.toIso8601String(),
  };

  factory MaterialRecommendation.fromMap(Map<String, dynamic> map) =>
      MaterialRecommendation(
        id: map['id'] as int?,
        category: (map['category'] as String?) ?? '',
        title: (map['title'] as String?) ?? '',
        summary: (map['summary'] as String?) ?? '',
        level: (map['level'] as String?) ?? '',
        reason: (map['reason'] as String?) ?? '',
        keywords: (map['keywords'] as String?) ?? '',
        content: (map['content'] as String?) ?? '',
        profileSnapshot: (map['profile_snapshot'] as String?) ?? '',
        createdAt:
            DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
      );

  MaterialRecommendation copyWith({String? content, int? id}) =>
      MaterialRecommendation(
        id: id ?? this.id,
        category: category,
        title: title,
        summary: summary,
        level: level,
        reason: reason,
        keywords: keywords,
        content: content ?? this.content,
        profileSnapshot: profileSnapshot,
        createdAt: createdAt,
      );
}

/// 学习画像(v1.8.0):AI 推荐的个性化依据,用户可编辑并持久化。
class LearnerProfile {
  /// 水平档位
  final String level;

  /// 学习目的
  final String goal;

  /// 偏好题材(多选,存逗号分隔)
  final List<String> interests;

  /// 补充说明(自由文本)
  final String note;

  /// 是否已让用户确认过(未确认时进入推荐页会先引导填写)
  final bool confirmed;

  const LearnerProfile({
    this.level = '',
    this.goal = '',
    this.interests = const [],
    this.note = '',
    this.confirmed = false,
  });

  static const levelOptions = [
    '入门（A1-A2）',
    '初级（A2-B1）',
    '中级（B1-B2）',
    '中高级（B2-C1）',
    '高级（C1-C2）',
    '备考（四六级/考研）',
    '备考（雅思/托福）',
  ];

  static const goalOptions = [
    '读懂原版书',
    '应试提分',
    '日常工作/邮件',
    '口语交流',
    '看剧/听播客',
    '写作输出',
  ];

  static const interestOptions = [
    '小说故事',
    '新闻时事',
    '科普科技',
    '商业财经',
    '历史文化',
    '影视娱乐',
    '个人成长',
    '考试真题',
  ];

  bool get isEmpty =>
      level.isEmpty && goal.isEmpty && interests.isEmpty && note.isEmpty;

  LearnerProfile copyWith({
    String? level,
    String? goal,
    List<String>? interests,
    String? note,
    bool? confirmed,
  }) => LearnerProfile(
    level: level ?? this.level,
    goal: goal ?? this.goal,
    interests: interests ?? this.interests,
    note: note ?? this.note,
    confirmed: confirmed ?? this.confirmed,
  );

  Map<String, dynamic> toJson() => {
    'level': level,
    'goal': goal,
    'interests': interests,
    'note': note,
    'confirmed': confirmed,
  };

  factory LearnerProfile.fromJson(Map<String, dynamic> json) => LearnerProfile(
    level: (json['level'] as String?) ?? '',
    goal: (json['goal'] as String?) ?? '',
    interests: ((json['interests'] as List?) ?? const [])
        .map((e) => '$e')
        .toList(),
    note: (json['note'] as String?) ?? '',
    confirmed: (json['confirmed'] as bool?) ?? false,
  );

  /// 给 AI 的人话摘要
  String get summaryText {
    final parts = <String>[];
    if (level.isNotEmpty) parts.add('水平:$level');
    if (goal.isNotEmpty) parts.add('目的:$goal');
    if (interests.isNotEmpty) parts.add('偏好题材:${interests.join('、')}');
    if (note.isNotEmpty) parts.add('补充:$note');
    return parts.isEmpty ? '(用户尚未填写学习画像)' : parts.join(';');
  }
}
