import 'package:dio/dio.dart';
import 'api_endpoint.dart';

/// 共享 API HTTP 基类:连接复用 + 响应提取 + 思考参数降级重试。
///
/// 三个服务(doubao/deepseek/material_search)原本各自复制了
/// _dio 缓存、_extractContent、_buildThinkingParams、降级重试,
/// 现统一收敛到此处;每个服务只需声明自己的槽位配置。
abstract class BaseApiService {
  /// 本服务使用的槽位(主/副)。追问等按需切换场景可传参覆盖。
  ApiEndpointConfig get config;

  Dio? _dioInstance;
  String? _dioBaseUrl;

  /// 按 baseUrl 缓存 Dio 实例,复用 TCP+TLS 连接
  Dio _dioFor(ApiEndpointConfig cfg) {
    final url = cfg.baseUrl;
    if (_dioInstance == null || _dioBaseUrl != url) {
      _dioBaseUrl = url;
      _dioInstance = Dio(BaseOptions(
        baseUrl: url,
        connectTimeout: const Duration(seconds: 60),
        // 接收空闲超时:流式响应持续有数据不受影响,长时间无数据才断开。
        // 600s 太长会让"模型失效/网络黑洞"看起来像卡死,收紧到 180s
        receiveTimeout: const Duration(seconds: 180),
        sendTimeout: const Duration(seconds: 60),
        headers: {'Content-Type': 'application/json'},
        // HTTP keep-alive 复用连接
        persistentConnection: true,
      ));
    }
    return _dioInstance!;
  }

