import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import 'graphics_core.dart';
import 'graphics_palette.dart';

/// 封面的**版式比例**。
///
/// 只做两种:书架/列表里的竖版 3:4、横排卡片里的 16:9。再多一种比例,同一
/// 张封面在不同页面就会"长得不一样"(用户扫列表时靠形状认材料)。
enum CoverRatioArt {
  portrait('3:4', 3 / 4),
  landscape('16:9', 16 / 9);

  const CoverRatioArt(this.label, this.value);

  final String label;

  /// 宽 / 高
  final double value;
}

/// ═══════════════════════════════════════════════════════════════════════
/// **材料封面身份图**(v2.13 · 图形资产系统 · 批 1)。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 它画的是"这是什么类型的东西"的**背景**,标题/难度/标签由调用方叠在上面
/// (所以这里**不画任何文字**)。
///
/// 和已有的 `MaterialCover` 的关系:
/// - `MaterialCover` 是"完整封面"(渐变 + 纹理 + 标题 + 徽标 + 难度胶囊 + 真图),
///   规则很重;这个组件是它的**可复用身份图层**:任何卡片想给一块区域"贴一个
///   材料身份"都能直接用,不用把封面那套壳层搬过去;
/// - 配色沿用同一套深邃低饱和色(白字对比度实测:亮面 5.52~9.63:1、
///   暗面 9.52~14.82:1),深色主题下再整体压暗一档 —— 深背景上发光的色块最廉价。
///
/// 三条自我约束:
/// 1. 纹理只用**白色极低透明度**(16~30/255):压在深底上,深浅两套主题都成立,
///    而且永远不会抢主体文字;
/// 2. 每种类型 3~6 笔几何纹理,只画"看第二眼才发现"的量;
/// 3. **不画文字**(避免和调用方标题打架 —— 这是上一版封面的教训)。
class MaterialCoverArt extends StatelessWidget {
  const MaterialCoverArt({
    super.key,
    required this.kind,
    this.seed = '',
    this.ratio = CoverRatioArt.portrait,
    this.width,
    this.height,
    this.radius = Radii.card,
    this.semanticLabel,
  });

  final MaterialKindArt kind;

  /// 稳定种子(通常传标题)。只用来微调纹理相位,避免一屏卡片完全雷同。
  final String seed;

  /// 版式比例(宽度/高度). 只在 [width]/[height] 没同时给定时生效
  final CoverRatioArt ratio;

  /// 显式尺寸(给网格/固定位用);都为 null 时按 [ratio] 自适应父级
  final double? width;
  final double? height;

  /// 圆角(默认卡片圆角 20,与全 App 卡片一致)
  final double radius;

  /// 无障碍标签;默认「<类型>封面」
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dark = GraphicsPalette.isDark(context);
    // 深色主题再压暗一档:暗背景上"亮色块"最扎眼,压暗后反而更贵
    final face = dark
        ? Color.lerp(kind.face, const Color(0xFF0A0D12), 0.16)!
        : kind.face;
    final shade = dark
        ? Color.lerp(kind.shade, const Color(0xFF0A0D12), 0.28)!
        : kind.shade;
    final ink = GraphicInk(line: shade, accent: face, tone: shade);

    Widget art = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[face, shade],
        ),
      ),
    );
    art = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        art,
        CustomPaint(
          painter: _CoverArtPainter(
            ink: ink,
            stroke: 1,
            kind: kind,
            seed: _hashSeed(seed),
            radius: radius,
            lightTheme: !dark,
          ),
        ),
      ],
    );

    Widget content = RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: art,
      ),
    );

    final w = width;
    final h = height;
    if (w != null && h != null) {
      content = SizedBox(width: w, height: h, child: content);
    } else if (w != null) {
      content = SizedBox(width: w, child: AspectRatio(aspectRatio: ratio.value, child: content));
    } else if (h != null) {
      content = SizedBox(height: h, child: AspectRatio(aspectRatio: ratio.value, child: content));
    } else {
      content = AspectRatio(aspectRatio: ratio.value, child: content);
    }

    final label = semanticLabel ?? '${kind.label}封面';
    return Semantics(container: true, image: true, label: label, child: content);
  }
}

