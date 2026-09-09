import 'package:flutter/foundation.dart';
import '../config/constants.dart';

/// 生词/短语/句子模型
class Vocabulary {
  final int? id;
  final String word;
  final String? translation;
  final String? sourceBook;
  final String? sourcePage;
  final String? originalSentence;
  final String? photoPath;
  final String wordType; // word, phrase, sentence
  final int masteryLevel; // 0=新词, 1=学习中, 2=掌握
  final String? partOfSpeech; // 词性（单词专用）
  final String? grammarNote; // 语法分析（短语/句子专用）
  final String? phonetic; // 音标(v1.5.0,AI 补全生成,如 /ˈʌnˈfetəd/)
  final String? category; // 分类：教材/书籍/外刊/碎片文章/其他
  final String? materialPath; // 分层素材路径，如 '教材/新概念英语/第1册'
  final DateTime createdAt;
  final DateTime? updatedAt;

  Vocabulary({
    this.id,
    required this.word,
    this.translation,
    this.sourceBook,
    this.sourcePage,
    this.originalSentence,
    this.photoPath,
    this.wordType = 'word',
    this.masteryLevel = 0,
    this.partOfSpeech,
    this.grammarNote,
    this.phonetic,
    this.category,
    this.materialPath,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // ── SQLite ↔ Dart ──
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'word': word,
      'translation': translation,
      'source_book': sourceBook,
      'source_page': sourcePage,
      'original_sentence': originalSentence,
      'photo_path': photoPath,
      'word_type': wordType,
      'mastery_level': masteryLevel,
      'part_of_speech': partOfSpeech,
      'grammar_note': grammarNote,
      'phonetic': phonetic,
      'category': category ?? AppConstants.dbCategoryDefault,
      'material_path': materialPath,
      'created_at': createdAt.toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory Vocabulary.fromMap(Map<String, dynamic> map) {
    return Vocabulary(
      id: map['id'] as int?,
      word: map['word'] as String,
      translation: map['translation'] as String?,
      sourceBook: map['source_book'] as String?,
      sourcePage: map['source_page'] as String?,
      originalSentence: map['original_sentence'] as String?,
      photoPath: map['photo_path'] as String?,
      wordType: map['word_type'] as String? ?? 'word',
      masteryLevel: map['mastery_level'] as int? ?? 0,
      partOfSpeech: map['part_of_speech'] as String?,
      grammarNote: map['grammar_note'] as String?,
      phonetic: map['phonetic'] as String?,
      category: map['category'] as String?,
      materialPath: map['material_path'] as String?,
      createdAt: _tryParseDate(map['created_at']),
      updatedAt: map['updated_at'] != null
          ? _tryParseDate(map['updated_at'])
          : null,
    );
  }

  /// 哨兵值：传此值表示「设为 null」，区别于「不传（保留原值）」
  static const _sentinel = Object();

  Vocabulary copyWith({
    int? id,
    Object? word = _sentinel,
    Object? translation = _sentinel,
    Object? sourceBook = _sentinel,
    Object? sourcePage = _sentinel,
    Object? originalSentence = _sentinel,
    Object? photoPath = _sentinel,
    String? wordType,
    int? masteryLevel,
    Object? partOfSpeech = _sentinel,
    Object? grammarNote = _sentinel,
    Object? phonetic = _sentinel,
    Object? category = _sentinel,
    Object? materialPath = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Vocabulary(
      id: id ?? this.id,
      word: _unwrap(word, this.word) as String,
      translation: _unwrap(translation, this.translation) as String?,
      sourceBook: _unwrap(sourceBook, this.sourceBook) as String?,
      sourcePage: _unwrap(sourcePage, this.sourcePage) as String?,
      originalSentence: _unwrap(originalSentence, this.originalSentence) as String?,
      photoPath: _unwrap(photoPath, this.photoPath) as String?,
      wordType: wordType ?? this.wordType,
      masteryLevel: masteryLevel ?? this.masteryLevel,
      partOfSpeech: _unwrap(partOfSpeech, this.partOfSpeech) as String?,
      grammarNote: _unwrap(grammarNote, this.grammarNote) as String?,
      phonetic: _unwrap(phonetic, this.phonetic) as String?,
      category: _unwrap(category, this.category) as String?,
      materialPath: _unwrap(materialPath, this.materialPath) as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 哨兵 → 保留原值；否则 → 传什么用什么（包括 null）
  static Object? _unwrap(Object? value, Object? fallback) {
    return identical(value, _sentinel) ? fallback : value;
  }

  /// 安全解析日期，DB 损坏时 fallback 到 DateTime.now()，不让一条坏记录阻塞所有加载
  static DateTime _tryParseDate(dynamic raw) {
    if (raw is String) {
      try {
        return DateTime.parse(raw);
      } catch (_) {}
    }
    debugPrint('ReadFlow: bad date in DB, using DateTime.now()');
    return DateTime.now();
  }

  /// 词条显示文本：模型会把长句 word 词条化截断（输出开头 ~20 字符+省略号，
  /// 省略号形态不固定：…/.../⋯ 等），original_sentence 字段才是完整句子——
  /// word 含省略号且存在更长的完整句子时，回退显示完整句子。
  /// 注意：不能按长度回退——短语（如 "compound with"）word 天然短于原句，
  /// 按长度判断会把正常短语误回退成整个句子（v1.2.20 用户实测回归）。
  String get displayWordText {
    final w = word;
    final os = originalSentence;
    if ((w.contains('…') || w.contains('...') || w.contains('⋯')) &&
        os != null &&
        os.isNotEmpty &&
        os.length > w.length) {
      return os;
    }
    return w;
  }

  /// 显示用：单词 + 音标或简单标注
  String get displayLabel {
    if (wordType == 'sentence') {
      return word.length > 30 ? '${word.substring(0, 30)}…' : word;
    }
    return word;
  }

  /// 出处简要
  String get sourceSummary {
    if (sourceBook == null || sourceBook!.isEmpty) return '未标注出处';
    final sb = StringBuffer(sourceBook!);
    if (sourcePage != null && sourcePage!.isNotEmpty) {
      sb.write(' · p$sourcePage');
    }
    return sb.toString();
  }

  /// 掌握度标签
  String get masteryLabel {
    switch (masteryLevel) {
      case 0:
        return '新词';
      case 1:
        return '学习中';
      case 2:
        return '已掌握';
      default:
        return '新词';
    }
  }
}
