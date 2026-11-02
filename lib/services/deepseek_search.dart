import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_endpoint.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// DeepSeek 官方 **Search / Fetch** 客户端(批 2 · C1-4 底座)。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 官方文档:https://api-docs.deepseek.com/zh-cn/guides/search
/// 这两个接口 2026-10-17 开放,定位是"给 Agent / RAG 提供实时网页内容":
/// - **Search**:按 query 搜网页,返回结构化候选(标题/URL/摘要/正文/权威性/时间);
/// - **Fetch** :抓单个网页,返回 Markdown 正文。
///
/// 计费:各自 **5 元 / 1000 次成功请求**;只有 HTTP 200 且**产生结果**才计费
/// (Search 的 `results` 非空、Fetch 返回网页正文),失败/无结果/超时不计费。
/// QPS:Search 100、Fetch 25(按账号计;Fetch 还按目标域名单独限速)。
///
/// ## 为什么这个文件必须自包含、且只认 DeepSeek 官方端点
/// 1. App 是 BYOK:用户可能把方舟(火山)Key 配在主槽位、DeepSeek Key 配在副槽位;
///    Search/Fetch **只存在于 `api.deepseek.com`**,拿方舟 Key 去调必然 401/404;
/// 2. 所以 [DeepSeekSearchClient.available] 的判定是"**能拿到 DS 官方 Key +
///    DS 官方 baseUrl**"([resolveEndpoint] 纯函数):拿不到就整体不可用
///    ([DeepSeekSearchClient.unavailableReason] 给中文引导),绝不拿方舟 Key 试;
/// 3. 解析/错误映射全部是**纯函数、不碰网络**,检索流水线与 UI 可以直接复用,
///    也方便单测(本仓库测试不联网)。
///
/// ## 边界(和官方能力一致,不吹牛)
/// - 不做浏览器渲染:需要 JS 的页面 Fetch 会 404;
/// - 不绕验证码/登录墙/付费墙:403/404 是常态,调用方要有降级路径;
/// - 单次 fetch 的 URL ≤ 8192 字符、必须是含 host 的 http/https;
/// - **所有返回必须带 url**:没 url 的结果直接丢弃 —— 否则"模型幻觉出来的
///   书名/链接"会被当成真实材料进卡片。
///
/// ## 调用示例(检索流水线里可以直接用)
/// ```dart
/// final client = DeepSeekSearchClient();
/// if (!client.available) {
///   // 引导用户去「设置 → API 设置」配置 DeepSeek 官方 Key(副槽位)
///   return;
/// }
/// final hits = await client.search('stoicism meditations', count: 5, needContent: true);
/// if (client.lastError != null) { /* auth/balance 等,lastError.message 是中文人话 */ }
/// final page = hits.isEmpty ? null : await client.fetch(hits.first.url);
/// debugPrint('已计费 ${client.requestCount} 次 ≈ ${client.estimatedCostCny} 元');
/// ```

// ═══════════════════════════════════════════════════════════════════════
// 数据模型
// ═══════════════════════════════════════════════════════════════════════

/// 一条 Search 结果(官方 `results[]` 的一项)。
///
/// 字段全部**容错解析**:官方文档说缺省时 `site_name`/`site_icon`/`date` 为 null,
/// 实测网关还可能把数字发成字符串 —— 一条脏数据不能让整批结果崩掉。
class DeepSeekSearchResult {
  /// 标题(缺失 = 空串)
  final String title;

  /// 结果链接(**必有**;无 url 的结果在 [parseSearchResults] 里就被丢弃了)
  final String url;

  /// 短摘要(约 100~200 字,适合前端直接展示)
  final String snippet;

  /// 长摘要(约 600~800 字,适合喂给模型阅读)
  final String summary;

  /// 网页正文(仅 `need_content: true` 时非空)
  final String content;

  /// 站点名(缺失 = 空串)
  final String siteName;

  /// 发布时间(ISO 8601;缺失/解析失败 = null)
  final DateTime? date;

