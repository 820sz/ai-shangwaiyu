import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/widgets/material_topic_card.dart';
import 'package:readflow/services/material_topics.dart';

/// 批 1 · 材料中心「大分区」卡片预览(看图验收)。
///
/// 为什么单独渲染卡片而不是整屏:材料中心首页依赖 Provider/SQLite/Hive,
/// widget 测试起一个完整页面成本高且脆弱;卡片是这次视觉改造的主角,
/// 单独渲染就能判断"图形墙"是否成立。
///
/// 输出:`build/graphics_preview/topic_cards_light.png` / `topic_cards_dark.png`
void main() {
  testWidgets('大分区卡片预览图导出(明暗两套)', (tester) async {
    await _loadPreviewFont();
    tester.view.physicalSize = const Size(820, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final dark in [false, true]) {
      await _export(
        tester,
        _scene(dark: dark),
        'build/graphics_preview/topic_cards_${dark ? 'dark' : 'light'}.png',
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
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '材料中心 · 大分区卡片(2 列网格,单卡约 170×152)',
                style: TextStyle(
                  fontFamily: _labelFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final topic in MaterialTopic.all)
                    SizedBox(
                      width: 170,
                      height: 152,
                      child: MaterialTopicCard(topic: topic),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '(用户自定义分区会落「其他」罗盘图形)',
                style: TextStyle(
                  fontFamily: _labelFamily,
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
