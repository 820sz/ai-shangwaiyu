import 'dart:async';
import 'dart:convert';

import '../models/learner_model.dart';
import '../models/vocabulary.dart';
import '../services/base_api.dart';
import '../services/deepseek_api.dart';
import '../services/deepseek_search.dart';
import '../services/doubao_api.dart' show DoubaoApiService;
import '../services/input_prefs.dart';
import '../services/material_library.dart';
import '../services/material_source.dart';
import '../services/original_search.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// **按需找材料 · 发现流水线**(v3 · 批 2 · C1-3/C1-5/C1-6/C1-7)
/// ═══════════════════════════════════════════════════════════════════════
///
/// 用户 2026-11-01 的原话:
/// > "输入里的需要最大程度发挥 AI(尤其是 deepseek v4.1 flash 1017)的适配,
/// >  以及 AI 找资源、爬材料的能力 …… 并且做好在 AI 学习软件这一场景下的
/// >  个性化、可选择化、具有指导性的运用。"
///
/// 旧实现的问题(侦察结论,见 `docs/research/input-ai.md`):
/// - AI 只把中文需求翻成英文检索词,返回 3 条 query **只用第 1 条**;
/// - 模型点名(picks)的作品**不参与检索**;
/// - 检索结果卡的难度是按源类型猜的,真实难度要抓回正文才算;
/// - 没有"官方联网检索"能力(现在有了 `/v1/tools/search` + `/v1/tools/fetch`)。
///
/// 这条流水线把顺序钉死为:
/// ```
/// 需求(InputPreferences)
///   → 检索计划(调用方传入 queries,通常来自 AI)
///   → 多源并发检索(公开源 + DeepSeek 官方 Search)
///   → 抓正文
///   → 本地难度分析(i+1 覆盖率,零 API 成本)
///   → 按"目标难度 + 权威度 + 相关性"排序
///   → 每篇给出**可解释的推荐理由**
/// ```
///
/// 边界(诚实):
/// - 不做浏览器渲染、不绕登录墙/验证码/付费墙 —— 抓不到就如实说;
/// - 不编造来源:没有 url 的结果一律丢弃;没抓到正文的条目会标注"未抓正文";
/// - 难度全部本地算(`MaterialLibrary.analyze`),AI 只负责"检索词/推荐理由的措辞"。
///
/// 可测性:纯函数(去重键、打分、排序、理由)都在文件上层单独导出;
/// 编排部分依赖真实网络,通过构造参数注入 [DeepSeekSearchClient] 与
/// [MaterialSourceService] 以便以后做集成测试。
class DiscoveredCandidate {
  /// 标题(可能是英文;中文标题需要另一条 AI 链路,不在本批)
  final String title;

  /// 出处链接(**必填**,无 url 的候选不会进这个类)
  final String url;

  /// 来源标签(如「NPR」「公版书」「DeepSeek 搜索」)
  final String sourceLabel;

  /// 内容形态(book/paper/news/podcast/wiki/article;决定卡片封面的类型身份图)
  final String kind;

  /// 摘要(公开源 note / 官方搜索 snippet+summary)
  final String snippet;

  /// 配图(公开源自带;官方搜索没给图)
  final String? imageUrl;

  /// 权威度 0~4(只有官方搜索给;公开源记 -1 = 未知)
  final int authority;

  /// 发布时间(只有官方搜索给;公开源没有 = null)。
  ///
  /// 批 8 加:两段式补救要把"真实候选 + 发布时间"交给模型判断时效
  /// (用户找"最近的报道"时,模型看得见日期才会换更精准的检索词)。
  final DateTime? date;

  /// 相关性 0~3(只有官方搜索给)
  final double rerankScore;

  /// 是否来自 DeepSeek 官方搜索(用于卡片上的来源标识与"权威度"展示)
  final bool fromSearchApi;

  /// 抓到的正文(没抓到 = null)
  final String? content;

