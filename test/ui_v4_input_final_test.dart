/// 输入板块收尾落地示意:
/// ① 阅读器「纸面 + 译文便签」② 识图「扫描工作台 + 校对清单」
/// (与生产代码本次改动一致;生产组件依赖 Provider/DB,此处用同款皮肤还原)
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/design_tokens.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/config/v4_theme.dart';
import 'package:readflow/widgets/app_ui.dart';
import 'package:readflow/widgets/graphics/graphics.dart';
import 'package:readflow/widgets/v4/v4_kit.dart';

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
    final loader = FontLoader('MaterialIcons')
      ..addFont(
          Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
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

void main() {
  testWidgets('输入板块收尾示意', (tester) async {
    await _loadFont();
    await _loadIcons();
    addTearDown(tester.view.reset);

    tester.view.physicalSize = const Size(828, 896);
    tester.view.devicePixelRatio = 1.0;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: const Scaffold(
            backgroundColor: Color(0xFF101216),
            body: Row(
              children: <Widget>[
                SizedBox(width: 414, height: 896, child: _ReaderPaperPanel()),
                SizedBox(width: 414, height: 896, child: _ScanWorkbenchPanel()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(Scaffold).first);
      await precacheImage(const AssetImage('assets/images/whale_tail.png'), ctx);
    });
    await tester.pump(const Duration(milliseconds: 400));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.4);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/ui_v4_flows').createSync(recursive: true);
      File('build/ui_v4_flows/jelly_input_final.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}

// ══════════════════════════════════════════════════════════════════
// ① 阅读器:纸面 + 译文便签
// ══════════════════════════════════════════════════════════════════

class _ReaderPaperPanel extends StatelessWidget {
  const _ReaderPaperPanel();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final body = TextStyle(fontSize: 15.5, height: 1.9, color: skin.ink);
    const mark = Color(0x66FFC9B0);
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: 'The College of Magic',
        domain: GraphicDomain.news,
        actions: <Widget>[
          IconButton(
              tooltip: '在书架',
              onPressed: () {},
              icon: const Icon(Icons.collections_bookmark_outlined, size: 20)),
          IconButton(
              tooltip: '更多',
              onPressed: () {},
              icon: const Icon(Icons.more_horiz, size: 20)),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 材料元信息条
          Container(
            width: double.infinity,
            color: skin.surfaceAlt,
            padding: const EdgeInsets.symmetric(
                horizontal: Gap.md, vertical: Gap.xs),
            child: Text(
              '612 词 · 约 4 分钟 · B2 · 覆盖率 96.2% · 生词收 12 个',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: skin.inkSoft),
            ),
          ),
          // 纸面正文
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: skin.hairline)),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Gap.md, Gap.md, Gap.md, Gap.sm),
                children: <Widget>[
                  Text('第 1 节 · 什么是魔法学院',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: skin.ink)),
                  const SizedBox(height: Gap.sm),
                  Text.rich(
                    TextSpan(
                      style: body,
                      children: <InlineSpan>[
                        const TextSpan(
                            text:
                                'The college of magic turns ordinary kids into '),
                        TextSpan(
                          text: 'confident',
                          style: body.copyWith(
                              backgroundColor: mark,
                              fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(
                            text:
                                ' magicians. Every summer, hundreds of children arrive with nothing but a suitcase and a letter.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.xs),
                  // 译文便签(与生产 _buildTranslationArea 成功态一致)
                  Container(
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                          skin.accent.withValues(alpha: 0.055), skin.surface),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: skin.accent.withValues(alpha: 0.16)),
                    ),
                    padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          margin: const EdgeInsets.only(top: 2, right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: skin.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('译',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: skin.accent)),
                        ),
                        Expanded(
                          child: Text(
                            '这所魔法学院把普通孩子变成自信的魔术师。每年夏天,'
                            '几百个孩子只带着一只行李箱和一封信来到这里。',
                            style: TextStyle(
                                fontSize: 13,
                                height: 1.75,
                                color: skin.inkSoft),
                          ),
                        ),
                        Icon(Icons.more_horiz,
                            size: 16, color: skin.inkFaint),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                  Text(
                    'They learn far more than tricks — patience, curiosity and courage. '
                    'Most of them will never perform on a stage, but the habit of showing up '
                    'stays with them for years.',
                    style: body,
                  ),
                  const SizedBox(height: Gap.xs),
                  Container(
                    decoration: BoxDecoration(
                      color: skin.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('正在翻译这段…',
                            style: TextStyle(
                                fontSize: 10, color: skin.inkFaint)),
                        const SizedBox(height: 6),
                        Container(
                            height: 10,
                            width: 240,
                            decoration: BoxDecoration(
                                color: skin.hairline,
                                borderRadius: BorderRadius.circular(999))),
                        const SizedBox(height: 6),
                        Container(
                            height: 10,
                            width: 170,
                            decoration: BoxDecoration(
                                color: skin.hairline,
                                borderRadius: BorderRadius.circular(999))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 底部动作栏(示意)
          Container(
            color: skin.surface,
            padding:
                const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
            child: Row(
              children: <Widget>[
                for (final a in const <(IconData, String)>[
                  (Icons.translate, '翻译'),
                  (Icons.playlist_add_check, '保存 3'),
                  (Icons.forum_outlined, '追问'),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: skin.surfaceAlt,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(a.$1, size: 15, color: skin.accent),
                            const SizedBox(width: 4),
                            Text(a.$2,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: skin.ink)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ② 识图:扫描工作台 + 校对清单
// ══════════════════════════════════════════════════════════════════

class _ScanWorkbenchPanel extends StatelessWidget {
  const _ScanWorkbenchPanel();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    const words = <(String, String, bool)>[
      ('ubiquitous', 'adj. 无处不在的', true),
      ('serendipity', 'n. 意外发现珍奇事物的运气', true),
      ('resilient', 'adj. 有韧性的', false),
    ];
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: '识别结果 (8/12)',
        domain: GraphicDomain.language,
        actions: <Widget>[
          IconButton(
              tooltip: '重新识别',
              onPressed: () {},
              icon: const Icon(Icons.auto_awesome, size: 20)),
          IconButton(
              tooltip: '全选',
              onPressed: () {},
              icon: const Icon(Icons.checklist, size: 20)),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Gap.page, Gap.sm, Gap.page, 0),
              children: <Widget>[
                // 识别状态卡(本次新增的扫描工作台顶部)
                Container(
                  padding:
                      const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: skin.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: skin.shadow,
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.check_circle_rounded,
                          size: 20, color: const Color(0xFF2F8A5B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Text('识别完成 · 12 个词',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: skin.ink)),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        skin.accent.withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(999),
                                  ),
                                  child: Text('已选 8',
                                      style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: skin.accent)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('2 张照片已存档 · 可回看对照',
                                style: TextStyle(
                                    fontSize: 10.5, color: skin.inkSoft)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Gap.sm),
                // 拍照大图(实际页面这里是用户气泡里的截图)
                Container(
                  height: 170,
                  decoration: BoxDecoration(
                    color: skin.surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: skin.hairline),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.image_outlined,
                            size: 26, color: skin.inkFaint),
                        const SizedBox(height: 4),
                        Text('共 2 张图片 · 可旋转/追加',
                            style: TextStyle(
                                fontSize: 10.5, color: skin.inkFaint)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Gap.md),
                Row(
                  children: <Widget>[
                    Text('校对清单',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: skin.ink)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: skin.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('12 个',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: skin.accent)),
                    ),
                    const Spacer(),
                    Text('勾选后保存 · 点词看详情',
                        style: TextStyle(
                            fontSize: 10.5, color: skin.inkFaint)),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                for (final w in words)
                  AppCard(
                    child: Row(
                      children: <Widget>[
                        Icon(
                          w.$3
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 20,
                          color: w.$3 ? skin.accent : skin.inkFaint,
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(w.$1,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: skin.ink)),
                              const SizedBox(height: 2),
                              Text(w.$2,
                                  style: TextStyle(
                                      fontSize: 12, color: skin.inkSoft)),
                            ],
                          ),
                        ),
                        Icon(Icons.volume_up_outlined,
                            size: 17, color: skin.inkSoft),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            color: skin.surface,
            padding:
                const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.md),
            child: FilledButton(
                onPressed: () {}, child: const Text('保存 8 个生词到词库')),
          ),
        ],
      ),
    );
  }
}
