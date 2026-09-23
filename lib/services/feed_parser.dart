/// RSS 2.0 / Atom / iTunes 播客订阅解析(纯函数,不联网、不抛异常)。
///
/// ## 用途
/// v2.0「材料中心」的选材入口:先解析订阅拿到**最新条目清单**(标题/链接/简介/
/// 音频),用户挑一条再抓详情页切块。所以这里只做"字段抽取",不做下载。
///
/// ## 合法边界
/// - 只解析**公开发布**的订阅源(RSS/Atom 生来就是给程序读的);
/// - 条目里的链接/音频地址一律**保留原样**,界面必须显示来源与出处;
/// - 供**个人学习**使用,不二次分发、不商用。
///
/// ## 为什么是正则 + 状态机,而不是 XML 库
/// 项目零额外依赖(见 `material_recommend_service.dart` 的自写 `_extractJson`),
/// 而订阅源的 XML 结构极其规整:`<item>`/`<entry>` 平铺、字段名固定。
/// 引入 XML 解析器换不来多少可靠性,却要付依赖与包体的代价。
///
/// ## 关键判断与已知局限
/// 1. **CDATA 必须先"去壳"再解实体**,不能反过来:CDATA 里 `&amp;` 是**字面量**,
///    先解实体等于把作者写的内容改掉(见 [FeedParser.parse] 里的处理顺序)。
/// 2. 命名空间前缀按**字面量**匹配(`media:content`/`itunes:author`/`dc:creator`),
///    不建命名空间表 —— 真实订阅源的写法高度一致,够用且可读。
/// 3. 时间字段(`pubDate`/`updated`/`published`)在**这里不做 DateTime 解析**,
///    原样返回字符串:格式太杂(RFC822/RFC3339/带时区名/非英文月份),
///    解析失败的代价("日期空了")比"留一串原样文本"更大,交给调用方按需处理。
/// 4. 只认**内联** XML,不处理外部实体(`<!ENTITY>`)/DTD;`<item>` 跨命名空间
///    混排、极端畸形 XML 下会返回空列表或跳过坏条目 —— **绝不抛异常**,
///    调用方看到空列表时应当报"该订阅源解析不出条目",而不是崩溃。
library;

import 'html_text.dart';

/// 一条订阅条目(列表页信息,不含正文)。
class FeedItem {
  /// 条目标题(已去 CDATA、已解实体)
  final String title;

  /// 条目链接(RSS 取 `<link>` 文本,Atom 取 `<link href>`)
  final String link;

  /// 简介/摘要(优先 `<description>`/`<summary>`,退回 `<content:encoded>`)
  final String summary;

  /// 发布时间**原样字符串**(如 `Wed, 23 Sep 2026 07:13:32 -0400` / RFC3339)
  final String? published;

  /// 音频地址(播客/听力材料的关键字段,可能为空)
  final String? audioUrl;

  /// 源内唯一 id(`<guid>`/`<id>`),用于去重
  final String? guid;

  /// 作者(`<dc:creator>`/`<itunes:author>`/Atom `<author><name>`,可能为空)
  final String? author;

  const FeedItem({
    required this.title,
    required this.link,
    this.summary = '',
    this.published,
    this.audioUrl,
    this.guid,
    this.author,
  });

  @override
  String toString() => 'FeedItem($title)';
}

/// 订阅解析器(全部静态纯函数)。
class FeedParser {
  FeedParser._();

