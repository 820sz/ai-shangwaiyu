import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/deepseek_search.dart';

/// DeepSeek 官方 Search / Fetch 客户端测试(批 2 · C1-4)。
///
/// 三条纪律(和这个文件的存在理由):
/// 1. **不联网**:解析/错误映射是纯函数直接测;客户端通过注入
///    [DeepSeekTransport] 假实现来测,永远不发真实请求、不花钱;
/// 2. **不读 Hive**:`available` 判定用 [resolveEndpoint] 纯函数与
///    `autoResolve: false` 构造参数模拟,不依赖真机配置;
/// 3. 官方文档样例直接贴进来当夹具 —— 以后接口字段变了,测试先红。
///
/// 官方文档:https://api-docs.deepseek.com/zh-cn/guides/search
void main() {
  // ── 测试夹具:官方文档里的样例响应 ─────────────────────────────────────
  const officialSearchJson = '''
{
  "results": [
    {
      "rerank_score": 2.4,
      "title": "DeepSeek V4 模型发布",
      "url": "https://example.com/deepseek-v4",
      "snippet": "DeepSeek V4 已上线，支持工具调用与长上下文。",
      "summary": "DeepSeek 发布了 V4 模型。此次发布改进了工具调用与长上下文能力，适合 Agent 工作流。",
      "content": "DeepSeek V4 现已正式上线……",
      "site_name": "Example News",
      "site_icon": "https://example.com/favicon.ico",
      "date": "2026-06-01T00:00:00+00:00",
      "authority": 3
    },
    {
      "rerank_score": 1.1,
      "title": "Second result",
      "url": "https://example.com/second",
      "snippet": "短摘要",
      "summary": "长摘要",
      "content": "",
      "site_name": null,
      "site_icon": null,
      "date": null,
      "authority": 1
    }
  ]
}
''';

  const officialFetchJson = '''
{"title": "Example article", "content": "# Example article\\n\\nArticle content."}
''';

  /// 构造"可用"客户端:显式端点 + 假传输(绝不联网)
  DeepSeekSearchClient clientWith(
    DeepSeekTransport transport, {
    String baseUrl = 'https://api.deepseek.com',
  }) {
    return DeepSeekSearchClient(
      endpoint: DeepSeekEndpoint(baseUrl: baseUrl, apiKey: 'sk-test'),
      transport: transport,
    );
  }

  group('parseSearchResults', () {
    test('官方样例:字段全部解析(含日期/权威性/排序分)', () {
      final parsed = parseSearchResults(_decode(officialSearchJson));
      expect(parsed, hasLength(2));

      final first = parsed.first;
      expect(first.title, 'DeepSeek V4 模型发布');
      expect(first.url, 'https://example.com/deepseek-v4');
      expect(first.snippet, contains('工具调用'));
      expect(first.summary, contains('Agent 工作流'));
      expect(first.content, isNotEmpty);
      expect(first.siteName, 'Example News');
      expect(first.date?.toUtc().year, 2026);
      expect(first.date?.toUtc().month, 6);
      expect(first.authority, 3);
      expect(first.rerankScore, closeTo(2.4, 1e-9));
      // 官方口径的派生判断
      expect(first.isHighQuality, isTrue, reason: 'rerank_score ≥1.5 是"优质结果"');
      expect(first.isAuthoritative, isTrue, reason: 'authority ≥3 是"极权威"');
      expect(first.hasContent, isTrue);

      final second = parsed[1];
      expect(second.siteName, isEmpty, reason: 'site_name 为 null → 空串');
      expect(second.date, isNull);
      expect(second.hasContent, isFalse);
      expect(second.isHighQuality, isFalse);
    });

    test('results 为空 / 不是 List / 缺字段 → 空列表不崩', () {
      expect(parseSearchResults(const <String, dynamic>{}), isEmpty);
      expect(
        parseSearchResults(const <String, dynamic>{'results': <dynamic>[]}),
        isEmpty,
      );
      expect(
        parseSearchResults(const <String, dynamic>{'results': 'oops'}),
        isEmpty,
      );
      expect(
        parseSearchResults(const <String, dynamic>{'results': null}),
        isEmpty,
      );
    });

    test('类型脏值:authority/rerank_score 是字符串、date 非法 → 容错不抛', () {
      final parsed = parseSearchResults(<String, dynamic>{
        'results': <dynamic>[
          <String, dynamic>{
            'title': 'dirty',
            'url': 'https://example.com/dirty',
            'authority': '3', // 字符串数字
            'rerank_score': '1.5',
            'date': 'not-a-date',
            'site_name': 123, // 类型不对
            'snippet': null,
            'summary': null,
            'content': null,
          },
        ],
      });
      expect(parsed, hasLength(1));
      expect(parsed.single.authority, 3);
      expect(parsed.single.rerankScore, closeTo(1.5, 1e-9));
      expect(parsed.single.date, isNull);
      expect(parsed.single.siteName, isEmpty);
    });

    test('没有 url 的结果直接丢弃(防无出处/幻觉内容进材料卡)', () {
      final parsed = parseSearchResults(<String, dynamic>{
        'results': <dynamic>[
          <String, dynamic>{'title': '没有 url', 'snippet': 'x'},
          <String, dynamic>{'title': '有 url', 'url': 'https://example.com/ok'},
          <String, dynamic>{'title': '空 url', 'url': '   '},
          'not-a-map', // 列表里混了非 Map 元素
        ],
      });
      expect(parsed, hasLength(1));
      expect(parsed.single.url, 'https://example.com/ok');
    });
  });

  group('parseFetchResult', () {
    test('正常响应 → title + Markdown 正文', () {
      final parsed = parseFetchResult(_decode(officialFetchJson));
      expect(parsed, isNotNull);
      expect(parsed!.title, 'Example article');
      expect(parsed.content, contains('# Example article'));
      expect(parsed.length, greaterThan(10));
    });

    test('缺 content / content 全空白 → null(等于没抓到,官方不计费)', () {
      expect(parseFetchResult(const <String, dynamic>{}), isNull);
      expect(parseFetchResult(const <String, dynamic>{'title': 'x'}), isNull);
      expect(
        parseFetchResult(const <String, dynamic>{'content': '   \n\t '}),
        isNull,
      );
      expect(
        parseFetchResult(const <String, dynamic>{'content': 123}),
        isNull,
        reason: 'content 类型不对也当没抓到',
      );
    });
  });

  group('mapStatusError:官方错误码 → 中文人话', () {
    test('8 个常见状态码各自 kind 正确、文案带状态码/下一步', () {
      final cases = <int, DeepSeekSearchErrorKind>{
        400: DeepSeekSearchErrorKind.badRequest,
        401: DeepSeekSearchErrorKind.auth,
        402: DeepSeekSearchErrorKind.balance,
        403: DeepSeekSearchErrorKind.forbidden,
        404: DeepSeekSearchErrorKind.notFound,
        408: DeepSeekSearchErrorKind.requestTimeout,
        413: DeepSeekSearchErrorKind.payloadTooLarge,
        429: DeepSeekSearchErrorKind.rateLimit,
        500: DeepSeekSearchErrorKind.server,
        504: DeepSeekSearchErrorKind.server,
      };
      cases.forEach((status, kind) {
        final error = mapStatusError(status, '');
        expect(error.kind, kind, reason: 'HTTP $status 分类不对');
        expect(error.statusCode, status);
        expect(error.message, contains('$status'), reason: '文案必须带状态码');
      });

      // 几个必须给"下一步"的高频错误
      expect(mapStatusError(401, '').message, contains('API Key'));
      expect(mapStatusError(402, '').message, contains('余额'));
      expect(mapStatusError(403, '').message, contains('安全策略'));
      expect(mapStatusError(404, '').message, contains('正文'));
      expect(mapStatusError(429, '').message, contains('QPS'));
      expect(mapStatusError(402, '').needsConfiguration, isTrue);
      expect(mapStatusError(401, '').needsConfiguration, isTrue);
      expect(mapStatusError(429, '').isRetryable, isTrue);
      expect(mapStatusError(400, '').isRetryable, isFalse);
    });

    test('未知状态码/null → unknown,不崩', () {
      expect(mapStatusError(418, '').kind, DeepSeekSearchErrorKind.unknown);
      expect(mapStatusError(null, '').kind, DeepSeekSearchErrorKind.unknown);
    });

    test('官方错误体里的服务端文案被拼进 message(400 参数错误样例)', () {
      final error = mapStatusError(
        400,
        '{"error":{"message":"\'count\' must be between 1 and 50",'
        '"type":"invalid_request_error","param":null,"code":"invalid_request_error"}}',
      );
      expect(error.serverMessage, contains('count'));
      expect(error.message, contains('count'), reason: '服务端文案要带上,便于排查');
    });
  });

  group('extractApiErrorMessage', () {
    test('三种官方/网关错误体形态都能抠出来', () {
      expect(extractApiErrorMessage('{"error":{"message":"余额不足"}}'), '余额不足');
      expect(extractApiErrorMessage('{"error":"boom"}'), 'boom');
      expect(extractApiErrorMessage('{"message":"直接 message"}'), '直接 message');
      expect(extractApiErrorMessage('纯文本错误'), '纯文本错误');
      expect(extractApiErrorMessage('   '), isEmpty);
    });

    test('HTML 错误页会被截断(不能把整页塞进 UI)', () {
      final html = '<html>${'x' * 1000}</html>';
      final extracted = extractApiErrorMessage(html);
      expect(extracted.length, lessThanOrEqualTo(201));
      expect(extracted, endsWith('…'));
    });
  });

  group('URL / 请求体纯函数', () {
    test('searchUrlFor/fetchUrlFor:baseUrl 带不带 /v1、带不带尾斜杠都归一', () {
      const expectedSearch = 'https://api.deepseek.com/v1/tools/search';
      expect(searchUrlFor('https://api.deepseek.com'), expectedSearch);
      expect(searchUrlFor('https://api.deepseek.com/'), expectedSearch);
      expect(searchUrlFor('https://api.deepseek.com/v1'), expectedSearch);
      expect(searchUrlFor('https://api.deepseek.com/v1/'), expectedSearch);
      expect(
        fetchUrlFor('https://api.deepseek.com'),
        'https://api.deepseek.com/v1/tools/fetch',
      );
    });

    test('isFetchableUrl:只接受含 host 的 http/https 且长度 ≤8192', () {
      expect(isFetchableUrl('https://example.com/a?b=1'), isTrue);
      expect(isFetchableUrl(' http://example.com '), isTrue);
      expect(isFetchableUrl(''), isFalse);
      expect(isFetchableUrl('example.com'), isFalse);
      expect(isFetchableUrl('ftp://example.com/x'), isFalse);
      expect(isFetchableUrl('https://'), isFalse);
      expect(
        isFetchableUrl('https://example.com/${'a' * 8200}'),
        isFalse,
        reason: '官方上限 8192 字符',
      );
    });

    test('buildSearchBody:count 夹紧 1~50、need_content 布尔、ori_question 可选', () {
      final body = buildSearchBody('  stoicism  ', count: 5, needContent: true);
      expect(body['query'], 'stoicism', reason: 'query 要 trim');
      expect(body['count'], 5);
      expect(body['need_content'], true);
      expect(body.containsKey('ori_question'), isFalse);

      expect(buildSearchBody('x', count: 0)['count'], 1);
      expect(buildSearchBody('x', count: 999)['count'], 50);

      final withOri = buildSearchBody('x', oriQuestion: '  为什么读这本书  ');
      expect(withOri['ori_question'], '为什么读这本书');
      expect(
        buildSearchBody('x', oriQuestion: '   ').containsKey('ori_question'),
        isFalse,
      );
    });
  });

  group('resolveEndpoint:只认 DeepSeek 官方 Key/端点', () {
    test('副槽位是 DS 官方 → 用副槽位', () {
      final ep = resolveEndpoint(
        secondaryApiKey: 'sk-secondary',
        secondaryBaseUrl: 'https://api.deepseek.com',
        primaryApiKey: 'ark-primary',
        primaryBaseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      );
      expect(ep, isNotNull);
      expect(ep!.apiKey, 'sk-secondary');
      expect(ep.baseUrl, contains('deepseek.com'));
    });

    test('副槽位是方舟 Key → 跳过,回落主槽位(用户把 DS 官方配在主槽位的情况)', () {
      final ep = resolveEndpoint(
        secondaryApiKey: 'ark-secondary',
        secondaryBaseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
        primaryApiKey: 'sk-primary',
        primaryBaseUrl: 'https://api.deepseek.com',
      );
      expect(ep, isNotNull);
      expect(ep!.apiKey, 'sk-primary');
    });

    test('没有 DS 官方 Key → null(不拿方舟 Key 瞎调)', () {
      expect(
        resolveEndpoint(
          secondaryApiKey: null,
          secondaryBaseUrl: 'https://api.deepseek.com',
          primaryApiKey: 'ark-primary',
          primaryBaseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
        ),
        isNull,
      );
      expect(
        resolveEndpoint(
          secondaryApiKey: '',
          secondaryBaseUrl: 'https://api.deepseek.com',
        ),
        isNull,
      );
    });

    test('sk- Key 但 baseUrl 不是 deepseek.com(第三方中转)→ null', () {
      expect(
        resolveEndpoint(
          secondaryApiKey: 'sk-third-party',
          secondaryBaseUrl: 'https://openai-proxy.example.com/v1',
        ),
        isNull,
        reason: 'Search/Fetch 是官方新接口,中转基本没实现,不能拿去调',
      );
    });

    test('DS Key 配在方舟端点上(历史错配)→ null,不误发', () {
      expect(
        resolveEndpoint(
          secondaryApiKey: 'sk-deepseek',
          secondaryBaseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
          primaryApiKey: null,
          primaryBaseUrl: '',
        ),
        isNull,
      );
    });
  });

  group('DeepSeekSearchClient', () {
    test('没有 DS 官方端点 → available=false,search/fetch 不发请求', () async {
      var called = 0;
      final client = DeepSeekSearchClient(
        autoResolve: false, // 不读真 Hive:模拟"用户没配 DS 官方 Key"
        transport: (url, body) async {
          called++;
          return const DeepSeekHttpResponse(statusCode: 200, body: '{}');
        },
      );
      expect(client.available, isFalse);
      expect(client.unavailableReason, contains('DeepSeek'));

      expect(await client.search('x'), isEmpty);
      expect(client.lastError?.kind, DeepSeekSearchErrorKind.auth);
      expect(await client.fetch('https://example.com'), isNull);
      expect(client.lastError?.needsConfiguration, isTrue);
      expect(called, 0, reason: '不可用时一次请求都不该发(不花钱)');
    });

    test('search 成功:命中解析 + 请求体/URL 正确 + 计费 1 次', () async {
      final calls = <({String url, Map<String, dynamic> body})>[];
      final client = clientWith((url, body) async {
        calls.add((url: url, body: body));
        return const DeepSeekHttpResponse(
          statusCode: 200,
          body: officialSearchJson,
        );
      });

      expect(client.available, isTrue);
      final hits = await client.search(
        'DeepSeek V4',
        count: 5,
        needContent: true,
      );

      expect(hits, hasLength(2));
      expect(client.lastError, isNull);
      expect(calls, hasLength(1));
      expect(calls.single.url, 'https://api.deepseek.com/v1/tools/search');
      expect(calls.single.body['query'], 'DeepSeek V4');
      expect(calls.single.body['count'], 5);
      expect(calls.single.body['need_content'], true);

      expect(client.requestCount, 1, reason: '200 + results 非空 = 官方计费一次');
      expect(client.estimatedCostCny, closeTo(0.005, 1e-9));
    });

    test('search 200 但没结果:空列表、不计费、无错误(不是失败)', () async {
      final client = clientWith(
        (url, body) async => const DeepSeekHttpResponse(
          statusCode: 200,
          body: '{"results": []}',
        ),
      );
      expect(await client.search('nonsense'), isEmpty);
      expect(client.lastError, isNull, reason: '"没搜到"≠"失败",UI 要能区分');
      expect(client.requestCount, 0);
    });

    test('search 401/402:返回空列表不抛,lastError 让用户知道去改配置', () async {
      var statusCode = 401;
      final client = clientWith(
        (url, body) async => DeepSeekHttpResponse(
          statusCode: statusCode,
          body: '{"error":{"message":"bad key"}}',
        ),
      );

      expect(await client.search('x'), isEmpty);
      expect(client.lastError?.kind, DeepSeekSearchErrorKind.auth);
      expect(client.lastError?.needsConfiguration, isTrue);
      expect(client.requestCount, 0);

      statusCode = 402;
      expect(await client.search('x'), isEmpty);
      expect(client.lastError?.kind, DeepSeekSearchErrorKind.balance);
      expect(client.lastError?.message, contains('余额'));
    });

    test('search 结果全部缺 url:全部丢弃,但钱已花 → lastError 说明原因', () async {
      final client = clientWith(
        (url, body) async => const DeepSeekHttpResponse(
          statusCode: 200,
          body: '{"results":[{"title":"a"},{"title":"b","url":""}]}',
        ),
      );
      expect(await client.search('x'), isEmpty);
      expect(client.requestCount, 1, reason: '服务端按"有结果"计费,统计要诚实');
      expect(client.lastError?.message, contains('URL'));
    });

    test('search 网络异常/超时:不抛,映射成可重试错误', () async {
      final timeoutClient = clientWith((url, body) async {
        throw DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.receiveTimeout,
        );
      });
      expect(await timeoutClient.search('x'), isEmpty);
      expect(
        timeoutClient.lastError?.kind,
        DeepSeekSearchErrorKind.requestTimeout,
      );
      expect(timeoutClient.lastError?.isRetryable, isTrue);

      final brokenClient = clientWith(
        (url, body) async => throw Exception('socket closed'),
      );
      expect(await brokenClient.search('x'), isEmpty);
      expect(brokenClient.lastError?.kind, DeepSeekSearchErrorKind.network);
      expect(brokenClient.requestCount, 0);
    });

    test('fetch 成功:返回正文 + 计费 1 次', () async {
      final calls = <({String url, Map<String, dynamic> body})>[];
      final client = clientWith((url, body) async {
        calls.add((url: url, body: body));
        return const DeepSeekHttpResponse(
          statusCode: 200,
          body: officialFetchJson,
        );
      });
      final page = await client.fetch('https://example.com/article');
      expect(page, isNotNull);
      expect(page!.content, contains('Article content'));
      expect(calls.single.url, 'https://api.deepseek.com/v1/tools/fetch');
      expect(calls.single.body['url'], 'https://example.com/article');
      expect(client.requestCount, 1);
      expect(client.lastError, isNull);
    });

    test('fetch 404(抓不到正文):null + notFound,不计费', () async {
      final client = clientWith(
        (url, body) async => const DeepSeekHttpResponse(
          statusCode: 404,
          body: '{"error":{"message":"not found"}}',
        ),
      );
      expect(await client.fetch('https://example.com/gone'), isNull);
      expect(client.lastError?.kind, DeepSeekSearchErrorKind.notFound);
      expect(client.requestCount, 0);
    });

    test('fetch 200 但正文为空:按"没抓到"处理,不计费', () async {
      final client = clientWith(
        (url, body) async => const DeepSeekHttpResponse(
          statusCode: 200,
          body: '{"title":"blank","content":"  "}',
        ),
      );
      expect(await client.fetch('https://example.com/blank'), isNull);
      expect(client.lastError?.kind, DeepSeekSearchErrorKind.notFound);
      expect(client.requestCount, 0);
    });

    test('fetch URL 非法:不发请求、不计费、给参数错误', () async {
      var called = 0;
      final client = clientWith((url, body) async {
        called++;
        return const DeepSeekHttpResponse(statusCode: 200, body: '{}');
      });
      expect(await client.fetch('not-a-url'), isNull);
      expect(client.lastError?.kind, DeepSeekSearchErrorKind.badRequest);
      expect(called, 0);
      expect(client.requestCount, 0);
    });

    test('成本口径:search/fetch 合计计费,resetCost 可清零(UI 按轮次显示)', () async {
      final client = clientWith((url, body) async {
        if (url.contains('/fetch')) {
          return const DeepSeekHttpResponse(
            statusCode: 200,
            body: officialFetchJson,
          );
        }
        return const DeepSeekHttpResponse(
          statusCode: 200,
          body: officialSearchJson,
        );
      });
      await client.search('a');
      await client.search('b');
      await client.fetch('https://example.com/x');
      expect(client.requestCount, 3);
      expect(client.estimatedCostCny, closeTo(0.015, 1e-9));

      client.resetCost();
      expect(client.requestCount, 0);
      expect(client.estimatedCostCny, 0);

      // 常量与官方价格一致(5 元/千次成功请求)
      expect(DeepSeekSearchClient.cnyPerThousandRequests, 5.0);
      expect(DeepSeekSearchClient.searchQps, 100);
      expect(DeepSeekSearchClient.fetchQps, 25);
    });
  });

  group('mapTransportError', () {
    test('Dio 超时/断网分别映射到 requestTimeout / network', () {
      DioException dio(DioExceptionType type) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: type,
      );

      expect(
        mapTransportError(dio(DioExceptionType.connectionTimeout)).kind,
        DeepSeekSearchErrorKind.requestTimeout,
      );
      expect(
        mapTransportError(dio(DioExceptionType.sendTimeout)).kind,
        DeepSeekSearchErrorKind.requestTimeout,
      );
      expect(
        mapTransportError(dio(DioExceptionType.receiveTimeout)).kind,
        DeepSeekSearchErrorKind.requestTimeout,
      );
      expect(
        mapTransportError(dio(DioExceptionType.connectionError)).kind,
        DeepSeekSearchErrorKind.network,
      );
      expect(
        mapTransportError(Exception('boom')).kind,
        DeepSeekSearchErrorKind.network,
      );
    });
  });
}

/// 测试内的小工具:把 JSON 字符串解成 Map(夹具全是合法 JSON,失败直接抛)
Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;
