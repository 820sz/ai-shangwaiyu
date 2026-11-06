import 'package:flutter/material.dart';

import '../../app.dart';
import '../../config/design_tokens.dart';
import '../../services/database.dart';
import '../../services/tutor_insights.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/dash_kit.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/v4/v4_kit.dart';
import '../input/learner_preferences_screen.dart';
import '../review/review_screen.dart';
import 'placement_test_screen.dart';

/// 助理 ·「任务详情」页(A 诊断台语言)。
///
/// 为什么必须新开一页:以前任务只有一个 `showModalBottomSheet` + 5 个
/// `ListTile`(开始/完成/跳过/编辑),既看不到"为什么安排这条任务",
/// 也没法看时间线;用户说"点进去又是一坨屎"就包括这里。
///
/// 这一页把一条任务拆成:状态 / 标题 / 预计时长 / 为什么(依据) / 时间线 /
/// 操作(开始·完成·撤销·跳过·编辑) —— 每个按钮都真写库,写完通知外层刷新。
class TutorTaskDetailScreen extends StatefulWidget {
  const TutorTaskDetailScreen({
    super.key,
    required this.row,
    this.onChanged,
  });

  /// tutor_tasks 的一行(已含解析后的 `payload` / `result`)
  final Map<String, Object?> row;
  final Future<void> Function()? onChanged;

  @override
  State<TutorTaskDetailScreen> createState() => _TutorTaskDetailScreenState();
}

class _TutorTaskDetailScreenState extends State<TutorTaskDetailScreen> {
  late Map<String, Object?> _row = Map<String, Object?>.from(widget.row);
  bool _busy = false;

  int? get _id => _row['id'] is int ? _row['id'] as int : null;

  String get _status =>
      '${_row['status'] ?? (_row['done_at'] != null ? 'done' : 'pending')}';

  String get _title => '${_row['title'] ?? '（未命名任务）'}';

  Map<String, Object?> get _payload {
    final Object? p = _row['payload'];
    return p is Map ? p.cast<String, Object?>() : <String, Object?>{};
  }

  String get _reason => '${_payload['reason'] ?? ''}'.trim();

  String get _jumpId => '${_payload['jump'] ?? ''}'.trim();

  int? get _minutes =>
      _row['target_minutes'] is num ? (_row['target_minutes'] as num).toInt() : null;

  String get _statusLabel => switch (_status) {
        'done' => '已完成',
        'skipped' => '已跳过',
        'active' => '进行中',
        _ => '待做',
      };

  DashTheme get _d => DashTheme.of(context);

