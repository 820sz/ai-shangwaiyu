import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/v4_theme.dart';
import '../services/bookshelf.dart';
import 'material_cover.dart';

/// 书架形态 B · **3D 立体轮播书架**(v5 · 第二版,对齐用户参考图)。
///
/// 用户参考图(轻小说文库 W8 书架)的关键不是"一次一本大书",而是:
/// 1. **一排书脊同时立在书架上**(书脊朝外、密密麻麻,能看到每本书的侧标题);
/// 2. 中间选中那本**被抽出来、微微倾斜地展示封面**(立体感来自封面卡 + 阴影 + 透视);
/// 3. 左右滑动/点书脊切换"被抽出来"的那本。
///
/// v5 第一版做成了 PageView 一次一本,和参考图差得远(用户 11/04 指出)。
/// 本文件按参考图重写:
/// - `SingleChildScrollView + Row` 铺**一排书脊**,宽度/高度按书名与进度稳定生成;
/// - 滚动到视口中心的那本 = 选中,顶部用 `Matrix4` 透视**倾斜抽出封面**;
/// - 点书脊 = 滚到它;点封面 = 打开阅读器;长按 = 原书架弹层。
///
/// 裁剪:外层 `ClipRect`(v2.13 3D 回退的坑),书脊不超出书架面。
class ShelfCarouselView extends StatefulWidget {
  final List<BookshelfBook> books;
  final ValueChanged<BookshelfBook>? onTapBook;
  final ValueChanged<BookshelfBook>? onLongPressBook;

