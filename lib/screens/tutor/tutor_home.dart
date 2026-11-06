import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../config/design_tokens.dart';
import '../../models/learner_model.dart';
import '../../models/material_recommendation.dart' show LearnerProfile;
import '../../providers/stats_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../services/database.dart';
import '../../services/learner_model_store.dart';
import '../../services/tutor_briefing.dart';
import '../../services/tutor_engine.dart';
import '../../services/tutor_insights.dart';
import '../../services/tutor_snapshot.dart';
import '../../services/widget_service.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/brief_kit.dart';
import '../../widgets/error_state.dart';
import '../../widgets/v4/v4_kit.dart';
import '../../widgets/waiting.dart';
import '../input/learner_preferences_screen.dart';
import 'placement_test_screen.dart';
import 'tutor_chat_screen.dart';
import 'tutor_interview_screen.dart';
import 'tutor_review_screen.dart';
import 'tutor_task_detail_screen.dart';

/// 助理首页 · B「每日简报」语言。
///
/// v5(2026-11-06,用户选型):从「大卡瀑布」改成**每天早上的一张纸**——
/// 40px 日期刊头 + 一句"今天有什么" + 时间线 + 这周事实 + 一句提醒 + 入口。
/// 数据仍然由 [TutorSnapshotService] 一次组装(五维/任务/复盘),文案由
/// [TutorBriefing] 纯函数生成;页面只负责排版与跳转。
///
/// 与旧版的区别(用户抱怨的"点进去又是一坨屎"):
/// 1. 五维现状与复盘**搬进独立页面**([TutorReviewScreen]),首页只留摘要;
/// 2. 每条任务可**点进详情页**([TutorTaskDetailScreen])做开始/完成/跳过/编辑,
///    不再只有底部 `ListTile` 弹层;
/// 3. 所有卡/色/字都走 [BriefTheme],与「我的」同一个语言。
class TutorHomeScreen extends StatefulWidget {
  const TutorHomeScreen({super.key, this.previewDashboard, this.previewTasks});

  /// **仅用于逐屏渲染/测试**:直接注入已组装好的数据,跳过异步装配
  /// (与服务层同一份 `TutorDashboard`,页面渲染路径完全不变)。
  final TutorDashboard? previewDashboard;
  final List<Map<String, Object?>>? previewTasks;

  @override
  State<TutorHomeScreen> createState() => _TutorHomeScreenState();
}

class _TutorHomeScreenState extends State<TutorHomeScreen> {
  LearnerModel _model = LearnerModel();
  LearnerSnapshot? _snapshot;

  /// 助理工作台数据:五维现状 + 任务建议 + 复盘一次组装
  TutorDashboard? _dash;
  List<Map<String, Object?>> _taskRows = const <Map<String, Object?>>[];

