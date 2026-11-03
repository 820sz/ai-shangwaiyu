/// v4「明亮果冻」主屏/内页预览图导出。
///
/// 用途(用户 2026-11-02 定案):**先看图,再打包**。本机没有真机,用 widget
/// 渲染成 PNG 是唯一可信的"第一眼验收"手段 —— 预览里用中文系统字体与
/// **真实生产组件**(V4Kit / AppCard / AppTag / AppContentTabs / MaterialCover /
/// ReadFlowBottomNav),所以图和装到手机上的观感一致。
///
/// 输出:`build/ui_v4_preview/*.png`(build/ 不进 git,重跑即重生成)。
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
import 'package:readflow/widgets/bottom_nav.dart';
import 'package:readflow/widgets/design_kit.dart';
import 'package:readflow/widgets/graphics/graphics.dart';
import 'package:readflow/widgets/material_cover.dart';
import 'package:readflow/widgets/v4/v4_kit.dart';

const String _previewFontFamily = 'PreviewCJK';

/// 本机实测抓取的真图(预览用):Douban 书封 + 360 插图。
/// 跑 `tool` 里的小脚本或用 curl 拉到 `build/art_samples/`;没有就跳过该行。
String? _samplePath(String name) {
  final f = File('build/art_samples/$name');
  return f.existsSync() ? f.path : null;
}

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
      final robotoLoader = FontLoader('Roboto')..addFont(bytes);
      final loader = FontLoader(_previewFontFamily)..addFont(bytes);
      await robotoLoader.load();
      await loader.load();
      return;
    } catch (_) {
      // 换下一个候选字体
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
          Future<ByteData>.value(
            ByteData.sublistView(file.readAsBytesSync()),
          ),
        );
      await loader.load();
      return;
    } catch (_) {
      // 换下一个候选路径
    }
  }
}

void main() {
  testWidgets('v4 明亮果冻:主屏与内页预览图导出', (tester) async {
    await _loadPreviewFont();
    await _loadPreviewIcons();
    addTearDown(tester.view.reset);

    // 主屏:输入 / 输出 / 内页三联 / 风格板 / 深色
    tester.view.physicalSize = const Size(1242, 896);
    tester.view.devicePixelRatio = 1.0;
    await _export(
      tester,
      Row(
        children: <Widget>[
          _shell(const _InputPreview(), tab: ReadFlowTab.input),
          _shell(const _OutputPreview(), tab: ReadFlowTab.output),
          _shell(const _InnerPreview(), tab: ReadFlowTab.tutor),
        ],
      ),
      'build/ui_v4_preview/jelly_main.png',
      pixelRatio: 2.4,
    );

    tester.view.physicalSize = const Size(1242, 896);
    tester.view.devicePixelRatio = 1.0;
    await _export(
      tester,
      Row(
        children: <Widget>[
          _shell(const _ProfilePreview(), tab: ReadFlowTab.profile),
          _shell(const _InnerPreview(), tab: ReadFlowTab.input),
          _shell(const _StyleBoard(), tab: ReadFlowTab.profile),
        ],
      ),
      'build/ui_v4_preview/jelly_detail.png',
      pixelRatio: 2.4,
    );

    // 深色:同一张主屏
    tester.view.physicalSize = const Size(414, 896);
    tester.view.devicePixelRatio = 1.0;
    await _export(
      tester,
      const _DarkPreview(),
      'build/ui_v4_preview/jelly_dark.png',
      pixelRatio: 2.4,
      dark: true,
    );

    // 第 1 组内页:材料中心 / 阅读器 / 题材分类
    tester.view.physicalSize = const Size(1242, 896);
    tester.view.devicePixelRatio = 1.0;
    await _export(
      tester,
      Row(
        children: <Widget>[
          const SizedBox(
            width: 414,
            height: 896,
            child: _MaterialCenterPreview(),
          ),
          const SizedBox(
            width: 414,
            height: 896,
            child: _ReaderPreview(),
          ),
          const SizedBox(
            width: 414,
            height: 896,
            child: _CategoryPreview(),
          ),
        ],
      ),
      'build/ui_v4_preview/jelly_inner.png',
      pixelRatio: 2.4,
    );

    // 封面样张:同一批材料在 5 种真实尺寸下的样子(明/暗)
    tester.view.physicalSize = const Size(828, 896);
    tester.view.devicePixelRatio = 1.0;
    await _export(
      tester,
      Row(
        children: <Widget>[
          const SizedBox(width: 414, height: 896, child: _CoverSheet(dark: false)),
          SizedBox(
            width: 414,
            height: 896,
            child: Theme(
              data: _themeData(true),
              child: const _CoverSheet(dark: true),
            ),
          ),
        ],
      ),
      'build/ui_v4_preview/jelly_covers.png',
      pixelRatio: 2.4,
    );

    // 第 2 批内页:书架 / 收藏夹
    tester.view.physicalSize = const Size(828, 896);
    tester.view.devicePixelRatio = 1.0;
    await _export(
      tester,
      Row(
        children: <Widget>[
          const SizedBox(width: 414, height: 896, child: _BookshelfPreview()),
          const SizedBox(width: 414, height: 896, child: _BookmarksPreview()),
        ],
      ),
      'build/ui_v4_preview/jelly_inner2.png',
      pixelRatio: 2.4,
    );

    // 第 2 批内页:生词本 / 词条详情
    tester.view.physicalSize = const Size(828, 896);
    tester.view.devicePixelRatio = 1.0;
    await _export(
      tester,
      Row(
        children: <Widget>[
          const SizedBox(width: 414, height: 896, child: _VocabListPreview()),
          const SizedBox(width: 414, height: 896, child: _VocabDetailPreview()),
        ],
      ),
      'build/ui_v4_preview/jelly_inner3.png',
      pixelRatio: 2.4,
    );

    // 主屏补全:助理 / 我的 / 复习
    tester.view.physicalSize = const Size(1242, 896);
    tester.view.devicePixelRatio = 1.0;
    await _export(
      tester,
      Row(
        children: <Widget>[
          const SizedBox(width: 414, height: 896, child: _TutorPreview()),
          const SizedBox(width: 414, height: 896, child: _ProfileMainPreview()),
          const SizedBox(width: 414, height: 896, child: _ReviewPreview()),
        ],
      ),
      'build/ui_v4_preview/jelly_main2.png',
      pixelRatio: 2.4,
    );

    // 输入链路收尾:识图结果 / 导入材料 / 读后测验
    tester.view.physicalSize = const Size(1242, 896);
    tester.view.devicePixelRatio = 1.0;
    await _export(
      tester,
      Row(
        children: <Widget>[
          const SizedBox(width: 414, height: 896, child: _ChatResultPreview()),
          const SizedBox(width: 414, height: 896, child: _ImportSheetPreview()),
          const SizedBox(width: 414, height: 896, child: _QuizPreview()),
        ],
      ),
      'build/ui_v4_preview/jelly_inner4.png',
      pixelRatio: 2.4,
    );
  });
}

