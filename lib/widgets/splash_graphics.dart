import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 开屏视觉件(v2.29.0,2026-11-07)。
///
/// 用户原话:「现在素白背景,我想改成你软件内置那个琉璃玻璃,然后 logo 和开屏动画
/// 想想有没有更好的方案」。方案 A「琉璃凝结」:一块 132 的琉璃从磨砂凝到澄澈,
/// 「引号(language)」与「星芒(AI)」两条元素相向滑入、相撞、合成一个标。
///
/// 设计规格与关键帧见 `docs/SPLASH-LOGO-OPTIONS-2026-11-07.md`(数值一一对应);
/// 这里**不读 V4Skin**:开屏要的是"琉璃",而 V4Skin 是果冻屏的令牌,两者混用会让
/// 阅读器/材料中心的配色语义被开屏带偏。颜色收在 [SplashColors] 一处。
///
/// 全部纯 Canvas 绘制:**无图片、无视频、无新依赖**;「引号·星」的 Path 还供
/// `test/gen_icons_test.dart` 生成桌面图标,保证开屏与 launcher 是同一个字形。
class SplashColors {
  SplashColors._();

  // 文字
  static const Color ink = Color(0xFF1E2233);
  static const Color darkInk = Color(0xFFF5F6FF);

  // 品牌
  static const Color brand = Color(0xFF5B6CFF);
  static const Color brandAlt = Color(0xFFC86BFF);

  /// 标的白投影:rgba(50,60,150,.25)
  static const Color markShadow = Color(0x40213896);

  // 浅色背景(160° 三段)
  static const Color bg0 = Color(0xFFF2F5FF);
  static const Color bg1 = Color(0xFFEDEBFF);
  static const Color bg2 = Color(0xFFFDF7F4);

  // 深色背景
  static const Color dark0 = Color(0xFF0E1220);
  static const Color dark1 = Color(0xFF141A2E);

  // 柔光斑
  static const Color blobA = Color(0xFF7C9BFF);
  static const Color blobB = Color(0xFFC7B6FF);
  static const Color blobC = Color(0xFFFFD9E8);

  // 琉璃填充
  static const Color glassBottom = Color(0xFFDDE3FF);
  static const Color glassBottomDark = Color(0xFF8FA0FF);
}

// ── 时间/数值工具(t 是"已播放秒数",与预览渲染逐行一致)────────────────────

double _seg(double t, double start, double end) {
  if (end <= start) return t >= end ? 1 : 0;
  return ((t - start) / (end - start)).clamp(0.0, 1.0);
}

double _ease(double x) => Curves.easeOutCubic.transform(x);

double _lerp(double a, double b, double x) => a + (b - a) * x;

// ── 图形基元(纯 Path,任何平台不掉字形)────────────────────────────────

/// 一枚「逗号」形引号:圆头 + 左下勾尾。
void _drawComma(Canvas canvas, Offset c, double r, Color color) {
  final paint = Paint()..color = color;
  canvas.drawCircle(c, r, paint);
  final tail = Path()
    ..moveTo(c.dx - r * 0.98, c.dy + r * 0.05)
    ..cubicTo(c.dx - r * 0.95, c.dy + r * 1.05, c.dx - r * 0.62,
        c.dy + r * 1.95, c.dx + r * 0.10, c.dy + r * 1.80)
    ..cubicTo(c.dx - r * 0.50, c.dy + r * 1.15, c.dx - r * 0.32,
        c.dy + r * 0.55, c.dx - r * 0.98, c.dy + r * 0.05)
    ..close();
  canvas.drawPath(tail, paint);
}

/// 四角星芒(AI 的通用符号 ✨):外径 R,内凹 0.30R。
Path _starPath(Offset c, double R) {
  final r = R * 0.30;
  final path = Path();
  for (var i = 0; i < 4; i++) {
    final a0 = -math.pi / 2 + i * (math.pi / 2);
    final a1 = a0 + math.pi / 4;
    final po = Offset(c.dx + math.cos(a0) * R, c.dy + math.sin(a0) * R);
    final pi = Offset(c.dx + math.cos(a1) * r, c.dy + math.sin(a1) * r);
    if (i == 0) {
      path.moveTo(po.dx, po.dy);
    } else {
      path.lineTo(po.dx, po.dy);
    }
    path.lineTo(pi.dx, pi.dy);
  }
  path.close();
  return path;
}

