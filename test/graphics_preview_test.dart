import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/widgets/graphics/graphics.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 图形资产的**预览图导出测试**(v2.13 · 批 1)。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 为什么用测试来"生成图"而不是写个 tool/ 脚本:
/// 1. 图形是 Flutter 画的,**只有真的 pump 一遍才算验证过** —— 测试顺便把
///    "light/dark 都不抛异常" 也断言了,图和验收合一;
/// 2. 测试里的渲染环境和真机一致(同一套 CustomPainter / 同一套 Theme),
///    不像离线渲染脚本那样容易和 App 里长得不一样;
/// 3. 产物落在 `build/graphics_preview/`(build 目录不进 git),随时可重跑。
///
/// 产物:
/// - `domains_light.png` / `domains_dark.png`  13 个领域图形(96px,带中文名)
/// - `covers.png`                              7 种材料封面(3:4 一行 + 16:9 一行)
/// - `empties.png`                             5 个空态插图
/// - `data.png`                                4 个数据图形 + 输出四阶
///
/// 运行:`flutter test test/graphics_preview_test.dart`
///
/// 注:测试环境默认只有 Ahem 字体(所有汉字都是方块),所以这里**从系统里读一个
/// 中文字体**注册成预览字体 —— 只影响测试渲染,不增大 App 包体。找不到字体时
/// 退化成方块,测试仍然通过(PNG 里标签不可读,但图形本身是准的)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _outDir.createSync(recursive: true);
    await _loadPreviewFont();
  });

  testWidgets('导出领域图形预览(明/暗两套)', (tester) async {
    await _prepareSurface(tester);
    for (final dark in <bool>[false, true]) {
      final key = GlobalKey();
      await tester.pumpWidget(
        _page(key: key, dark: dark, child: _domainsGrid(dark)),
      );
      expect(tester.takeException(), isNull,
          reason: '${dark ? '深色' : '浅色'}下领域图形渲染抛异常');
      await _capture(
        tester,
        key,
        dark ? 'domains_dark.png' : 'domains_light.png',
      );
    }
  });

  testWidgets('导出材料封面预览(7 类 × 两种比例)', (tester) async {
    await _prepareSurface(tester);
    final key = GlobalKey();
    await tester.pumpWidget(
      _page(key: key, dark: false, child: _coversPreview(false)),
    );
    expect(tester.takeException(), isNull, reason: '封面在浅色下渲染抛异常');
    await _capture(tester, key, 'covers.png');

    // 再渲染一遍深色(不存图):封面是最容易"深色下发闷"的资产,必须也验一次
    await tester.pumpWidget(
      _page(key: GlobalKey(), dark: true, child: _coversPreview(true)),
    );
    expect(tester.takeException(), isNull, reason: '封面在深色下渲染抛异常');
  });

  testWidgets('导出空态插图预览(5 种)', (tester) async {
    await _prepareSurface(tester);
    final key = GlobalKey();
    await tester.pumpWidget(
      _page(key: key, dark: false, child: _emptiesPreview(false)),
    );
    expect(tester.takeException(), isNull, reason: '空态在浅色下渲染抛异常');
    await _capture(tester, key, 'empties.png');

    await tester.pumpWidget(
      _page(key: GlobalKey(), dark: true, child: _emptiesPreview(true)),
    );
    expect(tester.takeException(), isNull, reason: '空态在深色下渲染抛异常');
  });

  testWidgets('导出数据图形预览(4 个 + 输出四阶)', (tester) async {
    await _prepareSurface(tester);
    final key = GlobalKey();
    await tester.pumpWidget(
      _page(key: key, dark: false, child: _dataPreview(false)),
    );
    expect(tester.takeException(), isNull, reason: '数据图形在浅色下渲染抛异常');
    await _capture(tester, key, 'data.png');

    await tester.pumpWidget(
      _page(key: GlobalKey(), dark: true, child: _dataPreview(true)),
    );
    expect(tester.takeException(), isNull, reason: '数据图形在深色下渲染抛异常');
  });

  // ── 性能闸门 ────────────────────────────────────────────────────────
  group('GraphicPainter.shouldRepaint', () {
    const ink = GraphicInk(
      line: Color(0xFF2B313B),
      accent: Color(0xFF7E5A2A),
      tone: Color(0xFF7A828F),
    );

    test('参数完全不变 → false(否则列表每帧重绘,滚动掉帧)', () {
      final a = domainGraphicPainter(GraphicDomain.science, ink: ink, stroke: 3);
      final b = domainGraphicPainter(GraphicDomain.science, ink: ink, stroke: 3);
      expect(a.shouldRepaint(b), isFalse);
    });

    test('颜色变了 → true', () {
      final a = domainGraphicPainter(GraphicDomain.science, ink: ink, stroke: 3);
      final b = domainGraphicPainter(
        GraphicDomain.science,
        ink: const GraphicInk(
          line: Color(0xFFDCE1E9),
          accent: Color(0xFF2F6FB5),
          tone: Color(0xFF8E99A8),
        ),
        stroke: 3,
      );
      expect(a.shouldRepaint(b), isTrue);
    });

    test('线宽变了 → true;领域变了 → true', () {
      final a = domainGraphicPainter(GraphicDomain.science, ink: ink, stroke: 3);
      expect(
        a.shouldRepaint(
          domainGraphicPainter(GraphicDomain.science, ink: ink, stroke: 4),
        ),
        isTrue,
      );
      expect(
        a.shouldRepaint(
          domainGraphicPainter(GraphicDomain.health, ink: ink, stroke: 3),
        ),
        isTrue,
      );
    });
  });

  // ── 颜色闸门 ────────────────────────────────────────────────────────
  group('领域身份色:明暗两套都清晰', () {
    test('浅色档对白卡片 ≥3:1(WCAG 非文字元素标准)', () {
      final card = AppTheme.lightTheme.cardTheme.color!;
      final failures = <String>[];
      for (final domain in GraphicDomain.values) {
        final ratio = AppTheme.contrastRatio(domain.baseColor, card);
        if (ratio < 3.0) {
          failures.add('${domain.label} = ${ratio.toStringAsFixed(2)}:1');
        }
      }
      expect(failures, isEmpty,
          reason: '浅色下这些领域图形会糊在白卡上:\n${failures.join('\n')}');
    });

    testWidgets('深色档经 readableOn 提亮后对深卡片 ≥3:1', (tester) async {
      late Map<GraphicDomain, Color> resolved;
      await tester.pumpWidget(
        Theme(
          data: AppTheme.darkTheme,
          child: Builder(
            builder: (ctx) {
              resolved = <GraphicDomain, Color>{
                for (final d in GraphicDomain.values) d: d.colorOf(ctx),
              };
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final card = AppTheme.darkTheme.cardTheme.color!;
      final failures = <String>[];
      resolved.forEach((domain, color) {
        final ratio = AppTheme.contrastRatio(color, card);
        if (ratio < 3.0) {
          failures.add('${domain.label} = ${ratio.toStringAsFixed(2)}:1');
        }
      });
      expect(failures, isEmpty,
          reason: '深色下这些领域图形会发闷:\n${failures.join('\n')}');
    });
  });

  group('封面身份色', () {
    test('7 类封面亮面/暗面对白字都 ≥4.5:1(调用方会叠白标题)', () {
      final failures = <String>[];
      for (final kind in MaterialKindArt.values) {
        for (final entry in <String, Color>{
          '亮面': kind.face,
          '暗面': kind.shade,
        }.entries) {
          final ratio = AppTheme.contrastRatio(Colors.white, entry.value);
          if (ratio < 4.5) {
            failures.add(
              '${kind.label}${entry.key} = ${ratio.toStringAsFixed(2)}:1',
            );
          }
        }
      }
      expect(failures, isEmpty,
          reason: '封面上的白字会看不清:\n${failures.join('\n')}');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// 预览图的排版
// ═══════════════════════════════════════════════════════════════════════

final Directory _outDir = Directory('build/graphics_preview');

/// 预览用中文字体族(不进 App 包体,只给测试渲染)
const String _fontFamily = 'PreviewCJK';

bool _previewFontLoaded = false;

String get _labelFamily => _previewFontLoaded ? _fontFamily : 'Roboto';

/// 从系统字体里找一个中文字体注册给测试环境。
///
/// 按"优先无衬线 + 变量字体"的顺序试:NotoSansSC(思源黑,VF 也能加载)→
/// 等线 → 黑体 → 楷体。任何一步失败都换下一个,全失败也不让测试挂
/// (PNG 里标签会变方块,但图形本身仍然是准的)。
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

/// 把测试画布调大,避免预览内容超出视口导致被裁
Future<void> _prepareSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1500, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 预览页外壳。
///
/// 不用 MaterialApp:它会套一层 AnimatedTheme 做 200ms 明暗过渡,第一帧的
/// brightness 可能还是旧的(theme_test 里有同样的坑);这里直接给确定的
/// Theme + MediaQuery + Directionality,一帧就是终态。
///
/// 主题的 textTheme 会被**统一替换成预览字体**:数据图形里的中心数字是
/// painter 用 TextPainter 画的(拿不到 Theme),它的字体是从 textTheme 派生的,
/// 不换字体的话预览图里数字会是方块。
Widget _page({
  required GlobalKey key,
  required bool dark,
  required Widget child,
}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _labelFamily),
  );
  return MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: theme,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: DefaultTextStyle(
                  style: TextStyle(
                    fontFamily: _labelFamily,
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

TextStyle _labelStyle(bool dark) {
  final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  return TextStyle(
    fontFamily: _labelFamily,
    fontSize: 11,
    height: 1.2,
    color: theme.colorScheme.onSurfaceVariant,
  );
}

TextStyle _titleStyle(bool dark) {
  final theme = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  return TextStyle(
    fontFamily: _labelFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: theme.colorScheme.onSurface,
  );
}

Widget _title(String text, bool dark) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Text(text, style: _titleStyle(dark)),
  );
}

Widget _caption(String text, bool dark) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, textAlign: TextAlign.center, style: _labelStyle(dark)),
  );
}

/// 13 个领域:5 列 × 3 行,每格 96px,下面带中文名
Widget _domainsGrid(bool dark) {
  return SizedBox(
    width: 720,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _title('领域图形 · 13 个(展示尺寸 96,面板开启)', dark),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: <Widget>[
            for (final domain in GraphicDomain.values)
              SizedBox(
                width: 108,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DomainGraphic(domain: domain, size: 96, showPanel: true),
                    _caption(domain.label, dark),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// 7 种材料封面:第一行 3:4(宽 96)、第二行 16:9(宽 150)
Widget _coversPreview(bool dark) {
  Widget cell(MaterialKindArt kind, {required bool portrait}) {
    final art = MaterialCoverArt(
      kind: kind,
      seed: '${kind.label}-seed',
      ratio: portrait ? CoverRatioArt.portrait : CoverRatioArt.landscape,
      width: portrait ? 96 : 150,
    );
    return SizedBox(
      width: portrait ? 96 : 150,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          art,
          _caption(portrait ? kind.label : '${kind.label} · 16:9', dark),
        ],
      ),
    );
  }

  return SizedBox(
    width: 1180,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _title('材料封面身份图 · 7 类(第一行 3:4 竖版)', dark),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: <Widget>[
            for (final kind in MaterialKindArt.values)
              cell(kind, portrait: true),
          ],
        ),
        const SizedBox(height: 26),
        _title('同一批封面 · 16:9 横版', dark),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: <Widget>[
            for (final kind in MaterialKindArt.values)
              cell(kind, portrait: false),
          ],
        ),
      ],
    ),
  );
}

/// 5 个空态插图(120)
Widget _emptiesPreview(bool dark) {
  return SizedBox(
    width: 760,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _title('空态插图 · 5 种(展示尺寸 120)', dark),
        Wrap(
          spacing: 20,
          runSpacing: 16,
          children: <Widget>[
            for (final kind in EmptyArtKind.values)
              SizedBox(
                width: 128,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    EmptyArt(kind: kind, size: 120),
                    _caption(kind.label, dark),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

/// 4 个数据图形 + 输出四阶
Widget _dataPreview(bool dark) {
  Widget dataCell(String label, Widget child) {
    return SizedBox(
      width: 168,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(height: 104, child: Center(child: child)),
          _caption(label, dark),
        ],
      ),
    );
  }

  Widget tierCell(OutputTierArt tier) {
    return SizedBox(
      width: 116,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          OutputTierGraphic(tier: tier, size: 96, showPanel: true),
          _caption(tier.label, dark),
        ],
      ),
    );
  }

  return SizedBox(
    width: 740,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _title('数据图形 · 4 个', dark),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: <Widget>[
            dataCell(
              '迷你柱状图',
              const SparkBars(
                values: <double>[4, 7, 5, 9, 6, 11, 14],
                width: 150,
                height: 56,
              ),
            ),
            dataCell(
              '趋势折线',
              const TrendLine(
                points: <double>[3, 5, 4, 8, 6, 10, 9, 13],
                width: 150,
                height: 72,
              ),
            ),
            dataCell(
              '打卡热力图',
              HeatmapCalendar(
                levels: HeatmapCalendar.tiersOf(<int>[
                  3, 0, 12, 5, 0, 0, 22, //
                  8, 4, 0, 31, 16, 2, 0, //
                  0, 9, 14, 6, 0, 25, 11, //
                  5, 0, 0, 18, 7, 3, 0, //
                  12, 20, 1, 0, 9, 27, 4, //
                  0, 6, 15, 8, 0, 0, 13, //
                  2, 11, 30, 5, 0, 19, 7, //
                  0, 3, 9, 24, 12, 0, 6, //
                ]),
                weeks: 8,
                cell: 11,
              ),
            ),
            dataCell(
              '环形进度',
              const RadialGauge(
                value: 0.72,
                size: 100,
                centerText: '72',
                caption: '综合得分',
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _title('输出四阶 · 单词 → 句子 → 段落 → 作文', dark),
        Wrap(
          spacing: 20,
          runSpacing: 16,
          children: <Widget>[
            for (final tier in OutputTierArt.values) tierCell(tier),
          ],
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 截图
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
