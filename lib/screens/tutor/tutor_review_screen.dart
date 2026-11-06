import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../models/learning_record.dart';
import '../../services/tutor_insights.dart';
import '../../services/tutor_snapshot.dart';
import '../../widgets/dash_kit.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/v4/v4_kit.dart';
import '../review/review_screen.dart';
import 'placement_test_screen.dart';
import 'tutor_task_detail_screen.dart';

/// 助理 ·「现状分析与复盘」页(A 诊断台语言)。
///
/// 为什么要独立成页:以前五维现状是首页 5 张卡、复盘是首页一张卡 ——
/// 用户"点不进去",也没法看明细。这一页把三件事放在一起:
/// 1. 五维现状(每个维度:值 + 依据 + 一条状态细条,没测到就写「待测」);
/// 2. 近 7 天计划 vs 实际(KPI 带 + 7 天柱 + 完成率环);
/// 3. 复盘结论(数据层 `TutorReview.lines` 原样呈现,页面不自己造句);
/// 4. 今天任务明细(点进 [TutorTaskDetailScreen] 做开始/完成/跳过/编辑)。
class TutorReviewScreen extends StatefulWidget {
  const TutorReviewScreen({
    super.key,
    required this.dashboard,
    this.dailyLogs,
    this.onChanged,
  });

  /// 首页已经组装好的数据(避免二次查库)
  final TutorDashboard dashboard;

  /// 近 7 天日志(可选;来自 StatsProvider,用于画柱状)
  final List<LearningRecord>? dailyLogs;

  /// 任何任务状态变化后通知外层刷新
  final Future<void> Function()? onChanged;

  @override
  State<TutorReviewScreen> createState() => _TutorReviewScreenState();
}

class _TutorReviewScreenState extends State<TutorReviewScreen> {
  late TutorDashboard _dash = widget.dashboard;
  late List<Map<String, Object?>> _tasks = widget.dashboard.todayTasks;

  Future<void> _reload() async {
    try {
      final TutorDashboard next = await TutorSnapshotService.load();
      if (!mounted) return;
      setState(() {
        _dash = next;
        _tasks = next.todayTasks;
      });
    } catch (_) {
      // 刷新失败保留旧数据(页面不至于变空)
    }
    await widget.onChanged?.call();
  }

