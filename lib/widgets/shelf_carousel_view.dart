import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/v4_theme.dart';
import '../services/bookshelf.dart';
import 'shelf_cover_grid.dart';

/// 书架形态 B · **3D 立体轮播书架**(v6 · 2026-11-07 修"每次点进去有书横档")。
///
/// 用户参考图(轻小说文库 W8 书架)的关键不是"一次一本大书",而是:
/// 1. **一排书脊同时立在书架上**(书脊朝外、密密麻麻,能看到每本书的侧标题);
/// 2. 点某一本书脊后,那本**被抽出来、微微倾斜地展示封面**(阴影 + 透视);
/// 3. 左右滑动浏览书脊。
///
/// ## v6 修的 bug(用户真机第 3 条:"每次点进去都会有一本书横档")
/// 旧实现有两个问题:
/// - `_selected` 初始就被设成"中间那本"(旧 `initState`),于是**一进页面**
///   就有一张"抽出的封面卡";
/// - 抽出封面用 `bottom: _bookBottomGap + 4` 定位,和书脊排(`bottom: _bookBottomGap + 6`)
///   **几乎同一层** → 封面正好横在书脊前面,挡住中间几本书,看起来像"横了一个东西"。
///
/// 现在:
/// - 初始 `_selected = null`(见 [ShelfCarouselView.spineKey] 附近注释),
///   只显示一排书脊 + 底部提示;
/// - 点书脊 → 该本抽出,**封面浮在书架排上方**(不覆盖任何书脊/hint),整条书架
///   高度用 [AnimatedSize] 平滑长高;
/// - 再点同一本书脊 / 点书架空白 → 收回;
/// - 左右滑动只滚书脊,不会自动"抽出"某本(旧实现滑到哪本就抽哪本,是横档的来源)。
///
/// 裁剪:外层 `ClipRect`,书脊不超出书架面。
class ShelfCarouselView extends StatefulWidget {
  final List<BookshelfBook> books;
  final ValueChanged<BookshelfBook>? onTapBook;
  final ValueChanged<BookshelfBook>? onLongPressBook;

  /// 渲染测试用开关(历史参数):本组件封面已改为 [CoverOrText],
  /// **不再联网抓封面** —— 有 `coverUrl` 显示真图,没有就显示文字版式。
  /// 保留该参数只为不破坏既有调用点,传什么都不会触发网络请求。
  final bool enableCoverFetch;

  const ShelfCarouselView({
    super.key,
    required this.books,
    this.onTapBook,
    this.onLongPressBook,
    this.enableCoverFetch = true,
  });

  /// 抽出封面卡的 Key(渲染/测试用:断言"初始态没有抽出封面")
  static const Key featuredCoverKey = Key('shelf_carousel_featured_cover');

  /// 整个书架面的 Key(点空白收回时,测试用它算空白坐标)
  static const Key surfaceKey = Key('shelf_carousel_surface');

  /// 第 [i] 本书脊的 Key(测试点书脊用)
  static Key spineKey(int i) => ValueKey<String>('shelf_carousel_spine_$i');

  @override
  State<ShelfCarouselView> createState() => _ShelfCarouselViewState();
}

class _ShelfCarouselViewState extends State<ShelfCarouselView> {
  final ScrollController _ctrl = ScrollController();

  /// 当前"抽出来"的书;null = **没有抽出任何一本**(初始态 / 收回态)。
  ///
  /// 旧实现这里是 `int _selected = 0` 并在 initState 里改成"中间那本",
  /// 所以一进页面就有封面横在书脊前(用户真机第 3 条)。
  int? _selected;

  double _viewportWidth = 0;

  /// 书架排(书脊 + 搁板 + 底部提示)的固定高度;抽出封面浮在它**上方**,
  /// 所以这个高度不随开合变化(变化的是外层 AnimatedSize 的总高度)
  static const double _shelfBandHeight =
      _maxSpineHeight + _bookBottomGap + 26;

