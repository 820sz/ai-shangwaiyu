// 开屏动画 + logo · 3 个方案的关键帧真实渲染(2026-11-07 · 第 3 版 / 美术规格版)
//
// 用户第 2 轮意见:文字方块已修,但视觉像初稿 —— 琉璃与背景同色、logo 对比弱、B 配色不统一。
// 本版按 Lead 给的美术规格重画:
//   · 背景:160° 三段渐变 #F2F5FF→#EDEBFF→#FDF7F4 + 三团柔光斑 + 3% 细噪点
//   · 琉璃:132×132 r40,#FFFFFF@0.55→#DDE3FF@0.35,1.5px 白内高光边,外阴影 0 24 60 rgba(96,110,255,.22)
//   · Logo:白色 + rgba(50,60,150,.25) blur6 投影;B 环 #5B6CFF→#C86BFF 3px,节点 9/13/9
//   · 字标 32px w800 ls2 #1E2233 / 副标 15px ls3 @0.55 / 跳过 12px @0.35
//   · 深色:底 #0E1220→#141A2E,琉璃 #FFFFFF@0.08→#8FA0FF@0.16,文字 #F5F6FF
//
// A 琉璃凝结(双元素汇合) / B 双轨闭环 / C 对话体。
// 每个方案是 `(t 秒, dark) -> 画面` 的纯函数,便于精确出帧;落地换 AnimationController 即可。
//
// 出图 16 张(390×844@3 → 1170×2532),同时写 build/ui_real/ 与 docs/ui-preview/real/:
//   splash-a-f1..f4 + splash-a-dark
//   splash-b-f1..f4 + splash-b-dark
//   splash-c-f1..f4 + splash-c-dark
//   splash-logo-sheet(3 概念 × 96/48/24 × 浅/深底)

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 实现后的对照帧:直接渲染线上组件 lib/widgets/splash_graphics.dart
import 'package:readflow/widgets/splash_graphics.dart';

const String _cjk = 'PreviewCJK';

// ── 美术规格常量 ─────────────────────────────────────────────────
class _S {
  _S._();
  // 字色 / 文字
  static const Color ink = Color(0xFF1E2233);
  static const Color darkInk = Color(0xFFF5F6FF);
  static const String tagline = '让语言,回归本质';
  static const String skip = '轻触任意处跳过';
  static const String wordmark = 'AI上外语';

  // 品牌色
  static const Color brandA = Color(0xFF5B6CFF);
  static const Color brandB = Color(0xFFC86BFF);
  static const Color markShadow = Color(0x40213896); // rgba(50,60,150,.25)

  // 背景
  static const Color bg0 = Color(0xFFF2F5FF);
  static const Color bg1 = Color(0xFFEDEBFF);
  static const Color bg2 = Color(0xFFFDF7F4);
  static const Color blobA = Color(0xFF7C9BFF);
  static const Color blobB = Color(0xFFC7B6FF);
  static const Color blobC = Color(0xFFFFD9E8);

  // 深色底
  static const Color dark0 = Color(0xFF0E1220);
  static const Color dark1 = Color(0xFF141A2E);

  // 琉璃
  static const Color glassTop = Color(0xFFFFFFFF);
  static const Color glassBottom = Color(0xFFDDE3FF);
  static const Color glassTopDark = Color(0xFFFFFFFF);
  static const Color glassBottomDark = Color(0xFF8FA0FF);
}

/// 中文字体:必须真的加载进来,否则 flutter_test 的默认字体把所有字画成方块(还带黄下划线)。
/// 本机字体路径不可靠,所以先试一批常见路径、再扫字体目录,每个候选 try/catch。
Future<String?> _loadFont() async {
  final candidates = <String>[];
  for (final p in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\NotoSansSC-VF.otf',
    r'C:\Windows\Fonts\NotoSansCJKsc-Regular.otf',
    r'C:\Windows\Fonts\SourceHanSansSC-Regular.otf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\msyh.ttc',
    r'C:\Windows\Fonts\msyhbd.ttc',
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\simsun.ttc',
  ]) {
    if (File(p).existsSync()) candidates.add(p);
  }
  try {
    final dir = Directory(r'C:\Windows\Fonts');
    if (dir.existsSync()) {
      final extra = <String>[];
      for (final e in dir.listSync(followLinks: false)) {
        final n = e.path.toLowerCase();
        if (!(n.endsWith('.ttf') || n.endsWith('.otf'))) continue;
        if (n.contains('noto') || n.contains('source') || n.contains('han')) {
          extra.add(e.path);
        }
      }
      extra.sort();
      candidates.addAll(extra);
    }
  } catch (_) {}

  for (final path in candidates) {
    try {
      final b1 = Future<ByteData>.value(
          ByteData.sublistView(File(path).readAsBytesSync()));
      await (FontLoader('Roboto')..addFont(b1)).load();
      final b2 = Future<ByteData>.value(
          ByteData.sublistView(File(path).readAsBytesSync()));
      await (FontLoader(_cjk)..addFont(b2)).load();
      Directory('build/ui_real').createSync(recursive: true);
      File('build/ui_real/_font_used.txt').writeAsStringSync(path);
      debugPrint('[font] loaded: $path');
      return path;
    } catch (e) {
      debugPrint('[font] skip $path: $e');
    }
  }
  Directory('build/ui_real').createSync(recursive: true);
  File('build/ui_real/_font_used.txt').writeAsStringSync('NONE');
  debugPrint('[font] NONE loaded -> 文本会变成方块');
  return null;
}