Widget _shell(Widget page, {required ReadFlowTab tab}) {
  return SizedBox(
    width: 414,
    height: 896,
    child: Scaffold(
      body: page,
      bottomNavigationBar: ReadFlowBottomNav(
        currentTab: tab,
        onTabChanged: (_) {},
      ),
    ),
  );
}

ThemeData _themeData(bool dark) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  // flutter_test 的默认字体是 Ahem(所有字形都是方块):任何"没带 fontFamily"
  // 的文字都会变方块。主题里的按钮/输入框文字样式是裸 TextStyle,所以这里
  // 统一补上预览中文字体(真机上系统字体会自动回落,不受影响)。
  TextStyle withFont(TextStyle? style, {double size = 14}) =>
      (style ?? const TextStyle()).copyWith(
        fontFamily: _previewFontFamily,
        fontSize: size,
      );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _previewFontFamily),
    primaryTextTheme:
        base.primaryTextTheme.apply(fontFamily: _previewFontFamily),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          withFont(base.filledButtonTheme.style?.textStyle?.resolve(
                const <WidgetState>{},
              ), size: 15),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          withFont(const TextStyle(), size: 14),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          withFont(const TextStyle(), size: 14),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: withFont(base.chipTheme.labelStyle),
      secondaryLabelStyle: withFont(base.chipTheme.secondaryLabelStyle),
    ),
  );
}

