/// **AI 改写学习版(非原文)**:自由搜"找不到可读原文"时的保底链路。
///
/// 用户 2026-11-07 真机反馈第 4 条原话要点:
/// > 搜《原子习惯》找不到原文时,现在只给无关的"真实材料"—— 应该说明为什么没找到,
/// > 并且让 AI 基于**已经搜到的标题/摘要/来源**改写一篇学习版,明确标注"非原文"。
///
/// 所以这个服务的边界写死在这里:
/// 1. **只基于真实搜到的东西**:候选标题/摘要/来源/链接由调用方传进来(来自
///    `OriginalSearch` / 官方搜索的真实结果),模型只能从这些线索里取材;
/// 2. **不许编来源/链接**:模型只能回填候选编号 `used_sources`,链接由本地按编号
///    映射回真实 URL;模型编的 URL 一律丢弃;
/// 3. **不许冒充原文**:标题固定带 [aiRewriteMarker]、license 固定 [aiRewriteLicense]、
///    正文末尾附"来源与说明"(见 [buildAiRewriteProvenanceText]),入库后在任何
///    列表/阅读器里都能一眼看出是 AI 改写;
/// 4. **缺数据不编数字**:字数由本地实数;难度只用"目标档位 + 真实覆盖率(算出来才有)",
///    模型自己报的"难度/词数"不采信。
///
/// 可测试性(与 `material_discovery.dart` 的 handler 注入同一模式):
/// - [buildAiRewritePrompt] / [parseAiRewrite] / [buildAiRewriteMaterialRow]
///   / [buildAiRewriteProvenanceText] 全是纯函数,直接单测;
/// - [MaterialAiRewriter] 支持注入 [AiRewriteHandler] 与 [AiRewriteMeasurer],
///   单测/渲染不碰网络、不碰词频库。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/learner_model.dart';
import '../models/vocabulary.dart';
import 'base_api.dart';
import 'database.dart';
import 'deepseek_api.dart';
import 'doubao_api.dart' show DoubaoApiService;
import 'learner_model_store.dart';
import 'material_library.dart';

/// 标题里必须出现的标注(用户要求"一眼看出不是原文")
const String aiRewriteMarker = 'AI 改写学习版（非原文）';

/// 入库 license(用户要求:license 标"AI 改写,仅供个人学习")
const String aiRewriteLicense = 'AI 改写,仅供个人学习(非原文;来源链接见正文末)';

/// 入库身份前缀。同一主题重复生成会更新同一行(而不是堆一堆重复材料)
const String aiRewriteSourceIdPrefix = 'ai-rewrite:';

/// 目标档位 → 建议英文词数(纯函数,可单测)。
///
/// 只影响"给模型的篇幅要求";最终字数以模型产出的**实数**为准,不按这里写死。
int aiRewriteTargetWords(String bandLabel) {
  final label = bandLabel.trim().toLowerCase();
  // 先判 i+100:它的字符串里也包含 "i+10",顺序反了会判错档
  if (label.contains('i+100')) return 420;
  if (label.contains('i+10')) return 340;
  if (label.contains('i+1')) return 260;
  return 320;
}

/// 真实搜索线索(只保留"搜到过、但读不了原文"的公开信息)
class AiRewriteSource {
  final String title;
  final String url;
  final String site;
  final String snippet;
  final String kind;

  const AiRewriteSource({
    required this.title,
    required this.url,
    this.site = '',
    this.snippet = '',
    this.kind = '',
  });

  bool get hasUrl => url.trim().startsWith('http');
}

/// AI 改写的输入(全部来自这次真实搜索)
class AiRewriteRequest {
  /// 用户这次搜的关键词(原样,不做改写)
  final String query;

  /// 这次搜到的线索(0 条时不允许生成 —— 没依据的内容不编)
  final List<AiRewriteSource> sources;

  /// 目标难度档文案(例:`i+10 · 挑战`);空 = 不限
  final String bandLabel;

