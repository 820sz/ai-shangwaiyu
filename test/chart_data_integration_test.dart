import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/learning_record.dart';
import 'package:readflow/widgets/graphics/graphics.dart';
import 'package:readflow/widgets/stats_chart.dart';

/// 批 1(V1-5)数据图形接入的回归测试。
///
/// 这里守两条硬要求:
/// 1. **稀疏数据补齐口径**:`daily_log` 只有"有学过的日子"才有行,图要连续 N 天,
///    缺的日子必须补 0(是事实,不是编造),且顺序是"左旧右新";
/// 2. **0 数据不崩、不画 NaN**:空数据要落到「暂无数据」,不是一条假平线/0 分环;
///    自绘组件即使拿到 0/NaN/空数组也不能抛异常。
///
/// 为什么不测 StatsPage/WeeklyReport 整页:那两页要读 SQLite(真库),在
/// widget 测试里起库会拖慢并引入与本次改动无关的失败;页面级验证留给真机
/// (见汇报里的真机验证点),这里只钉住"数据 → 图形"这一层的契约。
void main() {
  group('dailySeriesOf — 稀疏日志补齐为连续 N 天', () {
    final now = DateTime(2026, 11, 1);

    test('缺的日子补 0,顺序左旧右新,最后一天是 today', () {
      final logs = <LearningRecord>[
        LearningRecord(date: DateTime(2026, 11, 1), newWordsCount: 3),
        LearningRecord(date: DateTime(2026, 10, 30), newWordsCount: 5),
      ];
      final series = dailySeriesOf(
        logs,
        days: 7,
        pick: (r) => r.newWordsCount,
        now: now,
      );
      expect(series.length, 7);
      expect(series.last, 3, reason: '最后一根柱 = 今天');
      expect(series[4], 5, reason: '10-30 是今天-2 天 → 下标 4');
      expect(series[0], 0, reason: '没记录的日子补 0');
      expect(series.any((v) => v.isNaN), isFalse, reason: '0 数据不能产生 NaN');
    });

    test('空日志 / days<=0:返回全 0 或空数组,不抛异常', () {
      expect(
        dailySeriesOf(const <LearningRecord>[], days: 7, pick: (r) => r.newWordsCount, now: now),
        everyElement(0.0),
      );
      expect(dailySeriesOf(const <LearningRecord>[], days: 0, pick: (r) => r.newWordsCount, now: now), isEmpty);
      expect(dailySeriesOf(const <LearningRecord>[], days: -3, pick: (r) => r.newWordsCount, now: now), isEmpty);
    });

    test('同一天多行时以后出现的为准(表应有唯一 date,坏数据也不能崩)', () {
      final logs = <LearningRecord>[
        LearningRecord(date: DateTime(2026, 10, 31), newWordsCount: 1),
        LearningRecord(date: DateTime(2026, 10, 31), newWordsCount: 9),
      ];
      final series = dailySeriesOf(logs, days: 2, pick: (r) => r.newWordsCount, now: now);
      expect(series.first, 9);
    });
  });

  group('activeDaysOf — 真实活跃天(分母由调用方给窗口天数)', () {
    final now = DateTime(2026, 11, 1);

    test('只算有活动的日子', () {
      final logs = <LearningRecord>[
        LearningRecord(date: DateTime(2026, 11, 1), newWordsCount: 2),
        LearningRecord(date: DateTime(2026, 10, 29), exerciseCompleted: 1),
        LearningRecord(date: DateTime(2026, 10, 20), newWordsCount: 9), // 窗口外
      ];
      expect(activeDaysOf(logs, days: 7, now: now), 2);
    });

    test('没有任何记录 → 0(由页面决定显示"暂无数据",不是 0 分)', () {
      expect(activeDaysOf(const <LearningRecord>[], days: 7, now: now), 0);
    });
  });

  group('0 数据 / 脏数据渲染', () {
    /// 统一套一层有界宽度:SparkBars/TrendLine 默认撑满父级,Column 里必须给宽度
    Future<void> pumpColumn(WidgetTester tester, List<Widget> children) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: Column(children: children),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('空日志:学习曲线与热力图显示「暂无数据」,不画 0 线/空格', (tester) async {
      await pumpColumn(tester, const [
        LearningCurveChart(dailyLogs: <LearningRecord>[]),
        StudyCalendar(dailyLogs: <LearningRecord>[]),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.text('暂无数据'), findsNWidgets(2));
      expect(find.byType(TrendLine), findsNothing, reason: '没有数据就不画曲线');
      expect(find.byType(HeatmapCalendar), findsNothing, reason: '没有数据就不点格子');
    });

    testWidgets('全是 0 的新增词 → 仍判"暂无数据"(不画一条假平线)', (tester) async {
      await pumpColumn(tester, [
        LearningCurveChart(dailyLogs: <LearningRecord>[
          LearningRecord(date: DateTime.now(), newWordsCount: 0),
        ]),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.text('暂无数据'), findsOneWidget);
      expect(find.byType(TrendLine), findsNothing);
    });

    testWidgets('有数据:能渲染 TrendLine 与 HeatmapCalendar,且不抛异常', (tester) async {
      final today = DateTime.now();
      await pumpColumn(tester, [
        LearningCurveChart(dailyLogs: <LearningRecord>[
          LearningRecord(date: today, newWordsCount: 4),
          LearningRecord(
            date: today.subtract(const Duration(days: 2)),
            newWordsCount: 9,
          ),
        ]),
        StudyCalendar(dailyLogs: <LearningRecord>[
          LearningRecord(date: today, newWordsCount: 3, exerciseCompleted: 1),
          LearningRecord(
            date: today.subtract(const Duration(days: 3)),
            newWordsCount: 6,
          ),
        ]),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.byType(TrendLine), findsOneWidget);
      expect(find.byType(HeatmapCalendar), findsOneWidget);
      expect(find.text('暂无数据'), findsNothing);
    });

    testWidgets('SparkBars / HeatmapCalendar / RadialGauge:全 0、空数组、NaN 都不崩', (tester) async {
      await pumpColumn(tester, const [
        SparkBars(values: <double>[0, 0, 0, 0, 0, 0, 0], width: 240, height: 56),
        HeatmapCalendar(levels: <int>[], weeks: 5, cell: 16),
        RadialGauge(value: 0, size: 72, tickCount: 0, centerText: '0/7'),
        RadialGauge(value: double.nan, size: 72, tickCount: 0, centerText: '—'),
      ]);
      expect(tester.takeException(), isNull);
    });
  });
}
