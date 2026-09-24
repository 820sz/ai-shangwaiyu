import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 一个词**在哪儿出现过**(v2.4,B4 用户要求)。
///
/// 用户原话:"同一个词反复出现应改为出现次数的记录 —— 比如 apple(×2),
/// 词汇本里把每次出现的地方都列出来,这样也能起到加强记忆的作用"。
///
/// 为什么单独成结构而不是拼字符串:同一本书不同页、不同材料里的同一句,
/// 都需要**分别**记住;拼成一句话以后就没法去重、也没法按出处跳回去看。
class VocabOccurrence {
  /// 出处材料/书名(可能为空 —— 用户没标出处时)
  final String book;

  /// 页码/章节(可能为空)
  final String page;

  /// 该词所在的完整句子(用户要求"把每次出现的地方都列出来",句子最有记忆价值)
  final String sentence;

  /// 记录时间(第一次收进这个词条 / 又见到一次的时刻)
  final DateTime at;

  const VocabOccurrence({
    this.book = '',
    this.page = '',
    this.sentence = '',
    required this.at,
  });

  /// 去重键:同一本书 + 同一页 + 同一句 = 同一次出现
  /// (不比较时间:同一次出现被记两次不该算两次)
  String get key => '${book.trim()}|${page.trim()}|${sentence.trim()}';

  bool get isEmpty => book.trim().isEmpty && page.trim().isEmpty && sentence.trim().isEmpty;

  /// 一行人话出处:`《新概念3》· p12` / `p12` / `未标注出处`
  String get label {
    final p = page.trim();
    // 页码可能已经是 `p12`/`p16-17`(库里做过归一),也可能只是 `12` —— 别重复加 p
    final pageText = p.isEmpty
        ? ''
        : (RegExp(r'^[pP]\d').hasMatch(p) ? p : 'p$p');
    final parts = <String>[
      if (book.trim().isNotEmpty) book.trim(),
      if (pageText.isNotEmpty) pageText,
    ];
    return parts.isEmpty ? '未标注出处' : parts.join(' · ');
  }

  Map<String, Object?> toJson() => {
        if (book.trim().isNotEmpty) 'book': book.trim(),
        if (page.trim().isNotEmpty) 'page': page.trim(),
        if (sentence.trim().isNotEmpty) 'sentence': sentence.trim(),
        'at': at.toIso8601String(),
      };

  /// 坏数据一律跳过(返回 null)—— 词条加载在列表路径上,不能被一条脏 JSON 拖死
  static VocabOccurrence? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = DateTime.tryParse('${raw['at'] ?? ''}');
    final occ = VocabOccurrence(
      book: '${raw['book'] ?? ''}',
      page: '${raw['page'] ?? ''}',
      sentence: '${raw['sentence'] ?? ''}',
      at: at ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
    return occ.isEmpty ? null : occ;
  }

  /// 列表 ↔ JSON 文本(存 DB 的 occurrences_json 列)
  static String encodeList(List<VocabOccurrence> list) => jsonEncode([
        for (final o in list)
          if (!o.isEmpty) o.toJson(),
      ]);

  static List<VocabOccurrence> decodeList(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (VocabOccurrence.fromJson(item) case final VocabOccurrence o) o,
      ];
    } catch (e) {
      debugPrint('ReadFlow 出现记录解析失败(忽略该字段): $e');
      return const [];
    }
  }
}
