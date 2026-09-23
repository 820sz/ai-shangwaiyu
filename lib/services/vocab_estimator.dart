// 注意:`library;` 必须位于所有 import 之前(Dart 语法要求),所以文件头 doc
// 注释 + library 指令在最前,import 紧随其后。

/// 自适应英语词汇量测试(Yes/No 词汇测试 + 伪词校准)——v2.0 水平基线。
///
/// ## 这是什么
/// 给用户逐题展示单词,用户只需回答"认识 / 不认识"。题目分 6 个词频档位
/// (b1..b6,按词频名次 1..20000 划分),每档抽样若干词,并**穿插**若干个
/// "伪词"(看起来像真词、实际不存在)。按档位命中率估计"认识多少词",
/// 用伪词误报率扣掉吹牛成分,最后给一个 0..20000 的估计值 + 95% 区间 + CEFR 级别。
///
/// ## 方法依据
/// - Yes/No 词汇测试:由 [Meara & Buxton 1987, "An alternative to multiple choice
///   vocabulary tests?"] 提出,后续被 Meara(1992)、Meara & Jones(1990)等大量
///   研究使用;是二语词汇量测量里成本最低、信度尚可的范式(用户只需判断"认不认识")。
/// - 伪词校准:Yes/No 测试最大的问题是**自评夸大 / 过度自信**(被试倾向对没见过的
///   词也答"认识")。插入不存在但符合英语音形规则的伪词,把伪词的"认识"率当作
///   虚报率估计,再从各档命中率里扣掉,是最经典的校正手段(Meara & Buxton 1987;
///   Anderson & Freebody 1983 的"虚假警报"框架)。本文件用减法定标
///   `h' = clamp(h - fa, 0, 1)`,与 Meara 的原始做法一致(不做 logit/信号检测论变换)。
/// - 分档抽样:词频名次与"母语者/学习者认识概率"强相关(Nation 的词汇量分档思路、
///   Zipf 频段),所以每个档位可以看成一个"难度层",层内命中率 = 该层认识比例,
///   层命中率 × 层大小 求和 = 总认识词数(分层估计量 / stratified estimate)。
/// - 区间:各档独立二项近似,层间方差相加(分层抽样的标准误差公式)。
///
/// ## 已知局限(诚实声明,UI 文案不要过度承诺)
/// 1. **自评偏差仍在**:伪词只能扣掉"整体乱答'认识'"的成分;如果用户对真词也
///    只是"好像见过"就答认识,估计仍会偏高。减法定标只做一阶校正。
/// 2. **词形归一只做启发式**:只按小写原形比对,不还原屈折/派生形
///    (running/ran/runs 各算一个词),所以"认识词数"与词表条目数对齐,
///    不等于语言学意义上的"词族数"(word family)。真实词族数通常更低。
/// 3. **上限 20000**:b6 只到名次 20000,超过部分测不到,estimate 被 clamp 到
///    20000 → 高分段(母语者/接近母语者)会被压平,表现为 C2。
/// 4. **伪词是程序生成的**:只保证"不在本地 50k 表里 + 符合音形规则",理论上可能
///    撞上一个真实但极罕见的词或专有名词(概率很低)。见 [PlacementSession] 的
///    生成注释。
/// 5. **单次测量误差大**:每档只有 12~20 题,二项噪声明显(档内 se 约 0.10~0.14),
///    本文件给出的区间是"统计抽样误差",不含自评偏差这种系统性误差。
/// 6. 速测的提前终止([PlacementResult.earlyStopped])会**截断上限**,低分用户
///    的区间会因此变窄;这是有意的成本取舍,详情见 [PlacementResult] 注释。
///
/// 本文件无依赖(只用 `dart:math` + [WordFrequency]),不联网、不用 `dart:io`。
library;

import 'dart:math';

import 'word_frequency.dart';

/// 一个词频档位(闭区间 [fromRank, toRank],名次 1 起)。
class VocabBand {
  const VocabBand(this.fromRank, this.toRank);

