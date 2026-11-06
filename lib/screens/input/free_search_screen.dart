import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../services/find_need_context.dart';
import '../../services/input_prefs.dart';
import '../../services/material_library.dart';
import '../../services/material_source.dart';
import '../../services/material_taxonomy.dart';
import '../../services/original_search.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/material_result_list.dart';
import '../../widgets/search_timeline.dart';
import 'material_reader_screen.dart';

/// 「找材料 · 自由搜」独立搜索页(用户选型 A 方案的左路)。
///
/// 能力全部是真实可落地的:
/// - **关键词**:回车即搜;空关键词用"推荐检索词"(不弹空白页);
/// - **来源**:`MaterialSourceService.sources` 的 9 个真实公开源
///   (`material_source.dart`),可多选收窄;「实测可用」的源给标记;
/// - **类型**:5 类(书籍 / 论文 / 外刊新闻 / 播客 / 百科),与 `MaterialSource.kind`
///   对齐并映射到真实来源(`gutenberg` / `arxiv` / `npr`系 / `bbc_le`·`voa_le`·`ted` /
///   `wikipedia`);百科因为维基源没有关键词检索接口,走"随机条目池 + 本地关键词筛"
///   的如实降级(见 `_wikiFreshItems`);
/// - **难度**:按 `MaterialLibrary.estimateDifficulty` 的**来源级预计区间**过滤 ——
///   文案明说"非精确覆盖率",没抓正文**不标真实难度**(设计 §3.3 的硬规则);
/// - **场景**:`MaterialTaxonomy.scene` 的真实检索词预设(点了填入搜索框)——
///   公开源没有"场景"元数据,所以它是检索词预设,不是假过滤器。
///
/// 结果走与频道页共用的 [MaterialResultList](分组 / 每页 10 条 / 页码控件 /
/// 有真封面才显示 / 开始读·保存到我的·打开原文 / 切页回顶),快照按
/// `free:<归一关键词>` 复用 [MaterialChannelStore]。
class FreeSearchScreen extends StatefulWidget {
  /// 从入口卡/历史 chips 带进来的关键词(可空 = 空态)
  final String? initialQuery;

  /// **仅渲染测试用**:直接给结果,跳过网络(生产永不传)
  final List<MaterialResultItem>? initialResults;

  /// **仅渲染测试用**:给结果时顺带展示"搜索过程"卡
  final List<SearchEvent>? initialEvents;

