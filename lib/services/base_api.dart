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

  /// POST — 自适应递归降级(最多 3 次),应对端点不认思考参数的情况:
  /// 1. 有 reasoning_effort → 移除它(保留 thinking: enabled)
  /// 2. thinking: enabled → disabled → 整体移除
  Future<Response> postWithReasoningFallback(
    String path,
    Map<String, dynamic> body, {
    required ApiEndpointConfig cfg,
    ResponseType? responseType,
    int retryDepth = 0,
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
          data: body);
    } on DioException catch (e) {
      if (!isReasoningError(e) || retryDepth >= 3) rethrow;

      final degraded = Map<String, dynamic>.from(body);

      // Step 1: 移除 reasoning_effort(最常见的不兼容参数)
      if (degraded.containsKey('reasoning_effort')) {
        degraded.remove('reasoning_effort');
      } else if (degraded['thinking'] is Map) {
        // Step 2: enabled → disabled → 移除 thinking
        final t = degraded['thinking'] as Map;
        final type = t['type'] as String?;
        if (type == 'enabled') {
          degraded['thinking'] = {'type': 'disabled'};
        } else {
          degraded.remove('thinking');
        }
      } else {
        rethrow;
      }

      return postWithReasoningFallback(path, degraded,
          cfg: cfg,
          responseType: responseType,
          retryDepth: retryDepth + 1);
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
}
