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
  ///
  /// v3 批 8(C1-11 用户点名"字号默认偏大"):默认从 100% 下调到 85% 档 ——
  /// 16 × 0.85 ≈ 13.6 号,长文连续阅读更稳;想大一点在阅读设置里调回即可
  /// (设置入口一直是显式的,不改用户已保存的选择)。
  static const double defaultFontScale = 0.85;

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

  // ═══════════════════════════════════════════════════════════════════
  // C 方案阅读排印(2026-11-06 用户拍板)
  //
  // 为什么另起一组常量而不改上面的 baseFontSize/档位:
  // 上面那组是两个阅读器(材料 / 输出文章)共用的**历史口径**,直接改基准
  // 会顺带改掉输出板块文章阅读器的观感 —— 本轮只允许改阅读器主题内的东西。
  // 所以 C 用「档位下标 → C 字号」的映射:用户原来 5 档字号 / 3 档行距的选择
  // 完全保留(旧键、旧值都还能读),只是落到 C 的号数上。
  // ═══════════════════════════════════════════════════════════════════

  /// C 方案正文号数表:用户 5 档字号依次落在这 5 个号上(默认第 0 档 = 18 号)
  static const List<double> cFontSizes = [18, 19.5, 21, 22.5, 24];

  /// C 方案行距:紧凑 / 标准 / 宽松(默认标准 = 1.8 —— C 规范正文 18/1.8)
  static const List<double> cLineHeights = [1.6, 1.8, 2.0];

  /// 当前设置对应的 C 正文号数(默认 18)
  static double cBodyFontSize() => cFontSizes[scaleIndex(fontScale())];

  /// 当前设置对应的 C 正文行高(默认 1.8)
  static double cBodyLineHeight() => cLineHeights[lineHeightIndex(lineHeight())];

  /// 设置面板/控制台显示用的短标签:「18 号」「21 号」
  static String cFontLabel(double size) {
    final rounded = size.roundToDouble();
    return (size - rounded).abs() < 0.01
        ? '${rounded.toInt()} 号'
        : '${size.toStringAsFixed(1)} 号';
  }

  /// 纸张三色(C 方案 + B 方案的纸张色卡,用户 2026-11-06 拍板)
  ///
  /// - [white] 纸白(冷灰纸 #EEEFEA,默认 —— C 方案基底);
  /// - [beige] 米黄(暖纸 #F4EFE3,搬 B 方案的暖纸);
  /// - [night] 墨夜(深色纸 #16181C)。
  ///
  /// 只存枚举名,不存色值:色值表在 `lib/widgets/reader_paper.dart`
  /// ([ReaderPalette]),换配色不需要写迁移。
  static const String keyReaderPaper = 'reader_paper';

  static ReaderPaper paper() {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings).get(keyReaderPaper);
      if (raw is String) {
        for (final p in ReaderPaper.values) {
          if (p.name == raw) return p;
        }
      }
      if (raw is int && raw >= 0 && raw < ReaderPaper.values.length) {
        // 容错:手改配置写成 0/1/2 也能读
        return ReaderPaper.values[raw];
      }
    } catch (e) {
      debugPrint('ReadFlow 读取纸张设置失败(用默认): $e');
    }
    return ReaderPaper.white;
  }

  static Future<void> setPaper(ReaderPaper value) async {
    try {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(keyReaderPaper, value.name);
    } catch (e) {
      debugPrint('ReadFlow 保存纸张设置失败: $e');
    }
  }

  /// 纸张显示名(设置面板用)
  static String paperLabel(ReaderPaper value) => value.label;
}

/// 纸张三色(持久化在 `reader_settings` 的 settings Hive box 里)
enum ReaderPaper {
  /// 纸白:冷灰纸,默认(C 方案基底)
  white('纸白', '冷灰纸 · 默认'),

  /// 米黄:暖纸(搬 B 方案的纸张)
  beige('米黄', '暖纸 · 长时间读'),

  /// 墨夜:深色纸
  night('墨夜', '深色纸 · 夜里读');

  const ReaderPaper(this.label, this.hint);

  /// 显示名(纸白 / 米黄 / 墨夜)
  final String label;

  /// 一句说明(色卡下面那行小字)
  final String hint;
}
