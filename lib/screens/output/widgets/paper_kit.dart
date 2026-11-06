/// 输出板块 · **纸面工作台**(方案 A)局部组件集。
///
/// 用户 2026-11-06 选型:输出内页走 A「纸面工作台」——白面 + 1px 细边 +
/// 编号区块 + 扁平等级胶囊 + 唯一主行动;输出首页/练习中心入口借 B 的果冻头图。
///
/// 为什么放在 `lib/screens/output/widgets/` 而不是全局 `widgets/`:
/// 全局组件(`design_kit` / `v4_kit`)由 Lead 统一维护,本板块只做**局部纸面件**,
/// 避免四个主题并行时互相改同一个全局文件。这里不引入新主题令牌,
/// 所有颜色/字号/圆角全部来自 `V4Skin` / `AppFont` / `Gap` / `Radii`。
///
/// 视觉纪律(与 docs/OUTPUT-REDESIGN-PLAN-2026-11-06.md §四 一致):
/// - 底色 `skin.pageBg`;面 `skin.surface`;细边 `skin.hairline` 1px;
/// - 主色 `skin.accent` 只给:编号、选中胶囊、主按钮;
/// - **不用阴影与渐变**(入口头图除外),层级靠细线/留白/字阶建立;
/// - 一屏只有一个主行动(底部 `PaperBottomAction` 里的 `PaperPrimaryButton`)。
library;

import 'package:flutter/material.dart';

import '../../../config/design_tokens.dart';
import '../../../config/v4_theme.dart';

/// 等级筛选选项(题库 / 四阶设置共用;顺序即 UI 顺序)。
const List<({String value, String label})> examFilterOptions =
    <({String value, String label})>[
  (value: '', label: '全部'),
  (value: 'cet4', label: 'CET-4'),
  (value: 'cet6', label: 'CET-6'),
  (value: 'kaoyan', label: '考研'),
  (value: 'ielts', label: '雅思'),
];

/// A 纸面工作台的**纸面令牌**(暖纸白 / 暖灰细边 / 近黑墨 / 无柔影)。
///
/// 为什么不直接用 `V4Skin` 的果冻色:用户选型是「内页纸面、入口才果冻」。
/// 纸面的高级感来自"纸 + 墨 + 一条细边",不是浅紫底 + 大圆角柔影。
/// 这些值只在本板块内使用,由 [paperThemeOf] 覆写进 `V4Skin` 与 `ColorScheme`,
/// 所以页面里已有的共享组件(`AppCard` 等)也会一起变纸面,不会漏一块紫。
abstract final class PaperPalette {
  /// 纸底(暖白,不是纯白、也不是冷紫)
  static const Color bg = Color(0xFFF5F3EC);

  /// 次级面(浅一档的纸)
  static const Color surfaceAlt = Color(0xFFEFECE2);

  /// 细边(暖灰,1px)
  static const Color hairline = Color(0xFFE2DDD0);

  /// 墨色(正文)
  static const Color ink = Color(0xFF1D1B17);

  /// 次要文字
  static const Color inkSoft = Color(0xFF5C574D);

  /// 极淡文字(元信息/占位)
  static const Color inkFaint = Color(0xFF8B8578);

  /// 主行动/选中态 = 墨色实心(不用渐变、不用彩色),纸面上最"贵"的一笔
  static const Color primary = Color(0xFF1D1B17);

  /// 唯一暖点缀(砖红):只给编号/极少量强调,不超过 1~2 处/屏
  static const Color accent = Color(0xFF9A452C);

  /// 纸面档位色(四阶图标块/来源卡底色,全是低饱和暖纸)
  static const List<List<Color>> tints = <List<Color>>[
    <Color>[Color(0xFFF3EEE2), Color(0xFFE9E1D0)],
    <Color>[Color(0xFFF0EBE2), Color(0xFFE6DED1)],
    <Color>[Color(0xFFF2EEE5), Color(0xFFE8E2D4)],
    <Color>[Color(0xFFEEEBE2), Color(0xFFE4DFD3)],
  ];
}

