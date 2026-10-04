/// 书架的可视化控件(v2.10,用户 10/4 第 5 条)。
///
/// 用户原话:**"书架的 ui 展示要丰富,最好真的像一个书架,一架的书,等待用户放满 ——
/// 最开始是空的书架,然后放一篇材料,就多一本书,书上显示标题和阅读进度。"**
///
/// ## 为什么全部自绘,而不是拼现成组件
/// 想让人一眼认出"这是书架",靠的是三样东西:**有厚度的搁板**、**立着的书脊**、
/// **成排的留白**。Flutter 的现成组件里没有"书脊"这个概念 —— 用 `Card` 拼出来的
/// 只能是一排小方块。所以这里用 [CustomPainter] 画搁板与书脊(零新依赖),
/// 好处是尺寸/进度/配色全是可控的数字,连"书签带"这种细节都能精确到像素。
///
/// ## 一条明确的取舍:书脊上**不贴网络封面图**
/// 书脊是 34×122 的窄条。`MaterialCover` 的图是按封面比例(3:4)做的,
/// 塞进窄条只会被裁成一团噪点 —— 用户要的"像真书架"反而更弱。
/// 所以书脊 = 纯色纸感书脊 + 竖排书名 + 进度书签带;
/// **真封面留给"长按 → 查看封面"那张大图**(那里用 `MaterialCover`,尺寸对了才好看)。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../services/bookshelf.dart';

/// 书架控件:一层层搁板 + 立着的书。
///
/// 数据是**已经算好的** [BookshelfBook] 列表(界面层负责去数据库取),
/// 本控件只负责"怎么摆、怎么画",所以可以被书架页、材料中心预览、
/// 甚至测试里的 `pumpWidget` 直接复用。
class BookshelfView extends StatefulWidget {
  /// 架上的书(顺序 = 摆放顺序,数据层已按 slot 排好)
  final List<BookshelfBook> books;

  /// 顶部统计(不传就按 [books] 现算)
  final BookshelfStats? stats;

  /// 点一本书(书架页:直接打开阅读器)
  final ValueChanged<BookshelfBook>? onTapBook;

  /// 长按一本书(书架页:弹"打开 / 移出书架 / 查看封面")
  final ValueChanged<BookshelfBook>? onLongPressBook;

  /// 点空白书位(给"去挑一本"之类的引导留的口子)
  final VoidCallback? onTapEmptySlot;

  /// 每层最多几本;不传则按宽度自动算([booksPerShelf])
  final int? booksPerShelf;

  /// 是否显示顶部统计条
  final bool showStats;

  /// 空书架时按钮下方的补充说明(书架页传引导文案)
  final String? emptyHint;

  /// 空书架时的行动按钮(书架页传"去材料中心挑一本")
  final Widget? emptyAction;

  const BookshelfView({
    super.key,
    required this.books,
    this.stats,
    this.onTapBook,
    this.onLongPressBook,
    this.onTapEmptySlot,
    this.booksPerShelf,
    this.showStats = true,
    this.emptyHint,
    this.emptyAction,
  });

  @override
  State<BookshelfView> createState() => _BookshelfViewState();
}

class _BookshelfViewState extends State<BookshelfView> {
  /// 被点中的那本(先高亮,再进阅读器)。用 materialId 记,列表刷新后依然对得上。
  int? _selectedId;

  BookshelfStats get _stats => widget.stats ?? BookshelfStats.statsOf(widget.books);

