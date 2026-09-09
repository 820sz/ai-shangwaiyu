import 'dart:convert';

/// 写译练习日志(v1.6.0):每次批改可保存,按日期文件夹查阅复盘。
class WritingLog {
  final int? id;

  /// handwritten(手写档) / electronic(电子档)
  final String sourceType;
  final String originalText;
  final String? correctedText;
  final String? score;
  final String? summary;

  /// 逐条点评 [{original, correction, type, reason}]
  final List<Map<String, String>> issues;

  /// 四类汇总 {词汇, 语法, 表达优化, 其他}
  final Map<String, String> errorSummary;
  final String? model;

  /// 手写档图片来源(本地路径,便于回看原稿)
  final List<String> imagePaths;
  final DateTime createdAt;

  const WritingLog({
    this.id,
    required this.sourceType,
    required this.originalText,
    this.correctedText,
    this.score,
    this.summary,
    this.issues = const [],
    this.errorSummary = const {},
    this.model,
    this.imagePaths = const [],
    required this.createdAt,
  });

  static const categories = ['词汇', '语法', '表达优化', '其他'];

  /// 日期文件夹 key:2026-08-26
  String get dateKey {
    final m = createdAt.month.toString().padLeft(2, '0');
    final d = createdAt.day.toString().padLeft(2, '0');
    return '${createdAt.year}-$m-$d';
  }

  String get dateLabel =>
      '${createdAt.year}年${createdAt.month}月${createdAt.day}日';

  String get timeLabel =>
      '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';

  /// 列表标题:原文首行前 24 字
  String get title {
    final firstLine = originalText
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        .trim();
    if (firstLine.isEmpty) return '写译练习';
    return firstLine.length > 24 ? '${firstLine.substring(0, 24)}…' : firstLine;
  }

  int get issueCount => issues.length;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'source_type': sourceType,
    'original_text': originalText,
    'corrected_text': correctedText,
    'score': score,
    'summary': summary,
    'issues_json': jsonEncode(issues),
    'error_summary_json': jsonEncode(errorSummary),
    'model': model,
    'image_paths': imagePaths.join('\n'),
    'created_at': createdAt.toIso8601String(),
  };

  factory WritingLog.fromMap(Map<String, dynamic> map) {
    List<Map<String, String>> issues = [];
    try {
      final raw = jsonDecode((map['issues_json'] as String?) ?? '[]');
      if (raw is List) {
        issues = raw
            .whereType<Map>()
            .map(
              (e) => {
                for (final k in ['original', 'correction', 'type', 'reason'])
                  k: e[k]?.toString() ?? '',
              },
            )
            .toList();
      }
    } catch (_) {}
    Map<String, String> summary = {};
    try {
      final raw = jsonDecode((map['error_summary_json'] as String?) ?? '{}');
      if (raw is Map) {
        summary = {
          for (final c in categories) c: raw[c]?.toString() ?? '',
        };
      }
    } catch (_) {}
    final images = ((map['image_paths'] as String?) ?? '')
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    DateTime created;
    try {
      created = DateTime.parse(map['created_at'] as String);
    } catch (_) {
      created = DateTime.now();
    }
    return WritingLog(
      id: map['id'] as int?,
      sourceType: (map['source_type'] as String?) ?? 'electronic',
      originalText: (map['original_text'] as String?) ?? '',
      correctedText: map['corrected_text'] as String?,
      score: map['score'] as String?,
      summary: map['summary'] as String?,
      issues: issues,
      errorSummary: summary,
      model: map['model'] as String?,
      imagePaths: images,
      createdAt: created,
    );
  }
}