  /// 本地难度分析(有正文才算得出来)
  final MaterialAnalysis? analysis;

  const DiscoveredCandidate({
    required this.title,
    required this.url,
    required this.sourceLabel,
    this.kind = 'article',
    this.snippet = '',
    this.imageUrl,
    this.authority = -1,
    this.date,
    this.rerankScore = 0,
    this.fromSearchApi = false,
    this.content,
    this.analysis,
  });

  bool get hasAnalysis => analysis != null;

  /// 词次覆盖率(泛读体验看这个;分析过才有)
  double? get coverage => analysis?.knownTokenRatio;

  DiscoveredCandidate copyWith({
    String? content,
    MaterialAnalysis? analysis,
  }) {
    return DiscoveredCandidate(
      title: title,
      url: url,
      sourceLabel: sourceLabel,
      kind: kind,
      snippet: snippet,
      imageUrl: imageUrl,
      authority: authority,
      date: date,
      rerankScore: rerankScore,
      fromSearchApi: fromSearchApi,
      content: content ?? this.content,
      analysis: analysis ?? this.analysis,
    );
  }

  Map<String, Object?> toMap() => {
        'title': title,
        'url': url,
        'source': sourceLabel,
        'kind': kind,
        'snippet': snippet,
        'image_url': imageUrl,
        'authority': authority,
        'rerank_score': rerankScore,
        'from_search_api': fromSearchApi,
      };
}

/// 一次"按需找材料"的完整结果。
class DiscoveryRun {
  /// 已抓正文并分析、按推荐度排序的条目
  final List<DiscoveredCandidate> items;

  /// 过程说明(源失败/没搜到/被偏好过滤了几条 —— 直接显示给用户,不隐瞒)
  final List<String> notes;

  /// 本次官方 Search/Fetch 成功请求数(计费口径)与估算花费
  final int searchApiRequests;
  final double estimatedCostCny;

  /// 官方搜索是否可用(未配置 DS 官方 Key 时为 false,此时只用公开源)
  final bool searchApiAvailable;
  final String searchApiUnavailableReason;

  /// 没有进入 items 的候选数(抓取失败/太短/与已有材料重复等)
  final int droppedCount;

  /// 是否触发了"两段式补救"(批 8 · P2-4:第一轮候选不足 → 换关键词再搜一轮)
  final bool refined;

  /// 补救轮实际使用的新检索词(未触发 = 空;UI/诊断据此说明"为什么又搜了一次")
  final List<String> refineQueries;

  const DiscoveryRun({
    required this.items,
    this.notes = const [],
    this.searchApiRequests = 0,
    this.estimatedCostCny = 0,
    this.searchApiAvailable = false,
    this.searchApiUnavailableReason = '',
    this.droppedCount = 0,
    this.refined = false,
    this.refineQueries = const <String>[],
  });

  bool get isEmpty => items.isEmpty;
}

/// 发现流水线。
class MaterialDiscovery {
  final DeepSeekSearchClient? _injectedClient;
  final MaterialSourceService _source;

  /// 补救轮"换关键词"的执行者(**可注入**,单测不联网/不调模型)。
  ///
  /// 默认实现 [defaultMaterialRefine] 会调 DeepseekApiService(JSON mode +
  /// 轻思考);测试/联调可注入假实现,只验证"什么时候触发、触发几次、拿到
  /// 什么上下文"。
  final MaterialRefineHandler _refine;

  MaterialDiscovery({
    DeepSeekSearchClient? searchClient,
    MaterialSourceService? sourceService,
    MaterialRefineHandler? onRefine,
  })  : _injectedClient = searchClient,
        _source = sourceService ?? MaterialSourceService.instance,
        _refine = onRefine ?? defaultMaterialRefine;

