import 'package:flutter/material.dart';

import '../models/learning_record.dart';
import 'graphics/graphics.dart';

/// 统计页 / 周报共用的**逐日数据抽取**(纯函数,不碰 DB、不读时钟)。
///
/// 为什么抽出来:`daily_log` 是**稀疏表** —— 只有当天有收词/练习才有一行,
/// 没学习的日子根本没有行。而折线/柱状图要的是"连续的 N 天",缺的那天必须补 0
/// (补 0 是事实:那天确实没有记录,不是编数据)。两处页面各写一遍很容易出现
/// "一边补齐、一边漏天",图和数字就对不上。
///
/// [now] 可注入(测试/回看历史周期用);默认取系统当前时间。
List<double> dailySeriesOf(
  List<LearningRecord> logs, {
  required int days,
  required int Function(LearningRecord record) pick,
  DateTime? now,
}) {
  if (days <= 0) return const <double>[];
  final byDay = <String, int>{};
  for (final r in logs) {
    byDay[LearningRecord.dateKey(r.date)] = pick(r);
  }
  final anchor = now ?? DateTime.now();
  final today = DateTime(anchor.year, anchor.month, anchor.day);
  return List<double>.generate(days, (i) {
    final date = today.subtract(Duration(days: days - 1 - i));
    return (byDay[LearningRecord.dateKey(date)] ?? 0).toDouble();
  }, growable: false);
}

/// 近 [days] 天里**有活动**的天数(activity > 0)。
///
/// 用来算"近 7 天活跃率"这类真实比率 —— 分母是窗口天数,分子是真实活动日;
/// 没有数据时由调用方决定显示"暂无数据"而不是 0 分。
int activeDaysOf(
  List<LearningRecord> logs, {
  required int days,
  DateTime? now,
}) {
  final series = dailySeriesOf(
    logs,
    days: days,
    pick: (r) => r.totalActivity,
    now: now,
  );
  return series.where((v) => v > 0).length;
}

/// 学习曲线(近 30 天每日新增词汇)。
///
/// v2.13(图形资产系统 · 批 1):从 `fl_chart` 换成自绘 [TrendLine]。
/// 为什么换:这一块只需要"一眼看个大概"的趋势形,不需要坐标系/手势/tooltip;
/// 自绘组件明暗两套自适应、零交互依赖,和统计页其它新图形是一套笔触。
/// 数据口径不变:仍是 `daily_log.new_words_count`,空数据不画线。
class LearningCurveChart extends StatelessWidget {
  final List<LearningRecord> dailyLogs;

  const LearningCurveChart({super.key, required this.dailyLogs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    const windowDays = 30;
    final series = dailySeriesOf(
      dailyLogs,
      days: windowDays,
      pick: (r) => r.newWordsCount,
    );
    final total = series.fold<double>(0, (sum, v) => sum + v);
    // 一条全是 0 的线看起来像"失败渲染",也容易被误读成"数据就是这样";
    // 宁可明说没有数据,也不画一条假平线。
    if (series.isEmpty || total <= 0) {
      return const ChartEmptyHint(
        label: '暂无数据',
        hint: '收集生词或做练习后,这里会画出 30 天趋势',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrendLine(
          points: series,
          height: 96,
          semanticLabel: '近 30 天每日新增词汇趋势,合计 ${total.round()} 词',
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '近 $windowDays 天每日新增词汇',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const Spacer(),
            Text(
              '合计 ${total.round()} 词',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 打卡热力图(近 12 周)。
///
/// v2.13:用 [HeatmapCalendar] 替换手搓的 5×7 小方块 —— 同一份
/// `daily_log` 数据,但格子铺满卡片宽度、强度 4 档由组件统一处理,
/// 明暗两套色阶只在一处维护。
///
/// 口径说明:`daily_log` 目前只记录**新收词**与**练习量**(复习结果落在
/// `word_review`,没有逐日历史),所以这里的"活动量"= new_words + exercise;
/// 页面会把这条口径如实写在图下方,不把它说成"所有学习活动"。
class StudyCalendar extends StatelessWidget {
  final List<LearningRecord> dailyLogs;

  const StudyCalendar({super.key, required this.dailyLogs});

  /// 一次显示 12 周(84 天):比原来的 5 周更有"坚持感",又不至于让卡片太高。
  static const int _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (dailyLogs.isEmpty) {
      return const ChartEmptyHint(
        label: '暂无数据',
        hint: '有学习记录后,这里会按天点亮格子',
      );
    }
    final counts = dailySeriesOf(
      dailyLogs,
      days: _weeks * 7,
      pick: (r) => r.totalActivity,
    ).map((v) => v.round()).toList(growable: false);
    final levels = HeatmapCalendar.tiersOf(counts);
    const gap = 3.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) {
            // 组件宽度 = weeks*cell + (weeks-1)*gap;用可用宽度反推单格边长,
            // 再夹到 [10,18]:太大会让卡片变成一整块、太小又看不清格子
            final raw = (constraints.maxWidth - (_weeks - 1) * gap) / _weeks;
            final cell = raw.clamp(10.0, 18.0);
            return Center(
              child: HeatmapCalendar(
                levels: levels,
                weeks: _weeks,
                cell: cell,
                gap: gap,
                semanticLabel: '近 $_weeks 周学习热力图:颜色越深当天新收词与练习越多',
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '每格 = 当天新收词 + 练习量(复习记录按词存,没有逐日历史)',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// 图表空态:统一样式,避免三处各写一遍"暂无数据"的排版。
///
/// 公开而不是私有:统计页与周报的空态要求是同一条("没数据就明说,
/// 不画 0 分"),两处共用一个实现,文案与留白才不会漂。
class ChartEmptyHint extends StatelessWidget {
  final String label;
  final String hint;

  const ChartEmptyHint({super.key, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(Icons.query_stats_outlined, size: 22, color: muted),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
