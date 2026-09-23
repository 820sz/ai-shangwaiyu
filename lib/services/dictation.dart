import 'dart:math';

/// 听写练习(v2.2 听说)—— **纯函数、无 IO、不调 AI**。
///
/// 为什么用 TTS 而不是材料自带音频做听写:
/// RSS 音频**没有时间轴**,我们无法知道"第 37 秒对应文中哪一句" ——
/// 硬做只能瞎猜,或者让用户自己去对时间,都是假功能。
/// 而 TTS 能按任意句子生成语音,**文字与音频天然对齐**,所以听写可以
/// 客观评分(逐词比对),这才是真的练习而不是感觉。
///
/// 评分只比对**文字**(用户打出来的 vs 原文),不涉及发音 ——
/// 没有语音识别就说"没测发音",不编造发音分。
class DictationResult {
  final String reference;
  final String typed;

  /// 词级正确率 0..1(匹配词数 / 原句词数)
  final double accuracy;

  /// 漏掉/打错的词(原文有、你没打对)
  final List<String> missing;

  /// 多打的词(原文没有)
  final List<String> extra;

  const DictationResult({
    required this.reference,
    required this.typed,
    required this.accuracy,
    this.missing = const [],
    this.extra = const [],
  });

  bool get perfect => accuracy >= 0.999;

  String get scoreLine => '${(accuracy * 100).round()}%';

  /// 给用户的评语:必须带**具体信息**(漏了哪些词),不写"继续加油"
  String get comment {
    if (typed.trim().isEmpty) return '还没听到内容 —— 再放一遍,先听清开头几个词';
    if (perfect) return '完全正确';
    // 词都在但顺序/位置有偏差:LCS 扣了分,但"漏词"是空的 —— 要说清是语序问题
    if (missing.isEmpty) {
      return '词都听出来了,但语序/位置有偏差 —— 再听一遍留意句子结构';
    }
    if (accuracy >= 0.8) {
      return '基本听对了,漏/错了 ${missing.length} 个词:'
          '${missing.take(4).join('、')}';
    }
    if (accuracy >= 0.5) {
      return '听懂一半:漏/错 ${missing.length} 个词,建议先慢速再听一遍原文';
    }
    return '这段对你偏难:先看原文读一遍,再用慢速听写';
  }
}

/// 听写生成与判分
class Dictation {
  Dictation._();

  /// 太长/太短的句子都不适合听写:太短没信息量,太长打字负担大
  static const int minWords = 5;
  static const int maxWords = 28;
  static const int minChars = 25;
  static const int maxChars = 220;

  /// 从材料正文里挑 [count] 句做听写(同 seed 同结果 → 同一份材料可复现)
  static List<String> pickSentences(
    String text, {
    int count = 5,
    int seed = 1,
  }) {
    final all = splitSentences(text).where((s) {
      final words = _tokenize(s);
      return words.length >= minWords &&
          words.length <= maxWords &&
          s.length >= minChars &&
          s.length <= maxChars;
    }).toList();
    if (all.isEmpty) return const [];
    // 去重(同一句可能在材料里出现多次),保持顺序稳定
    final unique = <String>[];
    for (final s in all) {
      if (!unique.contains(s)) unique.add(s);
    }
    final rng = Random(seed);
    unique.shuffle(rng);
    // 按原文顺序排回去:听写顺序跟阅读顺序一致更自然
    final picked = unique.take(count).toList()
      ..sort((a, b) => text.indexOf(a).compareTo(text.indexOf(b)));
    return picked;
  }

  /// 句子切分:与读后测验同口径(按 . ! ? 切,不做缩写消歧)
  static List<String> splitSentences(String text) {
    final out = <String>[];
    final normalized = text.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\s+'), ' ');
    for (final m in RegExp(r'[^.!?]+[.!?]+').allMatches(normalized)) {
      final s = m.group(0)!.trim();
      if (s.isEmpty) continue;
      out.add(s);
    }
    return out;
  }