  /// 权威性 0~4,**-1 = 未知**(官方口径:≥3 为极权威)
  final int authority;

  /// 排序分 0~3(官方口径:≥1.5 为优质结果)
  final double rerankScore;

  const DeepSeekSearchResult({
    required this.title,
    required this.url,
    this.snippet = '',
    this.summary = '',
    this.content = '',
    this.siteName = '',
    this.date,
    this.authority = -1,
    this.rerankScore = 0,
  });

  /// 是否有正文(判断要不要再调 Fetch)
  bool get hasContent => content.trim().isNotEmpty;

  /// 官方口径的"优质结果"(≥1.5)
  bool get isHighQuality => rerankScore >= 1.5;

  /// 官方口径的"极权威"(≥3)
  bool get isAuthoritative => authority >= 3;

  /// 容错解析一条结果(缺字段/类型不符都当缺省,绝不抛)
  factory DeepSeekSearchResult.fromJson(Map<String, dynamic> json) {
    return DeepSeekSearchResult(
      title: _str(json['title']),
      url: _str(json['url']).trim(),
      snippet: _str(json['snippet']),
      summary: _str(json['summary']),
      content: _str(json['content']),
      siteName: _str(json['site_name']),
      date: _date(json['date']),
      authority: _int(json['authority'], fallback: -1),
      rerankScore: _double(json['rerank_score']),
    );
  }

  @override
  String toString() => 'DeepSeekSearchResult($title, $url, 权威$authority)';
}

/// Fetch 成功时的结果(官方只返回 title + Markdown 正文)。
class DeepSeekFetchResult {
  /// 页面标题(缺失 = 空串)
  final String title;

  /// Markdown 正文(**非空**才算成功,空正文由 [parseFetchResult] 返回 null)
  final String content;

  const DeepSeekFetchResult({required this.title, required this.content});

  /// 正文长度(UI 可以据此提示"抓到的内容太短")
  int get length => content.length;

  @override
  String toString() => 'DeepSeekFetchResult($title, ${content.length} 字)';
}

/// 错误分类(UI 按 kind 给不同引导:去改 Key / 去充值 / 换一篇 / 等一会)。
enum DeepSeekSearchErrorKind {
  /// 401:Key 缺失/无效(在 Search 客户端里也用于"压根没配 DS 官方 Key")
  auth,

  /// 402:账户余额不足
  balance,

  /// 403:被拒绝(Fetch 被目标站点的安全策略拒绝)
  forbidden,

  /// 404:页面抓不到可用正文 / 地址不存在(Fetch 最常见,不等于客户端 bug)
  notFound,

  /// 429:超过 QPS(Search 100 / Fetch 25,按账号)
  rateLimit,

  /// 408 / 连接超时:等一会重试
  requestTimeout,

  /// 400:参数不合法(调用方代码问题,不要重试)
  badRequest,

  /// 413:请求体超过大小限制
  payloadTooLarge,

  /// 500 / 504:服务端(或下游)出错,可重试
  server,

  /// 网络层失败(断网/DNS/代理),和 API 无关
  network,

  /// 其它(返回不是合法 JSON 等)
  unknown,
}

/// Search/Fetch 失败原因。**中文人话 + 状态码**,可直接显示给用户。
///
/// 注意:正常链路里客户端**不抛**这个异常([DeepSeekSearchClient.search] /
/// [fetch] 返回空/ null 并把错误放进 `lastError`),只有调用方自己想把
/// 错误往上抛时才用它包装。
class DeepSeekSearchException implements Exception {
  final DeepSeekSearchErrorKind kind;

  /// 中文人话(已含 HTTP 状态码与下一步建议)
  final String message;

  /// HTTP 状态码;网络层失败/参数校验失败时为 null
  final int? statusCode;

  /// 服务端返回的原始错误文案(可能为空;排查用,不要直接给用户看)
  final String? serverMessage;