  final int fromRank;
  final int toRank;

  int get size => toRank - fromRank + 1;

  /// 用于 [PlacementResult.bandHitRate] 的键,如 `'1-1000'`。
  String get label => '$fromRank-$toRank';

  @override
  String toString() => 'VocabBand($label)';
}

/// 档位定义(两模式共用)。b6 上限 20000 = 本测试的测量上限。
const List<VocabBand> kVocabBands = <VocabBand>[
  VocabBand(1, 1000),
  VocabBand(1001, 2000),
  VocabBand(2001, 3000),
  VocabBand(3001, 5000),
  VocabBand(5001, 10000),
  VocabBand(10001, 20000),
];

/// 本测试的估计上限(词)。超过 20000 名次的词不测。
const int kVocabCeiling = 20000;

/// 速测/完整版每档展示的真词数。
const int kFastWordsPerBand = 12;
const int kFullWordsPerBand = 20;

/// 速测/完整版默认伪词数(全局,均匀穿插,不占任何档位名额)。
const int kFastPseudo = 4;
const int kFullPseudo = 8;

/// 提前终止阈值:某档**原始**命中率(真词答"认识"比例)低于此值 → 跳过更高档位。
const double kEarlyStopHitRate = 0.15;

/// 单题。
class PlacementItem {
  const PlacementItem({
    required this.word,
    required this.isPseudo,
    required this.bandFromRank,
    required this.bandToRank,
  });

  final String word;

  /// 是否伪词(伪词不参与任何档位命中率的分母,只进虚报率)。
  final bool isPseudo;

  /// 所属档位的名次区间;伪词的 bandFromRank > bandToRank(空区间)以表明"不属于任何档"。
  final int bandFromRank;
  final int bandToRank;

  @override
  String toString() =>
      'PlacementItem($word${isPseudo ? ',pseudo' : ',${bandFromRank ~/ 1000 + 1}'})';
}

/// 测试结果。`buildResult` 可以在没答完时调用(按已答档位计算)。
class PlacementResult {
  const PlacementResult({
    required this.estimate,
    required this.low,
    required this.high,
    required this.falseAlarmRate,
    required this.cefr,
    required this.bandHitRate,
    required this.answeredItems,
    required this.earlyStopped,
    this.grammarScore,
    this.readingScore,
    this.lowConfidence = false,
    this.skippedItems = 0,
  });

  /// 估计认识词数(0..20000)。
  final int estimate;

  /// 95% 区间(已 clamp 到 [0, 20000])。
  final int low;
  final int high;

  /// 伪词误报率:伪词里答"认识"的比例。0 = 完全诚实,越高说明自评越夸大。
  final double falseAlarmRate;

  /// 由 [estimate] 映射的 CEFR 粗级别(A1..C2)。
  final String cefr;

  /// 各档**校正前**的原始命中率,键 = [VocabBand.label](如 `'1-1000'`)。
  /// 未作答的档位不出现(提前终止跳过的档位也不会出现)。
  final Map<String, double> bandHitRate;

  /// 已作答(含 skip)的题数。
  final int answeredItems;

  /// 其中被 skip 的题数(skip 按"不认识"计入统计)。
  final int skippedItems;

  /// 是否因某档命中率过低而跳过了更高档位(跳过的档位按 0 计入 estimate)。
  final bool earlyStopped;

  /// 作答数 < [kMinAnswersForInterval] → 区间退化为 estimate ±50%,此标志为 true。
  /// UI 应提示"题量太少,区间仅供参考"。
  final bool lowConfidence;

  /// 语法小题得分(百分制),由 UI 层注入;词汇模块本身不测语法。
  final int? grammarScore;

  /// 阅读小题得分(百分制),由 UI 层注入。
  final int? readingScore;