  /// 按需求找材料。
  ///
  /// [queries] 来自检索计划(通常由 AI 把中文需求翻成英文检索词;2~3 条最合适,
  /// 这里**全部用上**,不再只取第一条)。
  /// [maxFetch] 控制抓正文的条数 —— 每篇都有时延(1~5s),默认 5 篇 ≈ 10~20s。
  Future<DiscoveryRun> discover({
    required List<String> queries,
    required InputPreferences prefs,
    required LearnerModel model,
    List<Vocabulary> vocab = const [],
    int maxFetch = 5,
    bool usePublicSources = true,
    bool useSearchApi = true,
    /// 用户原始中文需求(补救轮提示词要用它,而不是让模型只看英文 queries 猜);
    /// 不传则退回偏好摘要([InputPreferences.promptHint])。
    String userQuery = '',
    /// 是否允许"两段式补救";默认允许,但只有第一轮候选不足时才真的触发。
    bool enableRefine = true,
    void Function(String label)? onEvent,
  }) async {
    final notes = <String>[];
    final raw = <DiscoveredCandidate>[];
    final seen = <String>{};

    void addAll(Iterable<DiscoveredCandidate> list) {
      for (final c in list) {
        final key = dedupeKeyOf(c.url);
        if (key.isEmpty) continue;
        if (!seen.add(key)) continue;
        // 用户黑名单:标题/来源里出现屏蔽词就整条丢掉(C1-14 的落点)
        if (!prefs.allowsMaterial(
          title: c.title,
          source: c.sourceLabel,
          genres: const [],
        )) {
          continue;
        }
        raw.add(c);
      }
    }

    final plan = queries
        .map((q) => q.trim())
        .where((q) => q.isNotEmpty)
        .toSet()
        .take(3)
        .toList();

    final client = _injectedClient ?? DeepSeekSearchClient();
    final apiAvailable = client.available;
    // 成本口径:计费按"成功请求数"累计,第一轮开始前清零一次;补救轮的
    // 请求自然累加在同一计数里(不做两套账,UI 上就是一个总花费)。
    if (useSearchApi && apiAvailable) client.resetCost();
    var refined = false;
    var refineQueries = const <String>[];

    // 一轮"公开源 + 官方搜索"的检索。抽成闭包是为了让**第一轮与补救轮
    // 共用同一套收集/过滤/去重口径** —— 否则补救轮很容易漏掉黑名单过滤
    // 或重复去重,导致"换关键词后又出现用户屏蔽过的材料"。
    Future<void> collectRound(List<String> roundQueries) async {
      // ① 公开源并发检索(可达性实测过的三个源,零 API 成本)
      if (usePublicSources) {
        for (final q in roundQueries) {
          onEvent?.call('在公开源里检索「$q」…');
          try {
            final result = await OriginalSearch.search(q, category: '其他');
            if (result.notes.isNotEmpty) notes.addAll(result.notes.take(2));
            addAll([
              for (final hit in result.hits)
                DiscoveredCandidate(
                  title: hit.title.trim().isEmpty ? hit.url : hit.title,
                  url: hit.url,
                  sourceLabel:
                      MaterialSourceService.sourceOf(hit.sourceId)?.label ??
                          hit.sourceId,
                  kind: MaterialSourceService.sourceOf(hit.sourceId)?.kind ??
                      'article',
                  snippet: hit.note.trim(),
                  imageUrl: hit.imageUrl,
                ),
            ]);
          } catch (e) {
            notes.add('公开源检索失败:$e');
          }
        }
      }

      // ② DeepSeek 官方搜索(长尾/时效性内容的来源)
      if (useSearchApi && apiAvailable) {
        for (final q in roundQueries.take(2)) {
          onEvent?.call('用 DeepSeek 搜索「$q」…');
          final hits = await client.search(q, count: 5, oriQuestion: q);
          final err = client.lastError;
          if (hits.isEmpty && err != null) notes.add('搜索失败:${err.message}');
          addAll(<DiscoveredCandidate>[
            for (final r in hits)
              DiscoveredCandidate(
                title: r.title.trim().isEmpty ? r.url : r.title,
                url: r.url,
                sourceLabel: r.siteName.trim().isEmpty
                    ? 'DeepSeek 搜索'
                    : 'DeepSeek 搜索 · ${r.siteName}',
                snippet: r.summary.isNotEmpty ? r.summary : r.snippet,
                authority: r.authority,
                date: r.date,
                rerankScore: r.rerankScore,
                fromSearchApi: true,
              ),
          ]);
        }
      }
    }

    // 官方搜索不可用时给一次提示(不在每轮重复刷屏)
    if (useSearchApi && !apiAvailable) {
      notes.add(
        'DeepSeek 官方搜索未配置,本次只用公开源 —— ${client.unavailableReason}',
      );
    }

    await collectRound(plan);

    // ── ③ 两段式补救(批 8 · P2-4)──
    //
    // 只有"第一轮真实候选 < 目标抓取数"才触发 —— 包括:公开源没搜到、
    // 官方搜索没搜到、以及 **allowsMaterial 黑名单过滤后变少** 的情况
    // (过滤发生在 addAll,所以 raw.length 已是过滤后的真实可用数)。
    // 补救最多一轮:绝不递归,避免"模型一直换词、用户一直等"。
    if (enableRefine &&
        needsMaterialRefine(
          candidateCount: raw.length,
          targetCount: maxFetch,
        )) {
      onEvent?.call('换几个关键词再找…');
      final refineInput = MaterialRefineInput(
        userQuery: userQuery.trim().isNotEmpty
            ? userQuery.trim()
            : prefs.promptHint,
        candidates: refineCandidateMaps(raw),
        prefsHint: prefs.promptHint,
      );
      var proposed = const <String>[];
      try {
        proposed = await _refine(refineInput);
      } catch (e) {
        notes.add('换关键词失败:$e');
      }
      final fresh = <String>[];
      for (final q in proposed) {
        final text = q.trim();
        if (text.isEmpty || plan.contains(text) || fresh.contains(text)) {
          continue;
        }
        fresh.add(text);
        if (fresh.length >= 3) break;
      }
      if (fresh.isNotEmpty) {
        onEvent?.call('用新关键词再搜一轮…');
        refineQueries = List<String>.unmodifiable(fresh);
        refined = true;
        await collectRound(fresh);
        notes.add('第一轮候选不足,已用新检索词补搜一轮。');
      }
    }

    final apiRequests = client.requestCount;
    final apiCost = client.estimatedCostCny;

    if (raw.isEmpty) {
      notes.add('这些渠道都没有找到合适的材料。可以换个关键词,或降低/提高难度档再试。');
      return DiscoveryRun(
        items: const [],
        notes: notes,
        searchApiRequests: apiRequests,
        estimatedCostCny: apiCost,
        searchApiAvailable: apiAvailable,
        searchApiUnavailableReason: client.unavailableReason,
        refined: refined,
        refineQueries: refineQueries,
      );
    }

    // ── ③ 选抓取目标:官方搜索优先(有权威度/相关性),再补公开源 ──
    final ordered = List<DiscoveredCandidate>.from(raw)
      ..sort(comparePreFetch);
    final targets = ordered.take(maxFetch.clamp(1, 10)).toList();

    // ── ④ 抓正文 + 本地难度分析(串行:内存/网络都稳,不做并发解码) ──
    final analyzed = <DiscoveredCandidate>[];
    var dropped = 0;
    for (var i = 0; i < targets.length; i++) {
      final c = targets[i];
      onEvent?.call('抓取正文 ${i + 1}/${targets.length}:${c.title}');
      try {
        final text = c.fromSearchApi
            ? await _fetchViaSearchApi(client, c.url)
            : await _fetchViaPublicSource(c);
        if (text == null || text.trim().length < 200) {
          dropped++;
          continue;
        }
        final analysis = await MaterialLibrary.analyze(
          text,
          model: model,
          vocab: vocab,
        );
        analyzed.add(c.copyWith(content: text, analysis: analysis));
      } catch (e) {
        dropped++;
        notes.add('抓取失败:${c.title}($e)');
      }
    }

    // ── ⑤ 排序 + 解释性推荐理由 ──
    final ranked = List<DiscoveredCandidate>.from(analyzed)
      ..sort((a, b) => scoreOf(b, prefs).compareTo(scoreOf(a, prefs)));
    notes.add('有效候选 ${ranked.length} 篇(抓取/分析失败 $dropped 篇)。');
    return DiscoveryRun(
      items: ranked,
      notes: notes,
      searchApiRequests: apiRequests,
      estimatedCostCny: apiCost,
      searchApiAvailable: apiAvailable,
      searchApiUnavailableReason: client.unavailableReason,
      droppedCount: dropped,
      refined: refined,
      refineQueries: refineQueries,
    );
  }

