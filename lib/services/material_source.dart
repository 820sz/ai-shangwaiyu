/// v2.0「材料中心」的内容获取层:内容源清单 + 抓取器 + 结果模型。
///
/// ## 这一层要解决什么
/// 用户不该自己找材料、更不该自己上传材料 —— **材料是软件提供的渠道**。
/// 所以这里的职责是:把"公开、合法、不需要 API key"的真实材料抓进来,
/// 并切成可学习的小块(交给难度分析/生词标注/阅读器)。
///
/// ## 合法边界(硬约束,不是客套话)
/// - 只抓**公开可访问**的内容:公开 RSS / 公开网页 / 公版书 / 百科 / 论文摘要页。
/// - **不绕过**登录墙、付费墙、验证码、robots 限制;不做身份伪造与 IP 轮换。
/// - 每条 [MaterialSource.license] 都会展示给用户;抓下来的 [MaterialDoc] 必须
///   带上出处 [MaterialDoc.url] 与许可 [MaterialDoc.license] —— 保留出处是底线。
/// - 面向**个人学习**使用,不二次分发、不商用。界面文案要写清这一点。
///
/// ## 解析是启发式,失败必须可诊断
/// 页面改版、源站下线、地区不可达都会让抽取失效。因此:
/// - 抽不到内容**不静默返回空文档**,而是抛 [MaterialSourceException](中文可读,
///   带源名与状态码),让界面能告诉用户"哪个源、什么原因、怎么办";
/// - 每个源的 URL 组装都是独立纯函数([feedUrlOf]/[documentUrlOf]),可单测。
///
/// ## 已知局限(诚实记录)
/// 1. **需要 JS 渲染的页面抽不到正文**:本层不跑无头浏览器,抽不到就抛异常。
/// 2. **地区可达性**:BBC Learning English / VOA / TED(feedburner)/ Wikipedia
///    在中国大陆网络下不可直连(实测超时),NPR / Project Gutenberg / arXiv 可直连。
///    不可达时 [MaterialSourceException] 会明确提示"网络不可达",不假装是解析问题。
/// 3. VOA 的订阅地址(VOA 自研的 `/api/…` 集合接口)在本次开发环境不可验证,
///    按社区通行写法提供并标 TODO,见 [sources] 里 `voa_le` 的注释。
/// 4. 正文抽取依赖 `HtmlText.readableText` 的启发式,源站改版后段落可能变粗/变细。
/// 5. 字体/格式:不解析 PDF、不解析 EPUB;arXiv 只取摘要页,不下载 PDF。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'feed_parser.dart';
import 'html_text.dart';

/// 一个内容源(渠道)的元信息。**全部无需 API key**。
class MaterialSource {
  /// 源 id,同时用作数据库/缓存里的 key
  final String id;

  /// 中文展示名
  final String label;

  /// 内容形态:`news` | `book` | `podcast` | `wiki` | `paper`
  final String kind;

  /// 一句话说明(展示给用户"这是什么材料")
  final String description;

  /// 版权/许可说明(**必须展示给用户**,关系到能不能复制、能不能再分发)
  final String license;

  /// 是否有音频(听力材料的筛选条件)
  final bool hasAudio;

  /// 主要语言
  final String language;

  const MaterialSource({
    required this.id,
    required this.label,
    required this.kind,
    required this.description,
    required this.license,
    required this.hasAudio,
    this.language = 'en',
  });
}

/// 切好块的一段材料(阅读器一屏/一次学习的单位)。
class MaterialChunk {
  /// 在本文档内的序号(从 1 开始,方便 UI 显示"第 3 段/共 12 段")
  final int index;

  /// 块标题(书是章节名,新闻/播客是 null)
  final String? title;

  final String text;

  const MaterialChunk({required this.index, this.title, required this.text});
}

/// 一份抓取完成、已切块的材料。
class MaterialDoc {
  /// 内容源 id(见 [MaterialSourceService.sources])
  final String sourceId;

  /// **源内 id**(去重用,按任务约定命名 `sourceId2`):书的 Gutenberg id、
  /// 论文的 arXiv id、新闻/播客条目的 guid 或 URL 路径。
  /// 与 [sourceId] 是两个维度:一个是"哪个渠道",一个是"渠道里的哪一篇"。
  final String sourceId2;

  /// 内容形态,同 [MaterialSource.kind]
  final String kind;

  final String title;
  final String author;

  /// 出处链接(**必须展示**,合法使用的底线)
  final String url;

  /// 许可说明(从 [MaterialSource.license] 带下来)
  final String license;

  final String language;

  final String? audioUrl;

  final List<MaterialChunk> chunks;

  /// 全文纯文本(交给 `text_difficulty.dart` 做难度分析)
  final String plainText;

  const MaterialDoc({
    required this.sourceId,
    required this.sourceId2,
    required this.kind,
    required this.title,
    this.author = '',
    required this.url,
    required this.license,
    this.language = 'en',
    this.audioUrl,
    required this.chunks,
    required this.plainText,
  });

  /// 词数(粗估:按空白切)
  int get wordCount =>
      plainText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  bool get hasAudio => (audioUrl ?? '').isNotEmpty;
}

/// 抓取/解析失败。**中文可读**,给界面直接显示。
class MaterialSourceException implements Exception {
  /// 出问题的源中文名(如「BBC Learning English」)
  final String sourceLabel;

  /// 人话原因(已含状态码等信息)
  final String message;

  /// HTTP 状态码(网络层失败时为 null)
  final int? statusCode;

