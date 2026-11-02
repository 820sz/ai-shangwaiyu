import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 图形资产的**颜色 / 尺寸 / 语义字典**(v2.13 · 图形资产系统 · 批 1)。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 为什么要有这一层,而不是让每个 painter 自己从 Theme 里抓色:
///
/// 1. **painter 不能持有 BuildContext**。`CustomPainter.paint()` 里读 Theme 既拿
///    不到最近的 context(要额外传),也让 `shouldRepaint` 无从比较 —— 颜色必须
///    在 build 阶段**解析成纯 Color** 再交给 painter(见 graphics_core.dart 的
///    `GraphicPainter`)。这个文件就是"解析规则"的唯一事实源。
///
/// 2. **13 个领域需要 13 个身份色**。它们不属于 Material 的调色板角色,塞进
///    colorScheme 反而是误导。做法和 theme.dart 里的品牌色一致:浅色档写死一个
///    对白卡片 **≥4.9:1** 的深色(见各枚举注释),深色档统一用
///    `AppTheme.readableOn` 提亮到对卡片 **≥3:1**(WCAG 非文字元素标准)——
///    所以明暗两套都"看得清",而且不会出现"浅色值直接搬进深色"那种发闷。
///
/// 3. **视觉常量必须集中**。线宽 2.5~4.0、面板浓度 26/40、圆角档位如果散在
///    13 个 painter 里,一定会走样;放这里,改一次全 App 一致(验收要求
///    "克制、安静、几何化",统一笔触是它成立的前提)。
class GraphicsPalette {
  GraphicsPalette._();

  // ── 尺寸档 ───────────────────────────────────────────────────────────
  //
  // 只留 4 档而不是任意尺寸:同一图形在 72/96/120/160 上必须"看起来是同一个东西",
  // 档位越少,跨页面的观感越整齐(列表小图 / 卡片图标 / 空态 / 首屏 hero)。
  static const List<double> sizes = <double>[72, 96, 120, 160];

  /// 默认尺寸(空态 / 卡片主图形)
  static const double defaultSize = 120;

  /// 视觉线宽:**按尺寸等比**的 2.4~4.0。
  ///
  /// 固定 3px 的画法在 72 的小图上会粗到糊、在 160 的 hero 上又细到飘;
  /// 按 2.6% 比例缩放后,人眼在 4 个档位上看到的是"同一种笔"。
  static double strokeOf(double size) => (size * 0.026).clamp(2.4, 4.0);

  // ── 中性墨色 ─────────────────────────────────────────────────────────
  //
  // 结构线(坐标系、分栏、网格)用中性墨,语义色只留给"身份笔画" ——
  // 这样一张图里最多两种色相,才不会花(用户要"精简和高级",不是花花绿绿)。
  // 浅色 #2B313B 对白卡 13.1:1;深色 #DCE1E9 对深卡 13.3:1。
  static const Color lightInk = Color(0xFF2B313B);
  static const Color darkInk = Color(0xFFDCE1E9);

  /// 弱化线(细节笔画、纹理)。浅色 #7A828F 对白卡 3.9:1、深色 #8E99A8 对深卡 6:1,
  /// 都过了"非文字元素 3:1"这条线,但又明显比主墨线轻一档。
  static const Color lightFaint = Color(0xFF7A828F);
  static const Color darkFaint = Color(0xFF8E99A8);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// 主墨线(结构)
  static Color line(BuildContext context) =>
      isDark(context) ? darkInk : lightInk;

  /// 弱化线(细节)
  static Color faint(BuildContext context) =>
      isDark(context) ? darkFaint : lightFaint;

  // ── 面板(可选背景)────────────────────────────────────────────────
  //
  // 为什么不用 surfaceContainerHighest:那是"卡片里的卡片"色,和页面底几乎同色,
  // 图形放上去仍然是一张"贴在白纸上的线稿"。这里给**语义色的极淡薄涂**:
  // 浅色 26/255、深色 40/255(深底上要更浓才有体积感),一眼能看出"这是一个图形位",
  // 又不至于变成彩色色块。
  static Color panel(BuildContext context, Color accent) =>
      accent.withAlpha(isDark(context) ? 40 : 26);

