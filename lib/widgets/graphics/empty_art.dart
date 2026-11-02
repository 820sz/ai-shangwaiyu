import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'graphics_core.dart';
import 'graphics_palette.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// **空态图形**(v2.13 · 图形资产系统 · 批 1)。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 空态是全 App 最容易显得"简陋"的地方:一块灰字 + 一个通用 inbox 图标,
/// 用户看不到"为什么空、空了之后会有什么"。这里给 5 种"为什么空"各配一个
/// 几何化的说法 —— 但**只画图形不写文案**,文案由调用方给(空态文案要结合
/// 上下文,不能写死在图形里)。
///
/// 配色刻意比领域图形更素:空态是"没有内容"的状态,不该比内容更抢眼。
/// 所以只有**主墨线 + 一点主题主色**,连领域身份色都不用。
///
/// 调用方一般不需要自己选图形:全 App 三个空态组件(`AppEmptyState` /
/// `AppEmpty` / `EmptyState`)会按旧的 `icon` 参数自动映射到 5 种图形之一
/// (规则见 [EmptyArtKind.fromIcon],在 graphics_palette.dart 的枚举里)。
/// 需要精确表达时,组件的 `art:` 参数可以直接指定 [EmptyArtKind]。
class EmptyArt extends StatelessWidget {
  const EmptyArt({
    super.key,
    required this.kind,
    this.size = GraphicsPalette.defaultSize,
    this.accent,
    this.semanticLabel,
  });

  final EmptyArtKind kind;

  /// 建议取自 [GraphicsPalette.sizes]
  final double size;

  /// 强调色;默认用主题主色(空态不引入新色相)
  final Color? accent;

  /// 无障碍标签;默认「<图形名>插图」
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = GraphicInk(
      line: GraphicsPalette.line(context),
      accent: accent ?? theme.colorScheme.primary,
      tone: GraphicsPalette.faint(context),
    );
    return GraphicFrame(
      painter: _painterFor(kind, ink, GraphicsPalette.strokeOf(size)),
      size: size,
      semanticLabel: semanticLabel ?? '${kind.label}插图',
      // 空态图形不进面板:它直接落在页面底上,加面板反而像"独立卡片"
    );
  }
}

GraphicPainter _painterFor(EmptyArtKind kind, GraphicInk ink, double stroke) {
  return switch (kind) {
    EmptyArtKind.floatingPages =>
      _FloatingPagesPainter(ink: ink, stroke: stroke),
    EmptyArtKind.paperPlane => _PaperPlanePainter(ink: ink, stroke: stroke),
    EmptyArtKind.scatteredLetters =>
      _ScatteredLettersPainter(ink: ink, stroke: stroke),
    EmptyArtKind.magnifier => _MagnifierPainter(ink: ink, stroke: stroke),
    EmptyArtKind.generic => _GenericPainter(ink: ink, stroke: stroke),
  };
}

/// 漂浮书页(「还没有内容 / 没有收藏」):3 张旋转的纸页 + 几个浮点。
///
/// 为什么是"飘"而不是"一摞书":空态要表达的是"这里将来会有东西",旋转 +
/// 浮点让画面有"轻"的感觉,不是"少了一摞书"的缺失感。
class _FloatingPagesPainter extends GraphicPainter {
  _FloatingPagesPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = size.center(Offset.zero);

    // 三张纸页:角度/位置错开,最后一张最淡(景深)
    _page(canvas, c, s, angle: -0.28, dx: -0.10, dy: 0.06, stroke: stroke,
        paint: strokePaint(ink.accent.withAlpha(235)));
    _page(canvas, c, s, angle: 0.10, dx: 0.06, dy: -0.02, stroke: stroke,
        paint: strokePaint(ink.tone.withAlpha(200)));
    _page(canvas, c, s, angle: 0.42, dx: 0.16, dy: -0.10, stroke: stroke,
        paint: strokePaint(ink.tone.withAlpha(140)));

