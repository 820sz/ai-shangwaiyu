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

/// 右侧悬浮进度轨道:96px × 3px,砖红按比例填充。
///
/// **第三轮整改(2026-11-07 用户真机反馈第 2 条)**:以前这里是「% 胶囊 + 竖轨」,
/// 为了不压字给正文右侧让位 46px,导致正文列只有 318px、右侧一大条空白。
/// 现在改成:胶囊移到顶部右侧(见 [ReaderProgressBadge]),轨道只占 3px,
/// **悬浮在正文右侧 11px 安全区之上** —— 正文因此恢复满宽,轨道也不遮字。
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

  /// 点轨道 = 打开阅读控制台(和底部把手区同一个入口)
  final VoidCallback? onTap;

  /// 竖轨道高度(C 规范 96px)
  static const double railHeight = 96;

  /// 竖轨道宽度(C 规范 3px)
  static const double railWidth = 3;

  /// 未填充轨道的颜色。
  ///
  /// 第三轮 QA:0% 时原来的 `hairline`(#D7D9D2 on #EEEFEA)对比度只有 1.23:1,
  /// 在真机上"若有若无"。这里用**该纸墨色 18% 混纸底**:纸白/米黄/墨夜都自动
  /// 得到一档更深的灰(对比度 ~1.4~1.65:1),能看见但不抢眼,也不引入第四种颜色。
  static Color trackColor(ReaderPalette palette) => Color.alphaBlend(
        palette.ink.withValues(alpha: 0.18),
        palette.page,
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (_, raw, _) {
        final ratio = raw.clamp(0.0, 1.0);
        return RepaintBoundary(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              // 3px 轨道外给 12px 宽的透明热区(手指能点到,但视觉只有 3px 线;
              // 热区落在正文右侧安全区,不会抢正文里单词的点击)
              width: 12,
              height: railHeight + 16,
              child: Center(
                child: SizedBox(
                  key: const ValueKey<String>('reader-rail-track'),
                  width: railWidth,
                  height: railHeight,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: ColoredBox(
                          color: ReaderProgressRail.trackColor(palette),
                        ),
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
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 顶部右侧的「% 胶囊」(原右侧悬浮胶囊,第三轮整改后移到顶条,不压正文)。
class ReaderProgressBadge extends StatelessWidget {
  const ReaderProgressBadge({
    super.key,
    required this.progress,
    required this.palette,
    this.onTap,
  });

  final ValueListenable<double> progress;
  final ReaderPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (_, raw, _) {
        final pct = (raw.clamp(0.0, 1.0) * 100).round();
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
