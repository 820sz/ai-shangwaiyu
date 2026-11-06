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
}
