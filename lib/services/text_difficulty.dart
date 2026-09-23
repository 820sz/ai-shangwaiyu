/// 本地材料难度分析引擎(v2.0 地基)。
///
/// ## 这是什么
/// 给一篇阅读材料算一份**可解释**的难度画像:词次/词形数、生词数、覆盖率、
/// 生词密度、CEFR 档位、Flesch 可读性、预估阅读时长,以及"最值得先学的生词"。
/// 全部在本地用 [WordFrequency] 词频表计算:不联网、不调用 AI。
///
/// 存在意义:替换 v1.x 里"把文章丢给 AI、让 AI 嘴上回一个 B1"的假评估 ——
/// 那种级别既不可复现、也无法向用户交代依据,同一天问两次可能给出不同的答案。
/// 本引擎的每个数字都能指回一张词频表和一条公式。
///
/// ## 为什么用"已知词集合"当输入
/// 材料难度不是材料的绝对属性,而是"这篇材料对**这个**用户有多难"。调用方传入
/// 用户已归一化的已知词集合(通常来自词汇量测试 [VocabEstimator] 的档位 + 用户的
/// 生词本/已掌握列表),引擎只做统计,不猜用户水平。
///
/// ## 已知局限(必须向用户显示依据,不能当黑箱)
/// 1. **词形归一只是启发式**,不是词形还原(lemmatizer):靠后缀剥离 + 词表命中,
///    不规则形式(gone/children/better/mice)无法还原,会被算成生词;派生词只覆盖
///    常见后缀(happiness → 不会还原到 happy)。宁可保守 —— 拿不准就按原词算生词,
///    宁可高估难度,也不要告诉用户"你都认识"。
/// 2. **音节数是启发式**(元音组计数 + 结尾 e/ed/es 修正):style/poem 这类词会差 1,
///    所以 Flesch 只适合**同一用户在不同材料之间的相对比较**,不要对外宣称
///    "本篇 Flesch 62.3 分"这种绝对等级。
/// 3. **CEFR 是一阶近似**:依据是"类型覆盖率 + 生词词频档位",阈值没有做过校准实验
///    (见 [TextDifficulty.cefrFromCoverage] 注释)。而且它是**相对该用户**的难度:
///    用户认识全部词时必然给出 A1。这与 [VocabEstimator] 里"用户词量 → CEFR"
///    (绝对水平)是两件事,UI 文案上不要混用。
/// 4. **覆盖率按"词形(type)"算,不是按"词次(token)"算**:同一个词形出现 10 次也只算
///    1 个类型。所以数值天然低于常被引用的"98% 词次覆盖率"(Nation 2006),两者不可
///    直接比较;需要词次视角时看 [TextDifficulty.knownTokenRatio]。
/// 5. 专有名词判定只看"大小写形态",标题体(每词首字母大写)会被误判成专有名词。
///
/// 本文件无额外依赖(只用 `dart:math` + [WordFrequency]),不联网,不用 `dart:io`。
library;

import 'dart:math' as math;

import 'word_frequency.dart';

/// 一篇材料的难度画像(全部本地计算,零 API 成本)。
class TextDifficulty {
  TextDifficulty({
    required this.totalTokens,
    required this.uniqueTypes,
    required this.knownTypes,
    required this.newTypes,
    required this.newTokens,
    required this.coverage,
    required this.knownTokenRatio,
    required this.newWordDensity,
    required this.cefr,
    required this.fleschReadingEase,
    required this.fleschKincaidGrade,
    required this.estMinutes,
    required this.topNewWords,
  });

  /// 词次:从原文里切出的英文词的总个数(不含标点/数字/中文/代码块)。
  final int totalTokens;

  /// 不同词形数(归一化之后去重)。`uniqueTypes <= totalTokens`。
  final int uniqueTypes;

  /// 用户已知的不同词数。
  final int knownTypes;

  /// 生词的不同词数。
  final int newTypes;

  /// 生词出现次数(按词次计)。同一个生词出现 5 次会记 5。
  final int newTokens;

  /// `knownTypes / uniqueTypes`(0..1)。空文本约定为 1.0。
  final double coverage;

  /// 已知词占**词次**的比例(0..1)。泛读体验看这个:用户读 100 个词里有多少个认识。
  /// 同一个生词反复出现会把这比值拉低很多,而这正是阅读时真正的卡顿来源。
  final double knownTokenRatio;

