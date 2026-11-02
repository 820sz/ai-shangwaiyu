import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/widgets/material_cover.dart';

/// 批 1 封面预览:把 `MaterialCover`(已接图形资产 [MaterialCoverArt])渲染成
/// PNG,用于人工"看图验收"新封面——本机没有真机时,这是最接近真机观感的手段。
///
/// 输出:`build/graphics_preview/covers_v3_light.png` / `covers_v3_dark.png`
/// (build/ 不进 git,重跑测试即重新生成)。
/// 预览用中文字体(只注册到测试环境,不进 App 包体)。
///
/// 不加载字体的话 flutter_test 默认用 Ahem:所有文字会渲染成**白色方块**,
/// 预览图就无法判断"标题压不压得住封面"这类问题。
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
      // 字体格式不支持(FontLoader 只吃 ttf/otf):换下一个候选
    }
  }
}

void main() {
  testWidgets('封面预览图导出(明暗两套)', (tester) async {
    await _loadPreviewFont();
    // 逻辑尺寸 1100×1500:6 张封面一行放得下,所有尺寸档都能完整渲染
    // (溢出会让预览图变成黄黑条,失去"看图验收"的意义)。
    tester.view.physicalSize = const Size(1100, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final dark in [false, true]) {
      await _export(
        tester,
        _scene(dark: dark),
        'build/graphics_preview/covers_v3_${dark ? 'dark' : 'light'}.png',
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
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/graphics_preview').createSync(recursive: true);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _scene({required bool dark}) {
  final base = dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  // 主题字体统一换成预览字体(封面里的标题/徽标走 TextStyle,不换字体就是方块)
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
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 同一套内容,三种真实使用尺寸:书架/横卡缩略/今日精读大图
              _row('书架缩略 84×112', 84, 112, levels: true),
              const SizedBox(height: 18),
              _row('横卡缩略 168×96', 168, 96, levels: true),
              const SizedBox(height: 18),
              _row('今日精读大图 340×170', 340, 170, levels: false),
              const SizedBox(height: 18),
              // 无真实配图 + 无等级:最"裸"的形态(列表小卡)
              _row('窄列表 64×86(无等级)', 64, 86, levels: false),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _row(
  String title,
  double w,
  double h, {
  required bool levels,
}) {
  const kinds = ['article', 'book', 'paper', 'news', 'podcast', 'wiki'];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          for (final k in kinds)
            Column(
              children: [
                MaterialCover(
                  seed: _seedFor(k),
                  kind: k,
                  width: w,
                  height: h,
                  levelLabel: levels ? 'Lv7' : null,
                ),
                const SizedBox(height: 2),
                Text(k, style: const TextStyle(fontSize: 9)),
              ],
            ),
        ],
      ),
    ],
  );
}

String _seedFor(String kind) => switch (kind) {
      'book' => 'Moby Dick',
      'paper' => 'Attention Is All You Need',
      'news' => 'NPR Up First',
      'podcast' => 'TED Talks Daily',
      'wiki' => 'Photosynthesis',
      _ => 'Virginia and D.C. sue to block construction',
    };
