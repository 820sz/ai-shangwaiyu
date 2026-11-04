import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../config/v4_theme.dart';
import '../services/bookshelf.dart';

/// 书架形态 B · **3D 轮播书架**(2026-11-04 用户拍板双形态之一)。
///
/// 参考用户给的「轻小说文库 3D 书架」:一排书脊朝外、中间一本最大,
/// 左右滑动切换,点中间的书打开。
///
/// 与旧平面书架的差别:
/// - 旧版是"多排平面搁板 + 书脊自绘";这版是**单排 3D 轮播**,书脊上的标题竖排,
///   适合快速扫标题找书;
/// - v2.13 曾尝试 3D 但因**没裁剪**导致书脊文字溢出、被回退;本实现:
///   ① 外层 `ClipRect`;② 每本用 `Transform` 的透视但**不做 translate 出界**;
///   ③ 只渲染 PageView 当前槽位(±1 由 PageView 自己管理),不额外铺全量书。
///
/// 点击/长按行为由 [BookshelfScreen] 注入,与详细书架完全一致。
class ShelfCarouselView extends StatefulWidget {
  final List<BookshelfBook> books;
  final ValueChanged<BookshelfBook>? onTapBook;
  final ValueChanged<BookshelfBook>? onLongPressBook;

  /// 渲染测试用:关掉联网抓封面(本组件不抓图,仅保留参数对位)
  final bool enableCoverFetch;

  const ShelfCarouselView({
    super.key,
    required this.books,
    this.onTapBook,
    this.onLongPressBook,
    this.enableCoverFetch = true,
  });

  @override
  State<ShelfCarouselView> createState() => _ShelfCarouselViewState();
}

class _ShelfCarouselViewState extends State<ShelfCarouselView> {
  late final PageController _ctrl = PageController(viewportFraction: 0.46);
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    if (widget.books.isEmpty) return const SizedBox.shrink();
    return Column(
      children: <Widget>[
        SizedBox(
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // 书桌/搁板底色(淡果冻),让书脊有"立起来"的参照
              Positioned(
                left: 0,
                right: 0,
                bottom: 26,
                child: Container(
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: Gap.md),
                  decoration: BoxDecoration(
                    color: skin.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: skin.shadow,
                  ),
                ),
              ),
              ClipRect(
                child: PageView.builder(
                  controller: _ctrl,
                  clipBehavior: Clip.hardEdge,
                  itemCount: widget.books.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final book = widget.books[i];
                    return AnimatedBuilder(
                      animation: _ctrl,
                      builder: (context, child) {
                        final page = _ctrl.hasClients && _ctrl.position.haveDimensions
                            ? (_ctrl.page ?? _page.toDouble())
                            : _page.toDouble();
                        final delta = (i - page).clamp(-2.5, 2.5);
                        final dist = delta.abs();
                        // 中间的立起来、两侧向内/向后倒
                        final angle = delta * 0.42;
                        final scale = 1 - dist * 0.14;
                        final lift = dist * 14.0;
                        return Transform.translate(
                          offset: Offset(0, lift),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0016)
                              ..rotateY(angle)
                              ..scaleByDouble(scale, scale, scale, 1.0),
                            child: child,
                          ),
                        );
                      },
                      child: _spine(skin, book),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.swipe, size: 13, color: skin.inkFaint),
            const SizedBox(width: 4),
            Text(
              '左右滑 · 点击打开 · 长按看详情',
              style: TextStyle(fontSize: 10.5, color: skin.inkFaint),
            ),
            const SizedBox(width: 8),
            Text(
              '${_page + 1}/${widget.books.length}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: skin.inkSoft,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 单本书脊:渐变色 + 竖排标题 + 进度条 + 等级角标(3:4 的书脊比例)
  Widget _spine(V4Skin skin, BookshelfBook book) {
    final seed = '${book.materialId}:${book.title}'.runes.fold<int>(
          0,
          (a, b) => (a * 31 + b) & 0x7fffffff,
        );
    final palette = _spinePalette(seed);
    final pct = (book.percent / 100).clamp(0.0, 1.0);
    final level = book.cefr.isNotEmpty ? book.cefr : '';
    return GestureDetector(
      onTap: () => widget.onTapBook?.call(book),
      onLongPress: () => widget.onLongPressBook?.call(book),
      child: Center(
        child: Container(
          width: 96,
          height: 240,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(5),
              topRight: Radius.circular(10),
              bottomLeft: Radius.circular(5),
              bottomRight: Radius.circular(10),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: skin.dark
                    ? Colors.black.withValues(alpha: 0.45)
                    : const Color(0xFF4C5AF0).withValues(alpha: 0.16),
                blurRadius: 14,
                offset: const Offset(2, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: <Widget>[
              // 书脊高光条(靠左),让平面矩形有"厚度"感
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 7,
                child: Container(
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (level.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          level,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    const Spacer(),
                    // 竖排标题(书侧标题 —— 用户 11/04 明确要看得到)
                    RotatedBox(
                      quarterTurns: 1,
                      child: Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      book.finished
                          ? '读完'
                          : '${(pct * 100).round()}%',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 3,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.25),
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 书脊配色:按 seed 稳定取一组糖果色渐变(深浅主题都能读白字)
  List<Color> _spinePalette(int seed) {
    const palettes = <List<Color>>[
      <Color>[Color(0xFF6A76F5), Color(0xFF8C7BF0)],
      <Color>[Color(0xFF3F8F8A), Color(0xFF5FB6A8)],
      <Color>[Color(0xFFC96A8E), Color(0xFFE48BA6)],
      <Color>[Color(0xFF7A6BD8), Color(0xFFA18CF0)],
      <Color>[Color(0xFF4C7FBF), Color(0xFF76A9DD)],
      <Color>[Color(0xFFB06A4C), Color(0xFFD08C6A)],
      <Color>[Color(0xFF5C7A5C), Color(0xFF8AA98A)],
    ];
    return palettes[seed % palettes.length];
  }
}

/// 书脊几何(纯函数,可单测):给渲染/测试一个统一的尺寸口径
abstract final class ShelfCarouselMetrics {
  static const double spineWidth = 96;
  static const double spineHeight = 240;

  /// 一本 3:4 封面的书在书脊上的可视高度比例(书脊略窄于封面)
  static double spineAspect(int bookCount) =>
      bookCount <= 1 ? 2.5 : math.min(2.6, 2.2 + bookCount * 0.02);
}
