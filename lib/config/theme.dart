import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 简约、高效的 ReadFlow 主题(v2.2 起支持深色)。
///
/// 深色不是"把浅色反一下":三个坑必须避开 ——
/// 1. **底色不用纯黑**。纯黑上放白字会发光晕(尤其 PMOLED/LCD),长时间阅读更累;
///    这里用 #12141A(近黑的冷灰),正文用 #E6E8EC 而不是纯白,夜间不刺眼。
/// 2. **层次靠亮度差,不靠阴影**。深色下阴影几乎看不见,所以卡片(#1B1F27)、
///    输入框(#262B35)都比底色**亮**一档,层级关系与浅色版一致(卡片在页面上浮起)。
/// 3. **主色要换**。浅色的主色是近黑 #1A1A2E,放在深底上等于隐形;
///    深色版主色换成亮蓝,并把 onPrimary 交给 M3 调色板(深色模式里
///    实心按钮是"亮底深字",保证对比度)。
///
/// 对比度(实测 WCAG 比值,正文标准 4.5:1):
/// 正文/底色 ≈ 14.6;次要文字/卡片 ≈ 6.5;主色/底色 ≈ 7.4。
class AppTheme {
  AppTheme._();

  // ── 浅色色板(v2.12 前端升级:暖白 + 蓝主色)──
  //
  // 为什么从"冷白 + 近黑主色"换成"暖白 + 蓝主色"(依据见 docs/FRONTEND-UPGRADE-PLAN.md):
  // 1. **背景换成暖白 #FDFCF9**:用户给的样图里,阅读类 App 的底都是温润的近白,
  //    冷灰白(#F8F9FA)在真机上会显得"医院感/工具感",不利于长时间阅读;
  // 2. **主色换成蓝 #1F63D8**:旧主色是近黑 #1A1A2E —— 它做按钮时像"次要/禁用",
  //    用户反复说"一眼看不到该选什么"。蓝色主按钮是这类产品的通用语言(样图也是),
  //    但这里选的是**偏深的蓝**(对白底 5.4:1,过 WCAG AA),不是样图那种亮蓝,
  //    以守住"高级"而不是"廉价活泼";
  // 3. 层级仍然靠**墨黑文字 + 留白**拉开,不是靠更多颜色。
  static const Color primary = Color(0xFF1F63D8);
  static const Color primaryPressed = Color(0xFF1A53B8);
  static const Color accent = Color(0xFF0F3460);
  static const Color highlight = Color(0xFF4A90D9);
  static const Color background = Color(0xFFFDFCF9);
  static const Color surface = Colors.white;

  /// 次级面板(分组底、输入框底、页签未选中区)
  static const Color surfaceAlt = Color(0xFFF5F2EC);
  static const Color textPrimary = Color(0xFF14161A);
  static const Color textSecondary = Color(0xFF5F6672);
  static const Color success = Color(0xFF157F35);
  static const Color error = Color(0xFFC62828);
  static const Color divider = Color(0xFFEDEAE3);

  // ── 深色色板 ──
  //
  // 比旧版再深一点(#12141A → #0F1115):深色下"高级感"来自**更暗的底 + 更亮的卡**,
  // 而不是整体发灰。三层亮度差保持:页面 < 卡片 < 输入框(theme_test 有闸门)。
  static const Color darkBackground = Color(0xFF0F1115);

  /// 卡片/AppBar/导航栏表面(比底色亮一档)
  static const Color darkSurface = Color(0xFF171A20);

  /// 输入框、Chip 等"再亮一档"的填充色
  static const Color darkSurfaceVariant = Color(0xFF1F232B);
  static const Color darkTextPrimary = Color(0xFFECEEF2);
  static const Color darkTextSecondary = Color(0xFFA6AEBB);
  static const Color darkDivider = Color(0xFF262B34);

  /// 深色主色(亮蓝,对深底 8:1)
  static const Color darkPrimary = Color(0xFF7FA8FF);
  static const Color darkAccent = Color(0xFFA9C6FF);

  // ── 描边色(v2.4 修"浅色下看不清")──────────────────────────────
  //
  // 用户实测:识图保存弹窗里的目录卡片"完全是泛白的"。根因是描边太淡 ——
  // M3 由近黑种子生成的浅色 outlineVariant 对白底只有 **1.70:1**,
  // 而卡片底(surface 白)与页面底(#F8F9FA)本来就几乎同色:
  // 没有可辨认的边界,整块就"泛白"。WCAG 对非文字元素的要求是 3:1。
  static const Color outlineLight = Color(0xFF6E6A72); // 白底 5.2:1(输入框/交互边界)
  static const Color outlineVariantLight = Color(0xFF8F8A93); // 白底 3.4:1(卡片/分隔)

  /// 深色下的描边:比原来的 #2E3440 稍亮一点,边界更清楚但不会显得重
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

      // 卡片:v2.12 **elevation 归零**(阴影改由 AppCard 用 AppShadow 画:
      // M3 的 elevation 在浅色下是"染色"不是投影,做不出样图那种柔和阴影)。
      // 圆角 16 → 20(样图的大卡圆角),margin 保持不动 —— 约 50 个页面依赖它。
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardRadius),
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

      // 按钮:v2.12 主按钮 = **48 高 + 14 圆角 + 15 号半粗**。
      // 为什么加高:旧版 44 高的按钮在单手操作时"点不准",而且样图里的主按钮
      // 都是整宽、明显偏高的形状 —— 主行动必须在视觉上"够大"。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: dark ? const Color(0xFF0B1220) : Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      // 输入框:v2.12 圆角 12、浅色底改成暖灰(比页面稍暗一档 = "凹进去"),
      // 比"与页面同色只靠描边"更清楚,也更有材质层次
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? darkSurfaceVariant : surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: mutedColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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
        backgroundColor: dark ? darkSurfaceVariant : surface,
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

      // 弹窗:同卡片色 + 大圆角(与 hero 卡同一档)
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetRadius),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.fixed,
        backgroundColor: dark ? darkSurfaceVariant : const Color(0xFF323232),
        contentTextStyle: TextStyle(
          color: dark ? darkTextPrimary : Colors.white,
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
    );
  }
}
