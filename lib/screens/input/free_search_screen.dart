import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../models/vocabulary.dart';
import '../../providers/vocab_provider.dart';
import '../../services/find_need_context.dart';
import '../../services/input_prefs.dart';
import '../../services/material_ai_rewrite.dart';
import '../../services/search_query_planner.dart';
import '../../widgets/ai_rewrite_options_sheet.dart';
import '../../services/material_channel.dart';
import '../../services/material_library.dart';
import '../../services/material_need.dart';
import '../../services/material_prefs.dart';
import '../../services/material_source.dart';
import '../../services/material_taxonomy.dart';
import '../../services/original_search.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/material_result_list.dart';
import '../../widgets/search_timeline.dart';
import 'material_reader_screen.dart';

/// 一次自由搜的执行结果(生产 = `OriginalSearch` 的真实返回;测试可注入)。
///
/// 为什么不只返回结果列表:用户 2026-11-07 真机反馈第 4 条要求"没找到原文时
/// 说清为什么没找到",这需要**过滤前**的真实信息(命中几条、筛掉了多少、
/// 每个源给了什么说明);同时 AI 改写保底只能基于真实搜到的线索
/// ([sources]),不能凭空编。所以一次检索把这三样一起带回来。
class FreeSearchRun {
  /// 按用户筛选条件过滤后、真正要展示的结果
  final List<MaterialResultItem> items;

  /// 过滤前的全部真实线索(AI 改写 / "为什么没找到"诊断用)
  final List<AiRewriteSource> sources;

  /// 过滤前的原始命中条数(用户可核对)
  final int rawHits;

  /// 这次检索了哪些源(展示名,真实)
  final List<String> searchedSourceLabels;

  /// 源自己给的真实说明(不可达/只认英文/没有匹配…)
  final List<String> notes;

  const FreeSearchRun({
    required this.items,
    this.sources = const <AiRewriteSource>[],
    this.rawHits = 0,
    this.searchedSourceLabels = const <String>[],
    this.notes = const <String>[],
  });
}

/// 自由搜执行器(**仅测试/渲染注入**;生产走 `OriginalSearch` 真实公开源)。
typedef FreeSearchRunner = Future<FreeSearchRun> Function({
  required String query,
  required String kind,
  required String band,
  required Set<String> sourceIds,
});

/// 「找材料 · 自由搜」独立搜索页(用户选型 A 方案的左路)。
///
/// 能力全部是真实可落地的:
/// - **关键词**:回车即搜;空关键词用"推荐检索词"(不弹空白页);
/// - **来源**:`MaterialSourceService.sources` 的 9 个真实公开源
///   (`material_source.dart`),可多选收窄;「实测可用」的源给标记;
/// - **类型**:5 类(书籍 / 论文 / 外刊新闻 / 播客 / 百科),与 `MaterialSource.kind`
///   对齐并映射到真实来源(`gutenberg` / `arxiv` / `npr`系 / `bbc_le`·`voa_le`·`ted` /
///   `wikipedia`);百科因为维基源没有关键词检索接口,走"随机条目池 + 本地关键词筛"
///   的如实降级(见 `_wikiRun`);
/// - **难度**:按 `MaterialLibrary.estimateDifficulty` 的**来源级预计区间**过滤 ——
///   文案明说"非精确覆盖率",没抓正文**不标真实难度**(设计 §3.3 的硬规则);
/// - **场景**:`MaterialTaxonomy.scene` 的真实检索词预设(点了填入搜索框)——
///   公开源没有"场景"元数据,所以它是检索词预设,不是假过滤器。
///
/// 筛选区(2026-11-07 用户真机反馈第 4 条):**默认收起**成一行
/// 「筛选(n) + 已选条件摘要」;点开是可滚动面板,再点收起;搜索开始/结束自动收起。
///
/// 结果走与频道页共用的 [MaterialResultList](分组 / 每页 10 条 / 页码控件 /
/// 有真封面才显示 / 开始读·保存到我的·打开原文 / 切页回顶),快照按
/// `free:<归一关键词>` 复用 [MaterialChannelStore]。
///
/// **AI 改写保底**(用户真机反馈第 4 条):结果 0 条 / 抓不到正文时,不说空话,
/// 而是:①用真实检索信息说明"为什么没找到";②给出「AI 改写学习版(非原文)」
/// 入口 —— 基于这次搜到的标题/摘要/来源改写一篇可读材料(标注非原文、来源、
/// 真实字数/难度,可读可存)。有原文时原文优先,AI 版只是明确分隔的可选兜底。
class FreeSearchScreen extends StatefulWidget {
  /// 从入口卡/历史 chips 带进来的关键词(可空 = 空态)
  final String? initialQuery;

  /// **仅渲染测试用**:直接给结果,跳过网络(生产永不传)
  final List<MaterialResultItem>? initialResults;

  /// **仅渲染测试用**:给结果时顺带展示"搜索过程"卡
  final List<SearchEvent>? initialEvents;

  /// **仅渲染/测试用**:给"没找到"诊断 + AI 改写用的真实线索形状
  /// (生产永不传:真实线索来自检索返回)
  final List<AiRewriteSource>? debugSources;

  /// **仅渲染/测试用**:给"为什么没找到"的源说明(生产来自检索返回)
  final List<String>? debugNotes;

  /// **仅渲染/测试用**:注入 AI 改写器(默认真调模型)
  final MaterialAiRewriter? aiRewriter;

  /// **仅渲染/测试用**:绕过真实公开源检索(网络)直接给一次运行结果
  final FreeSearchRunner? debugRun;

  /// **仅测试用**:注入检索词规划器(默认 DeepSeek)
  final SearchQueryPlanner? queryPlanner;

  const FreeSearchScreen({
    super.key,
    this.initialQuery,
    this.initialResults,
    this.initialEvents,
    this.debugSources,
    this.debugNotes,
    this.aiRewriter,
    this.debugRun,
    this.queryPlanner,
  });

  @override
  State<FreeSearchScreen> createState() => _FreeSearchScreenState();
}

