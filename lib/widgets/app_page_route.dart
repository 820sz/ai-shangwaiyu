import 'package:flutter/material.dart';

import '../config/design_tokens.dart';

/// 轻量页面转场(v3 · 批 6 动效)。
///
/// 为什么只做这一种:用户 2026-11-01 对动效的要求是"高级但不眼花缭乱"。
/// 默认 Material 转场在"练习流"里（首页 → 选来源 → 练习器 → 结果）会显得跳;
/// 统一成 **淡入 + 8px 上滑**,时长 220ms、`easeOutCubic`:
/// - 足够让用户感知"进入下一层",不打断节奏;
/// - 页面内容不缩放（缩放最容易在长列表里掉帧/花眼）;
/// - 系统开了"减少动画"(无障碍)或测试环境 `disableAnimations` 时直接零时长。
///
/// 不用 `MaterialPageRoute` 的默认右滑:输出模块是"钻取"关系(选来源→做题),
/// 右滑会被读成"同级前进",而上滑更接近"展开一层"。
class AppPageRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;

  AppPageRoute({required this.builder})
      : super(
          transitionDuration: const Duration(milliseconds: 220),
          reverseTransitionDuration: const Duration(milliseconds: 180),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondary, child) {
            // 无障碍/测试:不做动画(也避免测试里 settle 不掉)
            if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
              return child;
            }
            final curved = CurvedAnimation(
              parent: animation,
              curve: Motion.curve,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// 统一入口:像 `Navigator.push(context, AppPageRoute(builder: ...))` 一样用。
Future<T?> appPush<T>(BuildContext context, WidgetBuilder builder) {
  return Navigator.push<T>(context, AppPageRoute<T>(builder: builder));
}