  const DeepSeekSearchException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.serverMessage,
  });

  /// 需要用户去改配置(Key)的错误 —— UI 应该给"去设置"入口
  bool get needsConfiguration =>
      kind == DeepSeekSearchErrorKind.auth ||
      kind == DeepSeekSearchErrorKind.balance;

  /// 值得稍后重试的错误(限速/超时/服务端/网络)—— 调用方可自动退避重试
  bool get isRetryable =>
      kind == DeepSeekSearchErrorKind.rateLimit ||
      kind == DeepSeekSearchErrorKind.requestTimeout ||
      kind == DeepSeekSearchErrorKind.server ||
      kind == DeepSeekSearchErrorKind.network;

  @override
  String toString() => message;
}

// ═══════════════════════════════════════════════════════════════════════
// 纯函数:解析
// ═══════════════════════════════════════════════════════════════════════

/// 解析 Search 响应(`{"results":[...]}`)。
///
/// 规则:
/// - `results` 不是 List / 为空 → 返回空列表(官方"搜到但没有匹配"就是空数组);
/// - **没有 `url` 的条目直接丢弃**(防止无出处内容进材料卡);
/// - 单条字段类型不对不抛(见 [DeepSeekSearchResult.fromJson])。
List<DeepSeekSearchResult> parseSearchResults(Map<String, dynamic> json) {
  final raw = json['results'];
  if (raw is! List || raw.isEmpty) return const <DeepSeekSearchResult>[];
  final out = <DeepSeekSearchResult>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final result = DeepSeekSearchResult.fromJson(
      Map<String, dynamic>.from(item),
    );
    if (result.url.isEmpty) continue; // 无 url = 不可信,丢弃
    out.add(result);
  }
  return out;
}

/// 解析 Fetch 响应(`{"title": "...", "content": "Markdown"}`)。
///
/// 返回 null 的两种情况(都等于"这次没抓到正文",官方不计费):
/// - 响应里没有 `content` 字段 / content 不是字符串;
/// - content 全是空白。
DeepSeekFetchResult? parseFetchResult(Map<String, dynamic> json) {
  final content = _str(json['content']).trim();
  if (content.isEmpty) return null;
  return DeepSeekFetchResult(
    title: _str(json['title']).trim(),
    content: content,
  );
}

/// HTTP 状态码 → 中文人话错误(官方 Search/Fetch 错误码表)。
///
/// 为什么独立成纯函数:错误文案是"用户看到的那句话",必须能被单测锁住 ——
/// 同一个 402 在不同页面写两套文案,用户会以为是两个不同的问题。
DeepSeekSearchException mapStatusError(int? statusCode, String body) {
  final serverMessage = extractApiErrorMessage(body);
  final suffix = serverMessage.isEmpty ? '' : ':$serverMessage';

  DeepSeekSearchErrorKind kind;
  String message;
  switch (statusCode) {
    case 400:
      kind = DeepSeekSearchErrorKind.badRequest;
      message = '请求参数不合法(400)$suffix';
    case 401:
      kind = DeepSeekSearchErrorKind.auth;
      message =
          'DeepSeek API Key 无效或已过期(401)$suffix —— '
          '请到「设置 → API 设置」检查 DeepSeek 官方 Key(sk- 开头)';
    case 402:
      kind = DeepSeekSearchErrorKind.balance;
      message =
          'DeepSeek 账户余额不足(402)$suffix —— 请先充值;'
          'Search/Fetch 按 5 元/千次成功请求计费';
    case 403:
      kind = DeepSeekSearchErrorKind.forbidden;
      message =
          '请求被拒绝(403)$suffix —— 如果是在抓网页,'
          '可能是目标站点的安全策略不让抓,换一篇或改用公开源';
    case 404:
      kind = DeepSeekSearchErrorKind.notFound;
      message =
          '没能拿到网页正文(404)$suffix —— '
          '常见原因:地址失效、需要登录/JS 渲染、或站点不让抓';
    case 408:
      kind = DeepSeekSearchErrorKind.requestTimeout;
      message = '服务端读取超时(408)$suffix —— 稍后重试';
    case 413:
      kind = DeepSeekSearchErrorKind.payloadTooLarge;
      message = '请求体超过大小限制(413)$suffix';
    case 429:
      kind = DeepSeekSearchErrorKind.rateLimit;
      message =
          '请求太频繁(429)$suffix —— '
          'Search 限 100 QPS、Fetch 限 25 QPS(按账号),稍等再试';
    case 500:
      kind = DeepSeekSearchErrorKind.server;
      message = 'DeepSeek 服务端错误(500)$suffix —— 可稍后重试';
    case 504:
      kind = DeepSeekSearchErrorKind.server;
      message = '服务端或下游超时(504)$suffix —— 可稍后重试';
    default:
      kind = DeepSeekSearchErrorKind.unknown;
      message = statusCode == null
          ? '请求失败:$suffix'
          : '请求失败(HTTP $statusCode)$suffix';
  }
  return DeepSeekSearchException(
    kind: kind,
    message: message,
    statusCode: statusCode,
    serverMessage: serverMessage.isEmpty ? null : serverMessage,
  );
}

