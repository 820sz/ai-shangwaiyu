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

  test('长边超过上限 → 等比压到 2000px(不放大、不变形)', () {
    final out = VisionImagePrep.prepare(jpegOf(3000, 1500));
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, VisionImagePrep.maxLongEdge);
    expect(decoded.height, 1000, reason: '等比缩放:3000x1500 → 2000x1000');
  });

  test('竖图同样按长边压(高度方向)', () {
    final out = VisionImagePrep.prepare(jpegOf(1500, 3000));
    final decoded = img.decodeImage(out)!;
    expect(decoded.height, VisionImagePrep.maxLongEdge);
    expect(decoded.width, 1000);
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
      img.encodePng(img.Image(width: 2400, height: 1200)),
    );
    final out = VisionImagePrep.prepare(png);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 2000);
    expect(out[1], 0xD8, reason: '输出统一为 JPEG');
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
}