  /// 每 100 词里的生词**词次**数(0..100)。
  final double newWordDensity;

  /// 相对该用户的难度档位('A1'..'C2'),见 [cefrFromCoverage]。
  final String cefr;

  /// Flesch Reading Ease(越高越易读)。无有效词时为 0.0(哨兵值,调用方先看
  /// [totalTokens])。
  final double fleschReadingEase;

  /// Flesch–Kincaid Grade Level(美国年级数;可为负,表示低于 1 年级)。
  final double fleschKincaidGrade;

  /// 预估阅读时长(分钟,向上取整,至少 1)。默认按 [analyze] 的 `wpm`。
  final int estMinutes;

  /// 最值得先学的生词(已归一化,按 [analyze] 的排序规则取前 N 个)。
  final List<String> topNewWords;

  /// 文本里一个有效英文词都没有(纯中文/纯标点/空)。
  bool get isEmpty => totalTokens == 0;

  @override
  String toString() =>
      'TextDifficulty(tokens=$totalTokens, types=$uniqueTypes, '
      'coverage=${coverage.toStringAsFixed(3)}, '
      'knownTokenRatio=${knownTokenRatio.toStringAsFixed(3)}, '
      'density=${newWordDensity.toStringAsFixed(1)}, cefr=$cefr, '
      'flesch=${fleschReadingEase.toStringAsFixed(1)}, '
      'est=$estMinutes min, topNew=$topNewWords)';

  // ---------------------------------------------------------------------------
  // 分词
  // ---------------------------------------------------------------------------

