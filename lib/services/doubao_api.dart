import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image/image.dart' as img;
import '../config/constants.dart';

/// SSE 流式数据块
class SseChunk {
  final String text;
  final bool isReasoning;
  const SseChunk({required this.text, required this.isReasoning});
}

/// 豆包（火山方舟）视觉 API 服务
class DoubaoApiService {
  /// 从 Hive 读取配置（无自定义值则用默认）
  String get _baseUrl {
    final v = Hive.box(AppConstants.hiveBoxSettings)
        .get(AppConstants.keyDoubaoBaseUrl);
    return (v is String && v.isNotEmpty) ? v : AppConstants.doubaoBaseUrl;
  }

  /// 当前使用的模型名（公开，供 UI 展示/调试）
  String get modelName {
    final v = Hive.box(AppConstants.hiveBoxSettings)
        .get(AppConstants.keyDoubaoModel);
    return (v is String && v.isNotEmpty) ? v : AppConstants.doubaoVisionModel;
  }

  // 复用 Dio 实例，避免每次请求重新 TCP+TLS 握手
  Dio? _dioInstance;
  String? _dioBaseUrl;

  Dio get _dio {
    final url = _baseUrl;
    if (_dioInstance == null || _dioBaseUrl != url) {
      _dioBaseUrl = url;
      _dioInstance = Dio(BaseOptions(
        baseUrl: url,
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 600),
        sendTimeout: const Duration(seconds: 60),
        headers: {'Content-Type': 'application/json'},
        // HTTP keep-alive 复用连接
        persistentConnection: true,
      ));
    }
    return _dioInstance!;
  }

  /// 从 Hive 读取 API Key
  String? _getApiKey() {
    final box = Hive.box(AppConstants.hiveBoxSettings);
    return box.get(AppConstants.keyDoubaoApiKey);
  }

  /// 检查是否已配置 API Key
  bool get isConfigured {
    final key = _getApiKey();
    return key != null && key.isNotEmpty;
  }

  // ── 图片压缩 ──

  /// 安全提取 API 响应中的 content 字段
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

  /// 安全读取图片字节，文件不存在或读取失败时抛友好错误
  Future<Uint8List> _readImageBytes(File imageFile) async {
    try {
      return await imageFile.readAsBytes();
    } catch (e) {
      debugPrint('ReadFlow _readImageBytes error: $e');
      throw Exception('无法读取图片文件，请检查文件是否存在：$e');
    }
  }

  /// 读取文件并转为 data URI。
  /// 小图片（<500KB，image_picker 已控制在1024px）跳过解码，rawBytes 直发。
  /// 仅大图片才解码判断是否需缩放（>3072px 缩小至 JPEG 输出）。
  /// 任一环节异常均 fallback 到 rawBytes 直发，保证不崩。
  Future<String> _imageToDataUri(File imageFile) async {
    final rawBytes = await _readImageBytes(imageFile);
    final mime = _detectImageMime(rawBytes);

    // 小图片直接发，跳过昂贵的 decode 步骤（image_picker 1024px 一定走这里）
    if (rawBytes.length < 500 * 1024) {
      return 'data:$mime;base64,${base64Encode(rawBytes)}';
    }

    // 大图片才解码判断是否需缩小
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        return 'data:$mime;base64,${base64Encode(rawBytes)}';
      }

      if (decoded.width <= 2048 && decoded.height <= 2048) {
        return 'data:$mime;base64,${base64Encode(rawBytes)}';
      }

      // 需要缩小 → JPEG 输出，平衡清晰度与体积
      final output = img.copyResize(decoded,
          width: 2048, height: 2048, maintainAspect: true);
      final compressed = img.encodeJpg(output, quality: 75);
      return 'data:image/jpeg;base64,${base64Encode(compressed)}';
    } catch (e) {
      // decode/resize 失败 → 兜底：rawBytes 直发
      debugPrint('ReadFlow _imageToDataUri fallback: $e');
      return 'data:$mime;base64,${base64Encode(rawBytes)}';
    }
  }

  /// 通过文件头魔数检测图片 MIME 类型
  static String _detectImageMime(List<int> bytes) {
    if (bytes.length < 4) return 'image/png';
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'image/png';
    }
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    // WebP: 52 49 46 46 .* 57 45 42 50
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'image/webp';
    }
    // GIF: 47 49 46 38
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
      return 'image/gif';
    }
    return 'image/png';
  }

  // ── 共享 ──

  /// 豆包 thinking 参数
  /// turbo 模型开启 thinking 后即使 minimal 级别也要 1min+。
  /// 策略：低度以下禁用 thinking（秒级），中度以上才开启。
  /// disabled → thinking: disabled（秒级）
  /// low    → thinking: disabled（秒级，准确度靠系统提示词保证）
  /// medium → thinking: enabled + reasoning_effort: low
  /// high   → thinking: enabled + reasoning_effort: medium
  Map<String, dynamic>? _buildThinkingParams() {
    final v = Hive.box(AppConstants.hiveBoxSettings)
        .get(AppConstants.keyDoubaoThinking);
    final mode = (v is String &&
            (v == 'disabled' || v == 'low' || v == 'medium' || v == 'high'))
        ? v
        : 'disabled';

    switch (mode) {
      case 'disabled':
      case 'low':
        // turbo 模型 thinking 太慢，低度以下一律禁用
        return {'thinking': {'type': 'disabled'}};
      case 'medium':
        return {
          'thinking': {'type': 'enabled'},
          'reasoning_effort': 'low',
        };
      case 'high':
        return {
          'thinking': {'type': 'enabled'},
          'reasoning_effort': 'medium',
        };
      default:
        return {'thinking': {'type': 'disabled'}};
    }
  }

  /// POST — 自适应递归降级（最多 3 次）
  /// 1. 有 reasoning_effort → 移除它（保留 thinking: enabled，默认 minimal）
  /// 2. thinking: enabled → auto → disabled → 移除 thinking
  Future<Response> _postWithReasoningFallback(
    String path,
    Map<String, dynamic> body, {
    required String apiKey,
    ResponseType? responseType,
    int retryDepth = 0,
  }) async {
    try {
      return await _dio.post(path,
          options: Options(
            headers: {'Authorization': 'Bearer $apiKey'},
            responseType: responseType,
          ),
          data: body);
    } on DioException catch (e) {
      if (!_isReasoningError(e) || retryDepth >= 3) rethrow;

      final degraded = Map<String, dynamic>.from(body);

      // Step 1: 移除 reasoning_effort（最常见的不兼容参数）
      if (degraded.containsKey('reasoning_effort')) {
        degraded.remove('reasoning_effort');
      } else if (degraded['thinking'] is Map) {
        // Step 2: 逐级降 thinking.type
        final t = degraded['thinking'] as Map;
        final type = t['type'] as String?;
        if (type == 'enabled') {
          degraded['thinking'] = {'type': 'auto'};
        } else if (type == 'auto') {
          degraded['thinking'] = {'type': 'disabled'};
        } else {
          // disabled 或未知 → 移除 thinking
          degraded.remove('thinking');
        }
      } else {
        rethrow;
      }

      return _postWithReasoningFallback(path, degraded,
          apiKey: apiKey,
          responseType: responseType,
          retryDepth: retryDepth + 1);
    }
  }

  Map<String, dynamic> _buildRequestBody(
    List<String> imageUris, {
    String? sourceBook,
    String? sourcePage,
    bool stream = false,
    String analysisMode = AppConstants.analysisModeMarked,
  }) {
    final bookHint = sourceBook != null && sourceBook.isNotEmpty
        ? '，出处书籍："$sourceBook"' : '';
    final pageHint = sourcePage != null && sourcePage.isNotEmpty
        ? '，页码：$sourcePage' : '';
    final countHint = imageUris.length > 1
        ? '（共${imageUris.length}张图片）'
        : '';

    final (String systemPrompt, String userPrompt) = switch (analysisMode) {
      AppConstants.analysisModeFullText => (
        '''你是一个专业的翻译助手。用户发给你一张外语阅读材料的照片，请翻译照片中的所有文字内容。
返回 JSON：{"paragraphs": [{"original": "原文段落", "translation": "中文翻译"}]}
要求：保持原文段落结构，翻译准确流畅。只返回JSON。''',
        '请翻译这些阅读材料照片中的全文内容$bookHint$pageHint$countHint'
      ),
      _ => (
        '''你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式：
{"items":[{"word":"原文","translation":"中文释义","word_type":"word|phrase|sentence","part_of_speech":"词性(可选)","original_sentence":"所在句子(可选)"}]}
要求：单词给词性，短语/句子给翻译。${imageUris.length > 1 ? '多图格式：{"items_by_image":[{"image_index":0,"items":[...]},...]}' : ''}无标记返回{"items":[]}。只输出JSON。简洁思考。''',
        '识别标记的英语内容$bookHint$pageHint$countHint'
      ),
    };

    return {
      'model': modelName,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': [
            for (final uri in imageUris)
              {
                'type': 'image_url',
                'image_url': {'url': uri, 'detail': 'low'},
              },
            {'type': 'text', 'text': userPrompt},
          ],
        },
      ],
      'max_tokens': 2048,
      'temperature': 0,
      ..._buildThinkingParams()!,
      if (stream) 'stream': true,
    };
  }

  // ── 同步版（保留向下兼容） ──

  /// 拍照取词 — 发送图片到豆包 Vision API（非流式）
  Future<List<Map<String, dynamic>>> extractVocabulary(
    List<File> imageFiles, {
    String? sourceBook,
    String? sourcePage,
    String analysisMode = AppConstants.analysisModeMarked,
  }) async {
    if (imageFiles.isEmpty) throw Exception('没有可识别的图片');
    final apiKey = _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置豆包 API Key');
    }

    final imageUris = await Future.wait(
      imageFiles.map((f) => _imageToDataUri(f)),
      eagerError: true,
    );

    final body = _buildRequestBody(
      imageUris,
      sourceBook: sourceBook,
      sourcePage: sourcePage,
      analysisMode: analysisMode,
    );

    final response = await _postWithReasoningFallback(
      '/chat/completions', body, apiKey: apiKey);

    final content = _extractContent(response.data);
    return parseResponse(content, analysisMode: analysisMode);
  }

  // ── 流式版（新增） ──

  /// 拍照取词 — 流式返回（async* 生成器，逐个产出 SseChunk）
  Stream<SseChunk> extractVocabularyStream(
    List<File> imageFiles, {
    String? sourceBook,
    String? sourcePage,
    String analysisMode = AppConstants.analysisModeMarked,
  }) async* {
    if (imageFiles.isEmpty) throw Exception('没有可识别的图片');
    final apiKey = _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置豆包 API Key');
    }

    final imageUris = await Future.wait(
      imageFiles.map((f) => _imageToDataUri(f)),
      eagerError: true,
    );

    final body = _buildRequestBody(
      imageUris,
      sourceBook: sourceBook,
      sourcePage: sourcePage,
      stream: true,
      analysisMode: analysisMode,
    );

    final response = await _postWithReasoningFallback(
      '/chat/completions', body, apiKey: apiKey,
      responseType: ResponseType.stream);

    final data = response.data;
    if (data is! ResponseBody) {
      throw Exception('API 未返回流式响应：${data is Map ? data['error'] ?? data : data}');
    }
    yield* _parseSseStream(data.stream);
  }

  /// 判断是否因 reasoning_effort 参数导致 API 报错（应 retry 移除）
  static bool _isReasoningError(DioException e) {
    final statusCode = e.response?.statusCode;
    // 4xx 客户端错误才可能是参数问题
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
    return body.contains('1830102');
  }

  /// SSE data 行解析 → 产出 SseChunk（null = [DONE] 或空行）
  SseChunk? _parseDataLine(String jsonStr) {
    if (jsonStr.isEmpty || jsonStr == '[DONE]') return null;
    try {
      final data = jsonDecode(jsonStr);
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;
      final delta = choices[0]['delta'];
      final content = delta?['content'] as String?;
      final reasoning = delta?['reasoning_content'] as String?;
      if (content != null && content.isNotEmpty) {
        return SseChunk(text: content, isReasoning: false);
      } else if (reasoning != null && reasoning.isNotEmpty) {
        return SseChunk(text: reasoning, isReasoning: true);
      }
    } catch (e) {
      debugPrint('ReadFlow SSE: $e');
    }
    return null;
  }

  /// SSE 流解析器：区分 reasoning_content 和 content
  /// 按 \n\n 分隔 SSE 事件，跨 TCP 包的残片保留在 buffer 等下次补齐
  Stream<SseChunk> _parseSseStream(Stream<List<int>> rawStream) async* {
    String buffer = '';
    await for (final bytes in rawStream) {
      buffer += utf8.decode(bytes, allowMalformed: true);
      // 按双换行切分完整的 SSE 事件
      while (buffer.contains('\n\n')) {
        final eventEnd = buffer.indexOf('\n\n');
        final event = buffer.substring(0, eventEnd);
        buffer = buffer.substring(eventEnd + 2);

        for (final line in event.split('\n')) {
          if (line.startsWith('data: ')) {
            final chunk = _parseDataLine(line.substring(6).trim());
            if (chunk != null) yield chunk;
          }
        }
      }
    }
    // 尾部残留 flush（流结束但 buffer 里还有未关闭的事件）
    if (buffer.trim().isNotEmpty) {
      for (final line in buffer.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('data: ')) {
          final chunk = _parseDataLine(trimmed.substring(6).trim());
          if (chunk != null) yield chunk;
        }
      }
    }
  }

  // ── 追问对话（text-only 流式） ──

  /// 基于已有识别结果发送追问，返回流式 SSE 块
  Stream<SseChunk> followUpStream(
    String question, {
    required String context,
  }) async* {
    final apiKey = _getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置豆包 API Key');
    }

    final body = {
      'model': modelName,
      'messages': [
        {
          'role': 'system',
          'content':
              '你是英语学习助手。基于图片识别结果回答用户追问。简洁准确，根据材料量自行决定回答长度。',
        },
        {
          'role': 'user',
          'content': '$context\n\n用户提问：$question',
        },
      ],
      'temperature': 0.3,
      'max_tokens': 2048,
      ..._buildThinkingParams()!,
      'stream': true,
    };

    final response = await _postWithReasoningFallback(
      '/chat/completions', body, apiKey: apiKey,
      responseType: ResponseType.stream);

    final data = response.data;
    if (data is! ResponseBody) {
      throw Exception('API 未返回流式响应：${data is Map ? data['error'] ?? data : data}');
    }
    yield* _parseSseStream(data.stream);
  }

  // ── 静态解析方法（供 ProcessChatScreen 调用） ──

  /// 解析 AI 返回的 JSON 文本。
  /// [analysisMode]: 'marked' → items 列表, 'fullText' → paragraphs 列表
  static List<Map<String, dynamic>> parseResponse(String content, {String analysisMode = AppConstants.analysisModeMarked}) {
    String jsonStr = content.trim();
    // 去掉可能的 ```json 包裹
    if (jsonStr.startsWith('```')) {
      final start = jsonStr.indexOf('\n');
      final end = jsonStr.lastIndexOf('```');
      if (start != -1 && end != -1) {
        jsonStr = jsonStr.substring(start, end).trim();
      }
    }

    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      throw FormatException('无法解析 AI 返回的 JSON: $content');
    }

    // 全文翻译模式
    if (analysisMode == AppConstants.analysisModeFullText) {
      final paragraphs = parsed['paragraphs'] as List<dynamic>?;
      if (paragraphs == null) return [];
      return paragraphs
          .map((e) => {
                'original': e['original']?.toString() ?? '',
                'translation': e['translation']?.toString() ?? '',
              })
          .where((m) => m['original']!.isNotEmpty)
          .toList();
    }

    // 圈画模式 — 支持 items 和 items_by_image 两种格式
    // 多图格式: {"items_by_image": [{"image_index": 0, "items": [...]}]}
    final itemsByImage = parsed['items_by_image'] as List<dynamic>?;
    if (itemsByImage != null && itemsByImage.isNotEmpty) {
      final allItems = <Map<String, dynamic>>[];
      for (final group in itemsByImage) {
        final imgIdx = group['image_index'] as int? ?? 0;
        final items = group['items'] as List<dynamic>? ?? [];
        for (final e in items) {
          allItems.add({
            'word': e['word']?.toString() ?? '',
            'translation': e['translation']?.toString() ?? '',
            'word_type': e['word_type']?.toString() ?? 'word',
            'original_sentence': e['original_sentence']?.toString() ?? '',
            'part_of_speech': e['part_of_speech']?.toString(),
            'grammar_note': e['grammar_note']?.toString(),
            'image_index': imgIdx,
          });
        }
      }
      return allItems.where((m) => m['word']!.isNotEmpty).toList();
    }

    // 单图格式: {"items": [...]}
    final items = parsed['items'] as List<dynamic>?;
    if (items == null) return [];
    return items
        .map((e) => {
              'word': e['word']?.toString() ?? '',
              'translation': e['translation']?.toString() ?? '',
              'word_type': e['word_type']?.toString() ?? 'word',
              'original_sentence':
                  e['original_sentence']?.toString() ?? '',
              'part_of_speech': e['part_of_speech']?.toString(),
              'grammar_note': e['grammar_note']?.toString(),
            })
        .where((m) => m['word']!.isNotEmpty)
        .toList();
  }

  // ── 模型列表（混合：先调API，失败则用内置清单兜底） ──

  /// 豆包常用模型 ID 列表（API 不通时的兜底，按推荐速度排序）
  static const List<String> fallbackDoubaoModels = [
    'doubao-seed-2-0-mini-260715',   // 最快：速度和成本优先
    'doubao-seed-1-6-flash-250615',  // 闪推：上一代极速
    'doubao-seed-2-1-turbo-260628',  // 新 turbo
    'doubao-seed-2-0-lite-260428',   // 当前默认
    'doubao-seed-2-1-pro-260628',
    'doubao-seed-2-0-pro-260215',
    'doubao-seed-1-6-vision-250815',
    'doubao-seed-1-6-250615',
    'doubao-seed-evolving',
  ];

  /// 获取模型列表：先尝试 GET /models，失败则返回内置清单
  static Future<List<String>> fetchModels(
    String baseUrl,
    String apiKey,
  ) async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
      ));

      final response = await dio.get('/models');
      final data = response.data['data'] as List<dynamic>?;
      if (data != null && data.isNotEmpty) {
        final ids = data
            .map((e) => e['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
        ids.sort();
        if (ids.isNotEmpty) return ids;
      }
    } catch (_) {
      // API 不通，走兜底
    }
    return List.of(fallbackDoubaoModels);
  }
}
