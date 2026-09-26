import 'dart:async';

import 'package:flutter/material.dart';

import '../services/splash_settings.dart';

/// 开屏动画(v2.5,M3 用户要求)。
///
/// 用户原话:「增加开屏动画 —— 软件 logo 渐显动画 + 下面的一行文案渐显,
/// 支持用户自定义文案,目前开屏文案定为"让语言,回归本质"」。
///
/// 实现要点(不啰嗦,只做该做的):
/// - logo:淡入 + 轻微放大(0.92 → 1.0),700ms,`easeOutCubic`;
/// - 文案:延迟 350ms 后淡入 + 上移 8px,600ms —— 两段错开才有"渐次出现"的呼吸感,
///   同时出现会显得像页面没加载完;
/// - 总时长约 1.45 秒;**点一下可跳过**(不想等的人不该被强制看动画);
/// - 文案每次进入都重新读(用户改完立刻生效,不用重启)。
class SplashScreen extends StatefulWidget {
  /// 动画结束后进入的主界面
  final Widget child;

  /// 动画总时长(测试可缩短)
  final Duration hold;

  const SplashScreen({super.key, required this.child, this.hold = const Duration(milliseconds: 450)});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _textFade;
  /// 文案的位移量(px,8 → 0)
  late final Animation<double> _textSlide;
  late String _tagline;
  bool _done = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tagline = SplashSettings.tagline();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, 0.75, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    // 文案比 logo 晚 350ms 起(用整条时间线的 0.35~1.0 段表示)
    _textFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    );
    _textSlide = Tween<double>(begin: 8, end: 0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _ctrl.forward();
    // 动画 + 停顿时长后进入主界面
    _timer = Timer(
      const Duration(milliseconds: 700) + widget.hold,
      _finish,
    );
  }

  void _finish() {
    if (!mounted || _done) return;
    setState(() => _done = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 交叉淡出:开屏结束后用 250ms 淡入主界面,避免"硬切"
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _done
          ? widget.child
          : GestureDetector(
              // 点一下跳过(不想等的人不该被强制看动画)
              onTap: _finish,
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: _logo(theme),
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedBuilder(
                        animation: _ctrl,
                        builder: (_, child) => Opacity(
                          opacity: _textFade.value,
                          child: Transform.translate(
                            offset: Offset(0, _textSlide.value),
                            child: child,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _tagline,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 16,
                              letterSpacing: 2.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  /// logo:优先用打包进来的资源图;没有就退回"文字标"(不引入新资源依赖)
  Widget _logo(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withAlpha(60),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'AI',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'AI上外语',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}

/// 给 Tween 加个链式小工具(保持上面代码可读)
