import 'dart:convert';
import 'api_endpoint.dart';
import 'base_api.dart';

/// AI 学习材料推荐服务 — 纯文本 Chat Completions(读主槽位,与识图同一配置)
class MaterialSearchService extends BaseApiService {
  @override
  ApiEndpointConfig get config => ApiEndpointConfig.primary;

  /// 基于分类推荐学习材料
  Future<List<Map<String, String>>> searchMaterials(String category) async {
    if (!config.isConfigured) {
      throw Exception('请先在设置中配置 API Key');
    }

    final body = {
      'model': config.model,
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
      ...config.buildThinkingParams(),
    };

    final response = await postWithReasoningFallback(
      '/chat/completions',
      body,
      cfg: config,
    );

    final content = BaseApiService.extractContent(response.data);
    return parseMaterialResponse(content);
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
