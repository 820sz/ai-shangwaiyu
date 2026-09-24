import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/feed_parser.dart' show FeedItem;
import '../../services/learner_model_store.dart';
import '../../services/material_library.dart';
import '../../services/material_source.dart';
import '../../services/material_source_status.dart';
import '../../services/word_frequency.dart';
import '../../widgets/empty_state.dart';
import 'category_material_screen.dart';
import 'material_reader_screen.dart';

/// 材料中心(v2.0)。
///
/// 定位(用户明确要求):**材料由软件提供渠道,不是让用户上传**。
/// 所以这一页的主入口是"从公开内容源拉真实材料",而不是一个上传框;
/// 粘贴文本只是补充入口(自备材料)。
///
/// 三段:
/// 1. **今日推荐** —— 选源 → 拉该源最新条目 → 逐条"分析并打开"
///    (打开时才抓正文并本地算覆盖率,避免为了排序把整站抓一遍);
/// 2. **材料库** —— 已入库材料(带覆盖率/进度),按 i+1 排序,直接续读;
/// 3. **粘贴导入** —— 自备文本(论文、字幕稿、教材段落)进同一条分析管线。
class MaterialCenterScreen extends StatefulWidget {
  const MaterialCenterScreen({super.key});

  @override
  State<MaterialCenterScreen> createState() => _MaterialCenterScreenState();
}

class _MaterialCenterScreenState extends State<MaterialCenterScreen> {
  /// 源服务只有私有构造(全静态配置 + 无状态抓取),这里按需即用即弃
  final _service = MaterialSourceService.instance;

  /// 默认源:**上次成功过的源** → 没有就用实测可达的 NPR。
  /// (旧实现取 `sources.first` = BBC,在中国大陆必然超时,见
  /// `MaterialSourceService.defaultSourceId` 的说明)
  String _sourceId = MaterialSourceService.defaultSourceId;
  List<FeedItem> _items = const [];
  List<ShelfItem> _shelf = const [];
  bool _loadingShelf = true;
  bool _loadingItems = false;
  String? _error;
  LearnerModel _model = LearnerModel();

  /// 各源最近一次可用性(界面据此标注"上次失败",不让用户一个个试)
  Map<String, SourceHealth> _health = const {};
  bool _probing = false;

