/// 助理 / 我的 两板块改版 · 3 个整体方向预览图导出。
///
/// 这是**设计预览**(布局/配色/字体层级/卡片语言/数据可视化),不是已实现功能;
/// 用户选定方向后再落进 `lib/screens/tutor/` 与 `lib/screens/profile/` 的生产代码。
///
/// 产物(9 张,pixelRatio 3,390x844 逻辑尺寸):
///   build/ui_real/assistant-A.png  助理首页 · 方向 A(诊断台)
///   build/ui_real/assistant-B.png  助理首页 · 方向 B(每日简报)
///   build/ui_real/assistant-C.png  助理首页 · 方向 C(极简档案)
///   build/ui_real/mine-A.png       我的旗舰 · 方向 A(学习统计)
///   build/ui_real/mine-B.png       我的旗舰 · 方向 B(本周报告)
///   build/ui_real/mine-C.png       我的旗舰 · 方向 C(我的档案)
///   build/ui_real/detail-A.png     内页 · 方向 A(错误档案)
///   build/ui_real/detail-B.png     内页 · 方向 B(错误档案)
///   build/ui_real/detail-C.png     内页 · 方向 C(错误档案)
///
/// 跑法:`cd /d/readflow && flutter test test/assistant_mine_preview_test.dart --no-pub`
///
/// 为什么三个方向要画同一批内容(助理首页 / 我的旗舰 / 错误档案):
/// 内容固定才能一眼比较"语言"而不是比较"信息量";助理首页与错误档案在三张图里
/// 文案完全一致,方向差异只可能来自设计语言。
///
/// 字体:真实加载 `C:\Windows\Fonts\NotoSansSC-VF.ttf`(桌面有则用以保证中文
/// 不落成方框)+ Flutter SDK 缓存里的 MaterialIcons,和已装 App 的观感一致。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _ff = 'PreviewCJK';

Future<void> _loadFont() async {
  for (final path in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes =
        Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
    await (FontLoader('Roboto')..addFont(bytes)).load();
    await (FontLoader(_ff)..addFont(bytes)).load();
    return;
  }
}

Future<void> _loadIcons() async {
  for (final path in <String>[
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
    return;
  }
}

ThemeData _theme() => ThemeData(
      useMaterial3: true,
      fontFamily: _ff,
      scaffoldBackgroundColor: const Color(0xFFF4F5FA),
    );

Future<void> _capture(
    WidgetTester tester, GlobalKey key, String fileName) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/ui_real').createSync(recursive: true);
    File('build/ui_real/$fileName')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _render(WidgetTester tester, Widget child, String fileName) async {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: child,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 120));
  await _capture(tester, key, fileName);
}

void main() {
  setUpAll(() async {
    await _loadFont();
    await _loadIcons();
  });

  testWidgets('A · 助理首页(诊断台)', (tester) async {
    await _render(tester, const _AssistantA(), 'assistant-A.png');
  });
  testWidgets('B · 助理首页(每日简报)', (tester) async {
    await _render(tester, const _AssistantB(), 'assistant-B.png');
  });
  testWidgets('C · 助理首页(极简档案)', (tester) async {
    await _render(tester, const _AssistantC(), 'assistant-C.png');
  });
  testWidgets('A · 我的旗舰(学习统计)', (tester) async {
    await _render(tester, const _MineA(), 'mine-A.png');
  });
  testWidgets('B · 我的旗舰(本周报告)', (tester) async {
    await _render(tester, const _MineB(), 'mine-B.png');
  });
  testWidgets('C · 我的旗舰(我的档案)', (tester) async {
    await _render(tester, const _MineC(), 'mine-C.png');
  });
  testWidgets('A · 内页(错误档案)', (tester) async {
    await _render(tester, const _DetailA(), 'detail-A.png');
  });
  testWidgets('B · 内页(错误档案)', (tester) async {
    await _render(tester, const _DetailB(), 'detail-B.png');
  });
  testWidgets('C · 内页(错误档案)', (tester) async {
    await _render(tester, const _DetailC(), 'detail-C.png');
  });
}

// ═══════════════════════════════════════════════════════════════════
// 共享底座:调色板 / 文字 / 卡片 / 图表 / 状态栏
// ═══════════════════════════════════════════════════════════════════

/// 一个方向的一整套视觉令牌(配色 + 圆角 + 阴影)。
///
/// 方向 A 的数值直接取自生产皮肤 [V4Skin.jellyLight] 的同一批颜色,
/// 所以 A 不是"新配色",而是"果冻语言的数据化排布";
/// B/C 是本轮提案的新配色,用户选定后才进 `v4_theme.dart`。
class _P {
  const _P({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.line,
    required this.accent,
    required this.accent2,
    required this.warn,
    required this.radius,
    required this.shadow,
  });

  final Color bg;
  final Color surface;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color line;
  final Color accent;
  final Color accent2;
  final Color warn;
  final double radius;
  final List<BoxShadow> shadow;
}

const List<BoxShadow> _shadowA = <BoxShadow>[
  BoxShadow(color: Color(0x0D1B2140), blurRadius: 16, offset: Offset(0, 5)),
];
const List<BoxShadow> _shadowB = <BoxShadow>[
  BoxShadow(color: Color(0x14231C12), blurRadius: 26, offset: Offset(0, 10)),
];
const List<BoxShadow> _shadowC = <BoxShadow>[];

/// A ·「诊断台」:果冻的同一批色值,但排布从"大卡瀑布"改成"指标密集排布"。
const _P _pA = _P(
  bg: Color(0xFFF4F5FA),
  surface: Color(0xFFFFFFFF),
  ink: Color(0xFF1C1E2E),
  inkSoft: Color(0xFF5F6478),
  inkFaint: Color(0xFF9297AC),
  line: Color(0xFFE4E7F5),
  accent: Color(0xFF4C5AF0),
  accent2: Color(0xFF12A06E),
  warn: Color(0xFFD98600),
  radius: 18,
  shadow: _shadowA,
);

/// B ·「每日简报」:暖纸白 + 砖红 + 墨绿,像一份早上送到手里的简报。
const _P _pB = _P(
  bg: Color(0xFFFBF7F0),
  surface: Color(0xFFFFFFFF),
  ink: Color(0xFF211C16),
  inkSoft: Color(0xFF6C6259),
  inkFaint: Color(0xFFA0968A),
  line: Color(0xFFEDE3D5),
  accent: Color(0xFFC4562E),
  accent2: Color(0xFF2F5D50),
  warn: Color(0xFFD89A16),
  radius: 26,
  shadow: _shadowB,
);

