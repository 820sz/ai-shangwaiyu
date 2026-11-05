import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/deepseek_search.dart';
import 'package:readflow/services/input_prefs.dart';
import 'package:readflow/services/material_discovery.dart';
import 'package:readflow/services/material_source.dart';
import 'package:readflow/services/word_frequency.dart';

/// 批 12「方案2 频道化」:发现流水线的**分页 / 继续找更多 / PDF 回退**回归。
///
/// 这一层守的是频道页最容易"越用越乱"的三条口径:
/// 1. `excludeUrls` 必须真的挡住"上一页已经给用户看过"的候选(原始 URL 与
///    归一 key 两种写法都认,补救轮同样生效),否则「继续找更多」会重复出卡;
/// 2. `extraQueries` 必须与基础检索词合并去重、上限 8 条,且顺序可预期
///    (先基础词后补充词),否则新词会挤掉用户原本的方向;
/// 3. DS Fetch 读不了的 PDF/反爬页面要能回退公开抓取,回退也失败时**返回
///    null 而不是抛异常** —— 一篇抓不到不能把整轮发现打断。
///
/// 全程不联网:官方 Search/Fetch 走注入 transport,公开抓取层走
/// [MaterialSourceService.debugInjectDio] 注入的假 Dio。
void main() {
  /// 一句"正经英文正文":DS Fetch 返回它 → 走正常分析路径(不触发回退)。
  const longMarkdown = '''
# A Calm Look at AI Chips

The story of modern computing is a story of specialization. General purpose processors are good at many things, but they are not always good at the same thing at the same time. Engineers therefore build special hardware for the work that matters most.

A chip designed for one job can be smaller, faster and cheaper than a general purpose part. It can also use less power. These advantages explain why so many companies now design their own silicon instead of buying everything off the shelf.

The trade off is flexibility. A specialized chip is hard to change once it is built, so the design has to be right the first time. Teams spend months simulating workloads before they commit to a design.
''';

  /// 回退抓取拿到的 HTML 正文(必须能抽出 ≥120 字,否则 fetchAnyUrl 会报"没抽出来")
  const articleHtml = '''
<html><head><title>AI Chips Report</title></head><body>
<article>
<h1>AI Chips Report</h1>
<p>A chip designed for one job can be smaller, faster and cheaper than a general purpose part. It can also use less power, which matters a lot inside large data centers.</p>
<p>Many companies now design their own silicon because the advantages of specialization are large. The work is expensive, but the payoff can last for years.</p>
<p>The trade off is flexibility. A specialized chip is hard to change once it is built, so the design team has to get it right the first time around.</p>
</article></body></html>
''';

  setUpAll(() {
    // 难度分析要用词频表;注入假数据,测试不读 assets、不联网。
    const words = [
      'the', 'of', 'and', 'to', 'a', 'in', 'is', 'it', 'you', 'that',
      'time', 'people', 'water', 'run', 'chip', 'design', 'story', 'job',
    ];
    WordFrequency.debugInject(
      words: words,
      counts: List<int>.generate(words.length, (i) => 10000 - i),
    );
  });

  tearDown(() {
    // 回退测试会替换全局 Dio;跑完必须清掉,避免污染其它用例。
    MaterialSourceService.debugInjectDio(null);
  });

  // ─────────────────────────────────────────────────────────────────────
  // 工具
  // ─────────────────────────────────────────────────────────────────────

  Map<String, Object?> hit(
    String url, {
    String title = 'A Calm Look at AI Chips',
    String site = 'NPR',
  }) =>
      <String, Object?>{
        'title': title,
        'url': url,
        'site_name': site,
        'snippet': 'a short snippet',
        'summary': '',
        'authority': 2,
        'rerank_score': 2.0,
      };

  DeepSeekSearchClient clientWith(_FakeSearchTransport transport) =>
      DeepSeekSearchClient(
        // 给一个合法端点只是让 available=true;真正的往返全被注入的 transport 拦住。
        endpoint: const DeepSeekEndpoint(
          baseUrl: 'https://api.deepseek.com',
          apiKey: 'sk-test',
        ),
        transport: transport.call,
      );

  Dio dioWithBody(String body) {
    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        headers: const {'Accept-Language': 'en'},
      ),
    );
    dio.httpClientAdapter = _FakeHttpAdapter(body);
    return dio;
  }

  // ─────────────────────────────────────────────────────────────────────
  // ① 检索计划合并(纯函数)
  // ─────────────────────────────────────────────────────────────────────
  group('mergeDiscoveryQueries — 检索计划合并口径', () {
    test('基础词在前、补充词在后,trim 后去空去重', () {
      expect(
        mergeDiscoveryQueries(
          queries: const [' ai chips ', '', 'AI chips'],
          extraQueries: const ['AI chips', ' more 2024 ', '   '],
        ),
        ['ai chips', 'AI chips', 'more 2024'],
      );
    });

    test('最多 8 条:超出的补充词被丢弃', () {
      final merged = mergeDiscoveryQueries(
        queries: [for (var i = 0; i < 5; i++) 'base$i'],
        extraQueries: [for (var i = 0; i < 6; i++) 'extra$i'],
      );
      expect(merged, hasLength(8));
      expect(merged.sublist(0, 5), ['base0', 'base1', 'base2', 'base3', 'base4']);
      expect(merged.last, 'extra2');
    });

    test('limit 小于基础词数量时按前 limit 条截断', () {
      expect(
        mergeDiscoveryQueries(queries: const ['a', 'b', 'c'], limit: 2),
        ['a', 'b'],
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // ② discover · excludeUrls(分页/继续找更多不重复)
  // ─────────────────────────────────────────────────────────────────────
  group('discover · excludeUrls — 已见 URL 不再入库', () {
    test('原始 URL 与 dedupeKeyOf 归一 key 都能排除候选', () async {
      final transport = _FakeSearchTransport(
        defaultResults: [
          hit('https://example.com/post/one'),
          hit('https://example.com/post/two'),
          hit('https://example.com/post/three'),
        ],
        fetchContent: longMarkdown,
      );
      final run = await MaterialDiscovery(searchClient: clientWith(transport))
          .discover(
        queries: const ['ai chips'],
        prefs: InputPreferences(),
        model: LearnerModel(),
        maxFetch: 3,
        usePublicSources: false,
        enableRefine: false,
        excludeUrls: const {
          // 原始写法:带协议/大写主机/尾斜杠,归一后指向 post/one
          'https://EXAMPLE.com/post/one/',
          // 归一 key 写法:指向 post/two
          'example.com/post/two',
        },
      );

      expect(run.items.map((c) => c.url).toList(), [
        'https://example.com/post/three',
      ]);
      // 被排除的两条不能浪费抓取名额(连 DS Fetch 都不该发)
      expect(transport.fetchedUrls, ['https://example.com/post/three']);
    });

    test('补救轮补搜到的候选同样受 excludeUrls 约束', () async {
      var refineCalls = 0;
      final transport = _FakeSearchTransport(
        resultsByQuery: {
          'ai chips': [hit('https://example.com/post/one')],
          'ai chips 2024': [
            hit('https://example.com/post/one'), // 已见 → 必须丢
            hit('https://example.com/post/four'),
          ],
        },
        fetchContent: longMarkdown,
      );
      final discovery = MaterialDiscovery(
        searchClient: clientWith(transport),
        onRefine: (input) async {
          refineCalls++;
          return const ['ai chips 2024'];
        },
      );
      final run = await discovery.discover(
        queries: const ['ai chips'],
        prefs: InputPreferences(),
        model: LearnerModel(),
        maxFetch: 4,
        usePublicSources: false,
        userQuery: '找最近的 AI 芯片报道',
        excludeUrls: const {'https://example.com/post/one'},
      );

      expect(refineCalls, 1);
      expect(run.refined, isTrue);
      expect(transport.searchedQueries, ['ai chips', 'ai chips 2024']);
      expect(run.items.map((c) => c.url).toList(), [
        'https://example.com/post/four',
      ]);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // ③ discover · extraQueries(继续找更多的新词)
  // ─────────────────────────────────────────────────────────────────────
  group('discover · extraQueries — 新检索词合并进计划', () {
    test('补充词优先进入官方搜索(否则「继续找更多」等于重跑旧词)', () async {
      final transport = _FakeSearchTransport(
        defaultResults: [hit('https://example.com/post/one')],
        fetchContent: longMarkdown,
      );
      final run = await MaterialDiscovery(searchClient: clientWith(transport))
          .discover(
        queries: const ['base query'],
        extraQueries: const ['extra one', 'base query', ' extra two ', ''],
        prefs: InputPreferences(),
        model: LearnerModel(),
        maxFetch: 1,
        usePublicSources: false,
        enableRefine: false,
      );

      // 质检 P1-1:官方搜索只取 4 条,补充词必须排到基础词前面才有机会被搜到。
      // 这个用例里 extraQueries 自身含一条 'base query',所以它按出现顺序排第二,
      // 真正的频道基础词最后兜底 —— 关键是补充词都在名额内。
      expect(
        transport.searchedQueries,
        ['extra one', 'base query', 'extra two'],
      );
      expect(run.items, hasLength(1));
    });

    test('补充词为空的「继续找更多」不改变原计划', () async {
      final transport = _FakeSearchTransport(
        defaultResults: [hit('https://example.com/post/one')],
        fetchContent: longMarkdown,
      );
      await MaterialDiscovery(searchClient: clientWith(transport)).discover(
        queries: const ['base query'],
        extraQueries: const ['', '   '],
        prefs: InputPreferences(),
        model: LearnerModel(),
        maxFetch: 1,
        usePublicSources: false,
        enableRefine: false,
      );
      expect(transport.searchedQueries, ['base query']);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // ④ planNextQueries(继续找更多:让模型换词)
  // ─────────────────────────────────────────────────────────────────────
  group('planNextQueries — 继续找更多的新检索词', () {
    test('构造注入的 handler 收到归一化输入,输出清洗后最多 4 条', () async {
      MaterialRefineInput? captured;
      final discovery = MaterialDiscovery(
        onRefine: (input) async {
          captured = input;
          return const [
            '1. ai chips 2024',
            '  "ai chips 2024"  ',
            '',
            'CET-4 2024 真题 阅读',
            'New Concept English 3',
            'arxiv transformer survey',
          ];
        },
      );

      final queries = await discovery.planNextQueries(
        userQuery: ' 找最近的 AI 芯片报道 ',
        prefsHint: '目标:应试;难度:挑战',
        seenCandidates: const [
          {
            'title': 'AI Chips Report',
            'url': 'https://example.com/a',
            'sourceLabel': 'NPR',
            'snippet': 'snippet a',
            'authority': 3,
            'date': '2026-11-01T08:00:00.000',
          },
          // 没有 url 的条目对"哪些出处已经有了"没有信息量 → 跳过
          {'title': 'no url', 'sourceLabel': 'NPR'},
        ],
      );

      // 去编号/去引号/去重后正好 4 条,顺序保持模型给出的顺序
      expect(queries, [
        'ai chips 2024',
        'CET-4 2024 真题 阅读',
        'New Concept English 3',
        'arxiv transformer survey',
      ]);

      expect(captured, isNotNull);
      expect(captured!.userQuery, '找最近的 AI 芯片报道');
      expect(captured!.prefsHint, '目标:应试;难度:挑战');
      final first = captured!.candidates.first;
      expect(first['title'], 'AI Chips Report');
      expect(first['site'], 'NPR'); // sourceLabel → 提示词层的 site
      expect(first['date'], '2026-11-01'); // 截到天
      expect(first['authority'], 3);
      expect(first['snippet'], 'snippet a');
      expect(captured!.candidates, hasLength(1)); // 无 url 条目不喂模型
    });

    test('seenCandidates 最多喂 8 条(控制 token)', () async {
      MaterialRefineInput? captured;
      final discovery = MaterialDiscovery(
        onRefine: (input) async {
          captured = input;
          return const [];
        },
      );
      await discovery.planNextQueries(
        userQuery: 'x',
        seenCandidates: [
          for (var i = 0; i < 12; i++)
            <String, Object?>{
              'title': 't$i',
              'url': 'https://example.com/$i',
              'sourceLabel': 'NPR',
            },
        ],
      );
      expect(captured!.candidates, hasLength(8));
    });

    test('显式 handler 覆盖构造注入的实现', () async {
      final discovery = MaterialDiscovery(
        onRefine: (_) async => throw StateError('构造注入的实现不该被调用'),
      );
      final queries = await discovery.planNextQueries(
        userQuery: 'x',
        seenCandidates: const [],
        handler: (_) async => const ['brand new query'],
      );
      expect(queries, ['brand new query']);
    });

    test('模型失败/异常 → 返回空列表,不抛', () async {
      final discovery = MaterialDiscovery();
      final queries = await discovery.planNextQueries(
        userQuery: 'x',
        seenCandidates: const [],
        handler: (_) async => throw StateError('模型超时'),
      );
      expect(queries, isEmpty);
    });

    test('模型给出空/无效内容 → 返回空列表', () async {
      final discovery = MaterialDiscovery();
      final queries = await discovery.planNextQueries(
        userQuery: 'x',
        seenCandidates: const [],
        handler: (_) async => const ['', '   ', '!!!'],
      );
      expect(queries, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // ⑤ looksLikePdfUrl(纯函数)
  // ─────────────────────────────────────────────────────────────────────
  group('looksLikePdfUrl — PDF 识别', () {
    test('PDF 文件 / PDF 阅读页 / 下载参数都识别出来', () {
      const pdfUrls = [
        'https://example.com/files/report.pdf',
        'https://example.com/files/report.PDF?download=1',
        'https://arxiv.org/pdf/1706.03762v7',
        'https://arxiv.org/pdf/1706.03762',
        'https://example.com/download?format=pdf',
        'https://example.com/download?filetype=pdf&id=3',
        'https://example.com/view?file=/docs/guide.pdf',
        'https://example.com/paper/pdf',
      ];
      for (final url in pdfUrls) {
        expect(MaterialDiscovery.looksLikePdfUrl(url), isTrue, reason: url);
      }
    });

    test('普通文章 / 空串 / 名字里带 pdf 的文章不误判', () {
      const otherUrls = [
        '',
        '   ',
        'https://example.com/news/ai-chips',
        'https://example.com/blog/pdf-guide',
        'https://example.com/pdf-reader-article',
        'https://example.com/docs?format=html',
      ];
      for (final url in otherUrls) {
        expect(MaterialDiscovery.looksLikePdfUrl(url), isFalse, reason: url);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // ⑥ PDF 回退(DS Fetch 失败/过短 → 公开抓取)
  // ─────────────────────────────────────────────────────────────────────
  group('PDF 回退 — DS Fetch 读不了时走公开抓取', () {
    test('DS Fetch 失败 → 回退 fetchAnyUrl 拿到正文,候选保留', () async {
      final transport = _FakeSearchTransport(
        defaultResults: [
          hit('https://example.com/files/ai-chips.pdf', title: 'AI Chips Report'),
        ],
        fetchStatus: 404, // DS Fetch 403/404 是 PDF 的常态
      );
      MaterialSourceService.debugInjectDio(dioWithBody(articleHtml));

      final run = await MaterialDiscovery(searchClient: clientWith(transport))
          .discover(
        queries: const ['ai chips'],
        prefs: InputPreferences(),
        model: LearnerModel(),
        maxFetch: 2,
        usePublicSources: false,
        enableRefine: false,
      );

      // DS Fetch 确实试过这个 PDF URL(并失败),然后回退拿到了正文
      expect(transport.fetchedUrls, ['https://example.com/files/ai-chips.pdf']);
      expect(run.items.map((c) => c.url).toList(), [
        'https://example.com/files/ai-chips.pdf',
      ]);
      expect(run.items.single.content, contains('specialized chip'));
      expect(run.droppedCount, 0);
    });

    test('回退也失败(真 PDF 二进制)→ 返回 null 不抛,候选计入 dropped', () async {
      final transport = _FakeSearchTransport(
        defaultResults: [hit('https://example.com/files/real.pdf')],
        // DS 只拿到标题级短正文(<200 字)+ URL 像 PDF → 触发回退
        fetchContent: '# Real PDF\n\nJust a title.',
      );
      MaterialSourceService.debugInjectDio(dioWithBody('%PDF-1.7\nbinary-body'));

      final run = await MaterialDiscovery(searchClient: clientWith(transport))
          .discover(
        queries: const ['ai chips'],
        prefs: InputPreferences(),
        model: LearnerModel(),
        maxFetch: 2,
        usePublicSources: false,
        enableRefine: false,
      );

      // 回退层 fetchAnyUrl 对 PDF 二进制会抛;流水线必须吞掉 → 只记 dropped
      expect(run.items, isEmpty);
      expect(run.droppedCount, 1);
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// 假替身(不联网)
// ═══════════════════════════════════════════════════════════════════════

/// 假 Search/Fetch 传输:按请求体区分两个接口,并记录"到底搜了哪些词/抓了哪些 URL"。
class _FakeSearchTransport {
  _FakeSearchTransport({
    this.resultsByQuery = const {},
    this.defaultResults = const [],
    this.fetchStatus = 200,
    this.fetchContent = '',
  });

  /// 指定 query 的结果;没配的 query 用 [defaultResults]
  final Map<String, List<Map<String, Object?>>> resultsByQuery;
  final List<Map<String, Object?>> defaultResults;

  /// Fetch 的 HTTP 状态码(默认 200;404 模拟"DS 抓不了这页")
  final int fetchStatus;

  /// Fetch 成功时的 Markdown 正文
  final String fetchContent;

  final List<String> searchedQueries = [];
  final List<String> fetchedUrls = [];

  Future<DeepSeekHttpResponse> call(
    String url,
    Map<String, dynamic> body,
  ) async {
    if (body.containsKey('query')) {
      final query = '${body['query']}';
      searchedQueries.add(query);
      final results = resultsByQuery[query] ?? defaultResults;
      final payload = jsonEncode(<String, Object?>{'results': results});
      return DeepSeekHttpResponse(statusCode: 200, body: payload);
    }
    final target = '${body['url']}';
    fetchedUrls.add(target);
    if (fetchStatus != 200) {
      return DeepSeekHttpResponse(
        statusCode: fetchStatus,
        body: '{"error":{"message":"not found"}}',
      );
    }
    return DeepSeekHttpResponse(
      statusCode: 200,
      body: jsonEncode(<String, Object?>{
        'title': 'fetched',
        'content': fetchContent,
      }),
    );
  }
}

/// 假 Dio 适配器:固定返回一段正文(用于公开抓取层回退,不联网)。
class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
