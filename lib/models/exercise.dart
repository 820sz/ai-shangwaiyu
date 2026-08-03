/// 回译练习模型
class Exercise {
  final int? id;
  final int articleId;
  final String type; // back_translation
  final List<String> sourceSentences; // 题面(回译=中文句子)
  final List<String>? referenceAnswers; // 英文参考答案(新练习有,旧练习为 null)
  final List<String?>? userAnswers; // 用户回答（可为空）
  final double? score; // 得分（百分比）
  final DateTime createdAt;

  Exercise({
    this.id,
    required this.articleId,
    this.type = 'back_translation',
    required this.sourceSentences,
    this.referenceAnswers,
    this.userAnswers,
    this.score,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'article_id': articleId,
      'type': type,
      'source_sentences': _encodeJson(sourceSentences),
      'reference_answers':
          referenceAnswers != null ? _encodeJson(referenceAnswers!) : null,
      'user_answers':
          userAnswers != null ? _encodeJson(userAnswers!) : null,
      'score': score,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Exercise.fromMap(Map<String, dynamic> map) {
    final refRaw = map['reference_answers'] as String?;
    return Exercise(
      id: map['id'] as int?,
      articleId: map['article_id'] as int,
      type: map['type'] as String? ?? 'back_translation',
      sourceSentences: _decodeJsonList(map['source_sentences'] as String?)
          .whereType<String>()
          .toList(),
      referenceAnswers: refRaw != null
          ? _decodeJsonList(refRaw).whereType<String>().toList()
          : null,
      userAnswers: map['user_answers'] != null
          ? _decodeJsonList(map['user_answers'] as String?)
          : null,
      score: (map['score'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// 完成率（基于已作答数）
  double get completionRate {
    if (userAnswers == null) return 0;
    final answered =
        userAnswers!.where((a) => a != null && a.trim().isNotEmpty).length;
    return sourceSentences.isEmpty
        ? 0
        : answered / sourceSentences.length;
  }

  // ── 私有 JSON 编解码 ──
  static String _encodeJson(Iterable<String?> list) {
    return list.map((s) => s ?? '').join('|||');
  }

  static List<String?> _decodeJsonList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    return raw.split('|||').map((s) => s.isEmpty ? null : s).toList();
  }
}
