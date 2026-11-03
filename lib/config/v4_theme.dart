/// v4「明亮果冻」皮肤:把一套视觉基调收敛成可切换的设计令牌。
///
/// 为什么单开一层而不是继续往 `theme.dart` 里堆颜色:
/// 用户 2026-11-03 选了「明亮果冻」为**默认基调**,同时要求把「极简工具风」
/// 留作**以后可切换的备用主题**。所以颜色/圆角/阴影/渐变不能散落在页面里,
/// 必须收成一份 [V4Skin] —— 以后加一个 `mono` 皮肤(同一批组件换令牌)就能整体换肤,
/// 而不是再改 100 个页面。
///
/// 约定:
/// - 页面与组件**只读 [V4Skin.of]** 或 `Theme.colorScheme`,不写裸色值;
/// - 阴影/渐变/圆角都从这里取,保证"全 App 一套材质";
/// - 深浅两套都在这里定义,组件不用再写 `brightness == dark ? ...`。
library;

import 'package:flutter/material.dart';

/// 可切换的视觉基调。
///
/// 目前只有 [jelly](用户选定);[mono] 是用户要求保留的备用方向,
/// 加皮肤时在 [V4Skin.of] 的默认值之外再提供一份 `V4Skin.monoLight/Dark` 即可。
enum V4Flavor { jelly, mono }

@immutable
class V4Skin extends ThemeExtension<V4Skin> {
  const V4Skin({
    required this.flavor,
    required this.dark,
    required this.pageBg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.hairline,
    required this.accent,
    required this.accentAlt,
    required this.onAccent,
    required this.glass,
    required this.heroGradient,
    required this.accentGradient,
    required this.pastels,
    required this.cardRadius,
    required this.heroRadius,
    required this.controlRadius,
    required this.shadow,
    required this.heroShadow,
  });

  final V4Flavor flavor;
  final bool dark;

  /// 页面底(浅色不是纯白,深色不是纯黑)
  final Color pageBg;
  final Color surface;

  /// 次级面(输入框、未选中 pill、分组底)
  final Color surfaceAlt;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color hairline;

  /// 唯一强调色(主行动/选中/链接)
  final Color accent;

  /// 第二强调色(只用于"活力"点缀,不超过 2 处/屏)
  final Color accentAlt;
  final Color onAccent;

  /// 底栏/浮层玻璃底
  final Color glass;

  /// 头图渐变(2 段)
  final List<Color> heroGradient;

  /// 主行动渐变(2 段;文字统一 [onAccent])
  final List<Color> accentGradient;

  /// 四组"果冻色"(2 段渐变),按顺序循环使用
  final List<List<Color>> pastels;

  final double cardRadius;
  final double heroRadius;
  final double controlRadius;

  /// 常规卡片的软阴影(浅色=彩色柔影;深色=黑色柔影)
  final List<BoxShadow> shadow;

  /// 主角卡/浮层阴影
  final List<BoxShadow> heroShadow;

  // ── 派生 ───────────────────────────────────────────────────────────