  /// 逐词比对(词级 LCS 对齐):漏词、多词、错词都能指出来
  static DictationResult grade(String reference, String typed) {
    final ref = _tokenize(reference);
    final got = _tokenize(typed);
    if (ref.isEmpty) {
      return DictationResult(
        reference: reference,
        typed: typed,
        accuracy: 0,
      );
    }
    final lcs = _lcsLength(ref, got);
    final accuracy = (lcs / ref.length).clamp(0.0, 1.0).toDouble();

    // 漏词 = 原文里没被 LCS 匹配上的词(近似:用多重集差集表示)
    final refCount = <String, int>{};
    for (final w in ref) {
      refCount[w] = (refCount[w] ?? 0) + 1;
    }
    for (final w in got) {
      final c = refCount[w];
      if (c != null && c > 0) refCount[w] = c - 1;
    }
    final missing = <String>[];
    refCount.forEach((w, c) {
      for (var i = 0; i < c; i++) {
        missing.add(w);
      }
    });

    final gotCount = <String, int>{};
    for (final w in got) {
      gotCount[w] = (gotCount[w] ?? 0) + 1;
    }
    for (final w in ref) {
      final c = gotCount[w];
      if (c != null && c > 0) gotCount[w] = c - 1;
    }
    final extra = <String>[];
    gotCount.forEach((w, c) {
      for (var i = 0; i < c; i++) {
        extra.add(w);
      }
    });

    return DictationResult(
      reference: reference,
      typed: typed,
      accuracy: accuracy,
      missing: missing,
      extra: extra,
    );
  }

  /// 分词:小写、只留字母与内部撇号/连字符(与难度引擎口径一致)
  static List<String> _tokenize(String s) {
    final out = <String>[];
    for (final m in RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)*(?:-[A-Za-z]+)*")
        .allMatches(s)) {
      out.add(m.group(0)!.toLowerCase());
    }
    return out;
  }

  /// 最长公共子序列长度(词级)
  static int _lcsLength(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    // 一维滚动数组:句子级规模(≤28 词)完全够用
    var prev = List<int>.filled(b.length + 1, 0);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        cur[j] = a[i - 1] == b[j - 1]
            ? prev[j - 1] + 1
            : (prev[j] > cur[j - 1] ? prev[j] : cur[j - 1]);
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
      cur.fillRange(0, cur.length, 0);
    }
    return prev[b.length];
  }

  /// 一轮听写的总评(给结果页)。每个档位都报出**句数**与平均分 ——
  /// "3 句里 1 句全对"这种信息比单看百分比更能指导下一步。
  static String summaryLine(List<DictationResult> results) {
    if (results.isEmpty) return '这一轮没有可听写的句子';
    final avg = results.map((r) => r.accuracy).reduce((a, b) => a + b) / results.length;
    final perfect = results.where((r) => r.perfect).length;
    final pct = (avg * 100).round();
    final head = '平均 $pct%,$perfect/${results.length} 句完全正确';
    if (avg >= 0.95) {
      return '$head —— 这个语速的听力对你是舒适的';
    }
    if (avg >= 0.75) {
      return '$head —— 细节词(冠词/介词/复数)还漏一些,慢速再听一遍';
    }
    if (avg >= 0.5) {
      return '$head —— 大意能跟上,但逐词还差得远,建议先读一遍原文再听写';
    }
    return '$head —— 这段材料偏难,先换简单一点的材料练听力';
  }

  /// 把一轮里漏掉的词汇总(用于"一键收进生词本")
  static List<String> missWords(List<DictationResult> results, {int limit = 30}) {
    final out = <String>[];
    for (final r in results) {
      for (final w in r.missing) {
        if (w.length < 3) continue; // 太短的虚词不值得收
        if (!out.contains(w)) out.add(w);
        if (out.length >= limit) return out;
      }
    }
    return out;
  }
}
