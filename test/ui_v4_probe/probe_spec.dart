/// v4「视觉基调」探索用的设计令牌变体(仅预览/测试用)。
///
/// 目的：在同一批屏(输入首页 / 输出首页 / 风格板)上，把五种**视觉基调**
/// 拉到同一个画幅里对比，让用户选方向，而不是直接改 100 个页面。
///
/// 每个 [ProbeSpec] 只描述"这一个基调的世界观":
/// 底/面/墨/强调色、圆角、材质(阴影/描边/纸纹)、字体家族、字阶性格。
/// 组件长什么样由 `probe_screens.dart` 按 [ProbeFlavor] 分派 —— 同一套结构,
/// 五种不同的"说法",这样对比的是基调，不是信息架构。
library;

import 'package:flutter/material.dart';

import 'package:readflow/widgets/graphics/graphics.dart';

import 'probe_fonts.dart';

enum ProbeFlavor {
  /// A 杂志编辑风：纸底、衬线、编号、单色重音
  magazine,

  /// B 深色专业风：近黑、低饱和、细发光、等宽数字
  night,

  /// C 明亮果冻风：大圆角、柔和渐变、彩色软阴影
  jelly,

  /// D 极简工具风:1px 细线、等宽标签、无阴影
  mono,

  /// E 复古印刷风：米纸、衬线、双线、砖红/墨绿
  press,
}

class ProbeSpec {
  final ProbeFlavor flavor;
  final String code;
  final String slug;
  final String name;
  final String mood;
  final List<String> keywords;

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color hairline;
  final Color accent;
  final Color accentAlt;

  final bool dark;
  final bool serifDisplay;
  final bool monoLabels;
  final double cardRadius;
  final double heroRadius;
  final double controlRadius;
  final bool softShadow;
  final double grain;
  final Color grainColor;
  final double heroTitleSize;
  final FontWeight heroTitleWeight;

  final List<Color> palette;

  const ProbeSpec({
    required this.flavor,
    required this.code,
    required this.slug,
    required this.name,
    required this.mood,
    required this.keywords,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.hairline,
    required this.accent,
    required this.accentAlt,
    required this.dark,
    required this.serifDisplay,
    required this.monoLabels,
    required this.cardRadius,
    required this.heroRadius,
    required this.controlRadius,
    required this.softShadow,
    required this.grain,
    required this.grainColor,
    required this.heroTitleSize,
    required this.heroTitleWeight,
    required this.palette,
  });

  // ── 派生色 ──────────────────────────────────────────────────────────

  Color get accentSoft =>
      accent.withValues(alpha: dark ? 0.22 : (flavor == ProbeFlavor.jelly ? 0.12 : 0.09));

  Color get onAccent => accent.computeLuminance() > 0.55 ? ink : Colors.white;

  Color get onInk => ink.computeLuminance() > 0.55 ? const Color(0xFF14161A) : Colors.white;

  /// 卡片投影(柔和方向才用)
  List<BoxShadow> get cardShadow => softShadow
      ? [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: ink.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ]
      : const [];

  // ── 字体 ────────────────────────────────────────────────────────────

  String get displayFamily => serifDisplay ? kSerifLatin : kSans;

  List<String> get displayFallback =>
      serifDisplay ? const <String>[kSerif, kSans] : const <String>[kSans];

  String get labelFamily =>
      monoLabels ? kMono : (serifDisplay ? kSerifLatin : kSans);

  List<String> get labelFallback => monoLabels
      ? const <String>[kSans]
      : (serifDisplay ? const <String>[kSerif, kSans] : const <String>[kSans]);

  TextStyle display(
    Color color, {
    double size = 30,
    FontWeight? weight,
    double? height,
    double? tracking,
  }) =>
      TextStyle(
        fontFamily: displayFamily,
        fontFamilyFallback: displayFallback,
        fontSize: size,
        height: height ?? 1.14,
        letterSpacing: tracking ?? (serifDisplay ? -0.2 : -0.9),
        fontWeight: weight ?? heroTitleWeight,
        color: color,
      );