  Future<String?> _fetchViaSearchApi(
    DeepSeekSearchClient client,
    String url,
  ) async {
    final page = await client.fetch(url);
    if (page == null) return null;
    return plainTextFromMarkdown(page.content);
  }

  Future<String?> _fetchViaPublicSource(DiscoveredCandidate c) async {
    final doc = await _source.fetchAnyUrl(c.url, titleHint: c.title);
    final text = doc.chunks.map((chunk) => chunk.text).join('\n\n');
    return text.trim().isEmpty ? null : text;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 纯函数层(可单测;UI 与联调都依赖这里的口径)
// ═══════════════════════════════════════════════════════════════════════

/// 候选去重键:URL 归一(去协议差异/大小写/尾斜杠/常见追踪参数)。
///
/// 为什么不能直接比原串:同一篇文章在 RSS 里是 `http://x/a?id=1`、在搜索结果里
/// 是 `https://x/a/` —— 不去重会同一篇出现两次,用户点开发现是同一篇。
String dedupeKeyOf(String url) {
  var s = url.trim();
  if (s.isEmpty) return '';
  s = s.replaceFirst(RegExp(r'^https?://'), '');
  final hash = s.indexOf('#');
  if (hash >= 0) s = s.substring(0, hash);
  // 追踪参数对"是不是同一篇"没有影响
  s = s.replaceAll(RegExp(r'[?&](utm_[^&]*|ref=[^&]*|source=[^&]*)'), '');
  s = s.replaceAll(RegExp(r'/+$'), '');
  s = s.toLowerCase();
  return s;
}

/// 抓取前排序:官方搜索按"权威度 + 相关性",公开源按可达性优先级。
///
/// 目的只是决定"先抓哪 5 篇",真正的推荐排序在拿到覆盖率后由 [scoreOf] 决定。
int comparePreFetch(DiscoveredCandidate a, DiscoveredCandidate b) {
  if (a.fromSearchApi != b.fromSearchApi) return a.fromSearchApi ? -1 : 1;
  final byAuthority = b.authority.compareTo(a.authority);
  if (byAuthority != 0) return byAuthority;
  final byRerank = b.rerankScore.compareTo(a.rerankScore);
  if (byRerank != 0) return byRerank;
  return 0;
}

/// 推荐打分(越大越靠前)。规则公开、可解释:
/// - 落在用户难度档内:+100;偏易/偏难:-30(不隐藏,只是排后面);
/// - 官方搜索权威度:每级 +6(0~4);
/// - 相关性 rerank:×10(0~3);
/// - 有正文/分析:+20(能给出难度的优先);
/// - 公开源(公版书/外媒)+5(实测可达、无需计费)。
int scoreOf(DiscoveredCandidate c, InputPreferences prefs) {
  var score = 0;
  final coverage = c.coverage;
  if (coverage != null) {
    if (prefs.band.isAny || coverageInBand(coverage, prefs.band)) {
      score += 100;
    } else {
      score -= 30;
    }
    score += 20;
  }
  if (c.fromSearchApi) {
    if (c.authority >= 0) score += c.authority * 6;
    score += (c.rerankScore * 10).round();
  } else {
    score += 5;
  }
  return score;
}

/// 可解释的推荐理由(每条都必须能被数据验证,不许空话)。
///
/// 例:`覆盖率 96% · 符合 i+1 · 约 8 分钟 · 来源 NPR`;
/// 官方搜索还会带 `权威度 3/4`。没抓到正文时明确写"未抓正文",不假装有难度。
String reasonOf(DiscoveredCandidate c, InputPreferences prefs) {
  final parts = <String>[];
  final analysis = c.analysis;
  if (analysis != null) {
    final pct = (analysis.knownTokenRatio * 100).round();
    parts.add('覆盖率 $pct%');
    final fit = prefs.band.isAny
        ? ''
        : prefs.band.materialBand.fitLabel(analysis.knownTokenRatio);
    if (fit.isNotEmpty) parts.add(fit);
    if (analysis.estMinutes > 0) parts.add('约 ${analysis.estMinutes} 分钟');
    if (analysis.cefr.isNotEmpty) parts.add(analysis.cefr);
  } else {
    parts.add('未抓正文');
  }
  if (c.fromSearchApi && c.authority >= 0) {
    parts.add('权威度 ${c.authority}/4');
  }
  parts.add('来源 ${c.sourceLabel}');
  return parts.join(' · ');
}

/// 从 Markdown 里抽纯文本(给难度分析用)。
///
/// 官方 Fetch 返回 Markdown;直接拿 `##`/`**`/链接去算覆盖率会把符号算成生词。
/// 只做保守清理:去标题井号、强调符号、链接只留文字、图片/代码块整行丢。
String plainTextFromMarkdown(String markdown) {
  final out = <String>[];
  // 代码块状态:``` 之间的内容不是正文(旧实现只跳过 ``` 行本身,
  // 块内的 `void main()` 会被当成"生词密度"算进难度分析)。
  var inFence = false;
  for (final rawLine in markdown.replaceAll('\r\n', '\n').split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    if (line.isEmpty) continue;
    if (line.startsWith('![')) continue;
    if (RegExp(r'^[-*_]{3,}$').hasMatch(line)) continue;
    if (RegExp(r'^\|').hasMatch(line)) continue; // 表格行不是正文
    var t = line.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    t = t.replaceFirst(RegExp(r'^>\s*'), '');
    t = t.replaceFirst(RegExp(r'^[-*+]\s+'), '');
    t = t.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]*\)'),
      (m) => m.group(1) ?? '',
    );
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    t = t.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length >= 2) out.add(t);
  }
  return out.join('\n\n');
}

