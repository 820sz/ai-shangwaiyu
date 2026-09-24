import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/learner_model_store.dart';
import '../../services/learner_context.dart';
import '../../services/material_library.dart';
import '../../services/material_source.dart';
import '../../services/original_search.dart';
import '../../widgets/empty_state.dart';
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
  List<OriginalHit> _hits = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  LearnerModel _model = LearnerModel();

  @override
  void initState() {
    super.initState();
    _model = LearnerModelStore.load();
    _queryCtrl.text = _defaultQuery();
  }

  /// 默认关键词:分类名 + 用户感兴趣的题材(有就用,没有就只用分类名)
  String _defaultQuery() {
    final interest = _model.interests?.value;
    if (interest != null && interest.isNotEmpty) return interest.first;
    return widget.category == '其他' ? 'english' : widget.category;
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    final hits = await OriginalSearch.search(q, category: widget.category);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _loading = false;
      _error = hits.isEmpty
          ? '没有检索到原文。可能是关键词太窄,或者这个分类的源在你当前网络下不可达'
              '(可在材料中心点「检测可用源」确认)'
          : null;
    });
  }

  /// 打开一条原文:抓正文 → 本地分析 → 入库 → 读前卡 → 阅读器
  Future<void> _open(OriginalHit hit) async {
    final source = MaterialSourceService.sourceOf(hit.sourceId);
    if (source == null) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final vocab = context.read<VocabProvider>().vocabularies;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final service = MaterialSourceService.instance;
      final doc = switch (hit.sourceId) {
        'gutenberg' => await service.fetchGutenberg(int.parse(hit.sourceId2)),
        'arxiv' => await service.fetchArxiv(hit.sourceId2),
        _ => await service.fetchDocument(hit.sourceId, url: hit.url),
      };
      final ingested = await MaterialLibrary.ingestDoc(
        doc,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.category),
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

  // ── 方向一:资料原文(默认) ──
  Widget _buildOriginalTab(ThemeData theme, Color muted) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          '只搜**公开源的原文**:公版书全文、论文摘要、外刊最新条目 —— '
          '每条都能点开看原文与来源,不是 AI 改写的内容。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _queryCtrl,
                decoration: const InputDecoration(
                  hintText: '搜什么?(书名 / 作者 / 主题)',
                  isDense: true,
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _loading ? null : _search,
              child: Text(_loading ? '搜索中…' : '搜索原文'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_error!,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ),
          )
        else if (_hits.isEmpty && _searched)
          const EmptyState(title: '没有结果', hint: '换个关键词再试')
        else if (_hits.isEmpty)
          const EmptyState(
            title: '输入关键词开始找原文',
            hint: '例如 a christmas carol / climate change / language learning',
          )
        else
          for (final h in _hits) _buildHitCard(theme, muted, h),
      ],
    );
  }

  Widget _buildHitCard(ThemeData theme, Color muted, OriginalHit hit) {
    final source = MaterialSourceService.sourceOf(hit.sourceId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hit.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withAlpha(24),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '原文 · ${source?.label ?? hit.sourceId}',
                          style: TextStyle(
                              fontSize: 10, color: theme.colorScheme.primary),
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
                ],
              ),
            ),
            TextButton(
              onPressed: () => _open(hit),
              child: const Text('打开原文'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 方向二:AI 整理编写(明确标注是 AI 产物) ──
  Widget _buildAiTab(ThemeData theme, Color muted) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Card(
          color: Colors.amber.withAlpha(28),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: Colors.amber[800]),
                    const SizedBox(width: 6),
                    Text('这里的内容是 AI 整理/编写的',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '· AI 会按你的水平改写、整理出一份适合现在学的材料;'
                  '它不是出版原文,完整度与出处无法像公版书那样考究;\n'
                  '· 想要**可考证的原文**,请用左边的「资料原文」;',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 10),
        Text(
          '当前基线:${LearnerContext.describeBaseline(_model)}',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}
