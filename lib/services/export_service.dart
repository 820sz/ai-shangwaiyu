import 'dart:convert';

import '../models/learner_model.dart';
import '../models/vocabulary.dart';
import 'fsrs.dart';

/// 导出与备份的**纯函数层**(v2.2「生产力」)。
///
/// 为什么先做导出/备份:
/// 1. 这个 App 的设计是"数据只在这台手机上"(系统备份已关闭),所以**导出是
///    用户唯一的数据主权出口** —— 换机、丢机、手滑清数据都靠它;
/// 2. 生词本导出成 CSV / Anki 格式,让用户能把资产搬到别的工具里(不被本项目锁死);
/// 3. 全部是纯函数:格式化、转义、解析都能单测 —— 备份这种东西"写错一个引号"
///    就等于数据丢了。
/// 阅读包里的一段正文。
///
/// 为什么不直接用 `MaterialChunk`:导出是**纯函数层**,不该依赖抓取层的
/// 网络/切块实现;调用方映射一下字段即可,测试也能直接造数据。
class ExportParagraph {
  const ExportParagraph({this.title, required this.text});

  final String? title;
  final String text;
}

class ExportService {
  ExportService._();

  /// 旧格式版本(`version` 字段):导入侧据此判断兼容性。
  ///
  /// 保持 1 不动是有意的兼容设计:v2 备份**同时**写 `version: 1` 与
  /// `backupVersion: 2` —— 旧版 App(v2.20 及以前)只认 `version`,于是它会把
  /// v2 备份当 v1 读:恢复生词/画像/设置、忽略 `tables`(未知键) —— 不崩、不丢
  /// 它能理解的那部分数据。向后兼容靠的就是"旧字段语义不变"。
  static const int backupVersion = 1;

  /// 备份**格式**版本(新字段 `backupVersion`)。
  ///
  /// - v1:只有生词本/复习状态/学习画像/少量设置(历史格式,无 `backupVersion` 字段);
  /// - v2(2026-11-02,批 8 · P2-7):额外带 `tables` —— 阅读器译文、输出题组/题目/
  ///   作答、能力快照、任务事件、任务、错误标签、复习状态原表、rubrics;
  ///   以及 `truncation`(哪些表被截断、备份时共多少条)。
  ///
  /// 为什么加**新字段**而不是把 `version` 升到 2:见 [backupVersion] 的注释 ——
  /// 升老字段会让旧版 App 直接拒绝导入整份备份(用户从新手机退不回旧手机)。
  static const int currentBackupVersion = 2;

  /// Excel 打开中文 CSV 需要 BOM(否则乱码);JSON 不需要
  static const String utf8Bom = '\uFEFF';

  // ── ① 生词本 CSV(人看 / Excel) ──

  /// 列:单词,释义,词性,英式音标,美式音标,类型,掌握度,复习状态,来源书籍,页码,分类,收录时间
  static String vocabCsv(
    List<Vocabulary> vocab, {
    Map<int, FsrsCard> cards = const {},
    bool withBom = true,
  }) {
    final sb = StringBuffer();
    if (withBom) sb.write(utf8Bom);
    sb.writeln([
      '单词',
      '释义',
      '词性',
      '英式音标',
      '美式音标',
      '类型',
      '掌握度',
      '复习状态',
      '来源书籍',
      '页码',
      '分类',
      '收录时间',
    ].map(_csvField).join(','));
    for (final v in vocab) {
      final card = v.id == null ? null : cards[v.id!];
      sb.writeln([
        v.word,
        v.translation ?? '',
        v.partOfSpeech ?? '',
        v.phoneticUk ?? v.phonetic ?? '',
        v.phoneticUs ?? v.phonetic ?? '',
        _typeLabel(v.wordType),
        _masteryLabel(v.masteryLevel),
        _reviewLabel(card),
        v.sourceBook ?? '',
        v.sourcePage ?? '',
        v.category ?? '',
        _date(v.createdAt),
      ].map(_csvField).join(','));
    }
    return sb.toString();
  }

  /// RFC 4180:含逗号/引号/换行的字段要加引号,内部引号翻倍
  static String _csvField(String raw) {
    final needsQuote =
        raw.contains(',') || raw.contains('"') || raw.contains('\n') || raw.contains('\r');
    if (!needsQuote) return raw;
    return '"${raw.replaceAll('"', '""')}"';
  }

  // ── ② Anki 导入用 TSV ──

