import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';

/// 阅读器显示设置(v2.5,U2):**字号**与**行距**。
///
/// 为什么要有:材料/文章的正文之前是写死的 16 号 + 1.7 倍行距 —— 手机上偏小,
/// 而"长时间读英文"恰恰是最需要放大与拉开行距的场景(用户本轮要求:前端与体验
/// 大升级,阅读器字号行距要能调)。
///
/// 设计取舍:
/// - 只给**档位**不给无级滑杆:无级滑杆调不出"和上次一样"的手感,档位可以被记住
///   也能被描述("我一般用 115%");
/// - 行距只给 3 档(紧凑/标准/宽松),不做数字输入;
/// - 两个阅读器(材料 / 文章)共用同一份设置 —— 用户在哪儿调都是同一份偏好;
/// - 这里是**用户偏好**,乘在基准字号上;系统无障碍字号(WCAG/2× 缩放)由
///   MediaQuery 的 textScaler 叠加,**不在这里覆盖**(那会破坏无障碍)。
class ReaderSettings {
  ReaderSettings._();

  /// 字号档位(乘数,基准 16 号)
  static const List<double> fontScales = [0.85, 1.0, 1.15, 1.3, 1.5];

  /// 标准档(默认)
  static const double defaultFontScale = 1.0;

  /// 行距档位与名字
  static const List<double> lineHeights = [1.5, 1.7, 2.0];
  static const List<String> lineHeightLabels = ['紧凑', '标准', '宽松'];
  static const double defaultLineHeight = 1.7;

  /// 正文基准字号(各阅读器都用它 × fontScale)
  static const double baseFontSize = 16;

  /// 当前字号乘数(读不到/越界 → 夹到最近的合法档位)
  static double fontScale() =>
      _nearestScale(_readDouble(AppConstants.keyReaderFontScale, defaultFontScale));

  static Future<void> setFontScale(double value) async {
    await _write(AppConstants.keyReaderFontScale, _nearestScale(value));
  }

  /// 当前行距(读不到/越界 → 默认 1.7)
  static double lineHeight() => _nearestLineHeight(
      _readDouble(AppConstants.keyReaderLineHeight, defaultLineHeight));

  static Future<void> setLineHeight(double value) async {
    await _write(AppConstants.keyReaderLineHeight, _nearestLineHeight(value));
  }

  /// 字号档位的显示名(85% / 100% …)
  static String scaleLabel(double scale) => '${(scale * 100).round()}%';

  /// 行距档位的显示名(紧凑 / 标准 / 宽松)
  static String lineHeightLabel(double height) {
    final i = lineHeights.indexOf(_nearestLineHeight(height));
    return i < 0 ? '标准' : lineHeightLabels[i];
  }

  /// 取档位下标(界面上的分段按钮 / 上下一档要用)
  static int scaleIndex(double scale) {
    final i = fontScales.indexOf(_nearestScale(scale));
    return i < 0 ? fontScales.indexOf(defaultFontScale) : i;
  }

  static int lineHeightIndex(double height) {
    final i = lineHeights.indexOf(_nearestLineHeight(height));
    return i < 0 ? lineHeights.indexOf(defaultLineHeight) : i;
  }

  /// 夹到最近的合法档位(非法输入 → 默认档,而不是崩/乱)
  static double _nearestScale(double value) {
    if (value.isNaN || value.isInfinite) return defaultFontScale;
    var best = fontScales.first;
    for (final s in fontScales) {
      if ((s - value).abs() < (best - value).abs()) best = s;
    }
    return best;
  }

  static double _nearestLineHeight(double value) {
    if (value.isNaN || value.isInfinite) return defaultLineHeight;
    var best = lineHeights.first;
    for (final h in lineHeights) {
      if ((h - value).abs() < (best - value).abs()) best = h;
    }
    return best;
  }

  static double _readDouble(String key, double fallback) {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings).get(key);
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw) ?? fallback;
      return fallback;
    } catch (e) {
      debugPrint('ReadFlow 读取阅读设置失败(用默认): $e');
      return fallback;
    }
  }

  static Future<void> _write(String key, double value) async {
    try {
      await Hive.box(AppConstants.hiveBoxSettings).put(key, value);
    } catch (e) {
      debugPrint('ReadFlow 保存阅读设置失败: $e');
    }
  }
}
