import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../models/learner_model.dart';
import '../../services/database.dart';
import '../../services/deepseek_api.dart';
import '../../services/input_prefs.dart';
import '../../services/learner_model_store.dart';
import '../../services/output_bank.dart';
import '../../services/output_composer.dart';
import '../../services/output_source.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/material_cover.dart';
import '../../widgets/waiting.dart';
import '../review/review_screen.dart';
import 'practice_flow_screen.dart';
import 'word_bank_drill_screen.dart';

/// 出题入口(v3 · 批 3):先选"从哪出题",再进练习器。
///
/// 用户 2026-11-01 的原话:
/// > "翻译练习无法给学习者提供针对性的、符合目标的练题(比如一个四六级考生,
/// >  软件要能提供近几年真题中对应的写作翻译练习、或者新概念教材的回译练习)……
/// >  重点是让 AI 真的能发挥它'爬资料'的能力,然后根据功能逻辑的加工,
/// >  去给用户提供具有针对性的练习材料"
///
/// 所以这一页的两个来源,都是有真实依据的:
/// 1. **你读过的材料**(写句:抽句回译;写段:摘要/续写;写篇:按目标写一篇)——
///    材料和你的阅读进度绑定,这是"输入→输出闭环";
/// 2. **目标考试公开真题**(写篇):用 DeepSeek 官方搜索抓到真题页 → 只基于抓到的
///    正文出题、每题带来源 URL(没来源不生成)。
class PracticeSetupScreen extends StatefulWidget {
  final OutputTier tier;

  const PracticeSetupScreen({super.key, required this.tier});

  @override
  State<PracticeSetupScreen> createState() => _PracticeSetupScreenState();
}

class _PracticeSetupScreenState extends State<PracticeSetupScreen> {
  final OutputComposer _composer = OutputComposer();

  InputPreferences _prefs = InputPreferences.load();
  LearnerModel _model = LearnerModel();