// ═══════════════════════════════════════════════════════════════════════
// 两段式补救(批 8 · P2-4):第一轮候选不足 → 模型换检索词 → 再搜一轮
// ═══════════════════════════════════════════════════════════════════════
//
// 为什么需要"模型换词"而不是简单重搜:第一轮用的是 AI 一开始给的 2~3 条
// 英文 query。如果候选不够,通常不是"源坏了",而是 query 太泛/方向偏了
// (例如用户要"最近的 AI 芯片报道",query 却是 "AI"),再原样重搜一遍只会
// 得到同样的结果。把**真实候选**交给模型,它才能看出"缺的是时效性/某类
// 题材",从而换出更准的检索词。
//
// 边界(与整个发现流水线一致):模型**只准给检索词**,不准"回忆"资源;
// 资源必须由真实检索系统返回(无 url 照样丢弃)。这样即使模型想编也编不出
// 一张卡片 —— 它没有产出 url 的通道。

/// 一次补救轮的输入:用户需求 + 第一轮真实候选(只喂必要字段,省 token)。
class MaterialRefineInput {
  /// 用户原始中文需求(空串时调用方会退回偏好摘要)
  final String userQuery;

  /// 第一轮真实候选(每项含 title/url/site/date/authority/snippet)
  final List<Map<String, Object?>> candidates;

