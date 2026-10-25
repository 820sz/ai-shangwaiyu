import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 识图前的**图片预处理**(v2.4 起;v2.13 补了方向与划线增强)。
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

  /// 方向检测结论:不用转
  static const int rotationNone = 0;

  /// 方向检测结论:内容横放,需要顺时针转 90°
  static const int rotationClockwise90 = 90;

  /// 判断"**内容是不是被横放了**"(用户 2026-10-20 原话:
  /// 「当上传的图片/拍的图被列为横幅时(如图 1 所示),准确率非常低」)。
  ///
  /// 原理:**文字行会形成周期性的暗带**。
  /// - 正常书页(文字水平排列):按行求均值 → 有字的行暗、行间空白亮 → **行方差大**;
  /// - 内容横放 90°(文字变竖排):**列方差大**、行方差小。
  ///
  /// 为什么不用宽高比:横版照片也可能是"竖版内容 + 左右宽边距",
  /// 只有投影能反映**文字行本身的方向**。
  ///
  /// 局限(诚实记下来):投影分不出 0° 与 180°、90° 与 270° ——
  /// 倒置/反向由 EXIF 与调用方的"识别不到就换方向重试"兜底,
  /// UI 上也给了"方向不对?旋转重试"。
  static int detectRotation(Uint8List raw, {double threshold = 1.18}) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return rotationNone;
      // 缩到 200 宽再算:快、且抗噪(细线噪点被平均掉)
      final small = img.copyResize(
        img.bakeOrientation(decoded),
        width: 200,
        interpolation: img.Interpolation.average,
      );
      final gray = img.grayscale(small);
      final rowVar = _rowMeanVariance(gray);
      final colVar = _colMeanVariance(gray);
      // 文字竖排时列方差显著大于行方差
      if (colVar > rowVar * threshold) return rotationClockwise90;
      return rotationNone;
    } catch (e) {
      debugPrint('ReadFlow 方向检测失败(按原方向): $e');
      return rotationNone;
    }
  }

  /// 预处理:转正 → 必要时缩放 → (可选)划线增强 → 统一 JPEG 编码
  ///
  /// [autoRotate]:内容横放时自动转 90°(默认开)。
  /// [enhanceMarks]:淡色划线增强;**只在"识别标记"场景开** ——
  /// 全文翻译/普通阅读要的是清晰的字,不是更深的纸纹。
  static Uint8List prepare(
    Uint8List raw, {
    bool autoRotate = true,
    bool enhanceMarks = false,
  }) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      // ① 按 EXIF 把像素转正(手机照片最常见的问题)
      var work = img.bakeOrientation(decoded);
      // ② 内容横放(EXIF 救不了的那种)→ 本地转 90°
      if (autoRotate && detectRotation(raw) == rotationClockwise90) {
        work = img.copyRotate(work, angle: 90);
        debugPrint('ReadFlow 检测到内容横放,已顺时针转正');
      }
      // ③ 长边压到上限以内(不放大)
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
      // ④ 划线增强:让"淡淡的铅笔线/只画了一半的线"与纸面拉开对比。
      //    只做轻度的对比度 + gamma,不做锐化 —— 锐化会把纸纹、装订线也放大,
      //    反而让模型把噪点当标记。
      if (enhanceMarks) work = _enhanceMarks(work);
      return img.encodeJpg(work, quality: jpegQuality);
    } catch (e) {
      debugPrint('ReadFlow 识图预处理失败(原图直发): $e');
      return raw;
    }
  }

  /// 轻度对比度 + gamma 调整(纯函数,便于单测)。
  ///
  /// gamma < 1 = 中间调变暗:浅灰的笔迹被拉向深色,而纸面白(255)不动。
  /// contrast 1.10 是实测的"看得清又不脏"档位。
  static img.Image _enhanceMarks(img.Image src) =>
      img.adjustColor(src, contrast: 1.10, gamma: 0.94);

  /// 直接给视觉 API 用的 data URI
  static String toDataUri(
    Uint8List raw, {
    bool autoRotate = true,
    bool enhanceMarks = false,
  }) =>
      'data:image/jpeg;base64,${base64Encode(prepare(raw, autoRotate: autoRotate, enhanceMarks: enhanceMarks))}';

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
    bool autoRotate = true,
    bool enhanceMarks = false,
  }) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return [prepare(raw)];
      var work = img.bakeOrientation(decoded);
      if (autoRotate && detectRotation(raw) == rotationClockwise90) {
        work = img.copyRotate(work, angle: 90);
      }
      if (enhanceMarks) work = _enhanceMarks(work);
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
    bool autoRotate = true,
    bool enhanceMarks = false,
  }) =>
      tiles(
        raw,
        rows: rows,
        cols: cols,
        overlap: overlap,
        autoRotate: autoRotate,
        enhanceMarks: enhanceMarks,
      ).map((t) => 'data:image/jpeg;base64,${base64Encode(t)}').toList();

  // ── 投影方差(方向检测的核心) ──

  /// 每一行平均亮度的方差:文字行水平排列时**大**
  static double _rowMeanVariance(img.Image g) {
    final w = g.width;
    final h = g.height;
    final means = Float64List(h);
    for (var y = 0; y < h; y++) {
      var sum = 0.0;
      for (var x = 0; x < w; x++) {
        sum += g.getPixel(x, y).luminance;
      }
      means[y] = sum / w;
    }
    return _variance(means);
  }

  /// 每一列平均亮度的方差:文字**竖排**时大(即图被横放了)
  static double _colMeanVariance(img.Image g) {
    final w = g.width;
    final h = g.height;
    final means = Float64List(w);
    for (var x = 0; x < w; x++) {
      var sum = 0.0;
      for (var y = 0; y < h; y++) {
        sum += g.getPixel(x, y).luminance;
      }
      means[x] = sum / h;
    }
    return _variance(means);
  }

  static double _variance(Float64List v) {
    if (v.isEmpty) return 0;
    var mean = 0.0;
    for (final x in v) {
      mean += x;
    }
    mean /= v.length;
    var acc = 0.0;
    for (final x in v) {
      final d = x - mean;
      acc += d * d;
    }
    return acc / v.length;
  }
}
