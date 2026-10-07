import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../services/material_source.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 纯函数层:封面的"内容规则"全部放这里(不碰 BuildContext,可单测)
// ═══════════════════════════════════════════════════════════════════════════

/// 10 套低饱和配色,每套两笔:**[0] 光面(左上)/ [1] 暗面(右下)**。
///
/// 取值原则(不是随手挑的):
/// - 走莫兰迪/纸质书封的沉色,饱和度压低 —— 材料列表一屏十几张封面,
///   高饱和纯色块会互相打架,也会把旁边的正文压得看不见;
/// - 两笔都是"深底",因为封面上永远压白字:实测每套暗面对白字的对比度
///   ≥ 11:1、光面 ≥ 5.9:1(WCAG,`test/material_cover_test.dart` 有闸门锁住),
///   所以浅色主题和深色主题下都不存在"深底 + 深字"。
const List<List<Color>> _coverPalettes = [
  [Color(0xFF43617E), Color(0xFF25384C)], // 靛蓝
  [Color(0xFF4A6B57), Color(0xFF2A4034)], // 苔绿
  [Color(0xFF7A5142), Color(0xFF4C3128)], // 陶土
  [Color(0xFF584E75), Color(0xFF332E48)], // 紫藤
  [Color(0xFF3A6570), Color(0xFF204049)], // 青灰
  [Color(0xFF7B5060), Color(0xFF4C2F3A)], // 玫瑰
  [Color(0xFF6E5A3A), Color(0xFF443623)], // 赭石
  [Color(0xFF47585F), Color(0xFF29363C)], // 石墨
  [Color(0xFF3C6159), Color(0xFF22403A)], // 松柏
  [Color(0xFF6B3C42), Color(0xFF432428)], // 酒红
];

/// 深色主题下的"压暗"目标色(不用纯黑:留一点冷色,配深色主题更协调)
const Color _deepenTarget = Color(0xFF0A0D12);

/// 按标题稳定取配色槽位(纯函数)。
///
/// 为什么不用 `String.hashCode`:它在不同 run 之间不保证一致,列表滚动时
/// 同一篇文章可能"换色"。这里用 FNV-1a 自己算,完全可复现。
int coverPaletteIndex(String seed) {
  final s = seed.trim();
  if (s.isEmpty) return 0;
  var h = 2166136261; // FNV offset basis
  for (final r in s.runes) {
    h ^= r;
    h = (h * 16777619) & 0xFFFFFFFF; // FNV prime,取低 32 位防止越滚越大
  }
  h ^= h >> 13; // 再混一次:同前缀标题(「第 1 讲…」「第 2 讲…」)才不会挤在一桶
  return h % _coverPalettes.length;
}

/// 种子 → 该封面的两笔渐变色(亮面在前)。同一标题 + 同一主题永远同一组色。
///
/// 深色主题整体**再压暗一档**:深背景下"发光"的色块最廉价,压暗后白字对比度
/// 反而更高(暗面 ≥ 13:1),这是"深色模式下也要成立"的具体做法。
List<Color> coverPalette(String seed, Brightness brightness) {
  final base = _coverPalettes[coverPaletteIndex(seed)];
  if (brightness == Brightness.light) return base;
  return <Color>[
    Color.lerp(base[0], _deepenTarget, 0.16)!,
    Color.lerp(base[1], _deepenTarget, 0.28)!,
  ];
}

/// 主体文字取字规则(纯函数,单测覆盖)。
///
/// ## 小卡为什么要"第一个有意义的词",而不是标题前两个字
/// 用户截图里的「A电」「GG」「护」就是旧规则(取标题前 2 个字)的产物:
/// 冠词 `A` 和「电池」的"电"拼在一起,既不成词,也不指代任何东西 ——
/// 用户读完标题再回头看封面,对不上,这就是"意义不明"的来源。
///
/// 人扫封面是"抓词"的,所以:
/// - **英文**:取第一个长度 ≥4 的实词,首字母大写。
///   冠词/介词(the/of/on)没有信息量必须跳过;而英文标题的第一个实词
///   通常就是专名或主题词(`GENMO` / `Notes` / `Origin`),抓它最省认知。
///   若这个词长到一行放不下(> 8 字母),**先换下一个放得下的实词**,
///   实在没有才截断 —— 「Superc」这种半截字也是"意义不明";
/// - **中文**:没有词边界,取前 3 个字。3 个字在绝大多数标题上恰好落在词内
///   (「护眼灯」「电池管」),比 2 个字更不容易切成残字。
///
/// [small] 为 false 时放宽到 10 字符/4 汉字 —— 大卡本来走标题全文,
/// 这一支只作为"标题放不下时的兜底"(例如真图占位、极窄卡)。
String coverMonogram(String title, {required bool small}) {
  final s = _monoSource(title);
  if (s.isEmpty) return '·'; // 空标题也给个字符:封面绝不能是一块什么都没有的色块
  final tokens = _dropLeadingNoise(s.split(' ').where((t) => t.isNotEmpty).toList());
  if (tokens.isEmpty) return '·';

  final cjkLimit = small ? 3 : 4;
  final wordLimit = small ? 8 : 10;

  // ① 中文开头 → 取连续汉字(遇到英文就停:「护眼灯 Light」→「护眼灯」)。
  //    结构字/虚词单独成 token 时不算数(见 [_cjkLeadingNoise]),往后让 ⑤ 兜。
  if (_isCjk(tokens.first.runes.first)) {
    final run = _cjkMonogram(tokens.first, cjkLimit);
    if (run.runes.length >= 2 || tokens.length == 1) return run;
  }
  // ② 第一个"长度 ≥4 的实词" —— 短词(the/of/on)没有信息量。
  //    优先取"放得下"的那个:8 个字母在 78 的小卡上正好占满宽度。
  String? longest;
  for (final t in tokens) {
    if (!_isWordLike(t) || t.runes.length < 4) continue;
    longest ??= t;
    if (t.runes.length <= wordLimit) return _titleCase(t);
  }
  // ③ 所有实词都超上限:才退到第一个并截断 ——
  //    宁可换个词,也不要「Superc」这种半截字(半截字也是"意义不明")
  if (longest != null) return _titleCase(_clipRunes(longest, wordLimit));
  // ④ 全是短词:退到第一个长度 ≥2 的实词("On War" → War)
  for (final t in tokens) {
    if (_isWordLike(t) && t.runes.length >= 2) return _titleCase(t);
  }
  // ⑤ 开头是「第」「章」这类结构字:往后找第一个真正有信息量的中文 token
  //    (「第 3 章 边界与索引」→「边界」,而不是「第」)
  for (final t in tokens) {
    if (!_isCjk(t.runes.first)) continue;
    final run = _cjkMonogram(t, cjkLimit);
    if (run.runes.length >= 2) return run;
  }
  // ⑥ 实在没有可用词:第一个 token 截断(保底不空)
  final lone = _cjkMonogram(tokens.first, cjkLimit);
  if (lone.isNotEmpty) return lone;
  return _titleCase(_clipRunes(tokens.first, wordLimit));
}

