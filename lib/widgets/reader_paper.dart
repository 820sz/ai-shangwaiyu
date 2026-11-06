import 'package:flutter/material.dart';

import '../services/reader_settings.dart';

/// 阅读器 C 方案(2026-11-06 用户拍板)的纸张调色板与排印令牌。
///
/// 为什么单独一组令牌而不是用 `V4Skin`:
/// 1. 用户否掉的正是"彩色 App 里的一个页面"——阅读器要像一张纸,不能用
///    果冻蓝/粉这一套;**只活在阅读器内部**,不进全局主题、不影响其它页面;
/// 2. 用户要把 B 方案的**纸张三色**搬过来(纸白 / 米黄 / 墨夜),一套令牌
///    必须能整体换纸,而不是散落在 3000 行里改颜色常量;
/// 3. C 的排印(标题 28/1.1/w900、首段 20/1.82、正文 18/1.8、译文 13.5/1.8)
///    是"阅读排印",与界面字阶不是一回事,不能写进 `AppFont`。
///
/// 对比度(正文/译文/选中态/进度条)由 [contrastRatio] 守住,见
/// `test/reader_c_paper_test.dart` —— 三张纸都必须过 WCAG AA(≥4.5 正文/译文)。
class ReaderPalette {
  const ReaderPalette({
    required this.paper,
    required this.dark,
    required this.page,
    required this.sheet,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.hairline,
    required this.accent,
    required this.onAccent,
    required this.transBg,
    required this.selectedBg,
  });

  /// 这张纸对应哪一种纸张设置
  final ReaderPaper paper;

  /// 是否深色纸(墨夜)—— 状态栏图标、弹层阴影、按钮反色都要看它
  final bool dark;

  /// 页面底(纸面)
  final Color page;

  /// 弹层/控制台底(比纸面亮一档,仍是同一套纸)
  final Color sheet;

  /// 正文(近黑,不是纯黑)
  final Color ink;

  /// 次要文字(译文 / 署名 / 说明)
  final Color inkSoft;

  /// 极淡文字(栏目标签 / 元信息 / 进度说明)
  final Color inkFaint;

  /// 1px 分隔线 / 轨道底
  final Color hairline;

  /// 唯一强调色:砖红。进度、生词下划线、选中态、主按钮都用它
  final Color accent;

  /// 砖红底上的字色(墨夜纸上的砖红是提亮版,因此用深色字)
  final Color onAccent;

  /// 译文块底(砖红提亮到纸面上的一层极浅底)
  final Color transBg;

  /// 选中态底(设置里的选中色卡/分段、控制台当前行)
  final Color selectedBg;

  /// 主按钮(= ink 底)上的字色:浅纸用白,墨夜纸用纸色(反色)
  Color get onInk => dark ? page : const Color(0xFFF7F7F4);

  /// 弹层遮罩(浅纸 34% 黑,墨夜纸要更深一点才压得住)
  Color get scrim => Colors.black.withValues(alpha: dark ? 0.52 : 0.34);

  /// 纸张的「冷灰纸 / 暖纸 / 深色纸」那一行说明(设置色卡下用)
  String get paperHint => paper.hint;
}

/// 三张纸的具体色值
///
/// - 纸白:冷灰纸 `#EEEFEA`(C 方案基底)+ 近黑 `#15181A` + 砖红 `#B23A2C`;
/// - 米黄:暖纸 `#F4EFE3`(搬 B 方案)+ 暖黑 `#241F17` + 同一块砖红;
/// - 墨夜:深色纸 `#16181C` + 纸白字 `#ECEDE8` + **提亮砖红** `#E0604F`
///   (同色相;原色 #B23A2C 在深纸上只有 2.9:1,小字读不清,必须提亮)。
ReaderPalette paletteOf(ReaderPaper paper) {
  switch (paper) {
    case ReaderPaper.white:
      return const ReaderPalette(
        paper: ReaderPaper.white,
        dark: false,
        page: Color(0xFFEEEFEA),
        sheet: Color(0xFFF8F8F4),
        ink: Color(0xFF15181A),
        inkSoft: Color(0xFF494F51),
        inkFaint: Color(0xFF8C918F),
        hairline: Color(0xFFD7D9D2),
        accent: Color(0xFFB23A2C),
        onAccent: Color(0xFFF7F7F4),
        transBg: Color(0xFFECEDE6),
        selectedBg: Color(0xFFE4E0D7),
      );
    case ReaderPaper.beige:
      return const ReaderPalette(
        paper: ReaderPaper.beige,
        dark: false,
        page: Color(0xFFF4EFE3),
        sheet: Color(0xFFFBF7ED),
        ink: Color(0xFF241F17),
        inkSoft: Color(0xFF6E6555),
        inkFaint: Color(0xFF9A9080),
        hairline: Color(0xFFE2D8C4),
        accent: Color(0xFFB23A2C),
        onAccent: Color(0xFFFBF7ED),
        transBg: Color(0xFFF0E9DA),
        selectedBg: Color(0xFFE9DFCB),
      );
    case ReaderPaper.night:
      return const ReaderPalette(
        paper: ReaderPaper.night,
        dark: true,
        page: Color(0xFF16181C),
        sheet: Color(0xFF1E2126),
        ink: Color(0xFFECEDE8),
        inkSoft: Color(0xFFB6BAB4),
        inkFaint: Color(0xFF8F9691),
        hairline: Color(0xFF2E3238),
        accent: Color(0xFFE0604F),
        onAccent: Color(0xFF16181C),
        transBg: Color(0xFF23262C),
        selectedBg: Color(0xFF23262B),
      );
  }
}