  /// 最近一条对话摘要(对话在独立窗口,这里只做入口卡副标题)
  String _lastChatLine = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final TutorDashboard? injected = widget.previewDashboard;
    if (injected != null) {
      // 渲染/测试注入:不查库、不调服务,直接用给定数据出首帧
      _model = LearnerModelStore.load();
      _dash = injected;
      _snapshot = injected.snapshot;
      _taskRows = widget.previewTasks ?? injected.todayTasks;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _model = LearnerModelStore.load();
      _refresh();
    });
  }

  Future<void> _refresh() async {
    try {
      final List<dynamic> vocab = context.read<VocabProvider>().vocabularies;
      final List<dynamic> logs = context.read<StatsProvider>().dailyLogs;
      final TutorDashboard dash = await TutorSnapshotService.load(
        vocab: vocab,
        dailyLogs: logs.cast(),
      );
      final LearnerSnapshot snap = dash.snapshot;

      // 今日任务:没有就按五维建议落库一次(每天一份,不覆盖已有)
      List<Map<String, Object?>> rows = dash.todayTasks;
      if (rows.isEmpty && dash.suggestions.isNotEmpty) {
        for (final TaskSuggestion s in dash.suggestions) {
          await DatabaseService.insertTutorTask(
            planDate: snap.now,
            kind: s.action,
            title: s.title,
            targetMinutes: s.minutes,
            origin: 'auto',
            goalTag: s.goalTag,
            payload: <String, Object?>{
              'reason': s.reason,
              'jump': s.action,
              'jumpArg': null,
            },
          );
        }
        rows = await DatabaseService.listTutorTasks(
          planDate: _dateKey(snap.now),
          limit: 30,
        );
      }

      final List<Map<String, Object?>> msgs =
          await DatabaseService.getTutorMessages(limit: 20);
      if (!mounted) return;
      setState(() {
        _dash = dash;
        _snapshot = snap;
        _taskRows = rows;
        _lastChatLine =
            msgs.isEmpty ? '' : '${msgs.last['content'] ?? ''}'.replaceAll('\n', ' ');
        _loading = false;
      });
      // 桌面小组件显示的就是这里刚算出来的"今天该做什么",顺手推一次
      WidgetService.sync();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('诊断数据读取失败:$e')),
      );
    }
  }

  static String _dateKey(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)}';
  }

  // ── 跳转 ──────────────────────────────────────────────────────────

  /// 语义跳转 id → 实际页面(值与 `TutorActionJumps` 一致)
  void _jumpByActionId(String? id) {
    if (id == null || id.isEmpty) return;
    switch (id) {
      case TutorActionJumps.placement:
        _openPlacement();
      case TutorActionJumps.review:
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const _ReviewEntryPoint()),
        ).then((_) {
          if (mounted) _refresh();
        });
      case TutorActionJumps.output:
        AppTabs.maybeOf(context)?.switchTo(ReadFlowTab.output);
      case TutorActionJumps.reading:
        AppTabs.maybeOf(context)?.switchTo(ReadFlowTab.input);
      case TutorActionJumps.prefs:
        _openPreferences();
    }
  }

  Future<void> _openPlacement() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const PlacementTestScreen(full: false)),
    );
    if (!mounted) return;
    _model = LearnerModelStore.load();
    await _refresh();
  }

  Future<void> _openPreferences() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const LearnerPreferencesScreen()),
    );
    if (!mounted) return;
    _model = LearnerModelStore.load();
    setState(() {});
    await _refresh();
  }

  Future<void> _openChat({String? question}) async {
    final LearnerSnapshot? snap = _snapshot;
    if (snap == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TutorChatScreen(snapshot: snap, initialQuestion: question),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openInterview() async {
    final bool? changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => const TutorInterviewScreen()),
    );
    if (!mounted) return;
    if (changed == true) {
      _model = LearnerModelStore.load();
      await _refresh();
    }
  }

  Future<void> _openReview() async {
    final TutorDashboard? dash = _dash;
    if (dash == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TutorReviewScreen(
          dashboard: dash,
          onChanged: _refresh,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openTaskDetail(BriefToday item) async {
    if (item.rawId == null) {
      await _addSuggestedTaskByTitle(item.title);
      return;
    }
    Map<String, Object?>? row;
    for (final Map<String, Object?> r in _taskRows) {
      if (r['id'] == item.rawId) {
        row = r;
        break;
      }
    }
    if (row == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TutorTaskDetailScreen(row: row!, onChanged: _refresh),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  // ── 任务操作 ──────────────────────────────────────────────────────

  Future<void> _startTask(Map<String, Object?> row) async {
    final Object? id = row['id'];
    if (id is! int) return;
    try {
      await DatabaseService.updateTutorTaskStatus(id, 'active');
    } catch (_) {
      // 状态写失败不影响"开始去做"这件事本身
    }
  }

  Future<void> _addSuggestedTaskByTitle(String title) async {
    final List<TaskSuggestion> pool = _dash?.suggestions ?? const <TaskSuggestion>[];
    TaskSuggestion? hit;
    for (final TaskSuggestion s in pool) {
      if (s.title == title) {
        hit = s;
        break;
      }
    }
    if (hit == null) return;
    try {
      await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: hit.action,
        title: hit.title,
        targetMinutes: hit.minutes,
        origin: 'auto',
        goalTag: hit.goalTag,
        payload: <String, Object?>{
          'reason': hit.reason,
          'jump': hit.action,
          'jumpArg': null,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加进今天')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加入失败:$e')),
      );
    }
  }

  /// 自定义任务(用户说了算)
  Future<void> _addCustomTask() async {
    final TextEditingController titleCtrl = TextEditingController();
    final TextEditingController minCtrl = TextEditingController(text: '15');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('加一条自己的任务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '做什么',
                hintText: '例如:把昨天的作文重写一遍',
              ),
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
            child: const Text('加入今天'),
          ),
        ],
      ),
    );
    final String title = titleCtrl.text.trim();
    final int minutes = int.tryParse(minCtrl.text.trim()) ?? 15;
    titleCtrl.dispose();
    minCtrl.dispose();
    if (ok != true || title.isEmpty) return;
    try {
      await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: 'custom',
        title: title,
        targetMinutes: minutes.clamp(1, 600),
        origin: 'custom',
        status: 'pending',
      );
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加失败:$e')),
      );
    }
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
    await _refresh();
  }

  // ── 渲染 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    if (_loading) {
      return BriefScaffold(
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: SkeletonLines(lines: 6, seed: 0),
        ),
      );
    }
    final TutorDashboard? dash = _dash;
    final LearnerSnapshot? snap = _snapshot;
    if (dash == null || snap == null) {
      return BriefScaffold(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: ErrorState(
            message: '诊断数据暂时读不到',
            onRetry: _refresh,
          ),
        ),
      );
    }

    final List<dynamic> logs = context.watch<StatsProvider>().dailyLogs;
    final Briefing b = TutorBriefing.build(
      dash,
      dailyLogs: logs.cast(),
      now: snap.now,
    );
    final BriefToday? first = b.today.isEmpty ? null : b.today.first;

    return BriefScaffold(
      refresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BriefDateHead(
            eyebrow: b.eyebrow,
            bigDate: b.dateBig,
            rightTop: b.weekday,
            rightBottom: b.streakText,
          ),
          const SizedBox(height: Gap.md),
          Text(
            b.greeting,
            style: AppFont.headingStyle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          const SizedBox(height: Gap.xs),
          BriefLead(title: b.headline, body: b.lead),
          const SizedBox(height: Gap.md),

          // ── 今天:时间线 + 主行动 ──
          BriefCard(
            highlight: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const BriefLabel('今天的简报'),
                    const Spacer(),
                    if (b.totalMinutes > 0)
                      Text(
                        '约 ${b.totalMinutes} 分钟',
                        style: AppFont.metaStyle.copyWith(
                          fontSize: 10.5,
                          color: t.inkFaint,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (b.today.isEmpty)
                  BriefEmpty(
                    title: '今天还没有任务',
                    hint: b.dueWords > 0
                        ? '有 ${b.dueWords} 个到期词 —— 先完成一件最小的事,再谈计划。'
                        : '助理还没排出建议。自己加一条,或者先做一次词汇量速测。',
                    actionLabel: '自己加一条',
                    onAction: _addCustomTask,
                  )
                else
                  for (var i = 0; i < b.today.length; i++)
                    BriefTimelineRow(
                      when: b.today[i].when,
                      title: b.today[i].title,
                      detail: b.today[i].detail,
                      last: i == b.today.length - 1,
                      onTap: () => _openTaskDetail(b.today[i]),
                    ),
                if (b.todayNote.isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    b.todayNote,
                    style: AppFont.metaStyle.copyWith(
                      fontSize: 10.5,
                      color: t.inkFaint,
                    ),
                  ),
                ],
                const SizedBox(height: Gap.md),
                BriefPrimaryButton(
                  label: first == null ? '自己加一条任务' : '开始:${_short(first.title)}',
                  icon: first == null ? Icons.add : Icons.play_arrow,
                  onTap: first == null
                      ? _addCustomTask
                      : () {
                          if (first.rawId == null) {
                            _addSuggestedTaskByTitle(first.title);
                            return;
                          }
                          for (final Map<String, Object?> row in _taskRows) {
                            if (row['id'] != first.rawId) continue;
                            _startTask(row);
                            final Object? payload = row['payload'];
                            final String jump = payload is Map
                                ? '${payload['jump'] ?? ''}'
                                : '';
                            if (jump.isNotEmpty) {
                              _jumpByActionId(jump);
                            } else {
                              _openTaskDetail(first);
                            }
                            break;
                          }
                        },
                ),
                const SizedBox(height: Gap.xs),
                BriefOutlineButton(
                  label: '看全部任务与复盘',
                  onTap: _openReview,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── 这周:真实数字 + 7 天柱 ──
          BriefCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const BriefSectionTitle(eyebrow: '这周'),
                if (b.weekStats.isEmpty)
                  BriefEmpty(
                    title: '本周还没有结算过的任务',
                    hint: b.weekNote,
                    actionLabel: '去复盘看看',
                    onAction: _openReview,
                  )
                else ...[
                  BriefStatRow(
                    stats: <BriefStat>[
                      for (final BriefFact f in b.weekStats.take(3))
                        BriefStat(
                          value: f.value,
                          label: f.label,
                          valueSize: 24,
                          color: switch (f.tone) {
                            BriefTone.good => t.accent2,
                            BriefTone.accent => t.accent,
                            BriefTone.warn => t.warn,
                            BriefTone.neutral => t.ink,
                          },
                        ),
                    ],
                  ),
                  if (b.weekBarsTotal > 0) ...[
                    const SizedBox(height: 14),
                    BriefBars(values: b.weekBars, height: 30),
                    const SizedBox(height: 6),
                    Text(
                      '近 7 天活动量 合计 ${b.weekBarsTotal}',
                      style: AppFont.metaStyle.copyWith(
                        fontSize: 10.5,
                        color: t.inkFaint,
                      ),
                    ),
                  ],
                  if (b.weekNote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      b.weekNote,
                      style: AppFont.metaStyle.copyWith(
                        fontSize: 11,
                        height: 1.55,
                        color: t.inkSoft,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          // ── 一句提醒(有真实依据才出现)──
          if (b.reminder != null) ...[
            const SizedBox(height: 14),
            BriefQuote(text: b.reminder!),
          ],

          // ── 待测:没有数据就明说,并给"怎么测" ──
          if (b.pendingDimensions.isNotEmpty) ...[
            const SizedBox(height: 14),
            BriefCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  BriefLabel(
                    '待测 ${b.pendingDimensions.length} 项',
                    color: t.warn,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    b.pendingHint,
                    style: AppFont.bodyStyle.copyWith(
                      fontSize: 12,
                      height: 1.65,
                      color: t.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 10),
                  BriefOutlineButton(
                    label: '做一次词汇量速测(约 5 分钟)',
                    onTap: _openPlacement,
                  ),
                ],
              ),
            ),
          ],

          // ── 访谈 / 画像缺口 ──
          if ((snap.model.extras['interview_at'] as String?) == null) ...[
            const SizedBox(height: 14),
            BriefCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const BriefLabel('先聊两句'),
                  const SizedBox(height: 8),
                  Text(
                    '6 个问题,点选项就行(一分钟)。答完助理才知道你的目标、每天能学多久、'
                    '爱看什么 —— 下面的简报才会真的贴合你。',
                    style: AppFont.bodyStyle.copyWith(
                      fontSize: 12.5,
                      height: 1.7,
                      color: t.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 12),
                  BriefOutlineButton(label: '开始访谈', onTap: _openInterview),
                ],
              ),
            ),
          ],
          if (_model.missingFields.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildGapCard(t),
          ],

          const SizedBox(height: 14),

          // ── 入口 ──
          BriefCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              children: <Widget>[
                BriefEntryRow(
                  title: '现状分析与复盘',
                  subtitle: _reviewSubtitle(b),
                  trailingText: '${dash.insights.length} 维',
                  dense: true,
                  onTap: _openReview,
                ),
                BriefEntryRow(
                  title: '学习任务',
                  subtitle: _taskRows.isEmpty
                      ? '今天还没有任务 · 点开可以自己加'
                      : '${_taskRows.length} 条 · 点开看详情与操作',
                  dense: true,
                  onTap: _openReview,
                ),
                BriefEntryRow(
                  title: _lastChatLine.isEmpty ? '与 AI 聊聊' : '继续上次的对话',
                  subtitle: _lastChatLine.isEmpty
                      ? '聊你的卡点与计划 —— 它会记进长期记忆,影响上面的简报'
                      : _clip(_lastChatLine, 40),
                  dense: true,
                  onTap: () => _openChat(),
                ),
                BriefEntryRow(
                  title: '学习偏好',
                  subtitle: _preferencesSubtitle(),
                  dense: true,
                  onTap: _openPreferences,
                ),
                BriefEntryRow(
                  title: '学习访谈',
                  subtitle: '目标 / 每天时长 / 题材偏好',
                  dense: true,
                  showDivider: false,
                  onTap: _openInterview,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _reviewSubtitle(Briefing b) {
    if (b.weekStats.isEmpty) return '五维现状 · 近 7 天计划 vs 实际(还没有结算数据)';
    final StringBuffer sb = StringBuffer('五维现状 · 近 7 天');
    for (final BriefFact f in b.weekStats.take(2)) {
      sb.write(' · ${f.label} ${f.value}');
    }
    return sb.toString();
  }

  String _short(String s) => s.length <= 14 ? s : '${s.substring(0, 14)}…';

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  String _preferencesSubtitle() {
    final List<String> topics = _model.blockedTopics;
    final List<String> keywords = _model.blockedKeywords;
    final int total = topics.length + keywords.length;
    if (total == 0) return '朗读音色 · 屏蔽题材与关键词';
    final String shown = <String>[...topics, ...keywords].take(3).join('、');
    return '已屏蔽:$shown${total > 3 ? ' 等 $total 项' : ''}';
  }

  /// 画像缺口卡:缺什么问什么(选项点一下就存,不跳页)
  Widget _buildGapCard(BriefTheme t) {
    final List<String> missing = _model.missingFields;
    return BriefCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BriefLabel('助理还缺 ${missing.length} 项', color: t.warn),
          const SizedBox(height: 6),
          Text(
            missing.join(' · '),
            style: AppFont.metaStyle.copyWith(fontSize: 11, color: t.inkSoft),
          ),
          const SizedBox(height: 10),
          if ((_model.goal?.value ?? '').isEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String g in LearnerProfile.goalOptions)
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
              runSpacing: 6,
              children: <Widget>[
                for (final int m in const <int>[15, 30, 45, 60])
                  ActionChip(
                    label: Text('每天 $m 分钟'),
                    onPressed: () => _saveSelf(dailyMinutes: m),
                  ),
              ],
            ),
          ],
          if ((_model.interests?.value ?? const <String>[]).isEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String i in LearnerProfile.interestOptions)
                  ActionChip(
                    label: Text(i),
                    onPressed: () {
                      final List<String> cur =
                          List<String>.from(_model.interests?.value ?? const <String>[]);
                      if (!cur.contains(i)) cur.add(i);
                      _saveSelf(interests: cur);
                    },
                  ),
              ],
            ),
          ],
          if (!_model.hasVocabBaseline) ...[
            const SizedBox(height: 10),
            BriefOutlineButton(label: '去做词汇量速测(约 5 分钟)', onTap: _openPlacement),
          ],
        ],
      ),
    );
  }
}

/// 复盘跳转的中间壳:首页已经持有 dashboard,但跳转是从语义 id 触发的,
/// 这里用 StatefulWidget 包一层保证能拿到最新 dashboard —— 传 null 时自己加载。
class _ReviewEntryPoint extends StatefulWidget {
  const _ReviewEntryPoint();

  @override
  State<_ReviewEntryPoint> createState() => _ReviewEntryPointState();
}

class _ReviewEntryPointState extends State<_ReviewEntryPoint> {
  TutorDashboard? _dash;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final TutorDashboard dash = await TutorSnapshotService.load();
      if (!mounted) return;
      setState(() {
        _dash = dash;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TutorDashboard? dash = _dash;
    if (_loading) {
      return const Scaffold(body: Padding(
        padding: EdgeInsets.all(20),
        child: SkeletonLines(lines: 6, seed: 1),
      ));
    }
    if (dash == null) {
      return Scaffold(
        appBar: const V4JellyAppBar(title: '复盘'),
        body: ErrorState(message: _error ?? '复盘数据读不到', onRetry: _load),
      );
    }
    return TutorReviewScreen(dashboard: dash, onChanged: _load);
  }
}
