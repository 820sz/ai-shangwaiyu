/// ═══════════════════════════════════════════════════════════════════════
/// 输出模块 · **出题层**(批 3 · P1)。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 现状(见 docs/PLAN-V3.md §2.3、docs/research/output-and-tutor.md §1.5):
/// 输出 tab 以前的题**100% 从生词本捞**,没有"题"的概念 —— 没有题干/字数/
/// 参考/评分标准/来源,更谈不上"针对四六级真题出题"。
///
/// 这一层的职责只有两件:
/// 1. **把材料变成题**(四条路径:回译 / 句式改写 / 段落任务 / 真题写作);
/// 2. **把模型输出解析成结构化题组**([OutputSetSpec] / [OutputTaskSpec]),
///    供 UI 直接渲染与入库(数据库表由另一位同学在加,本文件不碰 DB)。
///
/// ## 三条硬纪律(用户点名,写进每一条提示词里)
/// 1. **禁止编造题源**:没有原文/来源的题只能 `source='ai'` +
///    `verify_status='pending'`;真题必须来自真实检索到的页面,每条带
///    `sourceUrl` —— 没有 URL 就不生成(宁可不练,不能让用户背假题)。
/// 2. **真实检索才叫"真题"**:[OutputComposer.composeFromExam] 先用
///    [DeepSeekSearchClient] search 再用 fetch 抓正文,抓不到正文直接返回 null;
/// 3. **题目必须可追溯**:每道题的 `sourceSpan`(回译=英文原句)与
///    `sourceUrl` 都要留着,复盘页才能定位"这道题从哪来"。
///
/// ## 分层
/// - 纯函数([buildBackTranslationPrompt] / [parseTaskList] / [extractSentences]…):
///   不联网、不读 Hive,单测直接覆盖;
/// - [OutputComposer]:唯一会发请求的类,HTTP 复用 [DeepseekApiService]
///   现有的 `postWithReasoningFallback`(**不新建 Dio**),可注入假服务做测试。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'base_api.dart';
import 'deepseek_api.dart';
import 'deepseek_search.dart';
import 'output_rubric.dart';

// ═══════════════════════════════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════════════════════════════

/// 四阶(与 PLAN-V3 §2.3 的"写词/写句/写段/写篇"对齐)。
///
/// 注意:**四阶是并行的,不是解锁关系**(用户 2026-11-01 明确)——
/// 这里只用来决定"出哪类题、用哪套提示词",不做门禁。
enum OutputTier {
  word('word', '写词'),
  sentence('sentence', '写句'),
  paragraph('paragraph', '写段'),
  essay('essay', '写篇');

  const OutputTier(this.id, this.label);

  final String id;
  final String label;

  /// 兼容历史/UI 文案(如"句子"/"段落"/"作文")的容错解析;
  /// 未知值 → [paragraph](出题最通用的档,不会因为一个脏字符串就不出题)
  static OutputTier fromId(Object? raw) {
    final text = '${raw ?? ''}'.trim().toLowerCase();
    for (final tier in OutputTier.values) {
      if (tier.id == text) return tier;
    }
    return switch (text) {
      '写词' || '词' || '词汇' => OutputTier.word,
      '写句' || '句' || '句子' => OutputTier.sentence,
      '写段' || '段' || '段落' => OutputTier.paragraph,
      '写篇' || '篇' || '作文' || '文章' => OutputTier.essay,
      _ => OutputTier.paragraph,
    };
  }
}

/// 一道题(对应数据库 `exercise_items` 的一行)。
///
/// 比 research 文档里的字段多了 [sourceUrl]/[source]/[verifyStatus]/[hint]:
/// 这四项是"禁止编造题源"落到数据结构上的必要字段(数据库由另一位同学加)。
class OutputTaskSpec {
  final OutputTier tier;

  /// 题型:`back_translation` / `sentence_rewrite` / `summary` / `paragraph` /
  /// `opinion` / `continuation` / `chart` / `exam_writing` / `exam_translation`
  final String type;

  /// 中文题面(用户看到的题干;回译题这里是中文译文)
  final String promptZh;

  /// 英文材料/原句(回译题的英文原句放 [reference];这里放"要改写的原句"等)
  final String promptEn;

  /// 参考答案(回译=英文原句/参考译文;写作=参考要点或范文;空串 = 参考暂缺)
  final String reference;

  /// 评分标准 id(对齐 [OutputRubric.builtin]:`cet4_writing` / `cet4_translation`
  /// / `back_translation` / `summary`;**空串 = 无 rubric**,用对照批改)
  final String rubricId;

  /// 能力标签(如 `["词汇","语法"]`,用于统计/错因汇总)
  final List<String> abilityTags;

  /// 涉及语法点(如 `["时态","非谓语"]`)
  final List<String> grammarPoints;

  /// 字数要求(0 = 不限)
  final int wordCount;

  /// 材料中的原文片段(**定位用**:回译题=英文原句,其他=题目依据的那一段)
  final String sourceSpan;

  /// 材料 id(来自 `materials` 表;null = 非材料来源)
  final int? materialId;

  /// 题目来源 URL(真题必须是真实抓到的页面;AI 生成且无来源时为空串)
  final String sourceUrl;

  /// 来源:`ai` / `builtin` / `user_import` / `exam`(对齐数据库口径)
  final String source;

  /// 校对状态:`pending`(AI 生成未校对)/ `verified`(人工核对过)
  final String verifyStatus;

  /// 出题提示(关键表达/改写方向;UI 可在"提示"按钮里展示)
  final String hint;

  const OutputTaskSpec({
    required this.tier,
    required this.type,
    required this.promptZh,
    this.promptEn = '',
    this.reference = '',
    this.rubricId = '',
    this.abilityTags = const <String>[],
    this.grammarPoints = const <String>[],
    this.wordCount = 0,
    this.sourceSpan = '',
    this.materialId,
    this.sourceUrl = '',
    this.source = 'ai',
    this.verifyStatus = 'pending',
    this.hint = '',
  });

  /// 是否有可用参考答案(UI 据此决定"看参考"按钮是否可点)
  bool get hasReference => reference.trim().isNotEmpty;

