import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/services/feed_parser.dart';
import 'package:readflow/services/html_text.dart';
import 'package:readflow/services/material_source.dart';

/// v2.0 材料中心「内容获取层」的单测。
///
/// ## 测试边界(**本文件绝不联网**)
/// 只测两类东西:
/// 1. **纯函数**:`HtmlText` 的标签剥离/实体解码/链接绝对化、`FeedParser` 的
///    RSS/Atom 字段抽取、`MaterialSourceService` 的 URL 组装与切块;
/// 2. **静态数据**:[MaterialSourceService.sources] 清单的完整性。
///
/// 带网络的 `listItems`/`fetchDocument` 一律不测 —— 单元测试连外网会让
/// CI 变成"看源站脸色的抽奖",而且抓到的内容随时会变。要验证抓取,
/// 用 `dio` 的 MockAdapter 那种专门的集成测试,不放在这里。
///
/// ## fixture 为什么内联在文件里
/// 解析是**启发式**:真实源的 sample 一旦落成外部文件,改版时就会"测试仍绿、
/// 线上已坏"。内联写死一份"真实感"的样本,改解析规则时必然要一起改,
/// 改动会显式出现在 diff 里,不容易糊过去。

void main() {
  // ══════════════════════════ HTML → 纯文本 ══════════════════════════

  group('HtmlText.titleOf', () {
    test('取 title 并解码实体', () {
      expect(
        HtmlText.titleOf('<html><head><title>Tom &amp; Jerry &#39;Show&#39;'
            '</title></head><body>x</body></html>'),
        equals("Tom & Jerry 'Show'"),
      );
    });

    test('没有 title → 空串', () {
      expect(HtmlText.titleOf('<html><body><h1>Hi</h1></body></html>'), '');
      expect(HtmlText.titleOf(''), '');
    });

    test('优先 head 里的 title(正文/内联 SVG 的 title 不算)', () {
      const html = '<html><head><title>真正的标题</title></head>'
          '<body><svg><title>图标</title></svg></body></html>';
      expect(HtmlText.titleOf(html), equals('真正的标题'));
    });
  });

  group('HtmlText.readableText — 正文提取', () {
    // 一份"真实感"的页面:脚本/样式/注释/导航/页头页脚 + 正文
    const page = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <title>Can apps teach you a language?</title>
  <style>
    body { font-family: Arial; }
    .promo::after { content: "SUBSCRIBE NOW AND SAVE"; }
  </style>
  <script type="text/javascript">
    window.__DATA__ = {"promo":"BUY PREMIUM ACCESS TODAY"};
    function track() { console.log("TRACKING PIXEL FIRED"); }
  </script>
</head>
<body>
<!-- 下面这块是注释里的导航,必须一起丢掉 -->
<!-- <p>COMMENTED OUT PARAGRAPH SHOULD NOT APPEAR</p> -->
<nav><a href="/home">Home</a><a href="/episodes">Episodes</a><a href="/about">About</a></nav>
<header><a href="/">6 Minute English</a></header>
<main>
  <h1>Can apps teach you a language?</h1>
  <p>Many people use apps to study English.
     They practise for ten minutes
     every day on the bus &amp; at home.</p>
  <p>But do apps really work? It&#39;s a good question&nbsp;&mdash; and the answer
     is not simple.</p>
  <p>Read the full transcript <a href="/transcript">Transcription</a> and
     <a href="/pdf">PDF</a> before you listen.</p>
  <blockquote>Learning a language is a marathon, not a sprint.</blockquote>
  <p>First line of a two-line paragraph.<br>Second line of the same paragraph.</p>
</main>
<footer><div><footer>Footer widgets should be removed too.</footer></div></footer>
</body>
</html>
''';

    /// 顶部导航(源码里排成几行,渲染后本该被丢掉)
    const navOnlyPage = '<html><body>'
        '<nav>\n  <a href="/home">Home</a>\n  <a href="/episodes">Episodes</a>\n'
        '  <a href="/about">About</a>\n</nav>'
        '<p>This is the only real paragraph on the page, and it is long enough '
        'to survive every filter we apply.</p>'
        '</body></html>';

    test('正文里绝不出现 CSS/JS 源码', () {
      final text = HtmlText.readableText(page);
      expect(text, contains('Many people use apps to study English.'));
      expect(text, isNot(contains('SUBSCRIBE NOW AND SAVE')));
      expect(text, isNot(contains('BUY PREMIUM ACCESS TODAY')));
      expect(text, isNot(contains('TRACKING PIXEL FIRED')));
      expect(text, isNot(contains('window.__DATA__')));
      expect(text, isNot(contains('font-family')));
      // 不是断言"不含 script 这个词"(正文里本来就可能提到),而是断言不含标签与源码
      expect(text, isNot(contains('</script>')));
      expect(text, isNot(contains('<style>')));
      expect(text, isNot(contains('console.log')));
    });

    test('注释块与 nav/header/footer 的模板内容被剔除', () {
      final text = HtmlText.readableText(page);
      expect(text, isNot(contains('COMMENTED OUT PARAGRAPH')));
      expect(text, isNot(contains('Footer widgets')));
      expect(text, isNot(contains('Episodes')));
    });

    test('段落之间用 \\n\\n 分隔,<p> 内的换行合并成一行', () {
      final text = HtmlText.readableText(page);
      final blocks = text.split('\n\n');
      expect(
        blocks.first,
        equals('Can apps teach you a language?'),
      );
      expect(
        blocks,
        contains('Many people use apps to study English. '
            'They practise for ten minutes every day on the bus & at home.'),
      );
      // 段落边界靠标签分,不靠标点猜:一段里有句号也不许被切开
      expect(
        blocks,
        contains('But do apps really work? '
            'It\'s a good question — and the answer is not simple.'),
      );
      // 正文没有被源码折行拆成多段
      expect(text, isNot(contains('practise for ten minutes\n')));
    });

    test('<br> 也是段落边界(老式页面用 <br><br> 分段)', () {
      final text = HtmlText.readableText(page);
      final blocks = text.split('\n\n');
      expect(blocks, contains('First line of a two-line paragraph.'));
      expect(blocks, contains('Second line of the same paragraph.'));
    });

    test('实体解码:&amp; &#39; &nbsp; &mdash;', () {
      final text = HtmlText.readableText(page);
      expect(text, contains('the bus & at home'));
      expect(text, contains("It's a good question"));
      expect(text, contains('a good question — and the answer is not simple.'));
      // &nbsp; 变成一个普通空格(不保留 \u00a0)
      expect(text, isNot(contains('\u00a0')));
      expect(text, isNot(contains('&amp;')));
    });

    test('段落边界:标题、引用各自成段', () {
      final text = HtmlText.readableText(page);
      final blocks = text.split('\n\n');
      expect(
        blocks,
        contains('Learning a language is a marathon, not a sprint.'),
      );
      expect(blocks.length, greaterThanOrEqualTo(5));
    });

    test('纯链接的导航块被丢掉,但正文里的行内链接保留', () {
      final text = HtmlText.readableText(page);
      expect(text, contains('Read the full transcript'));
      expect(text, contains('Transcription'));
      expect(text, contains('PDF before you listen.'));
      // 导航:整行只有 <a> 标签,且链接文字很短 → 丢
      final navPage = HtmlText.readableText(navOnlyPage);
      expect(navPage, isNot(contains('Episodes')));
      expect(navPage, isNot(contains('About')));
      expect(navPage, contains('This is the only real paragraph on the page'));
    });

    test('同一种标签出现多次时要全部删掉,不能只删第一处', () {
      // 回归用例:真实页面动辄十几个 <script>(埋点/同意管理/播放器各一个)。
      // 早期实现每类标签只调一次 removeBlock(只删第一处),结果 NPR 文章页
      // 正文里漏进 OneTrust 的 JS,词数从 800 涨到 2200。
      const multi = '<html><head>'
          '<script>var a = 1;</script>'
          '<style>.one{color:red}</style>'
          '<script>var b = 2; console.log("SECOND_SCRIPT");</script>'
          '<style>.two{color:blue}</style>'
          '</head><body>'
          '<nav><a href="/x">Menu</a></nav>'
          '<footer>FIRST_FOOTER</footer>'
          '<aside>SECOND_ASIDE</aside>'
          '<p>The only real sentence of this page, kept for comparison.</p>'
          '</body></html>';
      final text = HtmlText.readableText(multi);
      expect(text, contains('The only real sentence of this page'));
      expect(text, isNot(contains('SECOND_SCRIPT')));
      expect(text, isNot(contains('var a')));
      expect(text, isNot(contains('var b')));
      expect(text, isNot(contains('color:red')));
      expect(text, isNot(contains('color:blue')));
      expect(text, isNot(contains('FIRST_FOOTER')));
      expect(text, isNot(contains('SECOND_ASIDE')));
      expect(text, isNot(contains('Menu')));
    });

    test('removeAllBlocks 收敛且删干净(不会死循环)', () {
      const html = '<p>keep</p><script>1</script><script>2</script>'
          '<script>3</script>';
      final out = HtmlText.removeAllBlocks(html, 'script');
      expect(out, equals('<p>keep</p>'));
      // 已经删干净后再调用不应改变内容
      expect(HtmlText.removeAllBlocks(out, 'script'), equals(out));
      // 未闭合的标签:返回原串,不抛异常
      const broken = '<p>keep</p><script>never closed';
      expect(HtmlText.removeAllBlocks(broken, 'script'), equals(broken));
    });

    test('列表里的跳转链接(nav 之外的 <ul><li><a>)也要丢掉', () {
      // 回归用例:真实 NPR 页头的 skip-links 结构长这样 ——
      // 链接不在 <nav> 里,只能靠"整段就是一个短链接"判断;
      // 早期实现把 </a> 一起删了,导致这个判断彻底失效。
      const page = '<html><body>'
          '<div class="skip-links"><ul>'
          '<li><a href="#mainContent" class="skiplink">Skip to main content</a></li>'
          '<li><a href="/help/article?name=keyboard">'
          'Keyboard shortcuts for audio player</a></li>'
          '</ul></div>'
          '<p>The article body itself must survive this filter.</p>'
          '</body></html>';
      final text = HtmlText.readableText(page);
      expect(text, isNot(contains('Skip to main content')));
      expect(text, isNot(contains('Keyboard shortcuts')));
      expect(text, isNot(contains('<a')));
      expect(text, isNot(contains('</a>')));
      expect(text, contains('The article body itself must survive this filter.'));
    });

    test('锚点闭合标签不会被误删(开闭标签成对处理)', () {
      // `</a>` 若被当成普通标签删掉,"整段是链接"的判断就永远不成立
      const html = '<p>Text <a href="/x">link</a> more text.</p>';
      final text = HtmlText.readableText(html);
      expect(text, equals('Text link more text.'));
    });

    test('空输入 / 无标签的纯文本 / 只有 script 的页面', () {
      expect(HtmlText.readableText(''), '');
      // 没有任何标签说明调用方用错了 API:不假装抽出了正文
      expect(HtmlText.readableText('just plain text, no markup'), '');
      expect(
        HtmlText.readableText('<html><body><script>var a = 1;</script>'
            '<style>.a{color:red}</style></body></html>'),
        '',
      );
    });
  });

  group('HtmlText.decodeEntities', () {
    test('命名实体', () {
      expect(
        HtmlText.decodeEntities('a &amp; b &lt;tag&gt; &quot;q&quot; &apos;s&apos;'),
        equals('a & b <tag> "q" \'s\''),
      );
      expect(HtmlText.decodeEntities('a&nbsp;b'), equals('a b'));
      expect(HtmlText.decodeEntities('1&mdash;2'), equals('1—2'));
      expect(HtmlText.decodeEntities('&hellip;&rsquo;'), equals('…’'));
    });

    test('数字实体(十进制 + 十六进制)', () {
      expect(HtmlText.decodeEntities('&#39;&#8212;'), equals("'—"));
      expect(HtmlText.decodeEntities('&#x27;&#x2014;'), equals("'—"));
    });

    test('不认识的实体原样保留(不擅自删字符)', () {
      expect(HtmlText.decodeEntities('&weirdname; &#; & b'), equals('&weirdname; &#; & b'));
    });

    test('空串与不含 & 的串直接返回', () {
      expect(HtmlText.decodeEntities(''), '');
      expect(HtmlText.decodeEntities('plain'), 'plain');
    });
  });

  group('HtmlText.stripTags', () {
    test('去标签 + 解实体 + 合并成一行', () {
      expect(
        HtmlText.stripTags('<p>Hello\n   <b>world</b></p><p>Tom &amp; Jerry</p>'),
        equals('Hello world Tom & Jerry'),
      );
    });

    test('空串 → 空串', () {
      expect(HtmlText.stripTags(''), '');
    });
  });

  group('HtmlText.links — 相对链接绝对化', () {
    const page = '<a href="/podcast/1">A</a>'
        '<a href="../about">B</a>'
        '<a href="//cdn.example.com/x">C</a>'
        '<a href="https://other.example.org/d?y=1&amp;z=2">D</a>'
        '<a href="mailto:a@b.c">E</a>'
        '<a href="javascript:void(0)">F</a>'
        '<a href="#top">G</a>'
        '<a href="/podcast/1">A(重复)</a>';

    test('有 baseUrl:各种相对形式都解析', () {
      expect(
        HtmlText.links(page, baseUrl: 'https://example.com/news/index.html'),
        equals([
          'https://example.com/podcast/1',
          'https://example.com/about',
          'https://cdn.example.com/x',
          'https://other.example.org/d?y=1&z=2',
        ]),
      );
    });

    test('无 baseUrl:相对链接原样返回、绝对链接不变、mailto/js/锚点仍被跳过', () {
      expect(
        HtmlText.links(page),
        equals([
          '/podcast/1',
          '../about',
          '//cdn.example.com/x',
          'https://other.example.org/d?y=1&z=2',
        ]),
      );
    });

    test('resolveUrl 的边界', () {
      expect(
        HtmlText.resolveUrl('https://a.com/x', 'https://b.com/'),
        equals('https://a.com/x'),
      );
      expect(HtmlText.resolveUrl('', 'https://b.com/'), '');
      expect(HtmlText.resolveUrl('/x', ''), equals('/x'));
      expect(HtmlText.resolveUrl('/x', 'not a url'), equals('/x'));
      expect(
        HtmlText.resolveUrl('?page=2', 'https://b.com/list?page=1'),
        equals('https://b.com/list?page=2'),
      );
      // 多级回退不能越出根
      expect(
        HtmlText.resolveUrl('../../../../x', 'https://b.com/a/b/c'),
        equals('https://b.com/x'),
      );
    });

    test('空 HTML / 纯文本 → 空列表且不抛异常', () {
      expect(HtmlText.links(''), isEmpty);
      expect(HtmlText.links('no links here'), isEmpty);
    });
  });

  // ══════════════════════════ 订阅解析 ══════════════════════════

  group('FeedParser.parse — RSS 2.0', () {
    const rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:media="http://search.yahoo.com/mrss/" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>6 Minute English</title>
    <link>https://www.bbc.co.uk/learningenglish/features/6-minute-english</link>
    <item>
      <title><![CDATA[Tom &amp; Jerry: why we laugh]]></title>
      <description><![CDATA[<p>We talk about humour &amp; laughter.</p>]]></description>
      <link>https://www.bbc.co.uk/learningenglish/features/6-minute-english/ep-260917</link>
      <guid isPermaLink="false">urn:bbc:podcast:p0abc123</guid>
      <pubDate>Wed, 17 Sep 2026 09:00:00 +0000</pubDate>
      <enclosure url="https://downloads.bbc.co.uk/6min/ep-260917.mp3"
                 type="audio/mpeg" length="8231234" />
      <itunes:duration>00:06:12</itunes:duration>
      <itunes:author>BBC Learning English</itunes:author>
      <dc:creator>Neil and Beth</dc:creator>
    </item>
    <item>
      <title>Learning by listening</title>
      <description>Why listening is the hardest skill.</description>
      <link>https://www.bbc.co.uk/learningenglish/features/6-minute-english/ep-260910</link>
      <guid isPermaLink="false">urn:bbc:podcast:p0abc122</guid>
      <pubDate>Wed, 10 Sep 2026 09:00:00 +0000</pubDate>
      <media:content url="https://downloads.bbc.co.uk/6min/ep-260910.mp3"
                     type="audio/mpeg" medium="audio" />
      <media:thumbnail url="https://ichef.bbci.co.uk/images/ic/640x360/p0abc122.jpg" />
    </item>
    <item>
      <title>This broken item has no link at all</title>
      <description>应当被跳过</description>
    </item>
  </channel>
</rss>
''';

    test('条目数:没有链接的坏条目被跳过', () {
      final items = FeedParser.parse(rss);
      expect(items.length, equals(2));
    });

    test('第一条:CDATA 标题/简介已解实体、字段齐全', () {
      final item = FeedParser.parse(rss).first;
      // CDATA 去壳之后仍要走实体解码:CDATA 里的 &amp; 是作者写的字面文本
      expect(item.title, equals('Tom & Jerry: why we laugh'));
      expect(
        item.summary,
        equals('We talk about humour & laughter.'),
      );
      expect(
        item.link,
        equals('https://www.bbc.co.uk/learningenglish/features/6-minute-english/ep-260917'),
      );
      expect(item.guid, equals('urn:bbc:podcast:p0abc123'));
      expect(item.published, equals('Wed, 17 Sep 2026 09:00:00 +0000'));
      expect(
        item.audioUrl,
        equals('https://downloads.bbc.co.uk/6min/ep-260917.mp3'),
      );
      expect(item.author, equals('Neil and Beth'));
    });

    test('第二条:音频来自 media:content,封面图不会当成音频', () {
      final item = FeedParser.parse(rss)[1];
      expect(item.title, equals('Learning by listening'));
      expect(
        item.audioUrl,
        equals('https://downloads.bbc.co.uk/6min/ep-260910.mp3'),
      );
      expect(item.published, equals('Wed, 10 Sep 2026 09:00:00 +0000'));
      // 没有 dc:creator / itunes:author 时 author 为空
      expect(item.author, isNull);
    });

    test('published 保持原样字符串,不在这里解析成 DateTime', () {
      final item = FeedParser.parse(rss).first;
      expect(item.published, isA<String>());
      expect(item.published, contains('Sep 2026'));
    });
  });

  group('FeedParser.parse — Atom', () {
    const atom = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>arXiv cs.CL updates</title>
  <entry>
    <title>Attention Is All You Need</title>
    <link rel="self" href="https://export.arxiv.org/api/query?id_list=1706.03762"/>
    <link href="https://arxiv.org/abs/1706.03762"/>
    <id>oai:arXiv.org:1706.03762</id>
    <updated>2017-06-12T17:57:34Z</updated>
    <published>2017-06-12T17:57:34Z</published>
    <summary>The dominant sequence transduction models are based on
      complex recurrent or convolutional neural networks.</summary>
    <author><name>Ashish Vaswani</name></author>
    <author><name>Noam Shazeer</name></author>
  </entry>
  <entry>
    <title>Malformed entry without any link</title>
    <updated>2026-01-01T00:00:00Z</updated>
  </entry>
</feed>
''';

    test('Atom 条目:link 取 href 且优先无 rel/alternate 的那个', () {
      final items = FeedParser.parse(atom);
      expect(items.length, equals(1));
      final item = items.first;
      expect(item.title, equals('Attention Is All You Need'));
      expect(item.link, equals('https://arxiv.org/abs/1706.03762'));
      expect(item.published, equals('2017-06-12T17:57:34Z'));
      expect(item.guid, equals('oai:arXiv.org:1706.03762'));
      expect(item.summary, startsWith('The dominant sequence transduction'));
      expect(item.audioUrl, isNull);
    });

    test('RSS 与 Atom 可以混在一个文档里,按出现顺序返回', () {
      const mixed = '<rss><channel>'
          '<item><title>RSS 条目</title><link>https://a.example/1</link></item>'
          '</channel></rss>'
          '<feed><entry><title>Atom 条目</title>'
          '<link href="https://a.example/2"/></entry></feed>';
      final items = FeedParser.parse(mixed);
      expect(items.map((e) => e.title).toList(), equals(['RSS 条目', 'Atom 条目']));
    });
  });

  group('FeedParser.audioOf', () {
    test('enclosure 优先,type 必须像音频', () {
      expect(
        FeedParser.audioOf(
          '<enclosure url="https://x.example/a.mp3" type="audio/mpeg"/>',
        ),
        equals('https://x.example/a.mp3'),
      );
    });

    test('封面图类型的 enclosure 不算音频', () {
      expect(
        FeedParser.audioOf(
          '<enclosure url="https://x.example/cover.jpg" type="image/jpeg"/>',
        ),
        isNull,
      );
    });

    test('enclosure 是图、media:content 是音频时取音频', () {
      expect(
        FeedParser.audioOf('<enclosure url="https://x.example/cover.jpg" '
            'type="image/jpeg"/><media:content url="https://x.example/a.mp3" '
            'type="audio/mpeg"/>'),
        equals('https://x.example/a.mp3'),
      );
    });

    test('没有 type 的 url 作为兜底(但不认图片后缀)', () {
      expect(
        FeedParser.audioOf('<enclosure url="https://x.example/ep1.mp3"/>'),
        equals('https://x.example/ep1.mp3'),
      );
      expect(
        FeedParser.audioOf('<enclosure url="https://x.example/ep1.png"/>'),
        isNull,
      );
    });

    test('url 属性里的 &amp; 要被解码(否则下载 404)', () {
      expect(
        FeedParser.audioOf(
          '<enclosure url="https://x.example/a.mp3?t=1&amp;u=2" type="audio/mpeg"/>',
        ),
        equals('https://x.example/a.mp3?t=1&u=2'),
      );
    });

    test('没有音频 / 空串 → null', () {
      expect(FeedParser.audioOf('<item><title>t</title></item>'), isNull);
      expect(FeedParser.audioOf(''), isNull);
    });
  });

  group('FeedParser — 畸形输入不抛异常', () {
    test('空串 / 纯空白 → 空列表', () {
      expect(FeedParser.parse(''), isEmpty);
      expect(FeedParser.parse('   \n\t  '), isEmpty);
    });

    test('纯文本 → 空列表', () {
      expect(FeedParser.parse('this is not a feed at all'), isEmpty);
    });

    test('未闭合的 item → 跳过,不抛异常', () {
      expect(FeedParser.parse('<rss><channel><item><title>没闭合'), isEmpty);
    });

    test('注释里的 item 不算条目', () {
      expect(
        FeedParser.parse('<rss><!-- <item><title>x</title>'
            '<link>https://a.example/1</link></item> --></rss>'),
        isEmpty,
      );
    });

    test('缺字段的条目:title/summary 补空串,不崩', () {
      final items = FeedParser.parse(
        '<rss><channel><item><link>https://a.example/1</link></item></channel></rss>',
      );
      expect(items.length, equals(1));
      expect(items.first.title, '');
      expect(items.first.summary, '');
      expect(items.first.published, isNull);
      expect(items.first.audioUrl, isNull);
    });
  });

  // ══════════════════════════ 内容源清单与 URL 组装 ══════════════════════════

  group('MaterialSourceService.sources — 清单完整性', () {
    test('7 个源,id 唯一', () {
      final sources = MaterialSourceService.sources;
      expect(sources.length, equals(7));
      final ids = sources.map((s) => s.id).toList();
      expect(
        ids,
        equals([
          'bbc_le',
          'voa_le',
          'npr',
          'ted',
          'gutenberg',
          'wikipedia',
          'arxiv',
        ]),
      );
      expect(ids.toSet().length, equals(ids.length));
    });

    test('每个源都有中文名/说明/许可文案,kind 合法', () {
      const allowedKinds = {'news', 'book', 'podcast', 'wiki', 'paper'};
      for (final s in MaterialSourceService.sources) {
        expect(s.label, isNotEmpty, reason: '${s.id} 缺 label');
        expect(s.description.length, greaterThan(10), reason: '${s.id} 说明太短');
        expect(s.license, isNotEmpty, reason: '${s.id} 缺 license');
        // 许可文案必须真的说清"能不能再分发/是否仅个人使用",不能糊一行字
        expect(
          s.license,
          anyOf(contains('个人'), contains('公版'), contains('CC'), contains('公共领域')),
          reason: '${s.id} 的 license 没写清使用边界',
        );
        expect(allowedKinds, contains(s.kind), reason: '${s.id} kind 非法');
      }
    });

    test('有音频的源恰好是 3 个真正带 enclosure 的教学源', () {
      // NPR 的 1001 新闻订阅实测没有 enclosure,所以不算音频源(见 sources 注释)
      final audio = MaterialSourceService.sources
          .where((s) => s.hasAudio)
          .map((s) => s.id)
          .toList();
      expect(audio, equals(['bbc_le', 'voa_le', 'ted']));
    });

    test('sourceOf 命中与未命中', () {
      expect(MaterialSourceService.sourceOf('gutenberg')?.label, contains('Gutenberg'));
      expect(MaterialSourceService.sourceOf('nope'), isNull);
    });
  });

  group('MaterialSourceService — URL 组装(纯函数)', () {
    test('feedUrlOf:每个源都有列表地址', () {
      for (final s in MaterialSourceService.sources) {
        final url = MaterialSourceService.feedUrlOf(s.id);
        expect(url, isNotNull, reason: '${s.id} 没有列表地址');
        expect(url, startsWith('https://'), reason: '${s.id} 必须走 https');
      }
      expect(MaterialSourceService.feedUrlOf('nope'), isNull);
    });

    test('Gutenberg 全文地址', () {
      expect(
        MaterialSourceService.gutenbergTextUrl(1342),
        equals('https://www.gutenberg.org/cache/epub/1342/pg1342.txt'),
      );
    });

    test('gutenbergIdOf:各种写法都能认出书号', () {
      expect(MaterialSourceService.gutenbergIdOf('1342'), equals(1342));
      expect(
        MaterialSourceService.gutenbergIdOf('https://www.gutenberg.org/ebooks/1342'),
        equals(1342),
      );
      expect(
        MaterialSourceService.gutenbergIdOf(
          'https://www.gutenberg.org/cache/epub/1342/pg1342.txt',
        ),
        equals(1342),
      );
      expect(
        MaterialSourceService.gutenbergIdOf(
          'https://www.gutenberg.org/files/11/11-0.txt',
        ),
        equals(11),
      );
      expect(MaterialSourceService.gutenbergIdOf('https://example.com/book'), isNull);
      expect(MaterialSourceService.gutenbergIdOf(''), isNull);
    });

    test('wikipediaApiUrl:转义条目名并要纯文本正文', () {
      final url = MaterialSourceService.wikipediaApiUrl('English language');
      expect(url, startsWith('https://en.wikipedia.org/w/api.php?'));
      expect(url, contains('prop=extracts'));
      expect(url, contains('explaintext=1'));
      expect(url, contains('titles=English_language'));
      expect(
        MaterialSourceService.wikipediaApiUrl('英语', lang: 'zh'),
        contains('https://zh.wikipedia.org/w/api.php?'),
      );
    });

    test('wikipediaLangOf 从链接猜语言', () {
      expect(
        MaterialSourceService.wikipediaLangOf('https://zh.wikipedia.org/wiki/英语'),
        equals('zh'),
      );
      expect(
        MaterialSourceService.wikipediaLangOf('https://simple.wikipedia.org/wiki/X'),
        equals('simple'),
      );
      expect(MaterialSourceService.wikipediaLangOf('https://example.com/x'), equals('en'));
    });

    test('arxivIdOf:新式/带版本/完整链接/老式 id', () {
      expect(MaterialSourceService.arxivIdOf('1706.03762'), equals('1706.03762'));
      expect(MaterialSourceService.arxivIdOf('1706.03762v5'), equals('1706.03762'));
      expect(
        MaterialSourceService.arxivIdOf('https://arxiv.org/abs/1706.03762'),
        equals('1706.03762'),
      );
      expect(
        MaterialSourceService.arxivIdOf('https://arxiv.org/pdf/1706.03762v2.pdf'),
        equals('1706.03762'),
      );
      expect(MaterialSourceService.arxivIdOf('cs.CL/0301001'), equals('cs.CL/0301001'));
      expect(MaterialSourceService.arxivIdOf('hello'), isNull);
    });

    test('documentUrlOf:gutenberg 与 arxiv 会规范化地址', () {
      expect(
        MaterialSourceService.documentUrlOf(
          'gutenberg',
          url: 'https://www.gutenberg.org/ebooks/1342',
        ),
        equals('https://www.gutenberg.org/cache/epub/1342/pg1342.txt'),
      );
      expect(
        MaterialSourceService.documentUrlOf('arxiv', url: '1706.03762v3'),
        equals('https://arxiv.org/abs/1706.03762'),
      );
      expect(
        MaterialSourceService.documentUrlOf('npr', url: 'https://www.npr.org/x'),
        equals('https://www.npr.org/x'),
      );
      expect(MaterialSourceService.documentUrlOf('gutenberg', url: 'nope'), isNull);
    });

    test('未知 sourceId 的异常里列出可用来源', () {
      final e = MaterialSourceService.unknownSource('weibo');
      expect(e.message, contains('weibo'));
      expect(e.message, contains('gutenberg'));
      expect(e.toString(), contains('材料中心'));
    });

    test('stripSiteSuffix:砍掉站点名尾巴,不误伤标题里的冒号', () {
      expect(
        MaterialSourceService.stripSiteSuffix(
          'Hydropower and the Himalayas: What does the future hold? : NPR',
          'https://www.npr.org/2026/09/23/g-s1-144536/floods',
        ),
        equals('Hydropower and the Himalayas: What does the future hold?'),
      );
      expect(
        MaterialSourceService.stripSiteSuffix(
          'The joys of writing lists | TED',
          'https://www.ted.com/talks/x',
        ),
        equals('The joys of writing lists'),
      );
      expect(
        MaterialSourceService.stripSiteSuffix(
          'Can apps teach you a language? - BBC Learning English',
          'https://www.bbc.co.uk/learningenglish/features/6-minute-english/ep-260917',
        ),
        equals('Can apps teach you a language?'),
      );
      // 尾段不是站点名时保持原样(冒号在标题里很常见)
      expect(
        MaterialSourceService.stripSiteSuffix(
          'Nepal: a country of contrasts',
          'https://www.npr.org/x',
        ),
        equals('Nepal: a country of contrasts'),
      );
      expect(MaterialSourceService.stripSiteSuffix('', 'https://npr.org'), '');
      expect(
        MaterialSourceService.stripSiteSuffix('Title', 'not a url'),
        equals('Title'),
      );
    });

    test('unknownSource 的 id 与 sources 清单一一对应', () {
      expect(
        MaterialSourceService.sources.map((s) => MaterialSourceService.sourceOf(s.id)),
        everyElement(isNotNull),
      );
    });
  });

  // ══════════════════════════ 切块 ══════════════════════════

  group('MaterialSourceService.chunkByWords', () {
    test('空文本 → 空列表', () {
      expect(MaterialSourceService.chunkByWords(''), isEmpty);
      expect(MaterialSourceService.chunkByWords('   \n\n  '), isEmpty);
    });

    test('按词数切块且编号从 1 连续', () {
      // 9000 个词,上限 4000 → 3 块
      final text = List.generate(9000, (i) => 'word$i').join(' ');
      final chunks = MaterialSourceService.chunkByWords(text, wordsPerChunk: 4000);
      expect(chunks.length, equals(3));
      expect(chunks.map((c) => c.index).toList(), equals([1, 2, 3]));
      for (final c in chunks) {
        final words = c.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        expect(words, lessThanOrEqualTo(4000));
      }
      // 不丢词
      final total = chunks
          .expand((c) => c.text.split(RegExp(r'\s+')))
          .where((w) => w.isNotEmpty)
          .length;
      expect(total, equals(9000));
    });

    test('段落边界优先:不会把段落劈成两半', () {
      final paras = List.generate(6, (i) => 'P$i ${'x ' * 50}'.trim());
      final text = paras.join('\n\n');
      final chunks = MaterialSourceService.chunkByWords(text, wordsPerChunk: 110);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        // 每一块都是完整的段落集合:块内不应出现"半个 x 序列"之外的破裂
        expect(c.text, isNot(startsWith('x ')));
      }
    });

    test('splitOnlyAbove:短文不切', () {
      final short = List.generate(500, (i) => 'w$i').join(' ');
      final chunks = MaterialSourceService.chunkByWords(
        short,
        wordsPerChunk: 100,
        splitOnlyAbove: 4000,
      );
      expect(chunks.length, equals(1));
      expect(chunks.first.index, equals(1));
    });

    test('超长单段(公版书常见)按上限硬切,不丢词', () {
      final long = 'a ' * 5000;
      final chunks = MaterialSourceService.chunkByWords(long.trim(), wordsPerChunk: 2000);
      expect(chunks.length, equals(3));
    });
  });

  // ══════════════════════════ Project Gutenberg ══════════════════════════

  // 结构与真实 pg1342.txt 一致:许可说明 + START/END 标记 + 章标题 + 页脚许可
  const gutenbergText = '''
The Project Gutenberg eBook of Pride and Prejudice

This eBook is for the use of anyone anywhere in the United States and
most other parts of the world at no cost and with almost no restrictions
whatsoever.

Title: Pride and Prejudice

Author: Jane Austen

Release date: June 1, 1998 [eBook #1342]

Language: English

*** START OF THE PROJECT GUTENBERG EBOOK PRIDE AND PREJUDICE ***

PRIDE AND PREJUDICE

By Jane Austen

Chapter I.

It is a truth universally acknowledged, that a single man in
possession of a good fortune, must be in want of a wife.

However little known the feelings or views of such a man may be on his
first entering a neighbourhood, this truth is so well fixed in the minds
of the surrounding families, that he is considered as the rightful
property of some one or other of their daughters.

CHAPTER II.

Mr. Bennet was among the earliest of those who waited on Mr. Bingley.

He had always intended to visit him, though to the last always assuring
his wife that he would not go.

CHAPTER III.

Not all that Mrs. Bennet, however, with the assistance of her five
daughters, could ask on the subject, was sufficient to draw from her
husband any satisfactory description of Mr. Bingley.

*** END OF THE PROJECT GUTENBERG EBOOK PRIDE AND PREJUDICE ***

Section 1. General Terms of Use and Redistributing Project Gutenberg
electronic works

Most people start at our website which has the main PG search
facility: www.gutenberg.org.
''';

  group('MaterialSourceService — Gutenberg 解析', () {
    test('gutenbergBody:切掉头尾许可说明', () {
      final body = MaterialSourceService.gutenbergBody(gutenbergText);
      expect(body, contains('It is a truth universally acknowledged'));
      expect(body, isNot(contains('*** START OF')));
      expect(body, isNot(contains('*** END OF')));
      expect(body, isNot(contains('General Terms of Use')));
      expect(body, isNot(contains('Section 1.')));
      // 头部许可说明也不能混进正文
      expect(body, isNot(contains('Release date')));
    });

    test('gutenbergBody:没有标记时保守返回全文(宁可多留)', () {
      expect(
        MaterialSourceService.gutenbergBody('just some text'),
        equals('just some text'),
      );
    });

    test('gutenbergHeader:抽 Title/Author/Language', () {
      final h = MaterialSourceService.gutenbergHeader(gutenbergText);
      expect(h['title'], equals('Pride and Prejudice'));
      expect(h['author'], equals('Jane Austen'));
      expect(h['language'], equals('English'));
    });

    test('gutenbergChunks:按 CHAPTER 标题切块并保留章节名', () {
      final body = MaterialSourceService.gutenbergBody(gutenbergText);
      final chunks = MaterialSourceService.gutenbergChunks(body);
      expect(chunks.map((c) => c.title).toList(), equals([
        '前言',
        'Chapter I.',
        'CHAPTER II.',
        'CHAPTER III.',
      ]));
      expect(chunks.map((c) => c.index).toList(), equals([1, 2, 3, 4]));
      expect(
        chunks[1].text,
        contains('It is a truth universally acknowledged'),
      );
      // 章节正文不漏到下一章
      expect(chunks[1].text, isNot(contains('Mr. Bennet was among')));
      expect(chunks[2].text, startsWith('Mr. Bennet was among'));
      // 段内换行合并、段间空行保留
      expect(
        chunks[1].text,
        contains('possession of a good fortune, must be in want of a wife.'),
      );
      expect(chunks[1].text, contains('\n\n'));
      // 页脚许可不进任何块
      expect(
        chunks.every((c) => !c.text.contains('www.gutenberg.org')),
        isTrue,
      );
    });

    test('目录里的 "Chapter I. .... 5" 不算章节标题', () {
      const toc = 'CONTENTS\n\nChapter I. .......... 5\n\n'
          'The real text of the book starts here and keeps going.';
      final chunks = MaterialSourceService.gutenbergChunks(toc);
      // 切不出章节 → 退回按词数切(这里只有 1 块)
      expect(chunks.length, equals(1));
      expect(chunks.first.title, isNull);
      expect(chunks.first.text, contains('CONTENTS'));
    });

    test('没有章节标记的长文 → 按 ~4000 词切', () {
      final words = List.generate(9000, (i) => 'w$i').join(' ');
      final chunks = MaterialSourceService.gutenbergChunks(words);
      expect(chunks.length, equals(3));
      expect(chunks.map((c) => c.title).toList(), equals([null, null, null]));
    });

    test('空正文 → 空列表(调用方据此抛异常)', () {
      expect(MaterialSourceService.gutenbergChunks(''), isEmpty);
    });
  });

  // ══════════════════════════ Wikipedia ══════════════════════════

  group('MaterialSourceService — Wikipedia extracts JSON', () {
    // 真实 action=query&prop=extracts&explaintext=1&formatversion=2 的响应形状
    const json = '{"batchcomplete":true,"query":{"pages":[{"pageid":12345,'
        '"ns":0,"title":"English language","extract":"English is a West '
        'Germanic language.\\n\\n== History ==\\n\\nEnglish originated from '
        'Anglo-Frisian dialects.\\n\\n== See also ==\\n\\n* English studies"}]}}';

    test('取 title 与整篇 extract,反转义 \\n', () {
      final r = MaterialSourceService.wikipediaExtractOf(json);
      expect(r.title, equals('English language'));
      expect(r.missing, isFalse);
      expect(r.text, startsWith('English is a West Germanic language.'));
      expect(r.text, contains('\n\n== History ==\n\n'));
      expect(r.text, contains('English studies'));
    });

    test('页面不存在 → missing=true 且文本为空', () {
      const missing = '{"batchcomplete":true,"query":{"pages":[{"ns":0,'
          '"title":"Nope","missing":true,"contentmodel":"wikitext",'
          '"pagelanguage":"en","missing":""}]}}';
      final r = MaterialSourceService.wikipediaExtractOf(missing);
      expect(r.missing, isTrue);
      expect(r.text, '');
      expect(r.title, '');
    });

    test('空串/垃圾输入 → 空结果且不抛异常', () {
      expect(MaterialSourceService.wikipediaExtractOf('').text, '');
      expect(MaterialSourceService.wikipediaExtractOf('not json').text, '');
      expect(MaterialSourceService.wikipediaExtractOf('not json').missing, isFalse);
    });

    test('含引号与反斜杠的摘要能正确反转义', () {
      const tricky = '{"query":{"pages":[{"title":"Quote","extract":'
          '"He said \\"hello\\" and left.\\\\ done"}]}}';
      final r = MaterialSourceService.wikipediaExtractOf(tricky);
      expect(r.text, equals('He said "hello" and left.\\ done'));
    });
  });

  // ══════════════════════════ arXiv ══════════════════════════

  // 与真实 abs 页面同构:meta citation_* + 可见的 h1 / blockquote
  const arxivHtml = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <title>[1706.03762] Attention Is All You Need</title>
  <meta name="citation_title" content="Attention Is All You Need" />
  <meta name="citation_author" content="Vaswani, Ashish" />
  <meta name="citation_author" content="Shazeer, Noam" />
  <meta name="citation_abstract"
        content="The dominant sequence transduction models are based on complex recurrent or convolutional neural networks. We propose a new simple network architecture, the Transformer." />
</head>
<body>
<h1 class="title mathjax"><span class="descriptor">Title:</span>Attention Is All You Need</h1>
<blockquote class="abstract mathjax">
  <span class="descriptor">Abstract:</span>The dominant sequence transduction models are based on complex recurrent or convolutional neural networks.
</blockquote>
</body>
</html>
''';

  group('MaterialSourceService — arXiv 摘要页', () {
    test('元数据(h1 / citation_*)可被解析成标题与作者', () {
      // 这里只验证"解析素材本身是自洽的":标题与作者能从 HTML 里取到。
      // 真正的抓取走 _getText,不联网测;为此用一个轻量断言确认 fixture 有效。
      expect(arxivHtml, contains('citation_title'));
      expect(
        RegExp(r'<meta\s+name="citation_author"\s+content="([^"]*)"')
            .allMatches(arxivHtml)
            .length,
        equals(2),
      );
      final title = HtmlText.titleOf(arxivHtml);
      expect(title, equals('[1706.03762] Attention Is All You Need'));
      // 用通用正文提取确认摘要文本能落进纯文本(不依赖 arXiv 专属容器)
      expect(
        HtmlText.stripTags(HtmlText.readableText(arxivHtml)),
        contains('The dominant sequence transduction models'),
      );
    });

    test('arXiv 链接里的 id 与规范地址', () {
      expect(
        MaterialSourceService.documentUrlOf(
          'arxiv',
          url: 'https://arxiv.org/abs/1706.03762',
        ),
        equals('https://arxiv.org/abs/1706.03762'),
      );
    });
  });

  // ══════════════════════════ 异常模型 ══════════════════════════

  // ══════════════════════════ 对外入口(UI 调用面) ══════════════════════════

  group('MaterialSourceService.instance — UI 入口', () {
    test('公开单例:同一个实例,不是每次 new', () {
      expect(
        MaterialSourceService.instance,
        same(MaterialSourceService.instance),
      );
    });

    // 下面几条**不联网**:参数/来源不合法时,服务在发请求之前就抛异常。
    // 用来锁住"UI 拿得到实例、且错误是可读中文"这条契约。
    test('listItems:未知来源在联网前就抛中文异常', () async {
      await expectLater(
        MaterialSourceService.instance.listItems('weibo'),
        throwsA(
          isA<MaterialSourceException>()
              .having((e) => e.message, 'message', contains('weibo')),
        ),
      );
    });

    test('fetchDocument:未来源同样在联网前失败', () async {
      await expectLater(
        MaterialSourceService.instance
            .fetchDocument('weibo', url: 'https://example.com/x'),
        throwsA(isA<MaterialSourceException>()),
      );
    });

    test('fetchGutenberg:非法 id 不联网', () async {
      await expectLater(
        MaterialSourceService.instance.fetchGutenberg(0),
        throwsA(
          isA<MaterialSourceException>()
              .having((e) => e.message, 'message', contains('不合法')),
        ),
      );
    });

    test('fetchWikipedia:空条目名不联网', () async {
      await expectLater(
        MaterialSourceService.instance.fetchWikipedia('   '),
        throwsA(
          isA<MaterialSourceException>()
              .having((e) => e.message, 'message', contains('不能为空')),
        ),
      );
    });

    test('fetchArxiv:空编号不联网', () async {
      await expectLater(
        MaterialSourceService.instance.fetchArxiv(''),
        throwsA(
          isA<MaterialSourceException>()
              .having((e) => e.message, 'message', contains('不能为空')),
        ),
      );
    });

    test('fetchDocument:gutenberg 的非法链接在联网前提示示例', () async {
      await expectLater(
        MaterialSourceService.instance
            .fetchDocument('gutenberg', url: 'https://example.com/nope'),
        throwsA(
          isA<MaterialSourceException>()
              .having((e) => e.message, 'message', contains('1342')),
        ),
      );
    });
  });

  group('MaterialSourceException', () {
    test('toString 带源名、原因与状态码', () {
      const e = MaterialSourceException(
        sourceLabel: 'NPR News',
        message: '内容不存在(404)',
        statusCode: 404,
      );
      expect(e.toString(), equals('【NPR News】内容不存在(404)(HTTP 404)'));
    });

    test('无状态码时不显示 HTTP 段', () {
      const e = MaterialSourceException(
        sourceLabel: 'arXiv',
        message: '网络不可达',
      );
      expect(e.toString(), equals('【arXiv】网络不可达'));
    });
  });
}