  const MaterialSourceException({
    required this.sourceLabel,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() =>
      '【$sourceLabel】$message${statusCode == null ? '' : '(HTTP $statusCode)'}';
}

/// 内容源服务:清单 + 列表页 + 详情页。
///
/// ## 怎么调
/// 网络方法([listItems]/[fetchDocument]/[fetchGutenberg]/[fetchWikipedia]/
/// [fetchArxiv])是**实例方法**,统一通过单例 [instance] 调用:
/// ```dart
/// final items = await MaterialSourceService.instance.listItems('npr');
/// final doc = await MaterialSourceService.instance
///     .fetchDocument('gutenberg', url: 'https://www.gutenberg.org/ebooks/1342');
/// ```
/// 纯函数([sources]/[feedUrlOf]/[gutenbergChunks]/[chunkByWords]…)都是 static,
/// 直接 `MaterialSourceService.xxx` 调用。
///
/// 为什么是"私有构造 + 单例"而不是全 static:网络方法保留实例形态,将来可以用
/// [debugInjectDio] 注入替身做集成测试(全 static 就没法替换);而单例保证
/// 全局只有一份 Dio/连接池 —— 每个页面各 new 一个会重复建连接。
///
/// 网络走 [Dio](UA 标识 + 20s 超时),解析全部交给纯函数
/// ([HtmlText] / [FeedParser] / [MaterialSourceService.chunkByWords]),
/// 因此解析逻辑可以在不联网的前提下单测。
class MaterialSourceService {
  MaterialSourceService._();

  /// 全局唯一的服务实例(UI/阅读器一律用它调网络方法)
  static final MaterialSourceService instance = MaterialSourceService._();

  /// UA 标识:公开接口对"匿名脚本"和"有身份的客户端"待遇不同,
  /// 带上来源与用途是抓公开内容的基本礼节(也便于对方封禁时能联系到人)。
  static const String userAgent = 'ReadFlow/2.0 (personal study app)';

  static const Duration timeout = Duration(seconds: 20);

  /// 大文件(公版书全文)专用超时:实测 `pg1342.txt`(614KB)首包 26 秒,
  /// 用默认 20 秒必然失败 —— 而这不是"源挂了",是整本书本来就大。
  static const Duration longFetchTimeout = Duration(seconds: 90);

  /// 列表页默认抓多少条
  static const int defaultListLimit = 12;

  /// 切块目标词数(书按章节切不出来时的兜底粒度)
  static const int defaultChunkWords = 4000;

  /// 章节内超过该词数才二次切分,避免"一章被切成两块只有 300 词"的碎片
  static const int chapterSplitThreshold = 6000;

  static Dio? _dio;

  /// 懒加载 Dio:全进程一个实例,复用连接。
  static Dio get dio {
    final existing = _dio;
    if (existing != null) return existing;
    final created = Dio(
      BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': userAgent,
          'Accept-Language': 'en,zh-CN;q=0.8',
        },
      ),
    );
    _dio = created;
    return created;
  }

  /// 测试用:注入替身 Dio(默认实例不联网时也不会被创建)。
  static void debugInjectDio(Dio? d) => _dio = d;

  // ─────────────────────────── 内容源清单 ───────────────────────────
  //
  // 全部为公开 RSS / 公开页面,无需 API key、无需登录。
  // 可达性实测(2026-09,中国大陆网络):NPR / Project Gutenberg / arXiv 直连正常;
  // BBC Learning English / VOA / TED(feedburner) / Wikipedia 超时不可达。
  // 不可达不是代码问题,异常信息里会区分开(见 [_networkError])。
  static const List<MaterialSource> sources = [
    MaterialSource(
      id: 'bbc_le',
      label: 'BBC Learning English',
      kind: 'podcast',
      description: 'BBC 英语教学节目(6 Minute English 等),每期几分钟,配音频与文字稿',
      license: 'BBC 版权内容,仅限个人学习收听/阅读,请勿再分发或商用',
      hasAudio: true,
    ),
    MaterialSource(
      id: 'voa_le',
      label: 'VOA Learning English',
      kind: 'podcast',
      description: '美国之音慢速英语,语速慢、词汇受控,适合初中级听力与泛读',
      license: '美国之音(VOA)为美国联邦政府资助的公共领域内容,一般可自由使用;'
          '第三方素材(音乐/图片)除外',
      hasAudio: true,
    ),
    MaterialSource(
      id: 'npr',
      label: 'NPR News',
      kind: 'news',
      description: '美国国家公共电台新闻(Up First 等),真实语速的时事报道',
      license: 'NPR 版权内容,仅限个人学习使用;原文链接与署名必须保留',
      // 实测:`feeds.npr.org/1001/rss.xml` 的条目里**没有** `<enclosure>`
      // (逐条检查过),所以这条源目前只提供文字,不提供音频 —— 元数据不能
      // 谎报能力,否则"听力材料"筛选会给出点开没声音的结果。
      // TODO(v2.x 听力):改用 NPR 的单节目播客订阅(带 enclosure)拿音频,
      // 例如 Up First;需要先确认具体 feed id,不要凭印象写死。
      hasAudio: false,
    ),
    MaterialSource(
      id: 'ted',
      label: 'TED Talks',
      kind: 'podcast',
      description: 'TED 演讲音频,主题广、口语化,适合精听与表达积累',
      license: 'TED 演讲采用 CC BY-NC-ND 许可(署名-非商业-禁止演绎),'
          '仅供个人学习,不得商用或改编再分发',
      hasAudio: true,
    ),
    MaterialSource(
      id: 'gutenberg',
      label: 'Project Gutenberg(公版书)',
      kind: 'book',
      description: '5 万余本版权过期的公版书全文(TXT),按章节切块,适合长篇泛读',
      license: '公版书(Project Gutenberg License):在美国境内可自由复制、'
          '分发;若你不在美国,请先确认当地法律。保留本出处说明',
      hasAudio: false,
    ),
    MaterialSource(
      id: 'wikipedia',
      label: 'Wikipedia(维基百科)',
      kind: 'wiki',
      description: '百科条目正文,信息密度高、句式规整,适合精读与背景知识补充',
      license: '维基百科文本采用 CC BY-SA 4.0 许可(署名-相同方式共享),'
          '个人学习使用请保留条目链接与署名',
      hasAudio: false,
    ),
    MaterialSource(
      id: 'arxiv',
      label: 'arXiv(论文摘要)',
      kind: 'paper',
      description: '预印本论文摘要,学术英语的真实语料,写作/考研阅读的进阶材料',
      license: 'arXiv 预印本版权归作者所有;仅取公开摘要页供个人学习,'
          '不下载或再分发 PDF',
      hasAudio: false,
    ),
  ];