  /// 档位说明(来自 `MaterialBand.description` / `hintForAi`,给模型看)
  final String bandHint;

  /// 目标词数(默认按档位算,见 [aiRewriteTargetWords])
  final int targetWords;

  /// 学习目标(前两个足够,真实来自 `InputPreferences.examGoals`)
  final List<String> goals;

  /// 兴趣(真实来自 `LearnerModel.interests` ∪ `InputPreferences.interests`)
  final List<String> interests;

  /// 用户补充要求(可空)
  final String extraNote;

  /// 用户要求的篇幅（null = 不限，优先保证内容覆盖度）
  final int? wordLimit;

  /// 难度改写方式：'same'(贴近原材料难度,默认) / 'easier' / 'harder'
  final String difficultyMode;

  /// 用户要找的作品/主题（例：`原子习惯` / 原版名 `Atomic Habits`）。
  final String topicHint;

  AiRewriteRequest({
    required this.query,
    required this.sources,
    this.bandLabel = '',
    this.bandHint = '',
    int? targetWords,
    this.goals = const <String>[],
    this.interests = const <String>[],
    this.extraNote = '',
    this.wordLimit,
    this.difficultyMode = 'same',
    this.topicHint = '',
  }) : targetWords = targetWords != null && targetWords > 0
            ? targetWords
            : aiRewriteTargetWords(bandLabel);

  /// 依据是否有限(少于 2 条线索时,界面必须明说"依据有限")
  bool get basisLimited => sources.length < 2;
}

/// AI 改写产物(界面/入库都用这一份;数字全部来自本地真实计算)
class AiRewrittenMaterial {
  /// 英文主题(不含标注;入库标题 = 它 + 标注)
  final String topic;

  /// 中文标题(模型给;空串 = 没有)
  final String titleCn;

  /// 英文正文(已去掉 Markdown 围栏/多余空行)
  final String body;

  /// 1~2 句中文导读(模型给;空串 = 没有)
  final String summaryCn;

  /// **真实**用到的来源(只能是 [AiRewriteRequest.sources] 的子集)
  final List<AiRewriteSource> usedSources;

  /// 真实字数(本地数出来)
  final int wordCount;

  /// 真实预估阅读分钟(有词频分析时才有,否则 0)
  final int estMinutes;

  /// 真实覆盖率(词次;没算完就是 null —— 不许拿目标档位冒充)
  final double? coverage;

  /// 真实 CEFR(有词频分析时才有)
  final String cefr;

  /// 目标档位文案(用户选的档;用于说明"按什么难度改写")
  final String bandLabel;

  /// 生成这条的模型槽位说明(例:副槽位 · deepseek-flash);空 = 不知道
  final String modelLabel;

  /// 改写的要点覆盖清单（模型先提炼再逐点覆盖；空 = 模型没给）
  final List<String> outline;

  const AiRewrittenMaterial({
    required this.topic,
    required this.body,
    required this.usedSources,
    required this.wordCount,
    this.titleCn = '',
    this.summaryCn = '',
    this.estMinutes = 0,
    this.coverage,
    this.cefr = '',
    this.bandLabel = '',
    this.modelLabel = '',
    this.outline = const <String>[],
  });

  /// 入库/书架/阅读器里显示的完整标题(永远带"非原文"标注)
  String get title => aiRewriteTitleOf(topic);

  /// 依据是否有限(界面必须明说)
  bool get basisLimited => usedSources.length < 2;

  /// 要点覆盖说明（模型给了 outline 才有；界面上用来证明"覆盖到了原文主要内容"）
  String get coverageLine =>
      outline.isEmpty ? '' : '覆盖 ${outline.length} 个内容要点';

