import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/external_link.dart';
import '../../services/feed_parser.dart' show FeedItem;
import '../../services/learner_model_store.dart';
import '../../services/material_library.dart';
import '../../services/material_prefs.dart';
import '../../services/material_source.dart';
import '../../services/material_source_status.dart';
import '../../services/word_frequency.dart';
import '../../widgets/app_ui.dart';
import 'category_material_screen.dart';
import 'material_import_flow.dart';
import 'material_reader_screen.dart';
import 'widgets/material_preview_dialog.dart';

/// 材料中心(v2.0;v2.7 大改)。
///
/// 定位(用户明确要求):**材料由软件提供渠道,不是让用户上传**。
/// 所以这一页的主入口是"从公开内容源拉真实材料",而不是一个上传框。
///
/// v2.7 按用户第 2/4/5 条重做:
/// - **顶部个性化找资源**(第 5 条):难度档 + 内容类型 + 题材倾向 + 补充需求,
///   全部只影响"给 AI 的检索方案",不动用户已有的数据;
/// - **难度自选**(第 4 条):i+1 / i+10 / i+100 既可快速切换,也参与材料库排序与标注,
///   并作为约束交给 AI(`MaterialBand`);
/// - **每条材料都有两条路**(第 2(1) 条):「软件内阅读」+「原文链接」——
///   反爬/需要登录的页面至少还能点开看;
/// - **导入三通道**(第 2(4) 条):粘贴文本 / 文件 / 图片(AI 提取)/ 链接,
///   不再是"只能填标题和正文"。
///
/// 三段:
/// 1. **个性化找资源** → 偏好摘要(点开改);
/// 2. **今日推荐** → 选源 → 拉该源最新条目 → 逐条"分析并打开"(打开时才抓正文);
/// 3. **材料库** → 已入库材料(带覆盖率/进度),按当前难度档排序,直接续读。
class MaterialCenterScreen extends StatefulWidget {
  const MaterialCenterScreen({super.key});

  @override
  State<MaterialCenterScreen> createState() => _MaterialCenterScreenState();
}

class _MaterialCenterScreenState extends State<MaterialCenterScreen> {
  /// 源服务只有私有构造(全静态配置 + 无状态抓取),这里按需即用即弃
  final _service = MaterialSourceService.instance;

  /// 默认源:**上次成功过的源** → 没有就用实测可达的 NPR。
  String _sourceId = MaterialSourceService.defaultSourceId;
  List<FeedItem> _items = const [];
  List<ShelfItem> _shelf = const [];
  bool _loadingShelf = true;
  bool _loadingItems = false;
  String? _error;
  LearnerModel _model = LearnerModel();

  /// 用户偏好(第 4/5 条)
  MaterialPrefs _prefs = MaterialPrefs.empty;

  /// 材料库是否只显示"符合当前难度档"的材料(第 4 条:筛选)
  bool _onlyFit = false;