  /// 英文词(允许内部撇号与连字符):`well-known`、`don't`、`fox's` 各算 1 个 token。
  static final RegExp _wordPattern =
      RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)*(?:-[A-Za-z]+)*");

  /// 句末标点或换行:两次匹配之间出现它就说明下一个 token 处在句子(或 Markdown 行)开头。
  static final RegExp _boundaryPattern = RegExp(r'[.!?\n]');

  /// 把材料切成词(小写)。**纯函数**,唯一的隐藏依赖是连字符复合词的判定会查
  /// [WordFrequency](测试注入什么表,结果就是什么)。
  ///
  /// 规则(为什么这么定):
  /// - **只看拉丁字母**:数字、标点、emoji、中文都不是英语词汇,计进去只会污染
  ///   覆盖率。中文材料整体切出 0 个 token,这是**有意**的 —— 难度引擎不假装能评中文。
  /// - **撇号归一**:U+2019/‛ 等弯引号先折成 ASCII `'`,否则 `don’t` 会被切成
  ///   `don` + `t` 两个假词,凭空多出两个"生词"。
  /// - **单个字母丢弃**(`a`/`i` 除外):`U.S.`、`E.U.`、`A.B.` 这类缩写会碎成
  ///   `u`/`s` 并污染生词列表,而它们不是词汇;`a`/`i` 是真词,保留。
  /// - **连字符复合词**:整词在词表里 → 保留整体(`well-known` 作为一个条目);
  ///   不在表里 → 拆成 `well` + `known` 分别判断。理由:复合词多半由常见词构成,
  ///   拆开后如果两个部分用户都认识,就不该把一个"没在表里的字符串"报成生词。
  /// - **Markdown 噪声**(标题/加粗/行内代码/围栏代码块/URL/链接目标)先清掉,
  ///   见 [_stripMarkdownNoise]。代码块里的标识符(`runApp`)不是英语阅读内容。
  static List<String> tokenize(String text) =>
      _scan(text).map((t) => t.lower).toList(growable: false);

  /// Markdown/纯文本噪声清理。为什么按这个顺序:
  /// 1. 先折弯引号(后面所有规则都依赖 ASCII 撇号);
  /// 2. 围栏代码块**整段**丢弃(含未闭合的尾块)—— 里面的标识符不是阅读材料;
  /// 3. URL 整段丢弃(含 `www.`)。`\S+` 会把 markdown 的右括号和句末点号一起吞进来,
  ///    所以只把 URL 本体换成空格、把尾部标点**还回去**,否则会吃掉一个句子边界,
  ///    让 Flesch 的句数少算;
  /// 4. `](目标)` 这种链接/图片目标是路径不是散文,丢掉;链接**文字**保留
  ///    (用户读得到它,自然也要算进难度);
  /// 5. 最后把 `* _ \` > # ~ |` 换成空格。这些字符本来就不会被 [_wordPattern] 匹配,
  ///    显式清理是为了让 `well**known`、`snake_case` 之类的粘连按词切开,行为可预期。
  static String _stripMarkdownNoise(String text) {
    var s = text.replaceAll('\u2018', "'").replaceAll('\u2019', "'");
    s = s.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    s = s.replaceAll(RegExp(r'```[\s\S]*$'), ' ');
    s = s.replaceAll(RegExp(r'~~~[\s\S]*?~~~'), ' ');
    s = s.replaceAll(RegExp(r'~~~[\s\S]*$'), ' ');
    s = s.replaceAllMapped(RegExp(r'(?:https?://|www\.)\S+'), (m) {
      final raw = m[0]!;
      final trimmed = raw.replaceFirst(RegExp(r'''[.,;:!?)\]}"']+$'''), '');
      return trimmed.length == raw.length ? ' ' : raw.substring(trimmed.length);
    });
    s = s.replaceAll(RegExp(r'\]\([^)\s]*\)'), ' ');
    s = s.replaceAll(RegExp(r'[*_`>#~|]'), ' ');
    return s;
  }

  /// 扫描出 token,附带"是否句首"与"是否是专有名词形态"(给 [analyze] 用)。
  static List<_Tok> _scan(String text) {
    final cleaned = _stripMarkdownNoise(text);
    final out = <_Tok>[];
    var cursor = 0;
    var sentenceStart = true;
    for (final m in _wordPattern.allMatches(cleaned)) {
      if (_boundaryPattern.hasMatch(cleaned.substring(cursor, m.start))) {
        sentenceStart = true;
      }
      cursor = m.end;
      final raw = m[0]!;
      final parts = raw.split('-');
      if (parts.length > 1 && WordFrequency.contains(raw.toLowerCase())) {
        _emit(out, raw, sentenceStart: sentenceStart);
      } else {
        for (var i = 0; i < parts.length; i++) {
          _emit(out, parts[i], sentenceStart: sentenceStart && i == 0);
        }
      }
      sentenceStart = false;
    }
    return out;
  }

  static void _emit(List<_Tok> out, String raw, {required bool sentenceStart}) {
    final lower = raw.toLowerCase();
    // 单字母噪声过滤(见 tokenize 注释):只放过 a / i。
    if (lower.length < 2 && lower != 'a' && lower != 'i') return;
    out.add(_Tok(
      lower: lower,
      surface: raw,
      properLike: looksLikeProperNoun(raw, sentenceInitial: sentenceStart),
    ));
  }

  /// 是否"看起来像专有名词(人名/地名/品牌/缩写)"。
  ///
  /// 判定依据(为什么是这样):
  /// - **句中首字母大写**(非句首)→ 多半是专有名词。英语里普通名词在句中不会大写。
  /// - **全大写且长度 ≥ 2** → 缩写(NASA/API/US),不管在句首都按专有名词算。
  /// - **句首词一律不算**:句首大写是语法要求,区分不了 "The" 和 "London",
  ///   拿不准就不标记(保守)。
  ///
  /// 专有名词有什么用:它**仍然是生词**(不知道 "Readflow" 是什么确实会影响理解),
  /// 但学它的性价比低于实义词 —— 换一篇文章它就不出现了。所以 [analyze] 把它排在
  /// [TextDifficulty.topNewWords] 的最后。
  ///
  /// 局限:标题体("The Quick Brown Fox")里每个词都首字母大写,会被误判成专有名词。
  static bool looksLikeProperNoun(
    String rawToken, {
    required bool sentenceInitial,
  }) {
    final raw = rawToken.trim();
    if (raw.length < 2) return false;
    final letters = raw.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.isEmpty) return false;
    if (letters == letters.toUpperCase()) return true; // 全大写 = 缩写
    if (sentenceInitial) return false;
    final first = raw[0];
    return first == first.toUpperCase() && first != first.toLowerCase();
  }

  // ---------------------------------------------------------------------------
  // 词形归一
  // ---------------------------------------------------------------------------

  /// 轻量词形归一(启发式,不是词形还原)。
  ///
  /// 做法:依次尝试 原词 → 去 `'s` → 去 `s`/`es`/`ies` → 去 `ed` → 去 `ing`
  /// → 去 `ly` → 去 `er`/`est`,**返回第一个能在词频表里命中的形式**;
  /// 都不命中就返回原词(按生词处理)。
  ///
  /// 为什么用"词表命中即停"而不是更复杂的规则:词频表本身就是"这个词存不存在"的
  /// 判据,用查表代替词性分析,既便宜又不引入新依赖。各组内部的候选顺序也按这个
  /// 原则排:先试更可能正确还原的形式。
  /// - 复数:`-s` 在 `-es` **之前**试(`uses` → `use`,而不是先得到 `us`)。
  /// - `-ed`/`-ing`:先试补回结尾 `e`(`making` → `make`、`using` → `use`),
  ///   再试裸词干(`walked` → `walk`),再试去掉双写辅音(`running` → `run`),
  ///   最后试 `-i` → `-y`(`studied` → `study`)。
  /// - 派生候选要有长度下限:候选词形 < 2 个字母、或词干短于 3 个字母一律放弃
  ///   (`as` → `a`、`thing` → `the`、`used` → `us`、`daily` → `day`)。这类假命中
  ///   会把生词判成熟词,让用户看到"全都认识"却读不懂,比漏还原有害得多。
  ///
  /// 局限(宁可保守,不确定就按原词算生词):
  /// - 不规则形式不还原(better/gone/children/mice 仍是生词);
  /// - 派生词只覆盖常见后缀(happiness 不会还原到 happy);
  /// - 词性歧义不处理(`goods` 会被还原成 `good`);
  /// - 复合词不在这里拆,拆分在 [tokenize] 阶段完成。
  static String normalize(String word) {
    final w = word.trim().toLowerCase();
    if (w.isEmpty) return w;
    if (WordFrequency.contains(w)) return w;
    for (final cand in _candidates(w)) {
      if (cand.length < 2) continue;
      if (WordFrequency.contains(cand)) return cand;
    }
    return w;
  }

  /// 按后缀组依次产出候选词干(顺序 = 优先级,见 [normalize] 注释)。
  static Iterable<String> _candidates(String w) sync* {
    final seen = <String>{};
    Iterable<String> add(Iterable<String> xs) sync* {
      for (final x in xs) {
        if (x.isNotEmpty && seen.add(x)) yield x;
      }
    }

    // 1) 所有格 / 撇号结尾
    yield* add([
      if (w.endsWith("'s")) w.substring(0, w.length - 2),
      if (w.endsWith("'")) w.substring(0, w.length - 1),
    ]);

    // 2) 复数
    if (w.endsWith('s') && !w.endsWith('ss')) {
      yield* add([w.substring(0, w.length - 1)]);
      if (w.endsWith('es')) yield* add([w.substring(0, w.length - 2)]);
      if (w.endsWith('ies')) {
        yield* add(['${w.substring(0, w.length - 3)}y']);
      }
    }

    // 3) 过去式/过去分词(长度下限保证词干 ≥3 个字母,挡掉 used → us 这类烂还原)
    if (w.endsWith('ed') && w.length > 4) {
      final stem = w.substring(0, w.length - 2);
      yield* add(_stemForms(stem, allowY: true));
    }

    // 4) 现在分词/动名词
    if (w.endsWith('ing') && w.length > 5) {
      final stem = w.substring(0, w.length - 3);
      yield* add(_stemForms(stem, allowY: true));
    }

    // 5) 副词(词干只留 3 个字母就放弃:daily → day 这种"把实词吃成常识词"的假命中
    //    比漏还原更伤 —— 用户会看到"你都认识",却读不懂那句)
    if (w.endsWith('ly') && w.length > 5) {
      final stem = w.substring(0, w.length - 2);
      yield* add(_stemForms(stem, allowY: true));
    }

    // 6) 比较级/最高级
    if (w.endsWith('est') && w.length > 5) {
      yield* add(_stemForms(w.substring(0, w.length - 3), allowY: true));
    }
    if (w.endsWith('er') && w.length > 4) {
      yield* add(_stemForms(w.substring(0, w.length - 2), allowY: true));
    }
  }

  /// 一个词干可能的原形:补 e / 裸词干 / 去双写辅音 / `-i` → `-y`。
  ///
  /// 词干短于 3 个字母就直接放弃:英语里几乎没有这么短的原形,放行只会换来
  /// `thing` → `the`、`used` → `us` 这种"把生词判成熟词"的假命中 —— 与
  /// [normalize] "拿不准就按原词算生词"的原则冲突。
  static List<String> _stemForms(String stem, {required bool allowY}) {
    final out = <String>[];
    if (stem.length < 3) return out;
    if (!stem.endsWith('e')) out.add('${stem}e'); // making → make
    out.add(stem); // walked → walk
    final n = stem.length;
    if (stem[n - 1] == stem[n - 2] && !'sl'.contains(stem[n - 1])) {
      out.add(stem.substring(0, n - 1)); // running → run(ss/ll 不拆,避免 pass → pas)
    }
    if (allowY && stem.endsWith('i')) {
      out.add('${stem.substring(0, n - 1)}y'); // studied → study、happier → happy
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // 音节 / 句子 / Flesch
  // ---------------------------------------------------------------------------

  /// 音节数启发式估算(元音组计数 + 常见结尾修正)。
  ///
  /// 规则:连续元音算 1 个音节(aeiouy,`y` 按元音算才能覆盖 rhythm/my/city);
  /// - 结尾 `e` 不发音 → 减 1,但 `-le` 前是辅音时 `le` 自成音节(table/simple 保持 2),
  ///   而 `while`(`l` 前是元音)要减;
  /// - 结尾 `ed` 前不是 t/d → 不单独成音节(walked 1,wanted 2);
  /// - 结尾 `es` 前不是 s/x/z 且不是 `-ches/-shes` → 不单独成音节(makes 1,boxes 2);
  /// - 至少 1 个音节,避免 0 让 Flesch 除零。
  ///
  /// 局限:英语拼写与发音的对应太乱,style/poem/queue 这类词会偏差 1。
  /// 所以 Flesch 只当**相对指标**用(同一批材料之间比高低),不当绝对分数。
  static int estimateSyllables(String word) {
    var w = word.toLowerCase();
    if (w.contains('-')) {
      var sum = 0;
      for (final p in w.split('-')) {
        if (p.isNotEmpty) sum += estimateSyllables(p);
      }
      return sum < 1 ? 1 : sum;
    }
    w = w.replaceAll(RegExp(r'[^a-z]'), '');
    if (w.isEmpty) return 1;
    var syl = RegExp(r'[aeiouy]+').allMatches(w).length;
    if (syl == 0) return 1;
    final n = w.length;
    bool silentLe() {
      // -le 自成音节的条件:l 前面是辅音(table/simple/people)
      if (n < 3 || !w.endsWith('le')) return false;
      final before = w[n - 3];
      return !'aeiouy'.contains(before);
    }

    if (w.endsWith('ed') && n >= 4 && !'td'.contains(w[n - 3])) {
      syl--;
    } else if (w.endsWith('es') &&
        n >= 4 &&
        !'sxz'.contains(w[n - 3]) &&
        !w.endsWith('ches') &&
        !w.endsWith('shes')) {
      syl--;
    } else if (w.endsWith('e') && !silentLe() && syl > 1) {
      syl--;
    }
    return syl < 1 ? 1 : syl;
  }

  /// 句子数:`[.!?]+` 后面跟空白或文本结束算一句。
  ///
  /// 兜底为 1(空文本/无标点也算 1 句):Flesch 分母不能为 0。需要真实句数请自行
  /// 在调用侧判断 —— 这里的下限是给公式服务的。
  /// 局限:缩写里的点(`Dr.`、`U.S.`)和 Markdown 标题行会被误算边界,
  /// 但长短句的相对关系仍然成立。
  static int countSentences(String text) {
    final clean = _stripMarkdownNoise(text);
    final n = RegExp(r'[.!?]+(?=\s|$)').allMatches(clean).length;
    return n < 1 ? 1 : n;
  }

  /// 生词在词频表里的位置百分位(0 = 最高频,1 = 最罕见)。
  /// 不在 50k 表里 → 1.0(比表内任何词都罕见);表未加载 → 1.0。
  static double rankPercentile(String word) {
    final total = WordFrequency.rankedSize;
    final rank = WordFrequency.rankOf(word);
    if (rank <= 0 || total <= 0) return 1.0;
    final p = rank / total;
    return p > 1.0 ? 1.0 : p;
  }

  /// 排序用的"罕见度":不在表里视为比任何表内词都罕见。
  static const int _notInTableRank = 1 << 24;

  static int _rarityRank(String word) {
    final r = WordFrequency.rankOf(word);
    return r > 0 ? r : _notInTableRank;
  }

  // ---------------------------------------------------------------------------
  // 分析主入口
  // ---------------------------------------------------------------------------

  /// 分析一篇材料。
  ///
  /// [knownWords] 必须是**已归一化**的用户已知词集合(调用方负责,通常是
  /// `userWords.map(TextDifficulty.normalize).toSet()`);本函数对每个 token
  /// 先 [normalize] 再判断,所以传进来的词也应当是归一化后的形式。
  ///
  /// [wpm] 阅读速度(词/分钟),估算时长用;`<= 0` 时按 200 处理(不抛异常 ——
  /// 配置里的脏数据不该让整篇材料的分析失败)。
  ///
  /// [topNewWordsLimit] 取多少个推荐生词。
  static TextDifficulty analyze(
    String text, {
    required Set<String> knownWords,
    int wpm = 200,
    int topNewWordsLimit = 30,
  }) {
    final tokens = _scan(text);
    final totalTokens = tokens.length;

    // 词形 → 词次;同时记录"该词形的每一次出现是否都是专有名词形态"。
    // 同一个词形既当专有名词又当普通词出现过(如 Fox 公司 / a fox)时按普通词算,
    // 因为这时它确实是一个需要认识的普通词。
    final counts = <String, int>{};
    final properOnly = <String, bool>{};
    for (final t in tokens) {
      final norm = normalize(t.lower);
      counts[norm] = (counts[norm] ?? 0) + 1;
      properOnly[norm] = (properOnly[norm] ?? true) && t.properLike;
    }

    var knownTypes = 0;
    var newTypes = 0;
    var newTokens = 0;
    var percentileSum = 0.0;
    for (final e in counts.entries) {
      if (knownWords.contains(e.key)) {
        knownTypes++;
      } else {
        newTypes++;
        newTokens += e.value;
        percentileSum += rankPercentile(e.key); // 按"不同生词"取平均:出现次数不改变词的档位
      }
    }

    final uniqueTypes = counts.length;
    final knownTokens = totalTokens - newTokens;
    // 三处除法都要兜底:0 词形时覆盖率约定为 1.0(没有不认识的词),
    // 0 词次时占比/密度为 0,不能让它抛 NaN。
    final coverage = uniqueTypes == 0 ? 1.0 : knownTypes / uniqueTypes;
    final knownTokenRatio = totalTokens == 0 ? 1.0 : knownTokens / totalTokens;
    final newWordDensity =
        totalTokens == 0 ? 0.0 : newTokens * 100.0 / totalTokens;
    final avgNewWordPercentile = newTypes == 0 ? 0.0 : percentileSum / newTypes;

    // Flesch:分母靠 countSentences(≥1)兜底;没有词就给 0 哨兵值,
    // 免得"没有词"被误读成"极难文章"(Flesch 0 分 = 极难)。
    final sentences = countSentences(text);
    var syllables = 0;
    for (final t in tokens) {
      syllables += estimateSyllables(t.surface);
    }
    var flesch = 0.0;
    var grade = 0.0;
    if (totalTokens > 0) {
      final wordsPerSentence = totalTokens / sentences;
      final syllablesPerWord = syllables / totalTokens;
      flesch = 206.835 - 1.015 * wordsPerSentence - 84.6 * syllablesPerWord;
      grade = 0.39 * wordsPerSentence + 11.8 * syllablesPerWord - 15.59;
    }

    final effectiveWpm = wpm > 0 ? wpm : 200;
    final estMinutes = math.max(1, (totalTokens / effectiveWpm).ceil());

    // 排序:先按"对理解的影响" ——
    // 1. 普通生词优先于专有名词(专有名词换篇文章就没用了);
    // 2. 出现次数多的先学(同一篇里反复遇到);
    // 3. 次数相同 → 更罕见的先学(常见词用户早晚会碰到,罕见词往往是本篇的主题词);
    // 4. 最后按字母序,保证同一输入永远给同样的顺序(可复现,便于 UI diff 和单测)。
    final candidates = counts.entries
        .where((e) => !knownWords.contains(e.key))
        .toList()
      ..sort((a, b) {
        final pa = properOnly[a.key] == true ? 1 : 0;
        final pb = properOnly[b.key] == true ? 1 : 0;
        if (pa != pb) return pa - pb;
        if (a.value != b.value) return b.value - a.value;
        final ra = _rarityRank(a.key);
        final rb = _rarityRank(b.key);
        if (ra != rb) return rb.compareTo(ra);
        return a.key.compareTo(b.key);
      });
    final limit = topNewWordsLimit < 0 ? 0 : topNewWordsLimit;

    return TextDifficulty(
      totalTokens: totalTokens,
      uniqueTypes: uniqueTypes,
      knownTypes: knownTypes,
      newTypes: newTypes,
      newTokens: newTokens,
      coverage: coverage,
      knownTokenRatio: knownTokenRatio,
      newWordDensity: newWordDensity,
      cefr: cefrFromCoverage(coverage, avgNewWordPercentile),
      fleschReadingEase: flesch,
      fleschKincaidGrade: grade,
      estMinutes: estMinutes,
      topNewWords:
          List<String>.unmodifiable(candidates.take(limit).map((e) => e.key)),
    );
  }

  // ---------------------------------------------------------------------------
  // CEFR
  // ---------------------------------------------------------------------------

  /// 各档含义(UI 上**要连同依据一起展示**,不要只给一个字母)。
  static const Map<String, String> cefrNotes = {
    'A1': '几乎没有生词,可以直接读,不需要查词',
    'A2': '个别生词,靠上下文基本能猜出来',
    'B1': '有一定生词量,需要偶尔查词,适合精读',
    'B2': '生词较多且偏抽象,建议先做生词预习再读',
    'C1': '生词密集、主题专业,阅读会比较吃力',
    'C2': '大量低频词/专业词,建议换更简单的材料或配合译文',
  };

  /// 覆盖率 + 生词罕见度 → CEFR(A1..C2)。
  ///
  /// **这是一阶近似,不是考试级别判定,阈值未做校准实验。**
  ///
  /// 依据:
  /// - 覆盖率是主项(权重 0.75)。阅读研究里"词次覆盖率 98% 才能无辅助读懂"
  ///   (Nation 2006;Laufer & Ravenhorst-Kalovski 2010 给出 95% 为最低线)。
  ///   注意本引擎的 [TextDifficulty.coverage] 是**词形**覆盖率,同一个数值比词次
  ///   覆盖率更保守(偏低),所以阈值整体定得比 98/95 低:类型覆盖率 0.90 上下
  ///   已经接近"通篇词都认识"。
  /// - 生词的词频档位是次项(权重 0.25)。同样覆盖率下,生词是常见词(用户只是
  ///   还没学到)比生词是罕见专业词更好读,所以 `avgWordRankPercentile`(0 = 最高频
  ///   ~ 1 = 最罕见)越高,越往高级别压。
  ///
  /// 合成"易读分" `ease = coverage*0.75 + (1-罕见度)*0.25`,再切档:
  /// ease ≥0.90 → A1,≥0.80 → A2,≥0.70 → B1,≥0.60 → B2,≥0.50 → C1,否则 C2。
  ///
  /// 相对性(必须记住):它回答的是"**对这位用户**有多难"。用户认识全部词时
  /// coverage = 1、无生词 → 必然 A1。想要"语料的绝对难度",应换一个与用户无关的
  /// 输入(例如按固定基准词汇表算 coverage),不要复用这个函数。
  static String cefrFromCoverage(
    double coverage,
    double avgWordRankPercentile,
  ) {
    final cov = coverage.isNaN ? 0.0 : coverage.clamp(0.0, 1.0).toDouble();
    final rare = avgWordRankPercentile.isNaN
        ? 1.0
        : avgWordRankPercentile.clamp(0.0, 1.0).toDouble();
    final ease = cov * 0.75 + (1 - rare) * 0.25;
    if (ease >= 0.90) return 'A1';
    if (ease >= 0.80) return 'A2';
    if (ease >= 0.70) return 'B1';
    if (ease >= 0.60) return 'B2';
    if (ease >= 0.50) return 'C1';
    return 'C2';
  }
}

/// 扫描出来的一个 token。[_Tok.lower] 用于归一/查表,[_Tok.surface] 保留原拼写
/// 给音节估算和大小写判定用。
class _Tok {
  const _Tok({
    required this.lower,
    required this.surface,
    required this.properLike,
  });

  final String lower;
  final String surface;
  final bool properLike;
}
