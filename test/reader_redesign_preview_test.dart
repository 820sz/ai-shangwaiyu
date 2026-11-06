// 阅读器重设计 · 3 个**结构不同**的方案真实渲染预览(2026-11-06)
//
// 用户真机反馈(本轮的三个靶子):
//   1. 底部 UI 拥挤且不统一 —— 一排「模型 / 译 / 收词 / 追问 / ↑」挤在一起;
//   2. 整体字体、色调非常差;
//   3. 上下滑动没有阅读进度百分比。
//
// 这个测试**只出图,不跑业务**,所以刻意不 import package:readflow 的任何东西:
// 不碰数据库 / Hive / Provider / 网络,一次 `flutter test --no-pub` 十几秒出 6 张图。
// 三个方案的配色、字阶、底栏结构、弹层形态都写死在本文件里(见 READER-REDESIGN-
// OPTIONS-2026-11-06.md 的规格表),实现时照抄数值即可。
//
// 出图: build/ui_real/reader-redesign-{A,A-toc,B,B-settings,C,C-console}.png
// 同步: docs/ui-preview/real/(同名) —— 文档里直接引用这一份。
//
// 写法沿用 test/material_channel_render_test.dart:加载 Noto Sans SC + MaterialIcons,
// RenderRepaintBoundary.toImage(pixelRatio: 3) → 1170×2532 的真机比例 PNG。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _cjk = 'PreviewCJK';

/// 中文字体:必须真的加载进来,否则 flutter_test 的默认字体把所有字画成方块。
Future<void> _loadFont() async {
  for (final path in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\simsun.ttc',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes =
        Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
    await (FontLoader('Roboto')..addFont(bytes)).load();
    await (FontLoader(_cjk)..addFont(bytes)).load();
    return;
  }
}

/// 字体图标:底栏那些 translate / list_alt / more_horiz 必须真实加载才有字形。
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

/// 预览主题。
///
/// 注意（2026-11-06 实测）：只给 `ThemeData(fontFamily: …)` 在当前环境**不会**
/// 让文字吃到中文字体，渲染出来全是 Ahem 方块。必须显式 `textTheme.apply(fontFamily:)`
/// （与 `material_channel_render_test.dart` 同口径），否则 6 张图不可用。
ThemeData _theme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF9A5B2A),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFFFFFFF),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _cjk),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _cjk),
  );
}

/// 出图:同时写 build/ui_real 与 docs/ui-preview/real(文档直接引后者)。
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont();
    await _loadIcons();
  });

  Future<void> render(WidgetTester tester, Widget child, String name) async {
    addTearDown(tester.view.reset);
    // 390×844 = iPhone 14 / 主流安卓直屏的逻辑尺寸;pixelRatio 3 出图 1170×2532
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        // 兜底：预览自定义 widget 里裸 `Text`/`TextStyle` 也吃到中文字体
        // （只靠 ThemeData.fontFamily 在本环境不生效，会渲染成方块）。
        //
        // ⚠️ 必须同时写 `decoration: TextDecoration.none`：预览屏根节点不是
        // Scaffold/Material 时，MaterialApp 会把 WidgetsApp 的默认文字样式设成
        // 内部 `_errorTextStyle`（红字 + 纯黄双下划线，源码 app.dart:45-54），
        // 只覆盖 fontFamily 会让每行都留一条黄线。这里显式清掉 decoration。
        builder: (context, widget) => DefaultTextStyle.merge(
          style: const TextStyle(
            fontFamily: _cjk,
            decoration: TextDecoration.none,
          ),
          child: widget ?? const SizedBox.shrink(),
        ),
        home: child,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    // 布局告警不阻断出图(预览图的目的是看设计,不是断言零 overflow),
    // 但会记到 build/ui_real/_render_warnings.txt,便于实现阶段回归。
    final ex = tester.takeException();
    if (ex != null) {
      final f = File('build/ui_real/_render_warnings.txt');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('$name: $ex\n', mode: FileMode.append);
    }
    await _capture(tester, key, name);
  }

  testWidgets('方案 A · 书页(暖纸 / 顶部 2px 细条 + 右上角 37%)', (tester) async {
    await render(tester, const _VariantA(), 'reader-redesign-A.png');
  });

  testWidgets('方案 A · 目录弹层(卡片化,一节一张)', (tester) async {
    await render(tester, const _SheetA(), 'reader-redesign-A-toc.png');
  });

  testWidgets('方案 B · 学习台(白卡分段 / 分组底栏 / 右下进度环)', (tester) async {
    await render(tester, const _VariantB(), 'reader-redesign-B.png');
  });

  testWidgets('方案 B · 阅读设置弹层(同款卡片分组)', (tester) async {
    await render(tester, const _SheetB(), 'reader-redesign-B-settings.png');
  });

  testWidgets('方案 C · 版面(零常驻按钮 / 右侧百分比 / 上滑控制台)', (tester) async {
    await render(tester, const _VariantC(), 'reader-redesign-C.png');
  });

  testWidgets('方案 C · 阅读控制台(所有动作收进一个分组面板)', (tester) async {
    await render(tester, const _SheetC(), 'reader-redesign-C-console.png');
  });
}