  /// 同时支持 RSS 2.0(`<item>`)与 Atom(`<entry>`)。
  ///
  /// 返回顺序 = 文档顺序(通常是最新在前)。空串/畸形 XML/纯文本输入 → `[]`。
  static List<FeedItem> parse(String xml) {
    if (xml.trim().isEmpty) return const [];

    // ① 去 XML 声明与注释:声明里的 `?>` 和注释里的示例标签都会干扰后续正则
    var s = xml.replaceAll(RegExp(r'<\?[\s\S]*?\?>'), ' ');
    s = s.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');

    // ② CDATA 去壳(**必须在解实体之前**:CDATA 内的 `&amp;` 是字面量,
    //    先解实体就把作者的原文改掉了)。占位符 x01/x02 用来保留"这一段是
    //    代码/原文"的边界,避免与正常文本粘连。
    s = s.replaceAllMapped(
      RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'),
      (m) => '\u0001${m.group(1)}\u0001',
    );

    // ③ 逐块抽条目。RSS 用 <item>,Atom 用 <entry>;两种都按文档顺序,
    //    极少数源会混用,所以按出现位置排序而不是"先 item 再 entry"。
    final blocks = <({int start, String xml})>[
      ..._extractBlocks(s, 'item'),
      ..._extractBlocks(s, 'entry'),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final items = <FeedItem>[];
    for (final b in blocks) {
      final item = _parseItem(b.xml);
      // 坏条目直接跳过:没有标题也没有链接的块不可能是可用材料
      if (item == null) continue;
      items.add(item);
    }
    return items;
  }

  /// 从**单条** item 的 XML 片段里抽音频地址。
  ///
  /// 优先级(播客源的现实写法):
  /// 1. `<enclosure url=... type="audio/…">` —— RSS 2.0 标准做法;
  /// 2. `<media:content url=… type="audio/…">` —— Yahoo Media RSS,常与 enclosure 并存;
  /// 3. `<itunes:…>` / 无 type 的 enclosure —— 退而求其次,只要有 url 且不是图片就认。
  ///
  /// 排除 `.jpg/.png/.gif/.webp` 结尾的封面图 URL:很多源的 `<media:content>`
  /// 里同时挂着封面图,不排除会把"配图"当成"音频"发给播放器。
  static String? audioOf(String itemXml) {
    if (itemXml.trim().isEmpty) return null;
    final withType = <String>[];
    final fallback = <String>[];

    void collect(String? url, String? type) {
      final u = HtmlText.decodeEntities(url ?? '').trim();
      if (u.isEmpty) return;
      final t = (type ?? '').toLowerCase();
      if (t.contains('image') || _imageExt.hasMatch(u)) return;
      if (t.startsWith('audio') || t.contains('mpeg') || t.contains('mp3')) {
        withType.add(u);
      } else {
        fallback.add(u);
      }
    }

    // <enclosure> 与 <media:content> 都可能是自闭合(/>)或带子节点,统一只看开标签
    for (final m in _enclosureTag.allMatches(itemXml)) {
      collect(_attr(m.group(0)!, 'url'), _attr(m.group(0)!, 'type'));
    }
    for (final m in _mediaContentTag.allMatches(itemXml)) {
      collect(_attr(m.group(0)!, 'url'), _attr(m.group(0)!, 'type'));
    }
    if (withType.isNotEmpty) return withType.first;
    return fallback.isEmpty ? null : fallback.first;
  }

  // ────────────────────────── 内部实现 ──────────────────────────

  static final RegExp _imageExt =
      RegExp(r'\.(?:jpe?g|png|gif|webp|bmp|svg|ico)(?:\?|#|$)', caseSensitive: false);
  static final RegExp _enclosureTag =
      RegExp(r'<enclosure\b[^>]*>', caseSensitive: false);
  static final RegExp _mediaContentTag =
      RegExp(r'<(?:media:content|media:thumbnail|itunes:image)\b[^>]*>', caseSensitive: false);
  static final RegExp _attrRe = RegExp(
    r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  );

  /// 取标签属性值(纯函数)。属性值里的实体已解码 —— URL 里 `&amp;` 很常见
  /// (`?a=1&amp;b=2`),不解会让下载 404。
  static String? _attr(String tag, String name) {
    for (final m in _attrRe.allMatches(tag)) {
      if ((m.group(1) ?? '').toLowerCase() == name) {
        return HtmlText.decodeEntities(m.group(2) ?? m.group(3) ?? '');
      }
    }
    return null;
  }

  /// 深度扫描抽 `<tag>…</tag>` 块(支持嵌套、跨行)。
  /// 返回每块在原文中的起始下标(用于跨 item/entry 排序)与内容。
  static List<({int start, String xml})> _extractBlocks(String s, String tag) {
    final open = RegExp('<$tag\\b[^>]*>', caseSensitive: false);
    final close = RegExp('</$tag\\s*>', caseSensitive: false);
    final out = <({int start, String xml})>[];
    var i = 0;
    while (true) {
      final o = open.firstMatch(s.substring(i));
      if (o == null) break;
      final start = i + o.start;
      var depth = 0;
      var j = start;
      var end = -1;
      while (j < s.length) {
        final om = open.matchAsPrefix(s, j);
        if (om != null) {
          depth++;
          j = om.end;
          continue;
        }
        final cm = close.matchAsPrefix(s, j);
        if (cm != null) {
          depth--;
          j = cm.end;
          if (depth <= 0) {
            end = j;
            break;
          }
          continue;
        }
        j++;
      }
      if (end < 0) break; // 没有闭合标签:这一块不完整,后面的也不值得再试
      out.add((start: start, xml: s.substring(start, end)));
      i = end;
    }
    return out;
  }

  static FeedItem? _parseItem(String raw) {
    final title = _clean(_tagText(raw, 'title'));
    final link = _linkOf(raw);
    // **没有链接的条目直接丢掉**:链接是这条材料能不能被打开的唯一凭据,
    // 标题只是展示用的 —— 只有标题没有链接的条目点了也白点(订阅源里
    // 并不罕见:占位条目、已下架条目)。反过来,只有链接没标题**要保留**:
    // 标题可以由调用方用 URL 或简介兜底显示。
    if (link.isEmpty) return null;

    var summary = _clean(_tagText(raw, 'description'));
    if (summary.isEmpty) summary = _clean(_tagText(raw, 'summary'));
    if (summary.isEmpty) summary = _clean(_tagText(raw, 'content:encoded'));
    if (summary.isEmpty) summary = _clean(_tagText(raw, 'content'));
    // 简介要能当"一句话说明"用:里面还带标签就更糟,再剥一层
    summary = HtmlText.stripTags(summary);

    final published = _firstNonEmpty([
      _clean(_tagText(raw, 'pubDate')),
      _clean(_tagText(raw, 'published')),
      _clean(_tagText(raw, 'updated')),
      _clean(_tagText(raw, 'dc:date')),
    ]);

    final guid = _firstNonEmpty([
      _clean(_tagText(raw, 'guid')),
      _clean(_tagText(raw, 'id')),
    ]);

    // 作者优先级:dc:creator(RSS)> itunes:author(播客)> author(Atom)。
    // 取**第一个非空**而不是拼接:同一期节目的这几个字段常是同一个人/机构的不同
    // 表述,拼起来会得到 "Neil and Beth BBC Learning English" 这种脏数据。
    var author = '';
    for (final rawAuthor in [
      _tagText(raw, 'dc:creator'),
      _tagText(raw, 'itunes:author'),
      _tagText(raw, 'author'),
    ]) {
      final cleaned = _clean(rawAuthor);
      if (cleaned.isNotEmpty) {
        author = cleaned;
        break;
      }
    }

    return FeedItem(
      title: title,
      link: link,
      summary: summary,
      published: published,
      audioUrl: audioOf(raw),
      guid: guid,
      author: author.isEmpty ? null : author,
    );
  }

  /// 条目链接。
  /// - Atom:`<link href="…" rel="alternate"/>` —— 网址在**属性**里;
  ///   优先 `rel` 缺省或 `alternate`(那才是文章页),`self`/`edit`/`replies` 降权;
  /// - RSS:`<link>https://…</link>` —— 网址在**文本**里,没有 rel 属性,
  ///   只在"没有任何 href 候选"时才使用,避免 `<link rel="self" href="feed">`
  ///   这类自指链接盖掉真正的文章地址。
  static String _linkOf(String raw) {
    final attrHits = <({int score, String url})>[];
    final textHits = <({int score, String url})>[];
    for (final m in _linkTag.allMatches(raw)) {
      final tag = m.group(0) ?? '';
      final rel = (_attr(tag, 'rel') ?? '').toLowerCase();
      final href = _attr(tag, 'href');
      if (href != null && href.isNotEmpty) {
        final h = HtmlText.decodeEntities(href).trim();
        if (h.isNotEmpty) {
          // 0 = rel 缺省或 alternate(文章页);1 = 未知 rel;2 = 自指/编辑类
          final score = rel.isEmpty || rel == 'alternate'
              ? 0
              : (rel == 'self' || rel == 'edit' || rel == 'replies' ? 2 : 1);
          attrHits.add((score: score, url: h));
        }
      }
      // RSS 的 `<link>https://…</link>`:网址在**文本**里,对应捕获组 2
      // (组 1 是属性串,取错了会得到空链接 —— v2.0 开发中真实踩过)
      final text = _clean(m.group(2) ?? '');
      if (text.isNotEmpty) textHits.add((score: 0, url: text));
    }
    if (attrHits.isNotEmpty) {
      attrHits.sort((a, b) => a.score.compareTo(b.score));
      return attrHits.first.url;
    }
    if (textHits.isNotEmpty) return textHits.first.url;
    // 兜底:极少数源把链接塞在 guid 里(guid isPermaLink="true")
    final guid = _clean(_tagText(raw, 'guid'));
    return guid.startsWith('http') ? guid : '';
  }

  static final RegExp _linkTag = RegExp(
    r'''<link\b([^>]*?)(?:/>|>([\s\S]*?)</link\s*>)''',
    caseSensitive: false,
  );

  /// 取某标签的文本内容。找不到返回 null。
  ///
  /// 属性里带 `>` 的标签(如 `<meta content="a>b">`)会让非贪婪匹配偏斜,
  /// 但订阅源里极少见;真出现时最坏结果是该字段为空,不会污染其它字段。
  static String? _tagText(String raw, String name) {
    final re = RegExp(
      '<$name\\b[^>]*>([\\s\\S]*?)</$name\\s*>',
      caseSensitive: false,
    );
    for (final m in re.allMatches(raw)) {
      return m.group(1);
    }
    return null;
  }

  /// 去掉 CDATA 占位符、剥标签、收敛空白。
  static String _clean(String? s) {
    if (s == null || s.isEmpty) return '';
    final t = s.replaceAll('\u0001', ' ');
    return HtmlText.stripTags(t);
  }

  static String? _firstNonEmpty(List<String> vals) {
    for (final v in vals) {
      if (v.isNotEmpty) return v;
    }
    return null;
  }
}
