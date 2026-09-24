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

  // 启动 3 秒后静默检查更新(失败静默,不打扰使用)
  Future.delayed(const Duration(seconds: 3), _checkUpdateSilently);

  // 桌面小组件(v2.2):等首帧画完再推送。
  // 为什么不放在 runApp 之前 —— 这一步要查 SQLite(到期数/任务/日志),
  // 放在启动路径上会让冷启动多等一次数据库;而小组件晚几秒更新没有任何影响。
  Future.delayed(const Duration(seconds: 2), _syncWidgetSilently);
}

/// 把"今天该做什么"推给桌面小组件(失败静默:小组件只是顺带,不该打扰使用)
Future<void> _syncWidgetSilently() async {
  await WidgetService.sync();
}

Future<void> _checkUpdateSilently() async {
  final ctx = appNavigatorKey.currentContext;
  if (ctx == null) return;
  final info = await UpdateService.checkLatestRelease();
  if (info != null && info.hasUpdate && ctx.mounted) {
    showUpdateDialog(ctx, info);
  }
}