  /// 按 id 找源(找不到返回 null;不要抛,调用方要能优雅提示"未知来源")
  static MaterialSource? sourceOf(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// **默认源**(v2.2 修"材料中心没法用")。
  ///
  /// 旧实现取 `sources.first`(BBC Learning English)—— 而 BBC/VOA/TED/Wikipedia
  /// 在中国大陆**实测全部超时**,于是用户打开材料中心的第一屏必然是失败,
  /// 看起来像"功能坏了"。默认值必须选**实测可达**的:NPR 新闻。
  ///
  /// 更进一步的兜底在 [MaterialSourceStatus]:一旦用户手动切到别的源并成功,
  /// 下次就默认落到那个源(见 `MaterialSourceStatus.preferredSourceId`)。
  static const String defaultSourceId = 'npr';

  /// 实测可达的源(2026-09-24,中国大陆家庭宽带):
  ///   npr 200/2.7s、arxiv 200/0.9s、gutenberg 200/26s(首包慢,已单独放宽超时);
  ///   bbc_le / voa_le / ted / wikipedia 9 秒无响应。
  /// 界面上给这些源打"实测可用"标记,是为了让用户**一眼知道该点哪个**,
  /// 不用靠一个个试错(试错成本是每次 9~20 秒的等待)。
  static const Set<String> measuredReachable = {'npr', 'arxiv', 'gutenberg'};

  /// 未知 sourceId 时的统一异常(带可选值,便于排查打错的 id)
  static MaterialSourceException unknownSource(String sourceId) =>
      MaterialSourceException(
        sourceLabel: '材料中心',
        message: '未知的内容源「$sourceId」,可用来源:'
            '${sources.map((s) => s.id).join('/')}',
      );

  // ─────────────────────── URL 组装(纯函数,可单测) ───────────────────────

  /// 某源的订阅/列表地址(RSS 或 Atom)。
  static String? feedUrlOf(String sourceId) {
    switch (sourceId) {
      case 'bbc_le':
        return 'https://feeds.bbci.co.uk/learningenglish/english/features/'
            '6-minute-english/rss.xml';
      case 'voa_le':
        // TODO(可达性待验证):VOA 用自研的 `/api/{token}` 集合接口当 RSS,
        // token 形如 `zrqiteu-$i`(常被社区文档引用),但本开发环境访问
        // learningenglish.voanews.com 全部超时,无法确认该 token 是否仍有效。
        // 兜底方案:抓 `https://learningenglish.voanews.com/` 首页 HTML 里的
        // 文章链接(见 [fetchDocument] 的 `_web_html` 分支),不依赖该 token。
        // 若上线后发现此地址 404,把这里换成有效的集合 token 即可,解析逻辑不用改。
        return r'https://learningenglish.voanews.com/api/zrqiteu-$i';
      case 'npr':
        return 'https://feeds.npr.org/1001/rss.xml';
      case 'ted':
        return 'https://feeds.feedburner.com/TEDTalks_audio';
      case 'gutenberg':
        // 古腾堡有"最新发布"订阅,但真正好用的是 Top 100 书单页(RSS 里只有书名)
        return 'https://www.gutenberg.org/cache/epub/feeds/today.rss';
      case 'wikipedia':
        // 没有真正意义的"订阅源":用"随机条目"接口当推荐池(每次调用不同)
        return 'https://en.wikipedia.org/api/rest_v1/page/random/summary';
      case 'arxiv':
        return 'https://rss.arxiv.org/rss/cs.CL';
      default:
        return null;
    }
  }

  /// 某源某条目的详情地址绝对化;部分源还能把裸 id 拼成 URL。
  static String? documentUrlOf(String sourceId, {required String url}) {
    switch (sourceId) {
      case 'gutenberg':
        final id = gutenbergIdOf(url);
        return id == null ? null : gutenbergTextUrl(id);
      case 'wikipedia':
        return url.isEmpty ? null : url;
      case 'arxiv':
        final id = arxivIdOf(url);
        return id == null ? null : 'https://arxiv.org/abs/$id';
      default:
        return url.isEmpty ? null : url;
    }
  }

  /// 公版书全文 TXT 地址(纯函数)
  static String gutenbergTextUrl(int bookId) =>
      'https://www.gutenberg.org/cache/epub/$bookId/pg$bookId.txt';

  /// README / 元数据地址(用于取书名、作者、语言)
  static String gutenbergMetaUrl(int bookId) =>
      'https://www.gutenberg.org/ebooks/$bookId';

  /// 从任意写法的 Gutenberg URL 里抠出书籍 id;
  /// 支持 `…/ebooks/1342`、`…/files/1342/…`、`…/cache/epub/1342/pg1342.txt`、裸 `1342`。
  static int? gutenbergIdOf(String url) {
    final s = url.trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(s)) return int.tryParse(s);
    for (final re in [
      RegExp(r'/ebooks/(\d+)'),
      RegExp(r'/files/(\d+)'),
      RegExp(r'/epub/(\d+)'),
      RegExp(r'\bpg(\d+)\.txt'),
      RegExp(r'[?&]id=(\d+)'),
    ]) {
      final m = re.firstMatch(s);
      final id = m == null ? null : int.tryParse(m.group(1)!);
      if (id != null && id > 0) return id;
    }
    return null;
  }

  /// 维基百科纯文本接口(action=query&prop=extracts&explaintext=1)。
  /// 比 `rest_v1/page/summary` 强的地方:返回**整篇正文**而不只是导语。
  static String wikipediaApiUrl(String title, {String lang = 'en'}) {
    final t = Uri.encodeQueryComponent(title.trim().replaceAll(' ', '_'));
    return 'https://$lang.wikipedia.org/w/api.php'
        '?action=query&prop=extracts&explaintext=1&redirects=1'
        '&exlimit=1&format=json&formatversion=2&titles=$t';
  }

  /// 从维基 URL 里猜语言代码(zh/en/simple…),猜不到按 en
  static String wikipediaLangOf(String url) {
    final m = RegExp(r'^https?://([a-z\-]+)\.wikipedia\.org', caseSensitive: false)
        .firstMatch(url.trim());
    return m?.group(1)?.toLowerCase() ?? 'en';
  }

  /// 规范 arXiv id:允许传 `1706.03762`、`1706.03762v5`、完整 abs/pdf 链接
  static String? arxivIdOf(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final m = RegExp(
      r'(?:arxiv\.org/(?:abs|pdf)/)?(\d{4}\.\d{4,5})(v\d+)?',
      caseSensitive: false,
    ).firstMatch(s);
    if (m != null) return m.group(1);
    // 老式 id:cs.CL/0301001 这类
    final old = RegExp(r'([a-z\-]+(?:\.[A-Z]{2})?/\d{7})(v\d+)?')
        .firstMatch(s);
    return old?.group(1);
  }

  // ─────────────────────────── 列表页 ───────────────────────────

