import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/learning_record.dart';

/// 学习曲线图
class LearningCurveChart extends StatelessWidget {
  final List<LearningRecord> dailyLogs;

  const LearningCurveChart({super.key, required this.dailyLogs});

  @override
  Widget build(BuildContext context) {
    if (dailyLogs.isEmpty) {
      return Center(
        child: Text('暂无学习数据',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    // 取最近 30 天
    final recent = dailyLogs.length > 30
        ? dailyLogs.sublist(dailyLogs.length - 30)
        : dailyLogs;

    final maxWords = recent
        .map((r) => r.newWordsCount)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxWords > 0 ? (maxWords / 4).ceilToDouble() : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withAlpha(30),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}',
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 7,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= recent.length) return const Text('');
                  return Text(
                    '${recent[index].date.month}/${recent[index].date.day}',
                    style: TextStyle(
                        fontSize: 9,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: maxWords > 0 ? maxWords * 1.2 : 5,
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(recent.length,
                  (i) => FlSpot(i.toDouble(), recent[i].newWordsCount.toDouble())),
              isCurved: true,
              color: const Color(0xFF4A90D9),
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: recent.length <= 14,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: const Color(0xFF4A90D9),
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF4A90D9).withAlpha(30),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final index = spot.spotIndex;
                  final record = recent[index];
                  return LineTooltipItem(
                    '${record.date.month}月${record.date.day}日\n${record.newWordsCount} 个新词',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 学习日历热力图
class StudyCalendar extends StatelessWidget {
  final List<LearningRecord> dailyLogs;

  const StudyCalendar({super.key, required this.dailyLogs});

  @override
  Widget build(BuildContext context) {
    if (dailyLogs.isEmpty) {
      return Center(
        child: Text('暂无打卡记录',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    // 构建日期→活动量映射
    final dateMap = <DateTime, int>{};
    for (final r in dailyLogs) {
      dateMap[DateTime(r.date.year, r.date.month, r.date.day)] =
          r.totalActivity;
    }

    // 显示最近 5 周
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weeks = <List<DateTime?>>[];
    final startDate = today.subtract(const Duration(days: 34));
    var cursor = startDate;

    // 对齐到周日
    while (cursor.weekday != DateTime.sunday) {
      cursor = cursor.subtract(const Duration(days: 1));
    }

    for (int w = 0; w < 5; w++) {
      final week = <DateTime?>[];
      for (int d = 0; d < 7; d++) {
        final date = cursor.add(Duration(days: w * 7 + d));
        if (date.isAfter(today)) {
          week.add(null);
        } else {
          week.add(date);
        }
      }
      weeks.add(week);
    }

    return Column(
      children: weeks.map((week) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: week.map((date) {
              if (date == null) return const _DayCell(color: Colors.transparent);
              final activity = dateMap[date] ?? 0;
              return _DayCell(
                color: _activityColor(activity),
                tooltip: '${date.month}/${date.day}: $activity',
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Color _activityColor(int activity) {
    if (activity == 0) return Colors.grey.withAlpha(30);
    if (activity <= 5) return const Color(0xFF4A90D9).withAlpha(60);
    if (activity <= 15) return const Color(0xFF4A90D9).withAlpha(120);
    return const Color(0xFF4A90D9);
  }
}

class _DayCell extends StatelessWidget {
  final Color color;
  final String? tooltip;

  const _DayCell({required this.color, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
