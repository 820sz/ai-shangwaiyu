import 'dart:convert';

import 'deepseek_api.dart';
import 'input_prefs.dart';

/// 「自由搜」的检索词规划（2026-11-08 用户要求）：
///
/// 用户原话：搜《原子习惯》时，AI 要能判断原版书名是 *Atomic Habits* 再去搜，
/// 而不是拿中文书名硬搜出一堆无关内容。
///
/// 纪律：
/// - 只做"把用户意图翻译成更可检索的英文/原名"这一件事，不改用户意图；
/// - 模型不可用/返回坏 JSON 时退回原关键词（不阻塞搜索）；
/// - 纯函数可单测（注入 handler）。
class SearchQueryPlan {
  /// 用户原始输入（原样保留，用于展示/历史）
  final String original;

  /// 规划出的检索词（第一个是主检索词，其余为候选）
  final List<String> queries;

  /// 推测的材料类型（book/paper/news/podcast/wiki/article/空=不确定）
  final String kind;

  /// 给用户看的说明（例：已按原版书名《Atomic Habits》检索）
  final String reason;

  const SearchQueryPlan({
    required this.original,
    this.queries = const <String>[],
    this.kind = '',
    this.reason = '',
  });

  /// 原词直搜（不规划）
  const SearchQueryPlan.raw(this.original)
      : queries = const <String>[],
        kind = '',
        reason = '';

  bool get changed {
    if (queries.isEmpty) return false;
    final primary = queries.first.trim().toLowerCase();
    final raw = original.trim().toLowerCase();
    return primary.isNotEmpty && primary != raw;
  }

  String get primaryQuery =>
      queries.isEmpty ? original.trim() : queries.first.trim();
}

typedef SearchQueryPlannerHandler = Future<SearchQueryPlan?> Function(
    String raw);

/// 检索词规划器：默认调 DeepSeek（JSON mode），失败一律退回原词。
class SearchQueryPlanner {
  final SearchQueryPlannerHandler _handler;
  final Future<List<String>> Function(String intent, {int max})
      _planIntentHandler;

  SearchQueryPlanner({
    SearchQueryPlannerHandler? handler,
    Future<List<String>> Function(String intent, {int max})? planIntentHandler,
  })  : _handler = handler ?? defaultSearchQueryPlannerHandler,
        _planIntentHandler =
            planIntentHandler ?? defaultSearchIntentPlanner;

  Future<SearchQueryPlan> plan(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return SearchQueryPlan.raw(trimmed);
    // 纯英文/拉丁关键词已经可检索，不再花一次模型调用。
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(trimmed);
    if (!hasCjk) return SearchQueryPlan.raw(trimmed);
    try {
      final plan = await _handler(trimmed);
      if (plan != null && plan.queries.isNotEmpty) {
        // 清洗：去空、去重、最多 3 条
        final seen = <String>{};
        final clean = <String>[];
        for (final q in plan.queries) {
          final text = q.trim();
          if (text.isEmpty) continue;
          if (!seen.add(text.toLowerCase())) continue;
          clean.add(text);
          if (clean.length >= 3) break;
        }
        if (clean.isEmpty) return SearchQueryPlan.raw(trimmed);
        return SearchQueryPlan(
          original: trimmed,
          queries: clean,
          kind: plan.kind,
          reason: plan.reason,
        );
      }
    } catch (_) {
      // 规划失败不阻塞搜索：退回原词
    }
    return SearchQueryPlan.raw(trimmed);
  }

  /// 「按我的情况找」用：把整段中文需求（目标/兴趣/弱项）规划成 1~3 条
  /// **英文检索词**（目标只用于难度，不直接当检索词）。失败返回空列表。
  Future<List<String>> planQueries(String intent, {int max = 3}) async {
    final text = intent.trim();
    if (text.isEmpty) return const <String>[];
    // 已经全是英文 → 直接把拆出来的英文短语当检索词（不花模型调用）
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
    if (!hasCjk) {
      final out = <String>[];
      for (final m in RegExp(r'[A-Za-z][A-Za-z ]{3,}').allMatches(text)) {
        final q = m.group(0)!.trim();
        if (q.isNotEmpty && !out.contains(q)) out.add(q);
        if (out.length >= max) break;
      }
      return out;
    }
    try {
      final queries = await _planIntentHandler(text, max: max);
      final clean = <String>[];
      final seen = <String>{};
      for (final q in queries) {
        final t = q.trim();
        if (t.isEmpty) continue;
        if (!seen.add(t.toLowerCase())) continue;
        clean.add(t);
        if (clean.length >= max) break;
      }
      return clean;
    } catch (_) {
      return const <String>[];
    }
  }

}

