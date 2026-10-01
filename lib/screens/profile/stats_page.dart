import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/stats_provider.dart';
import '../../services/material_library.dart';
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
          // ── 最近在读(v2.9,用户 10/2 第 4 条)──
          // 用户原话:"材料中心阅读的那些材料阅读的进度,要自动同步留存,
          // 以及同步到'学习统计''本周报告'里。"
          // 阅读器把进度写进 material_progress,这里把同一份进度读出来 ——
          // 用户在阅读器里读到哪儿,统计页立刻看得到,不用再回去翻。
          const _ReadingInProgressCard(),
          const SizedBox(height: 12),
          // ── 连续打卡日历 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_fire_department,
                          color: AppTheme.warningColor(context)),
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
                      // 图例色必须与 StudyCalendar 的格子同色系(那边用
                      // scheme.primary 三档透明度 + 休息格 surfaceContainerHighest),
                      // 否则深色下"图例是浅蓝、格子是深蓝"对不上
                      _LegendDot(
                          color: theme.colorScheme.surfaceContainerHighest,
                          label: '休息'),
                      const SizedBox(width: 12),
                      _LegendDot(
                          color: theme.colorScheme.primary.withAlpha(60),
                          label: '少量'),
                      const SizedBox(width: 12),
                      _LegendDot(
                          color: theme.colorScheme.primary.withAlpha(120),
                          label: '中等'),
                      const SizedBox(width: 12),
                      _LegendDot(
                          color: theme.colorScheme.primary, label: '丰富'),
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

/// 「最近在读」卡(v2.9,用户 10/2 第 4 条)
///
/// 读的是**阅读器正在写的那份进度**(`material_progress` 经 `MaterialLibrary.shelf`
/// 暴露出来),所以:用户在阅读器里读到 38% 退出,回统计页就能看到"38% · 还差 12 分钟"。
/// 没读过任何材料时**整卡不显示**(不给空卡占地方)。
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
    final totalMinutes = _items.fold<int>(0, (a, s) => a + s.minutesRead);    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_stories_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('最近在读',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('已读 $totalMinutes 分钟',
                    style: TextStyle(fontSize: 11.5, color: muted)),
              ],
            ),
            const SizedBox(height: 10),
            for (final s in _items) ...[
              Text(s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (s.percent / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${s.progressLabel} · 还剩约 ${_left(s)} 分钟 · 已收 ${s.pickedWords} 词',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '进度在阅读器里自动保存(退出也不用记);本周报告里也能看到这些材料。',
              style: TextStyle(fontSize: 10.5, height: 1.4, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  String _left(ShelfItem s) {
    final left = s.estMinutes - s.minutesRead;
    return '${left <= 0 ? 1 : left}';
  }
}

class _LegendDot extends StatelessWidget {  final Color color;
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
