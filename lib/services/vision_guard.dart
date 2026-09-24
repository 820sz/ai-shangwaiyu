/// 识图结果的**确定性校验层**(v2.4,直击用户反馈的"识图开盲盒")。
///
/// 为什么必须有这一层:模型返回的 JSON 是不可控的 —— 它会
/// ①把同一个词说两遍;②把单词标成短语(用户实测:一整页批注单词全变短语);
/// ③把长句截断成"开头…省略号";④编出图上并不存在的词。
/// 这些**都是可以在本地确定性判定的**,不该继续交给模型"自觉"。
///
/// ⚠️ 一条**不要做**的事:手写中文批注**不丢**(2026-09-24 用户纠正)——
/// 用户有时要靠页边中文批注补录,所以中文条目照常进结果列表、由用户自己决定选不选。
///
/// 这个文件只做纯函数校验(不依赖 Flutter、不联网),因此可以逐条单测 ——
/// 而识图精度问题恰恰需要"每条规则都能被测试"才谈得上修好。
library;

/// 被丢弃的一条(带原因,给界面显示"忽略了什么、为什么")
class VisionDrop {
  final String text;
  final String reason;

  const VisionDrop({required this.text, required this.reason});
}

/// 校验结果
class VisionGuardResult {
  /// 清洗后的条目(仍是模型给的字段结构,便于直接沿用下游解析)
  final List<Map<String, dynamic>> kept;

  /// 被丢弃的条目
  final List<VisionDrop> dropped;

  /// 被本地改写过类型的条数(模型说 phrase → 实际是 word 之类)
  final int typeFixed;

  /// 被完整句替换掉的截断条目数
  final int truncationFixed;

  /// 有"证据行"但行内找不到该词条的条数(疑为模型编造/记错)
  final int unverified;

  /// 被合并成"同一词多次出现"的条数(用户要求:同一个词标了两次要记成 ×2)
  final int mergedOccurrences;

  const VisionGuardResult({
    required this.kept,
    required this.dropped,
    this.typeFixed = 0,
    this.truncationFixed = 0,
    this.unverified = 0,
    this.mergedOccurrences = 0,
  });

  int get keptCount => kept.length;

  int get droppedCount => dropped.length;

  /// 一行给人看的说明(没有问题时返回 null,界面就不显示)
  String? get note {
    final parts = <String>[];
    if (dropped.isNotEmpty) parts.add('忽略 ${dropped.length} 条');
    if (mergedOccurrences > 0) parts.add('合并重复出现 $mergedOccurrences 处');
    if (typeFixed > 0) parts.add('纠正类型 $typeFixed 条');
    if (truncationFixed > 0) parts.add('补全截断 $truncationFixed 条');
    if (unverified > 0) parts.add('存疑 $unverified 条');
    if (parts.isEmpty) return null;
    return '已校验:${parts.join(' · ')}';
  }
}

/// 识图结果校验器(纯函数)
class VisionGuard {
  VisionGuard._();

  /// 单次识别最多保留多少条(防止模型刷屏;正常一页材料不会有这么多标记)
  static const int maxItems = 200;

  /// 少于该长度(去掉标点后)的"词"没有学习价值,丢掉
  static const int minWordLength = 2;

  /// 判定"像句子"的虚词/系动词表 —— 命中说明这段文字里有个小句,
  /// 而不是一个名词短语。这是**启发式**(本地没有词性标注),但它是
  /// 确定性的、可测的,比"听模型自称"可靠得多。
  static const Set<String> _clauseMarkers = {
    'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am',
    'has', 'have', 'had', 'do', 'does', 'did',
    'will', 'would', 'can', 'could', 'shall', 'should',
    'may', 'might', 'must', 'that', 'which', 'who', 'whom', 'whose',
    'if', 'when', 'while', 'because', 'although', 'though', 'as',
  };