// ═══════════════════════════════════════════════════════════════════════
// 共享假数据:一篇 930 词外刊的前三段 + 逐段中文译文 + 生词
// (英文/译文互相对应,生词在正文里真的有下划线,方便看排印效果)
// ═══════════════════════════════════════════════════════════════════════
class _Article {
  _Article._();

  static const String kicker = 'READING · 外刊精读';
  static const String title = 'The Quiet Hour';
  static const String meta = '外刊 · C1 · 930 词 · 约 8 分钟';
  static const String metaShort = '外刊 · C1 · 930 词';

  /// 进度:三个方案都用同一个真值(37%),只是**呈现在不同位置**。
  static const int percent = 37;

  static const List<String> paras = <String>[
    'For decades the office celebrated the busy generalist: the person who '
        'answers email during a call and edits a deck while replying to a '
        'message.',
    'The evidence is unusually consistent. What multitasking produces is not '
        'more output but a thinner, more distracted version of it — and the '
        'cost is paid in working memory.',
    'That is why a quiet hour can feel more productive than a crowded '
        'afternoon: the effort is simply continuous.',
  ];

  static const List<String> trans = <String>[
    '几十年来，办公室推崇的始终是忙碌的多面手：一边开会一边回邮件，一边改方案一边回消息。',
    '证据惊人地一致：多任务带来的不是更高产出，而是一份更稀薄、更涣散的产出；代价由工作记忆来承担。',
    '这就是为什么安静的一小时会比拥挤的一下午更有产出——努力本身是连续的。',
  ];

  /// 每段的生词(要加下划线):第 1 段 2 个、第 2 段 3 个、第 3 段 1 个。
  static const List<List<String>> words = <List<String>>[
    <String>['generalist', 'busy generalist'],
    <String>['consistent', 'multitasking', 'working memory'],
    <String>['productive', 'continuous'],
  ];

  static const List<String> toc = <String>[
    'The cost of switching',
    'Working memory, not willpower',
    'What a quiet hour buys',
    'A shorter, slower inbox',
  ];
}

// ═══════════════════════════════════════════════════════════════════════
// 三套配色(数值直接抄进生产代码)
// ═══════════════════════════════════════════════════════════════════════

/// A · 书页:暖纸 + 墨褐 + 赭石强调色。零彩色渐变,正文第一。
class _Pa {
  _Pa._();
  static const Color paper = Color(0xFFF4EFE3);
  static const Color sheet = Color(0xFFFBF7ED);
  static const Color ink = Color(0xFF241F17);
  static const Color inkSoft = Color(0xFF6E6555);
  static const Color inkFaint = Color(0xFF9A9080);
  static const Color hairline = Color(0xFFE2D8C4);
  static const Color accent = Color(0xFF9A5B2A);
  static const Color transBg = Color(0xFFEDE5D4);
}

/// B · 学习台:纯白 + 墨绿 + 卡片层级。所有动作都有容器边界。
class _Pb {
  _Pb._();
  static const Color page = Color(0xFFFFFFFF);
  static const Color alt = Color(0xFFF3F6F5);
  static const Color ink = Color(0xFF141A1C);
  static const Color inkSoft = Color(0xFF5C6B6A);
  static const Color inkFaint = Color(0xFF96A3A1);
  static const Color hairline = Color(0xFFE3EAE8);
  static const Color accent = Color(0xFF0F7263);
  static const Color transBg = Color(0xFFEAF4F1);
}

/// C · 版面:冷灰纸 + 近黑正文 + 砖红单一强调色。排版靠字号/粗细/双线。
class _Pc {
  _Pc._();
  static const Color page = Color(0xFFEEEFEA);
  static const Color sheet = Color(0xFFF8F8F4);
  static const Color ink = Color(0xFF15181A);
  static const Color inkSoft = Color(0xFF494F51);
  static const Color inkFaint = Color(0xFF8C918F);
  static const Color hairline = Color(0xFFD7D9D2);
  static const Color accent = Color(0xFFB23A2C);
}

// ═══════════════════════════════════════════════════════════════════════
// 公共小件
// ═══════════════════════════════════════════════════════════════════════