  @override
  void initState() {
    super.initState();
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
        _shelf = MaterialLibrary.rankForToday(items);
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
  ///
  /// 为什么值得做:不可达的源每个要等 9~20 秒才失败,用户手动试一圈要一两分钟,
  /// 还未必记得住哪个行。一次探测(串行、逐个记账)之后,chip 上会直接标出结论。
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

  /// 打开一篇源材料:抓正文 → 本地分析 → 入库 → 读前卡 → 阅读器
  Future<void> _openItem(FeedItem item) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final doc = await _service.fetchDocument(_sourceId, url: item.link);
      if (!mounted) return;
      final vocab = context.read<VocabProvider>().vocabularies;
      final ingested = await MaterialLibrary.ingestDoc(
        doc,
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

  /// 读前卡:告诉用户"这份材料对你是什么难度",再决定读不读
  Future<void> _showPreview(IngestedMaterial ingested) async {
    final a = ingested.analysis;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ingested.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _kv('篇幅', '${a.wordCount} 词 · 约 ${a.estMinutes} 分钟'),
              _kv('难度估计', '${a.cefr} · ${a.hint}'),
              _kv('已知词覆盖率',
                  '${(a.knownTokenRatio * 100).toStringAsFixed(1)}%（词形 ${(a.coverage * 100).toStringAsFixed(0)}%）'),
              _kv('生词密度', '每 100 词约 ${a.newWordDensity.toStringAsFixed(1)} 个'),
              if (a.topNewWords.isNotEmpty)
                _kv('先认这几个词', a.topNewWords.take(8).join('、')),
              if (a.tooHard) ...[
                const SizedBox(height: 8),
                const Text(
                  '⚠️ 这份材料对你偏难(覆盖率低于 90%)。可以先读,但建议只精读前几段,别硬啃。',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('先不读'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始读'),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      await _openReader(ingested.materialId);
    }
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            children: [
              TextSpan(
                text: '$k：',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: v,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );

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

  /// 粘贴导入(自备材料)
  Future<void> _importText() async {
    final titleCtrl = TextEditingController();
    final textCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴材料'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: textCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '英文正文',
                  hintText: '论文段落、字幕稿、教材内容都可以',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('分析并入库'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final title = titleCtrl.text.trim();
    final text = textCtrl.text.trim();
    if (title.isEmpty || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题和正文都要填')),
      );
      return;
    }
    try {
      final vocab = context.read<VocabProvider>().vocabularies;
      final ingested = await MaterialLibrary.ingestText(
        title: title,
        text: text,
        model: _model,
        vocab: vocab,
      );
      if (!mounted) return;
      await _showPreview(ingested);
      await _loadShelf();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败:$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('材料中心'),
        actions: [
          IconButton(
            tooltip: '粘贴材料',
            onPressed: _importText,
            icon: const Icon(Icons.content_paste_go),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ── 今日推荐 ──
          Row(
            children: [
              Text('今日推荐',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('公开内容源 · 无需 API Key',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
              TextButton(
                onPressed: _probing ? null : _probeAll,
                child: Text(_probing ? '检测中…' : '检测可用源'),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
          const SizedBox(height: 6),
          // 选中源的说明与状态:一行话讲清"这个源是什么 + 在你这儿行不行",
          // 用户不用点开才知道(旧版只有 chip,失败了才发现不可达)
          _sourceNote(theme, muted),
          const SizedBox(height: 4),
          if (_loadingItems)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _errorCard(theme, muted)
          else if (_items.isEmpty)
            const EmptyState(title: '这个源暂时没有条目')
          else
            for (final item in _items.take(8)) _buildItemCard(theme, item),
          const Divider(height: 32),

          // ── 按你的水平找材料(两个方向:资料原文 / AI 整理)──
          Row(
            children: [
              Text('按你的水平找材料',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('默认找**公开源原文**,AI 整理的内容单独一栏并标注',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildAiDiscoverGrid(theme),
          const Divider(height: 32),

          // ── 材料库 ──
          Row(
            children: [
              Text('材料库',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('按"今天最适合读"排序',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingShelf)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_shelf.isEmpty)
            const EmptyState(title: '还没有材料', hint: '从上面挑一份,或粘贴自备材料')
          else
            for (final s in _shelf) _buildShelfCard(theme, s),
        ],
      ),
    );
  }

  /// 源 chip:选中态 + **可用性标记**(✔ 最近可用 / ⚠ 上次失败 / 未测)。
  /// 标记直接写在 chip 上,因为"哪个源在你这儿能用"是这个页面最贵的信息
  /// (试错一次要等 9~20 秒)。
  Widget _sourceChip(BuildContext context, ThemeData theme, MaterialSource s) {
    final health = _health[s.id];
    final measured = MaterialSourceService.measuredReachable.contains(s.id);
    final IconData? mark = health == null
        ? (measured ? Icons.check_circle_outline : null)
        : (health.ok ? Icons.check_circle : Icons.error_outline);
    final markColor = health == null
        ? theme.colorScheme.onSurfaceVariant
        : (health.ok ? Colors.green : Colors.orange);
    return ChoiceChip(
      avatar: mark == null ? null : Icon(mark, size: 15, color: markColor),
      label: Text(s.label),
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

  /// 选中源的一行说明:它是什么 + 在你这儿最近一次行不行
  Widget _sourceNote(ThemeData theme, Color muted) {
    final s = MaterialSourceService.sourceOf(_sourceId);
    if (s == null) return const SizedBox.shrink();
    final health = _health[s.id];
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.description,
            style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: 2),
        Text(
          health == null
              ? (MaterialSourceService.measuredReachable.contains(s.id)
                  ? '实测可用(2026-09 中国大陆):这个源一直比较稳'
                  : '还没试过这个源 —— 拉不到就换一个,不必纠结')
              : '${health.label(now)}'
                  '${health.ok ? '' : ' —— ${health.message ?? '未知原因'}'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: health != null && !health.ok ? Colors.orange : muted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// 失败卡片:说清"哪个源、为什么、下一步点哪"
  ///
  /// 旧版只有一句"这个源暂时拉不到 + 重试",用户不知道该怪网络还是怪 App,
  /// 也不知道该换哪个源 —— 结果就是"材料中心没法用"。
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_off, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('「$label」这次没拉到',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            const SizedBox(height: 6),
            Text(
              '内容源都在境外,部分网络(含中国大陆多数宽带/移动网络)会连不上 —— '
              '这不是 App 坏了。换个源试试,或点右上角「检测可用源」一次问清。',
              style: theme.textTheme.bodySmall?.copyWith(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _loadItems,
                  child: const Text('重试'),
                ),
                for (final o in others.take(3))
                  ActionChip(
                    label: Text('换到 ${o.label}'),
                    onPressed: () {
                      setState(() => _sourceId = o.id);
                      _loadItems();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 「按你的水平找材料」入口网格(原「其他输入材料」的分类入口并到这里)
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
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: _aiCategoryTile(context, theme, cats[i], icons)),
              if (i + 1 < cats.length) const SizedBox(width: 8),
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
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          // v2.4(D1 用户要求):先让用户选**方向** —— 默认「资料原文」
          // (公开源真实原文,可考究),AI 整理内容单独一栏并明确标注
          builder: (_) => CategoryMaterialScreen(category: category),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(icons[category] ?? Icons.folder,
                size: 24, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text(category,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(ThemeData theme, FeedItem item) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title.isEmpty ? '(无标题)' : item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (item.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                  if (item.published != null) ...[
                    const SizedBox(height: 4),
                    Text(item.published!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted, fontSize: 11)),
                  ],
                ],
              ),
            ),
            TextButton(
              onPressed: () => _openItem(item),
              child: const Text('分析并读'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShelfCard(ThemeData theme, ShelfItem s) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final cov = s.coverage;
    return Card(
      child: ListTile(
        title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${MaterialLibrary.kindLabel(s.kind)} · ${s.wordCount} 词'
          '${s.cefr.isEmpty ? '' : ' · ${s.cefr}'}'
          '${cov == null ? '' : ' · 覆盖 ${(cov * 100).toStringAsFixed(0)}%'}'
          ' · ${s.progressLabel}'
          '${s.pickedWords > 0 ? ' · 已收 ${s.pickedWords} 词' : ''}',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openReader(s.id),
      ),
    );
  }
}

/// 词频表在使用前必须先加载(分析依赖它);这里给一个统一的预热入口,
/// 让调用方(材料中心/阅读器)在打开前调用一次即可。
Future<void> warmUpWordFrequency() => WordFrequency.ensureLoaded();