  void _select(BookshelfBook b) {
    setState(() => _selectedId = b.materialId);
    final cb = widget.onTapBook;
    if (cb != null) {
      // 直接打开阅读器,不留一次"再点一下"的空转:用户点书就是想读它,
      // 高亮只作为这一瞬间的反馈(选中的书同时会显示在上方提示条里)。
      cb(b);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perShelf = widget.booksPerShelf ??
            booksPerShelf(constraints.maxWidth - Gap.md * 2);
        final rows = <List<BookshelfBook>>[];
        for (var i = 0; i < widget.books.length; i += perShelf) {
          rows.add(
            widget.books.sublist(i, math.min(i + perShelf, widget.books.length)),
          );
        }
        // 一本书都没有时也要摆一层空架子(用户:"最开始是空的书架")
        final empty = widget.books.isEmpty;
        if (empty) rows.add(const []);

        final selected = _findSelected();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showStats && !empty) ...[
              _StatsBar(stats: _stats),
              const SizedBox(height: Gap.sm),
            ],
            if (selected != null) ...[
              _HintBubble(
                book: selected,
                onOpen: () => widget.onTapBook?.call(selected),
              ),
              const SizedBox(height: Gap.xxs),
            ],
            for (var i = 0; i < rows.length; i++) ...[
              _ShelfRow(
                books: rows[i],
                perShelf: perShelf,
                selectedId: _selectedId,
                // 只有最后一层留空位:前面几层放满了,用户看到的是"这架还能放"
                fillEmpty: i == rows.length - 1 && !empty,
                onTapBook: _select,
                onLongPressBook: widget.onLongPressBook,
                onTapEmptySlot: widget.onTapEmptySlot,
              ),
              if (i != rows.length - 1) const SizedBox(height: SpineMetrics.rowSpacing),
            ],
            if (empty) ...[
              const SizedBox(height: Gap.md),
              Text(
                widget.emptyHint ??
                    '书架还是空的 —— 读到想留着的材料,在阅读器里点「加入书架」,它就摆上来了',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
              ),
              if (widget.emptyAction != null) ...[
                const SizedBox(height: Gap.md),
                Center(child: widget.emptyAction!),
              ],
            ],
          ],
        );
      },
    );
  }

  BookshelfBook? _findSelected() {
    final id = _selectedId;
    if (id == null) return null;
    for (final b in widget.books) {
      if (b.materialId == id) return b;
    }
    return null;
  }
}

/// 顶部统计:共几本 / 已读完 / 在读 / 合计读了多久
///
/// 为什么做成"四个大数字"而不是一行小字:用户对这一版的核心要求是
/// **"书架要有存在感"** —— 数字本身也是书架的一部分(藏书量、读完几本),
/// 用小字堆在角落就白做了。
class _StatsBar extends StatelessWidget {
  final BookshelfStats stats;

