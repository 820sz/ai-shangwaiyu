import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../services/material_library.dart';
import '../services/material_source.dart';

/// 材料封面(v2.8,用户第 6(2) 条:"整个软件全是字唉"、"别人都有文章图片")。
///
/// ## 为什么先做**程序化封面**而不是网图
/// 调研结论(见 `docs/SPEC-material-discovery-2026-10-01.md`):
/// - 参考软件(扇贝阅读)那张水彩插画是**自有版权图库**的产物,公开图源给不了那个质感;
/// - 本机实测:Wikipedia/Openverse/Gutendex/Open Library/Internet Archive **全部不可达**
///   (`en.wikipedia.org`/`gutendex.com`/`api.openverse.org` 解析到 Facebook/Cloudflare 段,
///   典型 DNS 污染),`upload.wikimedia.org` 连图片都拿不到;
///   可达的只有 Gutenberg 封面、Bing 每日图(不可商用)、Unsplash/Pexels 直链。
/// - 所以:**零网络、零版权**的程序化封面是首版唯一稳的选择 ——
///   同一篇材料永远得到同一张封面(按标题 hash 取色,不用随机数,列表滚动不会闪)。
///
/// 之后要换成真图,只需要在调用点把 [imageUrl] 传进来(优先级:真图 > 程序化封面)。
class MaterialCover extends StatelessWidget {
  /// 取材种子:用标题(稳定即可)。同一标题永远同一张封面。
  final String seed;

  /// 材料种类(book/news/paper/podcast/wiki/article)—— 决定角标图标
  final String kind;

  /// 可选真实配图(Gutenberg 封面 / RSS og:image)。为空则用程序化封面。
  final String? imageUrl;

  final double width;
  final double height;

  /// 圆角(默认卡片圆角 16);传 0 表示由父级裁剪
  final double radius;

  /// 右下角等级徽标(如 'Lv8');为空不显示
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

  /// 固定配色盘(挑的都是低饱和、深浅色下都不刺眼的一组)
  static const List<List<Color>> _palette = [
    [Color(0xFF2F4A6D), Color(0xFF5B7FA6)], // 靛蓝
    [Color(0xFF3F5A47), Color(0xFF6E8F72)], // 苔绿
    [Color(0xFF6A4A3C), Color(0xFFA6785E)], // 陶土
    [Color(0xFF4A3F63), Color(0xFF7E6FA3)], // 紫藤
    [Color(0xFF2E5560), Color(0xFF5B8C96)], // 青灰
    [Color(0xFF6B4A55), Color(0xFFA3768A)], // 玫瑰
    [Color(0xFF54452F), Color(0xFF8C7550)], // 赭石
    [Color(0xFF37474F), Color(0xFF6B8A96)], // 石墨
  ];

  /// 按种子取配色(纯函数,可单测):同一标题稳定得到同一组颜色
  static List<Color> paletteFor(String seed) {
    if (seed.trim().isEmpty) return _palette.first;
    var h = 0;
    for (final r in seed.runes) {
      h = (h * 31 + r) % 1000003; // 任意大质数,够散且可复现(不用 hashCode:
      // 它在不同 run 里可能不同,列表滚动会"换色")
    }
    return _palette[h % _palette.length];
  }

  /// 取标题里最有信息量的几个首字母(最多 3 个)当作封面上的"字"
  static String monogramOf(String title) {
    final words = title
        .replaceAll(RegExp(r'[^\w\s\u4e00-\u9fff]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .where((w) => !_stopWords.contains(w.toLowerCase()))
        .toList();
    if (words.isEmpty) return '·';
    final take = math.min(3, words.length);
    return words
        .take(take)
        .map((w) => w.runes.first)
        .map(String.fromCharCode)
        .join()
        .toUpperCase();
  }

  static const Set<String> _stopWords = {
    'the', 'a', 'an', 'of', 'on', 'in', 'to', 'and', 'or', 'for', 'with', 'at',
    'by', 'from', 'is', 'are', 'as',
  };

  static IconData iconOf(String kind) => switch (kind) {
        'book' => Icons.menu_book,
        'news' => Icons.newspaper,
        'paper' => Icons.science_outlined,
        'podcast' => Icons.podcasts,
        'wiki' => Icons.public,
        _ => Icons.article_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final colors = paletteFor(seed);
    final hasNet = (imageUrl ?? '').trim().isNotEmpty;
    final mono = monogramOf(seed);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: hasNet
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    // 图片加载失败/慢都不该让卡片空着:底下永远垫着程序化封面
                    errorBuilder: (_, _, _) => _procedural(colors, mono),
                    loadingBuilder: (ctx, child, progress) =>
                        progress == null ? child : _procedural(colors, mono),
                  ),
                  // 底部压一层渐变,保证角标文字在任何图上都读得清
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withAlpha(90),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  Positioned(right: 8, bottom: 6, child: _kindChip(context)),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  _procedural(colors, mono),
                  Positioned(right: 8, bottom: 6, child: _kindChip(context)),
                ],
              ),
      ),
    );
  }

  /// 程序化封面本体:斜向渐变 + 大字首字母 + 角标
  Widget _procedural(List<Color> colors, String mono) {
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
        // 右上角一枚很淡的大圆,给纯色块一点层次(避免整块死板)
        Positioned(
          right: -28,
          top: -28,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withAlpha(18),
            ),
          ),
        ),
        Center(
          child: Text(
            mono,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: Colors.white.withAlpha(235),
              letterSpacing: 2,
            ),
          ),
        ),
        // 底部深色渐变 + 等级徽标
        if ((levelLabel ?? '').isNotEmpty)
          Positioned(
            left: 8,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(120),
                borderRadius: BorderRadius.circular(Radii.control - 4),
              ),
              child: Text(
                levelLabel!,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _kindChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(110),
        borderRadius: BorderRadius.circular(Radii.control - 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconOf(kind), size: 12, color: Colors.white.withAlpha(230)),
          const SizedBox(width: 4),
          Text(
            MaterialLibrary.kindLabel(kind),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white.withAlpha(235),
            ),
          ),
        ],
      ),
    );
  }
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
