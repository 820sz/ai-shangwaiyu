import '../config/constants.dart';

/// 识图会话快照:识别结果 + 全文翻译 + 追问消息。
///
/// 用户暂存后可退出结果页,再从「输入」页"继续上次会话"恢复;
/// 追问消息随会话一起保存,恢复后追问抽屉内容不丢失。
/// 图片文件复制到持久目录 `<documents>/sessions/<id>/`,
/// 结果里的 photoPath 在保存时重写为副本路径(缓存目录可能被系统清理)。
class SavedSession {
  final String id;
  final DateTime createdAt;
  final String analysisMode; // marked / fullText
  final String? sourceBook;
  final String? sourcePage;
  /// Vocabulary.toMap() 序列化(含重写后的 photoPath)
  final List<Map<String, dynamic>> results;
  /// 全文翻译模式:{original, translation}
  final List<Map<String, dynamic>> fullTextParagraphs;
  /// 追问消息:{role, content, reasoningText?}
  final List<Map<String, dynamic>> followUpMessages;

  const SavedSession({
    required this.id,
    required this.createdAt,
    required this.analysisMode,
    this.sourceBook,
    this.sourcePage,
    required this.results,
    required this.fullTextParagraphs,
    required this.followUpMessages,
  });

  /// 列表标题:首个词 + 词数
  String get title {
    final firstWord = results.isNotEmpty
        ? (results.first['word'] as String? ?? '')
        : '';
    final base = firstWord.isNotEmpty ? '「$firstWord…」' : '识图会话';
    return '$base · ${results.length} 词';
  }

  String get dateLabel =>
      '${createdAt.month}月${createdAt.day}日 '
      '${createdAt.hour.toString().padLeft(2, '0')}:'
      '${createdAt.minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'analysisMode': analysisMode,
        'sourceBook': sourceBook,
        'sourcePage': sourcePage,
        'results': results,
        'fullTextParagraphs': fullTextParagraphs,
        'followUpMessages': followUpMessages,
      };

  factory SavedSession.fromJson(Map<String, dynamic> json) => SavedSession(
        id: json['id'] as String,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        analysisMode: json['analysisMode'] as String? ??
            AppConstants.analysisModeMarked,
        sourceBook: json['sourceBook'] as String?,
        sourcePage: json['sourcePage'] as String?,
        results: (json['results'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        fullTextParagraphs: (json['fullTextParagraphs'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        followUpMessages: (json['followUpMessages'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}
