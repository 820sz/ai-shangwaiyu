// 生成桌面图标 PNG(2026-11-07 · 开屏方案 A / Logo L1「引号 · 星」)。
//
// 为什么放在 test/ 而不是 tool/:图标要靠 `dart:ui` 的 PictureRecorder + toImage,
// 那是 Flutter 引擎的能力,`dart run` 跑不起来;用 `flutter test` 跑一次即可出全部 PNG。
//
// 产物写到 **build/gen_icons/**(不碰 android/ 目录,由 Lead 拷入 res):
//   build/gen_icons/ic_launcher_1024.png                 ← 商店/宣传用主图
//   build/gen_icons/mipmap-mdpi/ic_launcher.png          48×48
//   build/gen_icons/mipmap-hdpi/ic_launcher.png          72×72
//   build/gen_icons/mipmap-xhdpi/ic_launcher.png         96×96
//   build/gen_icons/mipmap-xxhdpi/ic_launcher.png        144×144
//   build/gen_icons/mipmap-xxxhdpi/ic_launcher.png       192×192
//   build/gen_icons/drawable-mdpi/ic_launcher_foreground.png      108×108
//   build/gen_icons/drawable-hdpi/ic_launcher_foreground.png      162×162
//   build/gen_icons/drawable-xhdpi/ic_launcher_foreground.png     216×216
//   build/gen_icons/drawable-xxhdpi/ic_launcher_foreground.png    324×324
//   build/gen_icons/drawable-xxxhdpi/ic_launcher_foreground.png   432×432
//   build/gen_icons/drawable-*/ic_launcher_monochrome.png         同尺寸(单色剪影)
//
// 约定:
// - **每个密度原生渲染**(不是大图缩小),所以 48px 的引号/星芒边缘是干净的;
// - 传统图标 = 渐变底 + 白标(标占 78%);自适应前景 = 透明底 + 白标(标占 62%,
//   落在 108dp 画布的 66dp 安全区内);monochrome = 透明底 + 白剪影(系统会染色);
// - 字形与开屏完全一致:都调 `paintSplashMark()`。

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/widgets/splash_graphics.dart';

const String _out = 'build/gen_icons';

Future<void> _writePng(ui.Image image, String path) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  debugPrint('[icon] $path (${image.width}×${image.height})');
  image.dispose();
}

/// 画一枚图标:[withBackground] 是否画品牌渐变底;[fill] 是标占画布的比例。
Future<void> _render({
  required int px,
  required String path,
  required double fill,
  required bool withBackground,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final full = px.toDouble();
  if (withBackground) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, full, full),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF7C9BFF), Color(0xFFC86BFF)],
        ).createShader(Rect.fromLTWH(0, 0, full, full)),
    );
  }
  final box = full * fill;
  final offset = (full - box) / 2;
  canvas.save();
  canvas.translate(offset, offset);
  paintSplashMark(canvas, Size(box, box), Colors.white);
  canvas.restore();

  final image = await recorder.endRecording().toImage(px, px);
  await _writePng(image, path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('生成 launcher 图标(全部密度)', (tester) async {
    await tester.runAsync(() async {
      // ① 商店/宣传主图
      await _render(
        px: 1024,
        path: '$_out/ic_launcher_1024.png',
        fill: 0.78,
        withBackground: true,
      );

      // ② 传统图标(mipmap,Android 5~7 与部分启动器)
      const legacy = <int, String>{
        48: 'mipmap-mdpi',
        72: 'mipmap-hdpi',
        96: 'mipmap-xhdpi',
        144: 'mipmap-xxhdpi',
        192: 'mipmap-xxxhdpi',
      };
      for (final entry in legacy.entries) {
        await _render(
          px: entry.key,
          path: '$_out/${entry.value}/ic_launcher.png',
          fill: 0.78,
          withBackground: true,
        );
      }

      // ③ 自适应图标前景(108dp 画布,内容缩到 62% → 落在 66dp 安全区内)
      const adaptive = <int, String>{
        108: 'drawable-mdpi',
        162: 'drawable-hdpi',
        216: 'drawable-xhdpi',
        324: 'drawable-xxhdpi',
        432: 'drawable-xxxhdpi',
      };
      for (final entry in adaptive.entries) {
        await _render(
          px: entry.key,
          path: '$_out/${entry.value}/ic_launcher_foreground.png',
          fill: 0.62,
          withBackground: false,
        );
        // ④ monochrome(Android 13+ 主题图标;系统会按壁纸染色,所以只要剪影)
        await _render(
          px: entry.key,
          path: '$_out/${entry.value}/ic_launcher_monochrome.png',
          fill: 0.62,
          withBackground: false,
        );
      }
    });

    // 出图自检:至少主图 + 5 套 mipmap + 5×2 套 drawable 存在
    expect(File('$_out/ic_launcher_1024.png').existsSync(), isTrue);
    expect(
        File('$_out/mipmap-xxxhdpi/ic_launcher.png').existsSync(), isTrue);
    expect(
        File('$_out/drawable-xxxhdpi/ic_launcher_foreground.png').existsSync(),
        isTrue);
    expect(
        File('$_out/drawable-mdpi/ic_launcher_monochrome.png').existsSync(),
        isTrue);
  });
}