/// 从官方错误体里抠出服务端文案(兼容 3 种形态):
/// - `{"error":{"message":"..."}}`(官方 Search/Fetch 的错误格式);
/// - `{"error":"..."}`;
/// - 纯文本正文(网关错误页)。
///
/// 抠不出来返回空串(调用方自己拼中文指引,不要给用户看一坨 HTML)。
String extractApiErrorMessage(String body) {
  final text = body.trim();
  if (text.isEmpty) return '';
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map) {
        final m = error['message'];
        if (m is String && m.trim().isNotEmpty) return m.trim();
      }
      if (error is String && error.trim().isNotEmpty) return error.trim();
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
    }
  } catch (_) {
    // 不是 JSON:按纯文本返回(截断,避免 HTML 错误页撑爆 UI)
  }
  if (text.length > 200) return '${text.substring(0, 200)}…';
  return text;
}

/// 网络层异常 → 错误分类(超时可重试、断网让用户查网络;不把 Dio 英文栈丢给用户)。
DeepSeekSearchException mapTransportError(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const DeepSeekSearchException(
          kind: DeepSeekSearchErrorKind.requestTimeout,
          message: '请求超时 —— 检查网络后重试(搜索服务在国内通常 1~3 秒返回)',
        );
      case DioExceptionType.connectionError:
        return const DeepSeekSearchException(
          kind: DeepSeekSearchErrorKind.network,
          message: '连不上 DeepSeek 服务 —— 检查网络/代理后重试',
        );
      case DioExceptionType.cancel:
        return const DeepSeekSearchException(
          kind: DeepSeekSearchErrorKind.network,
          message: '请求已被取消',
        );
      case DioExceptionType.badCertificate:
        return const DeepSeekSearchException(
          kind: DeepSeekSearchErrorKind.network,
          message: 'HTTPS 证书校验失败 —— 检查网络环境后重试',
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }
  }
  return DeepSeekSearchException(
    kind: DeepSeekSearchErrorKind.network,
    message: '网络请求失败:${_short(error)}',
  );
}

// ═══════════════════════════════════════════════════════════════════════
// 纯函数:URL / 请求体
// ═══════════════════════════════════════════════════════════════════════

/// Search 的**绝对 URL**。
///
/// 为什么要拼绝对 URL 而不是交给 Dio 的 baseUrl:用户可能在 baseUrl 里带了
/// `/v1`(甚至末尾斜杠),Dio 的"baseUrl + 绝对路径"拼接会把 baseUrl 的路径
/// 吃掉 → 请求打到 `/tools/search`(404)。这里统一归一:
/// - `https://api.deepseek.com`      → `…/v1/tools/search`
/// - `https://api.deepseek.com/v1`   → `…/v1/tools/search`
/// - `https://api.deepseek.com/v1/`  → 同上(去尾斜杠)
String searchUrlFor(String baseUrl) => _toolsUrl(baseUrl, 'search');

/// Fetch 的绝对 URL(规则同 [searchUrlFor])
String fetchUrlFor(String baseUrl) => _toolsUrl(baseUrl, 'fetch');

