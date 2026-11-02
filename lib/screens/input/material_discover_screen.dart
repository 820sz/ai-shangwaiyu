import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/deepseek_api.dart';
import '../../services/input_prefs.dart';
import '../../services/learner_model_store.dart';
import '../../services/material_discovery.dart';
import '../../services/material_library.dart';
import '../../services/original_search.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/material_cover.dart';
import '../../widgets/search_timeline.dart';
import '../../widgets/waiting.dart';
import 'material_reader_screen.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// **AI 按需求找材料**(v3 · 批 2 · C1-3/C1-5/C1-7 的界面)
/// ═══════════════════════════════════════════════════════════════════════
///
/// 用户 2026-11-01 的要求:"AI 找资源、爬材料的能力 …… 做好在 AI 学习软件
/// 这一场景下的个性化、可选择化、具有指导性的运用"。
///
/// 这一页把顺序做成:
/// 1. 先看你现在的需求(目标 / 难度档,可当场改) → 2. 用中文说想要什么 →
/// 3. AI 出检索计划 → 4. 公开源 + DeepSeek 官方搜索一起找 →
/// 5. **抓回正文本地算真实难度** → 6. 每张卡告诉你"为什么推荐它"。
///
/// 与旧"AI 推荐"的区别(旧链路在 `ai_material_search.dart`):
/// - 旧链路让模型**编**推荐清单,难度靠模型嘴上说;这里每条结果都有真实 URL,
///   难度是本地用词频算出来的覆盖率;
/// - 支持 DeepSeek 官方 `/v1/tools/search` + `/v1/tools/fetch`(用户已配 DS
///   官方 Key 时自动启用),能抓到公开源覆盖不到的长尾材料;
/// - 花费可见(官方搜索 5 元/千次成功请求,页面上显示本次约 X 元)。
class MaterialDiscoverScreen extends StatefulWidget {
  /// 进来时预填的需求(例如从某个分类页带过来的题材)
  final String? initialNeed;

  const MaterialDiscoverScreen({super.key, this.initialNeed});

  @override
  State<MaterialDiscoverScreen> createState() => _MaterialDiscoverScreenState();
}

class _MaterialDiscoverScreenState extends State<MaterialDiscoverScreen> {
  final TextEditingController _needCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  LearnerModel _model = LearnerModel();
  InputPreferences _prefs = InputPreferences.load();

  final List<SearchEvent> _events = [];
  bool _running = false;
  bool _opening = false;
  String? _error;
  DiscoveryRun? _run;

  @override
  void initState() {
    super.initState();
    _model = LearnerModelStore.load();
    _prefs = InputPreferences.load();
    if (widget.initialNeed != null && widget.initialNeed!.trim().isNotEmpty) {
      _needCtrl.text = widget.initialNeed!.trim();
    }
  }