  /// 用户偏好摘要(目标/难度/题材;没有 = 空串)
  final String prefsHint;

  const MaterialRefineInput({
    required this.userQuery,
    required this.candidates,
    this.prefsHint = '',
  });
}

/// 补救轮"换关键词"的执行者。生产默认为 [defaultMaterialRefine](调模型);
/// 测试注入假实现,验证触发时机与上下文,不联网不花 token。
typedef MaterialRefineHandler = Future<List<String>> Function(
  MaterialRefineInput input,
);

/// 第一轮候选是否不足,需要补救(纯函数,可单测)。
///
/// [candidateCount] 必须是**黑名单过滤之后**的真实可用候选数(发现流水线里
/// `raw.length` 就是);[targetCount] 是目标抓取数(通常是 maxFetch)。
/// target <= 0 表示调用方没给目标 → 不触发,避免"任何输入都补救"。
bool needsMaterialRefine({
  required int candidateCount,
  required int targetCount,
}) {
  if (targetCount <= 0) return false;
  return candidateCount < targetCount;
}

/// 把候选转成"喂模型的精简 JSON 数组"(纯函数,可单测)。
///
/// 只给模型判断方向所需的字段;url 带上是为了让它知道"哪些出处已经有了",
/// 但提示词明确禁止它复制/编造 url。
List<Map<String, Object?>> refineCandidateMaps(
  Iterable<DiscoveredCandidate> candidates, {
  int limit = 8,
}) {
  final out = <Map<String, Object?>>[];
  for (final c in candidates) {
    if (out.length >= limit) break;
    out.add(<String, Object?>{
      'title': c.title,
      'url': c.url,
      'site': c.sourceLabel,
      'date': c.date == null
          ? ''
          : c.date!.toIso8601String().substring(0, 10),
      'authority': c.authority,
      'snippet': c.snippet,
    });
  }
  return out;
}