String _toolsUrl(String baseUrl, String tool) {
  var base = baseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.toLowerCase().endsWith('/v1')) return '$base/tools/$tool';
  return '$base/v1/tools/$tool';
}

/// 单次 Fetch 的 URL 是否合法(官方要求:含 host 的 HTTP/HTTPS,
/// 长度 ≤ 8192 字符)。
bool isFetchableUrl(String url) {
  final raw = url.trim();
  if (raw.isEmpty || raw.length > 8192) return false;
  final uri = Uri.tryParse(raw);
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return false;
  return uri.host.trim().isNotEmpty;
}

/// 构造 Search 请求体(纯函数,便于单测与排查"到底发了什么")。
///
/// `count` 官方范围 1~50,这里**夹紧**而不是报错:调用方多写一个 0 不应让
/// 整个检索失败。`query` 必须非空(空 query 在 [DeepSeekSearchClient.search]
/// 里就被拦下,不发请求、不计费)。
Map<String, dynamic> buildSearchBody(
  String query, {
  int count = 10,
  bool needContent = false,
  String? oriQuestion,
}) {
  final body = <String, dynamic>{
    'query': query.trim(),
    'count': count.clamp(1, 50),
    'need_content': needContent,
  };
  final ori = oriQuestion?.trim() ?? '';
  if (ori.isNotEmpty) body['ori_question'] = ori;
  return body;
}

// ═══════════════════════════════════════════════════════════════════════
// 端点解析:只认 DeepSeek 官方
// ═══════════════════════════════════════════════════════════════════════

/// 一个可用的 DeepSeek 官方端点(Key + baseUrl)。
class DeepSeekEndpoint {
  final String baseUrl;
  final String apiKey;

  const DeepSeekEndpoint({required this.baseUrl, required this.apiKey});
}

/// 从两个槽位的 (Key, baseUrl) 里挑出 **DeepSeek 官方** 端点(纯函数)。
///
/// 判定条件(三条都要满足,缺一即视为不可用 —— 宁可不搜,也不拿方舟 Key 瞎调):
/// 1. Key 非空;
/// 2. Key 以 `sk-` 开头(DeepSeek 官方 Key;火山方舟是 `ark-`);
/// 3. baseUrl 含 `deepseek.com`(官方域名;第三方中转即使发 sk- Key 也不用,
///    因为 Search/Fetch 是官方新接口,中转基本没实现)。
///
/// 优先副槽位(专项文本,默认就是 DeepSeek),没有再回落到主槽位
/// (用户完全可能把 DeepSeek 官方配在主槽位)。
DeepSeekEndpoint? resolveEndpoint({
  required String? secondaryApiKey,
  required String secondaryBaseUrl,
  String? primaryApiKey,
  String primaryBaseUrl = '',
}) {
  DeepSeekEndpoint? pick(String? key, String baseUrl) {
    final k = (key ?? '').trim();
    final b = baseUrl.trim();
    if (k.isEmpty || b.isEmpty) return null;
    if (!k.toLowerCase().startsWith('sk-')) return null;
    if (!b.toLowerCase().contains('deepseek.com')) return null;
    return DeepSeekEndpoint(baseUrl: b, apiKey: k);
  }

  return pick(secondaryApiKey, secondaryBaseUrl) ??
      pick(primaryApiKey, primaryBaseUrl);
}

// ═══════════════════════════════════════════════════════════════════════
// HTTP 传输(可注入,测试不联网)
// ═══════════════════════════════════════════════════════════════════════

/// 一次 HTTP 响应(只要状态码 + 原始正文 —— Search/Fetch 都是小 JSON)。
class DeepSeekHttpResponse {
  final int statusCode;
  final String body;

  const DeepSeekHttpResponse({required this.statusCode, required this.body});
}

/// HTTP 传输抽象:默认走 Dio;单测注入假实现,**全程不联网**。
typedef DeepSeekTransport =
    Future<DeepSeekHttpResponse> Function(
      String url,
      Map<String, dynamic> body,
    );