/// 把「引号 · 星」品牌标画进任意 Canvas。
///
/// 抽成公开函数是为了**开屏与桌面图标共用同一份字形**(launcher 由
/// `test/gen_icons_test.dart` 用它画 PNG);比例按 96pt 设计稿归一化:
/// 引号圆心 (0.255, 0.600)/(0.500, 0.600) r=0.120,星芒 (0.655, 0.340) R=0.205。
void paintSplashMark(Canvas canvas, Size size, Color color) {
  final s = size.width;
  _drawComma(canvas, Offset(s * 0.255, s * 0.600), s * 0.120, color);
  _drawComma(canvas, Offset(s * 0.500, s * 0.600), s * 0.120, color);
  canvas.drawPath(
    _starPath(Offset(s * 0.655, s * 0.340), s * 0.205),
    Paint()..color = color,
  );
}

/// 品牌标(白 + 可选投影)。开屏里带投影,图标里不带。
class SplashMark extends StatelessWidget {
  /// 标的边长(设计稿基准 96,开屏用 84)
  final double size;

  /// 是否带 `rgba(50,60,150,.25) blur 6` 投影
  final bool shadow;

  final Color color;

  const SplashMark({
    super.key,
    required this.size,
    this.shadow = true,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size(size, size),
      painter: _MarkPainter(color: color),
    );
    if (!shadow) return mark;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Transform.translate(
              offset: const Offset(0, 3),
              child: Center(
                child: CustomPaint(
                  size: Size(size, size),
                  painter: const _MarkPainter(color: SplashColors.markShadow),
                ),
              ),
            ),
          ),
        ),
        mark,
      ],
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color color;
  const _MarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) => paintSplashMark(canvas, size, color);

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.color != color;
}

/// 语言层:一对引号(不含星)。开屏里从左侧滑入的那一层。
class _QuotePair extends StatelessWidget {
  final double size;
  const _QuotePair({required this.size});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: const _QuotePairPainter(),
      );
}

class _QuotePairPainter extends CustomPainter {
  const _QuotePairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    _drawComma(canvas, Offset(s * 0.34, s * 0.42), s * 0.160, Colors.white);
    _drawComma(canvas, Offset(s * 0.72, s * 0.42), s * 0.160, Colors.white);
  }

  @override
  bool shouldRepaint(covariant _QuotePairPainter old) => false;
}

/// AI 层:星芒 + 三颗节点。开屏里从右侧滑入的那一层。
class _StarBurst extends StatelessWidget {
  final double size;
  const _StarBurst({required this.size});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: const _StarBurstPainter(),
      );
}

class _StarBurstPainter extends CustomPainter {
  const _StarBurstPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s * 0.50, s * 0.50);
    canvas.drawPath(_starPath(c, s * 0.31), Paint()..color = Colors.white);
    for (var i = 0; i < 3; i++) {
      final a = -math.pi / 2 + i * (2 * math.pi / 3) + 0.45;
      final p = Offset(
          c.dx + math.cos(a) * s * 0.42, c.dy + math.sin(a) * s * 0.42);
      canvas.drawCircle(p, s * 0.052,
          Paint()..color = Colors.white.withValues(alpha: 0.30));
      canvas.drawCircle(p, s * 0.036, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _StarBurstPainter old) => false;
}

// ── 背景:160° 渐变 + 三团柔光斑 + 3% 噪点 ───────────────────────────────

class _NoisePainter extends CustomPainter {
  const _NoisePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final p = Paint();
    for (var i = 0; i < 2400; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      p.color =
          (rnd.nextBool() ? Colors.white : Colors.black).withValues(alpha: 0.018);
      canvas.drawCircle(Offset(x, y), 0.4 + rnd.nextDouble() * 1.2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter old) => false;
}

/// 开屏背景。
///
/// [aura] 是背景层入场(0→1),只改透明度、不重画;
/// [plain] 给低端机的降级:去掉 `ImageFiltered(blur 64)`,只叠径向渐变
/// (视觉几乎一致,但省掉一层大半径模糊)。
class SplashBackdrop extends StatelessWidget {
  final bool dark;
  final double aura;
  final bool plain;

