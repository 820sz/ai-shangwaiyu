/// v4 视觉系统共享组件(v4.1 · 2026-11-03 用户选定「明亮果冻」基调后重写)。
///
/// 设计语言:**大圆角、柔和渐变、彩色软阴影、玻璃浮层**;颜色/圆角/阴影全部
/// 来自 [V4Skin](`config/v4_theme.dart`),组件本身不写裸色值 —— 这样以后
/// 想切「极简工具风」只换皮肤,不用改页面。
///
/// 纪律:
/// - 内容优先:彩色只用于"身份(哪个域)/ 行动(点哪)/ 状态(进度)";
/// - 一屏最多 1 处渐变头图 + 1 个主行动;
/// - 卡片=白面/果冻渐变 + 柔影,不用重描边;
/// - 状态三件套([V4Skeleton]/[V4Empty]/[V4Error])统一走本文件。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../config/v4_theme.dart';
import '../graphics/graphics.dart';

/// 压在"白/浅色面"上的墨色:深色主题下白玻璃/白胶囊仍是浅色,
/// 上面的字必须用深墨(不能用 skin.ink —— 它本身是浅色的)。
Color _inkOnLight(V4Skin skin) =>
    skin.dark ? const Color(0xFF14161F) : skin.ink;

// ══════════════════════════════════════════════════════════
// 一、页面骨架
// ══════════════════════════════════════════════════════════

/// v4 页面骨架:果冻渐变头图 + 内容区。
class V4PageScaffold extends StatelessWidget {
  final GraphicDomain domain;
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget body;
  final bool showAppBarBack;
  final List<Widget>? chips;
  final VoidCallback? onHeaderTap;
  final EdgeInsets bodyPadding;

  const V4PageScaffold({
    super.key,
    required this.domain,
    required this.title,
    required this.body,
    this.eyebrow,
    this.subtitle,
    this.actions,
    this.showAppBarBack = true,
    this.chips,
    this.onHeaderTap,
    this.bodyPadding = const EdgeInsets.fromLTRB(
        Gap.page, Gap.md, Gap.page, Gap.xl),
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            V4HeroHeader(
              domain: domain,
              title: title,
              eyebrow: eyebrow,
              subtitle: subtitle,
              actions: actions,
              leadingBack: showAppBarBack,
              chips: chips,
              onTap: onHeaderTap,
            ),
            Padding(padding: bodyPadding, child: body),
          ],
        ),
      ),
    );
  }
}

/// 果冻头图:页面第一屏的门面。
///
/// 视觉结构(与探针 C 相同,但改成生产可用的实现):
/// 1. 冷白→蜜桃的柔渐变底 + 两团模糊光斑(左下主色、右上粉色);
/// 2. 左下大标题(ink 深墨,900 字重),上方小字眉标;
/// 3. 玻璃小胶囊承载状态(连续天数/难度),右侧浮一颗白色圆按钮;
/// 4. 底部 32 圆角,让内容"从圆弧里长出来"。
class V4HeroHeader extends StatelessWidget {
  final GraphicDomain domain;
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget>? actions;
  final bool leadingBack;
  final List<Widget>? chips;
  final VoidCallback? onTap;
  final double bottomRadius;