/// C 方案的 6 档字阶(标题 / 栏目标签 / 署名 / 首段 / 正文 / 译文)。
///
/// 号数全部相对**正文号数**给:用户在阅读设置里调字号时,整页按比例放大,
/// 不会出现"正文变大了、标题还是 28"这种失衡。默认正文 18 号时就是设计稿
/// 的 28 / 9.5 / 10.5 / 20 / 18 / 13.5 六档。
class ReaderType {
  const ReaderType({required this.body, required this.lineHeight});

  /// 从阅读设置(5 档字号 × 3 档行距)构造
  factory ReaderType.fromSettings() => ReaderType(
        body: ReaderSettings.cBodyFontSize(),
        lineHeight: ReaderSettings.cBodyLineHeight(),
      );

  /// 正文号数(默认 18)
  final double body;

  /// 正文行高(默认 1.8)
  final double lineHeight;

  /// 文章标题:28 / 1.1 / w900 / -0.8
  double get title => body * 28 / 18;
  static const double titleHeight = 1.1;
  static const double titleSpacing = -0.8;

  /// 栏目标签(kicker):9.5 / 1.3 / +1.6
  double get kicker => body * 9.5 / 18;
  static const double kickerHeight = 1.3;
  static const double kickerSpacing = 1.6;

  /// 署名 / 元信息:10.5 / 1.4 / +0.3
  double get signature => body * 10.5 / 18;
  static const double signatureHeight = 1.4;
  static const double signatureSpacing = 0.3;

  /// 首段(导语):20 / 1.82
  double get lead => body * 20 / 18;
  static const double leadHeight = 1.82;

  /// 译文:13.5 / 1.8
  double get translation => body * 13.5 / 18;
  static const double translationHeight = 1.8;

  /// 译文上方「中译」小标:8.5 / 1.2 / +1.5
  static const double transLabel = 8.5;

  /// 正文颜色在这里不进(由 ReaderPalette 决定),只有排印数值
}

/// 阅读器局部主题:把 `Theme.of(context)` 覆写成当前纸张的一套颜色。
///
/// 只包住阅读器自己的子树(Scaffold + 所有从阅读器弹出来的 sheet),
/// 不碰全局 `v4_theme`。共享弹层(查词 `showWordActionSheet`、追问抽屉、
/// 分类选择器)用的是 `Theme`/`V4Skin`,包进这层后它们也会跟着变成纸色,
/// 不用逐个大改别的文件。
ThemeData readerTheme(BuildContext context, ReaderPalette p) {
  final base = Theme.of(context);
  final cs = base.colorScheme.copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    surface: p.sheet,
    onSurface: p.ink,
    onSurfaceVariant: p.inkSoft,
    outline: p.hairline,
    outlineVariant: p.hairline,
    surfaceContainerHighest: Color.alphaBlend(
      p.ink.withValues(alpha: p.dark ? 0.10 : 0.05),
      p.page,
    ),
    surfaceContainerHigh: p.sheet,
    surfaceContainer: p.sheet,
    surfaceContainerLow: p.page,
    surfaceContainerLowest: p.page,
    inverseSurface: p.ink,
    onInverseSurface: p.page,
  );
  return base.copyWith(
    colorScheme: cs,
    scaffoldBackgroundColor: p.page,
    canvasColor: p.page,
    dividerColor: p.hairline,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: p.dark ? 0.42 : 0.22),
      selectionHandleColor: p.accent,
    ),
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    primaryTextTheme:
        base.primaryTextTheme.apply(bodyColor: p.ink, displayColor: p.ink),
    iconTheme: IconThemeData(color: p.inkSoft),
    // 全局按钮主题把 TextButton 前景写死成果冻蓝(共享件里的「取消/重试」等
    // 会漏出蓝色 = C 方案不允许的第二强调色);这里在阅读器子树内统一成砖红/墨色,
    // 并把字体接到当前 textTheme(否则测试/低端机字体会回落到无中文字形)。
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: p.accent,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.onInk,
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.hairline),
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
    // 全局 progressIndicatorTheme 把进度条写死果冻蓝(共享 ProgressStageBar
    // 会漏出来 = C 不允许的第二强调色);阅读器子树内统一砖红/纸线。
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.hairline,
      circularTrackColor: p.hairline,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.sheet,
      modalBackgroundColor: p.sheet,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: p.hairline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.sheet,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: p.ink, fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.hairline),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(color: p.page),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// WCAG 对比度(1~21)。三张纸的正文/译文/选中态/进度条都用它守门。
///
/// 纯函数,单测里逐条断言;`test/reader_c_paper_test.dart` 是"三纸都可读"
/// 这条验收标准的机器可核对版本。
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
