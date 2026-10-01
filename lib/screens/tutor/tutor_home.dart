import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/learner_model.dart';
import '../../models/material_recommendation.dart' show LearnerProfile;
import '../../providers/stats_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../services/database.dart';
import '../../services/learner_model_store.dart';
import '../../services/learner_snapshot_loader.dart';
import '../../services/tutor_engine.dart';
import '../../services/widget_service.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/bottom_nav.dart';
import '../input/learner_preferences_screen.dart';
import '../review/review_screen.dart';
import 'placement_test_screen.dart';
import 'tutor_chat_screen.dart';
import 'tutor_interview_screen.dart';

/// 导师页(v2.0,v1 版本)。
///
/// 与 v1.9 之前"AI 学习建议"的根本区别:
/// 1. **结论本地算**:[TutorEngine] 用规则把数据变成"发现 + 依据 + 动作",
///    每条都能在界面上指到具体数字(不是让模型自由发挥);
/// 2. **有任务卡**:今天做什么、多少分钟、点一下就到对应功能,
///    任务落库(tutor_tasks),做完了能打勾回填;
/// 3. **能对话**:会话上下文里带着结构化证据包,并明确要求模型
///    "优先遵守本地结论、不要编造";对话也落库(tutor_messages);
/// 4. **缺什么问什么**:画像缺口直接变成可点选的小表单,选完写回模型。
class TutorHomeScreen extends StatefulWidget {
  const TutorHomeScreen({super.key});

  @override
  State<TutorHomeScreen> createState() => _TutorHomeScreenState();
}

class _TutorHomeScreenState extends State<TutorHomeScreen> {
  LearnerModel _model = LearnerModel();
  LearnerSnapshot? _snapshot;
  List<Map<String, Object?>> _taskRows = const [];
  final Set<int> _doneTaskIds = {};