  const V4HeroHeader({
    super.key,
    required this.domain,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions,
    this.leadingBack = false,
    this.chips,
    this.onTap,
    this.bottomRadius = 32,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final pastel = skin.pastelAt(domain.index);
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (leadingBack)
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: Icon(Icons.arrow_back_rounded, color: skin.ink),
                  tooltip: '返回',
                ),
              Expanded(
                child: eyebrow == null
                    ? const SizedBox.shrink()
                    : Text(
                        eyebrow!,
                        style: AppFont.tagStyle.copyWith(
                          color: skin.inkSoft,
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                          letterSpacing: 1.8,
                        ),
                      ),
              ),
              if (actions != null)
                for (final a in actions!) ...[
                  a,
                  const SizedBox(width: Gap.xs),
                ],
            ],
          ),
          const SizedBox(height: Gap.md),
          Text(
            title,
            style: AppFont.displayStyle.copyWith(
              color: skin.ink,
              fontSize: 34,
              height: 1.1,
              letterSpacing: -1.2,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: AppFont.bodyStyle.copyWith(
                color: skin.inkSoft,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
          if (chips != null && chips!.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            Wrap(spacing: Gap.xs, runSpacing: Gap.xs, children: chips!),
          ],
          const SizedBox(height: Gap.md),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(bottomRadius)),
      child: Stack(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: skin
                    .copyWith(
                      heroGradient: <Color>[
                        skin.heroGradient.first,
                        pastel.first.withValues(alpha: 0.55),
                      ],
                    )
                    .heroGradient,
              ),
            ),
            child: Stack(
              children: <Widget>[
                // 光斑:左上主色、右上粉,低透明度大半径 —— 只给底子"透气",
                // 不干扰文字(文字是深墨,压在极浅的光斑上)
                Positioned(
                  left: -70,
                  top: -90,
                  child: _Blob(
                    color: skin.accent.withValues(alpha: 0.30),
                    size: 220,
                  ),
                ),
                Positioned(
                  right: -60,
                  top: -40,
                  child: _Blob(
                    color: skin.accentAlt.withValues(alpha: 0.28),
                    size: 200,
                  ),
                ),
                onTap == null
                    ? content
                    : InkWell(onTap: onTap, child: content),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;

  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            color,
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// 玻璃小胶囊:头图上的状态信息(连续天数/难度/目标),只展示不点击。
///
/// 为什么单独做一个而不是复用 [V4PillButton]:头图上放一堆"长得像按钮"的
/// 东西会让用户犹豫能不能点;这个没有点击反馈、对比度更低,读作"徽标"。
class V4GlassChip extends StatelessWidget {
  final IconData? icon;
  final String label;

  const V4GlassChip({super.key, this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: skin.dark
            ? skin.surfaceAlt.withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.62),
        borderRadius: Radii.pillRadius,
        border: Border.all(
          color: skin.dark
              ? skin.hairline
              : Colors.white.withValues(alpha: 0.9),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...[
            Icon(icon, size: 13, color: skin.inkSoft),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppFont.tagStyle.copyWith(
              color: skin.inkSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 二、内页骨架(二级页面/功能页)
// ══════════════════════════════════════════════════════════

/// 内页头图:比主屏头图**矮一档**,但保持同一套果冻语言。
///
/// 用户的要求是"点进每一个功能不能又是旧样式",所以内页不能再是
/// "白底 AppBar + 黑标题":这里给 28 圆角渐变头 + 玻璃返回键 + 大标题,
/// 内容从圆弧下面长出来。标题字号 26(主屏 34),一屏里仍然只有一个视觉重音。
class V4DetailHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final String? subtitle;
  final GraphicDomain domain;
  final List<Widget>? actions;
  final bool leadingBack;

  /// 自定义左上角控件(如"多选模式"的关闭键);不传则按 [leadingBack] 显示返回键
  final Widget? leading;
  final double bottomRadius;

  const V4DetailHeader({
    super.key,
    required this.title,
    required this.domain,
    this.eyebrow,
    this.subtitle,
    this.actions,
    this.leadingBack = true,
    this.leading,
    this.bottomRadius = 26,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final pastel = skin.pastelAt(domain.index);
    return ClipRRect(
      borderRadius:
          BorderRadius.vertical(bottom: Radius.circular(bottomRadius)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              skin.heroGradient.first,
              pastel.first.withValues(alpha: 0.55),
            ],
          ),
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              left: -60,
              top: -80,
              child: _Blob(
                color: skin.accent.withValues(alpha: 0.26),
                size: 190,
              ),
            ),
            Positioned(
              right: -55,
              top: -30,
              child: _Blob(
                color: skin.accentAlt.withValues(alpha: 0.22),
                size: 170,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      if (leading != null)
                        leading!
                      else if (leadingBack)
                        V4IconAction(
                          icon: Icons.arrow_back_rounded,
                          tooltip: '返回',
                          onTap: () => Navigator.maybePop(context),
                        )
                      else
                        const SizedBox(width: 2),
                      const SizedBox(width: Gap.xs),
                      Expanded(
                        child: eyebrow == null
                            ? const SizedBox.shrink()
                            : Text(
                                eyebrow!,
                                style: AppFont.tagStyle.copyWith(
                                  color: skin.inkSoft,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  letterSpacing: 1.6,
                                ),
                              ),
                      ),
                      if (actions != null)
                        for (final a in actions!) ...[
                          a,
                          const SizedBox(width: Gap.xs),
                        ],
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  Padding(
                    padding: EdgeInsets.only(left: leadingBack ? 2 : 0),
                    child: Text(
                      title,
                      style: AppFont.displayStyle.copyWith(
                        color: skin.ink,
                        fontSize: 26,
                        height: 1.1,
                        letterSpacing: -0.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: EdgeInsets.only(left: leadingBack ? 2 : 0),
                      child: Text(
                        subtitle!,
                        style: AppFont.bodyStyle.copyWith(
                          color: skin.inkSoft,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 头图上的玻璃圆形图标键(返回 / 导入 / 区块管理 / 更多)。
class V4IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const V4IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: skin.dark
            ? skin.surfaceAlt.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.85),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 19, color: _inkOnLight(skin)),
          ),
        ),
      ),
    );
  }
}

/// 内页果冻 AppBar:给"必须保留 Scaffold+AppBar"的页面(如阅读器)用。
///
/// 为什么不让这些页面也换成 [V4DetailHeader]:阅读器/编辑器需要 AppBar 的
/// 固定头、返回键与滚动阴影语义;在它们头上盖一个渐变 + 圆角即可,
/// 不改变页面结构,回归风险最小。
class V4JellyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;

  /// 可选的 AppBar 底部(如 TabBar / 进度条),与原生 AppBar 语义一致
  final PreferredSizeWidget? bottom;

  /// 身份域:决定 AppBar 渐变的第二段颜色(与内页头图同一套取色)
  final GraphicDomain domain;

  const V4JellyAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.domain = GraphicDomain.custom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final radius = BorderRadius.vertical(
      bottom: Radius.circular(skin.cardRadius),
    );
    // 标题样式从 textTheme 派生(而不是裸 TextStyle):
    // 这样字体族跟着主题走 —— 真机上 CJK 回落正常,预览/测试里也不会掉进
    // 默认 Ahem 字体变成方块。
    final baseTitle = Theme.of(context).textTheme.titleMedium ??
        const TextStyle(fontSize: 16);
    final pastel = skin.pastelAt(domain.index);
    // 与 V4DetailHeader 同一套渐变:页面底色 → 域色浅染,保证"有颜色"而不是白加白
    final headerGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        Color.alphaBlend(pastel.first.withValues(alpha: 0.55), skin.pageBg),
        Color.alphaBlend(
            skin.heroGradient.last.withValues(alpha: 0.75), skin.pageBg),
      ],
    );
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      shape: RoundedRectangleBorder(borderRadius: radius),
      iconTheme: IconThemeData(color: skin.ink),
      actionsIconTheme: IconThemeData(color: skin.ink),
      flexibleSpace: DecoratedBox(
        decoration: BoxDecoration(
          gradient: headerGradient,
          borderRadius: radius,
        ),
        // 必须给一个 expand 子节点:RenderDecoratedBox 没有 child 时在
        // AppBar 里会塌成 0 尺寸(渐变直接不显示)。
        child: const SizedBox.expand(),
      ),
      leading: leading,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseTitle.copyWith(
          color: skin.ink,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      bottom: bottom,
      actions: actions,
    );
  }
}

/// 微噪点/纸感:保留 API(旧调用点不炸),果冻基调里**默认关掉**
/// (果冻要"干净",噪点会显脏);以后印刷皮肤可以打开。
class V4Grain extends StatelessWidget {
  final double opacity;

  const V4Grain({super.key, this.opacity = 0.03});

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Opacity(
      opacity: opacity,
      child: CustomPaint(painter: _V4GrainPainter(color: skin.ink)),
    );
  }
}

class _V4GrainPainter extends CustomPainter {
  _V4GrainPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final rnd = math.Random(20261103);
    final count = (size.width * size.height / 220).clamp(80, 900).round();
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.4 + rnd.nextDouble() * 0.9;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _V4GrainPainter oldDelegate) => false;
}

/// 区块标题:标题 + 说明 + 右侧动作(取代各屏手写 Row)。
class V4SectionTitle extends StatelessWidget {
  final String title;
  final String? indexLabel;
  final String? subtitle;
  final Widget? action;
  final EdgeInsets padding;

  const V4SectionTitle({
    super.key,
    required this.title,
    this.indexLabel,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.only(top: Gap.lg, bottom: Gap.sm),
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (indexLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: skin.accent.withValues(alpha: 0.12),
                borderRadius: Radii.pillRadius,
              ),
              child: Text(
                indexLabel!,
                style: AppFont.tagStyle.copyWith(
                  color: skin.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: Gap.xs),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: AppFont.headingStyle.copyWith(
                    color: skin.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppFont.tagStyle.copyWith(color: skin.inkSoft),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: Gap.xs), action!],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 二、内容卡
// ══════════════════════════════════════════════════════════

/// 内容列表卡:白面 + 28 圆角 + 柔影;左封面 + 标题 + 一行元信息 + 尾部。
class V4ListCard extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final GraphicDomain? domain;
  final EdgeInsets padding;

  const V4ListCard({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.meta,
    this.trailing,
    this.onTap,
    this.domain,
    this.padding = const EdgeInsets.all(Gap.sm),
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final accent = domain == null
        ? skin.inkSoft
        : skin.pastelAt(domain!.index).first;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: Container(
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(skin.cardRadius - 6),
          boxShadow: skin.shadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(skin.cardRadius - 6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: padding,
              child: Row(
                children: <Widget>[
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: Gap.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.subheadStyle.copyWith(
                            color: skin.ink,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFont.tagStyle.copyWith(
                              color: skin.inkSoft,
                            ),
                          ),
                        ],
                        if (meta != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFont.tagStyle.copyWith(
                              color: skin.inkSoft,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                  trailing ??
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                              accent.withValues(alpha: 0.22), skin.surface),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 18, color: skin.inkSoft),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 动作砖:果冻渐变砖,图标在白色玻璃圆里。
class V4ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool primary;
  final GraphicDomain domain;
  final VoidCallback? onTap;
  final double height;
  final int? pastelIndex;

  const V4ActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.primary = false,
    this.domain = GraphicDomain.custom,
    this.onTap,
    this.height = 104,
    this.pastelIndex,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final idx = pastelIndex ?? domain.index;
    return SizedBox(
      height: height,
      child: Container(
        decoration: BoxDecoration(
          gradient: primary ? skin.accentFill : skin.pastelFill(idx),
          borderRadius: BorderRadius.circular(skin.cardRadius - 4),
          boxShadow: primary ? skin.heroShadow : skin.shadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(skin.cardRadius - 4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Gap.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: primary
                          ? Colors.white.withValues(alpha: 0.22)
                          : Colors.white.withValues(alpha: 0.78),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: primary ? skin.onAccent : _inkOnLight(skin),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.subheadStyle.copyWith(
                          color: primary ? skin.onAccent : skin.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.tagStyle.copyWith(
                            color: primary
                                ? skin.onAccent.withValues(alpha: 0.82)
                                : skin.inkSoft,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// 三、输出四阶阶段卡 + 统计块 + 题材 tabs
// ══════════════════════════════════════════════════════════

/// 四阶阶段卡:一阶一块果冻,进度环里写阶位,右侧白色胶囊"继续"。
class V4StageCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String levelLabel;
  final GraphicDomain domain;
  final double? progress;
  final String ctaLabel;
  final VoidCallback? onTap;

  const V4StageCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.domain,
    this.levelLabel = '',
    this.progress,
    this.ctaLabel = '开始',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final progressValue = (progress ?? 0).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Container(
        decoration: BoxDecoration(
          gradient: skin.pastelFill(domain.index),
          borderRadius: BorderRadius.circular(skin.cardRadius),
          boxShadow: skin.shadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(skin.cardRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.88),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: V4ProgressRing(
                        value: progressValue,
                        size: 30,
                        color: _inkOnLight(skin),
                        trackColor: _inkOnLight(skin).withValues(alpha: 0.14),
                        strokeWidth: 3,
                        center: Text(
                          levelLabel,
                          style: AppFont.tagStyle.copyWith(
                            color: _inkOnLight(skin),
                            fontWeight: FontWeight.w900,
                            fontSize: levelLabel.length > 2 ? 8 : 9.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: AppFont.titleStyle.copyWith(
                            color: skin.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.tagStyle.copyWith(
                            color: skin.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          ctaLabel,
                          style: AppFont.tagStyle.copyWith(
                            color: _inkOnLight(skin),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.play_arrow_rounded,
                            size: 14, color: _inkOnLight(skin)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统计块:白卡 + 彩色大数字 + 标签。
class V4StatBlock extends StatelessWidget {
  final String value;
  final String label;
  final GraphicDomain domain;
  final String? delta;
  final IconData? icon;
  final VoidCallback? onTap;

  const V4StatBlock({
    super.key,
    required this.value,
    required this.label,
    this.domain = GraphicDomain.custom,
    this.delta,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final tone = Color.lerp(skin.pastelAt(domain.index).first, skin.ink, 0.62) ??
        skin.accent;
    return Container(
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(skin.cardRadius - 8),
        boxShadow: skin.shadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(skin.cardRadius - 8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Gap.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (icon != null) ...[
                      Icon(icon, size: 15, color: tone),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.tagStyle.copyWith(color: skin.inkSoft),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: AppFont.titleStyle.copyWith(
                    color: tone,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (delta != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    delta!,
                    style: AppFont.tagStyle.copyWith(
                      color: skin.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 题材 tab:横向果冻胶囊,选中=主色渐变+白字。
class V4TopicTabs extends StatelessWidget {
  final List<V4Topic> topics;
  final String selectedId;
  final ValueChanged<V4Topic> onSelected;

  const V4TopicTabs({
    super.key,
    required this.topics,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: topics.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.xs),
        itemBuilder: (_, i) {
          final t = topics[i];
          final selected = t.id == selectedId;
          return GestureDetector(
            onTap: () => onSelected(t),
            child: AnimatedContainer(
              duration: Motion.transition,
              curve: Motion.curve,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                gradient: selected ? skin.accentFill : skin.pastelFill(t.domain.index),
                borderRadius: Radii.pillRadius,
                boxShadow: selected
                    ? <BoxShadow>[
                        BoxShadow(
                          color: skin.accent.withValues(alpha: 0.30),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: <Widget>[
                  Icon(t.icon,
                      size: 15, color: selected ? skin.onAccent : skin.ink),
                  const SizedBox(width: 6),
                  Text(
                    t.label,
                    style: AppFont.tagStyle.copyWith(
                      color: selected ? skin.onAccent : skin.ink,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 题材数据(供 [V4TopicTabs] 用;来源仍是 MaterialTopic,这里只做视觉映射)
class V4Topic {
  final String id;
  final String label;
  final IconData icon;
  final GraphicDomain domain;

  const V4Topic({
    required this.id,
    required this.label,
    required this.icon,
    required this.domain,
  });
}

/// 材料中心的题材 → v4 tab 映射(唯一入口,别在页面里再写一份)
List<V4Topic> v4TopicsFrom(List<({String id, String label})> raw) {
  const iconById = <String, IconData>{
    'sci_tech': Icons.science_outlined,
    'business': Icons.work_outline,
    'health': Icons.favorite_border,
    'language': Icons.translate,
    'culture': Icons.palette_outlined,
    'travel': Icons.flight_takeoff,
  };
  const domainById = <String, GraphicDomain>{
    'sci_tech': GraphicDomain.science,
    'business': GraphicDomain.business,
    'health': GraphicDomain.health,
    'culture': GraphicDomain.culture,
    'travel': GraphicDomain.travel,
    'language': GraphicDomain.language,
  };
  return <V4Topic>[
    for (final t in raw)
      V4Topic(
        id: t.id,
        label: t.label,
        icon: iconById[t.id] ?? Icons.category_outlined,
        domain: domainById[t.id] ?? GraphicDomain.custom,
      ),
  ];
}

// ══════════════════════════════════════════════════════════
// 四、状态三件套
// ══════════════════════════════════════════════════════════

/// 加载骨架:与真实布局同构的浅色块,加载完成原地换内容。
class V4Skeleton extends StatelessWidget {
  final int lines;
  final int seed;

  const V4Skeleton({super.key, this.lines = 3, this.seed = 0});

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final widths = <double>[1.0, 0.86, 0.72, 0.9, 0.64];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < lines; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.xs),
            child: FractionallySizedBox(
              widthFactor: widths[(seed + i) % widths.length],
              child: Container(
                height: i == 0 ? 18 : 12,
                decoration: BoxDecoration(
                  color: skin.surfaceAlt,
                  borderRadius: Radii.pillRadius,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 空态:果冻渐变底 + 白玻璃圆 + 一句可执行提示。
class V4Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;
  final GraphicDomain domain;

  const V4Empty({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
    this.domain = GraphicDomain.custom,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: Gap.lg, vertical: Gap.lg),
      decoration: BoxDecoration(
        gradient: skin.pastelFill(domain.index),
        borderRadius: BorderRadius.circular(skin.cardRadius),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.86),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 25, color: _inkOnLight(skin)),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppFont.subheadStyle.copyWith(
              color: skin.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: AppFont.tagStyle.copyWith(
                color: skin.inkSoft,
                height: 1.5,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: Gap.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 错误卡:柔和红底 + 说明 + 重试。
class V4Error extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const V4Error({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final danger = AppTheme.dangerColor(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            danger.withValues(alpha: 0.08), skin.surface),
        borderRadius: BorderRadius.circular(skin.cardRadius - 8),
        border: Border.all(
            color: danger.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: danger),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Text(
              message,
              style: AppFont.tagStyle.copyWith(
                color: skin.ink,
                height: 1.45,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 胶囊按钮:主态=主色渐变白字;次态=白底 ink 字;放在彩色/深色底上用 [onDark]。
class V4PillButton extends StatelessWidget {
  final String label;
  final bool primary;
  final bool light;
  final bool onDark;
  final IconData? icon;
  final VoidCallback? onTap;

  const V4PillButton({
    super.key,
    required this.label,
    this.primary = true,
    this.light = false,
    this.onDark = false,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final Color fg;
    final Gradient? gradient;
    final Color? bg;
    if (onDark) {
      fg = primary ? _inkOnLight(skin) : Colors.white;
      gradient = null;
      bg = primary ? Colors.white : Colors.transparent;
    } else if (light) {
      fg = _inkOnLight(skin);
      gradient = null;
      bg = Colors.white;
    } else if (primary) {
      fg = skin.onAccent;
      gradient = skin.accentFill;
      bg = null;
    } else {
      fg = skin.ink;
      gradient = null;
      bg = skin.surface;
    }
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.tap,
        curve: Motion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          gradient: gradient,
          borderRadius: Radii.pillRadius,
          boxShadow: primary && !light && !onDark ? skin.shadow : null,
          border: onDark && !primary
              ? Border.all(color: Colors.white.withValues(alpha: 0.6))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: AppFont.tagStyle.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 细进度环(阶段卡/统计用;比 CircularProgressIndicator 可控、不会卡在 indeterminate)。
class V4ProgressRing extends StatelessWidget {
  final double value;
  final double size;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final Widget? center;

  const V4ProgressRing({
    super.key,
    required this.value,
    this.size = 40,
    required this.color,
    required this.trackColor,
    this.strokeWidth = 3,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _V4RingPainter(
          value: value.clamp(0, 1),
          color: color,
          trackColor: trackColor,
          strokeWidth: strokeWidth,
        ),
        child: Center(child: center),
      ),
    );
  }
}

class _V4RingPainter extends CustomPainter {
  final double value;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  _V4RingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);
    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5707963,
      6.2831853 * value,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _V4RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
