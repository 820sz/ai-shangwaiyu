import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import '../config/theme.dart';

/// 深浅色设置(v2.2)。
///
/// 为什么做成 ValueNotifier 而不是 Provider:主题是 `MaterialApp` 的**入参**,
/// 切换时必须重建整棵树;ValueNotifier 在这里最直接(少一层依赖),
/// 而且**纯解析逻辑**(parse/id)能单独测 —— 存错档位会导致"选了深色却还是白底"
/// 这种一眼可见但难查的问题。
class ThemeController {
  ThemeController._();

  /// 当前生效的档位(默认跟随系统)
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// 从 Hive 读回(启动时调用一次;读不到就保持"跟随系统")
  static ThemeMode load() {
    try {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      final raw = box.get(AppConstants.keyThemeMode);
      final parsed = AppTheme.themeModeOf(raw is String ? raw : null);
      mode.value = parsed;
      return parsed;
    } catch (e) {
      // Hive 还没打开/读失败:跟随系统是安全的默认值,不该让启动崩掉
      debugPrint('ReadFlow 读取主题设置失败(用跟随系统): $e');
      return mode.value;
    }
  }

  /// 切换并落盘。写盘失败不影响本次生效(下次启动会退回默认值),
  /// 所以这里只记日志。
  static Future<void> set(ThemeMode next) async {
    mode.value = next;
    try {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyThemeMode, AppTheme.themeModeId(next));
    } catch (e) {
      debugPrint('ReadFlow 保存主题设置失败: $e');
    }
  }
}
