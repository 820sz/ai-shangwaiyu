import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/theme.dart';
import 'graphics_core.dart';
import 'graphics_palette.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// **数据图形**(v2.13 · 图形资产系统 · 批 1)。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 为什么不用 `fl_chart`(项目里已有):
/// 1. fl_chart 是为"可交互的完整图表"设计的,一个柱状小图也要 60+ 行配置,
///    而统计页需要的是"**一眼看个大概**"的 sparkline;
/// 2. 这里的四个图形是**装饰性/概览性**的(柱、折线、热力、环形),数据量很小,
///    自绘 30 行就够,还能和图形资产共用同一套笔触与主题解析逻辑;
/// 3. 零依赖 = 零构建风险(pubspec 里有过加插件导致 APK 构建不过的教训)。
///
/// 主题感知:数据色统一走 [AppTheme.chartSeries](浅色 #2C6BB3 / 深色 #6BA8E8,
/// 两档都过 3:1),结构/空档走主题的 faint。深色下不会出现"白底图表"。
///
/// 无障碍:每个图形都给中文 [Semantics] 标签 —— 图形本身对读屏软件是空的,
/// 数据必须能被读出来。

// ═══════════════════════════════════════════════════════════════════════
// 1) 迷你柱状图
// ═══════════════════════════════════════════════════════════════════════

/// 迷你柱状图:7 根左右的柱子,可高亮最后一根(「今天」)。
///
/// 典型用途:一周学习量、每日新增词数。不画坐标轴、不画网格线 ——
/// 卡片的正文里已经有数字了,这里只负责"形"。
class SparkBars extends StatelessWidget {
  const SparkBars({
    super.key,
    required this.values,
    this.height = 56,
    this.width,
    this.color,
    this.highlightLast = true,
    this.semanticLabel,
  });

  /// 数值数组(顺序 = 从左到右)
  final List<double> values;

  final double height;

  /// 宽度;null 时撑满父级(父级必须有界)
  final double? width;

  /// 覆盖数据色;默认走主题图表色
  final Color? color;

  /// 是否高亮最后一根(默认"今天/最新"那一根实心)
  final bool highlightLast;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final series = color ?? AppTheme.chartSeries(context);
    final ink = GraphicInk(
      line: series,
      accent: series,
      tone: GraphicsPalette.faint(context),
    );
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel ?? '柱状图',
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _SparkBarsPainter(
              ink: ink,
              stroke: GraphicsPalette.strokeOf(height),
              values: values,
              highlightLast: highlightLast,
            ),
          ),
        ),
      ),
    );
  }
}

class _SparkBarsPainter extends GraphicPainter {
  _SparkBarsPainter({
    required super.ink,
    required super.stroke,
    required this.values,
    required this.highlightLast,
  });

  final List<double> values;
  final bool highlightLast;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0) return;
    var maxValue = 0.0;
    for (final v in values) {
      if (v > maxValue) maxValue = v;
    }
    // 全 0 时也要画出"一排矮柱",否则空数据看起来像渲染失败
    final scale = maxValue <= 0 ? 1.0 : maxValue;

    // 柱宽 = 总宽 / (n*1.55 + 0.55):间距是柱宽的 55%,两端留白很薄
    final barW = size.width / (n * 1.55 + 0.55);
    final gap = barW * 0.55;
    final usableH = size.height * 0.92;
    final bottom = size.height;

    for (var i = 0; i < n; i++) {
      final v = values[i].clamp(0.0, double.infinity).toDouble();
      // 最小 6% 高度:0 值也给一根"地桩",不然那一列是纯空白
      final hRatio = math.max(0.06, v / scale);
      final h = usableH * hRatio;
      final x = gap * 0.5 + i * (barW + gap);
      final rect = Rect.fromLTRB(x, bottom - h, x + barW, bottom);
      final highlighted = highlightLast && i == n - 1;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(barW * 0.34),
          topRight: Radius.circular(barW * 0.34),
        ),
        fillPaint(
          highlighted ? ink.accent : ink.accent.withAlpha(110),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparkBarsPainter old) {
    return super.shouldRepaint(old) ||
        old.highlightLast != highlightLast ||
        !_sameDoubles(old.values, values);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 2) 趋势折线
// ═══════════════════════════════════════════════════════════════════════