  const _StatsBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(140),
        borderRadius: Radii.cardRadius,
      ),
      child: Row(
        children: [
          _cell(context, '${stats.total}', '本藏书', theme.colorScheme.onSurface),
          _divider(context),
          _cell(context, '${stats.finished}', '已读完',
              theme.colorScheme.primary),
          _divider(context),
          _cell(context, '${stats.reading}', '在读', theme.colorScheme.tertiary),
          _divider(context),
          _cell(context, stats.minutesLabel, '累计阅读',
              theme.colorScheme.onSurface, small: true),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(
        width: 1,
        height: 26,
        color: Theme.of(context).colorScheme.outlineVariant.withAlpha(120),
      );

  Widget _cell(
    BuildContext context,
    String value,
    String label,
    Color color, {
    bool small = false,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                // 时长是"1 小时 20 分"这种长文案,字号小一档才放得下
                fontSize: small ? 15 : 20,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 点中书之后浮在上面的提示条:书名 + 进度 + 读了多久(点它可以再进阅读器)
class _HintBubble extends StatelessWidget {
  final BookshelfBook book;
  final VoidCallback onOpen;

  const _HintBubble({required this.book, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = book.percent.round();
    final tail = book.finished
        ? '已读完'
        : (pct <= 0 ? '还没翻开' : '读到 $pct%');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: Radii.controlRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(20),
            borderRadius: Radii.controlRadius,
            border: Border.all(color: theme.colorScheme.primary.withAlpha(70)),
          ),
          child: Row(
            children: [
              const Icon(Icons.bookmark_outline, size: 14),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: Gap.xs),
              Text(
                book.minutes > 0 ? '$tail · ${book.minutes} 分钟' : tail,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// **一层书架**:底板(画)+ 一排书(真的 widget,所以点得到)
///
/// 为什么底板用画、书用 widget:书要能点/长按/长按出弹层,做成画布上的像素
/// 就得自己命中测试;而底板只是一块木头,画出来最省。两者叠在同一层 Stack 里,
/// 尺寸都来自 [SpineMetrics],不会对不上。
class _ShelfRow extends StatelessWidget {
  final List<BookshelfBook> books;
  final int perShelf;
  final int? selectedId;

  /// 是否补空书位(只给最后一层补)
  final bool fillEmpty;

  final ValueChanged<BookshelfBook> onTapBook;
  final ValueChanged<BookshelfBook>? onLongPressBook;
  final VoidCallback? onTapEmptySlot;

  const _ShelfRow({
    required this.books,
    required this.perShelf,
    required this.selectedId,
    required this.fillEmpty,
    required this.onTapBook,
    this.onLongPressBook,
    this.onTapEmptySlot,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _ShelfPalette.of(context);
    final slots = math.max(perShelf, books.length);
    // 空书位最多画 6 个:再宽的屏也够表达"这架还能放",不至于铺成一片虚线
    final visibleSlots = math.min(slots, math.max(books.length, 6));
    return SizedBox(
      height: SpineMetrics.shelfHeight,
      child: Stack(
        children: [
          // 1. 书架的木框内壁(一条比页面稍深的竖面色),让书像"待在格子里"
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: SpineMetrics.plankThickness,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.alcove,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(Radii.control),
                ),
              ),
            ),
          ),
          // 2. 大块木色(单色,不设圆角 —— 圆角留给底板那块,层次才不会糊)
          Positioned.fill(child: ColoredBox(color: palette.wood)),
          // 3. 一层底板(带厚度与下沿阴影的自绘搁板)
          Positioned.fill(child: CustomPaint(painter: _PlankPainter(palette))),
          // 4. 一排书(靠左对齐,右面留白)
          Positioned(
            left: SpineMetrics.framePadding,
            right: SpineMetrics.framePadding,
            top: SpineMetrics.framePadding * 0.5,
            bottom: SpineMetrics.plankThickness +
                SpineMetrics.framePadding * 0.5,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < books.length; i++)
                  Expanded(
                    child: _BookSlot(
                      key: ValueKey(books[i].materialId),
                      book: books[i],
                      selected: books[i].materialId == selectedId,
                      onTap: () => onTapBook(books[i]),
                      onLongPress: onLongPressBook == null
                          ? null
                          : () => onLongPressBook!(books[i]),
                    ),
                  ),
                // 空书位也占同样的宽度:最后一层"还能放几本"一眼可见
                if (fillEmpty)
                  for (var i = books.length; i < visibleSlots; i++)
                    const Expanded(child: _EmptySlot()),
              ],
            ),
          ),
          // 5. 空书位也要能点(整条的点击区,命中测试比一个个小方块友好)
          if (fillEmpty && books.isEmpty && onTapEmptySlot != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onTapEmptySlot,
              ),
            ),
        ],
      ),
    );
  }
}

/// 单本书(书脊 + 点击/长按 + 选中回声)
class _BookSlot extends StatefulWidget {
  final BookshelfBook book;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _BookSlot({
    super.key,
    required this.book,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_BookSlot> createState() => _BookSlotState();
}

class _BookSlotState extends State<_BookSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heard = AnimationController(
    vsync: this,
    duration: Motion.tap,
    reverseDuration: Motion.transition,
  );

  bool _pressed = false;

  @override
  void didUpdateWidget(covariant _BookSlot old) {
    super.didUpdateWidget(old);
    // 被点中(选中的是"这一本"而不是"上一本")时给一次轻微回声:
    // 点书的瞬间阅读器就推上来了,没有这声"回响"会显得没反应。
    if (widget.selected && !old.selected) {
      _heard.forward(from: 0).then((_) {
        if (mounted) _heard.reverse();
      });
    }
  }

  @override
  void dispose() {
    _heard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _ShelfPalette.of(context);
    final colors = spinePalette(widget.book.title);
    final active = widget.selected || _pressed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _heard,
        builder: (context, child) {
          final lift = active ? 3.0 : 0.0;
          final scale = 1 + (active ? 0.05 : 0) + _heard.value * 0.02;
          return Transform.translate(
            offset: Offset(0, -lift),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          );
        },
        child: _BookSlotBox(
          child: _BookSpine(
            label: spineLabel(widget.book.title, vertical: true),
            percent: widget.book.percent,
            colors: colors,
            finished: widget.book.finished,
            selected: active,
            palette: palette,
          ),
        ),
      ),
    );
  }
}

