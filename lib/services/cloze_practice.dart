import 'dart:math';

import 'output_source.dart' show splitSentences;

/// 语境选词填空（cloze）的纯逻辑层（v3 · 批 7 · P1-1）。
///
/// 为什么必须补这一块（用户 2026-11-01 的核心哲学）：
/// > "背单词功能必须基于输入输出闭环与材料语境。"
///
/// 之前的"写词"只有两条路：生词本复习（有材料出处，但练的是孤立词卡）和
/// 按目标练词表（干脆没有语境）。缺的正是中间那块：**在你自己读过的句子里
/// 挖掉目标词，让你从上下文把它补回来** —— 这是把"背过的词"变成"用得出"的桥。
///
/// 设计纪律：
/// - 目标词来自学习者生词本（他收藏过、有中文释义）；生词本没有命中材料时，
///   退回"考纲精选词表 ∩ 材料里出现的词"（仍是材料语境，只是不是他收藏过的）；
/// - 干扰项来自**同一篇文章/同一词表**的真实英文词，不用随机拼写伪词；
/// - 纯函数 + 自定 seed 可复现，方便测试与"再来一轮"；
/// - 抽不到足够好题就少给/不给（不编句子）。
class ClozeItem {
  /// 题面：原句，目标词被替换成 `____`（保留句首大写等其余部分）
  final String sentence;

  /// 正确答案（原形，保留原文大小写不敏感的匹配结果）
  final String answer;

  /// 4 个选项（含 answer，已打散）
  final List<String> options;

  /// 目标词中文释义（给提示用；无释义时为空串）
  final String hintZh;

  /// 原句（完整，含答案；复盘用）
  final String sourceSentence;

  const ClozeItem({
    required this.sentence,
    required this.answer,
    required this.options,
    required this.sourceSentence,
    this.hintZh = '',
  });

  /// 选中 [choice] 是否等于答案（大小写不敏感，去首尾空白）
  bool isCorrect(String choice) =>
      choice.trim().toLowerCase() == answer.trim().toLowerCase();
}

class ClozeSet {
  /// 材料名（结果页/标题用）
  final String materialTitle;
  final List<ClozeItem> items;

  const ClozeSet({required this.materialTitle, required this.items});

  bool get isEmpty => items.isEmpty;
  int get length => items.length;
}

class ClozePractice {
  ClozePractice._();

  /// 英文单词（允许连字符与撇号，如 well-known / it's）
  static final RegExp _wordRe = RegExp(r"[A-Za-z][A-Za-z'\-]*");

  /// 一行句子的"词数"（用于长度过滤，避免太短/太长的句子）
  static int wordCount(String sentence) =>
      _wordRe.allMatches(sentence).length;

  /// 句子里的所有英文词（小写、去重、保持出现顺序）
  static List<String> wordsIn(String text) {
    final seen = <String>{};
    final out = <String>[];
    for (final m in _wordRe.allMatches(text)) {
      final w = m.group(0)!.toLowerCase();
      if (w.length < 2) continue;
      if (seen.add(w)) out.add(w);
    }
    return out;
  }

  /// 从材料造一组语境填空题。
  ///
  /// [candidateMeanings]：候选目标词 → 中文释义（通常来自学习者生词本；
  /// 没有就传考纲精选词里"在材料中出现"的那些）。
  /// [poolWords]：干扰项池（一般传"材料词 ∪ 词表词"），为空时自动用材料词。
  ///
  /// 返回的题组可能少于 [count]（材料里命中不够），**不会编句子**。
  static ClozeSet build({
    required String materialTitle,
    required String materialText,
    required Map<String, String> candidateMeanings,
    List<String> poolWords = const [],
    int count = 5,
    int? seed,
  }) {
    if (materialText.trim().isEmpty || count <= 0) {
      return ClozeSet(materialTitle: materialTitle, items: const []);
    }
    final sentences = splitSentences(materialText);
    final pool = <String>[
      ...poolWords,
      ...wordsIn(materialText),
    ];
    final poolClean = <String>[];
    final usedPool = <String>{};
    for (final w in pool) {
      final low = w.trim().toLowerCase();
      if (low.length < 3) continue;
      if (!usedPool.add(low)) continue;
      poolClean.add(low);
    }

    final rng = Random(seed ?? DateTime.now().millisecondsSinceEpoch);
    final items = <ClozeItem>[];
    final usedTargets = <String>{};
    final usedSentences = <String>{};

    // 目标词随机顺序尝试,让"再来一轮"每次的组合不同
    final targets = candidateMeanings.keys
        .map((w) => w.trim())
        .where((w) => w.length >= 3)
        .toList()
      ..shuffle(rng);

    for (final target in targets) {
      if (items.length >= count) break;
      final lowTarget = target.toLowerCase();
      if (!usedTargets.add(lowTarget)) continue;
      // 找到第一个"含该词、长度合适、没用过"的句子
      for (final sentence in sentences) {
        final trimmed = sentence.trim();
        if (trimmed.isEmpty || usedSentences.contains(trimmed)) continue;
        final wc = wordCount(trimmed);
        if (wc < 8 || wc > 40) continue;
        final match = RegExp(
          r'\b' + RegExp.escape(lowTarget) + r'\b',
          caseSensitive: false,
        ).firstMatch(trimmed);
        if (match == null) continue;
        // 目标词在句子里只出现一次才挖空,否则会把题意弄混
        final occurrences = RegExp(
          r'\b' + RegExp.escape(lowTarget) + r'\b',
          caseSensitive: false,
        ).allMatches(trimmed).length;
        if (occurrences != 1) continue;
        final answer = match.group(0)!;

        final distractors = _pickDistractors(
          answer: answer,
          pool: poolClean,
          seed: rng.nextInt(1 << 31),
          count: 3,
        );
        if (distractors.length < 3) continue;

        final options = <String>[answer, ...distractors]..shuffle(rng);
        final blanked = trimmed.replaceRange(match.start, match.end, '____');
        items.add(ClozeItem(
          sentence: blanked,
          answer: answer,
          options: options,
          sourceSentence: trimmed,
          hintZh: candidateMeanings[target] ?? '',
        ));
        usedSentences.add(trimmed);
        break;
      }
    }

    return ClozeSet(materialTitle: materialTitle, items: items);
  }

  /// 抽 3 个干扰项：优先"长度接近答案"的真实词，避免一眼就能按长度排除。
  static List<String> _pickDistractors({
    required String answer,
    required List<String> pool,
    required int seed,
    required int count,
  }) {
    final answerLow = answer.toLowerCase();
    final rng = Random(seed);
    final candidates = <String>[];
    final seen = <String>{answerLow};
    for (final w in pool) {
      if (w == answerLow) continue;
      if (!seen.add(w)) continue;
      // 形近/同前缀的词会变成"拼写题",这里只用不同首字母,确保是词义辨析
      if (w.startsWith(answerLow) || answerLow.startsWith(w)) continue;
      candidates.add(w);
    }
    if (candidates.length < count) return const [];
    // 先按长度接近度分桶,再在桶内随机
    final answerLen = answerLow.length;
    candidates.sort((a, b) {
      final da = (a.length - answerLen).abs();
      final db = (b.length - answerLen).abs();
      return da.compareTo(db);
    });
    // 取最接近的一半(至少 count 个)再打散,避免总挑同样几个词
    final windowSize = (candidates.length / 2).ceil().clamp(count, candidates.length);
    final window = candidates.take(windowSize).toList()..shuffle(rng);
    return window.take(count).toList();
  }
}