/// 趋势折线:折线 + 渐变面积 + 末端圆点。
///
/// 面积用"数据色 → 透明"的竖向渐变:比纯色面积多一层空间感,又不像
/// 高斯模糊那样占 GPU。折线不做曲线平滑 —— 统计数据的"真实折点"比好看重要。
class TrendLine extends StatelessWidget {
  const TrendLine({
    super.key,
    required this.points,
    this.height = 80,
    this.width,
    this.color,
    this.showArea = true,
    this.showEndDot = true,
    this.semanticLabel,
  });

  /// 数值序列(顺序 = 从左到右)
  final List<double> points;

  final double height;
  final double? width;
  final Color? color;
  final bool showArea;
  final bool showEndDot;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final series = color ?? AppTheme.chartSeries(context);
    final ink = GraphicInk(
      line: series,
      accent: series,
      tone: GraphicsPalette.faint(context),
    );
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel ?? '趋势折线',
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _TrendLinePainter(
              ink: ink,
              stroke: GraphicsPalette.strokeOf(height),
              points: points,
              showArea: showArea,
              showEndDot: showEndDot,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendLinePainter extends GraphicPainter {
  _TrendLinePainter({
    required super.ink,
    required super.stroke,
    required this.points,
    required this.showArea,
    required this.showEndDot,
  });

  final List<double> points;
  final bool showArea;
  final bool showEndDot;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n < 2) return;
    var minValue = points.first;
    var maxValue = points.first;
    for (final v in points) {
      if (v < minValue) minValue = v;
      if (v > maxValue) maxValue = v;
    }
    final range = maxValue - minValue;

    final padX = stroke * 1.6;
    final padY = stroke * 1.6;
    final w = size.width - padX * 2;
    final h = size.height - padY * 2;
    final coords = <Offset>[];
    for (var i = 0; i < n; i++) {
      final x = padX + w * i / (n - 1);
      // 数据全相等时画中线,而不是除零后全挤在顶上
      final y = range <= 0
          ? padY + h / 2
          : padY + h * (1 - (points[i] - minValue) / range);
      coords.add(Offset(x, y));
    }

    if (showArea) {
      final area = Path()..moveTo(coords.first.dx, size.height - padY);
      for (final p in coords) {
        area.lineTo(p.dx, p.dy);
      }
      area
        ..lineTo(coords.last.dx, size.height - padY)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              ink.accent.withAlpha(70),
              ink.accent.withAlpha(0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    drawPolyline(canvas, coords, strokePaint(ink.accent, width: stroke * 1.05));

    if (showEndDot) {
      final end = coords.last;
      // 末端点:外圈淡、内圈实(焦点感,不用阴影)
      canvas.drawCircle(end, stroke * 2.4, fillPaint(ink.accent.withAlpha(40)));
      canvas.drawCircle(end, stroke * 1.05, fillPaint(ink.accent));
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter old) {
    return super.shouldRepaint(old) ||
        old.showArea != showArea ||
        old.showEndDot != showEndDot ||
        !_sameDoubles(old.points, points);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 3) 学习热力图
// ═══════════════════════════════════════════════════════════════════════

/// 学习打卡热力图:`weeks × 7` 方格,4 档强度。
///
/// 强度用**同一个数据色的 alpha 四档**(70/120/180/255),而不是四个色相 ——
/// 热力图的信息量是"密度",多色相会让人去找"颜色含义",反而慢。
class HeatmapCalendar extends StatelessWidget {
  const HeatmapCalendar({
    super.key,
    required this.levels,
    this.weeks = 12,
    this.cell = 12,
    this.gap = 3,
    this.color,
    this.semanticLabel,
  });

  /// 每格强度:0 = 空,1~4 = 由浅到深。长度不足 [weeks]×7 的补 0,
  /// 超出部分忽略(宁可少画,不能崩)
  final List<int> levels;

  final int weeks;

  /// 单格边长
  final double cell;

  /// 格间距
  final double gap;

  final Color? color;
  final String? semanticLabel;

  /// 把"打卡次数"映射成 0~4 档(阈值按同类 App 的常见量级:
  /// 0 次空、1~4 次最低档、5~14、15~29、≥30)
  static List<int> tiersOf(List<int> counts) {
    return counts
        .map((c) {
          if (c <= 0) return 0;
          if (c < 5) return 1;
          if (c < 15) return 2;
          if (c < 30) return 3;
          return 4;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final series = color ?? AppTheme.chartSeries(context);
    final ink = GraphicInk(
      line: series,
      accent: series,
      tone: GraphicsPalette.faint(context),
    );
    final w = weeks * cell + (weeks - 1) * gap;
    final h = 7 * cell + 6 * gap;
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel ?? '打卡热力图(最近 $weeks 周)',
      child: SizedBox(
        width: w,
        height: h,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _HeatmapPainter(
              ink: ink,
              stroke: GraphicsPalette.strokeOf(cell),
              levels: levels,
              weeks: weeks,
              cell: cell,
              gap: gap,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeatmapPainter extends GraphicPainter {
  _HeatmapPainter({
    required super.ink,
    required super.stroke,
    required this.levels,
    required this.weeks,
    required this.cell,
    required this.gap,
  });

  final List<int> levels;
  final int weeks;
  final double cell;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(cell * 0.24);
    // 空档用主题 faint 的极低 alpha:深浅两套主题下都只是"淡淡的格"
    final empty = fillPaint(ink.tone.withAlpha(46));
    final filled = <Paint>[
      fillPaint(ink.accent.withAlpha(70)),
      fillPaint(ink.accent.withAlpha(120)),
      fillPaint(ink.accent.withAlpha(180)),
      fillPaint(ink.accent),
    ];
    for (var week = 0; week < weeks; week++) {
      for (var day = 0; day < 7; day++) {
        final index = week * 7 + day;
        final level = index < levels.length ? levels[index].clamp(0, 4) : 0;
        final x = week * (cell + gap);
        final y = day * (cell + gap);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, cell, cell),
            radius,
          ),
          level == 0 ? empty : filled[level - 1],
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) {
    return super.shouldRepaint(old) ||
        old.weeks != weeks ||
        old.cell != cell ||
        old.gap != gap ||
        !_sameInts(old.levels, levels);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 4) 环形仪表
// ═══════════════════════════════════════════════════════════════════════

/// 环形进度(可带中心分数)。
///
/// 和 Material 自带的圆形进度指示器不同:那个是"加载中"的语义(本项目明确
/// 禁止用它当装饰),这个是**完成度可视化** —— 有轨道、有刻度、有中心数字,
/// 而且是静态自绘,不占一个动画 ticker。
class RadialGauge extends StatelessWidget {
  const RadialGauge({
    super.key,
    required this.value,
    this.size = 120,
    this.centerText,
    this.caption,
    this.color,
    this.tickCount = 48,
    this.semanticLabel,
  });

  /// 0~1(超界自动夹到 [0,1])
  final double value;

  final double size;

  /// 中心主文字(如分数「82」)。为空则不画文字
  final String? centerText;

  /// 中心主文字下面的一行小字(如「综合得分」)
  final String? caption;

  final Color? color;

  /// 外圈刻度数量(0 = 不画)
  final int tickCount;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = color ?? AppTheme.chartSeries(context);
    final ink = GraphicInk(
      line: GraphicsPalette.line(context),
      accent: series,
      tone: GraphicsPalette.faint(context),
    );
    final label = semanticLabel ??
        (centerText == null ? '环形进度' : '环形进度 $centerText');
    // 中心文字的样式**从主题的 textTheme 派生**(而不是 new 一个无 family 的
    // TextStyle):painter 里用 TextPainter 画字,拿不到 Theme,不继承主题字体
    // 就会退到平台默认字体 —— 中文会渲染成方块(预览图里会一眼看出来)。
    final textTheme = theme.textTheme;
    final mainStyle = (textTheme.titleLarge ?? const TextStyle()).copyWith(
      fontSize: size * 0.235,
      fontWeight: FontWeight.w800,
      height: 1.0,
      letterSpacing: -0.5,
      color: ink.line,
      // 等宽数字:否则「1」会让整个数字块视觉偏左
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    final captionStyle = (textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: size * 0.088,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
      color: ink.tone,
    );
    return GraphicFrame(
      painter: _RadialGaugePainter(
        ink: ink,
        stroke: GraphicsPalette.strokeOf(size) * 0.8,
        value: value,
        centerText: centerText,
        caption: caption,
        tickCount: tickCount,
        mainStyle: mainStyle,
        captionStyle: captionStyle,
      ),
      size: size,
      semanticLabel: label,
    );
  }
}

class _RadialGaugePainter extends GraphicPainter {
  _RadialGaugePainter({
    required super.ink,
    required super.stroke,
    required this.value,
    required this.centerText,
    required this.caption,
    required this.tickCount,
    required this.mainStyle,
    required this.captionStyle,
  });

  final double value;
  final String? centerText;
  final String? caption;
  final int tickCount;

  /// 已解析好(带字体族)的中心文字样式 —— painter 不碰 Theme
  final TextStyle mainStyle;
  final TextStyle captionStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = size.center(Offset.zero);
    final radius = s * 0.355;
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();

    // 轨道 + 进度环(主环比刻度粗、比常规描边粗,才有"仪表"的份量)
    final ringWidth = s * 0.072;
    canvas.drawCircle(
      c,
      radius,
      strokePaint(ink.tone.withAlpha(70), width: ringWidth),
    );
    if (clamped > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: radius),
        -math.pi / 2,
        math.pi * 2 * clamped,
        false,
        strokePaint(ink.accent, width: ringWidth),
      );
    }

    // 外圈刻度:细短线,已走进的部分用实色(不动画,静止也能读进度)
    if (tickCount > 0) {
      final tickOuter = radius + ringWidth * 0.92;
      for (var i = 0; i < tickCount; i++) {
        final t = i / tickCount;
        final angle = -math.pi / 2 + math.pi * 2 * t;
        final passed = t <= clamped;
        final len = s * (passed ? 0.035 : 0.024);
        canvas.drawLine(
          c + Offset.fromDirection(angle, tickOuter),
          c + Offset.fromDirection(angle, tickOuter + len),
          strokePaint(
            (passed ? ink.accent : ink.tone).withAlpha(passed ? 220 : 120),
            width: math.max(1, s * 0.010),
          ),
        );
      }
    }

    // 中心文字:用 TextPainter 而不是 Widget —— 图形必须一次 paint 画完,
    // 否则中心文字会脱离 RepaintBoundary 的缓存层
    _paintText(canvas, s, c);
  }

  void _paintText(Canvas canvas, double s, Offset center) {
    final main = centerText;
    final sub = caption;
    if (main == null && sub == null) return;
    final mainTp = (main != null && main.isNotEmpty)
        ? _textPainter(main, mainStyle)
        : null;
    final subTp = (sub != null && sub.isNotEmpty)
        ? _textPainter(sub, captionStyle)
        : null;
    final gap = s * 0.05;
    // 数字 + 小字作为**一个整体**垂直居中:分开各画一半,小字会顶到数字
    // 的下沿(预览图里能一眼看出挤)。
    var totalH = 0.0;
    if (mainTp != null) totalH += mainTp.height;
    if (subTp != null) {
      totalH += subTp.height;
      // 小字上方的间距是"上下两行"意义上的间距,所以这里只加一次
      if (mainTp != null) totalH += gap;
    }
    var top = center.dy - totalH / 2;
    if (mainTp != null) {
      mainTp.paint(canvas, Offset(center.dx - mainTp.width / 2, top));
      top += mainTp.height + gap;
    }
    if (subTp != null) {
      subTp.paint(canvas, Offset(center.dx - subTp.width / 2, top));
    }
  }

  TextPainter _textPainter(String text, TextStyle style) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  @override
  bool shouldRepaint(covariant _RadialGaugePainter old) {
    return super.shouldRepaint(old) ||
        old.value != value ||
        old.centerText != centerText ||
        old.caption != caption ||
        old.tickCount != tickCount ||
        old.mainStyle != mainStyle ||
        old.captionStyle != captionStyle;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 5) 输出四阶(单词 → 句子 → 段落 → 作文)
// ═══════════════════════════════════════════════════════════════════════

/// 输出四阶图形:用"排版体量"表达递进,而不是四个不同图标。
///
/// 单词 = 一个短块;句子 = 三个块 + 句号;段落 = 一个带框的行块;
/// 作文 = 叠起来的两页。四张图放一起,不需要文字也能看出"段位在涨"。
class OutputTierGraphic extends StatelessWidget {
  const OutputTierGraphic({
    super.key,
    required this.tier,
    this.size = 96,
    this.showPanel = false,
    this.semanticLabel,
  });

  final OutputTierArt tier;

  /// 建议取自 [GraphicsPalette.sizes]
  final double size;

  /// 是否铺面板(与 [DomainGraphic] 保持一致)
  final bool showPanel;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final ink = GraphicInk(
      line: GraphicsPalette.line(context),
      accent: accent,
      tone: GraphicsPalette.faint(context),
    );
    return GraphicFrame(
      painter: _OutputTierPainter(
        ink: ink,
        stroke: GraphicsPalette.strokeOf(size),
        tier: tier,
      ),
      size: size,
      semanticLabel: semanticLabel ?? '${tier.label}输出图形',
      panelAccent: showPanel ? accent : null,
    );
  }
}

class _OutputTierPainter extends GraphicPainter {
  _OutputTierPainter({
    required super.ink,
    required super.stroke,
    required this.tier,
  });

  final OutputTierArt tier;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final fill = fillPaint(ink.accent);
    final fillSoft = fillPaint(ink.accent.withAlpha(130));

    switch (tier) {
      case OutputTierArt.word:
        // 一个圆角短块 + 句点:最小写作单位
        _bar(canvas, s, 0.30, 0.50, 0.40, 0.115, fill);
        canvas.drawCircle(Offset(s * 0.76, s * 0.50), s * 0.038, fill);
      case OutputTierArt.sentence:
        // 三个块(词)+ 句号:一排词连成句
        _bar(canvas, s, 0.18, 0.50, 0.20, 0.10, fillSoft);
        _bar(canvas, s, 0.42, 0.50, 0.16, 0.10, fillSoft);
        _bar(canvas, s, 0.62, 0.50, 0.14, 0.10, fill);
        canvas.drawCircle(Offset(s * 0.84, s * 0.50), s * 0.034, fill);
      case OutputTierArt.paragraph:
        // 带框的多行:一段话的"面"
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(s * 0.17, s * 0.20, s * 0.83, s * 0.80),
            Radius.circular(s * 0.05),
          ),
          strokePaint(ink.tone, width: stroke * 0.85),
        );
        for (var i = 0; i < 4; i++) {
          final y = s * (0.34 + 0.11 * i);
          final end = s * (i == 3 ? 0.58 : 0.70);
          _bar(canvas, s, 0.27, (y / s), (end - s * 0.27) / s, 0.052,
              i == 0 ? fill : fillSoft);
        }
      case OutputTierArt.essay:
        // 叠起来的整页:作文 = 多页/整篇
        for (var i = 1; i >= 0; i--) {
          final off = s * 0.055 * i;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(s * 0.20 + off, s * 0.20 - off, s * 0.74 + off,
                  s * 0.82 - off),
              Radius.circular(s * 0.045),
            ),
            i == 1
                ? strokePaint(ink.tone.withAlpha(170), width: stroke * 0.8)
                : strokePaint(ink.accent, width: stroke * 0.95),
          );
        }
        // 第一页上的标题条 + 两行正文
        _bar(canvas, s, 0.29, 0.36, 0.30, 0.062, fill);
        _bar(canvas, s, 0.29, 0.49, 0.26, 0.042, fillSoft);
        _bar(canvas, s, 0.29, 0.57, 0.22, 0.042, fillSoft);
        _bar(canvas, s, 0.29, 0.65, 0.24, 0.042, fillSoft);
    }
  }

  /// 画一条"文字块":左/上/宽/高都是 s 的比例,圆角固定按高度算
  void _bar(
    Canvas canvas,
    double s,
    double leftRatio,
    double centerYRatio,
    double widthRatio,
    double heightRatio,
    Paint paint,
  ) {
    final h = s * heightRatio;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          s * leftRatio,
          s * centerYRatio - h / 2,
          s * widthRatio,
          h,
        ),
        Radius.circular(h / 2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _OutputTierPainter old) {
    return super.shouldRepaint(old) || old.tier != tier;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 内部工具
// ═══════════════════════════════════════════════════════════════════════

/// 逐元素比较数值数组(避免 import foundation 的 listEquals;
/// 数据量只有个位数,不值得一提的性能问题)
bool _sameDoubles(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