/// 大卡主体文字:标题前 [maxChars] 个字符,截断时补「…」。
///
/// 英文标题会**退到词边界**再截 —— 封面上的半截单词比少两个字更难看
/// (退得太多就不值当,所以要求至少保留 60% 的预算)。
String coverTitleSnippet(String title, {required int maxChars}) {
  final s = _normalizeTitle(title);
  if (s.isEmpty) return '';
  final budget = math.max(4, maxChars);
  if (s.runes.length <= budget) return s;

  var cut = String.fromCharCodes(s.runes.take(budget));
  final next = s.runes.elementAt(budget);
  if (_isAsciiLetter(next) && _isAsciiLetter(cut.runes.last)) {
    final sp = cut.lastIndexOf(' ');
    if (sp >= (budget * 0.6).floor()) cut = cut.substring(0, sp);
  }
  return '${cut.trimRight()}…';
}

/// 种类图标(种类集合与 `MaterialLibrary.kindLabel` 一致,未知一律当"文章")
IconData coverKindIcon(String kind) => switch (kind) {
      'book' => Icons.menu_book,
      'news' => Icons.newspaper,
      'paper' => Icons.science_outlined,
      'podcast' => Icons.podcasts,
      'wiki' => Icons.public,
      _ => Icons.article_outlined,
    };

/// 种类中文名。[compact] 为 true 时给「1~2 字」的短名。
///
/// 为什么不用 `MaterialLibrary.kindLabel` 那套完整文案:封面徽标只有几十像素宽,
/// 「外刊/新闻」「播客/听力」会把徽标撑满整张封面 —— 卡片正文里已经有完整文案了,
/// 封面只负责"一眼看出这是什么材料"。
String coverKindLabel(String kind, {bool compact = false}) {
  if (compact) {
    return switch (kind) {
      'book' => '书',
      'news' => '外刊',
      'paper' => '论文',
      'podcast' => '播客',
      'wiki' => '百科',
      _ => '文章',
    };
  }
  return switch (kind) {
    'book' => '原版书',
    'news' => '外刊/新闻',
    'paper' => '论文',
    'podcast' => '播客/听力',
    'wiki' => '百科',
    _ => '文章',
  };
}

/// 难度胶囊配色:同一难度全屏一个颜色,扫一眼就知道"这篇比那篇难"。
/// 四档都是深色低饱和,叠白字的对比度实测 8.0~10.0:1(闸门在单测里)。
///
/// 只认 `Lv7` 这种格式:认不出来就给中性色 —— 宁可没颜色,也不能把
/// `A2` 误当成 Lv2 涂成"入门绿"(难度是用户会当真的信息)。
Color coverLevelTint(String levelLabel) {
  final m = RegExp(r'^[Ll]v\s*(\d+)$').firstMatch(levelLabel.trim());
  final lv = m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  if (lv <= 0) return const Color(0xB325384C); // 认不出等级:中性靛蓝
  if (lv <= 3) return const Color(0xD92C5646); // 入门:青绿
  if (lv <= 6) return const Color(0xD92E4A6B); // 进阶:靛蓝
  if (lv <= 8) return const Color(0xD96A4A22); // 挑战:赭金
  return const Color(0xD96B2F3A); // 硬核:绛红
}

/// 难度胶囊的文案:空白/纯空格一律视为"没有",免得画出空胶囊
String coverLevelText(String? levelLabel) => (levelLabel ?? '').trim();

