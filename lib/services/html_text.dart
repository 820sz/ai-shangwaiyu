/// HTML → 正文纯文本(纯函数,v2.0 材料中心的内容获取层地基)。
///
/// ## 为什么自己写而不用 `html` / `package:html`
/// 项目至今**零额外依赖**(见 `material_recommend_service.dart` 里自写的
/// `_extractJson`)。为了抓材料正文引入一个 DOM 解析库,会把依赖面、包体、
/// 供应链风险一起带进来,而这里真正需要的只有三件事:剥标签、抽链接、解实体。
/// 三者都能用有限状态机 + 正则做到"够用且可测",所以维持既有风格。
///
/// ## 合法边界(必须遵守,写在这里是为了将来改代码的人不会越界)
/// - 只处理**公开可访问**的页面:公开新闻/播客页、公版书、百科、论文摘要页。
/// - 抓到的一切内容**保留出处**(调用方务必把来源 URL / 许可写进 `MaterialDoc`);
///   本文件只做文本转换,不负责抓取。
/// - 面向**个人学习**使用,不二次分发、不商用、不绕过任何付费墙或登录墙。
/// - 不做"反爬对抗":不伪造身份、不轮换 IP、不解析验证码。
///
/// ## 已知局限(启发式,源改版就会失效)
/// 1. 正则不是 HTML 解析器:畸形标签、`<script>` 里出现的 `</script>` 字符串、
///    注释里嵌套注释都可能让结果偏斜。宁可**少抽一点**,也不要混进标签。
/// 2. 去标签用"非贪婪匹配 + 深度扫描"两层:普通标签靠非贪婪,像
///    `<footer><footer></footer></footer>` 这种嵌套块靠 [removeBlock] 的深度计数。
/// 3. **需要 JS 渲染的页面**(前端框架挂载正文的站点)这里抽不到正文 ——
///    本层不做无头浏览器,抽不到就让调用方抛可诊断的中文异常,不要静默给空文档。
/// 4. 正文的"段落边界"只是标签启发式(`<p>`/`<br>`/标题/`<li>`),
///    不保证与视觉排版一致。
library;

/// HTML 文本处理工具(全部静态纯函数,无状态、无 IO、可单测)。
class HtmlText {
  HtmlText._();

