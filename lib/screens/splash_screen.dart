import 'dart:async';

import 'package:flutter/material.dart';

import '../services/splash_settings.dart';
import '../widgets/splash_graphics.dart';

/// 开屏动画(v2.29.0 · 方案 A「琉璃凝结」)。
///
/// 历史:用户 v2.5 要求「logo 渐显 + 文案渐显、支持自定义文案」(那时是素底 + 84 方块);
/// 2026-11-07 用户提出:「现在素白背景,我想改成你软件内置那个琉璃玻璃,
/// 然后 logo 和开屏动画想想有没有更好的方案」。
/// 选型与关键帧见 `docs/SPLASH-LOGO-OPTIONS-2026-11-07.md`;实现就在
/// [SplashKineticA](纯函数 `t → 画面`),预览渲染与线上是**同一份代码**。
///
/// 保留的行为(一个都不能丢):
/// - **点击任意处跳过**(不想等的人不该被强制看动画);
/// - 文案每次进入都重新读 [SplashSettings.tagline](用户改完立刻生效);
/// - `hold` 参数保留(动画结束后的额外停留,默认 0);
/// - 结束用 250ms 交叉淡出切到 [child];
/// - [child] 里包的 `AboutNoticeGate` 顺序不变 —— 只有 `_done == true` 之后它才首次
///   build,所以首启「关于」公告永远弹在开屏之后。
///
/// 无障碍/降级:`MediaQuery.disableAnimations == true` 时**不等动画**,
/// 直接渲染终帧 + 200ms 淡入(不让"减少动效"的用户干等 1.5 秒)。
class SplashScreen extends StatefulWidget {
  /// 动画结束后进入的主界面
  final Widget child;

  /// 动画结束后的额外停留(默认 0:总时长约 1.5s,含 80ms 静止尾)
  final Duration hold;

  const SplashScreen({
    super.key,
    required this.child,
    this.hold = Duration.zero,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// 动画总长 1.5s:预览里的时间轴是 0~1.5s(t = value × 1.5)
  static const Duration _animDuration = Duration(milliseconds: 1500);

  /// 减少动效时的淡入时长
  static const Duration _reducedFade = Duration(milliseconds: 200);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _animDuration,
  )..addStatusListener(_onStatus);

  late String _tagline;
  bool _done = false;
  bool _started = false;
  bool _reduced = false;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _tagline = SplashSettings.tagline();
  }

  /// 首次拿到 MediaQuery 后再决定走动画还是走降级(disableAnimations 只在 context 里)
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _reduced = true;
      _ctrl.value = 1.0; // 直接终帧
      _holdTimer = Timer(_reducedFade, _finish);
    } else {
      _ctrl.forward();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _reduced) return;
    if (widget.hold <= Duration.zero) {
      _finish();
    } else {
      _holdTimer = Timer(widget.hold, _finish);
    }
  }

  void _finish() {
    if (!mounted || _done) return;
    setState(() => _done = true);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _done
          ? widget.child
          : GestureDetector(
              // 点一下跳过(不想等的人不该被强制看动画)
              behavior: HitTestBehavior.opaque,
              onTap: _finish,
              child: Material(
                // 开屏页没有 Scaffold:补一层透明 Material,让文字继承主题的
                // DefaultTextStyle(否则中文会落到平台兜底样式上)。
                type: MaterialType.transparency,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) => SplashKineticA(
                    t: _ctrl.value * 1.5,
                    dark: dark,
                    tagline: _tagline,
                  ),
                ),
              ),
            ),
    );
  }
}
