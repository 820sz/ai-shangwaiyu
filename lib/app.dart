import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'widgets/bottom_nav.dart';
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
  /// v2.0:默认落在「导师」页 —— 打开 App 先看到"今天学什么"
  ReadFlowTab _currentTab = ReadFlowTab.tutor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI上外语',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: AppTheme.lightTheme,
      home: AppTabs(
        switchTo: (tab) => setState(() => _currentTab = tab),
        child: Scaffold(
          body: IndexedStack(
            index: _currentTab.index,
            children: const [
              TutorHomeScreen(),
              InputHomeScreen(),
              OutputHomeScreen(),
              ProfileHomeScreen(),
            ],
          ),
          bottomNavigationBar: ReadFlowBottomNav(
            currentTab: _currentTab,
            onTabChanged: (tab) {
              setState(() => _currentTab = tab);
            },
          ),
        ),
      ),
    );
  }
}