/// C ·「极简档案」:无渐变、几乎无卡,纸白 + 黑字 + 一根琥珀色。
const _P _pC = _P(
  bg: Color(0xFFF8F8F6),
  surface: Color(0xFFFFFFFF),
  ink: Color(0xFF121212),
  inkSoft: Color(0xFF5C5C5C),
  inkFaint: Color(0xFF9B9B9B),
  line: Color(0xFFE3E3E0),
  accent: Color(0xFF121212),
  accent2: Color(0xFFC2751C),
  warn: Color(0xFFB45309),
  radius: 10,
  shadow: _shadowC,
);

/// 统一文字构造:显式写 fontFamily,保证预览里中文是真字体(不是方框)。
Text _t(
  String s,
  double size,
  Color color, {
  FontWeight weight = FontWeight.w400,
  double height = 1.4,
  double spacing = 0,
  int maxLines = 0,
  TextAlign align = TextAlign.start,
}) {
  return Text(
    s,
    style: TextStyle(
      fontFamily: _ff,
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing == 0 ? null : spacing,
    ),
    maxLines: maxLines == 0 ? null : maxLines,
    overflow: maxLines == 0 ? null : TextOverflow.ellipsis,
    textAlign: align,
  );
}

Widget _hr(_P p) => Container(height: 1, color: p.line);

Widget _card(
  _P p,
  Widget child, {
  EdgeInsets pad = const EdgeInsets.all(16),
  Color? color,
  double? radius,
}) {
  return Container(
    padding: pad,
    decoration: BoxDecoration(
      color: color ?? p.surface,
      borderRadius: BorderRadius.circular(radius ?? p.radius),
      border: Border.all(color: p.line, width: 0.8),
      boxShadow: p.shadow,
    ),
    child: child,
  );
}

Widget _pill(
  _P p,
  String label, {
  Color? bg,
  Color? fg,
  double size = 11,
  double h = 26,
}) {
  return Container(
    height: h,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: bg ?? p.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: p.line, width: 0.8),
    ),
    child: _t(label, size, fg ?? p.inkSoft, weight: FontWeight.w700),
  );
}

Widget _statusBar(_P p) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
    child: Row(children: <Widget>[
      _t('9:41', 12.5, p.ink, weight: FontWeight.w700),
      const Spacer(),
      Icon(Icons.signal_cellular_alt, size: 13, color: p.ink),
      const SizedBox(width: 5),
      Icon(Icons.wifi, size: 13, color: p.ink),
      const SizedBox(width: 5),
      Icon(Icons.battery_full, size: 13, color: p.ink),
    ]),
  );
}

/// 手机外壳:状态栏 + 内容区 + 底部导航。
///
/// 内容区底部加一层「淡出遮罩」:预览截的是首屏,长内容必然被导航栏截断;
/// 用 24px 渐变把截断处淡进页底,读起来是"还能往下滚"而不是"字被切掉了"。
Widget _frame(_P p, {required Widget body, Widget? nav, Color? bg}) {
  final Color pageBg = bg ?? p.bg;
  return Material(
    color: pageBg,
    child: Column(children: <Widget>[
      _statusBar(p),
      Expanded(
        child: Stack(children: <Widget>[
          Positioned.fill(child: body),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 44,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      pageBg.withValues(alpha: 0),
                      pageBg,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
      if (nav != null) nav,
    ]),
  );
}

Widget _iconBtn(_P p, IconData icon, {double size = 16}) {
  return Container(
    width: 32,
    height: 32,
    margin: const EdgeInsets.only(left: 8),
    decoration: BoxDecoration(
      color: p.surface,
      shape: BoxShape.circle,
      border: Border.all(color: p.line, width: 0.8),
    ),
    child: Icon(icon, size: size, color: p.inkSoft),
  );
}

/// 细进度条:先铺底线,再按比例压一条彩色(不用 CustomPainter,渲染零风险)。
Widget _bar(_P p, double v, Color c, {double h = 4}) {
  final double f = v.clamp(0.03, 1.0).toDouble();
  return Container(
    height: h,
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: p.line,
      borderRadius: BorderRadius.circular(h),
    ),
    child: FractionallySizedBox(
      widthFactor: f,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(h),
        ),
      ),
    ),
  );
}

/// 7 根柱(左旧右新),固定高度,不需要按数据算父约束。
Widget _weekBars(
  _P p,
  List<double> vals,
  Color c, {
  double h = 40,
  double gap = 5,
  double minH = 3,
}) {
  double maxV = 0;
  for (final v in vals) {
    if (v > maxV) maxV = v;
  }
  if (maxV <= 0) maxV = 1;
  final List<Widget> items = <Widget>[];
  for (var i = 0; i < vals.length; i++) {
    if (i > 0) items.add(SizedBox(width: gap));
    final double bh = (h * (vals[i] / maxV)).clamp(minH, h).toDouble();
    items.add(Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: bh,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    ));
  }
  return SizedBox(
    height: h,
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: items),
  );
}

/// 12 周打卡热力图(每格 1 天,从左到右是周)。
Widget _heatmap(_P p, {double cell = 9, double gap = 3}) {
  Color tone(int v) {
    if (v <= 0) return p.line.withValues(alpha: 0.6);
    final double k = (v / 3).clamp(0.0, 1.0).toDouble();
    return Color.lerp(p.accent.withValues(alpha: 0.16), p.accent, k) ?? p.accent;
  }

  final List<Widget> cols = <Widget>[];
  for (var w = 0; w < 12; w++) {
    if (w > 0) cols.add(SizedBox(width: gap));
    final List<Widget> days = <Widget>[];
    for (var d = 0; d < 7; d++) {
      if (d > 0) days.add(SizedBox(height: gap));
      days.add(Container(
        width: cell,
        height: cell,
        decoration: BoxDecoration(
          color: tone(_heat[w * 7 + d]),
          borderRadius: BorderRadius.circular(2.5),
        ),
      ));
    }
    cols.add(Column(children: days));
  }
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: cols);
}