  const SplashBackdrop({
    super.key,
    required this.dark,
    required this.aura,
    this.plain = false,
  });

  Widget _blob(double size, Color inner) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[inner, inner.withValues(alpha: 0.0)],
            stops: const <double>[0.0, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _blobs() {
    final a = dark ? SplashColors.brand : SplashColors.blobA;
    final b = dark ? SplashColors.brandAlt : SplashColors.blobB;
    final c = dark ? const Color(0xFF6B3A5A) : SplashColors.blobC;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned(
          left: -110,
          top: -90,
          child: _blob(430, a.withValues(alpha: dark ? 0.30 : 0.22)),
        ),
        Positioned(
          right: -150,
          top: 260,
          child: _blob(460, b.withValues(alpha: dark ? 0.24 : 0.18)),
        ),
        Positioned(
          left: -30,
          bottom: -120,
          child: _blob(400, c.withValues(alpha: dark ? 0.18 : 0.16)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final blobs = _blobs();
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-0.42, -1),
                end: const Alignment(0.42, 1),
                colors: dark
                    ? const <Color>[
                        SplashColors.dark0,
                        SplashColors.dark1,
                        SplashColors.dark1,
                      ]
                    : const <Color>[
                        SplashColors.bg0,
                        SplashColors.bg1,
                        SplashColors.bg2,
                      ],
                stops: const <double>[0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: aura,
            child: plain
                ? blobs
                : ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                        sigmaX: 64, sigmaY: 64, tileMode: TileMode.decal),
                    child: blobs,
                  ),
          ),
        ),
        const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _NoisePainter()))),
      ],
    );
  }
}

// ── 琉璃块:132×132,圆角 40 ───────────────────────────────────────────

/// 琉璃块。填充 `#FFFFFF@0.55 → #DDE3FF@0.35`(深色 `#FFFFFF@0.08 → #8FA0FF@0.16`)、
/// 1.5px 白色内高光边、外阴影 `0 24 60 rgba(96,110,255,.22)`、顶部内高光、
/// 120° 斜扫高光带;内部用 [BackdropFilter] 把背后的极光磨砂掉。
///
/// [blurSigma] 16→4 就是"磨砂→澄澈"那一段;整块面积只有 132²,性能可控。
class SplashGlassBlock extends StatelessWidget {
  final bool dark;
  final double blurSigma;
  final double shine;
  final Widget child;

  const SplashGlassBlock({
    super.key,
    required this.dark,
    required this.blurSigma,
    required this.shine,
    required this.child,
  });

