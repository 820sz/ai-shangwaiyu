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
  /// 从**已解码、且已按 EXIF 转正**的图判断"内容是不是被横放了"。
  ///
  /// 为什么要把检测和"解码"拆开(B0-3 根治):旧实现 [detectRotation] 内部
  /// 会再 `decodeImage(raw)` 一次,而 [prepare]/[tiles] 自己已经解过整图 ——
  /// 同一张 12MP 图预处理要整图解码 **2 次**(每次 RGBA ≈ 20MB),叠加"追加图片"
  /// 时第二遍高清复查的并发解码,就是用户看到的"卡一下然后闪退"(native OOM,
  /// Dart 层 CrashLogger 抓不到)。现在调用方把已解码/已转正的图传进来,
  /// 全程只解 1 次,B200 宽的统计图也只是小图拷贝。
  static int detectRotationOf(img.Image oriented, {double threshold = 1.18}) {
    try {
      // 缩到 200 宽再算:快、且抗噪(细线噪点被平均掉)
      final small = img.copyResize(
        oriented,
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

  /// 从原始字节判断方向(自带一次解码)。
  ///
  /// ⚠️ 预处理链路([prepare]/[tiles])**不要**用它 —— 那边已有解码好的图,
  /// 应改用 [detectRotationOf],否则又会多解一次整图(B0-3 的根因之一)。
  /// 保留这个入口只为单测与"只有字节"的场景。
  static int detectRotation(Uint8List raw, {double threshold = 1.18}) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return rotationNone;
      return detectRotationOf(img.bakeOrientation(decoded), threshold: threshold);
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
  /// [quarterTurns]:用户手动点「方向不对?旋转重试」累积的顺时针 90° 数
  /// (B0-6)。检测分不出 0°/180°、也分不出 90°/270°,所以最终判断权交给用户;
  /// 这里只负责把**发出去的像素**转对,源文件一个字都不动。
  static Uint8List prepare(
    Uint8List raw, {
    bool autoRotate = true,
    bool enhanceMarks = false,
    int quarterTurns = 0,
  }) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      // ① 按 EXIF 把像素转正(手机照片最常见的问题)
      var work = img.bakeOrientation(decoded);
      // ② 内容横放(EXIF 救不了的那种)→ 本地转 90°
      //    B0-3:方向检测用**这张已解码的图**,不再为检测多解一次整图
      if (autoRotate && detectRotationOf(work) == rotationClockwise90) {
        work = img.copyRotate(work, angle: 90);
        debugPrint('ReadFlow 检测到内容横放,已顺时针转正');
      }
      // ②b 用户手动指定的角度(B0-6"方向不对?旋转重试")
      final turns = quarterTurns % 4;
      if (turns != 0) {
        work = img.copyRotate(work, angle: turns * 90);
        debugPrint('ReadFlow 按用户选择旋转 ${turns * 90}° 后识别');
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
    int quarterTurns = 0,
  }) =>
      'data:image/jpeg;base64,${base64Encode(prepare(raw, autoRotate: autoRotate, enhanceMarks: enhanceMarks, quarterTurns: quarterTurns))}';

  /// 把一页切成若干**互相重叠**的高清小块(v2.6 新增)。
  ///
  /// 为什么必须切:两家官方都写明**图片进模型前会被压到约 1300×1300 等效像素**
  /// (DeepSeek 文档:"缩小后的总像素约相当于 1300×1300 的图片"),整页 A4 送进去
  /// 就是"小字 + 淡色划线全糊"。切成 2×2 后每块只承载 1/4 内容,同样 1300px 的
  /// 预算下**每块的字大了一倍**;再带 8% 重叠,避免把划在切口上的词切断。
  ///
  /// 用途:第二遍"只找漏"复查(结果追加,不替换第一遍)。
  /// [quarterTurns]:同 [prepare] 的手动角度(B0-6:旋转重试后复查也要按同一角度切)
  static List<Uint8List> tiles(
    Uint8List raw, {
    int rows = 2,
    int cols = 2,
    double overlap = 0.08,
    bool autoRotate = true,
    bool enhanceMarks = false,
    int quarterTurns = 0,
  }) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return [prepare(raw, quarterTurns: quarterTurns)];
      var work = img.bakeOrientation(decoded);
      // B0-3:同 prepare —— 方向检测复用这张已解码的图,不再多解一次整图
      if (autoRotate && detectRotationOf(work) == rotationClockwise90) {
        work = img.copyRotate(work, angle: 90);
      }
      final turns = quarterTurns % 4;
      if (turns != 0) work = img.copyRotate(work, angle: turns * 90);
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
      return [prepare(raw, quarterTurns: quarterTurns)];
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
    int quarterTurns = 0,
  }) =>
      tiles(
        raw,
        rows: rows,
        cols: cols,
        overlap: overlap,
        autoRotate: autoRotate,
        enhanceMarks: enhanceMarks,
        quarterTurns: quarterTurns,
      ).map((t) => 'data:image/jpeg;base64,${base64Encode(t)}').toList();

  // ── 后台 isolate 入口(B0-3:图片预处理不再占 UI isolate) ──
  //
  // 为什么必须移:一张 12MP 图 `package:image` 解码一次 RGBA ≈ 20MB,压缩/
  // 方向检测/划线增强/编码全是**同步纯 Dart**;跑在 UI isolate 上就是"主线程
  // 长时间阻塞 → 追加时叠加第二遍复查 → native OOM/ANR 被杀"(Dart 层
  // CrashLogger 抓不到,所以反复修还有)。`image` 是纯 Dart 包,能直接在
  // isolate 里跑,UI 线程只负责发请求。
  //
  // 为什么参数用 List<Object?> 而不是自定义参数类:跨 isolate 消息对自定义
  // 实例的可发送性依赖 Dart 版本,只传 Uint8List/bool/int 最稳,不会在真机上
  // 抛 "Illegal argument in isolate message"。
  static Uint8List _prepareTask(List<Object?> args) => prepare(
        args[0] as Uint8List,
        autoRotate: args[1] as bool,
        enhanceMarks: args[2] as bool,
        quarterTurns: args[3] as int,
      );

  static String _dataUriTask(List<Object?> args) => toDataUri(
        args[0] as Uint8List,
        autoRotate: args[1] as bool,
        enhanceMarks: args[2] as bool,
        quarterTurns: args[3] as int,
      );

  static List<Uint8List> _tilesTask(List<Object?> args) => tiles(
        args[0] as Uint8List,
        autoRotate: args[1] as bool,
        enhanceMarks: args[2] as bool,
        quarterTurns: args[3] as int,
      );

  /// 后台 isolate 版 [prepare](识图链路一律用它)
  static Future<Uint8List> prepareInBackground(
    Uint8List raw, {
    bool autoRotate = true,
    bool enhanceMarks = false,
    int quarterTurns = 0,
  }) =>
      compute(
        _prepareTask,
        <Object?>[raw, autoRotate, enhanceMarks, quarterTurns],
        debugLabel: 'vision_prepare',
      );

  /// 后台 isolate 版 [toDataUri](JPEG 编码 + base64 也挪出 UI 线程)
  static Future<String> toDataUriInBackground(
    Uint8List raw, {
    bool autoRotate = true,
    bool enhanceMarks = false,
    int quarterTurns = 0,
  }) =>
      compute(
        _dataUriTask,
        <Object?>[raw, autoRotate, enhanceMarks, quarterTurns],
        debugLabel: 'vision_data_uri',
      );

  /// 后台 isolate 版 [tiles](第二遍高清复查用)
  static Future<List<Uint8List>> tilesInBackground(
    Uint8List raw, {
    int rows = 2,
    int cols = 2,
    double overlap = 0.08,
    bool autoRotate = true,
    bool enhanceMarks = false,
    int quarterTurns = 0,
  }) =>
      compute(
        _tilesTask,
        <Object?>[raw, autoRotate, enhanceMarks, quarterTurns],
        debugLabel: 'vision_tiles',
      );

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
