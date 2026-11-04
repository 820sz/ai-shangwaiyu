import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../config/v4_theme.dart';
import '../services/bookshelf.dart';
import 'art_cover.dart';

/// 书架形态 A · **详细书架**(封面优先,2026-11-04 用户拍板双形态之一)。
///
/// 之前 v2.13~v4 的书架只有一种"平面搁板"形态;用户要求两种可切换:
/// - 详细书架(本文件):封面网格,标题/进度一目了然,适合"找书继续读";
/// - 3D 轮播书架(`shelf_carousel_view.dart`):书脊朝外、可左右滑,适合"把玩/扫标题"。
///
/// 本组件只负责画;点击/长按行为由 [BookshelfScreen] 注入(与旧书架完全一致)。
class ShelfCoverGrid extends StatelessWidget {
  final List<BookshelfBook> books;
  final ValueChanged<BookshelfBook>? onTapBook;
  final ValueChanged<BookshelfBook>? onLongPressBook;

  /// 渲染测试用:关掉自动抓图(避免测试环境网络 timer)
  final bool enableCoverFetch;

  const ShelfCoverGrid({
    super.key,
    required this.books,
    this.onTapBook,
    this.onLongPressBook,
    this.enableCoverFetch = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 560 ? 4 : (width >= 380 ? 2 : 2);
        final spacing = Gap.sm;
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        // 封面 3:4 + 两行文字 ≈ 1:1.62
        final itemHeight = itemWidth * 4 / 3 + 62;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: Gap.md,
            crossAxisSpacing: spacing,
            mainAxisExtent: itemHeight,
          ),
          itemCount: books.length,
          itemBuilder: (context, i) {
            final b = books[i];
            return _ShelfCoverCard(
              book: b,
              onTap: () => onTapBook?.call(b),
              onLongPress: () => onLongPressBook?.call(b),
              enableCoverFetch: enableCoverFetch,
            );
          },
        );
      },
    );
  }
}

class _ShelfCoverCard extends StatelessWidget {
  final BookshelfBook book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool enableCoverFetch;

  const _ShelfCoverCard({
    required this.book,
    required this.onTap,
    required this.onLongPress,
    required this.enableCoverFetch,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final level = book.cefr.isNotEmpty ? book.cefr : null;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(builder: (ctx, c) {
              return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ArtCover(
                    title: book.title,
                    kind: book.kind,
                    imageUrl: book.coverUrl,
                    width: c.maxWidth,
                    height: c.maxHeight,
                    radius: 16,
                    levelLabel: level,
                    enableFetch: enableCoverFetch,
                  ),
                ),
                // 底部进度:详细书架也要能一眼看出读到哪
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                    child: LinearProgressIndicator(
                      value: (book.percent / 100).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: skin.surface.withValues(alpha: 0.55),
                      color: book.finished
                          ? const Color(0xFF2F8A5B)
                          : skin.accent,
                    ),
                  ),
                ),
                if (book.finished)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F8A5B),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '已读完',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                  ),
              ],
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.28,
              fontWeight: FontWeight.w700,
              color: skin.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            book.finished
                ? '已读完'
                : (book.percent > 0
                    ? '已读 ${book.percent.round()}%'
                    : '未开始'),
            maxLines: 1,
            style: TextStyle(fontSize: 10.5, color: skin.inkSoft),
          ),
        ],
      ),
    );
  }
}