/// 丢掉没有 url 的候选(纯函数,可单测)。
///
/// 整个流水线的铁律:没有 url 就不是"可验证的真实材料",不能进卡片。
/// 补救轮同样适用 —— 即使未来模型能直接返回资源候选,也先过这道闸。
List<DiscoveredCandidate> dropCandidatesWithoutUrl(
  Iterable<DiscoveredCandidate> candidates,
) {
  return <DiscoveredCandidate>[
    for (final c in candidates)
      if (dedupeKeyOf(c.url).isNotEmpty) c,
  ];
}

/// 构建"换检索词"提示词(纯函数,可单测)。
///
/// 纪律写死在三处:①只输出 JSON;②只准给检索词,不准编资源/链接;
/// ③候选足够时返回空数组(不为了"显得有用"硬凑一堆词)。
({String system, String user}) buildRefinePrompt({
  required String userQuery,
  required List<Map<String, Object?>> candidates,
  String prefsHint = '',
}) {
  const system = '''你是英语学习材料的检索助手。用户第一轮检索没有找到足够材料,
请帮他换更准的英文检索词。返回 JSON:{"queries":["英文检索词1","英文检索词2"]}

规则:
1. 只输出 3 条以内的**英文**检索关键词,越具体越好(如 "stoicism meditations aurelius",
   而不是 "philosophy");不要输出解释、不要编号列表之外的文字;
2. 只能基于"用户需求 + 下面给出的真实候选"调整检索词:从候选的题材/标题/日期里
   判断缺什么方向,或补足第一轮没覆盖的方向;
3. **不要编造资源**:不要返回作者、书名、链接或 URL —— 你只负责给检索词,
   真实资源由检索系统去找;
4. 如果候选里已经有足够的方向,返回 {"queries":[]}(空数组);
5. 只输出 JSON。''';

  final buf = StringBuffer()
    ..writeln('用户需求:${userQuery.trim().isEmpty ? '(未提供,按偏好判断)' : userQuery.trim()}');
  final prefs = prefsHint.trim();
  if (prefs.isNotEmpty) buf.writeln('用户偏好:$prefs');
  buf.writeln('第一轮找到的真实候选(只用于判断"缺什么方向";不要复制它们的链接):');
  if (candidates.isEmpty) {
    buf.writeln('- (第一轮没有返回任何候选)');
  } else {
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      buf.writeln(
        '${i + 1}. title=${c['title'] ?? ''} | url=${c['url'] ?? ''} '
        '| site=${c['site'] ?? ''} | date=${c['date'] ?? ''} '
        '| authority=${c['authority'] ?? -1} | snippet=${c['snippet'] ?? ''}',
      );
    }
  }
  buf.writeln('请给出更可能搜到有效材料的英文检索词(JSON)。');
  return (system: system, user: buf.toString());
}

