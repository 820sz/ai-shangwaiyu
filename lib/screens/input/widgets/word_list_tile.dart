import 'package:flutter/material.dart';
import '../../../config/theme.dart';
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

  /// 词条类型三色(v2.5,U2):收敛到 [AppTheme.wordTypeColor] ——
  /// 以前这里写死 orange/purple/#4A90D9,浅色下对白底不够 AA
  Color _barColor(BuildContext context) =>
      AppTheme.wordTypeColor(context, item.wordType);

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
              ? Border(left: BorderSide(color: _barColor(context), width: 3))
              : Border(
                  left: BorderSide(
                      color: cs.outlineVariant, width: 3)),
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
                        // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    // v2.4:同一个词出现过多次 → apple(×2);能推出原型 → taming(tame)
                    item.displayFull,
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
                // 待确认标(v2.6):模型"拿不准算不算标记"但仍然收进来的条目。
                // 放在类型标签左边、用警示色 —— 用户扫一眼就知道哪几条是边缘情况。
                if (item.needsReview) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor(context).withAlpha(24),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '待确认',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.warningColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                // 词性/类型标签
                //
                // ⚠️ v2.6 修一个真实排版 bug:这里原来写的是 `Flexible(...)`,
                // 而 **Flexible 默认 flex:1** —— 它和上面的 `Expanded(词条)`
                // 各分走一半剩余宽度!短单词看不出来,长句子就被挤成 ~140px 的
                // 窄列(用户实测:"句子显示成很长的一竖列,单词还从中间断开")。
                // 现在改成"不参与 flex 的定宽盒"(最多 96,超出省略),
                // 词条拿满剩余宽度。
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _barColor(context).withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.partOfSpeech ?? _typeLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: _barColor(context),
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
                        color: theme.colorScheme.onSurfaceVariant,
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
                        color: bookmarked ? AppTheme.amber(context) : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
            // 行2:音标(v1.5.0 AI 补全生成;v2.0 起英/美双音标一并显示)+ 释义(独占整行)
            if (item.displayPhonetic != null) ...[
              const SizedBox(height: 2),
              Text(
                item.displayPhonetic!,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
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
                  color: theme.colorScheme.onSurface,
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
