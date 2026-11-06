import 'package:flutter/foundation.dart';

import '../models/vocabulary.dart';
import 'database.dart';

/// 语境化素材来源(v2.16 · 批 3 · P1)。
///
/// ## 为什么要有这个文件
/// 用户对输出的核心要求是「**题目必须来自你读过的材料 + 你的薄弱点**」。
/// 改版前输出题的题目只有一处来源:生词本里的词与它自带的一句原句 ——
/// 于是练的永远是"收藏过的那几个词",跟刚读过的文章、刚犯的语法错没有关系。
///
/// 这一层只做**选素材**,不做题、不落库:
/// 1. 只读查询:从现有表里取"最近在学/入库的材料正文""active 错误标签"
///    (只用现有 `DatabaseService` 方法,不新增 SQL,不碰 task-11 正在加的题目表);
/// 2. 纯函数:分句、挑回译句、挑摘要段、挑写作用词、挑薄弱语法点、识别考试类型、
///    生成 UI 来源描述 —— 全部可单测、不联网、不碰 DB。
///
/// 出题器(批 3 后续)拿到这些素材后再交给 AI 加工;界面只在"来源"卡片上
/// 展示 [OutputSourceMaterial] 与 [describeSources] 的结果。

/// 一篇可用于出题的**材料正文快照**(已经从分块拼好、长度受控)。
///
/// 为什么只有这几个字段:出题需要的是"标题 + 正文 + 难度 + 覆盖率 + 类型",
/// 其余(materials 里的 url/license/封面等)属于材料中心,不该被输出模块依赖。
class OutputSourceMaterial {
  /// materials.id
  final int materialId;

  /// 展示用标题(优先中文译名,没有则英文原名)
  final String title;

  /// 拼接后的正文(已截断到 [kMaxCharsPerMaterial])
  final String text;

  /// 难度档(如 B1/B2;没分析过为空串)
  final String cefr;

  /// 词次覆盖率(0~1;没分析过为 null)
  final double? coverage;

  /// 材料类型(book/paper/news/podcast/wiki/article…)
  final String kind;

  const OutputSourceMaterial({
    required this.materialId,
    required this.title,
    required this.text,
    required this.cefr,
    required this.coverage,
    required this.kind,
  });

  /// 正文是否够用(拼出来是空串的材料不该出现在选题候选里)
  bool get hasText => text.trim().isNotEmpty;

  /// 正文长度(排序/截断提示用)
  int get textLength => text.length;

  @override
  String toString() =>
      'OutputSourceMaterial($materialId, $title, ${text.length} chars)';
}

/// 每篇材料拼进内存的正文上限。
///
/// 为什么不整本拼:公版书是几 MB 的全书,整本进内存 + 进 AI prompt 都会炸;
/// 2 万字符 ≈ 3000~4000 词,足够从中挑 5~10 个回译句/摘要段。
const int kMaxCharsPerMaterial = 20000;

/// 从已读材料/生词本/错误档案里取素材的**只读入口**。
///
/// 只调用 `DatabaseService` 已有方法:
/// - [OutputSourceService.recentMaterials] ← `getRecentMaterials` + `getMaterialChunks`
/// - [OutputSourceService.activeErrorTags]  ← `getErrorTags`
/// 没有新增 SQL、没有新增表(task-11 正在加的 exercise_* 表与本文件无关)。
class OutputSourceService {
  OutputSourceService._();

