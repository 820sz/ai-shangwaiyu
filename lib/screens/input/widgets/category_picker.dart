import 'package:flutter/material.dart';
import '../../../config/constants.dart';
import '../../../config/v4_theme.dart';

/// 分类选择 BottomSheet — 返回分类名字符串，用户取消返回 null
Future<String?> showCategoryPicker(BuildContext context) {
  // 必须在弹窗外捕获，showModalBottomSheet 内部 MediaQuery.padding.bottom = 0
  final bottomSafe = MediaQuery.of(context).padding.bottom;
  return showModalBottomSheet<String>(
    context: context,
    // 默认 isScrollControlled=false 会把弹窗高度锁死在屏高 9/16,
    // 内容超高(小屏/字体放大)时必然 overflow,放开限制配合滚动
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (ctx) => _CategoryPickerSheet(bottomSafe: bottomSafe),
  );
}

class _CategoryPickerSheet extends StatelessWidget {
  final double bottomSafe;
  const _CategoryPickerSheet({required this.bottomSafe});

  // 图标映射
  static const _icons = <String, IconData>{
    '教材': Icons.school,
    '书籍': Icons.menu_book,
    '外刊': Icons.article,
    '碎片文章': Icons.auto_stories,
    '其他': Icons.folder,
  };

  static const _subtitles = <String, String>{
    '教材': '课本、习题集、考试资料',
    '书籍': '原著、小说、非虚构',
    '外刊': '新闻、杂志、期刊',
    '碎片文章': '网页、短文、摘录',
    '其他': '未分类的学习材料',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skin = V4Skin.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomSafe),
      // 内容超高时允许滚动,不再溢出
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽条用系统主题自带的(这里不再画第二条)
            Text(
              '选择保存分类',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                color: skin.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '将生词归类,方便后续复习和查找',
              style: TextStyle(fontSize: 11.5, color: skin.inkSoft),
            ),
            const SizedBox(height: 16),
            // 分类网格(2列)
            ..._buildGrid(context, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGrid(BuildContext context, ThemeData theme) {
    final cats = AppConstants.learningCategories;
    final rows = <Widget>[];
    for (int i = 0; i < cats.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: _CategoryCard(
                  name: cats[i],
                  icon: _icons[cats[i]] ?? Icons.folder,
                  subtitle: _subtitles[cats[i]] ?? '',
                  onTap: () => Navigator.pop(context, cats[i]),
                ),
              ),
              if (i + 1 < cats.length) const SizedBox(width: 10),
              if (i + 1 < cats.length)
                Expanded(
                  child: _CategoryCard(
                    name: cats[i + 1],
                    icon: _icons[cats[i + 1]] ?? Icons.folder,
                    subtitle: _subtitles[cats[i + 1]] ?? '',
                    onTap: () => Navigator.pop(context, cats[i + 1]),
                  ),
                )
              else
                // 奇数个分类时补一个空位,让最后一张保持半宽而不是被拉通栏
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return rows;
  }
}

class _CategoryCard extends StatelessWidget {
  final String name;
  final IconData icon;
  final String subtitle;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    required this.icon,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: skin.hairline),
          boxShadow: skin.shadow,
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: skin.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: skin.accent),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: skin.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: skin.inkSoft,
                fontSize: 10,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
