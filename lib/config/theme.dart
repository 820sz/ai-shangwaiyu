import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'v4_theme.dart';

/// 简约、高效的 ReadFlow 主题(v2.2 起支持深色;v4 起换「明亮果冻」皮肤)。
///
/// 深色不是"把浅色反一下":三个坑必须避开 ——
/// 1. **底色不用纯黑**。纯黑上放白字会发光晕(尤其 PMOLED/LCD),长时间阅读更累;
///    这里用 #0E1017(近黑的冷灰),正文用 #E9EDF3 而不是纯白,夜间不刺眼。
/// 2. **层次靠亮度差,不靠阴影**。深色下阴影几乎看不见,所以卡片(#171A24)、
///    输入框(#1F2330)都比底色**亮**一档,层级关系与浅色版一致。
/// 3. **主色要换**。浅色的靛蓝 #4C5AF0 放在深底上会发闷;
///    深色版主色换成亮靛 #A9B4FF,并把 onPrimary 交给深墨(深色模式里
///    实心按钮是"亮底深字",保证对比度)。
///
/// v4(2026-11-03 用户选定「明亮果冻」):视觉基调的**令牌**收敛到 [V4Skin],
/// 这里只负责 Material 主题的映射 —— 以后换皮肤只改 [V4Skin],不用动页面。
///
/// 对比度(实测 WCAG 比值,正文标准 4.5:1):
/// 正文/底色 ≈ 15+;次要文字/卡片 ≈ 5.8;主色/白字 ≈ 5.2。
class AppTheme {
  AppTheme._();

  // ── 浅色色板(v4 明亮果冻:冷白底 + 靛蓝主色 + 糖果色点缀)──
  //
  // 为什么从"暖白 + 蓝"换成"冷白 + 靛蓝":
  // 1. 果冻基调的底必须是**干净的冷白**,糖果色块才显得亮、不脏;
  // 2. 主色换成偏紫的靛蓝 #4C5AF0 —— 比普通蓝更有"设计感",且与
  //    粉/薄荷/天蓝三块果冻色是同一族(色相相邻,不打架);
  // 3. 层级仍靠**深墨文字 + 留白 + 柔影**拉开,不靠更多颜色。
  static const Color primary = Color(0xFF4C5AF0);
  static const Color primaryPressed = Color(0xFF3E4AD6);
  static const Color accent = Color(0xFF2B2E52);
  static const Color highlight = Color(0xFF7B7CFF);
  static const Color background = Color(0xFFF6F6FD);
  static const Color surface = Colors.white;

  /// 次级面板(分组底、输入框底、页签未选中区)
  static const Color surfaceAlt = Color(0xFFEFF1FB);
  static const Color textPrimary = Color(0xFF1C1E2E);
  static const Color textSecondary = Color(0xFF5F6478);
  static const Color success = Color(0xFF157F35);
  static const Color error = Color(0xFFC62828);
  static const Color divider = Color(0xFFE4E7F5);

  // ── 深色色板(果冻·夜)──
  //
  // 深色下"高级感"来自**更暗的底 + 更亮的卡**,而不是整体发灰。
  // 三层亮度差保持:页面 < 卡片 < 输入框(theme_test 有闸门)。
  static const Color darkBackground = Color(0xFF0E1017);

  /// 卡片/AppBar/导航栏表面(比底色亮一档)
  static const Color darkSurface = Color(0xFF171A24);

  /// 输入框、Chip 等"再亮一档"的填充色
  static const Color darkSurfaceVariant = Color(0xFF1F2330);
  static const Color darkTextPrimary = Color(0xFFEAEDF6);
  static const Color darkTextSecondary = Color(0xFFA2A9BC);
  static const Color darkDivider = Color(0xFF2A2F3F);

  /// 深色主色(亮靛,对深底 9:1+)
  static const Color darkPrimary = Color(0xFFA9B4FF);
  static const Color darkAccent = Color(0xFFB49CFF);

  // ── 描边色(浅色下"看得见"是硬要求,见 theme_test)──────────────
  //
  // 用户实测:描边太淡,卡片/输入框就"完全是泛白的"。
  // WCAG 对非文字元素的要求是 3:1,这里按色相往靛蓝偏了一点,与主色同族。
  static const Color outlineLight = Color(0xFF6A6D84); // 白底 5.0:1(输入框/交互边界)
  static const Color outlineVariantLight = Color(0xFF8E90A8); // 白底 3.15:1(卡片/分隔)

