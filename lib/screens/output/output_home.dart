import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/learner_model.dart';
import '../../services/drill_catalog.dart';
import '../../services/drill_planner.dart';
import '../../services/learner_model_store.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/waiting.dart';
import '../writing/write_review_screen.dart';
import '../writing/writing_logs_screen.dart';
import 'drill_plan_screen.dart';
import 'drill_screen.dart';

/// 输出页(v1.8.0 起;v2.9 重做成"练习系统"的入口)。
///
/// 用户 10/2 第 2 条原话:"上次这个功能没做好 —— 词汇拼写、翻译练习、
/// 口语交流(等待开放,不着急,先挂那)—— 每个功能同样的,支持按用户目的需求、
/// 水平现状,进行提供分类、针对性个性化、可选择的练习材料,注意 ui……
/// 词汇练习、翻译练习这些,都要有系统规划、进度追踪,要让用户看得出有完整的
/// 练习方向 —— 而不是现在这种随便给几个词、给几个句子翻译。"
///
/// 所以这一页只做三件事(细节都在练习中心里):
/// 1. **说清"按什么练"**:目标需求(多选)+ 当前水平(软件内数据 + 用户补充),
///    点开进 [DrillPlanScreen] 改;
/// 2. **让方向看得见**:每个练习入口都挂上**当前进度摘要**
///    ("计划第 3/28 天 · 今天已练 10 题 · 正确率 82%"),而不是一个光秃秃的入口;
/// 3. **不假装能用**:口语交流仍然挂着,但把"为什么还没做、要接什么"写清楚 ——
///    用户要的是"先挂那",不是"给个按钮点了没反应"。
class OutputHomeScreen extends StatefulWidget {
  const OutputHomeScreen({super.key});

  @override
  State<OutputHomeScreen> createState() => _OutputHomeScreenState();
}

class _OutputHomeScreenState extends State<OutputHomeScreen> {
  LearnerModel _model = LearnerModel();

