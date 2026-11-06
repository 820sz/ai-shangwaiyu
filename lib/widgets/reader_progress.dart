import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'reader_paper.dart';

/// C 方案(2026-11-06 用户拍板)的**常驻进度**。
///
/// 用户第 3 条抱怨:"上下滑动没有阅读进度百分比"。现状审计的结论是
/// 数据早就有(`material_progress.percent` + 滚动比例),缺的是:
/// 1. 一个**常驻**容器(旧实现把 `$pct%` 画在列表第 0 项里,一滑就滚走了);
/// 2. 一个**只重建自己**的通知源(旧 `_onScroll` 从头到尾没有 setState)。
///
/// 所以这里两个组件都只吃 `ValueListenable<double>`(0~1),
/// 配合页面里的 `ValueNotifier` —— 滚动每帧只重建这 2 个像素级组件,
/// 不 setState 整屏(否则 _buildUnit 里上千个 TapGestureRecognizer 会跟着重建)。

/// 右侧悬浮进度:`37%` 胶囊 + 96px 竖轨道(3px 宽,砖红按比例填充)。
///
/// 位置由页面用 `Align` 决定;这里只管形状与数据。
class ReaderProgressRail extends StatelessWidget {
  const ReaderProgressRail({
    super.key,
    required this.progress,
    required this.palette,
    this.onTap,
  });

  /// 阅读进度(0~1)
  final ValueListenable<double> progress;

  final ReaderPalette palette;

  /// 点胶囊 = 打开阅读控制台(和底部把手区同一个入口,手指自然落点)
  final VoidCallback? onTap;

  /// 竖轨道高度(C 规范 96px)
  static const double railHeight = 96;

  /// 竖轨道宽度(C 规范 3px)
  static const double railWidth = 3;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (_, raw, _) {
        final ratio = raw.clamp(0.0, 1.0);
        final pct = (ratio * 100).round();
        return RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.page.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.hairline),
                  ),
                  child: Text(
                    '$pct%',
                    key: const ValueKey<String>('reader-rail-percent'),
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.2,
                      letterSpacing: -0.2,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: railWidth,
                height: railHeight,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: ColoredBox(color: palette.hairline),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: railWidth,
                        height: railHeight * ratio,
                        child: ColoredBox(color: palette.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 2px 进度线(底部把手区上方;控制台进度卡里也复用,高度传 3)。
///
/// 用 `FractionallySizedBox` 而不是 flex 权重:progress=0/1 时权重会退化成 0,
/// 而 0 宽度的 Expanded 在极限值上会抖一下。
class ReaderProgressLine extends StatelessWidget {
  const ReaderProgressLine({
    super.key,
    required this.progress,
    required this.palette,
    this.height = 2,
  });

  final ValueListenable<double> progress;
  final ReaderPalette palette;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (_, raw, _) {
        final ratio = raw.clamp(0.0, 1.0);
        return RepaintBoundary(
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(color: palette.hairline),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio,
                  child: ColoredBox(color: palette.accent),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 纯展示用的一行进度线(给定 0~1 的静态值;控制台/目录里一次性渲染)。
///
/// 和 [ReaderProgressLine] 的区别:那个吃 ValueListenable(常驻、每帧变),
/// 这个是弹层里的一次性快照 —— 弹层打开时进度不会变,不需要监听。
class ReaderProgressBar extends StatelessWidget {
  const ReaderProgressBar({
    super.key,
    required this.ratio,
    required this.palette,
    this.height = 3,
  });

  final double ratio;
  final ReaderPalette palette;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: palette.hairline),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: ratio.clamp(0.0, 1.0),
            child: ColoredBox(color: palette.accent),
          ),
        ],
      ),
    );
  }
}

/// 阅读器顶部的悬浮圆钮(C 的顶部只有一个返回圆钮;书架/更多都收进控制台)。
class ReaderCircleButton extends StatelessWidget {
  const ReaderCircleButton({
    super.key,
    required this.icon,
    required this.palette,
    required this.onTap,
    this.size = 14,
    this.diameter = 32,
    this.tooltip,
  });

  final IconData icon;
  final ReaderPalette palette;
  final VoidCallback onTap;
  final double size;
  final double diameter;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: diameter,
        height: diameter,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.page.withValues(alpha: 0.86),
          shape: BoxShape.circle,
          border: Border.all(color: palette.hairline),
        ),
        child: Icon(icon, size: size, color: palette.inkSoft),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