  static const double _size = 132;
  static const double _radius = 40;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: SplashColors.brand.withValues(alpha: dark ? 0.30 : 0.22),
              blurRadius: 60,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: Stack(
              children: <Widget>[
                // 填充渐变
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.white.withValues(alpha: dark ? 0.08 : 0.55),
                          (dark ? SplashColors.glassBottomDark : SplashColors.glassBottom)
                              .withValues(alpha: dark ? 0.16 : 0.35),
                        ],
                      ),
                    ),
                  ),
                ),
                // 顶部内高光
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 46,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.white.withValues(alpha: dark ? 0.16 : 0.40),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // 120° 斜扫高光带(40% 宽)
                Positioned.fill(
                  child: ClipRect(
                    child: Transform.translate(
                      offset: Offset(shine * 160, 0),
                      child: Transform.rotate(
                        angle: math.pi / 6,
                        child: SizedBox(
                          width: 54,
                          height: 260,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: <Color>[
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white
                                      .withValues(alpha: dark ? 0.14 : 0.42),
                                  Colors.white.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 1.5px 内高光边
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(1.5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_radius - 1.5),
                        border: Border.all(
                          color: Colors.white
                              .withValues(alpha: dark ? 0.35 : 0.90),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(child: Center(child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 方案 A 的整帧:纯函数 (t, dark) → 画面 ──────────────────────────────

/// 方案 A「琉璃凝结」的一帧。
///
/// **纯函数**:同一个 [t] 永远画同一帧——所以预览渲染
/// (`test/splash_preview_test.dart`)与生产动画是同一份代码,零落差。
/// 生产端只需 `AnimatedBuilder(animation: ctrl, builder: (_, __) =>
/// SplashKineticA(t: ctrl.value * 1.5, ...))`。
class SplashKineticA extends StatelessWidget {
  /// 已播放秒数(0 ~ 1.5)
  final double t;

  /// 深色主题
  final bool dark;

  /// 开屏文案(来自 SplashSettings.tagline(),用户可自定义)
  final String tagline;

  /// 低端机降级:背景不用大半径模糊
  final bool plainBackdrop;

  const SplashKineticA({
    super.key,
    required this.t,
    required this.dark,
    required this.tagline,
    this.plainBackdrop = false,
  });

  @override
  Widget build(BuildContext context) {
    // 时序(秒)与 docs §2.2 一一对应:
    // 0–0.42 背景/块入场 | 0.26–0.90 磨砂→澄澈 | 0.48–0.90 高光扫
    // 0.20–0.62 语言层(引号) | 0.28–0.74 AI 层(星芒) | 0.80–1.02 融合波
    // 0.98–1.18 合成标 | 1.00–1.32 字标 | 1.08–1.42 文案 | 0.70–1.00 跳过提示
    final aura = _ease(_seg(t, 0.00, 0.42));
    final blockIn = _ease(_seg(t, 0.00, 0.42));
    final sigma = _lerp(16, 4, _seg(t, 0.26, 0.90));
    final shine = _lerp(-0.8, 1.8, _seg(t, 0.48, 0.90));

    final quoteIn = _seg(t, 0.20, 0.62);
    final quoteX = _lerp(-62, -17, _ease(quoteIn));
    final starIn = _seg(t, 0.28, 0.74);
    final starX = _lerp(62, 17, _ease(starIn));
    final layerOut = _seg(t, 0.88, 1.02);
    final mergeT = _seg(t, 0.98, 1.18);
    final wave = _seg(t, 0.80, 1.02);
    final wordT = _seg(t, 1.00, 1.32);
    final tagT = _seg(t, 1.08, 1.42);
    final skipT = _seg(t, 0.70, 1.00) * 0.85;

    final ink = dark ? SplashColors.darkInk : SplashColors.ink;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: SplashBackdrop(
            dark: dark,
            aura: _lerp(0.6, 1.0, aura),
            plain: plainBackdrop,
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Transform.scale(
                scale: _lerp(0.92, 1.0, blockIn),
                child: Opacity(
                  opacity: blockIn,
                  child: SplashGlassBlock(
                    dark: dark,
                    blurSigma: sigma,
                    shine: shine,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        // 汇合波
                        if (wave > 0 && wave < 1)
                          SizedBox(
                            width: _lerp(30, 150, _ease(wave)),
                            height: _lerp(30, 150, _ease(wave)),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: 0.6 * (1 - wave)),
                                  width: 1.4,
                                ),
                              ),
                            ),
                          ),
                        // 语言层:引号
                        Opacity(
                          opacity: quoteIn * (1 - layerOut),
                          child: Transform.translate(
                            offset: Offset(quoteX, 4),
                            child: const _QuotePair(size: 74),
                          ),
                        ),
                        // AI 层:星芒 + 节点
                        Opacity(
                          opacity: starIn * (1 - layerOut),
                          child: Transform.translate(
                            offset: Offset(starX, -6),
                            child: Transform.scale(
                              scale: _lerp(0.74, 1.0, _ease(starIn)),
                              child: const _StarBurst(size: 68),
                            ),
                          ),
                        ),
                        // 合成标
                        Opacity(
                          opacity: mergeT,
                          child: Transform.scale(
                            scale: _lerp(0.90, 1.0, _ease(mergeT)),
                            child: const SplashMark(size: 84),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Opacity(
                opacity: wordT,
                child: Text(
                  'AI上外语',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Opacity(
                opacity: tagT,
                child: Transform.translate(
                  offset: Offset(0, _lerp(10, 0, _ease(tagT))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        letterSpacing: 3,
                        color: ink.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Opacity(
            opacity: skipT,
            child: Text(
              '轻触任意处跳过',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                letterSpacing: 1.6,
                color: ink.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
