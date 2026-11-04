import 'package:flutter/material.dart';

import '../../../config/v4_theme.dart';

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
    final skin = V4Skin.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      // v5:全文翻译段落改成"白卡果冻"(与阅读器/识图词卡同语言)
      decoration: BoxDecoration(
        color: skin.surface,
        border: Border.all(color: skin.hairline),
        borderRadius: BorderRadius.circular(18),
        boxShadow: skin.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 段落编号 + 讲解按钮
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: skin.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '段落 ${index + 1}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: skin.accent,
                  ),
                ),
              ),
              const Spacer(),
              if (onAskExplain != null)
                InkWell(
                  onTap: onAskExplain,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: skin.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 12,
                          color: skin.accent,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'AI 讲解',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: skin.accent,
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