  /// 渲染测试用:关掉联网抓封面(本组件封面走 MaterialCover,不主动抓图)
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
  final ScrollController _ctrl = ScrollController();
  int _selected = 0;
  double _viewportWidth = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onScroll);
    // 参考图构图:把"被抽出来"的那本放在中间,左右都能看到书脊
    _selected = widget.books.isEmpty ? 0 : widget.books.length ~/ 2;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centerOn(_selected, animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant ShelfCarouselView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 筛选/排序变了:选中的书可能已不在列表里 —— 重置到中间那本,
    // 否则会停在越界索引,出现"只显示一本、其余书脊看不到"的真机 bug。
    if (oldWidget.books.length != widget.books.length ||
        (oldWidget.books.isNotEmpty &&
            widget.books.isNotEmpty &&
            oldWidget.books.first.materialId != widget.books.first.materialId)) {
      _selected = widget.books.isEmpty ? 0 : widget.books.length ~/ 2;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _centerOn(_selected, animate: false);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onScroll);
    _ctrl.dispose();
    super.dispose();
  }

  // ── 布局口径(纯函数)────────────────────────────────────────────
  // 书脊宽度/高度按书名与进度稳定生成:同一本书每次进来姿势一致,不会"跳"。
  double _spineWidth(int i) {
    final seed = _seedOf(widget.books[i]);
    return 24 + (seed % 11).toDouble(); // 24~34
  }

  double _spineHeight(int i) {
    final seed = _seedOf(widget.books[i]);
    final h = 150 + (seed % 51); // 150~200
    return math.min(h.toDouble(), _maxSpineHeight);
  }

  static const double _maxSpineHeight = 200;
  static const double _bookBottomGap = 30; // 书底离容器底(给搁板+阴影)
  static const double _featuredHeight = 168;

  int _seedOf(BookshelfBook b) {
    final s = '${b.materialId}:${b.title}'.runes.fold<int>(
          0,
          (a, b2) => (a * 31 + b2) & 0x7fffffff,
        );
    return s;
  }

  double _gap(int i) => 2.5;

  /// 第 i 本书在 Row 里的左偏移
  double _offsetOf(int i) {
    var x = 0.0;
    for (var k = 0; k < i; k++) {
      x += _spineWidth(k) + _gap(k);
    }
    return x;
  }

  void _onScroll() {
    if (!_ctrl.hasClients || _viewportWidth <= 0) return;
    final center = _ctrl.offset + _viewportWidth / 2;
    var idx = 0;
    for (var i = 0; i < widget.books.length; i++) {
      final left = _offsetOf(i);
      final right = left + _spineWidth(i);
      if (center >= left && center <= right) {
        idx = i;
        break;
      }
      if (center > right) idx = math.min(i + 1, widget.books.length - 1);
    }
    if (idx != _selected) setState(() => _selected = idx);
  }

  Future<void> _centerOn(int i, {bool animate = true}) async {
    if (!_ctrl.hasClients) return;
    final target = (_offsetOf(i) + _spineWidth(i) / 2) - _viewportWidth / 2;
    final clamped =
        target.clamp(0.0, _ctrl.position.maxScrollExtent).toDouble();
    if (animate) {
      await _ctrl.animateTo(
        clamped,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } else {
      _ctrl.jumpTo(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    if (widget.books.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        final selected =
            widget.books[_selected.clamp(0, widget.books.length - 1)];
        return SizedBox(
          // 高度按"最高书脊 + 底部搁板 + 封面露出的顶"算;之前的公式把
          // 封面高度和书脊高度相加,真机上顶部空出一大块(用户 11/04 反馈)
          height: _maxSpineHeight + _bookBottomGap + 26,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              // 书架背景:淡果冻纸面(参考图是奶白/纸感,这里用主题浅底)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      skin.pastelAt(0).first.withValues(alpha: 0.25),
                      skin.pageBg,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
              // ① 一排书脊(真正"书架"的主体)
              Positioned(
                left: 0,
                right: 0,
                bottom: _bookBottomGap + 6,
                height: _maxSpineHeight + 6,
                child: ClipRect(
                  child: SingleChildScrollView(
                    controller: _ctrl,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: math.max(24, (constraints.maxWidth - 60) / 2),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        for (var i = 0; i < widget.books.length; i++)
                          Padding(
                            padding: EdgeInsets.only(right: _gap(i)),
                            child: _spine(skin, i, selected: i == _selected),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // ② 搁板(书底那条板)
              Positioned(
                left: 8,
                right: 8,
                bottom: _bookBottomGap - 6,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: skin.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: skin.shadow,
                  ),
                ),
              ),
              // ③ 被抽出来的那本:透视倾斜的封面(参考图的核心视觉)
              Positioned(
                left: 0,
                right: 0,
                bottom: _bookBottomGap + 4,
                height: _featuredHeight,
                child: Center(
                  child: GestureDetector(
                    onTap: () => widget.onTapBook?.call(selected),
                    onLongPress: () => widget.onLongPressBook?.call(selected),
                    child: _featuredCover(skin, selected),
                  ),
                ),
              ),
              // ④ 底部状态
              Positioned(
                left: 0,
                right: 0,
                bottom: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.swipe, size: 12, color: skin.inkFaint),
                    const SizedBox(width: 4),
                    Text(
                      '左右滑 · 点书脊切换 · 点封面打开',
                      style: TextStyle(fontSize: 10, color: skin.inkFaint),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_selected + 1}/${widget.books.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: skin.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 书脊:窄长条 + 竖排标题 + 进度条;选中那本微微抬高/提亮
  Widget _spine(V4Skin skin, int i, {required bool selected}) {
    final book = widget.books[i];
    final palette = _spinePalette(_seedOf(book));
    final pct = (book.percent / 100).clamp(0.0, 1.0);
    final width = _spineWidth(i);
    final height = _spineHeight(i);
    return GestureDetector(
      onTap: () {
        setState(() => _selected = i);
        _centerOn(i);
      },
      child: Transform(
        alignment: Alignment.bottomCenter,
        // 参考图是"一排书在透视里":离中心越远越向内收一点,整排才有 3D 纵深
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0010)
          ..rotateY(((i - _selected) * 0.030).clamp(-0.28, 0.28)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: width,
          height: height + (selected ? 10 : 0),
          transform: Matrix4.translationValues(0, selected ? -10 : 0, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette,
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(3),
              topRight: Radius.circular(6),
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(3),
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: selected ? 0.65 : 0.28),
              width: selected ? 1.2 : 0.6,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.28 : 0.16),
                blurRadius: selected ? 10 : 5,
                offset: const Offset(1, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: <Widget>[
              // 书脊高光(靠左),做出圆柱/厚度感
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 5,
                child: Container(color: Colors.white.withValues(alpha: 0.18)),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: Container(color: Colors.black.withValues(alpha: 0.08)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                child: Column(
                  children: <Widget>[
                    // 书脊顶部小横线(像布面书脊的压纹)
                    Container(
                      width: math.max(4, width - 12),
                      height: 1.5,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 1,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              letterSpacing: 0.4,
                              color: Colors.white,
                              height: 1.05,
                              shadows: const <Shadow>[
                                Shadow(
                                    color: Color(0x33000000), blurRadius: 1),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 2.5,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
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

  /// 被抽出来展示的封面:Matrix4 透视倾斜 + 阴影(参考图构图)
  Widget _featuredCover(V4Skin skin, BookshelfBook book) {
    final level = book.cefr.isNotEmpty ? book.cefr : '';
    return Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0015)
        ..rotateX(-0.035)
        ..rotateY(0.12)
        ..rotateZ(-0.012)
        ..scaleByDouble(1.0, 1.0, 1.0, 1.0),
      child: Container(
        width: 132,
        height: _featuredHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(6, 14),
            ),
            BoxShadow(
              color: skin.accent.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(-2, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            MaterialCover(
              seed: book.title,
              kind: book.kind,
              imageUrl: book.coverUrl,
              width: 132,
              height: _featuredHeight,
              radius: 8,
            ),
            // 书脊根部的阴影:像是从书架里抽出来
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.18),
                    ],
                  ),
                ),
              ),
            ),
            if (level.isNotEmpty)
              Positioned(
                left: 8,
                bottom: 7,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
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
              ),
          ],
        ),
      ),
    );
  }

  /// 书脊配色:按 seed 稳定取一组"布面书脊"色(白字可读)
  List<Color> _spinePalette(int seed) {
    const palettes = <List<Color>>[
      <Color>[Color(0xFF6A76F5), Color(0xFF8C7BF0)],
      <Color>[Color(0xFF3F8F8A), Color(0xFF5FB6A8)],
      <Color>[Color(0xFFC96A8E), Color(0xFFE48BA6)],
      <Color>[Color(0xFF7A6BD8), Color(0xFFA18CF0)],
      <Color>[Color(0xFF4C7FBF), Color(0xFF76A9DD)],
      <Color>[Color(0xFFB06A4C), Color(0xFFD08C6A)],
      <Color>[Color(0xFF5C7A5C), Color(0xFF8AA98A)],
      <Color>[Color(0xFF9A7B4F), Color(0xFFC0A274)],
    ];
    return palettes[seed % palettes.length];
  }
}

/// 书脊几何(纯函数,可单测):给渲染/测试一个统一的尺寸口径
abstract final class ShelfCarouselMetrics {
  static const double maxSpineHeight = 220;
  static const double featuredHeight = 190;
  static const double bookBottomGap = 30;

  /// 一本 3:4 封面的书在书脊上的可视高度比例(书脊略窄于封面)
  static double spineAspect(int bookCount) =>
      bookCount <= 1 ? 2.5 : math.min(2.6, 2.2 + bookCount * 0.02);
}
