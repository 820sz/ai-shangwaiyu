import 'dart:convert';

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
      'source_sentences': encodeAnswers(sourceSentences),
      'reference_answers':
          referenceAnswers != null ? encodeAnswers(referenceAnswers!) : null,
      'user_answers':
          userAnswers != null ? encodeAnswers(userAnswers!) : null,
      'score': score,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// v1.9.0(审查 P1-8):字段级兜底,单行坏数据不再炸掉整页。
  factory Exercise.fromMap(Map<String, dynamic> map) {
    final refRaw = map['reference_answers'] as String?;
    return Exercise(
      id: map['id'] is int ? map['id'] as int : null,
      articleId: map['article_id'] is int ? map['article_id'] as int : 0,
      type: map['type'] as String? ?? 'back_translation',
      sourceSentences: decodeAnswers(map['source_sentences'] as String?)
          .whereType<String>()
          .toList(),
      referenceAnswers: refRaw != null
          ? decodeAnswers(refRaw).whereType<String>().toList()
          : null,
      userAnswers: map['user_answers'] != null
          ? decodeAnswers(map['user_answers'] as String?)
          : null,
      score: (map['score'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
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

  // ── 答案列表的编解码 ──

  /// 编码为 JSON(v1.9.0,审查 P2-3)。
  ///
  /// 旧实现用 `'|||'` 拼串冒充 JSON:用户答案里只要出现 `|||` 就会错位
  /// (得分与逐句对照全错),空串与"未作答"也不可区分。
  static String encodeAnswers(Iterable<String?> list) =>
      jsonEncode(list.map((s) => s ?? '').toList());

  /// 解码:**兼容历史 `'|||'` 数据**(老库里的行仍是旧格式),
  /// 新写入一律 JSON。坏数据返回空列表,不抛异常。
  static List<String?> decodeAnswers(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final trimmed = raw.trim();
    if (trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded.map((e) => e?.toString()).toList();
        }
      } catch (_) {
        // 落到旧格式分支
      }
    }
    return raw.split('|||').map((s) => s.isEmpty ? null : s).toList();
  }
}
