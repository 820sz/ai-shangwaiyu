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
  /// 序号（从 0 起），null 时不显示（其他页面复用时不干扰）
  final int? index;
  /// 收藏星标(v1.4.0 问题 8):非 null 时显示;分别控制显示与状态
  final VoidCallback? onBookmark;
  final bool bookmarked;

  const WordListTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.index,
    this.onBookmark,
    this.bookmarked = false,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 行1:序号 + 单词(独占剩余宽度,绝不拆行)+ 类型标签 + 星标。
            // v1.4.3 重构:原文 单词/释义 同排 flex 分配,星标/标签一挤
            // 长词就被拆行("fascimiles"→"fascimi les" 用户实测);分两行后
            // 单词始终整行展示,不限行语义不变。
            Row(
              children: [
                if (index != null)
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${index! + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    item.displayWordText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    // 不限行 + 永不打省略号:一排放不下自动换行
                    // (2026-08-10 用户实测终局修复:maxLines:null + visible)
                    maxLines: null,
                    overflow: TextOverflow.visible,
                  ),
                ),
                const SizedBox(width: 8),
                // 词性/类型标签
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: _barColor().withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.partOfSpeech ?? _typeLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: _barColor(),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 收藏星标(可选)——好句子/词条单独收藏进收藏夹。
                if (onBookmark != null)
                  InkWell(
                    onTap: onBookmark,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 4,
                      ),
                      child: Icon(
                        bookmarked ? Icons.star : Icons.star_border,
                        size: 16,
                        color: bookmarked ? Colors.amber[700] : Colors.grey[400],
                      ),
                    ),
                  )
                else
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey[300]),
              ],
            ),
            // 行2:释义(独占整行)
            if ((item.translation ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item.translation ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
                maxLines: null,
                overflow: TextOverflow.visible,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
