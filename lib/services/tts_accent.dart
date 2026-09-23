import 'package:hive/hive.dart';

import '../config/constants.dart';

/// 朗读音色档位 → TTS 语言码(v2.0,纯函数,可单测)。
///
/// 为什么不直接把语言码存进 Hive:'system'(跟随系统)不是一个语言码,
/// 它要按设备当前语区动态解析 —— 存语言码等于把这个决策固化死。
///
/// 映射:
/// - `'uk'`     → `'en-GB'`
/// - `'us'`     → `'en-US'`
/// - `'system'` → null(由调用方按已初始化的引擎语言原样朗读)
/// - 其余/空值  → null(未知档位当"跟随系统",不让配置损坏导致朗读静默失效)
String? ttsLanguageForAccent(String? accent) {
  switch (accent) {
    case 'uk':
      return 'en-GB';
    case 'us':
      return 'en-US';
    default:
      return null;
  }
}

/// 档位 → 设置页/诊断页文案(未知档位按默认项显示)
String ttsAccentLabel(String? accent) =>
    AppConstants.ttsAccentOptions[accent] ??
    AppConstants.ttsAccentOptions['system']!;

/// 读用户选择的朗读音色档位。
///
/// 同步读 Hive:调用点在按钮回调里,取值必须立刻可用(朗读不能等异步)。
/// Hive 未初始化(单元测试/极早期调用)→ 回退 `'system'`,绝不抛。
String loadTtsAccent() {
  try {
    final v = Hive.box(AppConstants.hiveBoxSettings)
        .get(AppConstants.keyTtsAccent);
    return v is String && v.isNotEmpty ? v : 'system';
  } catch (_) {
    return 'system';
  }
}
