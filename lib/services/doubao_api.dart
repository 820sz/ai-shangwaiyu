import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../config/constants.dart';
import 'api_endpoint.dart';
import 'base_api.dart';

/// SSE 流式数据块
class SseChunk {
  final String text;
  final bool isReasoning;
  const SseChunk({required this.text, required this.isReasoning});
}

/// 主槽位(视觉)模型候选判断 — 只保留可能支持图片识别的模型。
/// 方舟 /models 返回全平台模型(含未开通的老文本模型/角色模型/纯文本 DS 转售),
/// 全量展示会误导用户(v1.3.0-2 用户实测截图实锤)。
/// 保留:含 vision 的模型(任何厂商)+ 豆包 seed 系(新一代多模态);
/// 隐藏:doubao-1-5* 老文本、*character* 角色、deepseek-r1/v3 纯文本等。
bool isVisionCandidate(String id) {
  final m = id.toLowerCase();
  if (m.contains('vision')) return true;
  if (m.startsWith('doubao-seed')) return true;
  return false;
}

/// 是否发送 image_url 的 detail 字段 — 豆包/Ark 系支持,DeepSeek 视觉模型
/// 不认此字段(未知参数可能 400),只发 url。纯函数,可单测。
bool shouldSendDetailFlag(String model) {
  final m = model.toLowerCase();
  return m.contains('doubao') || m.contains('seed') || m.contains('ark');
}

/// 模型是否支持图片输入 — 判断追问能否附带识别图片:
/// 豆包/Ark 系全支持;DeepSeek 只有 vision 系列支持(纯文本模型发图必 400);
/// 未知厂商默认不带图(稳妥,避免每次追问 400→降级重试的双倍耗时)。
bool modelSupportsImages(String model) {
  final m = model.toLowerCase();
  if (m.contains('doubao') || m.contains('seed') || m.contains('ark')) {
    return true;
  }
  if (m.contains('deepseek')) return m.contains('vision');
  return false;
}

/// 多模态 API 服务(主槽位):识图/全文翻译/追问。
/// 原豆包服务,配置源收敛到 ApiEndpointConfig.primary。
class DoubaoApiService extends BaseApiService {
  @override
  ApiEndpointConfig get config => ApiEndpointConfig.primary;

  /// 当前使用的模型名（公开，供 UI 展示/调试）
  String get modelName => config.model;

  /// 检查是否已配置 API Key
  bool get isConfigured => config.isConfigured;

  // ── 图片压缩 ──

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