/// 纸面版 v4 皮肤 + Material 主题:把页面内的共享组件一起变纸面。
///
/// 一次覆写三处,避免"换了一半":
/// 1. `V4Skin` → 纸底/暖灰细边/近黑墨/无柔影/16 圆角/暖纸档位色;
/// 2. `ColorScheme.primary` → 墨色(旧组件里的主色按钮/图标不再发紫);
/// 3. `scaffoldBackgroundColor` / `dividerColor` → 纸底 / 暖灰细边。
ThemeData paperThemeOf(BuildContext context) {
  final theme = Theme.of(context);
  final base = V4Skin.of(context);
  final skin = base.copyWith(
    pageBg: PaperPalette.bg,
    surface: Colors.white,
    surfaceAlt: PaperPalette.surfaceAlt,
    ink: PaperPalette.ink,
    inkSoft: PaperPalette.inkSoft,
    inkFaint: PaperPalette.inkFaint,
    hairline: PaperPalette.hairline,
    accent: PaperPalette.primary,
    accentAlt: PaperPalette.accent,
    onAccent: Colors.white,
    glass: const Color(0xE6FFFFFF),
    // 头图渐变也收成纸面(只有真正的入口屏用果冻头图,那里不套纸面主题)
    heroGradient: const <Color>[Color(0xFFF2EFE7), Color(0xFFE9E4D8)],
    accentGradient: const <Color>[PaperPalette.primary, PaperPalette.primary],
    pastels: PaperPalette.tints,
    cardRadius: 16,
    heroRadius: 20,
    shadow: const <BoxShadow>[],
    heroShadow: const <BoxShadow>[],
  );
  final fontFamily = theme.textTheme.bodyMedium?.fontFamily;
  return theme.copyWith(
    scaffoldBackgroundColor: PaperPalette.bg,
    dividerColor: PaperPalette.hairline,
    // 按钮主题要用"纸面"重新生成:AppTheme 里的按钮样式捕获了果冻主色,
    // 只改 colorScheme 不会更新已捕获的 foregroundColor(会残留紫色文字)。
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: PaperPalette.ink,
        textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PaperPalette.primary,
        foregroundColor: Colors.white,
        textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PaperPalette.ink,
        side: const BorderSide(color: PaperPalette.hairline),
        textStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600),
      ),
    ),
    // 输入区:纸面上就是"一片留白",不要 Material3 的填充圆角底
    // (作答框以前会继承果冻主题的 filled 浅紫底,和纸面打架)
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      isDense: true,
      contentPadding: EdgeInsets.zero,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      hintStyle: const TextStyle(
        color: PaperPalette.inkFaint,
        fontSize: 13,
        height: 1.5,
      ),
    ),
    // Chip 的 labelStyle 会**整体替换** DefaultTextStyle:不显式带字体族时,
    // 无中文字形的回退字体(测试环境 Ahem)会把「四级/考研」画成方块。
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: PaperPalette.ink,
      ),
      side: const BorderSide(color: PaperPalette.hairline),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFE8E2D4),
    ),
    colorScheme: theme.colorScheme.copyWith(
      primary: PaperPalette.primary,
      secondary: PaperPalette.accent,
      surface: Colors.white,
      onSurface: PaperPalette.ink,
      onSurfaceVariant: PaperPalette.inkSoft,
      outline: PaperPalette.hairline,
      outlineVariant: PaperPalette.hairline,
      surfaceContainerHighest: PaperPalette.surfaceAlt,
      // SegmentedButton / Chip 等 M3 组件默认用 secondaryContainer 做选中底;
      // 不覆盖会漏出果冻浅紫(写译工作台的"手写档/电子档"就是这样漏的)。
      secondaryContainer: const Color(0xFFE8E2D4),
      onSecondaryContainer: PaperPalette.ink,
      primaryContainer: PaperPalette.surfaceAlt,
      onPrimaryContainer: PaperPalette.ink,
      tertiaryContainer: PaperPalette.surfaceAlt,
      onTertiaryContainer: PaperPalette.ink,
      error: const Color(0xFF9E3B2F),
    ),
    extensions: <ThemeExtension<dynamic>>[skin],
  );
}

/// 纸面包裹层:页面里已有的旧卡片在纸面外壳下自动失去柔影、换暖纸底。
class PaperSkin extends StatelessWidget {
  final Widget child;

