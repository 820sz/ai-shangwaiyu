import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import 'graphics_palette.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 图形资产的**基础设施**:颜色束 / painter 基类 / 统一笔触 / 画法小工具。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 三条硬约束(整个图形系统都靠它们成立):
/// 1. **painter 只吃纯 Color**。`BuildContext` 在 paint 里既拿不到也不该有 ——
///    颜色在 build 阶段解析成 [GraphicInk] 传进来,`shouldRepaint` 才有东西可比;
/// 2. **一套笔**。所有笔画走 [graphicStroke]:圆头、圆角、统一线宽,
///    这样 13 个领域 + 7 种封面 + 5 种空态看起来才是"同一只手画的";
/// 3. **paint 里不做重活**。不建 TextPainter(除数据图形的中心数字)、
///    不在循环里建 Paint、复杂的几何要么用常量、要么缓存(见 [GraphicPainter.pathFor])。

/// 一个图形用到的**已解析颜色**(明暗两套已经算完,和主题彻底解耦)。
///
/// 为什么打包成一个值对象:`shouldRepaint` 只比 `ink != ink` 一次,而不是逐字段比;
/// 且 painter 构造签名统一,新增画法不用改基类。
@immutable
class GraphicInk {
  const GraphicInk({
    required this.line,
    required this.accent,
    required this.tone,
  });

  /// 主墨线:结构线(坐标、分栏、网格、外框)
  final Color line;

  /// 身份色:这张图"是谁"的那几笔(轨道、波形、书脊…) —— 也是面板底色来源
  final Color accent;

  /// 弱化色:细节/纹理(比主墨线轻一档,仍 ≥3:1)
  final Color tone;

  /// 从主题解析(唯一入口,普通页面只需要用它)
  static GraphicInk of(BuildContext context, {Color? accent}) {
    return GraphicInk(
      line: GraphicsPalette.line(context),
      accent: accent ?? Theme.of(context).colorScheme.primary,
      tone: GraphicsPalette.faint(context),
    );
  }

  /// 派生出"同一套色的另一种浓度"(只改 alpha,不改色相)
  GraphicInk withAccent(Color next) =>
      GraphicInk(line: line, accent: next, tone: tone);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphicInk &&
          other.line == line &&
          other.accent == accent &&
          other.tone == tone;

  @override
  int get hashCode => Object.hash(line, accent, tone);

  @override
  String toString() => 'GraphicInk(line: $line, accent: $accent, tone: $tone)';
}

/// 所有自绘图形的基类。
///
/// 和直接 `extends CustomPainter` 相比,这里锁死两件事:
/// - **颜色已在构造时解析完**(不持有 context,不在 paint 里读 Theme);
/// - **`shouldRepaint` 默认行为正确**:只有颜色 / 线宽 / 具体子类变化才重绘。
///   子类若有额外参数(数值数组、比例),**必须**覆写并 `super.shouldRepaint(old) || ...`,
///   否则滚动列表里那些图形会"数据变了但不刷新"。
abstract class GraphicPainter extends CustomPainter {
  // 注意:这里刻意不是 const 构造 —— 基类持有单槽路径缓存(可变字段),
  // 而 painter 本来就是每次 build 新建的轻对象,const 化收益为零。
  GraphicPainter({required this.ink, required this.stroke});

  final GraphicInk ink;

  /// 视觉线宽(由 [GraphicsPalette.strokeOf] 按尺寸算好,不在这里猜)
  final double stroke;

  /// 单槽几何缓存:尺寸不变时复用上次建好的 Path。
  ///
  /// 说明:painter 通常每次 build 都新建,所以这个缓存只在"同一个 painter 被多次
  /// paint"(重绘但没重建 widget,例如父级滚动/动画)时生效。真正的性能保证是
  /// 下面的 `shouldRepaint` + [GraphicFrame] 的 RepaintBoundary;
  /// 缓存是第三道防线 —— 对路径复杂的图(书页层叠、封面纹理)值得。
  Path pathFor(Size size, Path Function(Size size) build) {
    if (_cachedPath != null && _cachedSize == size) return _cachedPath!;
    _cachedSize = size;
    _cachedPath = build(size);
    return _cachedPath!;
  }

  Size? _cachedSize;
  Path? _cachedPath;

  /// 描边笔:圆头圆角 —— 全 App 图形同一支笔
  Paint strokePaint(Color color, {double? width, double alpha = 1.0}) {
    return Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width ?? stroke
      ..color = alpha >= 1 ? color : color.withAlpha((color.a * 255 * alpha).round());
  }

  /// 填充笔
  Paint fillPaint(Color color, {double alpha = 1.0}) {
    return Paint()
      ..style = PaintingStyle.fill
      ..color = alpha >= 1 ? color : color.withAlpha((color.a * 255 * alpha).round());
  }