  /// 是否来自真实检索(真题)——只有这种才允许标"真题"字样
  bool get isExam => source == 'exam' && sourceUrl.trim().isNotEmpty;

  OutputTaskSpec copyWith({
    OutputTier? tier,
    String? type,
    String? promptZh,
    String? promptEn,
    String? reference,
    String? rubricId,
    List<String>? abilityTags,
    List<String>? grammarPoints,
    int? wordCount,
    String? sourceSpan,
    int? materialId,
    String? sourceUrl,
    String? source,
    String? verifyStatus,
    String? hint,
    bool clearMaterialId = false,
  }) {
    return OutputTaskSpec(
      tier: tier ?? this.tier,
      type: type ?? this.type,
      promptZh: promptZh ?? this.promptZh,
      promptEn: promptEn ?? this.promptEn,
      reference: reference ?? this.reference,
      rubricId: rubricId ?? this.rubricId,
      abilityTags: abilityTags ?? this.abilityTags,
      grammarPoints: grammarPoints ?? this.grammarPoints,
      wordCount: wordCount ?? this.wordCount,
      sourceSpan: sourceSpan ?? this.sourceSpan,
      materialId: clearMaterialId ? null : (materialId ?? this.materialId),
      sourceUrl: sourceUrl ?? this.sourceUrl,
      source: source ?? this.source,
      verifyStatus: verifyStatus ?? this.verifyStatus,
      hint: hint ?? this.hint,
    );
  }

  Map<String, dynamic> toJson() => {
    'tier': tier.id,
    'type': type,
    'prompt_zh': promptZh,
    'prompt_en': promptEn,
    'reference_answer': reference,
    'rubric_id': rubricId,
    'ability_tags': abilityTags,
    'grammar_points': grammarPoints,
    'word_count': wordCount,
    'source_span': sourceSpan,
    'material_id': materialId,
    'source_url': sourceUrl,
    'source': source,
    'verify_status': verifyStatus,
    'hint': hint,
  };

  /// 容错解析(字段缺失/类型不符都当缺省;题干全空由调用方丢弃)
  static OutputTaskSpec? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final promptZh =
        '${raw['prompt_zh'] ?? raw['prompt'] ?? raw['question'] ?? ''}'.trim();
    final promptEn = '${raw['prompt_en'] ?? raw['original'] ?? ''}'.trim();
    final reference =
        '${raw['reference_answer'] ?? raw['reference'] ?? raw['answer'] ?? ''}'
            .trim();
    if (promptZh.isEmpty && promptEn.isEmpty && reference.isEmpty) return null;
    return OutputTaskSpec(
      tier: OutputTier.fromId(raw['tier']),
      type: '${raw['type'] ?? 'paragraph'}'.trim(),
      promptZh: promptZh,
      promptEn: promptEn,
      reference: reference,
      rubricId: '${raw['rubric_id'] ?? ''}'.trim(),
      abilityTags: _stringList(raw['ability_tags']),
      grammarPoints: _stringList(raw['grammar_points']),
      wordCount: _toInt(raw['word_count']),
      sourceSpan: '${raw['source_span'] ?? ''}'.trim(),
      materialId: _toIntOrNull(raw['material_id']),
      sourceUrl: '${raw['source_url'] ?? ''}'.trim(),
      source: '${raw['source'] ?? 'ai'}'.trim(),
      verifyStatus: '${raw['verify_status'] ?? 'pending'}'.trim(),
      hint: '${raw['hint'] ?? raw['tip'] ?? ''}'.trim(),
    );
  }

  @override
  String toString() =>
      'OutputTaskSpec(${tier.id}/$type, rubric=$rubricId, source=$source)';
}

/// 一个题组/卷面(对应数据库 `exercise_sets` 的一行)。
class OutputSetSpec {
  final String title;
  final OutputTier tier;

  /// 来源:`ai` / `builtin` / `user_import` / `exam`
  final String source;

  /// 考试类型:`cet4` / `cet6` / `kaoyan` / `ielts` / `nce` / `none`
  final String examType;

  /// 题型分区:`writing` / `reading_translation` / `back_translation` 等
  final String section;

  final List<OutputTaskSpec> tasks;

  /// 题组级 rubric id(取第一道题的;UI 也可逐题看 [OutputTaskSpec.rubricId])
  final String rubricId;

  /// 许可/来源说明(展示给用户"这些题哪来的")
  final String licenseNote;

  /// 真题来源 URL 列表(抓取页面)
  final List<String> sourceUrls;

  /// 校对状态:`pending`(AI 生成/结构化,未人工校对)/ `verified`
  final String verifyStatus;

  const OutputSetSpec({
    required this.title,
    required this.tier,
    this.source = 'ai',
    this.examType = 'none',
    this.section = '',
    this.tasks = const <OutputTaskSpec>[],
    this.rubricId = '',
    this.licenseNote = '',
    this.sourceUrls = const <String>[],
    this.verifyStatus = 'pending',
  });

  bool get isEmpty => tasks.isEmpty;

  int get taskCount => tasks.length;

  /// 是否包含真题(UI 决定是否展示"真题"角标与来源链接)
  bool get hasExamSource =>
      source == 'exam' &&
      (sourceUrls.isNotEmpty || tasks.any((t) => t.sourceUrl.isNotEmpty));

  Map<String, dynamic> toJson() => {
    'title': title,
    'tier': tier.id,
    'source': source,
    'exam_type': examType,
    'section': section,
    'rubric_id': rubricId,
    'license_note': licenseNote,
    'source_urls': sourceUrls,
    'verify_status': verifyStatus,
    'tasks': [for (final task in tasks) task.toJson()],
  };