  TextStyle label(
    Color color, {
    double size = 10.5,
    double? tracking,
    FontWeight weight = FontWeight.w600,
  }) =>
      TextStyle(
        fontFamily: labelFamily,
        fontFamilyFallback: labelFallback,
        fontSize: size,
        height: 1.25,
        letterSpacing:
            tracking ?? (monoLabels ? 1.3 : (serifDisplay ? 1.5 : 0.7)),
        fontWeight: weight,
        color: color,
      );

  TextStyle body(
    Color color, {
    double size = 12.5,
    double height = 1.55,
    FontWeight weight = FontWeight.w500,
  }) =>
      TextStyle(
        fontFamily: serifDisplay ? displayFamily : kSans,
        fontFamilyFallback: displayFallback,
        fontSize: size,
        height: height,
        fontWeight: weight,
        color: color,
      );

  TextStyle number(
    double size,
    Color color, {
    FontWeight weight = FontWeight.w700,
    double? tracking,
  }) =>
      TextStyle(
        fontFamily: serifDisplay ? kSerifLatin : (monoLabels ? kMono : kSans),
        fontFamilyFallback:
            serifDisplay ? const <String>[kSerif] : const <String>[kSans],
        fontSize: size,
        height: 1.0,
        letterSpacing: tracking ?? 0,
        fontWeight: weight,
        color: color,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  // ── 域色处理 ────────────────────────────────────────────────────────
  //
  // 基调之间的差别，一半在"域色怎么用":杂志只在编号旁点一个墨点、
  // 夜读把域色压暗做发光线、果冻把域色冲淡做渐变卡、极简只留一个色块、
  // 印刷把域色煮进墨里做小印章。谁都不能再"一卡一色"。

  Color domainTone(GraphicDomain domain) => switch (flavor) {
        ProbeFlavor.magazine =>
          Color.lerp(domain.baseColor, ink, 0.42) ?? domain.baseColor,
        ProbeFlavor.night =>
          Color.lerp(domain.baseColor, const Color(0xFFCBD5E4), 0.55) ??
              domain.baseColor,
        ProbeFlavor.jelly =>
          Color.lerp(domain.baseColor, const Color(0xFF1D2030), 0.12) ??
              domain.baseColor,
        ProbeFlavor.mono => domain.baseColor,
        ProbeFlavor.press =>
          Color.lerp(domain.baseColor, const Color(0xFF2A241A), 0.38) ??
              domain.baseColor,
      };

  /// 浅底染色(卡片/图标底)
  Color domainWash(GraphicDomain domain) {
    final tone = domainTone(domain);
    return switch (flavor) {
      ProbeFlavor.jelly => Color.lerp(domain.baseColor, Colors.white, 0.80)!,
      ProbeFlavor.night => tone.withValues(alpha: 0.14),
      ProbeFlavor.magazine => tone.withValues(alpha: 0.07),
      ProbeFlavor.press => tone.withValues(alpha: 0.07),
      ProbeFlavor.mono => tone.withValues(alpha: 0.10),
    };
  }

  LinearGradient? domainGradient(GraphicDomain domain) {
    if (flavor != ProbeFlavor.jelly) return null;
    final light = Color.lerp(domain.baseColor, Colors.white, 0.84)!;
    final deep = Color.lerp(domain.baseColor, Colors.white, 0.62)!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[light, deep],
    );
  }
}

