import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../config/v4_theme.dart';
import '../services/bookshelf.dart';
import 'material_cover.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 封面口径:「有真图才画图,没图就写字」—— 不再画渐变假封面
// ═══════════════════════════════════════════════════════════════════════════
//
// 用户 2026-11-06 真机反馈:书架 3D 里那本「原版书」渐变封面是**假封面** ——
// 数据里根本没有图,程序却画了一张"看起来像书封的色块",用户会以为"封面没加载
// 出来",而不是"这本书没有封面"。
//
// 所以这里把封面收成两条分支(纯函数 + 两个组件),书架两形态 / 频道页卡片共用:
// 1. 数据里有 http(s) 封面地址 → 显示真图(加载中/失败回落文字版式);
// 2. 没有 → [TextCover] **文字版式**:种类 + 标题 + 中文/英文副标题 + 难度,
//    信息密度和真封面一样,但不假装自己是一张图。
//
// 为什么组件放在本文件(而不是 design_kit):本轮修复的写作用域只包含
// `shelf_cover_grid.dart` / `shelf_carousel_view.dart`;3D 书架直接 import 本文件
// 复用,避免同一套文字封面写两遍。后续可平移到 `widgets/material_cover.dart`。

/// 封面地址能不能显示真图。
///
/// 只认 http(s)(与 [coverHasImage] 同一口径):空串、`file://`、相对路径、
/// 脏值一律当"没有封面图",直接走 [TextCover]。
bool shelfCoverHasImage(String? url) => coverHasImage(url);

/// **文字版式封面**(没有真实封面图时使用)。
///
/// 设计约束(为什么长这样):
/// - 底色用 [V4Skin.surface] 白卡 + 细边,和全 App 的果冻卡片同一套材质,
///   不再用彩色渐变(渐变正是"假封面"的观感来源);
/// - 左侧一条 5px 强调色"书脊"竖条:让文字块看起来像设计过的书封,而不是
///   "图片没加载出来"的空白块;
/// - 顶部种类小字(教材/原版书/外刊…)+ 中间标题 + 底部难度胶囊:一眼看出
///   "这是什么、叫什么、多难",对应卡片列表里用户决策要的三条信息。
class TextCover extends StatelessWidget {
  /// 展示标题(书架数据里已经是"中文优先"的展示标题)
  final String title;

  /// 副标题(英文原名/中文名,有才显示)
  final String? subtitle;

  /// 材料种类 book/news/paper/textbook/exam…
  final String kind;

  /// 难度(CEFR A1~C2 或 Lv1~Lv10),为空不显示
  final String? levelLabel;

  /// 来源(如 Gutenberg / NPR),为空不显示
  final String? sourceLabel;

  final double width;
  final double height;
  final double radius;