  static OutputSetSpec? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rawTasks = raw['tasks'] ?? raw['items'];
    final tasks = <OutputTaskSpec>[];
    if (rawTasks is List) {
      for (final item in rawTasks) {
        final task = OutputTaskSpec.fromJson(item);
        if (task != null) tasks.add(task);
      }
    }
    if (tasks.isEmpty) return null;
    return OutputSetSpec(
      title: '${raw['title'] ?? '未命名题组'}'.trim(),
      tier: OutputTier.fromId(raw['tier']),
      source: '${raw['source'] ?? 'ai'}'.trim(),
      examType: '${raw['exam_type'] ?? 'none'}'.trim(),
      section: '${raw['section'] ?? ''}'.trim(),
      rubricId: '${raw['rubric_id'] ?? ''}'.trim(),
      licenseNote: '${raw['license_note'] ?? ''}'.trim(),
      sourceUrls: _stringList(raw['source_urls']),
      verifyStatus: '${raw['verify_status'] ?? 'pending'}'.trim(),
      tasks: tasks,
    );
  }

  @override
  String toString() => 'OutputSetSpec($title, ${tasks.length} 题, $source)';
}

/// 一段可发给模型的提示词(system + user)。
///
/// 单独成对而不是只返回一个字符串:不同场景 system 纪律不同(出题 vs 评分),
/// 混在一起容易把"评分纪律"稀到"出题提示词"里。
class OutputPrompt {
  final String system;
  final String user;

  const OutputPrompt({required this.system, required this.user});
}

// ═══════════════════════════════════════════════════════════════════════
// 提示词:四条出题路径(纯函数)
// ═══════════════════════════════════════════════════════════════════════

/// **每条出题提示词都必须带上的"题源纪律"**(用户点名:禁止编造题源)。
///
/// 为什么写成硬约束而不是"请注意":模型对"请尽量"这类软措辞基本不执行,
/// 而编造出来的"真题来源"会直接摧毁用户对题库的信任(比没有题更糟)。
const String _sourceDiscipline = '''
【题源纪律(硬约束,违反即算错)】
1. 只能基于输入里给出的原文/材料出题;原文里没有的题目不许出。
2. **禁止编造题源**:不许声称"某年真题/某考试原题",不许编造来源链接。
3. 来源 URL 只能原样使用输入里给出的 URL;没有 URL 就留空串。
4. 材料不足以出题时,返回 {"tasks": []},不要硬凑。
5. 只输出 JSON,不要解释,不要 Markdown 围栏以外的文字。''';

/// **路径 1:回译**(英文原句 → 中文题面,用户再译回英文)。
///
/// [englishSentences] 来自材料/用户导入的完整英文句子(建议 3~8 句);
/// [levelHint]/[bandHint] 是用户水平与难度档(拼进提示词,不改变题目结构)。
OutputPrompt buildBackTranslationPrompt({
  required List<String> englishSentences,
  String levelHint = '',
  String bandHint = '',
  int count = 5,
}) {
  final sentences = englishSentences
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final askCount = count <= 0
      ? sentences.length
      : math.min(count, sentences.length);
  final system = '''你是英语回译练习出题老师。用户给你若干英文原句(来自他正在读的材料),
请把它们变成"看中文、写英文"的练习题。返回 JSON:
{"tasks":[{"prompt_zh":"该句的中文译文(题面;自然但必须保留原句的信息、限定与逻辑)",
"reference":"英文原句(参考)","hint":"1 条关键表达/语法提示(中文,可选)",
"grammar_points":["时态","定语从句"]}]}
要求:
1. 一句一题,题数不超过输入句数;不要增删句子,不要改写英文原句;
2. prompt_zh 要准确对应英文原句(宁可直译,也不要为了顺口丢掉信息/限定);
3. 题目来自用户材料,不要求出处、不编造出处。
$_sourceDiscipline''';
  final buffer = StringBuffer()..writeln('【英文原句(共 ${sentences.length} 条)】');
  for (var i = 0; i < sentences.length; i++) {
    buffer.writeln('${i + 1}. ${sentences[i]}');
  }
  buffer
    ..writeln()
    ..writeln('【出题数量】$askCount 题(最多不超过输入句数)');
  if (levelHint.trim().isNotEmpty) {
    buffer.writeln('【用户水平】${levelHint.trim()}');
  }
  if (bandHint.trim().isNotEmpty) {
    buffer.writeln('【难度要求】${bandHint.trim()}');
  }
  buffer.writeln('请按上面的 JSON 格式输出。');
  return OutputPrompt(system: system, user: buffer.toString());
}

/// **路径 2:句式改写/升级**(给原句 + 改写要求 → 参考改写)。
OutputPrompt buildSentenceRewritePrompt({
  required List<String> originalSentences,
  String rewriteFocus = '升级句式',
  String levelHint = '',
  int count = 5,
}) {
  final sentences = originalSentences
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final askCount = count <= 0
      ? sentences.length
      : math.min(count, sentences.length);
  final system = '''你是英语写作教练,出"句式改写"练习题。用户给你英文原句,
请给出改写要求与参考改写(必须保持原意,只换结构/表达)。返回 JSON:
{"tasks":[{"prompt_zh":"改写任务要求(中文,含原句与要练的句式)","prompt_en":"原句(英文)",
"reference":"参考改写(英文,保持原意)","hint":"1 条改写思路(中文)",
"grammar_points":["非谓语","倒装"]}]}
要求:
1. 一句一题;改写方向由输入给出(如"升级句式/合并从句/换更自然表达");
2. reference 必须是真的改写(不是原句照抄),且不改变原意;
3. 题目来自用户材料,不编造出处。
$_sourceDiscipline''';
  final buffer = StringBuffer()..writeln('【原句(共 ${sentences.length} 条)】');
  for (var i = 0; i < sentences.length; i++) {
    buffer.writeln('${i + 1}. ${sentences[i]}');
  }
  buffer
    ..writeln()
    ..writeln(
      '【改写方向】${rewriteFocus.trim().isEmpty ? '升级句式' : rewriteFocus.trim()}',
    )
    ..writeln('【出题数量】$askCount 题(最多不超过输入句数)');
  if (levelHint.trim().isNotEmpty) {
    buffer.writeln('【用户水平】${levelHint.trim()}');
  }
  buffer.writeln('请按上面的 JSON 格式输出。');
  return OutputPrompt(system: system, user: buffer.toString());
}

