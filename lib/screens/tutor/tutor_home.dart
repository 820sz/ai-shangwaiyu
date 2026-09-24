import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../models/learner_model.dart';
import '../../models/material_recommendation.dart' show LearnerProfile;
import '../../providers/stats_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../services/api_endpoint.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../services/learner_model_store.dart';
import '../../services/learner_snapshot_loader.dart';
import '../../services/tutor_engine.dart';
import '../../services/widget_service.dart';
import '../input/widgets/model_avatars.dart';
import 'tutor_chat_screen.dart';
import '../../widgets/bottom_nav.dart';
import '../review/review_screen.dart';
import '../input/learner_preferences_screen.dart';
import 'placement_test_screen.dart';

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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(TutorEngine.summaryLine(snap),
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 12),

          if (snap.model.missingFields.isNotEmpty) _buildProfileForm(theme),

          Text('今天做什么',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_taskRows.isEmpty)
            Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline,
                    color: theme.colorScheme.primary),
                title: const Text('今天没有待办'),
                subtitle: Text('从材料中心挑一份材料开始即可',
                    style: TextStyle(color: muted, fontSize: 12)),
              ),
            )
          else
            for (final row in _taskRows) _buildTaskCard(theme, row),
          const SizedBox(height: 16),

          Text('诊断(${findings.length} 条)',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final f in findings) _buildFindingCard(theme, f),
          const SizedBox(height: 16),

          Text('问助理',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          // v2.4(C1 用户要求):对话搬进**独立窗口** ——
          // 这一页只留"今天做什么 + 诊断",聊天不再挤在这里。
          // 入口卡同时给出最近一条对话的摘要,方便接着聊。
          Card(
            color: theme.colorScheme.primary.withAlpha(10),
            child: ListTile(
              leading: aiAvatar(radius: 16, modelName: _primaryModelName()),
              title: Text(
                _lastChatLine.isEmpty ? '和助理聊聊' : '继续上次的对话',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _lastChatLine.isEmpty
                    ? '助理知道你现在的全部学习数据 —— 可以问"我现在该读什么难度"、"为什么复习总是堆着"'
                    : (_lastChatLine.length > 44
                        ? '${_lastChatLine.substring(0, 44)}…'
                        : _lastChatLine),
                style: TextStyle(fontSize: 12, color: muted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TutorChatScreen(snapshot: snap),
                  ),
                );
                // 回来自刷新:对话里可能问了画像问题、或用户改了设置
                if (!mounted) return;
                _refresh();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 当前主模型名(入口卡头像用)
  String _primaryModelName() => ApiEndpointConfig.primary.model;

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
                color: done ? Colors.green : muted,
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
      FindingSeverity.action => (Icons.priority_high, Colors.red),
      FindingSeverity.warn => (Icons.info_outline, Colors.orange),
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
