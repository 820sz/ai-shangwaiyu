/// ReadFlow 设计套件 v2.12(前端全面升级的核心组件)。
///
/// 为什么单独一个文件而不是继续往 app_ui.dart 里塞:
/// `app_ui.dart` 是 v2.5 的"基础件"(卡片/标题/空态/等待),56 处老页面在用它,
/// 动它有回归风险;这里放的是**这次新引入的形态件** —— 大图内容卡、横卡、
/// 标签、徽标、内容领域页签、环形进度……新页面用新件,老页面逐屏迁移。
///
/// 设计依据(见 docs/FRONTEND-UPGRADE-PLAN.md):
/// - 用户样图(扇贝/训记/轻小说文库)的"大图 + 标签 + 元信息 + 整宽主按钮";
/// - 用户原则:精简高级、实用第一,再谈丰富与趣味。
///
/// **纪律**:这里只做**形态**,不收业务逻辑(不读库、不联网)。
/// 颜色一律从 `Theme.of(context).colorScheme` 或 [AppTheme] 语义色取,
/// 不写死浅色专用色(`test/theme_test.dart` 有硬编码闸门)。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../config/theme.dart';
import 'app_ui.dart';
import 'material_cover.dart';

// ─────────────────────────────────────────────────────────────
// 标签 / 徽标
// ─────────────────────────────────────────────────────────────

/// 标签的语气(只 5 种,不要随手加)。
enum AppTagTone { neutral, primary, success, warning, danger }

/// 胶囊标签:内容领域、来源、状态。
///
/// 形状用胶囊(999)而不是小圆角方块 —— 样图里的分类标签都是胶囊;
/// 小方块在真机上更像"表单控件",不像标签。
class AppTag extends StatelessWidget {
  final String label;
  final AppTagTone tone;
  final IconData? icon;

  /// 描边款(背景透明):用在图片/彩色底上
  final bool outlined;