class _FreeSearchScreenState extends State<FreeSearchScreen> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();

  InputPreferences _prefs = InputPreferences();
  late MaterialResultController _controller;

  /// 选中的来源 id(空 = 全部)
  final Set<String> _sources = <String>{};

  /// 类型筛选:'book' / 'paper' / 'news' / 'podcast' / 'wiki' / 空(=不限)
  String _kind = '';

  /// 最近一次检索词规划（用于 AI 改写时告诉模型「是哪本书/哪个主题」）
  SearchQueryPlan _lastPlan = SearchQueryPlan.raw('');

  /// 难度筛选:'' = 不限;否则是 `MaterialLibrary.difficultyBands` 里的区间
  String _band = '';

  /// 场景预设 id(空 = 没选)
  String _scene = '';

  bool _running = false;
  bool _showProcess = false;
  bool _searchedThisSession = false;
  String? _error;
  List<String> _notes = const <String>[];
  final List<SearchEvent> _events = <SearchEvent>[];

  /// 筛选面板是否展开(2026-11-07:默认收起)
  bool _filtersOpen = false;

  /// 这次会话真的跑过一轮检索(决定"为什么没找到"能不能引用真实命中数)
  bool _ranOnce = false;

  // ── 真实检索诊断("为什么没找到"用,全部来自这一轮检索)──
  int _rawHits = 0;
  List<String> _searchedSources = const <String>[];
  List<AiRewriteSource> _lastSources = const <AiRewriteSource>[];

  /// 「开始读」时抓不到正文的真实篇数(决定 AI 兜底是否需要提示)
  int _contentFailCount = 0;

  // ── AI 改写保底(非原文)──
  AiRewrittenMaterial? _aiMaterial;
  bool _aiRunning = false;
  bool _aiBusy = false;
  bool _aiSaved = false;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    try {
      _prefs = InputPreferences.load();
    } catch (_) {
      _prefs = InputPreferences();
    }
    final query = (widget.initialQuery ?? '').trim();
    if (query.isNotEmpty) _query.text = query;
    _query.addListener(_onQueryChanged);
    _controller = MaterialResultController(
      storeId: 'free:${_storeKey(query)}',
      readerBuilder: (materialId) =>
          MaterialReaderScreen(materialId: materialId),
    );
    _controller.addListener(_onController);
    if (widget.initialResults != null) {
      _controller.items.addAll(widget.initialResults!);
      _searchedThisSession = true;
      _ranOnce = widget.debugSources != null || widget.initialResults!.isNotEmpty;
      if (widget.debugSources != null) {
        _lastSources = List<AiRewriteSource>.of(widget.debugSources!);
        _rawHits = widget.debugSources!.length;
      }
      _notes = widget.debugNotes ?? const <String>[];
      if (widget.initialEvents != null) {
        _events.addAll(widget.initialEvents!);
        _showProcess = true;
      }
      return;
    }
    // 2026-11-08 用户反馈：进页自动恢复旧快照会让「上次的 NPR 新闻」看起来像本次结果；
    // 自由搜只展示本次搜索的结果（历史记录仍可在入口页「历史」里看）。
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _controller.dispose();
    _scroll.dispose();
    _query.removeListener(_onQueryChanged);
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (mounted) setState(() {});
  }

  void _onController() {
    if (mounted) setState(() {});
  }


  // ── 搜索 ────────────────────────────────────────────────────────────

  Future<void> _runSearch({bool broaden = false}) async {
    if (_running) return;
    var query = _query.text.trim();
    if (query.isEmpty) {
      query = _recommendedQuery();
      _query.text = query;
      _snack('没填关键词,先用推荐检索词:$query');
    }
    // 关键词变了 → 换一个快照身份(`free:<归一关键词>`)
    final storeId = 'free:${_storeKey(query)}';
    if (!broaden && storeId != _controller.storeId) {
      _controller.removeListener(_onController);
      _controller.dispose();
      _controller = MaterialResultController(
        storeId: storeId,
        readerBuilder: (materialId) =>
            MaterialReaderScreen(materialId: materialId),
      );
      _controller.addListener(_onController);
    }
    setState(() {
      _running = true;
      _showProcess = true;
      _error = null;
      _events.clear();
      // 用户第 4 条:搜索一开始就收起筛选,结果出来也不弹回
      _filtersOpen = false;
      _aiError = null;
      if (!broaden) {
        _notes = const <String>[];
        _aiMaterial = null;
        _aiSaved = false;
        _contentFailCount = 0;
      }
    });
    try {
      final run = await _executeSearch(query, broaden: broaden);
      if (!mounted) return;
      final saved = await _controller.applyRun(
        fresh: run.items,
        queriesUsed: <String>[query],
        runApiRequests: 0,
        runCostCny: 0,
        runNotes: run.notes,
        append: broaden,
      );
      await FindSearchHistory.remember(query);
      if (!mounted) return;
      setState(() {
        _running = false;
        _showProcess = false;
        _searchedThisSession = true;
        _ranOnce = true;
        _notes = List<String>.of(run.notes);
        _rawHits = broaden ? _rawHits + run.rawHits : run.rawHits;
        _searchedSources = run.searchedSourceLabels;
        _lastSources = broaden
            ? _mergeSources(_lastSources, run.sources)
            : run.sources;
        _filtersOpen = false; // 结果出来后筛选区保持收起
      });
      _scrollToTop();
      if (run.items.isEmpty && !saved) {
        _snack('结果没存上快照,下次进来可能看不到(本地存储写入失败)。');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _showProcess = false;
        _error = '$e';
      });
    }
  }

  /// 执行一次检索(生产:公开源 / 维基降级;测试:注入的运行结果)。
  Future<FreeSearchRun> _executeSearch(
    String query, {
    bool broaden = false,
  }) async {
    final debug = widget.debugRun;
    if (debug != null) {
      final run = await debug(
        query: query,
        kind: _kind,
        band: _band,
        sourceIds: Set<String>.of(_sources),
      );
      _event(
        run.items.isEmpty
            ? '没有匹配的结果 —— 下面是这次检索的真实情况'
            : '找到 ${run.items.length} 篇原文',
        stage: run.items.isEmpty ? SearchStage.sourceEmpty : SearchStage.done,
      );
      return run;
    }
    // 「百科」单独走:维基源在 OriginalSearch 链路里没有关键词检索接口,
    // 只能从**真实随机条目池**(listItems)拉一批再本地按关键词筛 ——
    // 这是能力边界,结果页文案会明说,不假装它和别的类型一样能搜。
    // 2026-11-08 用户要求：搜中文书名/译名时，AI 先判断原版英文名再检索
    //（例：《原子习惯》→ Atomic Habits）。规划失败退回原词，不阻塞搜索。
    final planner = widget.queryPlanner ?? SearchQueryPlanner();
    SearchQueryPlan plan = SearchQueryPlan.raw(query);
    try {
      plan = await planner.plan(query);
    } catch (_) {
      plan = SearchQueryPlan.raw(query);
    }
    final searchQuery = plan.primaryQuery;
    _lastPlan = plan;
    if (plan.changed) {
      _event(
        '已按「$searchQuery」检索'
        '${plan.reason.isEmpty ? '' : '（${plan.reason}）'}',
      );
    }
    // 用户没手动选类型时，按 AI 判断的类型收窄来源：
    // 书 → 只搜书籍源（不要在 arXiv 里把 "atomic" 当物理原子搜出论文）。
    final plannedKind = const <String>{'book', 'paper', 'news', 'podcast'}.contains(plan.kind)
        ? plan.kind
        : '';
    final effectiveKind = _kind.isNotEmpty ? _kind : plannedKind;
    if (effectiveKind == 'wiki' || (_kind == 'wiki' && plan.kind.isEmpty)) {
      return _wikiRun(searchQuery);
    }
    final category = _categoryOf(effectiveKind);
    final requested = broaden ? null : _selectedSourceIds(effectiveKind);
    final searchedIds = requested ?? OriginalSearch.sourcesForCategory(category);
    final searchedLabels = <String>[
      for (final id in searchedIds)
        _shortSourceLabelOf(id),
    ];
    // 相关性口径：能给原版书名时，要求**标题里出现书名/主题词**（比只命中摘要里的
    // 一个通用词严格得多），避免"沾边关键词但内容毫无关系"。
    var irrelevant = 0;
    final fresh = <MaterialResultItem>[];
    final sources = <AiRewriteSource>[];
    final notes = <String>[];
    final seenUrls = <String>{};
    var rawHits = 0;
    var seq = _controller.items.length;

    Future<void> runPass(String passQuery) async {
      final result = await OriginalSearch.search(
        passQuery,
        category: category,
        sourceIds: requested,
        onProgress: _onProgress,
      );
      rawHits += result.hits.length;
      notes.addAll(result.notes);
      for (final hit in result.hits) {
        if (!seenUrls.add(hit.url)) continue;
        final source = MaterialSourceService.sourceOf(hit.sourceId);
        final kind = inferMaterialKind(
          hit.title,
          hit.url,
          fallback: source?.kind ?? 'article',
        );
        // 过滤前的线索全部留下：AI 改写只能用真实搜到的东西
        sources.add(
          AiRewriteSource(
            title: hit.title.trim().isEmpty ? hit.url : hit.title.trim(),
            url: hit.url,
            site: source?.label ?? hit.sourceId,
            snippet: hit.note,
            kind: kind,
          ),
        );
        final haystack = '${hit.title} ${hit.note}';
        if (!_strictMatches(haystack, searchQuery)) {
          irrelevant++;
          continue;
        }
        final estimate = MaterialLibrary.estimateDifficulty(
          sourceId: hit.sourceId,
          kind: kind,
        );
        if (!_bandMatches(estimate.band)) continue;
        // 黑名单(题材/关键词)与材料推荐口径一致:命中就不展示
        if (!_prefs.allowsMaterial(
          title: hit.title,
          source: source?.label ?? '',
          genres: const <String>[],
        )) {
          continue;
        }
        fresh.add(
          MaterialResultItem(
            title: hit.title.trim().isEmpty ? hit.url : hit.title.trim(),
            url: hit.url,
            sourceLabel: source?.label ?? hit.sourceId,
            kind: kind,
            snippet: hit.note,
            imageUrl: hit.imageUrl,
            sourceId: hit.sourceId,
            estimateLabel: estimate.label,
            estimateBasis: estimate.basis,
            seq: seq++,
          ),
        );
      }
    }

    await runPass(searchQuery);
    // 用户 2026-11-08：原版搜不到时，应该去找**这本书/这篇材料的二手解析、
    // 书评、读后感**（真实存在的文章），而不是拿沾边关键词凑数。
    if (fresh.length < 2) {
      List<String> extra = const <String>[];
      try {
        extra = await planner.planQueries(
          '用户想找《${plan.original}》（原版名可能是 "${searchQuery}"）的英文二手材料：'
          '书评 book review、内容解析 summary/analysis、读后感 discussion/essay、'
          '作者观点解读。请给出 2 条英文检索词，必须包含书名或核心主题词。',
          max: 2,
        );
      } catch (_) {
        // AI 规划失败也要兜底试一把
      }
      if (extra.isEmpty && plan.changed) {
        extra = <String>[
          '"$searchQuery" book review',
          '"$searchQuery" summary analysis',
        ];
      }
      for (final extraQuery in extra) {
        _event('原版没找到，补搜相关解读:$extraQuery');
        await runPass(extraQuery);
        if (fresh.length >= 4) break;
      }
      if (fresh.isNotEmpty) {
        notes.add('原版没找到，已补搜「书评 / 解析 / 读后感」类相关文章 ${fresh.length} 条。');
      }
    }

    _event(
      fresh.isEmpty
          ? '没有匹配的结果 —— 换个关键词,或放宽来源/难度'
          : '找到 ${fresh.length} 篇相关材料',
      stage: fresh.isEmpty ? SearchStage.sourceEmpty : SearchStage.done,
    );
    return FreeSearchRun(
      items: fresh,
      sources: sources,
      rawHits: rawHits,
      searchedSourceLabels: searchedLabels,
      notes: <String>[
        ...notes,
        if (irrelevant > 0) '已丢弃 $irrelevant 条与书名/关键词无关的结果。',
      ],
    );
  }

  /// 严格相关性（2026-11-08 用户要求"别拿沾边关键词凑数"）：
  /// - 英文：先看完整短语是否出现；否则要求**多数实词**都出现（≤2 个词时必须全部出现）；
  /// - 中文：至少出现一个 2 字子串。
  static bool _strictMatches(String haystack, String query) {
    final hay = haystack.toLowerCase();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (hay.contains(q)) return true;
    // 中文查询：2 字子串命中即可
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(q)) {
      for (var i = 0; i + 2 <= q.length; i++) {
        final t = q.substring(i, i + 2);
        if (RegExp(r'[\u4e00-\u9fff]{2}').hasMatch(t) && hay.contains(t)) {
          return true;
        }
      }
      return false;
    }
    const stop = <String>{
      'the', 'and', 'for', 'with', 'from', 'that', 'this', 'how', 'why',
      'what', 'your', 'you', 'are', 'was', 'were', 'has', 'have', 'about',
      'into', 'book', 'books', 'article', 'articles', 'english',
    };
    final words = <String>[
      for (final m in RegExp(r"[a-z][a-z'’\-]{2,}").allMatches(q))
        if (!stop.contains(m.group(0)!)) m.group(0)!,
    ];
    if (words.isEmpty) return true;
    var hits = 0;
    for (final w in words) {
      if (hay.contains(w)) hits++;
    }
    return hits >= (words.length <= 2 ? words.length : (words.length * 0.66).ceil());
  }

  /// 关键词/原版检索词 → 相关性令牌（中文 2 字子串；英文 ≥3 字母词）。
  static List<String> _relevanceTokens(String text) {
    final out = <String>[];
    final seen = <String>{};
    final lower = text.toLowerCase();
    for (final match in RegExp(r'[a-z0-9]{3,}').allMatches(lower)) {
      final token = match.group(0)!;
      if (seen.add(token)) out.add(token);
    }
    for (final match in RegExp(r'[\u4e00-\u9fff]{2,}').allMatches(text)) {
      final cn = match.group(0)!;
      for (var i = 0; i + 2 <= cn.length; i++) {
        final token = cn.substring(i, i + 2);
        if (seen.add(token)) out.add(token);
      }
    }
    return out;
  }

  static bool _hitMatchesTokens(String haystack, List<String> tokens) {
    if (tokens.isEmpty) return true;
    final hay = haystack.toLowerCase();
    for (final token in tokens) {
      if (hay.contains(token)) return true;
    }
    return false;
  }

  /// 百科类型的真实候选:拉维基的随机条目池,再按关键词本地筛。
  ///
  /// 为什么不做成"假检索":`OriginalSearch` 只对 Gutenberg/arXiv/RSS 三类有检索
  /// 接口,Wikipedia 只有"随机条目"能力;硬造一个搜索框会变成"点了没反应"。
  /// 所以这里如实:随机池 → 本地关键词筛 → 命中几条报几条。
  Future<FreeSearchRun> _wikiRun(String query) async {
    final feed = await MaterialSourceService.instance.listItems(
      'wikipedia',
      limit: 10,
    );
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 3)
        .toList();
    final estimate = MaterialLibrary.estimateDifficulty(
      sourceId: 'wikipedia',
      kind: 'wiki',
    );
    final fresh = <MaterialResultItem>[];
    final sources = <AiRewriteSource>[];
    var seq = _controller.items.length;
    for (final item in feed) {
      sources.add(
        AiRewriteSource(
          title: item.title,
          url: item.link,
          site: 'Wikipedia(维基百科)',
          snippet: item.summary,
          kind: 'wiki',
        ),
      );
      final hay = '${item.title} ${item.summary}'.toLowerCase();
      if (tokens.isNotEmpty && !tokens.any(hay.contains)) continue;
      if (!_prefs.allowsMaterial(
        title: item.title,
        source: 'Wikipedia(维基百科)',
        genres: const <String>[],
      )) {
        continue;
      }
      fresh.add(
        MaterialResultItem(
          title: item.title.trim().isEmpty ? item.link : item.title.trim(),
          url: item.link,
          sourceLabel: 'Wikipedia(维基百科)',
          kind: 'wiki',
          snippet: item.summary,
          imageUrl: item.imageUrl,
          sourceId: 'wikipedia',
          estimateLabel: estimate.label,
          estimateBasis: estimate.basis,
          seq: seq++,
        ),
      );
    }
    final note = '维基百科源没有关键词检索接口:这次从随机条目池里筛出 '
        '${fresh.length} 条匹配。';
    _event(
      fresh.isEmpty ? note : '找到 ${fresh.length} 篇维基条目',
      stage: fresh.isEmpty ? SearchStage.sourceEmpty : SearchStage.done,
    );
    return FreeSearchRun(
      items: fresh,
      sources: sources,
      rawHits: feed.length,
      searchedSourceLabels: const <String>['Wikipedia(维基百科)'],
      notes: <String>[note],
    );
  }

  List<AiRewriteSource> _mergeSources(
    List<AiRewriteSource> old,
    List<AiRewriteSource> fresh,
  ) {
    final out = <AiRewriteSource>[];
    final seen = <String>{};
    for (final source in <AiRewriteSource>[...old, ...fresh]) {
      final key = source.url.trim().isEmpty ? source.title.trim() : source.url.trim();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(source);
    }
    return out;
  }

  /// 检索进度(OriginalSearch 每完成一个源回调一次)
  void _onProgress(SearchEvent event) {
    if (!mounted) return;
    setState(() => _events.add(event));
  }

  void _event(String label, {SearchStage stage = SearchStage.searching}) {
    if (!mounted) return;
    setState(
      () => _events.add(SearchEvent(stage: stage, label: label)),
    );
  }

  String _recommendedQuery() {
    try {
      final scene = _sceneDef();
      if (scene != null && scene.queries.isNotEmpty) return scene.queries.first;
      final fallback = OriginalSearch.defaultQueryFor(_categoryOf(_kind));
      if (fallback.trim().isNotEmpty) return fallback;
    } catch (_) {
      // 读 taxonomy 失败就退到通用词
    }
    return 'english reading';
  }

  MaterialSubtopic? _sceneDef() {
    if (_scene.isEmpty) return null;
    for (final sub in MaterialTaxonomy.scene.subtopics) {
      if (sub.id == _scene) return sub;
    }
    return null;
  }

  /// 类型 → `OriginalSearch` 的分类(它按分类决定去哪些源检索)
  ///
  /// 5 类与 `MaterialSource.kind` 对齐:book / paper / news / podcast / wiki
  /// (设计 §3.3 的五类)。wiki 不在这条公开源检索链路上(见 `_wikiRun`),
  /// 所以只在"不限类型"里随其他源出现,单独选「百科」走随机条目池筛选。
  String _categoryOf(String kind) => switch (kind) {
        'book' => '书籍',
        'paper' => '论文',
        'news' => '外刊',
        'podcast' => '外刊',
        _ => '其他',
      };

  /// 类型 → 该类型的**真实来源 id**(来自 `MaterialSourceService.sources` 的 kind)
  ///
  /// 用户没手动选来源时,按类型收窄到对应源;手动选了来源则以手动为准
  /// (两者在 `OriginalSearch` 内部按"分类源 ∩ 指定源"取交集)。
  List<String>? _selectedSourceIds([String? kindOverride]) {
    if (_sources.isNotEmpty) return _sources.toList();
    final kind = kindOverride ?? _kind;
    final matchedKind = switch (kind) {
      'book' => 'book',
      'paper' => 'paper',
      'news' => 'news',
      'podcast' => 'podcast',
      _ => '',
    };
    if (matchedKind.isEmpty) return null;
    final ids = <String>[
      for (final source in MaterialSourceService.sources)
        if (source.kind == matchedKind) source.id,
    ];
    return ids.isEmpty ? null : ids;
  }

  bool _bandMatches(String band) => _band.isEmpty || band == _band;

  String _storeKey(String query) {
    final text = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return 'default';
    // Hive key 里避免超长/怪字符:只留字母数字与少量分隔
    return text.replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff+ _-]'), '');
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(0);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _read(MaterialResultItem item) async {
    final message = await _controller.read(context, item);
    if (message != null) {
      _snack(message);
      if (item.contentUnavailable && mounted) {
        setState(() => _contentFailCount++);
      }
    }
  }

  Future<void> _save(MaterialResultItem item) async {
    final message = await _controller.save(context, item);
    if (message != null) _snack(message);
  }

  Future<void> _openOriginal(MaterialResultItem item) async {
    final message = await _controller.openOriginal(item);
    if (message != null) _snack(message);
  }

  // ── AI 改写保底(非原文)────────────────────────────────────────────

  /// AI 改写可用的真实线索:优先用这次检索的**过滤前**线索(比结果多、更全),
  /// 没有(例如从快照恢复)就退回结果卡上的真实字段。
  List<AiRewriteSource> _aiSources() {
    final out = <AiRewriteSource>[];
    final seen = <String>{};
    void add(AiRewriteSource source) {
      final key =
          source.url.trim().isEmpty ? source.title.trim() : source.url.trim();
      if (key.isEmpty || !seen.add(key)) return;
      out.add(source);
    }

    for (final source in _lastSources) {
      add(source);
    }
    for (final item in _controller.items) {
      add(
        AiRewriteSource(
          title: item.title,
          url: item.url,
          site: item.sourceLabel,
          snippet: item.snippet,
          kind: item.kind,
        ),
      );
    }
    return out.take(8).toList();
  }

  String _aiBandLabel() {
    final selected = _band.trim();
    if (selected.isNotEmpty) {
      final desc = MaterialLibrary.difficultyBandDesc[selected] ?? '';
      return 'CEFR $selected${desc.isEmpty ? '' : ' · $desc'}';
    }
    try {
      final band = MaterialNeed.load().band;
      if (!band.isAny) {
        final name = switch (band) {
          MaterialBand.i1 => '舒适区',
          MaterialBand.i10 => '挑战区',
          MaterialBand.i100 => '快反馈区',
          MaterialBand.any => '不限',
        };
        return '${band.label} · $name';
      }
    } catch (_) {
      // 读不到偏好 → 按"不限难度"如实说
    }
    return '不限难度';
  }

  String _aiBandHint() {
    final selected = _band.trim();
    if (selected.isNotEmpty) {
      final desc = MaterialLibrary.difficultyBandDesc[selected] ?? '';
      return '目标难度 CEFR $selected${desc.isEmpty ? '' : '($desc)'}'
          ':用词与句长按这个难度控制';
    }
    try {
      final band = MaterialNeed.load().band;
      if (!band.isAny) return band.hintForAi;
    } catch (_) {
      // 读不到偏好 → 不给难度约束(不编)
    }
    return '';
  }

  String _aiExtraNote() {
    final blocked = <String>[
      ..._prefs.blockedTopics.take(4),
      ..._prefs.blockedKeywords.take(4),
    ].where((value) => value.trim().isNotEmpty).toList();
    if (blocked.isEmpty) return '';
    return '避开这些题材/关键词:${blocked.join("、")}';
  }

  Future<void> _generateAiRewrite() async {
    if (_aiRunning || _aiBusy) return;
    final query =
        _query.text.trim().isEmpty ? _recommendedQuery() : _query.text.trim();
    // 2026-11-08 用户要求：生成前先问"字数/难度"，默认不限字数、贴近原难度。
    final options = await showAiRewriteOptions(context);
    if (options == null || !mounted) return;
    // 只把**与本次关键词相关**的线索给模型（NPR 最新新闻这种不相关线索会把内容带偏）
    final tokens = _relevanceTokens(query);
    final all = _aiSources();
    var sources = all
        .where((s) => _hitMatchesTokens('${s.title} ${s.snippet}', tokens))
        .take(8)
        .toList();
    if (sources.isEmpty) sources = all.take(3).toList();
    setState(() {
      _aiRunning = true;
      _aiError = null;
      _aiMaterial = null;
      _aiSaved = false;
    });
    final request = AiRewriteRequest(
      query: query,
      sources: sources,
      bandLabel: _aiBandLabel(),
      bandHint: _aiBandHint(),
      goals: _prefs.examGoals.take(2).toList(),
      interests: _prefs.interests.take(3).toList(),
      extraNote: _aiExtraNote(),
      topicHint: _lastPlan.changed
          ? '${_lastPlan.original}（原版名可能是 ${_lastPlan.primaryQuery}）'
          : query,
      wordLimit: options.wordLimit,
      difficultyMode: options.difficultyMode,
    );
    final rewriter = widget.aiRewriter ?? MaterialAiRewriter();
    var outcome = await rewriter.generate(request);
    // 覆盖优先：篇幅明显不够时重试一次（同一请求，模型通常会写得更完整）
    final minWords = options.wordLimit != null
        ? (options.wordLimit! * 0.75).round()
        : 300;
    if (outcome.ok && outcome.material!.wordCount < minWords) {
      final retry = await rewriter.generate(request);
      if (retry.ok) outcome = retry;
    }
    if (!mounted) return;
    setState(() {
      _aiRunning = false;
      if (outcome.ok) {
        _aiMaterial = outcome.material;
        _aiError = null;
      } else {
        _aiError = outcome.error;
      }
    });
  }

  /// 开始读 / 保存到我的:先把 AI 改写材料入库(source=ai,标题/许可带标注),
  /// 再进阅读器或记「保存到我的」关系。失败给人话提示,不静默。
  Future<void> _useAiMaterial({required bool save}) async {
    final material = _aiMaterial;
    if (material == null || _aiBusy) return;
    setState(() => _aiBusy = true);
    try {
      final materialId = await MaterialAiRewriteStore.ingest(
        material,
        vocab: _vocabOrEmpty(context),
      );
      if (!mounted) return;
      if (materialId <= 0) {
        _snack('入库失败:本地存储写入出错,请重试。');
        return;
      }
      if (save) {
        final ok = await MaterialChannelStore.addSavedMaterial(
          _controller.storeId,
          materialId,
        );
        if (!mounted) return;
        if (!ok) {
          _snack('保存关系没写进本地存储,可以稍后再点一次。');
          return;
        }
        setState(() => _aiSaved = true);
        _snack('已保存到「我的」:标题带「$aiRewriteMarker」标注,正文末尾保留来源链接。');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialReaderScreen(materialId: materialId),
        ),
      );
    } catch (e) {
      _snack('打开失败:$e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  List<Vocabulary> _vocabOrEmpty(BuildContext context) {
    try {
      return context.read<VocabProvider>().vocabularies;
    } catch (_) {
      // 渲染/单测没有 Provider 时按空词库算(仍能入库,只是少一层"已知词"加成)
      return const <Vocabulary>[];
    }
  }

  // ── 筛选(2026-11-07:默认收起 + 可滚动面板)────────────────────────

  int get _filterCount =>
      _sources.length +
      (_kind.isEmpty ? 0 : 1) +
      (_band.isEmpty ? 0 : 1) +
      (_scene.isEmpty ? 0 : 1);

  bool get _hasFilter => _filterCount > 0;

  void _clearFilters() {
    setState(() {
      _sources.clear();
      _kind = '';
      _band = '';
      _scene = '';
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            _searchBar(skin),
            const SizedBox(height: 6),
            _filterBar(skin),
            if (_filtersOpen) _filterPanel(skin),
            Divider(height: 1, color: skin.hairline),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(
                    Gap.page, Gap.sm, Gap.page, Gap.xl),
                children: _children(skin),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部搜索行。
  ///
  /// 2026-11-07 用户真机反馈第 4 条:输入文字**上半截被圆角框切掉**。
  /// 根因是原来给容器写死 `height: 42` + `isDense` 的 TextField,留给文字的内高
  /// 不够(中文行高 + 光标高度超过可用区,InputDecorator 把内容裁了)。
  /// 现在:容器只给 `minHeight`,文字区显式 `contentPadding` + 行高,
  /// 让 TextField 自己撑到够高 —— 任何中英文输入都完整显示。
  Widget _searchBar(V4Skin skin) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 2, Gap.page, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          InkWell(
            onTap: () => Navigator.maybePop(context),
            customBorder: const CircleBorder(),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: skin.surface,
                shape: BoxShape.circle,
                border: Border.all(color: skin.hairline),
                boxShadow: skin.shadow,
              ),
              child: Icon(Icons.arrow_back_rounded,
                  size: 19, color: skin.ink),
            ),
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: skin.accent.withValues(alpha: 0.45),
                ),
                boxShadow: skin.shadow,
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search_rounded,
                      size: 17, color: skin.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(),
                      textAlignVertical: TextAlignVertical.center,
                      cursorColor: skin.accent,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: skin.ink,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        // 全局 InputDecorationTheme 是"填充+描边"的表单样式;
                        // 搜索框在胶囊容器里,必须显式关掉所有状态的边框/填充,
                        // 否则文字外套会多出一个灰色圆角框(真机截图上很显眼)。
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        hintText: '英文关键词,如 climate change',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: skin.inkFaint,
                        ),
                        // 关键:文字上下留够(12+12),不再被容器高度裁掉;
                        // 13px 字号 × 1.35 行高 ≈ 17.6,内高 ~41.6 一定装得下整行
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_query.text.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => setState(_query.clear),
                      child: Icon(Icons.close_rounded,
                          size: 15, color: skin.inkFaint),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: _running ? null : () => _runSearch(),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(_running ? '搜…' : '搜索'),
            ),
          ),
        ],
      ),
    );
  }

  /// 收起态的一行:「筛选(n)」+ 已选条件摘要 chips(+ 清空)。
  Widget _filterBar(V4Skin skin) {
    final summary = <Widget>[
      for (final id in _sources)
        _summaryChip(
          skin,
          _shortSourceLabelOf(id),
          onClear: () => setState(() => _sources.remove(id)),
        ),
      if (_kind.isNotEmpty)
        _summaryChip(
          skin,
          _kindLabel(_kind),
          onClear: () => setState(() => _kind = ''),
        ),
      if (_band.isNotEmpty)
        _summaryChip(
          skin,
          _band,
          onClear: () => setState(() => _band = ''),
        ),
      if (_scene.isNotEmpty)
        _summaryChip(
          skin,
          _sceneLabel(_scene),
          onClear: () => setState(() {
            _scene = '';
          }),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, 0),
      child: Row(
        children: <Widget>[
          _filterToggle(skin),
          const SizedBox(width: 6),
          Expanded(
            child: summary.isEmpty
                ? Text(
                    '来源 · 类型 · 难度 · 场景',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: skin.inkFaint),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        for (var i = 0; i < summary.length; i++) ...<Widget>[
                          if (i > 0) const SizedBox(width: 4),
                          summary[i],
                        ],
                      ],
                    ),
                  ),
          ),
          if (_hasFilter)
            InkWell(
              onTap: _clearFilters,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  '清空',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: skin.inkFaint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterToggle(V4Skin skin) {
    final count = _filterCount;
    final active = _filtersOpen || count > 0;
    return InkWell(
      key: const ValueKey('free-filter-toggle'),
      onTap: () => setState(() => _filtersOpen = !_filtersOpen),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? skin.accent.withValues(alpha: 0.12)
              : skin.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? skin.accent.withValues(alpha: 0.5)
                : skin.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.tune_rounded,
              size: 14,
              color: active ? skin.accent : skin.inkSoft,
            ),
            const SizedBox(width: 5),
            Text(
              count > 0 ? '筛选($count)' : '筛选',
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? skin.accent : skin.inkSoft,
              ),
            ),
            Icon(
              _filtersOpen
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 15,
              color: skin.inkFaint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(V4Skin skin, String label,
      {required VoidCallback onClear}) {
    return InkWell(
      onTap: onClear,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: skin.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: skin.accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: skin.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.close_rounded, size: 10, color: skin.accent),
          ],
        ),
      ),
    );
  }

  /// 展开的筛选面板:**限高 + 可滚动**,不再悬置挡住大半个屏幕(用户第 4 条)。
  Widget _filterPanel(V4Skin skin) {
    final maxHeight =
        (MediaQuery.sizeOf(context).height * 0.42).clamp(200.0, 380.0).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 4, Gap.page, 6),
      child: AppCard(
        variant: AppCardVariant.compact,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
        child: Column(
          key: const ValueKey('free-filter-panel'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _filterGroup(
                      skin,
                      title: '来源',
                      hint: '9 个真实公开源,可多选',
                      children: <Widget>[
                        _chip(
                          skin,
                          '全部来源',
                          selected: _sources.isEmpty,
                          onTap: () => setState(_sources.clear),
                        ),
                        for (final source in MaterialSourceService.sources)
                          _chip(
                            skin,
                            _shortSourceLabel(source),
                            selected: _sources.contains(source.id),
                            onTap: () => setState(() {
                              if (!_sources.remove(source.id)) {
                                _sources.add(source.id);
                              }
                            }),
                            badge: MaterialSourceService.measuredReachable
                                    .contains(source.id)
                                ? '实测可用'
                                : null,
                          ),
                      ],
                    ),
                    _filterGroup(
                      skin,
                      title: '类型',
                      hint: '按材料形态过滤(百科走随机条目池)',
                      children: <Widget>[
                        _chip(
                          skin,
                          '不限类型',
                          selected: _kind.isEmpty,
                          onTap: () => setState(() => _kind = ''),
                        ),
                        _chip(
                          skin,
                          '书籍',
                          selected: _kind == 'book',
                          onTap: () => setState(() => _kind = 'book'),
                        ),
                        _chip(
                          skin,
                          '论文',
                          selected: _kind == 'paper',
                          onTap: () => setState(() => _kind = 'paper'),
                        ),
                        _chip(
                          skin,
                          '外刊新闻',
                          selected: _kind == 'news',
                          onTap: () => setState(() => _kind = 'news'),
                        ),
                        _chip(
                          skin,
                          '播客',
                          selected: _kind == 'podcast',
                          onTap: () => setState(() => _kind = 'podcast'),
                        ),
                        _chip(
                          skin,
                          '百科',
                          selected: _kind == 'wiki',
                          onTap: () => setState(() => _kind = 'wiki'),
                        ),
                      ],
                    ),
                    _filterGroup(
                      skin,
                      title: '难度',
                      hint: '按来源预估,非精确覆盖率(抓正文后才算真实难度)',
                      children: <Widget>[
                        _chip(
                          skin,
                          '不限难度',
                          selected: _band.isEmpty,
                          onTap: () => setState(() => _band = ''),
                        ),
                        for (final band in MaterialLibrary.difficultyBands)
                          _chip(
                            skin,
                            band,
                            selected: _band == band,
                            onTap: () => setState(() => _band = band),
                          ),
                      ],
                    ),
                    _filterGroup(
                      skin,
                      title: '场景',
                      hint: '公开源没有场景元数据 —— 点了是填入检索词预设',
                      children: <Widget>[
                        for (final sub in MaterialTaxonomy.scene.subtopics)
                          _chip(
                            skin,
                            sub.label,
                            selected: _scene == sub.id,
                            onTap: () => setState(() {
                              if (_scene == sub.id) {
                                _scene = '';
                              } else {
                                _scene = sub.id;
                                if (sub.queries.isNotEmpty) {
                                  _query.text = sub.queries.first;
                                }
                              }
                            }),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '语言:英文(当前公开源全部是英文站,没有多语言源可切)',
                        style: TextStyle(fontSize: 9.5, color: skin.inkFaint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _hasFilter ? '已选 $_filterCount 项' : '没有筛选条件',
                    style: TextStyle(fontSize: 10, color: skin.inkFaint),
                  ),
                ),
                TextButton(
                  key: const ValueKey('free-filter-collapse'),
                  onPressed: () => setState(() => _filtersOpen = false),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('收起筛选'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterGroup(
    V4Skin skin, {
    required String title,
    required String hint,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: skin.ink,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: skin.inkFaint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children,
          ),
        ],
      ),
    );
  }

  Widget _chip(
    V4Skin skin,
    String label, {
    required bool selected,
    required VoidCallback onTap,
    String? badge,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? skin.accent.withValues(alpha: 0.12)
              : skin.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? skin.accent.withValues(alpha: 0.5)
                : skin.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? skin.accent : skin.inkSoft,
              ),
            ),
            if (badge != null) ...<Widget>[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: skin.pastelAt(2).first.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(fontSize: 8, color: skin.ink),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _kindLabel(String kind) => switch (kind) {
        'book' => '书籍',
        'paper' => '论文',
        'news' => '外刊新闻',
        'podcast' => '播客',
        'wiki' => '百科',
        _ => kind,
      };

  String _sceneLabel(String id) {
    for (final sub in MaterialTaxonomy.scene.subtopics) {
      if (sub.id == id) return sub.label;
    }
    return id;
  }

  // ── 结果区 ──────────────────────────────────────────────────────────

  List<Widget> _children(V4Skin skin) {
    final children = <Widget>[];
    // 搜索过程卡:跑完一轮后**收起但保留**(用户想回看"查了哪些源"还能点开,
    // 不会一搜完就消失);没有任何过程事件时才不占位。
    if (_running || _events.isNotEmpty) {
      children.add(_processCard(skin));
      children.add(const SizedBox(height: Gap.sm));
    }
    if (_error != null) {
      children.add(
        AppErrorCard(
          message: _error!,
          onRetry: _running ? null : () => _runSearch(),
        ),
      );
      children.add(const SizedBox(height: Gap.sm));
    }
    if (_controller.items.isNotEmpty) {
      children.add(_metaRow(skin));
      children.add(const SizedBox(height: Gap.xs));
      children.add(
        MaterialResultList(
          items: _controller.items,
          page: _controller.page,
          busyUrl: _controller.busyUrl,
          onPageChanged: (next) {
            _controller.goPage(next);
            _scrollToTop();
          },
          onRead: _read,
          onSave: _save,
          onOpenOriginal: _openOriginal,
          onContinue: _running ? null : () => _runSearch(broaden: true),
          continueEnabled: !_running,
          continueLabel: '继续找更多',
          continueHint: '放宽来源再搜一轮;没有新增就说明这个关键词已经找全了。',
        ),
      );
      children.add(const SizedBox(height: Gap.md));
      children.add(_aiFallbackSection(skin));
      return children;
    }
    if (_searchedThisSession) {
      children.add(_emptyAfterRun(skin));
      children.add(const SizedBox(height: Gap.sm));
      children.add(_aiFallbackSection(skin));
      return children;
    }
    children.add(_introCard(skin));
    return children;
  }

  Widget _processCard(V4Skin skin) {
    return AppCard(
      variant: AppCardVariant.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _showProcess = !_showProcess),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Icon(
                    _running ? Icons.autorenew_rounded : Icons.timeline_rounded,
                    size: 17,
                    color: skin.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _running ? '正在检索公开源(点开看过程)' : '搜索过程 · ${_events.length} 步',
                      style: AppFont.subheadStyle.copyWith(
                        color: skin.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(_showProcess ? '收起' : '展开',
                      style: AppFont.tagStyle.copyWith(color: skin.accent)),
                  Icon(
                    _showProcess
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: skin.inkFaint,
                  ),
                ],
              ),
            ),
          ),
          if (_showProcess) ...<Widget>[
            const SizedBox(height: 6),
            SearchTimeline(events: _events, loading: _running),
          ],
        ],
      ),
    );
  }

  Widget _metaRow(V4Skin skin) {
    final parts = <String>[
      _searchedThisSession ? '本次结果' : '上次结果',
      '${_controller.items.length} 篇',
      '第 ${_controller.safePage + 1}/${_controller.pageCount} 页',
      if (_notes.isNotEmpty) '源说明 ${_notes.length} 条',
    ];
    return Row(
      children: <Widget>[
        Icon(Icons.history_rounded, size: 14, color: skin.inkFaint),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            parts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFont.metaStyle.copyWith(color: skin.inkSoft),
          ),
        ),
        if (_notes.isNotEmpty)
          Text('源说明',
              style: AppFont.tagStyle.copyWith(color: skin.accent)),
      ],
    );
  }

  Widget _introCard(V4Skin skin) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.manage_search_rounded,
                  size: 18, color: skin.accent),
              const SizedBox(width: 6),
              Text('直接搜公开源原文',
                  style: AppFont.subheadStyle.copyWith(
                    color: skin.ink,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '· 公开源只认英文关键词(中文需求请用「按我的情况找」)\n'
            '· 搜到的是原文链接,点「开始读」会抓正文入库并按你的词频算难度\n'
            '· 免费:不走 AI 检索,不花官方搜索的钱\n'
            '· 万一没有可读原文:可以看下面「AI 改写学习版(非原文)」兜底',
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: skin.inkSoft,
            ),
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final sample in const <String>[
                'climate change',
                'new concept english',
                'cet-4 reading',
                'short stories',
              ])
                InkWell(
                  onTap: () => setState(() => _query.text = sample),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: skin.surfaceAlt,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(sample,
                        style: TextStyle(
                            fontSize: 11, color: skin.inkSoft)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 空结果:先说清"为什么没找到"(只用真实检索信息),再给可落地的下一步。
  Widget _emptyAfterRun(V4Skin skin) {
    final query = _query.text.trim();
    final diagnostics = <String>[];
    if (_ranOnce) {
      final searched = _searchedSources.isEmpty
          ? '公开源'
          : _searchedSources.take(3).join('、');
      diagnostics.add('搜了什么:关键词「${query.isEmpty ? '(空)' : query}」'
          ' · 检索 $searched'
          '${_searchedSources.length > 3 ? ' 等 ${_searchedSources.length} 个源' : ''}');
      diagnostics.add('命中几条:原始命中 $_rawHits 条,按你选的筛选条件'
          '(来源/类型/难度/屏蔽词)后 0 条可展示');
      if (_notes.isNotEmpty) {
        diagnostics.add('源怎么说:${_notes.take(3).join(';')}');
      }
      if (_rawHits == 0) {
        diagnostics.add('为什么没抓到正文:根本没有命中结果 —— 关键词可能太窄/太新,'
            '或这个源没有可检索的原文');
      } else {
        diagnostics.add('为什么没抓到正文:命中的不是可读原文(列表页/需登录/非英文),'
            '或都被筛选条件挡掉了');
      }
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('这次没找到能读的结果',
              style: AppFont.subheadStyle.copyWith(
                color: skin.ink,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 6),
          if (diagnostics.isNotEmpty)
            for (final line in diagnostics)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '· $line',
                  style: TextStyle(
                      fontSize: 11, height: 1.5, color: skin.inkSoft),
                ),
              )
          else
            Text(
              _notes.isEmpty
                  ? '换个英文关键词,或放宽来源/难度再试。'
                  : _notes.take(3).join('\n'),
              style: TextStyle(
                  fontSize: 11, height: 1.5, color: skin.inkSoft),
            ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.xs,
            runSpacing: 6,
            children: <Widget>[
              FilledButton(
                onPressed: _running ? null : () => _runSearch(),
                child: const Text('再搜一次'),
              ),
              if (_hasFilter)
                OutlinedButton(
                  onPressed: _running
                      ? null
                      : () {
                          _clearFilters();
                          _runSearch();
                        },
                  child: const Text('清掉筛选再搜'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── AI 改写保底卡片(非原文)────────────────────────────────────────

  Widget _aiFallbackSection(V4Skin skin) {
    final material = _aiMaterial;
    if (material != null) return _aiResultCard(skin, material);
    return _aiEntryCard(skin);
  }

  Widget _aiEntryCard(V4Skin skin) {
    final sources = _aiSources();
    final hasOriginals = _controller.items.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: skin.pastelAt(2).first.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: skin.accent.withValues(alpha: 0.28)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded, size: 17, color: skin.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasOriginals ? '这些都不合适?' : '没找到想读的原文?',
                  style: AppFont.subheadStyle.copyWith(
                    color: skin.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              AppTag('AI 改写 · 非原文', tone: AppTagTone.primary),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasOriginals
                ? '如果有原文,优先读上面的结果;都不是你要的(或抓不到正文),'
                    '可以让 AI 基于这次搜到的标题/摘要改写一篇学习版 —— 它不是原文。'
                : '这次没找到可读原文。可以让 AI 基于这次真实搜到的标题/摘要/来源'
                    '改写一篇适合你难度的英文学习版 —— 它不是原文。',
            style: TextStyle(
              fontSize: 11,
              height: 1.55,
              color: skin.inkSoft,
            ),
          ),
          if (_contentFailCount > 0) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '· 有 $_contentFailCount 篇抓不到正文(上面已标注原因)',
              style: TextStyle(fontSize: 10.5, color: skin.inkFaint),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '依据:${sources.length} 条真实线索(标题/摘要/来源链接)',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: skin.ink,
            ),
          ),
          if (sources.isNotEmpty && sources.length < 2)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '线索只有 ${sources.length} 条 —— 改写的依据有限,内容会偏概括,'
                '拿到后建议对照来源链接核对。',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.45,
                  color: skin.inkFaint,
                ),
              ),
            ),
          if (sources.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '这次一条线索都没有 —— AI 会只围绕你的检索主题写一篇学习材料,'
                '不冒充任何来源、不编数据。',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.45,
                  color: skin.inkFaint,
                ),
              ),
            ),
          if (_aiRunning) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '正在让 AI 基于 ${sources.length} 条线索改写(通常 20~60 秒)…',
                    style: TextStyle(fontSize: 10.5, color: skin.inkSoft),
                  ),
                ),
              ],
            ),
          ] else ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _generateAiRewrite,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                label: const Text(
                  '生成 AI 改写学习版(非原文)',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '会调用 1 次模型(按你的 API 计费,不花官方搜索的钱)。',
              style: TextStyle(fontSize: 9.5, height: 1.5, color: skin.inkFaint),
            ),
            const SizedBox(height: 2),
            Text(
              '生成后可直接阅读,或保存到「我的」。',
              style: TextStyle(fontSize: 9.5, height: 1.5, color: skin.inkFaint),
            ),
            const SizedBox(height: 16),
          ],
          if (_aiError != null) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: skin.hairline),
              ),
              child: Text(
                _aiError!,
                style: TextStyle(
                    fontSize: 10.5, height: 1.45, color: skin.inkSoft),
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: _aiRunning ? null : _generateAiRewrite,
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }

  /// AI 改写产物卡:标注(非原文)/ 来源 / 真实字数与难度 / 可读可存。
  Widget _aiResultCard(V4Skin skin, AiRewrittenMaterial material) {
    return Container(
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: skin.accent.withValues(alpha: 0.45)),
        boxShadow: skin.shadow,
      ),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded, size: 17, color: skin.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'AI 改写学习版(非原文)',
                  style: AppFont.subheadStyle.copyWith(
                    color: skin.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_aiSaved) const AppTag('已在我的', tone: AppTagTone.success),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            material.topic,
            style: AppFont.subheadStyle.copyWith(
              color: skin.ink,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if (material.titleCn.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              material.titleCn,
              style: TextStyle(fontSize: 11, color: skin.inkSoft),
            ),
          ],
          if (material.summaryCn.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              material.summaryCn,
              style: TextStyle(
                  fontSize: 11, height: 1.5, color: skin.inkSoft),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            material.metricLine,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: skin.ink,
            ),
          ),
          const SizedBox(height: 6),
          if (material.coverageLine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                material.coverageLine,
                style: TextStyle(
                    fontSize: 10, height: 1.5, color: skin.inkSoft),
              ),
            ),
          Text(
            '基于 ${material.usedSources.length} 条真实来源:',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: skin.inkSoft,
            ),
          ),
          for (var i = 0; i < material.usedSources.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${i + 1}. ${material.usedSources[i].title}'
                '${material.usedSources[i].site.trim().isEmpty ? '' : ' — ${material.usedSources[i].site}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: skin.inkFaint),
              ),
            ),
          if (material.basisLimited)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '依据有限(只有 ${material.usedSources.length} 条线索),内容偏概括。',
                style: TextStyle(fontSize: 9.5, color: skin.inkFaint),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '正文末尾保留来源链接与许可;入库标题带「$aiRewriteMarker」标注,'
            '不会和原文混在一起。',
            style: TextStyle(fontSize: 9.5, height: 1.45, color: skin.inkFaint),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: Gap.xs,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton(
                onPressed: _aiBusy ? null : () => _useAiMaterial(save: false),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(_aiBusy ? '处理中…' : '开始读'),
              ),
              OutlinedButton(
                onPressed: _aiBusy || _aiSaved
                    ? null
                    : () => _useAiMaterial(save: true),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(_aiSaved ? '已在我的' : '保存到我的'),
              ),
              TextButton(
                onPressed: _aiRunning || _aiBusy
                    ? null
                    : () => setState(() {
                          _aiMaterial = null;
                          _aiSaved = false;
                        }),
                child: const Text('重新生成'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortSourceLabel(MaterialSource source) {
    var label = source.label;
    final paren = label.indexOf(RegExp(r'[（(]'));
    if (paren > 0) label = label.substring(0, paren);
    return label.trim().isEmpty ? source.id : label.trim();
  }

  String _shortSourceLabelOf(String id) {
    final source = MaterialSourceService.sourceOf(id);
    return source == null ? id : _shortSourceLabel(source);
  }
}