  /// Anki "导入文件"默认按 Tab 分列:正面 \t 背面 \t 标签。
  /// 字段内的换行按 Anki 惯例换成 `<br>`(否则一行变两行、整份导入错位)。
  static String vocabAnkiTsv(List<Vocabulary> vocab) {
    final sb = StringBuffer();
    for (final v in vocab) {
      final front = _anki(v.word);
      final back = _anki([
        if ((v.translation ?? '').isNotEmpty) v.translation!,
        if ((v.partOfSpeech ?? '').isNotEmpty) '(${v.partOfSpeech})',
        if ((v.phoneticUk ?? v.phonetic) != null) '英 /${v.phoneticUk ?? v.phonetic}/',
        if ((v.phoneticUs ?? v.phonetic) != null) '美 /${v.phoneticUs ?? v.phonetic}/',
        if ((v.originalSentence ?? '').isNotEmpty) v.originalSentence!,
      ].join('<br>'));
      final tags = <String>[
        'readflow',
        _typeLabel(v.wordType),
        _masteryLabel(v.masteryLevel),
        if ((v.category ?? '').isNotEmpty) v.category!,
      ].join(' ');
      sb.writeln('$front\t$back\t$tags');
    }
    return sb.toString();
  }

  static String _anki(String raw) =>
      raw.replaceAll('\r\n', '<br>').replaceAll('\n', '<br>').replaceAll('\t', ' ');

  // ── ③ 完整备份(可回导) ──