/// 环形进度(48~56 的逻辑尺寸,细环)。
class _Ring extends StatelessWidget {
  const _Ring({
    required this.value,
    required this.size,
    required this.color,
    required this.track,
    this.stroke = 5,
    this.center,
  });

  final double value;
  final double size;
  final Color color;
  final Color track;
  final double stroke;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(value, color, track, stroke),
          ),
          if (center != null) center!,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);

  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    paint.color = track;
    canvas.drawArc(r, 0, 6.28318, false, paint);
    paint.color = color;
    canvas.drawArc(r, -1.5708, 6.28318 * value.clamp(0.0, 1.0).toDouble(), false,
        paint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color;
}

/// 假数据:打卡热力 12 周 x 7 天(0 休息 / 1-3 强度)。
/// 固定值而不是随机 —— 同一个方向每次渲出来的图必须一样,便于对比与复现。
const List<int> _heat = <int>[
  1, 2, 1, 3, 0, 1, 0, //
  2, 3, 0, 2, 1, 2, 0, //
  1, 2, 2, 3, 1, 0, 1, //
  3, 1, 2, 2, 2, 1, 0, //
  2, 3, 3, 1, 0, 2, 1, //
  1, 1, 2, 3, 2, 0, 0, //
  3, 2, 1, 2, 3, 1, 1, //
  2, 3, 2, 1, 1, 0, 0, //
  3, 3, 2, 2, 1, 2, 1, //
  1, 2, 3, 3, 2, 0, 1, //
  3, 3, 3, 3, 3, 2, 1, //
  2, 3, 3, 2, 1, 1, 0,
];

const List<double> _last7 = <double>[12, 18, 0, 20, 14, 6, 9];

/// 近 7 天的星期标签(左旧右新),与 `_last7` 一一对应。
const List<String> _weekday = <String>['一', '二', '三', '四', '五', '六', '日'];

// ═══════════════════════════════════════════════════════════════════
// 方向 A 的零件:密集仪表盘
// ═══════════════════════════════════════════════════════════════════

Widget _navA(_P p, int active) {
  Widget item(IconData icon, String label, bool on) {
    return Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(icon, size: 21, color: on ? p.accent : p.inkFaint),
        const SizedBox(height: 3),
        _t(label, 10, on ? p.accent : p.inkFaint,
            weight: on ? FontWeight.w700 : FontWeight.w500),
      ]),
    );
  }

  return Container(
    padding: const EdgeInsets.fromLTRB(12, 9, 12, 14),
    decoration: BoxDecoration(
      color: p.surface,
      border: Border(top: BorderSide(color: p.line, width: 0.8)),
    ),
    child: Row(children: <Widget>[
      item(Icons.menu_book_outlined, '输入', active == 0),
      item(Icons.edit_outlined, '输出', active == 1),
      item(Icons.insights_outlined, '助理', active == 2),
      item(Icons.person_outline, '我的', active == 3),
    ]),
  );
}

Widget _headA(_P p, String index, String title, {String? trailing}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 2),
    child: Row(children: <Widget>[
      _t(index, 10.5, p.accent, weight: FontWeight.w800, spacing: 0.8),
      const SizedBox(width: 8),
      _t(title, 14.5, p.ink, weight: FontWeight.w800),
      const Spacer(),
      if (trailing != null) _t(trailing, 11.5, p.inkFaint),
    ]),
  );
}

Widget _kpiA(_P p, String value, String unit, String label, Color color) {
  return Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: <Widget>[
        _t(value, 22, color, weight: FontWeight.w800, height: 1.1, spacing: -0.4),
        const SizedBox(width: 2),
        _t(unit, 10, p.inkFaint, weight: FontWeight.w600),
      ]),
      const SizedBox(height: 3),
      _t(label, 10, p.inkSoft, weight: FontWeight.w600),
    ]),
  );
}

class _AssistantA extends StatelessWidget {
  const _AssistantA();