  /// 一行真实数字说明(字数/覆盖率/CEFR/时长/目标档)
  String get metricLine {
    final label = bandLabel.trim();
    final parts = <String>[
      '全文 $wordCount 词',
      if (coverage != null) '覆盖率 ${((coverage ?? 0) * 100).round()}%',
      if (cefr.trim().isNotEmpty) 'CEFR ${cefr.trim()}',
      if (estMinutes > 0) '约 $estMinutes 分钟',
      if (label.isNotEmpty && !label.contains('不限')) '按 $label 档改写',
    ];
    return parts.join(' · ');
  }

  AiRewrittenMaterial copyWithMeasure({
    required int wordCount,
    int estMinutes = 0,
    double? coverage,
    String cefr = '',
  }) =>
      AiRewrittenMaterial(
        topic: topic,
        titleCn: titleCn,
        body: body,
        summaryCn: summaryCn,
        usedSources: usedSources,
        wordCount: wordCount,
        estMinutes: estMinutes,
        coverage: coverage,
        cefr: cefr,
        bandLabel: bandLabel,
        modelLabel: modelLabel,
      );
}

/// AI 改写的失败原因(人话;不抛异常,由界面展示)
class AiRewriteOutcome {
  final AiRewrittenMaterial? material;
  final String? error;

  const AiRewriteOutcome.success(AiRewrittenMaterial this.material) : error = null;

  const AiRewriteOutcome.failure(String this.error) : material = null;

  bool get ok => material != null;
}

/// 模型执行者:输入 system/user,返回模型正文(可能带围栏);失败返回 null。
typedef AiRewriteHandler = Future<String?> Function(String system, String user);

/// 本地真实测量者:输入英文正文,返回真实字数/覆盖率/CEFR(失败返回 null)。
typedef AiRewriteMeasurer = Future<AiRewriteMeasurement?> Function(String body);

/// 本地真实测量结果(只放**算出来**的数,没有的就是 null/0)
class AiRewriteMeasurement {
  final int wordCount;
  final int estMinutes;
  final double? coverage;
  final String cefr;

  const AiRewriteMeasurement({
    required this.wordCount,
    this.estMinutes = 0,
    this.coverage,
    this.cefr = '',
  });
}

// ═══════════════════════════════════════════════════════════════════════
// 纯函数:提示词 / 解析 / 标题 / 入库行
// ═══════════════════════════════════════════════════════════════════════

/// 入库标题:主题 + 固定标注(模型给的标题一律洗掉可能自带的标注/引号/星号,不重复)
String aiRewriteTitleOf(String topic) {
  var clean = _stripAiTitleSuffix(topic);
  clean = clean.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  if (clean.isEmpty) clean = '未命名主题';
  if (clean.length > 90) clean = '${clean.substring(0, 90)}…';
  return '$clean · $aiRewriteMarker';
}

/// 入库身份(纯函数,可单测):同一主题重复生成更新同一行,不堆重复材料。
String aiRewriteSourceIdOf(String topic) {
  final key = topic
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '$aiRewriteSourceIdPrefix${key.isEmpty ? 'untitled' : key}';
}

/// 数英文词数(纯函数):与展示用的"全文 N 词"同一口径。
int aiRewriteCountWords(String text) {
  final matches =
      RegExp(r"[A-Za-z][A-Za-z'’\-]*").allMatches(text);
  return matches.length;
}

/// 正文里中文占比(纯函数):用来挡"模型把中文当英文正文"的情况。
double aiRewriteChineseRatio(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 1;
  final chinese =
      RegExp(r'[\u4e00-\u9fff]').allMatches(trimmed).length;
  return chinese / trimmed.length;
}