/// 假状态栏(9:41 + 信号/无线/电池):让 390×844 看起来就是一张真机截图,
/// 也顺便验证内容区不会被顶部安全区吃掉。
class _StatusBar extends StatelessWidget {
  final Color ink;
  const _StatusBar({required this.ink});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(
          children: <Widget>[
            Text('9:41',
                style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: ink)),
            const Spacer(),
            Icon(Icons.signal_cellular_alt, size: 12, color: ink),
            const SizedBox(width: 5),
            Icon(Icons.wifi, size: 12, color: ink),
            const SizedBox(width: 5),
            Icon(Icons.battery_full, size: 13, color: ink),
          ],
        ),
      ),
    );
  }
}

/// 生词下划线:把 [words] 在正文里找出来,换成加粗 + 虚线下划线的 span。
Widget _annotated({
  required String text,
  required List<String> words,
  required TextStyle style,
  required TextStyle marked,
}) {
  final lower = text.toLowerCase();
  final hitEnd = <int, int>{};
  for (final w in words) {
    if (w.trim().isEmpty) continue;
    for (final m in RegExp(RegExp.escape(w.toLowerCase())).allMatches(lower)) {
      hitEnd[m.start] = m.end;
    }
  }
  final starts = hitEnd.keys.toList()..sort();
  final spans = <TextSpan>[];
  var cursor = 0;
  for (final s in starts) {
    final e = hitEnd[s]!;
    if (s < cursor) continue;
    if (s > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, s), style: style));
    }
    spans.add(TextSpan(text: text.substring(s, e), style: marked));
    cursor = e;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: style));
  }
  return Text.rich(TextSpan(children: spans), style: style);
}

/// 一条 2px 横向进度条(左右两端都留着,不圆角、不渐变)。
class _ProgressLine extends StatelessWidget {
  final int percent;
  final Color track;
  final Color fill;
  final double height;
  const _ProgressLine({
    required this.percent,
    required this.track,
    required this.fill,
    this.height = 2,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: <Widget>[
          Expanded(flex: percent, child: ColoredBox(color: fill)),
          Expanded(flex: 100 - percent, child: ColoredBox(color: track)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 方案 A · 书页
//   底栏 3 组 / 4 个热区:[目录][翻译] | [收词 12(主)] | [⋯]
//   模型 / 阅读设置 / 导出 / 听写 全部下沉到「⋯」面板(不再常驻)
//   进度:顶部 2px 通栏细条 + 右上角常驻 37%
// ═══════════════════════════════════════════════════════════════════════
class _VariantA extends StatelessWidget {
  const _VariantA();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _Pa.paper,
      child: Column(
        children: <Widget>[
          const _StatusBar(ink: _Pa.inkFaint),
          _TopA(),
          _ProgressLine(percent: _Article.percent, track: _Pa.hairline, fill: _Pa.accent),
          Expanded(child: _BodyA()),
          _BottomA(),
        ],
      ),
    );
  }
}

class _TopA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        child: Row(
          children: <Widget>[
            const Icon(Icons.arrow_back_ios_new, size: 15, color: _Pa.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _Article.metaShort,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w500,
                    color: _Pa.inkFaint),
              ),
            ),
            const SizedBox(width: 8),
            // A 的进度呈现:右上角常驻百分比,细条在它下面一行通栏(见上层)
            Text(
              '${_Article.percent}%',
              style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  letterSpacing: 0.2,
                  fontWeight: FontWeight.w800,
                  color: _Pa.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyA extends StatelessWidget {
  Widget _para(int i) => _annotated(
        text: _Article.paras[i],
        words: _Article.words[i],
        style: const TextStyle(
            fontSize: 19,
            height: 1.92,
            letterSpacing: 0.05,
            color: _Pa.ink),
        marked: const TextStyle(
          fontSize: 19,
          height: 1.92,
          letterSpacing: 0.05,
          color: _Pa.ink,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: _Pa.accent,
          decorationThickness: 1.5,
          decorationStyle: TextDecorationStyle.dotted,
        ),
      );

  Widget _trans(int i) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: _Pa.transBg,
          border: Border(left: BorderSide(color: _Pa.accent, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('译',
                style: TextStyle(
                    fontSize: 9,
                    height: 1.2,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                    color: _Pa.accent)),
            const SizedBox(height: 5),
            Text(_Article.trans[i],
                style: const TextStyle(
                    fontSize: 14, height: 1.85, color: _Pa.inkSoft)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 28),
      children: <Widget>[
        Text(_Article.kicker,
            style: const TextStyle(
                fontSize: 9,
                height: 1.2,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w800,
                color: _Pa.accent)),
        const SizedBox(height: 10),
        Text(_Article.title,
            style: const TextStyle(
                fontSize: 27,
                height: 1.16,
                letterSpacing: -0.4,
                fontWeight: FontWeight.w800,
                color: _Pa.ink)),
        const SizedBox(height: 10),
        Text(_Article.meta,
            style: const TextStyle(
                fontSize: 11, height: 1.5, letterSpacing: 0.2, color: _Pa.inkFaint)),
        const SizedBox(height: 14),
        Container(height: 1, color: _Pa.hairline),
        const SizedBox(height: 18),
        const Text('01 · THE COST OF SWITCHING',
            style: TextStyle(
                fontSize: 10,
                height: 1.3,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: _Pa.inkFaint)),
        const SizedBox(height: 12),
        _para(0),
        _trans(0),
        const SizedBox(height: 22),
        _para(1),
        _trans(1),
        const SizedBox(height: 22),
        _para(2),
      ],
    );
  }
}

class _BottomA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 9, 16, 22),
      decoration: const BoxDecoration(
        color: _Pa.paper,
        border: Border(top: BorderSide(color: _Pa.hairline)),
      ),
      child: Row(
        children: <Widget>[
          _IconA(Icons.list_alt, '目录', active: false),
          const SizedBox(width: 22),
          _IconA(Icons.translate, '翻译', active: true),
          const Spacer(),
          // 唯一实心控件:收词(带本次已收数)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _Pa.accent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const <Widget>[
                Icon(Icons.bookmark_add_outlined, size: 15, color: Colors.white),
                SizedBox(width: 6),
                Text('收词 12',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.more_horiz, size: 22, color: _Pa.inkSoft),
        ],
      ),
    );
  }
}

