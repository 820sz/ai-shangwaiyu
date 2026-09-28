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

  /// 长边上限(px)。
  ///
  /// **v2.6 从 2000 提到 2600**:2000 时整页 A4 的正文只有十几像素高,浅色铅笔
  /// 划线几乎不可辨;而识别"哪一笔是标记"恰恰是低对比度细节任务。2600 在
  /// 多数端点(方舟、DeepSeek)的接收上限内,也让 2× 放大切片有料可切。
  static const int maxLongEdge = 2600;

  /// JPEG 质量:**v2.6 从 88 提到 92**。有损压缩最先牺牲的正是淡色细线。
  static const int jpegQuality = 92;

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

  /// 把一页切成若干**互相重叠**的高清小块(v2.6 新增)。
  ///
  /// 为什么必须切:两家官方都写明**图片进模型前会被压到约 1300×1300 等效像素**
  /// (DeepSeek 文档:"缩小后的总像素约相当于 1300×1300 的图片"),整页 A4 送进去
  /// 就是"小字 + 淡色划线全糊"。切成 2×2 后每块只承载 1/4 内容,同样 1300px 的
  /// 预算下**每块的字大了一倍**;再带 8% 重叠,避免把划在切口上的词切断。
  ///
  /// 用途:第二遍"只找漏"复查(结果追加,不替换第一遍)。
  static List<Uint8List> tiles(
    Uint8List raw, {
    int rows = 2,
    int cols = 2,
    double overlap = 0.08,
  }) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return [prepare(raw)];
      final work = img.bakeOrientation(decoded);
      final out = <Uint8List>[];
      final tileW = (work.width / cols).ceil();
      final tileH = (work.height / rows).ceil();
      final padX = (tileW * overlap).round();
      final padY = (tileH * overlap).round();
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final x = (c * tileW - padX).clamp(0, work.width - 1);
          final y = (r * tileH - padY).clamp(0, work.height - 1);
          final w = (tileW + padX * 2).clamp(1, work.width - x);
          final h = (tileH + padY * 2).clamp(1, work.height - y);
          final crop = img.copyCrop(work, x: x, y: y, width: w, height: h);
          out.add(img.encodeJpg(crop, quality: jpegQuality));
        }
      }
      return out;
    } catch (e) {
      debugPrint('ReadFlow 切块失败(退回整图): $e');
      return [prepare(raw)];
    }
  }

  /// 切块后的 data URI 列表(一次请求可以带多张,服务端按多图处理)
  static List<String> tileDataUris(
    Uint8List raw, {
    int rows = 2,
    int cols = 2,
    double overlap = 0.08,
  }) =>
      tiles(raw, rows: rows, cols: cols, overlap: overlap)
          .map((t) => 'data:image/jpeg;base64,${base64Encode(t)}')
          .toList();
}
