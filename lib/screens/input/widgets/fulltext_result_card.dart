import 'package:flutter/material.dart';

/// 全文翻译段落卡片
/// [onAskExplain] 非空时显示「✨ AI 讲解」——点击/点击原文询问 AI 详解该段
/// (v1.4.0 问题 6:全文翻译模式补齐圈画模式的讲解导引)
class FulltextResultCard extends StatelessWidget {
  final int index;
  final String original;
  final String translation;
  final VoidCallback? onAskExplain;

  const FulltextResultCard({
    super.key,
    required this.index,
    required this.original,
    required this.translation,
    this.onAskExplain,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 段落编号 + 讲解按钮
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '段落 ${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              if (onAskExplain != null)
                InkWell(
                  onTap: onAskExplain,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 13,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'AI 讲解',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // 原文(点击询问 AI 讲解,与 AI 讲解按钮同触发)
          GestureDetector(
            onTap: onAskExplain,
            child: Text(
              original,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Divider(color: theme.colorScheme.outlineVariant, height: 1),
          const SizedBox(height: 6),
          // 译文
          Text(
            translation,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