  const FreeSearchScreen({
    super.key,
    this.initialQuery,
    this.initialResults,
    this.initialEvents,
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

  /// 类型筛选:'book' / 'paper' / 'news' / 空(=不限)
  String _kind = '';

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
      if (widget.initialEvents != null) {
        _events.addAll(widget.initialEvents!);
        _showProcess = true;
      }
      return;
    }
    if (query.isNotEmpty) {
      unawaited(_restoreSnapshot(query));
    }
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

  Future<void> _restoreSnapshot(String query) async {
    await _controller.loadSnapshot();
    if (!mounted) return;
    if (_controller.items.isNotEmpty) {
      setState(() => _searchedThisSession = true);
    }
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
      if (!broaden) _notes = const <String>[];
    });
    try {
      // 「百科」单独走:维基源在 OriginalSearch 链路里没有关键词检索接口,
      // 只能从**真实随机条目池**(listItems)拉一批再本地按关键词筛 ——
      // 这是能力边界,结果页文案会明说,不假装它和别的类型一样能搜。
      if (_kind == 'wiki') {
        final fresh = await _wikiFreshItems(query);
        final saved = await _controller.applyRun(
          fresh: fresh,
          queriesUsed: <String>[query],
          runApiRequests: 0,
          runCostCny: 0,
          runNotes: const <String>[],
          append: broaden,
        );
        await FindSearchHistory.remember(query);
        if (!mounted) return;
        setState(() {
          _running = false;
          _showProcess = false;
          _searchedThisSession = true;
          _notes = <String>[
            '维基百科源没有关键词检索接口:这次从随机条目池里筛出 ${fresh.length} 条匹配。',
          ];
        });
        _scrollToTop();
        if (!saved && fresh.isEmpty) {
          _snack('结果没存上快照(本地存储写入失败)。');
        }
        return;
      }
      final category = _categoryOf(_kind);
      final result = await OriginalSearch.search(
        query,
        category: category,
        sourceIds: broaden ? null : _selectedSourceIds(),
        onProgress: _onProgress,
      );
      if (!mounted) return;
      final fresh = <MaterialResultItem>[];
      var seq = _controller.items.length;
      for (final hit in result.hits) {
        final source = MaterialSourceService.sourceOf(hit.sourceId);
        final kind = inferMaterialKind(
          hit.title,
          hit.url,
          fallback: source?.kind ?? 'article',
        );
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
      _event(
        fresh.isEmpty
            ? '没有匹配的结果 —— 换个关键词,或放宽来源/难度'
            : '找到 ${fresh.length} 篇原文',
        stage: fresh.isEmpty ? SearchStage.sourceEmpty : SearchStage.done,
      );
      final saved = await _controller.applyRun(
        fresh: fresh,
        queriesUsed: <String>[query],
        runApiRequests: 0,
        runCostCny: 0,
        runNotes: result.notes,
        append: broaden,
      );
      await FindSearchHistory.remember(query);
      if (!mounted) return;
      setState(() {
        _running = false;
        _showProcess = false;
        _searchedThisSession = true;
        _notes = List<String>.of(result.notes);
      });
      _scrollToTop();
      if (fresh.isEmpty && !saved) {
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
  /// (设计 §3.3 的五类)。wiki 不在这条公开源检索链路上(见 `_wikiFreshItems`),
  /// 所以只在"不限类型"里随其他源出现,单独选「百科」走随机条目池筛选。
  String _categoryOf(String kind) => switch (kind) {
        'book' => '书籍',
        'paper' => '论文',
        'news' => '外刊',
        'podcast' => '外刊',
        _ => '其他',
      };

  /// 百科类型的真实候选:拉维基的随机条目池,再按关键词本地筛。
  ///
  /// 为什么不做成"假检索":`OriginalSearch` 只对 Gutenberg/arXiv/RSS 三类有检索
  /// 接口,Wikipedia 只有"随机条目"能力;硬造一个搜索框会变成"点了没反应"。
  /// 所以这里如实:随机池 → 本地关键词筛 → 命中几条报几条。
  Future<List<MaterialResultItem>> _wikiFreshItems(String query) async {
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
    var seq = _controller.items.length;
    for (final item in feed) {
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
    return fresh;
  }

  /// 类型 → 该类型的**真实来源 id**(来自 `MaterialSourceService.sources` 的 kind)
  ///
  /// 用户没手动选来源时,按类型收窄到对应源;手动选了来源则以手动为准
  /// (两者在 `OriginalSearch` 内部按"分类源 ∩ 指定源"取交集)。
  List<String>? _selectedSourceIds() {
    if (_sources.isNotEmpty) return _sources.toList();
    final matchedKind = switch (_kind) {
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
    if (message != null) _snack(message);
  }

  Future<void> _save(MaterialResultItem item) async {
    final message = await _controller.save(context, item);
    if (message != null) _snack(message);
  }

  Future<void> _openOriginal(MaterialResultItem item) async {
    final message = await _controller.openOriginal(item);
    if (message != null) _snack(message);
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
            const SizedBox(height: Gap.xs),
            _sourceRow(skin),
            _typeRow(skin),
            _difficultyRow(skin),
            _sceneRow(skin),
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

  Widget _searchBar(V4Skin skin) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 2, Gap.page, 0),
      child: Row(
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
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
                      style: TextStyle(fontSize: 12.5, color: skin.ink),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '输英文关键词,如 climate change / new concept',
                        hintStyle: TextStyle(
                            fontSize: 12, color: skin.inkFaint),
                      ),
                    ),
                  ),
                  if (_query.text.isNotEmpty)
                    InkWell(
                      onTap: () => setState(_query.clear),
                      child: Icon(Icons.close_rounded,
                          size: 15, color: skin.inkFaint),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 42,
            child: FilledButton(
              onPressed: _running ? null : () => _runSearch(),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 42),
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

  Widget _sourceRow(V4Skin skin) {
    return _chipRow(
      skin,
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
              if (!_sources.remove(source.id)) _sources.add(source.id);
            }),
            badge: MaterialSourceService.measuredReachable.contains(source.id)
                ? '实测可用'
                : null,
          ),
      ],
    );
  }

  Widget _typeRow(V4Skin skin) {
    return _chipRow(
      skin,
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
    );
  }

  Widget _difficultyRow(V4Skin skin) {
    return _chipRow(
      skin,
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
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            '按来源预估,非精确覆盖率',
            style: TextStyle(fontSize: 9.5, color: skin.inkFaint),
          ),
        ),
      ],
    );
  }

  Widget _sceneRow(V4Skin skin) {
    return _chipRow(
      skin,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Text(
            '场景',
            style: TextStyle(fontSize: 10, color: skin.inkFaint),
          ),
        ),
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
                // 场景 = 检索词预设(公开源没有场景元数据)
                if (sub.queries.isNotEmpty) _query.text = sub.queries.first;
              }
            }),
          ),
      ],
    );
  }

  /// 筛选行容器:用 **Wrap** 换行而不是横向滚动 —— 390 宽下每个 chip 都必须
  /// 完整可见(用户会一个个点;横向滚动会把末尾 chip 藏起来,QA 也提过)。
  Widget _chipRow(V4Skin skin, {required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 3, Gap.page, 3),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
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

  List<Widget> _children(V4Skin skin) {
    final children = <Widget>[];
    if (_running || (_events.isNotEmpty && _showProcess)) {
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
      return children;
    }
    if (_searchedThisSession) {
      children.add(_emptyAfterRun(skin));
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
            '· 免费:不走 AI 检索,不花官方搜索的钱',
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

  Widget _emptyAfterRun(V4Skin skin) {
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
          Text(
            _notes.isEmpty
                ? '换个英文关键词,或放宽来源/难度再试。'
                : _notes.take(3).join('\n'),
            style: TextStyle(
                fontSize: 11, height: 1.5, color: skin.inkSoft),
          ),
          const SizedBox(height: Gap.sm),
          FilledButton(
            onPressed: _running ? null : () => _runSearch(),
            child: const Text('再搜一次'),
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
}