  Map<String, dynamic> _buildRequestBody(
    List<String> imageUris, {
    String? sourceBook,
    String? sourcePage,
    bool stream = false,
    String analysisMode = AppConstants.analysisModeMarked,
    List<String> excludeWords = const [],
  }) {
    final bookHint = sourceBook != null && sourceBook.isNotEmpty
        ? '，出处书籍："$sourceBook"' : '';
    final pageHint = sourcePage != null && sourcePage.isNotEmpty
        ? '，页码：$sourcePage' : '';
    final countHint = imageUris.length > 1
        ? '（共${imageUris.length}张图片）'
        : '';
    // 补充识别模式:告知已识别词,只找遗漏,禁止重复(v1.3.0 问题 3)
    final excludeHint = excludeWords.isEmpty
        ? ''
        : '\n补充识别：以下内容已经识别过，请找出照片中遗漏的标记内容，只输出遗漏项，不要重复输出任何一条：${excludeWords.take(200).join(' | ')}';

    final (String systemPrompt, String userPrompt) = switch (analysisMode) {
      AppConstants.analysisModeFullText => (
        '''你是一个专业的翻译助手。用户发给你一张外语阅读材料的照片，请翻译照片中的所有文字内容。
返回 JSON：{"paragraphs": [{"original": "原文段落", "translation": "中文翻译"}]}
要求：保持原文段落结构，翻译准确流畅。只返回JSON。''',
        '请翻译这些阅读材料照片中的全文内容$bookHint$pageHint$countHint'
      ),
      _ => (
        '''你是英语学习助手。识别照片中被标记的英语内容。输出JSON，格式：
{"items":[{"word":"完整原文","translation":"中文释义","word_type":"word|phrase|sentence","part_of_speech":"词性(可选)","original_sentence":"完整句子(短语/句子必填,单词可选)"}]}
要求：1.word 必须与照片中的文本完全一致——单词、短语、句子一律完整输出,禁止截断,禁止用省略号(…)代替后半部分。2.短语/句子必须在 original_sentence 中给出其所在的完整句子(必填,不可省略)。3.单词给词性。${imageUris.length > 1 ? '多图格式：{"items_by_image":[{"image_index":0,"items":[...]},...]}' : ''}无标记返回{"items":[]}。只输出JSON。简洁思考。''',
        '识别标记的英语内容$bookHint$pageHint$countHint$excludeHint'
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
                // detail 仅豆包系发:DeepSeek 视觉模型不认未知字段(400)
                'image_url': {
                  'url': uri,
                  if (shouldSendDetailFlag(modelName)) 'detail': 'low',
                },
              },
            {'type': 'text', 'text': userPrompt},
          ],
        },
      ],
      'max_tokens': 2048,
      'temperature': 0,
      ...config.buildThinkingParams(),
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
    if (!config.isConfigured) {
      throw Exception('请先在设置中配置主 API Key');
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

    final response = await postWithReasoningFallback(
      '/chat/completions', body, cfg: config);

    final content = BaseApiService.extractContent(response.data);
    return parseResponse(content, analysisMode: analysisMode);
  }

  // ── 流式版（新增） ──

  /// 拍照取词 — 流式返回（async* 生成器，逐个产出 SseChunk）
  Stream<SseChunk> extractVocabularyStream(
    List<File> imageFiles, {
    String? sourceBook,
    String? sourcePage,
    String analysisMode = AppConstants.analysisModeMarked,
    List<String> excludeWords = const [],
  }) async* {
    if (imageFiles.isEmpty) throw Exception('没有可识别的图片');
    if (!config.isConfigured) {
      throw Exception('请先在设置中配置主 API Key');
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
      excludeWords: excludeWords,
    );

    final response = await postWithReasoningFallback(
      '/chat/completions', body, cfg: config,
      responseType: ResponseType.stream);

    final data = response.data;
    if (data is! ResponseBody) {
      throw Exception('API 未返回流式响应：${data is Map ? data['error'] ?? data : data}');
    }
    yield* _parseSseStream(data.stream);
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

  /// AI 自动补全单词信息(v1.3.0 问题 2):
  /// 用户手动补充词汇时只填词,点「✨ AI 补全」调 [endpoint](默认当前追问端点)
  /// 非流式拿 释义/词性/例句/语法,回填表单可改。
  /// 思考强制 disabled(快速补全,不等待思考)。
  Future<Map<String, String>> completeWordInfo(
    String word, {
    ApiEndpointConfig? endpoint,
  }) async {
    final cfg = endpoint ?? config;
    if (!cfg.isConfigured) {
      throw Exception('请先在设置中配置 API Key');
    }

    final body = {
      'model': cfg.model,
      'messages': [
        {
          'role': 'system',
          'content':
              '你是英语学习助手。用户给出一个英语单词或短语，请返回 JSON：'
              '{"translation":"中文释义","part_of_speech":"词性(如 n./v./adj./phrase)","original_sentence":"包含该词的完整英文例句","grammar_note":"语法要点(可选,单词可省)"}。'
              '只输出 JSON。',
        },
        {'role': 'user', 'content': word},
      ],
      'temperature': 0,
      'max_tokens': 1024,
      'thinking': {'type': 'disabled'},
    };

    final response = await postWithReasoningFallback(
        '/chat/completions', body, cfg: cfg);
    final content = BaseApiService.extractContent(response.data);
    return parseWordInfo(content);
  }

  /// 解析 AI 补全返回的 JSON(纯静态,可单测)。
  /// 兼容 ```json 包裹;缺字段回空串,绝不抛异常——用户仍可手动填。
  static Map<String, String> parseWordInfo(String content) {
    String jsonStr = content.trim();
    if (jsonStr.startsWith('```')) {
      final start = jsonStr.indexOf('\n');
      final end = jsonStr.lastIndexOf('```');
      if (start != -1 && end != -1) {
        jsonStr = jsonStr.substring(start + 1, end).trim();
      }
    }
    try {
      final parsed = jsonDecode(jsonStr);
      if (parsed is! Map) return {};
      String s(String key) => parsed[key]?.toString().trim() ?? '';
      return {
        'translation': s('translation'),
        'part_of_speech': s('part_of_speech'),
        'original_sentence': s('original_sentence'),
        'grammar_note': s('grammar_note'),
      };
    } catch (_) {
      return {};
    }
  }

  /// 将图片文件转为 data URI 列表(供追问附带识别图片)。
  /// 复用 [extractVocabularyStream] 同款压缩逻辑,大图缩至 2048 内。
  Future<List<String>> imageDataUrisFor(List<File> files) async {
    return Future.wait(files.map((f) => _imageToDataUri(f)), eagerError: true);
  }

  /// 基于已有识别结果发送追问,返回流式 SSE 块。
  /// [endpoint] 指定槽位(主/副),null 用本服务默认槽位(主)。
  /// [imageDataUris] 非空时以多模态消息发送(模型能"看到"识别图片);
  /// 若模型不支持图片(4xx/错误信息含图相关词)→ 自动降级为纯文本重试一次。
  /// [thinkingLevel] 追问思考档位(独立于槽位识图档位),null 用槽位档位。
  /// [history] 本轮之前的对话(user/ai 交替,v1.4.0 问题 13 根因修复:
  /// 原实现只发 system+当前问题 → AI 完全没有上下楼记忆,"
  /// 连上一楼的对话都没印象")。材料上下文(识别结果/翻译)放 system。
  Stream<SseChunk> followUpStream(
    String question, {
    required String context,
    ApiEndpointConfig? endpoint,
    List<String>? imageDataUris,
    String? thinkingLevel,
    List<Map<String, String>> history = const [],
  }) async* {
    final cfg = endpoint ?? config;
    if (!cfg.isConfigured) {
      throw Exception('请先在设置中配置 API Key');
    }

    // 最后一条 user 消息:纯问题(+可选图片)由纯函数组装;材料上下文放 system
    final lastUserContent = buildFollowUpLastUserContent(
      question: question,
      imageDataUris: imageDataUris,
      model: cfg.model,
    );

    final systemContent = context.trim().isEmpty
        ? '你是英语学习助手。回答用户追问。简洁准确，根据材料量自行决定回答长度。'
        : '你是英语学习助手。基于图片识别结果回答用户追问。简洁准确，根据材料量自行决定回答长度。\n\n'
            '识别材料上下文：\n$context';

    final body = {
      'model': cfg.model,
      'messages': [
        {'role': 'system', 'content': systemContent},
        // 历史对话(上下楼记忆)— 仅已完成消息,最近 20 条由调用方截断
        for (final h in history)
          {
            'role': h['role'],
            'content': h['content'],
          },
        {'role': 'user', 'content': lastUserContent},
      ],
      'temperature': 0.3,
      'max_tokens': 2048,
      ...cfg.buildThinkingParamsFor(thinkingLevel ?? cfg.thinking),
      'stream': true,
    };

    try {
      final response = await postWithReasoningFallback(
        '/chat/completions', body, cfg: cfg,
        responseType: ResponseType.stream);
      yield* _parseSseStream(_responseStream(response));
    } catch (e) {
      // 带图但模型不支持图片 → 降级纯文本重试一次(每次追问最多 1 次降级)
      if (imageDataUris != null && imageDataUris.isNotEmpty && _imageRejected(e)) {
        debugPrint('ReadFlow followUp image rejected, retry text-only: $e');
        final retryBody = {
          ...body,
          'messages': [
            body['messages'][0],
            for (final h in history)
              {'role': h['role'], 'content': h['content']},
            {'role': 'user', 'content': '用户提问：$question'},
          ],
        };
        final retry = await postWithReasoningFallback(
          '/chat/completions', retryBody, cfg: cfg,
          responseType: ResponseType.stream);
        yield* _parseSseStream(_responseStream(retry));
        return;
      }
      rethrow;
    }
  }

  /// 组装追问最后一轮 user content(v1.4.0):
  /// 有图 → content parts(image_url + text=问题);无图 → 纯问题文本。
  /// 材料上下文不走这里——已放 system 消息。OpenAI 兼容多模态格式;
  /// detail 仅豆包系发。纯函数,可单测。
  static Object buildFollowUpLastUserContent({
    required String question,
    required List<String>? imageDataUris,
    required String model,
  }) {
    if (imageDataUris == null || imageDataUris.isEmpty) {
      return '用户提问：$question';
    }
    return [
      for (final uri in imageDataUris)
        {
          'type': 'image_url',
          'image_url': {
            'url': uri,
            if (shouldSendDetailFlag(model)) 'detail': 'low',
          },
        },
      {'type': 'text', 'text': '用户提问：$question'},
    ];
  }

  /// 判断错误是否"模型不支持图片"——带图追问失败时据此降级纯文本。
  /// 覆盖 DioException(400/422/参数错误)与描述含图相关关键词的错误。
  static bool _imageRejected(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('image') ||
        msg.contains('vision') ||
        msg.contains('multimodal') ||
        msg.contains('picture')) {
      return true;
    }
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 400 || code == 422 || code == 415) return true;
    }
    return false;
  }

  /// 从响应中取流式 body(统一 postWithReasoningFallback 的两种返回形态)
  Stream<List<int>> _responseStream(Response response) {
    final data = response.data;
    if (data is! ResponseBody) {
      throw Exception(
          'API 未返回流式响应：${data is Map ? data['error'] ?? data : data}');
    }
    return data.stream;
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
        // 安全解析:该模型族可能返回字符串/浮点 image_index(结构输出不可靠)
        final rawIdx = group['image_index'];
        final imgIdx = rawIdx is int
            ? rawIdx
            : rawIdx is num
                ? rawIdx.toInt()
                : rawIdx is String
                    ? int.tryParse(rawIdx) ?? 0
                    : 0;
        final items = group['items'] as List<dynamic>? ?? [];
        for (final e in items) {
          final word = e['word']?.toString() ?? '';
          final type = e['word_type']?.toString() ?? 'word';
          final os = e['original_sentence']?.toString() ?? '';
          allItems.add({
            'word': cleanTruncatedWord(word, type, os),
            'translation': e['translation']?.toString() ?? '',
            'word_type': type,
            'original_sentence': os,
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
        .map((e) {
          final word = e['word']?.toString() ?? '';
          final type = e['word_type']?.toString() ?? 'word';
          final os = e['original_sentence']?.toString() ?? '';
          return {
            'word': cleanTruncatedWord(word, type, os),
            'translation': e['translation']?.toString() ?? '',
            'word_type': type,
            'original_sentence': os,
            'part_of_speech': e['part_of_speech']?.toString(),
            'grammar_note': e['grammar_note']?.toString(),
          };
        })
        .where((m) => m['word']!.isNotEmpty)
        .toList();
  }

  /// 词条化截断清洗(数据层治本):模型可能把长句 word 截断成
  /// "开头~20字符+省略号"(省略号形态不固定:…/.../⋯/……/.. 等),
  /// original_sentence 字段才是完整句子。word 带截断特征且存在更长的
  /// 完整句时,用完整句替换 word 数据本身——显示/保存/编辑全走完整句子。
  /// 正常单词/短语不带省略号特征,不受影响(如 "compound with" 不匹配)。
  static String cleanTruncatedWord(
    String word,
    String wordType,
    String originalSentence,
  ) {
    if (originalSentence.isEmpty) return word;
    if (originalSentence.length <= word.length) return word;
    // 截断特征:尾部 2+ 个点(…/⋯/../.../…… 等任意形态)
    final truncRe = RegExp(r'([…⋯]{1,}|\.{2,})$');
    if (truncRe.hasMatch(word)) return originalSentence;
    return word;
  }

  // ── 模型列表（混合：先调API，失败则用内置清单兜底） ──

  /// 获取模型列表：先尝试 GET /models，再按允许前缀/能力过滤，最后内置清单兜底。
  /// [allowPrefixes] 只保留前缀匹配的模型(如副槽位只留 deepseek 系列)——
  /// 方舟聚合端点会返回非本族模型，混入列表会误导用户。
  /// [keepFilter] 按能力过滤(如主槽位 [isVisionCandidate]);过滤后为空
  /// (该端点没有视觉模型)→ 返回内置视觉清单,不显示全量。
  /// 拉取失败 → 返回内置清单。
  static Future<List<String>> fetchModels(
    String baseUrl,
    String apiKey, {
    List<String> allowPrefixes = const [],
    bool Function(String)? keepFilter,
    List<String> fallback = AppConstants.primaryFallbackModels,
  }) async {
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
        if (ids.isNotEmpty && allowPrefixes.isNotEmpty) {
          final filtered = ids
              .where((id) => allowPrefixes.any((p) => id.startsWith(p)))
              .toList();
          if (filtered.isNotEmpty) return filtered;
        }
        if (ids.isNotEmpty && keepFilter != null) {
          final kept = ids.where(keepFilter).toList();
          if (kept.isNotEmpty) return kept;
          return List.of(fallback); // 无视觉模型 → 内置视觉清单
        }
        if (ids.isNotEmpty) return ids;
      }
    } catch (_) {
      // API 不通，走兜底
    }
    return List.of(fallback);
  }
}
