import 'package:flutter/material.dart';

/// AI 推荐的学习材料结果卡片
class MaterialSearchResultCard extends StatelessWidget {
  final String name;
  final String description;
  final String level;
  final String keywords;

  const MaterialSearchResultCard({
    super.key,
    required this.name,
    required this.description,
    required this.level,
    required this.keywords,
  });

  /// 难度标签颜色
  static Color _levelColor(String level) {
    final upper = level.toUpperCase();
    if (upper.startsWith('A1')) return Colors.green;
    if (upper.startsWith('A2')) return Colors.lightGreen;
    if (upper.startsWith('B1')) return Colors.blue;
    if (upper.startsWith('B2')) return Colors.indigo;
    if (upper.startsWith('C1')) return Colors.orange;
    if (upper.startsWith('C2')) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 名称行
            Text(
              name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            // 简介
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            // 底部标签行
            Row(
              children: [
                // 难度标签
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _levelColor(level).withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    level.isNotEmpty ? level.toUpperCase() : '未知',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _levelColor(level),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 关键词
                if (keywords.isNotEmpty)
                  Expanded(
                    child: Text(
                      keywords,
                      style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
