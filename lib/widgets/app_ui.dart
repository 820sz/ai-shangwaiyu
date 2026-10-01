/// 全 App 统一的基础组件(v2.5,U1)。
///
/// 为什么要有这一套:以前每页自己 `Card(child: Padding(child: Row(...)))`,
/// 于是同样"一个入口"在不同页面长得不一样(内边距、圆角、图标大小、箭头颜色
/// 全都不同),用户看到的就是"乱"。这里把 6 个最常用的形态固定下来,
/// 新页面直接用,老页面逐屏替换。
///
/// 边界:**只管外观与结构,不含业务逻辑**(没有 provider、没有网络)。
library;

import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import 'waiting.dart';

/// 卡片:统一圆角、内边距、外边距与点击反馈
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? color;
  final bool dense;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.color,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ?? (dense ? Insets.tile : Insets.card),
      child: child,
    );
    return Card(
      color: color,
      margin: margin ?? const EdgeInsets.only(bottom: Gap.xs),
      shape: RoundedRectangleBorder(borderRadius: Radii.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}

/// 区块标题:标题 + 可选说明 + 可选右侧动作(替代各页手写的 Row+Text)
class AppSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets? padding;

  const AppSectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ??
          const EdgeInsets.only(top: Gap.md, bottom: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: Gap.xs),
            Expanded(
              child: Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 入口行:图标 + 标题 + 副标题 + 右箭头(全 App 的"进入某个功能"统一长这样)
class AppActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final bool highlight;

  /// 不可用态(v2.5):置灰 + 不可点。
  /// 为什么单独给一个开关:调用方常常是"忙碌中"临时禁用(例如备份导出),
  /// 而 `onTap: null` 只让它点不动、外观照旧 —— 用户会以为点了没反应。
  final bool enabled;

  const AppActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.highlight = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final dim = !enabled;
    final card = AppCard(
      onTap: dim ? null : onTap,
      color: highlight ? theme.colorScheme.primary.withAlpha(12) : null,
      child: Row(
        children: [
          Icon(icon,
              size: 22,
              color: dim ? muted : (iconColor ?? theme.colorScheme.primary)),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: dim ? muted : null,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          trailing ??
              Icon(Icons.chevron_right,
                  size: 20,
                  color: dim ? muted : theme.colorScheme.outline),
        ],
      ),
    );
    return dim ? Opacity(opacity: 0.6, child: card) : card;
  }
}

/// 空态:图标 + 一句话 + 补充说明(+ 可选动作)
class AppEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  const AppEmpty({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.hint,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.lg, horizontal: Gap.md),
      child: Column(
        children: [
          Icon(icon, size: 44, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: Gap.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (hint != null) ...[
            const SizedBox(height: Gap.xxs),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: Gap.md),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 加载态(v2.9 改版:不再是一个转圈)。
///
/// 用户 10/2 原话:"该软件最后所有让 ai 进行思考或者什么任务的功能,都要把现在的
/// **转圈等待 ui 改成其他更可感、更高级的等待动画形式**,最好是流式输出"。
/// 他选了三套方案**都要**,于是这里:
/// - 默认 = **骨架屏**(B 方案):先铺出"结果将要占据的形状",内容一到原地替换 ——
///   等待感显著变短,也不会再出现"一个孤零零的圈在屏幕中间";
/// - 传 [steps] = **流式过程时间线**(A 方案):有明确步骤的任务(检索/抓取/识图/批改),
///   每一步都是真实发生的;
/// - 传 [progress] = **进度条**(C 方案):能估算进度的批量任务(逐段翻译/批量分析)。
///
/// 三种共用同一个入口,调用方按任务类型选,不必各页自己画。
class AppLoading extends StatelessWidget {
  final String? label;

  /// A 方案:真实步骤(传了就显示时间线)
  final List<AiStep>? steps;

  /// C 方案:0~1 的真实进度(传了就显示进度条)
  final double? progress;

  /// C 方案:开始时间(显示"已用 N 秒")
  final DateTime? startedAt;

  /// 骨架屏行数(默认 4)
  final int skeletonLines;

  const AppLoading({
    super.key,
    this.label,
    this.steps,
    this.progress,
    this.startedAt,
    this.skeletonLines = 4,
  });

  @override
  Widget build(BuildContext context) {
    // A:有步骤 → 时间线(用户最想要的"可感的等待")
    if (steps != null && steps!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        child: AiWaitingTimeline(
          steps: steps!,
          running: true,
          footer: null,
        ),
      );
    }
    // C:有进度 → 进度条
    if (progress != null || startedAt != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        child: ProgressStageBar(
          stage: label ?? '正在处理',
          value: progress,
          startedAt: startedAt,
        ),
      );
    }
    // B:默认 → 骨架屏 + 一行说明
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Row(
              children: [
                const ThinkingDots(label: '', compact: true),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
          ],
          SkeletonLines(lines: skeletonLines),
        ],
      ),
    );
  }
}

/// 失败态:说明 + 重试(全 App 统一"出错长这样",而不是各页各写一段红字)
class AppErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const AppErrorCard({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = '重试',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline,
                  size: 18, color: theme.colorScheme.error),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error, height: 1.5),
                ),
              ),
            ],
          ),
          if (onRetry != null) ...[
            const SizedBox(height: Gap.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(retryLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 列表项入场动画:让"内容出现"有节奏(每项错峰 40ms,最多错峰到 240ms)。
///
/// 只做**入场**:淡入 + 上移 10px,用统一曲线与时长;不做列表增删动画
/// (那需要 key 与 AnimatedList,收益低于复杂度)。
class AppStagger extends StatefulWidget {
  final int index;
  final Widget child;

  const AppStagger({super.key, required this.index, required this.child});

  @override
  State<AppStagger> createState() => _AppStaggerState();
}

class _AppStaggerState extends State<AppStagger> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: (widget.index * 40).clamp(0, 240));
    if (delay == Duration.zero) {
      _shown = true;
    } else {
      Future.delayed(delay, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: Motion.enter,
      curve: Motion.curve,
      offset: _shown ? Offset.zero : const Offset(0, 0.06),
      child: AnimatedOpacity(
        duration: Motion.enter,
        curve: Motion.curve,
        opacity: _shown ? 1 : 0,
        child: widget.child,
      ),
    );
  }
}