  @override
  void dispose() {
    _needCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _stage(String label) {
    if (!mounted) return;
    setState(() {
      _events.add(SearchEvent(stage: SearchStage.searching, label: label));
    });
    // 新事件进来时自动滚到底(时间线是"正在发生什么"的直播)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  /// 检索计划:先用 AI 把中文需求翻成英文检索词(失败/未配置时用本地兜底)。
  Future<List<String>> _planQueries() async {
    final need = _needCtrl.text.trim();
    final fallback = _fallbackQueries(need);
    if (need.isEmpty) return fallback;
    try {
      final api = DeepseekApiService();
      if (!api.isConfigured) return fallback;
      _stage('让 AI 把需求变成检索计划…');
      final plan = await api.planMaterialSearch(
        need,
        category: '其他',
        prefsHint: _prefs.promptHint,
        bandHint: _prefs.band.hintForAi,
      );
      final raw = plan['queries'];
      final queries = <String>[
        if (raw is List)
          for (final q in raw)
            if (q is String && q.trim().isNotEmpty) q.trim(),
      ];
      notesFromPlan = (plan['note'] as String?)?.trim() ?? '';
      if (queries.isNotEmpty) return queries;
      return fallback;
    } catch (e) {
      // AI 规划失败不阻断:直接用用户输入/偏好当检索词,并把原因写进过程说明
      _stage('AI 规划失败($e),改用本地检索词继续找…');
      return fallback;
    }
  }

  /// AI 规划返回的一句中文提示(显示在结果上方)
  String notesFromPlan = '';

  /// 没配置 AI / 规划失败时的本地检索词:用户输入(英文)优先,其次兴趣,最后通用词。
  List<String> _fallbackQueries(String need) {
    final out = <String>[];
    if (need.isNotEmpty && RegExp(r'^[\x20-\x7E]+$').hasMatch(need)) {
      out.add(need);
    }
    for (final interest in _prefs.interests) {
      if (interest.trim().isEmpty) continue;
      if (RegExp(r'^[\x20-\x7E]+$').hasMatch(interest)) out.add(interest.trim());
    }
    for (final goal in _prefs.examGoals) {
      // 考试目标本身搜不到材料,但能当"题材词"用(cet reading 之类在公开源无效,
      // 所以这里只取其中的英文关键词,没有就跳过)
      final m = RegExp(r'[A-Za-z]{3,}').allMatches(goal).map((e) => e.group(0));
      out.addAll(m.whereType<String>());
    }
    if (out.isEmpty) out.add('english reading');
    return out.take(3).toList();
  }

  Future<void> _find() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _run = null;
      _events.clear();
    });
    try {
      // 词库在第一个 await 之前取好:之后 context 可能已失效(页面被 pop)
      final vocab = context.read<VocabProvider>().vocabularies;
      final queries = await _planQueries();
      _stage('检索计划:${queries.join(' / ')}');
      final run = await MaterialDiscovery().discover(
        queries: queries,
        prefs: _prefs,
        model: _model,
        vocab: vocab,
        onEvent: _stage,
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _run = run;
      });
      // 结果出来后回到顶部看"本次找到的内容"
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '$e';
      });
    }
  }

  /// 打开一篇发现结果:把已抓到的正文直接入库(不重新抓一遍),然后进阅读器。
  Future<void> _open(DiscoveredCandidate c) async {
    final content = c.content;
    if (content == null || content.trim().isEmpty) return;
    setState(() => _opening = true);
    try {
      final vocab = context.read<VocabProvider>().vocabularies;
      final ingested = await MaterialLibrary.ingestText(
        title: c.title.trim().isEmpty ? c.url : c.title.trim(),
        text: content,
        model: _model,
        vocab: vocab,
        kind: c.kind,
        url: c.url,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialReaderScreen(materialId: ingested.materialId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开失败:$e')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('按我的需求找材料')),
      body: ListView(
        controller: _scrollCtrl,
        padding: Insets.page,
        children: [
          _buildNeedCard(theme),
          const SizedBox(height: Gap.md),
          _buildSearchCard(theme),
          if (_events.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            SearchTimeline(events: _events, loading: _running),
          ],
          if (_error != null) ...[
            const SizedBox(height: Gap.md),
            AppErrorCard(message: _error!, onRetry: _find),
          ],
          if (_run != null) ...[
            const SizedBox(height: Gap.md),
            _buildRunSummary(theme, _run!),
            const SizedBox(height: Gap.sm),
            if (_run!.isEmpty)
              AppEmptyState(
                icon: Icons.travel_explore_outlined,
                title: '这次没找到合适的材料',
                hint: _run!.notes.isEmpty
                    ? '换个说法,或把难度档放宽一点再试'
                    : _run!.notes.join('\n'),
                action: FilledButton(
                  onPressed: _running ? null : _find,
                  child: const Text('再找一次'),
                ),
              )
            else
              for (var i = 0; i < _run!.items.length; i++)
                AppStagger(
                  index: i,
                  child: _buildResultCard(theme, cs, _run!.items[i]),
                ),
          ],
          if (_opening) ...[
            const SizedBox(height: Gap.md),
            const SkeletonLines(lines: 3),
          ],
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }

  /// 需求卡:目标 + 难度档(可直接改,改完立即影响下一次检索)
  Widget _buildNeedCard(ThemeData theme) {
    final cs = theme.colorScheme;
    final goals = _prefs.examGoals;
    return AppCard(
      variant: AppCardVariant.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: cs.primary),
              const SizedBox(width: Gap.xs),
              Text(
                '我的需求',
                style: AppFont.subheadStyle.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (goals.isNotEmpty)
                Text(
                  goals.take(2).join(' / '),
                  style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              for (final band in DifficultyBand.values)
                ChoiceChip(
                  label: Text(band.label, style: const TextStyle(fontSize: 12)),
                  selected: _prefs.band == band,
                  onSelected: (v) async {
                    if (!v) return;
                    setState(() => _prefs = _prefs.withBand(band));
                    await _prefs.saveBand(band);
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _prefs.band.description,
            style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 输入卡:用中文说想要什么 + 开始找
  Widget _buildSearchCard(ThemeData theme) {
    final cs = theme.colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _needCtrl,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _find(),
            decoration: const InputDecoration(
              hintText: '用中文说你想要什么，例如：\n最近一周的科技新闻，最好有小标题；或者：四六级难度的议论文',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Gap.sm),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _running ? null : _find,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(_running ? '正在找…' : '让 AI 按需求找'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '会先用公开源(公版书/外刊/论文)找,再按你的 DeepSeek 官方 Key 用官方搜索补长尾;'
            '每条结果都会抓回正文算出真实难度。',
            style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant, height: 1.35),
          ),
        ],
      ),
    );
  }

  /// 本次结果摘要:找到几篇、官方搜索花费、过程说明
  Widget _buildRunSummary(ThemeData theme, DiscoveryRun run) {
    final cs = theme.colorScheme;
    final costText = run.searchApiRequests > 0
        ? '官方搜索 ${run.searchApiRequests} 次 · 约 ${run.estimatedCostCny.toStringAsFixed(3)} 元'
        : (run.searchApiAvailable ? '未使用官方搜索' : '官方搜索未配置(只用公开源)');
    return AppCard(
      variant: AppCardVariant.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '找到 ${run.items.length} 篇可读材料',
            style: AppFont.subheadStyle.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            costText,
            style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant),
          ),
          if (notesFromPlan.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              notesFromPlan,
              style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          if (run.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              run.notes.take(4).join(' · '),
              style: AppFont.tagStyle.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 结果卡:封面(类型身份图) + 标题 + **为什么推荐** + 打开
  Widget _buildResultCard(
    ThemeData theme,
    ColorScheme cs,
    DiscoveredCandidate c,
  ) {
    final reason = reasonOf(c, _prefs);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: AppCard(
        variant: AppCardVariant.compact,
        padding: const EdgeInsets.all(Gap.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MaterialCover(
              seed: c.title,
              kind: c.kind,
              imageUrl: c.imageUrl,
              width: 72,
              height: 96,
              levelLabel: c.analysis?.cefr.isNotEmpty == true
                  ? c.analysis!.cefr
                  : null,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.subheadStyle.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reason,
                    style: AppFont.tagStyle.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  if (c.snippet.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      c.snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.tagStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: _opening || c.content == null
                            ? null
                            : () => _open(c),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.md,
                          ),
                        ),
                        child: const Text('开始读'),
                      ),
                      const SizedBox(width: Gap.xs),
                      Text(
                        c.fromSearchApi ? '官方搜索' : '公开源',
                        style: AppFont.tagStyle.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
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
}
