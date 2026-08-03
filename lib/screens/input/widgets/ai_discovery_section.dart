import 'package:flutter/material.dart';
import '../../../config/constants.dart';
import '../ai_material_search.dart';

/// 板块3：其他输入材料 — AI 推荐学习资源（实验性功能）
class AiDiscoverySection extends StatelessWidget {
  const AiDiscoverySection({super.key});

  static const _icons = <String, IconData>{
    '教材': Icons.school,
    '书籍': Icons.menu_book,
    '外刊': Icons.article,
    '碎片文章': Icons.auto_stories,
    '其他': Icons.folder,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Icon(Icons.explore, color: theme.colorScheme.primary),
        title: Row(
          children: [
            Text(
              '其他输入材料',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Text(
                '实验性',
                style: TextStyle(fontSize: 9, color: Colors.amber[800]),
              ),
            ),
          ],
        ),
        subtitle: const Text(
          'AI 帮您搜索学习资源，点击分类开始探索',
          style: TextStyle(fontSize: 11),
        ),
        children: [
          // 分类网格（2列）
          ..._buildGrid(context, theme),
          const SizedBox(height: 8),
          Text(
            '提示：该功能由 AI 实时搜索推荐，效果取决于模型能力，仅供参考。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey[400],
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGrid(BuildContext context, ThemeData theme) {
    final cats = AppConstants.learningCategories;
    final rows = <Widget>[];
    for (int i = 0; i < cats.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: _DiscoveryCard(
                  name: cats[i],
                  icon: _icons[cats[i]] ?? Icons.folder,
                  onTap: () => _navigateToSearch(context, cats[i]),
                ),
              ),
              if (i + 1 < cats.length) const SizedBox(width: 8),
              if (i + 1 < cats.length)
                Expanded(
                  child: _DiscoveryCard(
                    name: cats[i + 1],
                    icon: _icons[cats[i + 1]] ?? Icons.folder,
                    onTap: () => _navigateToSearch(context, cats[i + 1]),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  void _navigateToSearch(BuildContext context, String category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiMaterialSearchScreen(category: category),
      ),
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final VoidCallback onTap;

  const _DiscoveryCard({
    required this.name,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