  /// 词量 → CEFR 的粗对照表(A1 <1000 / A2 1000–2000 / B1 2000–3500 /
  /// B2 3500–6000 / C1 6000–10000 / C2 >10000)。
  ///
  /// **这是"认识词量"到级别的粗略映射,不是考试分数**:CEFR 的 B1/B2 判定还看
  /// 听说读写任务表现与语法控制,词量只是必要条件之一。真实研究里 2000~3000 词族
  /// 大致对应 A2~B1、5000 词族上下对应 B2,C1/C2 则需要更大的词量与语用能力。
  static String cefrOf(int words) {
    if (words < 1000) return 'A1';
    if (words < 2000) return 'A2';
    if (words < 3500) return 'B1';
    if (words < 6000) return 'B2';
    if (words <= 10000) return 'C1';
    return 'C2';
  }

  /// 中文一句话总结:"你在哪一档开始掉",UI 可直接展示。
  String get summaryLine {
    if (bandHitRate.isEmpty) return '还没有足够的作答数据,无法判断词汇档位。';

    // 临界点:校正命中率 < 0.5(一半都不认识)的最高档位。
    VocabBand? firstWeak;
    for (final band in kVocabBands) {
      final h = bandHitRate[band.label];
      if (h == null) break; // 未作答/被跳过的档位,不参与
      if (h < 0.5) {
        firstWeak = band;
        break;
      }
    }

    if (firstWeak == null) {
      // 全部作答档位命中率 ≥ 0.5;若因提前终止而截断,上限是"跳到的那一档"的起点。
      final lastAnswered = _lastAnsweredBand();
      final covered = lastAnswered?.toRank ?? kVocabCeiling;
      if (earlyStopped) {
        return '$covered 词以内基本认识,更高档位没测(按当前表现大概率还不会)。';
      }
      return '$covered 词以内基本认识,暂未测到你的上限。';
    }
    if (firstWeak.fromRank <= 1) {
      return '最基础的 1000 词就有不少不认识,建议先从高频词打底。';
    }
    // 用"最后一个撑住的档位"的上界作为分界点,和 estimate 的档位粒度一致
    // (例如 b2 撑住、b3 掉档 → "2000 词以内基本认识,2001 词以上开始吃力")。
    final strongTop = firstWeak.fromRank - 1;
    return '$strongTop 词以内基本认识,${firstWeak.fromRank} 词以上开始吃力。';
  }

  /// 已作答的最后一个档位(用于 [summaryLine] 的上限文案)。
  VocabBand? _lastAnsweredBand() {
    VocabBand? last;
    for (final band in kVocabBands) {
      if (bandHitRate.containsKey(band.label)) last = band;
    }
    return last;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'estimate': estimate,
        'low': low,
        'high': high,
        'falseAlarmRate': falseAlarmRate,
        'cefr': cefr,
        'bandHitRate': bandHitRate,
        'answeredItems': answeredItems,
        'skippedItems': skippedItems,
        'earlyStopped': earlyStopped,
        'lowConfidence': lowConfidence,
        if (grammarScore != null) 'grammarScore': grammarScore,
        if (readingScore != null) 'readingScore': readingScore,
      };

  @override
  String toString() => 'PlacementResult(estimate=$estimate, '
      '区间[$low,$high], cefr=$cefr, fa=${falseAlarmRate.toStringAsFixed(2)}, '
      '答$answeredItems题${earlyStopped ? ', 提前终止' : ''})';
}

/// 会话:构造题目 → 逐题作答 → 出结果。**构造时即固定全部题目顺序**(确定性,
/// 同 seed 同题目),作答只推进下标,不重新抽样。
class PlacementSession {
  /// 速测:每档 12 词 + 4 个伪词(共 64 题,约 5 分钟)。
  factory PlacementSession.fast({int seed = 1, int pseudoCount = kFastPseudo}) =>
      PlacementSession._(
        wordsPerBand: kFastWordsPerBand,
        pseudoCount: pseudoCount,
        seed: seed,
        mode: 'fast',
      );

