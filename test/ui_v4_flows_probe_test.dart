/// 识图 / 翻译内页的「审美方案」试渲(用户 2026-11-03:
/// "拍照识图/翻译里面那个前端你升级了嘛,没的话有什么新审美方案")。
///
/// 只渲图,不改生产代码:三个方向各渲一屏,让用户挑/混。
/// 产物:`build/ui_v4_flows/jelly_flows.png`(三屏并排,明色)。
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
import 'package:readflow/widgets/design_kit.dart';
import 'package:readflow/widgets/graphics/graphics.dart';
import 'package:readflow/widgets/material_cover.dart';
import 'package:readflow/widgets/v4/v4_kit.dart';

const String _previewFontFamily = 'PreviewCJK';

Future<void> _loadPreviewFont() async {
  const candidates = <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final bytes = Future<ByteData>.value(
        ByteData.sublistView(file.readAsBytesSync()),
      );
      await (FontLoader('Roboto')..addFont(bytes)).load();
      await (FontLoader(_previewFontFamily)..addFont(bytes)).load();
      return;
    } catch (_) {
      // 换下一个候选
    }
  }
}

Future<void> _loadPreviewIcons() async {
  const candidates = <String>[
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final loader = FontLoader('MaterialIcons')
        ..addFont(
            Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
      return;
    } catch (_) {
      // 换下一个候选
    }
  }
}

String? _sample(String name) {
  final f = File('build/art_samples/$name');
  return f.existsSync() ? f.path : null;
}