/// 构建提示词(纯函数,可单测)。
///
/// 纪律(和 `tutor_insights.dart` 的"没数据不出数字"同一条):
/// - 只能基于给定的真实线索写,不许编链接/作者/数据;
/// - 明确说"不是原文",不许声称是某书/某站原文,不许复制受版权保护的长段落;
/// - 难度按目标档位,但**不许在正文里自称难度百分比/词数**(由本地实数算)。
({String system, String user}) buildAiRewritePrompt(AiRewriteRequest request) {
  final limit = request.wordLimit;
  final lengthRule = (limit == null || limit <= 0)
      ? '篇幅**不设固定字数上限**：优先保证把主题的主要内容讲完整（一般 500~900 词，'
          '按内容需要写，不要为了凑字数重复，也不要为了短而省略关键点）。'
      : '篇幅约 $limit 词（±15%）；如关键点较多可略超，但不要冗长重复。';
  final difficulty = switch (request.difficultyMode) {
    'easier' => '在目标难度之下的**更简单**版本：优先高频词、短句、清楚的结构。',
    'harder' => '在目标难度之上的**更难**版本：使用更丰富的词汇与更复杂的句式，但保持可读。',
    _ => '尽量**贴近原材料/目标难度的用词与句长**；不要额外拔高或刻意简化。',
  };
  final system = '''你是英语学习材料编辑。用户这次搜到的材料大多读不到全文（或只有标题/摘要线索）。
你的任务：围绕用户的**检索主题**，改写一篇**英文学习材料**——它不是原文，而是把主题讲清楚的改写学习版。

硬规则（违反任何一条都算失败）：
1. **先确定作品/主题，再按体系改写**：先用你已有的知识判断用户要找的是哪本书/哪篇文章、它讲了什么；
   先列 outline（4~8 个核心要点：主旨、关键观点/方法、章节结构、结论或应用），正文必须**逐点覆盖**这些核心内容
   —— 不要用零散线索拼凑，也不要写成泛泛而谈。
2. 允许使用你自己对这部作品/主题的知识（不限语言），但必须明确这是**改写学习版、不是原文**；
   不许编造具体引文、页码、统计数据或链接；不要冒充原书原文，不要写 "excerpt from"。
3. 给到的搜索线索只用于**补充或纠正**（确认书名/作者/主题）；线索不足时以你的知识为主。
4. 正文用**英文**，分段清楚（有开头、逐点展开、收束）；不要写练习题、生词表或 JSON 外解释。
5. $lengthRule
6. 难度：$difficulty
7. 只输出 JSON：
{
  "topic": "英文主题（<=60 字符，不带书名号/引号/星号）",
  "title_cn": "中文标题（<=30 字）",
  "summary_cn": "1~2 句中文导读（说明这是 AI 改写学习版）",
  "outline": ["关键点1", "关键点2", "…"],
  "body": "英文正文（段落之间用 \\n\\n 分隔，覆盖 outline 的全部要点）",
  "used_sources": [1, 2]
}
used_sources 填线索编号（1 起，最多 3 个，必须真实用到；可空数组）。''';

  final buf = StringBuffer();
  if (request.topicHint.trim().isNotEmpty) {
    buf.writeln('用户要找的作品/主题:${request.topicHint.trim()}');
  }
  buf.writeln('用户搜索关键词（主题以此为准）:${request.query.trim()}');
  if (request.bandLabel.trim().isNotEmpty) {
    buf.writeln('目标难度档:${request.bandLabel.trim()}');
  }
  if (request.goals.isNotEmpty) {
    buf.writeln('学习目标:${request.goals.take(3).join("、")}');
  }
  if (request.interests.isNotEmpty) {
    buf.writeln('兴趣:${request.interests.take(4).join("、")}');
  }
  if (request.extraNote.trim().isNotEmpty) {
    buf.writeln('用户补充要求:${request.extraNote.trim()}');
  }
  buf.writeln('这次搜到的真实线索（只用来理解主题/背景；不要复制链接）：');
  if (request.sources.isEmpty) {
    buf.writeln('（这次没有可用线索——请只围绕检索主题写一般性学习材料，不要声称有来源、不要编具体数据。）');
  } else {
    for (var i = 0; i < request.sources.length; i++) {
      final s = request.sources[i];
      buf.writeln(
        '${i + 1}. title=${s.title} | site=${s.site} | kind=${s.kind} '
        '| snippet=${s.snippet} | url=${s.url}',
      );
    }
  }
  buf.writeln('请先列 outline（3~6 点），再写覆盖全部要点的英文正文，按上面的 JSON 输出。');
  return (system: system, user: buf.toString());
}

