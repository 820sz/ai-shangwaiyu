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
import '../../services/material_library.dart';
import '../../services/material_source.dart';
import '../../services/original_search.dart';
import '../../widgets/app_ui.dart';
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

  @override
  void initState() {
    super.initState();
    _model = LearnerModelStore.load();
    _queryCtrl.text = _defaultQuery();
    // v2.5:进来就自动搜一次 —— "打开即行动"(训记的本质):
    // 不再要求用户先想关键词、再点按钮。书籍类不填关键词时取"最受欢迎书单"。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search();
    });
  }

  /// 默认关键词:用户感兴趣的第一个题材;没有就用该分类的默认检索
  String _defaultQuery() {
    final interest = _model.interests?.value;
    if (interest != null && interest.isNotEmpty) return interest.first;
    return OriginalSearch.defaultQueryFor(widget.category);
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  /// 是不是"中文需求"(v2.6):是的话先让 AI 把它变成能搜的东西,
  /// 而不是像以前那样弹一句"请用英文关键词"再把用户顶回去。
  bool get _looksChinese => RegExp(r'[\u4e00-\u9fa5]').hasMatch(_queryCtrl.text);

  Future<void> _search() async {
    final raw = _queryCtrl.text.trim();
    setState(() {
      _loading = true;
      _searched = true;
      _aiNote = '';
    });

    // ── ① AI 规划:中文需求 → 英文检索词 + 直接点名作品(带原文链接)──
    var query = raw;
    var picks = const <Map<String, String>>[];
    var aiNote = '';
    if (_ai.isConfigured && (raw.isEmpty || _looksChinese)) {
      try {
        final plan = await _ai.planMaterialSearch(
          raw.isEmpty ? '${widget.category} 入门 经典' : raw,
          category: widget.category,
          levelHint: LearnerContext.describeBaseline(_model),
        );
        final queries = (plan['queries'] as List?)?.cast<String>() ?? const [];
        picks = (plan['picks'] as List?)
                ?.whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry('$k', '$v')))
                .toList() ??
            const <Map<String, String>>[];
        aiNote = '${plan['note'] ?? ''}';
        if (queries.isNotEmpty) query = queries.first;
      } catch (e) {
        debugPrint('ReadFlow 材料检索规划失败(退回关键词直搜): $e');
      }
    }

    // ── ② 真实检索:拿 AI 给的英文词去公开源里搜真东西 ──
    final result = await OriginalSearch.search(query, category: widget.category);

    // ── ③ 标题中文化:整屏英文没人看得懂(用户第 8(3) 条)──
    var titleCn = const <String, String>{};
    if (_ai.isConfigured && result.hits.isNotEmpty) {
      try {
        titleCn = await _ai.translateTitles(
          result.hits.take(12).map((h) => h.title).toList(),
        );
      } catch (e) {
        debugPrint('ReadFlow 标题中文化失败(保持英文): $e');
      }
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
      builder: (_) => const Dialog(
        child: AppLoading(label: '正在抓取并分析原文…'),
      ),
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
      padding: Insets.page,
      children: [
        Text(
          '公开源的真实原文:公版书全文、论文、外刊条目 —— '
          '每条都能点开看原文与来源,不是 AI 改写的内容。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
        ),
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _queryCtrl,
                decoration: const InputDecoration(
                  // v2.6:不再要求用户"用英文搜" —— 中文说需求,AI 去想办法
                  hintText: '想找什么?中文说就行(例:适合入门的哲学公版书)',
                  isDense: true,
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: Gap.xs),
            FilledButton(
              onPressed: _loading ? null : _search,
              child: Text(_loading ? '搜索中…' : '搜索'),
            ),
          ],
        ),
        // AI 规划说明 + AI 直接点名的作品(带「中文(英文)」标题与原文链接)
        if (_aiNote.isNotEmpty || _picks.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          _aiPicksSection(theme, muted),
        ],
        // 每个源的真实情况(v2.5):通了几条 / 为什么没结果 / 上次没连上已跳过 ——
        // 旧版只有"没有结果"四个字,用户只能得出"这功能没用"
        if (_notes.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          _notesStrip(theme, muted),
        ],
        const SizedBox(height: Gap.sm),
        if (_loading)
          const AppLoading(label: '正在检索公开源…')
        else if (_hits.isEmpty && _searched && _picks.isEmpty)
          AppEmpty(
            icon: Icons.search_off,
            title: '这次没找到原文',
            hint: '换个说法再试(中文描述需求也行);或到材料中心点「检测可用源」看看哪个源通',
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
            InkWell(
              // 有原文链接就点开浏览器/Gutenberg 原文;没有链接则不可点
              onTap: (p['url'] ?? '').isEmpty
                  ? null
                  : () => _openExternalUrl(p['url']!),
              child: Column(
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
                ],
              ),
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
    return AppCard(
      onTap: () => _open(hit),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_displayTitle(hit.title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: Gap.xs),
                // 来源徽章:这条是**真实原文**,来自哪个站 —— 用户最关心的信息
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(24),
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
                  const SizedBox(height: Gap.xxs),
                  Text(hit.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, fontSize: 11)),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gap.xs),
          FilledButton.tonal(
            onPressed: () => _open(hit),
            child: const Text('打开原文'),
          ),
        ],
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