  /// 完整版:每档 20 词 + 8 个伪词(词汇部分 136 题;语法/阅读小题由 UI 层另外做,
  /// 通过 [buildResult] 的 grammarScore/readingScore 注入合并)。
  factory PlacementSession.full({int seed = 1, int pseudoCount = kFullPseudo}) =>
      PlacementSession._(
        wordsPerBand: kFullWordsPerBand,
        pseudoCount: pseudoCount,
        seed: seed,
        mode: 'full',
      );

  PlacementSession._({
    required this.wordsPerBand,
    required int pseudoCount,
    required this.seed,
    required this.mode,
  }) : pseudoTargetCount = pseudoCount < 0 ? 0 : pseudoCount {
    _buildItems();
  }

  final int wordsPerBand;

  /// 请求的伪词数(实际可能因词表限制更少,见 [items] 实际数量)。
  final int pseudoTargetCount;

  /// 抽样种子。同 seed + 同词表 → 完全相同的题目序列与顺序(可复现、可单测)。
  final int seed;

  /// `'fast'` 或 `'full'`,仅用于展示/统计。
  final String mode;

  final List<PlacementItem> _items = <PlacementItem>[];
  final List<bool?> _responses = <bool?>[];
  final List<bool> _skipped = <bool>[];

  /// 每档实际抽到的真词数(键 = [VocabBand.label]);用于统计"该档是否答完"。
  final Map<String, int> _bandRealCount = <String, int>{};

  /// 真正生成的伪词数(词表太小时可能少于 [pseudoTargetCount])。
  int _actualPseudoCount = 0;

  int _cursor = 0;
  int _answered = 0;
  int _skippedCount = 0;
  bool _earlyStopTriggered = false;

  /// 全部题目(顺序已定,伪词已确定性穿插)。
  List<PlacementItem> get items => List<PlacementItem>.unmodifiable(_items);

  /// 当前题号(0 起);== [items].length 表示已答完。
  int get currentIndex => _cursor;

  /// 当前题目;已答完返回 null。
  PlacementItem? get currentItem => _cursor < _items.length ? _items[_cursor] : null;

  bool get isComplete => _cursor >= _items.length;

  /// 已作答(含 skip)题数。
  int get answeredCount => _answered;

  /// 被 skip 的题数(按"不认识"计入统计,但单独计数以便 UI 区分)。
  int get skippedCount => _skippedCount;

  /// 实际生成的伪词数。
  int get pseudoCount => _actualPseudoCount;

  /// 是否已触发提前终止(更高档位不会被问到)。
  bool get earlyStopTriggered => _earlyStopTriggered;

  // ---------------------------------------------------------------- 题目构建

