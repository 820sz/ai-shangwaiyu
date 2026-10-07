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

/// 卡片的视觉变体(v2.11,G 批"全局 UI 升级"的地基)。
///
/// **为什么加这个而不是加更多圆角/间距档位**:体检结论是"全 App 只有一种容器、
/// 它没有型号" —— 约 51 处 `AppCard` 用同一组圆角/内边距/底色,于是同一屏里所有
/// "块"必然同宽同角同节奏,用户看到的就是"清一色的竖列功能块"。
/// 缺的是**变体维度**(语义),不是更多数值。
///
/// 4 个变体各自的语义(只用这 4 个,别再随手加):
/// - [plain]  :常规内容卡(列表项、说明块)—— 保持 v2.5 的样子不变;
/// - [plain] 的紧凑版是 [compact]:信息密度高的行(书架书脊、导入列表);
/// - [hero]   :**一屏只有一个**的主角卡(今日精读、当前任务)—— 大圆角 + 浮起 + 轻微染底;
/// - [accent] :强调但不需要"主角"地位(进行中、已选中)。
enum AppCardVariant { plain, compact, hero, accent }

/// 卡片:统一圆角、内边距、外边距与点击反馈
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? color;
  final bool dense;

  /// 视觉变体(默认 [AppCardVariant.plain] = v2.5 的老样子,老调用点不受影响)
  final AppCardVariant variant;

  /// 变体内部用的 Key:测试要能精确找到"卡片自己的内边距",
  /// 而不是 `Card` 内部的 margin padding(两者都是 `Padding`,不区分会断错对象)。
  static const Key paddingKey = Key('app_card_padding');

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.color,
    this.dense = false,
    this.variant = AppCardVariant.plain,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isHero = variant == AppCardVariant.hero;
    final isCompact = variant == AppCardVariant.compact;
    final isAccent = variant == AppCardVariant.accent;

    final effectivePadding = padding ??
        (isCompact || dense ? Insets.tile : Insets.card);
    // 层级:**只让主角卡浮起来**,其余沿用主题给的那一档(当前是 1)。
    // 这里踩过一次坑并已回退:曾把 plain 硬压成 0,结果全 App 的普通卡片
    // 一下子都变平了 —— "统一视觉"不等于"顺手改掉 51 处老调用点的观感"。
    final elevation = isHero ? AppElevation.raised : null;
    final radius = isHero
        ? const BorderRadius.all(Radius.circular(Radii.sheet))
        : Radii.cardRadius;
    final bg = color ??
        (isHero
            // 主角卡:在 surface 上叠一点 primary —— 亮暗两套都成立,不硬编码色值
            ? Color.alphaBlend(
                cs.primary.withAlpha(AppSurface.raisedTintAlpha), cs.surface)
            : isAccent
                ? Color.alphaBlend(
                    cs.primary.withAlpha(AppSurface.accentTintAlpha), cs.surface)
                : null);

    final content = Padding(
      key: paddingKey,
      padding: effectivePadding,
      child: child,
    );
    return Card(
      color: bg,
      elevation: elevation,
      margin: margin ?? const EdgeInsets.only(bottom: Gap.xs),
      shape: RoundedRectangleBorder(borderRadius: radius),
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
///
/// v2.11 加了第二种版式 [AppActionTileStyle.grid]:把"大图标 + 标题"排成
/// 两列小方块(材料中心的"按你的水平找材料"用的就是它)。
/// 为什么不再加第三、第四种:体检发现这一种版式被用了 20 次(光"我的"页 13 个),
/// 全屏都是"图标-标题-箭头"三件套 —— 缺的是**第二种**,不是第十种。
enum AppActionTileStyle { row, grid }

class AppActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final bool highlight;

  /// 版式(默认 [AppActionTileStyle.row] = 原来的行式)
  final AppActionTileStyle style;

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
    this.style = AppActionTileStyle.row,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final dim = !enabled;
    if (style == AppActionTileStyle.grid) {
      return AppCard(
        onTap: dim ? null : onTap,
        variant: AppCardVariant.plain,
        color: highlight ? theme.colorScheme.primary.withAlpha(12) : null,
        padding: const EdgeInsets.symmetric(vertical: Gap.sm, horizontal: Gap.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Icon(icon,
                  size: 20, color: dim ? muted : (iconColor ?? theme.colorScheme.primary)),
            ),
            const SizedBox(height: Gap.xs),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: dim ? muted : null,
              ),
            ),
          ],
        ),
      );
    }
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