/// 有没有可用的真实配图。
///
/// 只认 http(s):`Image.network` 处理不了 `file://` 或本地路径,硬塞进去
/// 必然走 errorBuilder —— 不如一开始就直说"没有图",直接用程序化封面,
/// 少一次无意义的请求,也不会闪一下白块。
bool coverHasImage(String? imageUrl) {
  final s = (imageUrl ?? '').trim();
  return s.startsWith('http://') || s.startsWith('https://');
}

/// 难度胶囊是否显示:小于 56(52 的列表缩略图)时藏掉 ——
/// 那个尺寸下它只能挤成一条看不清的细线,不如把空间让给主体文字。
bool coverShowLevelBadge(String? levelLabel, double shortestSide) =>
    shortestSide >= 56 && coverLevelText(levelLabel).isNotEmpty;

/// 是否走"大卡"版式(标题全文 + 底部一行种类小字)
bool coverIsLarge(double height) => height >= 120;

/// 类型徽标是否只留图标。
/// 52 的小卡上「图标 + 2 个字」会占掉 2/3 宽度,和主体文字抢视线。
bool coverBadgeIconOnly(double shortestSide) => shortestSide < 64;

/// 类型徽标是否改用 1~2 字短名(否则用完整中文名)
bool coverBadgeCompact(double shortestSide) => shortestSide < 96;

/// 大卡右下角那行"种类小字"是否显示。
///
/// 三种情况不显示:① 小卡(没空间);② 有真图(压在照片上像补丁);
/// ③ 卡片太窄(左下的难度胶囊 + 右下的种类名会撞在一起)。
bool coverShowKindText(double width, double height, {required bool hasImage}) =>
    coverIsLarge(height) && !hasImage && width >= 168;

/// 大卡主体文字的字数预算(用户要求 14~18 字:封面只负责"认出是哪篇",
/// 完整标题本来就在封面右边的卡片上,不该重复)
int coverTitleCharBudget(double height) {
  if (height >= 168) return 18;
  if (height >= 140) return 16;
  return 14;
}

/// 大卡主体文字的最大行数(卡片不够高时降到 2 行,避免字号被压得太小)
int coverTitleMaxLines(double height) => height >= 150 ? 3 : 2;

/// 大卡标题字号:随高度线性放大,上限 21(再大就"喊"了,不像书封)
double coverTitleFontSize(double height) => (height * 0.125).clamp(14.0, 21.0);

/// 小卡单字号:随边长线性放大,上限 26
double coverMonogramFontSize(double shortestSide) =>
    (shortestSide * 0.28).clamp(12.0, 26.0);

// ── 取字的内部工具(私有,但都是纯函数) ──────────────────────────────────

/// 英文里的功能词:开头的这些没有信息量,取字时要跳过
const Set<String> _leadingNoise = {
  'a', 'an', 'the', 'of', 'on', 'in', 'to', 'at', 'by', 'for', 'from', 'with',
  'and', 'or', 'is', 'are', 'as', 'my', 'his', 'her', 'its', 'our', 'their',
  'this', 'that', 'these', 'those', 'no', 'not',
};

/// 中文里"只有结构意义"的字:**只有一个「第」**。
///
/// 集合故意留得极小,因为多一个候选就多一种掐坏标题的可能:「个」有「个人」、
/// 「回」有「回忆录」、「课」有「课外」、「章」有「章鱼」—— 都是常见词头。
/// 而「第」几乎只作序数前缀,掐掉之后若不足 2 个字会整体退回(「第一」→「一」
/// 退回成「第一」),所以是安全的。真正做到"跳过无信息量 token"的是
/// [coverMonogram] 里"中文至少 2 个字才算数"这条规则 —— 「第 3 章 边界与索引」
/// 里的「第」「章」都是单字,本来就进不了封面。
const Set<String> _cjkLeadingNoise = {'第'};

/// 中文里"没收尾"的虚词:出现在封面字末尾会像写了一半
const Set<String> _cjkTrailingNoise = {
  '的', '地', '得', '了', '着', '与', '和', '之', '及', '或', '是', '在', '把',
  '被', '让', '使', '令', '对', '为', '以', '而', '则', '并', '且', '又', '从',
  '向', '跟', '同', '给', '就', '都', '也',
};