  /// 双层渐变面板:左上浓、右下几乎透明 —— 比纯色多一层空间感,但不到"艳"的程度
  static LinearGradient panelGradient(BuildContext context, Color accent) {
    final dark = isDark(context);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        accent.withAlpha(dark ? 40 : 26),
        accent.withAlpha(dark ? 12 : 6),
      ],
    );
  }

  /// 按明暗解析一个"身份色":浅色原样,深色提亮到对卡片 ≥3:1。
  ///
  /// 直接复用 [AppTheme.readableOn](只提亮度、不动色相),保证深色下的身份色
  /// 既是同一个色系、又不会糊进深底。
  static Color accentOf(BuildContext context, Color base) =>
      isDark(context) ? AppTheme.readableOn(context, base) : base;

  /// 面板装饰(给 [GraphicFrame] 用):渐变 + 统一圆角
  static BoxDecoration panelDecoration(
    BuildContext context,
    Color accent,
    double radius,
  ) {
    return BoxDecoration(
      gradient: panelGradient(context, accent),
      borderRadius: BorderRadius.circular(radius),
    );
  }
}

/// 13 个**内容领域**(资料分类 / 学习方向 / 推荐卡片的身份图形)。
///
/// 为什么用 enum 而不是 String:图形、颜色、中文标签必须是**同一个事实源** ——
/// 以前界面里散落的 `Icons.category` + 手写中文,改一处漏三处。以后调用方只传
/// `GraphicDomain` / `GraphicDomain.fromId(kind)`,三样东西一起对齐。
///
/// 颜色值都过了 WCAG:浅色档对白卡片 ≥4.95:1(脚本实测 4.95~7.92),
/// 深色档由 `colorOf` 经 `readableOn` 提亮到对 #171A20 卡片 ≥3:1。
enum GraphicDomain {
  science('科学与技术', Color(0xFF2F6FB5)),
  business('商业与政治', Color(0xFF7E5A2A)),
  health('健康与生活', Color(0xFF2E7D5B)),
  culture('文化与艺术', Color(0xFF8A4A63)),
  travel('旅行与体验', Color(0xFF2C7A88)),
  language('语言与学习', Color(0xFF4A5FA8)),
  exam('备考冲刺', Color(0xFFA6512B)),
  academic('学术论文', Color(0xFF5B4A82)),
  news('外刊新闻', Color(0xFF3B5A73)),
  book('公版书', Color(0xFF6B4A32)),
  audio('听力播客', Color(0xFFB2453F)),
  note('笔记碎片', Color(0xFF6E5A3E)),
  custom('其他', Color(0xFF47535F));

  const GraphicDomain(this.label, this.baseColor);

  /// 中文标签(界面上显示的分类名 / 无障碍标签)
  final String label;

  /// 浅色档身份色(深色请走 [colorOf],不要直接用它画线)
  final Color baseColor;

  /// 当前主题下的身份色(明暗自适应)
  Color colorOf(BuildContext context) =>
      GraphicsPalette.accentOf(context, baseColor);

  /// 脏数据 / 未知 id 一律回退到 [custom](宁可中性,不能让图形颜色崩掉)
  static GraphicDomain fromId(String? id) {
    return switch ((id ?? '').trim().toLowerCase()) {
      'science' || 'tech' || 'technology' || 'sci' => science,
      'business' || 'politics' || 'finance' || 'economy' => business,
      'health' || 'life' || 'wellness' || 'lifestyle' => health,
      'culture' || 'art' || 'arts' || 'humanities' => culture,
      'travel' || 'experience' || 'trip' => travel,
      'language' || 'lang' || 'learn' || 'learning' || 'english' => language,
      'exam' || 'test' || 'ielts' || 'toefl' || 'cet' => exam,
      'academic' || 'paper' || 'papers' || 'research' => academic,
      'news' || 'magazine' || 'press' || 'journalism' => news,
      'book' || 'books' || 'literature' || 'novel' => book,
      'audio' || 'podcast' || 'listening' || 'radio' => audio,
      'note' || 'notes' || 'memo' || 'fragment' => note,
      _ => custom,
    };
  }
}

