import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/stats_provider.dart';
import '../../widgets/error_state.dart';
import '../../widgets/stats_chart.dart';

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = context.watch<StatsProvider>();
    final appBar = AppBar(title: const Text('学习统计'));

    if (stats.loading) {
      return Scaffold(
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
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

    return Scaffold(
      appBar: appBar,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 连续打卡日历 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_fire_department,
                          color: Colors.orange),
                      const SizedBox(width: 6),
                      Text(
                        '已连续学习 ${stats.streakDays} 天',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: StudyCalendar(dailyLogs: stats.dailyLogs),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LegendDot(color: Colors.grey.withAlpha(30), label: '休息'),
                      const SizedBox(width: 12),
                      _LegendDot(
                          color: const Color(0xFF4A90D9).withAlpha(60),
                          label: '少量'),
                      const SizedBox(width: 12),
                      _LegendDot(
                          color: const Color(0xFF4A90D9).withAlpha(120),
                          label: '中等'),
                      const SizedBox(width: 12),
                      _LegendDot(
                          color: const Color(0xFF4A90D9), label: '丰富'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 学习曲线 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('每日新增词汇',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  LearningCurveChart(dailyLogs: stats.dailyLogs),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 月度统计 ──
          if (monthly.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('月度统计',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ...monthly.entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Text(e.key,
                                  style: const TextStyle(fontSize: 13)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: stats.totalVocab > 0
                                        ? e.value / (stats.totalVocab * 1.5)
                                        : 0,
                                    minHeight: 8,
                                    backgroundColor:
                                        theme.colorScheme.surfaceContainerHighest,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${e.value}词',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
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
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