  /// 主入口:清洗模型返回的条目列表。
  ///
  /// [raw] 是模型 JSON 里的 items(字段:`word`/`text`、`word_type`、
  /// `original_sentence`、`line` 等);返回 kept/dropped 与统计。
  static VisionGuardResult apply(
    List<Map<String, dynamic>> raw, {
    int maxItems = VisionGuard.maxItems,
  }) {
    final kept = <Map<String, dynamic>>[];
    final dropped = <VisionDrop>[];
    var typeFixed = 0;
    var truncationFixed = 0;
    var unverified = 0;
    var mergedOccurrences = 0;

    for (final item in raw) {
      final rawText = (item['word'] ?? item['text'] ?? '').toString().trim();
      if (rawText.isEmpty) {
        dropped.add(const VisionDrop(text: '(空)', reason: '空条目'));
        continue;
      }
      // ① 手写中文批注 **必须保留**(2026-09-24 用户纠正):
      //    用户有时要靠它补录 —— 所以这里不做任何丢弃,只把它当普通条目,
      //    并在本地类型判定里单独处理(中文不按英文词法判类型)。

      // ② 截断:模型把长句写成"开头…省略号"。有更长的完整句就用它替换,
      //    否则丢掉 —— 截断的词条对学习毫无价值,还会污染生词本。
      //    (放在字母检查之前:省略号本身会让"非英文字符"判断误杀整条)
      var text = rawText;
      if (looksTruncated(text)) {
        final sentence = (item['original_sentence'] ?? '').toString().trim();
        if (sentence.length > text.length && !looksTruncated(sentence)) {
          text = sentence;
          truncationFixed++;
        } else {
          dropped.add(VisionDrop(text: _short(text), reason: '截断/省略号'));
          continue;
        }
      }

      // ③④ 英文条目才做"太短/必须全是英文"的检查;中文批注跳过这两条
      if (!hasCjk(text)) {
        if (_letterCount(text) < minWordLength) {
          dropped.add(VisionDrop(text: _short(text), reason: '太短'));
          continue;
        }
        if (!isMostlyEnglish(text)) {
          dropped.add(VisionDrop(text: _short(text), reason: '不是英文'));
          continue;
        }
      }

      final key = normalize(text);
      if (key.length < minWordLength && !hasCjk(text)) {
        dropped.add(VisionDrop(text: _short(text), reason: '太短'));
        continue;
      }

      // ⑤ **同一个词重复出现 = 记录出现次数**(2026-09-24 用户要求),
      //    不是丢掉:一页里标了两次 "apple" 说明它更该背。
      //    判定方式:同一词面但**证据行不同** → 合并成一条并累计次数;
      //    词面与证据行都一样 → 只是模型复读,按重复丢掉。
      final existingIndex = kept.indexWhere(
        (k) => normalize((k['word'] ?? k['text'] ?? '').toString()) == key,
      );
      if (existingIndex >= 0) {
        final line = (item['line'] ?? item['source_line'] ?? item['evidence'] ?? '')
            .toString()
            .trim();
        final prev = kept[existingIndex];
        final prevLines =
            (prev['occurrences'] as List?)?.cast<String>() ?? const <String>[];
        if (line.isNotEmpty && !prevLines.contains(line)) {
          kept[existingIndex] = {
            ...prev,
            'occurrences': [...prevLines, line],
            'occurrence_count': prevLines.length + 1,
          };
          mergedOccurrences++;
        } else {
          dropped.add(VisionDrop(text: _short(text), reason: '重复条目'));
        }
        continue;
      }

      // ⑥ 被更长条目包含(按词边界判断:"blur" 是 "began to blur" 的一部分,
      //    但 "art" 不算 "artist" 的一部分 —— 后者是独立单词,不该被丢)
      final container = kept.firstWhere(
        (k) => _containsAsWord(normalize((k['word'] ?? k['text'] ?? '').toString()), key),
        orElse: () => const <String, dynamic>{},
      );
      if (container.isNotEmpty) {
        dropped.add(VisionDrop(text: _short(text), reason: '已包含在更长条目里'));
        continue;
      }

      // ⑦ 类型本地判定(不再全信模型):用户实测过"一整页单词全被标成短语"
      final modelType = (item['word_type'] ?? '').toString().trim();
      final localType = classify(text);
      if (modelType.isNotEmpty && modelType != localType) typeFixed++;

      // ⑧ 证据行核对:模型给了所在原文行时,行里必须真的能找到这个词条
      final line = (item['line'] ?? item['source_line'] ?? item['evidence'] ?? '')
          .toString()
          .trim();
      final verified = line.isEmpty || normalize(line).contains(key);
      if (!verified) unverified++;

      kept.add({
        ...item,
        'word': text,
        'word_type': localType,
        if (line.isNotEmpty) 'occurrences': [line],
        if (line.isNotEmpty) 'occurrence_count': 1,
        if (!verified) 'needs_review': true,
      });
      if (kept.length >= maxItems) break;
    }

    return VisionGuardResult(
      kept: kept,
      dropped: dropped,
      typeFixed: typeFixed,
      truncationFixed: truncationFixed,
      unverified: unverified,
      mergedOccurrences: mergedOccurrences,
    );
  }