Future<void> _loadIcons() async {
  for (final path in <String>[
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()))))
        .load();
    return;
  }
}

ThemeData _theme({required bool dark}) => ThemeData(
      useMaterial3: true,
      fontFamily: _cjk,
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: _S.bg0,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _S.brandA,
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
    );

Future<void> _capture(
    WidgetTester tester, GlobalKey key, String fileName) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final data = bytes!.buffer.asUint8List();
    for (final dir in <String>['build/ui_real', 'docs/ui-preview/real']) {
      Directory(dir).createSync(recursive: true);
      File('$dir/$fileName').writeAsBytesSync(data);
    }
    image.dispose();
  });
}

// ═══════════════════════════════════════════════════════════════════
// 时间工具
// ═══════════════════════════════════════════════════════════════════
double _seg(double t, double start, double end) {
  if (end <= start) return t >= end ? 1 : 0;
  return ((t - start) / (end - start)).clamp(0.0, 1.0);
}

double _ease(double x) => Curves.easeOutCubic.transform(x);
double _lerp(double a, double b, double x) => a + (b - a) * x;

// ═══════════════════════════════════════════════════════════════════
// 背景:160° 渐变 + 三团柔光斑 + 3% 细噪点
// ═══════════════════════════════════════════════════════════════════
class _NoisePainter extends CustomPainter {
  final int seed;
  final double alpha;
  const _NoisePainter({this.seed = 7, this.alpha = 0.03});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final p = Paint();
    for (var i = 0; i < 2400; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      p.color = (rnd.nextBool() ? Colors.white : Colors.black)
          .withValues(alpha: alpha);
      canvas.drawCircle(
          Offset(x, y), 0.4 + rnd.nextDouble() * 1.2, p);
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter old) => false;
}

class _Backdrop extends StatelessWidget {
  final bool dark;
  final double aura; // 0..1 背景层入场
  const _Backdrop({required this.dark, required this.aura});

  Widget _blob(double size, Color inner) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[inner, inner.withValues(alpha: 0.0)],
            stops: const <double>[0.0, 1.0],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-0.42, -1),
                end: const Alignment(0.42, 1),
                colors: dark
                    ? const <Color>[_S.dark0, _S.dark1, _S.dark1]
                    : const <Color>[_S.bg0, _S.bg1, _S.bg2],
                stops: const <double>[0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        Opacity(
          opacity: aura,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
                sigmaX: 64, sigmaY: 64, tileMode: TileMode.decal),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: -110,
                  top: -90,
                  child: _blob(
                      430,
                      _S.blobA.withValues(
                          alpha: dark ? 0.30 : 0.22)),
                ),
                Positioned(
                  right: -150,
                  top: 260,
                  child: _blob(
                      460,
                      _S.blobB.withValues(
                          alpha: dark ? 0.26 : 0.18)),
                ),
                Positioned(
                  left: -30,
                  bottom: -120,
                  child: _blob(
                      400,
                      _S.blobC.withValues(
                          alpha: dark ? 0.18 : 0.16)),
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _NoisePainter(seed: 7, alpha: 0.018)),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 图形基元(纯 Canvas)
// ═══════════════════════════════════════════════════════════════════

/// 一枚「逗号」形引号:圆头 + 左下勾尾(纯 Path,任何平台不掉字形)
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

/// 四角星芒(✨)
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

/// 「语言层」:一对引号(不含星)
class _QuotePair extends StatelessWidget {
  final double size;
  final Color color;
  const _QuotePair({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _QuotePairPainter(color: color),
      );
}

class _QuotePairPainter extends CustomPainter {
  final Color color;
  const _QuotePairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    _drawComma(canvas, Offset(s * 0.34, s * 0.42), s * 0.160, color);
    _drawComma(canvas, Offset(s * 0.72, s * 0.42), s * 0.160, color);
  }

