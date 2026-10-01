import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../models/learner_model.dart';
import '../../services/learner_context.dart';
import '../../services/learner_model_store.dart';
import '../../widgets/app_ui.dart';
import 'drill_screen.dart';
import '../writing/write_review_screen.dart';
import '../writing/writing_logs_screen.dart';

/// 输出页(v1.8.0 起;v2.8 扩展成"练 + 写"两段)。
///
/// 用户第 7 条原话:"输出功能需增加:词汇拼写、翻译练习、口语交流(等待开放,不着急,
/// 先挂那)—— 每个功能支持按用户目的需求、水平现状,进行提供分类、针对性个性化、
/// 可选择的练习材料,注意 ui"。
///
/// 所以这一页现在分三段:
/// 1. **练什么,先看目标与水平**:顶上一张卡写明"目标 / 水平 / 每天时间"(来自学习者模型),
///    可直接改目标 —— 下面的练习按它组题(目标决定题量与提示强弱);
/// 2. **练**:词汇拼写 / 翻译练习(都基于你生词本里的真实词与句,零等待);
/// 3. **写**:写译批改 / 写译记录(原有);
/// 4. **口语交流**:先挂着(点一下说明为什么还没做,而不是假装能用)。
class OutputHomeScreen extends StatefulWidget {
  const OutputHomeScreen({super.key});

  @override
  State<OutputHomeScreen> createState() => _OutputHomeScreenState();
}

class _OutputHomeScreenState extends State<OutputHomeScreen> {
  LearnerModel _model = LearnerModel();

  /// 目标选项(与访谈、找材料的"目标需求"同一套说法)
  static const List<String> _goalOptions = [
    '四六级',
    '考研',
    '雅思/托福',
    '出国生活',
    '工作/学术',
    '兴趣阅读',
    '看剧看视频',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _model = LearnerModelStore.load());
    });
  }

  Future<void> _pickGoal() async {
    final current = _model.goal?.value ?? '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
              child: Text('你的目标是?(决定练习的题量与难度)',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final g in _goalOptions)
              ListTile(
                dense: true,
                leading: Icon(
                  g == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                title: Text(g),
                onTap: () => Navigator.pop(ctx, g),
              ),
            const SizedBox(height: Gap.xs),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final next = _model.copyWith(
      goal: ProfileField<String>(
        value: picked,
        source: ProfileSource.self,
        confidence: 0.9,
        updatedAt: DateTime.now(),
      ),
    );
    await LearnerModelStore.save(next);
    if (!mounted) return;
    setState(() => _model = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('目标已设为「$picked」—— 下面的练习会按它组题'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final goal = _model.goal?.value ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('输出')),
      body: ListView(
        padding: Insets.page,
        children: [
          // ── ① 目标与水平(可点改)──
          AppStagger(
            index: 0,
            child: AppCard(
              onTap: _pickGoal,
              color: theme.colorScheme.primary.withAlpha(12),
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
                          goal.isEmpty ? '还没设目标 —— 点这里选一个' : '目标:$goal',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Icon(Icons.edit_outlined, size: 15, color: muted),
                    ],
                  ),
                  const SizedBox(height: Gap.xxs),
                  Text(
                    '当前水平:${LearnerContext.describeBaseline(_model)}'
                    '${(_model.dailyMinutes?.value ?? 0) > 0 ? ' · 每天 ${_model.dailyMinutes!.value} 分钟' : ''}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: muted, height: 1.4),
                  ),
                  const SizedBox(height: Gap.xxs),
                  Text(
                    '练习会按这个目标组题(备考类题量更多、提示更少;兴趣类更轻松)。'
                    '目标与水平也能在「学习助理 → 先聊两句」里一次说清。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: muted, fontSize: 11, height: 1.4),
                  ),
                ],
              ),
            ),
          ),

          // ── ② 练 ──
          const AppSectionTitle(
            title: '练',
            subtitle: '用你生词本里的真实词与句出题,点开就能练',
          ),
          AppStagger(
            index: 1,
            child: Row(
              children: [
                Expanded(
                  child: _drillTile(
                    theme,
                    mode: DrillMode.spelling,
                    subtitle: '看中文拼英文',
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: _drillTile(
                    theme,
                    mode: DrillMode.translation,
                    subtitle: '看中文写英文句',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xs),
          // 口语:明确"还没做",不假装能用(用户说"先挂那")
          AppStagger(
            index: 2,
            child: Opacity(
              opacity: 0.72,
              child: AppActionTile(
                icon: Icons.mic_none,
                title: '口语交流(敬请期待)',
                subtitle: '要接实时语音与评分,正在做;先用手写/翻译练习打基础',
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
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('口语交流还在做 —— 需要实时语音与发音评分,'
                          '做不好不上;可以先练拼写与翻译,它们同样能提口语的地基'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ),

          // ── ③ 写 ──
          const AppSectionTitle(
            title: '写',
            subtitle: '写完让 AI 按目标当场批改',
          ),
          AppStagger(
            index: 3,
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
            index: 4,
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

  /// 练习入口方块(两列并排,图标 + 标题 + 一句话)
  Widget _drillTile(
    ThemeData theme, {
    required DrillMode mode,
    required String subtitle,
  }) {
    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DrillScreen(mode: mode)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Icon(mode.icon, size: 21, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: Gap.xs),
          Text(mode.label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              )),
        ],
      ),
    );
  }
}