  const TextCover({
    super.key,
    required this.title,
    this.subtitle,
    this.kind = 'article',
    this.levelLabel,
    this.sourceLabel,
    required this.width,
    required this.height,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final level = (levelLabel ?? '').trim();
    final source = (sourceLabel ?? '').trim();
    final sub = (subtitle ?? '').trim();

    // 尺寸全部按高度线性派生:同一组件在书架网格(≈160×213)和 3D 抽出封面
    // (132×168)上都要成立,写死字号会在小尺寸上挤成一团。
    final pad = (height * 0.055).clamp(8.0, 14.0);
    final titleSize = (height * 0.088).clamp(12.0, 19.0);
    final subSize = (titleSize * 0.62).clamp(9.5, 11.5);
    // 168 高的 3D 抽出封面也按"紧凑"处理:4 行标题 + 副标题 + 难度胶囊
    // 在 168 里会溢出(实测差 5~8px),3 行刚好装得下。
    final compact = height < 180;

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: skin.hairline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: <Widget>[
              // 「书脊」:一条强调色竖条,让文字封面有"被设计过"的重量
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        skin.accent.withValues(alpha: 0.90),
                        skin.accent.withValues(alpha: 0.42),
                      ],
                    ),
                  ),
                ),
              ),
              // 幽灵字标:把"书名里最有信息量的那个词"用极淡的大号字压在右下角,
              // 作用有两个 —— ① 长封面上填补中部/底部的留白(用户要求"不空旷");
              // ② 远看能认出是哪本,近看是排版元素,而不是一张假的渐变封面。
              Positioned(
                left: pad + 6,
                right: 2,
                bottom: pad + 16,
                child: IgnorePointer(
                  child: Text(
                    coverMonogram(title, small: true),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: height * 0.17,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: skin.accent.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad + 6, pad, pad, pad),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          coverKindIcon(kind),
                          size: 13,
                          color: skin.inkFaint,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            coverKindLabel(kind),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFont.tagStyle.copyWith(
                              color: skin.inkFaint,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 标题块**垂直居中**:书封的经典排法是"种类在上、书名居中、
                    // 难度在下";顶部对齐会在长封面上留出一大块空白(渲染图里很明显)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title.trim().isEmpty ? '未命名材料' : title.trim(),
                              maxLines: compact ? 3 : 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: titleSize,
                                height: 1.26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                color: skin.ink,
                              ),
                            ),
                            if (sub.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 5),
                              Text(
                                sub,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: subSize,
                                  height: 1.32,
                                  color: skin.inkSoft,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (level.isNotEmpty || source.isNotEmpty)
                      Row(
                        children: <Widget>[
                          if (level.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: skin.accent.withValues(alpha: 0.10),
                                borderRadius: Radii.pillRadius,
                              ),
                              child: Text(
                                level,
                                style: AppFont.tagStyle.copyWith(
                                  color: skin.accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          if (level.isNotEmpty && source.isNotEmpty)
                            const SizedBox(width: 6),
                          // 用 Expanded 而不是 Spacer:两者同时出现时 Spacer 会
                          // 吃光剩余宽度,来源文字会被挤成 0 宽(真机上看不见)
                          if (source.isNotEmpty)
                            Expanded(
                              child: Text(
                                source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: AppFont.tagStyle.copyWith(
                                  color: skin.inkFaint,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 封面区(书架两形态共用):**有真图显示真图,没图显示文字版式**。
///
/// 真图加载中/失败也回落到文字版式 —— 所以永远不会出现"白块"或"假封面"。
class CoverOrText extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String kind;
  final String? coverUrl;
  final String? levelLabel;
  final String? sourceLabel;
  final double width;
  final double height;
  final double radius;

  const CoverOrText({
    super.key,
    required this.title,
    this.subtitle,
    this.kind = 'article',
    this.coverUrl,
    this.levelLabel,
    this.sourceLabel,
    required this.width,
    required this.height,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = TextCover(
      title: title,
      subtitle: subtitle,
      kind: kind,
      levelLabel: levelLabel,
      sourceLabel: sourceLabel,
      width: width,
      height: height,
      radius: radius,
    );
    final url = (coverUrl ?? '').trim();
    if (!shelfCoverHasImage(url)) return fallback;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          url,
          width: width,
          height: height,
          fit: BoxFit.cover,
          // 首帧还没到:先显示文字版式,避免闪一块空白
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
              (wasSynchronouslyLoaded || frame != null) ? child : fallback,
          // 图挂了(图床被墙/防盗链/404):回落文字版式,不画假封面
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 书架形态 A · 详细书架(封面优先)
// ═══════════════════════════════════════════════════════════════════════════

/// 书架形态 A · **详细书架**(封面优先,2026-11-04 用户拍板双形态之一)。
///
/// 之前 v2.13~v4 的书架只有一种"平面搁板"形态;用户要求两种可切换:
/// - 详细书架(本文件):封面网格,标题/进度一目了然,适合"找书继续读";
/// - 3D 轮播书架(`shelf_carousel_view.dart`):书脊朝外、可左右滑,适合"把玩/扫标题"。
///
/// 本组件只负责画;点击/长按行为由 [BookshelfScreen] 注入(与旧书架完全一致)。
class ShelfCoverGrid extends StatelessWidget {
  final List<BookshelfBook> books;
  final ValueChanged<BookshelfBook>? onTapBook;
  final ValueChanged<BookshelfBook>? onLongPressBook;

  /// 保留的参数:旧版用来关掉"自动抓图"(避免测试环境网络 timer)。
  /// 新版封面不再联网抓图(抓不到就画文字版式),所以这个开关已无实际作用,
  /// 只为不破坏既有调用点(bookshelf_screen / 渲染测试)而保留。
  final bool enableCoverFetch;

  const ShelfCoverGrid({
    super.key,
    required this.books,
    this.onTapBook,
    this.onLongPressBook,
    this.enableCoverFetch = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 560 ? 4 : (width >= 380 ? 2 : 2);
        final spacing = Gap.sm;
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        // 封面 3:4 + 两行文字 ≈ 1:1.62
        final itemHeight = itemWidth * 4 / 3 + 62;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: Gap.md,
            crossAxisSpacing: spacing,
            mainAxisExtent: itemHeight,
          ),
          itemCount: books.length,
          itemBuilder: (context, i) {
            final b = books[i];
            return _ShelfCoverCard(
              book: b,
              onTap: () => onTapBook?.call(b),
              onLongPress: () => onLongPressBook?.call(b),
            );
          },
        );
      },
    );
  }
}

class _ShelfCoverCard extends StatelessWidget {
  final BookshelfBook book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ShelfCoverCard({
    required this.book,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final level = book.cefr.isNotEmpty ? book.cefr : null;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(builder: (ctx, c) {
              return Stack(
                children: <Widget>[
                  Positioned.fill(
                    // 有封面图 → 真图;没有 → 文字版式(不再画渐变假封面)
                    child: CoverOrText(
                      title: book.title,
                      subtitle: book.subtitle,
                      kind: book.kind,
                      coverUrl: book.coverUrl,
                      levelLabel: level,
                      width: c.maxWidth,
                      height: c.maxHeight,
                      radius: 16,
                    ),
                  ),
                  // 底部进度:详细书架也要能一眼看出读到哪
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(16),
                      ),
                      child: LinearProgressIndicator(
                        value: (book.percent / 100).clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: skin.surface.withValues(alpha: 0.55),
                        color: book.finished
                            ? const Color(0xFF2F8A5B)
                            : skin.accent,
                      ),
                    ),
                  ),
                  if (book.finished)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F8A5B),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '已读完',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.28,
              fontWeight: FontWeight.w700,
              color: skin.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            book.finished
                ? '已读完'
                : (book.percent > 0
                    ? '已读 ${book.percent.round()}%'
                    : '未开始'),
            maxLines: 1,
            style: TextStyle(fontSize: 10.5, color: skin.inkSoft),
          ),
        ],
      ),
    );
  }
}