  void _buildItems() {
    final pool = WordFrequency.rankedSize;

    // 1) 每档抽样真词。数量不足时 sampleBand 返回全部可用词(不报错,只是题变少)。
    final realBands = <List<String>>[];
    final layoutCounts = <int>[];
    for (final band in kVocabBands) {
      final words = pool <= 0
          ? const <String>[]
          : WordFrequency.sampleBand(
              band.fromRank,
              band.toRank,
              count: wordsPerBand,
              seed: seed + band.fromRank,
            );
      realBands.add(words);
      layoutCounts.add(words.length);
      _bandRealCount[band.label] = words.length;
    }

    // 2) 生成伪词。伪词基词只取高频段(名次 ≤ 3000),这样生成的伪词"看着像常见词",
    //    否则用 15000 名次的怪词改字母,用户一眼就知道是假词,校准会失效。
    final pseudoPool = pool <= 0
        ? const <String>[]
        : WordFrequency.sampleBand(1, 3000, count: 3000, seed: seed + 4242);
    final pseudoWords = _makePseudoWords(
      pseudoPool,
      pseudoTargetCount,
      seed: seed,
    );
    _actualPseudoCount = pseudoWords.length;

    // 3) 排题目顺序:按档位切成 6 个"块"([本档全部真词] + [若干伪词]),再把块拼起来。
    //    为什么按块(而不是全局打散)排:
    //    - 提前终止要能"裁掉更高档位",块状结构让裁切点干净(切在块边界);
    //    - 档位边界本身也是 UI 的进度锚点。
    //    块内伪词用 `slot_j = floor(j*n/(k+1)) - 1`(j=1..k)均匀撒开:
    //    k 个伪词把 n 个真词切成 k+1 段,伪词落在每段末尾 → 既不在开头、
    //    也不会全堆在最后,而且**不占用**任何档位的名额(真词数恒 = wordsPerBand)。
    //
    //    伪词在块间的分布:`k_i = floor((i+1)*P/6) - floor(i*P/6)`(P = 伪词总数),
    //    即"把 P 个伪词尽量均匀铺到 6 个块"。空档块是允许的,关键是不成堆:
    //    速测 P=4 → 块分布 [0,1,1,0,1,1](2/3/5/6 档各 1 个伪词);
    //    完整版 P=8 → [1,1,1,1,1,1,2] 的上限 6 档内均分,每块 1~2 个。
    final blocks = <List<PlacementItem>>[];
    final pseudoTotal = pseudoWords.length;
    var pseudoCursor = 0;
    for (var i = 0; i < kVocabBands.length; i++) {
      final band = kVocabBands[i];
      final words = realBands[i];
      final n = layoutCounts[i];

      // 本块分到的伪词数 = 前 (i+1) 块累计 floor(j*P/6) 的差分(i=0..5)。
      // 速测 P=4 → 各块 [0,1,1,0,1,1](第 2/3/5/6 档各 1 个);空块是允许的,
      // 关键是不成堆、不在开头连出。完整版 P=8 → [1,1,1,1,1,1] 之外多出的 2 个
      // 落到中间块。伪词总数恒等于 P(每块真词数 12/20 ≥ 1,槽位足够)。
      final cumBefore = ((i) * pseudoTotal / kVocabBands.length).floor();
      final cumAfter = (((i + 1) * pseudoTotal) / kVocabBands.length).floor();
      final k = n <= 0 ? pseudoTotal : cumAfter - cumBefore;

      final inline = List<String>.filled(n, '');
      final slots = <int>{};
      final span = k + 1;
      for (var j = 0; j < k && pseudoCursor + j < pseudoWords.length; j++) {
        var slot = ((j + 1) * n / span).floor() - 1;
        if (slot < 0) slot = 0;
        if (slot >= n) slot = n - 1;
        // 槽位冲突时向后找空位(保证 k 个伪词都能落下,且最多每格一个)
        while (slots.contains(slot) && slot < n - 1) {
          slot++;
        }
        slots.add(slot);
        inline[slot] = pseudoWords[pseudoCursor + j];
      }
      pseudoCursor += k;

      final block = <PlacementItem>[];
      for (var p = 0; p < n; p++) {
        if (inline[p].isNotEmpty) {
          block.add(PlacementItem(
            word: inline[p],
            isPseudo: true,
            // 伪词不属于任何档位 → 空区间
            bandFromRank: 1,
            bandToRank: 0,
          ));
        }
        block.add(PlacementItem(
          word: words[p],
          isPseudo: false,
          bandFromRank: band.fromRank,
          bandToRank: band.toRank,
        ));
      }
      // 退化情形:本档真词为 0(词表太小),伪词直接跟在块首,别丢题
      if (n == 0) {
        for (var j = k; j > 0; j--) {
          block.insert(
            0,
            PlacementItem(
              word: pseudoWords[pseudoCursor - j],
              isPseudo: true,
              bandFromRank: 1,
              bandToRank: 0,
            ),
          );
        }
      }
      blocks.add(block);
    }
    // 兜底:极端小词表下仍可能有伪词没排进去(真词不足以承载槽位),按序补在最后
    for (var i = pseudoCursor; i < pseudoWords.length; i++) {
      blocks.add(<PlacementItem>[
        PlacementItem(
          word: pseudoWords[i],
          isPseudo: true,
          bandFromRank: 1,
          bandToRank: 0,
        ),
      ]);
    }

    _items.addAll(blocks.expand((b) => b));
    _responses.addAll(List<bool?>.filled(_items.length, null));
    _skipped.addAll(List<bool>.filled(_items.length, false));
  }

