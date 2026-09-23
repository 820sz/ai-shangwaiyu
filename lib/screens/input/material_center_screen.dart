import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/feed_parser.dart' show FeedItem;
import '../../services/learner_model_store.dart';
import '../../services/material_library.dart';
import '../../services/material_source.dart';
import '../../services/word_frequency.dart';
import '../../widgets/empty_state.dart';
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
  String _sourceId = MaterialSourceService.sources.first.id;
  List<FeedItem> _items = const [];
  List<ShelfItem> _shelf = const [];
  bool _loadingShelf = true;
  bool _loadingItems = false;
  String? _error;
  LearnerModel _model = LearnerModel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _model = LearnerModelStore.load();
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
      if (!mounted) return;
      setState(() {
        _items = items;
        _loadingItems = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingItems = false;
        _error = '$e';
      });
    }
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
              Text('来自公开内容源,无需 API Key',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in MaterialSourceService.sources)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s.label),
                      selected: _sourceId == s.id,
                      onSelected: (_) {
                        setState(() => _sourceId = s.id);
                        _loadItems();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingItems)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off),
                title: const Text('这个源暂时拉不到'),
                subtitle: Text(_error!, maxLines: 3, overflow: TextOverflow.ellipsis),
                trailing: TextButton(
                  onPressed: _loadItems,
                  child: const Text('重试'),
                ),
              ),
            )
          else if (_items.isEmpty)
            const EmptyState(title: '这个源暂时没有条目')
          else
            for (final item in _items.take(8)) _buildItemCard(theme, item),
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