  /// 最近入库/在学材料的正文快照(新→旧),跳过正文为空的材料。
  ///
  /// 为什么用 `getRecentMaterials` 而不是 `getMaterials`:
  /// 它已经 LEFT JOIN 了阅读进度并按 `COALESCE(进度时间, 入库时间) DESC` 排 ——
  /// "刚读过的"会排在"只入库没打开的"前面,正好符合"语境化"要的优先级。
  static Future<List<OutputSourceMaterial>> recentMaterials({
    int limit = 5,
  }) async {
    if (limit <= 0) return const <OutputSourceMaterial>[];
    try {
      // 多取一些再过滤:正文为空/损坏的材料会被跳过,只取 limit 条可能不够
      final rows = await DatabaseService.getRecentMaterials(
        limit: limit * 3 < 30 ? limit * 3 : 30,
      );
      final out = <OutputSourceMaterial>[];
      for (final row in rows) {
        if (out.length >= limit) break;
        final id = _asInt(row['material_id'] ?? row['id']);
        if (id <= 0) continue;
        final text = await _materialText(id);
        if (text.trim().isEmpty) continue;
        final titleCn = '${row['title_cn'] ?? ''}'.trim();
        final title = titleCn.isNotEmpty
            ? titleCn
            : '${row['title'] ?? ''}'.trim();
        final coverage = _asDouble(row['coverage']);
        out.add(OutputSourceMaterial(
          materialId: id,
          title: title.isEmpty ? '未命名材料' : title,
          text: text,
          cefr: '${row['cefr'] ?? ''}'.trim(),
          coverage: coverage,
          kind: '${row['kind'] ?? 'article'}'.trim(),
        ));
      }
      return out;
    } catch (e) {
      debugPrint('ReadFlow 读取输出素材材料失败(当空处理): $e');
      return const <OutputSourceMaterial>[];
    }
  }

  /// 读 active 错误标签(失败/没有 active 时回退全部,由调用方再排序)。
  ///
  /// 为什么回退全部:`error_tags` 只有"复习答错"和"读后测验"两个写入方,
  /// 很多用户一条 active 都没有;此时返回空会让"薄弱点"永远空白,
  /// 而历史里可能仍有 status 变化过的 tag 可以展示(次数排序仍由纯函数做)。
  static Future<List<Map<String, Object?>>> activeErrorTags({
    int limit = 10,
  }) async {
    if (limit <= 0) return const <Map<String, Object?>>[];
    try {
      var rows = await DatabaseService.getErrorTags(status: 'active');
      if (rows.isEmpty) rows = await DatabaseService.getErrorTags();
      return rows.take(limit).toList(growable: false);
    } catch (e) {
      debugPrint('ReadFlow 读取错误标签失败(当空处理): $e');
      return const <Map<String, Object?>>[];
    }
  }