/// 7 种**材料类型**的封面身份(`MaterialCoverArt` 用)。
///
/// [face] / [shade] 是封面渐变的两笔,**都是深色**:调用方会在上面叠白色标题,
/// 所以白字对比度必须够 —— 实测亮面 5.52~9.63:1、暗面 9.52~14.82:1
/// (test/graphics_preview_test.dart 有闸门)。
///
/// 为什么不能和 [GraphicDomain] 合并:领域是"内容讲什么",材料类型是"这份东西
/// 长什么样"(文章/书/论文/外刊…),两者的拆分粒度本来就不同 —— 一篇 science
/// 领域的文章仍是 article 类型。
enum MaterialKindArt {
  article('文章', Color(0xFF3E6B9E), Color(0xFF274866)),
  book('原版书', Color(0xFF574C7C), Color(0xFF332C4C)),
  paper('论文', Color(0xFF2F6570), Color(0xFF1E4650)),
  news('外刊', Color(0xFF2A4763), Color(0xFF17293B)),
  exam('考题', Color(0xFF7A5A22), Color(0xFF4E3A16)),
  audio('听力', Color(0xFF8A4B44), Color(0xFF5A302C)),
  note('笔记', Color(0xFF4A5A66), Color(0xFF2E3A44));

  const MaterialKindArt(this.label, this.face, this.shade);

  /// 类型中文名(封面角标 / 无障碍标签)
  final String label;

  /// 渐变亮面(左上)
  final Color face;

  /// 渐变暗面(右下)
  final Color shade;

  /// 项目里的材料 kind 字符串 → 类型身份
  ///
  /// 映射依据是 `material_cover.dart` 的 `coverKindIcon`:wiki(百科)归到 article,
  /// podcast 归到 audio —— 宁可落到同一个身份,也不要显示成"未知"。
  static MaterialKindArt fromId(String? id) {
    return switch ((id ?? '').trim().toLowerCase()) {
      'book' || 'gutenberg' || 'novel' => book,
      'paper' || 'arxiv' || 'research' => paper,
      'news' || 'rss' || 'magazine' => news,
      'exam' || 'test' || 'quiz' => exam,
      'podcast' || 'audio' || 'ted' || 'listening' => audio,
      'note' || 'notes' || 'memo' => note,
      _ => article,
    };
  }
}

/// 5 种**空态**图形(替换界面里那句"什么都没有"的 Material 图标)。
///
/// 空态是全 App 最容易显得"简陋"的地方:一块灰字 + 一个通用 inbox 图标。
/// 这里给每种"为什么空"配一个几何化的说法(书页 / 纸飞机 / 字母 / 放大镜 / 波纹)。
enum EmptyArtKind {
  floatingPages('漂浮书页'),
  paperPlane('纸飞机'),
  scatteredLetters('散落字母'),
  magnifier('放大镜'),
  generic('波纹');

  const EmptyArtKind(this.label);

  /// 图形名(无障碍标签用,不是界面文案)
  final String label;

