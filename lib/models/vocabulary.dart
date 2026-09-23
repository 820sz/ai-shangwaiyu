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
  /// 英式/美式音标(v2.0):词条同时给两套音标,发音音色可切换。
  /// 只填一边时另一边留空 —— 不强行复制,UI 按"有几边显示几边"处理。
  final String? phoneticUk;
  final String? phoneticUs;
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
    this.phoneticUk,
    this.phoneticUs,
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
      'phonetic': phonetic ?? phoneticUk ?? phoneticUs,
      'phonetic_uk': phoneticUk,
      'phonetic_us': phoneticUs,
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
      phonetic: _str(map['phonetic']),
      // v2.0:新列可能缺失(老库/自定义 SELECT),类型也可能是脏的 —— 一律退 null,
      // 绝不让一条脏记录把整个词表加载炸掉(fromMap 在列表路径上被高频调用)
      phoneticUk: _str(map['phonetic_uk']) ?? _str(map['phonetic']),
      phoneticUs: _str(map['phonetic_us']) ?? _str(map['phonetic']),
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
    Object? phoneticUk = _sentinel,
    Object? phoneticUs = _sentinel,
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
      phoneticUk: _unwrap(phoneticUk, this.phoneticUk) as String?,
      phoneticUs: _unwrap(phoneticUs, this.phoneticUs) as String?,
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

  /// 容错取字符串：非 String 类型(脏数据/列类型不对)→ null。
  /// 为什么不用 `as String?`：那会在类型不符时抛 TypeError,而 fromMap 跑在
  /// "加载全部词条"的循环里,一条脏记录就会白屏。
  static String? _str(dynamic raw) => raw is String ? raw : null;

  /// 英式音标(null = 没有,UI 据此决定显示几边)
  String? get phoneticsUk => _nonEmpty(phoneticUk) ?? _nonEmpty(phonetic);

  /// 美式音标
  String? get phoneticsUs => _nonEmpty(phoneticUs) ?? _nonEmpty(phonetic);

  /// 有没有任何音标可用
  bool get hasPhonetic => phoneticsUk != null || phoneticsUs != null;

  /// 显示用音标文本(v2.0):
  /// - 两边都有 → `英 /a/ · 美 /b/`
  /// - 只有一边 → 就显示那一边(**不加标签**,与 v1.5 的老样式一致;
  ///   只有单音标时标上"英/美"反而是误导,用户无从判断这是哪一套)
  /// - 两边都空 → null(调用方整块不渲染,不留空占位)
  String? get displayPhonetic {
    final uk = phoneticsUk;
    final us = phoneticsUs;
    if (uk != null && us != null) {
      // 两边实际是同一套(老数据回填会把 phonetic 同时补到两边)→ 按单音标显示
      if (uk == us) return uk;
      return '英 $uk · 美 $us';
    }
    return uk ?? us;
  }

  static String? _nonEmpty(String? raw) {
    final t = raw?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// 安全解析日期，DB 损坏时 fallback 到 DateTime.now()，不让一条坏记录阻塞所有加载
  static DateTime _tryParseDate(dynamic raw) {
    if (raw is String) {
      try {
        return DateTime.parse(raw);
      } catch (_) {}
    }
    // v1.9.0(审查 P1-8):回退到 epoch 而不是 now() —— 坏行被当成"今天"
    // 会排到列表最前、显示"今天存的",让用户以为数据错乱
    debugPrint('ReadFlow: bad date in DB, using epoch');
    return DateTime.fromMillisecondsSinceEpoch(0);
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

  /// 保存时间简短标签(v1.7.0):今天 / 昨天 / N天前 / YYYY/M/D。
  /// 保存时自动记录(created_at),列表与复习卡片据此显示"何时存的"。
  String get createdLabel {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(createdAt.year, createdAt.month, createdAt.day))
        .inDays;
    if (days <= 0) return '今天';
    if (days == 1) return '昨天';
    if (days < 30) return '$days 天前';
    return '${createdAt.year}/${createdAt.month}/${createdAt.day}';
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