  /// `<title>` 标签(HTML5 里 `</title>` 不能省略,但现实页面有省略的)。
  static final RegExp _titleTag = RegExp(
    r'<title[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  );

  /// 注释:必须在一切别的处理之前剥掉 —— 注释里常出现被注释掉的 `<script>`、
  /// `<nav>`,不先删就会把它们当真实标签处理掉正文。
  static final RegExp _comment = RegExp(r'<!--[\s\S]*?-->');

  /// 取 `<title>`(解码实体;没有则返回空串)。
  ///
  /// 只在 `<head>` 里找:某些页面正文/内联 SVG 也可能出现 `<title>`,
  /// 优先 head 才拿得到"真正的标题"。head 缺失时退回全文第一个匹配。
  static String titleOf(String html) {
    if (html.isEmpty) return '';
    String? raw = _firstGroup(_titleTag, _headOf(html));
    // head 里没有才退回全文找:很多页面省了 </head> 或用了非标准结构,
    // 这时宁可拿到"第一个 title",也好过空标题让材料列表一片空白。
    raw ??= _firstGroup(_titleTag, html.replaceAll(_comment, zeroWidth));
    if (raw == null) return '';
    return decodeEntities(raw).replaceAll(zeroWidth, ' ').trim();
  }

  /// 抽正文,返回按段落用 `\n\n` 连接的纯文本。
  ///
  /// 步骤(顺序有讲究,别随意调换):
  /// 1. 去注释 → 删掉 script/style/… 整块(**必须先做,否则 CSS/JS 源码会混进正文**);
  /// 2. 去掉 nav/header/footer/aside 的**标签但保留其中文字**(正文里 `<header>` 常
  ///    被用来包标题、`<footer>` 里可能有作者署名,整块删会丢内容;模板导航在上一步
  ///    已经随 `<nav>` 一起清掉了);
  /// 3. 块级标签换成段标记、`<br>` 换成软换行 → 其余标签删掉;
  /// 4. 解码实体 → 逐行清理 → 成段 → 丢掉整段都是导航链接的块。
  ///
  /// 输入没有任何 `<` 时按"纯文本"处理,直接返回空串:本函数的契约是
  /// "解析 HTML",拿到纯文本说明调用方用错了 API,不要假装抽出了正文。
  static String readableText(String html) {
    if (html.isEmpty || !html.contains('<')) return '';
    var s = html;

    // ① 注释 + 整块删除的容器(script/style 里的源码不能进正文)
    s = s.replaceAll(_comment, zeroWidth);
    for (final tag in _dropBlockTags) {
      s = removeAllBlocks(s, tag);
    }

    // ② 段落边界标签 → 段标记(双换行)。
    //    `<br>` 也按段落边界处理(任务约定的边界集合:p/br/h1-6/li/blockquote):
    //    老式页面用 `<br><br>` 当分段符,学习材料里的歌词/对话也靠 `<br>` 断行,
    //    当成段边界比"粘成一行"更贴近作者意图。
    //    注意闭标签要先于开标签处理,`</h2><p>` 才不会粘成一行。
    s = s.replaceAll(_blockClose, paraMark);
    s = s.replaceAll(_blockOpen, paraMark);
    s = s.replaceAll(_liClose, paraMark);
    s = s.replaceAll(_liOpen, paraMark);
    s = s.replaceAll(_brTag, paraMark);

    // ③ 除 `<a>` 之外的标签全删。**`<a>` 故意留到段落阶段之后**:
    //    "整段就是一个短链接"(菜单/按钮/跳转提示)只能靠标签本身判断 ——
    //    先把 `<a>` 删了,段落阶段只看到一串纯文字,就再也分不出它是导航还是正文
    //    (真实 NPR 页面的 "Accessibility links"、"Skip to main content"
    //    就是这么漏进正文的)。
    s = s.replaceAll(_nonAnchorTag, zeroWidth);
    s = decodeEntities(s);

    // ④ 逐行成段(纯链接的导航段在这里被丢掉)
    final text = _paragraphize(s);
    // ⑤ 段落成型后再去掉残留的 `<a>` 标签(正文里的行内链接文字要留下)
    return text.replaceAll(_anchorTagAny, '').trim();
  }

  /// 抽出所有 `<a href>` 的链接并绝对化(相对路径按 [baseUrl] 解析)。
  ///
  /// - 只认 `href`,不认 `src`/`data-href`;
  /// - 跳过 `javascript:`/`mailto:`/`tel:`/`data:` 与纯 `#锚点` —— 这些不是"可抓的材料";
  /// - 保持文档顺序,按最终绝对 URL 去重(同一篇文章在页头页脚各链一次很常见);
  /// - 没有 [baseUrl](或 baseUrl 非法)时,相对链接**原样返回**:
  ///   调用方至少能看到"这里有个相对链接",比丢掉更好诊断。
  static List<String> links(String html, {String? baseUrl}) {
    if (html.isEmpty || !html.contains('<')) return const [];
    final out = <String>[];
    final seen = <String>{};
    for (final m in _anchorTag.allMatches(html)) {
      final raw = decodeEntities(m.group(1) ?? '').trim();
      if (raw.isEmpty) continue;
      final lower = raw.toLowerCase();
      if (lower.startsWith('javascript:') ||
          lower.startsWith('mailto:') ||
          lower.startsWith('tel:') ||
          lower.startsWith('data:') ||
          raw.startsWith('#')) {
        continue;
      }
      final abs = resolveUrl(raw, baseUrl);
      if (abs.isEmpty || !seen.add(abs)) continue;
      out.add(abs);
    }
    return out;
  }

  /// 解码 HTML 实体(独立可测)。认识命名实体 + 十进制/十六进制数字实体;
  /// **不认识的实体原样保留**:擅自删掉会把可见文本吃掉,保留至少能看出处。
  static String decodeEntities(String s) {
    if (s.isEmpty || !s.contains('&')) return s;
    return s.replaceAllMapped(_entity, (m) {
      final name = m.group(1);
      if (name != null && name.isNotEmpty) {
        return _namedEntities[name.toLowerCase()] ?? m.group(0)!;
      }
      final hex = m.group(3);
      final dec = m.group(2);
      // 十进制与十六进制**必须分开解析**:
      // `int.tryParse('0x$num')` 对十进制输入也会成功(`0x39` = 57 = '9'),
      // 于是 `&#39;` 会被解成 '9'、`&#8212;` 解成 '舒'(v2.0 开发中真实踩过)。
      // 组 2 是十进制、组 3 才是十六进制,按各自进制解析,不用 ?? 兜底混用。
      final int? code;
      if (hex != null && hex.isNotEmpty) {
        code = int.tryParse(hex, radix: 16);
      } else if (dec != null && dec.isNotEmpty) {
        code = int.tryParse(dec);
      } else {
        code = null;
      }
      if (code == null || code < 0 || code > 0x10FFFF) return m.group(0)!;
      // 代理区码点单独出现时 String.fromCharCode 会产出非法字符,直接放过
      if (code >= 0xD800 && code <= 0xDFFF) return m.group(0)!;
      return String.fromCharCode(code);
    });
  }

  /// 去掉标签只留文本(不保留段落,用于 summary / 一句话简介)。
  ///
  /// 与 [readableText] 的区别:这里**合并成一行**,并且不丢"短行" ——
  /// 摘要场景下一句话被当成导航丢掉是最糟的错误。
  static String stripTags(String s) {
    if (s.isEmpty) return '';
    var t = s.replaceAll(_comment, zeroWidth);
    t = t.replaceAll(_anyTag, ' ');
    // 连着两个标签(如 `</p><p>`)会留下两个空格,这里一并压成一个
    return _oneLine(decodeEntities(t));
  }

  /// 删除页面上**所有** `<tag>…</tag>` 块(反复调 [removeBlock] 直到没有变化)。
  ///
  /// 为什么必须"删干净"而不是删一处:真实页面动辄十几个 `<script>`(埋点、
  /// 同意管理、播放器各一个)。只删第一处,剩下的 JS 会整段混进正文 ——
  /// 实测 NPR 文章页正文里就漏进过 OneTrust 的 `function OptanonWrapper()…`,
  /// 词数从 800 涨到 2200,难度统计跟着全错。
  ///
  /// 终止性:[removeBlock] 每轮要么删掉至少一个字符(串变短),要么原样返回
  /// (此时立即结束),所以循环必然收敛,不需要额外计数。
  static String removeAllBlocks(String html, String tag) {
    var s = html;
    while (true) {
      final next = removeBlock(s, tag);
      if (next.length >= s.length) return next;
      s = next;
    }
  }

  /// 删除**第一处** `<tag>…</tag>` 整块(**含嵌套**,含跨行内容)。
  ///
  /// 为什么不用一个非贪婪正则了事:页面里 `<footer><footer>…</footer></footer>`
  /// 这类嵌套并不罕见,非贪婪会在**第一个** `</footer>` 就停下,把内层的
  /// 尾部内容漏进正文。这里做深度计数,只在自己这一层的闭合标签处收尾。
  ///
  /// 只处理第一处(方便单测与"删一层再判断"的用法);要清掉某类标签的**全部**
  /// 出现,用 [removeAllBlocks]。
  ///
  /// 未闭合时返回原串(剩余的开标签随后会被 [readableText] 的整标签删除兜掉)。
  static String removeBlock(String html, String tag) {
    if (html.isEmpty) return html;
    final open = RegExp('<$tag\\b', caseSensitive: false);
    final close = RegExp('</$tag\\s*>', caseSensitive: false);
    final start = open.firstMatch(html);
    if (start == null) return html;
    var depth = 0;
    var i = start.start;
    while (i < html.length) {
      final o = open.matchAsPrefix(html, i);
      if (o != null) {
        depth++;
        i = o.end;
        continue;
      }
      final c = close.matchAsPrefix(html, i);
      if (c != null) {
        depth--;
        i = c.end;
        if (depth <= 0) {
          return html.substring(0, start.start) + html.substring(i);
        }
        continue;
      }
      i++;
    }
    return html;
  }

  /// 把相对链接解析成绝对链接(RFC 3986 的常用子集;纯函数,可单测)。
  ///
  /// 支持:`https://…`(原样)、`//host/path`(补协议)、`/path`(补源)、
  /// `a/b`(拼在 base 目录后)、`../x`(按段回退)、`?q` / `#f`(只换查询/片段)。
  /// [baseUrl] 为空或不像 URL 时返回 [href] 原样。
  static String resolveUrl(String href, String? baseUrl) {
    final h = href.trim();
    if (h.isEmpty) return '';
    if (_schemeHead.hasMatch(h)) return h;
    final base = (baseUrl ?? '').trim();
    if (base.isEmpty) return h;
    final m = _absBase.firstMatch(base);
    if (m == null) return h;
    final scheme = m.group(1)!;
    final authority = m.group(2)!;
    final basePath = m.group(3) ?? '';
    final origin = '$scheme://$authority';

    if (h.startsWith('#')) return '$origin$basePath$h';
    if (h.startsWith('?')) {
      final q = basePath.indexOf('?');
      final path = q >= 0 ? basePath.substring(0, q) : basePath;
      return '$origin$path$h';
    }
    if (h.startsWith('//')) return '$scheme:$h';
    if (h.startsWith('/')) return '$origin${_removeDotSegments(h)}';
    // 相对:base 的最后一段是文件名,要丢掉,再拼接
    final cut = basePath.indexOf('?');
    final noQuery = cut >= 0 ? basePath.substring(0, cut) : basePath;
    final slash = noQuery.lastIndexOf('/');
    final dir = slash >= 0 ? noQuery.substring(0, slash + 1) : '/';
    return '$origin${_removeDotSegments('$dir$h')}';
  }

  // ────────────────────────── 内部实现 ──────────────────────────

  /// 换行标记:用不可见字符而不是 '\n'。
  /// 原因:标签属性里也常有换行,统一把"原始换行"合并成空格(见 [_paragraphize]),
  /// 才不会把 `<meta\n  content="x">` 拆成两段;只有标记能产生段落。
  static const String zeroWidth = '\u0001';

  /// 段落标记:**两个** zeroWidth。段落用双换行表示,所以"一个新段落"要留两个该字符。
  /// 用同一个字符而不是引入第三种标记,是为了让 [_paragraphize] 只有一条拆行规则。
  static const String paraMark = '\u0001\u0001';

  static final RegExp _schemeHead = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');
  static final RegExp _absBase = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*)://([^/?#]+)([\s\S]*)$');
  static final RegExp _anyTag = RegExp(r'<[^>]*>');

