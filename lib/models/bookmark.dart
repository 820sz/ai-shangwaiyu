import '../config/constants.dart';

/// 收藏夹条目(v1.4.0 问题 8/9):
/// 追问的 AI 回答片段 / 识别结果的词汇卡片 —— 碎片知识收集,
/// 独立于生词本(vocabulary),不参与词汇量统计。
class Bookmark {
  final int? id;
  /// 来源:follow_up(追问答案)| vocab(词汇卡片)
  final String source;
  /// 摘要(列表显示,生成时截断;追问=首个标题行,词汇=原文)
  final String title;
  /// 完整内容(展示全文;词汇=原文+释义+例句拼接)
  final String content;
  /// 关联原文(词汇收藏=单词/短语)
  final String? sourceWord;
  /// 回答模型(追问收藏)
  final String? model;
  final DateTime createdAt;

  Bookmark({
    this.id,
    required this.source,
    required this.title,
    required this.content,
    this.sourceWord,
    this.model,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'source': source,
        'title': title,
        'content': content,
        'source_word': sourceWord,
        'model': model,
        'created_at': createdAt.toIso8601String(),
      };

  factory Bookmark.fromMap(Map<String, dynamic> map) => Bookmark(
        id: map['id'] as int?,
        source: map['source'] as String? ?? AppConstants.bookmarkSourceFollowUp,
        title: map['title'] as String? ?? '',
        content: map['content'] as String? ?? '',
        sourceWord: map['source_word'] as String?,
        model: map['model'] as String?,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}