  const PaperSkin({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      Theme(data: paperThemeOf(context), child: child);
}

/// 纸面顶栏(给还依赖 AppBar 的内页做过渡):无阴影、页面底色、居中细眉标。
///
/// 为什么不直接禁用 AppBar:练习中心/写译工作台的 body 里还有大量
/// `ListView` 依赖 `Scaffold` 的滚动与返回,替换成自定义顶栏会牵动布局;
/// 这里只换"外观",保证视觉与纸面一致,等下一轮再彻底换成 [PaperTopBar]。
AppBar paperAppBar(
  BuildContext context,
  String title, {
  List<Widget> actions = const <Widget>[],
}) {
  final skin = V4Skin.of(context);
  // AppBar 的 titleTextStyle 会**完全替换** DefaultTextStyle,所以这里必须显式带上
  // 主题字体族,否则部分环境下标题会落到没有中文字形的回退字体(显示成方块)。
  final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
  return AppBar(
    backgroundColor: skin.pageBg,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: true,
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppFont.tagStyle.copyWith(
        color: skin.inkFaint,
        fontFamily: fontFamily,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
      ),
    ),
    iconTheme: IconThemeData(size: 20, color: skin.ink),
    actions: actions,
  );
}

/// 纸面页骨架:顶部细工具行 + 可滚动内容 + 可选底部固定行动。
class PaperScaffold extends StatelessWidget {
  final Widget? topBar;
  final Widget body;
  final Widget? bottomBar;

  /// 内容区左右边距(与 `Insets.page` 的 20 对齐)
  final double horizontalPadding;

  const PaperScaffold({
    super.key,
    this.topBar,
    required this.body,
    this.bottomBar,
    this.horizontalPadding = Gap.page,
  });

  @override
  Widget build(BuildContext context) {
    // 整页套纸面主题:顶栏/内容/底部行动 + 页面里的共享组件一次性变纸面
    return Theme(
      data: paperThemeOf(context),
      child: Builder(
        builder: (context) {
          final skin = V4Skin.of(context);
          return Scaffold(
            backgroundColor: skin.pageBg,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: <Widget>[
                  ?topBar,
                  Expanded(child: body),
                  ?bottomBar,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 顶部细工具行:返回 + 居中眉标 + 右侧动作(替代原生 AppBar,视觉更轻)。
class PaperTopBar extends StatelessWidget {
  final String? eyebrow;
  final VoidCallback? onBack;
  final bool showBack;
  final List<Widget> actions;

  const PaperTopBar({
    super.key,
    this.eyebrow,
    this.onBack,
    this.showBack = true,
    this.actions = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, 0),
      child: SizedBox(
        height: 36,
        child: Row(
          children: <Widget>[
            if (showBack)
              _CircleAction(
                icon: Icons.arrow_back_rounded,
                onTap: onBack ?? () => Navigator.maybePop(context),
                tooltip: '返回',
              )
            else
              const SizedBox(width: 36),
            Expanded(
              child: eyebrow == null || eyebrow!.trim().isEmpty
                  ? const SizedBox.shrink()
                  : Center(
                      child: Text(
                        eyebrow!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.tagStyle.copyWith(
                          color: skin.inkFaint,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
            ),
            if (actions.isEmpty)
              const SizedBox(width: 36)
            else
              for (var i = 0; i < actions.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: Gap.xs),
                actions[i],
              ],
          ],
        ),
      ),
    );
  }
}

/// 圆形细边小按钮(顶栏用;36×36,不抢视线)。
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const _CircleAction({required this.icon, this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final child = Icon(icon, size: 19, color: skin.inkSoft);
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// 轻量圆形动作按钮(给页面自己放顶栏用;与 `PaperTopBar.actions` 配套)。
class PaperIconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const PaperIconAction({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final button = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: skin.surface,
        shape: BoxShape.circle,
        border: Border.all(color: skin.hairline, width: 1),
      ),
      child: Icon(icon, size: 18, color: skin.inkSoft),
    );
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(onTap: onTap, child: button),
    );
  }
}

/// 页面大标题区:眉标(可选) + 30/w900 标题 + 13 副标题。
class PaperTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const PaperTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: AppFont.displayStyle.copyWith(
                  color: skin.ink,
                  fontSize: 30,
                  height: 1.1,
                  letterSpacing: -0.9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 7),
          Text(
            subtitle!,
            style: AppFont.bodyStyle.copyWith(
              color: skin.inkSoft,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ],
      ],
    );
  }
}

/// 等级筛选行:扁平细边胶囊,选中 = 主色渐充实心。
///
/// 这是 P0-2「四六级分桶」的入口:题库页与四阶设置页共用一套选项与视觉。
class PaperLevelTabs extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final List<({String value, String label})> options;

  const PaperLevelTabs({
    super.key,
    required this.value,
    required this.onChanged,
    this.options = examFilterOptions,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < options.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: Gap.xs),
            _tab(context, skin, options[i]),
          ],
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, V4Skin skin, ({String value, String label}) option) {
    final selected = option.value == value;
    return GestureDetector(
      onTap: () => onChanged(option.value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? null : skin.surface,
          gradient: selected ? skin.accentFill : null,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: selected ? null : Border.all(color: skin.hairline, width: 1),
        ),
        child: Text(
          option.label,
          style: AppFont.tagStyle.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? skin.onAccent : skin.inkSoft,
          ),
        ),
      ),
    );
  }
}

/// 编号区块头:「01 ── 标题 ─────── 右侧说明」。
class PaperSectionHead extends StatelessWidget {
  final String index;
  final String title;
  final String? trailing;
  final Widget? action;

