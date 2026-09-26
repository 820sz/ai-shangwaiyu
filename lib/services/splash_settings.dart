import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';

/// 开屏与退出的文案设置(v2.5,M3 用户要求)。
///
/// 用户原话:「增加开屏动画和关闭动画 —— 软件 logo 渐显动画 + 下面的一行文案渐显 ——
/// **支持用户自定义文案**,目前开屏文案定为"让语言,回归本质";退出软件的提示动画
/// 就是字幕选项"辛苦啦,再学一会儿?"和"累了~休息啦"两个选项」。
///
/// 所以:开屏文案可改(空 = 恢复默认),退出文案固定为这两句(是产品语气的一部分,
/// 不给改,避免用户改出"确定/取消"这种没有温度的字幕)。
class SplashSettings {
  SplashSettings._();

  /// 默认开屏文案
  static const String defaultTagline = '让语言,回归本质';

  /// 退出提示的两句话
  static const String exitStay = '辛苦啦,再学一会儿?';
  static const String exitLeave = '累了~休息啦';

  /// 现在的开屏文案(读不到/空 → 默认)
  static String tagline() {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings)
          .get(AppConstants.keySplashTagline);
      final t = raw is String ? raw.trim() : '';
      return t.isEmpty ? defaultTagline : t;
    } catch (e) {
      debugPrint('ReadFlow 读取开屏文案失败(用默认): $e');
      return defaultTagline;
    }
  }

  /// 保存开屏文案;传空/全空白 = 恢复默认(写空串)
  static Future<void> setTagline(String text) async {
    try {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keySplashTagline, text.trim());
    } catch (e) {
      debugPrint('ReadFlow 保存开屏文案失败: $e');
    }
  }

  /// 今天是否已经问过"要不要退出"(一天只问一次,用户选的行为)
  static bool exitPromptShownToday() {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings)
          .get(AppConstants.keyExitPromptDate);
      return raw is String && raw == _todayKey();
    } catch (_) {
      return false;
    }
  }

  static Future<void> markExitPromptShown() async {
    try {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyExitPromptDate, _todayKey());
    } catch (e) {
      debugPrint('ReadFlow 记录退出提示失败: $e');
    }
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }
}