/// 单个书位:书脊在书位里居中,并**按可用高度收一下**
///
/// 为什么要收高度:书脊高 122 是"理想值",而每层的高度由 [SpineMetrics] 算出来;
/// 万一将来改了搁板厚度/留白,这里不会变成一条 5px 的溢出条纹(黄黑警告条),
/// 而是整本书等比缩一点 —— 视觉上完全看不出来。
class _BookSlotBox extends StatelessWidget {
  final Widget child;

  const _BookSlotBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    );
  }
}

/// 书脊本体:圆角窄条 + 竖排书名 + 底部进度书签带(全部自绘)
class _BookSpine extends StatelessWidget {
  final String label;
  final double percent;
  final List<Color> colors;
  final bool finished;
  final bool selected;
  final _ShelfPalette palette;

  const _BookSpine({
    required this.label,
    required this.percent,
    required this.colors,
    required this.finished,
    required this.selected,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 书位宽度 → 书脊宽度(见 spineWidthForSlot 的注释:跟着屏宽走,
        // 一排书才会"摆满这层架子"而不是缩在左边)
        return SizedBox(
          width: spineWidthForSlot(constraints.maxWidth),
          height: SpineMetrics.height,
          child: CustomPaint(
            painter: _SpinePainter(
              label: label,
              progress: spineProgress(percent),
              colors: colors,
              finished: finished,
              selected: selected,
              palette: palette,
              labelColor: readableOn(colors.first),
            ),
          ),
        );
      },
    );
  }
}

/// 空书位:一道极淡的虚线框 + 最前面一个加号 —— "这架还能放"
class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    final palette = _ShelfPalette.of(context);
    return _BookSlotBox(
      child: CustomPaint(
        painter: _EmptySlotPainter(
          line: palette.slotHint,
          glyph: palette.slotHintGlyph,
        ),
        child: const SizedBox(
          width: SpineMetrics.maxWidth,
          height: SpineMetrics.height,
        ),
      ),
    );
  }
}

// ── 配色 ──────────────────────────────────────────────────────────────

/// 书架的木头/内壁配色(随明暗主题走两档)
class _ShelfPalette {
  /// 书架木框底色(页面与搁板之间那块面)
  final Color wood;

  /// 书架内壁(比木框稍深,做出"格子"的感觉)
  final Color alcove;

  /// 搁板正面(受光的那一条)
  final Color plankTop;

  /// 搁板下沿(背光,厚度感来源)
  final Color plankFront;

  /// 搁板投影
  final Color plankShadow;

  /// 内壁上沿的暗线(让格子有纵深)
  final Color alcoveEdge;

  /// 空书位的虚线
  final Color slotHint;

  /// 空书位的加号
  final Color slotHintGlyph;

  /// 选中态的光晕
  final Color glow;

  const _ShelfPalette({
    required this.wood,
    required this.alcove,
    required this.plankTop,
    required this.plankFront,
    required this.plankShadow,
    required this.alcoveEdge,
    required this.slotHint,
    required this.slotHintGlyph,
    required this.glow,
  });

  /// 深色主题:**深胡桃木** —— 比页面(#12141A)亮一档,书脊才"跳"得出来;
  /// 搁板正面再亮一点点,用来交代"这块板有厚度"。
  static const _ShelfPalette _dark = _ShelfPalette(
    wood: Color(0xFF2A2119),
    alcove: Color(0xFF1F1913),
    plankTop: Color(0xFF6A4F35),
    plankFront: Color(0xFF3B2C1F),
    plankShadow: Color(0xCC000000),
    alcoveEdge: Color(0xFF14100C),
    slotHint: Color(0x1FFFFFFF),
    slotHintGlyph: Color(0x33FFFFFF),
    glow: Color(0xFF6BA8E8), // 深色主色(AppTheme.darkPrimary)
  );