  /// 安全提取 API 响应中的 content 字段(报错时抛友好中文错误)
  static String extractContent(Map<String, dynamic> data) {
    final error = data['error'];
    if (error != null) {
      final msg = error is Map ? (error['message'] ?? '未知错误') : '$error';
      throw Exception('API 返回错误：$msg');
    }
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('API 返回空响应，请检查模型是否可用');
    }
    final message = choices[0]['message'];
    if (message == null) {
      throw Exception('API 响应格式异常：缺少 message 字段');
    }
    final content = message['content'];
    if (content is String) return content;
    throw Exception('API 返回内容为空');
  }

  /// 构建 chat/completions 请求体(v1.9.0 抽出的公共纯函数,可单测)。
  ///
  /// 抽取动机(审查 P1-1):仓库里曾有两套并行的请求构造 —— 思考档位/
  /// max_tokens 的根因修复只落在 `doubao_api`,`deepseek_api`(文章生成、
  /// 回译练习、学习建议)仍发旧参数,导致"同一类 bug 修两遍、另一处必复发"。
  ///
  /// 规则:
  /// - **DeepSeek 官方**:省略 `max_tokens`(它是 reasoning+content 总预算,
  ///   写死会被思考吃光 → content 为空)、省略 `temperature`(官方样例与
  ///   dsh 都不发)、补 `stream_options.include_usage`
  /// - **其他端点**(方舟/第三方网关):显式 `max_tokens` + `temperature`,
  ///   且**不发** `stream_options`(未知字段可能 400)
  static Map<String, dynamic> buildChatBody({
    required ApiEndpointConfig cfg,
    required List<Map<String, dynamic>> messages,
    bool stream = false,
    double temperature = 0.3,
    int maxTokens = 4096,
    String? thinkingLevel,
    bool includeThinking = true,
  }) {
    final official = cfg.isDeepSeekOfficial;
    return {
      'model': cfg.model,
      'messages': messages,
      if (!official) 'max_tokens': maxTokens,
      if (!official) 'temperature': temperature,
      if (includeThinking)
        ...cfg.buildThinkingParamsFor(thinkingLevel ?? cfg.thinking),
      if (official && stream) 'stream_options': {'include_usage': true},
      if (stream) 'stream': true,
    };
  }

  /// 降级一次(纯函数,可单测):同时移除 `reasoning_effort` 并把
  /// `thinking` 置为 `disabled` —— 第一步就真正换掉两类不兼容参数,
  /// 因此只重试一次就够(审查 P1-4:旧实现第一步只删 reasoning_effort
  /// 却保留 `thinking: enabled`,对不认该字段的端点等于原样重发)。
  /// 没有任何可降级字段时返回 null —— 调用方应立即失败,不做无意义重发。
  static Map<String, dynamic>? degradeOnce(Map<String, dynamic> body) {
    final next = Map<String, dynamic>.from(body);
    var changed = false;
    if (next.remove('reasoning_effort') != null) changed = true;
    final thinking = next['thinking'];
    if (thinking is Map) {
      if ((thinking['type'] as String?) == 'enabled') {
        next['thinking'] = {'type': 'disabled'};
      } else {
        next.remove('thinking');
      }
      changed = true;
    }
    return changed ? next : null;
  }

  /// 提取正文;**正文为空但思考通道有内容时返回思考内容**(v1.9.0)。
  /// 用途:思考模型常把最终结果整段写在 `reasoning_content`(content 为空),
  /// 调用方拿到后可用 `extractJsonBlock` 抠出 JSON —— 而不是把用户选的
  /// 思考档位砍成"不思考"。
  static String extractContentWithReasoning(Map<String, dynamic> data) {
    final error = data['error'];
    if (error != null) {
      final msg = error is Map ? (error['message'] ?? '未知错误') : '$error';
      throw Exception('API 返回错误：$msg');
    }
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('API 返回空响应，请检查模型是否可用');
    }
    final message = choices[0]['message'];
    if (message == null) {
      throw Exception('API 响应格式异常：缺少 message 字段');
    }
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) return content;
    final reasoning = message['reasoning_content'];
    if (reasoning is String && reasoning.trim().isNotEmpty) return reasoning;
    throw Exception('API 返回内容为空');
  }

  /// POST — 自适应降级重试(**最多 1 次**,v1.9.0 收敛):
  /// 只在"参数不兼容"类 4xx(见 [isReasoningError])且请求体确实含有
  /// 可降级字段时重试一次,并同时去掉 reasoning_effort、关闭 thinking。
  /// [cancelToken] 供调用方中途取消(流式看门狗/用户点取消)。
  Future<Response> postWithReasoningFallback(
    String path,
    Map<String, dynamic> body, {
    required ApiEndpointConfig cfg,
    ResponseType? responseType,
    int retryDepth = 0,
    CancelToken? cancelToken,
  }) async {
    final apiKey = cfg.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置 API Key');
    }
    try {
      return await _dioFor(cfg).post(path,
          options: Options(
            headers: {'Authorization': 'Bearer $apiKey'},
            responseType: responseType,
          ),
          data: body,
          cancelToken: cancelToken);
    } on DioException catch (e) {
      if (!isReasoningError(e) || retryDepth >= 1) rethrow;
      final degraded = degradeOnce(body);
      if (degraded == null) rethrow;
      return postWithReasoningFallback(path, degraded,
          cfg: cfg,
          responseType: responseType,
          retryDepth: retryDepth + 1,
          cancelToken: cancelToken);
    }
  }

  /// 判断是否因 thinking/reasoning 参数导致 API 报错(应降级重试)
  static bool isReasoningError(DioException e) {
    final statusCode = e.response?.statusCode;
    // 4xx 客户端错误才可能是参数问题
    if (statusCode == null || statusCode < 400 || statusCode >= 500) {
      return false;
    }

    final d = e.response?.data;
    String body;
    if (d is Map) {
      final error = d['error'];
      if (error is Map) {
        body = '${error['code'] ?? ''} ${error['message'] ?? ''}';
      } else {
        body = d.toString();
      }
    } else if (d is String) {
      body = d;
    } else {
      body = e.message ?? '';
    }
    // 豆包错误码 1830102(参数不兼容)或通用 invalid parameter
    return body.contains('1830102') ||
        (body.contains('invalid') && body.contains('parameter'));
  }

  /// 把 Dio/API 异常转成人类可读错误(v1.4.1):
  /// 优先显示服务端 error message;常见状态码给中文指引——
  /// 用户实拍一屏 DioException 英文,完全看不懂原因。
  static String friendlyError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final err = data['error'];
        if (err is Map) {
          final em = err['message']?.toString() ?? '';
          if (em.isNotEmpty) return 'API 返回错误：$em';
        }
        final m = data['message']?.toString() ?? '';
        if (m.isNotEmpty) return 'API 返回错误：$m';
        // 有些网关把错误直接放 body(Map 键不含 message/error)
        final str = data.toString();
        if (str.contains('error') || str.contains('Error')) {
          return 'API 返回错误：${_truncate(str)}';
        }
      }
      if (data is String && data.trim().isNotEmpty) {
        return 'API 返回错误：${_truncate(data.trim())}';
      }
      final code = e.response?.statusCode;
      switch (code) {
        case 301:
        case 302:
          return '端点重定向：Base URL 请使用 https:// 开头(已自动修复,重新保存即可)';
        case 400:
          return '请求被拒绝(400)：模型或参数与该端点不匹配，请检查模型名称与端点是否同一家';
        case 401:
        case 403:
          return '鉴权失败(401/403)：API Key 与端点不匹配或无效，请检查 Key 前缀(sk-=DeepSeek / ark-=方舟)';
        case 404:
          return '请求路径/模型不存在(404)：请检查 Base URL 与模型名称';
        case 429:
          return '请求太频繁(429)：稍等几秒再试';
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return '网络超时：请检查网络后重试';
      }
      if (e.type == DioExceptionType.connectionError) {
        return '网络连接失败：请检查网络/代理后重试';
      }
    }
    final s = e.toString()
        .replaceFirst('DioException [bad response]: ', '')
        .replaceFirst('DioException [unknown]: ', '');
    return _truncate(s);
  }

  static String _truncate(String s) =>
      s.length > 200 ? '${s.substring(0, 200)}…' : s;
}