  LinearGradient get accentFill => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: accentGradient,
      );

  LinearGradient get heroFill => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: heroGradient,
      );

  /// 第 [i] 组果冻色渐变(循环取,页面不用自己的色表)
  List<Color> pastelAt(int i) => pastels[i % pastels.length];

  LinearGradient pastelFill(int i) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: pastelAt(i),
      );

  /// 卡片基底的极淡染色(白卡在彩色底上不"发灰")
  Color tintOf(Color color, {double alpha = 0.08}) =>
      Color.alphaBlend(color.withValues(alpha: alpha), surface);

  /// 深色/浅色通用的"次级文字"派生,避免页面里写透明度
  Color softInk({double amount = 0.72}) =>
      Color.lerp(ink, surface, amount) ?? inkSoft;

  @override
  V4Skin copyWith({
    V4Flavor? flavor,
    bool? dark,
    Color? pageBg,
    Color? surface,
    Color? surfaceAlt,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? hairline,
    Color? accent,
    Color? accentAlt,
    Color? onAccent,
    Color? glass,
    List<Color>? heroGradient,
    List<Color>? accentGradient,
    List<List<Color>>? pastels,
    double? cardRadius,
    double? heroRadius,
    double? controlRadius,
    List<BoxShadow>? shadow,
    List<BoxShadow>? heroShadow,
  }) {
    return V4Skin(
      flavor: flavor ?? this.flavor,
      dark: dark ?? this.dark,
      pageBg: pageBg ?? this.pageBg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkFaint: inkFaint ?? this.inkFaint,
      hairline: hairline ?? this.hairline,
      accent: accent ?? this.accent,
      accentAlt: accentAlt ?? this.accentAlt,
      onAccent: onAccent ?? this.onAccent,
      glass: glass ?? this.glass,
      heroGradient: heroGradient ?? this.heroGradient,
      accentGradient: accentGradient ?? this.accentGradient,
      pastels: pastels ?? this.pastels,
      cardRadius: cardRadius ?? this.cardRadius,
      heroRadius: heroRadius ?? this.heroRadius,
      controlRadius: controlRadius ?? this.controlRadius,
      shadow: shadow ?? this.shadow,
      heroShadow: heroShadow ?? this.heroShadow,
    );
  }

  /// 主题切换时的过渡:浅色→深色直接取近端(不做半透明混色,避免文字发灰)
  @override
  V4Skin lerp(ThemeExtension<V4Skin>? other, double t) {
    if (other is! V4Skin) return this;
    return t < 0.5 ? this : other;
  }

  /// 当前皮肤(主题里没注册时回退到默认果冻;预览/测试也不会崩)
  static V4Skin of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<V4Skin>() ??
        (theme.brightness == Brightness.dark ? jellyDark : jellyLight);
  }

  // ══════════════════════════════════════════════════════════════════
  // 明亮果冻 · 浅色
  // ══════════════════════════════════════════════════════════════════
  static const V4Skin jellyLight = V4Skin(
    flavor: V4Flavor.jelly,
    dark: false,
    pageBg: Color(0xFFF6F6FD),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEFF1FB),
    ink: Color(0xFF1C1E2E),
    inkSoft: Color(0xFF5F6478),
    inkFaint: Color(0xFF9297AC),
    hairline: Color(0xFFE4E7F5),
    accent: Color(0xFF4C5AF0),
    accentAlt: Color(0xFFFF7FA8),
    onAccent: Color(0xFFFFFFFF),
    glass: Color(0xBFFFFFFF),
    heroGradient: <Color>[Color(0xFFEDEFFF), Color(0xFFFFF0EA)],
    accentGradient: <Color>[Color(0xFF4A57E8), Color(0xFF6D5AE0)],
    pastels: <List<Color>>[
      <Color>[Color(0xFFFFE3D1), Color(0xFFFFC9B0)],
      <Color>[Color(0xFFE4E0FF), Color(0xFFC9C1FF)],
      <Color>[Color(0xFFD7F4E7), Color(0xFFB4E9D4)],
      <Color>[Color(0xFFE3ECFF), Color(0xFFC6D6FF)],
    ],
    cardRadius: 26,
    heroRadius: 32,
    controlRadius: 16,
    shadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x1A4C5AF0),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
      BoxShadow(
        color: Color(0x0A1C1E2E),
        blurRadius: 6,
        offset: Offset(0, 2),
      ),
    ],
    heroShadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x244C5AF0),
        blurRadius: 32,
        offset: Offset(0, 14),
      ),
      BoxShadow(
        color: Color(0x0D1C1E2E),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
  );

  // ══════════════════════════════════════════════════════════════════
  // 明亮果冻 · 深色(同一套"果冻"关系:大圆角、柔光、低刺激对比)
  // ══════════════════════════════════════════════════════════════════
  static const V4Skin jellyDark = V4Skin(
    flavor: V4Flavor.jelly,
    dark: true,
    pageBg: Color(0xFF0E1017),
    surface: Color(0xFF171A24),
    surfaceAlt: Color(0xFF1F2330),
    ink: Color(0xFFEAEDF6),
    inkSoft: Color(0xFFA2A9BC),
    inkFaint: Color(0xFF737A8D),
    hairline: Color(0xFF2A2F3F),
    accent: Color(0xFFA9B4FF),
    accentAlt: Color(0xFFFF9DBC),
    onAccent: Color(0xFF14161F),
    glass: Color(0xD9171A24),
    heroGradient: <Color>[Color(0xFF1B1F33), Color(0xFF2A1E2E)],
    accentGradient: <Color>[Color(0xFF8C9AFF), Color(0xFFB49CFF)],
    pastels: <List<Color>>[
      <Color>[Color(0xFF3A2A26), Color(0xFF4A3129)],
      <Color>[Color(0xFF2C2942), Color(0xFF3A3456)],
      <Color>[Color(0xFF1E3A31), Color(0xFF254A3E)],
      <Color>[Color(0xFF243149), Color(0xFF2C3D5C)],
    ],
    cardRadius: 26,
    heroRadius: 32,
    controlRadius: 16,
    shadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
    ],
    heroShadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x99000000),
        blurRadius: 32,
        offset: Offset(0, 14),
      ),
    ],
  );
}