  /// 生成伪词:优先用 [WordFrequency.makePseudoword](基词 = 表内前 3000 名);
  /// 若它连续失败(表太小/词都太短),退化为"取采样到的基词、交换一个字母"。
  /// 无论哪条路径都保证:纯字母、长度 ≥ 3、不在 50k 表里、不撞 clean10k。
  /// 确定性:同 seed + 同词表 → 同结果。
  static List<String> _makePseudoWords(
    List<String> bandWords,
    int count, {
    required int seed,
  }) {
    if (count <= 0) return const <String>[];
    final out = <String>[];
    final used = <String>{};
    final rng = Random(seed + 90210);
    for (var i = 0; i < count; i++) {
      String? cand = WordFrequency.makePseudoword(rng);
      cand ??= _substituteLetter(bandWords, i, seed);
      // 再兜一层:确保"可测词"形态,且没被前面用过
      if (cand == null ||
          !WordFrequency.isTestableWord(cand) ||
          WordFrequency.contains(cand) ||
          used.contains(cand)) {
        final alt = _substituteLetter(bandWords, i, seed + 1);
        cand = (alt != null &&
                WordFrequency.isTestableWord(alt) &&
                !WordFrequency.contains(alt) &&
                !used.contains(alt))
            ? alt
            : null;
      }
      if (cand == null) continue; // 生成不出来就少一题,不报错
      used.add(cand);
      out.add(cand);
    }
    return out;
  }

  /// 退化伪词:把基词某个字母换成另一个字母。
  /// 优先"元音换辅音 / 辅音换元音"(改动词形但保留可读性),
  /// 基词没有元音时插一个元音。返回 null = 无法生成。
  static String? _substituteLetter(List<String> bandWords, int i, int seed) {
    if (bandWords.isEmpty) return null;
    const vowels = 'aeiou';
    String? fallback;
    for (var t = 0; t < bandWords.length; t++) {
      final base = bandWords[(i * 977 + t * 31 + seed) % bandWords.length];
      if (base.length < 3) continue;
      final chars = base.split('');
      final pos = (i + t) % chars.length;
      final isVowel = vowels.contains(chars[pos]);
      final pool = isVowel
          ? 'bcdfghjklmnprstvwz'
          : vowels;
      final repl = pool[(i * 13 + t * 7 + seed) % pool.length];
      if (chars[pos] == repl) continue;
      final cand = [...chars]..[pos] = repl;
      final joined = cand.join();
      if (joined.length < 3) continue;
      if (!WordFrequency.isTestableWord(joined)) continue;
      if (WordFrequency.contains(joined)) continue;
      if (!isVowel) return joined; // 无元音 → 插入元音是最优解,直接用
      fallback ??= joined;
    }
    return fallback;
  }

  // ------------------------------------------------------------------- 作答

  /// 按 [currentIndex] 顺序作答。[known] = true 表示"认识"。
  /// 重复调用(已答完)是安全的空操作。
  void answer(bool known) {
    if (_cursor >= _items.length) return;
    if (_responses[_cursor] != null) return; // 该题已答过
    _responses[_cursor] = known;
    _answered++;
    _cursor++;
    _maybeEarlyStop();
  }

  /// 跳过当前题:**按"不认识"计入统计**(与 Yes/No 测试"不确定即不算认识"的
  /// 保守约定一致),同时单独计数,便于 UI 显示"已跳过 N 题"。
  void skip() {
    if (_cursor >= _items.length) return;
    if (_responses[_cursor] != null) return;
    _responses[_cursor] = false;
    _skipped[_cursor] = true;
    _answered++;
    _skippedCount++;
    _cursor++;
    _maybeEarlyStop();
  }