class _IconA extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  const _IconA(this.icon, this.label, {required this.active});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 20, color: active ? _Pa.accent : _Pa.inkSoft),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(
                fontSize: 9.5,
                height: 1.1,
                letterSpacing: 0.3,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? _Pa.accent : _Pa.inkFaint)),
      ],
    );
  }
}

/// A 的目录弹层:一节一张卡 —— 节号 / 节名 / 词数 / 本节进度 / 在读徽标。
class _SheetA extends StatelessWidget {
  const _SheetA();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: IgnorePointer(child: _VariantA())),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.30)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 470,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: _Pa.sheet,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _Pa.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Text('目录',
                                style: TextStyle(
                                    fontSize: 20,
                                    height: 1.2,
                                    letterSpacing: -0.2,
                                    fontWeight: FontWeight.w900,
                                    color: _Pa.ink)),
                            const Spacer(),
                            Text('共 8 节 · 已读 ${_Article.percent}%',
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    height: 1.3,
                                    color: _Pa.inkFaint)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text('圆点是正在读的位置;每张卡下面那条是本节读完的比例',
                            style: TextStyle(
                                fontSize: 10.5,
                                height: 1.4,
                                color: _Pa.inkFaint)),
                        const SizedBox(height: 14),
                        for (var i = 0; i < _Article.toc.length; i++) ...<Widget>[
                          _TocCardA(
                            index: i + 1,
                            title: _Article.toc[i],
                            words: 120 + i * 40,
                            pct: <int>[62, 38, 12, 0][i],
                            current: i == 1,
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 2),
                        Container(
                          width: double.infinity,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _Pa.accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('从 ${_Article.percent}% 继续',
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TocCardA extends StatelessWidget {
  final int index;
  final String title;
  final int words;
  final int pct;
  final bool current;
  const _TocCardA({
    required this.index,
    required this.title,
    required this.words,
    required this.pct,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _Pa.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                current ? _Pa.accent.withValues(alpha: 0.5) : _Pa.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('0$index',
                  style: const TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                      color: _Pa.accent)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight:
                            current ? FontWeight.w800 : FontWeight.w600,
                        color: current ? _Pa.accent : _Pa.ink)),
              ),
              if (current)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _Pa.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('在读',
                      style: TextStyle(
                          fontSize: 9,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          color: _Pa.accent)),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 3,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                          flex: pct == 0 ? 1 : pct,
                          child: ColoredBox(
                              color: pct == 0
                                  ? _Pa.hairline
                                  : _Pa.accent.withValues(alpha: 0.7))),
                      Expanded(
                          flex: pct == 0 ? 99 : 100 - pct,
                          child: ColoredBox(color: _Pa.hairline)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('约 $words 词 · $pct%',
                  style: const TextStyle(
                      fontSize: 10, height: 1.2, color: _Pa.inkFaint)),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 方案 B · 学习台
//   段落 = 一张白卡(卡内原文 + 译文 + 卡头两个微动作)
//   底栏 3 组 / 5 个热区: [目录|翻译] 胶囊 · 收词(圆主按钮) · [追问|更多] 胶囊
//   进度:右下角 52px 悬浮环(环内 37%),同时兼任"回到顶部"
// ═══════════════════════════════════════════════════════════════════════
class _VariantB extends StatelessWidget {
  const _VariantB();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _Pb.page,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Column(
              children: <Widget>[
                const _StatusBar(ink: _Pb.inkFaint),
                _TopB(),
                Expanded(child: _BodyB()),
                _BottomB(),
              ],
            ),
          ),
          const Positioned(right: 16, bottom: 100, child: _RingB()),
        ],
      ),
    );
  }
}

