import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../services/deepseek_api.dart';
import '../../services/external_link.dart';
import '../../services/learner_model_store.dart';
import '../../services/learner_context.dart';
import '../../services/material_import.dart';
import '../../services/material_library.dart';
import '../../services/material_prefs.dart';
import '../../services/material_source.dart';
import '../../services/original_search.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/material_cover.dart';
import '../../widgets/search_timeline.dart';
import 'ai_material_search.dart';
import 'material_reader_screen.dart';

/// 「按你的水平找材料」的方向页(v2.4,D1 用户要求)。
///
/// 用户实测反馈:「里的资源全是 ai 二手改写的…完全不是一手原料。应该让用户可以
/// 自选 —— 推出来一本书,应该是"AI 总结/整理/编写"or"资料原文"这类的方向」。
///
/// 所以这一页给**两个明确的方向**,默认落在**资料原文**:
/// 1. 【资料原文】按关键词检索公开源(Gutendex 公版书 / arXiv 论文 / RSS 最新条目),
///    每条都能点开原文,来源与许可写在卡片上;
/// 2. 【AI 整理编写】沿用原来的 AI 推荐,但入口与结果都**明确标注是 AI 产物**,
///    不再冒充"推荐的书"。
class CategoryMaterialScreen extends StatefulWidget {
  /// 分类名(书籍/教材/外刊/碎片文章/论文/其他)
  final String category;

  const CategoryMaterialScreen({super.key, required this.category});

  @override
  State<CategoryMaterialScreen> createState() => _CategoryMaterialScreenState();
}

class _CategoryMaterialScreenState extends State<CategoryMaterialScreen> {
  final _queryCtrl = TextEditingController();
  final _ai = DeepseekApiService();
  List<OriginalHit> _hits = const [];
  /// 命中标题的中文译名(「中文(英文)」显示用),AI 翻不出来就回落纯英文
  Map<String, String> _titleCn = const {};
  /// AI 直接点名的作品(带 why 与原文链接)
  List<Map<String, String>> _picks = const [];
  String _aiNote = '';
  bool _loading = false;
  bool _searched = false;
  List<String> _notes = const [];
  LearnerModel _model = LearnerModel();

  /// 材料偏好(v2.7,第 4/5 条):难度档 + 类型 + 题材 + 补充需求,一并交给 AI
  MaterialPrefs _prefs = MaterialPrefs.empty;

  /// 检索过程事件(第 6(4) 条:流式展示"查阅了 xxx")
  List<SearchEvent> _events = const [];

  /// 正在抓取的 AI 点名作品(按引用比较,用来只禁用那一行)
  Map<String, String>? _openingPick;