  /// 深色下的描边:比底色亮,边界清楚但不显得重
  static const Color darkOutline = Color(0xFF5A6270);
  static const Color darkOutlineVariant = Color(0xFF3D4553);

  // ── 主题数据 ──
  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  /// 按主题设置解析 MaterialApp.themeMode(纯函数,便于单测)
  static ThemeMode themeModeOf(String? id) => switch (id) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  /// "琥珀色强调"(未高亮的入口图标之类)。
  ///
  /// 为什么单独给一个函数:浅色下 #B07A1E 在深底上只有 ~2.5:1、深色下
  /// 又太暗,同一个琥珀色不可能两头都对 —— 它必须随明暗切换,而这类**语义色**
  /// 不属于 Material 调色板角色,塞进 colorScheme 反而是误导。
  static Color amber(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFE0A83C)
          : const Color(0xFFB07A1E);

  // ── 语义色(v2.5,U2):成功 / 警告 / 危险 ──────────────────────
  //
  // 为什么不能直接用 Colors.green / Colors.orange / Colors.red:
  // 它们在白底上只有 ~2.5~3.1:1(小字号就是"看不清"),在深底上又偏刺眼;
  // 同一个值不可能两头都对 —— 与 amber 同理,必须随明暗切换。
  // 这里的值都过了 WCAG:浅色档对白底 ≥4.5:1,深色档对 #12141A ≥4.5:1
  // (闸门测试见 test/theme_test.dart 的"语义色"组)。
  static const Color lightSuccess = Color(0xFF157F35);
  static const Color lightWarning = Color(0xFFB45309);
  static const Color lightDanger = Color(0xFFC62828);
  static const Color darkSuccess = Color(0xFF45C46A);
  static const Color darkWarning = Color(0xFFE0A83C);
  static const Color darkDanger = Color(0xFFFF6B6B);

  /// 成功(分数及格、任务完成、源可用)
  static Color successColor(BuildContext context) =>
      _semantic(context, lightSuccess, darkSuccess);

  /// 警告(偏难、待注意、源不可用但非错误)
  static Color warningColor(BuildContext context) =>
      _semantic(context, lightWarning, darkWarning);

  /// 危险(错误、扣分项、删除)
  static Color dangerColor(BuildContext context) =>
      _semantic(context, lightDanger, darkDanger);