  List<OutputSourceMaterial> _materials = const [];
  bool _loadingMaterials = true;
  bool _busy = false;
  String _busyLabel = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefs = InputPreferences.load();
    _model = LearnerModelStore.load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMaterials());
  }

  Future<void> _loadMaterials() async {
    try {
      final list = await OutputSourceService.recentMaterials(limit: 5);
      if (!mounted) return;
      setState(() {
        _materials = list;
        _loadingMaterials = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMaterials = false);
    }
  }

  String get _levelHint => levelHintOf(_model);

  String get _tierTitle => switch (widget.tier) {
        OutputTier.sentence => '写句 · 中译英回译',
        OutputTier.paragraph => '写段 · 摘要 / 续写 / 观点段',
        OutputTier.essay => '写篇 · 按目标写一篇',
        OutputTier.word => '写词 · 拼写与中译英',
      };

  String get _tierHint => switch (widget.tier) {
        OutputTier.sentence => '两种来源:从你读过的文章抽真实句子,或直接用内置作文范文句',
        OutputTier.paragraph => '两种来源:读完的材料当依据,或内置范文段落做仿写/默写',
        OutputTier.essay => '两种来源:按目标考试抓真题,或用内置真题风格题目按 rubric 练',
        OutputTier.word => '两种来源:复习你的生词本,或按目标练内置考纲/外刊高频词',
      };

  /// 按目标/需求练(内置素材库):不依赖已读材料,离线可用。
  ///
  /// 用户 2026-11-01 的新要求:"输出练习不要局限于和输入闭环……他要考四六级,
  /// 就提供四六级材料练习——考纲词汇、作文范文句子;同理要读外刊就给外刊高频词"。
  /// 所以这里是**自选练习来源**的入口:来源按多选目标排序,也允许没有目标的人练。
  Future<void> _practiceFromSource(OutputPracticeSource source) async {
    if (_busy) return;
    switch (source.tier) {
      case OutputTier.word:
        final pool =
            source.id == 'news_words' ? OutputBank.newsWords : OutputBank.cet4Words;
        final words = OutputBank.pickWords(pool, 10);
        if (words.isEmpty) return;
        await appPush(
          context,
          (_) => WordBankDrillScreen(
            words: words,
            sourceTitle: source.title,
          ),
        );
      case OutputTier.sentence:
        final pairs = List<SentencePair>.of(OutputBank.essaySentences)
          ..shuffle(Random(DateTime.now().millisecondsSinceEpoch));
        await _startBuiltinSet(OutputBank.buildSentenceSet(
          pairs: pairs.take(5).toList(),
          title: source.title,
        ));
      case OutputTier.paragraph:
        final models = List<ParagraphModel>.of(OutputBank.paragraphModels)
          ..shuffle(Random(DateTime.now().millisecondsSinceEpoch));
        await _startBuiltinSet(OutputBank.buildParagraphSet(
          models: models.take(3).toList(),
          title: source.title,
        ));
      case OutputTier.essay:
        final prompts = List<EssayPrompt>.of(OutputBank.essayPrompts)
          ..shuffle(Random(DateTime.now().millisecondsSinceEpoch));
        await _startBuiltinSet(OutputBank.buildEssaySet(
          prompts: prompts.take(1).toList(),
          title: source.title,
        ));
    }
  }

  /// 内置题组直接入库 + 进练习器(不调 AI,不会失败也不会花钱)。
  Future<void> _startBuiltinSet(OutputSetSpec set) async {
    if (!mounted || set.tasks.isEmpty) return;
    final setId = await _saveSet(set);
    if (!mounted) return;
    await appPush(
      context,
      (_) => PracticeFlowScreen(set: set, savedSetId: setId),
    );
  }

  Future<void> _composeFromMaterial(OutputSourceMaterial material) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = 'AI 正在从《${material.title}》出题…';
      _error = null;
    });
    try {
      final set = await _composer.composeFromMaterial(
        materialText: material.text,
        examGoals: _prefs.examGoals,
        levelHint: _levelHint,
        bandHint: _prefs.band.hintForAi,
        tier: widget.tier.id,
        materialId: material.materialId,
        taskCount: widget.tier == OutputTier.sentence ? 5 : 3,
      );
      if (!mounted) return;
      if (set == null || set.tasks.isEmpty) {
        setState(() {
          _busy = false;
          _error = '这次没生成出题目。可以换一篇材料再试，或确认 API Key 已配置。';
        });
        return;
      }
      final setId = await _saveSet(set);
      if (!mounted) return;
      setState(() => _busy = false);
      await appPush(
        context,
        (_) => PracticeFlowScreen(set: set, savedSetId: setId),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '出题失败:$e';
      });
    }
  }

  /// 真题:先弹出"写作 / 翻译"选择,再用官方搜索抓真题页出题。
  Future<void> _composeFromExam() async {
    if (_busy) return;
    final exam = targetExamOf(_prefs.examGoals);
    if (exam == null) {
      setState(() => _error = '先到「我的需求」里选一个考试目标（四六级 / 考研 / 雅思 / 托福 / 新概念），才能按真题出题。');
      return;
    }
    final section = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
              child: Text(
                '练哪种真题？',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('写作真题'),
              subtitle: const Text('按题目要求写一篇（议论文/图表/书信）'),
              onTap: () => Navigator.pop(ctx, 'writing'),
            ),
            ListTile(
              leading: const Icon(Icons.translate),
              title: const Text('翻译真题'),
              subtitle: const Text('段落汉译英'),
              onTap: () => Navigator.pop(ctx, 'translation'),
            ),
            const SizedBox(height: Gap.xs),
          ],
        ),
      ),
    );
    if (section == null || !mounted) return;
    setState(() {
      _busy = true;
      _busyLabel = '正在用 DeepSeek 搜索${examLabelFor(exam)}${sectionLabelFor(section)}…';
      _error = null;
    });
    try {
      final set = await _composer.composeFromExam(
        examType: exam,
        section: section,
        levelHint: _levelHint,
      );
      if (!mounted) return;
      if (set == null || set.tasks.isEmpty) {
        setState(() {
          _busy = false;
          _error = '没抓到可用的真题页面（或没有配 DeepSeek 官方 Key）。'
              '真题检索需要「设置 → API 设置 → 副槽位」填 DeepSeek 官方 Key（sk- 开头）。';
        });
        return;
      }
      final setId = await _saveSet(set);
      if (!mounted) return;
      setState(() => _busy = false);
      await appPush(
        context,
        (_) => PracticeFlowScreen(set: set, savedSetId: setId),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '真题出题失败:$e';
      });
    }
  }

  /// 题组入库(失败返回 0:还能练,只是不进统计)。
  Future<int> _saveSet(OutputSetSpec set) async {
    try {
      return await DatabaseService.insertExerciseSet(
        {
          'source': set.source,
          'exam_type': set.examType,
          'paper_label': '',
          'section': set.section,
          'title': set.title,
          'difficulty_cefr': '',
          'goals_json': jsonEncode(_prefs.examGoals),
          'rubric_id': set.rubricId,
          'material_id':
              set.tasks.isNotEmpty ? set.tasks.first.materialId : null,
          'license_note': set.licenseNote,
          'verify_status': set.verifyStatus,
          'created_at': DateTime.now().toIso8601String(),
        },
        items: [
          for (var i = 0; i < set.tasks.length; i++)
            {
              'idx': i,
              'type': set.tasks[i].type,
              'prompt_zh': set.tasks[i].promptZh,
              'prompt_en': set.tasks[i].promptEn,
              'reference_answer': set.tasks[i].reference,
              'accepted_answers_json': '[]',
              'rubric_id': set.tasks[i].rubricId,
              'ability_tags_json': jsonEncode(set.tasks[i].abilityTags),
              'grammar_points_json': jsonEncode(set.tasks[i].grammarPoints),
              'word_count': set.tasks[i].wordCount,
              'source_span': set.tasks[i].sourceSpan,
              'audio_ref': '',
            },
        ],
      );
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final exam = targetExamOf(_prefs.examGoals);
    return Scaffold(
      appBar: AppBar(title: Text(_tierTitle)),
      body: ListView(
        padding: Insets.page,
        children: [
          AppCard(
            variant: AppCardVariant.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '题目来自你读过的材料',
                  style: AppFont.subheadStyle.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _tierHint,
                  style: AppFont.tagStyle.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (!DeepseekApiService().isConfigured) ...[
            const SizedBox(height: Gap.sm),
            AppCard(
              variant: AppCardVariant.compact,
              color: Theme.of(context).colorScheme.errorContainer.withAlpha(40),
              child: Row(
                children: [
                  Icon(Icons.key_off_outlined,
                      size: 18, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: Text(
                      '还没配置 AI Key：出题与批改都要调用模型。'
                      '去「我的 → API 设置」填好 Key 再回来。',
                      style: AppFont.tagStyle.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // ── 按你的目标练(内置素材库,不依赖已读材料)────────────────
          //
          // 用户 2026-11-01:"输出练习不要局限于和输入闭环……考四六级就提供
          // 四六级的材料练习(考纲词汇、作文范文句子),读外刊就给外刊高频词"。
          // 这里的来源按他的多选目标排序;没有目标的人也能练(通用来源)。
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Text(
                '按你的目标练',
                style: AppFont.metaStyle.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '内置素材 · 离线可用',
                style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          if (widget.tier == OutputTier.word) ...[
            AppCard(
              variant: AppCardVariant.compact,
              onTap: _busy
                  ? null
                  : () => appPush(context, (_) => const ReviewScreen()),
              child: Row(
                children: [
                  Icon(Icons.sync, size: 18, color: cs.primary),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '复习我的生词本',
                          style: AppFont.subheadStyle.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '按 FSRS 到期队列练(读过的材料里收的词)',
                          style: AppFont.tagStyle
                              .copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: cs.outline),
                ],
              ),
            ),
            const SizedBox(height: Gap.xs),
          ],
          for (final src
              in OutputBank.recommendedSources(_prefs.examGoals))
            if (src.tier == widget.tier)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xs),
                child: AppCard(
                  variant: AppCardVariant.compact,
                  onTap: _busy ? null : () => _practiceFromSource(src),
                  child: Row(
                    children: [
                      OutputTierGraphic(
                        tier: switch (src.tier) {
                          OutputTier.word => OutputTierArt.word,
                          OutputTier.sentence => OutputTierArt.sentence,
                          OutputTier.paragraph => OutputTierArt.paragraph,
                          OutputTier.essay => OutputTierArt.essay,
                        },
                        size: 40,
                        showPanel: true,
                        semanticLabel: src.title,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              src.title,
                              style: AppFont.subheadStyle.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              src.description,
                              style: AppFont.tagStyle.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${src.itemCount} 条',
                            style: AppFont.tagStyle.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 18, color: cs.outline),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          if (widget.tier == OutputTier.essay) ...[
            const SizedBox(height: Gap.sm),
            // 真题:需要考试目标 + DeepSeek 官方 Key
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium_outlined,
                          size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          exam == null
                              ? '按目标考试真题练'
                              : '按${examLabelFor(exam)}真题练',
                          style: AppFont.subheadStyle.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    exam == null
                        ? '先在「输入 → 我的需求」或「我的 → 学习偏好」里选考试目标（可多选）。'
                        : (_composer.examSearchAvailable
                            ? '用 DeepSeek 官方搜索抓取公开真题页面，只基于抓到的正文出题，每题标注来源。'
                            : '需要 DeepSeek 官方 Key（设置 → API 设置 → 副槽位，sk- 开头）才能抓真题。'),
                    style: AppFont.tagStyle.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: (_busy || exam == null) ? null : _composeFromExam,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('去抓真题出题'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Text(
                '从你读过的材料出题',
                style: AppFont.metaStyle.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_loadingMaterials)
                Text(
                  '正在读取…',
                  style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          if (_busy) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _busyLabel,
                          style: AppFont.tagStyle.copyWith(color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  const SkeletonLines(lines: 3, seed: 5),
                ],
              ),
            ),
            const SizedBox(height: Gap.xs),
          ],
          if (_error != null) ...[
            AppErrorCard(
              message: _error!,
              onRetry: () => setState(() => _error = null),
            ),
            const SizedBox(height: Gap.xs),
          ],
          if (!_loadingMaterials && _materials.isEmpty)
            AppEmptyState(
              icon: Icons.auto_stories_outlined,
              title: '还没有读过的材料',
              hint: '先去「输入」读一篇材料 —— 输出练习的题目从你读过的内容里出，才有语境。',
              action: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('去输入'),
              ),
            )
          else
            for (final material in _materials)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xs),
                child: AppCard(
                  padding: const EdgeInsets.all(Gap.sm),
                  onTap: _busy ? null : () => _composeFromMaterial(material),
                  child: Row(
                    children: [
                      MaterialCover(
                        seed: material.title,
                        kind: material.kind,
                        width: 56,
                        height: 74,
                        levelLabel:
                            material.cefr.isEmpty ? null : material.cefr,
                      ),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              material.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppFont.subheadStyle.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              describeSources(material),
                              style: AppFont.tagStyle.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: cs.outline),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }
}