class _TopB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
        child: Row(
          children: <Widget>[
            const Icon(Icons.arrow_back_ios_new, size: 15, color: _Pb.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_Article.metaShort,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      letterSpacing: 0.3,
                      fontWeight: FontWeight.w600,
                      color: _Pb.inkFaint)),
            ),
            const Icon(Icons.ios_share, size: 18, color: _Pb.inkSoft),
            const SizedBox(width: 12),
            const Icon(Icons.more_horiz, size: 20, color: _Pb.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _BodyB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 120),
      children: <Widget>[
        const Text('THE ATLANTIC · 2026',
            style: TextStyle(
                fontSize: 9,
                height: 1.2,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w800,
                color: _Pb.accent)),
        const SizedBox(height: 8),
        Text(_Article.title,
            style: const TextStyle(
                fontSize: 24,
                height: 1.2,
                letterSpacing: -0.5,
                fontWeight: FontWeight.w800,
                color: _Pb.ink)),
        const SizedBox(height: 8),
        Text('930 词 · 约 8 分钟 · 已读 ${_Article.percent}%',
            style: const TextStyle(
                fontSize: 11, height: 1.4, color: _Pb.inkFaint)),
        const SizedBox(height: 14),
        Container(height: 1, color: _Pb.hairline),
        const SizedBox(height: 14),
        _paraCardB(0),
        const SizedBox(height: 12),
        _paraCardB(1),
        const SizedBox(height: 12),
        _paraCardB(2),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _paraCardB(int i) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
      decoration: BoxDecoration(
        color: _Pb.page,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Pb.hairline),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x0C0C2E28), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('0${i + 1}',
                  style: const TextStyle(
                      fontSize: 9.5,
                      height: 1.2,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                      color: _Pb.inkFaint)),
              const Spacer(),
              _MiniB(Icons.translate, i == 0 ? '已译' : '译'),
              const SizedBox(width: 12),
              _MiniB(Icons.chat_bubble_outline, '问'),
            ],
          ),
          const SizedBox(height: 10),
          _annotated(
            text: _Article.paras[i],
            words: _Article.words[i],
            style: const TextStyle(
                fontSize: 17, height: 1.78, letterSpacing: 0.05, color: _Pb.ink),
            marked: const TextStyle(
              fontSize: 17,
              height: 1.78,
              letterSpacing: 0.05,
              color: _Pb.ink,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: _Pb.accent,
              decorationThickness: 1.5,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _Pb.transBg,
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                  left: BorderSide(color: _Pb.accent, width: 2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: const <Widget>[
                    Icon(Icons.translate, size: 11, color: _Pb.accent),
                    SizedBox(width: 4),
                    Text('译文',
                        style: TextStyle(
                            fontSize: 9,
                            height: 1.2,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w800,
                            color: _Pb.accent)),
                  ],
                ),
                const SizedBox(height: 5),
                Text(_Article.trans[i],
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.75, color: _Pb.inkSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniB extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniB(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: _Pb.accent),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 10.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: _Pb.accent)),
      ],
    );
  }
}

/// B 的进度环:52px 悬浮圆,环 37%,心 37%。点它 = 回到顶部 + 展开目录。
class _RingB extends StatelessWidget {
  const _RingB();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: _Pb.page,
        shape: BoxShape.circle,
        border: Border.all(color: _Pb.hairline),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x1A0A2622), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              value: _Article.percent / 100,
              strokeWidth: 3.2,
              backgroundColor: _Pb.hairline,
              color: _Pb.accent,
            ),
          ),
          Text('${_Article.percent}%',
              style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  letterSpacing: -0.2,
                  fontWeight: FontWeight.w800,
                  color: _Pb.ink)),
        ],
      ),
    );
  }
}

class _BottomB extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
      decoration: const BoxDecoration(
        color: _Pb.page,
        border: Border(top: BorderSide(color: _Pb.hairline)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // 左组:阅读导航(同一容器 = 同一类动作)
          _GroupB(items: <_GroupItem>[
            _GroupItem(Icons.list_alt, '目录', false),
            _GroupItem(Icons.translate, '翻译', true),
          ]),
          // 中央:唯一的主行动
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
                color: _Pb.accent, shape: BoxShape.circle),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: <Widget>[
                const Icon(Icons.bookmark_add_outlined,
                    size: 22, color: Colors.white),
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _Pb.page,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _Pb.accent, width: 1.2),
                    ),
                    child: const Text('12',
                        style: TextStyle(
                            fontSize: 9,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: _Pb.accent)),
                  ),
                ),
              ],
            ),
          ),
          // 右组:AI 与更多
          _GroupB(items: <_GroupItem>[
            _GroupItem(Icons.chat_bubble_outline, '追问', false),
            _GroupItem(Icons.more_horiz, '更多', false),
          ]),
        ],
      ),
    );
  }
}

