/// AI 生成的英语文章
class Article {
  final int? id;
  final String title;
  final String content;
  /// 全文中文翻译(与 content 段落一一对应,空行分隔)。旧文章无此数据。
  final String? translation;
  final List<int> vocabIds; // 文章包含的生词 ID 列表
  final DateTime createdAt;

  Article({
    this.id,
    required this.title,
    required this.content,
    this.translation,
    this.vocabIds = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'content': content,
      'translation': translation,
      'vocab_ids': vocabIds.join(','),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Article.fromMap(Map<String, dynamic> map) {
    final vocabStr = map['vocab_ids'] as String? ?? '';
    return Article(
      id: map['id'] as int?,
      title: map['title'] as String,
      content: map['content'] as String,
      translation: map['translation'] as String?,
      vocabIds: vocabStr.isEmpty
          ? []
          : vocabStr
              .split(',')
              .map((s) => int.tryParse(s.trim()) ?? 0)
              .where((n) => n > 0)
              .toList(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// 文章摘要
  String get summary =>
      content.length > 80 ? '${content.substring(0, 80)}…' : content;

  /// 段落拆分（按双换行）
  List<String> get paragraphs {
    return content
        .split('\n\n')
        .where((p) => p.trim().isNotEmpty)
        .toList();
  }

  /// 翻译段落拆分（与 paragraphs 索引一一对应；无翻译数据时为空列表）
  List<String> get translationParagraphs {
    if (translation == null || translation!.isEmpty) return const [];
    return translation!
        .split('\n\n')
        .where((p) => p.trim().isNotEmpty)
        .toList();
  }

  /// 生词数量
  int get vocabCount => vocabIds.length;
}