  /// 本地判定 word / phrase / sentence(确定性规则,可单测)
  static String classify(String text) {
    // 中文批注不按英文词法判类型(用户要用它补录,类型只是个标签)
    if (hasCjk(text)) return 'word';
    final t = stripEdgePunctuation(text);
    if (t.isEmpty) return 'word';
    final tokens = t.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final endsLikeSentence = RegExp(r'[.!?。！？]$').hasMatch(text.trim());
    // 单个 token 一律是"单词"(连字符/撇号不拆,如 nature-versus-nurture)。
    // 这条规则专治用户实测到的"一整页批注单词全被标成短语"。
    if (tokens.length <= 1) return 'word';
    if (endsLikeSentence) return 'sentence';
    if (tokens.length <= 3) return 'phrase';
    // 4 个词以上:看有没有"小句标志词"(系动词/助动词/关系词)
    final lower = tokens.map((w) => w.toLowerCase()).toSet();
    if (lower.any(_clauseMarkers.contains)) return 'sentence';
    return 'phrase';
  }

  /// 去掉首尾的引号/括号/标点(用于计数与比较,不改动展示文本)
  static String stripEdgePunctuation(String text) => text
      .trim()
      .replaceAll(RegExp(r'''^[\s"'“”‘’(\[【《]+'''), '')
      .replaceAll(RegExp(r'''[\s"'“”‘’)\]】》]+$'''), '')
      .trim();

  /// 比较用的归一化形式:小写、统一空白、去首尾标点、去省略号
  static String normalize(String text) {
    var t = text.toLowerCase();
    t = t.replaceAll(RegExp(r'[…⋯]+'), '');
    t = t.replaceAll(RegExp(r'\.{2,}'), '');
    t = stripEdgePunctuation(t);
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    // 统一各种引号/破折号,避免"同一个词因排版差异被当成两条"
    t = t.replaceAll(RegExp(r'[“”‘’]'), "'");
    t = t.replaceAll(RegExp(r'[–—-]'), '-');
    t = t.replaceAll(RegExp(r"^'+|'+$"), '');
    return t.trim();
  }

  /// 含中日韩字符(用户手写的中文批注)
  static bool hasCjk(String text) =>
      RegExp(r'[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]').hasMatch(text);

  /// 主要是英文字母(不允许数字/杂符号混进来)
  static bool isMostlyEnglish(String text) {
    final letters = _letterCount(text);
    if (letters < minWordLength) return false;
    final nonLetters = text.replaceAll(RegExp(r'[A-Za-z]'), '').trim();
    // 允许的"非字母"只有空白与常见标点/连字符/撇号/省略号
    return !RegExp(r'[^A-Za-z\s\-''.,;:!?()"“”‘’/&…⋯]').hasMatch(nonLetters);
  }

  /// 字母个数(判断"太短"用)
  static int _letterCount(String text) =>
      RegExp(r'[A-Za-z]').allMatches(text).length;

  /// 截断特征:结尾是省略号(各种形态)
  static bool looksTruncated(String text) =>
      RegExp(r'([…⋯]+|\.{2,})\s*$').hasMatch(text.trim());

  /// [haystack] 里是否含**独立单词** [needle](按词边界)
  static bool _containsAsWord(String haystack, String needle) {
    if (needle.isEmpty || haystack.isEmpty || haystack == needle) return false;
    if (!haystack.contains(needle)) return false;
    final re = RegExp(
      r'(^|[^a-z0-9])' + RegExp.escape(needle) + r'([^a-z0-9]|$)',
    );
    return re.hasMatch(haystack);
  }

  static String _short(String s, [int max = 40]) {
    final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= max ? flat : '${flat.substring(0, max)}…';
  }
}