// ═══════════════════════════════════════════════════════════════════════
// 客户端
// ═══════════════════════════════════════════════════════════════════════

/// DeepSeek 官方 Search / Fetch 客户端。
///
/// 使用方式:
/// ```dart
/// final client = DeepSeekSearchClient();          // 生产:自动读设置里的 DS 官方 Key
/// if (!client.available) { /* 显示 client.unavailableReason */ }
/// final hits = await client.search('climate news', needContent: true);
/// final page = hits.isEmpty ? null : await client.fetch(hits.first.url);
/// ```
///
/// 失败约定(重要,UI 依赖它):
/// - **search 失败返回空列表、fetch 失败返回 null,都不抛异常**;
/// - 失败原因写在 [lastError](中文人话 + kind),401/402 用
///   [DeepSeekSearchException.needsConfiguration] 让 UI 引导用户去配置/充值;
/// - 只有"服务器真计费"的成功请求才进 [requestCount](失败/空结果不计费)。
///
/// 并发:方法本身无共享可变状态(除 [requestCount] 自增),可放心并发调用;
/// 但官方 QPS 是账号级(Search 100 / Fetch 25),调用方要自己控制并发/退避。
///
/// [DeepSeekSearchClient.autoResolve] 仅给**测试/降级**用:传 false 时不去读
/// Hive 配置(Hive 未打开时也不会抛),方便单测构造"不可用"客户端。
class DeepSeekSearchClient {
  /// 每个成功请求的价格(元/次):官方 5 元/千次成功请求
  static const double cnyPerThousandRequests = 5.0;

  /// 官方 QPS 上限(账号级;调用方做并发控制时参考)
  static const int searchQps = 100;
  static const int fetchQps = 25;

  /// 连接超时:搜索服务正常 1~3 秒返回,12 秒足够;超时按"网络问题"处理
  static const Duration connectTimeout = Duration(seconds: 12);

  /// 接收超时:Search 很快;Fetch 受目标站影响,20 秒兜底(与项目现有抓取同量级)
  static const Duration receiveTimeout = Duration(seconds: 20);

  final DeepSeekEndpoint? _endpoint;
  final DeepSeekTransport? _injectedTransport;

  /// 默认 Dio 传输(仅在未注入时创建,懒加载 → 单测完全不碰)
  Dio? _dio;

  int _requestCount = 0;
  DeepSeekSearchException? _lastError;

  DeepSeekSearchClient({
    DeepSeekEndpoint? endpoint,
    DeepSeekTransport? transport,
    bool autoResolve = true,
  }) : _endpoint = endpoint ?? (autoResolve ? _resolveFromAppConfig() : null),
       _injectedTransport = transport;

  /// 是否可用:**有 DeepSeek 官方 Key + 官方 baseUrl** 才为 true。
  ///
  /// false 时 UI 应显示 [unavailableReason] 并给"去设置"入口,不要调 search/fetch。
  bool get available => _endpoint != null;

  /// 不可用原因(中文);可用时为空串
  String get unavailableReason {
    if (available) return '';
    return '未配置 DeepSeek 官方 API Key(设置 → API 设置 → 副槽位,Key 以 sk- 开头)。'
        '搜索/抓取只走 api.deepseek.com,不会用方舟 Key。';
  }

  /// 当前端点(诊断用;Key 不要打日志)
  DeepSeekEndpoint? get endpoint => _endpoint;

  /// 最近一次调用的失败原因;成功时清空。UI 在拿到空结果后读它区分"没搜到"和"失败"。
  DeepSeekSearchException? get lastError => _lastError;

  /// 累计**已计费**的成功请求数(Search + Fetch 合计)
  int get requestCount => _requestCount;

  /// 累计花费估算(元):成功请求数 × 5 元/1000
  double get estimatedCostCny =>
      _requestCount * cnyPerThousandRequests / 1000.0;

  /// 清零计数(开始一轮新的"找材料"任务时调,UI 用它显示"本次约 X 元")
  void resetCost() {
    _requestCount = 0;
  }