  /// 浅色主题:浅橡木(木色不能太黄,否则像旧木头家具而不是书架)
  static const _ShelfPalette _light = _ShelfPalette(
    wood: Color(0xFFE4D6C3),
    alcove: Color(0xFFD6C6B0),
    plankTop: Color(0xFFC4A276),
    plankFront: Color(0xFF9C7B52),
    plankShadow: Color(0x40000000),
    alcoveEdge: Color(0xFFB49C7C),
    slotHint: Color(0x22000000),
    slotHintGlyph: Color(0x44000000),
    glow: Color(0xFF4A90D9), // 浅色强调色(AppTheme.highlight)
  );

  /// 取当前主题那一档。
  ///
  /// 为什么是**两个 const 实例**而不是每次 new 一个:配色参与
  /// `CustomPainter.shouldRepaint` 的比较(见 [_PlankPainter]),每次返回新对象
  /// 会让"颜色根本没变"也判定成需要重绘 —— 书架上有几十本书,白白重绘很亏。
  static _ShelfPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;
}

// ── 自绘 ──────────────────────────────────────────────────────────────

/// 搁板(那块木头):上表面 + 厚度 + 下沿阴影 + 前沿高光
class _PlankPainter extends CustomPainter {
  final _ShelfPalette palette;

  _PlankPainter(this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final shelfTop = h - SpineMetrics.plankThickness - SpineMetrics.plankShadow;
    final top = math.max(0.0, shelfTop);
    final frontBottom = top + SpineMetrics.plankThickness;
    const r = Radius.circular(4);

    // 1. 下沿阴影:搁板"压"在下面那层上,先画才不会被板子盖住
    final shadowBottom = math.min(h.toDouble(), frontBottom + SpineMetrics.plankShadow);
    if (shadowBottom > frontBottom) {
      final rect = Rect.fromLTRB(0, frontBottom - 2, w, shadowBottom);
      canvas.drawRect(
        rect,
        Paint()
          ..color = palette.plankShadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // 2. 搁板上表面:受光 → 前沿渐深,厚度感就是这么来的
    final topFace = RRect.fromRectAndCorners(
      Rect.fromLTRB(0, top, w, frontBottom),
      topLeft: r,
      topRight: r,
    );
    canvas.drawRRect(
      topFace,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, top),
          Offset(0, frontBottom),
          [palette.plankTop, palette.plankFront],
        ),
    );

    // 3. 前沿上的一条亮线:像木头被磨得发亮的那道边
    canvas.drawLine(
      Offset(0, top + 1),
      Offset(w, top + 1),
      Paint()
        ..color = Colors.white.withAlpha(70)
        ..strokeWidth = 1.5,
    );

    // 4. 板子与内壁的接缝:一条暗线,把"格子"和"搁板"分开
    canvas.drawLine(
      Offset(0, top),
      Offset(w, top),
      Paint()
        ..color = palette.alcoveEdge
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _PlankPainter old) => old.palette != palette;
}

/// 书脊:圆角窄条 + 书头书尾的横带 + 竖排书名 + 底部进度书签带
class _SpinePainter extends CustomPainter {
  final String label;

  /// 0~1
  final double progress;
  final List<Color> colors;

  /// 读完的书:进度条走主色(一眼分辨"读完的那几本")
  final bool finished;
  final bool selected;
  final _ShelfPalette palette;
  final Color labelColor;

