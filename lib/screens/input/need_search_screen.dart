import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../providers/vocab_provider.dart';
import '../../services/find_need_context.dart';
import '../../services/input_prefs.dart';
import '../../services/learner_model_store.dart';
import '../../services/material_channel.dart';
import '../../services/material_ai_rewrite.dart';
import '../../widgets/ai_rewrite_options_sheet.dart';
import '../../services/material_discovery.dart';
import '../../services/search_query_planner.dart';
import '../../services/material_need.dart';
import '../../services/material_taxonomy.dart';
import '../../services/original_search.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/material_result_list.dart';
import '../../widgets/search_timeline.dart';
import 'material_browse_screen.dart';
import 'free_search_screen.dart';
import 'material_reader_screen.dart';

/// 「找材料 · 按我的情况找」独立页(用户选型 A 方案的右路)。
///
/// 与「自由搜」的区别:**检索词和依据来自学习助理统计的真实用户情况**,不是用户
/// 自己敲的关键词:
/// - 4 行依据(难度档 / 学习目标 / 弱项 / 最近阅读)全部来自
///   [FindNeedContext](每个字段的 file:line 见实现文档对照表);
/// - 面板里「为什么推这些」文案由真实字段拼成(设计 §3.2 级别 1);
/// - 每张结果卡的「为什么推」只有**补抓正文、算完真实覆盖率**才出现(级别 2);
///   没算过就只显示来源/类型,绝不编难度数字;
/// - 没数据 → 写「待测 + 怎么测」,不显示任何数字(与学习助理同一条纪律)。
///
/// 检索走 `MaterialDiscovery().discover(...)`(与频道页同一条真实流水线:
/// AI 检索计划 → 公开源 + 官方搜索 → 抓正文 → 本地算难度),结果用共用
/// [MaterialResultList] 渲染,快照身份固定 `need:all`(与频道页「按需求」互通)。
class NeedSearchScreen extends StatefulWidget {
  /// **仅渲染测试用**:注入上下文,跳过 Hive/DB 异步读取(生产永不传)
  final FindNeedContext? initialContext;

  /// **仅渲染测试用**:直接给结果(展示结果页/无封面卡)
  final List<MaterialResultItem>? initialResults;

  /// **仅渲染测试用**:给结果时展示搜索过程卡
  final List<SearchEvent>? initialEvents;

  const NeedSearchScreen({
    super.key,
    this.initialContext,
    this.initialResults,
    this.initialEvents,
  });

  @override
  State<NeedSearchScreen> createState() => _NeedSearchScreenState();
}

class _NeedSearchScreenState extends State<NeedSearchScreen> {
  final ScrollController _scroll = ScrollController();
  late final MaterialResultController _controller = MaterialResultController(
    storeId: 'need:all',
    readerBuilder: (materialId) =>
        MaterialReaderScreen(materialId: materialId),
  );

  FindNeedContext? _ctx;
  InputPreferences _prefs = InputPreferences();
  bool _loadingContext = true;
  bool _running = false;
  bool _showProcess = false;
  bool _searchedThisSession = false;
  String? _error;
  List<String> _notes = const <String>[];
  final List<SearchEvent> _events = <SearchEvent>[];

  /// 本次会话的花费(官方搜索计费口径,与频道页一致:不含模型调用)
  double _costCny = 0;
  int _apiRequests = 0;