  const PaperSectionHead({
    super.key,
    required this.index,
    required this.title,
    this.trailing,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Row(
      children: <Widget>[
        Text(
          index,
          style: AppFont.tagStyle.copyWith(
            // 编号用唯一暖点缀(砖红),其余全中性墨色 —— 每屏 1~2 处暖色
            color: skin.accentAlt,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppFont.subheadStyle.copyWith(
            color: skin.ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: skin.hairline)),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: 10),
          Text(
            trailing!,
            style: AppFont.tagStyle.copyWith(
              color: skin.inkFaint,
              fontSize: 10.5,
            ),
          ),
        ],
        if (action != null) ...<Widget>[
          const SizedBox(width: 4),
          action!,
        ],
      ],
    );
  }
}

/// 纸面分段控件(2~4 段):细边容器 + 选中段**墨色实心**。
///
/// 为什么不用 Material 的 `SegmentedButton`:它在果冻主题下的选中态是
/// 浅紫药丸(旧语言),纸面 A 要求"选中=墨色、未选=白纸 + 细边"。
class PaperSegmented extends StatelessWidget {
  final String value;
  final List<({String value, String label, IconData? icon})> options;
  final ValueChanged<String> onChanged;

  const PaperSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: skin.hairline, width: 1),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < options.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 3),
            Expanded(child: _segment(context, skin, options[i])),
          ],
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    V4Skin skin,
    ({String value, String label, IconData? icon}) option,
  ) {
    final selected = option.value == value;
    return GestureDetector(
      onTap: () => onChanged(option.value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? skin.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (option.icon != null) ...<Widget>[
              Icon(
                option.icon,
                size: 15,
                color: selected ? skin.onAccent : skin.inkSoft,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              option.label,
              style: AppFont.tagStyle.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? skin.onAccent : skin.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 纸面卡:白面 + 1px 细边 + 圆角(默认 16);可点。
class PaperCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? color;

  const PaperCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.radius = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final content = Padding(
      padding: padding,
      child: child,
    );
    // 一定要有一层 Material:ListTile/ExpansionTile 的墨水与背景画在最近的
    // Material 上;若只隔一层带底色的 DecoratedBox,Flutter 会报
    // "ink splashes may be invisible"(纸面卡里放 ExpansionTile 时真的会炸)。
    final inner = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
    return Container(
      decoration: BoxDecoration(
        color: color ?? skin.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: skin.hairline, width: 1),
      ),
      child: inner,
    );
  }
}

/// 清单行:图标/封面 + 标题 + 一行元信息 + 尾部(默认 chevron)。
///
/// 用于四阶设置页的来源卡、题库列表、练习中心入口等——同一行走同一套间距。
class PaperRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? meta;
  final String? meta2;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int titleMaxLines;
  final Color? titleColor;

  const PaperRow({
    super.key,
    this.leading,
    required this.title,
    this.meta,
    this.meta2,
    this.trailing,
    this.onTap,
    this.titleMaxLines = 2,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return PaperCard(
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: Gap.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.subheadStyle.copyWith(
                    color: titleColor ?? skin.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (meta != null && meta!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    meta!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.tagStyle.copyWith(
                      color: skin.inkSoft,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
                if (meta2 != null && meta2!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    meta2!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.tagStyle.copyWith(
                      color: skin.inkFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Gap.xs),
          trailing ??
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: skin.inkFaint),
        ],
      ),
    );
  }
}

/// 无卡片清单行(只有底部细线):低干扰列表,用于"我的题库"这类次级列表。
class PaperFlatRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last;

  const PaperFlatRow({
    super.key,
    this.leading,
    required this.title,
    this.meta,
    this.trailing,
    this.onTap,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: Gap.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.bodyStyle.copyWith(
                    color: skin.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (meta != null && meta!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    meta!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.tagStyle.copyWith(
                      color: skin.inkFaint,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing ??
              Icon(Icons.chevron_right_rounded,
                  size: 17, color: skin.inkFaint),
        ],
      ),
    );
    final content = Container(
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: skin.hairline, width: 1),
              ),
            ),
      child: row,
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

/// 来源行:🔗 + 小标题 + 一行来源(等级 · 年份套数 · 站点 · 校对)。
///
/// P0-1 的展示落点:题库卡 / 答题页 / 历史还原三处共用同一口径。
class PaperSourceLine extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData icon;

  const PaperSourceLine({
    super.key,
    this.label = '本题来源',
    required this.value,
    this.onTap,
    this.icon = Icons.link_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return PaperCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: skin.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: AppFont.tagStyle.copyWith(
                    color: skin.inkFaint,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.tagStyle.copyWith(
                    color: skin.inkSoft,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.open_in_new_rounded,
                size: 15, color: skin.inkFaint),
        ],
      ),
    );
  }
}

/// 小型元信息胶囊(白底细边,不用主色,避免抢注意力)。
class PaperMetaChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  const PaperMetaChip({super.key, required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: skin.surfaceAlt,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: skin.inkSoft),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: AppFont.tagStyle.copyWith(
              color: skin.inkSoft,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 主行动胶囊(一屏唯一)。[primary] = 主色渐充;[secondary] = 白底细边。
class PaperPillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool expand;

  const PaperPillButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.primary = true,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final fg = primary ? skin.onAccent : skin.inkSoft;
    final content = Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        // 主色渐充只在主行动上出现(与"每屏最多 1 个主行动"配套)
        gradient: primary ? skin.accentFill : null,
        color: primary ? null : skin.surface,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: primary ? null : Border.all(color: skin.hairline, width: 1),
        boxShadow: primary ? skin.shadow : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 17, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppFont.tagStyle.copyWith(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
    final tappable = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: content),
    );
    return expand
        ? SizedBox(width: double.infinity, child: tappable)
        : tappable;
  }
}

