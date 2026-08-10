import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/stats_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../providers/article_provider.dart';
import '../../widgets/stats_chart.dart';
import '../../widgets/update_dialog.dart';
import '../../services/update_service.dart';
import 'vocab_list.dart';
import 'stats_page.dart';
import 'api_settings.dart';

class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({super.key});

  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  String _advice = '';
  bool _loadingAdvice = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAll();
    });
  }

  Future<void> _loadAll() async {
    await Future.wait([
      context.read<StatsProvider>().loadStats(),
      context.read<VocabProvider>().loadVocabularies(),
    ]);
    _loadAdvice();
  }

  Future<void> _loadAdvice() async {
    final stats = context.read<StatsProvider>();
    final vocab = context.read<VocabProvider>();
    final articleProv = context.read<ArticleProvider>();

    if (stats.totalVocab < 5) return; // 数据太少不推荐

    setState(() => _loadingAdvice = true);
    try {
      final result = await articleProv.getPersonalizedAdvice(
        totalVocab: stats.totalVocab,
        masteredVocab: 0, // TODO: 从 vocab 统计掌握数
        streakDays: stats.streakDays,
        vocabByBook: vocab.vocabByBook,
      );
      if (mounted) setState(() => _advice = result);
    } catch (_) {
      // 静默失败
    }
    if (mounted) setState(() => _loadingAdvice = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = context.watch<StatsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 统计卡片 ──
            Row(
              children: [
                _StatCard(
                    icon: Icons.menu_book,
                    value: '${stats.totalVocab}',
                    label: '总词汇量',
                    color: Colors.blue),
                const SizedBox(width: 10),
                _StatCard(
                    icon: Icons.local_fire_department,
                    value: '${stats.streakDays}',
                    label: '连续天数',
                    color: Colors.orange),
                const SizedBox(width: 10),
                _StatCard(
                    icon: Icons.fitness_center,
                    value: '${stats.totalExercises}',
                    label: '已完成练习',
                    color: Colors.green),
              ],
            ),
            const SizedBox(height: 20),

            // ── 快速入口 ──
            _MenuTile(
              icon: Icons.book,
              title: '我的生词本',
              subtitle: '按书籍分类，可跳转原文',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VocabListScreen()),
              ),
            ),
            _MenuTile(
              icon: Icons.bar_chart,
              title: '学习统计',
              subtitle: '曲线图、日历热力图',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StatsPageScreen()),
              ),
            ),
            _MenuTile(
              icon: Icons.settings,
              title: 'API 设置',
              subtitle: '配置豆包和 DeepSeek API Key',
              onTap: () => _showSettings(),
            ),
            _MenuTile(
              icon: Icons.system_update_alt,
              title: '检查更新',
              subtitle: '检查 GitHub 最新版本',
              onTap: () async {
                try {
                  final info = await UpdateService.checkLatestRelease();
                  if (!context.mounted) return;
                  if (info == null || !info.hasUpdate) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('当前已是最新版本')),
                    );
                  } else {
                    showUpdateDialog(context, info);
                  }
                } catch (e) {
                  // F3:检查失败(网络全断)必须明说,不能伪装成"已是最新"
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('检查更新失败:$e')),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 16),

            // ── 学习曲线预览 ──
            if (stats.dailyLogs.isNotEmpty) ...[
              Text('学习趋势',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              LearningCurveChart(dailyLogs: stats.dailyLogs),
            ],

            const SizedBox(height: 20),

            // ── AI 建议 ──
            if (_loadingAdvice)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_advice.isNotEmpty) ...[
              Text('AI 学习建议',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Card(
                color: theme.colorScheme.primary.withAlpha(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          color: Colors.amber, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _advice,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
