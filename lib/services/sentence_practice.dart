/// 写句阶多题型练习(v3 批 8 · P1-5)。
///
/// 背景(用户 2026-11-01 的批注):「写句阶只有回译一条路,想要自选练习方式」。
/// 这个文件是**纯逻辑层**,三种题型共用:
/// 1. **句式改写**:AI 出"原句 + 改写要求 + 参考改写",用回译 rubric 批改;
///    联网/模型不可用时自动降级为**离线对照模式**(只给原句 + 可改写点,不评分,
///    绝不白屏);
/// 2. **错句纠错**:程序化往正确句子里植入常见错误(时态/主谓一致/冠词/搭配/拼写),
///    用户改回原句 → 精确比对;错误类型按错误档案既有 tag 记入;
/// 3. **连词成句**:句子打散成词块(标点粘在前一个词上),点选拼句 → 比对。
///
/// 三条纪律(会被单测钉住):
/// - **不联网可测**:AI 调用可注入假响应;离线路径全部是纯函数;
/// - **答案不泄漏**:纠错题在提交前只给错句,正确句与错误点解释留在模型里,
///   提交后才展示;改写题的参考改写同理("看参考"是用户主动点的动作);
/// - **结果要回流**:错题按题型写 `output_attempts`(mode = rewrite/correction/
///   word_order)+ 错误档案 tag —— 练了不留痕等于没练(P1-2 的教训)。
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'base_api.dart';
import 'database.dart';
import 'deepseek_api.dart';
import 'output_bank.dart';
import 'output_composer.dart';
import 'output_feedback.dart';
import 'output_rubric.dart';


// ═══════════════════════════════════════════════════════════════════════
// 一、句子来源:读过的材料优先,内置范文句兜底
// ═══════════════════════════════════════════════════════════════════════

/// 句式练习的句子来源。
///
/// 为什么"读过的材料优先":用户反复强调练习要基于**自己读过的内容**
/// (背单词要语境、写作要仿写自己读过的句子)。从刚读过的材料里抽句,
/// 改写/纠错才有上下文;读不到材料(新装/全没读)时回退内置范文句,
/// 保证任何时候都有题可练 —— 离线也不许出现"没有素材"的白屏。
class SentencePracticeSource {
  SentencePracticeSource._();

  /// 从**读过的材料**正文里抽句子(最近读的优先)。
  ///
  /// 口径:
  /// - 只取 `material_progress.percent > 0`(真的打开读过)的材料,最多 [maxMaterials] 份;
  /// - 每份材料按阅读器的正文分块顺序拼回,再用 [extractSentences] 抽合格句
  ///   (6~40 词、去重、按原文顺序) —— 与回译出题同一套切句口径;
  /// - 抽不到返回空列表(调用方回退内置)。
  static Future<List<String>> fromReadMaterials({
    int count = 5,
    int maxMaterials = 8,
  }) async {
    if (count <= 0) return const <String>[];
    final out = <String>[];
    final seen = <String>{};
    try {
      final materials = await DatabaseService.getRecentMaterials(
        limit: maxMaterials,
      );
      for (final row in materials) {
        if (out.length >= count) break;
        final percent = (row['percent'] as num?)?.toDouble() ?? 0;
        final finishedAt = DateTime.tryParse('${row['finished_at'] ?? ''}');
        if (percent <= 0 && finishedAt == null) continue;
        final id = (row['material_id'] as num?)?.toInt() ??
            (row['id'] as num?)?.toInt();
        if (id == null) continue;
        final chunks = await DatabaseService.getMaterialChunks(id);
        final text = chunks
            .map((c) => '${c['text'] ?? ''}')
            .where((t) => t.trim().isNotEmpty)
            .join('\n\n');
        if (text.isEmpty) continue;
        for (final sentence in extractSentences(text, max: count - out.length)) {
          if (seen.add(sentence.toLowerCase())) out.add(sentence);
        }
      }
    } catch (e) {
      debugPrint('ReadFlow 从读过的材料抽句失败(已降级到内置): $e');
    }
    return out;
  }

  /// 内置范文句(英中对照库里的英文句)。
  ///
  /// [seed] 给定 = 可复现(测试/回看用);不传则按当天日期轮换 ——
  /// 同一用户不同天进来看到不同句子,但同一天两次进入一致(不会"刷新就变")。
  static List<String> fromBuiltin({int count = 5, int? seed}) {
    if (count <= 0) return const <String>[];
    final pool = [for (final pair in OutputBank.essaySentences) pair.en];
    if (pool.isEmpty) return const <String>[];
    final rng = Random(
      seed ?? DateTime.now().year * 10000 + DateTime.now().month * 100 + DateTime.now().day,
    );
    final copy = List<String>.of(pool)..shuffle(rng);
    return copy.take(count).toList(growable: false);
  }