    // 浮点:一大两小,位置不对称(对称会像"雪花",不对称才像"飘")
    final dot = fillPaint(ink.accent);
    canvas.drawCircle(c + Offset(s * 0.30, -s * 0.28), stroke * 0.95, dot);
    canvas.drawCircle(c + Offset(s * 0.38, -s * 0.12), stroke * 0.62,
        fillPaint(ink.tone));
    canvas.drawCircle(c + Offset(-s * 0.34, -s * 0.20), stroke * 0.75,
        fillPaint(ink.accent.withAlpha(150)));
  }

  void _page(
    Canvas canvas,
    Offset c,
    double s, {
    required double angle,
    required double dx,
    required double dy,
    required double stroke,
    required Paint paint,
  }) {
    final w = s * 0.30;
    final h = s * 0.38;
    canvas.save();
    canvas.translate(c.dx + s * dx, c.dy + s * dy);
    canvas.rotate(angle);
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.022));
    canvas.drawRRect(rr, paint);
    // 页内两行文字线:让"纸页"读得懂,不是空方块
    final linePaint = graphicStroke(paint.color.withAlpha(
      (paint.color.a * 255 * 0.55).round(),
    ), stroke * 0.62);
    for (var i = 0; i < 2; i++) {
      final y = -h * 0.16 + h * 0.24 * i;
      canvas.drawLine(
        Offset(-w * 0.28, y),
        Offset(w * (i == 0 ? 0.30 : 0.16), y),
        linePaint,
      );
    }
    canvas.restore();
  }
}

/// 纸飞机(「还没有开始 / 没有记录」):虚线航迹 + 飞机 + 一朵云。
///
/// 空态里最适合表达"起步"的符号。航迹用虚线 = "将要去"而不是"已经去过",
/// 这是它和旅行领域图形的差别(旅行是实线 + 飞机已经到达)。
class _PaperPlanePainter extends GraphicPainter {
  _PaperPlanePainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);

    // 云:两个圆(和旅行图形同语言,但只有一朵,画面更空)
    // 底边对齐再压底线,才像一朵云(不对齐会像"两个泡泡")
    final cloud = strokePaint(ink.tone, width: stroke * 0.8);
    canvas.drawCircle(Offset(s * 0.25, s * 0.302), s * 0.058, cloud);
    canvas.drawCircle(Offset(s * 0.335, s * 0.322), s * 0.038, cloud);
    canvas.drawLine(
      Offset(s * 0.205, s * 0.360),
      Offset(s * 0.385, s * 0.360),
      cloud,
    );

    // 虚线航迹:从左下爬升到右上
    final arc = quadraticPoints(
      Offset(s * 0.14, s * 0.80),
      Offset(s * 0.36, s * 0.34),
      Offset(s * 0.72, s * 0.32),
      segments: 24,
    );
    drawDashedPolyline(
      canvas,
      arc,
      strokePaint(ink.accent.withAlpha(200), width: stroke * 0.85),
      dash: s * 0.05,
      gap: s * 0.038,
    );

    // 纸飞机:两个三角拼折叠(上翼实色、下翼半透明)
    final tip = Offset(s * 0.82, s * 0.22);
    final back = Offset(s * 0.56, s * 0.34);
    final tail = Offset(s * 0.63, s * 0.49);
    final fold = Offset(s * 0.615, s * 0.368);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(back.dx, back.dy)
        ..lineTo(fold.dx, fold.dy)
        ..close(),
      fillPaint(ink.accent),
    );
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(fold.dx, fold.dy)
        ..lineTo(tail.dx, tail.dy)
        ..close(),
      fillPaint(ink.accent.withAlpha(155)),
    );

    // 两个小点:补"飘着"的空气感
    canvas.drawCircle(Offset(s * 0.46, s * 0.22), stroke * 0.62,
        fillPaint(ink.tone));
    canvas.drawCircle(Offset(s * 0.20, s * 0.52), stroke * 0.8,
        fillPaint(ink.accent.withAlpha(140)));
  }
}

/// 散落字母(「还没有单词 / 词库为空」):几何化的 A/B/C + 几个点。
///
/// 用"散落"而不是"一列字母":词库空的时候,用户看到的不该是"整齐缺失",
/// 而是"字母还没被收集起来"。三个字母各自旋转一点,就有了"散"的意思。
class _ScatteredLettersPainter extends GraphicPainter {
  _ScatteredLettersPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final accent = strokePaint(ink.accent, width: stroke * 1.05);
    final tone = strokePaint(ink.tone, width: stroke * 0.95);

    // A:顶点 + 两条腿 + 横杠
    final aCenter = Offset(s * 0.30, s * 0.44);
    canvas.save();
    canvas.translate(aCenter.dx, aCenter.dy);
    canvas.rotate(-0.14);
    canvas.drawLine(Offset(0, -s * 0.16), Offset(-s * 0.13, s * 0.16), accent);
    canvas.drawLine(Offset(0, -s * 0.16), Offset(s * 0.13, s * 0.16), accent);
    canvas.drawLine(Offset(-s * 0.075, s * 0.045), Offset(s * 0.075, s * 0.045), accent);
    canvas.restore();