/// 清洗标题:去掉书名号/引号/序号,只留字母、数字、汉字、假名与连字符
String _monoSource(String title) {
  return title
      .replaceAll(RegExp(r'[《》〈〉「」『』【】〔〕（）()\[\]{}“”‘’"]'), ' ')
      .replaceAll(RegExp(r"[^A-Za-z0-9\u3400-\u4dbf\u4e00-\u9fff\u3040-\u30ff'\-]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// 清洗标题(大卡用):保留标点(冒号/逗号在书封上是好看的),
/// 只去装饰性包裹与 Markdown 残留
String _normalizeTitle(String raw) {
  var s = raw.replaceAll(RegExp(r'[《》〈〉「」『』【】〔〕“”‘’"]'), ' ');
  s = s.replaceAll(RegExp(r'[*_`#>|]+'), ' ');
  s = s.replaceAll(RegExp(r'^\s*\d+[.、)．]\s*'), ''); // 列表序号「1. 」
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 掐掉开头的功能词(至少留一个 token,不然"On War"会被掐空)
List<String> _dropLeadingNoise(List<String> tokens) {
  var i = 0;
  while (i < tokens.length - 1 && _leadingNoise.contains(tokens[i].toLowerCase())) {
    i++;
  }
  return tokens.sublist(i);
}

bool _isCjk(int r) =>
    (r >= 0x4E00 && r <= 0x9FFF) ||
    (r >= 0x3400 && r <= 0x4DBF) ||
    (r >= 0xF900 && r <= 0xFAFF);

bool _isAsciiLetter(int r) =>
    (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);

bool _isUpperAscii(int r) => r >= 0x41 && r <= 0x5A;

bool _isWordLike(String t) {
  if (t.isEmpty) return false;
  return RegExp(r"^[A-Za-z][A-Za-z0-9'\-]*$").hasMatch(t);
}

/// 取 token 开头的连续汉字 → 封面字(最多 [limit] 个)。
///
/// 两个"掐一下"的动作,都是为了不出现看着像没写完的字:
/// - **掐头**:「第」「章」「个」这类只有结构意义的字单独当封面字什么也不说明
///   (「第 3 章 边界与索引」取到「第」就是又一次"意义不明");掐完不足 2 个字
///   就整体退回,免得「本能」被掐成「能」;
/// - **去尾**:「的」「与」「在」这类虚词收尾会像半截话(「沉默的」→「沉默」)。
String _cjkMonogram(String token, int limit) {
  final all = <int>[];
  for (final r in token.runes) {
    if (!_isCjk(r)) break;
    all.add(r);
  }
  if (all.isEmpty) return '';
  var start = 0;
  while (start < all.length && _cjkLeadingNoise.contains(_ch(all[start]))) {
    start++;
  }
  if (all.length - start < 2) start = 0; // 掐多了就退回
  var run = all.sublist(start, math.min(all.length, start + limit));
  while (run.length > 2 && _cjkTrailingNoise.contains(_ch(run.last))) {
    run = run.sublist(0, run.length - 1);
  }
  return String.fromCharCodes(run);
}

String _ch(int r) => String.fromCharCode(r);

String _clipRunes(String s, int max) => s.runes.length <= max
    ? s
    : String.fromCharCodes(s.runes.take(max));

/// 首字母大写:全大写专名(GENMO/BBC)原样保留;词内还有大写(iPhone/DeepMind)
/// 时只抬首字母,不动其余 —— 否则会把品牌名改坏
String _titleCase(String w) {
  if (w.isEmpty) return w;
  final rs = w.runes.toList();
  if (rs.length > 1 && w.toUpperCase() == w) return w;
  final rest = String.fromCharCodes(rs.skip(1));
  final internalCaps = rest.runes.any(_isUpperAscii);
  return String.fromCharCode(rs.first).toUpperCase() +
      (internalCaps ? rest : rest.toLowerCase());
}

// ═══════════════════════════════════════════════════════════════════════════
// 封面本体
// ═══════════════════════════════════════════════════════════════════════════

/// 材料封面(v2.10 重做,用户第 (5) 条:"依然很简陋和意义不明")。
///
/// ## 为什么是程序化封面而不是网图(沿用上一版的调研结论)
/// 参考软件(扇贝阅读)那张水彩插画是自有版权图库的产物;本机实测
/// Wikipedia/Openverse/Gutendex/Open Library/Internet Archive 全部不可达
/// (DNS 污染),可达的只有 Gutenberg 封面 / Bing 每日图(不可商用)/ Unsplash 直链。
/// 所以**零网络、零版权**的程序化封面是稳妥的底,有真图时再用真图盖上去。
///
/// ## 这次重做解决什么
/// 上一版 = 纯色块 + 标题前两个字(「护」「GG」「A电」)+ 一个种类小角标。
/// - **简陋**:只有一层渐变,没有任何"印刷品"的层次;
/// - **意义不明**:「A电」把冠词和首字硬拼在一起,不构成词也不指代任何东西。
///
/// 这一版从底到上五层(每一层都有明确职责,不是堆装饰):
/// 1. **底**:按标题 hash 稳定取色的双色渐变(10 套低饱和配色),亮面在左上、
///    暗面在右下 —— 斜向渐变比纯色多一层空间感,同一篇永远同一色;
/// 2. **纹理**:按 [kind] 自绘的几何纹理(书=书脊+页线 / 论文=点阵 /
///    外刊=斜切色带 / 播客=同心圆弧 / 百科=经纬球 / 文章=排版行线),
///    白 20~22/255 的极淡透明度 —— 只在"看第二眼"时出现,绝不抢主体;
/// 3. **主体文字**:大卡显示标题前 14~18 字(底部对齐,最多 2~3 行),
///    小卡显示"第一个有意义的词"([coverMonogram]);
/// 4. **徽标**:左上角种类徽标(图标 + 中文),左下角难度胶囊(按档位配色),
///    大卡右下角再补一行种类小字;
/// 5. **真图优先**:有 [imageUrl] 就用网图**盖住**程序化封面,再压一层暗色渐变
///    保证徽标可读 —— 加载中/失败时露出的就是下面那层程序化封面,
///    所以永远不会出现白块(不需要任何计时器或状态)。
class MaterialCover extends StatelessWidget {
  /// 取材种子:用标题(稳定即可)。同一标题永远同一张封面。
  final String seed;

  /// 材料种类(book/news/paper/podcast/wiki/article)—— 决定图标与纹理
  final String kind;

  /// 可选真实配图(Gutenberg 封面 / RSS og:image)。为空则用程序化封面。
  final String? imageUrl;

  final double width;
  final double height;

  /// 圆角(默认卡片圆角 16);传 0 表示由父级裁剪
  final double radius;

  /// 左下角等级徽标(如 'Lv8');为空不显示
  final String? levelLabel;

  const MaterialCover({
    super.key,
    required this.seed,
    this.kind = 'article',
    this.imageUrl,
    this.width = double.infinity,
    this.height = 168,
    this.radius = Radii.card,
    this.levelLabel,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: LayoutBuilder(
          builder: (context, box) {
            // 调用方常传 width: double.infinity(拉伸铺满),真实尺寸从约束里拿
            final w = box.maxWidth.isFinite
                ? box.maxWidth
                : (width.isFinite ? width : height);
            final h = box.maxHeight.isFinite
                ? box.maxHeight
                : (height.isFinite ? height : w);
            final short = math.min(w, h);
            final showLevel = coverShowLevelBadge(levelLabel, short);
            final chrome = _CoverChrome.of(w, h, showLevel: showLevel);
            final colors = coverPalette(seed, brightness);
            final hasImage = coverHasImage(imageUrl);
            final large = coverIsLarge(h);
            // v2.11:按**真实渲染尺寸 × 设备像素比**解码(见下面 Image.network 的注释)
            final dpr = MediaQuery.devicePixelRatioOf(context);
            final decodeW = (math.max(w, h) * dpr).round();

            return Stack(
              fit: StackFit.expand,
              children: [
                // ① + ② + ③ 程序化封面(真图会整个盖住它,包括里面的标题文字)
                _procedural(colors, chrome, large),
                if (hasImage) ...[
                  Image.network(
                    imageUrl!.trim(),
                    fit: BoxFit.cover,
                    // v2.11:小卡按**设备像素**解码,别把 2000px 的原图整张读进内存。
                    // 为什么必须给:列表里同时有十几张封面,而项目里**没有**
                    // 磁盘缓存依赖(见 pubspec 血泪教训:加插件后 APK 可能构建不过),
                    // 只能靠 Flutter 默认的内存 ImageCache —— 不限制解码尺寸时,
                    // 一张 2000×1084 的头图 decoded 后是 ~8MB,十几张就把缓存冲爆,
                    // 表现为"滚动时图反复消失重下"。
                    cacheWidth: decodeW > 0 ? decodeW : null,
                    // 加载中/失败都返回透明占位:露出的就是下层程序化封面,
                    // 既不会白块,也不必把封面重画一遍
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const SizedBox.expand(),
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.expand(),
                  ),
                  _imageScrim(),
                ],
                // ④ 类型徽标:左上
                Positioned(
                  left: chrome.pad,
                  top: chrome.pad,
                  child: _kindChip(chrome),
                ),
                // ④ 难度胶囊:左下(与类型徽标一上一下,永不重叠)
                if (showLevel)
                  Positioned(
                    left: chrome.pad,
                    bottom: chrome.pad,
                    child: _levelPill(chrome),
                  ),
                // ④ 大卡右下:种类小字(把左下让给难度胶囊)
                if (coverShowKindText(w, h, hasImage: hasImage))
                  Positioned(
                    right: chrome.pad,
                    bottom: chrome.pad + 4,
                    child: _kindText(chrome),
                  ),
                // ⑤ 外廓 1px 描边 + 顶边内阴影:小卡在深色背景上不"糊"进卡片
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _CoverEdgePainter(radius: radius)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 程序化封面:渐变底 + 纹理 + 顶部提亮/底部压暗 + 主体文字
  Widget _procedural(List<Color> colors, _CoverChrome c, bool large) {
    final text = large
        ? coverTitleSnippet(seed, maxChars: c.titleChars)
        : coverMonogram(seed, small: true);
    final body = text.isEmpty ? coverKindLabel(kind) : text; // 空标题兜底,绝不空白
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
        ),
        CustomPaint(painter: _CoverTexturePainter(kind: kind)),
        // 顶部一点"光"、底部压暗:底部压暗是白字对比度的保险(暗面本来已经够深)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withAlpha(20),
                Colors.white.withAlpha(0),
                Colors.black.withAlpha(52),
              ],
              stops: const [0.0, 0.46, 1.0],
            ),
          ),
        ),
        Positioned(
          left: c.pad,
          right: c.pad,
          top: large ? c.pad + c.chipHeight + 8 : c.pad + c.chipHeight + 3,
          bottom: large
              ? c.pad + c.levelHeight + 8
              : c.pad + (c.hasLevel ? c.levelHeight + 3 : 0),
          child: large ? _titleBlock(body, c) : _monoBlock(body, c),
        ),
      ],
    );
  }

  /// 大卡标题:底部对齐,最多 [titleMaxLines] 行
  Widget _titleBlock(String text, _CoverChrome c) {
    return FittedBox(
      // 第三道保险:字号/行数都算过了,真放不下时整体等比缩小,绝不溢出
      fit: BoxFit.scaleDown,
      alignment: Alignment.bottomLeft,
      child: SizedBox(
        width: c.bodyWidth, // 先按这个宽度折行,否则 FittedBox 里文字不会换行
        child: Text(
          text,
          maxLines: c.titleLines, // 第二道保险
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: c.titleFont, // 第一道保险:字号随尺寸算,且有上限
            height: 1.32, // 中文要多留行高,1.32 是"不挤也不散"的甜点
            fontWeight: FontWeight.w700,
            color: Colors.white.withAlpha(245),
            letterSpacing: 0.2,
            shadows: const [
              Shadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }

  /// 小卡单字:居中,一行;汉字给足字距,拉丁词收紧一点
  Widget _monoBlock(String text, _CoverChrome c) {
    final cjk = text.isNotEmpty && _isCjk(text.runes.first);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: c.monoFont,
          height: 1.12,
          fontWeight: FontWeight.w700,
          color: Colors.white.withAlpha(248),
          letterSpacing: c.monoFont * (cjk ? 0.10 : 0.02),
          shadows: const [
            Shadow(color: Color(0x73000000), blurRadius: 7, offset: Offset(0, 2)),
          ],
        ),
      ),
    );
  }

  /// 类型徽标:半透明玻璃底 + 细白描边 + 白字(小尺寸下自动退化成图标)
  ///
  /// 整块关掉系统字号缩放(`withNoTextScaling`):封面是**缩略图**,
  /// 这三枚徽标是固定尺寸的装饰层 —— 跟着系统字号放大,在 78 的小卡上会
  /// 直接吃掉半张封面(实测 2.0 倍时难度胶囊宽到 55/78),而且会让
  /// `_CoverChrome` 算出的壳层高度对不上真实排版,进而压到主体文字。
  /// 真正的信息(种类/难度)在封面右边的卡片正文里还有一份,不靠这里。
  Widget _kindChip(_CoverChrome c) {
    return MediaQuery.withNoTextScaling(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: c.bodyWidth),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: c.chipPadH,
            vertical: c.chipPadV,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(120),
            borderRadius: BorderRadius.circular(999), // 胶囊
            border: Border.all(color: Colors.white.withAlpha(40), width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                coverKindIcon(kind),
                size: c.chipIcon,
                color: Colors.white.withAlpha(240),
              ),
              if (c.chipWithText) ...[
                const SizedBox(width: 3.5),
                Flexible(
                  child: Text(
                    coverKindLabel(kind, compact: c.chipCompact),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: c.chipFont,
                      height: 1.05,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withAlpha(242),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 难度胶囊:颜色按等级档位走(同一难度全屏同色)
  Widget _levelPill(_CoverChrome c) {
    final text = coverLevelText(levelLabel);
    return MediaQuery.withNoTextScaling(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: c.levelPadH,
          vertical: c.levelPadV,
        ),
        decoration: BoxDecoration(
          color: coverLevelTint(text),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withAlpha(48), width: 0.8),
        ),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontSize: c.levelFont,
            height: 1.05,
            fontWeight: FontWeight.w700,
            color: Colors.white.withAlpha(246),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  /// 大卡右下角那行种类小字(与左下的难度胶囊左右对称)
  Widget _kindText(_CoverChrome c) {
    return MediaQuery.withNoTextScaling(
      child: Text(
        coverKindLabel(kind),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: c.levelFont,
          height: 1.05,
          fontWeight: FontWeight.w500,
          color: Colors.white.withAlpha(186),
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  /// 真图上的暗色渐变:上下两头压暗(徽标都在这两头),中间留亮给照片
  Widget _imageScrim() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withAlpha(112),
            Colors.black.withAlpha(16),
            Colors.black.withAlpha(124),
          ],
          stops: const [0.0, 0.42, 1.0],
        ),
      ),
    );
  }
}

/// 封面"壳层"(内边距 / 徽标 / 难度胶囊 / 字号)的尺寸档。
///
/// 为什么单独抽一个类:主体文字的可用区域 = 卡片尺寸 − 上下壳层高度,
/// 这几个数散在 build 里写,小卡上必然出现"标题压在徽标下面"的重叠。
/// 集中算一遍,重叠就不可能发生(见 `_CoverChrome.of` 的注释)。
class _CoverChrome {
  const _CoverChrome({
    required this.width,
    required this.pad,
    required this.chipIcon,
    required this.chipFont,
    required this.chipPadH,
    required this.chipPadV,
    required this.chipWithText,
    required this.chipCompact,
    required this.monoFont,
    required this.titleFont,
    required this.titleLines,
    required this.titleChars,
    required this.levelFont,
    required this.levelPadH,
    required this.levelPadV,
    required this.hasLevel,
  });

  final double width;
  final double pad;

  final double chipIcon;
  final double chipFont;
  final double chipPadH;
  final double chipPadV;
  final bool chipWithText;
  final bool chipCompact;

  final double monoFont;
  final double titleFont;
  final int titleLines;
  final int titleChars;

  final double levelFont;
  final double levelPadH;
  final double levelPadV;

  /// 难度胶囊是否画(尺寸够 + 有文案);文字区块要按它留边距
  final bool hasLevel;

  /// 徽标高度(含 0.8 的描边):主体文字的 top 边距由它决定
  double get chipHeight =>
      (chipWithText ? math.max(chipIcon, chipFont * 1.05) : chipIcon) +
      chipPadV * 2 +
      1.6;

  /// 难度胶囊高度
  double get levelHeight => levelFont * 1.05 + levelPadV * 2 + 1.6;

  /// 主体文字可用宽度
  double get bodyWidth => math.max(8.0, width - pad * 2);

  /// 按卡片尺寸选档。三个真实档位:52 / 76~92(小卡)、186(大卡)。
  static _CoverChrome of(double w, double h, {required bool showLevel}) {
    final short = math.min(w, h);
    if (coverIsLarge(h)) {
      return _CoverChrome(
        width: w,
        pad: (h * 0.075).clamp(12.0, 18.0), // 186 → 14
        chipIcon: 14,
        chipFont: 11.5,
        chipPadH: 8,
        chipPadV: 4,
        chipWithText: true,
        chipCompact: false,
        monoFont: coverMonogramFontSize(short),
        titleFont: coverTitleFontSize(h),
        titleLines: coverTitleMaxLines(h),
        titleChars: coverTitleCharBudget(h),
        levelFont: 10.5,
        levelPadH: 7,
        levelPadV: 2.5,
        hasLevel: showLevel,
      );
    }
    final iconOnly = coverBadgeIconOnly(short);
    return _CoverChrome(
      width: w,
      pad: (short * 0.085).clamp(5.0, 9.0), // 78 → 6.6 / 88 → 7.5 / 52 → 5
      chipIcon: iconOnly ? 11 : 11.5,
      chipFont: 9.5,
      chipPadH: iconOnly ? 5 : 4.5,
      chipPadV: iconOnly ? 4 : 3,
      chipWithText: !iconOnly,
      chipCompact: coverBadgeCompact(short),
      monoFont: coverMonogramFontSize(short),
      titleFont: coverTitleFontSize(h),
      titleLines: coverTitleMaxLines(h),
      titleChars: coverTitleCharBudget(h),
      levelFont: 9,
      levelPadH: 5.5,
      levelPadV: 1.5,
      hasLevel: showLevel,
    );
  }
}

/// 按 [kind] 画低对比度几何纹理。用 CustomPainter 自绘:零依赖、零资源。
///
/// 三条自我约束:
/// - 透明度只有 20~22/255(白),层次感靠"形"而不是靠"亮";
/// - 线条间距下限 9px —— 52 的小卡上按比例画会把线挤成一片灰雾;
/// - 只画 5~8 笔,列表里一屏十几张封面也不会掉帧。
class _CoverTexturePainter extends CustomPainter {
  const _CoverTexturePainter({required this.kind});

  final String kind;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final short = math.min(w, h);
    final step = math.max(9.0, short / 6.0);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, short / 110)
      ..color = Colors.white.withAlpha(22);
    final fill = Paint()..color = Colors.white.withAlpha(20);

    if (kind == 'book') {
      _book(canvas, size, step, stroke, fill);
    } else if (kind == 'paper') {
      _paper(canvas, size, fill);
    } else if (kind == 'news') {
      _news(canvas, size, step, fill);
    } else if (kind == 'podcast') {
      _podcast(canvas, size, short, stroke);
    } else if (kind == 'wiki') {
      _wiki(canvas, size, stroke);
    } else {
      _article(canvas, size, step, stroke);
    }
  }

  /// 书:左侧一条"书脊"竖带 + 右侧页线
  void _book(Canvas canvas, Size size, double step, Paint stroke, Paint fill) {
    final spine = (size.width * 0.11).clamp(5.0, 16.0);
    canvas.drawRect(Rect.fromLTWH(0, 0, spine, size.height), fill);
    canvas.drawLine(Offset(spine, 0), Offset(spine, size.height), stroke);
    for (var y = step * 1.3; y < size.height - step * 0.2; y += step) {
      canvas.drawLine(
        Offset(spine + step * 0.55, y),
        Offset(size.width - step * 0.4, y),
        stroke,
      );
    }
  }

  /// 论文:点阵纸
  void _paper(Canvas canvas, Size size, Paint fill) {
    final dot = math.max(7.0, math.min(size.width, size.height) / 8.0);
    final r = math.max(0.8, dot / 9.0);
    for (var y = dot; y < size.height; y += dot) {
      for (var x = dot; x < size.width; x += dot) {
        canvas.drawCircle(Offset(x, y), r, fill);
      }
    }
  }

  /// 外刊:斜切色带(-30°)
  void _news(Canvas canvas, Size size, double step, Paint fill) {
    final band = math.max(10.0, step * 1.5);
    final span = size.width + size.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.52);
    for (var x = -span; x < span; x += band * 2) {
      canvas.drawRect(Rect.fromLTWH(x, -span, band, span * 2), fill);
    }
    canvas.restore();
  }

  /// 播客:从左下角扩散的同心圆弧(声波)
  void _podcast(Canvas canvas, Size size, double short, Paint stroke) {
    final center = Offset(size.width * 0.22, size.height * 0.88);
    final maxR = math.sqrt(size.width * size.width + size.height * size.height);
    final rStep = math.max(8.0, short / 5.0);
    for (var r = rStep; r < maxR; r += rStep) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        -math.pi * 0.62,
        math.pi * 0.78,
        false,
        stroke,
      );
    }
  }

  /// 百科:经纬球
  void _wiki(Canvas canvas, Size size, Paint stroke) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * 0.42;
    canvas.drawCircle(c, r, stroke);
    for (var i = 1; i <= 2; i++) {
      final dy = r * i / 3;
      final rx = math.sqrt(math.max(0.0, r * r - dy * dy));
      canvas.drawLine(Offset(c.dx - rx, c.dy - dy), Offset(c.dx + rx, c.dy - dy), stroke);
      canvas.drawLine(Offset(c.dx - rx, c.dy + dy), Offset(c.dx + rx, c.dy + dy), stroke);
    }
    for (var i = 1; i <= 2; i++) {
      final rx = r * i / 3;
      canvas.drawOval(
        Rect.fromCenter(center: c, width: rx * 2, height: r * 2),
        stroke,
      );
    }
  }

  /// 文章(以及一切未知种类):模拟排版行线,长短交替像一段正文
  void _article(Canvas canvas, Size size, double step, Paint stroke) {
    var y = step * 0.9;
    var i = 0;
    while (y < size.height - step * 0.3) {
      final short = i % 3 == 2; // 每三行来一条短的,像段末
      canvas.drawLine(
        Offset(step * 0.5, y),
        Offset(short ? size.width * 0.62 : size.width - step * 0.4, y),
        stroke,
      );
      y += step;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _CoverTexturePainter old) => old.kind != kind;
}

/// 封面外廓:1px 上亮下暗的描边 + 顶边内阴影。
///
/// 为什么必须有:封面块本身很深,在深色主题的卡片上几乎同色,没这一笔
/// 小卡就"糊"在卡片里(用户上一版截图正是这个问题)。
class _CoverEdgePainter extends CustomPainter {
  const _CoverEdgePainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = math.max(0.0, radius);
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(r));

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(r)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withAlpha(58), Colors.white.withAlpha(16)],
        ).createShader(rect),
    );

    final shadeH = math.min(size.height * 0.22, 16.0);
    final shadeRect = Rect.fromLTWH(0, 0, size.width, shadeH);
    canvas.save();
    canvas.clipRRect(outer);
    canvas.drawRect(
      shadeRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withAlpha(40), Colors.black.withAlpha(0)],
        ).createShader(shadeRect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CoverEdgePainter old) => old.radius != radius;
}