  /// 搜索网页。
  ///
  /// - [count]:1~50(夹紧),默认 10;
  /// - [needContent]:true 时让服务端**顺手返回网页正文**(省一次 Fetch,但结果更长);
  /// - [oriQuestion]:触发搜索的原始用户问题,帮助搜索引擎理解意图(可选)。
  ///
  /// 返回**只含 url 的结果**(无 url 已丢弃);失败/没搜到都返回空列表,
  /// 失败原因在 [lastError](没搜到时 lastError 为 null)。
  Future<List<DeepSeekSearchResult>> search(
    String query, {
    int count = 10,
    bool needContent = false,
    String? oriQuestion,
  }) async {
    _lastError = null;
    final q = query.trim();
    final endpoint = _endpoint;
    if (endpoint == null) {
      _lastError = const DeepSeekSearchException(
        kind: DeepSeekSearchErrorKind.auth,
        message:
            '未配置 DeepSeek 官方 API Key,搜索不可用 —— '
            '请到「设置 → API 设置」填写 DeepSeek 官方 Key(sk- 开头)',
      );
      return const <DeepSeekSearchResult>[];
    }
    if (q.isEmpty) {
      _lastError = const DeepSeekSearchException(
        kind: DeepSeekSearchErrorKind.badRequest,
        message: '搜索词不能为空',
      );
      return const <DeepSeekSearchResult>[];
    }

    final body = buildSearchBody(
      q,
      count: count,
      needContent: needContent,
      oriQuestion: oriQuestion,
    );

    try {
      final response = await _post(searchUrlFor(endpoint.baseUrl), body);
      if (response.statusCode != 200) {
        _lastError = mapStatusError(response.statusCode, response.body);
        return const <DeepSeekSearchResult>[];
      }
      final decoded = _decodeMap(response.body);
      if (decoded == null) {
        _lastError = const DeepSeekSearchException(
          kind: DeepSeekSearchErrorKind.unknown,
          message: '搜索接口返回的不是合法 JSON,已忽略',
        );
        return const <DeepSeekSearchResult>[];
      }

      final rawResults = decoded['results'];
      final billed = rawResults is List && rawResults.isNotEmpty;
      if (billed) {
        // 官方计费口径:HTTP 200 且 results 非空才算一次成功请求
        _requestCount++;
      }

      final parsed = parseSearchResults(decoded);
      if (parsed.isEmpty && billed) {
        // 有结果但全部缺 url → 全部丢弃。钱已经花了,必须让调用方知道为什么没有卡片
        _lastError = const DeepSeekSearchException(
          kind: DeepSeekSearchErrorKind.unknown,
          message: '搜索返回的结果都缺少 URL,已丢弃(不会把无出处内容当成材料)',
        );
      }
      return parsed;
    } catch (e) {
      if (e is DeepSeekSearchException) {
        _lastError = e;
        return const <DeepSeekSearchResult>[];
      }
      _lastError = mapTransportError(e);
      debugPrint('ReadFlow DeepSeek Search 失败: ${_short(e)}');
      return const <DeepSeekSearchResult>[];
    }
  }

