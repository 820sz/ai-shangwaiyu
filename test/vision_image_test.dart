import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:readflow/services/vision_image.dart';

/// 识图预处理测试(v2.4)。
///
/// 用户样本照片是**横置/倒置**的翻拍页 —— 模型得先"歪着读"再识别,
/// 漏识与错识多半就发生在那一步。这层负责把像素转正、把分辨率压到确定值,
/// 让"发出去的东西"每次都一样(别再开盲盒)。
void main() {
  Uint8List jpegOf(int width, int height) {
    final image = img.Image(width: width, height: height);
    // 画一些"像文字"的东西,保证编码后不是全白
    for (var y = 10; y < height - 10; y += 12) {
      for (var x = 10; x < width - 10; x += 3) {
        image.setPixelRgb(x, y, 0, 0, 0);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  test('长边超过上限 → 等比压到上限(不放大、不变形)', () {
    final out = VisionImagePrep.prepare(jpegOf(3000, 1500));
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, VisionImagePrep.maxLongEdge);
    // v2.6 上限从 2000 提到 2600:小字与浅色划线在 2000 下会被压糊
    expect(VisionImagePrep.maxLongEdge, 2600);
    expect(decoded.height, 1300, reason: '等比缩放:3000x1500 → 2600x1300');
  });

  test('竖图同样按长边压(高度方向)', () {
    final out = VisionImagePrep.prepare(jpegOf(1500, 3000));
    final decoded = img.decodeImage(out)!;
    expect(decoded.height, VisionImagePrep.maxLongEdge);
    expect(decoded.width, 1300);
  });

  test('小图不放大,但会被统一重编码成 JPEG(方向已被烘焙进像素)', () {
    final out = VisionImagePrep.prepare(jpegOf(800, 600));
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 800);
    expect(decoded.height, 600);
    // 输出一定以 JPEG 魔数开头(FF D8)
    expect(out[0], 0xFF);
    expect(out[1], 0xD8);
  });

  test('PNG 输入也能处理(翻拍/截图混用)', () {
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 3000, height: 1200)),
    );
    final out = VisionImagePrep.prepare(png);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, VisionImagePrep.maxLongEdge);
    expect(out[1], 0xD8, reason: '输出统一为 JPEG');
  });

  group('高清分块(v2.6 "只找漏"复查用)', () {
    test('切成 2×2 小块,每块都有内容且解得出图', () {
      final tiles = VisionImagePrep.tiles(jpegOf(1600, 2400));
      expect(tiles, hasLength(4));
      for (final t in tiles) {
        final d = img.decodeImage(t);
        expect(d, isNotNull, reason: '每块都必须是合法 JPEG');
        expect(d!.width, greaterThan(100));
        expect(d.height, greaterThan(100));
      }
    });

    test('小块带重叠:相邻块的宽度之和大于原图宽(不切断跨界的标记)', () {
      final tiles = VisionImagePrep.tiles(jpegOf(2000, 2000),
          rows: 2, cols: 2, overlap: 0.08);
      final a = img.decodeImage(tiles.first)!;
      final b = img.decodeImage(tiles[1])!;
      expect(a.width + b.width, greaterThan(2000),
          reason: '两块宽度之和超过原图 → 说明中间有重叠区');
    });

    test('data URI 列表与块数一致,且都能直接发给 API', () {
      final uris = VisionImagePrep.tileDataUris(jpegOf(1200, 1600));
      expect(uris, hasLength(4));
      for (final u in uris) {
        expect(u.startsWith('data:image/jpeg;base64,'), isTrue);
        expect(img.decodeImage(base64Decode(u.split(',').last)), isNotNull);
      }
    });
  });

  test('解不开的字节 → 原样返回(绝不能因为预处理失败就不给识别)', () {
    final garbage = Uint8List.fromList(List<int>.generate(64, (i) => i));
    expect(VisionImagePrep.prepare(garbage), garbage);
  });

  test('toDataUri 产出可直接发的 data URI', () {
    final uri = VisionImagePrep.toDataUri(jpegOf(600, 400));
    expect(uri.startsWith('data:image/jpeg;base64,'), isTrue);
    final b64 = uri.split(',').last;
    final bytes = base64Decode(b64);
    expect(img.decodeImage(bytes), isNotNull, reason: 'base64 内容必须是能解开的图');
  });

  test('EXIF 方向被烘焙:带 orientation 的图会转正', () {
    // 造一张 200x100 的图,标记 EXIF orientation=6(顺时针 90°)
    final image = img.Image(width: 200, height: 100);
    image.exif.imageIfd['Orientation'] = 6;
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));

    final after = img.decodeImage(VisionImagePrep.prepare(bytes))!;
    // 结果必须是"转正后"的尺寸:200x100 竖过来 = 100x200。
    // 注意:本版本 image 包在 decode 时已按 EXIF 转过一次,prepare 里的
    // bakeOrientation 是**幂等保护**(换解码器/换图片格式时仍然转正)——
    // 这条断言正是用来防止"转两次"这类错误(输出若变成 200x100 就说明转重了)。
    expect(after.width, 100, reason: 'orientation=6 应把 200x100 转成 100x200');
    expect(after.height, 200);
  });

  // ── B0-6:手动旋转(只转"发给模型的像素",源文件/缩略图不动) ──
  group('B0-6 quarterTurns 手动旋转', () {
    test('quarterTurns:1 → 宽高互换(发送前按 90° 转后编码)', () {
      final out = VisionImagePrep.prepare(jpegOf(400, 600), quarterTurns: 1);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 600, reason: '400x600 顺时针转 90° → 600x400');
      expect(decoded.height, 400);
    });

    test('quarterTurns 按 4 取模:4 等价于 0(连点 4 次回到原方向)', () {
      final base = img.decodeImage(VisionImagePrep.prepare(jpegOf(800, 600)))!;
      final full = img.decodeImage(
        VisionImagePrep.prepare(jpegOf(800, 600), quarterTurns: 4),
      )!;
      expect(full.width, base.width);
      expect(full.height, base.height);
    });

    test('tiles 也支持手动角度:旋转后切块仍是横的(整批一致)', () {
      final tiles = VisionImagePrep.tiles(jpegOf(400, 600), quarterTurns: 1);
      expect(tiles, hasLength(4));
      final first = img.decodeImage(tiles.first)!;
      // 400x600 转 90° → 600x400,2×2 切块后每块约 348x232(含 8% 重叠)
      expect(
        first.width,
        greaterThan(first.height),
        reason: '页面旋转后是横的,切出来的块也应是横的(说明角度进了切块链路)',
      );
    });
  });

  // ── B0-3:detectRotationOf(接已解码的图,避免每张图二次整图解码) ──
  group('B0-3 detectRotationOf(已解码图)方向判定', () {
    /// 造一张"横排文字"合成图:整行暗带 + 行间白底。
    /// 原理与实现一致:行投影方差大 → 内容水平排列;列投影方差大 → 内容被横放。
    img.Image textRowsImage({int width = 400, int height = 600}) {
      final image = img.Image(width: width, height: height);
      // 先铺白底(image 包默认像素是透明黑,不铺白就分不出"文字行"和背景)
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          image.setPixelRgb(x, y, 255, 255, 255);
        }
      }
      // 每 24px 画一条 4px 高的"文字行"(整行铺满 → 行均值方差拉起来)
      for (var y = 20; y < height - 20; y += 24) {
        for (var dy = 0; dy < 4; dy++) {
          for (var x = 20; x < width - 20; x++) {
            image.setPixelRgb(x, y + dy, 0, 0, 0);
          }
        }
      }
      return image;
    }

    test('横排文字 → 判定不用转(rotationNone)', () {
      expect(
        VisionImagePrep.detectRotationOf(textRowsImage()),
        VisionImagePrep.rotationNone,
      );
    });

    test('内容横放(整图转 90°)→ 判定需顺时针转 90°(rotationClockwise90)', () {
      expect(
        VisionImagePrep.detectRotationOf(
          img.copyRotate(textRowsImage(), angle: 90),
        ),
        VisionImagePrep.rotationClockwise90,
      );
    });

    test('倒置 180°/反向 270°:返回的是**约定**(分不出,由用户旋转重试兜底)', () {
      // vision_image.dart 的注释写明:投影法只能判"内容是否横放",
      // 分不出 0°/180°、90°/270°。所以这里断言的是既定约定而不是"理想答案":
      // 180° 仍按"不转"、270° 仍按"转 90°";这两种情况由 UI 的
      // 「方向不对?旋转重试」(B0-6,用户可循环 90/180/270)兜底。
      expect(
        VisionImagePrep.detectRotationOf(
          img.copyRotate(textRowsImage(), angle: 180),
        ),
        VisionImagePrep.rotationNone,
      );
      expect(
        VisionImagePrep.detectRotationOf(
          img.copyRotate(textRowsImage(), angle: 270),
        ),
        VisionImagePrep.rotationClockwise90,
      );
    });
  });

  // ── B0-3:后台 isolate 入口 smoke(真机内存收益靠真机验证,这里只保接口/等价性) ──
  group('B0-3 isolate 后台入口 smoke', () {
    test('toDataUriInBackground 与同步版逐字节一致', () async {
      final raw = jpegOf(600, 400);
      expect(
        await VisionImagePrep.toDataUriInBackground(raw),
        VisionImagePrep.toDataUri(raw),
        reason: 'isolate 只是换线程,结果必须与同步版完全一致',
      );
    });

    test('prepareInBackground 与同步版一致(含 quarterTurns 分支)', () async {
      final raw = jpegOf(400, 600);
      expect(
        await VisionImagePrep.prepareInBackground(raw, quarterTurns: 1),
        VisionImagePrep.prepare(raw, quarterTurns: 1),
      );
    });

    test('tilesInBackground 在后台 isolate 产出 4 块合法 JPEG', () async {
      final tiles = await VisionImagePrep.tilesInBackground(
        jpegOf(1600, 2400),
      );
      expect(tiles, hasLength(4));
      for (final tile in tiles) {
        expect(img.decodeImage(tile), isNotNull, reason: '每块都必须是合法 JPEG');
      }
    });
  });
}
