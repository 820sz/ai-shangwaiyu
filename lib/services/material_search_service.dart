import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../config/constants.dart';

/// AI 学习材料推荐服务 — 纯文本 Chat Completions，不涉及图片
class MaterialSearchService {
  Dio? _dioInstance;
  String? _dioBaseUrl;

  String get _baseUrl {
    final v = Hive.box(AppConstants.hiveBoxSettings)
        .get(AppConstants.keyDoubaoBaseUrl);
    return (v is String && v.isNotEmpty) ? v : AppConstants.doubaoBaseUrl;
  }

  String get _modelName {
    final v = Hive.box(AppConstants.hiveBoxSettings)
        .get(AppConstants.keyDoubaoModel);
    return (v is String && v.isNotEmpty) ? v : AppConstants.doubaoVisionModel;
  }

  String? _getApiKey() {
    return Hive.box(AppConstants.hiveBoxSettings)
        .get(AppConstants.keyDoubaoApiKey);
  }

  Dio get _dio {
    final url = _baseUrl;
    if (_dioInstance == null || _dioBaseUrl != url) {
      _dioBaseUrl = url;
      _dioInstance = Dio(BaseOptions(
        baseUrl: url,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
        headers: {'Content-Type': 'application/json'},
      ));
    }
    return _dioInstance!;
  }

  /// 从 Hive 读取思考模式配置
  Map<String, dynamic>? _buildThinkingParams() {
    final v = Hive.box(AppConstants.hiveBoxSettings)
        .get(AppConstants.keyDoubaoThinking);
    final mode = (v is String &&
            (v == 'disabled' || v == 'low' || v == 'medium' || v == 'high'))
        ? v
        : 'disabled';

    if (mode == 'disabled') {
      return {'thinking': {'type': 'disabled'}};
    }
    return {
      'thinking': {'type': 'enabled'},
      'reasoning_effort': mode,
    };
  }

  /// 基于分类推荐学习材料
  Future<List<Map<String, String>>> searchMaterials(String category) async {
    final apiKey = _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置 API Key');
    }

    final body = {
      'model': _modelName,
      'messages': [
        {
          'role': 'system',
          'content':
              '你是英语学习素材推荐助手。根据用户选择的分类，推荐 5-8 个具体可检索的英语学习素材。\n返回 JSON：{"materials": [{"name": "素材名", "description": "简介", "level": "CEFR等级", "keywords": "搜索关键词"}]}\n只返回JSON，不要其他文字。',
        },
        {
          'role': 'user',
          'content':
              '分类：$category\n请推荐该分类下适合英语学习的阅读素材。每个素材包括：name（名称）、description（简短介绍）、level（适合水平，如A1/A2/B1/B2/C1/C2）、keywords（用于进一步搜索的关键词）。',
        },
      ],
      'temperature': 0.8,
      'max_tokens': 2048,
      ..._buildThinkingParams()!,
    };

    // POST with reasoning_effort fallback — retry once without thinking params
    Response response;
    try {
      response = await _dio.post(
        '/chat/completions',
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
        data: body,
      );
    } on DioException catch (e) {
      // If rejected because of thinking/reasoning params, retry without them
      if (_isReasoningError(e) && (body.containsKey('thinking') || body.containsKey('reasoning_effort'))) {
        final safeBody = Map<String, dynamic>.from(body)
          ..remove('reasoning_effort')
          ..remove('thinking');
        response = await _dio.post(
          '/chat/completions',
          options: Options(
            headers: {'Authorization': 'Bearer $apiKey'},
          ),
          data: safeBody,
        );
      } else {
        rethrow;
      }
    }

    final content = _extractContent(response.data);
    return parseMaterialResponse(content);
  }

  /// 判断是否因 reasoning_effort 参数导致 API 报错（应 retry 移除）
  static bool _isReasoningError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == null || statusCode < 400 || statusCode >= 500) return false;
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
    return body.contains('1830102') ||
        (body.contains('invalid') && body.contains('parameter'));
  }

  /// 安全提取 API 响应中的 content
  static String _extractContent(Map<String, dynamic> data) {
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

  /// 解析 AI 返回的素材推荐 JSON
  static List<Map<String, String>> parseMaterialResponse(String content) {
    String jsonStr = content.trim();
    // 去掉可能的 ```json 包裹
    if (jsonStr.startsWith('```')) {
      final start = jsonStr.indexOf('\n');
      final end = jsonStr.lastIndexOf('```');
      if (start != -1 && end != -1) {
        jsonStr = jsonStr.substring(start, end).trim();
      }
    }

    try {
      final parsed = jsonDecode(jsonStr);
      if (parsed is! Map<String, dynamic>) {
        throw FormatException('AI 返回的不是 JSON 对象');
      }
      final materials = parsed['materials'] as List<dynamic>? ?? [];
      return materials
          .map((e) => {
                'name': e['name']?.toString() ?? '',
                'description': e['description']?.toString() ?? '',
                'level': e['level']?.toString() ?? '',
                'keywords': e['keywords']?.toString() ?? '',
              })
          .where((m) => m['name']!.isNotEmpty)
          .toList();
    } catch (e) {
      // AI 返回格式异常时抛出中文友好错误
      throw FormatException('AI 返回材料格式异常，可尝试重试：${e.toString()}');
    }
  }
}