  /// 提前终止检查:当**当前档位的真词全部答完**且该档**原始**命中率 < [kEarlyStopHitRate]
  /// 时,把更高档位的题目从卷面移除(用户不会察觉"被跳题",因为根本不会看到)。
  ///
  /// 采样依据:低档位(高频词)命中率极低的学习者,在高档位(罕见词)几乎不可能认识
  /// —— 频率与认识概率单调相关,所以"高概率不会"是合理外推,能省掉大量无用题。
  ///
  /// 注意这里用**原始命中率 h**(真词答对比例),不用校正后的 h-fa:
  /// "该不该跳过更高档"是"他到底认不认识真词"的问题,与伪词虚报率无关。
  /// 若用 h-fa,一个真词全认识、只误判了伪词的用户会被误判成"低水平"而被截断,
  /// 反而把水平测低。虚报率只参与最终 estimate 的校正。
  ///
  /// 代价:estimate 上限被截断(跳过的档位按 0 计入),见 [PlacementResult.earlyStopped]。
  void _maybeEarlyStop() {
    if (_earlyStopTriggered) return;
    final idx = _cursor - 1;
    if (idx < 0) return;
    final item = _items[idx];
    if (item.isPseudo) return; // 伪词不触发(它不属于任何档位)

    final band = kVocabBands.firstWhere(
      (b) => b.fromRank == item.bandFromRank && b.toRank == item.bandToRank,
      orElse: () => const VocabBand(0, 0),
    );
    if (band.toRank < band.fromRank) return;
    final label = band.label;
    final total = _bandRealCount[label] ?? 0;
    if (total <= 0) return;

    // 该档真词是否答完?
    var answered = 0;
    var hits = 0;
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it.isPseudo) continue;
      if (it.bandFromRank != band.fromRank || it.bandToRank != band.toRank) {
        continue;
      }
      final r = _responses[i];
      if (r == null) continue;
      answered++;
      if (r) hits++;
    }
    if (answered < total) return; // 该档还没答完,不判定

    final h = hits / total;
    if (h >= kEarlyStopHitRate) return;

    // 触发:裁掉更高档位的题目(保留已答部分)
    _earlyStopTriggered = true;
    var keep = _items.length;
    for (var i = _cursor; i < _items.length; i++) {
      final it = _items[i];
      if (!it.isPseudo && it.bandFromRank > band.fromRank) {
        keep = i;
        break;
      }
    }
    if (keep < _items.length) {
      _items.removeRange(keep, _items.length);
      _responses.removeRange(keep, _responses.length);
      _skipped.removeRange(keep, _skipped.length);
      _actualPseudoCount = _items.where((e) => e.isPseudo).length;
    }
  }

  /// 伪词误报率:伪词答"认识"数 / 已答伪词数。没有伪词样本 → 0(不做校正)。
  double _falseAlarmRate() {
    var n = 0;
    var alarms = 0;
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].isPseudo) continue;
      final r = _responses[i];
      if (r == null) continue;
      n++;
      if (r) alarms++;
    }
    return n == 0 ? 0.0 : alarms / n;
  }

  // ------------------------------------------------------------------- 结果

  /// 生成结果。**未答完也可以调用**(按已作答的档位计算;一题没答 → estimate 0)。
  ///
  /// [grammarScore] / [readingScore]:语法与阅读小题的百分制得分,由 UI 层注入,
  /// 词汇模块不测它们,只是把分数合并进同一个结果对象,方便 UI 一起展示/存库。
  PlacementResult? buildResult({int? grammarScore, int? readingScore}) {
    final fa = _falseAlarmRate();

    final bandHitRate = <String, double>{};
    final perBandSe = <double>[]; // 各档 se × 档大小(用于合并方差)
    var estimateRaw = 0.0;
    var hasBandData = false;

    for (final band in kVocabBands) {
      // 统计该档已答真词
      var answered = 0;
      var hits = 0;
      for (var i = 0; i < _items.length; i++) {
        final it = _items[i];
        if (it.isPseudo) continue;
        if (it.bandFromRank != band.fromRank || it.bandToRank != band.toRank) {
          continue;
        }
        final r = _responses[i];
        if (r == null) continue;
        answered++;
        if (r) hits++;
      }
      if (answered == 0) break; // 该档没答 → 更高档更没答,直接收尾

      hasBandData = true;
      final h = hits / answered;
      bandHitRate[band.label] = h;

      // 校正:h' = clamp(h - fa, 0, 1)
      final corrected = (h - fa).clamp(0.0, 1.0);
      final size = band.size; // 用档位标称大小,而非"表里实际有几个词"
      estimateRaw += corrected * size;

      // 单档二项标准误:se = sqrt(p(1-p)/n),p 用校正后命中率(估计的"真实认识率")。
      // 有限总体校正:本档只有 size 个词、抽了 n 个且不放回 → ×sqrt((N-n)/(N-1)),
      // 档内抽得越满,误差越小(速测 n=12/N=1000 时约等于 1,可忽略)。
      final p = corrected;
      final n = answered;
      var se = sqrt(p * (1 - p) / n);
      if (size > 1 && size > n) {
        se *= sqrt((size - n) / (size - 1));
      }
      perBandSe.add(se * size);

      // 提前终止的判断口径:用**原始**命中率(真词答对比例),不用校正值 ——
      // "该不该跳过更高档"是"他到底认不认识真词"的问题,与伪词虚报率无关。
      // 若提前终止已触发,后面的档位没题可答,循环自然在下一步 break。
      if (answered >= (_bandRealCount[band.label] ?? 0) &&
          h < kEarlyStopHitRate) {
        break;
      }
    }

    // 方差合并:Var(Σ h'_b × N_b) = Σ (se_b × N_b)²(档间独立假设)
    var seTotal = 0.0;
    for (final v in perBandSe) {
      seTotal += v * v;
    }
    seTotal = sqrt(seTotal);

    final estimate = estimateRaw.round().clamp(0, kVocabCeiling);
    var low = (estimate - 1.96 * seTotal).floor();
    var high = (estimate + 1.96 * seTotal).ceil();
    var lowConfidence = false;

    if (_answered < kMinAnswersForInterval) {
      // 题量太少,二项近似不可靠(也会出现 se=0 的假精确)→ 退化为 ±50% 保守区间
      lowConfidence = true;
      low = (estimate * 0.5).floor();
      high = (estimate * 1.5).ceil();
    }
    low = low.clamp(0, kVocabCeiling);
    high = high.clamp(0, kVocabCeiling);
    if (high < low) high = low;

    if (!hasBandData) {
      return PlacementResult(
        estimate: 0,
        low: 0,
        high: 0,
        falseAlarmRate: fa,
        cefr: PlacementResult.cefrOf(0),
        bandHitRate: bandHitRate,
        answeredItems: _answered,
        skippedItems: _skippedCount,
        earlyStopped: _earlyStopTriggered,
        lowConfidence: true,
        grammarScore: grammarScore,
        readingScore: readingScore,
      );
    }

    return PlacementResult(
      estimate: estimate,
      low: low,
      high: high,
      falseAlarmRate: fa,
      cefr: PlacementResult.cefrOf(estimate),
      bandHitRate: bandHitRate,
      answeredItems: _answered,
      skippedItems: _skippedCount,
      earlyStopped: _earlyStopTriggered,
      lowConfidence: lowConfidence,
      grammarScore: grammarScore,
      readingScore: readingScore,
    );
  }
}

/// 低于这个作答数 → [PlacementResult.lowConfidence] = true,区间退化为 ±50%。
const int kMinAnswersForInterval = 20;