  /// 除 `<a>`(任意大小写,含 `</a>`)之外的所有标签。
  ///
  /// 两个先行断言分别管开标签与闭标签,**不能用 `</?(?!a\b)` 那种写法**:
  /// `</?` 里的 `/?` 可以回溯成"不匹配斜杠",于是 `</a>` 会被 `<[^>]*>` 这一路
  /// 匹配掉 —— 闭标签一丢,后面的"整段就是一个链接"判断全部失效
  /// (v2.0 实测:NPR 的 skip-links 两行就是被这个回溯漏进正文的)。
  static final RegExp _nonAnchorTag = RegExp(
    r'<(?!a[\s>])(?!/a[\s>])[^>]*>',
    caseSensitive: false,
  );

  /// 残留的 `<a …>` / `</a>`(段落成型后清掉)
  static final RegExp _anchorTagAny = RegExp(r'</?a\b[^>]*>', caseSensitive: false);

  static final RegExp _anchorTag = RegExp(
    r'''<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''',
    caseSensitive: false,
  );

  /// 整块删除的容器:看一眼就知道不是正文的东西。
  ///
  /// - script/style/noscript:前者是 CSS/JS 源码,不删会混进正文(本层最重要的一条);
  ///   noscript 里常塞一整份"请开启 JavaScript"的说明;
  /// - svg:全是 path 数据;iframe:抽不出内容;form:搜索框/订阅框一类的交互件;
  /// - template:未渲染的模板片段;
  /// - nav/header/footer/aside:模板导航、页头页脚、侧栏 —— 与正文无关。
  ///
  /// 代价要说清:正文页里 `<header>` 偶尔被拿来包标题(`<article><header><h1>`),
  /// 整块删会连标题一起删。这里仍选择删,因为"菜单/页脚文字混进正文"更常见、
  /// 更伤学习材料质量;标题可以从 `<title>` 拿([titleOf]),不会全丢。
  static const List<String> _dropBlockTags = [
    'script',
    'style',
    'noscript',
    'svg',
    'iframe',
    'form',
    'template',
    'nav',
    'header',
    'footer',
    'aside',
  ];

