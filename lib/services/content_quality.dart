/// 发现流水线的「这段抓取结果是不是一篇可读正文」判定（2026-11-06 用户真机反馈）。
///
/// 问题：找「四六级真题」时，部分结果点进去**只有图书介绍/购买页**的文字。
/// 根因：旧流水线只校验「正文 ≥ 200 字」—— 书店商品详情页、课程售卖页、
/// 站点导航页都轻松超过 200 字，于是被当成"抓到正文"入库。
///
/// 这里把门槛从"长度"升级成四道闸（都是可解释的纯函数，可单测）：
/// 1. 长度：低于 [defaultMinLength] 直接不算正文；
/// 2. 购买意图：出现「加入购物车 / 立即购买 / 去购买 / 立即报名」这类按钮文案
///    → 一定是商品/课程售卖页，不是正文；
/// 3. 商品/介绍页信号：内容简介、商品详情、ISBN、定价、出版社、店铺、包邮…
///    加权计分，够分就判为介绍页；
/// 4. 正文形态：英文正文比例过低（中文站点导航/介绍）或短行占比过高
///    （导航/列表页）也不算可读正文。
///
/// 另外提供 [firstImageFromMarkdown]：官方 Fetch 返回的是 markdown，正文里
/// 常带 `![图](url)` / `<img src>`，用它给结果卡补真实封面（拿不到就不补，
/// 由 UI 退化成"标题文字版式"，绝不画假封面）。
class ContentQuality {
  ContentQuality._();

  /// 正文最小长度（与流水线原先的门槛保持一致，避免改变既有行为）。
  static const int defaultMinLength = 200;

  /// 购买/行动按钮文案：命中任一 → 直接判定为售卖页（不看分数）。
  static const List<String> _buyIntent = <String>[
    '加入购物车',
    '立即购买',
    '去购买',
    '立即抢购',
    '购买数量',
    '购买课程',
    '立即报名',
    '点击购买',
    '领取优惠',
    '限时特惠',
    '扫码关注',
    '添加客服',
    '进入店铺',
    '店铺首页',
    '收藏宝贝',
    'add to cart',
    'buy now',
    'add to bag',
    'proceed to checkout',
  ];

  /// 商品/图书详情页的版块标题：命中 +2 分。
  static const List<String> _listingHeaders = <String>[
    '内容简介',
    '商品详情',
    '商品介绍',
    '图书详情',
    '课程介绍',
    '课程大纲',
    '作者简介',
    '目录',
    'product details',
    'book description',
    'about the author',
  ];

  /// 电商/书店平台的弱信号：命中 +1 分（书评文章里提到"出版社/定价"不该误杀）。
  static const List<String> _listingWeak = <String>[
    '定价',
    '售价',
    '折扣',
    '满减',
    '包邮',
    '促销',
    '秒杀',
    'isbn',
    '出版社',
    '出版时间',
    '开本',
    '页数',
    '装帧',
    '版次',
    '印次',
    '销量',
    '好评',
    '库存',
    '配送',
    '客服',
    '当当',
    '京东',
    '天猫',
    '淘宝',
    '拼多多',
    '苏宁',
    '孔夫子',
    '新华书店',
    '专营店',
    '旗舰店',
    'in stock',
    'out of stock',
    'customer reviews',
    'free shipping',
  ];

  static final RegExp _pricePattern = RegExp(r'[¥￥]\s*\d|\$\s*\d+[.,]\d{2}');

  /// 封面图排除词：站点 logo/图标/头像/埋点像素不算正文配图。
  static const List<String> _imageNoise = <String>[
    'logo',
    'icon',
    'avatar',
    'sprite',
    'pixel',
    '1x1',
    'badge',
    'tracking',
    'spacer',
    'blank.gif',
    'emoji',
  ];

  /// 这段抓取结果能不能当阅读正文；能用返回 `null`，不能用返回**给用户看的原因**。
  static String? rejectReason(String raw, {int minLength = defaultMinLength}) {
    final text = raw.trim();
    if (text.length < minLength) return '抓到的正文太短';
    if (looksLikeBookOrProductPage(text)) {
      return '抓到的是图书/课程介绍或售卖页,不是正文';
    }
    // 第三轮（用户真机：搜出越南语文章）：拉丁字母但非英语的正文不能当阅读材料。
    // 中文页面的拦截仍交给下面的 latinLetterRatio（教材/真题的中文站旧口径不变）。
    if (looksLatinNonEnglish(text)) {
      return '抓到的不是英文正文(疑似越南语/印尼语等)';
    }
    if (latinLetterRatio(text) < 0.08) {
      return '抓到的是中文站点页面,不是英文正文';
    }
    if (looksLikeNavListing(text)) {
      return '抓到的是站点导航/列表页,不是正文';
    }
    return null;
  }

