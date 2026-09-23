import 'package:flutter/material.dart';

/// AI 结果摘要头部 — 紧凑版
class AiResultHeader extends StatelessWidget {
  final int totalCount;
  final int wordCount;
  final int phraseCount;
  final int sentenceCount;
  final String modelName;
  final String thinkingLabel;

  const AiResultHeader({
    super.key,
    required this.totalCount,
    required this.wordCount,
    required this.phraseCount,
    required this.sentenceCount,
    required this.modelName,
    required this.thinkingLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF4A90D9).withAlpha(12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '识别完成 · 共 $totalCount 个标记',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _countBadge('📝', '$wordCount 单词', const Color(0xFF4A90D9)),
              _countBadge('📐', '$phraseCount 短语', Colors.orange),
              _countBadge('💬', '$sentenceCount 句子', Colors.purple),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$modelName · $thinkingLabel',
            // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
            style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _countBadge(String emoji, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$emoji $label',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
