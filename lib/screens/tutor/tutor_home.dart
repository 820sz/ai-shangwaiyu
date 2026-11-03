import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../config/v4_theme.dart';
import '../../models/learner_model.dart';
import '../../models/material_recommendation.dart' show LearnerProfile;
import '../../providers/stats_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../services/database.dart';
import '../../services/learner_model_store.dart';
import '../../services/tutor_engine.dart';
import '../../services/tutor_insights.dart';
import '../../services/tutor_snapshot.dart';
import '../../services/widget_service.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/v4/v4_kit.dart';
import '../../widgets/waiting.dart';
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

  /// 助理工作台数据(v3 批 4):五维现状 + 任务建议 + 复盘都由它一次性组装。
  TutorDashboard? _dash;

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
      // v3 批 4:一次组装「五维现状 + 任务建议 + 复盘」——
      // 数据来源统一在 TutorSnapshotService 里降级,页面不再各查各的。
      final dash = await TutorSnapshotService.load(
        vocab: vocab,
        dailyLogs: logs,
      );
      final snap = dash.snapshot;

      // 今日任务:没有就按**五维建议**落库一次(每天一份,不覆盖已有)。
      // 旧实现用 TutorEngine.planTasks(行为债规则);v3 改成 insight 驱动,
      // 每条任务自带"为什么"(reason)与 goalTag,复盘能按维度聚合。
      var rows = dash.todayTasks;
      if (rows.isEmpty && dash.suggestions.isNotEmpty) {
        for (final s in dash.suggestions) {
          await DatabaseService.insertTutorTask(
            planDate: snap.now,
            kind: s.action,
            title: s.title,
            targetMinutes: s.minutes,
            origin: 'auto',
            goalTag: s.goalTag,
            payload: {
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

      final msgs = await DatabaseService.getTutorMessages(limit: 20);
      if (!mounted) return;
      setState(() {
        _dash = dash;
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

  static String _dateKey(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)}';
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

  /// 任务"开始":只标成进行中(started_at),**不勾完成**(E1-6 的补漏)。
  ///
  /// 失败静默不弹窗:跳转已经发生,弹一个"标记失败"只会打断用户;
  /// 下次刷新任务仍显示待做,用户还能再点。
  Future<void> _startTask(Map<String, Object?> row) async {
    final id = row['id'];
    if (id is! int) return;
    try {
      await DatabaseService.updateTutorTaskStatus(id, 'active');
    } catch (_) {
      // 状态写失败不影响"开始去做"这件事本身
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

  /// 助理页统一外壳:主屏级果冻头 + 内容区。
  ///
  /// 为什么抽一个 _page:这一页有"骨架 / 读不到 / 正常"三种返回,以前只有正常态
  /// 有 AppBar —— 加载中会突然变成一块没有标题的白屏。统一外壳后三态都有头。
  Widget _page(Widget body) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            V4HeroHeader(
              domain: GraphicDomain.academic,
              eyebrow: '诊断 · 规划 · 复盘',
              title: '学习助理',
              subtitle: '先问清楚你的目标和水平,再给能执行的建议',
              chips: <Widget>[
                const V4GlassChip(
                  icon: Icons.insights_outlined,
                  label: '本地诊断,不花 API',
                ),
              ],
              actions: <Widget>[
                V4IconAction(
                  icon: Icons.block,
                  tooltip: '不想看的题材',
                  onTap: _openPreferences,
                ),
                V4IconAction(
                  icon: Icons.refresh,
                  tooltip: '重新诊断',
                  onTap: _refresh,
                ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (_loading) {
      // v2.12:这里以前是裸 `CircularProgressIndicator` —— 违反项目铁律
      // (界面里不许出现转圈,统一用等待三件套)。改成骨架屏,形状接近真实内容。
      return _page(
        const Padding(
          padding: Insets.page,
          child: SkeletonLines(lines: 6, seed: 0),
        ),
      );
    }
    final snap = _snapshot;
    if (snap == null) {
      return _page(
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('诊断数据暂时读不到'),
              const SizedBox(height: 8),
              FilledButton(onPressed: _refresh, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final findings = TutorEngine.diagnose(snap);

    return _page(
      ListView(
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

          // ── ② 现状分析:五维(词汇 / 语法 / 阅读 / 输出 / 习惯)──────────
          //
          // v3 批 4(用户 11/01):"学习现状分析意义不大……而是分析更精准更专业,
          // 想'词汇量xxx''语法xxx',然后每个大现状问题下对应的才是具体问题表现"。
          // 所以这里不再是"11 条互相独立的行为债提醒",而是**五个维度**:
          // 每个维度先给一个可核对的数字/状态,再给依据与下一步动作;
          // 没采到数据的维度显示"待测 + 怎么测",绝不编数字。
          AppStagger(
            index: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  title: '现状分析',
                  indexLabel: '01',
                ),
                ..._buildInsightCards(theme, muted),
                // 旧诊断规则(行为债)不删:它们仍能发现"攒了一堆到期词"这类事,
                // 但降为"更多提醒",不再占据五维的位置。
                if (findings.isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text(
                        '更多提醒(${findings.length})',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      children: [
                        for (final f in findings) _buildFindingCard(theme, f),
                      ],
                    ),
                  ),
                ],
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

          // ── ③ 学习任务(②的结论落成今天能做的事;可编辑、可自定义)──────
          AppStagger(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: AppSectionHeader(
                        title: '学习任务',
                        indexLabel: '02',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addCustomTask,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('自己加一条'),
                    ),
                  ],
                ),
                _buildPrimaryAction(theme, muted, snap),
                // 其余任务:每一条都能 开始 / 完成 / 跳过 / 编辑 / 撤销
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
                // 助理建议:只显示还没加进今天的(加过的会出现在任务列表里)
                ..._buildSuggestionCards(theme, muted),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),

          // ── ④ 复盘(近 7 天:计划 vs 实际,每条结论都带数字)────────────
          if (_dash != null && _dash!.review.metrics.isNotEmpty)
            AppStagger(
              index: 3,
              child: _buildReviewCard(theme, muted, _dash!.review),
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
      // v3 批 4:访谈改成多选目标后,优先显示多选清单(旧数据只有 goal 单值)
      if (model.goals.isNotEmpty)
        '目标 ${model.goals.join(' / ')}'
      else if ((model.goal?.value ?? '').isNotEmpty)
        '目标 ${model.goal!.value}',
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
                              // v3 补漏(E1-6):「开始」只把任务标成进行中再跳过去,
                              // **不再先勾完成** —— 旧实现点"开始"任务就变已完成,
                              // 用户根本还没做,复盘完成率因此虚高。
                              if (action != null) {
                                _startTask(first);
                                _jump(action, jumpArg);
                              } else {
                                _completeTask(first);
                              }
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

  // ── 五维现状 / 任务建议 / 复盘(v3 批 4)──────────────────────────

  Color _severityColor(int severity) => switch (severity) {
        2 => AppTheme.dangerColor(context),
        1 => AppTheme.warningColor(context),
        _ => AppTheme.successColor(context),
      };

  /// 语义跳转 id → 实际页面(见 [TutorActionJumps])。
  ///
  /// 为什么不在 insights 层硬编码页面类:页面会拆分/改名,而逻辑层不该跟着改。
  void _jumpByActionId(String id) {
    switch (id) {
      case TutorActionJumps.placement:
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
      case TutorActionJumps.review:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReviewScreen()),
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

  List<Widget> _buildInsightCards(ThemeData theme, Color muted) {
    final dash = _dash;
    if (dash == null || dash.insights.isEmpty) return const [];
    return [
      for (final insight in dash.insights.take(6))
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.xs),
          child: _buildInsightCard(theme, muted, insight),
        ),
    ];
  }

  /// 一个维度一张卡:维度名 + 可核对的值 + 依据 + 动作。
  ///
  /// "待测"维度的排版故意**更轻**(弱色、没有大数字):它不是一个"结果",
  /// 而是一个入口 —— 用户点进去测一次,下一次打开就变成真数字。
  Widget _buildInsightCard(
    ThemeData theme,
    Color muted,
    TutorInsight insight,
  ) {
    final cs = theme.colorScheme;
    final color = _severityColor(insight.severity);
    final label = TutorDimensions.labelOf(insight.dimension);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: insight.measured
                        ? color.withAlpha(20)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(Radii.control - 4),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: insight.measured ? color : muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    insight.title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (insight.measured && insight.valueText.isNotEmpty)
              Text(
                insight.valueText,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: 20,
                ),
              ),
            if (insight.measured && insight.valueText.isNotEmpty)
              const SizedBox(height: 2),
            Text(
              insight.evidence,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            if (insight.actionLabel != null && insight.actionJump != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _jumpByActionId(insight.actionJump!),
                  child: Text(insight.actionLabel!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 助理建议:还没加进今天的,给一条"加入今天"。
  List<Widget> _buildSuggestionCards(ThemeData theme, Color muted) {
    final dash = _dash;
    if (dash == null || dash.suggestions.isEmpty) return const [];
    final existing = _taskRows.map((r) => '${r['title'] ?? ''}').toSet();
    final pending = dash.suggestions
        .where((s) => !existing.contains(s.title))
        .toList();
    if (pending.isEmpty) return const [];
    return [
      const SizedBox(height: Gap.xs),
      Text(
        '助理建议',
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      for (final s in pending)
        Card(
          margin: const EdgeInsets.only(top: 6),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.minutes} 分钟 · ${s.reason}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _addSuggestedTask(s),
                  child: const Text('加入今天'),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  Future<void> _addSuggestedTask(TaskSuggestion suggestion) async {
    try {
      await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: suggestion.action,
        title: suggestion.title,
        targetMinutes: suggestion.minutes,
        origin: 'auto',
        goalTag: suggestion.goalTag,
        payload: {
          'reason': suggestion.reason,
          'jump': suggestion.action,
          'jumpArg': null,
        },
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加入失败:$e')));
    }
  }

  /// 自定义任务:用户说了算("支持用户编辑自定义"是用户点名的要求)。
  Future<void> _addCustomTask() async {
    final titleCtrl = TextEditingController();
    final minCtrl = TextEditingController(text: '15');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加一条自己的任务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              decoration: const InputDecoration(
                labelText: '预计分钟',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('加入今天')),
        ],
      ),
    );
    final title = titleCtrl.text.trim();
    final minutes = int.tryParse(minCtrl.text.trim()) ?? 15;
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
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('添加失败:$e')));
    }
  }

  /// 任务操作面板(开始 / 完成 / 跳过 / 撤销 / 编辑)。
  Future<void> _openTaskActions(Map<String, Object?> row) async {
    final id = row['id'];
    if (id is! int) return;
    final status = '${row['status'] ?? (row['done_at'] != null ? 'done' : 'pending')}';
    final payload = row['payload'];
    final jumpName = payload is Map ? '${payload['jump'] ?? ''}' : '';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
                child: Text(
                  '${row['title'] ?? '任务'}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (status != 'done' && status != 'active')
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('开始做'),
                  subtitle: const Text('标记为进行中,并跳到对应页面'),
                  onTap: () => Navigator.pop(ctx, 'active'),
                ),
              if (status != 'done')
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('标记完成'),
                  onTap: () => Navigator.pop(ctx, 'done'),
                ),
              if (status == 'done')
                ListTile(
                  leading: const Icon(Icons.undo),
                  title: const Text('撤销完成'),
                  onTap: () => Navigator.pop(ctx, 'pending'),
                ),
              if (status != 'skipped' && status != 'done')
                ListTile(
                  leading: const Icon(Icons.skip_next),
                  title: const Text('今天跳过'),
                  subtitle: const Text('跳过会记进复盘(算未完成),不会被忽略'),
                  onTap: () => Navigator.pop(ctx, 'skipped'),
                ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑标题 / 时长'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              const SizedBox(height: Gap.xs),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    if (action == 'edit') {
      await _renameTask(id, row);
      return;
    }
    try {
      await DatabaseService.updateTutorTaskStatus(id, action);
      await _refresh();
      if (action == 'active' && jumpName.isNotEmpty) {
        _jumpByActionId(jumpName);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新失败:$e')));
    }
  }

  Future<void> _renameTask(int id, Map<String, Object?> row) async {
    final titleCtrl = TextEditingController(text: '${row['title'] ?? ''}');
    final minCtrl =
        TextEditingController(text: '${_intOf(row['target_minutes'] ?? 15)}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑任务'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    final title = titleCtrl.text.trim();
    final minutes = int.tryParse(minCtrl.text.trim()) ?? 15;
    titleCtrl.dispose();
    minCtrl.dispose();
    if (ok != true || title.isEmpty) return;
    try {
      await DatabaseService.updateTutorTaskFields(
        id,
        title: title,
        targetMinutes: minutes.clamp(1, 600),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败:$e')));
    }
  }

  /// 复盘卡:近 7 天计划 vs 实际。每条结论都带数字(逻辑层保证)。
  Widget _buildReviewCard(ThemeData theme, Color muted, TutorReview review) {
    final cs = theme.colorScheme;
    final metrics = review.metrics;
    final planned = metrics['planned'] ?? 0;
    final done = metrics['done'] ?? 0;
    final rate = metrics['completionRate'];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '近 7 天复盘',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '计划 $planned · 完成 $done',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          if (rate != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (rate / 100).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: cs.outlineVariant.withAlpha(80),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '完成率 ${rate.toStringAsFixed(0)}%',
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
            const SizedBox(height: Gap.xs),
          ],
          for (final line in review.lines) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    line,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: muted, height: 1.45),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskCard(ThemeData theme, Map<String, Object?> row) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final id = row['id'];
    final status = '${row['status'] ?? (row['done_at'] != null ? 'done' : 'pending')}';
    final done = status == 'done' ||
        (id is int && _doneTaskIds.contains(id));
    final payload = row['payload'];
    final reason = payload is Map ? '${payload['reason'] ?? ''}' : '';
    final jumpName = payload is Map ? '${payload['jump'] ?? ''}' : '';
    final jumpArg = payload is Map ? payload['jumpArg'] as String? : null;
    final action = _parseAction(jumpName);
    final (String statusLabel, Color statusColor) = switch (status) {
      'done' => ('已完成', AppTheme.successColor(context)),
      'active' => ('进行中', theme.colorScheme.primary),
      'skipped' => ('已跳过', muted),
      'expired' => ('已过期', AppTheme.warningColor(context)),
      _ => ('待做', muted),
    };

    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openTaskActions(row),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            children: [
              IconButton(
                tooltip: done ? '点一下撤销完成' : '标记完成',
                // 完成态**不再禁用**:再点一下就是撤销完成(A5)
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${row['title'] ?? ''}',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration:
                                  done ? TextDecoration.lineThrough : null,
                              color: done ? muted : null,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: statusColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: statusColor),
                          ),
                        ),
                      ],
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