  /// 最近一条对话摘要(v2.4:对话搬到独立窗口,这里只做入口卡副标题)
  String _lastChatLine = '';

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // P2-10:进页立刻返回时 element 已 deactivate,不加这道判断会抛错
      if (!mounted) return;
      _model = LearnerModelStore.load();
      _refresh();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 重新组装快照 + 今日任务 + 会话历史
  Future<void> _refresh() async {
    try {
      final vocab = context.read<VocabProvider>().vocabularies;
      final logs = context.read<StatsProvider>().dailyLogs;
      final snap = await LearnerSnapshotLoader.load(
        vocab: vocab,
        dailyLogs: logs,
      );

      // 今日任务:没有就按诊断生成一次并落库(每天一份,不覆盖已有)
      var rows = await DatabaseService.getTutorTasks(snap.now);
      if (rows.isEmpty) {
        for (final t in TutorEngine.planTasks(snap)) {
          await DatabaseService.insertTutorTask(
            planDate: snap.now,
            kind: t.kind,
            title: t.title,
            targetMinutes: t.targetMinutes,
            payload: {
              'reason': t.reason,
              'jump': t.jump?.name,
              'jumpArg': t.jumpArg,
            },
          );
        }
        rows = await DatabaseService.getTutorTasks(snap.now);
      }

      final msgs = await DatabaseService.getTutorMessages(limit: 20);
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _taskRows = rows;
        // 只留最后一条做入口卡副标题(完整对话在独立窗口里)
        _lastChatLine =
            msgs.isEmpty ? '' : '${msgs.last['content'] ?? ''}'.replaceAll('\n', ' ');
        _loading = false;
      });
      // 桌面小组件显示的就是这里刚算出来的"今天该做什么",顺手推一次 ——
      // 不 await:面板已经画好了,小组件晚半秒无所谓,卡住反而不该
      WidgetService.sync();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('诊断数据读取失败:$e')),
      );
    }
  }

  // ── 跳转 ──
  void _jump(TutorAction? action, [String? arg]) {
    switch (action) {
      case null:
        return;
      case TutorAction.placementTest:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PlacementTestScreen(full: false),
          ),
        ).then((_) {
          if (!mounted) return;
          _model = LearnerModelStore.load();
          _refresh();
        });
      case TutorAction.review:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReviewScreen()),
        );
      case TutorAction.materialCenter:
      case TutorAction.continueReading:
      case TutorAction.listening:
        AppTabs.maybeOf(context)?.switchTo(ReadFlowTab.input);
      case TutorAction.writing:
      case TutorAction.backTranslation:
        AppTabs.maybeOf(context)?.switchTo(ReadFlowTab.output);
      case TutorAction.profile:
        AppTabs.maybeOf(context)?.switchTo(ReadFlowTab.profile);
    }
  }

  /// 任务打勾回填(落库 done_at;失败不静默)
  Future<void> _completeTask(Map<String, Object?> row) async {
    final id = row['id'];
    if (id is! int) return;
    try {
      await DatabaseService.completeTutorTask(id);
      if (!mounted) return;
      setState(() => _doneTaskIds.add(id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('标记失败:$e')),
      );
    }
  }

  /// 取消完成(v2.4,A5):勾选要能来回切换 ——
  /// 用户实测"划去任务后没法再点回来"(旧实现完成态按钮直接 disabled)
  Future<void> _reopenTask(Map<String, Object?> row) async {
    final id = row['id'];
    if (id is! int) return;
    try {
      await DatabaseService.reopenTutorTask(id);
      if (!mounted) return;
      setState(() => _doneTaskIds.remove(id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取消失败:$e')),
      );
    }
  }

  // ── 导师会话 ──
  // v2.4(C1 用户要求):对话搬进独立窗口 [TutorChatScreen] ——
  // 这一页不再内嵌聊天(输入框/气泡/流式接收全部移过去),
  // 只保留"今天做什么 + 诊断 + 入口卡"。系统提示与证据包也一并搬走,
  // 避免两处各写一份、说法不一致。

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final snap = _snapshot;
    if (snap == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('诊断数据暂时读不到'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _refresh, child: const Text('重试')),
          ],
        ),
      );
    }
    final findings = TutorEngine.diagnose(snap);

    return Scaffold(
      appBar: AppBar(
        title: const Text('学习助理'),
        actions: [
          IconButton(
            tooltip: '不想看的题材',
            onPressed: _openPreferences,
            icon: const Icon(Icons.block),
          ),
          IconButton(
            tooltip: '重新诊断',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: Insets.page,
        children: [
          // ── ① AI 助理沟通(先用)──────────────────────────────
          // 用户第 5(3) 条:助理必须先**问清楚**水平/偏好/目标,再谈建议。
          // 所以这一页第一条是"先聊两句"(给选项的访谈,一分钟答完),
          // 它的答案会写进学习者模型与长期记忆,②③ 直接吃这份数据。
          AppStagger(index: 0, child: _buildInterviewCard(theme, muted, snap)),
          // 不想走访谈?给一条"只补一项"的快路(目标 / 时间 / 题材点一下就存)
          if (snap.model.missingFields.isNotEmpty) _buildProfileForm(theme),
          const SizedBox(height: Gap.md),

          // ── ② 学习现状分析以及规划 ─────────────────────────────
          AppStagger(
            index: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionTitle(
                  title: '学习现状分析',
                  subtitle: '基于你软件里的真实数据(不编造)',
                ),
                if (findings.isEmpty)
                  const AppEmpty(
                    icon: Icons.check_circle_outline,
                    title: '目前没有发现明显问题',
                    hint: '继续按计划走就好;想知道下一步,点下面「让 AI 排规划」',
                  )
                else
                  for (final f in findings) _buildFindingCard(theme, f),
                const SizedBox(height: Gap.xs),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _openChat(
                          snap,
                          question: '根据我的现状,帮我排一份这两周的学习规划:'
                              '每天多少分钟、先练什么、用什么材料。',
                        ),
                        icon: const Icon(Icons.auto_awesome, size: 16),
                        label: const Text('让 AI 排规划'),
                      ),
                    ),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openChat(
                          snap,
                          question: '我这块最薄弱?给我一个最小可行的改进动作。',
                        ),
                        icon: const Icon(Icons.insights, size: 16),
                        label: const Text('看我最薄弱的'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),

          // ── ③ 学习任务(②的结论落成今天能做的事)────────────────
          AppStagger(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionTitle(
                  title: '学习任务',
                  subtitle: '今天做完就算完成,不用想顺序',
                ),
                _buildPrimaryAction(theme, muted, snap),
                if (_taskRows.length > 1)
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text('今天还有 ${_taskRows.length - 1} 件事',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      children: [
                        for (final row in _taskRows.skip(1))
                          _buildTaskCard(theme, row),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),

          // ── ④ 与 AI 聊聊(自由对话;它同样影响 ②③)────────────
          AppStagger(
            index: 3,
            child: AppActionTile(
              icon: Icons.chat_bubble_outline,
              title: _lastChatLine.isEmpty ? '与 AI 聊聊' : '继续上次的对话',
              subtitle: _lastChatLine.isEmpty
                  ? '聊你的想法、卡点、计划 —— 它会记进长期记忆,影响上面的分析与任务'
                  : (_lastChatLine.length > 44
                      ? '${_lastChatLine.substring(0, 44)}…'
                      : _lastChatLine),
              highlight: true,
              onTap: () => _openChat(snap),
            ),
          ),
        ],
      ),
    );
  }

  /// ① 助理访谈入口(v2.8,用户第 5(3) 条)
  Widget _buildInterviewCard(
    ThemeData theme,
    Color muted,
    LearnerSnapshot snap,
  ) {
    final model = snap.model;
    final done = (model.extras['interview_at'] as String?) != null;
    final items = <String>[
      if ((model.goal?.value ?? '').isNotEmpty) '目标 ${model.goal!.value}',
      if ((model.dailyMinutes?.value ?? 0) > 0) '每天 ${model.dailyMinutes!.value} 分钟',
      if ((model.interests?.value ?? const []).isNotEmpty)
        '题材 ${model.interests!.value.join('、')}',
      if (model.blockedTopics.isNotEmpty) '避开 ${model.blockedTopics.join('、')}',
    ];
    return AppCard(
      color: done ? null : theme.colorScheme.primary.withAlpha(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text(
                  done ? '你的情况(助理已了解)' : '先聊两句,助理才知道你要什么',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xxs),
          Text(
            done
                ? (items.isEmpty ? '还没填 — 再聊一次补上' : items.join(' · '))
                : '6 个问题,点选项就行(一分钟)。答完它就知道你的目标、时间与偏好 —— '
                    '下面的分析与任务才会真的贴合你。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: muted, height: 1.45),
          ),
          const SizedBox(height: Gap.sm),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TutorInterviewScreen(),
                  ),
                );
                if (!mounted) return;
                if (changed == true) _refresh();
              },
              icon: Icon(done ? Icons.tune : Icons.play_arrow, size: 18),
              label: Text(done ? '重新聊一次 / 补全信息' : '开始(1 分钟)'),
            ),
          ),
        ],
      ),
    );
  }

  /// 打开对话窗口(可带开场问题 —— 从②点进来时用)
  Future<void> _openChat(LearnerSnapshot snap, {String? question}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TutorChatScreen(
          snapshot: snap,
          initialQuestion: question,
        ),
      ),
    );
    // 回来自刷新:对话里可能补了画像、或用户改了设置(①④ 会影响②③)
    if (!mounted) return;
    _refresh();
  }

  /// 主行动卡(v2.5,U1):今天最该做的那件事 + 一个大按钮。
  ///
  /// 为什么这样排:训记的本质是"一进来就能开始"。以前首屏是"摘要行 + 4 张任务卡
  /// + 若干诊断卡",用户得自己判断先做哪个;现在把第一件事放大、给出按钮,
  /// 其余收进折叠区。
  Widget _buildPrimaryAction(ThemeData theme, Color muted, LearnerSnapshot snap) {
    final first = _taskRows.isEmpty ? null : _taskRows.first;
    final title = first == null ? '今天没有待办' : '${first['title'] ?? ''}';
    final done = first != null &&
        (first['done_at'] != null ||
            (first['id'] is int && _doneTaskIds.contains(first['id'])));
    final payload = first?['payload'];
    final reason = payload is Map ? '${payload['reason'] ?? ''}' : '';
    final jumpName = payload is Map ? '${payload['jump'] ?? ''}' : '';
    final jumpArg = payload is Map ? payload['jumpArg'] as String? : null;
    final action = _parseAction(jumpName);

    // 该复习多少个词(数字放在主卡上,一眼看到"今天的分量")
    final dueLine = snap.dueReviewCount > 0
        ? '待复习 ${snap.dueReviewCount} 个词'
        : (snap.overdueCount > 0 ? '有 ${snap.overdueCount} 个词过期' : '');

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      color: theme.colorScheme.primary.withAlpha(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  done ? '今天已完成 ✓' : '今天先做这件事',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (dueLine.isNotEmpty)
                Text(dueLine,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 22,
              height: 1.3,
              fontWeight: FontWeight.w700,
              decoration: done ? TextDecoration.lineThrough : null,
              color: done ? muted : null,
            ),
          ),
          if (reason.isNotEmpty || first?['target_minutes'] != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              '${first?['target_minutes'] == null ? '' : '约 ${_intOf(first?['target_minutes'])} 分钟'}'
              '${reason.isEmpty ? '' : (first?['target_minutes'] == null ? reason : ' · $reason')}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          const SizedBox(height: Gap.md),
          // v2.8(用户第 5(1) 条):两个按钮以前是**定宽**塞进 Row(没有 Expanded),
          // 「已完成,点这里取消」带图标 + 「取消完成」总宽超卡片 → 文字溢出卡片、
          // 第二个按钮被裁(用户截屏就是这个)。而且 done 时两个按钮做的是同一件事。
          // 现在:未完成 = 「开始」+「直接标记完成」各占一半;完成 = 只有一个「撤销完成」。
          if (done)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => _reopenTask(first),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('撤销完成'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: first == null
                          ? null
                          : () {
                              _completeTask(first);
                              if (action != null) _jump(action, jumpArg);
                            },
                      icon: Icon(
                        action == null ? Icons.check : Icons.play_arrow,
                        size: 20,
                      ),
                      label: Text(action == null ? '标记完成' : '开始'),
                    ),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: first == null
                          ? null
                          : () => _completeTask(first),
                      child: const Text('只标记完成'),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── 画像表单(缺什么问什么) ──
  Widget _buildProfileForm(ThemeData theme) {
    final missing = _model.missingFields;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      color: theme.colorScheme.secondaryContainer.withAlpha(90),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('助理还缺这些信息',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(missing.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            const SizedBox(height: 10),
            if ((_model.goal?.value ?? '').isEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final g in LearnerProfile.goalOptions)
                    ActionChip(
                      label: Text(g),
                      onPressed: () => _saveSelf(goal: g),
                    ),
                ],
              ),
            if ((_model.dailyMinutes?.value ?? 0) <= 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final m in const [15, 30, 45, 60])
                    ActionChip(
                      label: Text('每天 $m 分钟'),
                      onPressed: () => _saveSelf(dailyMinutes: m),
                    ),
                ],
              ),
            ],
            if ((_model.interests?.value ?? const []).isEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final i in LearnerProfile.interestOptions)
                    ActionChip(
                      label: Text(i),
                      onPressed: () {
                        final cur =
                            List<String>.from(_model.interests?.value ?? const []);
                        if (!cur.contains(i)) cur.add(i);
                        _saveSelf(interests: cur);
                      },
                    ),
                ],
              ),
            ],
            if (!_model.hasVocabBaseline) ...[
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: () => _jump(TutorAction.placementTest),
                child: const Text('去做词汇量速测(约 5 分钟)'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveSelf({
    String? goal,
    int? dailyMinutes,
    List<String>? interests,
  }) async {
    _model = await LearnerModelStore.saveSelfReported(
      base: _model,
      goal: goal,
      dailyMinutes: dailyMinutes,
      interests: interests,
    );
    if (!mounted) return;
    setState(() {});
    // 画像变了 → 诊断与任务都可能变,重新生成
    await _refresh();
  }

  /// 学习偏好(v2.0):朗读音色 + 题材/关键词黑名单。
  /// 导师选材已读 `_model.blockedTopics`(见 TutorEngine),回到本页必须重读
  /// 模型 —— 否则刚屏蔽的题材在这一页的选材建议里还会出现。
  Future<void> _openPreferences() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LearnerPreferencesScreen()),
    );
    if (!mounted) return;
    _model = LearnerModelStore.load();
    setState(() {});
    await _refresh();
  }

  Widget _buildTaskCard(ThemeData theme, Map<String, Object?> row) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final id = row['id'];
    final done = row['done_at'] != null ||
        (id is int && _doneTaskIds.contains(id));
    final payload = row['payload'];
    final reason = payload is Map ? '${payload['reason'] ?? ''}' : '';
    final jumpName = payload is Map ? '${payload['jump'] ?? ''}' : '';
    final jumpArg = payload is Map ? payload['jumpArg'] as String? : null;
    final action = _parseAction(jumpName);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: done ? '点一下取消完成' : '标记完成',
              // 完成态**不再禁用**:再点一下就是取消完成(A5)
              onPressed: () => done ? _reopenTask(row) : _completeTask(row),
              icon: Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? AppTheme.successColor(context) : muted,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['title'] ?? ''}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? muted : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '约 ${_intOf(row['target_minutes'])} 分钟'
                    '${reason.isEmpty ? '' : ' · $reason'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: () => _jump(action, jumpArg),
                child: const Text('开始'),
              ),
          ],
        ),
      ),
    );
  }

  TutorAction? _parseAction(String name) {
    for (final a in TutorAction.values) {
      if (a.name == name) return a;
    }
    return null;
  }

  int _intOf(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  Widget _buildFindingCard(ThemeData theme, TutorFinding f) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final (IconData icon, Color color) = switch (f.severity) {
      FindingSeverity.action => (
          Icons.priority_high,
          AppTheme.dangerColor(context)
        ),
      FindingSeverity.warn => (
          Icons.info_outline,
          AppTheme.warningColor(context)
        ),
      FindingSeverity.info => (
          Icons.lightbulb_outline,
          theme.colorScheme.primary
        ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(f.title,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 依据永远显示 —— 这是"专业评估"与"瞎猜"的分界
            Text(f.evidence,
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            if (f.action != null) ...[
              const SizedBox(height: 6),
              Text('→ ${f.action!}', style: theme.textTheme.bodyMedium),
            ],
            if (f.jump != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _jump(f.jump, f.jumpArg),
                  child: Text(switch (f.jump!) {
                    TutorAction.placementTest => '去测词汇量',
                    TutorAction.review => '去复习',
                    TutorAction.materialCenter => '去材料中心',
                    TutorAction.continueReading => '继续阅读',
                    TutorAction.writing => '去写作',
                    TutorAction.backTranslation => '做回译',
                    TutorAction.listening => '去听力',
                    TutorAction.profile => '去设置',
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

}