  @override
  Widget build(BuildContext context) {
    const _P p = _pA;
    return _frame(
      p,
      nav: _navA(p, 2),
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                _t('学习助理', 20, p.ink, weight: FontWeight.w800, height: 1.2, spacing: -0.3),
                const SizedBox(height: 2),
                _t('11月6日 周四 · 连续 6 天', 11, p.inkFaint),
              ]),
            ),
            _iconBtn(p, Icons.refresh),
            _iconBtn(p, Icons.tune),
          ]),
          const SizedBox(height: 12),
          _card(
            p,
            Row(children: <Widget>[
              _kpiA(p, '42', '个', '待复习', p.accent),
              Container(width: 1, height: 30, color: p.line),
              const SizedBox(width: 12),
              _kpiA(p, '22', '分钟', '今日计划', p.ink),
              Container(width: 1, height: 30, color: p.line),
              const SizedBox(width: 12),
              _kpiA(p, '75', '%', '完成率', p.accent2),
            ]),
            pad: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          ),
          const SizedBox(height: 10),
          _card(
            p,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                _pill(p, '今天先做', bg: p.accent.withValues(alpha: 0.10), fg: p.accent, h: 22, size: 10),
                const Spacer(),
                _t('12 分钟', 11, p.inkFaint),
              ]),
              const SizedBox(height: 9),
              _t('复习 42 个到期词', 19, p.ink, weight: FontWeight.w800, height: 1.3, spacing: -0.3),
              const SizedBox(height: 4),
              _t('3 天内到期 · 复习准确率 82%', 11.5, p.inkSoft),
              const SizedBox(height: 12),
              Row(children: <Widget>[
                Expanded(
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _t('开始', 13, Colors.white, weight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.line, width: 1),
                    ),
                    child: _t('只标记完成', 12.5, p.inkSoft, weight: FontWeight.w600),
                  ),
                ),
              ]),
            ]),
            pad: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          ),
          const SizedBox(height: 18),
          _headA(p, '01', '现状分析', trailing: '五维'),
          _card(
            p,
            Column(children: <Widget>[
              _dimA(p, '词汇', '4,200', 'CEFR B1 · 距目标 800', 0.62, p.accent),
              _hr(p),
              _dimA(p, '语法', '62%', '近 30 天测验正确率', 0.62, p.warn),
              _hr(p),
              _dimA(p, '阅读', '148', 'wpm · 30 天读完 2 篇', 0.74, p.accent2),
              _hr(p),
              _dimA(p, '输出', '3 篇', '写译 30 天 · 均分 78', 0.4, p.accent),
              _hr(p),
              _dimA(p, '习惯', '6 天', '每天 22 分钟 · 连续', 0.86, p.accent2),
            ]),
            pad: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          ),
          const SizedBox(height: 18),
          _headA(p, '02', '复盘', trailing: '近 7 天'),
          _card(
            p,
            Row(children: <Widget>[
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  _t('计划 4 · 完成 3', 15, p.ink, weight: FontWeight.w800),
                  const SizedBox(height: 3),
                  _t('完成率 75% · 跳过 1 次', 11, p.inkSoft),
                ]),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 112,
                child: _weekBars(p, _last7, p.accent.withValues(alpha: 0.85), h: 34, gap: 3),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(p.radius),
            ),
            child: Row(children: <Widget>[
              Icon(Icons.bolt, size: 16, color: p.accent),
              const SizedBox(width: 8),
              Expanded(
                child: _t('把 42 个词拆成 2 组,中间休息 1 分钟', 12, p.ink, height: 1.5, maxLines: 2),
              ),
              const SizedBox(width: 8),
              _t('加入', 11.5, p.accent, weight: FontWeight.w800),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _dimA(_P p, String label, String value, String evidence, double v, Color c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: <Widget>[
          _t(label, 12.5, p.ink, weight: FontWeight.w700),
          const Spacer(),
          _t(value, 16, p.ink, weight: FontWeight.w800, height: 1.1, spacing: -0.2),
        ]),
        const SizedBox(height: 5),
        _bar(p, v, c, h: 3),
        const SizedBox(height: 5),
        _t(evidence, 10.5, p.inkFaint),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 方向 B 的零件:编辑排版 / 时间线
// ═══════════════════════════════════════════════════════════════════

Widget _navB(_P p, int active) {
  Widget item(IconData icon, String label, bool on) {
    return Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(
          width: 34,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon, size: 19, color: on ? p.accent : p.inkFaint),
        ),
        const SizedBox(height: 2),
        _t(label, 9.5, on ? p.accent : p.inkFaint,
            weight: on ? FontWeight.w800 : FontWeight.w500),
      ]),
    );
  }

  return Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
    decoration: BoxDecoration(
      color: p.surface,
      border: Border(top: BorderSide(color: p.line, width: 0.8)),
    ),
    child: Row(children: <Widget>[
      item(Icons.menu_book_outlined, '输入', active == 0),
      item(Icons.edit_outlined, '输出', active == 1),
      item(Icons.insights_outlined, '助理', active == 2),
      item(Icons.person_outline, '我的', active == 3),
    ]),
  );
}

Widget _eyebrowB(_P p, String s, {Color? color}) {
  return _t(s, 9.5, color ?? p.accent, weight: FontWeight.w800, spacing: 1.6);
}

Widget _timelineB(_P p, List<String> when, List<String> what) {
  final List<Widget> rows = <Widget>[];
  for (var i = 0; i < what.length; i++) {
    final bool last = i == what.length - 1;
    rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      SizedBox(
        width: 14,
        child: Column(children: <Widget>[
          const SizedBox(height: 4),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
          ),
          if (!last) Container(width: 1, height: 26, color: p.line),
        ]),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          _t(when[i], 10.5, p.inkFaint, weight: FontWeight.w600),
          const SizedBox(height: 1),
          _t(what[i], 12.5, p.ink, weight: FontWeight.w600, height: 1.45),
          if (!last) const SizedBox(height: 10),
        ]),
      ),
    ]));
  }
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
}

class _AssistantB extends StatelessWidget {
  const _AssistantB();

  @override
  Widget build(BuildContext context) {
    const _P p = _pB;
    return _frame(
      p,
      nav: _navB(p, 2),
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                _eyebrowB(p, 'THURSDAY BRIEF'),
                const SizedBox(height: 6),
                _t('11 / 06', 40, p.ink, weight: FontWeight.w900, height: 1.0, spacing: -1.2),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
              _t('周四', 11, p.inkSoft),
              const SizedBox(height: 2),
              _t('连续 6 天', 11.5, p.ink, weight: FontWeight.w800),
            ]),
          ]),
          const SizedBox(height: 14),
          _t('早上好,xi283。', 22, p.ink, weight: FontWeight.w800, height: 1.3, spacing: -0.4),
          const SizedBox(height: 6),
          _t('今天有 42 个到期词和一篇短文,大约 22 分钟。昨天你完成了 3 件事。',
              13.5, p.inkSoft, height: 1.75),
          const SizedBox(height: 18),
          _card(
            p,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                _eyebrowB(p, '今天的简报'),
                const Spacer(),
                _t('约 22 分钟', 10.5, p.inkFaint),
              ]),
              const SizedBox(height: 10),
              _t('42 个词,加一篇 380 词的短文', 19, p.ink,
                  weight: FontWeight.w800, height: 1.35, spacing: -0.3),
              const SizedBox(height: 14),
              _timelineB(p, const <String>['3 分钟 · 复习', '12 分钟 · 精读', '7 分钟 · 回译'],
                  const <String>['42 个到期词(准确率 82%)', '《The Four Million》第二节', '把昨天那句译文重写一遍']),
              const SizedBox(height: 16),
              Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: _t('开始今天的简报', 13.5, Colors.white, weight: FontWeight.w800),
              ),
            ]),
            pad: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          ),
          const SizedBox(height: 14),
          _card(
            p,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              _eyebrowB(p, '昨天', color: p.inkFaint),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: <Widget>[
                _t('2', 26, p.ink, weight: FontWeight.w900, height: 1.0),
                _t(' 篇材料', 11, p.inkSoft),
                const SizedBox(width: 14),
                _t('12', 26, p.ink, weight: FontWeight.w900, height: 1.0),
                _t(' 个新词', 11, p.inkSoft),
                const SizedBox(width: 14),
                _t('82%', 26, p.accent2, weight: FontWeight.w900, height: 1.0),
                _t(' 准确率', 11, p.inkSoft),
              ]),
              const SizedBox(height: 7),
              _t('比前天高 6 个点,是最近两周最好的一次。', 11.5, p.inkSoft, height: 1.6),
            ]),
            pad: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
            decoration: BoxDecoration(
              color: p.accent2.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border(left: BorderSide(color: p.accent2, width: 3)),
            ),
            child: _t('今天别一次刷完 42 个词 —— 拆成两组,中间起来走两步。',
                14, p.ink, height: 1.8),
          ),
          const SizedBox(height: 16),
          Row(children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                _eyebrowB(p, '本周', color: p.inkFaint),
                const SizedBox(height: 5),
                _t('4 天 · 86 个词', 13, p.ink, weight: FontWeight.w700),
              ]),
            ),
            const SizedBox(width: 16),
            SizedBox(width: 120, child: _weekBars(p, _last7, p.accent, h: 30, gap: 4)),
          ]),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 方向 C 的零件:档案排版(线 + 表 + 单色)
