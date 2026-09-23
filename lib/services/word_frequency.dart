import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// 词频表加载与查询(v2.0 地基)。
///
/// 两份数据(见 `assets/data/README.md`):
/// - `en_freq_50k.txt`  : 每行 `词 出现次数`,按频次降序 → 覆盖率/难度/词表记忆
/// - `en_10k_clean.txt` : 每行一个词,按频次降序(书面语、已过滤不雅词) → 测试抽样池
///
/// 设计要点:
/// - **纯函数解析**(`parseFrequencyText`)与资源加载分离 → 单测不需要真实 assets;
/// - 只保留一份 `Map<String,int>`(词→名次),出现次数放平行 List → 内存更省;
/// - 全部本地计算,不联网、不调用 AI。
class WordFrequency {
  WordFrequency._();

  static const String assetRanked50k = 'assets/data/en_freq_50k.txt';
  static const String assetClean10k = 'assets/data/en_10k_clean.txt';

  static List<String> _ranked = const [];
  static List<int> _counts = const [];
  static Map<String, int> _rank = const {};
  static List<String> _clean10k = const [];
  static bool _loaded = false;

  static bool get isLoaded => _loaded;

  /// 50k 表的词条数(名次上限)
  static int get rankedSize => _ranked.length;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final raw50k = await rootBundle.loadString(assetRanked50k);
    final raw10k = await rootBundle.loadString(assetClean10k);
    final parsed = parseFrequencyText(raw50k);
    _ranked = parsed.words;
    _counts = parsed.counts;
    _rank = parsed.rank;
    _clean10k = parseWordList(raw10k);
    _loaded = true;
  }

  /// 仅测试/预热用:直接注入解析结果,避免依赖 assets。
  static void debugInject({
    required List<String> words,
    required List<int> counts,
    List<String> clean10k = const [],
  }) {
    _ranked = words;
    _counts = counts;
    _rank = {
      for (var i = 0; i < words.length; i++) words[i]: i + 1,
    };
    _clean10k = clean10k;
    _loaded = true;
  }

  /// 解析 `词 次数` 文本(纯函数,可单测)。
  /// 逐行取第一个空白前的 token 作为词、第二个 token 作为次数;
  /// 跳过空行/注释(# 开头)/非法行;重复词只保留首次(名次更靠前)。
  static ({List<String> words, List<int> counts, Map<String, int> rank})
      parseFrequencyText(String text) {
    final words = <String>[];
    final counts = <int>[];
    final rank = <String, int>{};
    for (final line in text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final sp = t.indexOf(' ');
      if (sp <= 0) continue;
      final w = t.substring(0, sp).trim().toLowerCase();
      if (w.isEmpty || rank.containsKey(w)) continue;
      final c = int.tryParse(t.substring(sp + 1).trim());
      if (c == null || c < 0) continue;
      rank[w] = words.length + 1;
      words.add(w);
      counts.add(c);
    }
    return (words: words, counts: counts, rank: rank);
  }

  /// 解析"每行一个词"的列表(纯函数,可单测)。
  static List<String> parseWordList(String text) {
    final out = <String>[];
    for (final line in text.split('\n')) {
      final w = line.trim().toLowerCase();
      if (w.isEmpty || w.startsWith('#')) continue;
      out.add(w);
    }
    return out;
  }

  /// 词在 50k 表中的名次(1 起)。返回 0 = 不在表中(视为更罕见)。
  static int rankOf(String word) => _rank[word.trim().toLowerCase()] ?? 0;

  /// 词在语料中的出现次数(不在表中 → 0)。
  static int countOf(String word) {
    final r = _rank[word.trim().toLowerCase()];
    if (r == null) return 0;
    return _counts[r - 1];
  }

  static bool contains(String word) => rankOf(word) > 0;

  /// 干净 10k 池(按频次降序),用于词汇量测试抽样。
  static List<String> get clean10k => _clean10k;

  /// 名次区间 [fromRank, toRank] 内、可通过"可测词"过滤的词(按名次升序)。
  /// [pool] 传 `cleanOnly: true` 时只用干净 10k 池。
  static List<String> bandWords(
    int fromRank,
    int toRank, {
    bool cleanOnly = false,
  }) {
    final lo = fromRank < 1 ? 1 : fromRank;
    final hi = toRank > _ranked.length ? _ranked.length : toRank;
    if (hi < lo) return const [];
    final out = <String>[];
    if (cleanOnly) {
      final cleanSet = _clean10k.toSet();
      for (var r = lo; r <= hi; r++) {
        final w = _ranked[r - 1];
        if (cleanSet.contains(w) && isTestableWord(w)) out.add(w);
      }
      return out;
    }
    for (var r = lo; r <= hi; r++) {
      final w = _ranked[r - 1];
      if (isTestableWord(w)) out.add(w);
    }
    return out;
  }

  /// 从名次区间里确定性抽样 [count] 个词(同 seed 同结果 → 可复现、可单测)。
  static List<String> sampleBand(
    int fromRank,
    int toRank, {
    int count = 20,
    int seed = 0,
    bool cleanOnly = false,
  }) {
    final pool = bandWords(fromRank, toRank, cleanOnly: cleanOnly);
    if (pool.isEmpty) return const [];
    final rng = Random(seed * 7919 + fromRank);
    if (pool.length <= count) {
      final copy = List<String>.from(pool);
      copy.shuffle(rng);
      return copy;
    }
    // 均匀抽样:洗牌前 count 个(词数 ≤ 50k,代价可接受)
    final copy = List<String>.from(pool);
    copy.shuffle(rng);
    return copy.take(count).toList();
  }

  /// 名次 ≤ [maxRank] 的全部词(**不做"可测词"过滤**)。
  ///
  /// 与 [bandWords] 的区别很关键:
  /// - [bandWords] 用于**出题**,必须过滤掉 of/to/in 这类短词与语气词;
  /// - [rankedUpTo] 用于**判定"用户是否认识"**(覆盖率计算):of/to/in/is
  ///   这些功能词占了英文文本近一半词次,如果把它们排除在"已知词"之外,
  ///   任何材料的覆盖率都会被严重低估(把 the 当生词)。
  static List<String> rankedUpTo(int maxRank) {
    final hi = maxRank > _ranked.length ? _ranked.length : maxRank;
    if (hi <= 0) return const [];
    return _ranked.sublist(0, hi);
  }

  /// 生成一个"像真词但不存在"的伪词(用于校准测试的虚报率)。
  ///
  /// 做法:取表中一个常见词,替换/插入字母后校验不在词表里。最多尝试 200 次,
  /// 失败返回 null(调用方跳过该题)。确定性:同 rng 序列同结果。
  static String? makePseudoword(Random rng) {
    const vowels = 'aeiou';
    const consonants = 'bcdfghjklmnprstvwz';
    if (_ranked.isEmpty) return null;
    for (var attempt = 0; attempt < 200; attempt++) {
      final base = _ranked[rng.nextInt(min(3000, _ranked.length))];
      if (base.length < 3) continue;
      final chars = base.split('');
      final pos = rng.nextInt(chars.length);
      final isVowel = vowels.contains(chars[pos]);
      final pool = isVowel ? consonants : vowels;
      final repl = pool[rng.nextInt(pool.length)];
      if (chars[pos] == repl) continue;
      chars[pos] = repl;
      final cand = chars.join();
      if (cand.length < 3) continue;
      if (rankOf(cand) > 0) continue; // 撞到真词 → 换一个
      if (_clean10k.contains(cand)) continue;
      return cand;
    }
    return null;
  }

  /// 是否适合出现在测试/词表里:
  /// 纯字母(允许内部连字符)、长度 ≥ 3、不在屏蔽表里。
  /// 字幕语料里有大量语气词、缩写与不雅词,不能直接拿去问用户。
  static bool isTestableWord(String w) {
    if (w.length < 3) return false;
    if (!RegExp(r'^[a-z]+(-[a-z]+)*$').hasMatch(w)) return false;
    return !_blocked.contains(w);
  }

  /// 不适合出现在测试中的词(语气词/缩略/不雅词;不追求穷尽,只求不冒犯)
  static const Set<String> _blocked = {
    'yeah', 'yep', 'nope', 'okay', 'gonna', 'wanna', 'gotta', 'kinda',
    'sorta', 'dunno', 'hmm', 'hmmm', 'umm', 'uhh', 'ahh', 'ohh', 'mmm',
    'huh', 'hey', 'yo', 'wow', 'ooh', 'eww', 'ugh', 'phew', 'yay',
    'lol', 'lmao', 'omg', 'wtf', 'haha', 'hahaha', 'hehe', 'hihi',
    'damn', 'hell', 'crap', 'shit', 'fuck', 'fucking', 'bitch', 'ass',
    'asshole', 'bastard', 'dick', 'piss', 'suck', 'sucks', 'sex', 'sexy',
    'goddamn', 'jesus', 'christ', 'lord', 'sir', 'madam', 'mrs', 'mr',
    'dr', 'st', 'vs', 'etc', 'ie', 'eg', 'ok', 'tv', 'dvd', 'cd',
  };
}