    // B:竖线 + 两个半圆(上半圆小、下半圆大)
    final bCenter = Offset(s * 0.50, s * 0.40);
    canvas.save();
    canvas.translate(bCenter.dx, bCenter.dy);
    canvas.rotate(0.10);
    canvas.drawLine(Offset(-s * 0.10, -s * 0.17), Offset(-s * 0.10, s * 0.17), tone);
    for (var i = 0; i < 2; i++) {
      final r = s * (i == 0 ? 0.075 : 0.095);
      final cy = i == 0 ? -s * 0.075 : s * 0.075;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(-s * 0.10, cy), radius: r),
        -math.pi / 2,
        math.pi,
        false,
        tone,
      );
    }
    canvas.restore();

    // C:开口朝右的大弧
    final cCenter = Offset(s * 0.76, s * 0.46);
    canvas.save();
    canvas.translate(cCenter.dx, cCenter.dy);
    canvas.rotate(0.20);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: s * 0.145),
      math.pi * 0.28,
      math.pi * 1.44,
      false,
      accent,
    );
    canvas.restore();

    // 散点:3 个,不对称
    final dot = fillPaint(ink.accent);
    canvas.drawCircle(Offset(s * 0.62, s * 0.20), stroke * 0.82, dot);
    canvas.drawCircle(Offset(s * 0.22, s * 0.72), stroke * 0.6,
        fillPaint(ink.tone));
    canvas.drawCircle(Offset(s * 0.86, s * 0.72), stroke * 0.72,
        fillPaint(ink.accent.withAlpha(150)));
  }
}

/// 放大镜(「没有搜到 / 没有结果」):圆 + 柄 + 圈内点 + 一道扫线。
///
/// 搜索无结果是高频空态,放大镜是最不易出错的符号。圈里放"扫线 + 两个点",
/// 让画面像"正在找"而不是"找不到"(空态不该加重挫败感)。
class _MagnifierPainter extends GraphicPainter {
  _MagnifierPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final center = Offset(s * 0.45, s * 0.43);
    final radius = s * 0.235;

    // 镜圈
    canvas.drawCircle(
      center,
      radius,
      strokePaint(ink.accent, width: stroke * 1.15),
    );
    // 柄:一圈粗线,从镜圈右下伸出去(带圆头,和镜圈自然相接)
    canvas.drawLine(
      center + Offset.fromDirection(math.pi / 4, radius * 0.92),
      center + Offset.fromDirection(math.pi / 4, radius * 1.62),
      strokePaint(ink.accent, width: stroke * 1.35),
    );

    // 圈内:一道斜扫线 + 两个点(暗示"正在搜索")
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));
    canvas.drawLine(
      center + Offset(-radius * 0.62, radius * 0.5),
      center + Offset(radius * 0.62, -radius * 0.5),
      strokePaint(ink.accent.withAlpha(90), width: stroke * 0.8),
    );
    canvas.restore();

    canvas.drawCircle(
      center + Offset(-radius * 0.34, radius * 0.10),
      stroke * 0.82,
      fillPaint(ink.line),
    );
    canvas.drawCircle(
      center + Offset(radius * 0.24, -radius * 0.30),
      stroke * 0.58,
      fillPaint(ink.tone),
    );

    // 圈外两点:视线的落点
    canvas.drawCircle(Offset(s * 0.80, s * 0.20), stroke * 0.62,
        fillPaint(ink.accent.withAlpha(140)));
    canvas.drawCircle(Offset(s * 0.22, s * 0.74), stroke * 0.5,
        fillPaint(ink.tone));
  }
}

/// 兜底空态:两道波纹 + 点。
///
/// 没有任何具体语义时,最安全的做法是"安静的水面" —— 不暗示任何方向,
/// 也不至于是一块空白。
class _GenericPainter extends GraphicPainter {
  _GenericPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);

    // 两道错开的波纹:上面实一点、下面淡一点
    drawWave(
      canvas,
      Rect.fromLTRB(s * 0.12, s * 0.30, s * 0.88, s * 0.50),
      strokePaint(ink.accent.withAlpha(210), width: stroke * 1.0),
      cycles: 2,
    );
    drawWave(
      canvas,
      Rect.fromLTRB(s * 0.18, s * 0.58, s * 0.82, s * 0.72),
      strokePaint(ink.tone.withAlpha(170), width: stroke * 0.85),
      cycles: 2,
    );

    // 三个点:疏密不均(均匀会像"省略号")
    canvas.drawCircle(Offset(s * 0.50, s * 0.22), stroke * 0.8,
        fillPaint(ink.accent));
    canvas.drawCircle(Offset(s * 0.32, s * 0.80), stroke * 0.58,
        fillPaint(ink.tone));
    canvas.drawCircle(Offset(s * 0.70, s * 0.84), stroke * 0.72,
        fillPaint(ink.accent.withAlpha(150)));
  }
}