  @override
  bool shouldRepaint(covariant GraphicPainter old) {
    return old.runtimeType != runtimeType ||
        old.ink != ink ||
        old.stroke != stroke;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 统一画法工具(函数式,无状态)
// ═══════════════════════════════════════════════════════════════════════

/// 描边笔(给不走 painter 基类的数据图形用)
Paint graphicStroke(Color color, double width) {
  return Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = width
    ..color = color;
}

/// 填充笔
Paint graphicFill(Color color) => Paint()
  ..style = PaintingStyle.fill
  ..color = color;

/// 椭圆轨道(科学/科技的三条轨道):以 [center] 为心旋转 [rotation] 弧度后描边。
///
/// 用 canvas 变换而不是手算点:轨道要"转起来"才有原子模型的辨识度,
/// 旋转交给 canvas 比自己算 12 个椭圆点清楚得多。
void drawOrbit(
  Canvas canvas,
  Offset center,
  Size orbit,
  Paint paint, {
  double rotation = 0,
}) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(rotation);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: orbit.width, height: orbit.height),
    paint,
  );
  canvas.restore();
}

/// 折线(柱顶连线 / 折线图 / 心电图共用)
void drawPolyline(Canvas canvas, List<Offset> points, Paint paint) {
  if (points.length < 2) return;
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length; i++) {
    path.lineTo(points[i].dx, points[i].dy);
  }
  canvas.drawPath(path, paint);
}

/// 点阵(3×3 / 2×2)
///
/// [rect] 是**点阵中心覆盖的区域**:点按行列均分,不贴边。
void drawDotGrid(
  Canvas canvas,
  Rect rect,
  Paint paint, {
  required int cols,
  required int rows,
  double radius = 1.8,
}) {
  if (cols <= 0 || rows <= 0) return;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final x = cols == 1
          ? rect.center.dx
          : rect.left + rect.width * c / (cols - 1);
      final y = rows == 1
          ? rect.center.dy
          : rect.top + rect.height * r / (rows - 1);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }
}

/// 拱门(文化/艺术):两侧竖边 + 顶部半圆
///
/// 路径按 [rect] 自动算半径(宽一半):拱脚的竖直段 = 矩形高 − 半径,
/// 所以传一个"比半圆高"的矩形就是完整拱门,不会画成圆。
void drawArch(Canvas canvas, Rect rect, Paint paint) {
  final radius = rect.width / 2;
  final archTop = Rect.fromLTWH(rect.left, rect.top, rect.width, radius * 2);
  final path = Path()
    ..moveTo(rect.left, rect.bottom)
    ..lineTo(rect.left, rect.top + radius)
    ..arcTo(archTop, math.pi, math.pi, false)
    ..lineTo(rect.right, rect.bottom);
  canvas.drawPath(path, paint);
}

/// 四角星芒(科学/科技的中心亮点、custom 兜底的罗盘星)
///
/// 四个长角 + 四个短角(notch),几何化而非"爆炸形":克制。
void drawStar4(
  Canvas canvas,
  Offset center,
  double radius,
  Paint paint, {
  double notch = 0.26,
}) {
  final inner = radius * notch;
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final angle = -math.pi / 2 + i * math.pi / 4;
    final r = i.isEven ? radius : inner;
    final p = Offset(
      center.dx + math.cos(angle) * r,
      center.dy + math.sin(angle) * r,
    );
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  path.close();
  canvas.drawPath(path, paint);
}

/// 虚线圆弧(旅行航线 / custom 兜底的虚线圆 / 计时环)
///
/// 用"每段小圆弧"实现而不是 PathMetric:圆弧的 dash 就是角度切分,算起来最省,
/// 也不依赖 Path 的度量 API。
void drawDashedArc(
  Canvas canvas,
  Offset center,
  double radius,
  double startAngle,
  double sweepAngle,
  Paint paint, {
  double dash = 6,
  double gap = 5,
}) {
  if (radius <= 0 || sweepAngle == 0) return;
  final dir = sweepAngle.sign;
  final dashAngle = dash / radius;
  final gapAngle = gap / radius;
  final end = startAngle + sweepAngle;
  var a = startAngle;
  final rect = Rect.fromCircle(center: center, radius: radius);
  // 上限保护:半径极小 + dash 极小时避免死循环
  var guard = 0;
  while ((dir > 0 ? a < end : a > end) && guard < 512) {
    guard++;
    final remaining = (end - a).abs();
    final next = a + dir * math.min(dashAngle, remaining);
    canvas.drawArc(rect, a, next - a, false, paint);
    a = next + dir * gapAngle;
  }
}

/// 虚线段(纸飞机的虚线航迹、虚线圆之外的自由曲线)
///
/// 按累计弧长切段:曲线本身是折线近似,所以这里只要沿段长走即可。
void drawDashedPolyline(
  Canvas canvas,
  List<Offset> points,
  Paint paint, {
  double dash = 6,
  double gap = 5,
}) {
  if (points.length < 2) return;
  final period = dash + gap;
  var cursor = 0.0; // 笔尖在一个 dash+gap 周期里的位置(跨线段连续)
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final len = (b - a).distance;
    if (len <= 0) continue;
    var t = 0.0;
    while (t < len) {
      final inDash = cursor < dash;
      // 本周期还剩多长(画完 or 空完)
      final limit = inDash ? dash - cursor : period - cursor;
      final take = math.min(limit, len - t);
      if (inDash) {
        canvas.drawLine(
          Offset.lerp(a, b, t / len)!,
          Offset.lerp(a, b, (t + take) / len)!,
          paint,
        );
      }
      t += take;
      cursor = (cursor + take) % period;
    }
  }
}