/// 五个基调(A→E)。
const List<ProbeSpec> probeSpecs = <ProbeSpec>[
  // ── A · 杂志编辑风 ─────────────────────────────────────────────────
  ProbeSpec(
    flavor: ProbeFlavor.magazine,
    code: 'A',
    slug: 'magazine',
    name: '杂志编辑风',
    mood: '像一本翻开的外刊：纸感底、衬线标题、编号与细线做秩序',
    keywords: <String>['纸感', '衬线', '编号', '单色重音'],
    bg: Color(0xFFF3EEE4),
    surface: Color(0xFFFBF7EE),
    surfaceAlt: Color(0xFFEAE3D4),
    ink: Color(0xFF1D1A15),
    inkSoft: Color(0xFF5E574B),
    inkFaint: Color(0xFF8C8577),
    hairline: Color(0xFFD8CFBC),
    accent: Color(0xFFA8402C),
    accentAlt: Color(0xFF3F5347),
    dark: false,
    serifDisplay: true,
    monoLabels: false,
    cardRadius: 4,
    heroRadius: 0,
    controlRadius: 3,
    softShadow: false,
    grain: 0.055,
    grainColor: Color(0xFF6B5F45),
    heroTitleSize: 46,
    heroTitleWeight: FontWeight.w700,
    palette: <Color>[
      Color(0xFFF3EEE4),
      Color(0xFF1D1A15),
      Color(0xFFA8402C),
      Color(0xFF3F5347),
      Color(0xFFD8CFBC),
      Color(0xFFFBF7EE),
    ],
  ),
  // ── B · 深色专业风 ─────────────────────────────────────────────────
  ProbeSpec(
    flavor: ProbeFlavor.night,
    code: 'B',
    slug: 'nocturne',
    name: '深色专业风',
    mood: '夜读：近黑底、低饱和身份色，界面向后退，内容顶上来',
    keywords: <String>['近黑', '低饱和', '细发光', '等宽数字'],
    bg: Color(0xFF0B0D11),
    surface: Color(0xFF12161C),
    surfaceAlt: Color(0xFF181D25),
    ink: Color(0xFFE9EDF3),
    inkSoft: Color(0xFF98A3B2),
    inkFaint: Color(0xFF69737F),
    hairline: Color(0xFF232A34),
    accent: Color(0xFF8FB2FF),
    accentAlt: Color(0xFFE2B872),
    dark: true,
    serifDisplay: false,
    monoLabels: true,
    cardRadius: 16,
    heroRadius: 0,
    controlRadius: 12,
    softShadow: false,
    grain: 0,
    grainColor: Color(0xFF000000),
    heroTitleSize: 34,
    heroTitleWeight: FontWeight.w700,
    palette: <Color>[
      Color(0xFF0B0D11),
      Color(0xFF12161C),
      Color(0xFF8FB2FF),
      Color(0xFFE2B872),
      Color(0xFF232A34),
      Color(0xFFE9EDF3),
    ],
  ),
  // ── C · 明亮果冻风 ─────────────────────────────────────────────────
  ProbeSpec(
    flavor: ProbeFlavor.jelly,
    code: 'C',
    slug: 'jelly',
    name: '明亮果冻风',
    mood: '轻甜：大圆角、柔和渐变、彩色软阴影，有活力但不幼稚',
    keywords: <String>['大圆角', '柔和渐变', '软阴影', '玻璃浮层'],
    bg: Color(0xFFF6F6FC),
    surface: Colors.white,
    surfaceAlt: Color(0xFFF0F1FA),
    ink: Color(0xFF1D2030),
    inkSoft: Color(0xFF666D82),
    inkFaint: Color(0xFF9CA2B5),
    hairline: Color(0xFFE7E9F4),
    accent: Color(0xFF5B6CFF),
    accentAlt: Color(0xFFFF8BA8),
    dark: false,
    serifDisplay: false,
    monoLabels: false,
    cardRadius: 26,
    heroRadius: 32,
    controlRadius: 16,
    softShadow: true,
    grain: 0,
    grainColor: Color(0xFFFFFFFF),
    heroTitleSize: 34,
    heroTitleWeight: FontWeight.w900,
    palette: <Color>[
      Colors.white,
      Color(0xFF5B6CFF),
      Color(0xFFFF8BA8),
      Color(0xFFD9F5E7),
      Color(0xFFFFE3D3),
      Color(0xFF1D2030),
    ],
  ),
  // ── D · 极简工具风 ─────────────────────────────────────────────────
  ProbeSpec(
    flavor: ProbeFlavor.mono,
    code: 'D',
    slug: 'mono',
    name: '极简工具风',
    mood: '白描:1px 细线、等宽标签、只说必要的话，克制到近乎冷静',
    keywords: <String>['1px 细线', '等宽数字', '无阴影', '单一强调色'],
    bg: Color(0xFFF6F7F9),
    surface: Colors.white,
    surfaceAlt: Color(0xFFF0F2F5),
    ink: Color(0xFF14171C),
    inkSoft: Color(0xFF606A78),
    inkFaint: Color(0xFF98A1AE),
    hairline: Color(0xFFE1E5EB),
    accent: Color(0xFF3555F0),
    accentAlt: Color(0xFF16A394),
    dark: false,
    serifDisplay: false,
    monoLabels: true,
    cardRadius: 10,
    heroRadius: 0,
    controlRadius: 8,
    softShadow: false,
    grain: 0,
    grainColor: Color(0x00000000),
    heroTitleSize: 30,
    heroTitleWeight: FontWeight.w800,
    palette: <Color>[
      Colors.white,
      Color(0xFFF6F7F9),
      Color(0xFF14171C),
      Color(0xFF3555F0),
      Color(0xFFE1E5EB),
      Color(0xFF606A78),
    ],
  ),
  // ── E · 复古印刷风 ─────────────────────────────────────────────────
  ProbeSpec(
    flavor: ProbeFlavor.press,
    code: 'E',
    slug: 'press',
    name: '复古印刷风',
    mood: '铅字：米色纸、衬线大标题、双线版式，砖红与墨绿两枚印章',
    keywords: <String>['米纸', '衬线', '双线', '砖红/墨绿'],
    bg: Color(0xFFEFE5D0),
    surface: Color(0xFFF7EEDA),
    surfaceAlt: Color(0xFFE7DCC2),
    ink: Color(0xFF211D16),
    inkSoft: Color(0xFF5B5245),
    inkFaint: Color(0xFF8B8069),
    hairline: Color(0xFFC6B792),
    accent: Color(0xFFA63E2A),
    accentAlt: Color(0xFF2A4A3E),
    dark: false,
    serifDisplay: true,
    monoLabels: false,
    cardRadius: 0,
    heroRadius: 0,
    controlRadius: 0,
    softShadow: false,
    grain: 0.065,
    grainColor: Color(0xFF7A6440),
    heroTitleSize: 44,
    heroTitleWeight: FontWeight.w700,
    palette: <Color>[
      Color(0xFFEFE5D0),
      Color(0xFF211D16),
      Color(0xFFA63E2A),
      Color(0xFF2A4A3E),
      Color(0xFFC6B792),
      Color(0xFFF7EEDA),
    ],
  ),
];