  Future<void> _write(Future<void> Function() action) async {
    final int? id = _id;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      // 重新读这一行(状态机字段由 DB 层维护,不在这里自己拼)
      final List<Map<String, Object?>> rows =
          await DatabaseService.listTutorTasks(limit: 200);
      for (final Map<String, Object?> r in rows) {
        if (r['id'] == id) {
          if (!mounted) return;
          setState(() => _row = r);
          break;
        }
      }
      await widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败:$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final int? id = _id;
    if (id == null) return;
    await _write(() => DatabaseService.updateTutorTaskStatus(id, 'active'));
    if (!mounted) return;
    final String jump = _jumpId;
    if (jump.isEmpty) return;
    switch (jump) {
      case TutorActionJumps.placement:
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const PlacementTestScreen(full: false)),
        );
      case TutorActionJumps.review:
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const ReviewScreen()),
        );
      case TutorActionJumps.output:
        AppTabs.maybeOf(context)?.switchTo(ReadFlowTab.output);
        Navigator.maybePop(context);
      case TutorActionJumps.reading:
        AppTabs.maybeOf(context)?.switchTo(ReadFlowTab.input);
        Navigator.maybePop(context);
      case TutorActionJumps.prefs:
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const LearnerPreferencesScreen()),
        );
    }
  }

  Future<void> _complete() async {
    final int? id = _id;
    if (id == null) return;
    await _write(() => DatabaseService.completeTutorTask(id));
  }

  Future<void> _reopen() async {
    final int? id = _id;
    if (id == null) return;
    await _write(() => DatabaseService.reopenTutorTask(id));
  }

  Future<void> _skip() async {
    final int? id = _id;
    if (id == null) return;
    await _write(() => DatabaseService.updateTutorTaskStatus(id, 'skipped'));
  }

  Future<void> _edit() async {
    final int? id = _id;
    if (id == null) return;
    final TextEditingController titleCtrl = TextEditingController(text: _title);
    final TextEditingController minCtrl =
        TextEditingController(text: '${_minutes ?? 15}');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('编辑任务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '做什么'),
            ),
            const SizedBox(height: Gap.xs),
            TextField(
              controller: minCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '预计分钟'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final String title = titleCtrl.text.trim();
    final int minutes = int.tryParse(minCtrl.text.trim()) ?? (_minutes ?? 15);
    titleCtrl.dispose();
    minCtrl.dispose();
    if (ok != true || title.isEmpty) return;
    await _write(() async {
      await DatabaseService.updateTutorTaskFields(
        id,
        title: title,
        targetMinutes: minutes.clamp(0, 600),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final DashTheme d = _d;
    final List<String> timeline = <String>[
      if (_row['created_at'] != null) '创建 ${_fmtTime('${_row['created_at']}')}',
      if (_row['started_at'] != null) '开始 ${_fmtTime('${_row['started_at']}')}',
      if (_row['done_at'] != null) '完成 ${_fmtTime('${_row['done_at']}')}',
    ];
    return Scaffold(
      backgroundColor: d.skin.pageBg,
      appBar: const V4JellyAppBar(title: '任务详情', domain: GraphicDomain.academic),
      body: ListView(
        padding: Insets.page,
        children: <Widget>[
          // 状态 + 标题
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _status == 'done'
                      ? d.good.withValues(alpha: 0.12)
                      : (_status == 'skipped'
                          ? d.warn.withValues(alpha: 0.14)
                          : d.accent.withValues(alpha: 0.10)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel,
                  style: AppFont.tagStyle.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _status == 'done'
                        ? d.good
                        : (_status == 'skipped' ? d.warn : d.accent),
                  ),
                ),
              ),
              const Spacer(),
              if (_minutes != null)
                Text(
                  '预计 $_minutes 分钟',
                  style: AppFont.metaStyle.copyWith(
                    fontSize: 11,
                    color: d.inkFaint,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            _title,
            style: AppFont.displayStyle.copyWith(
              fontSize: 24,
              height: 1.25,
              letterSpacing: -0.4,
              fontWeight: FontWeight.w800,
              color: d.ink,
            ),
          ),
          const SizedBox(height: Gap.md),

          // 为什么做这件事
          DashCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '为什么安排这条',
                  style: AppFont.tagStyle.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: d.accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _reason.isEmpty
                      ? '这条任务没有记录依据(手工添加或旧版数据)。做完它,复盘里会记一条真实产出。'
                      : _reason,
                  style: AppFont.bodyStyle.copyWith(
                    fontSize: 12.5,
                    height: 1.7,
                    color: d.ink,
                  ),
                ),
                if (_jumpId.isNotEmpty || (_row['goal_tag'] ?? '') != '') ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      if ((_row['goal_tag'] ?? '').toString().trim().isNotEmpty)
                        _pill(d, '目标 ${_goalLabel('${_row['goal_tag']}'.trim())}'),
                      if (_jumpId.isNotEmpty) _pill(d, '开始后跳转:${_jumpLabel(_jumpId)}'),
                      if ((_row['origin'] ?? '') == 'custom') _pill(d, '自己添加'),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // 时间线
          if (timeline.isNotEmpty) ...[
            const DashSectionTitle(index: '01', title: '时间线'),
            DashCard(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < timeline.length; i++) ...<Widget>[
                    if (i > 0) Divider(height: 1, thickness: 0.8, color: d.line),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == timeline.length - 1 ? d.accent : d.inkFaint,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              timeline[i],
                              style: AppFont.bodyStyle.copyWith(
                                fontSize: 12.5,
                                color: d.inkSoft,
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

          const SizedBox(height: Gap.lg),

          // 操作
          if (_status != 'done')
            BriefActionButton(
              label: _status == 'active' ? '继续(标记进行中)' : '开始做',
              icon: Icons.play_arrow_rounded,
              onTap: _busy ? null : _start,
            ),
          if (_status == 'done') ...<Widget>[
            _secondaryButton(
              context,
              label: '撤销完成(回到待做)',
              icon: Icons.undo_rounded,
              onTap: _busy ? null : _reopen,
            ),
          ] else ...[
            _secondaryButton(
              context,
              label: '标记完成',
              icon: Icons.check_rounded,
              onTap: _busy ? null : _complete,
            ),
            _secondaryButton(
              context,
              label: '今天跳过(会记进复盘)',
              icon: Icons.skip_next_rounded,
              onTap: _busy ? null : _skip,
            ),
          ],
          _secondaryButton(
            context,
            label: '编辑标题 / 时长',
            icon: Icons.edit_outlined,
            onTap: _busy ? null : _edit,
          ),
          const SizedBox(height: Gap.sm),
          Text(
            '所有操作都会写进任务事件,复盘按真实状态统计 —— 勾完成不会替你写"学了多久"。',
            style: AppFont.metaStyle.copyWith(
              fontSize: 10.5,
              height: 1.6,
              color: d.inkFaint,
            ),
          ),
          const SizedBox(height: Gap.xl),
        ],
      ),
    );
  }

  Widget _pill(DashTheme d, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: d.skin.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: AppFont.tagStyle.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: d.inkSoft,
        ),
      ),
    );
  }

  Widget _secondaryButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final DashTheme d = _d;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: d.line),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, size: 17, color: d.inkSoft),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: AppFont.bodyStyle.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: d.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _goalLabel(String tag) {
    if (tag.isEmpty) return '—';
    return switch (tag) {
      'vocab' => '词汇',
      'grammar' => '语法',
      'reading' => '阅读',
      'output' => '输出',
      'habit' => '习惯',
      _ => tag,
    };
  }

  String _jumpLabel(String jump) {
    return switch (jump) {
      TutorActionJumps.placement => '词汇量速测',
      TutorActionJumps.review => '复习',
      TutorActionJumps.output => '输出板块',
      TutorActionJumps.reading => '输入板块',
      TutorActionJumps.prefs => '学习偏好',
      _ => jump,
    };
  }

  static String _fmtTime(String raw) {
    final DateTime? t = DateTime.tryParse(raw);
    if (t == null) return raw;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.month}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// A 语言的主行动按钮(诊断台蓝,与 dash_kit 同一套形状)
class BriefActionButton extends StatelessWidget {
  const BriefActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    final bool enabled = onTap != null;
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: Material(
        color: enabled ? d.accent : d.line,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: enabled ? Colors.white : d.inkFaint,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppFont.bodyStyle.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: enabled ? Colors.white : d.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