/// 正弦波(空态兜底的波纹):用二次贝塞尔近似,控制点偏移 = 2×振幅
void drawWave(
  Canvas canvas,
  Rect rect,
  Paint paint, {
  int cycles = 2,
}) {
  final half = rect.height / 2;
  final cy = rect.center.dy;
  final step = rect.width / (cycles * 2);
  final path = Path()..moveTo(rect.left, cy);
  for (var i = 0; i < cycles * 2; i++) {
    final x0 = rect.left + step * i;
    final up = i.isEven;
    path.quadraticBezierTo(
      x0 + step / 2,
      cy + (up ? -2 * half : 2 * half),
      x0 + step,
      cy,
    );
  }
  canvas.drawPath(path, paint);
}

/// 对勾(备考:答对了)
void drawCheck(Canvas canvas, Rect rect, Paint paint) {
  final points = <Offset>[
    Offset(rect.left, rect.top + rect.height * 0.54),
    Offset(rect.left + rect.width * 0.34, rect.bottom),
    Offset(rect.right, rect.top),
  ];
  drawPolyline(canvas, points, paint);
}

/// 圆角矩形描边(带统一圆角比例)
void drawRoundRect(
  Canvas canvas,
  Rect rect,
  Paint paint, {
  double radiusFactor = 0.18,
}) {
  final r = math.min(rect.width, rect.height) * radiusFactor;
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(r)),
    paint,
  );
}

/// 从一条二次贝塞尔上采样若干点(虚线弧航线之类)
List<Offset> quadraticPoints(
  Offset start,
  Offset control,
  Offset end, {
  int segments = 28,
}) {
  final points = <Offset>[];
  for (var i = 0; i <= segments; i++) {
    final t = i / segments;
    final mt = 1 - t;
    final x = mt * mt * start.dx + 2 * mt * t * control.dx + t * t * end.dx;
    final y = mt * mt * start.dy + 2 * mt * t * control.dy + t * t * end.dy;
    points.add(Offset(x, y));
  }
  return points;
}

// ═══════════════════════════════════════════════════════════════════════
// 统一外壳
// ═══════════════════════════════════════════════════════════════════════

/// 图形的**统一外壳**:固定尺寸 + 可选淡色面板 + 圆角 + 重绘边界 + 无障碍标签。
///
/// 为什么必须有外壳,而不是让每个调用方自己包 SizedBox + CustomPaint:
/// - 尺寸必须从 4 个档位里选(72/96/120/160)。散着写,同一个图形在不同页面
///   就会出现 84、100、116 这些"看起来差不多但就是不齐"的尺寸;
/// - 圆角必须统一(control 12 / card 20 / hero 24);
/// - **RepaintBoundary** 是性能关键:图形一旦画好就是一张位图,列表滚动时
///   0 重绘(见 README 里的性能说明);
/// - 图形本身没有文字,读屏软件会把整块当空气 —— 必须给中文 [semanticLabel]。
class GraphicFrame extends StatelessWidget {
  const GraphicFrame({
    super.key,
    required this.painter,
    this.size = GraphicsPalette.defaultSize,
    this.semanticLabel,
    this.panelAccent,
    this.radius,
  });

  /// 实际绘制者(颜色已在构建时解析好)
  final CustomPainter painter;

  /// 尺寸(建议取自 [GraphicsPalette.sizes])
  final double size;

  /// 无障碍标签(中文);null 则不进语义树(纯装饰图形)
  final String? semanticLabel;

  /// 非空 = 画一层该色的淡渐变面板(空态/hero 位常用)
  final Color? panelAccent;

  /// 圆角;null 时按尺寸取 Radii 档位
  final double? radius;

  /// 按尺寸取统一圆角档:小图 12、中图 20、hero 24(全部来自 Radii 令牌)
  static double radiusOf(double size) {
    if (size >= 160) return Radii.hero;
    if (size >= 120) return Radii.card;
    return Radii.control;
  }

  @override
  Widget build(BuildContext context) {
    final r = radius ?? radiusOf(size);
    Widget art = CustomPaint(painter: painter, size: Size.square(size));
    final accent = panelAccent;
    if (accent != null) {
      art = DecoratedBox(
        decoration: GraphicsPalette.panelDecoration(context, accent, r),
        child: art,
      );
    }
    Widget box = SizedBox(width: size, height: size, child: art);
    // RepaintBoundary:图形是静态的,画成位图后父级滚动/动画都不再重绘它
    box = RepaintBoundary(child: box);
    final label = semanticLabel;
    if (label != null && label.isNotEmpty) {
      box = Semantics(container: true, image: true, label: label, child: box);
    }
    return box;
  }
}