/// 默认实现：让模型识别中文书名/译名/主题对应的英文原名或最合适检索词。
Future<SearchQueryPlan?> defaultSearchQueryPlannerHandler(String raw) async {
  const system = '''你是检索词规划器。用户想找英文学习材料，但可能输入中文书名/译名/主题。
你的任务：判断它对应的**英文原名**或**最合适的英文检索词**（用于书籍/论文/外刊/播客/百科检索）。

规则：
1. 只输出 JSON：{"queries":["...","..."],"kind":"book|paper|news|podcast|wiki|article|","reason":"一句中文说明"}；
2. queries 1~3 条，优先"英文原名"（如《原子习惯》→ "Atomic Habits"），其次"英文原名 + 作者/主题"；
3. 不确定原版名时，给最可能命中的英文主题词；**不许编造不存在的书名**；
4. kind 只在比较确定时给（书→book，论文→paper，外刊新闻→news，播客→podcast，百科→wiki），不确定给空串；
5. reason 只写"已按什么检索"，不要长解释、不要客套。''';
  final user = '用户输入：$raw';
  final text = await DeepseekApiService().completeJson(
    system: system,
    user: user,
    maxTokens: 300,
    temperature: 0.2,
    // 用户可在「找材料 → 筛选 → AI 思考强度」里调(默认标准 = low);
    // 之前这里写的是任务名 'output'(非法档位 → 被静默降级成 disabled)
    thinkingLevel: AiThinkingLevel.load().planLevel,
  );
  if (text == null || text.trim().isEmpty) return null;
  final map = _decodeJsonMap(text);
  if (map == null) return null;
  final rawQueries = map['queries'];
  final queries = <String>[];
  if (rawQueries is List) {
    for (final q in rawQueries) {
      if (q is String && q.trim().isNotEmpty) queries.add(q.trim());
    }
  }
  return SearchQueryPlan(
    original: raw,
    queries: queries,
    kind: '${map['kind'] ?? ''}'.trim(),
    reason: '${map['reason'] ?? ''}'.trim(),
  );
}

/// 容错解析 JSON（去围栏/截取第一个 {...}）。
Map<String, dynamic>? _decodeJsonMap(String raw) {
  var text = raw.trim();
  final fence = RegExp(r'```(?:json)?').firstMatch(text);
  if (fence != null) {
    text = text.substring(fence.end);
  }
  final endFence = text.indexOf('```');
  if (endFence >= 0) text = text.substring(0, endFence);
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {}
  return null;
}

/// 默认实现：把「按我的情况找」的一整段中文需求规划成 1~3 条英文检索词。
///
/// 关键纪律：**目标（四六级/考研…）只用于难度，不当检索词**；
/// 检索词要为"能搜到英文学习材料"服务（topic-first，如
/// "interesting science article for intermediate English readers"）。
Future<List<String>> defaultSearchIntentPlanner(
  String intent, {
  int max = 3,
}) async {
  final system = '''你是检索词规划器。用户想找**英文学习材料**，下面给出他的中文需求、兴趣、目标与难度。
请规划 1~$max 条**英文检索词**，目标是让公开源（Gutenberg/arXiv/RSS）或官方搜索能搜到可读的英文材料。

规则：
1. 只输出 JSON：{"queries":["...","..."],"reason":"一句中文说明"}；
2. 检索词要 topic-first（先主题、再类型/难度词），每条 2~8 个英文词；
3. **不要把考试名称（四六级/考研/雅思）当检索词**；考试目标只影响难度；
4. 不要把中文原样塞进检索词；不确定就把主题写成一般性英文表达（如 "interesting non-fiction article"）；
5. queries 去重、最多 $max 条。''';
  final text = await DeepseekApiService().completeJson(
    system: system,
    user: '用户需求：$intent',
    maxTokens: 300,
    temperature: 0.2,
    // 用户可在「找材料 → 筛选 → AI 思考强度」里调(默认标准 = low);
    // 之前这里写的是任务名 'output'(非法档位 → 被静默降级成 disabled)
    thinkingLevel: AiThinkingLevel.load().planLevel,
  );
  if (text == null || text.trim().isEmpty) return const <String>[];
  final map = _decodeJsonMap(text);
  if (map == null) return const <String>[];
  final raw = map['queries'];
  final out = <String>[];
  if (raw is List) {
    for (final q in raw) {
      if (q is String && q.trim().isNotEmpty) out.add(q.trim());
    }
  } else if (raw is String && raw.trim().isNotEmpty) {
    out.add(raw.trim());
  }
  return out;
}