/// 解析模型返回(纯函数,可单测;容错优先,不合格返回 null)。
///
/// 兼容:标准 JSON / ```json 围栏 / JSON 前后夹说明文字;字段名做同义词兜底。
/// 不合格(正文不是英文、词数过少、没有主题)一律返回 null —— 宁可失败重试,
/// 也不把半成品塞给用户。
AiRewrittenMaterial? parseAiRewrite(
  String content, {
  required AiRewriteRequest request,
  String modelLabel = '',
}) {
  final text = content.trim();
  if (text.isEmpty) return null;
  Object? decoded;
  final jsonStr = DoubaoApiService.extractJsonBlock(text);
  final candidates = <String>[
    if (jsonStr.isNotEmpty) jsonStr,
    if (text.startsWith('{') && text.endsWith('}')) text,
  ];
  for (final raw in candidates) {
    try {
      decoded = jsonDecode(raw);
      if (decoded is Map) break;
      decoded = null;
    } catch (_) {
      decoded = null;
    }
  }
  if (decoded is! Map) return null;
  final map = Map<String, dynamic>.from(decoded);

  String pick(List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  final topic = _stripAiTitleSuffix(
    pick(<String>['topic', 'title', 'headline', 'topic_en']),
  );
  final bodyRaw =
      pick(<String>['body', 'article', 'text', 'content', 'english', 'article_body']);
  if (topic.isEmpty || bodyRaw.isEmpty) return null;
  final body = _cleanAiBody(bodyRaw);
  final wordCount = aiRewriteCountWords(body);
  // 正文必须是英文、且不能太短(<=80 词的"学习材料"没有阅读价值,也说明模型在敷衍)
  if (wordCount < 80) return null;
  if (aiRewriteChineseRatio(body) > 0.08) return null;

  final used = _pickUsedSources(map, request.sources);
  final outlineRaw =
      map['outline'] ?? map['points'] ?? map['key_points'] ?? map['keyPoints'];
  final outline = <String>[];
  if (outlineRaw is List) {
    for (final value in outlineRaw) {
      if (value is String && value.trim().isNotEmpty) {
        outline.add(value.trim());
      } else if (value is Map) {
        final text = '${value['point'] ?? value['text'] ?? value['title'] ?? ''}'
            .trim();
        if (text.isNotEmpty) outline.add(text);
      }
    }
  }
  return AiRewrittenMaterial(
    topic: topic,
    titleCn: pick(<String>['title_cn', 'title_cn_note', 'zh_title', 'title_zh']),
    summaryCn: pick(<String>['summary_cn', 'summary', 'zh_summary', 'note_cn']),
    body: body,
    usedSources: used,
    wordCount: wordCount,
    bandLabel: request.bandLabel.trim(),
    modelLabel: modelLabel,
    outline: outline,
  );
}

/// used_sources → 真实来源(纯函数,可单测)。
///
/// 编号 1 起;越界/非整数一律丢;模型没给或全无效时退化为"这次搜到的前 3 条"
/// (仍然是真实来源,不会凭空造)。**永远不接受模型自带的 URL**。
List<AiRewriteSource> _pickUsedSources(
  Map<String, dynamic> map,
  List<AiRewriteSource> sources,
) {
  if (sources.isEmpty) return const <AiRewriteSource>[];
  final raw = map['used_sources'] ??
      map['used_source'] ??
      map['sources'] ??
      map['source_ids'];
  final indices = <int>[];
  void addIndex(Object? value) {
    int? idx;
    if (value is int) {
      idx = value;
    } else if (value is num) {
      idx = value.toInt();
    } else if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) idx = parsed;
    } else if (value is Map) {
      final inner = value['index'] ?? value['i'] ?? value['no'] ?? value['n'];
      if (inner is int) {
        idx = inner;
      } else if (inner is String) {
        idx = int.tryParse(inner.trim());
      }
    }
    // 1 基编号;同时容忍模型给 0 基(0 视为第 1 条)
    if (idx == null) return;
    if (idx >= 1 && idx <= sources.length) indices.add(idx - 1);
    if (idx == 0) indices.add(0);
  }

  if (raw is List) {
    for (final value in raw) {
      addIndex(value);
    }
  } else if (raw != null) {
    addIndex(raw);
  }
  final out = <AiRewriteSource>[];
  for (final idx in indices) {
    if (idx < 0 || idx >= sources.length) continue;
    final s = sources[idx];
    if (out.any((e) => e.url == s.url)) continue;
    out.add(s);
    if (out.length >= 3) break;
  }
  if (out.isEmpty) return sources.take(3).toList();
  return out;
}

