import 'package:flutter/material.dart';
import '../../../models/vocabulary.dart';

/// 紧凑的生词行组件，用于总览/详细两种显示模式。
///
/// [onTap] 单击（总览→详情页，详细→询问AI）
/// [onLongPress] 长按切换选中状态
class WordListTile extends StatelessWidget {
  final Vocabulary item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const WordListTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  Color _barColor() {
    final t = item.wordType;
    if (t == 'phrase') return Colors.orange;
    if (t == 'sentence') return Colors.purple;
    return const Color(0xFF4A90D9); // word = blue
  }

  String _typeLabel() {
    final t = item.wordType;
    if (t == 'phrase') return '短语';
    if (t == 'sentence') return '句子';
    return '单词';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary.withAlpha(10) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border(left: BorderSide(color: _barColor(), width: 3))
              : Border(left: BorderSide(color: Colors.grey.withAlpha(40), width: 3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            // 单词
            Expanded(
              flex: 3,
              child: Text(
                item.word,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // 词性/类型标签
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: _barColor().withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.partOfSpeech ?? _typeLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: _barColor(), fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 释义（brief）
            Expanded(
              flex: 4,
              child: Text(
                item.translation ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            // 箭头指示
            Icon(Icons.chevron_right, size: 18, color: Colors.grey[300]),
          ],
        ),
      ),
    );
  }
}