  /// 抓某源的**最新条目清单**(不下载正文),供"今日推荐"选材。
  ///
  /// - 按最终链接去重(同一个故事在订阅里可能重复出现);
  /// - 丢掉没有任何链接的条目(点了也没法用);
  /// - wikipedia 的 random/summary 返回的是 JSON 不是 XML —— 单独处理。
  Future<List<FeedItem>> listItems(String sourceId, {int limit = 12}) async {
    final source = sourceOf(sourceId);
    if (source == null) throw unknownSource(sourceId);
    final url = feedUrlOf(sourceId);
    if (url == null || url.isEmpty) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '该来源暂不支持列表浏览,请直接输入链接/ID 抓取',
      );
    }
    final body = await _getText(url, source);

    var items = <FeedItem>[];
    if (sourceId == 'wikipedia') {
      final one = _wikiRandomToItem(body, source);
      if (one != null) items.add(one);
    } else {
      items = FeedParser.parse(body);
    }

    final out = <FeedItem>[];
    final seen = <String>{};
    for (final it in items) {
      if (it.link.trim().isEmpty) continue;
      if (!seen.add(it.link)) continue;
      out.add(it);
      if (out.length >= limit) break;
    }
    if (out.isEmpty) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '订阅源里没有解析出任何条目(可能是源站改版,或该源在本地网络不可达)',
      );
    }
    return out;
  }

  // ─────────────────────────── 详情页 ───────────────────────────

  /// 按 URL/ID 抓一份可学习材料并切块。
  ///
  /// 分派规则(按源):
  /// - `gutenberg` → 全文 TXT,按章节切块([fetchGutenberg]);
  /// - `wikipedia` → action=query 纯文本([fetchWikipedia]);
  /// - `arxiv` → 摘要页([fetchArxiv]);
  /// - `bbc_le`/`voa_le`/`npr`/`ted` → 抓公开文章页,用 [HtmlText.readableText] 抽正文;
  ///   若条目带音频(订阅里有 `<enclosure>`),音频地址由调用方从 [FeedItem] 传进来。
  Future<MaterialDoc> fetchDocument(
    String sourceId, {
    required String url,
    String? id,
  }) async {
    final source = sourceOf(sourceId);
    if (source == null) throw unknownSource(sourceId);
    switch (sourceId) {
      case 'gutenberg':
        final bookId = gutenbergIdOf(id ?? url);
        if (bookId == null) {
          throw MaterialSourceException(
            sourceLabel: source.label,
            message: '这不是一个公版书 id 或链接,无法定位全文(示例:1342 或 '
                'https://www.gutenberg.org/ebooks/1342)',
          );
        }
        return fetchGutenberg(bookId);
      case 'wikipedia':
        final title = (id ?? '').trim().isNotEmpty ? id!.trim() : _wikiTitleOf(url);
        if (title.isEmpty) {
          throw MaterialSourceException(
            sourceLabel: source.label,
            message: '缺少条目名(请传 title,或用 /wiki/条目名 形式的链接)',
          );
        }
        return fetchWikipedia(title, lang: wikipediaLangOf(url));
      case 'arxiv':
        final arxivId = arxivIdOf(id ?? url);
        if (arxivId == null) {
          throw MaterialSourceException(
            sourceLabel: source.label,
            message: '无法从「$url」识别 arXiv 编号(示例:1706.03762)',
          );
        }
        return fetchArxiv(arxivId);
      default:
        return _fetchWebArticle(source, url.isEmpty ? (id ?? '') : url);
    }
  }

  // ─────────────────────── Project Gutenberg ───────────────────────

  /// 按书籍 id 抓全文并按章节切块。
  ///
  /// Gutenberg 的 .txt 结构非常规整,是这一层里最可靠的解析对象:
  /// - 正文被 `*** START OF THE PROJECT GUTENBERG EBOOK … ***` /
  ///   `*** END OF … ***` 夹住,两头是许可说明 —— **必须切掉**,否则会被当成
  ///   正文切成一堆法律条文块;
  /// - 头部有 `Title:` / `Author:` / `Language:` 行,直接当元数据用;
  /// - 章节标题是 `CHAPTER I.` / `Chapter 1` / `CHAPTER XII.` 这种独立行,按它切。
  ///   切不出来(诗集、短篇集、没有章节标记)就按 ~4000 词一块兜底。
  Future<MaterialDoc> fetchGutenberg(int bookId) async {
    final source = sourceOf('gutenberg')!;
    if (bookId <= 0) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '书籍 id 不合法:$bookId',
      );
    }
    // 整本书全文:用长超时(实测首包 26 秒)
    final raw = await _getText(gutenbergTextUrl(bookId), source, longFetch: true);
    var text = raw;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    if (text.trim().isEmpty) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '书籍 #$bookId 的全文是空的(可能该书只提供 HTML/EPUB,'
            '或该书号不存在)',
      );
    }

    final body = gutenbergBody(text);
    final header = gutenbergHeader(text);
    final chunks = gutenbergChunks(body, wordsPerChunk: defaultChunkWords);
    if (chunks.isEmpty) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '书籍 #$bookId 解析后没有正文(该书的 TXT 结构可能是特殊排版)',
      );
    }
    final title = (header['title'] ?? '').isNotEmpty
        ? header['title']!
        : 'Project Gutenberg #$bookId';
    final lang = (header['language'] ?? 'en').toLowerCase();
    return MaterialDoc(
      sourceId: source.id,
      sourceId2: '$bookId',
      kind: source.kind,
      title: title,
      author: header['author'] ?? '',
      url: 'https://www.gutenberg.org/ebooks/$bookId',
      license: source.license,
      language: lang.startsWith('en') ? 'en' : lang,
      chunks: chunks,
      plainText: chunks.map((c) => c.text).join('\n\n'),
    );
  }

  /// 切出 `*** START … ***` 与 `*** END … ***` 之间的正文(纯函数)。
  /// 标记缺失时返回去掉头部许可说明后的全文(保守:宁可多留正文)。
  static String gutenbergBody(String text) {
    final s = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final start = RegExp(r'\*\*\*\s*START OF (?:THE|THIS) PROJECT GUTENBERG[^\n]*\*\*\*',
            caseSensitive: false)
        .firstMatch(s);
    final end = RegExp(r'\*\*\*\s*END OF (?:THE|THIS) PROJECT GUTENBERG[^\n]*\*\*\*',
            caseSensitive: false)
        .firstMatch(s);
    var body = s;
    if (start != null) {
      body = s.substring(start.end);
    }
    if (end != null && end.start > (start?.end ?? 0)) {
      body = body.substring(0, end.start - (start?.end ?? 0));
    }
    return body.trim();
  }

  /// 抽取头部元数据(Title/Author/Language,纯函数)。
  /// 只看 START 标记**之前**的部分,避免正文里的 "Author:" 之类误命中。
  static Map<String, String> gutenbergHeader(String text) {
    final s = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final marker = RegExp(r'\*\*\*\s*START OF', caseSensitive: false).firstMatch(s);
    final head = marker == null ? '' : s.substring(0, marker.start);
    final out = <String, String>{};
    void grab(String key, String label) {
      final m = RegExp('^\\s*$label:\\s*(.+?)\\s*\$', caseSensitive: false, multiLine: true)
          .firstMatch(head);
      if (m != null && m.group(1)!.trim().isNotEmpty) {
        out[key] = m.group(1)!.trim();
      }
    }

    grab('title', 'Title');
    grab('author', 'Author');
    grab('language', 'Language');
    // 老式排版把书名作者放在 START 之后的第一段(Title: 行缺失时的兜底)
    if (out['title'] == null) {
      final m = RegExp(r'^\s*Title:\s*(.+)$', caseSensitive: false, multiLine: true)
          .firstMatch(s);
      if (m != null) out['title'] = m.group(1)!.trim();
    }
    return out;
  }

  /// 按章节标题切块(纯函数,可单测)。
  ///
  /// 章节正则要求**整行**匹配:`^\s*(CHAPTER|Chapter|BOOK|PART|卷)\s*([0-9IVXLCDM]+)\.?`
  /// - 整行匹配是关键:目录页常有 `Chapter I. ...... 5` 这种带页码的行,
  ///   它前面有前导点号,不满足"点号后直接行尾",自然被排除(虽然可能连真正的
  ///   标题也被排除 —— 那种情况下会退回按词数切,仍是可用的材料);
  /// - 章节数 < 2 时视为"没切出章节",退回按 ~[wordsPerChunk] 词分块。
  static List<MaterialChunk> gutenbergChunks(
    String body, {
    int wordsPerChunk = 4000,
  }) {
    final text = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return const [];
    final lines = text.split('\n');
    final heads = <({int line, String title})>[];
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.isEmpty || t.length > 80) continue;
      if (_chapterHeading.hasMatch(t)) heads.add((line: i, title: t));
    }
    if (heads.length < 2) return chunkByWords(text, wordsPerChunk: wordsPerChunk);

    final chunks = <MaterialChunk>[];
    // 第一个章节标题之前的内容(序言/献词)单独成块 —— 丢掉会让人以为书缺了一段
    final preface = _paragraphizeLines(lines.sublist(0, heads.first.line));
    if (preface.trim().isNotEmpty) {
      chunks.add(MaterialChunk(index: 1, title: '前言', text: preface.trim()));
    }
    for (var h = 0; h < heads.length; h++) {
      final from = heads[h].line + 1;
      final to = h + 1 < heads.length ? heads[h + 1].line : lines.length;
      final bodyText = _paragraphizeLines(lines.sublist(from, to));
      if (bodyText.trim().isEmpty) continue; // 空章节(只有标题行的目录项)跳过
      final pieces = chunkByWords(
        bodyText,
        wordsPerChunk: wordsPerChunk,
        splitOnlyAbove: chapterSplitThreshold,
      );
      for (var p = 0; p < pieces.length; p++) {
        chunks.add(
          MaterialChunk(
            index: chunks.length + 1,
            title: pieces.length > 1
                ? '${heads[h].title}(${p + 1}/${pieces.length})'
                : heads[h].title,
            text: pieces[p].text,
          ),
        );
      }
    }
    if (chunks.isEmpty) return chunkByWords(text, wordsPerChunk: wordsPerChunk);
    return chunks;
  }

  static final RegExp _chapterHeading = RegExp(
    r'^(?:chapter|book|part|volume)\s+[0-9IVXLCDM]+\b[^\n]{0,40}$',
    caseSensitive: false,
  );

  // ─────────────────────────── 通用切块 ───────────────────────────

  /// 按词数切块(纯函数,可单测):每块约 [wordsPerChunk] 个词,尽量落在段落边界。
  ///
  /// [splitOnlyAbove]:全文不超过它时**不切** —— 免得把一篇 4200 词的文章切成
  /// "4000 + 200" 这种毫无意义的碎片。默认 0 表示总是按上限切。
  static List<MaterialChunk> chunkByWords(
    String text, {
    int wordsPerChunk = 4000,
    int splitOnlyAbove = 0,
  }) {
    final t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (t.isEmpty) return const [];
    final limit = wordsPerChunk <= 0 ? defaultChunkWords : wordsPerChunk;
    if (splitOnlyAbove > 0 && _countWords(t) <= splitOnlyAbove) {
      return [MaterialChunk(index: 1, text: t)];
    }
    final paras = t
        .split(RegExp(r'\n\s*\n'))
        .map((p) => _paragraphize(p))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (paras.isEmpty) return [MaterialChunk(index: 1, text: t)];

    final out = <MaterialChunk>[];
    final buf = <String>[];
    var count = 0;
    void flush() {
      if (buf.isEmpty) return;
      out.add(MaterialChunk(index: out.length + 1, text: buf.join('\n\n')));
      buf.clear();
      count = 0;
    }

    for (final p in paras) {
      final w = _countWords(p);
      // 单段就超限(公版书里几百行的长段很常见):先落盘已有的,再按词硬切
      if (w > limit) {
        flush();
        for (final piece in _splitLongParagraph(p, limit)) {
          out.add(MaterialChunk(index: out.length + 1, text: piece));
        }
        continue;
      }
      if (count + w > limit && buf.isNotEmpty) flush();
      buf.add(p);
      count += w;
    }
    flush();
    if (out.isEmpty) return [MaterialChunk(index: 1, text: t)];
    return out;
  }

  static int _countWords(String s) =>
      s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  /// 超长段落按词数硬切(只在找不到段落边界时兜底),切点保持句内不裂得太碎
  static List<String> _splitLongParagraph(String p, int limit) {
    final words = p.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final out = <String>[];
    for (var i = 0; i < words.length; i += limit) {
      final end = (i + limit) > words.length ? words.length : i + limit;
      out.add(words.sublist(i, end).join(' '));
    }
    return out;
  }

  /// 按空行把多行文本收敛成段落(保留段内换行为空格)
  static String _paragraphize(String s) => s
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .join(' ')
      .trim();

  static String _paragraphizeLines(List<String> lines) {
    final out = <String>[];
    final buf = <String>[];
    void flush() {
      if (buf.isEmpty) return;
      out.add(buf.join(' ').trim());
      buf.clear();
    }

    for (final l in lines) {
      if (l.trim().isEmpty) {
        flush();
      } else {
        buf.add(l.trim());
      }
    }
    flush();
    return out.where((p) => p.isNotEmpty).join('\n\n');
  }

  // ─────────────────────────── Wikipedia ───────────────────────────

  /// 用 action=query&prop=extracts&explaintext=1 取**纯文本正文**并切块。
  ///
  /// 为什么不用 `rest_v1/page/summary`:那个只给导语(一到两段),
  /// 拿来做"一份材料"太短;`extracts` 给整篇,且 `explaintext=1` 已去掉维基标记。
  ///
  /// 返回内容是**纯文本**,所以这里不走 [HtmlText],直接按段落/小标题切块
  /// (维基的小标题在纯文本里是独立成行的 `== 标题 ==`)。
  Future<MaterialDoc> fetchWikipedia(String title, {String lang = 'en'}) async {
    final source = sourceOf('wikipedia')!;
    final t = title.trim();
    if (t.isEmpty) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '条目名不能为空',
      );
    }
    final body = await _getText(wikipediaApiUrl(t, lang: lang), source);
    final parsed = wikipediaExtractOf(body);
    if (parsed.text.trim().isEmpty) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: parsed.missing
            ? '找不到条目「$t」($lang 维基),请检查拼写;'
                '若该语言站点在本地网络不可达,请换用其它来源'
            : '条目「$t」没有可提取的正文(可能是消歧义页或纯列表页)',
      );
    }
    final pageTitle = parsed.title.isEmpty ? t : parsed.title;
    final chunks = _wikiChunks(parsed.text, pageTitle);
    return MaterialDoc(
      sourceId: source.id,
      sourceId2: '$lang:$pageTitle',
      kind: source.kind,
      title: pageTitle,
      url: 'https://$lang.wikipedia.org/wiki/'
          '${Uri.encodeComponent(pageTitle.replaceAll(' ', '_'))}',
      license: source.license,
      language: lang,
      chunks: chunks,
      plainText: chunks.map((c) => c.text).join('\n\n'),
    );
  }

  /// 解析 `action=query&prop=extracts&formatversion=2` 的 JSON(纯函数)。
  ///
  /// 为什么手写抽取而不用 `jsonDecode`:extract 是**长文本**,用
  /// `RegExp(r'"extract"\s*:\s*"((?:[^"\\]|\\.)*)"')` 抠出转义后的原文再交给
  /// `jsonDecode` 反转义,比手工处理 `\n`/`\uXXXX`/`\"` 可靠得多。
  /// [missing] 为 true 表示接口明确说"页面不存在"(`"missing":true`),
  /// 调用方据此给出"拼写错误"而不是"内容为空"的提示。
  static ({String title, String text, bool missing}) wikipediaExtractOf(
    String json,
  ) {
    if (json.trim().isEmpty) return (title: '', text: '', missing: false);
    // 页面不存在
    if (RegExp(r'"missing"\s*:\s*(?:true|"")').hasMatch(json) &&
        !RegExp(r'"extract"\s*:').hasMatch(json)) {
      return (title: '', text: '', missing: true);
    }
    final title = _jsonStringField(json, 'title');
    final extract = _jsonStringField(json, 'extract');
    return (title: title, text: extract.replaceAll('\u0001', ''), missing: false);
  }

  /// 抠出 JSON 里某个字符串字段的**真实值**(已反转义)。取不到返回空串。
  static String _jsonStringField(String json, String field) {
    final re = RegExp('"$field"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"');
    final m = re.firstMatch(json);
    if (m == null) return '';
    try {
      final decoded = jsonDecode('"${m.group(1)}"');
      return decoded is String ? decoded : '';
    } catch (_) {
      return m.group(1)!;
    }
  }

  /// 维基纯文本切块:小标题(`== X ==`,explaintext 会保留)优先当块标题;
  /// 单个小节太长时再按词数切。没有小标题就整体按词数切。
  static List<MaterialChunk> _wikiChunks(String text, String pageTitle) {
    final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final heads = <({int line, String title})>[];
    final headRe = RegExp(r'^\s*(={2,6})\s*(.+?)\s*\1\s*$');
    for (var i = 0; i < lines.length; i++) {
      final m = headRe.firstMatch(lines[i]);
      if (m != null) heads.add((line: i, title: m.group(2)!.trim()));
    }
    if (heads.isEmpty) return chunkByWords(text, wordsPerChunk: defaultChunkWords);

    final out = <MaterialChunk>[];
    void push(String? title, String body) {
      final pieces = chunkByWords(
        body,
        wordsPerChunk: defaultChunkWords,
        splitOnlyAbove: chapterSplitThreshold,
      );
      for (var p = 0; p < pieces.length; p++) {
        out.add(
          MaterialChunk(
            index: out.length + 1,
            title: pieces.length > 1 ? '$title(${p + 1}/${pieces.length})' : title,
            text: pieces[p].text,
          ),
        );
      }
    }

    final lead = _paragraphizeLines(lines.sublist(0, heads.first.line));
    if (lead.trim().isNotEmpty) push('简介', lead);
    for (var h = 0; h < heads.length; h++) {
      final from = heads[h].line + 1;
      final to = h + 1 < heads.length ? heads[h + 1].line : lines.length;
      final body = _paragraphizeLines(lines.sublist(from, to));
      if (body.trim().isEmpty) continue;
      push(heads[h].title, body);
    }
    if (out.isEmpty) {
      return chunkByWords(text, wordsPerChunk: defaultChunkWords);
    }
    return out;
  }

  /// 从维基链接里取条目名(`/wiki/English_language` → `English language`)
  static String _wikiTitleOf(String url) {
    final m = RegExp(r'/wiki/([^?#]+)').firstMatch(url);
    if (m == null) return '';
    return Uri.decodeComponent(m.group(1)!).replaceAll('_', ' ').trim();
  }

  /// `rest_v1/page/random/summary` 的 JSON → [FeedItem]
  FeedItem? _wikiRandomToItem(String json, MaterialSource source) {
    final title = _jsonStringField(json, 'title');
    if (title.trim().isEmpty) return null;
    var url = '';
    try {
      final m = RegExp(r'"content_urls"\s*:\s*\{[\s\S]*?"page"\s*:\s*\{[\s\S]*?"url"\s*:\s*"([^"]+)"')
          .firstMatch(json);
      url = m == null ? '' : m.group(1)!;
    } catch (_) {
      url = '';
    }
    if (url.isEmpty) {
      url = 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}';
    }
    return FeedItem(
      title: title,
      link: url,
      summary: _jsonStringField(json, 'extract'),
      guid: _jsonStringField(json, 'pageid'),
      published: _jsonStringField(json, 'timestamp'),
    );
  }

  // ─────────────────────────── arXiv ───────────────────────────

  /// 取摘要页的标题/作者/摘要(**不下载 PDF**)。
  ///
  /// arXiv 的 abs 页面是**服务端渲染**的,信息有两份:
  /// - `<meta name="citation_title">` / `citation_author` / `citation_abstract`(最稳);
  /// - 可见的 `<h1 class="title">` 与 `<blockquote class="abstract">`(元数据缺失时的兜底)。
  /// 两份都拿不到就抛异常(而不是返回只有标题的空文档)。
  Future<MaterialDoc> fetchArxiv(String arxivId) async {
    final source = sourceOf('arxiv')!;
    final id = arxivIdOf(arxivId) ?? arxivId.trim();
    if (id.isEmpty) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: 'arXiv 编号不能为空(示例:1706.03762)',
      );
    }
    final url = 'https://arxiv.org/abs/$id';
    final html = await _getText(url, source);

    var title = _metaOf(html, 'citation_title');
    if (title.isEmpty) {
      title = HtmlText.stripTags(_firstGroupOf(
            RegExp(r'<h1[^>]*class="[^"]*title[^"]*"[^>]*>([\s\S]*?)</h1>',
                caseSensitive: false),
            html,
          ) ??
          '');
      title = title.replaceFirst(RegExp(r'^Title:\s*', caseSensitive: false), '').trim();
    }
    final authors = <String>[];
    for (final m in RegExp(r'<meta\s+name="citation_author"\s+content="([^"]*)"',
            caseSensitive: false)
        .allMatches(html)) {
      final a = HtmlText.decodeEntities(m.group(1)!).trim();
      if (a.isNotEmpty) authors.add(a);
    }

    var abstract = _metaOf(html, 'citation_abstract');
    if (abstract.isEmpty) {
      final block = _firstGroupOf(
        RegExp(r'<blockquote[^>]*class="[^"]*abstract[^"]*"[^>]*>([\s\S]*?)</blockquote>',
            caseSensitive: false),
        html,
      );
      abstract = HtmlText.stripTags(block ?? '')
          .replaceFirst(RegExp(r'^Abstract:\s*', caseSensitive: false), '')
          .trim();
    }
    if (abstract.isEmpty) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '论文 $id 的摘要页解析不出摘要(arXiv 若改版需同步更新解析规则)',
      );
    }
    final chunks = <MaterialChunk>[
      MaterialChunk(index: 1, title: title.isEmpty ? 'Abstract' : title, text: abstract),
    ];
    return MaterialDoc(
      sourceId: source.id,
      sourceId2: id,
      kind: source.kind,
      title: title.isEmpty ? 'arXiv:$id' : title,
      author: authors.join(', '),
      url: url,
      license: source.license,
      language: 'en',
      chunks: chunks,
      plainText: abstract,
    );
  }

  /// 取 `<meta name="…" content="…">`(属性顺序任意,纯函数)
  static String _metaOf(String html, String name) {
    final nameRe = RegExp(r'''name\s*=\s*(?:"([^"]*)"|'([^']*)')''');
    final contentRe = RegExp(r'''content\s*=\s*(?:"([^"]*)"|'([^']*)')''');
    for (final m in RegExp(r'<meta\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final tag = m.group(0)!;
      final nm = nameRe.firstMatch(tag);
      if (nm == null) continue;
      if ((nm.group(1) ?? nm.group(2) ?? '').toLowerCase() != name.toLowerCase()) {
        continue;
      }
      final cm = contentRe.firstMatch(tag);
      if (cm == null) continue;
      final content = (cm.group(1) ?? cm.group(2) ?? '').trim();
      if (content.isNotEmpty) return HtmlText.decodeEntities(content).trim();
    }
    return '';
  }

  static String? _firstGroupOf(RegExp re, String s) {
    for (final m in re.allMatches(s)) {
      return m.group(1);
    }
    return null;
  }

  // ─────────────────────── 通用网页正文(新闻/播客页) ───────────────────────

  /// 抓公开文章页:抽标题 + 正文,正文按词数切块。
  Future<MaterialDoc> _fetchWebArticle(MaterialSource source, String url) async {
    final abs = _absolutize(url, source);
    final html = await _getText(abs, source);
    var title = stripSiteSuffix(HtmlText.titleOf(html), abs);
    final text = _cleanArticleText(HtmlText.readableText(html));
    if (text.length < 120) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '页面正文抽取失败(只抽到 ${text.length} 个字符)。'
            '常见原因:该页正文由 JavaScript 动态渲染,或源站改版;'
            '可改用带文字稿的来源或换一篇',
      );
    }
    final chunks = chunkByWords(text, wordsPerChunk: 2500);
    return MaterialDoc(
      sourceId: source.id,
      sourceId2: _docIdOf(abs),
      kind: source.kind,
      title: title.isEmpty ? source.label : title,
      author: '',
      url: abs,
      license: source.license,
      language: 'en',
      chunks: chunks,
      plainText: chunks.map((c) => c.text).join('\n\n'),
    );
  }

  /// 去掉标题尾部的站点名(纯函数,可单测)。
  ///
  /// 页面标题几乎都带站点名尾巴,且各家分隔符不一样:`… : NPR`、
  /// `… | TED`、`… - BBC Learning English`。硬编码一张后缀表迟早漏 ——
  /// 这里改成**从 URL 推断站点名**再比对尾段:
  /// `https://www.npr.org/…` → 站点标记 `npr`,于是 `… : NPR` 被砍掉,
  /// 而正文标题里的冒号("Hydropower and the Himalayas: What does the future hold?")
  /// 不会被误伤 —— 因为尾段 `What does the future hold?` 不等于站点名。
  static String stripSiteSuffix(String title, String url) {
    final t = title.trim();
    if (t.isEmpty) return t;
    final names = _siteNamesOf(url);
    if (names.isEmpty) return t;
    for (final sep in const [': ', ' | ', ' - ', ' — ', ' – ']) {
      final i = t.lastIndexOf(sep);
      if (i <= 0) continue;
      final tail = t.substring(i + sep.length).trim().toLowerCase();
      if (tail.isEmpty || tail.length > 24) continue;
      for (final n in names) {
        if (tail == n || tail == '$n.com' || tail == '$n.org') {
          return t.substring(0, i).trim();
        }
        // "BBC Learning English" / "NPR News" 这类"站点名 + 栏目名"的尾巴:
        // 以站点名开头且不超过 4 个词时也砍掉。
        // 已知代价:极少数标题的副标题正好以站点名开头(如 "…: NPR reports from Kyiv")
        // 会被误砍。权衡后认为"标题里挂着站点名"更常见、更影响阅读,故保留此规则。
        if (tail.startsWith('$n ') && tail.split(' ').length <= 4) {
          return t.substring(0, i).trim();
        }
      }
    }
    return t;
  }

  /// 从 URL 推断站点标识:`https://www.npr.org/x` → ['npr', 'npr.org']。
  /// 取"去掉 www 与公共后缀之后剩下的最后一段",够用且不引依赖。
  static List<String> _siteNamesOf(String url) {
    final m = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://([^/?#]+)').firstMatch(url.trim());
    if (m == null) return const [];
    var host = m.group(1)!.toLowerCase();
    final colon = host.indexOf(':');
    if (colon > 0) host = host.substring(0, colon);
    var labels = host.split('.').where((l) => l.isNotEmpty).toList();
    if (labels.isNotEmpty && labels.first == 'www') labels = labels.sublist(1);
    const generic = {
      'com', 'org', 'net', 'edu', 'gov', 'io', 'co', 'uk', 'cn', 'us', 'me', 'tv',
    };
    while (labels.length > 1 && generic.contains(labels.last)) {
      labels.removeLast();
    }
    if (labels.isEmpty) return const [];
    final core = labels.last;
    if (core.isEmpty) return const [];
    return [core, host];
  }

  /// 正文清理(纯函数):删掉页面里的时间戳/播放器控件残留行。
  /// 播客/视频页的正文里常混进 `(00:00)`、`Media player`、`Download` 这类行,
  /// 留着会污染词频与难度统计。只删**整行匹配**的,不误伤正文里的括号时间。
  static String _cleanArticleText(String text) {
    final lines = text.split('\n');
    final out = <String>[];
    for (final raw in lines) {
      final l = raw.trim();
      if (l.isEmpty) continue;
      if (_noiseLine.hasMatch(l)) continue;
      out.add(l);
    }
    return out.join('\n\n').trim();
  }

  static final RegExp _noiseLine = RegExp(
    r'^(?:\(\d{1,2}:\d{2}(?::\d{2})?\)|'
    r'\d{1,2}:\d{2}(?::\d{2})?|'
    r'media player|download|share|subscribe|sign in|log in|sign up|'
    r'read more|watch now|listen now|play|pause|menu|search|'
    // 页面控件文案(skip-links/无障碍跳转条):真实 NPR/新闻站页头常驻这几条,
    // 它们不是链接也不是 <nav>,标签层拦不住,只能按文案整行丢
    r'accessibility links?|skip to main content|skip to content|'
    r'keyboard shortcuts?[^|]{0,40}|'
    r'copyright ©?.*|terms of use|privacy policy|advertisement)$',
    caseSensitive: false,
  );

  /// 源内 id:用 URL 的 path+query 当去重键(同一篇文章的多种跳转参数不影响)
  static String _docIdOf(String url) {
    final m = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://([^/?#]+)([\s\S]*)$').firstMatch(url);
    if (m == null) return url;
    return '${m.group(1)}${m.group(2)}';
  }

  /// 把可能的相对链接绝对化(订阅里偶尔给相对地址)
  static String _absolutize(String url, MaterialSource source) {
    final u = url.trim();
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    final feed = feedUrlOf(source.id) ?? '';
    if (feed.isEmpty) return u;
    return HtmlText.resolveUrl(u, feed);
  }

  // ─────────────────────────── 网络层 ───────────────────────────

  /// GET 文本。失败一律转成**中文可诊断**的 [MaterialSourceException]。
  ///
  /// **瞬时故障重试一次**:公版书全文有几百 KB(NPR/古腾堡实测:763KB 要 ~11 秒),
  /// 中途被 reset 一次就会让用户看到失败 —— 而重试几乎总能成功。只重试
  /// "连接被断/未知网络错"这两类(GET 幂等,重试无副作用);**超时不重试**,
  /// 否则用户要等两个 20 秒;4xx/5xx 也不重试(重试解决不了)。
  ///
  /// [longFetch] = 大文件(公版书全文):用 [longFetchTimeout] 覆盖默认 20 秒 ——
  /// 实测(2026-09-24)`pg1342.txt` 首包就要 26 秒,默认超时必然失败;
  /// 这不是网络坏,是"整本书"本来就慢,所以只给这一类放宽,不全局放宽
  /// (全局放宽会让 NPR 新闻卡在一个坏源上等一分钟)。
  Future<String> _getText(
    String url,
    MaterialSource source, {
    bool longFetch = false,
  }) async {
    if (url.trim().isEmpty) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '请求地址为空',
      );
    }
    final options = longFetch
        ? Options(receiveTimeout: longFetchTimeout)
        : null;
    Response<dynamic> resp;
    try {
      resp = await dio.get<dynamic>(url, options: options);
    } on DioException catch (e) {
      final retryable = e.type == DioExceptionType.connectionError ||
          (e.type == DioExceptionType.unknown && e.response == null);
      if (retryable) {
        try {
          resp = await dio.get<dynamic>(url, options: options);
        } on DioException catch (e2) {
          throw _networkError(e2, source, longFetch: longFetch);
        }
      } else {
        throw _networkError(e, source, longFetch: longFetch);
      }
    } catch (e) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '抓取失败:${_short(e.toString())}',
      );
    }
    final code = resp.statusCode ?? 0;
    final data = resp.data;
    final text = data is String ? data : (data == null ? '' : '$data');
    if (code >= 400 || code == 0) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '请求被拒绝或服务异常:${_short(text)}',
        statusCode: code == 0 ? null : code,
      );
    }
    if (text.trim().isEmpty) {
      throw MaterialSourceException(
        sourceLabel: source.label,
        message: '服务端返回了空内容(可能是反爬拦截或临时故障)',
        statusCode: code,
      );
    }
    return text;
  }

  /// DioException → 人话错误。**区分"网络不可达"与"源站返回错误"**:
  /// 中国大陆网络下 BBC/VOA/TED/Wikipedia 是不可直连的,用户看到
  /// "解析失败"会以为软件坏了,必须明确说是网络到不了。
  ///
  /// [longFetch] 也会影响**提示语**:大文件被掐断可以说"重试一次通常就好",
  /// 而列表/正文请求被掐断更可能是"这个源在你这儿连不上",说反了会把用户
  /// 引向错误的排查方向(实测 BBC 列表请求返回的就是 TLS 握手中断)。
  MaterialSourceException _networkError(
    DioException e,
    MaterialSource source, {
    bool longFetch = false,
  }) {
    final code = e.response?.statusCode;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      // transformTimeout 是 dio 5.10 新增的类型(响应体转换阶段超时),
      // 用户看到的现象和普通超时一样,归到同一类提示里
      case DioExceptionType.transformTimeout:
        return MaterialSourceException(
          sourceLabel: source.label,
          // 超时秒数要与实际用的那个超时一致(公版书全文是 90 秒,不是 20 秒)
          message: '连接超时(${(longFetch ? longFetchTimeout : timeout).inSeconds} 秒):'
              '该来源在当前网络下可能不可达,请检查网络或换一个来源',
        );
      case DioExceptionType.connectionError:
        return MaterialSourceException(
          sourceLabel: source.label,
          message: '网络不可达:无法连接该来源(部分地区需自备网络环境)。'
              'NPR / Project Gutenberg / arXiv 通常可直连',
        );
      case DioExceptionType.badCertificate:
        return MaterialSourceException(
          sourceLabel: source.label,
          message: '证书校验失败:连接可能被中间人劫持,已中止',
        );
      case DioExceptionType.cancel:
        return MaterialSourceException(
          sourceLabel: source.label,
          message: '请求已取消',
        );
      case DioExceptionType.badResponse:
        return MaterialSourceException(
          sourceLabel: source.label,
          message: _httpHint(code),
          statusCode: code,
        );
      case DioExceptionType.unknown:
        // `unknown` 是 dio 的"兜底"类型:底层可能是 SocketException(连接被对端
        // 掐断)、TLS 握手失败等。e.message 经常为空,必须把 e.error 也带上,
        // 否则用户(和排查的人)只看到"未知网络错误",完全无从下手 ——
        // 实测抓古腾堡 763KB 全文时中途被 reset 就是这种情况。
        //
        // 提示语分两种:列表/正文请求被掐断,最常见的原因是**源站在当前网络
        // 不可直连**(实测 BBC 的 TLS 握手直接被终止);只有"整本书全文"这种
        // 大文件才适合说"重试一次通常就好"。旧实现不分场景,导致用户请求一个
        // RSS 列表却被告知"大文件首次抓取可能被掐断",误导排查方向。
        final detail = [
          if ((e.message ?? '').trim().isNotEmpty) e.message!.trim(),
          if (e.error != null) '${e.error}'.trim(),
        ].join(' / ');
        return MaterialSourceException(
          sourceLabel: source.label,
          message: '网络中断:${_short(detail.isEmpty ? '连接被中断' : detail)}。'
              '${longFetch ? '大文件(公版书全文)首次抓取可能被中途掐断,重试一次通常就好' : '该来源在当前网络下可能不可直连(部分网络会重置连接),换一个来源或稍后重试'}',
        );
    }
  }

  static String _httpHint(int? code) {
    switch (code) {
      case 403:
        return '被拒绝访问(403):该来源可能限制非浏览器访问,或需要更换来源';
      case 404:
        return '内容不存在(404):链接可能已失效,或该书的 TXT/条目名写错了';
      case 429:
        return '请求太频繁(429):请稍后重试,不要连续刷新';
      case 500:
      case 502:
      case 503:
        return '服务端故障($code):源站临时不可用,请稍后重试';
    }
    return '源站返回异常状态码';
  }

  static String _short(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }
}