  /// 各源最近一次可用性(界面据此标注"上次失败",不让用户一个个试)
  Map<String, SourceHealth> _health = const {};
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _prefs = MaterialPrefs.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _model = LearnerModelStore.load();
      _health = MaterialSourceStatus.loadAll();
      _sourceId = MaterialSourceStatus.preferredSourceId(
        knownIds: [for (final s in MaterialSourceService.sources) s.id],
        fallback: MaterialSourceService.defaultSourceId,
        all: _health,
      );
      _loadShelf();
      _loadItems();
    });
  }

  Future<void> _loadShelf() async {
    try {
      final items = await MaterialLibrary.shelf(limit: 50);
      if (!mounted) return;
      setState(() {
        // 排序与筛选都按用户选的难度档(v2.7,第 4 条)
        _shelf = MaterialLibrary.rankForBand(items, _prefs.band);
        _loadingShelf = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingShelf = false);
      debugPrint('材料库读取失败: $e');
    }
  }

  Future<void> _loadItems() async {
    setState(() {
      _loadingItems = true;
      _error = null;
    });
    try {
      final items = await _service.listItems(_sourceId, limit: 12);
      // 成功要记下来:下次打开材料中心直接落在这个源上
      await MaterialSourceStatus.recordOk(_sourceId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loadingItems = false;
        _health = MaterialSourceStatus.loadAll();
      });
    } catch (e) {
      await MaterialSourceStatus.recordFail(_sourceId, e);
      if (!mounted) return;
      setState(() {
        _loadingItems = false;
        _error = '$e';
        _health = MaterialSourceStatus.loadAll();
      });
    }
  }

  /// 挨个探测所有源,把"哪个能用"一次性问清楚。
  Future<void> _probeAll() async {
    setState(() => _probing = true);
    for (final s in MaterialSourceService.sources) {
      try {
        await _service.listItems(s.id, limit: 1);
        await MaterialSourceStatus.recordOk(s.id);
      } catch (e) {
        await MaterialSourceStatus.recordFail(s.id, e);
      }
      if (!mounted) return;
      setState(() => _health = MaterialSourceStatus.loadAll());
    }
    if (!mounted) return;
    setState(() => _probing = false);
    final usable = MaterialSourceService.sources
        .where((s) => _health[s.id]?.ok == true)
        .map((s) => s.label)
        .toList();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(usable.isEmpty
            ? '所有源都连不上 —— 检查网络后重试'
            : '可用源:${usable.join('、')}'),
      ),
    );
  }

  /// 打开一篇源材料:抓正文 → 标题中文化 → 本地分析 → 入库 → 读前卡 → 阅读器
  Future<void> _openItem(FeedItem item) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(child: AppLoading(label: '正在抓取并分析原文…')),
    );
    try {
      final doc = await _service.fetchDocument(_sourceId, url: item.link);
      if (!mounted) return;
      final vocab = context.read<VocabProvider>().vocabularies;
      // 标题补成「中文(英文)」(第 2(2) 条):入库前就定好,书架/阅读器/材料文件夹
      // 三处显示的是同一个标题,不会一处中文一处英文
      final title = await MaterialImportFlow.localizedTitle(doc.title);
      final ingested = await MaterialLibrary.ingestDoc(
        _retitled(doc, title),
        model: _model,
        vocab: vocab,
      );
      if (!mounted) return;
      Navigator.pop(context); // 关掉加载框
      await _showPreview(ingested);
      await _loadShelf();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开失败:$e')),
      );
    }
  }

  /// 只换标题(正文与元信息原样)
  MaterialDoc _retitled(MaterialDoc doc, String title) {
    if (title.trim().isEmpty || title.trim() == doc.title.trim()) return doc;
    return MaterialDoc(
      sourceId: doc.sourceId,
      sourceId2: doc.sourceId2,
      kind: doc.kind,
      title: title.trim(),
      author: doc.author,
      url: doc.url,
      license: doc.license,
      language: doc.language,
      audioUrl: doc.audioUrl,
      chunks: doc.chunks,
      plainText: doc.plainText,
    );
  }

  /// 读前卡:告诉用户"这份材料对你是什么难度",再决定读不读(v2.7 抽到公共件)
  Future<void> _showPreview(IngestedMaterial ingested) async {
    final go = await showMaterialPreview(context, ingested);
    if (go && mounted) await _openReader(ingested.materialId);
  }

  Future<void> _openReader(int materialId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialReaderScreen(materialId: materialId),
      ),
    );
    if (!mounted) return;
    _model = LearnerModelStore.load();
    await _loadShelf();
  }

  /// 导入材料(v2.7,第 2(4) 条):粘贴文本 / 文件 / 图片(AI 提取)/ 链接
  Future<void> _import() async {
    final ingested = await MaterialImportFlow.run(
      context,
      model: _model,
      dialogTitle: '导入材料',
    );
    if (ingested == null || !mounted) return;
    await _showPreview(ingested);
    await _loadShelf();
  }

  /// 用系统浏览器打开原文链接(第 2(1) 条:反爬/付费页面的退路)
  Future<void> _openExternal(String url) async {
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

  Future<void> _setBand(MaterialBand band) async {
    setState(() => _prefs = _prefs.copyWith(band: band));
    await _prefs.save();
    if (!mounted) return;
    await _loadShelf();
  }

  /// 个性化找资源面板(第 5 条):难度 / 类型 / 题材倾向 / 补充需求
  Future<void> _showPrefsSheet() async {
    var draft = _prefs;
    final genresCtrl = TextEditingController(text: _prefs.genres);
    final extraCtrl = TextEditingController(text: _prefs.extra);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final muted = theme.colorScheme.onSurfaceVariant;
          void apply(MaterialPrefs p) => setSheet(() => draft = p);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Gap.md,
                0,
                Gap.md,
                Gap.md + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('个性化找资源',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: Gap.xxs),
                    Text(
                      '这些只影响"让 AI 去找什么样的材料",不会改动你已有的生词与材料。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, height: 1.4),
                    ),
                    const SizedBox(height: Gap.md),

                    // ① 难度
                    Text('难度(i+1 / i+10 / i+100)',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final b in MaterialBand.values)
                          ChoiceChip(
                            label: Text(b.label),
                            selected: draft.band == b,
                            onSelected: (_) =>
                                apply(draft.copyWith(band: b)),
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.xxs),
                    Text(draft.band.description,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted, fontSize: 11)),

                    // ② 内容类型
                    const SizedBox(height: Gap.md),
                    Text('内容类型',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final e in MaterialPrefs.kindLabels.entries)
                          FilterChip(
                            label: Text(e.value),
                            selected: draft.kinds.contains(e.key),
                            onSelected: (on) {
                              final next = {...draft.kinds};
                              if (on) {
                                next.add(e.key);
                              } else {
                                next.remove(e.key);
                              }
                              apply(draft.copyWith(kinds: next));
                            },
                          ),
                      ],
                    ),

                    // ③ 题材倾向
                    const SizedBox(height: Gap.md),
                    TextField(
                      controller: genresCtrl,
                      decoration: const InputDecoration(
                        labelText: '题材倾向(可留空)',
                        hintText: '如:哲学散文、英式幽默、科技新闻',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => apply(draft.copyWith(genres: v)),
                    ),

                    // ④ 补充需求
                    const SizedBox(height: Gap.sm),
                    TextField(
                      controller: extraCtrl,
                      maxLines: 3,
                      minLines: 2,
                      decoration: const InputDecoration(
                        labelText: '补充 / 调整需求(可留空)',
                        hintText: '如:不要学术腔,每篇 10 分钟以内读完',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => apply(draft.copyWith(extra: v)),
                    ),

                    const SizedBox(height: Gap.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => apply(MaterialPrefs.empty),
                            child: const Text('清空偏好'),
                          ),
                        ),
                        const SizedBox(width: Gap.xs),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('保存'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    genresCtrl.dispose();
    extraCtrl.dispose();
    if (saved != true || !mounted) return;
    setState(() => _prefs = draft);
    await _prefs.save();
    if (!mounted) return;
    await _loadShelf();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('偏好已保存 —— 下次找材料会按它来'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 材料库里符合当前档位的条数(摘要行用)
  int get _fitCount {
    if (_prefs.band.isAny) return _shelf.length;
    return _shelf.where((s) {
      final c = s.coverage;
      return c != null && _prefs.band.contains(c);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // 只显示符合档位的(第 4 条:筛选);不限档时不过滤
    final shelf = (_onlyFit && !_prefs.band.isAny)
        ? _shelf.where((s) {
            final c = s.coverage;
            return c == null || _prefs.band.contains(c);
          }).toList()
        : _shelf;
    return Scaffold(
      appBar: AppBar(
        title: const Text('材料中心'),
        actions: [
          IconButton(
            tooltip: '导入材料(文件 / 图片 / 链接 / 粘贴)',
            onPressed: _import,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: ListView(
        padding: Insets.page,
        children: [
          // ── ⓪ 个性化找资源(v2.7,第 5 条 + 第 4 条)──
          AppStagger(index: 0, child: _buildPrefsCard(theme, muted)),

          // ── ① 按你的水平找材料(两个方向:资料原文 / AI 整理)──
          AppStagger(
            index: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionTitle(
                  title: '按你的水平找材料',
                  subtitle: '中文说需求,AI 去公开源找原文;AI 整理的内容单独一栏',
                ),
                _buildAiDiscoverGrid(theme),
              ],
            ),
          ),

          // ── ② 今日推荐 ──
          AppStagger(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionTitle(
                  title: '今日推荐',
                  subtitle: '公开内容源 · 无需 API Key',
                  trailing: TextButton(
                    onPressed: _probing ? null : _probeAll,
                    child: Text(_probing ? '检测中…' : '检测可用源'),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final s in MaterialSourceService.sources)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _sourceChip(context, theme, s),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.xs),
                _sourceNote(theme, muted),
                const SizedBox(height: Gap.sm),
                if (_loadingItems)
                  const AppLoading(label: '正在拉取最新条目…')
                else if (_error != null)
                  _errorCard(theme, muted)
                else if (_items.isEmpty)
                  const AppEmpty(
                    icon: Icons.article_outlined,
                    title: '这个源暂时没有条目',
                    hint: '换一个源试试,或让助手「检测可用源」',
                  )
                else
                  for (final item in _items.take(8)) _buildItemCard(theme, item),
              ],
            ),
          ),

          // ── ③ 材料库 ──
          AppStagger(
            index: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionTitle(
                  title: '材料库',
                  subtitle: _prefs.band.isAny
                      ? '按「今天最适合读」排序'
                      : '按 ${_prefs.band.label} 排序 · 符合 $_fitCount 篇',
                  trailing: _prefs.band.isAny || _shelf.isEmpty
                      ? null
                      : FilterChip(
                          label: const Text('只看符合'),
                          selected: _onlyFit,
                          onSelected: (v) => setState(() => _onlyFit = v),
                        ),
                ),
                if (_loadingShelf)
                  const AppLoading()
                else if (shelf.isEmpty)
                  AppEmpty(
                    icon: Icons.library_books_outlined,
                    title: _onlyFit ? '没有符合 ${_prefs.band.label} 的材料' : '还没有材料',
                    hint: _onlyFit
                        ? '把上面的「只看符合」取消,或换一个难度档'
                        : '从上面挑一份,或点右上角「+」导入自己的材料',
                  )
                else
                  for (final s in shelf) _buildShelfCard(theme, s),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }

  /// 个性化找资源卡(第 5 条):摘要 + 难度档快捷切换
  Widget _buildPrefsCard(ThemeData theme, Color muted) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text('个性化找资源',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (_prefs.activeCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_prefs.activeCount} 项偏好',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              TextButton(
                onPressed: _showPrefsSheet,
                child: const Text('调整'),
              ),
            ],
          ),
          const SizedBox(height: Gap.xxs),
          Text(
            _prefs.summary,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: muted, height: 1.4),
          ),
          const SizedBox(height: Gap.sm),
          // 难度自选(第 4 条):常用档位直接露在外面,点一下立刻影响排序/检索
          Text('难度', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: Gap.xxs),
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              for (final b in MaterialBand.values)
                ChoiceChip(
                  label: Text(b.label),
                  selected: _prefs.band == b,
                  onSelected: (_) => _setBand(b),
                ),
            ],
          ),
          if (!_prefs.band.isAny) ...[
            const SizedBox(height: Gap.xxs),
            Text(
              _prefs.band.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  /// 源 chip:选中态 + **可用性标记**(✔ 最近可用 / ⚠ 上次失败 / 未测)。
  Widget _sourceChip(BuildContext context, ThemeData theme, MaterialSource s) {
    final health = _health[s.id];
    final measured = MaterialSourceService.measuredReachable.contains(s.id);
    final IconData? mark = health == null
        ? (measured ? Icons.check_circle_outline : null)
        : (health.ok ? Icons.check_circle : Icons.error_outline);
    final markColor = health == null
        ? theme.colorScheme.onSurfaceVariant
        : (health.ok
              ? AppTheme.successColor(context)
              : AppTheme.warningColor(context));
    // 偏好里选了类型 → 对应的源排在前面(用户第 5 条:类型偏好要真的起作用)
    final preferred = _prefs.kinds.isEmpty || _prefs.kinds.contains(s.kind);
    return ChoiceChip(
      avatar: mark == null ? null : Icon(mark, size: 15, color: markColor),
      label: Text(preferred ? s.label : '${s.label}(非偏好)'),
      labelStyle: health != null && !health.ok
          ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
          : null,
      selected: _sourceId == s.id,
      onSelected: (_) {
        setState(() => _sourceId = s.id);
        _loadItems();
      },
    );
  }

  /// 选中源的一行说明:它是什么 + 在你这儿最近一次行不行。
  Widget _sourceNote(ThemeData theme, Color muted) {
    final s = MaterialSourceService.sourceOf(_sourceId);
    if (s == null) return const SizedBox.shrink();
    final health = _health[s.id];
    final ok = health?.ok == true;
    final dot = health == null
        ? theme.colorScheme.outlineVariant
        : (ok
              ? AppTheme.successColor(context)
              : AppTheme.warningColor(context));
    final now = DateTime.now();
    final status = health == null
        ? (MaterialSourceService.measuredReachable.contains(s.id)
            ? '实测可用(2026-09 中国大陆):这个源一直比较稳'
            : '还没试过这个源 —— 拉不到就换一个,不必纠结')
        : '${health.label(now)}'
            '${ok ? '' : ' —— ${health.message ?? '未知原因'}'}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: Gap.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.description,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              const SizedBox(height: 2),
              Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: health != null && !ok
                      ? AppTheme.warningColor(context)
                      : muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 失败卡片:说清"哪个源、为什么、下一步点哪"
  Widget _errorCard(ThemeData theme, Color muted) {
    final s = MaterialSourceService.sourceOf(_sourceId);
    final label = s?.label ?? _sourceId;
    final others = MaterialSourceService.sources
        .where((x) => x.id != _sourceId)
        .toList()
      ..sort((a, b) {
        final ah = _health[a.id]?.ok == true ? 0 : 1;
        final bh = _health[b.id]?.ok == true ? 0 : 1;
        return ah.compareTo(bh);
      });
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_off, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text('「$label」这次没拉到',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              FilledButton.tonalIcon(
                onPressed: _loadItems,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(_error!,
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: Gap.xxs),
          Text(
            '内容源都在境外,部分网络(含中国大陆多数宽带/移动网络)会连不上 —— '
            '这不是 App 坏了。换个源试试,或点右上角「检测可用源」一次问清。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: muted, fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: Gap.sm),
          Text('换到哪个源:',
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: Gap.xxs),
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xxs,
            children: [
              for (final o in others.take(3))
                ActionChip(
                  avatar: _health[o.id]?.ok == true
                      ? const Icon(Icons.check_circle, size: 15)
                      : null,
                  label: Text(o.label),
                  onPressed: () {
                    setState(() => _sourceId = o.id);
                    _loadItems();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 「按你的水平找材料」入口网格
  Widget _buildAiDiscoverGrid(ThemeData theme) {
    final cats = AppConstants.learningCategories;
    const icons = <String, IconData>{
      '教材': Icons.school,
      '书籍': Icons.menu_book,
      '外刊': Icons.article,
      '碎片文章': Icons.auto_stories,
      '其他': Icons.folder,
    };
    final rows = <Widget>[];
    for (var i = 0; i < cats.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.xs),
          child: Row(
            children: [
              Expanded(child: _aiCategoryTile(context, theme, cats[i], icons)),
              if (i + 1 < cats.length) const SizedBox(width: Gap.xs),
              if (i + 1 < cats.length)
                Expanded(
                  child: _aiCategoryTile(context, theme, cats[i + 1], icons),
                ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _aiCategoryTile(
    BuildContext context,
    ThemeData theme,
    String category,
    Map<String, IconData> icons,
  ) {
    return InkWell(
      borderRadius: Radii.controlRadius,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CategoryMaterialScreen(category: category),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm, horizontal: Gap.xs),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: Radii.controlRadius,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Icon(icons[category] ?? Icons.folder,
                  size: 20, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: Gap.xs),
            Text(category,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  /// 今日推荐条目卡(v2.7):「分析并读」+「原文链接」两条路
  Widget _buildItemCard(ThemeData theme, FeedItem item) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final link = item.link.trim();
    return AppCard(
      onTap: () => _openItem(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.title.isEmpty ? '(无标题)' : item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          if (item.summary.isNotEmpty) ...[
            const SizedBox(height: Gap.xxs),
            Text(item.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
          if (item.published != null) ...[
            const SizedBox(height: Gap.xxs),
            Text(item.published!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: muted, fontSize: 11)),
          ],
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: () => _openItem(item),
                child: const Text('分析并读'),
              ),
              const SizedBox(width: Gap.xs),
              if (link.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _openExternal(link),
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('原文链接'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 书架卡(v2.7):难度档适配标注 + 原文链接入口
  Widget _buildShelfCard(ThemeData theme, ShelfItem s) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final cov = s.coverage;
    final fit = cov == null ? '' : _prefs.band.fitLabel(cov);
    final meta = '${MaterialLibrary.kindLabel(s.kind)} · ${s.wordCount} 词'
        '${s.cefr.isEmpty ? '' : ' · ${s.cefr}'}'
        '${cov == null ? '' : ' · 覆盖 ${(cov * 100).toStringAsFixed(0)}%'}'
        ' · ${s.progressLabel}'
        '${s.pickedWords > 0 ? ' · 已收 ${s.pickedWords} 词' : ''}';
    return AppCard(
      onTap: () => _openReader(s.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500)),
              ),
              if (fit.isNotEmpty) ...[
                const SizedBox(width: Gap.xxs),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: (fit.startsWith('符合')
                            ? AppTheme.successColor(context)
                            : muted)
                        .withAlpha(26),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    fit,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: fit.startsWith('符合')
                          ? AppTheme.successColor(context)
                          : muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Gap.xxs),
          Text(meta,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: muted, fontSize: 12)),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: () => _openReader(s.id),
                child: const Text('继续读'),
              ),
              const SizedBox(width: Gap.xs),
              // 第 2(1) 条:软件内读与原文链接**都给**,让用户灵活切换
              if (s.url.trim().isNotEmpty)
                TextButton.icon(
                  onPressed: () => _openExternal(s.url),
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('原文链接'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 词频表在使用前必须先加载(分析依赖它);这里给一个统一的预热入口,
/// 让调用方(材料中心/阅读器)在打开前调用一次即可。
Future<void> warmUpWordFrequency() => WordFrequency.ensureLoaded();