/// 去掉模型自己加的"AI 改写学习版"后缀/引号/星号(标题只留主题)
String _stripAiTitleSuffix(String raw) {
  var s = raw.trim();
  s = s.replaceAll(RegExp(r'^[\s"“”\[\]【】]+'), '');
  s = s.replaceAll(RegExp(r'[\s"“”\[\]【】]+$'), '');
  s = _trimQuoteEdges(s);
  s = s.replaceAll('*', '');
  s = s.replaceAll(RegExp(r'\s*[·\-—|]?\s*AI\s*改写[^,，。;；]*$'), '');
  s = s.replaceAll(RegExp(r'\s*[·\-—|]?\s*非原文\s*$'), '');
  return s.trim();
}

/// 去掉首尾的直引号/弯引号(不动词中间的撇号,如 `Learner's`)
String _trimQuoteEdges(String value) {
  var s = value;
  bool isEdgeQuote(String ch) =>
      ch == "'" || ch == '‘' || ch == '’' || ch == '`';
  while (s.isNotEmpty && isEdgeQuote(s[0])) {
    s = s.substring(1);
  }
  while (s.isNotEmpty && isEdgeQuote(s[s.length - 1])) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// 清洗正文:去 Markdown 围栏/标题井号/行内星号,压缩多余空行。
String _cleanAiBody(String raw) {
  var s = raw.replaceAll('\r\n', '\n').trim();
  s = s.replaceAll(RegExp(r'^```[a-zA-Z]*\n'), '');
  s = s.replaceAll(RegExp(r'\n```$'), '');
  s = s.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
  s = s.replaceAll('**', '');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// 正文 + 来源说明(AI 材料入库/阅读时**必须**带上,保证来源与"非原文"不丢)
String buildAiRewriteProvenanceText(AiRewrittenMaterial material) {
  final lines = <String>[
    material.body.trim(),
    '',
    '──────── 来源与说明（AI 改写学习版 · 非原文） ────────',
    '本材料由 AI 基于你在「找材料 · 自由搜」里搜到的公开线索改写而成,'
        '不是原文,也不代表原站/原作者的观点。',
    '改写只用到下面这些真实来源的标题/摘要级信息（按编号抄录,未复制正文）:',
  ];
  if (material.usedSources.isEmpty) {
    lines.add('(这次没有可标注的来源 —— 依据有限)');
  } else {
    for (var i = 0; i < material.usedSources.length; i++) {
      final s = material.usedSources[i];
      final site = s.site.trim().isEmpty ? '来源站' : s.site.trim();
      final url = s.url.trim().isEmpty ? '(无链接)' : s.url.trim();
      lines.add('${i + 1}. ${s.title.trim().isEmpty ? url : s.title.trim()}'
          ' — $site — $url');
    }
  }
  lines
    ..add('入库许可:$aiRewriteLicense')
    ..add('如需引用原文内容,请打开上面的来源链接自行核对。');
  return lines.join('\n');
}

/// 入库行(纯函数,可单测):source=ai / license 标注 / title 带标注 / url 保留来源链接。
///
/// 不直接写库,是为了让"身份/许可/标注"这三件容易出错的事可以纯单测;
/// 真正写库在 [MaterialAiRewriteStore.ingest]。
Map<String, Object?> buildAiRewriteMaterialRow(
  AiRewrittenMaterial material, {
  MaterialAnalysis? analysis,
}) {
  final primary = material.usedSources.isEmpty
      ? ''
      : material.usedSources.first.url.trim();
  return <String, Object?>{
    'kind': 'article',
    'source': 'ai',
    'source_id': aiRewriteSourceIdOf(material.topic),
    'title': material.title,
    'author': '',
    'url': primary.isEmpty ? null : primary,
    'license': aiRewriteLicense,
    'language': 'en',
    'cover_url': null,
    'word_count': analysis?.wordCount ?? material.wordCount,
    'unique_words': analysis?.uniqueWords ?? 0,
    'cefr': analysis?.cefr ?? material.cefr,
    'coverage': analysis?.coverage ?? material.coverage,
    'new_word_density': analysis?.newWordDensity ?? 0,
    'est_minutes': analysis?.estMinutes ?? material.estMinutes,
    'chapters': 1,
    'difficulty_json':
        analysis == null ? null : jsonEncode(analysis.toJson()),
    'cached_at': DateTime.now().toIso8601String(),
  };
}

// ═══════════════════════════════════════════════════════════════════════
// 生产默认实现:调模型 / 本地量难度
// ═══════════════════════════════════════════════════════════════════════

/// 生产默认:用 JSON mode 让模型改写(任务级思考档与"出题"同类:要完整 JSON)。
Future<String?> defaultMaterialAiRewriteHandler(String system, String user) {
  return DeepseekApiService().completeJson(
    system: system,
    user: user,
    maxTokens: 2600,
    temperature: 0.7,
    thinkingLevel: BaseApiService.thinkingForTask('output'),
    receiveTimeout: const Duration(seconds: 120),
  );
}

/// 生产默认:用材料库同一套词频分析量正文(失败只给字数,不编难度)。
Future<AiRewriteMeasurement?> defaultMaterialAiRewriteMeasurer(
  String body,
) async {
  LearnerModel model;
  try {
    model = LearnerModelStore.load();
  } catch (_) {
    model = LearnerModel();
  }
  try {
    final analysis = await MaterialLibrary.analyze(body, model: model);
    return AiRewriteMeasurement(
      wordCount: analysis.wordCount,
      estMinutes: analysis.estMinutes,
      coverage: analysis.knownTokenRatio,
      cefr: analysis.cefr,
    );
  } catch (e) {
    debugPrint('ReadFlow AI 改写难度测量失败(只保留字数): $e');
    return AiRewriteMeasurement(wordCount: aiRewriteCountWords(body));
  }
}

/// AI 改写执行者:提示词 → 模型 → 解析 → 本地量难度。
///
/// 失败不抛:返回 [AiRewriteOutcome.failure] 的人话原因,界面直接展示。
class MaterialAiRewriter {
  final AiRewriteHandler _handler;
  final AiRewriteMeasurer _measurer;

  MaterialAiRewriter({
    AiRewriteHandler? handler,
    AiRewriteMeasurer? measurer,
  })  : _handler = handler ?? defaultMaterialAiRewriteHandler,
        _measurer = measurer ?? defaultMaterialAiRewriteMeasurer;

  /// 模型槽位说明(给界面标注"谁改写的";拿不到就空串)
  static String get modelLabel {
    try {
      return DeepseekApiService.targetSummary;
    } catch (_) {
      return '';
    }
  }

  Future<AiRewriteOutcome> generate(AiRewriteRequest request) async {
    // 2026-11-08 用户明确逻辑：没有原版/线索时，AI 应当先用**自己的知识**
    // 梳理这本书/主题讲什么，再按体系改写（明确标注非原文），而不是拒绝生成。
    // 只有在连"作品/主题"都没有时（topicHint/query 都空）才拒绝。
    final hasTopic = request.topicHint.trim().isNotEmpty ||
        request.query.trim().isNotEmpty;
    if (request.sources.isEmpty && !hasTopic) {
      return const AiRewriteOutcome.failure(
        '这次没有作品名/主题也没有可用线索 —— 先输入书名或一个更具体的关键词。',
      );
    }
    final prompt = buildAiRewritePrompt(request);
    String? raw;
    try {
      raw = await _handler(prompt.system, prompt.user);
    } catch (e) {
      debugPrint('ReadFlow AI 改写请求失败: $e');
      raw = null;
    }
    if (raw == null || raw.trim().isEmpty) {
      return const AiRewriteOutcome.failure(
        'AI 改写没有返回内容:通常是 API 未配置、网络失败或模型超时。'
        '可以先到「设置 → API」检查(不需要改任何设置,回来点重试即可)。',
      );
    }
    var material = parseAiRewrite(
      raw,
      request: request,
      modelLabel: modelLabel,
    );
    if (material == null) {
      return const AiRewriteOutcome.failure(
        'AI 返回的内容不像一篇可读的英文材料(可能被截断或没按 JSON 输出),'
        '这次不硬塞给你。可以直接重试,或用原文关键词再搜一次。',
      );
    }
    final measured = await _measurer(material.body);
    if (measured != null) {
      material = material.copyWithMeasure(
        wordCount: measured.wordCount > 0 ? measured.wordCount : material.wordCount,
        estMinutes: measured.estMinutes,
        coverage: measured.coverage,
        cefr: measured.cefr,
      );
    }
    return AiRewriteOutcome.success(material);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 入库(保存到我的 / 开始读 都走这里)
// ═══════════════════════════════════════════════════════════════════════

/// AI 改写材料入库:写材料库(source=ai),正文末尾带来源与说明。
///
/// 为什么不复用 `MaterialLibrary.ingestText`:那条链路的身份是"用户自备材料"
/// (`source=manual`, license 写死"用户自备材料")。AI 改写必须是 **source=ai** +
/// 专属 license,才能在「我的」/书架里和原文区分开(用户明确要求"不要误当原文")。
/// 这两条是不同的来路,不是重复实现;难度/正文分块仍走同一个 [MaterialLibrary.analyze]。
class MaterialAiRewriteStore {
  /// 返回 materialId;失败返回 -1(不抛,界面给"保存失败"人话)。
  static Future<int> ingest(
    AiRewrittenMaterial material, {
    LearnerModel? model,
    List<Vocabulary> vocab = const <Vocabulary>[],
  }) async {
    try {
      final text = buildAiRewriteProvenanceText(material);
      LearnerModel learner;
      try {
        learner = model ?? LearnerModelStore.load();
      } catch (_) {
        learner = model ?? LearnerModel();
      }
      MaterialAnalysis? analysis;
      try {
        analysis = await MaterialLibrary.analyze(
          text,
          model: learner,
          vocab: vocab,
        );
      } catch (e) {
        debugPrint('ReadFlow AI 改写入库分析失败(用本地产物数字): $e');
        analysis = null;
      }
      final row = buildAiRewriteMaterialRow(material, analysis: analysis);
      final id = await DatabaseService.upsertMaterial(
        row,
        chunks: <Map<String, Object?>>[
          <String, Object?>{'chunk_index': 0, 'title': null, 'text': text},
        ],
      );
      return id;
    } catch (e) {
      debugPrint('ReadFlow AI 改写入库失败: $e');
      return -1;
    }
  }
}