  _SpinePainter({
    required this.label,
    required this.progress,
    required this.colors,
    required this.finished,
    required this.selected,
    required this.palette,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final base = colors.first;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(3),
    );

    // 1. 选中光晕(先画,压在书脊下面)
    if (selected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h).inflate(2),
          const Radius.circular(6),
        ),
        Paint()
          ..color = palette.glow.withAlpha(130)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // 2. 底色:斜向渐变 + 中缝高光 —— 这是"书脊是圆的"的唯一线索
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, h),
          [base, colors.last],
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.30, 0, w * 0.26, h),
      Paint()
        ..color = Colors.white.withAlpha(26)
        ..blendMode = BlendMode.plus,
    );

    // 3. 左右边缘压暗:书与书之间才有"一本一本"的分界
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 2.5, h),
      Paint()..color = Colors.black.withAlpha(56),
    );
    canvas.drawRect(
      Rect.fromLTWH(w - 2.5, 0, 2.5, h),
      Paint()..color = Colors.black.withAlpha(70),
    );

    // 4. 书头/书尾两条横带:真书的堵头布,加一点"装帧"的细节
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.06, w, 1.5),
      Paint()..color = Colors.white.withAlpha(46),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.90, w, 1.5),
      Paint()..color = Colors.black.withAlpha(56),
    );

    // 5. 书签带:从底部往上长到进度位置。
    //    为什么用"生长的条"而不是"进度条控件":书脊只有 34 宽,
    //    任何标准进度控件在这里都是一根糊掉的线;一条从书尾长上来的彩带
    //    既看得清比例,又天然像"这本书被读到哪儿了"。
    if (progress > 0.01) {
      final filled = h * progress.clamp(0.0, 1.0);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(w - 9, h - filled, 6, filled),
        bottomLeft: const Radius.circular(3),
        bottomRight: const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, h - filled),
            Offset(0, h),
            finished
                ? [const Color(0xFF9FD9A8), const Color(0xFF4E9C5E)]
                : [const Color(0xFFF0C96A), const Color(0xFFD08A2C)],
          ),
      );
    } else {
      // 还没翻开:书签带画成一条极淡的"引子",暗示"读了就会有"
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w - 9, h - 14, 6, 14),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.white.withAlpha(30),
      );
    }

    // 6. 竖排书名:`TextPainter` 写在 90° 旋转的画布上。
    //
    //    为什么旋转画布而不是一个字一个字画:旋转一次就能用正常的排版引擎,
    //    字距、基线、字体度量全对;逐字 `drawParagraph` 要自己算每个字的位置,
    //    中英混排时会算歪。
    _paintVerticalText(canvas, size);
  }

  void _paintVerticalText(Canvas canvas, Size size) {
    final available = size.height * 0.78;
    var fontSize = 12.0;
    TextPainter tp = _layout(fontSize);
    // 太长就缩字号,而不是截断:书脊上宁可字小一点,也别显示半截书名
    while (tp.height > available && fontSize > 8) {
      fontSize -= 0.5;
      tp = _layout(fontSize);
    }
    canvas.save();
    // 目标位置(未旋转坐标系):文字的"左下角"
    canvas.translate(size.width * 0.62, size.height * 0.10);
    canvas.rotate(math.pi / 2); // 顺时针 90°:书脊上的字从上往下读
    tp.paint(canvas, Offset(-tp.width, 0));
    canvas.restore();
  }

  TextPainter _layout(double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.0,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: labelColor,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: SpineMetrics.height * 0.8);
    return tp;
  }

  @override
  bool shouldRepaint(covariant _SpinePainter old) =>
      old.label != label ||
      old.progress != progress ||
      old.colors != colors ||
      old.finished != finished ||
      old.selected != selected ||
      old.labelColor != labelColor;
}

/// 空书位:一道虚线框(下沿与书尾齐平),最前面那个带一个淡淡加号
class _EmptySlotPainter extends CustomPainter {
  final Color line;
  final Color glyph;

  _EmptySlotPainter({required this.line, required this.glyph});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 6 || h <= 6) return;
    // 与书脊对齐:书位里书脊居中占 [spineWidthForSlot],虚线框也照着它画
    final spine = spineWidthForSlot(w);
    final rect = Rect.fromLTWH((w - spine) / 2, 8, spine, h - 12);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    _dashedRRect(canvas, rrect, paint);

    // 一个极淡的加号:告诉用户"这里可以放书"
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final plus = Paint()
      ..color = glyph
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 4, cy), Offset(cx + 4, cy), plus);
    canvas.drawLine(Offset(cx, cy - 4), Offset(cx, cy + 4), plus);
  }

  /// 虚线圆角矩形:用 PathMetrics 沿轮廓取段 —— 手算四条边太容易在圆角处接歪
  void _dashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    final path = Path()..addRRect(rrect);
    const dash = 4.0;
    const gapLen = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EmptySlotPainter old) =>
      old.line != line || old.glyph != glyph;
}
