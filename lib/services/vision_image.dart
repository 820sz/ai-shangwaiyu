import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 识图前的**图片预处理**(v2.4,用户反馈"识图开盲盒"的另一半根因)。
///
/// 为什么必须在本地先处理:
/// 1. **方向**:手机横拍/倒置的照片,像素本身是转过的(用户提供的样本里就有
///    横置与倒置的页面)。模型要额外花注意力去"转正再读",漏识与错识大多
///    发生在这一步;本地把像素转正,模型只需要认字。
/// 2. **分辨率**:过小(被上游压到 512px)小字与浅色铅笔痕迹直接糊掉;过大
///    又会被服务端二次压缩。这里统一把长边压到 [maxLongEdge] 再按 JPEG 编码,
///    让"发出去的东西"是确定的,而不是"看服务端心情"。
/// 3. **可预期**:同一张图每次发出去都一样,问题可复现 —— 这是"别再开盲盒"
///    的前提。
///
/// 失败一律**原样返回**(宁可发未处理的图,也不能因为预处理失败而不给识别)。
class VisionImagePrep {
  VisionImagePrep._();

  /// 长边上限(px)。2000 是权衡:小字仍可辨,超过 2000 多数端点也会自己压。
  static const int maxLongEdge = 2000;

  /// JPEG 质量:88 在文字清晰度与体积之间比较稳
  static const int jpegQuality = 88;

  /// 预处理:转正 → 必要时缩放 → 统一 JPEG 编码
  static Uint8List prepare(Uint8List raw) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      // ① 按 EXIF 把像素转正(手机照片最常见的问题)
      var work = img.bakeOrientation(decoded);
      // ② 长边压到上限以内(不放大)
      final longEdge = work.width > work.height ? work.width : work.height;
      if (longEdge > maxLongEdge) {
        final scale = maxLongEdge / longEdge;
        final w = (work.width * scale).round();
        final h = (work.height * scale).round();
        work = img.copyResize(
          work,
          width: w < 1 ? 1 : w,
          height: h < 1 ? 1 : h,
          interpolation: img.Interpolation.cubic,
        );
      }
      return img.encodeJpg(work, quality: jpegQuality);
    } catch (e) {
      debugPrint('ReadFlow 识图预处理失败(原图直发): $e');
      return raw;
    }
  }

  /// 直接给视觉 API 用的 data URI
  static String toDataUri(Uint8List raw) =>
      'data:image/jpeg;base64,${base64Encode(prepare(raw))}';
}