  @override
  bool shouldRepaint(covariant _QuotePairPainter old) => old.color != color;
}

/// 「AI 层」:星芒 + 三颗节点
class _StarBurst extends StatelessWidget {
  final double size;
  final Color color;
  final Color nodeColor;
  const _StarBurst({
    required this.size,
    required this.color,
    required this.nodeColor,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _StarBurstPainter(color: color, nodeColor: nodeColor),
      );
}

class _StarBurstPainter extends CustomPainter {
  final Color color;
  final Color nodeColor;
  const _StarBurstPainter({required this.color, required this.nodeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s * 0.50, s * 0.50);
    canvas.drawPath(_starPath(c, s * 0.31), Paint()..color = color);
    for (var i = 0; i < 3; i++) {
      final a = -math.pi / 2 + i * (2 * math.pi / 3) + 0.45;
      final p = Offset(
          c.dx + math.cos(a) * s * 0.42, c.dy + math.sin(a) * s * 0.42);
      canvas.drawCircle(p, s * 0.052, Paint()..color = nodeColor.withValues(alpha: 0.18));
      canvas.drawCircle(p, s * 0.036, Paint()..color = nodeColor);
    }
  }

  @override
  bool shouldRepaint(covariant _StarBurstPainter old) => true;
}

/// Logo 1「引号 · 星」:引号压左下,星芒嵌在引号右上、间距收紧 → 一个整体 mark
class _MarkQuoteStar extends StatelessWidget {
  final double size;
  final Color color;
  const _MarkQuoteStar({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _MarkQuoteStarPainter(color: color),
      );
}

class _MarkQuoteStarPainter extends CustomPainter {
  final Color color;
  const _MarkQuoteStarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // 引号(language):两枚逗号,占左侧 60%
    _drawComma(canvas, Offset(s * 0.255, s * 0.600), s * 0.120, color);
    _drawComma(canvas, Offset(s * 0.500, s * 0.600), s * 0.120, color);
    // 星芒(AI):嵌在第二枚引号的右上,离得很近 → 一个整体
    canvas.drawPath(
      _starPath(Offset(s * 0.655, s * 0.340), s * 0.205),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkQuoteStarPainter old) =>
      old.color != color;
}

/// Logo 2「A · 节点」:几何 A + 横杠三节点(#5B6CFF)
class _MarkANode extends StatelessWidget {
  final double size;
  final Color color;
  final Color nodeColor;
  const _MarkANode({
    required this.size,
    required this.color,
    required this.nodeColor,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _MarkANodePainter(color: color, nodeColor: nodeColor),
      );
}

class _MarkANodePainter extends CustomPainter {
  final Color color;
  final Color nodeColor;
  const _MarkANodePainter({required this.color, required this.nodeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final p = Paint()
      ..color = color
      ..strokeWidth = s * 0.110
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(s * 0.17, s * 0.85), Offset(s * 0.50, s * 0.17), p);
    canvas.drawLine(Offset(s * 0.83, s * 0.85), Offset(s * 0.50, s * 0.17), p);
    // 横杠 = 节点链(半径 9/13/9 的比例:0.052 / 0.075 / 0.052)
    const xs = <double>[0.305, 0.50, 0.695];
    const rs = <double>[0.052, 0.075, 0.052];
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(s * xs[i], s * 0.690), s * rs[i] * 1.45,
          Paint()..color = nodeColor.withValues(alpha: 0.14));
      canvas.drawCircle(Offset(s * xs[i], s * 0.690), s * rs[i],
          Paint()..color = nodeColor);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkANodePainter old) => true;
}

/// Logo 3「气泡 · 星」:对话气泡 + 星芒
class _MarkBubbleStar extends StatelessWidget {
  final double size;
  final Color color;
  final double stroke;
  const _MarkBubbleStar({
    required this.size,
    required this.color,
    required this.stroke,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _MarkBubbleStarPainter(color: color, stroke: stroke),
      );
}

class _MarkBubbleStarPainter extends CustomPainter {
  final Color color;
  final double stroke;
  const _MarkBubbleStarPainter({required this.color, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromLTRBR(
          s * 0.07, s * 0.09, s * 0.93, s * 0.68, Radius.circular(s * 0.22)),
      paint,
    );
    final tail = Path()
      ..moveTo(s * 0.27, s * 0.64)
      ..lineTo(s * 0.19, s * 0.90)
      ..lineTo(s * 0.46, s * 0.68);
    canvas.drawPath(tail, paint);
    canvas.drawPath(
      _starPath(Offset(s * 0.615, s * 0.385), s * 0.170),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkBubbleStarPainter old) =>
      old.color != color || old.stroke != stroke;
}

/// 给 mark 加「rgba(50,60,150,.25) blur6」投影:同一形状画两遍(虚影 + 白标)
class _ShadowedMark extends StatelessWidget {
  final Widget Function(Color) builder;
  const _ShadowedMark({required this.builder});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Transform.translate(
              offset: const Offset(0, 3),
              child: Center(child: builder(_S.markShadow)),
            ),
          ),
        ),
        Center(child: builder(Colors.white)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 琉璃块(132×132 r40):A / B / C 的终标容器
// ═══════════════════════════════════════════════════════════════════
class _GlassBlock extends StatelessWidget {
  final bool dark;
  final double blurSigma;
  final double shine; // -0.6..1.8
  final Widget child;
  const _GlassBlock({
    required this.dark,
    required this.blurSigma,
    required this.shine,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    const size = 132.0;
    const radius = 40.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF606EFF).withValues(alpha: dark ? 0.30 : 0.22),
            blurRadius: 60,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Stack(
            children: <Widget>[
              // 填充渐变:上白下淡蓝
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        (_S.glassTop).withValues(alpha: dark ? 0.08 : 0.55),
                        (_S.glassBottom).withValues(alpha: dark ? 0.16 : 0.35),
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
              // 斜向 120° 白色高光带(40% 宽)
              Positioned.fill(
                child: ClipRect(
                  child: Transform.translate(
                    offset: Offset(shine * 160, 0),
                    child: Transform.rotate(
                      angle: math.pi / 6,
                      child: Container(
                        width: 54,
                        height: 260,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: <Color>[
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: dark ? 0.14 : 0.42),
                              Colors.white.withValues(alpha: 0),
                            ],
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
                      borderRadius: BorderRadius.circular(radius - 1.5),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: dark ? 0.35 : 0.90),
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 文字件(规格:字标 32/w800/ls2;副标 15/ls3;跳过 12)
// ═══════════════════════════════════════════════════════════════════
class _Wordmark extends StatelessWidget {
  final bool dark;
  final double opacity;
  const _Wordmark({required this.dark, required this.opacity});

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: opacity,
        child: Text(
          _S.wordmark,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: _cjk,
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: dark ? _S.darkInk : _S.ink,
          ),
        ),
      );
}

class _Tagline extends StatelessWidget {
  final bool dark;
  final double opacity;
  final double slide;
  const _Tagline({
    required this.dark,
    required this.opacity,
    this.slide = 0,
  });

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, slide),
          child: Text(
            _S.tagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _cjk,
              fontSize: 15,
              height: 1.5,
              letterSpacing: 3,
              color: (dark ? _S.darkInk : _S.ink).withValues(alpha: 0.55),
            ),
          ),
        ),
      );
}

class _SkipHint extends StatelessWidget {
  final bool dark;
  final double opacity;
  const _SkipHint({required this.dark, required this.opacity});

  @override
  Widget build(BuildContext context) => Positioned(
        left: 0,
        right: 0,
        bottom: 40,
        child: Opacity(
          opacity: opacity,
          child: Text(
            _S.skip,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _cjk,
              fontSize: 12,
              height: 1.2,
              letterSpacing: 1.6,
              color: (dark ? _S.darkInk : _S.ink).withValues(alpha: 0.35),
            ),
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════
// 方案 A · 琉璃凝结(双元素汇合)
//   语言层(引号)左滑入 / AI 层(星芒+节点)右滑入 → 相向 → 碰撞 → 合成「引号 · 星」
// ═══════════════════════════════════════════════════════════════════
class _SplashA extends StatelessWidget {
  final double t;
  final bool dark;
  const _SplashA({required this.t, this.dark = false});

  @override
  Widget build(BuildContext context) {
    // 0–420 背景/块入场 | 260–900 磨砂→澄澈 | 480–900 高光扫
    // 200–620 语言层 | 280–740 AI 层 | 800–1020 汇合波 | 980–1180 合体标
    // 1000–1320 字标 | 1080–1420 副标
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

    return Stack(
      children: <Widget>[
        Positioned.fill(child: _Backdrop(dark: dark, aura: _lerp(0.6, 1.0, aura))),
        Align(
          alignment: const Alignment(0, -0.14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Transform.scale(
                scale: _lerp(0.92, 1.0, blockIn),
                child: Opacity(
                  opacity: blockIn,
                  child: _GlassBlock(
                    dark: dark,
                    blurSigma: sigma,
                    shine: shine,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        // 汇合波
                        if (wave > 0 && wave < 1)
                          Container(
                            width: _lerp(30, 150, _ease(wave)),
                            height: _lerp(30, 150, _ease(wave)),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white
                                    .withValues(alpha: 0.6 * (1 - wave)),
                                width: 1.4,
                              ),
                            ),
                          ),
                        // 语言层:引号
                        Opacity(
                          opacity: quoteIn * (1 - layerOut),
                          child: Transform.translate(
                            offset: Offset(quoteX, 4),
                            child: _QuotePair(size: 74, color: Colors.white),
                          ),
                        ),
                        // AI 层:星芒 + 节点
                        Opacity(
                          opacity: starIn * (1 - layerOut),
                          child: Transform.translate(
                            offset: Offset(starX, -6),
                            child: Transform.scale(
                              scale: _lerp(0.74, 1.0, _ease(starIn)),
                              child: _StarBurst(
                                size: 68,
                                color: Colors.white,
                                nodeColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        // 合体标
                        Opacity(
                          opacity: mergeT,
                          child: Transform.scale(
                            scale: _lerp(0.90, 1.0, _ease(mergeT)),
                            child: _ShadowedMark(
                              builder: (c) =>
                                  _MarkQuoteStar(size: 84, color: c),                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              _Wordmark(dark: dark, opacity: wordT),
              const SizedBox(height: 14),
              _Tagline(
                dark: dark,
                opacity: tagT,
                slide: _lerp(10, 0, _ease(tagT)),
              ),
            ],
          ),
        ),
        _SkipHint(dark: dark, opacity: _seg(t, 0.70, 1.00) * 0.85),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 方案 B · 双轨闭环
//   外环=语言流(36 个长短笔画) / 内环=3px 双色渐变弧 + 3 节点 + 跑动光点
//   双轨同向流转 → 收进环心 → 琉璃块里的「A · 节点」
// ═══════════════════════════════════════════════════════════════════
class _DualRingPainter extends CustomPainter {
  final double progress;
  final double langSpin;
  final double aiSpin;
  final double collapse;
  final Color track;
  const _DualRingPainter({
    required this.progress,
    required this.langSpin,
    required this.aiSpin,
    required this.collapse,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final s = size.width;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(_lerp(1.0, 0.40, collapse));
    final fade = _lerp(1.0, 0.0, collapse);

    // 外环:语言流(一行长短交替的笔画,慢转)
    final langR = s * 0.450;
    final tickPaint = Paint()
      ..color = _S.brandA.withValues(alpha: 0.60 * fade)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 36; i++) {
      final a = i * (2 * math.pi / 36) + langSpin;
      final len = <double>[5.5, 9.5, 7.0, 4.5][i % 4];
      final dir = Offset(-math.sin(a), math.cos(a));
      final base = Offset(math.cos(a) * langR, math.sin(a) * langR);
      canvas.drawLine(base - dir * (len / 2), base + dir * (len / 2), tickPaint);
    }

    // 内环:3px 双色渐变弧 + 底环
    final aiR = s * 0.320;
    canvas.drawCircle(
      Offset.zero,
      aiR,
      Paint()
        ..color = _S.brandA.withValues(alpha: 0.22 * fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    if (progress > 0.002) {
      final rect = Rect.fromCircle(center: Offset.zero, radius: aiR);
      final arcPaint = Paint()
        ..shader = SweepGradient(
          colors: const <Color>[_S.brandA, _S.brandB, _S.brandA],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawArc(
          rect, -math.pi / 2, 2 * math.pi * 0.86 * progress, false, arcPaint);
    }

    // 三颗节点(半径 9/13/9 比例)+ 柔光
    const nodeR = <double>[0.034, 0.049, 0.034];
    for (var i = 0; i < 3; i++) {
      final a = aiSpin + i * (2 * math.pi / 3);
      final p = Offset(math.cos(a) * aiR, math.sin(a) * aiR);
      canvas.drawCircle(p, s * nodeR[i] * 2.2,
          Paint()..color = _S.brandA.withValues(alpha: 0.22 * fade));
      canvas.drawCircle(p, s * nodeR[i],
          Paint()..color = _S.brandA.withValues(alpha: fade));
    }
    // 跑动光点
    if (progress > 0.02) {
      final a = -math.pi / 2 + 2 * math.pi * 0.86 * progress;
      final p = Offset(math.cos(a) * aiR, math.sin(a) * aiR);
      canvas.drawCircle(p, 11,
          Paint()..color = _S.brandB.withValues(alpha: 0.30 * fade));
      canvas.drawCircle(p, 4.6, Paint()..color = _S.brandB.withValues(alpha: fade));
      canvas.drawCircle(p, 2.0, Paint()..color = Colors.white.withValues(alpha: fade));
    }
    canvas.restore();
    if (collapse > 0.10) {
      canvas.drawCircle(
        c,
        _lerp(4, 12, collapse),
        Paint()..color = track.withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DualRingPainter old) => true;
}

class _SplashB extends StatelessWidget {
  final double t;
  final bool dark;
  const _SplashB({required this.t, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final aura = _ease(_seg(t, 0.00, 0.40));
    final langT = _seg(t, 0.00, 0.50);
    final progress = _ease(_seg(t, 0.10, 0.95));
    final collapse = _ease(_seg(t, 0.95, 1.25));
    final blockT = _seg(t, 0.98, 1.22);
    final markT = _seg(t, 1.00, 1.24);
    final wordT = _seg(t, 1.05, 1.38);
    final tagT = _seg(t, 1.12, 1.44);

    return Stack(
      children: <Widget>[
        Positioned.fill(child: _Backdrop(dark: dark, aura: _lerp(0.5, 0.95, aura))),
        Align(
          alignment: const Alignment(0, -0.12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 268,
                height: 268,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Opacity(
                      opacity: langT,
                      child: CustomPaint(
                        size: const Size(268, 268),
                        painter: _DualRingPainter(
                          progress: progress,
                          // 外环慢(0.34 rad/s)、内环节点快(1.55 rad/s)
                          langSpin: t * 0.34,
                          aiSpin: t * 1.55 + 0.6,
                          collapse: collapse,
                          track: _S.brandA,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: blockT,
                      child: Transform.scale(
                        scale: _lerp(0.82, 1.0, _ease(blockT)),
                        child: _GlassBlock(
                          dark: dark,
                          blurSigma: _lerp(14, 4, blockT),
                          shine: -0.6,
                          child: Opacity(
                            opacity: markT,
                            child: _ShadowedMark(
                              builder: (c) => _MarkANode(
                                size: 84,
                                color: c,
                                nodeColor: _S.brandA,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 34),
              _Wordmark(dark: dark, opacity: wordT),
              const SizedBox(height: 14),
              _Tagline(
                dark: dark,
                opacity: tagT,
                slide: _lerp(10, 0, _ease(tagT)),
              ),
            ],
          ),
        ),
        _SkipHint(dark: dark, opacity: _seg(t, 0.70, 1.00) * 0.85),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 方案 C · 对话体
//   琉璃气泡里 language 逐字打出 → 最后一个字符被星芒顶掉 → 收成「气泡 · 星」
// ═══════════════════════════════════════════════════════════════════
class _SplashC extends StatelessWidget {
  final double t;
  final bool dark;
  const _SplashC({required this.t, this.dark = false});

  static const String _word = 'language';

  @override
  Widget build(BuildContext context) {
    final aura = _ease(_seg(t, 0.06, 0.26));
    final bubbleIn = _ease(_seg(t, 0.06, 0.26));
    final typeT = _seg(t, 0.26, 0.76);
    final typed = (typeT * _word.length).floor().clamp(0, _word.length);
    final starT = _seg(t, 0.78, 0.90);
    final shrink = _ease(_seg(t, 0.92, 1.10));
    final blockT = _seg(t, 1.00, 1.20);
    final wordT = _seg(t, 1.02, 1.34);
    final tagT = _seg(t, 1.10, 1.44);

    final shown = starT > 0
        ? _word.substring(0, _word.length - 1)
        : _word.substring(0, typed);

    final textColor = dark ? _S.darkInk : _S.ink;

    return Stack(
      children: <Widget>[
        Positioned.fill(child: _Backdrop(dark: dark, aura: _lerp(0.55, 1.0, aura))),
        Align(
          alignment: const Alignment(0, -0.12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 280,
                height: 168,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    // 尾巴(画在气泡后面)
                    if (shrink < 0.9)
                      Positioned(
                        left: 36,
                        top: 132,
                        child: Opacity(
                          opacity: (1 - shrink) * bubbleIn,
                          child: CustomPaint(
                            size: const Size(56, 38),
                            painter: _TailPainter(
                              color: Colors.white.withValues(
                                  alpha: dark ? 0.16 : 0.66),
                            ),
                          ),
                        ),
                      ),
                    // 气泡
                    Opacity(
                      opacity: bubbleIn,
                      child: Transform.scale(
                        scale: _lerp(0.92, 1.0, bubbleIn),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(_lerp(28, 24, shrink)),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Container(
                              width: _lerp(248, 132, shrink),
                              height: _lerp(116, 132, shrink),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    Colors.white
                                        .withValues(alpha: dark ? 0.10 : 0.62),
                                    (_S.glassBottom).withValues(
                                        alpha: dark ? 0.18 : 0.38),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(
                                    _lerp(28, 24, shrink)),
                                border: Border.all(
                                  color: Colors.white
                                      .withValues(alpha: dark ? 0.30 : 0.95),
                                  width: 2,
                                ),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: const Color(0xFF606EFF)
                                        .withValues(alpha: 0.22),
                                    blurRadius: 60,
                                    offset: const Offset(0, 24),
                                  ),
                                ],
                              ),
                              child: shrink >= 0.999
                                  ? const SizedBox.shrink()
                                  : _bubbleContent(
                                      shown: shown,
                                      starT: starT,
                                      shrink: shrink,
                                      textColor: textColor,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 收成标
                    Opacity(
                      opacity: _seg(t, 1.08, 1.24),
                      child: _ShadowedMark(
                        builder: (c) => _MarkBubbleStar(
                            size: 92, color: c, stroke: 3.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              _Wordmark(dark: dark, opacity: wordT),
              const SizedBox(height: 14),
              _Tagline(
                dark: dark,
                opacity: tagT,
                slide: _lerp(10, 0, _ease(tagT)),
              ),
            ],
          ),
        ),
        _SkipHint(dark: dark, opacity: _seg(t, 0.70, 1.00) * 0.85),
      ],
    );
  }

  Widget _bubbleContent({
    required String shown,
    required double starT,
    required double shrink,
    required Color textColor,
  }) {
    return Opacity(
      opacity: 1 - shrink,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  shown,
                  style: TextStyle(
                    fontFamily: _cjk,
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 5),
                if (starT > 0)
                  Transform.scale(
                    scale: _lerp(0.2, 1.0,
                        Curves.easeOutBack.transform(starT.clamp(0.0, 1.0))),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CustomPaint(
                        painter: _GlyphStarPainter(color: _S.brandA),
                      ),
                    ),
                  ),
                if (starT <= 0)
                  Container(
                    width: 2.4,
                    height: 28,
                    margin: const EdgeInsets.only(left: 3),
                    color: _S.brandA,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphStarPainter extends CustomPainter {
  final Color color;
  const _GlyphStarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawPath(
      _starPath(Offset(s / 2, s / 2), s * 0.47),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _GlyphStarPainter old) => old.color != color;
}

class _TailPainter extends CustomPainter {
  final Color color;
  const _TailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width * 0.82, 0)
      ..lineTo(size.width * 0.05, size.height * 0.97)
      ..lineTo(size.width * 0.36, 0)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TailPainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════════════
// Logo 变体图:3 概念 × 96/48/24 × 浅底/深底(单色可识别性)
// ═══════════════════════════════════════════════════════════════════
class _LogoSheet extends StatelessWidget {
  final bool dark;
  const _LogoSheet({required this.dark});

  @override
  Widget build(BuildContext context) {
    final ink = dark ? _S.darkInk : _S.ink;
    final markColor = dark ? Colors.white : _S.brandA;
    final subs = dark ? _S.darkInk.withValues(alpha: 0.50) : _S.ink.withValues(alpha: 0.45);

    Widget mark(int i, double s) {
      switch (i) {
        case 0:
          return _MarkQuoteStar(size: s, color: markColor);
        case 1:
          return _MarkANode(size: s, color: markColor, nodeColor: _S.brandA);
        default:
          return _MarkBubbleStar(size: s, color: markColor, stroke: s * 0.062);
      }
    }

    return Stack(
      children: <Widget>[
        Positioned.fill(child: _Backdrop(dark: dark, aura: 1.0)),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 44, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                dark ? 'logo 变体 · 深底' : 'logo 变体 · 浅底',
                style: TextStyle(
                  fontFamily: _cjk,
                  fontSize: 13,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              Text(
                '3 个概念 × 96 / 48 / 24 px(单色,靠形状识别)',
                style: TextStyle(
                  fontFamily: _cjk,
                  fontSize: 10,
                  letterSpacing: 0.6,
                  color: subs,
                ),
              ),
              const SizedBox(height: 26),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          Text(
                            const <String>[
                              'L1 引号·星',
                              'L2 A·节点',
                              'L3 气泡·星',
                            ][i],
                            style: TextStyle(
                              fontFamily: _cjk,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: ink.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 18),
                          mark(i, 96),
                          const SizedBox(height: 22),
                          mark(i, 48),
                          const SizedBox(height: 16),
                          mark(i, 24),
                          const SizedBox(height: 10),
                          Text(
                            '96   48   24',
                            style: TextStyle(
                              fontFamily: _cjk,
                              fontSize: 8,
                              letterSpacing: 0.6,
                              color: subs,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                '同一字形:引号=language,星芒=AI / A 的横杠=节点 / 气泡=对话',
                style: TextStyle(
                  fontFamily: _cjk,
                  fontSize: 9.5,
                  height: 1.5,
                  letterSpacing: 0.3,
                  color: subs,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 出图
// ═══════════════════════════════════════════════════════════════════
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont();
    await _loadIcons();
  });

  Future<void> shot(
      WidgetTester tester, Widget child, String name, {bool dark = false}) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(dark: dark),
        // 开屏页本身没有 Scaffold/Material:补一个,让 DefaultTextStyle 来自主题,
        // 否则测试环境里会退到兜底字体(方块 + 黄下划线)。
        home: Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle(
            style: TextStyle(
              fontFamily: _cjk,
              color: dark ? _S.darkInk : _S.ink,
            ),
            child: child,
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    final ex = tester.takeException();
    if (ex != null) {
      final f = File('build/ui_real/_render_warnings.txt');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('$name: $ex\n', mode: FileMode.append);
    }
    await _capture(tester, key, name);
  }

  // ── A · 琉璃凝结 ──
  testWidgets('A f1 两个元素分开', (tester) async {
    await shot(tester, const _SplashA(t: 0.40), 'splash-a-f1.png');
  });
  testWidgets('A f2 相向靠近', (tester) async {
    await shot(tester, const _SplashA(t: 0.66), 'splash-a-f2.png');
  });
  testWidgets('A f3 相撞 · 融合波', (tester) async {
    await shot(tester, const _SplashA(t: 0.86), 'splash-a-f3.png');
  });
  testWidgets('A f4 合成标 + 字标(终帧)', (tester) async {
    await shot(tester, const _SplashA(t: 1.50), 'splash-a-f4.png');
  });
  testWidgets('A dark 终帧', (tester) async {
    await shot(tester, const _SplashA(t: 1.50, dark: true), 'splash-a-dark.png',
        dark: true);
  });

  // ── B · 双轨闭环 ──
  testWidgets('B f1 语言流浮现', (tester) async {
    await shot(tester, const _SplashB(t: 0.26), 'splash-b-f1.png');
  });
  testWidgets('B f2 双轨流转 · 光点跑动', (tester) async {
    await shot(tester, const _SplashB(t: 0.58), 'splash-b-f2.png');
  });
  testWidgets('B f3 收束进环心', (tester) async {
    await shot(tester, const _SplashB(t: 1.04), 'splash-b-f3.png');
  });
  testWidgets('B f4 A · 节点 mark(终帧)', (tester) async {
    await shot(tester, const _SplashB(t: 1.50), 'splash-b-f4.png');
  });
  testWidgets('B dark 终帧', (tester) async {
    await shot(tester, const _SplashB(t: 1.50, dark: true), 'splash-b-dark.png',
        dark: true);
  });

  // ── C · 对话体 ──
  testWidgets('C f1 气泡 + 打字中', (tester) async {
    await shot(tester, const _SplashC(t: 0.48), 'splash-c-f1.png');
  });
  testWidgets('C f2 打满 language + 光标', (tester) async {
    await shot(tester, const _SplashC(t: 0.78), 'splash-c-f2.png');
  });
  testWidgets('C f3 末字符被星芒替换', (tester) async {
    await shot(tester, const _SplashC(t: 0.86), 'splash-c-f3.png');
  });
  testWidgets('C f4 收成气泡 · 星(终帧)', (tester) async {
    await shot(tester, const _SplashC(t: 1.50), 'splash-c-f4.png');
  });
  testWidgets('C dark 终帧', (tester) async {
    await shot(tester, const _SplashC(t: 1.50, dark: true), 'splash-c-dark.png',
        dark: true);
  });

  // ── Logo 变体图(浅/深各一张)──
  testWidgets('logo 变体 · 浅底', (tester) async {
    await shot(tester, const _LogoSheet(dark: false), 'splash-logo-sheet.png');
  });
  testWidgets('logo 变体 · 深底', (tester) async {
    await shot(tester, const _LogoSheet(dark: true), 'splash-logo-sheet-dark.png',
        dark: true);
  });

  // ── 实现后对照帧:渲染**线上组件**(SplashKineticA),与预览逐像素对齐 ──
  testWidgets('REAL A f1(线上组件)', (tester) async {
    await shot(
      tester,
      const SplashKineticA(
        t: 0.40,
        dark: false,
        tagline: '让语言,回归本质',
      ),
      'splash-real-a-f1.png',
    );
  });
  testWidgets('REAL A f4 终帧(线上组件)', (tester) async {
    await shot(
      tester,
      const SplashKineticA(
        t: 1.50,
        dark: false,
        tagline: '让语言,回归本质',
      ),
      'splash-real-a-f4.png',
    );
  });
  testWidgets('REAL A dark 终帧(线上组件)', (tester) async {
    await shot(
      tester,
      const SplashKineticA(
        t: 1.50,
        dark: true,
        tagline: '让语言,回归本质',
      ),
      'splash-real-a-dark.png',
      dark: true,
    );
  });
}
