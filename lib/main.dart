import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'config/constants.dart';
import 'providers/vocab_provider.dart';
import 'providers/article_provider.dart';
import 'providers/stats_provider.dart';
import 'providers/bookmark_provider.dart';
import 'services/theme_controller.dart';
import 'services/update_service.dart';
import 'services/widget_service.dart';
import 'utils/crash_logger.dart';
import 'widgets/update_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 崩溃捕获先行:任何后续初始化/运行期异常落盘 crash_log.txt,
  // 真机闪退不再盲猜(v1.3.2)
  await CrashLogger.install();

  // 初始化 Hive（本地 KV 存储，用于 API Key 等配置）
  await Hive.initFlutter();
  await Hive.openBox(AppConstants.hiveBoxSettings);

  // 主题档位要在 runApp 之前读回来,否则首帧会先亮白底再跳深色(闪一下)
  ThemeController.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VocabProvider()),
        ChangeNotifierProvider(create: (_) => ArticleProvider()),
        ChangeNotifierProvider(create: (_) => StatsProvider()),
        // 启动即加载收藏夹——识别页/追问页星标状态随时准确
        ChangeNotifierProvider(create: (_) => BookmarkProvider()..load()),
      ],
      child: const ReadFlowApp(),
    ),
  );

  // v3(2026-11-01 用户):"点进软件自动提示新版本"。
  // 时机:首帧画完 + 开屏动画走完(约 1.4s)后再查,避免弹窗被开屏压住;
  // 每天最多自动查一次(Hive 节流),手动「检查更新」不受限。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(seconds: 2), _checkUpdateOnLaunch);
  });

  // 桌面小组件(v2.2):等首帧画完再推送。
  // 为什么不放在 runApp 之前 —— 这一步要查 SQLite(到期数/任务/日志),
  // 放在启动路径上会让冷启动多等一次数据库;而小组件晚几秒更新没有任何影响。
  Future.delayed(const Duration(seconds: 2), _syncWidgetSilently);
}

/// 进 App 自动检查更新(v3,2026-11-01 用户新增要求)。
///
/// 以前的问题(用户原话:"只有手动点才会推送新版本"):
/// - 旧实现 `Future.delayed(3s)` 后直接取 `appNavigatorKey.currentContext`,
///   启动早期拿到 null 就 return,之后再也不会检查;
/// - `checkLatestRelease()` 抛异常(国内网络常态)时没有人 catch,于是静默失败;
/// - 就算查到了,弹窗里塞的是整段 markdown 汇报文,不像"升级说明"。
///
/// 现在的策略:
/// 1. 等首帧 + 开屏结束后再查;Navigator 没就绪最多等 10 秒;
/// 2. 每天最多自动查一次(Hive 记时间戳);手动按钮不走这个节流;
/// 3. 任何异常都吞掉(不打扰使用),但 debugPrint 留痕便于诊断。
Future<void> _checkUpdateOnLaunch() async {
  try {
    final now = DateTime.now();
    final lastMs = await UpdateService.lastAutoCheckMs();
    if (!UpdateService.isAutoCheckDue(lastMs, now)) return;

    final ctx = await _waitForAppContext();
    if (ctx == null || !ctx.mounted) return;

    final info = await UpdateService.checkLatestRelease();
    // 成功拿到响应(不论有没有新版)才记时间戳:失败的话下次启动还能重试
    await UpdateService.markAutoCheckDone(now);
    if (info != null && info.hasUpdate && ctx.mounted) {
      await showUpdateDialog(ctx, info);
    }
  } catch (e) {
    // 网络失败是常态,不打扰用户;但不要吞成"什么都没有"
    debugPrint('ReadFlow 自动检查更新失败(静默): $e');
  }
}

/// 等 App 的 Navigator 就绪(启动早期 `appNavigatorKey.currentContext` 可能为 null)。
Future<BuildContext?> _waitForAppContext() async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) return ctx;
    await Future.delayed(const Duration(milliseconds: 400));
  }
  return null;
}

/// 把"今天该做什么"推给桌面小组件(失败静默:小组件只是顺带,不该打扰使用)
Future<void> _syncWidgetSilently() async {
  await WidgetService.sync();
}
