import 'package:flutter/material.dart';
import '../../../config/constants.dart';

/// 分析模式选择 BottomSheet
/// 返回 'marked' 或 'fullText'，null 表示取消
Future<String?> showAnalysisModePicker(BuildContext context) {
  final theme = Theme.of(context);

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽条
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              '选择分析模式',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            // 圈画识别卡片
            _ModeCard(
              icon: Icons.edit_note,
              title: '圈画识别',
              subtitle: '分析手写勾画标记的内容',
              detail: '适合纸质书、笔记等有标记痕迹的场景。AI 自动识别被圈画/划线的单词短语。',
              onTap: () => Navigator.pop(ctx, AppConstants.analysisModeMarked),
            ),
            const SizedBox(height: 12),
            // 全文翻译卡片
            _ModeCard(
              icon: Icons.translate,
              title: '全文翻译',
              subtitle: '翻译图片中所有文字内容',
              detail: '适合电子文档、文献、菜单、路牌等需要整篇翻译的外语场景。',
              onTap: () => Navigator.pop(ctx, AppConstants.analysisModeFullText),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
                  Text(subtitle, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
