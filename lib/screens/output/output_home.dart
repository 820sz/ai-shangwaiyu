import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../writing/write_review_screen.dart';
import '../writing/writing_logs_screen.dart';

/// 输出页(v1.8.0):
/// - 「AI 生词定制文章」已迁到「输入」页(特色功能),这里不再重复
/// - 输出页专注于"写"的东西:写译批改 + 写译记录
class OutputHomeScreen extends StatefulWidget {
  const OutputHomeScreen({super.key});

  @override
  State<OutputHomeScreen> createState() => _OutputHomeScreenState();
}

class _OutputHomeScreenState extends State<OutputHomeScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('输出')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _entryCard(
            theme,
            icon: Icons.edit_note,
            title: '写译批改',
            subtitle: '手写 / 电子稿 → AI 批改',
            highlighted: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WriteReviewScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _entryCard(
            theme,
            icon: Icons.history_edu_outlined,
            title: '写译记录',
            subtitle: '按日期查阅与复盘',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WritingLogsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      color: highlighted ? theme.colorScheme.primary.withAlpha(12) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Icon(
                icon,
                size: 26,
                color: highlighted
                    ? theme.colorScheme.primary
                    : AppTheme.amber(context),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
