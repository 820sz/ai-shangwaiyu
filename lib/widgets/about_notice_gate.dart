import 'package:flutter/material.dart';

import '../screens/profile/about_notice_screen.dart';
import '../services/about_notice.dart';

/// 首次启动公告的挂载点（由 `lib/app.dart` 包在主壳外面）。
///
/// 为什么做成"包一层"而不是在 app.dart 里写一段逻辑：
/// - app.dart 是集成层（Lead 所有），这里只暴露**一个 Widget + 一个静态方法**，
///   集成改动就是一行 `AboutNoticeGate(child: _RootShell(...))`；
/// - 检查发生在**首帧之后**（addPostFrameCallback），不拖慢启动、不抢开屏动画；
/// - 只在"没读过"时用全屏路由推公告页；用户点「我已阅读并继续」才写标记
///   （用返回键/系统手势退出不会写标记 —— 下次启动仍会提醒，符合"必须确认"）。
///
/// 接线方式（app.dart）：
/// ```dart
/// home: SplashScreen(
///   child: AboutNoticeGate(child: _RootShell(...)),
/// ),
/// ```
class AboutNoticeGate extends StatefulWidget {
  const AboutNoticeGate({
    super.key,
    required this.child,
    this.autoCheck = true,
  });

  final Widget child;

  /// 测试/特殊场景可关掉自动检查（默认开启）
  final bool autoCheck;

  /// 打开公告页（首次启动 & 关于页"重看"共用）。
  /// 返回 true = 用户点了「我已阅读并继续 / 关闭」。
  static Future<bool> show(BuildContext context) async {
    final bool? ok = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (BuildContext _, Animation<double> _, Animation<double> _) =>
            const AboutNoticeScreen(),
        transitionsBuilder: (
          BuildContext _,
          Animation<double> animation,
          Animation<double> secondary,
          Widget child,
        ) {
          final CurvedAnimation curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    return ok == true;
  }

  @override
  State<AboutNoticeGate> createState() => _AboutNoticeGateState();
}

class _AboutNoticeGateState extends State<AboutNoticeGate> {
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    if (!widget.autoCheck) return;
    // 首帧之后再检查：此时 SplashScreen 已开始动画、Navigator 已就绪
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    if (!AboutNotice.shouldShow) return;
    // 不要盖在别的路由上面（例如从深链直接进到详情页时）
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final bool confirmed = await AboutNoticeGate.show(context);
    if (!mounted) return;
    if (confirmed) {
      await AboutNotice.markSeen();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