// ═══════════════════════════════════════════════════════════════════

Widget _navC(_P p, int active) {
  Widget item(String label, bool on) {
    return Expanded(
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? p.accent : Colors.transparent,
              width: 1.4,
            ),
          ),
        ),
        child: _t(label, 11, on ? p.ink : p.inkFaint,
            weight: on ? FontWeight.w700 : FontWeight.w500, spacing: 0.4),
      ),
    );
  }

  return Container(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    decoration: BoxDecoration(
      color: p.bg,
      border: Border(top: BorderSide(color: p.line, width: 0.8)),
    ),
    child: Row(children: <Widget>[
      item('输入', active == 0),
      item('输出', active == 1),
      item('助理', active == 2),
      item('我的', active == 3),
    ]),
  );
}

Widget _headC(_P p, String index, String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 6),
    child: Row(children: <Widget>[
      _t(index, 10, p.inkFaint, weight: FontWeight.w600, spacing: 0.8),
      const SizedBox(width: 10),
      _t(title, 13, p.ink, weight: FontWeight.w700),
      const SizedBox(width: 12),
      Expanded(child: Container(height: 1, color: p.line)),
    ]),
  );
}

Widget _metaRow(_P p, String title, String meta) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(children: <Widget>[
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          _t(title, 13.5, p.ink, weight: FontWeight.w600),
          const SizedBox(height: 3),
          _t(meta, 11, p.inkSoft, height: 1.55),
        ]),
      ),
      const SizedBox(width: 10),
      _t('›', 16, p.inkFaint, weight: FontWeight.w600),
    ]),
  );
}

Widget _ledgerRow(_P p, String label, String a, String b) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(children: <Widget>[
      Expanded(child: _t(label, 12.5, p.ink, weight: FontWeight.w500)),
      SizedBox(width: 62, child: _t(a, 12.5, p.ink, weight: FontWeight.w600, align: TextAlign.right)),
      SizedBox(width: 78, child: _t(b, 12.5, p.inkSoft, align: TextAlign.right)),
    ]),
  );
}

class _AssistantC extends StatelessWidget {
  const _AssistantC();

