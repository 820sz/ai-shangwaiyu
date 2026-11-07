import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';

/// 「首次启动开屏公告」的持久化标记。
///
/// 只做一件事:记住用户有没有点过「我已阅读并继续」。
/// - 用**独立的 key**(`about_notice_seen_v1`),不污染其它设置;
/// - 任何异常都当"没看过"处理(宁可多弹一次,也不要因为 Hive 挂了就永远不弹);
/// - 公告内容/文风以后大改时,把版本后缀从 `_v1` 升到 `_v2` 即可再次公告。
class AboutNotice {
  AboutNotice._();

  static const String seenKey = 'about_notice_seen_v1';

  static Box<dynamic>? get _box {
    try {
      if (Hive.isBoxOpen(AppConstants.hiveBoxSettings)) {
        return Hive.box<dynamic>(AppConstants.hiveBoxSettings);
      }
    } catch (_) {}
    return null;
  }

  /// 是否已经读过（Hive 读不到 = false，即"该弹"）
  static bool get seen {
    try {
      final Object? v = _box?.get(seenKey);
      return v == true || v == 'true';
    } catch (_) {
      return false;
    }
  }

  /// 是否应该弹（只在首次启动时为 true）
  static bool get shouldShow => !seen;

  /// 点「我已阅读并继续」后写标记；写失败不抛（下次再弹一次而已）
  static Future<void> markSeen() async {
    try {
      await _box?.put(seenKey, true);
    } catch (_) {
      // 忽略：公告不是关键路径
    }
  }

  /// 测试/调试用：清掉标记（让下一次启动重新弹）
  static Future<void> reset() async {
    try {
      await _box?.delete(seenKey);
    } catch (_) {}
  }
}