  /// 过滤前的真实线索(给「搜不到 → AI 改写保底」当依据)
  List<DiscoveredCandidate> _clues = const <DiscoveredCandidate>[];
  bool _aiBusy = false;
  AiRewrittenMaterial? _aiMaterial;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onController);
    try {
      _prefs = InputPreferences.load();
    } catch (_) {
      _prefs = InputPreferences();
    }
    if (widget.initialContext != null) {
      _ctx = widget.initialContext;
      _loadingContext = false;
      _searchedThisSession = widget.initialResults != null;
      if (widget.initialResults != null) {
        _controller.items.addAll(widget.initialResults!);
      }
      if (widget.initialEvents != null) {
        _events.addAll(widget.initialEvents!);
        _showProcess = true;
      }
      return;
    }
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loadingContext = true);
    FindNeedContext? ctx;
    try {
      ctx = await FindNeedContext.load();
    } catch (_) {
      ctx = null;
    }
    await _controller.loadSnapshot();
    if (!mounted) return;
    setState(() {
      _ctx = ctx;
      _loadingContext = false;
      _searchedThisSession = _searchedThisSession || _controller.items.isNotEmpty;
      _costCny = _controller.costCny;
      _apiRequests = _controller.apiRequests;
    });
  }

  // ── 检索 ────────────────────────────────────────────────────────────

  Future<void> _runSearch({bool more = false}) async {
    if (_running) return;
    final ctx = _ctx;
    if (ctx == null) return;
    if (more && _controller.items.isEmpty) return;
    if (more &&
        _controller.items.length >= MaterialChannelStore.maxSnapshotItems) {
      _snack(
        '结果已到上限(${MaterialChannelStore.maxSnapshotItems} 篇)。'
        '先读或保存已有结果,再继续找。',
      );
      return;
    }
    setState(() {
      _running = true;
      _showProcess = true;
      _error = null;
      _events.clear();
    });
    try {
      var extraQueries = const <String>[];
      if (more) {
        _event('让 AI 根据已找到的结果想新的检索词…');
        try {
          extraQueries = await MaterialDiscovery().planNextQueries(
            userQuery: ctx.needText,
            seenCandidates: <Map<String, Object?>>[
              for (final item in _controller.items) item.toSnapshotMap(),
            ],
            prefsHint: _prefs.promptHint,
          );
        } catch (e) {
          extraQueries = const <String>[];
        }
        if (!mounted) return;
        if (extraQueries.isEmpty) {
          setState(() {
            _running = false;
            _showProcess = false;
          });
          _snack('没想出新的检索词。可以改一下需求,或点右上角重新找。');
          return;
        }
        _event('新检索词:${extraQueries.join(' / ')}');
      }

      // 2026-11-08 根因：`ctx.queries()` 里是中文目标/兴趣（兴趣只留拉丁字母），
      // 公开源只认英文、官方搜索拿到中文就是考试/报名页 → 永远 0 条。
      // 这里把「需求+兴趣+目标+难度」交给 AI 规划成英文检索词（目标只用于难度）。
      var plannedQueries = ctx.queries();
      final needsPlanning = plannedQueries.any(
            (q) => RegExp(r'[\u4e00-\u9fff]').hasMatch(q),
          ) ||
          plannedQueries.every((q) => !RegExp(r'[A-Za-z]').hasMatch(q));
      if (needsPlanning) {
        final intent = <String>[
          ctx.needText,
          if (ctx.interests.isNotEmpty) '兴趣:${ctx.interests.join("、")}',
          if (ctx.goals.isNotEmpty) '目标:${ctx.goals.join("、")}',
          '想找能读到原文的英文学习材料',
        ].join('；');
        try {
          final planned =
              await SearchQueryPlanner().planQueries(intent, max: 3);
          if (planned.isNotEmpty) {
            plannedQueries = planned;
            _event('已规划英文检索词:${planned.join(" / ")}');
          }
        } catch (e) {
          _event('检索词规划失败,按原需求检索: $e');
        }
      }
      if (!mounted) return;
      final vocab = context.read<VocabProvider>().vocabularies;
      final run = await MaterialDiscovery().discover(
        queries: plannedQueries,
        extraQueries: extraQueries,
        excludeUrls: <String>{for (final item in _controller.items) item.url},
        prefs: _prefs,
        model: LearnerModelStore.load(),
        vocab: vocab,
        maxFetch: 8,
        userQuery: ctx.needText,
        onEvent: _event,
      );
      if (!mounted) return;

      final fresh = <MaterialResultItem>[];
      var seq = _controller.items.length;
      for (final candidate in run.items) {
        fresh.add(MaterialResultItem.fromCandidate(candidate, seq: seq++));
      }
      _event(
        fresh.isEmpty
            ? '这次没有抓到可读正文'
            : '找到 ${fresh.length} 篇可读材料'
                '${run.estimatedCostCny > 0 ? ' · 官方搜索约 ${run.estimatedCostCny.toStringAsFixed(3)} 元' : ''}',
        stage: fresh.isEmpty ? SearchStage.sourceEmpty : SearchStage.done,
      );
      final saved = await _controller.applyRun(
        fresh: fresh,
        queriesUsed: <String>[...ctx.queries(), ...extraQueries],
        runApiRequests: run.searchApiRequests,
        runCostCny: run.estimatedCostCny,
        runNotes: run.notes,
        append: more,
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _showProcess = false;
        _searchedThisSession = true;
        _notes = List<String>.of(run.notes);
        _costCny = _controller.costCny;
        _apiRequests = _controller.apiRequests;
        _clues = run.clues;
        _aiMaterial = null;
        _aiError = null;
      });
      _scrollToTop();
      if (!saved) {
        _snack('结果已显示,但保存频道快照失败(下次进来可能看不到这批)。');
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

  void _event(String label, {SearchStage stage = SearchStage.searching}) {
    if (!mounted) return;
    setState(() => _events.add(SearchEvent(stage: stage, label: label)));
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

  Future<void> _openNeedSettings() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const MaterialBrowseScreen(
          direction: MaterialDirection.need,
          settingsOnly: true,
        ),
      ),
    );
    if (!mounted) return;
    // 改完需求重读依据(难度档/目标可能变了)
    try {
      _prefs = InputPreferences.load();
    } catch (_) {
      // 保持旧偏好:页面不因此崩溃
    }
    await _loadAll();
  }

  /// 「为什么推这篇」:**只有补抓到正文、算过真实覆盖率才允许出现**(级别 2)，
  /// 且覆盖率低于 [needSearchMinReasonCoverage] 时不显示（见该常量的说明）。
  String? _reasonFor(MaterialResultItem item) {
    final ctx = _ctx;
    return needSearchReasonFor(
      item: item,
      need: ctx?.need ?? const MaterialNeed(),
      goals: ctx?.goals ?? const <String>[],
    );
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
            _topBar(skin),
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

  Widget _topBar(V4Skin skin) {
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
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('按我的情况找',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                      color: skin.ink,
                    )),
                Text('读学习助理的统计,不用自己填条件',
                    style: TextStyle(fontSize: 10, color: skin.inkFaint)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _running ? null : _openNeedSettings,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: Icon(Icons.tune_rounded, size: 16, color: skin.accent),
            label: Text('改需求',
                style: AppFont.tagStyle.copyWith(color: skin.accent)),
          ),
        ],
      ),
    );
  }

  List<Widget> _children(V4Skin skin) {
    final children = <Widget>[];
    if (_loadingContext) {
      children.add(_loadingCard(skin));
      return children;
    }
    final ctx = _ctx;
    if (ctx != null) children.add(_basisCard(skin, ctx));
    children.add(const SizedBox(height: Gap.sm));
    children.add(
      SizedBox(
        height: 48,
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _running ? null : () => _runSearch(),
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_rounded, size: 18),
          label: Text(_running ? '正在按你的情况找…' : '按这些条件找材料'),
        ),
      ),
    );
    children.add(const SizedBox(height: Gap.xs));
    children.add(
      Text(
        '每次最多抓 8 篇正文;官方搜索按成功请求计费(几厘到几分钱)。',
        style: TextStyle(fontSize: 10, color: skin.inkFaint, height: 1.4),
      ),
    );
    children.add(const SizedBox(height: Gap.md));
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
          reasonFor: _reasonFor,
          onContinue: _running ? null : () => _runSearch(more: true),
          continueEnabled: !_running,
          continueLabel: '继续找更多',
          continueHint: '会让 AI 基于已找到的结果换检索词,追加新结果(页数随之增加)。',
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

  Widget _loadingCard(V4Skin skin) {
    return AppCard(
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: skin.accent,
            ),
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Text(
              '正在读取学习助理的数据(水平/目标/弱项/最近阅读)…',
              style: TextStyle(fontSize: 11.5, color: skin.inkSoft),
            ),
          ),
        ],
      ),
    );
  }

  /// 4 行真实依据 + 「为什么推这些」+ 两个动作
  Widget _basisCard(V4Skin skin, FindNeedContext ctx) {
    final rows = ctx.rows;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.insights_rounded, size: 16, color: skin.accent),
              const SizedBox(width: 5),
              Text('你的情况',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: skin.ink,
                  )),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: skin.pastelAt(2).first.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('来自学习助理',
                    style: TextStyle(fontSize: 9, color: skin.ink)),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _showBasisSheet(ctx),
                child: Text('看数据依据',
                    style: AppFont.tagStyle.copyWith(color: skin.accent)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) Divider(height: 1, color: skin.hairline),
            _basisRow(skin, rows[i]),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: skin.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('为什么推这些',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: skin.accent,
                    )),
                const SizedBox(height: 3),
                for (final line in ctx.reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.5,
                        color: skin.inkSoft,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _basisRow(V4Skin skin, FindNeedRow row) {
    final icon = switch (row.key) {
      'band' => Icons.tune_rounded,
      'goals' => Icons.flag_rounded,
      'weak' => Icons.error_outline_rounded,
      _ => Icons.auto_stories_outlined,
    };
    final tint = switch (row.key) {
      'band' => skin.pastelAt(3).first,
      'goals' => skin.pastelAt(0).first,
      'weak' => skin.pastelAt(1).first,
      _ => skin.pastelAt(2).first,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: skin.ink),
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(row.label,
                  style: TextStyle(fontSize: 10.5, color: skin.inkFaint)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight:
                          row.measured ? FontWeight.w600 : FontWeight.w400,
                      color: row.measured ? skin.ink : skin.inkFaint,
                    ),
                  ),
                  if (!row.measured && (row.hint ?? '').isNotEmpty)
                    Text(
                      row.hint!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.35,
                        color: skin.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
                      _running ? '正在按你的情况找材料(点开看过程)' : '搜索过程 · ${_events.length} 步',
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
      if (_apiRequests > 0)
        '官方搜索约 ${_costCny.toStringAsFixed(3)} 元(模型未计)',
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
              Icon(Icons.auto_awesome_rounded,
                  size: 18, color: skin.accent),
              const SizedBox(width: 6),
              Text('点上面的按钮开始找',
                  style: AppFont.subheadStyle.copyWith(
                    color: skin.ink,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '· 按难度档/目标/弱项找真实原文;每篇抓正文算真实覆盖率\n'
            '· 官方搜索按成功请求计费,页面显示本轮花费',
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: skin.inkSoft,
            ),
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
          Text('这次没找到能读的正文',
              style: AppFont.subheadStyle.copyWith(
                color: skin.ink,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 6),
          Text(
            _notes.isEmpty
                ? '换个方向:去「改需求」调一下难度档/目标,或再用「自由搜」直接搜关键词。'
                : _notes.take(3).join('\n'),
            style:
                TextStyle(fontSize: 11, height: 1.5, color: skin.inkSoft),
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.xs,
            children: <Widget>[
              FilledButton(
                onPressed: _running ? null : () => _runSearch(),
                child: const Text('再找一次'),
              ),
              OutlinedButton(
                onPressed: _running ? null : _openFreeSearchFallback,
                child: const Text('去自由搜'),
              ),
            ],
          ),
          if (_clues.isNotEmpty || _aiMaterial != null || _aiError != null) ...[
            const SizedBox(height: Gap.md),
            _aiFallback(skin),
          ],
        ],
      ),
    );
  }

  /// 搜不到正文时的 AI 改写保底（用户 2026-11-08 明确要求）：
  /// 不是原文、依据这次真实搜到的线索（标题/摘要/来源）重写一篇英文学习材料；
  /// 正文末尾写明来源，标题带「AI 改写学习版（非原文）」。
  Widget _aiFallback(V4Skin skin) {
    final material = _aiMaterial;
    return Container(
      padding: const EdgeInsets.all(Gap.sm),
      decoration: BoxDecoration(
        color: skin.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: skin.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            material == null ? '没有可读原文？AI 改写兜底（非原文）' : 'AI 改写学习版（非原文）',
            style: AppFont.subheadStyle.copyWith(
              color: skin.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          if (material == null)
            Text(
              _clues.isEmpty
                  ? '这次没有真实线索可依据,无法生成(不凭空编)。'
                  : '基于 ${_clues.length} 条真实线索改写(非原文),正文末尾注明来源。',
              style: TextStyle(fontSize: 11, height: 1.5, color: skin.inkSoft),
            ),
          if (_aiError != null) ...[
            const SizedBox(height: 6),
            Text(
              _aiError!,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (material != null) ...[
            const SizedBox(height: 6),
            Text(
              material.titleCn.trim().isEmpty
                  ? material.topic
                  : '${material.topic} · ${material.titleCn}',
              style: AppFont.bodyStyle.copyWith(
                fontSize: 13,
                height: 1.4,
                color: skin.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              material.metricLine,
              style: TextStyle(fontSize: 11, height: 1.5, color: skin.inkSoft),
            ),
            if (material.coverageLine.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  material.coverageLine,
                  style:
                      TextStyle(fontSize: 11, height: 1.5, color: skin.inkSoft),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              '来源：${material.usedSources.map((s) => s.title).take(3).join(' / ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, height: 1.4, color: skin.inkSoft),
            ),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.xs,
              children: <Widget>[
                FilledButton(
                  onPressed: () => _openAiMaterial(material),
                  child: const Text('开始读'),
                ),
                OutlinedButton(
                  onPressed: () => _saveAiMaterial(material),
                  child: const Text('保存到我的'),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: Gap.sm),
            FilledButton(
              onPressed: _aiBusy ? null : _generateAiRewrite,
              child: Text(_aiBusy ? '生成中…' : '生成 AI 改写学习版（非原文）'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _generateAiRewrite() async {
    if (_aiBusy) return;
    final ctx = _ctx;
    final query = ctx?.needText.trim() ?? '按我的情况找材料';
    // 2026-11-08 用户要求：生成前先问"字数/难度"，默认不限字数、贴近原难度。
    final options = await showAiRewriteOptions(context);
    if (options == null || !mounted) return;
    // 线索优先取与本主题相关的；全不相关时保留前 3 条真实线索（仍是真实来源）
    final tokens = _tokensFor(query);
    var picked = _clues
        .where((c) => _matchesTokens('${c.title} ${c.snippet}', tokens))
        .take(8)
        .toList();
    if (picked.isEmpty) picked = _clues.take(3).toList();
    final sources = picked
        .map((c) => AiRewriteSource(
              title: c.title,
              url: c.url,
              site: c.sourceLabel,
              snippet: c.snippet,
              kind: c.kind,
            ))
        .toList();
    setState(() {
      _aiBusy = true;
      _aiError = null;
      _aiMaterial = null;
    });
    try {
      final band = ctx?.need.band;
      final request = AiRewriteRequest(
        query: query,
        sources: sources,
        bandLabel: (band == null || band.isAny) ? '' : band.label,
        bandHint: (band == null || band.isAny) ? '' : band.description,
        goals: ctx?.goals ?? const <String>[],
        interests: ctx?.interests ?? const <String>[],
        topicHint: query,
        wordLimit: options.wordLimit,
        difficultyMode: options.difficultyMode,
      );
      final rewriter = MaterialAiRewriter();
      var outcome = await rewriter.generate(request);
      final minWords = options.wordLimit != null
          ? (options.wordLimit! * 0.75).round()
          : 300;
      if (outcome.ok && outcome.material!.wordCount < minWords) {
        final retry = await rewriter.generate(request);
        if (retry.ok) outcome = retry;
      }
      if (!mounted) return;
      setState(() {
        _aiBusy = false;
        if (outcome.ok) {
          _aiMaterial = outcome.material;
        } else {
          _aiError = outcome.error ?? 'AI 改写失败，请稍后再试。';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiBusy = false;
        _aiError = 'AI 改写失败：$e';
      });
    }
  }

  static List<String> _tokensFor(String text) {
    final out = <String>[];
    final seen = <String>{};
    for (final m in RegExp(r'[a-z0-9]{3,}').allMatches(text.toLowerCase())) {
      if (seen.add(m.group(0)!)) out.add(m.group(0)!);
    }
    for (final m in RegExp(r'[\u4e00-\u9fff]{2,}').allMatches(text)) {
      final cn = m.group(0)!;
      for (var i = 0; i + 2 <= cn.length; i++) {
        final t = cn.substring(i, i + 2);
        if (seen.add(t)) out.add(t);
      }
    }
    return out;
  }

  static bool _matchesTokens(String haystack, List<String> tokens) {
    if (tokens.isEmpty) return true;
    final hay = haystack.toLowerCase();
    for (final t in tokens) {
      if (hay.contains(t)) return true;
    }
    return false;
  }

  Future<void> _openAiMaterial(AiRewrittenMaterial material) async {
    final id = await _ingestAiMaterial(material);
    if (id <= 0) {
      _snack('保存失败，没法打开这篇 AI 改写材料。');
      return;
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MaterialReaderScreen(materialId: id),
      ),
    );
  }

  Future<void> _saveAiMaterial(AiRewrittenMaterial material) async {
    final id = await _ingestAiMaterial(material);
    if (!mounted) return;
    if (id <= 0) {
      _snack('保存失败，请稍后再试。');
    } else {
      _snack('已保存到「我的」：标题带「AI 改写学习版（非原文）」标注。');
    }
  }

  Future<int> _ingestAiMaterial(AiRewrittenMaterial material) {
    return MaterialAiRewriteStore.ingest(
      material,
      model: _ctx?.model,
      vocab: context.read<VocabProvider>().vocabularies,
    );
  }

  void _openFreeSearchFallback() {
    final query = _ctx?.needText.trim() ?? '';
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FreeSearchScreen(initialQuery: query),
      ),
    );
  }

  /// 「看数据依据」:把 4 行背后的真实字段全摊开(没有的写"待测",不编)
  Future<void> _showBasisSheet(FindNeedContext ctx) async {
    final skin = V4Skin.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottom = MediaQuery.of(sheetContext).padding.bottom;
        final lines = <String>[
          '词汇量基线:${ctx.baselineText}',
          if (ctx.cefr != null) 'CEFR:${ctx.cefr}',
          if (ctx.goals.isNotEmpty) '学习目标:${ctx.goals.join('、')}',
          if (ctx.interests.isNotEmpty) '兴趣题材:${ctx.interests.join('、')}',
          if (ctx.readingWpm != null) '阅读速度:${ctx.readingWpm} 词/分',
          if (ctx.materialsFinished30d != null)
            '近 30 天读完:${ctx.materialsFinished30d} 篇',
          if (ctx.materialsReading != null) '在读:${ctx.materialsReading} 篇',
          if (ctx.dailyMinutes != null) '每天可读:${ctx.dailyMinutes} 分钟',
          if (ctx.weakTags.isNotEmpty)
            '错误标签:${ctx.weakTags.map((tag) => '$tag ${ctx.errorCounts[tag] ?? 0} 次').join(' · ')}',
          if (ctx.blockedTopics.isNotEmpty) '屏蔽题材:${ctx.blockedTopics.join('、')}',
          if (ctx.blockedKeywords.isNotEmpty)
            '屏蔽关键词:${ctx.blockedKeywords.join('、')}',
          if (!ctx.hasTutorData) '助理还没数据:先做一次词汇量测试 / 读完一篇,这里就会有依据。',
        ];
        return Container(
          padding: EdgeInsets.fromLTRB(Gap.page, 12, Gap.page, 12 + bottom),
          decoration: BoxDecoration(
            color: skin.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: skin.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: Gap.sm),
              Text('这些数据从哪来',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: skin.ink,
                  )),
              const SizedBox(height: 4),
              Text('全部读自本机学习助理,没有编造。',
                  style:
                      TextStyle(fontSize: 10.5, color: skin.inkFaint)),
              const SizedBox(height: Gap.sm),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('· ',
                          style:
                              TextStyle(fontSize: 11, color: skin.inkFaint)),
                      Expanded(
                        child: Text(line,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.45,
                              color: skin.inkSoft,
                            )),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Gap.xs),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 「为什么推这篇」的阈值(纯函数,可单测)
// ═══════════════════════════════════════════════════════════════════════

/// 覆盖率低于该值就**不显示**「为什么推」。
///
/// 2026-11-07 用户真机反馈:覆盖率 0% 的卡片还写「为什么推:难度 0%」,既没用又
/// 像 bug。0.10（每 100 词 ≤10 个生词）是"至少落在 i+100 档以内"的下限 ——
/// 比这更低的材料连"能读"都谈不上,给理由只会误导用户。
const double needSearchMinReasonCoverage = 0.10;

/// 生成一张结果卡的「为什么推这篇」。
///
/// 只有**补抓到正文、算过真实覆盖率**且覆盖率 ≥ [needSearchMinReasonCoverage]
/// 时才返回文案;否则返回 null(卡片不显示理由行)。
String? needSearchReasonFor({
  required MaterialResultItem item,
  required MaterialNeed need,
  required List<String> goals,
}) {
  final coverage = item.analysis?.knownTokenRatio;
  if (coverage == null || coverage < needSearchMinReasonCoverage) return null;
  final parts = <String>['难度 ${(coverage * 100).round()}%'];
  if (!need.band.isAny) parts.add('落在你选的 ${need.band.label}');
  if (goals.isNotEmpty) parts.add('命中目标「${goals.first}」');
  return '为什么推:${parts.join(' · ')}';
}