class _GroupItem {
  final IconData icon;
  final String label;
  final bool active;
  const _GroupItem(this.icon, this.label, this.active);
}

class _GroupB extends StatelessWidget {
  final List<_GroupItem> items;
  const _GroupB({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _Pb.alt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _Pb.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0)
              Container(width: 1, height: 22, color: _Pb.hairline),
            SizedBox(
              width: 46,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(items[i].icon,
                      size: 18,
                      color: items[i].active ? _Pb.accent : _Pb.inkSoft),
                  const SizedBox(height: 3),
                  Text(items[i].label,
                      style: TextStyle(
                          fontSize: 9.5,
                          height: 1.1,
                          letterSpacing: 0.2,
                          fontWeight: items[i].active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: items[i].active ? _Pb.accent : _Pb.inkFaint)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// B 的阅读设置弹层:所有弹层共用一套「组标题 + 卡片」语言。
class _SheetB extends StatelessWidget {
  const _SheetB();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: IgnorePointer(child: _VariantB())),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.30)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 580,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: _Pb.page,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: _Pb.hairline,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Text('阅读设置',
                                style: TextStyle(
                                    fontSize: 20,
                                    height: 1.2,
                                    letterSpacing: -0.2,
                                    fontWeight: FontWeight.w900,
                                    color: _Pb.ink)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _Pb.transBg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text('实时生效',
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      height: 1.2,
                                      fontWeight: FontWeight.w700,
                                      color: _Pb.accent)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _labelB('字号'),
                        const SizedBox(height: 8),
                        _segB(const <String>['85%', '100%', '115%', '130%', '150%'], 2),
                        const SizedBox(height: 18),
                        _labelB('行距'),
                        const SizedBox(height: 8),
                        _segB(const <String>['紧凑', '标准', '宽松'], 1),
                        const SizedBox(height: 18),
                        _labelB('纸张'),
                        const SizedBox(height: 8),
                        Row(
                          children: const <Widget>[
                            Expanded(
                                child: _PaperChipB(
                                    '纸白', Color(0xFFFFFFFF), true)),
                            SizedBox(width: 10),
                            Expanded(
                                child: _PaperChipB(
                                    '米黄', Color(0xFFF4EFE3), false)),
                            SizedBox(width: 10),
                            Expanded(
                                child: _PaperChipB(
                                    '墨夜', Color(0xFF16181C), false)),
                          ],
                        ),
                        const SizedBox(height: 18),
                        // 预览:调完立刻看到正文长什么样
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _Pb.alt,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const <Widget>[
                              Text(
                                  'That is why a quiet hour can feel more '
                                  'productive than a crowded afternoon.',
                                  style: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.7,
                                      color: _Pb.ink)),
                              SizedBox(height: 6),
                              Text('这就是为什么安静的一小时会比拥挤的一下午更有产出。',
                                  style: TextStyle(
                                      fontSize: 12,
                                      height: 1.7,
                                      color: _Pb.inkSoft)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _Pb.ink,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('完成',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _labelB(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          height: 1.2,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: _Pb.inkFaint));

  Widget _segB(List<String> labels, int selected) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _Pb.alt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Pb.hairline),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                alignment: Alignment.center,
                decoration: i == selected
                    ? BoxDecoration(
                        color: _Pb.page,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 6,
                              offset: Offset(0, 2)),
                        ],
                      )
                    : null,
                child: Text(labels[i],
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: i == selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: i == selected ? _Pb.ink : _Pb.inkFaint)),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaperChipB extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  const _PaperChipB(this.label, this.color, this.selected);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? _Pb.accent : _Pb.hairline,
                width: selected ? 2 : 1),
          ),
        ),
        const SizedBox(height: 5),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                height: 1.2,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? _Pb.accent : _Pb.inkFaint)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 方案 C · 版面
//   底部常态 **0 个按钮**:只有一条贴底 2px 进度线 + 42px 把手区(左 37% / 中抓手)
//   所有动作 → 上滑「阅读控制台」(分组卡片面板,见 _SheetC)
//   进度:右侧悬浮 37% 胶囊 + 96px 竖轨道;双保险(把手区也写着 37%)
// ═══════════════════════════════════════════════════════════════════════
class _VariantC extends StatelessWidget {
  const _VariantC();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _Pc.page,
      child: Column(
        children: <Widget>[
          const _StatusBar(ink: _Pc.inkFaint),
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: _BodyC()),
                Positioned(
                  left: 12,
                  top: 2,
                  child: _CircleC(Icons.arrow_back_ios_new, 14),
                ),
                const Positioned(top: 268, right: 8, child: _RailC()),
              ],
            ),
          ),
          _BottomC(),
        ],
      ),
    );
  }
}