/// 稳定 hash(FNV-1a):同一种子永远同一张封面。
///
/// 不用 `String.hashCode`:它在不同 run 之间不保证一致,列表滚动/重启后
/// 同一篇文章的纹理相位会变,看起来像"抽奖"。
int _hashSeed(String seed) {
  final s = seed.trim();
  if (s.isEmpty) return 0;
  var h = 2166136261;
  for (final r in s.runes) {
    h ^= r;
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h;
}

/// 封面身份图层的绘制者。
///
/// 渐变底由 widget 的 [DecoratedBox] 负责(GPU 上更便宜),这里只画几何纹理
/// 和 1px 内描边 —— 所以 `paint` 里的活很轻:每种类型 3~6 笔,没有路径拼接循环。
class _CoverArtPainter extends GraphicPainter {
  _CoverArtPainter({
    required super.ink,
    required super.stroke,
    required this.kind,
    required this.seed,
    required this.radius,
    required this.lightTheme,
  });

  final MaterialKindArt kind;

  /// 纹理相位(来自标题 hash),只影响几条线的起止位置
  final int seed;

  final double radius;
  final bool lightTheme;

  /// 纹理白:18~40/255 之间三档,靠"形"而不是"亮"来做层次。
  /// 下限 18 是实测出来的:再淡在 3:4 小封面上就"看不出有纹理"了。
  static const int _paleStrong = 40;
  static const int _pale = 28;
  static const int _paleFaint = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strong = graphicFill(Colors.white.withAlpha(_paleStrong));
    final pale = graphicFill(Colors.white.withAlpha(_pale));
    final faint = graphicFill(Colors.white.withAlpha(_paleFaint));
    final strokePale = graphicStroke(Colors.white.withAlpha(_pale), math.max(1, math.min(w, h) * 0.012));
    final strokeFaint = graphicStroke(Colors.white.withAlpha(_paleFaint), math.max(1, math.min(w, h) * 0.010));

    // 相位:0~2 三档,让一排封面的纹理不完全重合
    final phase = (seed % 3) * 0.04;

    switch (kind) {
      case MaterialKindArt.article:
        _article(canvas, w, h, phase, pale, faint, strong);
      case MaterialKindArt.book:
        _book(canvas, w, h, pale, faint, strokePale, strokeFaint);
      case MaterialKindArt.paper:
        _paper(canvas, w, h, strokeFaint, pale);
      case MaterialKindArt.news:
        _news(canvas, w, h, pale, faint, strong);
      case MaterialKindArt.exam:
        _exam(canvas, w, h, strokePale, pale);
      case MaterialKindArt.audio:
        _audio(canvas, w, h, pale, faint, strokeFaint);
      case MaterialKindArt.note:
        _note(canvas, w, h, strokePale);
    }

    // 1px 内描边:封面在深色卡片上几乎同色,没有这一笔会"糊"进卡片
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.5, 0.5, w - 1, h - 1),
        Radius.circular(math.max(0, radius - 0.5)),
      ),
      graphicStroke(
        Colors.white.withAlpha(lightTheme ? 34 : 24),
        1,
      ),
    );
  }

  /// 文章:一道斜向光带 + 底部几行"文段短横线"
  void _article(Canvas canvas, double w, double h, double phase, Paint pale,
      Paint faint, Paint strong) {
    final short = math.min(w, h);
    canvas.save();
    canvas.translate(w * 0.5, h * 0.5);
    canvas.rotate(-0.62);
    final bandW = short * 0.30;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(-short * 0.30 + phase * short, 0),
        width: bandW,
        height: short * 2.2,
      ),
      pale,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(-short * 0.02 + phase * short, 0),
        width: bandW * 0.45,
        height: short * 2.2,
      ),
      faint,
    );
    canvas.restore();

    // 文段:3 行,长度递减(像段末),只在下半部分,给文字留上半区
    final left = w * 0.12;
    for (var i = 0; i < 3; i++) {
      final y = h * (0.66 + 0.075 * i + phase);
      final endX = left + w * (i == 2 ? 0.26 : 0.42);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, y, endX, y + short * 0.022),
          Radius.circular(short * 0.011),
        ),
        i == 0 ? strong : faint,
      );
    }
  }

  /// 原版书:左侧书脊竖带 + 两层层叠书页
  void _book(Canvas canvas, double w, double h, Paint pale, Paint faint,
      Paint strokePale, Paint strokeFaint) {
    final short = math.min(w, h);
    // 书脊:实心竖带(比书页亮一档)
    canvas.drawRect(
      Rect.fromLTRB(w * 0.10, 0, w * 0.18, h),
      faint,
    );
    // 两层书页:右移错位,做出"厚度"
    for (var i = 1; i >= 0; i--) {
      final offset = short * 0.045 * (i + 1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            w * 0.18 + offset,
            h * 0.16 - offset,
            w * 0.88 + offset,
            h * 0.84 - offset,
          ),
          Radius.circular(short * 0.02),
        ),
        i == 1 ? strokeFaint : strokePale,
      );
    }
    // 书名线:两条短横线
    canvas.drawRect(
      Rect.fromLTRB(w * 0.30, h * 0.34, w * 0.70, h * 0.34 + short * 0.020),
      pale,
    );
    canvas.drawRect(
      Rect.fromLTRB(w * 0.30, h * 0.43, w * 0.54, h * 0.43 + short * 0.016),
      faint,
    );
  }

  /// 论文:点阵/网格 + 一个积分号 + 等号
  void _paper(Canvas canvas, double w, double h, Paint strokeFaint, Paint pale) {
    final short = math.min(w, h);
    // 网格:3 横 3 竖(比"点阵纸"更克制,也不糊)
    for (var i = 1; i <= 3; i++) {
      final y = h * 0.12 + h * 0.76 * i / 4;
      canvas.drawLine(
        Offset(w * 0.10, y),
        Offset(w * 0.90, y),
        strokeFaint,
      );
      final x = w * 0.10 + w * 0.80 * i / 4;
      canvas.drawLine(
        Offset(x, h * 0.12),
        Offset(x, h * 0.88),
        strokeFaint,
      );
    }
    // 公式:积分号(两段弧的简化) + 等号,放在中心
    final ic = Offset(w * 0.44, h * 0.46);
    final ir = short * 0.16;
    final formula = graphicStroke(Colors.white.withAlpha(_paleStrong), short * 0.035);
    canvas.drawPath(
      Path()
        ..moveTo(ic.dx + ir * 0.30, ic.dy - ir)
        ..cubicTo(ic.dx - ir * 0.55, ic.dy - ir * 1.15, ic.dx - ir * 0.25,
            ic.dy - ir * 0.4, ic.dx - ir * 0.12, ic.dy + ir * 0.2)
        ..cubicTo(ic.dx, ic.dy + ir * 1.1, ic.dx - ir * 0.3, ic.dy + ir * 1.2,
            ic.dx - ir * 0.75, ic.dy + ir),
      formula,
    );
    canvas.drawLine(
      Offset(ic.dx + ir * 0.75, ic.dy - ir * 0.22),
      Offset(ic.dx + ir * 1.5, ic.dy - ir * 0.22),
      formula,
    );
    canvas.drawLine(
      Offset(ic.dx + ir * 0.75, ic.dy + ir * 0.22),
      Offset(ic.dx + ir * 1.5, ic.dy + ir * 0.22),
      formula,
    );
    // 底部一条"图注"短横线
    canvas.drawRect(
      Rect.fromLTRB(w * 0.24, h * 0.78, w * 0.56, h * 0.78 + short * 0.018),
      pale,
    );
  }

  /// 外刊:顶部报头粗条 + 两栏竖线 + 三条头条条
  void _news(Canvas canvas, double w, double h, Paint pale, Paint faint,
      Paint strong) {
    final short = math.min(w, h);
    // 报头
    canvas.drawRect(Rect.fromLTRB(w * 0.12, h * 0.12, w * 0.88, h * 0.12 + short * 0.055), strong);
    // 分隔线
    canvas.drawRect(Rect.fromLTRB(w * 0.12, h * 0.22, w * 0.88, h * 0.22 + short * 0.010), faint);
    // 栏间竖线
    final colX = w * 0.52;
    canvas.drawRect(Rect.fromLTRB(colX, h * 0.28, colX + short * 0.012, h * 0.86), faint);
    // 头条条:左右各两条,长短不一
    final bars = <List<double>>[
      <double>[w * 0.12, h * 0.30, w * 0.42, h * 0.30 + short * 0.032],
      <double>[w * 0.56, h * 0.30, w * 0.88, h * 0.30 + short * 0.032],
      <double>[w * 0.12, h * 0.42, w * 0.38, h * 0.42 + short * 0.022],
      <double>[w * 0.56, h * 0.42, w * 0.80, h * 0.42 + short * 0.022],
    ];
    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      canvas.drawRect(
        Rect.fromLTRB(b[0], b[1], b[2], b[3]),
        i.isEven ? pale : faint,
      );
    }
    // 正文行线
    for (var i = 0; i < 3; i++) {
      final y = h * (0.55 + 0.075 * i);
      canvas.drawRect(Rect.fromLTRB(w * 0.12, y, w * 0.46, y + short * 0.011), faint);
      canvas.drawRect(Rect.fromLTRB(w * 0.56, y, w * 0.88, y + short * 0.011), faint);
    }
  }

  /// 考题:考卷网格 + 题号小方块 + 一个对勾
  void _exam(Canvas canvas, double w, double h, Paint strokePale, Paint pale) {
    final short = math.min(w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.14, h * 0.14, w * 0.86, h * 0.80),
        Radius.circular(short * 0.03),
      ),
      strokePale,
    );
    for (var i = 0; i < 3; i++) {
      final y = h * (0.30 + 0.14 * i);
      // 题号方块
      canvas.drawRect(
        Rect.fromLTRB(w * 0.21, y - short * 0.030, w * 0.29, y + short * 0.030),
        pale,
      );
      // 作答横线
      canvas.drawRect(
        Rect.fromLTRB(w * 0.36, y - short * 0.010, w * 0.72, y + short * 0.010),
        pale,
      );
    }
    // 对勾:右下(和考卷域图形同一套语言)
    drawCheck(
      canvas,
      Rect.fromLTRB(w * 0.60, h * 0.66, w * 0.86, h * 0.84),
      graphicStroke(Colors.white.withAlpha(_paleStrong + 8), short * 0.05),
    );
  }

  /// 听力:对称声波柱 + 一段圆环
  void _audio(Canvas canvas, double w, double h, Paint pale, Paint faint,
      Paint strokeFaint) {
    final short = math.min(w, h);
    final cy = h * 0.46;
    final step = w * 0.085;
    final startX = w * 0.5 - step * 3;
    const heights = <double>[0.12, 0.20, 0.30, 0.40, 0.30, 0.20, 0.12];
    for (var i = 0; i < heights.length; i++) {
      final hh = short * heights[i];
      final x = startX + step * i;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - short * 0.018, cy - hh / 2, x + short * 0.018, cy + hh / 2),
          Radius.circular(short * 0.018),
        ),
        i == 3 ? pale : faint,
      );
    }
    // 圆环:压在声波下方,暗示"录音/播放"
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * 0.5, h * 0.72), radius: short * 0.22),
      math.pi * 1.08,
      math.pi * 0.84,
      false,
      strokeFaint,
    );
    // 播放三角:底弧正中,朝右(与领域图形 audio 同一套符号)
    final triY = h * 0.83;
    final tri = Path()
      ..moveTo(w * 0.47, triY - short * 0.055)
      ..lineTo(w * 0.47, triY + short * 0.055)
      ..lineTo(w * 0.56, triY)
      ..close();
    canvas.drawPath(tri, pale);
  }

  /// 笔记:便签 + 折角 + 三条手写线
  void _note(Canvas canvas, double w, double h, Paint strokePale) {
    final short = math.min(w, h);
    final fold = short * 0.16;
    final path = Path()
      ..moveTo(w * 0.16, h * 0.16)
      ..lineTo(w * 0.84 - fold, h * 0.16)
      ..lineTo(w * 0.84, h * 0.16 + fold)
      ..lineTo(w * 0.84, h * 0.84)
      ..lineTo(w * 0.16, h * 0.84)
      ..close();
    canvas.drawPath(path, strokePale);
    // 折角:三角形实心(深色下唯一读得懂的折角表达),用最亮一档白强调
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.84 - fold, h * 0.16)
        ..lineTo(w * 0.84 - fold, h * 0.16 + fold)
        ..lineTo(w * 0.84, h * 0.16 + fold)
        ..close(),
      graphicFill(Colors.white.withAlpha(_paleStrong)),
    );
    // 三条手写线(轻微起伏,不是表格线)
    for (var i = 0; i < 3; i++) {
      final y = h * (0.42 + 0.13 * i);
      final x0 = w * 0.26;
      final x1 = w * (i == 2 ? 0.60 : 0.74);
      canvas.drawPath(
        Path()
          ..moveTo(x0, y)
          ..quadraticBezierTo((x0 + x1) / 2, y - short * 0.03, x1, y),
        graphicStroke(Colors.white.withAlpha(i == 2 ? _paleFaint : _pale),
            math.max(1, short * 0.014)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CoverArtPainter old) {
    return super.shouldRepaint(old) ||
        old.kind != kind ||
        old.seed != seed ||
        old.radius != radius ||
        old.lightTheme != lightTheme;
  }
}