  /// 是否像图书/课程的商品详情、售卖或站点导航页（加权计分）。
  static bool looksLikeBookOrProductPage(String raw) {
    final text = raw.toLowerCase();
    for (final signal in _buyIntent) {
      if (text.contains(signal)) return true;
    }
    var score = 0;
    for (final signal in _listingHeaders) {
      if (text.contains(signal.toLowerCase())) score += 2;
    }
    for (final signal in _listingWeak) {
      if (text.contains(signal.toLowerCase())) score += 1;
    }
    if (_pricePattern.hasMatch(text)) score += 1;
    return score >= 5;
  }

  /// 英文字母占非空白字符的比例（英文正文 ≈ 0.6~0.8；中文站点 < 0.05）。
  static double latinLetterRatio(String raw) {
    var letters = 0;
    var total = 0;
    for (final rune in raw.runes) {
      if (rune == 0x20 || rune == 0x0a || rune == 0x0d || rune == 0x09) {
        continue;
      }
      total++;
      final isLatin =
          (rune >= 0x41 && rune <= 0x5a) || (rune >= 0x61 && rune <= 0x7a);
      if (isLatin) letters++;
    }
    if (total == 0) return 0;
    return letters / total;
  }

  /// 是否像站点导航/列表页：行数足够多、且大多数是极短行。
  static bool looksLikeNavListing(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length < 15) return false;
    final short = lines.where((line) => line.length <= 12).length;
    return short / lines.length >= 0.65;
  }

  /// 从官方 Fetch 返回的 markdown 里取第一张可能的**正文配图**。
  ///
  /// 只做"有没有一张像样的图"判断，不做图片内容理解；取不到返回 null
  /// （UI 据此走"无封面 → 标题文字版式"，而不是画渐变假封面）。
  static String? firstImageFromMarkdown(String markdown, {String? baseUrl}) {
    if (markdown.trim().isEmpty) return null;
    final candidates = <String>[];
    for (final match in RegExp(
      r'!\[[^\]]*\]\(\s*([^)\s]+)',
    ).allMatches(markdown)) {
      candidates.add(match.group(1) ?? '');
    }
    for (final match in RegExp(
      r'''<img[^>]+src\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(markdown)) {
      candidates.add(match.group(1) ?? '');
    }
    for (final raw in candidates) {
      final url = raw.trim();
      if (url.isEmpty || url.startsWith('data:')) continue;
      final lower = url.toLowerCase();
      if (_imageNoise.any(lower.contains)) continue;
      final absolute = absoluteHttpUrl(url, baseUrl: baseUrl);
      if (absolute == null) continue;
      return absolute;
    }
    return null;
  }

  /// 相对路径 → 绝对 http(s) 地址；转不出来返回 null。
  static String? absoluteHttpUrl(String raw, {String? baseUrl}) {
    final url = raw.trim();
    if (url.isEmpty) return null;
    final direct = Uri.tryParse(url);
    if (direct != null && direct.hasScheme) {
      return (direct.scheme == 'http' || direct.scheme == 'https')
          ? direct.toString()
          : null;
    }
    if (baseUrl == null || baseUrl.trim().isEmpty) return null;
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null || !base.hasScheme) return null;
    try {
      return base.resolve(url).toString();
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 第三轮（2026-11-07 用户真机反馈）：候选级三层过滤
  // ═══════════════════════════════════════════════════════════════════
  //
  // 真机问题：搜「四六级真题」时结果里混进 ①越南语文章 ②「考试报名网 / 考试简介」
  // ③与分类完全无关的条目。正文级闸门（rejectReason）要抓完正文才生效，
  // 这些候选会先占掉抓取名额与官方搜索的钱；所以在**候选阶段**补一层同样
  // 可解释的过滤（纯函数，全部可单测）。

  /// 英语功能词（高频）。长文本语言判定用：英语正文通常占 10%~50%，
  /// 越南语/印尼语等拉丁语系几乎不命中。
  static const Set<String> _englishStopwords = <String>{
    'the', 'and', 'of', 'to', 'in', 'is', 'that', 'for', 'with', 'as', 'on',
    'are', 'was', 'were', 'be', 'been', 'by', 'this', 'these', 'those', 'it',
    'from', 'at', 'or', 'an', 'but', 'not', 'have', 'has', 'had', 'its',
    'their', 'they', 'we', 'you', 'he', 'she', 'which', 'who', 'will',
    'would', 'can', 'could', 'should', 'more', 'than', 'into', 'about',
    'also', 'when', 'what', 'how', 'all', 'one', 'two', 'said', 'there',
    'such', 'may', 'if', 'so', 'no', 'do', 'does', 'did', 'our', 'out',
    'up', 'any', 'some', 'most', 'other', 'new', 'only', 'just', 'over',
    'after', 'before', 'between', 'because', 'while', 'where', 'through',
    'during', 'without', 'against', 'per', 'via', 'used', 'using', 'use',
    'each', 'both', 'many', 'much', 'very', 'well', 'then', 'them', 'her',
    'his', 'my', 'me', 'us', 'am', 'here', 'now', 'still', 'even',
  };

  /// 越南语高频词（无重音写法也能命中）。
  static const Set<String> _vietnameseMarkers = <String>{
    'và', 'của', 'là', 'những', 'được', 'trong', 'với', 'cho', 'không',
    'người', 'cách', 'học', 'tiếng', 'các', 'một', 'khi', 'để', 'này',
    'từ', 'anh', 'viết', 'bài', 'hiệu', 'quả', 'cũng', 'như', 'nhiều',
  };

  /// 印尼语高频词。
  static const Set<String> _indonesianMarkers = <String>{
    'yang', 'dan', 'dengan', 'untuk', 'dari', 'adalah', 'ini', 'itu',
    'tidak', 'cara', 'belajar', 'bahasa', 'inggris', 'bisa', 'akan',
    'pada', 'juga', 'lebih', 'kamu', 'saya', 'atau', 'karena', 'sudah',
  };

  /// 公告/报名/考试信息页：强信号（单个命中即拒）。
  static const List<String> _announcementStrongSignals = <String>[
    '报名入口',
    '报名时间',
    '报名条件',
    '考试报名',
    '报名系统',
    '准考证',
    '成绩查询',
    '查分',
    '分数线',
    '考试大纲',
    '考试安排',
    '考试科目',
    '考试流程',
    '考试时间',
    '考试简介',
    '招生简章',
    '校园招聘',
    '课程大纲',
    '课程介绍',
    '课程安排',
    '成绩单',
  ];

  /// 公告/报名页：弱信号（累计 3 个才拒，避免正常文章里出现一个词就被误杀）。
  static const List<String> _announcementWeakSignals = <String>[
    '报名',
    '公告',
    '招生',
    '培训',
    '辅导班',
    '网校',
    '官网',
  ];

  /// 英文强信号。
  static const List<String> _announcementStrongSignalsEn = <String>[
    'registration',
    'sign up',
    'signup',
    'admission',
    'admissions',
    'enrollment',
    'official website',
    'exam schedule',
    'admission ticket',
    'exam guide',
    'exam dates',
    'tuition',
    'apply now',
    'application form',
    'how to apply',
  ];

  /// 英文弱信号（累计 3 个才拒）。
  static const List<String> _announcementWeakSignalsEn = <String>[
    'notice',
    'apply',
    'official',
    'schedule',
  ];

  /// URL 里的公告/报名信号（路径级）。
  static const List<String> _announcementUrlSignals = <String>[
    '/baoming',
    '/zhaosheng',
    '/signup',
    '/sign-up',
    '/registration',
    '/peixun',
    '/apply',
    '/kaoshi/',
    '/notice/',
    '/announcement',
    '/news/notice',
  ];

  /// 英文功能词占比（0~1）；没有拉丁词返回 0。
  static double englishStopwordRatio(String raw) {
    final words = RegExp(r'[a-z]+')
        .allMatches(raw.toLowerCase())
        .map((match) => match.group(0)!)
        .toList();
    if (words.isEmpty) return 0;
    var hits = 0;
    for (final word in words) {
      if (_englishStopwords.contains(word)) hits++;
    }
    return hits / words.length;
  }

  /// 是否「拉丁字母但内容不是英语」（越南语/印尼语等）。
  ///
  /// 判定顺序（保守优先，宁可漏判不误杀）：
  /// 1. 中文占一定比例 → 这是中文页面（教材/真题/教辅多在中文站），**不算**外语乱入；
  /// 2. 词数太少（标题短语）不下结论，交给正文级闸门；
  /// 3. 越南语/印尼语高频词命中 → 非英文；
  /// 4. 越南语密集重音字符 → 非英文；
  /// 5. 长文本（≥40 词）英文功能词占比过低 + 有外语特征 → 非英文。
  static bool looksLatinNonEnglish(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return false;
    var cjk = 0;
    var latin = 0;
    var diacritic = 0;
    for (final rune in text.runes) {
      if (rune >= 0x4e00 && rune <= 0x9fff) {
        cjk++;
        continue;
      }
      final isLatin =
          (rune >= 0x41 && rune <= 0x5a) || (rune >= 0x61 && rune <= 0x7a);
      if (isLatin) latin++;
      if ((rune >= 0x00c0 && rune <= 0x024f) ||
          (rune >= 0x1e00 && rune <= 0x1eff)) {
        diacritic++;
      }
    }
    // 中文页面：不当"外语乱入"拒（中文教材/真题是合法材料）
    if (cjk >= 8 || (cjk > 0 && cjk >= latin)) return false;
    final words = RegExp(r'[a-zà-ỹ]+')
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0)!)
        .toList();
    if (words.length < 4) return false;
    var vi = 0;
    var id = 0;
    for (final word in words) {
      if (_vietnameseMarkers.contains(word)) vi++;
      if (_indonesianMarkers.contains(word)) id++;
    }
    if (vi >= 2) return true;
    if (id >= 3) return true;
    if (diacritic >= 3 && latin > 0 && diacritic * 60 >= latin) return true;
    if (words.length >= 40) {
      final ratio = englishStopwordRatio(text);
      if (ratio < 0.04 && vi + id >= 1) return true;
      if (ratio < 0.02 && diacritic >= 2) return true;
    }
    return false;
  }

  /// 是否像公告/报名/考试信息页。
  ///
  /// 2026-11-08 用户真机反馈「按需搜永远 0 条、8 条全被当公告过滤」：
  /// 旧实现是**任一弱信号命中就拒**（`官网/公告/培训/招生` 这类词在正常文章里
  /// 也可能出现）。现在改成"强信号单个即拒 + 弱信号累计 3 个才拒 + URL 路径强信号"。
  static bool looksLikeAnnouncementPage({
    required String title,
    String url = '',
    String snippet = '',
  }) {
    final hay = '${title.toLowerCase()} ${snippet.toLowerCase()}';
    for (final signal in _announcementStrongSignals) {
      if (hay.contains(signal)) return true;
    }
    for (final signal in _announcementStrongSignalsEn) {
      if (hay.contains(signal)) return true;
    }
    var weak = 0;
    for (final signal in _announcementWeakSignals) {
      if (hay.contains(signal)) weak++;
    }
    for (final signal in _announcementWeakSignalsEn) {
      if (hay.contains(signal)) weak++;
    }
    if (weak >= 3) return true;
    final path = url.toLowerCase();
    if (path.isNotEmpty) {
      for (final signal in _announcementUrlSignals) {
        if (path.contains(signal)) return true;
      }
    }
    return false;
  }

  /// 弱相关：标题+摘要与「检索词/分类」没有任何实质命中。
  ///
  /// 为什么不误杀官方搜索的好结果：
  /// - `rerankScore > 0`（官方搜索已排过相关性）或 `authority >= 2`（权威站点）→ 直接信任；
  /// - 中文用 2 字子串命中，英文用前 4 个字母做前缀匹配（`reading` 能命中 `read`）；
  /// - 没有种子词时不判（调用方没给依据就别乱杀）。
  static bool isWeaklyRelated({
    required String title,
    String snippet = '',
    required List<String> seeds,
    int rerankScore = 0,
    int authority = -1,
  }) {
    if (seeds.isEmpty) return false;
    if (rerankScore > 0 || authority >= 2) return false;
    final hay = '$title $snippet'.toLowerCase().trim();
    if (hay.isEmpty) return false;
    for (final seed in seeds) {
      final text = seed.toLowerCase().trim();
      if (text.isEmpty) continue;
      if (text.length >= 2 && hay.contains(text)) return false;
      final cjk = text.replaceAll(RegExp(r'[^\u4e00-\u9fff]'), '');
      for (var i = 0; i + 2 <= cjk.length; i++) {
        if (hay.contains(cjk.substring(i, i + 2))) return false;
      }
      for (final match in RegExp(r'[a-z0-9]+').allMatches(text)) {
        final token = match.group(0)!;
        final probe = token.length > 4 ? token.substring(0, 4) : token;
        if (probe.length >= 3 && hay.contains(probe)) return false;
      }
    }
    return true;
  }

  /// 候选级综合过滤：通过返回 null，否则返回拒收类别。
  static ContentReject? rejectCandidate({
    required String title,
    required String url,
    String snippet = '',
    List<String> seeds = const <String>[],
    int rerankScore = 0,
    int authority = -1,
  }) {
    if (looksLikeAnnouncementPage(title: title, url: url, snippet: snippet)) {
      return ContentReject.announcement;
    }
    if (looksLatinNonEnglish('$title $snippet')) return ContentReject.nonEnglish;
    if (isWeaklyRelated(
      title: title,
      snippet: snippet,
      seeds: seeds,
      rerankScore: rerankScore,
      authority: authority,
    )) {
      return ContentReject.weakRelated;
    }
    return null;
  }

  /// 拒收类别 → 给用户看的短说明（发现页 notes 汇总用）。
  static String rejectLabel(ContentReject reject) => switch (reject) {
        ContentReject.announcement => '公告/报名页',
        ContentReject.nonEnglish => '非英文内容',
        ContentReject.weakRelated => '与分类弱相关',
      };
}

/// 候选级拒收类别（发现流水线统计用）。
enum ContentReject { announcement, nonEnglish, weakRelated }