class _CircleC extends StatelessWidget {
  final IconData icon;
  final double size;
  const _CircleC(this.icon, this.size);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _Pc.page.withValues(alpha: 0.86),
        shape: BoxShape.circle,
        border: Border.all(color: _Pc.hairline),
      ),
      child: Icon(icon, size: size, color: _Pc.inkSoft),
    );
  }
}

/// C 的进度:右上悬浮 "37%" + 一条 96px 竖轨道(轨道里 37% 是砖红)。
class _RailC extends StatelessWidget {
  const _RailC();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: _Pc.page.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _Pc.hairline),
          ),
          child: Text('${_Article.percent}%',
              style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  letterSpacing: -0.2,
                  fontWeight: FontWeight.w800,
                  color: _Pc.ink)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 3,
          height: 96,
          child: Stack(
            children: <Widget>[
              const Positioned.fill(child: ColoredBox(color: _Pc.hairline)),
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 3,
                  height: 96 * _Article.percent / 100,
                  child: const ColoredBox(color: _Pc.accent),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BodyC extends StatelessWidget {
  Widget _em(String text, Color color) => Text(text,
      style: TextStyle(
          fontSize: 9.5,
          height: 1.3,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w800,
          color: color));

  Widget _transC(int i) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.only(left: 12),
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: _Pc.accent, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('中译',
                style: TextStyle(
                    fontSize: 8.5,
                    height: 1.2,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                    color: _Pc.accent)),
            const SizedBox(height: 4),
            Text(_Article.trans[i],
                style: const TextStyle(
                    fontSize: 13.5, height: 1.8, color: _Pc.inkSoft)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(26, 8, 46, 30),
      children: <Widget>[
        Row(
          children: <Widget>[
            _em('READING · 03', _Pc.accent),
            const Spacer(),
            _em('930 词', _Pc.inkFaint),
          ],
        ),
        const SizedBox(height: 10),
        Text(_Article.title,
            style: const TextStyle(
                fontSize: 28,
                height: 1.1,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w900,
                color: _Pc.ink)),
        const SizedBox(height: 10),
        const Text('The Atlantic · 2026 年 11 月 · C1',
            style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                letterSpacing: 0.3,
                color: _Pc.inkSoft)),
        const SizedBox(height: 12),
        Container(height: 2, color: _Pc.ink),
        const SizedBox(height: 2),
        Container(height: 1, color: _Pc.hairline),
        const SizedBox(height: 18),
        _annotated(
          text: _Article.paras[0],
          words: _Article.words[0],
          style: const TextStyle(
              fontSize: 20,
              height: 1.82,
              letterSpacing: 0.1,
              color: _Pc.ink),
          marked: const TextStyle(
            fontSize: 20,
            height: 1.82,
            letterSpacing: 0.1,
            color: _Pc.ink,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: _Pc.accent,
            decorationThickness: 1.6,
          ),
        ),
        _transC(0),
        const SizedBox(height: 24),
        _annotated(
          text: _Article.paras[1],
          words: _Article.words[1],
          style: const TextStyle(
              fontSize: 18, height: 1.8, letterSpacing: 0.05, color: _Pc.ink),
          marked: const TextStyle(
            fontSize: 18,
            height: 1.8,
            letterSpacing: 0.05,
            color: _Pc.ink,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: _Pc.accent,
            decorationThickness: 1.5,
          ),
        ),
        _transC(1),
        const SizedBox(height: 24),
        _annotated(
          text: _Article.paras[2],
          words: _Article.words[2],
          style: const TextStyle(
              fontSize: 18, height: 1.8, letterSpacing: 0.05, color: _Pc.ink),
          marked: const TextStyle(
            fontSize: 18,
            height: 1.8,
            letterSpacing: 0.05,
            color: _Pc.ink,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: _Pc.accent,
            decorationThickness: 1.5,
          ),
        ),
      ],
    );
  }
}

/// C 的底部:2px 贴底进度线 + 42px 把手区(左 37% / 中抓手)。没有任何按钮。
class _BottomC extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _Pc.page,
      child: Column(
        children: <Widget>[
          _ProgressLine(
              percent: _Article.percent, track: _Pc.hairline, fill: _Pc.accent),
          SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: <Widget>[
                  Text('${_Article.percent}%',
                      style: const TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          letterSpacing: 0.2,
                          fontWeight: FontWeight.w800,
                          color: _Pc.ink)),
                  const SizedBox(width: 8),
                  const Text('已读',
                      style: TextStyle(
                          fontSize: 9.5, height: 1.2, color: _Pc.inkFaint)),
                  const Spacer(),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _Pc.inkFaint.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  const Text('上滑工具',
                      style: TextStyle(
                          fontSize: 9.5, height: 1.2, color: _Pc.inkFaint)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
        ],
      ),
    );
  }
}

