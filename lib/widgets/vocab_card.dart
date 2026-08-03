import 'package:flutter/material.dart';
import '../models/vocabulary.dart';

class VocabCard extends StatelessWidget {
  final Vocabulary vocab;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final bool? selected; // null = 正常模式，true/false = 多选模式

  const VocabCard({
    super.key,
    required this.vocab,
    this.onTap,
    this.onLongPress,
    this.onDelete,
    this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inSelection = selected != null;

    return Card(
      color: inSelection && selected!
          ? theme.colorScheme.primary.withAlpha(15)
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 多选模式 → 复选框；正常模式 → 掌握度标记
              if (inSelection)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 12),
                  child: Icon(
                    selected! ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 22,
                    color: selected! ? theme.colorScheme.primary : Colors.grey[400],
                  ),
                )
              else
                Container(
                  width: 4,
                  height: 48,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: _masteryColor(vocab.masteryLevel),
                  ),
                ),
              // 内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vocab.displayLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _typeChip(vocab.wordType, theme),
                      ],
                    ),
                    if (vocab.translation != null &&
                        vocab.translation!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        vocab.translation!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(180),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      vocab.sourceSummary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(120),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // 操作（多选模式下隐藏删除按钮，使用批量操作）
              if (onDelete != null && !inSelection)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _masteryColor(int level) {
    switch (level) {
      case 0:
        return Colors.orange;
      case 1:
        return Colors.blue;
      case 2:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _typeChip(String type, ThemeData theme) {
    String label;
    switch (type) {
      case 'phrase':
        label = '短语';
      case 'sentence':
        label = '句子';
      default:
        label = '单词';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }
}