Future<void> _export(
  WidgetTester tester,
  Widget child,
  String path, {
  required double pixelRatio,
  bool dark = false,
}) async {
  // 先把"真图样张"解码进 ImageCache:widget 测试的假时钟不会推进
  // FileImage 的真实 IO,直接 pump 的话 Image.file 永远停在错误占位上。
  await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(SizedBox).first);
    for (final name in <String>[
      'book_1.jpg',
      'book_2.jpg',
      'book_3.jpg',
      'book_4.jpg',
      'book_5.jpg',
      'art_1.jpg',
      'art_2.jpg',
    ]) {
      final p = _samplePath(name);
      if (p == null) continue;
      await precacheImage(FileImage(File(p)), ctx);
    }
  });

  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _themeData(dark),
        home: Scaffold(
          backgroundColor: const Color(0xFF101216),
          body: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/ui_v4_preview').createSync(recursive: true);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

// ══════════════════════════════════════════════════════════════════
// 输入首页(与 input_home 当前结构同构)
// ══════════════════════════════════════════════════════════════════

class _InputPreview extends StatelessWidget {
  const _InputPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return V4PageScaffold(
      domain: GraphicDomain.news,
      eyebrow: '11 月 3 日 · 星期一',
      title: '输入',
      subtitle: '读和写,才是输入。找不到想读的,去材料中心挑一篇。',
      showAppBarBack: false,
      actions: <Widget>[
        V4PillButton(
          label: '材料中心',
          light: true,
          icon: Icons.explore_outlined,
          onTap: () {},
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          V4TopicTabs(
            topics: v4TopicsFrom(const <({String id, String label})>[
              (id: 'sci_tech', label: '科技'),
              (id: 'business', label: '商业'),
              (id: 'health', label: '健康'),
              (id: 'culture', label: '文化'),
              (id: 'travel', label: '旅行'),
              (id: 'language', label: '语言'),
            ]),
            selectedId: 'sci_tech',
            onSelected: (_) {},
          ),
          const SizedBox(height: Gap.sm),
          AppCard(
            variant: AppCardVariant.hero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('继续读',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        )),
                    Spacer(),
                    AppTag('B2', tone: AppTagTone.primary),
                  ],
                ),
                SizedBox(height: Gap.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 88,
                      height: 118,
                      child: MaterialCover(
                        seed: 'The College of Magic',
                        kind: 'article',
                        width: 88,
                        height: 118,
                        levelLabel: 'B2',
                        localImagePath: _samplePath('art_2.jpg'),
                      ),
                    ),
                    SizedBox(width: Gap.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('魔法学院让普通孩子变身自信的戴高帽魔术师',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                height: 1.35,
                                fontWeight: FontWeight.w800,
                              )),
                          SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
                            AppTag('已读 62%'),
                            AppTag('覆盖率 68%'),
                            AppTag('约 8 分钟'),
                          ]),
                          SizedBox(height: Gap.sm),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: 0.62,
                              minHeight: 6,
                              backgroundColor: skin.surfaceAlt,
                            ),
                          ),
                          SizedBox(height: Gap.sm),
                          Row(children: <Widget>[
                            FilledButton(
                                onPressed: () {}, child: const Text('接着读')),
                            SizedBox(width: Gap.xs),
                            OutlinedButton(
                                onPressed: () {}, child: const Text('材料中心')),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
          Row(children: <Widget>[
            Expanded(
              child: V4ActionTile(
                icon: Icons.explore_outlined,
                title: '材料中心',
                subtitle: '按题材/难度找',
                primary: true,
                domain: GraphicDomain.news,
                onTap: () {},
              ),
            ),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: V4ActionTile(
                icon: Icons.auto_awesome,
                title: 'AI 找材料',
                subtitle: '说出需求自动找',
                domain: GraphicDomain.academic,
                onTap: () {},
              ),
            ),
          ]),
          const SizedBox(height: Gap.xs),
          Row(children: <Widget>[
            Expanded(
              child: V4ActionTile(
                icon: Icons.add_photo_alternate_outlined,
                title: '拍照/相册',
                subtitle: '纸面、屏幕变材料',
                domain: GraphicDomain.language,
                onTap: () {},
              ),
            ),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: V4ActionTile(
                icon: Icons.link,
                title: '链接导入',
                subtitle: '网页 / 论文 / 期刊',
                domain: GraphicDomain.culture,
                onTap: () {},
              ),
            ),
          ]),
          const V4SectionTitle(
            indexLabel: '01',
            title: '在读材料',
            subtitle: '按你的难度档 B2 排序',
          ),
          V4ListCard(
            title: '随着疫情蔓延,美国麻疹病例数比去年增加一倍以上',
            subtitle: '外刊 · 8 分钟 · 覆盖率 68%',
            domain: GraphicDomain.news,
            leading: const MaterialCover(
              seed: '麻疹疫情',
              kind: 'news',
              width: 42,
              height: 54,
              levelLabel: 'B2',
            ),
          ),
          V4ListCard(
            title: 'The Elements of Style',
            subtitle: '公版书 · 46 分钟 · 已读 12%',
            domain: GraphicDomain.book,
            leading: const MaterialCover(
              seed: 'The Elements of Style',
              kind: 'book',
              width: 42,
              height: 54,
              levelLabel: 'C1',
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 输出首页
// ══════════════════════════════════════════════════════════════════

class _OutputPreview extends StatelessWidget {
  const _OutputPreview();

  @override
  Widget build(BuildContext context) {
    return V4PageScaffold(
      domain: GraphicDomain.exam,
      eyebrow: '11 月 3 日 · 星期一',
      title: '输出',
      subtitle: '写词 → 写句 → 写段 → 写篇,四阶并行,从哪阶开始都行。',
      showAppBarBack: false,
      actions: <Widget>[
        V4PillButton(
          label: '练习中心',
          light: true,
          icon: Icons.tune,
          onTap: () {},
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const V4StageCard(
            title: '写词',
            subtitle: '语境填空 · 按目标词表',
            levelLabel: 'Lv1',
            domain: GraphicDomain.exam,
            progress: 0.72,
            ctaLabel: '继续',
          ),
          const V4StageCard(
            title: '写句',
            subtitle: '改写 · 纠错 · 连词成句',
            levelLabel: 'Lv2',
            domain: GraphicDomain.language,
            progress: 0.35,
            ctaLabel: '继续',
          ),
          const V4StageCard(
            title: '写段',
            subtitle: '材料回译 · 段落成文',
            levelLabel: 'Lv3',
            domain: GraphicDomain.news,
            progress: 0.12,
            ctaLabel: '开始',
          ),
          const V4StageCard(
            title: '写篇',
            subtitle: '作文题 · rubric 批改 · 折算档位',
            levelLabel: 'Lv4',
            domain: GraphicDomain.academic,
            progress: 0,
            ctaLabel: '开始',
          ),
          const V4SectionTitle(indexLabel: '02', title: '今日建议', subtitle: '按真实数据给'),
          V4ListCard(
            title: '先清 18 个到期复习词',
            subtitle: '昨晚 6 个词忘得快,今天先过一遍',
            domain: GraphicDomain.exam,
            leading: const CircleAvatar(
              radius: 16,
              child: Icon(Icons.refresh, size: 16),
            ),
          ),
          const V4SectionTitle(indexLabel: '03', title: '最近记录'),
          V4ListCard(
            title: '写篇 · 四六级作文:AI 与学习',
            subtitle: '昨天 · 88 分 · 折算 C1',
            domain: GraphicDomain.academic,
          ),
          V4ListCard(
            title: '写句 · 错句纠错 5/5',
            subtitle: '昨天 · 正确率 100%',
            domain: GraphicDomain.language,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 内页样张:材料中心 / 阅读器 / 练习结果(三种典型内页)
// ══════════════════════════════════════════════════════════════════

class _InnerPreview extends StatelessWidget {
  const _InnerPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, Gap.xl),
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('材料中心',
                style: AppFont.displayStyle.copyWith(
                    color: skin.ink, fontSize: 26, fontWeight: FontWeight.w900)),
            const Spacer(),
            AppTag('B2', tone: AppTagTone.primary),
          ],
        ),
        const SizedBox(height: Gap.sm),
        const Text('外刊 · 公版书 · 论文,按题材与难度挑',
            style: TextStyle(fontSize: 12, height: 1.5)),
        const SizedBox(height: Gap.md),
        AppContentTabs(
          tabs: const <String>['全部', '外刊', '公版书', '论文', '真题'],
          index: 0,
          onChanged: (_) {},
          horizontalPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: Gap.sm),
        Wrap(spacing: Gap.xs, children: <Widget>[
          AppTag('科技', icon: Icons.science_outlined),
          AppTag('商业'),
          AppTag('健康'),
          AppTag('文化'),
        ]),
        const SizedBox(height: Gap.md),
        AppWideCard(
          title: '随着疫情蔓延,美国麻疹病例数比去年增加一倍以上',
          subtitle: '外刊 · 8 分钟 · 覆盖率 68%',
          tags: <Widget>[
            AppTag('B2', tone: AppTagTone.primary),
            AppTag('外刊'),
          ],
          seed: '麻疹疫情',
          kind: 'news',
        ),
        AppWideCard(
          title: 'The Elements of Style',
          subtitle: '公版书 · 46 分钟 · 已读 12%',
          tags: <Widget>[AppTag('C1', tone: AppTagTone.primary)],
          seed: 'The Elements of Style',
          kind: 'book',
        ),
        const SizedBox(height: Gap.md),
        Text('阅读器',
            style: AppFont.headingStyle.copyWith(
                color: skin.ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: Gap.xs),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'The college of magic turns ordinary kids into confident '
                'magicians. 魔法学院让普通孩子变身自信的戴帽魔术师。',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.85,
                  color: skin.ink,
                ),
              ),
              const SizedBox(height: Gap.sm),
              Container(
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(
                  color: skin.surfaceAlt,
                  borderRadius: BorderRadius.circular(skin.controlRadius),
                ),
                child: Text(
                  '译:这所魔法学院把普通孩子变成了自信的魔术师。',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: skin.inkSoft,
                  ),
                ),
              ),
              const SizedBox(height: Gap.sm),
              Row(
                children: <Widget>[
                  AppTag('点词查询', icon: Icons.touch_app_outlined),
                  const SizedBox(width: Gap.xs),
                  AppTag('逐段翻译', icon: Icons.translate),
                  const Spacer(),
                  AppProgressRing(
                    value: 0.62,
                    centerText: '62%',
                    size: 46,
                    stroke: 5,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        Text('今日进度',
            style: AppFont.headingStyle.copyWith(
                color: skin.ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: Gap.xs),
        Row(
          children: const <Widget>[
            Expanded(child: AppStat(value: '18', label: '复习词')),
            Expanded(child: AppStat(value: '2', label: '输出练习')),
            Expanded(child: AppStat(value: '24', label: '分钟')),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 我的(主屏第四页)
// ══════════════════════════════════════════════════════════════════

class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, Gap.xl),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            gradient: skin.heroFill,
            borderRadius: BorderRadius.circular(skin.heroRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const CircleAvatar(
                    radius: 22,
                    child: Icon(Icons.person_rounded, size: 24),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('学习者',
                            style: AppFont.titleStyle.copyWith(
                                color: skin.ink, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text('目标 · 四六级 · 难度 B2',
                            style: AppFont.tagStyle
                                .copyWith(color: skin.inkSoft)),
                      ],
                    ),
                  ),
                  AppProgressRing(
                    value: 0.72,
                    centerText: '72%',
                    size: 48,
                    stroke: 5,
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Row(
                children: const <Widget>[
                  Expanded(child: AppStat(value: '18', label: '待复习')),
                  Expanded(child: AppStat(value: '24', label: '本周分钟')),
                  Expanded(child: AppStat(value: '12', label: '连续天数')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        AppCard(
          padding: const EdgeInsets.symmetric(
              horizontal: Gap.md, vertical: Gap.xs),
          child: Column(
            children: <Widget>[
              AppActionTile(
                icon: Icons.tune,
                title: '学习偏好',
                subtitle: '难度档 / 每日时长 / 目标考试',
                onTap: () {},
              ),
              AppActionTile(
                icon: Icons.insights_outlined,
                title: '统计与周报',
                subtitle: '能力趋势 / 输出量 / 复盘',
                onTap: () {},
              ),
              AppActionTile(
                icon: Icons.error_outline,
                title: '错误档案',
                subtitle: '按语法点归类的高频错误',
                onTap: () {},
              ),
              AppActionTile(
                icon: Icons.cloud_sync_outlined,
                title: '备份与恢复',
                subtitle: '十张表 / 能力快照全量备份',
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        V4Empty(
          icon: Icons.auto_stories_outlined,
          title: '本周还没有输出练习',
          hint: '先从写句开始,一句话就算一次输出。',
          domain: GraphicDomain.language,
          action: FilledButton(onPressed: () {}, child: const Text('去写一句')),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 第 1 组内页:材料中心 / 阅读器 / 题材分类
// ══════════════════════════════════════════════════════════════════

Widget _readerPill(V4Skin skin, IconData icon, String label,
    {bool primary = false}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    decoration: BoxDecoration(
      gradient: primary ? skin.accentFill : null,
      color: primary ? null : skin.surfaceAlt,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: primary ? skin.onAccent : skin.inkSoft),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: primary ? skin.onAccent : skin.inkSoft,
          ),
        ),
      ],
    ),
  );
}

class _MaterialCenterPreview extends StatelessWidget {
  const _MaterialCenterPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            V4DetailHeader(
              domain: GraphicDomain.news,
              title: '材料中心',
              subtitle: '选一篇,今天就读它',
              actions: <Widget>[
                V4IconAction(
                  icon: Icons.view_agenda_outlined,
                  tooltip: '区块管理',
                  onTap: () {},
                ),
                V4IconAction(
                  icon: Icons.add_circle_outline,
                  tooltip: '导入材料',
                  onTap: () {},
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Gap.page, Gap.md, Gap.page, Gap.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppCard(
                    variant: AppCardVariant.hero,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.tune, size: 20, color: skin.accent),
                        const SizedBox(width: Gap.sm),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text('我的需求',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800)),
                              SizedBox(height: 2),
                              Text('目标:四六级 · 难度 B2 · 喜欢外刊',
                                  style: TextStyle(fontSize: 11.5)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: skin.inkFaint),
                      ],
                    ),
                  ),
                  const AppSectionHeader(title: '今日精读', indexLabel: '01'),
                  AppHeroCard(
                    seed: '麻疹疫情',
                    kind: 'news',
                    eyebrow: '今日精读 · B2',
                    imageHeight: 118,
                    tags: <Widget>[
                      AppTag('外刊', tone: AppTagTone.primary),
                      AppTag('已读 62%'),
                    ],
                    title: '随着疫情蔓延,美国麻疹病例数比去年增加一倍以上',
                    subtitle: '读完进阅读器:点词查义、逐段翻译、追问',
                    meta: <Widget>[
                      const AppMeta(icon: Icons.schedule, text: '8 分钟'),
                      const AppMeta(icon: Icons.bar_chart, text: '覆盖率 68%'),
                    ],
                    actionLabel: '接着读',
                    onAction: () {},
                  ),
                  const AppSectionHeader(title: '按分类找材料', indexLabel: '02'),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AppActionTile(
                          style: AppActionTileStyle.grid,
                          icon: Icons.public,
                          title: '外刊',
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      Expanded(
                        child: AppActionTile(
                          style: AppActionTileStyle.grid,
                          icon: Icons.menu_book_outlined,
                          title: '公版书',
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      Expanded(
                        child: AppActionTile(
                          style: AppActionTileStyle.grid,
                          icon: Icons.science_outlined,
                          title: '论文',
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                  const AppSectionHeader(title: '今日推荐', indexLabel: '03'),
                  const AppWideCard(
                    title: 'The Elements of Style',
                    subtitle: '公版书 · 46 分钟 · 已读 12%',
                    tags: <Widget>[AppTag('C1', tone: AppTagTone.primary)],
                    seed: 'The Elements of Style',
                    kind: 'book',
                  ),
                  const AppWideCard(
                    title: 'A History of the World in 100 Objects',
                    subtitle: '外刊 · 12 分钟 · 预计 B2',
                    tags: <Widget>[AppTag('B2', tone: AppTagTone.primary)],
                    seed: 'History',
                    kind: 'news',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderPreview extends StatelessWidget {
  const _ReaderPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: 'The College of Magic',
        actions: <Widget>[
          IconButton(
            tooltip: '加入书架',
            onPressed: () {},
            icon: const Icon(Icons.collections_bookmark_outlined, size: 21),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (_) {},
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'settings', child: Text('阅读设置')),
              PopupMenuItem<String>(value: 'toc', child: Text('目录')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, Gap.xl),
        children: <Widget>[
          Row(
            children: <Widget>[
              const AppTag('外刊', tone: AppTagTone.primary),
              const SizedBox(width: Gap.xs),
              const AppTag('B2'),
              const Spacer(),
              Text('已读 62%',
                  style: TextStyle(fontSize: 11, color: skin.inkSoft)),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text('The College of Magic',
              style: TextStyle(
                fontSize: 25,
                height: 1.2,
                letterSpacing: -0.5,
                fontWeight: FontWeight.w900,
                color: skin.ink,
              )),
          const SizedBox(height: 4),
          Text('魔法学院让普通孩子变身自信的戴高帽魔术师',
              style: TextStyle(fontSize: 13, color: skin.inkSoft)),
          const SizedBox(height: Gap.md),
          Text(
            'The college of magic turns ordinary kids into confident '
            'magicians. Every summer, hundreds of children arrive with '
            'nothing but a suitcase and a letter.',
            style: TextStyle(fontSize: 16, height: 1.9, color: skin.ink),
          ),
          const SizedBox(height: Gap.sm),
          Container(
            padding: const EdgeInsets.all(Gap.sm),
            decoration: BoxDecoration(
              color: skin.surfaceAlt,
              borderRadius: BorderRadius.circular(skin.controlRadius),
            ),
            child: Text(
              '译:这所魔法学院把普通孩子变成了自信的魔术师。每个夏天,'
              '几百个孩子只带着一只行李箱和一封信来到这里。',
              style: TextStyle(
                  fontSize: 12.5, height: 1.6, color: skin.inkSoft),
            ),
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            spacing: Gap.xs,
            children: <Widget>[
              const AppTag('点词查询', icon: Icons.touch_app_outlined),
              const AppTag('逐段翻译', icon: Icons.translate),
              AppTag('生词 18 个', tone: AppTagTone.primary),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: skin.pageBg,
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, Gap.md),
        child: Row(
          children: <Widget>[
            _readerPill(skin, Icons.translate, '翻译', primary: true),
            const SizedBox(width: Gap.xs),
            _readerPill(skin, Icons.forum_outlined, '追问'),
            const SizedBox(width: Gap.xs),
            _readerPill(skin, Icons.bookmark_border, '收藏'),
            const Spacer(),
            _readerPill(skin, Icons.more_horiz, '更多'),
          ],
        ),
      ),
    );
  }
}

class _CategoryPreview extends StatelessWidget {
  const _CategoryPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            V4DetailHeader(
              domain: GraphicDomain.science,
              title: '科学与技术',
              subtitle: '前沿科技、医学与太空 —— 读得动的最新材料',
              actions: <Widget>[
                V4IconAction(
                  icon: Icons.refresh_rounded,
                  tooltip: '重新找',
                  onTap: () {},
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Gap.page, Gap.md, Gap.page, Gap.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const AppSectionHeader(title: '在这些来源里找', indexLabel: '01'),
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: Gap.xs,
                    children: const <Widget>[
                      AppTag('公版书', tone: AppTagTone.primary),
                      AppTag('外媒'),
                      AppTag('论文'),
                      AppTag('官方检索'),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  Text('找到 3 篇 · 按难度 B2 排序',
                      style: TextStyle(fontSize: 11.5, color: skin.inkSoft)),
                  const SizedBox(height: Gap.sm),
                  const AppWideCard(
                    title: 'How CRISPR Is Changing Medicine',
                    subtitle: '外媒 · 10 分钟 · 预计 B2',
                    tags: <Widget>[
                      AppTag('B2', tone: AppTagTone.primary),
                      AppTag('科学'),
                    ],
                    seed: 'CRISPR',
                    kind: 'news',
                  ),
                  const AppWideCard(
                    title: 'The Origins of the Universe',
                    subtitle: '论文 · 15 分钟 · 预计 C1',
                    tags: <Widget>[
                      AppTag('C1', tone: AppTagTone.primary),
                      AppTag('论文'),
                    ],
                    seed: 'Universe',
                    kind: 'paper',
                  ),
                  const SizedBox(height: Gap.sm),
                  AppCard(
                    variant: AppCardVariant.compact,
                    onTap: () {},
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.auto_awesome, size: 19, color: skin.accent),
                        const SizedBox(width: Gap.xs),
                        const Expanded(
                          child: Text(
                            '用中文说需求,让 AI 去公开源找科学与技术的材料',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: skin.inkFaint),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 封面样张:同一批材料在 5 种真实尺寸下
// ══════════════════════════════════════════════════════════════════

class _CoverSheet extends StatelessWidget {
  const _CoverSheet({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    const samples = <(String, String, String?)>[
      ('随着疫情蔓延,美国麻疹病例数比去年增加一倍以上', 'news', 'B2'),
      ('The Elements of Style', 'book', 'C1'),
      ('Attention Is All You Need', 'paper', 'C1'),
      ('TED Talks Daily', 'podcast', 'B1'),
      ('Photosynthesis', 'wiki', 'B2'),
      ('Moby Dick', 'book', 'C1'),
    ];
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.xs),
          child: Row(
            children: <Widget>[
              Text(title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: skin.ink,
                  )),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Container(height: 0.8, color: skin.hairline),
              ),
            ],
          ),
        );
    Widget cover(int i, {required double w, required double h}) =>
        MaterialCover(
          seed: samples[i].$1,
          kind: samples[i].$2,
          levelLabel: samples[i].$3,
          width: w,
          height: h,
          radius: 12,
        );
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.md),
          children: <Widget>[
            Text('材料封面 · 样张',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: skin.ink,
                  letterSpacing: -0.6,
                )),
            const SizedBox(height: 2),
            Text('印刷封面语言:糖果纸面 + 域色书脊 + 墨字 + 白玻璃徽标',
                style: TextStyle(fontSize: 11.5, color: skin.inkSoft)),
            section('列表缩略 · 42×54'),
            Row(
              children: <Widget>[
                for (var i = 0; i < 6; i++) ...<Widget>[
                  cover(i, w: 42, h: 54),
                  const SizedBox(width: 7),
                ],
              ],
            ),
            section('书架 · 96×128(真图:豆瓣书封自动抓取)'),
            Row(
              children: <Widget>[
                for (var i = 0; i < 3; i++) ...<Widget>[
                  Column(
                    children: <Widget>[
                      MaterialCover(
                        seed: samples[i].$1,
                        kind: samples[i].$2,
                        levelLabel: samples[i].$3,
                        localImagePath: _samplePath('book_${i + 1}.jpg'),
                        width: 96,
                        height: 128,
                        radius: 14,
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 96,
                        child: Text(
                          samples[i].$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9, color: skin.inkSoft),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                ],
              ],
            ),
            section('横卡 · 88×88'),
            Row(
              children: <Widget>[
                for (var i = 2; i < 5; i++) ...<Widget>[
                  cover(i, w: 88, h: 88),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            section('今日精读 · 340×150(真图:360 插图自动抓取)'),
            const SizedBox(height: 2),
            MaterialCover(
              seed: '随着疫情蔓延,美国麻疹病例数比去年增加一倍以上',
              kind: 'news',
              levelLabel: 'B2',
              localImagePath: _samplePath('art_1.jpg'),
              width: 340,
              height: 150,
              radius: 18,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 第 2 批内页:书架 / 收藏夹
// ══════════════════════════════════════════════════════════════════

class _BookshelfPreview extends StatelessWidget {
  const _BookshelfPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    const books = <(String, String, String)>[
      ('The Elements of Style', 'book_1.jpg', 'C1'),
      ('Moby Dick', 'book_2.jpg', 'B2'),
      ('The Great Gatsby', 'book_3.jpg', 'B2'),
      ('Walden', 'book_4.jpg', 'C1'),
    ];
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            V4DetailHeader(
              domain: GraphicDomain.book,
              title: '书架',
              subtitle: '共 12 本 · 在读 3 · 已读完 6',
              actions: <Widget>[
                V4IconAction(
                  icon: Icons.swap_vert,
                  tooltip: '排列',
                  onTap: () {},
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Gap.page, Gap.md, Gap.page, Gap.xl),
                children: <Widget>[
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: Gap.xs,
                    children: const <Widget>[
                      AppTag('全部 12', tone: AppTagTone.primary),
                      AppTag('在读 3'),
                      AppTag('已读完 6'),
                      AppTag('已搁置 3'),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.md,
                    children: <Widget>[
                      for (final b in books)
                        SizedBox(
                          width: 165,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              MaterialCover(
                                seed: b.$1,
                                kind: 'book',
                                levelLabel: b.$3,
                                localImagePath: _samplePath(b.$2),
                                width: 165,
                                height: 220,
                                radius: 16,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                b.$1,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: skin.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text('已读 38% · 约 46 分钟',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: skin.inkSoft)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  Text('点一本书继续读,长按可以移出书架或看封面',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: skin.inkFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarksPreview extends StatelessWidget {
  const _BookmarksPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    const marks = <(String, String, String)>[
      (
        'The college of magic turns ordinary kids into confident magicians.',
        '阅读器 · 今天 09:12',
        '外刊 · The College of Magic',
      ),
      (
        'Rather than a single breakthrough, progress came from many small improvements.',
        '追问 · 昨天 21:40',
        '助理回答 · 关于写作',
      ),
      (
        'ubiquitous',
        '词条 · 昨天 20:05',
        '词汇本 · 生词',
      ),
    ];
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const V4DetailHeader(
              domain: GraphicDomain.note,
              title: '收藏夹',
              subtitle: '追问、词条、阅读记录都归在这里,按来源找回来',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Gap.page, Gap.md, Gap.page, Gap.xl),
                children: <Widget>[
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: Gap.xs,
                    children: const <Widget>[
                      AppTag('全部 18', tone: AppTagTone.primary),
                      AppTag('阅读 7'),
                      AppTag('追问 6'),
                      AppTag('词条 5'),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  for (final m in marks)
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(Icons.format_quote_rounded,
                                  size: 18, color: skin.accent),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  m.$3,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: skin.inkSoft,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  size: 18, color: skin.inkFaint),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            m.$1,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.55,
                              color: skin.ink,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              AppTag(m.$2),
                              const Spacer(),
                              Icon(Icons.star_rounded,
                                  size: 18, color: skin.accent),
                            ],
                          ),
                        ],
                      ),
                    ),
                  AppCard(
                    variant: AppCardVariant.compact,
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.tune, size: 18, color: skin.accent),
                        const SizedBox(width: Gap.xs),
                        const Expanded(
                          child: Text('按来源筛选、批量整理',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Icon(Icons.chevron_right,
                            size: 18, color: skin.inkFaint),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 第 2 批内页:生词本 / 词条详情
// ══════════════════════════════════════════════════════════════════

class _VocabListPreview extends StatelessWidget {
  const _VocabListPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    const words = <(String, String, String, String)>[
      ('ubiquitous', '/juːˈbɪkwɪtəs/', 'adj. 无处不在的', '学习中'),
      ('serendipity', '/ˌserənˈdɪpəti/', 'n. 意外发现珍奇事物的运气', '已掌握'),
      ('resilient', '/rɪˈzɪliənt/', 'adj. 有韧性的;能恢复的', '新词'),
      ('take for granted', '', '认为理所当然', '学习中'),
    ];
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const V4DetailHeader(
              domain: GraphicDomain.language,
              title: '生词本',
              subtitle: '共 128 个生词 · 点词看详情,长按可多选',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, 0),
              child: Wrap(
                spacing: Gap.xs,
                runSpacing: Gap.xs,
                children: const <Widget>[
                  AppTag('全部 128', tone: AppTagTone.primary),
                  AppTag('单词 96'),
                  AppTag('短语 24'),
                  AppTag('句子 8'),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Gap.page, Gap.sm, Gap.page, Gap.xl),
                children: <Widget>[
                  for (var i = 0; i < words.length; i++)
                    AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Text(
                                      words[i].$1,
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: skin.ink,
                                      ),
                                    ),
                                    const SizedBox(width: Gap.xs),
                                    AppTag(
                                      words[i].$4,
                                      tone: i % 2 == 1
                                          ? AppTagTone.success
                                          : AppTagTone.neutral,
                                    ),
                                  ],
                                ),
                                if (words[i].$2.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(words[i].$2,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: skin.inkSoft)),
                                ],
                                const SizedBox(height: 4),
                                Text(words[i].$3,
                                    style: TextStyle(
                                        fontSize: 12.5, color: skin.inkSoft)),
                              ],
                            ),
                          ),
                          Icon(Icons.volume_up_outlined,
                              size: 18, color: skin.accent),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VocabDetailPreview extends StatelessWidget {
  const _VocabDetailPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    Widget infoRow(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 68,
                child: Text(label,
                    style: TextStyle(fontSize: 12, color: skin.inkFaint)),
              ),
              Expanded(
                child: Text(value,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: skin.ink)),
              ),
            ],
          ),
        );
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            V4DetailHeader(
              domain: GraphicDomain.language,
              title: 'ubiquitous',
              subtitle: '生词详情 · 出现 2 次',
              actions: <Widget>[
                V4IconAction(
                  icon: Icons.volume_up_outlined,
                  tooltip: '朗读',
                  onTap: () {},
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Gap.page, Gap.md, Gap.page, Gap.xl),
                children: <Widget>[
                  Text('/juːˈbɪkwɪtəs/',
                      style: TextStyle(
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          color: skin.inkSoft)),
                  const SizedBox(height: 4),
                  Text('adj. 无处不在的,普遍存在的',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: skin.ink)),
                  const SizedBox(height: Gap.md),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('基本信息',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: skin.ink)),
                        const SizedBox(height: 4),
                        infoRow('类型', '单词'),
                        infoRow('出处', '外刊 · The College of Magic'),
                        infoRow('添加时间', '11月2日 21:08'),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  Text('原文例句',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: skin.ink)),
                  const SizedBox(height: Gap.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: skin.surfaceAlt,
                      borderRadius: BorderRadius.circular(skin.controlRadius),
                    ),
                    child: Text(
                      'Smartphones have become ubiquitous in daily life.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        fontStyle: FontStyle.italic,
                        color: skin.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                  Text('掌握程度',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: skin.ink)),
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: <Widget>[
                      for (var i = 0; i < 3; i++) ...<Widget>[
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: i == 1
                                  ? Color.alphaBlend(
                                      skin.accent.withValues(alpha: 0.14),
                                      skin.surface)
                                  : skin.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: i == 1
                                    ? skin.accent
                                    : skin.hairline,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                const <String>['新词', '学习中', '已掌握'][i],
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: i == 1
                                      ? skin.accent
                                      : skin.inkSoft,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (i < 2) const SizedBox(width: Gap.xs),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 主屏补全:助理 / 我的 / 复习
// ══════════════════════════════════════════════════════════════════

class _TutorPreview extends StatelessWidget {
  const _TutorPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            V4HeroHeader(
              domain: GraphicDomain.academic,
              eyebrow: '诊断 · 规划 · 复盘',
              title: '学习助理',
              subtitle: '先问清楚你的目标和水平,再给能执行的建议',
              chips: const <Widget>[
                V4GlassChip(
                  icon: Icons.insights_outlined,
                  label: '本地诊断,不花 API',
                ),
              ],
              actions: <Widget>[
                V4IconAction(
                    icon: Icons.block, tooltip: '不想看的题材', onTap: () {}),
                V4IconAction(
                    icon: Icons.refresh, tooltip: '重新诊断', onTap: () {}),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Gap.page, Gap.md, Gap.page, Gap.xl),
                children: <Widget>[
                  AppCard(
                    color: Color.alphaBlend(
                        skin.accent.withValues(alpha: 0.08), skin.surface),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(Icons.record_voice_over_outlined,
                                size: 18, color: skin.accent),
                            const SizedBox(width: 6),
                            Text('先聊两句,一分钟',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: skin.ink)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text('告诉我目标、每天能学多久、喜欢读什么,'
                            '建议才有依据',
                            style: TextStyle(fontSize: 12, height: 1.5)),
                        const SizedBox(height: Gap.sm),
                        Wrap(
                          spacing: Gap.xs,
                          children: const <Widget>[
                            AppTag('四六级'),
                            AppTag('每天 20 分钟'),
                            AppTag('外刊'),
                          ],
                        ),
                        const SizedBox(height: Gap.sm),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {},
                            child: const Text('开始访谈'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const AppSectionHeader(title: '现状分析', indexLabel: '01'),
                  for (final d in const <(String, String, String)>[
                    ('词汇', '约 4,200 词 · B2', '先补高频 500 词'),
                    ('语法', '时态错误最多', '已归档 7 类错误'),
                    ('输出', '本周 0 次', '从写句开始'),
                  ])
                    AppCard(
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(d.$1,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: skin.ink)),
                                const SizedBox(height: 2),
                                Text(d.$2,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: skin.inkSoft)),
                              ],
                            ),
                          ),
                          AppTag(d.$3),
                        ],
                      ),
                    ),
                  const SizedBox(height: Gap.sm),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('让 AI 排规划'),
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {},
                          child: const Text('去复习'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMainPreview extends StatelessWidget {
  const _ProfileMainPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            V4HeroHeader(
              domain: GraphicDomain.custom,
              eyebrow: '学习资产 · 数据 · 设置',
              title: '我的',
              subtitle: '词库、统计、备份都在这里;数据只存在这台手机上',
              chips: const <Widget>[
                V4GlassChip(
                    icon: Icons.menu_book_outlined, label: '生词 128'),
                V4GlassChip(
                    icon: Icons.local_fire_department_outlined,
                    label: '连续 12 天'),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Gap.page, Gap.md, Gap.page, Gap.xl),
                children: <Widget>[
                  AppCard(
                    variant: AppCardVariant.hero,
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const CircleAvatar(
                              radius: 22,
                              child: Icon(Icons.person_rounded, size: 24),
                            ),
                            const SizedBox(width: Gap.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text('学习者',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: skin.ink)),
                                  Text('目标 四六级 · 难度 B2',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: skin.inkSoft)),
                                ],
                              ),
                            ),
                            AppTag('已测', tone: AppTagTone.success),
                          ],
                        ),
                        const SizedBox(height: Gap.md),
                        Row(
                          children: const <Widget>[
                            Expanded(child: AppStat(value: '128', label: '生词')),
                            Expanded(child: AppStat(value: '12', label: '连续天')),
                            Expanded(child: AppStat(value: '36', label: '练习')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const AppSectionHeader(title: '学习', indexLabel: '01'),
                  AppActionTile(
                    icon: Icons.book,
                    title: '我的生词本',
                    subtitle: '按书籍分组',
                    onTap: () {},
                  ),
                  AppActionTile(
                    icon: Icons.style,
                    title: '复习模式',
                    subtitle: '抽认卡记忆',
                    onTap: () {},
                  ),
                  AppActionTile(
                    icon: Icons.star_outline,
                    title: '收藏夹',
                    subtitle: '收藏的洞见与好句',
                    onTap: () {},
                  ),
                  const AppSectionHeader(title: '数据与回顾', indexLabel: '02'),
                  AppActionTile(
                    icon: Icons.bar_chart,
                    title: '学习统计',
                    subtitle: '趋势与热力图',
                    onTap: () {},
                  ),
                  AppActionTile(
                    icon: Icons.insights,
                    title: '本周报告',
                    subtitle: '这周做了什么、下周改什么',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewPreview extends StatelessWidget {
  const _ReviewPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            V4DetailHeader(
              domain: GraphicDomain.exam,
              title: '今日复习',
              subtitle: '按记忆强度排的到期队列,先过该忘的',
              actions: <Widget>[
                V4IconAction(
                    icon: Icons.refresh, tooltip: '重新计算队列', onTap: () {}),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    Gap.page, Gap.md, Gap.page, Gap.xl),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('第 3 / 18 个',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: skin.ink)),
                      const Spacer(),
                      Text('预计 6 分钟',
                          style: TextStyle(
                              fontSize: 11.5, color: skin.inkSoft)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: 3 / 18,
                      minHeight: 6,
                      backgroundColor: skin.surfaceAlt,
                      color: skin.accent,
                    ),
                  ),
                  const SizedBox(height: Gap.md),
                  AppCard(
                    variant: AppCardVariant.hero,
                    child: Column(
                      children: <Widget>[
                        AppTag('复习中 · 到期 2 天',
                            tone: AppTagTone.warning),
                        const SizedBox(height: Gap.md),
                        Text('ubiquitous',
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: skin.ink,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 4),
                        Text('/juːˈbɪkwɪtəs/',
                            style: TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: skin.inkSoft)),
                        const SizedBox(height: Gap.md),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: skin.surfaceAlt,
                            borderRadius:
                                BorderRadius.circular(skin.controlRadius),
                          ),
                          child: Text(
                            'adj. 无处不在的,普遍存在的',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: skin.ink),
                          ),
                        ),
                        const SizedBox(height: Gap.md),
                        Row(
                          children: <Widget>[
                            for (var i = 0; i < 3; i++) ...<Widget>[
                              Expanded(
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: i == 0
                                        ? Color.alphaBlend(
                                            const Color(0xFFFF8FA3)
                                                .withValues(alpha: 0.16),
                                            skin.surface)
                                        : skin.surfaceAlt,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: skin.hairline),
                                  ),
                                  child: Center(
                                    child: Text(
                                      const <String>[
                                        '忘记了',
                                        '有点模糊',
                                        '记得'
                                      ][i],
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        color: i == 0
                                            ? const Color(0xFFB03A56)
                                            : skin.inkSoft,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (i < 2) const SizedBox(width: Gap.xs),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 输入链路收尾:识图结果 / 导入材料 / 读后测验
// ══════════════════════════════════════════════════════════════════

class _ChatResultPreview extends StatelessWidget {
  const _ChatResultPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    const words = <(String, String, String)>[
      ('ubiquitous', 'adj. 无处不在的', '已选'),
      ('serendipity', 'n. 意外发现珍奇事物的运气', '已选'),
      ('resilient', 'adj. 有韧性的', '未选'),
      ('diligent', 'adj. 勤勉的', '已选'),
    ];
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: '识别结果 · 12 个生词',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 0),
            child: AppCard(
              variant: AppCardVariant.compact,
              child: Row(
                children: <Widget>[
                  Icon(Icons.image_outlined, size: 18, color: skin.accent),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('来自 2 张照片 · 已自动去重、查词典',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ),
                  const AppTag('可编辑', tone: AppTagTone.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.xs),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Gap.page, Gap.xs, Gap.page, Gap.xl),
              children: <Widget>[
                for (final w in words)
                  AppCard(
                    child: Row(
                      children: <Widget>[
                        Icon(
                          w.$3 == '已选'
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 20,
                          color: w.$3 == '已选' ? skin.accent : skin.inkFaint,
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
            padding: const EdgeInsets.fromLTRB(
                Gap.page, Gap.sm, Gap.page, Gap.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('保存 8 个生词到词库'),
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

class _ImportSheetPreview extends StatelessWidget {
  const _ImportSheetPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    const channels = <(IconData, String, String)>[
      (Icons.photo_library_outlined, '拍照 / 相册', '拍书页、截图或文章,自动取词'),
      (Icons.link, '粘贴链接', '网页、论文、外刊链接都行'),
      (Icons.upload_file, '本地文件', 'txt / md / epub 导入'),
      (Icons.edit_note, '粘贴文字', '复制一段文字直接导入'),
    ];
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: Column(
        children: <Widget>[
          // 背景示意(底部弹层的上一层页面)
          Expanded(
            child: Container(
              color: skin.pageBg,
              alignment: Alignment.center,
              child: Text('材料中心',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: skin.ink.withValues(alpha: 0.25))),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30)),
              boxShadow: skin.heroShadow,
            ),
            padding: const EdgeInsets.fromLTRB(
                Gap.page, Gap.sm, Gap.page, Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: skin.hairline,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.md),
                Text('导入材料',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: skin.ink)),
                const SizedBox(height: 2),
                Text('四种方式最后都进同一个材料库',
                    style: TextStyle(fontSize: 11.5, color: skin.inkSoft)),
                const SizedBox(height: Gap.md),
                for (final c in channels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.xs),
                    child: Container(
                      padding: const EdgeInsets.all(Gap.sm),
                      decoration: BoxDecoration(
                        color: skin.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: skin.hairline),
                      ),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: skin.surfaceAlt,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(c.$1, size: 20, color: skin.accent),
                          ),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(c.$2,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: skin.ink)),
                                const SizedBox(height: 2),
                                Text(c.$3,
                                    style: TextStyle(
                                        fontSize: 11, color: skin.inkSoft)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              size: 18, color: skin.inkFaint),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: Gap.xs),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizPreview extends StatelessWidget {
  const _QuizPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: '读后测验 · 3/8',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: 3 / 8,
            minHeight: 4,
            backgroundColor: skin.surfaceAlt,
            color: skin.accent,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Gap.page, Gap.md, Gap.page, Gap.xl),
        children: <Widget>[
          const AppTag('词义选择 · 来自刚读的文章', tone: AppTagTone.primary),
          const SizedBox(height: Gap.sm),
          AppCard(
            variant: AppCardVariant.hero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('选出原文里 “ubiquitous” 的意思',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: skin.ink,
                        height: 1.5)),
                const SizedBox(height: Gap.md),
                for (var i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.xs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Gap.md, vertical: 13),
                      decoration: BoxDecoration(
                        color: i == 1
                            ? Color.alphaBlend(
                                skin.accent.withValues(alpha: 0.12),
                                skin.surface)
                            : skin.surfaceAlt,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: i == 1 ? skin.accent : skin.hairline,
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Text(
                            String.fromCharCode(65 + i),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: i == 1 ? skin.accent : skin.inkSoft,
                            ),
                          ),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Text(
                              const <String>[
                                '到处都在的,普遍存在的',
                                '难以理解的',
                                '短暂出现的',
                                '令人愉快的',
                              ][i],
                              style: TextStyle(
                                  fontSize: 13.5, color: skin.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: Gap.xs),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: () {}, child: const Text('提交答案')),
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
// 风格板
// ══════════════════════════════════════════════════════════════════

class _StyleBoard extends StatelessWidget {
  const _StyleBoard();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, Gap.xl),
      children: <Widget>[
        Text('明亮果冻 · 风格板',
            style: AppFont.displayStyle.copyWith(
                color: skin.ink, fontSize: 26, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('大圆角 / 柔和渐变 / 彩色软阴影 / 玻璃浮层',
            style: AppFont.tagStyle.copyWith(color: skin.inkSoft)),
        const SizedBox(height: Gap.md),
        Row(
          children: <Widget>[
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 3 ? 0 : 6),
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: skin.pastelFill(i),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.md),
        Wrap(spacing: Gap.xs, runSpacing: Gap.xs, children: <Widget>[
          AppTag('B2', tone: AppTagTone.primary),
          AppTag('已掌握', tone: AppTagTone.success),
          AppTag('复习中'),
          AppTag('待注意', tone: AppTagTone.warning),
          AppTag('超时', tone: AppTagTone.danger),
        ]),
        const SizedBox(height: Gap.md),
        Row(
          children: <Widget>[
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('开始阅读'),
            ),
            const SizedBox(width: Gap.xs),
            OutlinedButton(onPressed: () {}, child: const Text('稍后')),
            const Spacer(),
            AppProgressRing(value: 0.65, centerText: '65%', size: 52, stroke: 6),
          ],
        ),
        const SizedBox(height: Gap.md),
        V4Empty(
          icon: Icons.auto_stories_outlined,
          title: '还没有读过的材料',
          hint: '按你的目标和难度档找一篇开始读,题目会从你读过的内容里出。',
          domain: GraphicDomain.news,
          action: FilledButton(
              onPressed: () {}, child: const Text('去找材料')),
        ),
        const SizedBox(height: Gap.md),
        const V4Skeleton(lines: 3),
      ],
    );
  }
}

class _DarkPreview extends StatelessWidget {
  const _DarkPreview();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Theme(
      data: Theme.of(context),
      child: SizedBox(
        width: 414,
        height: 896,
        child: Scaffold(
          backgroundColor: skin.pageBg,
          body: V4PageScaffold(
            domain: GraphicDomain.news,
            eyebrow: 'NOV 03 · MONDAY',
            title: '输入',
            subtitle: '读和写,才是输入。找不到想读的,去材料中心挑一篇。',
            showAppBarBack: false,
            actions: <Widget>[
              V4PillButton(
                label: '材料中心',
                light: true,
                icon: Icons.explore_outlined,
                onTap: () {},
              ),
            ],
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                V4TopicTabs(
                  topics: v4TopicsFrom(const <({String id, String label})>[
                    (id: 'sci_tech', label: '科技'),
                    (id: 'business', label: '商业'),
                    (id: 'health', label: '健康'),
                    (id: 'culture', label: '文化'),
                  ]),
                  selectedId: 'sci_tech',
                  onSelected: (_) {},
                ),
                const SizedBox(height: Gap.sm),
                const V4StageCard(
                  title: '写词',
                  subtitle: '语境填空 · 按目标词表',
                  levelLabel: 'Lv1',
                  domain: GraphicDomain.exam,
                  progress: 0.72,
                  ctaLabel: '继续',
                ),
                const V4StageCard(
                  title: '写句',
                  subtitle: '改写 · 纠错 · 连词成句',
                  levelLabel: 'Lv2',
                  domain: GraphicDomain.language,
                  progress: 0.35,
                  ctaLabel: '继续',
                ),
                const V4SectionTitle(indexLabel: '01', title: '在读材料'),
                V4ListCard(
                  title: '随着疫情蔓延,美国麻疹病例数比去年增加一倍以上',
                  subtitle: '外刊 · 8 分钟 · 覆盖率 68%',
                  domain: GraphicDomain.news,
                ),
              ],
            ),
          ),
          bottomNavigationBar: ReadFlowBottomNav(
            currentTab: ReadFlowTab.input,
            onTabChanged: (_) {},
          ),
        ),
      ),
    );
  }
}
