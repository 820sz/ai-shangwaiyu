import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/widgets/app_ui.dart';
import 'package:readflow/widgets/design_kit.dart';
import 'package:readflow/widgets/empty_state.dart';
import 'package:readflow/widgets/graphics/graphics.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 空态组件接入空态图形的**预览图导出 + 兼容性测试**(批 1 · B1-4)。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 为什么用测试来"生成预览图"(与 `test/graphics_preview_test.dart` 同理):
/// 1. 组件是 Flutter 画的,只有真的 pump 一遍才算验证过 —— 导出图的同时把
///    "明暗两套都不抛异常"也断言了,图与验收合一;
/// 2. 渲染环境与真机一致(同一套 Theme / 同一套自定义图形);
/// 3. 产物落 `build/graphics_preview/`(build 不进 git),随时可重跑。
///
/// 产物:`build/graphics_preview/empty_widgets.png`
/// - 上排:浅色;下排:深色;每排 3 格 = AppEmptyState(96)/ AppEmpty(72)/
///   EmptyState(96)。每格下面标注"旧 icon → 自动映射到的图形",方便验收
///   语义归并是否符合预期。
///
/// 运行:`flutter test test/empty_state_preview_test.dart`
///
/// 注:测试环境默认只有 Ahem 字体(汉字都是方块),所以这里从系统里读一个中文
/// 字体注册成预览字体 —— 只影响测试渲染,不进 App 包体。找不到字体时退化成
/// 方块,测试仍然通过(图形本身是准的)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _outDir.createSync(recursive: true);
    await _loadPreviewFont();
  });

  // ── 预览图 ──────────────────────────────────────────────────────────
  testWidgets('导出空态三组件预览(明暗各一次)', (tester) async {
    _prepareSurface(tester);
    final key = GlobalKey();
    await tester.pumpWidget(_page(key: key));
    expect(tester.takeException(), isNull, reason: '空态组件渲染抛异常');
    await _capture(tester, key, 'empty_widgets.png');
  });

  // ── 向后兼容(旧调用点一行不改也必须能用)────────────────────────────
  testWidgets('不传 art 时按 icon 语义自动选图;传 art 时以 art 为准', (tester) async {
    await tester.pumpWidget(
      _page(
        key: GlobalKey(),
        child: SingleChildScrollView(
          // 4 个空态叠一起会超过测试视口高度:滚动容器兜底,
          // 这里验的是"旧调用点不传 art 也能渲染",不是布局
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 旧写法(只传 icon/title/hint):三个组件都必须仍然可用
              const AppEmpty(
                icon: Icons.search_off,
                title: '没搜到',
                hint: '换个词',
              ),
              const AppEmptyState(icon: Icons.menu_book, title: '还没有内容'),
              const EmptyState(icon: Icons.translate, title: '词库为空'),
              // 显式 art 必须压过 icon 的语义
              const AppEmpty(
                icon: Icons.search_off,
                art: EmptyArtKind.paperPlane,
                title: '显式指定',
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final kinds = tester
        .widgetList<EmptyArt>(find.byType(EmptyArt))
        .map((art) => art.kind)
        .toList();
    expect(
      kinds,
      <EmptyArtKind>[
        EmptyArtKind.magnifier, // search_off
        EmptyArtKind.floatingPages, // menu_book
        EmptyArtKind.scatteredLetters, // translate
        EmptyArtKind.paperPlane, // 显式 art 优先于 icon 语义
      ],
      reason: '旧调用点的语义映射 / 显式 art 优先级不对',
    );
  });

  // ── fromIcon 语义归并规则(兼容层的唯一出口,必须锁住)────────────────
  group('EmptyArtKind.fromIcon 语义映射', () {
    test('搜索/查找 → 放大镜(空的原因是"没搜到")', () {
      for (final icon in <IconData>[
        Icons.search,
        Icons.search_off,
        Icons.zoom_in,
        Icons.find_in_page,
        Icons.travel_explore,
        Icons.travel_explore_outlined,
      ]) {
        expect(EmptyArtKind.fromIcon(icon), EmptyArtKind.magnifier);
      }
    });

    test('内容/收藏/列表/历史 → 漂浮书页(空的原因是"还没有内容")', () {
      for (final icon in <IconData>[
        Icons.inbox,
        Icons.inbox_outlined,
        Icons.library_books_outlined,
        Icons.menu_book,
        Icons.auto_stories_outlined,
        Icons.article_outlined,
        Icons.folder_outlined,
        Icons.list,
        Icons.history,
        Icons.history_edu_outlined,
        Icons.bookmark_border,
        Icons.star_border,
      ]) {
        expect(EmptyArtKind.fromIcon(icon), EmptyArtKind.floatingPages);
      }
    });

    test('网络/故障/刷新 → 纸飞机(空的原因是"还没连上/还没开始")', () {
      for (final icon in <IconData>[
        Icons.cloud_off,
        Icons.wifi_off,
        Icons.error_outline,
        Icons.refresh,
        Icons.sync_problem,
      ]) {
        expect(EmptyArtKind.fromIcon(icon), EmptyArtKind.paperPlane);
      }
    });

    test('语言/文字 → 散落字母(词库为空、翻译/语言相关)', () {
      for (final icon in <IconData>[
        Icons.translate,
        Icons.abc,
        Icons.spellcheck,
        Icons.text_fields,
        Icons.language,
      ]) {
        expect(EmptyArtKind.fromIcon(icon), EmptyArtKind.scatteredLetters);
      }
    });

    test('未知图标 / null → 波纹兜底(不猜语义)', () {
      expect(EmptyArtKind.fromIcon(Icons.settings), EmptyArtKind.generic);
      expect(EmptyArtKind.fromIcon(Icons.widgets_outlined), EmptyArtKind.generic);
      expect(EmptyArtKind.fromIcon(null), EmptyArtKind.generic);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// 预览图排版
// ═══════════════════════════════════════════════════════════════════════

final Directory _outDir = Directory('build/graphics_preview');

/// 预览用中文字体族(不进 App 包体,只给测试渲染)
const String _fontFamily = 'PreviewCJK';

/// 是否成功加载了预览字体(否则标签退化成方块)
bool _previewFontLoaded = false;

String get _labelFamily => _previewFontLoaded ? _fontFamily : 'Roboto';

/// 从系统字体里找一个中文字体注册给测试环境(顺序同 graphics_preview_test)。
Future<void> _loadPreviewFont() async {
  const candidates = <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\simkai.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(_fontFamily)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      _previewFontLoaded = true;
      return;
    } catch (_) {
      // 字体格式不支持(FontLoader 只吃 ttf/otf):换下一个候选
    }
  }
}

/// 把测试画布调大,避免预览内容超出视口被裁
void _prepareSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1260, 1180);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 预览页外壳。
///
/// 不用 MaterialApp:它会套 AnimatedTheme 做 200ms 明暗过渡,第一帧的
/// brightness 可能还是旧的(theme_test 里踩过同样的坑);这里直接给确定的
/// Theme + MediaQuery + Directionality,一帧就是终态。
Widget _page({required GlobalKey key, Widget? child}) {
  final light = AppTheme.lightTheme;
  return MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: light.copyWith(
          textTheme: light.textTheme.apply(fontFamily: _labelFamily),
        ),
        child: DefaultTextStyle(
          // 组件的显式 TextStyle 若没指定 fontFamily(如 AppFont 系列),
          // Text 会与这里的 DefaultTextStyle 合并 → 预览图里中文才可读
          style: TextStyle(
            fontFamily: _labelFamily,
            fontSize: 12,
            color: light.colorScheme.onSurface,
          ),
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: light.scaffoldBackgroundColor,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: child ?? _widgetsPreview(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 三组件 × 明暗两排
Widget _widgetsPreview() {
  final light = AppTheme.lightTheme;
  final dark = AppTheme.darkTheme;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _title('空态三组件 · 接入空态图形(批 1 · B1-4)', light),
      _sectionLabel('浅色', light),
      _row(light),
      const SizedBox(height: 18),
      _sectionLabel('深色', light),
      _row(dark),
    ],
  );
}

Widget _row(ThemeData theme) {
  return Container(
    color: theme.scaffoldBackgroundColor,
    padding: const EdgeInsets.all(14),
    child: Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: _labelFamily),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _cell(
            theme,
            'AppEmptyState(96)\nsearch_off → 放大镜',
            AppEmptyState(
              icon: Icons.search_off,
              title: '没有找到原文',
              hint: '换个说法再试,或让 AI 换个方向找',
              action: FilledButton(
                onPressed: () {},
                // 预览字体要显式给:按钮的 textStyle 走 ButtonStyle(不继承
                // 页面 DefaultTextStyle 的 family),不给的话预览里是方块
                style: FilledButton.styleFrom(
                  textStyle: TextStyle(
                    fontFamily: _labelFamily,
                    fontSize: 12,
                  ),
                ),
                child: const Text('换个说法'),
              ),
            ),
          ),
          const SizedBox(width: 14),
          _cell(
            theme,
            'AppEmpty(72)\ninbox_outlined → 漂浮书页',
            const AppEmpty(
              icon: Icons.inbox_outlined,
              title: '还没有存档',
              hint: '收藏的对话会出现在这里',
            ),
          ),
          const SizedBox(width: 14),
          _cell(
            theme,
            'EmptyState(96)\nauto_stories_outlined → 漂浮书页',
            const EmptyState(
              icon: Icons.auto_stories_outlined,
              title: '词库还是空的',
              hint: '在阅读器里点词即可收藏',
            ),
          ),
        ],
      ),
    ),
  );
}

/// 一格:卡片底 + 固定舞台上放组件 + 下方标注(旧 icon → 图形)
Widget _cell(ThemeData theme, String caption, Widget child) {
  return Container(
    width: 360,
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
    decoration: BoxDecoration(
      color: theme.cardTheme.color,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // 固定舞台高度:三个组件高度不同,给统一容器才能横向对齐比较
        // (v4 果冻按钮变高到 52,舞台从 300 提到 320)
        SizedBox(height: 320, child: Center(child: child)),
        const SizedBox(height: 6),
        Text(
          caption,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: _labelFamily,
            fontSize: 11,
            height: 1.35,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

Widget _title(String text, ThemeData theme) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: _labelFamily,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
    ),
  );
}

Widget _sectionLabel(String text, ThemeData theme) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: _labelFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 截图(与 graphics_preview_test 同一套写法)
// ═══════════════════════════════════════════════════════════════════════

/// 把 [key] 对应的 RepaintBoundary 导出成 PNG(2x,视网膜可读)
Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String fileName,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(data, isNotNull, reason: '$fileName 编码失败');
      File('${_outDir.path}/$fileName')
          .writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
  final file = File('${_outDir.path}/$fileName');
  expect(file.existsSync(), isTrue, reason: '预览图没有落盘:${file.path}');
  // 阈值防"空图":一张上千像素见方的 PNG 不可能只有几百字节
  expect(file.lengthSync(), greaterThan(2048),
      reason: '$fileName 太小,说明内容没画出来');
  debugPrint('预览图已生成: ${file.absolute.path} (${file.lengthSync()} bytes)');
}