  /// 抓取单个网页正文(Markdown)。
  ///
  /// 失败(403/404/网络/参数非法)返回 null,原因在 [lastError];
  /// 空正文也算失败(官方不计费)。
  Future<DeepSeekFetchResult?> fetch(String url) async {
    _lastError = null;
    final endpoint = _endpoint;
    if (endpoint == null) {
      _lastError = const DeepSeekSearchException(
        kind: DeepSeekSearchErrorKind.auth,
        message:
            '未配置 DeepSeek 官方 API Key,抓取不可用 —— '
            '请到「设置 → API 设置」填写 DeepSeek 官方 Key(sk- 开头)',
      );
      return null;
    }
    final target = url.trim();
    if (!isFetchableUrl(target)) {
      _lastError = const DeepSeekSearchException(
        kind: DeepSeekSearchErrorKind.badRequest,
        message: 'URL 不合法:需要 http/https、含域名、长度不超过 8192 字符',
      );
      return null;
    }

    try {
      final response = await _post(fetchUrlFor(endpoint.baseUrl), {
        'url': target,
      });
      if (response.statusCode != 200) {
        _lastError = mapStatusError(response.statusCode, response.body);
        return null;
      }
      final decoded = _decodeMap(response.body);
      if (decoded == null) {
        _lastError = const DeepSeekSearchException(
          kind: DeepSeekSearchErrorKind.unknown,
          message: '抓取接口返回的不是合法 JSON,已忽略',
        );
        return null;
      }
      final parsed = parseFetchResult(decoded);
      if (parsed == null) {
        // HTTP 200 但正文为空:官方不计费,对用户等于"这页抓不到"
        _lastError = const DeepSeekSearchException(
          kind: DeepSeekSearchErrorKind.notFound,
          message: '这页没有可提取的正文(可能需要登录或 JS 渲染),已跳过',
          statusCode: 200,
        );
        return null;
      }
      // 官方计费口径:Fetch 必须返回网页正文才算成功请求
      _requestCount++;
      return parsed;
    } catch (e) {
      if (e is DeepSeekSearchException) {
        _lastError = e;
        return null;
      }
      _lastError = mapTransportError(e);
      debugPrint('ReadFlow DeepSeek Fetch 失败: ${_short(e)}');
      return null;
    }
  }

  // ── 内部 ────────────────────────────────────────────────────────────

  /// 生产环境:从现有槽位配置解析 DS 官方端点。
  ///
  /// 读 Hive 可能失败(测试环境没开 Hive / 配置读坏)→ 返回 null(不可用),
  /// **绝不让构造客户端这件事把调用方炸掉**。
  static DeepSeekEndpoint? _resolveFromAppConfig() {
    try {
      final secondary = ApiEndpointConfig.secondary;
      final primary = ApiEndpointConfig.primary;
      return resolveEndpoint(
        secondaryApiKey: secondary.apiKey,
        secondaryBaseUrl: secondary.baseUrl,
        primaryApiKey: primary.apiKey,
        primaryBaseUrl: primary.baseUrl,
      );
    } catch (e) {
      debugPrint('ReadFlow DeepSeek Search 读取 API 配置失败(视为不可用): ${_short(e)}');
      return null;
    }
  }

  Future<DeepSeekHttpResponse> _post(String url, Map<String, dynamic> body) {
    final injected = _injectedTransport;
    if (injected != null) return injected(url, body);
    return _dioTransport(url, body);
  }

  /// 默认 Dio 实现:显式 12s/20s 超时、所有状态码都当响应返回
  /// (4xx/5xx 由 [mapStatusError] 统一翻译成中文,不让 DioException 漏出去)。
  Future<DeepSeekHttpResponse> _dioTransport(
    String url,
    Map<String, dynamic> body,
  ) async {
    final endpoint = _endpoint!;
    final dio = _dio ??= Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        responseType: ResponseType.plain,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    final response = await dio.post<dynamic>(
      url,
      data: jsonEncode(body),
      options: Options(
        headers: {'Authorization': 'Bearer ${endpoint.apiKey}'},
        // 4xx/5xx 也要拿到 body(官方错误详情在里面),所以不抛
        validateStatus: (_) => true,
      ),
    );
    return DeepSeekHttpResponse(
      statusCode: response.statusCode ?? 0,
      body: response.data is String
          ? response.data as String
          : '${response.data ?? ''}',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 小工具(容错解析)
// ═══════════════════════════════════════════════════════════════════════

String _str(Object? raw) => raw is String ? raw : '';

int _int(Object? raw, {int fallback = 0}) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

double _double(Object? raw) {
  if (raw is double) return raw;
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim()) ?? 0;
  return 0;
}

DateTime? _date(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

Map<String, dynamic>? _decodeMap(String body) {
  final text = body.trim();
  if (text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    // 网关错误页/空 body:交给上层按"返回不是 JSON"处理
  }
  return null;
}

String _short(Object? error) {
  final flat = '$error'.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length > 120 ? '${flat.substring(0, 120)}…' : flat;
}
