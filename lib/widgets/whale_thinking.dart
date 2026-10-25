import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/design_tokens.dart';

/// 项目自定的"AI 思考中"形象:**鲸鱼尾**(用户 2026-10-25 指定)。
///
/// 用户原话:「ai 软件内涉及"思考"的 ui,都改成我给的 gif 的鲸鱼尾」。
///
/// 素材处理(见 `build/make_whale.py`):
/// 1. 他给的图是**白底蓝线**;我把白底去成透明,RGB 归一为白色,再用
///    `ColorFiltered(BlendMode.srcIn)` 染成**主题色** —— 深色/浅色主题共用一张图;
/// 2. 传递中的附件只剩静态帧(GIF 动画帧丢了),所以**游动感由代码补**:
///    绕底部枢轴轻摆 + 轻微上浮,像一个尾巴在划水。
///    比 GIF 的好处:速度/幅度可调、任意分辨率都不发虚、能跟主题色走。
///
/// 为什么不是纯装饰动画:它是**状态指示器** —— 有它=AI 正在工作,
/// 所以尺寸小、颜色跟主色,不做夸张弹跳(用户反感"眼花缭乱")。
class WhaleThinking extends StatefulWidget {
  /// 尾巴高度(px)。默认 22:比正文略大,塞进气泡/按钮都不挤。
  final double size;

  /// 染色;默认主题主色
  final Color? color;

  /// 摆速(毫秒/循环)。慢一点更像"思考",快一点更像"加载中"。
  final Duration period;

  const WhaleThinking({
    super.key,
    this.size = 22,
    this.color,
    this.period = const Duration(milliseconds: 1400),
  });

  @override
  State<WhaleThinking> createState() => _WhaleThinkingState();
}

class _WhaleThinkingState extends State<WhaleThinking>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final h = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value * 2 * math.pi;
        // 摆动 ±8°(0.14 rad):足够看出"在游",又不至于晃眼
        final angle = math.sin(t) * 0.14;
        // 上下浮动:用 |sin(2t)| 让一次摆动里"沉-浮"两下,更像划水
        final dy = math.sin(t * 2).abs() * h * 0.06;
        return Transform.translate(
          offset: Offset(0, -dy),
          child: Transform.rotate(
            angle: angle,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: Image.asset(
          'assets/images/whale_tail.png',
          height: h,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

/// 鲸鱼尾 + 一行说明(聊天气泡 / 等待区 / 按钮内联都用它)
class WhaleThinkingLine extends StatelessWidget {
  final String label;
  final bool compact;

  /// 染色;默认主色
  final Color? color;

  /// 文案颜色;默认次要文字色
  final Color? textColor;

  const WhaleThinkingLine({
    super.key,
    this.label = '正在思考',
    this.compact = false,
    this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WhaleThinking(size: compact ? 15 : 21, color: color ?? cs.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFont.metaStyle.copyWith(
              color: textColor ?? cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