/// 底部固定行动区:顶部 1px 细线 + 24 安全边距(与页面底色一致)。
class PaperBottomAction extends StatelessWidget {
  final Widget child;

  const PaperBottomAction({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.page, 10, Gap.page, 24),
      decoration: BoxDecoration(
        color: skin.pageBg,
        border: Border(top: BorderSide(color: skin.hairline, width: 1)),
      ),
      child: child,
    );
  }
}

/// 细进度线(答题进度 / 分值占比);3px,不抢注意力。
class PaperProgressLine extends StatelessWidget {
  final double value;
  final Color? color;
  final double height;

  const PaperProgressLine({
    super.key,
    required this.value,
    this.color,
    this.height = 3,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: skin.hairline,
        color: color ?? skin.accent,
      ),
    );
  }
}

/// 纸面空态:大图形 + 一句可执行提示 + 一个主行动。
class PaperEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PaperEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: skin.surface,
              shape: BoxShape.circle,
              border: Border.all(color: skin.hairline, width: 1),
            ),
            child: Icon(icon, size: 24, color: skin.inkFaint),
          ),
          const SizedBox(height: Gap.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppFont.subheadStyle.copyWith(
              color: skin.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: AppFont.tagStyle.copyWith(
              color: skin.inkSoft,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: Gap.md),
            PaperPillButton(label: actionLabel!, onTap: onAction, primary: false),
          ],
        ],
      ),
    );
  }
}

/// 返回/关闭按钮的统一点击区域(给自定义顶栏用)
Widget paperBackButton(BuildContext context, {VoidCallback? onTap}) =>
    PaperIconAction(
      icon: Icons.arrow_back_rounded,
      onTap: onTap ?? () => Navigator.maybePop(context),
      tooltip: '返回',
    );