/// **路径 3:段落任务**(摘要 / 读后续写 / 观点段 / 图表描述)。
///
/// [materialText] 会按 [maxMaterialWords] 截断(默认 1500 词)——
/// 段落任务只需要"读懂材料",不是整本喂给模型(既省钱又避免超长被截断)。
OutputPrompt buildParagraphTaskPrompt({
  required String materialText,
  String taskKind = 'summary',
  required int wordCount,
  String levelHint = '',
  String bandHint = '',
  String? examGoal,
  int maxMaterialWords = 1500,
}) {
  final kind = taskKind.trim().isEmpty ? 'summary' : taskKind.trim();
  final kindLabel = _paragraphKindLabel(kind);
  final material = truncateWords(materialText.trim(), maxMaterialWords);
  final truncated = _wordCount(materialText) > maxMaterialWords;
  final words = wordCount > 0 ? wordCount : _defaultWordCountForKind(kind);
  final system =
      '''你是英语写作出题老师。根据用户给的材料,出"$kindLabel"任务。
返回 JSON:
{"tasks":[{"prompt_zh":"任务要求(中文;写清读者对象、要点提示与字数)",
"reference":"参考要点(中文/英文分点,3~5 条;不是整篇范文)","hint":"1 条写作提示(中文)",
"word_count":$words}]}
要求:
1. 任务必须**紧扣给定材料**:读后续写只能续材料的情节,摘要只能概括材料内容,
观点段要围绕材料的主题,图表描述只能描述材料里的数据;
2. 参考要点必须是"这道题的作答方向",不要写成空话;不要编造材料里没有的事实/数字;
3. 题目来自用户材料,不编造出处。
$_sourceDiscipline''';
  final buffer = StringBuffer()
    ..writeln('【材料正文${truncated ? '(已截断到约 $maxMaterialWords 词)' : ''}】')
    ..writeln(material)
    ..writeln()
    ..writeln('【任务类型】$kindLabel')
    ..writeln('【字数要求】约 $words 词')
    ..writeln('【出题数量】1 题(如需多题,可在同一任务里分要点)');
  if (levelHint.trim().isNotEmpty) {
    buffer.writeln('【用户水平】${levelHint.trim()}');
  }
  if (bandHint.trim().isNotEmpty) {
    buffer.writeln('【难度要求】${bandHint.trim()}');
  }
  final goal = examGoal?.trim() ?? '';
  if (goal.isNotEmpty) {
    buffer.writeln('【目标考试】$goal(评分口径按该考试写作要求)');
  }
  buffer.writeln('请按上面的 JSON 格式输出。');
  return OutputPrompt(system: system, user: buffer.toString());
}

/// **路径 4:真题写作/翻译**(输入 = 检索抓到的真题页正文 + 来源 URL)。
///
/// ⚠️ 这是"真题"的唯一合法入口:
/// - [sourceText] 必须是从真实网页 fetch 到的正文;
/// - [sourceUrls] 必须非空,且逐题回传(解析阶段校验);
/// - 正文里看不出题目 → 返回空 tasks,**宁可不生成**。
OutputPrompt buildExamWritingPrompt({
  required String examType,
  required String section,
  required String sourceText,
  required List<String> sourceUrls,
  int? year,
  String levelHint = '',
}) {
  final examLabel = examLabelFor(examType);
  final sectionLabel = sectionLabelFor(section);
  final source = sourceText.trim();
  final allowedUrls = sourceUrls
      .map((u) => u.trim())
      .where((u) => u.isNotEmpty)
      .toList();
  final sourceForPrompt = truncateWords(source, 1200);
  final system =
      '''你是$examLabel $sectionLabel的题库整理助手。用户会给你从网上抓到的**真题页面正文**,
你只能**基于这段正文**整理出题目,不得编造。返回 JSON:
{"tasks":[{"prompt_zh":"题目要求(忠实转述/照抄正文里的题干,不要虚构)",
"prompt_en":"","reference":"参考范文或参考译文(正文里有才填,没有就空串)",
"word_count":${section == 'translation' ? 0 : 150},"hint":"1 条作答提示(中文)"}],
"note":"来源说明(一句话)"}
要求:
1. **正文里没有题目就返回 {"tasks": []}**;正文与该题型不符(比如是新闻/广告)也返回空;
2. 禁止编造题目、禁止编造"某年真题"标签、禁止编造参考范文;
3. 每道题的 source_url 必须原样使用下面给出的 URL(解析时会核对);
4. 参考范文/参考译文只能从正文里摘录;没有就空串。
$_sourceDiscipline''';
  final buffer = StringBuffer()
    ..writeln('【考试】$examLabel${year != null ? '($year 年)' : ''}')
    ..writeln('【题型】$sectionLabel')
    ..writeln('【可用来源 URL(每道题只能从这里取)】');
  for (final url in allowedUrls) {
    buffer.writeln('- $url');
  }
  if (allowedUrls.isEmpty) buffer.writeln('- (无:此时只能返回空 tasks)');
  buffer
    ..writeln()
    ..writeln('【抓到的页面正文(已截断到约 1200 词)】')
    ..writeln(sourceForPrompt)
    ..writeln()
    ..writeln('【出题数量】1~2 题(正文里能确定几题就出几题,不要硬凑)');
  if (levelHint.trim().isNotEmpty) {
    buffer.writeln('【用户水平】${levelHint.trim()}');
  }
  buffer.writeln('请按上面的 JSON 格式输出。');
  return OutputPrompt(system: system, user: buffer.toString());
}

// ═══════════════════════════════════════════════════════════════════════
// 解析:模型 JSON → 题组(全部纯函数,失败返回空/null 不抛)
// ═══════════════════════════════════════════════════════════════════════