  @override
  Widget build(BuildContext context) {
    const _P p = _pC;
    return _frame(
      p,
      nav: _navC(p, 2),
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: _t('ASSISTANT / 助理', 10, p.inkFaint, weight: FontWeight.w600, spacing: 1.4)),
            Icon(Icons.search, size: 16, color: p.inkSoft),
            const SizedBox(width: 14),
            Icon(Icons.more_horiz, size: 16, color: p.inkSoft),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
            Expanded(
              child: _t('学习助理', 28, p.ink, weight: FontWeight.w700, height: 1.15, spacing: -0.6),
            ),
            _t('11.06', 11, p.inkFaint, weight: FontWeight.w500),
          ]),
          const SizedBox(height: 12),
          _hr(p),
          const SizedBox(height: 14),
          Row(children: <Widget>[
            _stripC(p, '42', '待复习'),
            _vlineC(p),
            _stripC(p, '22', '今日分钟'),
            _vlineC(p),
            _stripC(p, '75%', '完成率'),
          ]),
          const SizedBox(height: 22),
          _headC(p, '01', '现状分析'),
          _dimC(p, '词汇', '4,200 · CEFR B1', '距目标 800'),
          _hr(p),
          _dimC(p, '语法', '62%', '近 30 天测验'),
          _hr(p),
          _dimC(p, '阅读', '148 wpm', '30 天读完 2 篇'),
          _hr(p),
          _dimC(p, '输出', '3 篇 / 78 分', '写译 30 天'),
          _hr(p),
          _dimC(p, '习惯', '连续 6 天', '每天 22 分钟'),
          const SizedBox(height: 22),
          _headC(p, '02', '今天的任务'),
          _taskC(p, '复习 42 个到期词', '12′', false),
          _taskC(p, '精读《The Four Million》第二节', '12′', false),
          _taskC(p, '回译昨天那句', '7′', true),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Icon(Icons.add, size: 14, color: p.accent2),
            const SizedBox(width: 6),
            _t('自己加一条', 12.5, p.accent2, weight: FontWeight.w600),
          ]),
          const SizedBox(height: 22),
          _headC(p, '03', '复盘'),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: <Widget>[
            _t('计划 4 · 完成 3 · 跳过 1', 13, p.ink, weight: FontWeight.w500),
            const Spacer(),
            _t('75%', 15, p.accent2, weight: FontWeight.w700),
          ]),
          const SizedBox(height: 6),
          _t('主要卡在晚上:19 点后的任务只完成 1/3。', 11.5, p.inkSoft, height: 1.6),
          const SizedBox(height: 20),
          _hr(p),
          const SizedBox(height: 10),
          _t('本地计算 · 数据只存这台手机 · 不花 API', 10.5, p.inkFaint),
        ]),
      ),
    );
  }

  Widget _stripC(_P p, String value, String label) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _t(value, 20, p.ink, weight: FontWeight.w700, height: 1.1, spacing: -0.4),
        const SizedBox(height: 3),
        _t(label, 10.5, p.inkSoft),
      ]),
    );
  }

  Widget _vlineC(_P p) => Container(width: 1, height: 30, color: p.line, margin: const EdgeInsets.symmetric(horizontal: 12));

  Widget _dimC(_P p, String label, String value, String meta) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        SizedBox(width: 44, child: _t(label, 12.5, p.inkSoft, weight: FontWeight.w500)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            _t(value, 13, p.ink, weight: FontWeight.w600),
            const SizedBox(height: 2),
            _t(meta, 10.5, p.inkFaint),
          ]),
        ),
      ]),
    );
  }

  Widget _taskC(_P p, String title, String min, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(children: <Widget>[
        Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: done ? p.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: done ? p.ink : p.inkFaint, width: 1.2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _t(title, 13, done ? p.inkFaint : p.ink, weight: FontWeight.w500)),
        _t(min, 11, p.inkFaint),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 我的旗舰 · A:学习统计(仪表盘)
// ═══════════════════════════════════════════════════════════════════

class _MineA extends StatelessWidget {
  const _MineA();

  @override
  Widget build(BuildContext context) {
    const _P p = _pA;
    return _frame(
      p,
      nav: _navA(p, 3),
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                _t('我的 · 数据', 20, p.ink, weight: FontWeight.w800, height: 1.2, spacing: -0.3),
                const SizedBox(height: 2),
                _t('学习统计 · 学习节奏', 11, p.inkFaint),
              ]),
            ),
            _iconBtn(p, Icons.share_outlined),
          ]),
          const SizedBox(height: 12),
          _card(
            p,
            Row(children: <Widget>[
              _kpiA(p, '4,200', '个', '累计词汇', p.ink),
              _vp(p),
              _kpiA(p, '6', '天', '连续打卡', p.accent),
              _vp(p),
              _kpiA(p, '+86', '', '本周新增', p.accent2),
            ]),
            pad: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          ),
          const SizedBox(height: 18),
          _headA(p, '01', '学习节奏', trailing: '近 12 周'),
          _card(
            p,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                _t('学习打卡', 13, p.ink, weight: FontWeight.w800),
                const Spacer(),
                _t('每格 = 1 天', 10, p.inkFaint),
              ]),
              const SizedBox(height: 12),
              _heatmap(p),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                _t('少', 9.5, p.inkFaint),
                const SizedBox(width: 5),
                for (var i = 0; i < 4; i++) ...<Widget>[
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(right: 3),
                    decoration: BoxDecoration(
                      color: i == 0
                          ? p.line.withValues(alpha: 0.6)
                          : Color.lerp(p.accent.withValues(alpha: 0.16), p.accent, i / 3),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ],
                const SizedBox(width: 3),
                _t('多', 9.5, p.inkFaint),
                const Spacer(),
                _t('12 周共 41 天有记录', 10, p.inkFaint),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          _card(
            p,
            Column(children: <Widget>[
              Row(children: <Widget>[
                _t('近 7 天学习量', 13, p.ink, weight: FontWeight.w800),
                const Spacer(),
                _t('合计 79', 10.5, p.inkFaint),
              ]),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                Expanded(child: _weekBars(p, _last7, p.accent, h: 52, gap: 6)),
                const SizedBox(width: 16),
                Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  _Ring(
                    value: 5 / 7,
                    size: 54,
                    color: p.accent,
                    track: p.line,
                    stroke: 5,
                    center: _t('5/7', 12, p.ink, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  _t('活跃天', 9.5, p.inkFaint),
                ]),
              ]),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: _t(_weekday[i], 9.5, p.inkFaint, align: TextAlign.center),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: 18),
          _headA(p, '02', '最近在读'),
          _card(
            p,
            Column(children: <Widget>[
              _readingA(p, 'The Four Million', 'O. Henry · C1', 0.62, '读到 62%'),
              _hr(p),
              _readingA(p, 'CET-4 真题 2024', '四级阅读 · B1', 0.35, '读到 35%'),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _vp(_P p) => Container(width: 1, height: 30, color: p.line, margin: const EdgeInsets.symmetric(horizontal: 10));

  Widget _readingA(_P p, String title, String meta, double v, String tail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: _t(title, 12.5, p.ink, weight: FontWeight.w700, maxLines: 1)),
          _t(tail, 10.5, p.inkFaint),
        ]),
        const SizedBox(height: 4),
        _t(meta, 10, p.inkFaint),
        const SizedBox(height: 7),
        _bar(p, v, p.accent, h: 3),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 我的旗舰 · B:本周报告(简报)
// ═══════════════════════════════════════════════════════════════════

class _MineB extends StatelessWidget {
  const _MineB();

  @override
  Widget build(BuildContext context) {
    const _P p = _pB;
    return _frame(
      p,
      nav: _navB(p, 3),
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                _eyebrowB(p, 'WEEKLY REPORT'),
                const SizedBox(height: 6),
                _t('10.31 — 11.06', 20, p.ink, weight: FontWeight.w800, height: 1.2, spacing: -0.3),
              ]),
            ),
            _iconBtn(p, Icons.copy_all_outlined),
          ]),
          const SizedBox(height: 16),
          _t('这周,你比上周多学了 1 天。', 24, p.ink, weight: FontWeight.w800, height: 1.32, spacing: -0.5),
          const SizedBox(height: 7),
          _t('共 2 小时 40 分钟,收词 86 个,完成 3 次写译批改。晚上比上周稳。', 13, p.inkSoft, height: 1.75),
          const SizedBox(height: 16),
          _card(
            p,
            Row(children: <Widget>[
              _bigB(p, '2h40', '总时长'),
              _vpB(p),
              _bigB(p, '86', '新收词'),
              _vpB(p),
              _bigB(p, '82%', '复习准确率'),
            ]),
            pad: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          ),
          const SizedBox(height: 14),
          _card(
            p,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              _eyebrowB(p, '这周的形状', color: p.inkFaint),
              const SizedBox(height: 10),
              _weekBars(p, _last7, p.accent, h: 46, gap: 8),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                _t('周二最满(18)', 10.5, p.inkFaint),
                const Spacer(),
                _t('周三休息', 10.5, p.inkFaint),
              ]),
            ]),
            pad: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          ),
          const SizedBox(height: 14),
          _card(
            p,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              _eyebrowB(p, '三条要点', color: p.inkFaint),
              const SizedBox(height: 4),
              _pointB(p, '01', '复习准确率 82%,比上周高 6 个点,到期词从 61 降到 42。'),
              _hr(p),
              _pointB(p, '02', '写译批改 3 篇,均分 78;冠词错误依然是最多的一类。'),
              _hr(p),
              _pointB(p, '03', '周三整天没有记录 —— 不是坏事,但周四的任务因此压到了 4 件。'),
            ]),
            pad: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
            decoration: BoxDecoration(
              color: p.accent2.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border(left: BorderSide(color: p.accent2, width: 3)),
            ),
            child: _t('下周只改一件事:把 42 个到期词拆成每天 2 组,别留到周日。',
                14, p.ink, height: 1.8),
          ),
          const SizedBox(height: 16),
          Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.line),
            ),
            child: _t('复制这份报告', 12.5, p.inkSoft, weight: FontWeight.w700),
          ),
        ]),
      ),
    );
  }

  Widget _bigB(_P p, String value, String label) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _t(value, 21, p.ink, weight: FontWeight.w900, height: 1.1, spacing: -0.5),
        const SizedBox(height: 3),
        _t(label, 10, p.inkSoft),
      ]),
    );
  }

  Widget _vpB(_P p) => Container(width: 1, height: 28, color: p.line, margin: const EdgeInsets.symmetric(horizontal: 10));

  Widget _pointB(_P p, String index, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _t(index, 10, p.accent, weight: FontWeight.w800, spacing: 0.8),
        const SizedBox(width: 12),
        Expanded(child: _t(text, 12.5, p.ink, height: 1.7)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 我的旗舰 · C:我的档案(档案页)
// ═══════════════════════════════════════════════════════════════════

class _MineC extends StatelessWidget {
  const _MineC();

  @override
  Widget build(BuildContext context) {
    const _P p = _pC;
    return _frame(
      p,
      nav: _navC(p, 3),
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: _t('PROFILE / 我的', 10, p.inkFaint, weight: FontWeight.w600, spacing: 1.4)),
            Icon(Icons.settings_outlined, size: 16, color: p.inkSoft),
          ]),
          const SizedBox(height: 8),
          _t('我的档案', 28, p.ink, weight: FontWeight.w700, height: 1.15, spacing: -0.6),
          const SizedBox(height: 4),
          _t('xi283 · 学习第 118 天 · 数据只存本机', 11, p.inkSoft),
          const SizedBox(height: 14),
          _hr(p),
          const SizedBox(height: 14),
          Row(children: <Widget>[
            _stripC(p, '4,200', '累计词汇'),
            _vlineC(p),
            _stripC(p, '6 天', '连续打卡'),
            _vlineC(p),
            _stripC(p, '+86', '本周新增'),
          ]),
          const SizedBox(height: 22),
          _headC(p, '01', '数据台账'),
          Row(children: <Widget>[
            const Expanded(child: SizedBox()),
            SizedBox(width: 62, child: _t('本周', 10, p.inkFaint, align: TextAlign.right)),
            SizedBox(width: 78, child: _t('累计', 10, p.inkFaint, align: TextAlign.right)),
          ]),
          _hr(p),
          _ledgerRow(p, '新收词', '86', '4,200'),
          _hr(p),
          _ledgerRow(p, '阅读材料', '2 篇', '37 篇'),
          _hr(p),
          _ledgerRow(p, '复习准确率', '82%', '62%'),
          _hr(p),
          _ledgerRow(p, '写译批改', '3 篇', '41 篇'),
          _hr(p),
          _ledgerRow(p, '待处理错误', '7 类', '23 次'),
          const SizedBox(height: 22),
          _headC(p, '02', '打卡'),
          _heatmap(p, cell: 10, gap: 3.5),
          const SizedBox(height: 8),
          _t('最近 12 周 · 每格 = 1 天 · 深 = 当天学习量高', 10.5, p.inkFaint),
          const SizedBox(height: 22),
          _headC(p, '03', '入口'),
          _metaRow(p, '学习统计', '趋势 / 热力图 / 月度'),
          _hr(p),
          _metaRow(p, '本周报告', '本地算 · 不调 AI'),
          _hr(p),
          _metaRow(p, '错误档案', '待处理 7 类'),
          _hr(p),
          _metaRow(p, '写译记录', '41 篇 · 均分 78'),
          _hr(p),
          _metaRow(p, '备份与导出', '完整备份 / CSV / Anki'),
        ]),
      ),
    );
  }

  Widget _stripC(_P p, String value, String label) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _t(value, 20, p.ink, weight: FontWeight.w700, height: 1.1, spacing: -0.4),
        const SizedBox(height: 3),
        _t(label, 10.5, p.inkSoft),
      ]),
    );
  }

  Widget _vlineC(_P p) => Container(width: 1, height: 30, color: p.line, margin: const EdgeInsets.symmetric(horizontal: 12));
}