  @override
  void initState() {
    super.initState();
    _model = LearnerModelStore.load();
    _prefs = MaterialPrefs.load();
    // v2.7(用户第 2(3) 条):搜索框只回填**上次在这个分类里真搜过的词**。
    // 旧实现填的是学习画像里的第一个兴趣词 —— 用户每次进来都看到同一个词挂着,
    // 以为"上次搜的东西没清掉",其实是拿画像词冒充搜索历史。
    _queryCtrl.text = MaterialPrefs.lastQueryFor(widget.category);
    // v2.5 起进来就自动搜一次("打开即行动");自动那一次用内部默认词,
    // **不写进搜索框**(搜索框留白 + hint 提示可以中文说需求)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search(auto: true);
    });
  }

  /// 自动首搜时的内部默认词:用户上次搜过就用上次的,否则按分类给一个默认。
  String _autoQuery() {
    final last = MaterialPrefs.lastQueryFor(widget.category);
    if (last.isNotEmpty) return last;
    return OriginalSearch.defaultQueryFor(widget.category);
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  /// 是不是"中文需求"(v2.6):是的话先让 AI 把它变成能搜的东西。
  bool get _looksChinese => RegExp(r'[\u4e00-\u9fa5]').hasMatch(_queryCtrl.text);

  Future<void> _search({bool auto = false, String? overrideQuery}) async {
    final raw = (overrideQuery ?? (auto ? _autoQuery() : _queryCtrl.text)).trim();
    // 记住用户真正搜过的东西(自动首搜不记,免得把默认词写成"历史")
    if (!auto && raw.isNotEmpty) {
      await MaterialPrefs.rememberQuery(widget.category, raw);
    }
    final started = DateTime.now();
    final events = <SearchEvent>[];
    void push(SearchEvent e) {
      events.add(e);
      if (mounted) setState(() => _events = List.of(events));
    }

    setState(() {
      _loading = true;
      _searched = true;
      _aiNote = '';
      _events = const [];
    });
    push(SearchEvent(
      stage: SearchStage.preparing,
      label: raw.isEmpty
          ? '按「${widget.category}」入门经典为你找材料'
          : '读懂你的需求:「$raw」',
    ));

    // ── ① AI 规划:中文需求 → 英文检索词 + 直接点名作品(带原文链接)──
    var query = raw;
    var picks = const <Map<String, String>>[];
    var aiNote = '';
    if (_ai.isConfigured && (raw.isEmpty || _looksChinese || !_prefs.isEmpty)) {
      try {
        push(SearchEvent(
          stage: SearchStage.preparing,
          label: '让 AI 把它变成公开源认的英文检索词…',
        ));
        final plan = await _ai.planMaterialSearch(
          raw.isEmpty ? '${widget.category} 入门 经典' : raw,
          category: widget.category,
          levelHint: LearnerContext.describeBaseline(_model),
          prefsHint: _prefs.hintForAi,
          bandHint: _prefs.band.isAny ? '' : _prefs.band.hintForAi,
        );
        final queries = (plan['queries'] as List?)?.cast<String>() ?? const [];
        picks = (plan['picks'] as List?)
                ?.whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry('$k', '$v')))
                .toList() ??
            const <Map<String, String>>[];
        aiNote = '${plan['note'] ?? ''}';
        if (queries.isNotEmpty) query = queries.first;
        push(SearchEvent(
          stage: SearchStage.preparing,
          label: '检索词:「$query」'
              '${picks.isEmpty ? '' : ' · AI 另外点名了 ${picks.length} 部作品'}',
        ));
      } catch (e) {
        debugPrint('ReadFlow 材料检索规划失败(退回关键词直搜): $e');
        push(SearchEvent(
          stage: SearchStage.sourceFailed,
          label: 'AI 规划失败,直接用关键词搜:$e',
        ));
      }
    }

    // ── ② 真实检索:拿 AI 给的英文词去公开源里搜真东西(按偏好挑源)──
    //     每一步都通过 onProgress 流式上报(用户第 6(4) 条)
    final result = await OriginalSearch.search(
      query,
      category: widget.category,
      sourceIds: _prefs.kinds.isEmpty
          ? null
          : [for (final s in _prefs.preferredSources) s.id],
      onProgress: push,
    );

    // ── ③ 标题中文化:整屏英文没人看得懂(用户第 8(3)/2(2) 条)──
    //     AI 点名的作品也要翻 —— 它们同样显示「中文(英文)」
    var titleCn = const <String, String>{};
    if (_ai.isConfigured) {
      final titles = <String>[
        ...result.hits.take(12).map((h) => h.title),
        for (final p in picks)
          if ((p['title_en'] ?? '').trim().isNotEmpty) p['title_en']!.trim(),
      ];
      if (titles.isNotEmpty) {
        push(SearchEvent(
          stage: SearchStage.translating,
          label: '正在把 ${titles.length} 个标题翻成中文…',
        ));
        try {
          titleCn = await _ai.translateTitles(titles);
        } catch (e) {
          debugPrint('ReadFlow 标题中文化失败(保持英文): $e');
        }
      }
    }
    if (mounted) {
      final seconds = DateTime.now().difference(started).inSeconds;
      setState(() => _events = [
            ...events,
            SearchEvent(
              stage: SearchStage.done,
              label: '查阅了 ${result.hits.length} 篇 · 用时 '
                  '${seconds == 0 ? '不到 1' : seconds} 秒',
              done: 1,
              total: 1,
              hits: result.hits.length,
            ),
          ]);
    }

    if (!mounted) return;
    setState(() {
      _hits = result.hits;
      _notes = result.notes;
      _titleCn = titleCn;
      _picks = picks;
      _aiNote = aiNote;
      _loading = false;
    });
  }

  /// 「中文(英文)」标题(v2.6):有译名就中英并列,没有就原样英文
  String _displayTitle(String en) {
    final cn = _titleCn[en]?.trim() ?? '';
    if (cn.isEmpty || cn == en) return en;
    return '$cn（$en）';
  }

  /// 打开一条原文:抓正文 → 本地分析 → 入库 → 阅读器
  Future<void> _open(OriginalHit hit) async {
    final source = MaterialSourceService.sourceOf(hit.sourceId);
    if (source == null) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final vocab = context.read<VocabProvider>().vocabularies;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        child: AppLoading(label: '正在抓取并分析原文…'),
      ),
    );
    try {
      final service = MaterialSourceService.instance;
      // v2.11:这里以前写死 `int.parse(hit.sourceId2)` —— 遇到"链接写法"的命中
      // (RSS 列表、AI 点名的作品)会抛 FormatException,用户看到一串英文红字。
      // 统一走 [MaterialSourceService.normalizeSourceId2]:书号从任意写法里抠出来,
      // 抠不到就交给 [fetchDocument],由它给中文提示(它内部也用同一个解析函数)。
      final resolved = MaterialSourceService.normalizeSourceId2(
        hit.sourceId,
        hit.sourceId2,
      );
      final doc = switch (hit.sourceId) {
        'gutenberg' => resolved.isEmpty
            ? await service.fetchDocument(
                hit.sourceId,
                url: hit.url,
                id: hit.sourceId2,
              )
            : await service.fetchGutenberg(int.parse(resolved)),
        'arxiv' => resolved.isEmpty
            ? await service.fetchDocument(
                hit.sourceId,
                url: hit.url,
                id: hit.sourceId2,
              )
            : await service.fetchArxiv(resolved),
        _ => await service.fetchDocument(hit.sourceId, url: hit.url),
      };
      // 标题补成「中文(英文)」再入库(用户第 2(2) 条):书架/阅读器/材料文件夹
      // 三处显示同一个标题,不会一处中文一处英文
      final title = await MaterialImport.localizedTitle(doc.title);
      final ingested = await MaterialLibrary.ingestDoc(
        _retitled(doc, title),
        model: _model,
        vocab: vocab,
      );
      if (!mounted) return;
      nav.pop(); // 关掉 loading
      await nav.push(
        MaterialPageRoute(
          builder: (_) => MaterialReaderScreen(materialId: ingested.materialId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      nav.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('打不开这条原文:$e')),
      );
    }
  }

  /// AI 点名的作品 → 在软件内抓取并打开(v2.7,第 2(1) 条:不能只有外链)
  Future<void> _openPick(Map<String, String> p) async {
    final url = (p['url'] ?? '').trim();
    if (url.isEmpty) return;
    setState(() => _openingPick = p);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final vocab = context.read<VocabProvider>().vocabularies;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        child: AppLoading(label: '正在抓取这份材料…'),
      ),
    );
    try {
      // Gutenberg 书号 / arXiv 编号走专用抓取(能拿到全文或摘要)
      final doc = await MaterialImport.fromAnyUrl(
        url,
        title: p['title_en'] ?? '',
      );
      final title = await MaterialImport.localizedTitle(
        (p['title_en'] ?? '').trim().isEmpty ? doc.title : p['title_en']!,
      );
      final ingested = await MaterialLibrary.ingestDoc(
        _retitled(doc, title),
        model: _model,
        vocab: vocab,
      );
      if (!mounted) return;
      nav.pop();
      await nav.push(
        MaterialPageRoute(
          builder: (_) => MaterialReaderScreen(materialId: ingested.materialId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      nav.pop();
      // 抓不到就给"用浏览器打开"的退路 —— 这正是用户要"链接+软件内呈现"两条路的原因
      messenger.showSnackBar(
        SnackBar(
          content: Text('这份材料在软件内抓不到:$e'),
          action: SnackBarAction(
            label: '用浏览器打开',
            onPressed: () => _openExternalUrl(url),
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingPick = null);
    }
  }

  /// 只换标题(正文与元信息原样)
  MaterialDoc _retitled(MaterialDoc doc, String title) {
    final t = title.trim();
    if (t.isEmpty || t == doc.title.trim()) return doc;
    return MaterialDoc(
      sourceId: doc.sourceId,
      sourceId2: doc.sourceId2,
      kind: doc.kind,
      title: t,
      author: doc.author,
      url: doc.url,
      license: doc.license,
      language: doc.language,
      audioUrl: doc.audioUrl,
      // v2.11:改标题不能把配图丢掉(见 material_import_flow._retitle 的同款注释)
      coverUrl: doc.coverUrl,
      chunks: doc.chunks,
      plainText: doc.plainText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.category),
          actions: [
            // v2.8(用户第 6(5) 条):分类区里的 **AI 对话入口** ——
            // "在每个找材料分类区点击后增加 ai 对话的功能,方便用户自行补充需求、
            //  寻找材料方向"
            IconButton(
              tooltip: '跟 AI 说需求,让它换个方向找',
              onPressed: _loading ? null : _showAiChatSheet,
              icon: const Icon(Icons.forum_outlined),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '资料原文'),
              Tab(text: 'AI 整理编写'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildOriginalTab(theme, muted),
            _buildAiTab(theme, muted),
          ],
        ),
      ),
    );
  }

  /// **AI 对话找材料**(v2.8,用户第 6(5) 条)。
  ///
  /// 不是把用户丢给一个空白搜索框,而是:给几个**可直接点的方向**(像 agent 给选项),
  /// 也可以自己打字;AI 读懂后换检索词重搜,并把"它理解成了什么"显示出来。
  Future<void> _showAiChatSheet() async {
    final ctrl = TextEditingController(text: _queryCtrl.text);
    // 快捷方向:点的都是"改方向"的常见诉求,比自己想词快得多
    const hints = [
      '再简单一点,能读懂就行',
      '换短一点的文章(5 分钟内读完)',
      '不要学术腔,口语一点的',
      '我要能听的材料(带音频)',
      '难度拉高,想挑战一下',
      '换个题材,腻了',
    ];
    final need = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Gap.md,
            0,
            Gap.md,
            Gap.md + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.forum_outlined,
                      size: 18, color: Theme.of(ctx).colorScheme.primary),
                  const SizedBox(width: Gap.xs),
                  Text('跟 AI 说你要什么',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                ],
              ),
              const SizedBox(height: Gap.xxs),
              Text(
                '你说的会进检索方案,AI 换词重找一遍 —— 不用自己想英文关键词。',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.xs,
                runSpacing: Gap.xs,
                children: [
                  for (final h in hints)
                    ActionChip(
                      label: Text(h, style: const TextStyle(fontSize: 12)),
                      onPressed: () => Navigator.pop(ctx, h),
                    ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: ctrl,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '也可以自己写,例如:想读英文笑话,别太长',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
              const SizedBox(height: Gap.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('按这个找'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
    if (need == null || need.trim().isEmpty || !mounted) return;
    _queryCtrl.text = need.trim();
    setState(() {});
    await _search(overrideQuery: need.trim());
  }

  // ── 方向一:资料原文(默认) ──
  Widget _buildOriginalTab(ThemeData theme, Color muted) {
    return ListView(
      padding: Insets.page,
      children: [
        Text(
          '公开源的真实原文:公版书全文、论文、外刊条目 —— '
          '每条都能点开看原文与来源,不是 AI 改写的内容。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
        // 当前生效的偏好(v2.7,第 4/5 条):难度档与偏好摘要直接摊在这里,
        // 用户不用回材料中心也知道"这次是按什么找的"
        if (!_prefs.isEmpty) ...[
          const SizedBox(height: Gap.xs),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Gap.sm, vertical: Gap.xs),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(10),
              borderRadius: Radii.controlRadius,
            ),
            child: Row(
              children: [
                Icon(Icons.tune, size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: Gap.xxs + 2),
                Expanded(
                  child: Text(
                    '按你的偏好找:${_prefs.summary}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      height: 1.4,
                    ),
                  ),
                ),
                Text('在材料中心可改',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: muted, fontSize: 10)),
              ],
            ),
          ),
        ],
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _queryCtrl,
                decoration: const InputDecoration(
                  // v2.6:不再要求用户"用英文搜" —— 中文说需求,AI 去想办法。
                  // v2.7:框里只回填"上次真搜过的词",没有就留空(不再挂画像词)。
                  hintText: '想找什么?中文说就行(例:适合入门的哲学公版书)',
                  isDense: true,
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: Gap.xs),
            FilledButton(
              onPressed: _loading ? null : () => _search(),
              child: Text(_loading ? '搜索中…' : '搜索'),
            ),
          ],
        ),
        // 检索过程:流式时间线(v2.8,用户第 6(4) 条 —— 不再只是一个转圈)
        if (_events.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          SearchTimeline(events: _events, loading: _loading),
        ],
        // AI 规划说明 + AI 直接点名的作品(带「中文(英文)」标题与原文链接)
        if (_aiNote.isNotEmpty || _picks.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          _aiPicksSection(theme, muted),
        ],
        // 每个源的真实情况(v2.5):通了几条 / 为什么没结果 / 上次没连上已跳过
        if (_notes.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          _notesStrip(theme, muted),
        ],
        const SizedBox(height: Gap.sm),
        if (_loading && _hits.isEmpty)
          const AppLoading(label: '正在检索公开源…')
        else if (_hits.isEmpty && _searched && _picks.isEmpty)
          AppEmpty(
            icon: Icons.search_off,
            title: '这次没找到原文',
            hint: '换个说法再试(中文描述需求也行);或用右上角的 AI 对话让它换方向找',
          )
        else ...[
          if (_hits.isNotEmpty) const AppSectionTitle(title: '公开源检索结果'),
          for (var i = 0; i < _hits.length; i++)
            AppStagger(
              index: i,
              child: _buildHitCard(theme, muted, _hits[i]),
            ),
        ],
      ],
    );
  }

  /// AI 规划区(v2.6):一句话说明 + 它点名的作品(中文(英文) + 为什么 + 原文链接)
  Widget _aiPicksSection(ThemeData theme, Color muted) {
    final amber = AppTheme.amber(context);
    return AppCard(
      color: amber.withAlpha(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 15, color: amber),
              const SizedBox(width: Gap.xxs + 2),
              Expanded(
                child: Text(
                  'AI 按你的需求找的',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (_aiNote.isNotEmpty) ...[
            const SizedBox(height: Gap.xxs),
            Text(_aiNote,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: muted, height: 1.5)),
          ],
          for (final p in _picks) ...[
            const SizedBox(height: Gap.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayTitle(p['title_en'] ?? ''),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if ((p['author'] ?? '').isNotEmpty) p['author']!,
                    if ((p['why'] ?? '').isNotEmpty) p['why']!,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: muted, height: 1.4),
                ),
                if ((p['url'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.link, size: 13, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          p['url']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // 第 2(1) 条:AI 点名的作品也要能**在软件内读**,不能只给个链接
                if ((p['url'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: Gap.xxs),
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: _openingPick == p
                            ? null
                            : () => _openPick(p),
                        child: Text(_openingPick == p ? '抓取中…' : '软件内阅读'),
                      ),
                      const SizedBox(width: Gap.xs),
                      TextButton.icon(
                        onPressed: () => _openExternalUrl(p['url']!),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('原文链接'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: Gap.xxs + 2),
          Text(
            '注:链接来自公开源的书目/摘要页;AI 点名的作品若没有把握给准链接,就只给标题。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: muted, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// 用系统浏览器打开外部链接(材料原文的"原文出处")
  Future<void> _openExternalUrl(String url) async {
    try {
      final ok = await launchExternalUrl(url);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打不开这个链接:$url')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开链接失败:$e')),
      );
    }
  }

  /// 各源检索结果说明条:一眼看清"哪个源通/几条/为什么空"
  Widget _notesStrip(ThemeData theme, Color muted) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Gap.sm, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: Radii.controlRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: muted),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final n in _notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(n,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted, fontSize: 11, height: 1.4)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHitCard(ThemeData theme, Color muted, OriginalHit hit) {
    final source = MaterialSourceService.sourceOf(hit.sourceId);
    final kind = MaterialLevel.kindOfSource(hit.sourceId);
    final lv = MaterialLevel.fallbackForKind(kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: AppCard(
        onTap: () => _open(hit),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // v2.8:配图(用户第 6(2) 条"别人都有文章图片")。
            // 公版书用官方封面,RSS 用 media:content,其余程序化封面兜底
            MaterialCover(
              seed: hit.title,
              kind: kind,
              imageUrl: hit.imageUrl,
              width: 88,
              height: 88,
              radius: Radii.control,
              levelLabel: 'Lv$lv',
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_displayTitle(hit.title),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withAlpha(22),
                          borderRadius:
                              BorderRadius.circular(Radii.control - 4),
                        ),
                        child: Text(
                          '原文 · ${source?.label ?? hit.sourceId}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (hit.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(hit.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted, fontSize: 11)),
                  ],
                  const SizedBox(height: 6),
                  // 第 2(1) 条:软件内读 + 原文链接**两条路都给**
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: () => _open(hit),
                        child: const Text('软件内阅读'),
                      ),
                      const SizedBox(width: Gap.xxs),
                      if (hit.url.trim().isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _openExternalUrl(hit.url),
                          icon: const Icon(Icons.open_in_new, size: 15),
                          label: const Text('原文链接'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 方向二:AI 整理编写(明确标注是 AI 产物) ──
  Widget _buildAiTab(ThemeData theme, Color muted) {
    final amber = AppTheme.amber(context);
    return ListView(
      padding: Insets.page,
      children: [
        AppCard(
          color: amber.withAlpha(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: amber),
                  const SizedBox(width: Gap.xxs + 2),
                  Text('这里的内容是 AI 整理/编写的',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: Gap.xs),
              Text(
                '· AI 会按你的水平改写、整理出一份适合现在学的材料;'
                '它不是出版原文,完整度与出处无法像公版书那样考究;\n'
                '· 想要可考证的原文,请用左边的「资料原文」;',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: muted, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AiMaterialSearchScreen(category: widget.category),
            ),
          ),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('让 AI 按我的水平整理一份'),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          '当前基线:${LearnerContext.describeBaseline(_model)}',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}
