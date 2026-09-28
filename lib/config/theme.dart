import 'package:flutter/material.dart';

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

  // ── 浅色色板 ──
  static const Color primary = Color(0xFF1A1A2E);
  static const Color accent = Color(0xFF0F3460);
  static const Color highlight = Color(0xFF4A90D9);
  static const Color background = Color(0xFFF8F9FA);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6C757D);
  static const Color success = Color(0xFF28A745);
  static const Color error = Color(0xFFDC3545);
  static const Color divider = Color(0xFFE9ECEF);

  // ── 深色色板 ──
  static const Color darkBackground = Color(0xFF12141A);

  /// 卡片/AppBar/导航栏表面(比底色亮一档)
  static const Color darkSurface = Color(0xFF1B1F27);

  /// 输入框、Chip 等"再亮一档"的填充色
  static const Color darkSurfaceVariant = Color(0xFF262B35);
  static const Color darkTextPrimary = Color(0xFFE6E8EC);
  static const Color darkTextSecondary = Color(0xFF9BA3B0);
  static const Color darkDivider = Color(0xFF2E3440);

  /// 深色主色(亮蓝,与浅色的 highlight 同色系)
  static const Color darkPrimary = Color(0xFF6BA8E8);
  static const Color darkAccent = Color(0xFF8FC0F0);

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

  /// **把任意色点亮到"在深色下看得见"**(v2.5)。
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
            seedColor: highlight,
            brightness: Brightness.dark,
          ).copyWith(
            primary: darkPrimary,
            secondary: darkAccent,
            surface: darkSurface,
            onSurface: darkTextPrimary,
            onSurfaceVariant: darkTextSecondary,
            outline: darkOutline,
            outlineVariant: darkOutlineVariant,
            error: const Color(0xFFFF6B6B),
          )
        : ColorScheme.fromSeed(
            seedColor: primary,
            primary: primary,
            secondary: accent,
            surface: surface,
            error: error,
          ).copyWith(
            // v2.4:浅色描边整体加深到"看得见"为止(默认生成的太淡,见上方注释)
            outline: outlineLight,
            outlineVariant: outlineVariantLight,
          );

    final bg = dark ? darkBackground : background;
    final card = dark ? darkSurface : surface;
    final line = dark ? darkDivider : divider;
    final titleColor = dark ? darkTextPrimary : textPrimary;
    final mutedColor = dark ? darkTextSecondary : textSecondary;
    final accentColor = dark ? darkPrimary : highlight;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      dividerColor: line,

      // 底部导航栏
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: accentColor,
        unselectedItemColor: mutedColor,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: card,
        foregroundColor: titleColor,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: titleColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      // 卡片
      cardTheme: CardThemeData(
        color: card,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        // v2.5(U1):**保持既有外边距不变** —— 全库约 50 个页面里有不少老卡片
        // 依赖这个默认边距;一旦改成 0,那些页面会立刻"贴边",属于静默布局回归。
        // 新代码请用 `AppCard`(它自己管边距),老页面逐屏替换时再统一。
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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

      // 按钮
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark ? darkPrimary : primary,
          foregroundColor: dark ? const Color(0xFF0B1220) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),

      // 输入框:浅色下沿用原设计(填充与页面同色),但**描边必须看得见** ——
      // 用 scheme.outline(浅色 5.2:1 / 深色对比足够)而不是 divider 那种装饰色
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? darkSurfaceVariant : background,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: mutedColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        // 深色下 chip 底比页面亮一档(#262B35),原来的 outline(#5A6270)
        // 对只有 2.31:1 —— 描边等于看不见。换成更亮一档的 #767E8D(3.45:1)。
        side: BorderSide(
          color: dark ? const Color(0xFF767E8D) : scheme.outline,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // 弹窗/Tab 之类用 M3 默认色即可,但对话框在深色下要跟卡片同色,
      // 否则会浮出一块比页面更亮的面板
      dialogTheme: DialogThemeData(backgroundColor: card),
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