  static Color _semantic(BuildContext context, Color light, Color dark) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// 极淡的辅助文字(编号小标、装饰性标签)。
  ///
  /// 为什么不直接在页面里 `onSurfaceVariant.withAlpha(...)`:那样在浅色下会掉到
  /// 3:1 以下(正是用户骂过的"发灰看不清"),而且 `theme_test` 的硬编码闸门会抓。
  /// 这里给**明暗各一档、都过 4.5:1** 的淡色,既弱化又不糊。
  static Color faintText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF8A94A3)
          : const Color(0xFF6E7480);

  /// 把任意色点亮到"在深色下看得见"(v2.5)。
  ///
  /// 用在**品牌色/身份色**上(AI 厂商头像、第三方标识):这些色不能换成主题色
  /// (换了就分不清是哪家),但深色下有些只有 2.07:1(百度蓝 #2932E1)、
  /// 2.99:1(通义紫 #6B4CE6)—— 低于 WCAG 非文字元素要求的 3:1,圆块会发闷。
  /// 做法是**只提亮度、不动色相**:向白色插值直到对卡片底达标。
  /// 浅色主题原样返回(品牌色在白底上都够)。
  static Color readableOn(
    BuildContext context,
    Color color, {
    double minRatio = 3.0,
  }) {
    final theme = Theme.of(context);
    if (theme.brightness != Brightness.dark) return color;
    final bg = theme.cardTheme.color ?? theme.colorScheme.surface;
    var c = color;
    for (var i = 0; i < 8; i++) {
      if (contrastRatio(c, bg) >= minRatio) break;
      c = Color.lerp(c, Colors.white, 0.12)!;
    }
    return c;
  }

  /// WCAG 对比度(公开给测试与调用方复用,避免各写一份)
  static double contrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// **图表系列色**:曲线 / 圆点 / 面积 / 热力图都用它。
  ///
  /// 为什么不直接用主色:浅色主色是近黑 #1A1A2E,图表会从"蓝色数据线"
  /// 变成"黑色墨迹",丢掉了 v1.x 以来的观感;而写死的 #4A90D9 是浅色档,
  /// 深底上偏暗。所以给一个**两档都达标**的蓝:
  /// 浅色 #2C6BB3(白底 5.5:1)、深色 #6BA8E8(深底 7.2:1)。
  static const Color lightChartSeries = Color(0xFF2C6BB3);
  static const Color darkChartSeries = Color(0xFF6BA8E8);

  static Color chartSeries(BuildContext context) =>
      _semantic(context, lightChartSeries, darkChartSeries);

  /// **掌握度色**(0 新词 / 1 学习中 / 2 已掌握)。
  ///
  /// 为什么要收敛:同一件事在好几个文件里各写了一份 `Colors.orange/blue/green`
  /// (词卡、词条详情、词库列表、复习标记、统计),浅色下这些色对白底只有
  /// 2.2~2.8:1 —— 用户说的"很多地方看不清"就是它们。
  static Color masteryColor(BuildContext context, int level) => switch (level) {
        1 => Theme.of(context).colorScheme.primary,
        2 => successColor(context),
        _ => warningColor(context),
      };

  /// **词条类型色**(word / phrase / sentence):同一类词条在全 App 一个颜色
  static Color wordTypeColor(BuildContext context, String type) =>
      switch (type) {
        'phrase' => warningColor(context),
        'sentence' => Theme.of(context).colorScheme.tertiary,
        _ => Theme.of(context).colorScheme.primary,
      };

  /// themeMode → 存储用的语义档位
  static String themeModeId(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = dark
        ? ColorScheme.fromSeed(
            seedColor: darkPrimary,
            brightness: Brightness.dark,
          ).copyWith(
            primary: darkPrimary,
            onPrimary: const Color(0xFF0B1220),
            secondary: darkAccent,
            surface: darkSurface,
            onSurface: darkTextPrimary,
            onSurfaceVariant: darkTextSecondary,
            surfaceContainerHighest: darkSurfaceVariant,
            outline: darkOutline,
            outlineVariant: darkOutlineVariant,
            error: const Color(0xFFFF6B6B),
          )
        : ColorScheme.fromSeed(
            seedColor: primary,
            primary: primary,
            onPrimary: Colors.white,
            secondary: accent,
            surface: surface,
            error: error,
          ).copyWith(
            onSurface: textPrimary,
            onSurfaceVariant: textSecondary,
            // 浅色下"浅色容器"统一成暖灰(而不是 M3 从种子色生成的偏冷灰),
            // 这样次要文字压在上面仍是 5:1+(theme_test 有闸门)。
            surfaceContainerHighest: surfaceAlt,
            surfaceContainer: surfaceAlt,
            // v2.4:浅色描边整体加深到"看得见"为止(默认生成的太淡,见上方注释)
            outline: outlineLight,
            outlineVariant: outlineVariantLight,
          );

    final bg = dark ? darkBackground : background;
    final card = dark ? darkSurface : surface;
    final line = dark ? darkDivider : divider;
    final titleColor = dark ? darkTextPrimary : textPrimary;
    final mutedColor = dark ? darkTextSecondary : textSecondary;

    /// 强调色 = 主色(浅色蓝 / 深色亮蓝)。
    /// v2.12:从"浅色用 highlight(#4A90D9)"改成主色 —— 全 App 的选中态、图标、
    /// 页签指示器必须是**同一个蓝**,否则会出现两种蓝(用户说的"配色杂乱")。
    final accentColor = dark ? darkPrimary : primary;

    /// v4 视觉基调令牌(明亮果冻)。换皮肤 = 换这一行,不用动页面。
    final skin = dark ? V4Skin.jellyDark : V4Skin.jellyLight;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      dividerColor: line,

      // 底部导航栏:v2.12 去掉 elevation(阴影由 bottom_nav 自己按主题画,
      // 深色下不能有阴影 —— 见 AppShadow 注释)
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: accentColor,
        unselectedItemColor: mutedColor,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
      ),

      // AppBar:v2.12 改成**与页面同色 + 左对齐大标题**。
      // 为什么:旧版是"卡片色 + 居中标题 + 18px",每个页面顶上都像一条工具条,
      // 把页面切碎了;阅读类 App 的做法是让标题成为内容的一部分(样图就是这样)。
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: titleColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: titleColor,
          fontSize: AppFont.title,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),

      // 卡片:v4 果冻卡 = **26 圆角 + 白面 + 柔影**(阴影由 AppCard 画:
      // M3 的 elevation 在浅色下是"染色"不是投影,做不出果冻那种柔光)。
      // margin 保持不动 —— 约 50 个页面依赖它。
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(skin.cardRadius),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // 分隔线:更细更淡,让"留白分组"而不是"线条分组"
      dividerTheme: DividerThemeData(
        color: line,
        thickness: 1,
        space: 1,
      ),

      // 页面切换动画(v2.5,U1):Android 默认是"整页从下往上推",在内容页之间
      // 显得很重;换成"淡入 + 轻微上移",与卡片入场同一套手感。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),

      // 按钮:v4 果冻按钮 = **胶囊(999) + 52 高 + 15 号半粗**。
      // 果冻基调的大圆角必须落到所有系统控件上,否则页面里会混着"方按钮"。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: dark ? const Color(0xFF14161F) : Colors.white,
          minimumSize: const Size(0, 52),
          shape: const RoundedRectangleBorder(
            borderRadius: Radii.pillRadius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: titleColor,
          minimumSize: const Size(0, 48),
          shape: const RoundedRectangleBorder(
            borderRadius: Radii.pillRadius,
          ),
          side: BorderSide(color: scheme.outline, width: 1),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentColor,
          shape: const RoundedRectangleBorder(
            borderRadius: Radii.pillRadius,
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // 输入框:v4 圆角 16、浅色底用淡靛灰(比页面稍深一档 = "凹进去")
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? darkSurfaceVariant : surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(color: mutedColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(skin.controlRadius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(skin.controlRadius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(skin.controlRadius),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
      ),

      // 标签Chip:补上描边 —— 浅色下 chip 底(background)与卡片底(白)几乎同色,
      // 没有描边时整排 chip 看着"糊在一起"
      //
      // v2.6 再加一条(用户实测"追问抽屉的快捷回复看不清""保存弹窗的文件名看不清"):
      // **显式指定未选中 chip 的文字色**。M3 默认会把 label 用 onSurfaceVariant
      // 混色压在半透明底上,浅色下就是"白底浅灰字"。这里统一钉成 onSurface
      // (对 surface 4.5:1+),并把描边从 outlineVariant 提到 outline(3:1+)。
      chipTheme: ChipThemeData(
        backgroundColor: dark ? darkSurfaceVariant : surfaceAlt,
        selectedColor: accentColor.withAlpha(dark ? 60 : 30),
        secondarySelectedColor: accentColor.withAlpha(dark ? 60 : 30),
        labelStyle: TextStyle(
          fontSize: 13,
          color: dark ? darkTextPrimary : textPrimary,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: 13,
          color: dark ? darkTextPrimary : textPrimary,
        ),
        iconTheme: IconThemeData(color: dark ? darkTextPrimary : textPrimary),
        checkmarkColor: dark ? darkTextPrimary : textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // 深色下 chip 底比页面亮一档(#1F232B),原来的 outline(#5A6270)
        // 对它只有 2.31:1 —— 描边等于看不见。换成更亮一档的 #767E8D(3.45:1)。
        side: BorderSide(
          color: dark ? const Color(0xFF767E8D) : scheme.outline,
        ),
        // v2.12:标签改成**胶囊形**(样图里的分类标签/难度徽标都是胶囊;
        // 8 圆角的小方块在真机上像表单控件,不像标签)
        shape: const RoundedRectangleBorder(borderRadius: Radii.pillRadius),
      ),

      // 弹窗/弹层:v4 用 30 大圆角(与 hero 卡同一档)
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(skin.heroRadius - 2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(skin.heroRadius),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.fixed,
        backgroundColor: dark ? darkSurfaceVariant : const Color(0xFF23263A),
        contentTextStyle: TextStyle(
          color: dark ? darkTextPrimary : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(skin.controlRadius),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accentColor,
        unselectedLabelColor: mutedColor,
        indicatorColor: accentColor,
      ),
      listTileTheme: ListTileThemeData(iconColor: mutedColor),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accentColor),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accentColor : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accentColor.withAlpha(90)
              : null,
        ),
      ),

      // v4 视觉基调令牌:所有 v4 组件与页面从这里取颜色/圆角/阴影/渐变。
      extensions: <ThemeExtension<dynamic>>[skin],
    );
  }
}