  /// 把某篇材料的正文分块按顺序拼起来,最多 [kMaxCharsPerMaterial] 字符。
  ///
  /// 分块之间用空行连接:下游的 `pickSummaryParagraphs` 正是按空行分段,
  /// 用换行连会把两段粘成一段、摘要素材就串味了。
  static Future<String> _materialText(int materialId) async {
    final chunks = await DatabaseService.getMaterialChunks(materialId);
    final buf = StringBuffer();
    for (final chunk in chunks) {
      if (buf.length >= kMaxCharsPerMaterial) break;
      final text = '${chunk['text'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      final remain = kMaxCharsPerMaterial - buf.length;
      buf.write(text.length <= remain ? text : text.substring(0, remain));
      buf.write('\n\n');
    }
    return buf.toString().trim();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 纯函数(可单测;不碰 DB、不联网)
// ═══════════════════════════════════════════════════════════════════════

/// 常见缩写:句点后面紧跟空格时**不当作句子结束**。
///
/// 只收"真实材料里高频"的一小撮 —— 收太多会把真正的句界也吃掉,
/// 收太少会把 `Mr. Smith` 切成两句。宁缺毋滥。
const Set<String> _abbreviations = <String>{
  'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'vs', 'etc',
  'e.g', 'i.e', 'cf', 'al', 'inc', 'ltd', 'co', 'no', 'fig', 'eq',
  'approx', 'dept', 'est', 'min', 'max', 'u.s', 'u.k', 'ph.d', 'a.m', 'p.m',
};

/// 残句开头(从句/连接词开头多半不是完整句子,不适合当回译题)
const Set<String> _fragmentStarters = <String>{
  'and', 'but', 'or', 'so', 'because', 'although', 'though', 'while',
  'which', 'that', 'who', 'whom', 'whose', 'if', 'when', 'where', 'as',
  'than', 'then', 'thus', 'hence', 'however', 'moreover', 'therefore',
};

/// 高频动词/助动词表:给"含完整主谓"的**粗判**用(不做句法分析)。
const Set<String> _verbCandidates = <String>{
  'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am',
  'has', 'have', 'had', 'do', 'does', 'did', 'will', 'would', 'can',
  'could', 'may', 'might', 'must', 'shall', 'should', 'need', 'dare',
  'make', 'makes', 'made', 'take', 'takes', 'took', 'get', 'gets', 'got',
  'give', 'gives', 'gave', 'go', 'goes', 'went', 'come', 'comes', 'came',
  'see', 'sees', 'saw', 'know', 'knows', 'knew', 'think', 'thinks', 'thought',
  'say', 'says', 'said', 'tell', 'tells', 'told', 'want', 'wants', 'wanted',
  'use', 'uses', 'used', 'find', 'finds', 'found', 'become', 'becomes',
  'show', 'shows', 'showed', 'leave', 'leaves', 'left', 'feel', 'feels',
  'put', 'mean', 'means', 'keep', 'keeps', 'let', 'begin', 'begins', 'began',
  'seem', 'seems', 'seemed', 'help', 'helps', 'helped', 'talk', 'talks',
  'turn', 'turns', 'start', 'starts', 'hear', 'hears', 'heard', 'play',
  'plays', 'run', 'runs', 'ran', 'move', 'moves', 'like', 'likes', 'liked',
  'live', 'lives', 'lived', 'believe', 'believes', 'bring',
  'brings', 'brought', 'happen', 'happens', 'write', 'writes', 'wrote',
  'provide', 'provides', 'sit', 'sits', 'sat', 'stand', 'stands', 'stood',
  'lose', 'loses', 'lost', 'pay', 'pays', 'paid', 'meet', 'meets', 'met',
  'include', 'includes', 'continue', 'continues', 'set', 'sets',
  'learn', 'learns', 'learnt', 'change', 'changes', 'lead', 'leads', 'led',
  'understand', 'understands', 'understood', 'watch', 'watches', 'follow',
  'follows', 'stop', 'stops', 'create', 'creates', 'speak', 'speaks', 'spoke',
  'read', 'reads', 'spend', 'spends', 'grow', 'grows', 'grew', 'open', 'opens',
  'walk', 'walks', 'win', 'wins', 'won', 'offer', 'offers', 'remember',
  'remembers', 'love', 'loves', 'consider', 'considers', 'appear', 'appears',
  'buy', 'buys', 'wait', 'waits', 'serve', 'serves', 'send', 'sends', 'sent',
  'expect', 'expects', 'build', 'builds', 'built', 'stay', 'stays', 'fall',
  'falls', 'fell', 'cut', 'cuts', 'reach', 'reaches', 'remain', 'remains',
  'require', 'requires', 'required', 'expose', 'exposes', 'cover', 'covers',
  'improve', 'improves', 'summarize', 'summarizes', 'reconstruct',
};

/// 稳健分句(英文 + 中文混排)。
///
/// 规则(为什么这么定):
/// 1. 句界:. ! ? 与中文 。！？;句点后紧跟字母/数字**不算**句界
///    —— 一次搞定小数点、域名/URL(`example.com`)、单字母缩写(`U.S`)。
/// 2. 常见缩写(`Mr.` `Dr.` `e.g.`)后面跟空格也不算句界,靠 [_abbreviations] 兜。
/// 3. 省略号 `...` 不算句界(连续句点第二个起直接跳过)。
/// 4. 换行是**软边界**:下一行以小写字母/逗号/分号开头 → 视为接行(把换行换成空格);
///    否则当硬断句。真实材料(Gutenberg / RSS)正文有按 70 列硬折行的习惯,
///    一律按换行断句会把一句话切成两半;而真正的段落间是**空行**,空行必然断开。
/// 5. 收尾引号/括号(`" ) ] 」`)吸附到当前句,不单独成句。
List<String> splitSentences(String text) {
  final raw = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (raw.trim().isEmpty) return const <String>[];
  final n = raw.length;
  final out = <String>[];
  final buf = StringBuffer();

  void flush() {
    final sentence = buf.toString().trim();
    buf.clear();
    if (sentence.isNotEmpty) out.add(sentence);
  }

  /// 句点前的一个 token 是否为缩写(含单大写字母缩写 `J.`)
  bool isAbbreviationBeforeDot() {
    final soFar = buf.toString().trimRight();
    final match = RegExp(r'([A-Za-z][A-Za-z.]*|\d+)$').firstMatch(soFar);
    if (match == null) return false;
    final token = match.group(1)!;
    if (_abbreviations.contains(token.toLowerCase())) return true;
    // 单个大写字母 + 点 = 人名首字母缩写(J. K. Rowling),不当句界
    return RegExp(r'^[A-Z]$').hasMatch(token);
  }

  var i = 0;
  while (i < n) {
    final ch = raw[i];

    // ── 换行:软/硬边界 ──
    if (ch == '\n') {
      var k = i + 1;
      while (k < n && (raw[k] == ' ' || raw[k] == '\t')) {
        k++;
      }
      if (k < n && raw[k] == '\n') {
        // 空行 = 真段落边界(硬断)
        flush();
        i = k + 1;
        continue;
      }
      if (k >= n) {
        flush();
        i = k;
        continue;
      }
      // 下一行以小写字母 / 逗号 / 分号 / 右括号开头 → 视为续行
      if (RegExp(r'[a-z,;:)\]]').hasMatch(raw[k])) {
        buf.write(' ');
        i = k;
        continue;
      }
      flush();
      i = k;
      continue;
    }

    // ── 终止符 ──
    if (ch == '.' || ch == '!' || ch == '?' || ch == '。' ||
        ch == '！' || ch == '？') {
      final prev = i > 0 ? raw[i - 1] : '';
      final next = i + 1 < n ? raw[i + 1] : '';
      var boundary = true;
      if (ch == '.') {
        if (prev == '.' || next == '.') {
          boundary = false; // 省略号
        } else if (next.isNotEmpty && RegExp(r'[0-9A-Za-z]').hasMatch(next)) {
          boundary = false; // 小数 / URL / 域名 / 缩写中间的点
        } else if (isAbbreviationBeforeDot()) {
          boundary = false; // Mr. / Dr. / e.g.
        }
      } else if (ch == '!' || ch == '?') {
        // URL 查询串里的 ? 后面紧接字母 → 不是句界(如 ...?x=1)
        if (next.isNotEmpty && RegExp(r'[0-9A-Za-z]').hasMatch(next)) {
          boundary = false;
        }
      }
      // 中文标点例外:。！？ 后面即使紧跟中文字也应当是句界(中文不写空格)
      if (ch == '。' || ch == '！' || ch == '？') {
        boundary = true;
      }

      buf.write(ch);
      if (!boundary) {
        i++;
        continue;
      }
      // 吸收紧跟的收尾引号/括号
      var j = i + 1;
      while (j < n && '”’"\')】」』'.contains(raw[j])) {
        buf.write(raw[j]);
        j++;
      }
      flush();
      i = j;
      continue;
    }

    buf.write(ch);
    i++;
  }
  flush();
  return out;
}

/// 从正文里挑适合**中→英回译**的句子。
///
/// 取舍(用户要的是"能写出来、值得写"的句子,不是随机一句):
/// - 长度 [minWords]~[maxWords] 词(太短没有语法含量,太长写不完);
/// - 粗判"完整主谓"([_looksLikeCompleteSentence]):排除从句片段/列表项;
/// - 去重(同一句在材料里出现多次只出一次);
/// - 保持**原文顺序**(回译题按文章前后出,学习者能顺着语境回忆);
/// - 数量不足时**放宽一轮**:长句上限翻倍 + 短句下限最多降 2 词,
///   仍不足就有多少给多少(不编句子)。
List<String> pickBackTranslationSentences(
  String text, {
  int count = 5,
  int minWords = 8,
  int maxWords = 32,
}) {
  if (count <= 0 || text.trim().isEmpty) return const <String>[];
  final safeMin = minWords < 2 ? 2 : minWords;
  final safeMax = maxWords < safeMin ? safeMin : maxWords;
  final sentences = splitSentences(text);
  if (sentences.isEmpty) return const <String>[];

  final pickedIndexes = <int>{};
  final seen = <String>{};

  void collect(int lo, int hi) {
    for (var i = 0; i < sentences.length; i++) {
      if (pickedIndexes.length >= count) return;
      if (pickedIndexes.contains(i)) continue;
      final sentence = sentences[i];
      final words = _latinWordCount(sentence);
      if (words < lo || words > hi) continue;
      if (!_looksLikeCompleteSentence(sentence)) continue;
      final key = _dedupeKey(sentence);
      if (key.isEmpty || !seen.add(key)) continue;
      pickedIndexes.add(i);
    }
  }

  collect(safeMin, safeMax);
  if (pickedIndexes.length < count) {
    // 放宽:长句允许到 2 倍上限;短句下限最多降到 4(再短就不是"写句"了)
    final relaxedMin = safeMin - 2 < 4 ? 4 : safeMin - 2;
    collect(relaxedMin, safeMax * 2);
  }

  final ordered = pickedIndexes.toList()..sort();
  return <String>[for (final i in ordered) sentences[i]];
}

/// 从正文里挑适合**摘要/段落翻译**的正文段。
///
/// 规则:
/// - 按**空行**分段(Gutenberg/RSS 的段落边界就是空行;单换行是折行,已粘回一句);
/// - 跳过标题(短、无句末标点、`Chapter 1`/`第3章`/纯大写等)与过短段;
/// - 总字数不超过 [maxChars];第一段本身超长时在句子/空格边界截断(不硬切单词);
/// - 保持原文顺序(摘要要按文章脉络给材料)。
List<String> pickSummaryParagraphs(String text, {int maxChars = 1500}) {
  if (maxChars <= 0 || text.trim().isEmpty) return const <String>[];
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final blocks = normalized.split(RegExp(r'\n[ \t]*\n'));
  final out = <String>[];
  var used = 0;

  for (final block in blocks) {
    if (used >= maxChars) break;
    // 段内单换行 = 折行 → 粘成空格;连续空白压成一个
    final paragraph = block
        .replaceAll(RegExp(r'[ \t]*\n[ \t]*'), ' ')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
    if (paragraph.isEmpty) continue;
    if (_looksLikeHeading(paragraph)) continue;
    if (_letterCount(paragraph) < 40) continue; // 过短(口号/目录/署名)

    final remain = maxChars - used;
    if (paragraph.length <= remain) {
      out.add(paragraph);
      used += paragraph.length;
      continue;
    }
    // 第一段就超长:截到上限(优先句末,其次空格),后面不再塞
    if (out.isEmpty) {
      out.add(_truncateAtBoundary(paragraph, remain));
      used = maxChars;
    }
    break;
  }
  return out;
}

/// 从生词本挑适合**写作用**的词。
///
/// 为什么不是"取生词本前 N 个":
/// - 过滤超短词(`a`/`of` 不值得出题)、超长词(写不出来的学术词反而挫败)、
///   专有名词/缩写(人名地名不能考"写作")、没有中文释义的词(出不了题面);
/// - **未掌握优先**(mastery 2 已掌握的词放后面,写了也没意义);
/// - 含空格短语**单独一档排在单词之后**:短语更值得练,但一次写对更难,
///   先用单词热身,余量再给短语;
/// - 按长度接近 9 个字符排序(写作常用的中长词区间),长度只是弱排序键。
List<String> pickWritingVocab(List<Vocabulary> vocab, {int count = 8}) {
  if (count <= 0 || vocab.isEmpty) return const <String>[];
  final singles = <String>[];
  final phrases = <String>[];
  final seen = <String>{};

  for (final v in vocab) {
    final word = v.word.trim();
    if (word.isEmpty) continue;
    if (word.length < 3 || word.length > 24) continue;
    if (!RegExp(r'[A-Za-z]').hasMatch(word)) continue; // 纯中文/数字/符号
    if ((v.translation ?? '').trim().isEmpty) continue; // 没释义就没法出题
    if (_looksLikeProperNoun(word)) continue;
    final key = word.toLowerCase();
    if (!seen.add(key)) continue;
    final isPhrase =
        v.wordType == 'phrase' || RegExp(r'\s').hasMatch(word);
    if (isPhrase) {
      phrases.add(word);
    } else {
      singles.add(word);
    }
  }

  _sortWritingCandidates(singles, vocab);
  _sortWritingCandidates(phrases, vocab);

  final out = <String>[];
  for (final bucket in <List<String>>[singles, phrases]) {
    for (final word in bucket) {
      if (out.length >= count) return out;
      out.add(word);
    }
  }
  return out;
}

/// 按"掌握度低优先 → 长度接近 9 字符 → 字母序"给写作候选排序。
///
/// 用原词表反查掌握度(候选列表里只有字符串,避免再带一个包装类)。
void _sortWritingCandidates(List<String> candidates, List<Vocabulary> vocab) {
  int masteryOf(String word) {
    final lower = word.toLowerCase();
    for (final v in vocab) {
      if (v.word.trim().toLowerCase() == lower) {
        return v.masteryLevel.clamp(0, 2);
      }
    }
    return 0;
  }

  candidates.sort((a, b) {
    final byMastery = masteryOf(a).compareTo(masteryOf(b));
    if (byMastery != 0) return byMastery;
    final byLength =
        (a.length - 9).abs().compareTo((b.length - 9).abs());
    if (byLength != 0) return byLength;
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
}

/// 从错误标签里挑**高频/复发**的语法点(返回 tag 中文名原样)。
///
/// - 同一个 tag 可能来自不同 source(复习/读后测验/写译),这里**合并计次** ——
///   "时态错 8 次"比"两个来源各 4 次"更像用户能理解的薄弱点;
/// - `status == fixed` 的不算(已经改好,不该再建议练);
/// - 排序:次数降序 → 最近一次更近的优先(次数相同看复发时间);
/// - 不改写 tag 文本(错误档案里的中文名是唯一事实源,UI 别自己翻译)。
List<String> weakGrammarPoints(
  List<Map<String, Object?>> errorTags, {
  int limit = 5,
}) {
  if (limit <= 0 || errorTags.isEmpty) return const <String>[];
  final aggregated = <String, _TagStat>{};

  for (final row in errorTags) {
    final tag = '${row['tag'] ?? ''}'.trim();
    if (tag.isEmpty) continue;
    final status = '${row['status'] ?? 'active'}'.trim().toLowerCase();
    if (status == 'fixed') continue;
    final count = _asInt(row['count']);
    final lastAt = DateTime.tryParse('${row['last_at'] ?? ''}');
    final stat = aggregated.putIfAbsent(tag, () => _TagStat(tag));
    stat.count += count > 0 ? count : 1;
    if (lastAt != null &&
        (stat.lastAt == null || lastAt.isAfter(stat.lastAt!))) {
      stat.lastAt = lastAt;
    }
  }

  final stats = aggregated.values.toList()
    ..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      final at = a.lastAt;
      final bt = b.lastAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

  return stats.take(limit).map((s) => s.tag).toList(growable: false);
}

/// 目标考试统一值(UI 筛选 chip / 出题器分支用;未知 = null)
const List<String> targetExamValues = <String>[
  'cet4',
  'cet6',
  'kaoyan',
  'ielts',
  'toefl',
  'nce',
];

/// 从多选目标里识别**目标考试类型**;识别不出返回 null(不猜)。
///
/// 取值:[targetExamValues] 六个之一。
/// 识别口径(中英混合都认):
/// - 先认"更具体"的:六级/雅思/托福/考研/新概念;
/// - `四六级` 本身**区分不了四还是六**,作为兜底记为 `cet4`(多数人先考四级;
///   若同批目标里还选了更具体的目标,以更具体的为准,轮询顺序在下面注明);
/// - 英文写法认 `CET-4`/`CET6`/`IELTS`/`TOEFL`/`NCE`(大小写、空格、连字符都忽略)。
///
/// 实现是**两趟**:第一趟扫显式目标(六级/雅思/考研…),第二趟才用泛化目标兜底,
/// 所以 `['四六级','雅思']` 会得到 ielts 而不是 cet4 —— 泛化目标不该压过明确目标。
String? targetExamOf(List<String> examGoals) {
  String? generic;
  for (final raw in examGoals) {
    final s = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_/]+'), '')
        .trim();
    if (s.isEmpty) continue;

    // 泛化"四六级":无法区分,先记着,等明确目标扫完再兜底
    if (s.contains('四六级') || s.contains('cet') && s.contains('46')) {
      generic ??= 'cet4';
      continue;
    }
    if (s.contains('六级') || s.contains('cet6') || s.contains('band6')) {
      return 'cet6';
    }
    if (s.contains('四级') || s.contains('cet4') || s.contains('band4')) {
      return 'cet4';
    }
    if (s.contains('考研') || s.contains('kaoyan') || s.contains('postgraduate')) {
      return 'kaoyan';
    }
    if (s.contains('雅思') || s.contains('ielts')) return 'ielts';
    if (s.contains('托福') || s.contains('toefl')) return 'toefl';
    if (s.contains('新概念') ||
        s.contains('newconcept') ||
        s.contains('nce')) {
      return 'nce';
    }
    // 纯 "cet" 也按泛化处理(用户可能只写了 CET)
    if (s == 'cet') generic ??= 'cet4';
  }
  return generic;
}

/// 目标 → 考试等级**集合**(筛选 / 来源匹配 / 词池切分用)。
///
/// 与 [targetExamOf] 的分工:
/// - [targetExamOf] 回答"这批目标里最具体的**一个**考试"(出题提示词只能有一个);
/// - 本函数回答"这批目标覆盖**哪些**等级"(四级/六级两个目标同时勾时两个都要算)。
///
/// 「四六级」是泛化档(2026-11-06 拆目标前存下来的老数据):识别不出四还是六,
/// 所以**同时展开成 cet4 与 cet6**,这样老用户按等级筛选时两个桶都能看到,
/// 不需要迁移已存的学习目标。
Set<String> examTypesForGoals(List<String> examGoals) {
  final out = <String>{};
  for (final raw in examGoals) {
    final s = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_/]+'), '')
        .trim();
    if (s.isEmpty) continue;
    if (s.contains('四六级') || (s.contains('cet') && s.contains('46'))) {
      out.addAll(const <String>['cet4', 'cet6']);
      continue;
    }
    final one = targetExamOf(<String>[raw]);
    if (one != null) out.add(one);
  }
  return out;
}

/// UI 卡片用的一句话来源描述(如「《人类简史》· B2 · 覆盖率 96%」)。
///
/// 只描述**有值**的字段:没分析过难度/覆盖率就不写,不留" · ·"这种空槽。
String describeSources(OutputSourceMaterial material) {
  final title = material.title.trim();
  final parts = <String>[title.isEmpty ? '《未命名材料》' : '《$title》'];
  final cefr = material.cefr.trim();
  if (cefr.isNotEmpty) parts.add(cefr.toUpperCase());
  final coverage = material.coverage;
  if (coverage != null && coverage.isFinite) {
    final percent = (coverage.clamp(0.0, 1.0) * 100).round();
    parts.add('覆盖率 $percent%');
  }
  return parts.join(' · ');
}

// ═══════════════════════════════════════════════════════════════════════
// 内部工具
// ═══════════════════════════════════════════════════════════════════════

/// 英文词计数(只数拉丁字母词;中文句子的"词数"不参与回译筛选)
int _latinWordCount(String sentence) {
  final matches =
      RegExp(r"[A-Za-z][A-Za-z'\u2019\-]*").allMatches(sentence);
  return matches.length;
}

/// 拉丁字母个数(判断"过短段"用;纯数字/目录行会被排除)
int _letterCount(String text) {
  var count = 0;
  for (final unit in text.codeUnits) {
    if ((unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122)) count++;
  }
  return count;
}

/// 粗判"像不像一个完整句子"(不做句法分析,只排掉明显残句)
bool _looksLikeCompleteSentence(String sentence) {
  final text = sentence.trim();
  if (text.isEmpty) return false;
  final words = RegExp(r"[A-Za-z][A-Za-z'\u2019\-]*")
      .allMatches(text)
      .map((m) => m.group(0)!.toLowerCase())
      .toList(growable: false);
  if (words.length < 2) return false;

  // 从句/连接词开头 → 多半是残句(回译题写出来会很别扭)
  if (_fragmentStarters.contains(words.first)) return false;

  // 英文句子小写开头 → 大概率是从上一句切下来的片段
  final firstLetter = RegExp(r'[A-Za-z]').firstMatch(text)?.group(0);
  if (firstLetter != null && firstLetter == firstLetter.toLowerCase()) {
    return false;
  }

  // 粗判主谓:至少有一个动词候选(助动词/高频动词/常见词尾)
  return words.any(_isVerbLike);
}

bool _isVerbLike(String word) {
  if (_verbCandidates.contains(word)) return true;
  if (word.length < 3) return false;
  return word.endsWith('ed') ||
      word.endsWith('ing') ||
      (word.endsWith('s') && word.length > 3);
}

/// 看起来像标题/目录行(摘要素材要跳过它们)
bool _looksLikeHeading(String paragraph) {
  final text = paragraph.trim();
  if (text.isEmpty) return true;
  // 1) 章节行: Chapter 1 / Part Two / 第3章 / 1. Introduction
  if (RegExp(
    r'^(chapter|part|section|book|prologue|epilogue|contents|preface)\b',
    caseSensitive: false,
  ).hasMatch(text)) {
    return true;
  }
  if (RegExp(r'^\d+([.)、]|\s)').hasMatch(text) && _letterCount(text) < 80) {
    return true;
  }
  if (RegExp(r'^第.{1,8}[章节卷部篇]').hasMatch(text)) return true;
  // 2) 短且没有任何句末标点 → 标题
  if (_letterCount(text) < 80 &&
      !RegExp(r'[.!?。！？：:]$').hasMatch(text)) {
    return true;
  }
  return false;
}

/// 在句子/空格边界截断,避免把单词切一半
String _truncateAtBoundary(String paragraph, int maxChars) {
  if (maxChars <= 0) return '';
  if (paragraph.length <= maxChars) return paragraph;
  final head = paragraph.substring(0, maxChars);
  // 先找句末,再找空格;都没有就硬截(极少见)
  final sentenceEnd = RegExp(r'[.!?。！？]\s').allMatches(head);
  if (sentenceEnd.isNotEmpty) {
    final end = sentenceEnd.last.end;
    if (end > maxChars ~/ 2) return '${head.substring(0, end).trim()}…';
  }
  final space = head.lastIndexOf(' ');
  final cut = space > maxChars ~/ 2 ? space : head.length;
  return '${head.substring(0, cut).trim()}…';
}

/// 去重键:小写 + 折叠空白(标点保留;"Hello, world!" 与 "hello,  world!" 视为同一句)
String _dedupeKey(String sentence) =>
    sentence.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// 专有名词/缩写粗判:首字母大写(如 `London` / `NASA`)不适合当"写作用词"
bool _looksLikeProperNoun(String word) {
  final first = word[0];
  return first == first.toUpperCase() && first != first.toLowerCase();
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

/// 错误标签聚合(weakGrammarPoints 内部用)
class _TagStat {
  _TagStat(this.tag);

  final String tag;
  int count = 0;
  DateTime? lastAt;
}