  /// 从旧空态组件的 `icon` 参数反推该用哪种空态插图(批 1 · B1-4 的兼容层)。
  ///
  /// ## 为什么按语义归并,而不是"一个图标配一张图"
  /// 1. **图形资产只有 5 种,而全 App 空态调用点几十处、用的 Material 图标
  ///    五花八门。** 一个图标配一张图做不到;硬配也会让"同一种空"在不同页面
  ///    长得不一样 —— 用户看到的应该是"同一种状态用同一种说法"。
  /// 2. **空态要回答的是"为什么空",不是"用了哪个控件"。** 没有搜索结果 /
  ///    还没有内容 / 还没连上,在图形上分别对应放大镜 / 书页 / 纸飞机;至于
  ///    调用方当初传的是 `search_off` 还是 `travel_explore`,对用户没有区别。
  /// 3. **归并只决定"默认值"。** 调用方随时可以用组件的 `art:` 精确指定 ——
  ///    语义映射只影响"没显式指定时"的观感,不会锁死表达。
  ///
  /// ## 归并规则(图标 → 图形)
  /// - 搜索/查找类 → [magnifier]:空的原因是"没搜到";
  /// - 内容/收藏/列表/历史类 → [floatingPages]:"还没有内容",书页最能表达
  ///   "这里将来会有东西";
  /// - 网络/故障/刷新类 → [paperPlane]:空的原因是"还没连上/还没开始",
  ///   纸飞机是"起步"的符号(不是"失败"符号 —— 空态不该加重挫败感);
  /// - 语言/文字类 → [scatteredLetters]:词库为空、翻译/语言相关;
  /// - 其余 → [generic]:不猜语义,用"安静的水面"兜底。
  ///
  /// ## 为什么用常量模式匹配而不是比较 codePoint
  /// [IconData] 的相等性本来就是 `codePoint + fontFamily + fontPackage`,
  /// 直接 `switch` 常量模式与 `==` 同语义、可读性最好;手写 codePoint 数字
  /// 反而会在 Material 图标更新时静默失配。
  static EmptyArtKind fromIcon(IconData? icon) {
    return switch (icon) {
      // ── 搜索/查找:空 = "没搜到" ──
      Icons.search ||
      Icons.search_off ||
      Icons.search_rounded ||
      Icons.zoom_in ||
      Icons.zoom_out ||
      Icons.find_in_page ||
      Icons.find_in_page_outlined ||
      Icons.manage_search ||
      Icons.travel_explore ||
      Icons.travel_explore_outlined ||
      Icons.person_search =>
        EmptyArtKind.magnifier,
      // ── 内容/收藏/列表/历史:空 = "还没有内容" ──
      Icons.inbox ||
      Icons.inbox_outlined ||
      Icons.article ||
      Icons.article_outlined ||
      Icons.library_books ||
      Icons.library_books_outlined ||
      Icons.menu_book ||
      Icons.menu_book_outlined ||
      Icons.auto_stories ||
      Icons.auto_stories_outlined ||
      Icons.book ||
      Icons.book_outlined ||
      Icons.collections_bookmark ||
      Icons.collections_bookmark_outlined ||
      Icons.folder ||
      Icons.folder_outlined ||
      Icons.folder_open ||
      Icons.list ||
      Icons.list_alt ||
      Icons.history ||
      Icons.history_edu_outlined ||
      Icons.notes ||
      Icons.note_alt_outlined ||
      Icons.bookmark ||
      Icons.bookmark_border ||
      Icons.star_border ||
      Icons.star_outline ||
      Icons.assignment_outlined =>
        EmptyArtKind.floatingPages,
      // ── 网络/故障/刷新:空 = "还没连上 / 还没开始" ──
      Icons.cloud_off ||
      Icons.wifi_off ||
      Icons.error ||
      Icons.error_outline ||
      Icons.refresh ||
      Icons.sync_problem ||
      Icons.signal_wifi_connected_no_internet_4 ||
      Icons.hourglass_empty ||
      Icons.update =>
        EmptyArtKind.paperPlane,
      // ── 语言/文字:词库为空、翻译/语言相关 ──
      Icons.translate ||
      Icons.abc ||
      Icons.spellcheck ||
      Icons.text_fields ||
      Icons.text_snippet ||
      Icons.text_snippet_outlined ||
      Icons.language =>
        EmptyArtKind.scatteredLetters,
      // ── 其余:不猜语义,安静兜底 ──
      _ => EmptyArtKind.generic,
    };
  }
}

/// **输出四阶**(单词 → 句子 → 段落 → 作文)。
///
/// "输出"是产品里一条独立的成长线:写译作业按这四阶递进。图形上用"越来越大的
/// 排版体量"来表达,而不是四个不同图标 —— 用户一眼看到的应该是"段位在涨"。
enum OutputTierArt {
  word('单词'),
  sentence('句子'),
  paragraph('段落'),
  essay('作文');

  const OutputTierArt(this.label);

  final String label;
}