  /// UI 首选入口:读过的材料优先,不足用内置范文句补齐(去重)。
  ///
  /// 永远返回非空列表(只要内置库还在)—— 空列表会让三种题型都没题,
  /// 那是"白屏",不可接受。
  static Future<List<String>> load({int count = 5, int? seed}) async {
    final material = await fromReadMaterials(count: count);
    if (material.length >= count) return material;
    final out = <String>[...material];
    final seen = {for (final s in out) s.toLowerCase()};
    for (final builtin in fromBuiltin(count: count * 2, seed: seed)) {
      if (out.length >= count) break;
      if (seen.add(builtin.toLowerCase())) out.add(builtin);
    }
    return out;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 二、句式改写:AI 出题 + 离线对照兜底
// ═══════════════════════════════════════════════════════════════════════

/// AI 句式改写出题器。
///
/// 为什么单独一个类而不是塞进 [OutputComposer]:`OutputComposer` 现有的三个
/// 入口是"材料/段落/真题",写句的"改写"只需要"给定句子 → 出改写题"这一条窄路径;
/// 单独一层还能**注入假 API** 给单测(不联网夹具),不必为了测出题去读 Hive 配置。
///
/// 失败约定:**任何失败返回 null**(未配置/网络/解析空/模型自造句子),
/// 由界面切到离线对照模式 —— 用户永远有题可练。
class SentenceRewriteGenerator {
  SentenceRewriteGenerator({DeepseekApiService? api})
      : _api = api ?? DeepseekApiService();

  final DeepseekApiService _api;

  /// 是否可用(UI 可据此提示"当前是离线对照模式")。
  bool get available => _api.isConfigured;

  /// 生成 [count] 道改写题。
  ///
  /// [rewriteFocus] 对应提示词里的"改写方向"(升级句式/合并从句/换更自然表达);
  /// 返回的题只保留**输入集合里的原句**(模型自造的句子一律丢弃 —— 题源必须可追溯)。
  Future<List<OutputTaskSpec>?> generate({
    required List<String> sentences,
    String rewriteFocus = '升级句式',
    String levelHint = '',
    int count = 5,
  }) async {
    final cleaned = _cleanSentences(sentences);
    if (cleaned.isEmpty || count <= 0) return null;
    if (!_api.isConfigured) return null;
    final prompt = buildSentenceRewritePrompt(
      originalSentences: cleaned,
      rewriteFocus: rewriteFocus,
      levelHint: levelHint,
      count: count,
    );
    try {
      final cfg = _api.config;
      final path = cfg.isDeepSeekOfficial
          ? '/v1/chat/completions'
          : '/chat/completions';
      final response = await _api.postWithReasoningFallback(
        path,
        BaseApiService.buildChatBody(
          cfg: cfg,
          temperature: 0.4,
          maxTokens: 2048,
          messages: [
            {'role': 'system', 'content': prompt.system},
            {'role': 'user', 'content': prompt.user},
          ],
        ),
        cfg: cfg,
        // 出题是"一次算完才返回":60s 足够,又不让用户干等 3 分钟
        receiveTimeout: const Duration(seconds: 60),
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final content = BaseApiService.extractContentWithReasoning(data);
      final parsed = parseSentenceRewriteTasks(content);
      final tasks = _keepKnownSentences(parsed, cleaned, count);
      return tasks.isEmpty ? null : tasks;
    } catch (e) {
      debugPrint('ReadFlow 句式改写出题失败(已降级离线模式): $e');
      return null;
    }
  }

  /// 只保留"原句确实来自输入"的题,并按原句去重。
  ///
  /// 为什么要这道闸:模型偶尔会把原句自己"润色"一下再当 prompt_en 返回 ——
  /// 那样用户改写的对象就不是他读过的句子,题源不可追溯,也会让"参考改写"
  /// 看起来像在纠正原句。
  static List<OutputTaskSpec> _keepKnownSentences(
    List<OutputTaskSpec> tasks,
    List<String> allowed,
    int count,
  ) {
    final byKey = {for (final s in allowed) s.toLowerCase(): s};
    final out = <OutputTaskSpec>[];
    final seen = <String>{};
    for (final task in tasks) {
      final key = task.promptEn.trim().toLowerCase();
      final origin = byKey[key];
      if (origin == null) continue;
      if (!seen.add(key)) continue;
      out.add(task);
      if (out.length >= count) break;
    }
    return out;
  }

  static List<String> _cleanSentences(List<String> sentences) {
    final out = <String>[];
    for (final raw in sentences) {
      final s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (s.isEmpty) continue;
      if (!out.any((e) => e.toLowerCase() == s.toLowerCase())) out.add(s);
    }
    return out;
  }
}

/// 离线改写任务(没有 AI 时也能练:给原句 + 可改写点,仅对照不评分)。
class OfflineRewriteTask {
  /// 原句(用户要改写的对象)
  final String original;

  /// 可改写点(连接词/结构标记的中文说明;界面高亮展示)
  final List<String> focusPoints;

  /// 一句练习方向(必须可执行,不能是"多练练")
  final String guidance;

  const OfflineRewriteTask({
    required this.original,
    required this.focusPoints,
    required this.guidance,
  });
}

/// 离线改写任务生成(纯函数,可单测)。
///
/// 依据是句子里的**真实结构标记**(and/but/which/because/while/It is…),
/// 没有匹配到时给一句通用方向(合并短句/加从句/换更自然的表达),
/// 但绝不编造"参考改写" —— 离线没有权威答案时,只做对照不评分。
/// 覆盖的句式标记 → 改写方向。**顺序有意义**:先具体结构,再通用连接词。
///
/// [pattern] 是**源字符串**而不是 RegExp:常量列表里写 RegExp 无法 const 化
/// (RegExp 构造不是 const),而这里只需要"模式 + 说明"的静态字典。
const List<({String pattern, String focus, String guidance})> _rewriteFocusRules = [
  (
    pattern: r'\bwhich\b',
    focus: '非限制性定语从句(which)',
    guidance: '把 which 从句改成更短的表达:名词短语同位语 / 分词短语,句意不变',
  ),
  (
    pattern: r'\bthat\b',
    focus: 'that 从句',
    guidance: '试试把 that 从句拆成两个短句,或用 it 作形式主语让句子更利落',
  ),
  (
    pattern: r'\b(and)\b',
    focus: 'and 并列',
    guidance: '把 and 连接的两部分合并成从句或分词短语,避免流水句',
  ),
  (
    pattern: r'\b(but|however)\b',
    focus: '转折(but/however)',
    guidance: '把转折改成 While/Although 让步从句,或用 Despite 短语',
  ),
  (
    pattern: r'\b(because|so)\b',
    focus: '因果(because/so)',
    guidance: '改成 The reason why… lies in… 或分词作结果状语',
  ),
  (
    pattern: r'\b(while|although|though)\b',
    focus: '让步/对比(while/although)',
    guidance: '保留让步关系,尝试 Despite + 名词短语或倒装结构',
  ),
  (
    pattern: r'\bif\b',
    focus: '条件句(if)',
    guidance: '试虚拟语气(与现在/过去事实相反)或 Unless 改写',
  ),
  (
    pattern: r'\bIt is\b',
    focus: '形式主语(It is…)',
    guidance: '换成真正的主语从句(What…/That…)或名词短语作主语',
  ),
  (
    pattern: r'\bthere\b',
    focus: 'there be 结构',
    guidance: '改成实义动词作谓语的句子,信息更直接',
  ),
];

List<OfflineRewriteTask> buildOfflineRewriteTasks(
  List<String> sentences, {
  int count = 5,
  int? seed,
}) {
  final out = <OfflineRewriteTask>[];
  final seen = <String>{};
  for (final raw in sentences) {
    if (out.length >= count) break;
    final sentence = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (sentence.isEmpty) continue;
    if (!seen.add(sentence.toLowerCase())) continue;
    final focus = <String>[];
    final guides = <String>[];
    for (final rule in _rewriteFocusRules) {
      if (!RegExp(rule.pattern, caseSensitive: false).hasMatch(sentence)) {
        continue;
      }      focus.add(rule.focus);
      if (guides.isEmpty) guides.add(rule.guidance);
      if (focus.length >= 3) break;
    }
    if (focus.isEmpty) {
      focus.add('句式多样性');
      guides.add('合并短句、补一个从句,或换更自然的主语开头(句意不变)');
    }
    out.add(OfflineRewriteTask(
      original: sentence,
      focusPoints: focus,
      guidance: guides.first,
    ));
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════
// 三、错句纠错:程序化植入错误 + 精确比对
// ═══════════════════════════════════════════════════════════════════════

/// 一处被程序化植入的错误。
///
/// [correct] 与 [noteZh] **提交前不能显示** —— 它们就是答案;
/// 界面在用户提交后才用它们做逐点对照。
class ErrorSpot {
  /// 错误类型(与错误档案 tag 体系对齐:时态/主谓一致/冠词/搭配/拼写)
  final String kind;

  /// 错句中出现的错误文本(用于定位/对照)
  final String wrong;

  /// 正确文本(原句里的写法)
  final String correct;

  /// 中文说明(提交后才显示)
  final String noteZh;

  const ErrorSpot({
    required this.kind,
    required this.wrong,
    required this.correct,
    required this.noteZh,
  });

  @override
  String toString() => 'ErrorSpot($kind: $wrong → $correct)';
}

/// 一道纠错题:错句 + 原句 + 错误点清单。
class InjectedError {
  /// 原句(正确句子;提交前不显示)
  final String correctSentence;

  /// 展示给用户的错句(提交前唯一可见的句子)
  final String wrongSentence;

  /// 植入的错误点(至少 1 条;空列表的句子不该出题)
  final List<ErrorSpot> spots;

  const InjectedError({
    required this.correctSentence,
    required this.wrongSentence,
    required this.spots,
  });

  bool get hasErrors => spots.isNotEmpty;

  /// 提交前给用户看的提示语(**不说错在哪、更不给改正后的词**)
  String get prompt =>
      '下面这句话被故意改坏了 ${spots.length} 处,请把它改回正确的英文句子。';
}

/// 一条植入规则:[pattern] 命中后由 [build] 生成替换。
///
/// 单独抽成"规则表"而不是一串 if:新增一类错误只要加一行规则,
/// 测试也能逐类断言"这个句子能不能命中时态错误"。
class _InjectRule {
  final String kind;
  final RegExp pattern;
  final String noteZh;

  /// 返回 (错误文本, 正确文本);返回 null = 这条规则这次不适用
  final (String, String) Function(RegExpMatch match, Random rng) build;

  const _InjectRule(this.kind, this.pattern, this.noteZh, this.build);
}

/// 拼写错误词典(用真实常见拼错,而不是随机换字母 —— 学生真的会这么错)。
const Map<String, String> _commonMisspellings = {
  'acknowledged': 'acknowleged',
  'technology': 'tecnology',
  'environment': 'enviroment',
  'development': 'developement',
  'convenient': 'convinient',
  'important': 'improtant',
  'because': 'becuase',
  'definitely': 'definately',
  'separate': 'seperate',
  'receive': 'recieve',
  'believe': 'beleive',
  'necessary': 'neccessary',
  'foreign': 'foriegn',
  'government': 'goverment',
  'experience': 'experiance',
  'opportunity': 'opurtunity',
  'successful': 'sucessful',
  'knowledge': 'knowlege',
  'different': 'differant',
};

/// 搭配错误规则(把正确搭配换成中国学生常见的错误介词)。
const List<({String from, String to, String note})> _collocationErrors = [
  (from: 'plays a vital role in', to: 'plays a vital role to', note: '固定搭配是 play a role in'),
  (from: 'contributes to', to: 'contributes for', note: 'contribute 后接 to'),
  (from: 'worried about', to: 'worried of', note: 'be worried about 是固定搭配'),
  (from: 'the key to', to: 'the key of', note: 'the key to 是固定搭配'),
  (from: 'advantage of', to: 'advantage for', note: 'advantage of 是固定搭配'),
  (from: 'lack of', to: 'lack for', note: 'lack of 是固定搭配'),
  (from: 'interested in', to: 'interested on', note: 'be interested in 是固定搭配'),
  (from: 'good at', to: 'good in', note: 'be good at 是固定搭配'),
  (from: 'based on', to: 'based in', note: 'be based on 是固定搭配'),
  (from: 'according to', to: 'according with', note: 'according to 是固定搭配'),
  (from: 'reason why', to: 'reason for why', note: 'the reason why 是固定搭配'),
  (from: 'way of thinking', to: 'way for thinking', note: 'a way of doing 是固定搭配'),
  (from: 'depends on', to: 'depends of', note: 'depend on 是固定搭配'),
  (from: 'compared with', to: 'compared to', note: 'compared with/to 都可,但这里应保持原搭配'),
  (from: 'treat this issue', to: 'treat this issue', note: ''),
];

/// 拼写规则的通用兜底:选一个长度 ≥8 的词,按种子交换相邻两位字母。
/// (词典优先,因为"真实拼错"对学生更有辨识价值;这条只保证任何长句都能出拼写题。)
(String, String)? _fallbackSpelling(String sentence, Set<int> usedRanges, Random rng) {
  final matches = RegExp(r"[A-Za-z']{8,}").allMatches(sentence).toList();
  if (matches.isEmpty) return null;
  final candidates = [
    for (final m in matches)
      if (!_overlaps(usedRanges, m.start, m.end)) m,
  ];
  if (candidates.isEmpty) return null;
  final match = candidates[rng.nextInt(candidates.length)];
  final word = match.group(0)!;
  // 不在首尾交换(首字母/词尾变化太容易被误认成别的词);保留大小写
  final pos = 1 + rng.nextInt(word.length - 3);
  final chars = word.split('');
  final left = chars[pos];
  chars[pos] = chars[pos + 1];
  chars[pos + 1] = left;
  final typo = chars.join();
  if (typo == word) return null;
  return (typo, word);
}

bool _overlaps(Set<int> usedRanges, int start, int end) {
  // usedRanges 里存的是 [start, end) 区间的 start*10000+end,逐条比一下即可
  for (final packed in usedRanges) {
    final s = packed ~/ 100000;
    final e = packed % 100000;
    if (start < e && s < end) return true;
  }
  return false;
}

/// 规则表:顺序 = 施加顺序(时态 → 主谓一致 → 冠词 → 搭配 → 拼写,每类最多 1 处)。
///
/// 为什么每类最多 1 处:纠错题的目的是"辨别错误类型",同一类出现 3 次会让
/// 句子面目全非;而且错点太多时用户改不完,体验反而差。
final List<_InjectRule> _injectRules = [
  // ── 时态 ──
  _InjectRule('时态', RegExp(r'\b(is|are|was|were)\b', caseSensitive: false),
      '时态不一致:与全句时间背景不符', (match, rng) {
    final correct = match.group(0)!;
    return ('will be', correct);
  }),
  _InjectRule('时态', RegExp(r'\b(has|have|had)\b', caseSensitive: false),
      '时态不一致:与全句时间背景不符', (match, rng) {
    final correct = match.group(0)!;
    return ('will have', correct);
  }),
  // ── 主谓一致 ──
  _InjectRule('主谓一致', RegExp(r'\b(is|are)\b', caseSensitive: false),
      '主谓一致:be 动词与主语单复数不一致', (match, rng) {
    final correct = match.group(0)!;
    final wrong = correct.toLowerCase() == 'is' ? 'are' : 'is';
    return (wrong, correct);
  }),
  _InjectRule('主谓一致', RegExp(r'\b(has|have)\b', caseSensitive: false),
      '主谓一致:have/has 与主语单复数不一致', (match, rng) {
    final correct = match.group(0)!;
    final wrong = correct.toLowerCase() == 'has' ? 'have' : 'has';
    return (wrong, correct);
  }),
  _InjectRule('主谓一致',
      RegExp(r'\b(plays|takes|makes|gives|shows|means|helps|brings|tells|requires)\b',
          caseSensitive: false),
      '主谓一致:第三人称单数丢了 -s', (match, rng) {
    final correct = match.group(0)!;
    return (correct.substring(0, correct.length - 1), correct);
  }),
  // ── 冠词 ──
  _InjectRule('冠词', RegExp(r'\ban\b(?=\s+[aeiou])', caseSensitive: false),
      '冠词:元音音素前仍用 a', (match, rng) {
    final correct = match.group(0)!;
    return ('a', correct);
  }),
  _InjectRule('冠词', RegExp(r'\ba\b(?=\s+[^aeiou\s])', caseSensitive: false),
      '冠词:辅音音素前不能用 an', (match, rng) {
    final correct = match.group(0)!;
    return ('an', correct);
  }),
  _InjectRule('冠词', RegExp(r'\bthe\b', caseSensitive: false),
      '冠词:特指与泛指用错', (match, rng) {
    final correct = match.group(0)!;
    return ('a', correct);
  }),
  // ── 搭配 ──
  for (final item in _collocationErrors)
    if (item.note.isNotEmpty)
      _InjectRule(
        '搭配',
        RegExp(RegExp.escape(item.from), caseSensitive: false),
        item.note,
        (match, rng) => (item.to, match.group(0)!),
      ),
  // ── 拼写(词典优先;通用兜底单独处理) ──
  for (final entry in _commonMisspellings.entries)
    _InjectRule(
      '拼写',
      RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false),
      '拼写错误:${entry.value} 应为 ${entry.key}',
      (match, rng) => (entry.value, match.group(0)!),
    ),
];

/// 往一个正确句子里植入常见错误(纯函数,可复现)。
///
/// [seed] 相同 → 输出完全相同(测试/复盘可重现);不传说明每次出题可以不同。
/// 返回 null = 这个句子不适合出纠错题(太短 / 所有规则都没命中)。
///
/// 纪律:**每类错误最多植入 1 处**,且不重叠;`spots` 里记录正确文本,
/// 但错误文本之外的原文**原样保留** —— 用户改的是"被改坏的地方",
/// 不是重写整句(那样无法精确比对)。
InjectedError? injectErrors(
  String sentence, {
  int? seed,
  List<String> kinds = const ['时态', '主谓一致', '冠词', '搭配', '拼写'],
}) {
  final original = sentence.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (original.isEmpty) return null;
  // 少于 4 个词的句子改一处就面目全非,不适合做纠错题
  if (original.split(' ').length < 4) return null;

  final rng = Random(seed ?? original.hashCode);
  final used = <String>{}; // 已植入的错误类型
  final usedRanges = <int>{}; // 防重叠:[start,end) 打包
  final mutations = <({int start, int end, String replacement, ErrorSpot spot})>[];

  void applyRule(_InjectRule rule) {
    if (used.contains(rule.kind)) return;
    final matches = [
      for (final m in rule.pattern.allMatches(original))
        if (!_overlaps(usedRanges, m.start, m.end)) m,
    ];
    if (matches.isEmpty) return;
    final match = matches[rng.nextInt(matches.length)];
    final (wrong, correct) = rule.build(match, rng);
    if (wrong == correct || wrong.isEmpty) return;
    // 错误文本必须真的不同,且替换后句子仍以错文本为主
    mutations.add((
      start: match.start,
      end: match.end,
      replacement: wrong,
      spot: ErrorSpot(
        kind: rule.kind,
        wrong: wrong,
        correct: correct,
        noteZh: rule.noteZh,
      ),
    ));
    used.add(rule.kind);
    usedRanges.add(match.start * 100000 + match.end);
  }

  // 按 kinds 的顺序施加(界面可只练某几类);拼写兜底放在词典规则之后
  for (final kind in kinds) {
    for (final rule in _injectRules.where((r) => r.kind == kind)) {
      applyRule(rule);
      if (used.contains(kind)) break;
    }
    if (kind == '拼写' && !used.contains('拼写')) {
      final fallback = _fallbackSpelling(original, usedRanges, rng);
      if (fallback != null) {
        final (typo, word) = fallback;
        final match = RegExp(RegExp.escape(word)).firstMatch(original);
        if (match != null && !_overlaps(usedRanges, match.start, match.end)) {
          mutations.add((
            start: match.start,
            end: match.end,
            replacement: typo,
            spot: ErrorSpot(
              kind: '拼写',
              wrong: typo,
              correct: word,
              noteZh: '拼写错误:$typo 应为 $word',
            ),
          ));
          used.add('拼写');
          usedRanges.add(match.start * 100000 + match.end);
        }
      }
    }
  }

  if (mutations.isEmpty) return null;
  // 从后往前替换,前面的下标才不会漂移(String 没有 replaceRange,
  // 用"切片拼接":不断在末尾追加前面那段 + 替换文本,最后一次补尾部)
  mutations.sort((a, b) => b.start.compareTo(a.start));
  var wrongSentence = original;
  for (final m in mutations) {
    wrongSentence = wrongSentence.replaceRange(m.start, m.end, m.replacement);
  }
  if (wrongSentence == original) return null;
  mutations.sort((a, b) => a.start.compareTo(b.start));
  return InjectedError(
    correctSentence: original,
    wrongSentence: wrongSentence,
    spots: [for (final m in mutations) m.spot],
  );
}

/// 纠错判定结果。
class CorrectionCheck {
  /// 是否改对(与正确句/任一接受答案一致)
  final bool correct;

  /// 规范化后的用户答案(展示"你写的是"用)
  final String normalizedAnswer;

  /// 答错时:用户**没改对**的错误点(答对时为空)
  final List<ErrorSpot> missed;

  /// 是否命中了某个"接受答案"(一个错误可以有多种合法改法时的兜底)
  final bool matchedAccepted;

  const CorrectionCheck({
    required this.correct,
    required this.normalizedAnswer,
    this.missed = const [],
    this.matchedAccepted = false,
  });
}

/// 句子规范化(纠错/连词成句共用):
/// - 去首尾空白、内部空白折叠成一个空格;
/// - 忽略大小写(用户把 It 写成 it 不该判错);
/// - **只忽略句尾标点**(句号/问号/感叹号):句中标点是纠错的一部分,不能吞掉。
String normalizeSentence(String text) {
  var s = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'[.!?。！？]+$'), '').trim();
  return s.toLowerCase();
}

/// 纠错比对:忽略大小写、首尾空白、句尾标点;多解用 [acceptedAnswers]。
CorrectionCheck checkCorrection({
  required String answer,
  required InjectedError injected,
  List<String> acceptedAnswers = const [],
}) {
  final normalized = normalizeSentence(answer);
  final correctKey = normalizeSentence(injected.correctSentence);
  var matchedAccepted = false;
  var ok = normalized.isNotEmpty && normalized == correctKey;
  if (!ok) {
    for (final accepted in acceptedAnswers) {
      if (normalized.isNotEmpty && normalizeSentence(accepted) == normalized) {
        ok = true;
        matchedAccepted = true;
        break;
      }
    }
  }
  // 答错时算出"哪些错误点还没改对":用户答案里仍出现错误写法、且没有正确写法
  final missed = <ErrorSpot>[];
  if (!ok) {
    final low = normalized;
    for (final spot in injected.spots) {
      final wrong = normalizeSentence(spot.wrong);
      final right = normalizeSentence(spot.correct);
      if (wrong.isEmpty) continue;
      if (low.contains(wrong) && !low.contains(right)) missed.add(spot);
    }
  }
  return CorrectionCheck(
    correct: ok,
    normalizedAnswer: normalized,
    missed: missed,
    matchedAccepted: matchedAccepted,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 四、连词成句:打散 + 点选 + 比对
// ═══════════════════════════════════════════════════════════════════════

/// 一道连词成句题。
class WordOrderTask {
  /// 原句(正确顺序的事实源)
  final String sentence;

  /// 正确词块顺序(分词口径见 [tokenizeSentence])
  final List<String> correctOrder;

  /// 打散后的展示顺序(与 [correctOrder] 同集合)
  final List<String> chunks;

  const WordOrderTask({
    required this.sentence,
    required this.correctOrder,
    required this.chunks,
  });

  /// 用户点选的词块是否已拼回原句
  bool get isComplete => chunks.length == correctOrder.length;
}

/// 句子 → 词块(纯函数)。
///
/// 标点处理是这题的**判分关键**:
/// - 句读标点 `, . ! ? ; :` 单独成块时,粘到**前一个词**上("world ," → "world,");
/// - 词内标点(one's / well-known / 3.5)原样保留;
/// - 句首/句尾的引号保留在所在词上。
List<String> tokenizeSentence(String sentence) {
  final text = sentence.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return const <String>[];
  final out = <String>[];
  for (final raw in text.split(' ')) {
    final token = raw.trim();
    if (token.isEmpty) continue;
    // 纯标点块:粘到前一个词(前面没词就粘到后一个——极端脏数据兜底)
    if (RegExp(r'^[,\.!?;:]+$').hasMatch(token)) {
      if (out.isNotEmpty) {
        out[out.length - 1] = '${out.last}$token';
        continue;
      }
      out.add(token);
      continue;
    }
    // 后半截是标点的词块(用户输入 "world ." 会被上面分支处理;
    // 这里只处理 "world," 这种已粘连的正常情况)
    out.add(token);
  }
  return out;
}

/// 打散词块(纯函数,可复现)。
///
/// 保证:同 [seed] → 同顺序;[seed] 为空时用句子 hashCode(同一句每次进来顺序稳定,
/// 用户不会"刷新一次换一个样");长度 >1 时**保证不等于原顺序**(否则这题白给)。
List<String> shuffleWords(String sentence, {int? seed}) {
  final order = tokenizeSentence(sentence);
  if (order.length <= 1) return List<String>.of(order);
  final rng = Random(seed ?? sentence.hashCode);
  final shuffled = List<String>.of(order);
  for (var attempt = 0; attempt < 8; attempt++) {
    shuffled.shuffle(rng);
    final same = _sameOrder(shuffled, order);
    if (!same) return shuffled;
  }
  // 8 次都还原成原序(概率极低):手动把第一个词挪到末尾,保证不是原序
  final first = shuffled.removeAt(0);
  shuffled.add(first);
  return shuffled;
}

/// 生成一道连词成句题([seed] 可复现)。
WordOrderTask buildWordOrderTask(String sentence, {int? seed}) {
  final order = tokenizeSentence(sentence);
  return WordOrderTask(
    sentence: sentence.trim(),
    correctOrder: order,
    chunks: shuffleWords(sentence, seed: seed),
  );
}

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 连词成句比对:用户按点选顺序拼出的词块必须与正确顺序一致。
///
/// 口径与纠错一致:大小写、句尾标点可容错;**词块内部标点不一致算错**
/// (逗号放错位置本来就是这类题要练的点)。
bool checkWordOrder(String sentence, List<String> picked) {
  final expected = tokenizeSentence(sentence);
  if (picked.length != expected.length) {
    // 长度不同也可能只是标点差异(用户少选/多选),先按规范化比一次
    return normalizeSentence(picked.join(' ')) == normalizeSentence(sentence) &&
        picked.length >= expected.length;
  }
  return _sameOrder(picked, expected) ||
      normalizeSentence(picked.join(' ')) == normalizeSentence(sentence);
}

// ═══════════════════════════════════════════════════════════════════════
// 五、结果统一回流(attempts + 错误档案)
// ═══════════════════════════════════════════════════════════════════════

/// 写句阶三种题型的落库 mode(与 output_attempts.mode 对齐)。
enum SentencePracticeMode {
  rewrite('rewrite', '句式改写'),
  correction('correction', '错句纠错'),
  wordOrder('word_order', '连词成句');

  const SentencePracticeMode(this.id, this.label);

  final String id;
  final String label;
}

/// 一次写句练习的结果记录器(三种题型共用)。
///
/// 为什么收在一处:任务明确要求"结果统一" —— 三种题型如果各写各的
/// `insertOutputAttempt`,字段口径(mode/score_json/error_tags_json)迟早分裂;
/// 这里同时负责两件事:
/// 1. 写 `output_attempts`(mode = rewrite/correction/word_order);
/// 2. 答错时把错误类型写进错误档案(走 [OutputFeedback],归一成既有 tag)。
///
/// [enabled]=false:测试/离线预览用,完全不碰 SQLite/Hive。
class SentencePracticeRecorder {
  const SentencePracticeRecorder({this.enabled = true});

  final bool enabled;

  /// 记一次作答。
  ///
  /// [correct] 只有客观题(纠错/连词成句)有;改写是主观题传 null
  /// (`output_attempts.correct` 留空,不污染正确率分母)。
  /// [errorKinds] 是"这次错在哪"的类型文本(纠错=ErrorSpot.kind,
  /// 连词成句=词汇),由本方法归一成错误档案既有 tag。
  Future<void> record({
    required SentencePracticeMode mode,
    required String answer,
    bool? correct,
    ScoredOutput? scored,
    Iterable<String> errorKinds = const [],
    String? evidence,
  }) async {
    if (!enabled) return;
    final tags = <String>[];
    for (final kind in errorKinds) {
      final tag = OutputFeedback.canonicalTagFor(kind);
      if (tag != null && !tags.contains(tag)) tags.add(tag);
    }
    // 结果页数据(score_json)统一用 ScoredOutput.toJson,与材料出题同一口径
    try {
      await DatabaseService.insertOutputAttempt({
        'mode': mode.id,
        'answer': answer,
        'correct': correct == null ? null : (correct ? 1 : 0),
        'score_json': scored == null ? null : jsonEncode(scored.toJson()),
        'seconds': 0,
        'error_tags_json': jsonEncode(tags),
      });
    } catch (e) {
      debugPrint('ReadFlow 写句练习记录落库失败(已忽略): $e');
    }
    // 错误档案:改写用 rubric 问题列表(归一后写),客观题用错误类型
    if (scored != null) {
      await OutputFeedback.recordOutputFeedback(
        issues: scored.issues,
        source: 'exercise',
      );
    } else if (tags.isNotEmpty) {
      await OutputFeedback.recordErrorTags(
        tags,
        source: 'exercise',
        evidence: evidence,
      );
    }
  }
}

/// 改写题评分用的 rubric(复用回译 rubric:改写与回译都是"句子级产出")。
OutputRubric? rewriteRubric() => OutputRubric.byId('back_translation');