  /// 段落边界(闭标签)。处理后开标签与 `li` 单独走,顺序见 [readableText]。
  static final RegExp _blockClose = RegExp(
    r'</(?:p|div|ul|ol|dl|dd|dt|tr|td|th|table|h[1-6]|blockquote|pre|'
    r'figure|figcaption|section|article|main)\s*>',
    caseSensitive: false,
  );
  static final RegExp _blockOpen = RegExp(
    r'<(?:p|div|hr|ul|ol|dl|dd|dt|tr|td|th|table|'
    r'h[1-6]|blockquote|pre|figure|figcaption|section|article|main)\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _liClose = RegExp(r'</li\s*>', caseSensitive: false);
  static final RegExp _liOpen = RegExp(r'<li\b[^>]*>', caseSensitive: false);
  static final RegExp _brTag = RegExp(r'<br\b[^>]*>', caseSensitive: false);

  /// 整段就是链接/按钮的导航块:去掉正文里的"菜单噪声"。
  static final RegExp _linkOnly = RegExp(
    r'^(?:\s*<a\b[\s\S]*?</a>)+\s*$',
    caseSensitive: false,
  );
  static final RegExp _anyLink = RegExp(
    r'<a\b[\s\S]*?</a>',
    caseSensitive: false,
  );
  static final RegExp _cjk = RegExp(r'[\u3000-\u9fff\uff00-\uffef]');
  static final RegExp _spaceRun = RegExp(r'[ \t\u00a0]+');
  static final RegExp _allSpace = RegExp(r'\s+');

  static String _headOf(String html) {
    final m = RegExp(r'<head\b[^>]*>([\s\S]*?)</head>', caseSensitive: false)
        .firstMatch(html);
    return m?.group(1) ?? html;
  }

  static String? _firstGroup(RegExp re, String s) {
    for (final m in re.allMatches(s)) {
      return m.group(1);
    }
    return null;
  }

  /// RFC 3986 remove_dot_segments(只处理 path 部分)
  static String _removeDotSegments(String path) {
    final q = path.indexOf('?');
    final f = path.indexOf('#');
    var end = path.length;
    if (q >= 0 && q < end) end = q;
    if (f >= 0 && f < end) end = f;
    final pure = path.substring(0, end);
    final tail = path.substring(end);
    final trailingSlash = pure.endsWith('/');
    final out = <String>[];
    for (final seg in pure.split('/')) {
      if (seg == '.' || seg.isEmpty) continue;
      if (seg == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(seg);
    }
    final joined = '/${out.join('/')}';
    return (trailingSlash && joined != '/') ? '$joined/$tail' : '$joined$tail';
  }

  static String _normSpace(String s) =>
      s.replaceAll(_spaceRun, ' ').trim();

  static String _oneLine(String s) => s.replaceAll(_allSpace, ' ').trim();

  /// 逐行成段。
  ///
  /// 规则只有两条,别再往里加"以句号结尾就断段"这类启发式:
  /// - **空行 = 段边界**:段落边界标签(p/br/h1-6/li/blockquote…)在 [readableText]
  ///   里已被换成段落标记(双换行),拆行后正好留下一行空行;
  /// - **段内换行 = 软换行**:源码里的排版折行只产生 '\n',相邻两行用 [_joiner]
  ///   拼起来 —— 一个 `<p>` 就是一段,这是 HTML 的语义。
  ///
  /// 早期版本用"上一行以 `.`/`?`/`!` 结尾就断段"来补段落,结果一段正常英文
  /// 因为内部有句号被切成一堆碎片 —— 反了:段落之间靠标签分,不靠标点猜。
  static String _paragraphize(String s) {
    final lines = s
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(zeroWidth, '\n')
        .split('\n');
    final blocks = <String>[];
    final buf = <String>[];
    void flush() {
      if (buf.isEmpty) return;
      blocks.add(buf.join());
      buf.clear();
    }

    for (final raw in lines) {
      // 导航块判定要在删标签**之前**做(那时才看得见 `<a>`),
      // 所以在判断之后再用 _normSpace 规范化这一行
      if (_isNavBlock(raw)) continue;
      final line = _normSpace(raw);
      if (line.isEmpty) {
        flush();
        continue;
      }
      if (buf.isNotEmpty) buf.add(_joiner(buf.last, line));
      buf.add(line);
    }
    flush();
    return blocks.where((b) => b.trim().isNotEmpty).join('\n\n').trim();
  }

  /// 两行之间的连接方式:英文补一个空格;上一行以连字符结尾说明是**断词**,
  /// 不能塞空格(否则生词会被拼坏,直接影响取词与词频统计);中文之间不补空格。
  static String _joiner(String prev, String next) {
    if (prev.isEmpty) return '';
    if (prev.endsWith('-')) return '';
    final a = prev[prev.length - 1];
    final b = next[0];
    if (_cjk.hasMatch(a) && _cjk.hasMatch(b)) return '';
    if (b == ',' || b == '.' || b == ';' || b == ':' || b == '!' ||
        b == '?' || b == ')' || b == ']' || b == '，' || b == '。') {
      return '';
    }
    return ' ';
  }

  /// 是不是"导航块":整行只由 `<a>…</a>` 组成(可以多个),没有别的内容。
  /// 链接文字累计超过 6 个词或 40 个字符时**不丢** —— 那更可能是正文里的引用。
  /// 例:`<a>Accessibility links</a>`、`<a>Skip to main content</a>` 丢掉;
  /// `<a>Read the full transcript and listen to the audio</a>` 保留。
  static bool _isNavBlock(String line) {
    if (line.isEmpty || !line.contains('<')) return false;
    if (!_linkOnly.hasMatch(line)) return false;
    final linkText = _oneLine(line.replaceAll(_anyTag, ' '));
    if (linkText.isEmpty) return true; // 空链接(只有图标)
    if (linkText.length > 40) return false;
    if (linkText.split(' ').where((w) => w.isNotEmpty).length > 6) return false;
    // `<a>` 之外还有文字(如 `主站 · <a>关于</a>`)就不算纯导航
    final outside = _oneLine(line.replaceAll(_anyLink, ' '));
    return outside.isEmpty;
  }
}

/// 常见命名实体表(够覆盖新闻/书籍/百科页面;冷门实体保留原样更安全)。
const Map<String, String> _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ensp': ' ',
  'emsp': ' ',
  'thinsp': ' ',
  'zwnj': '',
  'zwj': '',
  'shy': '',
  'mdash': '—',
  'ndash': '–',
  'minus': '−',
  'horbar': '―',
  'lsquo': '‘',
  'rsquo': '’',
  'sbquo': '‚',
  'ldquo': '“',
  'rdquo': '”',
  'bdquo': '„',
  'hellip': '…',
  'bull': '•',
  'middot': '·',
  'dagger': '†',
  'sect': '§',
  'para': '¶',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'euro': '€',
  'pound': '£',
  'yen': '¥',
  'cent': '¢',
  'deg': '°',
  'plusmn': '±',
  'times': '×',
  'divide': '÷',
  'frac12': '½',
  'frac14': '¼',
  'frac34': '¾',
  'laquo': '«',
  'raquo': '»',
  'lsaquo': '‹',
  'rsaquo': '›',
  'larr': '←',
  'rarr': '→',
  'harr': '↔',
  'prime': '′',
  'oelig': 'œ',
  'aelig': 'æ',
  'szlig': 'ß',
  'agrave': 'à',
  'aacute': 'á',
  'auml': 'ä',
  'aring': 'å',
  'ccedil': 'ç',
  'egrave': 'è',
  'eacute': 'é',
  'euml': 'ë',
  'igrave': 'ì',
  'iacute': 'í',
  'iuml': 'ï',
  'ntilde': 'ñ',
  'ograve': 'ò',
  'oacute': 'ó',
  'ouml': 'ö',
  'ugrave': 'ù',
  'uacute': 'ú',
  'uuml': 'ü',
  'alpha': 'α',
  'beta': 'β',
  'gamma': 'γ',
  'delta': 'δ',
  'pi': 'π',
  'sigma': 'σ',
  'omega': 'ω',
  'mu': 'µ',
  'spades': '♠',
  'clubs': '♣',
  'hearts': '♥',
  'diams': '♦',
};

/// 实体匹配:1=命名,2=十进制,3=十六进制
final RegExp _entity = RegExp(r'&([a-zA-Z][a-zA-Z0-9]{1,31});|&#(\d{1,7});|&#[xX]([0-9a-fA-F]{1,6});');