/// **通用**出题解析:把模型返回的 `{"tasks":[...]}` 解析成题列表。
///
/// 容错原则(与评分解析一致):
/// - 围栏/前后说明 → [extractJsonObject];
/// - 坏 JSON / 没有 tasks → 返回空列表(**不抛**,调用方按"这次没出成题"处理);
/// - 单题字段缺失/类型不对 → 跳过该字段或整题,不影响其它题;
/// - 题干(reference/prompt_zh/prompt_en)全空的题 → 丢弃。
///
/// [tier]/[type]/[rubricId]/[source]/[verifyStatus] 是整组默认值,
/// 单题里若有覆盖字段(模型给了 `rubric_id`/`source_span` 等)优先用单题的。
List<OutputTaskSpec> parseTaskList(
  String content, {
  required OutputTier tier,
  required String type,
  String rubricId = '',
  String source = 'ai',
  String sourceUrl = '',
  String verifyStatus = 'pending',
  int? materialId,
  String fallbackSourceSpan = '',
}) {
  final jsonText = extractJsonObject(content);
  if (jsonText.isEmpty) return const <OutputTaskSpec>[];

  Map<String, dynamic>? map;
  try {
    final decoded = jsonDecode(jsonText);
    if (decoded is Map) map = Map<String, dynamic>.from(decoded);
  } catch (e) {
    debugPrint('ReadFlow 出题结果不是合法 JSON(已忽略): ${_short(e)}');
    return const <OutputTaskSpec>[];
  }
  if (map == null) return const <OutputTaskSpec>[];

  final rawTasks = map['tasks'] ?? map['items'] ?? map['questions'];
  if (rawTasks is! List || rawTasks.isEmpty) return const <OutputTaskSpec>[];

  final tasks = <OutputTaskSpec>[];
  for (final raw in rawTasks) {
    if (raw is! Map) continue;
    final promptZh =
        '${raw['prompt_zh'] ?? raw['prompt'] ?? raw['question'] ?? raw['task'] ?? ''}'
            .trim();
    final promptEn = '${raw['prompt_en'] ?? raw['original'] ?? ''}'.trim();
    final reference =
        '${raw['reference'] ?? raw['reference_answer'] ?? raw['answer'] ?? ''}'
            .trim();
    // 三个内容字段全空 → 这道题没有可展示的内容,丢弃
    if (promptZh.isEmpty && promptEn.isEmpty && reference.isEmpty) continue;

    final taskType = '${raw['type'] ?? type}'.trim();
    final itemRubric = '${raw['rubric_id'] ?? rubricId}'.trim();
    final hint = '${raw['hint'] ?? raw['tip'] ?? ''}'.trim();
    var sourceSpan = '${raw['source_span'] ?? ''}'.trim();
    if (sourceSpan.isEmpty) {
      // 回译题的"材料原文"就是英文原句;其它题允许用调用方给的兜底
      sourceSpan = (taskType == 'back_translation' && reference.isNotEmpty)
          ? reference
          : fallbackSourceSpan;
    }
    // 单题 source_url 只接受"调用方给过的 URL"(防模型编造链接)
    var itemSourceUrl = '${raw['source_url'] ?? ''}'.trim();
    if (itemSourceUrl.isEmpty) {
      itemSourceUrl = sourceUrl;
    } else if (sourceUrl.isNotEmpty && itemSourceUrl != sourceUrl) {
      itemSourceUrl = sourceUrl;
    }

    tasks.add(
      OutputTaskSpec(
        tier: tier,
        type: taskType,
        promptZh: promptZh,
        promptEn: promptEn,
        reference: reference,
        rubricId: itemRubric,
        abilityTags: _stringList(raw['ability_tags']),
        grammarPoints: _stringList(raw['grammar_points']),
        wordCount: _toInt(raw['word_count']),
        sourceSpan: sourceSpan,
        materialId: materialId,
        sourceUrl: itemSourceUrl,
        source: '${raw['source'] ?? source}'.trim(),
        verifyStatus: '${raw['verify_status'] ?? verifyStatus}'.trim(),
        hint: hint,
      ),
    );
  }
  return tasks;
}

/// 路径 1 专用解析:回译题(题面=中文译文,参考=英文原句)。
List<OutputTaskSpec> parseBackTranslationTasks(
  String content, {
  String levelHint = '',
  String? materialSourceSpan,
}) {
  return parseTaskList(
    content,
    tier: OutputTier.sentence,
    type: 'back_translation',
    rubricId: 'back_translation',
    source: 'ai',
    verifyStatus: 'pending',
    fallbackSourceSpan: materialSourceSpan ?? '',
  );
}

/// 路径 2 专用解析:句式改写(无 rubric,结果页用"原句 vs 改写"对照)。
List<OutputTaskSpec> parseSentenceRewriteTasks(String content) {
  return parseTaskList(
    content,
    tier: OutputTier.sentence,
    type: 'sentence_rewrite',
    // 句式改写没有 AI rubric:参考改写就是标准答案,结果页做逐词对照
    rubricId: '',
    source: 'ai',
    verifyStatus: 'pending',
  );
}

/// 路径 3 专用解析:段落任务(摘要用 summary rubric;其余用写作 rubric)。
List<OutputTaskSpec> parseParagraphTasks(
  String content, {
  String taskKind = 'summary',
}) {
  final kind = taskKind.trim().isEmpty ? 'summary' : taskKind.trim();
  return parseTaskList(
    content,
    tier: OutputTier.paragraph,
    type: kind,
    rubricId: kind == 'summary' ? 'summary' : 'cet4_writing',
    source: 'ai',
    verifyStatus: 'pending',
  );
}

/// 路径 4 专用解析:真题写作/翻译。
///
/// **无来源不生成**:`sourceUrls` 为空时直接返回空列表;每题都会带上
/// 来源 URL(且只允许来自 [sourceUrls],防止模型编造链接)。
List<OutputTaskSpec> parseExamWritingTasks(
  String content, {
  required String examType,
  required String section,
  required List<String> sourceUrls,
}) {
  final urls = sourceUrls
      .map((u) => u.trim())
      .where((u) => u.isNotEmpty)
      .toList();
  if (urls.isEmpty) {
    debugPrint('ReadFlow 真题出题:没有来源 URL,拒绝生成(禁止编造题源)');
    return const <OutputTaskSpec>[];
  }
  final isTranslation = section == 'translation';
  final tasks = parseTaskList(
    content,
    tier: OutputTier.essay,
    type: isTranslation ? 'exam_translation' : 'exam_writing',
    rubricId: isTranslation ? 'cet4_translation' : 'cet4_writing',
    source: 'exam',
    sourceUrl: urls.first,
    // 真题由 AI 从抓取页面结构化而来,未人工校对 → pending
    verifyStatus: 'pending',
  );
  // 二次保险:任何没有 URL 的题都不许进"真题"题组
  return [
    for (final task in tasks)
      if (task.sourceUrl.trim().isNotEmpty)
        task
      else
        task.copyWith(sourceUrl: urls.first),
  ];
}

