import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../providers/stats_provider.dart';
import '../../services/learner_extras_sync.dart';
import '../../services/material_library.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/dash_kit.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/error_state.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/stats_chart.dart';
import '../../widgets/v4/v4_kit.dart';
import '../../widgets/waiting.dart';

/// 学习统计页。
///
/// v2.13(图形资产系统 · 批 1):把"文字 + 进度条"升级成**图 + 数字** ——
/// 近 7 天学习量用 [SparkBars]、近 7 天活跃率用 [RadialGauge]、
/// 30 天新增词汇用 [TrendLine](LearningCurveChart 内)、打卡用
/// [HeatmapCalendar](StudyCalendar 内)、月度新增词汇用 [SparkBars]。
///
/// 数据纪律(全页共用):只用 `StatsProvider` 里**真实存在**的字段;
/// 某个窗口没有任何记录时显示「暂无数据」,不画 0 分、不补假曲线。
/// 唯一"补"的东西是稀疏表缺失的日期补 0 —— 那天没有记录就是 0,不是编造。
class StatsPageScreen extends StatefulWidget {
  const StatsPageScreen({super.key});

  @override
  State<StatsPageScreen> createState() => _StatsPageScreenState();
}

class _StatsPageScreenState extends State<StatsPageScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // P2-10:进页立刻返回时 context 已经 deactivate,
      // 不加这道判断会抛错并被 CrashLogger 记成"崩溃",污染诊断日志
      if (!mounted) return;
      context.read<StatsProvider>().loadStats();
      // C1-15(批 8):统计页是"看整体数据"的幂等时机 —— 顺手把真实阅读速度
      // (近 30 天 avg_wpm)与词汇量测试基线回写进学习者模型 extras,供
      // LearnerContext 做难度/速度预估。值没变不会写盘;失败静默,不影响统计。
      unawaited(LearnerExtrasSync.syncAll());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = context.watch<StatsProvider>();
    final appBar = const V4JellyAppBar(
      title: '学习统计',
      domain: GraphicDomain.custom,
    );

    if (stats.loading) {
      return Scaffold(
        appBar: appBar,
        // v2.10:整页加载态不再转圈 —— 骨架屏先占住统计卡片的位置。内边距
        // 与下面真正的 ListView 一致(Insets.page),内容到达时位置不会跳。
        body: const Padding(
          padding: Insets.page,
          child: SkeletonLines(lines: 6, seed: 2),
        ),
      );
    }

    // P2-30:DB 读失败以前是"永久转圈"(provider 的 _loading 不复位),
    // 现在给明确原因 + 重试入口,而不是让用户以为 App 卡死
    if (stats.error != null) {
      return Scaffold(
        appBar: appBar,
        body: ErrorState(
          message: stats.error!,
          onRetry: () => context.read<StatsProvider>().loadStats(),
        ),
      );
    }

    final monthly = stats.getMonthlyStats();
    // 近 7 天:每日活动量(新收词 + 练习量)。稀疏表缺的日子由
    // dailySeriesOf 补 0 —— 那天确实没有记录,不是编数据。
    final weekSeries = dailySeriesOf(
      stats.dailyLogs,
      days: 7,
      pick: (r) => r.totalActivity,
    );
    final weekTotal = weekSeries.fold<double>(0, (sum, v) => sum + v).round();
    // 学习时长同口径取近 7 天(daily_log 的 study_minutes);为 0 时文案不出现,
    // 避免把"没记录"当成"0 分钟"。
    final weekMinutes = dailySeriesOf(
      stats.dailyLogs,
      days: 7,
      pick: (r) => r.studyMinutes,
    ).fold<double>(0, (sum, v) => sum + v).round();
    final activeDays7 = activeDaysOf(stats.dailyLogs, days: 7);

    return Scaffold(
      appBar: appBar,
      body: ListView(
        // v3(批 5):页面留白走设计 tokens —— 以前写死 16,别的屏是 20,
        // 两屏并排看"边距不一致"正是用户说的"不够统一"。
        padding: Insets.page,
        children: [
          // ── 数据内页 · A 诊断台:KPI 带(与助理复盘/错误档案同一排布)──
          DashKpiBand(
            items: <DashKpi>[
              DashKpi(label: '累计词汇', value: '${stats.totalVocab}', unit: '个'),
              DashKpi(
                label: '连续打卡',
                value: '${stats.streakDays}',
                unit: '天',
                color: theme.colorScheme.primary,
              ),
              DashKpi(
                label: '近 7 天活动',
                value: '$weekTotal',
                unit: weekTotal > 0 ? '' : '',
                color: weekTotal > 0
                    ? DashTheme.of(context).good
                    : DashTheme.of(context).inkFaint,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: Text(
              '活跃 $activeDays7/7 天'
              '${weekMinutes > 0 ? ' · 共 $weekMinutes 分钟' : ''}'
              ' · 口径:新收词 + 练习量',
              style: AppFont.metaStyle.copyWith(
                fontSize: 10.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // ── 最近在读(阅读进度自动同步到统计;没读过时整卡不显示)──
          const _ReadingInProgressCard(),

          const DashSectionTitle(
            index: '01',
            title: '学习节奏',
            trailing: '近 12 周',
          ),

          // ── 打卡热力图(近 12 周)──
          // v3(批 5):Card + Padding(16) 换成 AppCard/AppSectionTitle ——
          // 与「我的」页同一套卡片形态与内边距,两屏并排看才像一套设计。
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionTitle(
                  title: '学习打卡',
                  subtitle: '连续 ${stats.streakDays} 天 · 近 12 周',
                ),
                const SizedBox(height: Gap.md),
                // 热力图色阶与组件内部一致:空档 = 图形弱化色(极低 alpha),
                // 有活动 = 图表系列色四档 alpha。图例必须同源,否则深浅色下
                // 会出现"图例是浅蓝、格子是深蓝"对不上的情况。
                StudyCalendar(dailyLogs: stats.dailyLogs),
                const SizedBox(height: Gap.xs),
                Center(
                  child: Wrap(
                    spacing: Gap.md,
                    runSpacing: Gap.xxs,
                    alignment: WrapAlignment.center,
                    children: [
                      _LegendDot(
                        color: GraphicsPalette.faint(context).withAlpha(46),
                        label: '休息',
                      ),
                      _LegendDot(
                        color: AppTheme.chartSeries(context).withAlpha(70),
                        label: '少',
                      ),
                      _LegendDot(
                        color: AppTheme.chartSeries(context).withAlpha(120),
                        label: '中',
                      ),
                      _LegendDot(
                        color: AppTheme.chartSeries(context),
                        label: '多',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── 近 7 天学习量(柱状 + 活跃率环)──
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionTitle(
                  title: '近 7 天学习量',
                  subtitle: '新收词 + 练习量 · 左旧右新',
                  trailing: Text(
                    '合计 $weekTotal',
                    style: AppFont.metaStyle.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: Gap.md),
                if (weekTotal <= 0)
                  // 整周没有任何记录:不画一排 0 柱、不显示 0/7 的环 ——
                  // 那会被读成"系统给你打了 0 分",而事实是"这周没数据"。
                  // v3:空态用图形资产插画(AppEmpty 内含 EmptyArt),不再是灰图标。
                  AppEmptyState(
                    icon: Icons.query_stats_outlined,
                    title: '这 7 天还没有记录',
                    hint: '收词或做练习后,这里会出现每天的学习量',
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: SparkBars(
                          values: weekSeries,
                          height: 64,
                          semanticLabel: '近 7 天每日学习量(新收词 + 练习),共 $weekTotal',
                        ),
                      ),
                      const SizedBox(width: Gap.sm),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 环 = 近 7 天里有几天真的有活动(真实分母 7 天)。
                          // 只在有活动时出现,避免"0/7"被当成评分。
                          RadialGauge(
                            value: activeDays7 / 7,
                            size: 84,
                            tickCount: 0,
                            centerText: '$activeDays7/7',
                            semanticLabel: '近 7 天有 $activeDays7 天有学习记录',
                          ),
                          const SizedBox(height: Gap.xxs),
                          Text(
                            '活跃天',
                            style: AppFont.tagStyle.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  _WeekdayLabels(days: 7),
                  const SizedBox(height: Gap.xxs),
                  Text(
                    '新收词 + 练习量 · 左旧右新(复习记录没有逐日历史,不在此图)',
                    style: AppFont.metaStyle.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const DashSectionTitle(
            index: '02',
            title: '词汇增长',
            trailing: '近 30 天',
          ),

          // ── 学习曲线(近 30 天,图形:TrendLine)──
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionTitle(
                  title: '每日新增词汇',
                  subtitle: '近 30 天 · 来自每日学习日志',
                ),
                const SizedBox(height: Gap.md),
                LearningCurveChart(dailyLogs: stats.dailyLogs),
              ],
            ),
          ),

          // ── 月度统计(近 6 个月,图形:SparkBars)──
          if (monthly.isNotEmpty) _MonthlyCard(monthly: monthly),

          const SizedBox(height: Gap.xl),
        ],
      ),
    );
  }
}

/// 近 7 天的星期标签(与 SparkBars 的 7 根柱一一对应,左旧右新)。
///
/// 单独抽出来是因为月份/星期都要"按真实日期算",不能在页面里临时拼字符串 ——
/// 今天改变时标签要跟着变(周一/周日错位是这类小部件最常见的 bug)。
class _WeekdayLabels extends StatelessWidget {
  final int days;

  const _WeekdayLabels({required this.days});

  static const List<String> _labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: days - 1));
    final style = AppFont.tagStyle.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        for (var i = 0; i < days; i++)
          Expanded(
            child: Text(
              _labels[start.add(Duration(days: i)).weekday - 1],
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
      ],
    );
  }
}

/// 月度新增词汇卡。
///
/// 为什么只画最近 6 个月:`daily_log` 有 365 天,但一整年的 12 根柱在手机
/// 宽度上会糊成一排;6 根还能看清趋势,又足够说明"最近在涨还是在掉"。
class _MonthlyCard extends StatelessWidget {
  final Map<String, int> monthly;

  const _MonthlyCard({required this.monthly});

  static const int _maxMonths = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // key 形如 2026-09:字典序 = 时间序(定长补零),直接排序取最后 6 个
    final keys = monthly.keys.toList()..sort();
    final recent =
        keys.length > _maxMonths ? keys.sublist(keys.length - _maxMonths) : keys;
    final values =
        recent.map((k) => (monthly[k] ?? 0).toDouble()).toList(growable: false);
    final total = values.fold<double>(0, (sum, v) => sum + v).round();
    // v3(批 5):统一 AppCard + AppSectionTitle(与统计页其它卡、"我的"页同一套)。
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: '月度新增词汇',
            subtitle: '最近 ${recent.length} 个月 · 来自每日学习日志(左旧右新)',
            trailing: Text(
              '合计 $total 词',
              style: AppFont.metaStyle.copyWith(color: muted),
            ),
          ),
          const SizedBox(height: Gap.md),
          if (total <= 0)
            // 没有数据就明说,不画一排 0 柱(会被读成"每月都是 0 词")。
            AppEmptyState(
              icon: Icons.calendar_month_outlined,
              title: '还没有月度数据',
              hint: '收词后这里会按月统计新增词汇',
            )
          else ...[
            SparkBars(
              values: values,
              height: 72,
              semanticLabel: '最近 ${recent.length} 个月每月新增词汇,合计 $total 词',
            ),
            const SizedBox(height: Gap.xs),
            Row(
              children: [
                for (var i = 0; i < recent.length; i++)
                  Expanded(
                    child: Text(
                      _labelOf(recent[i]),
                      textAlign: TextAlign.center,
                      style: AppFont.tagStyle.copyWith(color: muted),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Gap.xxs),
            Text(
              '按每日学习日志里的新增词统计',
              style: AppFont.metaStyle.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }

  /// '2026-09' → '9月'(跨年也只看月份;柱状图只用于看最近趋势,不需要年份)
  static String _labelOf(String key) {
    final parts = key.split('-');
    if (parts.length < 2) return key;
    final month = int.tryParse(parts[1]);
    return month == null ? key : '$month月';
  }
}

/// 「最近在读」卡(v2.9,用户 10/2 第 4 条)
///
/// 读的是**阅读器正在写的那份进度**(`material_progress` 经 `MaterialLibrary.shelf`
/// 暴露出来),所以:用户在阅读器里读到 38% 退出,回统计页就能看到"38% · 还差 12 分钟"。
/// 没读过任何材料时**整卡不显示**(不给空卡占地方)。
///
/// v2.13:每篇的完成度从"一条进度条"改成 [RadialGauge] 小环 —— 三篇并排时
/// 环比三条长度相近的进度条更容易比较,也能把"还剩多少"留在正文里。
class _ReadingInProgressCard extends StatefulWidget {
  const _ReadingInProgressCard();

  @override
  State<_ReadingInProgressCard> createState() => _ReadingInProgressCardState();
}

class _ReadingInProgressCardState extends State<_ReadingInProgressCard> {
  List<ShelfItem> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final shelf = await MaterialLibrary.shelf(limit: 30);
      if (!mounted) return;
      setState(() {
        _items = shelf
            .where((s) => !s.finished && s.percent > 0)
            .take(3)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      debugPrint('读最近在读失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final totalMinutes = _items.fold<int>(0, (a, s) => a + s.minutesRead);
    // 在读写均完成度:小环给"这三本大概读到哪了",不必逐本比较数字。
    // 用 AppProgressRing(设计系统统一环)而不是自绘,保证与"我的"页一致。
    final avgPercent = _items.isEmpty
        ? 0
        : (_items.fold<double>(0, (a, s) => a + s.percent) / _items.length)
            .round();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: '最近在读',
            subtitle: '在读写均 $avgPercent% · 已读 $totalMinutes 分钟'
                '(进度由阅读器自动保存)',
            trailing: AppProgressRing(
              value: (avgPercent / 100).clamp(0.0, 1.0),
              centerText: '$avgPercent%',
              size: 52,
              stroke: 6,
            ),
          ),
          const SizedBox(height: Gap.sm),
          for (final s in _items) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.bodyStyle
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: Gap.xxs),
                      Text(
                        '还剩约 ${_left(s)} 分钟 · 已收 ${s.pickedWords} 词',
                        style: AppFont.tagStyle.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.xs),
                RadialGauge(
                  value: (s.percent / 100).clamp(0.0, 1.0),
                  size: 56,
                  tickCount: 0,
                  centerText: '${s.percent.round()}%',
                  semanticLabel: '《${s.title}》已读 ${s.percent.round()}%',
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
          ],
          Text(
            '退出阅读器也不用记进度,回来接着读;本周报告里也能看到这些材料。',
            style: AppFont.metaStyle.copyWith(color: muted),
          ),
        ],
      ),
    );
  }

  String _left(ShelfItem s) {
    final left = s.estMinutes - s.minutesRead;
    return '${left <= 0 ? 1 : left}';
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: Gap.xxs),
        Text(label,
            style: AppFont.tagStyle
                .copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
