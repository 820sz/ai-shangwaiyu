import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/database.dart';
import '../../services/drill_catalog.dart';
import '../../services/drill_planner.dart';
import '../../services/learner_model_store.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/waiting.dart';
import 'drill_screen.dart';

/// 目标需求选择器(练习中心与输出首页共用一处)。
///
/// 用户原话:"目标需求:四六级/雅思/托福/出国/学术工作/其他,等等哈,你自行想一下
/// 怎么分类,**支持多选**"。
///
/// 交互取舍:
/// - 按族分组(备考/应用/学术/兴趣),8 个 chip 平铺会变成一堵墙;
/// - **点整行切换**选中(不是只有 checkbox 能点 —— 手机上点小方框很难中);
/// - 选中即回写学习者模型 `goals`(不是等"确定"),用户关掉弹层也不会丢选择;
/// - 底部给"明天再看"的一句话说明:目标决定练什么,当场就能看到反馈。
Future<void> showDrillGoalPicker(
  BuildContext context, {
  required LearnerModel model,
  required Future<void> Function(LearnerModel next) onSaved,
}) async {
  final current = <String>{
    ...DrillCatalog.normalizeAll(model.goals),
    if ((model.goal?.value ?? '').isNotEmpty) DrillCatalog.normalize(model.goal!.value),
  };

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      var selected = <String>{...current};
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final muted = theme.colorScheme.onSurfaceVariant;
          Future<void> persist() async {
            final list = DrillCatalog.normalizeAll(selected.toList());
            await onSaved(model.copyWith(
              goals: list,
              // 主目标跟第一个选中项走(兼容旧界面与导师的"目的"字段)
              goal: list.isEmpty
                  ? null
                  : ProfileField<String>(
                      value: list.first,
                      source: ProfileSource.self,
                      confidence: 0.8,
                    ),
              clearGoal: list.isEmpty,
            ));
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.82,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, 2),
                    child: Text(
                      '你要练什么?(可多选)',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
                    child: Text(
                      '目标决定给你练哪些词、多长的句子;多选可以混着练'
                      '(比如同时在备六级又想过雅思)。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, height: 1.4),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                      children: [
                        for (final tag in GoalTag.values) ...[
                          Padding(
                            padding: const EdgeInsets.only(
                              top: Gap.sm,
                              bottom: Gap.xxs,
                            ),
                            child: Text(
                              tag.label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: muted,
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: Gap.xs,
                            runSpacing: Gap.xs,
                            children: [
                              for (final g in DrillCatalog.goals
                                  .where((g) => g.tag == tag))
                                FilterChip(
                                  label: Text(g.label),
                                  selected: selected.contains(g.label),
                                  onSelected: (on) {
                                    setSheet(() {
                                      if (on) {
                                        selected.add(g.label);
                                      } else {
                                        selected.remove(g.label);
                                      }
                                    });
                                    persist();
                                  },
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: Gap.md),
                        // 选中的目标各自"练什么"(让用户知道勾了会发生什么)
                        if (selected.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(Gap.sm),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withAlpha(12),
                              borderRadius: Radii.controlRadius,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final g in DrillCatalog.resolve(
                                    selected.toList()))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.45,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: '${g.label}:',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          TextSpan(
                                            text: g.what,
                                            style: TextStyle(color: muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: Gap.lg),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('好了'),
                      ),
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
}

/// 练习进度摘要(输出首页与练习中心共用同一套数字口径)
class DrillSummary {
  final DrillProgress progress;
  final DrillLogStats stats;
  final DrillPlanNote note;
  final bool hasPlan;

  const DrillSummary({
    required this.progress,
    required this.stats,
    required this.note,
    required this.hasPlan,
  });

  static const DrillSummary empty = DrillSummary(
    progress: DrillProgress(
      doneDays: 0,
      totalDays: 28,
      dayIndex: 0,
      todayTotal: 0,
      perDay: 10,
      todayDone: false,
      remainDays: 28,
      rate: 0,
      streak: 0,
      total: 0,
      accuracy: 0,
    ),
    stats: DrillLogStats.empty,
    note: DrillPlanNote(),
    hasPlan: false,
  );

  /// 顶部一行("计划第 3/28 天 · 今天已练 10 题 · 正确率 82%")
  String get headline => progress.summary;

  bool get practiced => stats.hasData;
}

/// 读取某个练习模式的进度摘要(供输出首页与练习中心复用)。
///
/// 为什么不把这个逻辑塞进 provider:它要读三处数据(drill_plans / drill_logs /
/// learner model),而这三处**只有练习功能**关心 —— 放进全局 provider 会让
/// 无关页面也跟着重建。
Future<DrillSummary> loadDrillSummary(DrillMode mode) async {
  try {
    final plan = await DatabaseService.activeDrillPlan(mode.key);
    final note = decodePlanNote(plan?['level_note'] as String?);
    final logs = await DatabaseService.getDrillLogs(mode: mode.key, limit: 200);
    final stats = DrillPlanner.statsFrom(logs);
    final progressBag = await DatabaseService.drillProgress(mode: mode.key);
    final perDay = (plan?['per_day'] as int?) ??
        DrillPlanner.suggestPerDay(
          goals: note.goals,
          level: note.level,
        );
    final weeks = (plan?['weeks'] as int?) ?? 4;
    final start = DateTime.tryParse('${plan?['start_date'] ?? ''}');
    return DrillSummary(
      progress: DrillPlanner.progressOf(
        progressBag,
        perDay: perDay,
        weeks: weeks,
        startDate: start,
        logStats: stats,
      ),
      stats: stats,
      note: note,
      hasPlan: plan != null,
    );
  } catch (e) {
    debugPrint('ReadFlow 读练习进度失败: $e');
    return DrillSummary.empty;
  }
}

/// 练习中心(v2.9,用户 10/2 第 2 条)。
///
/// 用户原话:"我在备课六级,点进去后,ai 提供功能分区选项 —— 目标需求:…支持多选;
/// 当前水平 —— 软件内数据、用户自行补充…… 词汇练习、翻译练习这些,都要有系统
/// 规划、进度追踪,要让用户看得出有完整的练习方向"。
///
/// 页面结构(自上而下就是用户的决策顺序):
/// 1. **怎么练**:三种模式卡片(跟计划走 / 今日练习包 / 自适应)—— 用户拍板
///    "三种都要,让用户自己选",所以这里不做推荐排序,只把差别写清楚;
/// 2. **练什么**:目标需求多选 chip(来自 [DrillCatalog],单一事实源);
/// 3. **什么水平**:软件内数据(词汇量基线/CEFR/生词数)+ 用户自己补充一句;
/// 4. **练到哪了**:计划进度条(第几天/共几天)、连续打卡、累计题数、正确率、
///    最近 7 次趋势、今日是否达标;没有计划时给"生成 4 周计划";
/// 5. **开始练**:两个入口(词汇拼写 / 翻译练习),点了就走真实步骤的组题时间线。
class DrillPlanScreen extends StatefulWidget {
  /// 进入时默认选中的练习模式(输出首页的入口会带过来)
  final DrillMode initialMode;

  const DrillPlanScreen({super.key, this.initialMode = DrillMode.spelling});

  @override
  State<DrillPlanScreen> createState() => _DrillPlanScreenState();
}

class _DrillPlanScreenState extends State<DrillPlanScreen> {
  LearnerModel _model = LearnerModel();
  DrillMode _mode = DrillMode.spelling;
  DrillPlanNote _note = const DrillPlanNote();
  DrillProgress _progress = DrillSummary.empty.progress;
  DrillLogStats _stats = DrillLogStats.empty;
  bool _hasPlan = false;
  DateTime? _startDate;
  bool _loading = true;

  /// 生成大纲/组题时的真实步骤(有内容时整页显示等待面板)
  bool _busy = false;
  String _busyTitle = '';
  List<AiStep> _steps = const [];

  /// 只练到期词(用户可选:今天只想把复习债还掉)
  bool _onlyDue = false;

  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final model = LearnerModelStore.load();
    if (mounted) {
      setState(() {
        _model = model;
        _noteCtrl.text = '${model.extras['drill_level_note'] ?? ''}';
      });
    }
    // 生词本可能还没加载(用户直接点进「输出」页)
    final vocabs = context.read<VocabProvider>();
    if (vocabs.vocabularies.isEmpty) {
      try {
        await vocabs.loadVocabularies();
      } catch (_) {}
    }
    final summary = await loadDrillSummary(_mode);
    if (!mounted) return;
    final plan = await DatabaseService.activeDrillPlan(_mode.key);
    if (!mounted) return;
    setState(() {
      _note = summary.note.planMode.isEmpty && summary.note.goals.isEmpty
          ? _noteFromModel(model)
          : summary.note;
      _progress = summary.progress;
      _stats = summary.stats;
      _hasPlan = summary.hasPlan;
      _startDate = DateTime.tryParse('${plan?['start_date'] ?? ''}');
      _loading = false;
    });
  }

  /// 没有计划记录时,用学习者模型里的目标 + 水平先把界面填满
  /// (用户看到的是"我填过的目的",而不是空白)
  DrillPlanNote _noteFromModel(LearnerModel model) {
    final goals = DrillCatalog.normalizeAll([
      ...model.goals,
      if ((model.goal?.value ?? '').isNotEmpty) model.goal!.value,
    ]);
    return DrillPlanNote(
      planMode: DrillPlanNote.planPlan,
      goals: goals,
      level: DrillPlanner.levelOf(model),
      userNote: '${model.extras['drill_level_note'] ?? ''}',
    );
  }

  List<String> get _goals {
    final fromNote = _note.goals;
    if (fromNote.isNotEmpty) return fromNote;
    return DrillCatalog.normalizeAll([
      ..._model.goals,
      if ((_model.goal?.value ?? '').isNotEmpty) _model.goal!.value,
    ]);
  }

  DrillLevel get _level => DrillPlanner.levelOf(_model);

  // ═══════════════ 模式切换(写库) ═══════════════

  /// 选练习模式:立刻落库(`level_note` 里存结构化串,见 [encodePlanNote])。
  ///
  /// 为什么**切换模式也要写库**:计划(4 周/每日/自适应)必须跨重启记住 ——
  /// 用户下次进来要接着上次的模式练,而不是每次重新选一遍。
  /// 切模式时旧计划标 `switched` 归档(不是删:历史记录还挂在它下面)。
  Future<void> _pickPlanMode(String planMode) async {
    if (_busy) return;
    final next = DrillPlanNote(
      planMode: planMode,
      goals: _goals,
      level: _level,
      userNote: _noteCtrl.text.trim(),
    );
    setState(() {
      _busy = true;
      _busyTitle = '正在切换练习模式';
      _steps = [
        const AiStep(label: '保存练习模式', state: AiStepState.running),
      ];
    });
    try {
      final old = await DatabaseService.activeDrillPlan(_mode.key);
      if (old != null && old['id'] is int) {
        await DatabaseService.closeDrillPlan(old['id'] as int, status: 'switched');
      }
      final perDay = DrillPlanner.suggestPerDay(goals: next.goals, level: next.level);
      final id = await DatabaseService.createDrillPlan(
        mode: _mode.key,
        goals: next.goals,
        levelNote: encodePlanNote(next),
        weeks: 4,
        perDay: perDay,
        // **沿用原起始日**:换练法不该把"第 11/28 天"打回"第 1/28 天"。
        // 进度条要回答的是"我坚持了多久",换一种练法是换个姿势继续,不是重新开始。
        startDate: _startDate,
      );
      if (!mounted) return;
      setState(() {
        _note = next;
        _hasPlan = id > 0;
        _startDate = _startDate ?? DateTime.now();
        _steps = [
          AiStep(
            label: '保存练习模式',
            state: id > 0 ? AiStepState.done : AiStepState.failed,
            detail: '${DrillPlanNote.labelOf(planMode)} · 每天 $perDay 题',
          ),
        ];
        _busy = false;
      });
      await _refreshProgress();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换到「${DrillPlanNote.labelOf(planMode)}」——'
              '${DrillPlanNote.describeOf(planMode)}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('ReadFlow 切换练习模式失败: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshProgress() async {
    final summary = await loadDrillSummary(_mode);
    if (!mounted) return;
    setState(() {
      _progress = summary.progress;
      _stats = summary.stats;
      _hasPlan = summary.hasPlan;
    });
  }

  /// 生成/重做 4 周计划:每一步都是**真的**(算大纲 → 定题量 → 写库)
  Future<void> _generatePlan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyTitle = '正在生成 4 周计划';
      _steps = const [AiStep(label: '按目标推算每周练什么')];
    });
    final goals = _goals;
    final level = _level;
    final perDay = DrillPlanner.suggestPerDay(goals: goals, level: level);
    final outline = DrillPlanner.planOutline(
      goals: goals,
      weeks: 4,
      perDay: perDay,
      level: level,
    );
    await Future<void>.delayed(const Duration(milliseconds: 620));
    if (!mounted) return;
    setState(() {
      _steps = [
        AiStep(
          label: '按目标推算每周练什么',
          state: AiStepState.done,
          detail: outline.goals,
        ),
        const AiStep(label: '定每日题量与难度', state: AiStepState.running),
      ];
    });
    await Future<void>.delayed(const Duration(milliseconds: 620));
    if (!mounted) return;
    setState(() {
      _steps = [
        ..._steps.take(1),
        AiStep(
          label: '定每日题量与难度',
          state: AiStepState.done,
          detail: '每天 $perDay 题 · ${level.label}',
        ),
        const AiStep(label: '把计划存进你的练习本', state: AiStepState.running),
      ];
    });
    final note = DrillPlanNote(
      planMode: _note.planMode,
      goals: goals,
      level: level,
      userNote: _noteCtrl.text.trim(),
    );
    final old = await DatabaseService.activeDrillPlan(_mode.key);
    if (old != null && old['id'] is int) {
      await DatabaseService.closeDrillPlan(old['id'] as int, status: 'archived');
    }
    final id = await DatabaseService.createDrillPlan(
      mode: _mode.key,
      goals: goals,
      levelNote: encodePlanNote(note),
      weeks: 4,
      perDay: perDay,
      // 目标变了要重排大纲,但**起始日不能重置**:用户是在原计划途中调整方向,
      // 不是开一个新的 28 天(否则进度条永远停在第一天)
      startDate: _startDate ?? DateTime.now(),
    );
    if (!mounted) return;
    setState(() {
      _steps = [
        ..._steps.take(2),
        AiStep(
          label: '把计划存进你的练习本',
          state: id > 0 ? AiStepState.done : AiStepState.failed,
          detail: id > 0
              ? '${DrillPlanner.dateRange(_startDate ?? DateTime.now(), 4)} · 共 28 天'
              : '写入失败,稍后再试',
        ),
      ];
      _note = note;
      _hasPlan = id > 0;
      _startDate ??= DateTime.now();
      _busy = false;
    });
    await _refreshProgress();
  }

  // ═══════════════ 组题 → 开练 ═══════════════

  /// 自适应模式:按最近一次的正确率给出今天的题量与难度。
  ///
  /// **每次现算**(不落库):日志是唯一事实源,而 [DrillPlanner.adaptiveNext]
  /// 保留了几档余量 —— 万一哪天算法改了,历史数据不会带着旧结论一起错。
  DrillAdaptive? get _autoAdvice {
    if (_note.planMode != DrillPlanNote.planAuto) return null;
    if (!_stats.hasData) return null;
    final last = _stats.rates.isEmpty ? 0 : (_stats.rates.last * 100).round();
    return DrillPlanner.adaptiveNext(
      accuracy: last,
      currentPerDay: _progress.perDay,
      level: _level,
    );
  }

  Future<void> _startDrill() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyTitle = '正在按「${DrillCatalog.describe(_goals)}」组题';
      _steps = const [AiStep(label: '准备组题')];
    });
    // 异步前的引用先取出来:await 之后不许再碰 context
    final vocabProvider = context.read<VocabProvider>();
    final navigator = Navigator.of(context);
    final plan = await DatabaseService.activeDrillPlan(_mode.key);
    final planId = plan?['id'] is int ? plan!['id'] as int : null;
    final planMode = _note.planMode;
    final mode = _mode;
    // 题量优先级:只练到期(有多少练多少)> 计划里的 per_day > 自适应建议 > 水平建议
    final limit = _onlyDue
        ? 0
        : ((plan?['per_day'] as int?) ?? (_autoAdvice?.perDay ?? 0));
    try {
      final session = await prepareDrillSession(
        mode: mode,
        goals: _goals,
        level: _level,
        limit: limit,
        planMode: planMode,
        onlyDue: _onlyDue,
        planId: planId,
        vocabProvider: vocabProvider,
        onTick: (steps) {
          if (mounted) setState(() => _steps = steps);
        },
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (session.questions.isEmpty) {
        _showNoMaterial();
        return;
      }
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => DrillScreen(mode: mode, session: session),
        ),
      );
      if (!mounted) return;
      await _refreshProgress();
    } catch (e) {
      debugPrint('ReadFlow 组题失败: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('组题出错了 —— 已经记下,稍后再试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 素材不够时说清"缺什么、去哪儿补",而不是只说"暂无内容"
  void _showNoMaterial() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _onlyDue ? '今天没有到期的词' : '这一步还没有可练的素材',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                _onlyDue
                    ? '复习队列里的词都还没到期 —— 关掉「只练到期词」就能练新词;'
                        '或者去「复习」页把到期的先过一遍。'
                    : _mode.emptyHint,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(height: 1.5),
              ),
              const SizedBox(height: Gap.md),
              if (_onlyDue)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _onlyDue = false);
                      _startDrill();
                    },
                    child: const Text('关掉「只练到期词」再试'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════ 水平补充(用户自己写的说明) ═══════════════

  Future<void> _editLevelNote() async {
    final ctrl = TextEditingController(text: _noteCtrl.text);
    final text = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: Gap.md,
          right: Gap.md,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + Gap.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '补充你的水平情况',
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Gap.xxs),
            Text(
              '软件里的数据(词汇量基线 / CEFR / 生词数)不够用时,自己补一句 —— '
              '比如"六级已过,主攻听力""语法弱,长句看不懂"。练习会按它选材料。',
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(height: 1.5),
            ),
            const SizedBox(height: Gap.sm),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '例如:六级已过,主攻听力与长难句',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Gap.sm),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (text == null || !mounted) return;
    final extras = Map<String, dynamic>.from(_model.extras);
    if (text.isEmpty) {
      extras.remove('drill_level_note');
    } else {
      extras['drill_level_note'] = text;
    }
    final next = _model.copyWith(extras: extras);
    await LearnerModelStore.save(next);
    if (!mounted) return;
    setState(() {
      _model = next;
      _noteCtrl.text = text;
    });
  }

  // ═══════════════ 界面 ═══════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('练习中心'),
        actions: [
          if (!_loading)
            IconButton(
              tooltip: '刷新进度',
              onPressed: _refreshProgress,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _loading
          ? ListView(
              padding: Insets.page,
              children: const [
                // 骨架屏:与真实内容同形状,等待感更短(方案 B)
                AppCard(child: SkeletonLines(lines: 3, seed: 0)),
                AppCard(child: SkeletonLines(lines: 5, seed: 1)),
              ],
            )
          : ListView(
              padding: Insets.page,
              children: [
                if (_busy)
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _busyTitle,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: Gap.xs),
                        AiWaitingTimeline(steps: _steps, running: true),
                      ],
                    ),
                  ),
                _buildModeSection(theme),
                _buildGoalSection(theme),
                _buildLevelSection(theme),
                _buildProgressSection(theme),
                _buildStartSection(theme),
                const SizedBox(height: Gap.lg),
              ],
            ),
    );
  }

  // ① 怎么练
  Widget _buildModeSection(ThemeData theme) {
    return AppStagger(
      index: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: '怎么练',
            subtitle: '三种都能用,随时可切',
          ),
          for (final m in DrillPlanNote.planModes)
            AppCard(
              onTap: () => _pickPlanMode(m.$1),
              color: _note.planMode == m.$1
                  ? theme.colorScheme.primary.withAlpha(16)
                  : null,
              dense: true,
              child: Row(
                children: [
                  Icon(
                    _note.planMode == m.$1
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: _note.planMode == m.$1
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.$2,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _note.planMode == m.$1
                                ? theme.colorScheme.primary
                                : null,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          m.$3,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_note.planMode == m.$1)
                    Icon(Icons.check_circle,
                        size: 16, color: theme.colorScheme.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ② 练什么
  Widget _buildGoalSection(ThemeData theme) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final goals = _goals;
    return AppStagger(
      index: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: '目标需求',
            subtitle: goals.isEmpty ? '还没选' : '已选 ${goals.length} 个',
            trailing: TextButton.icon(
              onPressed: () => showDrillGoalPicker(
                context,
                model: _model,
                onSaved: (next) async {
                  await LearnerModelStore.save(next);
                  if (!mounted) return;
                  setState(() => _model = next);
                  // 目标变了 → 计划要跟着重建(不然进度还挂在旧目标上)
                  if (_hasPlan) await _generatePlan();
                },
              ),
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('选择'),
            ),
          ),
          AppCard(
            onTap: () => showDrillGoalPicker(
              context,
              model: _model,
              onSaved: (next) async {
                await LearnerModelStore.save(next);
                if (!mounted) return;
                setState(() => _model = next);
                if (_hasPlan) await _generatePlan();
              },
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (goals.isEmpty)
                  Text(
                    '点这里选目标(可多选)—— 没选时按「兴趣阅读」的强度练',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  )
                else
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: Gap.xs,
                    children: [
                      for (final g in DrillCatalog.resolve(goals))
                        Chip(
                          label: Text(g.label),
                          avatar: Icon(
                            g.exam ? Icons.school_outlined : Icons.explore_outlined,
                            size: 15,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                const SizedBox(height: Gap.xs),
                Text(
                  DrillCatalog.resolve(goals)
                      .map((g) => g.what)
                      .join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ③ 什么水平
  Widget _buildLevelSection(ThemeData theme) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final vocabCount = context.watch<VocabProvider>().vocabularies.length;
    final level = _level;
    final userNote = _noteCtrl.text;
    return AppStagger(
      index: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: '当前水平',
            subtitle: '软件内数据 + 你自己补充',
            trailing: TextButton.icon(
              onPressed: _editLevelNote,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(userNote.isEmpty ? '补充' : '修改'),
            ),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          level.label,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Text('难度档', style: TextStyle(fontSize: 10.5, color: muted)),
                      ],
                    ),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vocabCount > 0
                                ? '$vocabCount 个生词在练'
                                : '生词本还是空的',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DrillPlanner.describeLevel(_model),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  _model.hasVocabBaseline
                      ? '难度档按你测出来的词汇量算(数据来自软件内测试)。'
                      : '还没测过词汇量,暂按进阶档练 —— 去「我的 → 词汇量测试」量一次会更准。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
                if (userNote.isNotEmpty) ...[
                  const SizedBox(height: Gap.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Gap.xs + 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(12),
                      borderRadius: Radii.controlRadius,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.person_outline,
                            size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '你补充的情况:$userNote',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11.5,
                              height: 1.45,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ④ 练到哪了
  Widget _buildProgressSection(ThemeData theme) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final p = _progress;
    final planMode = _note.planMode;
    final showPlanProgress = planMode != DrillPlanNote.planDaily;
    return AppStagger(
      index: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: '进度追踪',
            subtitle: _stats.hasData
                ? '累计 ${_stats.total} 题 · 正确率 ${(_stats.accuracy * 100).round()}%'
                : '开始第一次练习后就有数据',
            trailing: _hasPlan
                ? TextButton.icon(
                    onPressed: _generatePlan,
                    icon: const Icon(Icons.refresh, size: 15),
                    label: const Text('重做计划'),
                  )
                : null,
          ),
          AppCard(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 计划进度条(只练到期/自适应模式也照样显示"第几天")
                if (showPlanProgress && _hasPlan) ...[
                  Row(
                    children: [
                      Text(
                        '第 ${p.dayIndex}/${p.totalDays} 天',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        _startDate != null
                            ? DrillPlanner.dateRange(_startDate!, 4)
                            : '',
                        style: TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: p.totalDays == 0
                          ? 0
                          : (p.dayIndex / p.totalDays).clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '已完成 ${p.doneDays} 天 · 剩余 ${p.remainDays} 天'
                    '${p.todayDone ? ' · 今天已达标' : ' · 今天还差 ${(p.perDay - p.todayTotal).clamp(0, p.perDay)} 题达标'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: p.todayDone
                          ? AppTheme.successColor(context)
                          : muted,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                ],

                // 三个大数字:连续打卡 / 累计题数 / 正确率
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _bigStat(
                      theme,
                      '${_stats.days}',
                      '打卡天数',
                      AppTheme.amber(context),
                    ),
                    _bigStat(
                      theme,
                      '${_stats.total}',
                      '累计题数',
                      theme.colorScheme.primary,
                    ),
                    _bigStat(
                      theme,
                      _stats.hasData
                          ? '${(_stats.accuracy * 100).round()}%'
                          : '—',
                      '正确率',
                      _stats.accuracy >= 0.85
                          ? AppTheme.successColor(context)
                          : AppTheme.warningColor(context),
                    ),
                  ],
                ),

                // 最近 7 次趋势(自己画 7 根小柱:一眼看出在涨还是在掉)
                if (_stats.rates.isNotEmpty) ...[
                  const SizedBox(height: Gap.md),
                  Row(
                    children: [
                      Icon(Icons.insights, size: 15, color: muted),
                      const SizedBox(width: 6),
                      Text(
                        '最近 ${_stats.rates.length} 次正确率',
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                      const Spacer(),
                      Text(
                        '旧 → 新',
                        style: TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  _TrendBars(rates: _stats.rates),
                ],

                if (!_hasPlan) ...[
                  const SizedBox(height: Gap.sm),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: _generatePlan,
                      icon: const Icon(Icons.auto_awesome, size: 17),
                      label: const Text('生成 4 周计划'),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '按你的目标排出 4 周练什么(每周一个能力面),每天一包题,进度自动记。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],

                // 自适应模式:把"系统打算怎么调"写在明面上(不让用户猜)
                if (_autoAdvice != null) ...[
                  const SizedBox(height: Gap.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Gap.xs + 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(12),
                      borderRadius: Radii.controlRadius,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 15, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _autoAdvice!.note,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 跟计划走时把 4 周大纲摆出来(用户要"看得出有完整的练习方向")
          if (showPlanProgress && _hasPlan) _buildOutline(theme),
        ],
      ),
    );
  }

  Widget _bigStat(ThemeData theme, String value, String label, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 4 周大纲(每周主题 + 本周每天练什么)
  Widget _buildOutline(ThemeData theme) {
    final outline = DrillPlanner.planOutline(
      goals: _goals,
      weeks: 4,
      perDay: _progress.perDay,
      level: _level,
      startDate: _startDate,
    );
    final currentWeek = _progress.dayIndex <= 0
        ? 1
        : ((_progress.dayIndex - 1) ~/ 7 + 1).clamp(1, outline.weeks.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionTitle(
          title: '4 周练什么',
          subtitle: '每周一个能力面,循环加难',
        ),
        for (final w in outline.weeks)
          AppCard(
            dense: true,
            color: w.week == currentWeek
                ? theme.colorScheme.primary.withAlpha(12)
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      w.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: w.week == currentWeek
                            ? theme.colorScheme.primary
                            : null,
                      ),
                    ),
                    const Spacer(),
                    if (w.week == currentWeek)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withAlpha(24),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '本周',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  w.days.map((d) => d.focus).toSet().take(4).join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ⑤ 开始练
  Widget _buildStartSection(ThemeData theme) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final alreadyToday = _progress.todayTotal;
    return AppStagger(
      index: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: '开始练',
            subtitle: '每天 ${_progress.perDay} 题'
                '${alreadyToday > 0 ? ' · 今天已练 $alreadyToday 题' : ''}',
          ),
          // 只练到期词:复习债优先(默认关 —— 只在复习队列很满时才值得开)
          AppCard(
            dense: true,
            color: _onlyDue ? theme.colorScheme.primary.withAlpha(12) : null,
            child: Row(
              children: [
                Icon(
                  _onlyDue ? Icons.alarm_on : Icons.alarm,
                  size: 17,
                  color: _onlyDue
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '只练到期的词',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '把复习队列里今天该复习的词全过一遍',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _onlyDue,
                  onChanged: (v) => setState(() => _onlyDue = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xs),
          for (final mode in DrillMode.values) ...[
            AppCard(
              onTap: () => _startDrillWith(mode),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(Radii.control),
                    ),
                    child: Icon(mode.icon,
                        size: 21, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mode.label,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          mode.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.play_circle_fill,
                      size: 26, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 从指定模式开练(卡片点了先切模式)
  Future<void> _startDrillWith(DrillMode mode) async {
    if (_mode != mode) setState(() => _mode = mode);
    await _startDrill();
  }
}

/// 最近 N 次正确率的小柱状图。
///
/// 为什么不用 fl_chart:7 根定宽小柱不需要坐标系、tooltip、手势,
/// 手写 20 行反而更容易与设计令牌一致(颜色随正确率分档,不是一条单色曲线)。
class _TrendBars extends StatelessWidget {
  final List<double> rates;

  const _TrendBars({required this.rates});

  /// 柱区高度(柱 + 上方数字 = 46)
  static const double _barArea = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 46,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final rate in rates)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${(rate * 100).round()}',
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    // 柱子高度直接与正确率成正比(0% 也留 4px,否则像没数据),
                    // 上不封顶的写法会让"全对"的柱子比"全错"的还短 —— 早期版本
                    // 就是这个 bug(高度算了 (46-18)*rate,满分只有 28px)
                    height: _barArea * rate.clamp(0.0, 1.0) + 4,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: rate >= 0.85
                          ? AppTheme.successColor(context)
                          : (rate >= 0.6
                              ? theme.colorScheme.primary
                              : AppTheme.warningColor(context)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 练习中心里"当前进度"的一行摘要(输出首页用同一套口径)
String drillSummaryLine(DrillSummary summary) => summary.progress.summary;