  /// 两个练习模式各自的进度摘要(入口卡上要显示)
  final Map<DrillMode, DrillSummary> _summaries = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    final model = LearnerModelStore.load();
    if (mounted) setState(() => _model = model);
    for (final mode in DrillMode.values) {
      final summary = await loadDrillSummary(mode);
      if (!mounted) return;
      setState(() => _summaries[mode] = summary);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openPlan({DrillMode? mode}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrillPlanScreen(initialMode: mode ?? DrillMode.spelling),
      ),
    );
    if (!mounted) return;
    await _load(); // 回来刷新进度(用户可能刚练了一轮)
  }

  /// 练习入口:直接开练(组题的步骤在练习中心/练习页里用真实时间线显示)
  Future<void> _startDrill(DrillMode mode) async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DrillScreen(mode: mode)),
    ).then((_) {
      if (mounted) _load();
    });
  }

  /// 口语交流:说明白"在做什么、为什么还不能用"
  void _explainSpeaking() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final muted = theme.colorScheme.onSurfaceVariant;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mic_none, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: Gap.xs),
                    Text(
                      '口语交流还没开放',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  '这件事做不好不如不做 —— 它至少要接三样东西:',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: Gap.xs),
                for (final line in const [
                  '实时语音(你说一句、它接一句,延迟要低到不打断思路)',
                  '发音评分(音素级:哪个音不准、重音在哪,不能只给个总分)',
                  '按目标出话题(四六级口试 / 雅思 Part 2 / 日常寒暄,题库不同)',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: Gap.xs),
                        Expanded(
                          child: Text(
                            line,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: Gap.xs),
                Text(
                  '在那之前:拼写与翻译练的是"想得起、写得出",这正是口语的地基 —— '
                  '说不出来,多半是先写不出来。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final goals = DrillCatalog.normalizeAll([
      ..._model.goals,
      if ((_model.goal?.value ?? '').isNotEmpty) _model.goal!.value,
    ]);
    final level = DrillPlanner.levelOf(_model);

    return Scaffold(
      appBar: AppBar(
        title: const Text('输出'),
        actions: [
          TextButton.icon(
            onPressed: () => _openPlan(),
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('练习中心'),
          ),
        ],
      ),
      body: ListView(
        padding: Insets.page,
        children: [
          // ── ① 按什么练:目标 + 水平(点开进练习中心改)──
          AppStagger(
            index: 0,
            child: AppCard(
              onTap: () => _openPlan(),
              color: theme.colorScheme.primary.withAlpha(12),
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag_outlined,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: Gap.xs),
                      Expanded(
                        child: Text(
                          goals.isEmpty ? '还没选目标' : '目标:${goals.join(' + ')}',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${level.label}档',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right,
                          size: 18, color: theme.colorScheme.outline),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    goals.isEmpty
                        ? '选目标(可多选)后,练习会按它挑词长与句长 —— 备考偏长词长句,'
                            '生活偏高频短语'
                        : DrillCatalog.resolve(goals)
                            .map((g) => g.what)
                            .take(2)
                            .join(';'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: Gap.xs,
                    children: [
                      _infoPill(
                        theme,
                        Icons.speed,
                        '水平:${level.label}',
                      ),
                      if (_model.hasVocabBaseline)
                        _infoPill(
                          theme,
                          Icons.bar_chart,
                          '词汇量 ${_model.vocabEstimate!.value}',
                        )
                      else
                        _infoPill(
                          theme,
                          Icons.help_outline,
                          '还没测词汇量',
                        ),
                      if ((_model.dailyMinutes?.value ?? 0) > 0)
                        _infoPill(
                          theme,
                          Icons.schedule,
                          '每天 ${_model.dailyMinutes!.value} 分钟',
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    '练习中心里能改目标、补一句自己的水平情况、切三种练法。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── ② 练(每个入口都挂当前进度)──
          AppSectionTitle(
            title: '练',
            subtitle: '用你生词本里的真实词与句出题',
            trailing: TextButton(
              onPressed: () => _openPlan(),
              child: const Text('练习中心'),
            ),
          ),
          for (var i = 0; i < DrillMode.values.length; i++)
            AppStagger(
              index: 1 + i,
              child: _loading
                  ? const AppCard(
                      child: SkeletonLines(lines: 2, withTitle: true, seed: 2),
                    )
                  : _drillTile(theme, muted, DrillMode.values[i]),
            ),

          // ── ③ 口语(先挂着,但说清规划)──
          const SizedBox(height: Gap.xs),
          AppStagger(
            index: 3,
            child: Opacity(
              opacity: 0.75,
              child: AppActionTile(
                icon: Icons.mic_none,
                title: '口语交流(敬请期待)',
                subtitle: '要接实时语音 + 音素级发音评分 + 按目标出话题,做不好不上',
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(Radii.control - 4),
                  ),
                  child: Text('开发中',
                      style: TextStyle(fontSize: 10, color: muted)),
                ),
                onTap: _explainSpeaking,
              ),
            ),
          ),

          // ── ④ 写 ──
          const AppSectionTitle(
            title: '写',
            subtitle: '写完让 AI 按目标当场批改',
          ),
          AppStagger(
            index: 4,
            child: AppActionTile(
              icon: Icons.edit_note,
              title: '写译批改',
              subtitle: '手写 / 电子稿 → AI 批改(按你的目标提要求)',
              highlight: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WriteReviewScreen()),
              ),
            ),
          ),
          AppStagger(
            index: 5,
            child: AppActionTile(
              icon: Icons.history_edu_outlined,
              title: '写译记录',
              subtitle: '按日期查阅与复盘',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WritingLogsScreen()),
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }

  Widget _infoPill(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(160),
        borderRadius: BorderRadius.circular(Radii.control - 3),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 练习入口卡:图标 + 标题 + 一句话 + **当前进度摘要**(用户要"看得出有方向")
  Widget _drillTile(ThemeData theme, Color muted, DrillMode mode) {
    final summary = _summaries[mode] ?? DrillSummary.empty;
    final p = summary.progress;
    final note = summary.note;
    final hasData = summary.stats.hasData;
    return AppCard(
      onTap: () => _startDrill(mode),
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child:
                    Icon(mode.icon, size: 20, color: theme.colorScheme.primary),
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
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (summary.hasPlan)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(18),
                    borderRadius: BorderRadius.circular(Radii.control - 4),
                  ),
                  child: Text(
                    DrillPlanNote.labelOf(note.planMode),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          // 进度摘要:没有计划时给"怎么开始",有计划时给当前状态
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.sm,
              vertical: Gap.xs,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(140),
              borderRadius: Radii.controlRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.hasPlan
                      ? p.summary
                      : (hasData
                          ? '还没定方向 · 已练 ${summary.stats.total} 题'
                          : '还没开始 —— 点「练习中心」定个方向'),
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (hasData) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: summary.hasPlan && p.totalDays > 0
                                ? (p.dayIndex / p.totalDays).clamp(0.0, 1.0)
                                : (p.todayTotal / (p.perDay == 0 ? 10 : p.perDay))
                                    .clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor:
                                theme.colorScheme.outlineVariant.withAlpha(90),
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      Text(
                        p.todayDone
                            ? '今天已达标'
                            : '今天 ${p.todayTotal}/${p.perDay} 题',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: p.todayDone
                              ? AppTheme.successColor(context)
                              : muted,
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      Text(
                        '正确率 ${(summary.stats.accuracy * 100).round()}%',
                        style: TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