  const AppTag(
    this.label, {
    super.key,
    this.tone = AppTagTone.neutral,
    this.icon,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(context, tone);
    final bg = outlined
        ? Colors.transparent
        : Color.alphaBlend(color.withAlpha(20), Colors.transparent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: Radii.pillRadius,
        border: outlined ? Border.all(color: color.withAlpha(120)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppFont.tagStyle.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  static Color _toneColor(BuildContext context, AppTagTone tone) {
    final cs = Theme.of(context).colorScheme;
    return switch (tone) {
      AppTagTone.primary => cs.primary,
      AppTagTone.success => AppTheme.successColor(context),
      AppTagTone.warning => AppTheme.warningColor(context),
      AppTagTone.danger => AppTheme.dangerColor(context),
      AppTagTone.neutral => cs.onSurfaceVariant,
    };
  }
}

/// 难度徽标(Lv1–Lv10)。
///
/// [vertical] = true 时是**竖排**三行(L / v / 8),对应样图里发现页右侧的窄徽标;
/// 默认是横排胶囊,用在大卡标签行里。
class AppLevelBadge extends StatelessWidget {
  final String level;
  final bool vertical;
  final bool filled;

  const AppLevelBadge({
    super.key,
    required this.level,
    this.vertical = false,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.onSurfaceVariant;
    final bg = filled
        ? Color.alphaBlend(color.withAlpha(24), cs.surface)
        : Colors.transparent;
    if (vertical) {
      return Container(
        width: 26,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: Radii.controlRadius,
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('L', style: AppFont.tagStyle.copyWith(color: color)),
            Text('v', style: AppFont.tagStyle.copyWith(color: color)),
            Text(
              level,
              style: AppFont.tagStyle.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: Radii.pillRadius,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        'Lv$level',
        style: AppFont.tagStyle.copyWith(color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 区块标题 / 内容领域页签
// ─────────────────────────────────────────────────────────────

/// 区块标题:可选"编号小标"(杂志感) + 标题 + 右侧动作。
///
/// 样图里的「01 / CATALOG」那种编号小标,作用不是装饰,而是**给长页面分段**:
/// 用户滚动时靠编号知道"这是一组新的内容"。
class AppSectionHeader extends StatelessWidget {
  final String title;

  /// 编号小标(如 '01'),不传就不显示
  final String? indexLabel;

  /// 右侧动作(如「全部 >」)
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.indexLabel,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (indexLabel != null) ...[
                  Text(
                    indexLabel!,
                    style: AppFont.tagStyle.copyWith(
                      color: AppTheme.faintText(context),
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  title,
                  style: AppFont.headingStyle.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ),
          ?trailing,
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: AppFont.metaStyle.copyWith(color: cs.primary),
              ),
            ),
        ],
      ),
    );
  }
}

/// 内容领域页签(横向滚动,选中态 = 主色文字 + 短下划线)。
///
/// 为什么不用 Material 的 `TabBar`:它会占满整行、切换是"位移指示器";
/// 而样图里的领域 tab 是**可横滑的文字列表**,选中项只有一条短横线 ——
/// 更轻,不会把页面切成两半。
class AppContentTabs extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  /// 左右内边距(默认按页面边距;嵌在已有 page padding 的容器里时传 0)
  final EdgeInsets horizontalPadding;

  const AppContentTabs({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.horizontalPadding =
        const EdgeInsets.symmetric(horizontal: Gap.page),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: horizontalPadding,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.lg),
        itemBuilder: (context, i) {
          final selected = i == index;
          return InkWell(
            onTap: () => onChanged(i),
            borderRadius: Radii.controlRadius,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedDefaultTextStyle(
                  duration: Motion.tap,
                  style: AppFont.subheadStyle.copyWith(
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(tabs[i]),
                ),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: Motion.transition,
                  curve: Motion.curve,
                  height: 3,
                  width: selected ? 18 : 0,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: Radii.pillRadius,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 内容卡:大图 Hero 卡 / 横卡
// ─────────────────────────────────────────────────────────────

/// 大图内容卡(Hero 形态):通栏图 + 标签行 + 标题 + 副标题 + 元信息 + 整宽主按钮。
///
/// 这是这次升级里最重要的新形态 —— 一个"内容单元"把用户决策需要的信息全给齐:
/// 是什么(图/标题)、属于哪类(标签)、多难(徽标)、多久(元信息)、下一步(主按钮)。
/// 以前我们的卡片只有"小图 + 标题 + 一行小字",要靠点进去才知道这些。
class AppHeroCard extends StatelessWidget {
  /// 真图地址(拿不到就回落程序化封面)
  final String? imageUrl;

  /// 程序化封面种子(标题)
  final String seed;

  /// 内容类型(book/news/paper/podcast/wiki/article)
  final String kind;

  /// 顶部小标(如「今日精读」「10/23 · 星期四」),画在图片左上角的渐变上
  final String? eyebrow;

  /// 图片高度(默认 190)
  final double imageHeight;

  /// 标签行(内容领域、来源等)
  final List<Widget> tags;

  final String title;
  final String? subtitle;

  /// 元信息行(图标 + 文字,由调用方组好)
  final List<Widget> meta;

  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  /// 整卡点击(打开详情);不传则只有主按钮可点
  final VoidCallback? onTap;

  const AppHeroCard({
    super.key,
    this.imageUrl,
    required this.seed,
    this.kind = 'article',
    this.eyebrow,
    this.imageHeight = 190,
    this.tags = const [],
    required this.title,
    this.subtitle,
    this.meta = const [],
    required this.actionLabel,
    this.actionIcon = Icons.play_arrow_rounded,
    this.onAction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      variant: AppCardVariant.hero,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ① 图(通栏)。eyebrow 叠在图片底部渐变上,保证在任何图上都读得清
          SizedBox(
            height: imageHeight,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MaterialCover(
                  seed: seed,
                  kind: kind,
                  imageUrl: imageUrl,
                  width: double.infinity,
                  height: imageHeight,
                  radius: 0,
                ),
                // 底部渐变:让白字压在亮图上也可读(只覆盖下 40%)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: imageHeight * 0.42,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withAlpha(0),
                            Colors.black.withAlpha(110),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (eyebrow != null)
                  Positioned(
                    left: Gap.md,
                    bottom: Gap.sm,
                    right: Gap.md,
                    child: Text(
                      eyebrow!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.tagStyle.copyWith(
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ② 内容区
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm + 2, Gap.md, Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tags.isNotEmpty) ...[
                  Wrap(spacing: Gap.xs, runSpacing: Gap.xs, children: tags),
                  const SizedBox(height: Gap.sm),
                ],
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.titleStyle.copyWith(color: cs.onSurface),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: Gap.xxs),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.bodyStyle.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: Gap.sm),
                  Wrap(
                    spacing: Gap.md,
                    runSpacing: Gap.xs,
                    children: meta,
                  ),
                ],
                const SizedBox(height: Gap.md),
                // ③ 整宽主按钮(样图的核心:主行动必须一眼看到、一指按到)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: onAction ?? onTap,
                    icon: Icon(actionIcon, size: 20),
                    label: Text(actionLabel),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 横卡(左文右图):高密度列表项。
///
/// 为什么是"左文右图"而不是"左图右文":标题通常 2~3 行,左文右图能让
/// **文字左边对齐成一条线**,扫读时眼睛不用来回跳(样图的发现页就是这样)。
class AppWideCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? dateText;
  final List<Widget> tags;
  final String? imageUrl;
  final String seed;
  final String kind;
  /// 图片边长(默认 88)
  final double imageSize;
  /// 难度徽标(竖排),传 null 不显示
  final String? level;
  final VoidCallback? onTap;
  /// 右上角额外动作(如「⋯」),不传不显示
  final Widget? trailing;

  const AppWideCard({
    super.key,
    required this.title,
    this.subtitle,
    this.dateText,
    this.tags = const [],
    this.imageUrl,
    required this.seed,
    this.kind = 'article',
    this.imageSize = 88,
    this.level,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(Gap.sm),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dateText != null || trailing != null) ...[
                  Row(
                    children: [
                      if (dateText != null)
                        Expanded(
                          child: Text(
                            dateText!,
                            style: AppFont.metaStyle.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      ?trailing,
                    ],
                  ),
                  const SizedBox(height: Gap.xxs),
                ],
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.subheadStyle.copyWith(
                    color: cs.onSurface,
                    height: 1.35,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.metaStyle.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Wrap(spacing: Gap.xs, runSpacing: 4, children: tags),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (level != null) ...[
                AppLevelBadge(level: level!, vertical: true),
                const SizedBox(width: Gap.xs),
              ],
              ClipRRect(
                borderRadius: Radii.controlRadius,
                child: MaterialCover(
                  seed: seed,
                  kind: kind,
                  imageUrl: imageUrl,
                  width: imageSize,
                  height: imageSize,
                  radius: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 小件:元信息 / 大数字 / 进度环 / 空态
// ─────────────────────────────────────────────────────────────

/// 元信息(图标 + 文字):如「12 分钟」「60 句」「美音」。
class AppMeta extends StatelessWidget {
  final IconData icon;
  final String text;

  const AppMeta({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text, style: AppFont.metaStyle.copyWith(color: color)),
      ],
    );
  }
}

/// 大数字统计(统计页/首页用):数字是主角,标签是配角。
class AppStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const AppStat({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 26,
            height: 1.05,
            letterSpacing: -0.5,
            fontWeight: FontWeight.w800,
            color: valueColor ?? cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppFont.metaStyle.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// 环形进度:自绘(不用 `CircularProgressIndicator` —— 它会被铁律判为"转圈")。
class AppProgressRing extends StatelessWidget {
  final double value;
  final String centerText;
  final double size;
  final double stroke;
  final Color? color;

  const AppProgressRing({
    super.key,
    required this.value,
    required this.centerText,
    this.size = 72,
    this.stroke = 7,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.primary;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value.clamp(0, 1),
          color: fg,
          track: cs.outlineVariant.withAlpha(90),
          stroke: stroke,
        ),
        child: Center(
          child: Text(
            centerText,
            style: TextStyle(
              fontSize: size * 0.24,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  _RingPainter({
    required this.value,
    required this.color,
    required this.track,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawCircle(center, radius, trackPaint);
    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// 空态:自绘小图形(圆 + 点) + 标题 + 说明 + 主按钮。
///
/// 为什么不用一个灰色大图标:空态是"第一印象"(样图都会给空态做设计)。
/// 这里用**主色的低透明度圆 + 两个装饰点**做出"轻量插画"的观感,
/// 不引入任何图片资源,也不破坏暗色。
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.hint,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.lg,
        vertical: Gap.xl,
      ),
      child: Column(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(16),
                    shape: BoxShape.circle,
                  ),
                ),
                // 两个装饰点:制造"轻插图"的手感,不抢主体
                Positioned(
                  right: 6,
                  top: 14,
                  child: _Dot(size: 8, color: cs.primary.withAlpha(60)),
                ),
                Positioned(
                  left: 8,
                  bottom: 12,
                  child: _Dot(size: 5, color: cs.primary.withAlpha(38)),
                ),
                Icon(icon, size: 32, color: cs.primary.withAlpha(200)),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppFont.subheadStyle.copyWith(color: cs.onSurface),
          ),
          if (hint != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: AppFont.bodyStyle.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: Gap.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final double size;
  final Color color;

  const _Dot({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 按压缩放包装:给"没有水波纹"的自绘元素(封面/图表/自绘按钮)加触觉反馈。
///
/// Apple 的响应原则:反馈必须在**按下瞬间**发生,不是抬手后。
/// 0.97~0.98 的缩放足够感知,又不显得"廉价弹跳"。
class AppPressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  const AppPressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
  });

  @override
  State<AppPressScale> createState() => _AppPressScaleState();
}

class _AppPressScaleState extends State<AppPressScale> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              _set(false);
              widget.onTap?.call();
            },
      child: AnimatedScale(
        duration: Motion.tap,
        curve: Motion.curve,
        scale: _pressed ? widget.scale : 1.0,
        child: widget.child,
      ),
    );
  }
}