  /// 生成备份 JSON。
  /// 包含:词条(含双音标) + 复习状态(FSRS 卡片) + 学习者模型 + 少量设置白名单。
  /// **不含** API Key(那是用户自己的密钥,不该出现在导出文件里)。
  ///
  /// v2 起额外带 [tables]:v3 新表的**原样行数据**。为什么不做强类型建模 ——
  /// 这些表的列会随版本演进(例如 tutor_tasks 从 9 列扩到 16 列),备份层的契约
  /// 是"原样搬运 + 恢复侧按白名单取列",宽进宽出比给每一列建模更不容易漏数据。
  static String backupJson({
    required List<Vocabulary> vocab,
    required Map<int, FsrsCard> cards,
    required LearnerModel model,
    Map<String, String> settings = const {},
    Map<String, List<Map<String, Object?>>> tables = const {},
    Map<String, Object?> truncation = const {},
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final payload = {
      'version': backupVersion,
      // 新字段:格式版本。旧版 App 不认它 → 只会恢复 `vocab`/`learner_model`,
      // 忽略 `tables`;新版 App 认它 → 决定要不要碰 v3 新表(见 parseBackup)。
      'backupVersion': currentBackupVersion,
      'app': 'readflow',
      'exported_at': at.toIso8601String(),
      'counts': {
        'vocab': vocab.length,
        'review_cards': cards.length,
        // 各表条数也写进 counts:用户/支持人员打开 JSON 一眼能看到备份装了什么
        for (final entry in tables.entries) entry.key: entry.value.length,
      },
      'vocab': [
        for (final v in vocab)
          {
            ...v.toMap(),
            if (v.id != null && cards[v.id!] != null)
              'review': _cardToJson(cards[v.id!]!),
          },
      ],
      'learner_model': model.toJson(),
      'settings': settings,
      'tables': tables,
      // 只在真的截断时出现:空对象写进去会让"没截断"和"不确定"分不清
      if (truncation.isNotEmpty) 'truncation': truncation,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  static Map<String, Object?> _cardToJson(FsrsCard c) => {
        'stability': c.stability,
        'difficulty': c.difficulty,
        'due_at': c.due.toIso8601String(),
        if (c.lastReview != null) 'last_review_at': c.lastReview!.toIso8601String(),
        'reps': c.reps,
        'lapses': c.lapses,
        if (c.lastRating != null) 'last_rating': c.lastRating!.value,
      };

  /// 解析备份(容错:坏 JSON / 缺字段 / 版本不符都要给可诊断结果,绝不抛)
  static BackupData parseBackup(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const BackupData(error: '内容为空');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      return const BackupData(error: '不是合法的 JSON(可能复制时被截断)');
    }
    if (decoded is! Map) {
      return const BackupData(error: '备份内容不是对象格式');
    }
    final map = Map<String, dynamic>.from(decoded);
    if ('${map['app'] ?? ''}' != 'readflow') {
      return const BackupData(error: '这不是本 App 的备份文件');
    }
    final version = map['version'] is int ? map['version'] as int : 0;
    if (version > backupVersion) {
      return BackupData(
        error: '备份来自更新版本的 App(v$version),请先升级再导入',
      );
    }
    // 格式版本:v2 起才有 `backupVersion`。**没有该字段 = v1 老备份** ——
    // 这是"旧备份继续能恢复"的判定点:只有 v2 才去读 tables,
    // 老备份连 `tables` 键都没有,自然走 v1 路径(与升级前行为完全一致)。
    final formatVersion = map['backupVersion'] is int
        ? map['backupVersion'] as int
        : 1;
    if (formatVersion > currentBackupVersion) {
      return BackupData(
        error: '备份来自更新版本的 App(备份格式 v$formatVersion),请先升级再导入',
      );
    }
    // 字段类型不对一律当空(备份导入的契约是"绝不抛":宁可少导入,
    // 也不能让用户在最需要它的时候看到一个英文类型错误)
    final rawVocab = map['vocab'];
    final vocabRows = rawVocab is List ? rawVocab : const [];
    final vocab = <Vocabulary>[];
    final cards = <String, FsrsCard>{}; // 以"词"为键:导入时词 id 会变
    for (final r in vocabRows) {
      if (r is! Map) continue;
      final row = Map<String, dynamic>.from(r);
      // 先自己检查必需字段:Vocabulary.fromMap 的 `word` 是硬转换(必需字段),
      // 一条缺词的坏行会直接抛异常 —— 备份导入不能因为一行坏数据整份失败
      final word = row['word'];
      if (word is! String || word.trim().isEmpty) continue;
      final review = row.remove('review');
      final Vocabulary v;
      try {
        v = Vocabulary.fromMap(row);
      } catch (_) {
        continue; // 其它字段类型不对也不该让整份备份失败
      }
      vocab.add(v);
      if (review is Map) {
        cards[v.word.toLowerCase()] =
            _cardFromJson(Map<String, dynamic>.from(review));
      }
    }
    LearnerModel? model;
    if (map['learner_model'] is Map) {
      try {
        model = LearnerModel.fromJson(
          Map<String, dynamic>.from(map['learner_model'] as Map),
        );
      } catch (_) {
        model = null;
      }
    }
    final settings = <String, String>{};
    if (map['settings'] is Map) {
      (map['settings'] as Map).forEach((k, v) {
        if (v is String) settings['$k'] = v;
      });
    }
    // v2 表数据:宽进 —— 只收"表名 → 行对象列表",行里字段类型不在这里校验
    // (恢复侧按白名单取列 + 事务兜底);一行坏数据不能毁掉整份备份的解析。
    final tables = <String, List<Map<String, Object?>>>{};
    final rawTables = map['tables'];
    if (rawTables is Map) {
      rawTables.forEach((key, value) {
        final name = '$key'.trim();
        if (name.isEmpty || value is! List) return;
        final rows = <Map<String, Object?>>[];
        for (final raw in value) {
          if (raw is Map) rows.add(Map<String, Object?>.from(raw));
        }
        tables[name] = rows;
      });
    }
    final truncation = map['truncation'] is Map
        ? Map<String, Object?>.from(map['truncation'] as Map)
        : const <String, Object?>{};
    return BackupData(
      version: version,
      backupVersion: formatVersion,
      exportedAt: DateTime.tryParse('${map['exported_at']}'),
      vocab: vocab,
      cardsByWord: cards,
      model: model,
      settings: settings,
      tables: tables,
      truncation: truncation,
    );
  }

  static FsrsCard _cardFromJson(Map<String, dynamic> j) {
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    final rating = j['last_rating'];
    return FsrsCard(
      stability: d(j['stability']),
      difficulty: d(j['difficulty']),
      due: DateTime.tryParse('${j['due_at']}') ?? DateTime.now(),
      lastReview: DateTime.tryParse('${j['last_review_at']}'),
      reps: i(j['reps']),
      lapses: i(j['lapses']),
      lastRating: rating is int ? FsrsRating.fromValue(rating) : null,
    );
  }

  // ── ④ 阅读包(Markdown) ──

  /// 把一份材料导成 Markdown「阅读包」:元信息 + 正文 + 生词表。
  ///
  /// 为什么要它:材料库里攒的都是**真实语料**,用户会想带走(存到网盘/笔记/打印)。
  /// 带上元信息(来源/许可/难度/覆盖率)和生词表,离线看也知道这份材料
  /// 从哪来、自己该注意哪些词 —— 这才叫"包",不是一堆裸文本。
  static String materialPackMarkdown({
    required String title,
    required List<ExportParagraph> chunks,
    String author = '',
    String source = '',
    String license = '',
    String url = '',
    String cefr = '',
    double? coverage,
    int? wordCount,
    int? estMinutes,
    List<String> newWords = const [],
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final b = StringBuffer();
    b.writeln('# $title');
    b.writeln();
    b.writeln('> 导出时间:${_dateTime(at)}');
    if (author.trim().isNotEmpty) b.writeln('> 作者/主播:${author.trim()}');
    if (source.trim().isNotEmpty) b.writeln('> 来源:${source.trim()}');
    if (url.trim().isNotEmpty) b.writeln('> 原文链接:${url.trim()}');
    if (license.trim().isNotEmpty) b.writeln('> 版权许可:${license.trim()}');
    final meta = <String>[
      if (wordCount != null && wordCount > 0) '$wordCount 词',
      if (estMinutes != null && estMinutes > 0) '约 $estMinutes 分钟',
      if (cefr.trim().isNotEmpty) '难度 $cefr',
      if (coverage != null) '已知词覆盖率 ${(coverage * 100).toStringAsFixed(1)}%',
    ];
    if (meta.isNotEmpty) b.writeln('> 篇幅与难度:${meta.join(' · ')}');
    b.writeln();
    b.writeln('---');
    b.writeln();
    for (final c in chunks) {
      final t = (c.title ?? '').trim();
      if (t.isNotEmpty) {
        b.writeln('## $t');
        b.writeln();
      }
      b.writeln(c.text.trim());
      b.writeln();
    }
    if (newWords.isNotEmpty) {
      b.writeln('---');
      b.writeln();
      b.writeln('## 生词表(${newWords.length} 个,阅读时优先留意)');
      b.writeln();
      for (var i = 0; i < newWords.length; i++) {
        b.writeln('${i + 1}. ${newWords[i]}');
      }
    }
    return b.toString();
  }

  static String _dateTime(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  // ── 文案映射(与 UI 共用同一份,避免导出结果与界面说法不一致) ──

  static String _typeLabel(String t) => switch (t) {
        'phrase' => '短语',
        'sentence' => '句子',
        _ => '单词',
      };

  static String _masteryLabel(int level) => switch (level) {
        2 => '已掌握',
        1 => '学习中',
        _ => '新词',
      };

  /// 复习状态文案:按**自然日**算(不是 24 小时窗口)。
  /// 用 `inDays` 直接截断会出偏差:距到期 4 天 23 小时会显示成"4 天后",
  /// 而"明天到期"的卡在临界时刻可能被算成"今天到期"—— 与复习页的分桶口径
  /// (自然日)不一致,用户会对不上号。
  static String _reviewLabel(FsrsCard? c) {
    if (c == null || c.isNew) return '未复习';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(c.due.year, c.due.month, c.due.day);
    final days = dueDay.difference(today).inDays;
    if (days < 0) return '已过期 ${-days} 天';
    if (days == 0) return '今天到期';
    return '$days 天后到期';
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 解析后的备份内容(导入用)
class BackupData {
  /// 旧 `version` 字段(v1 = 1);保留是为了兼容只认它的旧读者/旧代码
  final int version;

  /// 备份**格式**版本(v1/v2)。老备份没有该字段 → 1:
  /// 恢复路径只看它决定要不要碰 v3 新表(见 [backupVersion] 注释)。
  final int backupVersion;

  final DateTime? exportedAt;
  final List<Vocabulary> vocab;

  /// 以**小写词面**为键:导入后 id 会重新分配,只能按词对齐复习状态
  final Map<String, FsrsCard> cardsByWord;
  final LearnerModel? model;
  final Map<String, String> settings;

  /// v2 才有:v3 新表的原样行数据(表名 → 行)。为空 = 没有新表数据可恢复。
  final Map<String, List<Map<String, Object?>>> tables;

  /// v2 才有:导出时被截断的表的说明(表名 → {limit, total, exported})。
  /// 恢复时据此给用户一句"备份里的作答只保留最近 N 条"。
  final Map<String, Object?> truncation;

  /// 解析失败时的原因(非空即失败)
  final String? error;

  const BackupData({
    this.version = 0,
    this.backupVersion = 1,
    this.exportedAt,
    this.vocab = const [],
    this.cardsByWord = const {},
    this.model,
    this.settings = const {},
    this.tables = const {},
    this.truncation = const {},
    this.error,
  });

  bool get ok => error == null;

  String get summaryLine {
    if (!ok) return error!;
    final parts = <String>['${vocab.length} 个词'];
    if (cardsByWord.isNotEmpty) parts.add('${cardsByWord.length} 条复习状态');
    if (model != null) parts.add('学习画像');
    if (settings.isNotEmpty) parts.add('${settings.length} 项设置');
    // 让用户在"粘贴备份"这一步就看到这份备份带了哪些学习历史,
    // 而不是导入完才发现"怎么没有输出记录"
    final nonEmpty = [
      for (final entry in tables.entries)
        if (entry.value.isNotEmpty) entry,
    ];
    if (nonEmpty.isNotEmpty) {
      final total = nonEmpty.fold<int>(0, (sum, e) => sum + e.value.length);
      parts.add('$total 条 v3 学习记录(${nonEmpty.length} 张表)');
    }
    return parts.join(' · ');
  }
}