// ═══════════════════════════════════════════════════════════════════════
// 纯函数:材料/考试小工具
// ═══════════════════════════════════════════════════════════════════════

/// 从材料正文抽句子(回译/改写的原料)。
///
/// 规则:
/// - 按 `.!?` + 空白切句(英文材料;中文材料也能切,但回译路径应传英文);
/// - 只保留 [minWords]~[maxWords] 词的句子(太短没内容、太长不适合单句回译);
/// - 去重(同一句出现两次只出一次题);
/// - 最多 [max] 句(按原文顺序,不随机 —— 保持"来自材料哪一段"的可追溯性)。
List<String> extractSentences(
  String materialText, {
  int max = 6,
  int minWords = 6,
  int maxWords = 40,
}) {
  final text = materialText.trim();
  if (text.isEmpty) return const <String>[];
  final out = <String>[];
  final seen = <String>{};
  final pieces = text.split(RegExp(r'(?<=[.!?])\s+|\n+'));
  for (final piece in pieces) {
    final sentence = piece
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[-*•\d.)\s]+'), '') // 去掉列表符号/序号
        .trim();
    if (sentence.isEmpty) continue;
    final words = sentence.split(RegExp(r'\s+')).length;
    if (words < minWords || words > maxWords) continue;
    final key = sentence.toLowerCase();
    if (!seen.add(key)) continue;
    out.add(sentence);
    if (out.length >= max) break;
  }
  return out;
}

/// 按词数截断(段落任务/真题正文用),超出时补一句说明由调用方决定。
String truncateWords(String text, int maxWords) {
  final source = text.trim();
  if (source.isEmpty || maxWords <= 0) return source;
  final words = source.split(RegExp(r'\s+'));
  if (words.length <= maxWords) return source;
  return '${words.take(maxWords).join(' ')}…';
}

/// 纯函数:从 `DrillCatalog` 目标 id 列表推 `exercise_sets.exam_type`。
///
/// 为什么需要:用户勾的目标是"四六级/考研/雅思"这种**学习目标**,
/// 数据库里存的是 `cet4/cet6/kaoyan/ielts` 这种**考试类型**;
/// 两套口径必须在一处映射,散着写迟早对不上。
String examTypeFromGoalIds(List<String> goalIds) {
  final ids = goalIds.map((g) => g.trim().toLowerCase()).toSet();
  if (ids.contains('cet') || ids.contains('cet4') || ids.contains('cet6')) {
    return ids.contains('cet6') ? 'cet6' : 'cet4';
  }
  if (ids.contains('kaoyan')) return 'kaoyan';
  if (ids.contains('ielts') || ids.contains('toefl')) return 'ielts';
  if (ids.contains('nce') || ids.contains('new_concept')) return 'nce';
  return 'none';
}

/// 考试类型的中文名(提示词/UI 共用一份口径)
String examLabelFor(String examType) => switch (examType.trim().toLowerCase()) {
  'cet4' => '英语四级(CET-4)',
  'cet6' => '英语六级(CET-6)',
  'kaoyan' => '考研英语',
  'ielts' => '雅思',
  'toefl' => '托福',
  'nce' => '新概念英语',
  _ => '英语',
};

/// 题型分区的中文名
String sectionLabelFor(String section) => switch (section.trim()) {
  'writing' => '写作',
  'translation' || 'reading_translation' => '段落翻译',
  'back_translation' => '回译',
  'blank_filling' => '选词填空',
  _ => '写作与翻译',
};

/// 构造真题检索的英文 query(Search 接口对英文 query 效果更好)。
///
/// 例:`CET-4 writing past exam 2023`(年份可空)。
String buildExamSearchQuery({
  required String examType,
  required String section,
  int? year,
}) {
  final exam = switch (examType.trim().toLowerCase()) {
    'cet4' => 'CET-4',
    'cet6' => 'CET-6',
    'kaoyan' => 'Postgraduate English Entrance Exam',
    'ielts' => 'IELTS',
    'toefl' => 'TOEFL',
    'nce' => 'New Concept English',
    _ => 'English exam',
  };
  final topic = section == 'translation' ? 'translation' : 'writing prompts';
  final yearText = year != null && year > 0 ? ' $year' : '';
  return '$exam $topic past exam$yearText';
}

/// 由 tier 推 `exercise_sets.section`(数据库枚举值)
String sectionForTier(OutputTier tier) => switch (tier) {
  OutputTier.word => 'blank_filling',
  OutputTier.sentence => 'back_translation',
  OutputTier.paragraph => 'writing',
  OutputTier.essay => 'writing',
};

/// 材料 → 段落任务类型(按目标选:备考写"观点段",其他写"摘要")
String paragraphKindForGoals(List<String> goalIds) {
  final exam = examTypeFromGoalIds(goalIds);
  return exam == 'none' ? 'summary' : 'opinion';
}

// ═══════════════════════════════════════════════════════════════════════
// OutputComposer:唯一会发请求的地方
// ═══════════════════════════════════════════════════════════════════════

/// 出题 + 评分编排器。
///
/// 构造函数可注入:
/// - `api`:[DeepseekApiService](默认实例)—— 发请求复用它的
///   `postWithReasoningFallback`(**不新建 Dio**,超时/降级/思考档位与全 App 一致);
/// - `searchClient`:[DeepSeekSearchClient](默认按配置创建)—— 真题检索用;
///   传 null 且 `autoResolveSearch=false` = 完全禁用真题路径(测试/离线场景)。
///
/// 失败约定:**所有公开方法失败返回 null**,原因只进 debugPrint ——
/// UI 拿 null 显示"这次没出成题,可重试",不让异常打到页面。
class OutputComposer {
  final DeepseekApiService _api;
  final DeepSeekSearchClient? _search;

