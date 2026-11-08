import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../models/learner_model.dart';
import '../../services/cloze_practice.dart';
import '../../services/database.dart';
import '../../services/deepseek_api.dart';
import '../../services/exam_vocab.dart';
import '../../services/input_prefs.dart';
import '../../services/learner_model_store.dart';
import '../../services/output_bank.dart';
import '../../services/output_composer.dart';
import '../../services/output_source.dart';
import '../../services/sentence_practice.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/art_cover.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/waiting.dart';
import '../review/review_screen.dart';
import 'cloze_practice_screen.dart';
import 'practice_flow_screen.dart';
import 'sentence_practice_screen.dart';
import 'widgets/paper_kit.dart';
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

  /// 按目标记的考纲词表(v3 批 7 P1-3):有目标且 assets 加载成功才出现,
  /// 让"写词"能按四级/六级/考研/雅思/托福分表练,而不是只吃一个四六级精选池。
  String? _examId;
  List<ExamWord> _examWords = const [];

  /// P0-2:等级筛选('' = 跟随学习目标;其余 = 用户在这屏临时指定练哪一级)。
  ///
  /// 为什么要在设置页也放筛选:题库能按 CET-4/CET-6 筛了,但"我要练六级真题"
  /// 这件事必须在**出题入口**就能选,否则用户还是得先改学习目标再回来。
  String _levelOverride = '';

  /// 本次出题实际使用的考试等级(筛选 > 学习目标;识别不出为 null)
  String? get _effectiveExam =>
      _levelOverride.isNotEmpty ? _levelOverride : targetExamOf(_prefs.examGoals);

  @override
  void initState() {
    super.initState();
    _prefs = InputPreferences.load();
    _model = LearnerModelStore.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMaterials();
      _loadExamVocab();
    });
  }

  /// 切等级:立刻按新等级重载考纲词表,并让"按你的目标练"的来源跟着变。
  void _applyLevel(String level) {
    if (level == _levelOverride) return;
    setState(() => _levelOverride = level);
    _loadExamVocab();
  }

  /// 读考纲词表(assets 只读一次,失败静默 —— 没有词表时页面照常可用)。
  Future<void> _loadExamVocab() async {
    try {
      await ExamVocab.ensureLoaded();
      final id = _effectiveExam;
      if (id == null) {
        if (mounted) {
          setState(() {
            _examId = null;
            _examWords = const <ExamWord>[];
          });
        }
        return;
      }
      final words = ExamVocab.wordsFor(id, limit: 400);
      if (!mounted) return;
      setState(() {
        _examId = id;
        _examWords = words;
      });
    } catch (_) {
      // 词表加载失败只是少一条来源,不影响已读材料/内置词表
    }
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
        OutputTier.sentence => '从读过的文章抽句，或内置范文句',
        OutputTier.paragraph => '从材料写段，或内置范文段仿写',
        OutputTier.essay => '按目标抓真题，或内置真题风格题',
        OutputTier.word => '复习生词本，或按目标练考纲词',
      };

  /// 按目标考试词表练词(v3 批 7 P1-3):用 assets 里的考纲词表,
  /// 让四六级/考研/雅思/托福考生能按自己的词表练,而不是只有四六级精选池。
  Future<void> _practiceExamWords() async {
    if (_busy || _examWords.isEmpty) return;
    final pool = <WordBankEntry>[
      for (final w in _examWords) WordBankEntry(w.word, w.zh, w.pos),
    ];
    final words = OutputBank.pickWords(pool, 10);
    if (words.isEmpty) return;
    final label = ExamVocab.examLabels[_examId ?? ''] ?? '考纲';
    await appPush(
      context,
      (_) => WordBankDrillScreen(words: words, sourceTitle: '$label·考纲词'),
    );
  }

  /// 从读过的材料练词(语境选词填空):目标词 = 生词本 ∩ 材料,干扰项取同文真实词。
  ///
  /// 用户核心哲学:"背单词功能必须基于输入输出闭环与材料语境。"
  /// 这是把"背过的词"接回"读过的句子"的桥:生词本没有命中材料时退回考纲精选词
  /// (仍是材料里出现的词,语境不变),不编句子。
  Future<void> _practiceCloze() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = '正在从你读过的材料里挑句子…';
      _error = null;
    });
    try {
      final materials = _materials.isNotEmpty
          ? _materials
          : await OutputSourceService.recentMaterials(limit: 3);
      if (!mounted) return;
      if (materials.isEmpty) {
        setState(() {
          _busy = false;
          _error = '还没有读过的材料。先去「输入」读一篇,再回来练语境填空。';
        });
        return;
      }
      // 目标词优先用生词本(有中文释义、是单词而不是短语/句子)
      final meanings = <String, String>{};
      try {
        final vocab = await DatabaseService.getVocabularies(limit: 500);
        for (final v in vocab) {
          if (v.wordType != 'word') continue;
          final zh = (v.translation ?? '').trim();
          final word = v.word.trim();
          if (word.isEmpty || zh.isEmpty) continue;
          meanings[word] = zh;
        }
      } catch (_) {
        // 生词本读失败就用下面的精选词兜底
      }
      // 生词本为空/没命中时:用考纲精选词作目标词池(仍只在本材料句子里挖空)
      if (meanings.isEmpty) {
        for (final w in [...OutputBank.cet4Words, ...OutputBank.newsWords]) {
          meanings[w.word] = w.meaning;
        }
      }
      final bankWords = <String>[
        for (final w in [...OutputBank.cet4Words, ...OutputBank.newsWords]) w.word,
      ];
      ClozeSet? built;
      for (final material in materials) {
        final candidate = ClozePractice.build(
          materialTitle: material.title,
          materialText: material.text,
          candidateMeanings: meanings,
          poolWords: bankWords,
          count: 6,
        );
        if (candidate.length >= 3) {
          built = candidate;
          break;
        }
      }
      if (!mounted) return;
      if (built == null) {
        setState(() {
          _busy = false;
          _error = '这篇材料里没找到足够的目标词。可以先「按目标练词」积累一些,或换一篇材料。';
        });
        return;
      }
      setState(() => _busy = false);
      await appPush(context, (_) => ClozePracticeScreen(set: built!));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '准备语境填空题失败:$e';
      });
    }
  }

  /// 按目标/需求练(内置素材库):不依赖已读材料,离线可用。
  ///
  /// 用户 2026-11-01 的新要求:"输出练习不要局限于和输入闭环……他要考四六级,
  /// 就提供四六级材料练习——考纲词汇、作文范文句子;同理要读外刊就给外刊高频词"。
  /// 所以这里是**自选练习来源**的入口:来源按多选目标排序,也允许没有目标的人练。
  Future<void> _practiceFromSource(OutputPracticeSource source) async {
    if (_busy) return;
    switch (source.tier) {
      case OutputTier.word:
        // 2026-11-06 二期:四级/六级拆桶 —— 词池优先用考纲词表按等级切分,
        // 词表没加载(离线首屏)再回落内置精选池,保证"点了一定有词"。
        final level = switch (source.id) {
          'cet4_words' => 'cet4',
          'cet6_words' => 'cet6',
          _ => null,
        };
        final pool = level == null
            ? (source.id == 'news_words'
                ? OutputBank.newsWords
                : OutputBank.cet4Words)
            : () {
                final words = OutputBank.wordsForLevel(level);
                return words.isEmpty ? OutputBank.cet4Words : words;
              }();
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
          // 等级跟着设置页筛选走:六级 → cet6_writing,答题页显示六级标准
          examType: _effectiveExam ?? 'none',
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
        // P2-1:入口等级筛选要真正生效(否则筛 CET-6 出题、题库按 CET-6 筛不到)
        examTypeOverride: _effectiveExam,
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
    // P0-2:等级 = 本屏筛选优先,否则取学习目标里更明确的那一个(四六级→cet4 兜底)
    final exam = _effectiveExam;
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
            // P3:题型选择也走纸面件(旧 ListTile 与纸面语言不一致)
            PaperRow(
              leading: Icon(
                Icons.edit_note,
                size: 20,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
              title: '写作真题',
              meta: '按题目要求写一篇（议论文/图表/书信）',
              onTap: () => Navigator.pop(ctx, 'writing'),
            ),
            const SizedBox(height: Gap.xs),
            PaperRow(
              leading: Icon(
                Icons.translate,
                size: 20,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
              title: '翻译真题',
              meta: '段落汉译英',
              onTap: () => Navigator.pop(ctx, 'translation'),
            ),
            const SizedBox(height: Gap.xs),
          ],
        ),
      ),
    );
    if (section == null || !mounted) return;
    // P0-1:年份 / 套数选择。只用于**检索**("按 2023 年第 2 套找页面"),
    // 卷面身份以抓到的页面为准 —— 页面没写年份就只显示来源站点,不拿筛选条件冒充事实。
    final paper = await _pickExamPaper();
    if (paper == null || !mounted) return;
    final paperHint = <String>[
      if (paper.year != null) '${paper.year} 年',
      if (paper.setNo != null) '第 ${paper.setNo} 套',
    ].join();
    setState(() {
      _busy = true;
      _busyLabel =
          '正在用 DeepSeek 搜索$paperHint${examLabelFor(exam)}${sectionLabelFor(section)}…';
      _error = null;
    });
    try {
      final set = await _composer.composeFromExam(
        examType: exam,
        section: section,
        year: paper.year,
        setNo: paper.setNo,
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

  /// 年份 / 套数选择(P0-1)。
  ///
  /// 返回 null = 用户取消。这里的年份套数**只作为检索条件**:
  /// 页面标题/URL 里能抽到真实卷面身份时以页面为准,抽不到就只显示来源站点,
  /// 绝不把"我按 2023 年搜的"伪装成"这套题是 2023 年的"。
  Future<({int? year, int? setNo})?> _pickExamPaper() async {
    final now = DateTime.now().year;
    final years = <int?>[null, for (var y = now; y >= now - 6; y--) y];
    final sets = <int?>[null, 1, 2, 3];
    int? year;
    int? setNo;
    final picked = await showModalBottomSheet<({int? year, int? setNo})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Widget option(
              String label,
              bool selected,
              VoidCallback onTap,
            ) {
              final fg = selected ? cs.onPrimary : cs.onSurfaceVariant;
              return GestureDetector(
                onTap: onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? cs.primary : cs.surface,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(
                      color: selected ? cs.primary : cs.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    label,
                    style: AppFont.tagStyle.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Gap.md, 0, Gap.md, Gap.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '练哪一份真题？',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '年份/套数只用于检索；卷面以抓到的页面为准，页面没写就不猜。',
                      style: AppFont.tagStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    Text(
                      '年份',
                      style: AppFont.tagStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final y in years)
                          option(
                            y == null ? '不限' : '$y 年',
                            year == y,
                            () => setSheetState(() => year = y),
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.md),
                    Text(
                      '套数',
                      style: AppFont.tagStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final s in sets)
                          option(
                            s == null ? '不限' : '第 $s 套',
                            setNo == s,
                            () => setSheetState(() => setNo = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.lg),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(
                          ctx,
                          (year: year, setNo: setNo),
                        ),
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('去抓这几份真题'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return picked;
  }

  /// 题组入库(失败返回 0:还能练,只是不进统计)。
  Future<int> _saveSet(OutputSetSpec set) async {
    try {
      return await DatabaseService.insertExerciseSet(
        {
          'source': set.source,
          'exam_type': set.examType,
          'paper_year': set.paperYear,
          'paper_label': set.paperLabel,
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
    // 纸面:本页所有显式取的色也走纸面主题(否则图标/文字会残留果冻紫)
    final theme = paperThemeOf(context);
    final cs = theme.colorScheme;
    final exam = _effectiveExam;
    final levelLabel = exam == null ? '' : examLabelFor(exam);
    return PaperScaffold(
      topBar: PaperTopBar(eyebrow: '出题来源'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Gap.page, Gap.xs, Gap.page, 120),
        children: [
          // ① 标题区(A 纸面:大标题 + 一句说明;不用彩色头图抢注意力)
          PaperTitle(title: _tierTitle, subtitle: _tierHint),
          const SizedBox(height: Gap.md),
          // P0-2 等级筛选:这一屏选完,真题/考纲词/内置来源都跟着走
          PaperLevelTabs(value: _levelOverride, onChanged: _applyLevel),
          const SizedBox(height: 8),
          Text(
            exam == null
                ? '先在「输入 → 我的需求」选考试目标'
                : '本次按「$levelLabel」出题',
            style: AppFont.tagStyle.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: Gap.lg),
          const PaperSectionHead(
            index: '01',
            title: '按目标练',
          ),
          const SizedBox(height: Gap.sm),
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
                      '未配置 AI Key；去「我的 → API 设置」填写。',
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
          const SizedBox(height: 2),
          if (widget.tier == OutputTier.word) ...[
            // v3 批 7:语境选词填空 —— 用你读过的句子挖空,替之前"只有孤立词卡"的空档
            AppCard(
              variant: AppCardVariant.compact,
              onTap: _busy ? null : _practiceCloze,
              child: Row(
                children: [
                  Icon(Icons.auto_stories_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '从读过的材料练词（语境填空）',
                          style: AppFont.subheadStyle.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '读过的句子挖空，四选一补词',
                          style: AppFont.tagStyle
                              .copyWith(color: cs.onSurfaceVariant, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: cs.outline),
                ],
              ),
            ),
            const SizedBox(height: Gap.xs),
            // 按目标考试词表练(v3 批 7):只有"识别出你的目标 + 词表加载成功"才出现
            if (_examWords.isNotEmpty) ...[
              AppCard(
                variant: AppCardVariant.compact,
                onTap: _busy ? null : _practiceExamWords,
                child: Row(
                  children: [
                    Icon(Icons.school_outlined, size: 18, color: cs.primary),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '按${ExamVocab.examLabels[_examId ?? ''] ?? '考纲'}词表练',
                            style: AppFont.subheadStyle.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '目标词表 ${_examWords.length} 词 · 拼写与中译英',
                            style: AppFont.tagStyle.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.35,
                            ),
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
                          '按到期队列练（FSRS）',
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
          // v3 批 8(P1-5):写句阶三种题型自选 —— 改写/纠错/连词成句,
          // 不再只有"从材料抽句回译"一条路。
          if (widget.tier == OutputTier.sentence) ...[
            for (final mode in const [
              SentencePracticeMode.rewrite,
              SentencePracticeMode.correction,
              SentencePracticeMode.wordOrder,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xs),
                child: AppCard(
                  variant: AppCardVariant.compact,
                  onTap: () => appPush(
                    context,
                    (_) => SentencePracticeScreen(mode: mode),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        switch (mode) {
                          SentencePracticeMode.rewrite =>
                            Icons.auto_fix_high_outlined,
                          SentencePracticeMode.correction => Icons.spellcheck,
                          SentencePracticeMode.wordOrder => Icons.shuffle,
                        },
                        size: 18,
                        color: cs.primary,
                      ),
                      const SizedBox(width: Gap.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mode.label,
                              style: AppFont.subheadStyle.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              switch (mode) {
                                SentencePracticeMode.rewrite => '升级句式或合并从句',
                                SentencePracticeMode.correction => '改回正确英文',
                                SentencePracticeMode.wordOrder => '词块排成一句话',
                              },
                              style: AppFont.tagStyle.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 18, color: cs.outline),
                    ],
                  ),
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                        ? '先在「我的需求」选考试目标'
                        : (_composer.examSearchAvailable
                            ? '用官方搜索抓真题页，只基于正文出题，标注来源。'
                            : '需 DeepSeek 官方 Key（API 设置 → 副槽位）。'),
                    style: AppFont.tagStyle.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    // 次行动样式:整页唯一的主行动在底部固定条,这里不再抢
                    child: PaperPillButton(
                      label: '去抓真题出题',
                      icon: Icons.search,
                      primary: false,
                      onTap: (_busy || exam == null) ? null : _composeFromExam,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Gap.lg),
          PaperSectionHead(
            index: '02',
            title: '从你读过的材料出题',
            trailing: _loadingMaterials
                ? '正在读取…'
                : (_materials.isEmpty ? '' : '${_materials.length} 篇'),
            action: _materials.isEmpty
                ? null
                : TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('去输入'),
                  ),
          ),
          const SizedBox(height: Gap.sm),
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
              hint: '先去「输入」读一篇。',
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
                      ArtCover(
                        title: material.title,
                        kind: material.kind,
                        width: 52,
                        height: 70,
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
                              style: AppFont.metaStyle.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            // 一行元信息:材料名 · CEFR · 覆盖率(超过就省略,
                            // 不在卡里堆三行小字 —— 用户反馈"排版丑"多半来自这里)
                            Text(
                              describeSources(material),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
      // 唯一主行动:按当前阶推"最该点的那个入口"(写词/写句/写段/写篇各不相同)
      bottomBar: _buildBottomAction(context),
    );
  }

  /// 底部主行动(一屏只有一个)。
  ///
  /// 不在这里放"开始练习"这种空话:四阶是**并行**的,每阶的推荐入口不同 ——
  /// 写篇 = 去抓真题;写词 = 按考纲词练;写句/写段 = 练对应内置来源。
  Widget? _buildBottomAction(BuildContext context) {
    final exam = _effectiveExam;
    final recommended = _firstRecommendedSource();
    var label = '开始练习';
    var icon = Icons.play_arrow_rounded;
    VoidCallback? onTap;
    switch (widget.tier) {
      case OutputTier.essay:
        label = exam == null
            ? '去抓真题出题（先选考试目标）'
            : '抓「${examLabelFor(exam)}」真题';
        icon = Icons.workspace_premium_outlined;
        onTap = (_busy || exam == null) ? null : _composeFromExam;
      case OutputTier.word:
        if (_examWords.isNotEmpty) {
          label = '按考纲词练（${_examWords.length} 词）';
          icon = Icons.spellcheck;
          onTap = _busy ? null : _practiceExamWords;
        } else {
          label = '从读过的材料练语境填空';
          icon = Icons.auto_stories_outlined;
          onTap = _busy ? null : _practiceCloze;
        }
      case OutputTier.sentence:
        label = recommended == null ? '回译我的材料' : '练「${recommended.title}」';
        icon = Icons.translate_rounded;
        onTap = (_busy || recommended == null)
            ? null
            : () => _practiceFromSource(recommended);
      case OutputTier.paragraph:
        label = recommended == null ? '从材料写一段' : '练「${recommended.title}」';
        icon = Icons.edit_note_rounded;
        onTap = (_busy || recommended == null)
            ? null
            : () => _practiceFromSource(recommended);
    }
    if (onTap == null) return null;
    return PaperBottomAction(
      child: PaperPillButton(
        label: label,
        icon: icon,
        onTap: onTap,
        expand: true,
      ),
    );
  }

  /// 当前阶的第一个推荐内置来源(没有就返回 null,底部主行动随之隐藏)
  OutputPracticeSource? _firstRecommendedSource() {
    for (final source in OutputBank.recommendedSources(_prefs.examGoals)) {
      if (source.tier == widget.tier) return source;
    }
    return null;
  }
}