  @override
  void initState() {
    super.initState();
    // 抽出封面要一直"悬在选中那本书的正上方":滚动书脊时跟着对齐
    _ctrl.addListener(_realignCover);
    // 初始只滚到中间,让书脊铺满书架;**不**选中、不抽出封面
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.books.isEmpty) return;
      _centerOn(widget.books.length ~/ 2, animate: false);
    });
  }

  /// 滚动时重算抽出封面的横向位置(只在有抽出封面时才重建)
  void _realignCover() {
    if (!mounted || _selected == null) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant ShelfCarouselView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 筛选/排序变了:抽出的那本可能已不在列表里 —— 收回封面,把书架回正。
    if (oldWidget.books.length != widget.books.length ||
        (oldWidget.books.isNotEmpty &&
            widget.books.isNotEmpty &&
            oldWidget.books.first.materialId != widget.books.first.materialId)) {
      _selected = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.books.isEmpty) return;
        _centerOn(widget.books.length ~/ 2, animate: false);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_realignCover);
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
  static const double _featuredWidth = 132;

  int _seedOf(BookshelfBook b) {
    final s = '${b.materialId}:${b.title}'.runes.fold<int>(
          0,
          (a, b2) => (a * 31 + b2) & 0x7fffffff,
        );
    return s;
  }

  double _gap(int i) => 2.5;

  /// 书脊排左右内边距:让"任意一本都能滚到视口正中"(首尾也能居中)。
  /// 必须和 [_centerOn] 用同一个口径,否则选中后书脊会偏到一边(实测差 ~100px)。
  double get _sidePadding => math.max(24, (_viewportWidth - 60) / 2);

  /// 第 i 本书在 Row 里的左偏移
  double _offsetOf(int i) {
    var x = 0.0;
    for (var k = 0; k < i; k++) {
      x += _spineWidth(k) + _gap(k);
    }
    return x;
  }

  /// 点书脊:没抽出 → 抽出这本并把它滚到中间;已抽出同一本 → 收回。
  ///
  /// 为什么用"点同一本再收回"而不是"点哪本换哪本":收回是明确的可达操作
  /// (否则封面一旦抽出就只能靠点空白收回,而空白区域在书脊满屏时很小)。
  void _toggleBook(int i) {
    if (i < 0 || i >= widget.books.length) return;
    if (_selected == i) {
      _closeFeatured();
      return;
    }
    setState(() => _selected = i);
    _centerOn(i);
  }

  /// 收回抽出的封面(点空白 / 再点书脊都走这里)
  void _closeFeatured() {
    if (_selected == null) return;
    setState(() => _selected = null);
  }

  Future<void> _centerOn(int i, {bool animate = true}) async {
    if (!_ctrl.hasClients) return;
    // 书脊在滚动内容里的真实 x = 左内边距 + 前面所有书脊宽度;旧实现漏了
    // padding,导致"点了某本,它还是偏在一边"(实测偏 ~100px)
    final target =
        (_sidePadding + _offsetOf(i) + _spineWidth(i) / 2) - _viewportWidth / 2;
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
        final selected = _selected;
        final open = selected != null && selected < widget.books.length;
        // 抽出封面**浮在书架排上方**,不压在书脊上 —— 这是"横档"bug 的直接修法。
        // 收起时这块高度为 0,所以初始态就是一整排书脊。
        final featuredSlot = open ? _featuredHeight + 14 : 0.0;
        // 抽出封面的横向落点:对准选中书脊在屏幕上的中心(再夹在左右安全边距内),
        // 这样"抽出来"的封面总是悬在**那本书**正上方,不会在正中飘着像别的卡
        double? coverLeft;
        if (open) {
          final centerOnScreen = _sidePadding +
              _offsetOf(selected) +
              _spineWidth(selected) / 2 -
              (_ctrl.hasClients ? _ctrl.offset : 0);
          final minCenter = _featuredWidth / 2 + 10;
          final maxCenter = constraints.maxWidth - _featuredWidth / 2 - 10;
          final clampedCenter = maxCenter <= minCenter
              ? constraints.maxWidth / 2
              : centerOnScreen.clamp(minCenter, maxCenter).toDouble();
          coverLeft = clampedCenter - _featuredWidth / 2;
        }
        return GestureDetector(
          key: ShelfCarouselView.surfaceKey,
          behavior: HitTestBehavior.opaque,
          // 点书架空白 = 收回;书脊/封面的 GestureDetector 在里层,会先拿到手势
          onTap: _closeFeatured,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: _shelfBandHeight + featuredSlot,
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
                  // ① 一排书脊(真正"书架"的主体;初始可见的全部内容)
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
                          horizontal: _sidePadding,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            for (var i = 0; i < widget.books.length; i++)
                              Padding(
                                padding: EdgeInsets.only(right: _gap(i)),
                                child: _spine(
                                  skin,
                                  i,
                                  selected: i == selected,
                                  // 没选中时以"中间那本"为透视锚点,
                                  // 书脊排仍有纵深,不会变成一张平面卡片墙
                                  anchor: selected ?? (widget.books.length ~/ 2),
                                ),
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
                  // ③ 被抽出来的那本:只在点开时出现,且**浮在书架排上方**
                  //    (bottom 从书架排顶部再往上 4px,压不到任何书脊)
                  if (open && coverLeft != null)
                    Positioned(
                      left: coverLeft,
                      width: _featuredWidth,
                      bottom: _shelfBandHeight + 4,
                      height: _featuredHeight,
                      child: GestureDetector(
                        key: ShelfCarouselView.featuredCoverKey,
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            widget.onTapBook?.call(widget.books[selected]),
                        onLongPress: () => widget
                            .onLongPressBook
                            ?.call(widget.books[selected]),
                        // 封面不再压住书脊,但保留"在封面上横向拖 = 翻书"
                        onHorizontalDragUpdate: (details) {
                          if (!_ctrl.hasClients) return;
                          final next = (_ctrl.offset - details.delta.dx)
                              .clamp(0.0, _ctrl.position.maxScrollExtent)
                              .toDouble();
                          _ctrl.jumpTo(next);
                        },
                        child: _featuredCover(skin, widget.books[selected]),
                      ),
                    ),
                  // ④ 底部状态(始终在书架排底部,不会被封面盖住)
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
                          open
                              ? '点书脊收回 · 点封面打开 · 左右滑翻书'
                              : '左右滑翻书 · 点书脊抽出封面',
                          style: TextStyle(fontSize: 10, color: skin.inkFaint),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          open
                              ? '${selected + 1}/${widget.books.length}'
                              : '${widget.books.length} 本',
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
            ),
          ),
        );
      },
    );
  }

  /// 书脊:窄长条 + 竖排标题 + 进度条;抽出那本微微抬高/提亮
  Widget _spine(
    V4Skin skin,
    int i, {
    required bool selected,
    required int anchor,
  }) {
    final book = widget.books[i];
    final palette = _spinePalette(_seedOf(book));
    final pct = (book.percent / 100).clamp(0.0, 1.0);
    final width = _spineWidth(i);
    final height = _spineHeight(i);
    return GestureDetector(
      key: ShelfCarouselView.spineKey(i),
      // 点书脊 = 抽出/收回;不再"点一下就永久选中"
      onTap: () => _toggleBook(i),
      child: Transform(
        alignment: Alignment.bottomCenter,
        // 参考图是"一排书在透视里":离锚点越远越向内收一点,整排才有 3D 纵深
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0010)
          ..rotateY(((i - anchor) * 0.030).clamp(-0.28, 0.28)),
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
  ///
  /// 封面内容是 [CoverOrText]:**有 `coverUrl` 显示真图,没有就显示文字版式**
  /// (标题 + 英文原名 + 难度),不再用 `MaterialCover` 的程序化渐变封面 ——
  /// 用户 2026-11-06 真机反馈那层渐变「原版书」封面是假封面。
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
        width: _featuredWidth,
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
            CoverOrText(
              title: book.title,
              subtitle: book.subtitle,
              kind: book.kind,
              coverUrl: book.coverUrl,
              levelLabel: level,
              width: _featuredWidth,
              height: _featuredHeight,
              radius: 8,
            ),
            // 真图时才需要额外的黑底难度角标(文字版式自己带难度胶囊)
            if (shelfCoverHasImage(book.coverUrl) && level.isNotEmpty)
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
