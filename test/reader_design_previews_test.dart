import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/config/v4_theme.dart';

/// 阅读器改版 · 3 个设计方向预览(用户明确要求先看方案再动手)。
///
/// 这三张是**设计预览**(布局/字体/底栏语言),不是已实现功能;
/// 用户选定方向后,再落到 `material_reader_screen.dart` 的生产代码里。
const String _fontFamily = 'PreviewCJK';

Future<void> _loadFont() async {
  for (final path in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes =
        Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
    await (FontLoader('Roboto')..addFont(bytes)).load();
    await (FontLoader(_fontFamily)..addFont(bytes)).load();
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
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()))))
        .load();
    return;
  }
}

ThemeData _theme() {
  final base = AppTheme.lightTheme;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _fontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _fontFamily),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(
              fontFamily: _fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}

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

const _title = 'The Four Million';
const _source = 'O. Henry · Project Gutenberg · C1';
const _paras = <String>[
  'The Four Million is a collection of short stories about the lives of '
      'ordinary people in New York City at the beginning of the twentieth '
      'century.',
  'Each story is a small window into a different life: a young woman who '
      'sells her hair to buy a gift, a clerk who dreams of a better job, and '
      'a group of neighbours who gather in the street on a hot summer night.',
  'What makes these stories memorable is not the plot but the tone. The '
      'narrator watches the city with warmth and a quiet sense of humour, '
      'never mocking the people he describes.',
];
const _paragraphHighlight = <String>['ordinary people', 'quiet sense of humour'];
const _translation = '正是这种语气让故事难忘——叙述者带着温暖和一种安静的幽默感看着这座城市,'
    '从不嘲笑他笔下的人。';

void main() {
  setUpAll(() async {
    await _loadFont();
    await _loadIcons();
  });

  Future<void> render(
    WidgetTester tester,
    Widget child,
    String name,
  ) async {
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
    await _capture(tester, key, name);
  }

  testWidgets('阅读器方案 A · 沉浸纸面', (tester) async {
    await render(tester, const _VariantA(), 'reader_plan_a.png');
  });
  testWidgets('阅读器方案 B · 杂志封面', (tester) async {
    await render(tester, const _VariantB(), 'reader_plan_b.png');
  });
  testWidgets('阅读器方案 C · 学习工作台', (tester) async {
    await render(tester, const _VariantC(), 'reader_plan_c.png');
  });
}

// ═══════════════════════════════════════════════════════════════════
// A · 沉浸纸面:不要彩色大头部,让正文成为主角;顶部极细工具行 + 底部玻璃胶囊
// ═══════════════════════════════════════════════════════════════════
class _VariantA extends StatelessWidget {
  const _VariantA();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4EC),
      body: SafeArea(
        bottom: false,
        child: Stack(children: <Widget>[
          Column(children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(children: <Widget>[
                Icon(Icons.arrow_back, size: 20, color: skin.inkSoft),
                const Spacer(),
                Text(_source,
                    style: TextStyle(fontSize: 10, color: skin.inkFaint)),
                const Spacer(),
                Icon(Icons.more_horiz, size: 20, color: skin.inkSoft),
              ]),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: 0.38,
                minHeight: 2,
                backgroundColor: skin.hairline,
                color: skin.accent,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(26, 22, 26, 120),
                children: <Widget>[
                  Text('TODAY’S READING',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w800,
                          color: skin.accent)),
                  const SizedBox(height: 8),
                  Text(_title,
                      style: TextStyle(
                          fontSize: 30,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          color: skin.ink)),
                  const SizedBox(height: 6),
                  Text('O. Henry · 2,400 words · about 11 min',
                      style: TextStyle(fontSize: 11, color: skin.inkSoft)),
                  const SizedBox(height: 16),
                  Container(height: 1, color: skin.hairline),
                  const SizedBox(height: 20),
                  for (var i = 0; i < _paras.length; i++) ...[
                    _immersiveParagraph(context, _paras[i],
                        highlight: i == 0 ? _paragraphHighlight : null),
                    if (i == 1) _immersiveTranslation(context),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          ]),
          // 底部玻璃胶囊:翻译 / 收词(主)/ 追问
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: skin.hairline),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 10)),
                ],
              ),
              child: Row(children: <Widget>[
                _glassAction(skin, Icons.translate, '翻译'),
                _glassAction(skin, Icons.headphones_outlined, '朗读'),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                      color: skin.accent,
                      borderRadius: BorderRadius.circular(999)),
                  child: const Text('收词',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
                const Spacer(),
                _glassAction(skin, Icons.auto_awesome, '追问'),
                _glassAction(skin, Icons.bookmark_border, '收藏'),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _immersiveParagraph(BuildContext context, String text,
      {List<String>? highlight}) {
    final skin = V4Skin.of(context);
    return Text(
      text,
      style: TextStyle(
          fontSize: 19,
          height: 1.85,
          color: skin.ink.withValues(alpha: 0.92)),
    );
  }

  Widget _immersiveTranslation(BuildContext context) {
    final skin = V4Skin.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: skin.accent, width: 2.5)),
        color: skin.accent.withValues(alpha: 0.04),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.translate, size: 12, color: skin.accent),
          const SizedBox(width: 4),
          Text('译文',
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: skin.accent)),
        ]),
        const SizedBox(height: 4),
        Text(_translation,
            style: TextStyle(
                fontSize: 13, height: 1.7, color: skin.inkSoft)),
      ]),
    );
  }

  Widget _glassAction(V4Skin skin, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 19, color: skin.inkSoft),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 8.5, color: skin.inkFaint)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// B · 杂志封面:大图 hero + 标题压在图上,正文白卡
