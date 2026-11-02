import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/output/widgets/output_tier_card.dart';
import 'package:readflow/widgets/graphics/graphics.dart';

/// 批 3 · 输出四阶卡片预览(看图验收)。
///
/// 输出首页依赖 Provider/SQLite,单独渲染四张阶卡就能判断"四阶并行的台阶"
/// 是否成立(图形递进 + 平级 + 进度行)。
///
/// 输出:`build/graphics_preview/output_tiers_light.png` / `_dark.png`
void main() {
  testWidgets('输出四阶卡片预览图导出(明暗两套)', (tester) async {
    await _loadPreviewFont();
    tester.view.physicalSize = const Size(820, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final dark in [false, true]) {
      await _export(
        tester,
        _scene(dark: dark),
        'build/graphics_preview/output_tiers_${dark ? 'dark' : 'light'}.png',
      );
    }
  });
}

Future<void> _export(WidgetTester tester, Widget child, String path) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/graphics_preview').createSync(recursive: true);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _scene({required bool dark}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _labelFamily),
  );
  // 模拟输出首页里 2 列网格的单卡宽度(360 屏:约 156 宽 / 约 122 高)
  const cardW = 156.0;
  const cardH = 122.0;
  return ColoredBox(
    color: theme.scaffoldBackgroundColor,
    child: Theme(
      data: theme,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: _labelFamily,
          fontSize: 12,
          color: theme.colorScheme.onSurface,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '输出四阶卡片（2 列网格，单卡约 156×116）',
                style: TextStyle(
                  fontFamily: _labelFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < outputTierCatalog.length; i++)
                    SizedBox(
                      width: cardW,
                      height: cardH,
                      child: OutputTierCard(
                        tier: outputTierCatalog[i].tier,
                        title: outputTierCatalog[i].title,
                        subtitle: outputTierCatalog[i].subtitle,
                        available: i != 2, // 写段 = 开发中
                        progress: switch (i) {
                          0 => '已练 42 题 · 正确率 86%',
                          1 => '已练 18 题 · 正确率 72%',
                          3 => null,
                          _ => null,
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '输出四阶图形对照（由小到大：词→句→段→篇）',
                style: TextStyle(
                  fontFamily: _labelFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final tier in OutputTierArt.values) ...[
                    OutputTierGraphic(
                      tier: tier,
                      size: 72,
                      showPanel: true,
                    ),
                    const SizedBox(width: 10),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── 预览字体(只注册到测试环境,不进 App 包体)────────────────────────

const String _previewFontFamily = 'PreviewCJK';
bool _previewFontLoaded = false;

String get _labelFamily => _previewFontLoaded ? _previewFontFamily : 'Roboto';

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
      final loader = FontLoader(_previewFontFamily)
        ..addFont(
          Future<ByteData>.value(
            ByteData.sublistView(file.readAsBytesSync()),
          ),
        );
      await loader.load();
      _previewFontLoaded = true;
      return;
    } catch (_) {
      // 字体格式不支持:换下一个候选
    }
  }
}