  OutputComposer({
    DeepseekApiService? api,
    DeepSeekSearchClient? searchClient,
    bool autoResolveSearch = true,
  }) : _api = api ?? DeepseekApiService(),
       _search =
           searchClient ?? (autoResolveSearch ? DeepSeekSearchClient() : null);

  /// 真题检索是否可用(UI 可据此禁用"抓真题"按钮并给配置引导)
  bool get examSearchAvailable => _search?.available ?? false;

  /// 从**材料**出题(写句/写段/写篇)。
  ///
  /// [tier] 取 `sentence` / `paragraph` / `essay`(写词不走 AI 出题:
  /// 词从生词本/词表来,见 PLAN-V3 §2.3 的"写词"行)。
  ///
  /// 材料来自用户已有材料(已入库的 `materials`)或用户导入文本:
  /// - 回译路径:从正文抽 3~[taskCount] 个合格句 → 出"中文题面/英文参考"题;
  /// - 段落路径:摘要/观点段(按目标考试选)→ 出 1 题;
  /// - 写篇路径:观点/续写 → 出 1~2 题(带写作 rubric)。
  ///
  /// 返回 null = 材料不够/模型没返回可解析题组/API 未配置。
  Future<OutputSetSpec?> composeFromMaterial({
    required String materialText,
    required List<String> examGoals,
    required String levelHint,
    required String bandHint,
    required String tier,
    int? materialId,
    int taskCount = 5,
  }) async {
    final text = materialText.trim();
    if (text.isEmpty) return null;
    final targetTier = OutputTier.fromId(tier);
    if (targetTier == OutputTier.word) {
      debugPrint('ReadFlow 出题:写词不走 AI 出题(应来自生词本),已跳过');
      return null;
    }
    final examType = examTypeFromGoalIds(examGoals);

    OutputPrompt prompt;
    String type;
    String rubricId;
    var finalTier = targetTier;
    switch (targetTier) {
      case OutputTier.sentence:
        final sentences = extractSentences(text, max: taskCount);
        if (sentences.isEmpty) return null;
        prompt = buildBackTranslationPrompt(
          englishSentences: sentences,
          levelHint: levelHint,
          bandHint: bandHint,
          count: taskCount,
        );
        type = 'back_translation';
        rubricId = 'back_translation';
      case OutputTier.paragraph:
        final kind = paragraphKindForGoals(examGoals);
        prompt = buildParagraphTaskPrompt(
          materialText: text,
          taskKind: kind,
          wordCount: 120,
          levelHint: levelHint,
          bandHint: bandHint,
          examGoal: examType == 'none' ? null : examLabelFor(examType),
        );
        type = kind;
        rubricId = kind == 'summary' ? 'summary' : 'cet4_writing';
      case OutputTier.essay:
        // 写篇：材料只提供"话题语境",题目本身是写作任务 — 用观点段提示词，
        // 但题组 tier/section 记 essay，方便 UI 走"作文"骨架。
        prompt = buildParagraphTaskPrompt(
          materialText: text,
          taskKind: 'opinion',
          wordCount: 150,
          levelHint: levelHint,
          bandHint: bandHint,
          examGoal: examType == 'none' ? null : examLabelFor(examType),
        );
        type = 'opinion';
        rubricId = 'cet4_writing';
        finalTier = OutputTier.essay;
      case OutputTier.word:
        return null; // 上面已拦，防御性兜底
    }

    final content = await _complete(
      prompt,
      maxTokens: 4096,
      temperature: 0.4,
      purpose: '出题(材料·${finalTier.id})',
      // 批 8 · P2-3:出题要吐完整 JSON(题干/参考/rubric 标签),用 JSON mode
      // 降低"围栏/夹带说明"导致的解析失败;思考档按任务取模型默认 high。
      jsonMode: true,
      thinkingLevel: BaseApiService.thinkingForTask('output'),
    );
    if (content == null) return null;
    final tasks = parseTaskList(
      content,
      tier: finalTier,
      type: type,
      rubricId: rubricId,
      source: 'ai',
      verifyStatus: 'pending',
      materialId: materialId,
    );
    if (tasks.isEmpty) return null;
    return OutputSetSpec(
      title: '${finalTier.label}练习 · 来自材料',
      tier: finalTier,
      source: 'ai',
      examType: examType,
      section: sectionForTier(finalTier),
      tasks: tasks,
      rubricId: tasks.first.rubricId,
      licenseNote: 'AI 基于你提供的材料生成,未经人工校对,练前请自行核对。',
      verifyStatus: 'pending',
    );
  }

