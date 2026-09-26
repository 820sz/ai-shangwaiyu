import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/theme.dart';
import 'services/theme_controller.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/exit_prompt.dart';
import 'screens/splash_screen.dart';
import 'screens/tutor/tutor_home.dart';
import 'screens/input/input_home.dart';
import 'screens/output/output_home.dart';
import 'screens/profile/profile_home.dart';

/// 全局导航 Key:供启动时的静默更新检查弹窗使用
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 让子页面能请求"切到某个 tab"(v2.0 导师任务卡需要:
/// 点"复习 30 个词"应该直接跳过去,而不是让用户自己找入口)。
class AppTabs extends InheritedWidget {
  final void Function(ReadFlowTab tab) switchTo;

  const AppTabs({super.key, required this.switchTo, required super.child});

  static AppTabs? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppTabs>();

  @override
  bool updateShouldNotify(AppTabs oldWidget) => false;
}

class ReadFlowApp extends StatefulWidget {
  const ReadFlowApp({super.key});

  @override
  State<ReadFlowApp> createState() => _ReadFlowAppState();
}

class _ReadFlowAppState extends State<ReadFlowApp> {
  /// 默认落在「学习助理」页 —— 打开 App 先看到"今天学什么"。
  /// 注意:它在底栏是**最右**一格(v2.2 用户调整后的顺序),
  /// 所以启动时选中的是最右项,这是刻意的(入口位 ≠ 优先级)。
  ReadFlowTab _currentTab = ReadFlowTab.tutor;

  @override
  Widget build(BuildContext context) {
    // 主题切换要重建整棵 MaterialApp(theme/darkTheme/themeMode 都是它的入参),
    // 所以这里监听 ValueNotifier 而不是用 Builder 局部刷新
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'AI上外语',
        debugShowCheckedModeBanner: false,
        navigatorKey: appNavigatorKey,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        // v2.5(M3):开屏动画(logo 渐显 + 文案渐显)包在主界面外面,
        // 动画结束或用户点一下即进入;分页切换等仍走原来的路由
        home: SplashScreen(
          child: _RootShell(
            currentTab: _currentTab,
            onTabChanged: (tab) => setState(() => _currentTab = tab),
          ),
        ),
      ),
    );
  }
}

/// 主壳(四栏 + 底部导航)。抽成独立 widget 是为了让开屏动画只包住它,
/// 而不影响 `_ReadFlowAppState` 的 setState 语义。
class _RootShell extends StatelessWidget {
  final ReadFlowTab currentTab;
  final void Function(ReadFlowTab tab) onTabChanged;

  const _RootShell({required this.currentTab, required this.onTabChanged});

  @override
  Widget build(BuildContext context) {
    return AppTabs(
      switchTo: onTabChanged,
      child: PopScope(
        // v2.5(M3):根页面按返回 → 先出"字幕式退出确认"(一天只问一次);
        // 用户选"累了~休息啦"才真的退出。子路由的返回不受影响(它们不在这一层)。
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final leave = await ExitPrompt.show(context);
          if (leave) {
            // 系统级退出(不杀进程)
            await SystemNavigator.pop();
          }
        },
        child: Scaffold(
          body: IndexedStack(
            // 顺序必须与 ReadFlowTab 枚举一致(输入 / 输出 / 我的 / 学习助理)
            index: currentTab.index,
            children: const [
              InputHomeScreen(),
              OutputHomeScreen(),
              ProfileHomeScreen(),
              TutorHomeScreen(),
            ],
          ),
          bottomNavigationBar: ReadFlowBottomNav(
            currentTab: currentTab,
            onTabChanged: onTabChanged,
          ),
        ),
      ),
    );
  }
}