// ═══════════════════════════════════════════════════════════════════
// 内页 · 错误档案(三个方向同内容,只换语言)
// ═══════════════════════════════════════════════════════════════════

/// 错误档案的假数据(7 类待处理,共 23 次)。
const List<List<String>> _errs = <List<String>>[
  <String>['时态', '写译', '7', '11-05'],
  <String>['冠词', '测验', '5', '11-04'],
  <String>['搭配', '复习', '4', '11-05'],
  <String>['拼写', '写译', '3', '11-02'],
  <String>['语序', '测验', '2', '10-30'],
  <String>['单复数', '复习', '1', '10-29'],
  <String>['标点', '写译', '1', '11-01'],
];

Widget _backHeader(_P p, String title, {String? right}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
    child: Row(children: <Widget>[
      Icon(Icons.arrow_back_ios_new, size: 16, color: p.ink),
      const SizedBox(width: 10),
      Expanded(child: _t(title, 17, p.ink, weight: FontWeight.w800, height: 1.2, spacing: -0.2)),
      if (right != null) _t(right, 11, p.inkFaint),
    ]),
  );
}

class _DetailA extends StatelessWidget {
  const _DetailA();

  @override
  Widget build(BuildContext context) {
    const _P p = _pA;
    return _frame(
      p,
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          _backHeader(p, '错误档案'),
          const SizedBox(height: 6),
          Row(children: <Widget>[
            _pill(p, '待处理 7', bg: p.ink, fg: Colors.white, h: 28),
            const SizedBox(width: 8),
            _pill(p, '已改正 3', h: 28),
            const Spacer(),
            Icon(Icons.filter_list, size: 17, color: p.inkSoft),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: p.warn.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Icon(Icons.priority_high, size: 15, color: p.warn),
              const SizedBox(width: 6),
              Expanded(
                child: _t('共 7 类、23 次;最需要处理的是「时态」(7 次)', 11.5, p.inkSoft, height: 1.55),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          _card(
            p,
            Column(children: <Widget>[
              for (var i = 0; i < _errs.length; i++) ...<Widget>[
                if (i > 0) _hr(p),
                _errRowA(p, i),
              ],
            ]),
            pad: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Icon(Icons.check_circle_outline, size: 15, color: p.accent2),
            const SizedBox(width: 6),
            _t('已标记改正后,这条不再出现在待处理里', 10.5, p.inkFaint),
          ]),
        ]),
      ),
    );
  }

  Widget _errRowA(_P p, int i) {
    final List<String> row = _errs[i];
    final int n = int.tryParse(row[2]) ?? 0;
    final double v = n / 7;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: <Widget>[
        _Ring(
          value: v,
          size: 38,
          color: i == 0 ? p.warn : p.accent,
          track: p.line,
          stroke: 3,
          center: _t(row[2], 12, p.ink, weight: FontWeight.w800),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              _t(row[0], 13.5, p.ink, weight: FontWeight.w700),
              const SizedBox(width: 6),
              _pill(p, row[1], h: 19, size: 9),
            ]),
            const SizedBox(height: 4),
            _t('最近一次 ${row[3]}', 10.5, p.inkFaint),
          ]),
        ),
        _t('${row[2]} 次', 12, p.inkSoft, weight: FontWeight.w700),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, size: 17, color: p.inkFaint),
      ]),
    );
  }
}