  Future<void> _openTask(Map<String, Object?> row) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TutorTaskDetailScreen(row: row, onChanged: _reload),
      ),
    );
    if (!mounted) return;
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    final TutorReview review = _dash.review;
    final Map<String, num> m = review.metrics;
    final int planned = (m['planned'] ?? 0).toInt();
    final int done = (m['done'] ?? 0).toInt();
    final int settled = (m['settled'] ?? 0).toInt();
    final double? rate = m['completionRate']?.toDouble();
    final List<LearningRecord> logs = widget.dailyLogs ?? const <LearningRecord>[];
    final List<double> weekBars = _last7(logs, _dash.snapshot.now);

    return Scaffold(
      backgroundColor: d.skin.pageBg,
      appBar: const V4JellyAppBar(
        title: '现状与复盘',
        domain: GraphicDomain.academic,
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        color: d.accent,
        child: ListView(
          padding: Insets.page,
          children: <Widget>[
            DashKpiBand(
              items: <DashKpi>[
                DashKpi(label: '本周计划', value: '$planned', unit: '条'),
                DashKpi(label: '已完成', value: '$done', unit: '条', color: d.good),
                DashKpi(
                  label: '完成率',
                  value: rate == null ? '待测' : '${(rate * 100).round()}',
                  unit: rate == null ? '' : '%',
                  color: rate == null
                      ? d.inkFaint
                      : (rate >= 0.8 ? d.good : (rate < 0.5 ? d.warn : d.accent)),
                  size: rate == null ? 16 : 22,
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '近 7 天 · 已完成 $done / 已结算 $settled',
                    style: AppFont.metaStyle.copyWith(
                      fontSize: 10.5,
                      color: d.inkFaint,
                    ),
                  ),
                ),
                if (settled > 0)
                  Text(
                    '跳过 ${(m['skipped'] ?? 0).toInt()} 条',
                    style: AppFont.metaStyle.copyWith(
                      fontSize: 10.5,
                      color: d.inkFaint,
                    ),
                  ),
              ],
            ),

            // ── 01 五维现状 ──
            const DashSectionTitle(index: '01', title: '五维现状'),
            DashCard(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(
                children: <Widget>[
                  if (_dash.insights.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        '还没有可分析的维度 —— 先做一次词汇量速测,或收几个词。',
                        style: AppFont.bodyStyle.copyWith(
                          fontSize: 12,
                          height: 1.6,
                          color: d.inkSoft,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < _dash.insights.length; i++) ...<Widget>[
                      if (i > 0)
                        Divider(height: 1, thickness: 0.8, color: d.line),
                      _insightRow(context, d, _dash.insights[i]),
                    ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '细条 = 这一维当前状态(越满越稳;空 = 需要处理)。没测到的维度写「待测」,不编数字。',
                style: AppFont.metaStyle.copyWith(
                  fontSize: 10,
                  height: 1.5,
                  color: d.inkFaint,
                ),
              ),
            ),

            // ── 02 近 7 天 ──
            const DashSectionTitle(index: '02', title: '近 7 天学习节奏'),
            DashCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        '每日活动量',
                        style: AppFont.headingStyle.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: d.ink,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        weekBars.fold<double>(0, (double a, double b) => a + b) > 0
                            ? '合计 ${weekBars.fold<double>(0, (double a, double b) => a + b).round()}'
                            : '暂无记录',
                        style: AppFont.metaStyle.copyWith(
                          fontSize: 10.5,
                          color: d.inkFaint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  if (weekBars.fold<double>(0, (double a, double b) => a + b) <= 0)
                    Text(
                      '这 7 天没有学习记录 —— 收词或做一次练习后,这里会出现每天的量。',
                      style: AppFont.bodyStyle.copyWith(
                        fontSize: 12,
                        height: 1.6,
                        color: d.inkSoft,
                      ),
                    )
                  else
                    SparkBars(
                      values: weekBars,
                      height: 56,
                      semanticLabel: '近 7 天每日活动量',
                    ),
                  const SizedBox(height: Gap.sm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _kv(d, '计划投入', review.metrics['plannedMinutes'] == null
                            ? '未记录'
                            : '${review.metrics['plannedMinutes']!.round()} 分钟'),
                      ),
                      Expanded(
                        child: _kv(d, '实际投入', review.metrics['actualMinutes'] == null
                            ? '未记录'
                            : '${review.metrics['actualMinutes']!.round()} 分钟'),
                      ),
                      Expanded(
                        child: _kv(d, '输出练习', review.metrics['outputCount'] == null
                            ? '未记录'
                            : '${review.metrics['outputCount']!.round()} 次'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── 03 复盘结论 ──
            const DashSectionTitle(index: '03', title: '复盘结论'),
            DashCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (review.lines.isEmpty)
                    Text(
                      '还没有可复盘的记录 —— 完成或跳过一条任务后,这里会给出完成率与偏差。',
                      style: AppFont.bodyStyle.copyWith(
                        fontSize: 12,
                        height: 1.6,
                        color: d.inkSoft,
                      ),
                    )
                  else
                    for (var i = 0; i < review.lines.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '${i + 1}'.padLeft(2, '0'),
                              style: AppFont.tagStyle.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: d.accent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                review.lines[i],
                                style: AppFont.bodyStyle.copyWith(
                                  fontSize: 12.5,
                                  height: 1.7,
                                  color: d.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),

            // ── 04 今天任务 ──
            const DashSectionTitle(index: '04', title: '今天的任务'),
            DashCard(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(
                children: <Widget>[
                  if (_tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        '今天还没有任务。回首页可以「自己加一条」,或让助理按现状给建议。',
                        style: AppFont.bodyStyle.copyWith(
                          fontSize: 12,
                          height: 1.6,
                          color: d.inkSoft,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < _tasks.length; i++) ...<Widget>[
                      if (i > 0) Divider(height: 1, thickness: 0.8, color: d.line),
                      _taskRow(context, d, _tasks[i]),
                    ],
                ],
              ),
            ),
            const SizedBox(height: Gap.xl),
          ],
        ),
      ),
    );
  }

  Widget _insightRow(BuildContext context, DashTheme d, TutorInsight insight) {
    final String label = TutorDimensions.labelOf(insight.dimension);
    final Color c = dashSeverityColor(context, insight.severity);
    // 条长只是 severity 的视觉编码(不是编出来的指标):越满越稳
    final double ratio = switch (insight.severity) {
      0 => 0.92,
      1 => 0.55,
      _ => 0.28,
    };
    if (!insight.measured) {
      return DashMetricRow(
        label: label,
        value: '待测',
        measured: false,
        evidence: insight.evidence.isEmpty
            ? '还没有这一维的数据 —— 做一次词汇量速测,或先完成一次相关练习。'
            : insight.evidence,
        onTap: insight.actionJump == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const PlacementTestScreen(full: false),
                  ),
                ),
      );
    }
    return DashMetricRow(
      label: label,
      value: insight.valueText.isEmpty ? '—' : insight.valueText,
      evidence: insight.title,
      ratio: ratio,
      color: c,
      onTap: insight.actionLabel == null || insight.actionJump == null
          ? null
          : () => _onInsightAction(insight),
    );
  }

  void _onInsightAction(TutorInsight insight) {
    final String? jump = insight.actionJump;
    if (jump == null) return;
    switch (jump) {
      case TutorActionJumps.placement:
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const PlacementTestScreen(full: false)),
        );
      case TutorActionJumps.review:
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const ReviewScreen()),
        );
      default:
        break;
    }
  }

  Widget _taskRow(BuildContext context, DashTheme d, Map<String, Object?> row) {
    final Object? payload = row['payload'];
    final String reason = payload is Map ? '${payload['reason'] ?? ''}'.trim() : '';
    final Object? min = row['target_minutes'];
    final String status = '${row['status'] ?? (row['done_at'] != null ? 'done' : 'pending')}';
    final String statusLabel = switch (status) {
      'done' => '已完成',
      'skipped' => '已跳过',
      'active' => '进行中',
      _ => '待做',
    };
    final String subtitle = <String>[
      if (min != null) '$min 分钟',
      if (reason.isNotEmpty) reason,
    ].join(' · ');
    return DashListRow(
      title: '${row['title'] ?? '（未命名任务）'}',
      subtitle: subtitle.isEmpty ? '点击看详情与操作' : subtitle,
      trailingText: statusLabel,
      onTap: () => _openTask(row),
    );
  }

  Widget _kv(DashTheme d, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: AppFont.bodyStyle.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: d.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppFont.metaStyle.copyWith(fontSize: 10, color: d.inkFaint),
        ),
      ],
    );
  }

  static List<double> _last7(List<LearningRecord> logs, DateTime at) {
    final Map<String, double> byDay = <String, double>{};
    for (final LearningRecord r in logs) {
      final String key = '${r.date.year}-${r.date.month}-${r.date.day}';
      byDay[key] = (byDay[key] ?? 0) + r.totalActivity.toDouble();
    }
    final List<double> out = <double>[];
    for (var i = 6; i >= 0; i--) {
      final DateTime day = at.subtract(Duration(days: i));
      out.add(byDay['${day.year}-${day.month}-${day.day}'] ?? 0);
    }
    return out;
  }
}