// ══════════════════════════════════════════════════════════════════════
// 样张文案(全部是真实内容，不编造数字)
// ══════════════════════════════════════════════════════════════════════

class ProbeCopy {
  ProbeCopy._();

  static const String date = '11 月 2 日 · 星期日';
  static const String dateLatin = 'NOV 02 · SUNDAY';
  static const String inputTitle = '输入';
  static const String inputSub = '读和听，才是输入。找不到想读的，去材料中心挑一篇。';
  static const String outputTitle = '输出';
  static const String outputSub = '写词 → 写句 → 写段 → 写篇，四阶并行，从哪阶开始都行。';
  static const String streak = '连续 12 天';
  static const String weekly = '本周 3 小时';
  static const String goal = '目标：四六级';
  static const String level = '水平：B2';

  static const String readTitle = '魔法学院让普通孩子变身自信的戴高帽魔术师';
  static const String readMeta = '外刊 · B2 · 8 分钟';
  static const String readProgress = '62%';

  static const String rowTitle = '随着疫情蔓延，美国麻疹病例数比去年增加一倍以上';
  static const String rowMeta = '外刊 · 8 分钟 · 覆盖率 68%';
  static const String rowTitle2 = 'The Elements of Style';
  static const String rowMeta2 = '公版书 · 46 分钟 · 已读 12%';

  static const String emptyTitle = '还没有读过的材料';
  static const String emptyHint = '按你的目标和难度档找一篇，题目会从你读过的内容里出。';

  static const String boardType = '读一本好书，像和聪明人聊了一个下午。';
  static const String boardBody =
      '阅读是最慢但最稳的学习方式。每天 20 分钟，一年就是 120 小时。';
  static const String boardMeta = '外刊 · 8 分钟 · 覆盖率 68% · Nov 02, 2026';
}