class _DetailB extends StatelessWidget {
  const _DetailB();

  @override
  Widget build(BuildContext context) {
    const _P p = _pB;
    return _frame(
      p,
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: <Widget>[
              Icon(Icons.arrow_back_ios_new, size: 15, color: p.ink),
              const Spacer(),
              _eyebrowB(p, 'ERRORS', color: p.inkFaint),
            ]),
          ),
          _t('错误档案', 26, p.ink, weight: FontWeight.w900, height: 1.2, spacing: -0.6),
          const SizedBox(height: 7),
          _t('有 7 类错还没改,加起来 23 次。最该先动的是「时态」,它一个人占了 7 次。',
              13, p.inkSoft, height: 1.8),
          const SizedBox(height: 16),
          _card(
            p,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              _eyebrowB(p, '待处理 · 7 类', color: p.accent),
              const SizedBox(height: 4),
              for (var i = 0; i < _errs.length; i++) ...<Widget>[
                if (i > 0) _hr(p),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    _t('0${i + 1}', 10, p.accent, weight: FontWeight.w800, spacing: 0.8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Row(children: <Widget>[
                          _t(_errs[i][0], 13.5, p.ink, weight: FontWeight.w800),
                          const SizedBox(width: 8),
                          _t('${_errs[i][2]} 次 · ${_errs[i][1]}', 10.5, p.inkFaint),
                        ]),
                        const SizedBox(height: 3),
                        _t('最近一次 ${_errs[i][3]}', 10.5, p.inkSoft),
                      ]),
                    ),
                    Icon(Icons.arrow_forward, size: 15, color: p.inkFaint),
                  ]),
                ),
              ],
            ]),
            pad: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
            decoration: BoxDecoration(
              color: p.accent2.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border(left: BorderSide(color: p.accent2, width: 3)),
            ),
            child: _t('改错不是把 7 类全改一遍 —— 先把「时态」写对三次,剩下的会松一半。',
                13.5, p.ink, height: 1.8),
          ),
          const SizedBox(height: 16),
          Row(children: <Widget>[
            _t('已改正', 11, p.inkFaint, weight: FontWeight.w700, spacing: 0.4),
            const SizedBox(width: 8),
            _t('3 类', 11, p.ink, weight: FontWeight.w800),
            const Spacer(),
            _t('查看 ›', 11.5, p.accent2, weight: FontWeight.w700),
          ]),
        ]),
      ),
    );
  }
}

class _DetailC extends StatelessWidget {
  const _DetailC();

  @override
  Widget build(BuildContext context) {
    const _P p = _pC;
    return _frame(
      p,
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(Icons.arrow_back, size: 18, color: p.ink),
            const SizedBox(width: 12),
            Expanded(child: _t('错误档案', 13, p.ink, weight: FontWeight.w600)),
            _t('7 / 23', 11, p.inkFaint),
          ]),
          const SizedBox(height: 16),
          _t('错误档案', 26, p.ink, weight: FontWeight.w700, height: 1.15, spacing: -0.5),
          const SizedBox(height: 6),
          _t('待处理 7 类,累计 23 次。按次数排序。', 11.5, p.inkSoft, height: 1.6),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            for (var i = 0; i < 7; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                flex: (int.tryParse(_errs[i][2]) ?? 1),
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: i == 0 ? p.accent2 : p.ink.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 18),
          Row(children: <Widget>[
            Expanded(child: _t('错误', 10, p.inkFaint, weight: FontWeight.w600, spacing: 0.8)),
            SizedBox(width: 56, child: _t('来源', 10, p.inkFaint, weight: FontWeight.w600, align: TextAlign.right)),
            SizedBox(width: 46, child: _t('次数', 10, p.inkFaint, weight: FontWeight.w600, align: TextAlign.right)),
            SizedBox(width: 62, child: _t('最近', 10, p.inkFaint, weight: FontWeight.w600, align: TextAlign.right)),
          ]),
          _hr(p),
          for (var i = 0; i < _errs.length; i++) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(children: <Widget>[
                Expanded(child: _t(_errs[i][0], 13.5, p.ink, weight: i == 0 ? FontWeight.w700 : FontWeight.w500)),
                SizedBox(width: 56, child: _t(_errs[i][1], 11, p.inkSoft, align: TextAlign.right)),
                SizedBox(
                  width: 46,
                  child: _t(_errs[i][2], 12.5, i == 0 ? p.accent2 : p.ink, weight: FontWeight.w700, align: TextAlign.right),
                ),
                SizedBox(width: 62, child: _t(_errs[i][3], 10.5, p.inkFaint, align: TextAlign.right)),
              ]),
            ),
            _hr(p),
          ],
          const SizedBox(height: 18),
          Row(children: <Widget>[
            Expanded(
              child: Container(
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(8)),
                child: _t('开始改「时态」', 12.5, Colors.white, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: p.line),
                ),
                child: _t('已改正 3 类', 12, p.inkSoft, weight: FontWeight.w600),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