/// 解析模型返回的检索词(纯函数,可单测;容错优先)。
///
/// 兼容:标准 `{"queries":[...]}`、裸数组 `[...]`、`{"queries":"a, b"}`、
/// ```json 围栏/前置说明;模型偶尔"不听话"直接给行文本时按行兜底。
/// 过滤:去编号/引号/空串/非英文行(检索系统只认英文),去重,最多 3 条。
List<String> parseRefineQueries(String content) {
  final text = content.trim();
  if (text.isEmpty) return const <String>[];

  final jsonStr = DoubaoApiService.extractJsonBlock(text);
  Object? decoded;
  if (jsonStr.isNotEmpty) {
    try {
      decoded = jsonDecode(jsonStr);
    } catch (_) {
      decoded = null;
    }
  }
  final raw = <Object?>[];
  if (decoded is List) {
    raw.addAll(decoded);
  } else if (decoded is Map) {
    final q = decoded['queries'] ??
        decoded['search_queries'] ??
        decoded['keywords'];
    if (q is List) {
      raw.addAll(q);
    } else if (q is String) {
      raw.addAll(q.split(RegExp(r'[,，、\n]')));
    }
  }
  if (raw.isEmpty) {
    raw.addAll(text.split(RegExp(r'[\n,，、]+')));
  }

  final out = <String>[];
  for (final item in raw) {
    var s = '$item'.trim();
    s = s.replaceAll(RegExp(r'^[-*\d.)、\s]+'), '').trim();
    s = s.replaceAll(RegExp(r'''^[`"']+|[`"']+$'''), '').trim();
    if (s.isEmpty || s.length > 120) continue;
    // 非英文行(中文说明/JSON 残片)不是检索词
    if (!RegExp(r'[A-Za-z]').hasMatch(s)) continue;
    if (s.startsWith('{') || s.startsWith('[')) continue;
    if (out.contains(s)) continue;
    out.add(s);
    if (out.length >= 3) break;
  }
  return out;
}

/// 生产默认的补救实现:用 JSON mode + 轻思考让模型换检索词。
///
/// 失败/未配置/解析不出 → 空列表(调用方按"没补救成功"处理,不中断主流程)。
Future<List<String>> defaultMaterialRefine(MaterialRefineInput input) async {
  final prompt = buildRefinePrompt(
    userQuery: input.userQuery,
    candidates: input.candidates,
    prefsHint: input.prefsHint,
  );
  final content = await DeepseekApiService().completeJson(
    system: prompt.system,
    user: prompt.user,
    maxTokens: 1024,
    temperature: 0.3,
    // 换检索词和"检索计划"同类:输出短、要快 → 任务级轻思考
    thinkingLevel: BaseApiService.thinkingForTask('plan'),
  );
  if (content == null) return const <String>[];
  return parseRefineQueries(content);
}