/// C 的阅读控制台:上滑面板,4 组卡片 —— 进度 / 学习 / 目录 / 材料。
class _SheetC extends StatelessWidget {
  const _SheetC();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(child: IgnorePointer(child: _VariantC())),
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.34)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 640,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: _Pc.sheet,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: _Pc.hairline,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Text('阅读控制台',
                                style: TextStyle(
                                    fontSize: 15,
                                    height: 1.2,
                                    letterSpacing: 0.2,
                                    fontWeight: FontWeight.w800,
                                    color: _Pc.ink)),
                            const Spacer(),
                            const Icon(Icons.keyboard_arrow_down,
                                size: 20, color: _Pc.inkFaint),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // 组 1 · 进度
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          decoration: BoxDecoration(
                            color: _Pc.page,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _Pc.hairline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  const Text('已读',
                                      style: TextStyle(
                                          fontSize: 10,
                                          height: 1.2,
                                          letterSpacing: 1.4,
                                          fontWeight: FontWeight.w800,
                                          color: _Pc.inkFaint)),
                                  const Spacer(),
                                  const Text('第 3 段 / 共 8 段',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          height: 1.2,
                                          color: _Pc.inkFaint)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: <Widget>[
                                  const Text('37',
                                      style: TextStyle(
                                          fontSize: 34,
                                          height: 1.0,
                                          letterSpacing: -1.5,
                                          fontWeight: FontWeight.w900,
                                          color: _Pc.accent)),
                                  const Text('%',
                                      style: TextStyle(
                                          fontSize: 15,
                                          height: 1.6,
                                          fontWeight: FontWeight.w800,
                                          color: _Pc.accent)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: _Pc.ink,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text('继续阅读',
                                        style: TextStyle(
                                            fontSize: 11,
                                            height: 1.2,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _ProgressLine(
                                  percent: _Article.percent,
                                  track: _Pc.hairline,
                                  fill: _Pc.accent,
                                  height: 3),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _labelC('学习'),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                                child: _TileC(
                                    Icons.translate, '翻译', '已翻 6/6 段', true)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _TileC(Icons.chat_bubble_outline, '追问',
                                    '带原文追问', false)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _TileC(Icons.bookmark_add_outlined, '收词',
                                    '本次 12 个', false)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _labelC('目录'),
                        const SizedBox(height: 8),
                        for (var i = 0; i < 3; i++)
                          _RowC(
                            leading: '0${i + 1}',
                            title: _Article.toc[i],
                            trailing: <String>['62%', '38%', '12%'][i],
                            current: i == 1,
                          ),
                        const SizedBox(height: 16),
                        _labelC('材料'),
                        const SizedBox(height: 8),
                        _RowC(
                            leading: 'Aa',
                            title: '字号与行距',
                            trailing: '115% · 标准',
                            current: false),
                        _RowC(
                            leading: 'AI',
                            title: '模型与思考档',
                            trailing: 'deepseek-chat · 标准',
                            current: false),
                        _RowC(
                            leading: '↓',
                            title: '导出 / 听写 / 读完',
                            trailing: 'Markdown',
                            current: false),
                        const SizedBox(height: 22),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _labelC(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          height: 1.2,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w800,
          color: _Pc.inkFaint));

  Widget _TileC(IconData icon, String title, String sub, bool active) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: active ? _Pc.accent.withValues(alpha: 0.06) : _Pc.page,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: active ? _Pc.accent.withValues(alpha: 0.45) : _Pc.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: active ? _Pc.accent : _Pc.inkSoft),
          const SizedBox(height: 7),
          Text(title,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: active ? _Pc.accent : _Pc.ink)),
          const SizedBox(height: 2),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 9.5, height: 1.2, color: _Pc.inkFaint)),
        ],
      ),
    );
  }

  Widget _RowC({
    required String leading,
    required String title,
    required String trailing,
    required bool current,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: current ? _Pc.accent.withValues(alpha: 0.06) : _Pc.page,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: current ? _Pc.accent.withValues(alpha: 0.45) : _Pc.hairline),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Text(leading,
                style: TextStyle(
                    fontSize: 9.5,
                    height: 1.2,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                    color: current ? _Pc.accent : _Pc.inkFaint)),
          ),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                    color: current ? _Pc.accent : _Pc.ink)),
          ),
          const SizedBox(width: 8),
          Text(trailing,
              style: const TextStyle(
                  fontSize: 9.5, height: 1.2, color: _Pc.inkFaint)),
        ],
      ),
    );
  }
}