/// 材料"等级"与元信息(v2.8,参考软件的 `Lv8` 徽标)。
///
/// 口径(见 SPEC 文档 §5):**等级 = 文本难度**,与"适不适合你"分开表达 ——
/// 所以卡片上会同时出现 `Lv8`(文本难度)与「已知 97%」(个人匹配)。
/// 文本难度直接取本地已算好的 CEFR(离线、零 API),映射到 Lv1~Lv10;
/// 没有 CEFR 时按种类给一个保守默认(新闻/论文偏难、播客偏易)。
class MaterialLevel {
  MaterialLevel._();

  static const Map<String, int> _cefrToLv = {
    'A1': 1,
    'A2': 3,
    'B1': 5,
    'B2': 7,
    'C1': 8,
    'C2': 9,
  };

  /// CEFR → Lv(1~10)。认不出 CEFR 时用 [fallbackForKind]。
  static int of(String cefr, {String kind = 'article'}) {
    final key = cefr.trim().toUpperCase();
    for (final e in _cefrToLv.entries) {
      if (key.startsWith(e.key)) return e.value;
    }
    return fallbackForKind(kind);
  }

  /// 没有难度数据时的默认等级(宁可保守,别把难的说成简单)
  static int fallbackForKind(String kind) => switch (kind) {
        'book' => 7,
        'paper' => 9,
        'news' => 7,
        'podcast' => 5,
        'wiki' => 8,
        _ => 6,
      };