ThemeData _themeData() {
  final base = AppTheme.lightTheme;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _previewFontFamily),
    primaryTextTheme:
        base.primaryTextTheme.apply(fontFamily: _previewFontFamily),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(
              fontFamily: _previewFontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w700),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(
              fontFamily: _previewFontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('识图/翻译 内页审美方案试渲', (tester) async {
    await _loadPreviewFont();
    await _loadPreviewIcons();
    addTearDown(tester.view.reset);

    // 预解码本地样张(否则 Image.file 在假时钟下永远加载不出来)
    await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(SizedBox).first);
      for (final name in <String>['art_1.jpg', 'art_2.jpg', 'book_2.jpg']) {
        final p = _sample(name);
        if (p != null) await precacheImage(FileImage(File(p)), ctx);
      }
    });

    tester.view.physicalSize = const Size(1242, 896);
    tester.view.devicePixelRatio = 1.0;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _themeData(),
          home: Scaffold(
            backgroundColor: const Color(0xFF101216),
            body: Row(
              children: const <Widget>[
                SizedBox(width: 414, height: 896, child: _ScanWorkbench()),
                SizedBox(width: 414, height: 896, child: _PaperAnnotation()),
                SizedBox(width: 414, height: 896, child: _BilingualFlow()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.4);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/ui_v4_flows').createSync(recursive: true);
      File('build/ui_v4_flows/jelly_flows.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}

// ══════════════════════════════════════════════════════════════════
// 方案 A:识图 = 扫描工作台(照片条 + 时间线 + 校对清单)
// ══════════════════════════════════════════════════════════════════

class _ScanWorkbench extends StatelessWidget {
  const _ScanWorkbench();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    const words = <(String, String, bool)>[
      ('ubiquitous', 'adj. 无处不在的', true),
      ('serendipity', 'n. 意外发现珍奇事物的运气', true),
      ('resilient', 'adj. 有韧性的', false),
      ('diligent', 'adj. 勤勉的', true),
    ];
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: '识别结果 · 12 个生词',
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
          // ① 照片条:识别结果始终能对回原图(点开可放大对照)
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 0),
              children: <Widget>[
                for (var i = 0; i < 3; i++) ...<Widget>[
                  Stack(
                    children: <Widget>[
                      MaterialCover(
                        seed: 'raw_$i',
                        kind: 'article',
                        width: 96,
                        height: 72,
                        radius: 14,
                        localImagePath: _sample(
                            const <String>['art_2.jpg', 'book_2.jpg', 'art_1.jpg'][i]),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: Gap.xs),
                ],
              ],
            ),
          ),
          // ② 识别过程:一条安静的时间线,而不是转圈
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 0),
            child: AppCard(
              variant: AppCardVariant.compact,
              child: Row(
                children: <Widget>[
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: skin.accent),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('拍照 2 张 → 识别 12 个词 → 去重 + 查词典',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                  const AppTag('2 张已存档', tone: AppTagTone.success),
                ],
              ),
            ),
          ),
          // ③ 校对清单:像一份"待核对清单",而不是一坨卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 0),
            child: Row(
              children: <Widget>[
                Text('校对清单',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: skin.ink)),
                const SizedBox(width: 6),
                const AppTag('12 个', tone: AppTagTone.primary),
                const Spacer(),
                Text('点词可改释义',
                    style: TextStyle(fontSize: 10.5, color: skin.inkFaint)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, 0),
              children: <Widget>[
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
                              Row(
                                children: <Widget>[
                                  Text(w.$1,
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: skin.ink)),
                                  if (!w.$3) ...[
                                    const SizedBox(width: 6),
                                    const AppTag('待核对',
                                        tone: AppTagTone.warning),
                                  ],
                                ],
                              ),
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
          // ④ 保存:底部唯一主行动
          Container(
            color: skin.surface,
            padding: const EdgeInsets.fromLTRB(
                Gap.page, Gap.sm, Gap.page, Gap.md),
            child: FilledButton(
                onPressed: () {}, child: const Text('保存 8 个生词到词库')),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 方案 B:阅读/翻译 = 纸面批注(正文像纸,生词马克笔,译文便签)
// ══════════════════════════════════════════════════════════════════

class _PaperAnnotation extends StatelessWidget {
  const _PaperAnnotation();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final base = TextStyle(
        fontSize: 15, height: 1.95, color: skin.ink, letterSpacing: 0.1);
    const mark = Color(0x66FFC9B0);
    const mark2 = Color(0x55C9C1FF);
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: 'The College of Magic',
        domain: GraphicDomain.news,
        actions: <Widget>[
          IconButton(
              tooltip: '翻译',
              onPressed: () {},
              icon: const Icon(Icons.translate, size: 20)),
          IconButton(
              tooltip: '更多',
              onPressed: () {},
              icon: const Icon(Icons.more_horiz, size: 20)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.lg),
        children: <Widget>[
          // 纸面:浅色卡片 + 细边;生词用马克笔底色,像批改过的讲义
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: skin.shadow,
            ),
            child: Text.rich(
              TextSpan(
                style: base,
                children: <InlineSpan>[
                  const TextSpan(
                      text: 'The college of magic turns ordinary kids into '),
                  TextSpan(
                    text: 'confident',
                    style: base.copyWith(
                      backgroundColor: mark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: ' magicians. Every summer, hundreds of '),
                  TextSpan(
                    text: 'resilient',
                    style: base.copyWith(
                      backgroundColor: mark2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(
                      text: ' children arrive with nothing but a suitcase and '
                          'a letter. They learn far more than tricks — '),
                  TextSpan(
                    text: 'ubiquitous',
                    style: base.copyWith(
                      backgroundColor: mark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: ' patience, curiosity and courage.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          // 译文便签:贴在段末,不打断正文
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                  skin.accentAlt.withValues(alpha: 0.08), skin.surface),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: skin.accentAlt.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.sticky_note_2_outlined,
                        size: 15, color: skin.accentAlt),
                    const SizedBox(width: 5),
                    Text('译文 · 第 3 段',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: skin.accentAlt)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '这所魔法学院把普通孩子变成自信的魔术师。每年夏天,几百个孩子只带着一只行李箱和一封信来到这里。',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.7, color: skin.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          // 查词浮层预览:点击生词后从底部升起(这里画成一张玻璃卡)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: skin.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: skin.hairline),
              boxShadow: skin.heroShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('ubiquitous',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: skin.ink)),
                    const SizedBox(width: 8),
                    Text('/juːˈbɪkwɪtəs/',
                        style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: skin.inkSoft)),
                    const Spacer(),
                    Icon(Icons.volume_up_outlined,
                        size: 19, color: skin.accent),
                  ],
                ),
                const SizedBox(height: 4),
                Text('adj. 无处不在的,普遍存在的',
                    style: TextStyle(fontSize: 13.5, color: skin.inkSoft)),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('收进生词本'),
                      ),
                    ),
                    const SizedBox(width: Gap.xs),
                    OutlinedButton(onPressed: () {}, child: const Text('追问')),
                  ],
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
// 方案 C:翻译 = 双语对照(段对段,进度环,局部骨架)
// ══════════════════════════════════════════════════════════════════

class _BilingualFlow extends StatelessWidget {
  const _BilingualFlow();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    const pairs = <(String, String)>[
      (
        'The college of magic turns ordinary kids into confident magicians.',
        '这所魔法学院把普通孩子变成自信的魔术师。',
      ),
      (
        'Every summer, hundreds of children arrive with nothing but a suitcase and a letter.',
        '每年夏天,几百个孩子只带着一只行李箱和一封信来到这里。',
      ),
    ];
    Widget pair(int i) {
      final p = pairs[i];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('§ ${i + 1}',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: skin.inkFaint)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: skin.shadow,
            ),
            child: Text(p.$1,
                style: TextStyle(
                    fontSize: 14.5, height: 1.8, color: skin.ink)),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                  skin.accent.withValues(alpha: 0.06), skin.surface),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: skin.accent.withValues(alpha: 0.16)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: skin.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('译',
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: skin.accent)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(p.$2,
                      style: TextStyle(
                          fontSize: 13.5, height: 1.75, color: skin.inkSoft)),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
        ],
      );
    }

    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: '逐段翻译 · 4/9 段',
        domain: GraphicDomain.news,
        actions: <Widget>[
          IconButton(
              tooltip: '停止翻译',
              onPressed: () {},
              icon: const Icon(Icons.stop_circle_outlined, size: 20)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: 4 / 9,
            minHeight: 4,
            backgroundColor: skin.surfaceAlt,
            color: skin.accent,
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 0),
            child: Row(
              children: <Widget>[
                const AppTag('对照阅读', tone: AppTagTone.primary),
                const SizedBox(width: Gap.xs),
                const AppTag('点段落可追问'),
                const Spacer(),
                Text('已翻好的段落会保留',
                    style: TextStyle(fontSize: 10.5, color: skin.inkFaint)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Gap.page, Gap.sm, Gap.page, 0),
              children: <Widget>[
                pair(0),
                pair(1),
                // 正在翻译的段落:就地显示骨架(不是全局转圈)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('§ 3',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: skin.inkFaint)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: skin.surface,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: skin.shadow,
                      ),
                      child: Text(
                        'They learn far more than tricks — patience, '
                        'curiosity and courage.',
                        style: TextStyle(
                            fontSize: 14.5,
                            height: 1.8,
                            color: skin.ink),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: skin.surfaceAlt,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                              height: 10,
                              width: 220,
                              decoration: BoxDecoration(
                                  color: skin.hairline,
                                  borderRadius:
                                      BorderRadius.circular(999))),
                          const SizedBox(height: 8),
                          Container(
                              height: 10,
                              width: 150,
                              decoration: BoxDecoration(
                                  color: skin.hairline,
                                  borderRadius:
                                      BorderRadius.circular(999))),
                          const SizedBox(height: 6),
                          Text('正在翻译这一段…',
                              style: TextStyle(
                                  fontSize: 9.5, color: skin.inkFaint)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            color: skin.surface,
            padding: const EdgeInsets.fromLTRB(
                Gap.page, Gap.sm, Gap.page, Gap.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                      onPressed: () {}, child: const Text('只看原文')),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: FilledButton(
                      onPressed: () {}, child: const Text('继续翻译')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