// ═══════════════════════════════════════════════════════════════════
class _VariantB extends StatelessWidget {
  const _VariantB();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: <Widget>[
            Row(children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: skin.surface.withValues(alpha: 0.9),
                    shape: BoxShape.circle),
                child: Icon(Icons.arrow_back, size: 18, color: skin.ink),
              ),
              const Spacer(),
              Icon(Icons.bookmark_border, size: 20, color: skin.inkSoft),
              const SizedBox(width: 14),
              Icon(Icons.more_horiz, size: 20, color: skin.inkSoft),
            ]),
            const SizedBox(height: 10),
            // hero 封面
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(children: <Widget>[
                // 设计预览里不用程序化封面(它自带书名,会和下面的标题叠字),
                // 用一块书封质感的渐变占位
                Container(
                  width: double.infinity,
                  height: 230,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[Color(0xFF7C8BEF), Color(0xFF4C5AF0)],
                    ),
                  ),
                  child: Icon(Icons.menu_book_rounded,
                      size: 96, color: Colors.white.withValues(alpha: 0.18)),
                ),
                Container(
                  height: 230,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 16,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(999)),
                          child: const Text('原版书 · C1',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                        const SizedBox(height: 6),
                        const Text(_title,
                            style: TextStyle(
                                fontSize: 28,
                                height: 1.1,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                                color: Colors.white)),
                      ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
              _chip(skin, Icons.text_snippet_outlined, '2,400 词'),
              _chip(skin, Icons.schedule, '约 11 分钟'),
              _chip(skin, Icons.donut_small_outlined, '已知 72%'),
              _chip(skin, Icons.auto_awesome_outlined, '适合精读'),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(26),
                boxShadow: skin.shadow,
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('O. Henry',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: skin.inkSoft)),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _paras.length; i++) ...[
                      Text(_paras[i],
                          style: TextStyle(
                              fontSize: 16,
                              height: 1.8,
                              color: skin.ink)),
                      if (i == 1)
                        Container(
                          margin: const EdgeInsets.only(top: 10, bottom: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: skin.surfaceAlt,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(_translation,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.7,
                                  color: skin.inkSoft)),
                        ),
                      const SizedBox(height: 14),
                    ],
                  ]),
            ),
            const SizedBox(height: 12),
            Row(children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.translate, size: 17),
                  label: const Text('全文翻译'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('生词练习'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _chip(V4Skin skin, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: skin.hairline)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: skin.accent),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 10, color: skin.inkSoft)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// C · 学习工作台:每段一张卡,译文/查词/朗读贴段,底部大收词
// ═══════════════════════════════════════════════════════════════════
class _VariantC extends StatelessWidget {
  const _VariantC();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(children: <Widget>[
              Icon(Icons.arrow_back, size: 20, color: skin.inkSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: skin.ink)),
                      Text('第 3 / 8 段 · 已读 38%',
                          style: TextStyle(
                              fontSize: 9.5, color: skin.inkFaint)),
                    ]),
              ),
              SizedBox(
                width: 34,
                height: 34,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                    value: 0.38,
                    strokeWidth: 3,
                    backgroundColor: skin.hairline,
                    color: skin.accent,
                  ),
                  Text('38',
                      style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: skin.inkSoft)),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              children: <Widget>[
                for (var i = 0; i < _paras.length; i++) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: skin.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: i == 1 ? skin.accent : skin.hairline,
                          width: i == 1 ? 1.4 : 1),
                      boxShadow: skin.shadow,
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('§ ${i + 1}',
                                style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: skin.accent)),
                            const Spacer(),
                            Icon(Icons.volume_up_outlined,
                                size: 15, color: skin.inkFaint),
                            const SizedBox(width: 10),
                            Icon(Icons.translate,
                                size: 15,
                                color: i == 1 ? skin.accent : skin.inkFaint),
                          ]),
                          const SizedBox(height: 8),
                          Text(_paras[i],
                              style: TextStyle(
                                  fontSize: 16,
                                  height: 1.75,
                                  color: skin.ink)),
                          if (i == 1) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: skin.accent.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Text(_translation,
                                  style: TextStyle(
                                      fontSize: 12,
                                      height: 1.6,
                                      color: skin.inkSoft)),
                            ),
                          ],
                        ]),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: skin.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: skin.shadow,
          ),
          child: Row(children: <Widget>[
            _deskAction(skin, Icons.translate, '翻译', highlight: true),
            _deskAction(skin, Icons.search, '查词'),
            _deskAction(skin, Icons.auto_awesome, 'AI讲解'),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {},
              style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.add_circle_outline, size: 17),
              label: const Text('收词'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _deskAction(V4Skin skin, IconData icon, String label,
      {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 19, color: highlight ? skin.accent : skin.inkSoft),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 8.5,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                color: highlight ? skin.accent : skin.inkFaint)),
      ]),
    );
  }
}