  static String label(String cefr, {String kind = 'article'}) =>
      'Lv${of(cefr, kind: kind)}';

  /// 个人匹配文案(与 MaterialBand 的档位口径一致,但更口语)
  static String matchHint(double knownTokenRatio) {
    if (knownTokenRatio >= 0.98) return '刚好适合你';
    if (knownTokenRatio >= 0.95) return '有点挑战';
    if (knownTokenRatio >= 0.90) return '需要带读';
    if (knownTokenRatio > 0) return '先攒点基础';
    return '';
  }

  /// 口音标注(有音频才有意义):来源 → 英美音
  static String accentOf(String sourceId) => switch (sourceId) {
        'bbc_le' => '英音',
        'voa_le' => '美音',
        'ted' => '美音',
        'npr' => '美音',
        _ => '',
      };

  /// 句数估算:按句末标点切(给卡片上的「N 句」用)
  static int sentenceCount(String text) {
    if (text.trim().isEmpty) return 0;
    final n = RegExp(r'[.!?。！？]+').allMatches(text).length;
    return n == 0 ? 1 : n;
  }

  /// 从材料种类推断内容源 id(口音标注用)
  static String sourceIdOfKind(String kind) => switch (kind) {
        'book' => 'gutenberg',
        'paper' => 'arxiv',
        'news' => 'npr',
        'podcast' => 'ted',
        _ => '',
      };

  /// 源 id → 口音
  static String accentOfSource(String sourceId) => accentOf(sourceId);

  /// 源健康数据里的 kind → 展示用素材种类(FeedItem 只有 link,没有 kind)
  static String kindOfSource(String sourceId) =>
      MaterialSourceService.sourceOf(sourceId)?.kind ?? 'article';
}