  /// 从**真题**出题:检索 → 抓正文 → 结构化。
  ///
  /// 流程(每一步失败都返回 null,绝不凭空出"真题"):
  /// 1. [DeepSeekSearchClient] 是否可用(没有 DS 官方 Key → 返回 null);
  /// 2. search(`CET-4 writing prompts past exam 2023`)拿候选;
  /// 3. fetch 前 [maxPages] 条有 URL 的页面正文(为空/抓不到就跳过);
  /// 4. 全部抓不到正文 → null(**没有原文就不生成题目**);
  /// 5. 用 [buildExamWritingPrompt] 让模型只基于正文切题,解析时强制带来源 URL。
  Future<OutputSetSpec?> composeFromExam({
    required String examType,
    required String section,
    int? year,
    int maxPages = 3,
    String levelHint = '',
  }) async {
    final search = _search;
    if (search == null || !search.available) {
      debugPrint('ReadFlow 真题出题:DS Search 不可用(未配置官方 Key),已跳过');
      return null;
    }
    final query = buildExamSearchQuery(
      examType: examType,
      section: section,
      year: year,
    );
    final hits = await search.search(query, count: 5);
    if (hits.isEmpty) {
      debugPrint('ReadFlow 真题出题:搜索无结果($query)');
      return null;
    }

    final pages = <({String url, String text})>[];
    for (final hit in hits) {
      if (pages.length >= maxPages) break;
      final url = hit.url.trim();
      if (url.isEmpty) continue; // 客户端已过滤，防御性再查
      final page = await search.fetch(url);
      final text = page?.content.trim() ?? '';
      if (text.isEmpty) continue;
      pages.add((url: url, text: text));
    }
    if (pages.isEmpty) {
      debugPrint('ReadFlow 真题出题:候选页全部抓不到正文,拒绝无来源生成');
      return null;
    }

    final sourceUrls = pages.map((p) => p.url).toList();
    final sourceText = pages
        .map((p) => '【来源:${p.url}】\n${p.text}')
        .join('\n\n---\n\n');
    final prompt = buildExamWritingPrompt(
      examType: examType,
      section: section,
      sourceText: sourceText,
      sourceUrls: sourceUrls,
      year: year,
      levelHint: levelHint,
    );
    final content = await _complete(
      prompt,
      maxTokens: 4096,
      temperature: 0.3,
      purpose: '出题(真题·$examType/$section)',
      // 真题出题同样走 JSON mode + 默认思考档(见 P2-3)
      jsonMode: true,
      thinkingLevel: BaseApiService.thinkingForTask('output'),
    );
    if (content == null) return null;

    final tasks = parseExamWritingTasks(
      content,
      examType: examType,
      section: section,
      sourceUrls: sourceUrls,
    );
    if (tasks.isEmpty) return null;
    final yearText = year != null && year > 0 ? '$year 年' : '近年';
    return OutputSetSpec(
      title:
          '${examLabelFor(examType)} · ${sectionLabelFor(section)}真题($yearText)',
      tier: OutputTier.essay,
      source: 'exam',
      examType: examType,
      section: section,
      tasks: tasks,
      rubricId: tasks.first.rubricId,
      licenseNote:
          '题目来自公开网页抓取(${sourceUrls.join(' , ')}),'
          '仅本地学习使用;AI 结构化为未人工校对状态。',
      sourceUrls: sourceUrls,
      verifyStatus: 'pending',
    );
  }

  /// 评分(一次 AI rubric 调用)。
  ///
  /// [task] 是题面/题目要求(评分提示词必须带题目,否则"内容切题"没法判);
  /// [answer] 是用户作答。失败(未配置/解析失败/网络)返回 null。
  Future<ScoredOutput?> score({
    required OutputRubric rubric,
    required String task,
    required String answer,
    String? notes,
  }) async {
    if (answer.trim().isEmpty) return null;
    if (rubric.dimensions.isEmpty) return null;
    final prompt = OutputPrompt(
      system: '你是严谨的英语评分员,只输出 JSON。',
      user: buildScoringPrompt(
        rubric: rubric,
        task: task,
        answer: answer,
        notes: notes,
      ),
    );
    final content = await _complete(
      prompt,
      maxTokens: 4096,
      // 评分要稳定:温度低,避免同一篇作文两次评分差太多
      temperature: 0.2,
      purpose: '评分(${rubric.id})',
      // 评分必须逐维给证据,轻思考容易"拍脑袋给分" → JSON mode + high
      jsonMode: true,
      thinkingLevel: BaseApiService.thinkingForTask('scoring'),
    );
    if (content == null) return null;
    return parseScoringResult(content, rubric: rubric);
  }

  // ── HTTP(复用现有 DeepseekApiService,不新建 Dio) ───────────────────

  /// 发一次非流式 chat 请求并取正文。
  ///
  /// 为什么路径要按端点判断:`DeepseekApiService` 在"副槽位未配置"时会回落到
  /// 主槽位(方舟),而方舟的 chat 路径是 `/chat/completions`(不带 /v1)——
  /// 旧代码把 `/v1/chat/completions` 写死,回落主槽位时会 404。
  Future<String?> _complete(
    OutputPrompt prompt, {
    required int maxTokens,
    required double temperature,
    required String purpose,
    bool jsonMode = false,
    String? thinkingLevel,
  }) async {
    try {
      if (!_api.isConfigured) {
        debugPrint('ReadFlow $purpose:API 未配置,跳过');
        return null;
      }
      final cfg = _api.config;
      final path = cfg.isDeepSeekOfficial
          ? '/v1/chat/completions'
          : '/chat/completions';
      final response = await _api.postWithReasoningFallback(
        path,
        BaseApiService.buildChatBody(
          cfg: cfg,
          temperature: temperature,
          maxTokens: maxTokens,
          jsonMode: jsonMode,
          thinkingLevel: thinkingLevel,
          messages: [
            {'role': 'system', 'content': prompt.system},
            {'role': 'user', 'content': prompt.user},
          ],
        ),
        cfg: cfg,
        jsonMode: jsonMode,
        // 出题/评分都是"一次算完才返回":90s 覆盖长 JSON 生成,
        // 又比默认 180s 早失败(用户不用干等 3 分钟)
        receiveTimeout: const Duration(seconds: 90),
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      return BaseApiService.extractContentWithReasoning(data);
    } catch (e) {
      debugPrint('ReadFlow $purpose 失败: ${_short(e)}');
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 小工具(容错 + 类型转换)
// ═══════════════════════════════════════════════════════════════════════

List<String> _stringList(Object? raw) {
  if (raw is List) {
    return raw
        .map((e) => '${e ?? ''}'.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (raw is String) {
    return raw
        .split(RegExp(r'[,，、/;；\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return const <String>[];
}

int _toInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) {
    final match = RegExp(r'\d+').firstMatch(raw);
    if (match != null) return int.tryParse(match.group(0)!) ?? 0;
  }
  return 0;
}

int? _toIntOrNull(Object? raw) {
  final value = _toInt(raw);
  return value > 0 ? value : null;
}

int _wordCount(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

String _paragraphKindLabel(String kind) => switch (kind) {
  'summary' => '摘要写作',
  'continuation' => '读后续写',
  'opinion' => '观点段写作',
  'chart' => '图表描述',
  _ => '段落写作',
};

int _defaultWordCountForKind(String kind) => switch (kind) {
  'summary' => 80,
  'continuation' => 150,
  'chart' => 120,
  _ => 120,
};

String _short(Object? error) {
  final flat = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length > 120 ? '${flat.substring(0, 120)}…' : flat;
}
