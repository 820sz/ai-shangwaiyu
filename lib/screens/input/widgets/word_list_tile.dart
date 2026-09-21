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
  /// 朗读(v1.5.0):非 null 时显示小喇叭,点击系统 TTS 朗读词条
  final VoidCallback? onSpeak;

  const WordListTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    this.index,
    this.onBookmark,
    this.bookmarked = false,
    this.onSpeak,
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
                        // P2-31:正文灰阶对比度 <4.5:1,提到 grey[600] 达 WCAG AA
                        color: Colors.grey[600],
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
                // P2-32 附带修:2× 系统字号下标签+右侧图标会把整行撑爆
                // (实测 Row overflowed by 25 pixels)。标签改为可压缩
                // (Flexible + 已有 ellipsis),长词条与图标优先保留完整。
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
                      style: TextStyle(
                        fontSize: 10,
                        color: _barColor(),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 朗读喇叭(v1.5.0):单词点一下朗读,无需进详情
                if (onSpeak != null)
                  InkWell(
                    onTap: onSpeak,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 4,
                      ),
                      child: Icon(
                        Icons.volume_up_outlined,
                        size: 15,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
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
            // 行2:音标(v1.5.0,AI 补全生成)+ 释义(独占整行)
            if ((item.phonetic ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item.phonetic!,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[600],
                ),
                maxLines: null,
                overflow: TextOverflow.visible,
              ),
            ],
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
