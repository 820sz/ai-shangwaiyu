import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../models/learner_model.dart';
import '../../models/material_recommendation.dart' show LearnerProfile;
import '../../providers/stats_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../services/learner_model_store.dart';
import '../../services/learner_snapshot_loader.dart';
import '../../services/tutor_engine.dart';
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
  final List<_ChatTurn> _chat = [];
  final Set<int> _doneTaskIds = {};
  final _inputCtrl = TextEditingController();

  bool _loading = true;
  bool _askingTutor = false;

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
    _inputCtrl.dispose();
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
        _chat
          ..clear()
          ..addAll(msgs.map((m) => _ChatTurn(
                role: '${m['role']}' == 'user' ? 'user' : 'tutor',
                text: '${m['content'] ?? ''}',
              )));
        _loading = false;
      });
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

  // ── 导师会话 ──
  Future<void> _ask([String? preset]) async {
    final q = (preset ?? _inputCtrl.text).trim();
    if (q.isEmpty || _askingTutor) return;
    _inputCtrl.clear();
    final snap = _snapshot;
    if (snap == null) return;
    final findings = TutorEngine.diagnose(snap);

    setState(() {
      _chat.add(_ChatTurn(role: 'user', text: q));
      _askingTutor = true;
    });
    await DatabaseService.insertTutorMessage(role: 'user', content: q);

    try {
      final history = <Map<String, String>>[
        for (final t in _chat.take(_chat.length - 1))
          {
            'role': t.role == 'user' ? 'user' : 'assistant',
            'content': t.text,
          },
      ];
      final api = DoubaoApiService();
      final buffer = StringBuffer();
      setState(() => _chat.add(const _ChatTurn(role: 'tutor', text: '')));
      await for (final chunk in api.followUpStream(
        q,
        context: _tutorSystemPrompt(
          TutorEngine.evidencePrompt(snap, findings),
        ),
        history: history,
      )) {
        if (!mounted) return;
        if (chunk.isReasoning) continue; // 思考过程不占正文
        buffer.write(chunk.text);
        setState(() {
          _chat[_chat.length - 1] =
              _ChatTurn(role: 'tutor', text: buffer.toString());
        });
      }
      final answer = buffer.isEmpty ? '(没有拿到回复,请重试)' : buffer.toString();
      if (mounted && buffer.isEmpty) {
        setState(() {
          _chat[_chat.length - 1] = _ChatTurn(role: 'tutor', text: answer);
        });
      }
      if (!answer.startsWith('(')) {
        await DatabaseService.insertTutorMessage(role: 'tutor', content: answer);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chat.add(_ChatTurn(role: 'tutor', text: '出错了:$e'));
      });
    } finally {
      if (mounted) setState(() => _askingTutor = false);
    }
  }

  String _tutorSystemPrompt(String evidence) => '''
你是这位学习者的私人英语导师。你**只能基于下面给出的数据快照与本地诊断结论**回答,
禁止编造数据、禁止编造材料名、禁止给出与数据矛盾的判断。

回答要求:
1. 先给结论,再给依据(引用具体数字);
2. 给可执行的下一步(具体到"读什么/读多少/几分钟/练什么");
3. 数据不足以判断时,直接说"我缺 X 信息",并向用户提 1-2 个具体问题;
4. 不要说"加油""坚持就是胜利"这类空话;回答控制在 200 字内。

$evidence''';

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
        title: const Text('导师'),
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

          Text('问导师',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_chat.isEmpty)
            Card(
              color: theme.colorScheme.primary.withAlpha(10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('导师知道你现在的全部学习数据 —— 可以直接问:',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    const SizedBox(height: 6),
                    for (final q in const [
                      '我现在该读什么难度的材料?',
                      '为什么我的复习总是堆着?',
                      '帮我排一下这周的学习安排',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: InkWell(
                          onTap: _askingTutor ? null : () => _ask(q),
                          child: Text('· $q',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              )),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          for (final turn in _chat) _buildChatBubble(theme, turn),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  decoration: const InputDecoration(
                    hintText: '问导师任何关于你学习的问题…',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _ask(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _askingTutor ? null : () => _ask(),
                child: Text(_askingTutor ? '…' : '发送'),
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
                Text('导师还缺这些信息',
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
              tooltip: done ? '已完成' : '标记完成',
              onPressed: done ? null : () => _completeTask(row),
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

  Widget _buildChatBubble(ThemeData theme, _ChatTurn turn) {
    final isUser = turn.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary.withAlpha(20)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          turn.text.isEmpty ? '思考中…' : turn.text,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _ChatTurn {
  final String role; // user | tutor
  final String text;
  const _ChatTurn({required this.role, required this.text});
}
