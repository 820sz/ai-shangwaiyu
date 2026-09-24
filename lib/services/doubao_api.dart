import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/constants.dart';
import 'api_endpoint.dart';
import 'base_api.dart';
import 'vision_image.dart';

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

/// 主槽位模型菜单清单(v1.4.3 用户实测"配了 DS 还显示豆包待选"):
/// 1. 优先最近一次 /models 拉取的真实列表([DoubaoApiService.lastModels]);
/// 2. 否则按当前端点族:deepseek.com → DS 三件套;方舟/其他 → 豆包系;
/// 3. 始终包含当前配置模型(去重,保证菜单能显示当前选中项)。
List<String> primaryModelChoices() {
  final model = ApiEndpointConfig.primary.model;
  final hasDsEndpoint =
      ApiEndpointConfig.primary.baseUrl.toLowerCase().contains('deepseek.com');
  final List<String> base = hasDsEndpoint
      ? [
          AppConstants.deepseekVisionModel,
          AppConstants.deepseekChatModel,
          ...AppConstants.deepseekFallbackModels,
        ]
      : List.of(AppConstants.primaryFallbackModels);
  final source = DoubaoApiService.lastModels ?? base;
  return <String>{
    if (model.isNotEmpty) model,
    ...source,
  }.toList();
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
  ///
  /// v2.4:统一走 [VisionImagePrep] 预处理 —— **按 EXIF 把像素转正 + 长边压到
  /// 2000px + JPEG q88**。旧实现只在"文件 >500KB 且 >2048px"时才处理:
  /// 手机直出的小图(或被 image_picker 压过的图)会**原样发出**,方向与分辨率
  /// 全凭运气 —— 用户提供的样本里就有横置/倒置的页面,模型得先"歪着读"。
  /// 失败仍回退原图,绝不因为预处理失败就不给识别。
  Future<String> _imageToDataUri(File imageFile) async {
    final rawBytes = await _readImageBytes(imageFile);
    try {
      return VisionImagePrep.toDataUri(rawBytes);
    } catch (e) {
      debugPrint('ReadFlow _imageToDataUri fallback: $e');
      final mime = _detectImageMime(rawBytes);
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
    bool calibrate = false,
  }) {
    final bookHint = sourceBook != null && sourceBook.isNotEmpty
        ? '，出处书籍："$sourceBook"' : '';
    final pageHint = sourcePage != null && sourcePage.isNotEmpty
        ? '，页码：$sourcePage' : '';
    final countHint = imageUris.length > 1
        ? '（共${imageUris.length}张图片）'
        : '';
    // 补充识别模式(v1.4.4 加固):已识别清单 + "绝不重复/只找标记/宁少勿错"
    final excludeHint = excludeWords.isEmpty
        ? ''
        : '\n补充识别模式：以下内容已经识别过了，绝对不要重复输出任何一条：\n'
            '${excludeWords.take(200).join(' | ')}\n'
            '只输出这次新发现的、且在照片上有明确手写标记痕迹的内容。\n'
            '如果你无法确定某个内容是否有标记，宁可漏掉也不要输出。\n'
            '如果本页没有新的标记内容，直接返回 {"items": []}。';

    final (String systemPrompt, String userPrompt) = switch (analysisMode) {
      AppConstants.analysisModeFullText => (
        '''你是一个专业的翻译助手。用户发给你一张外语阅读材料的照片，请翻译照片中的所有文字内容。
返回 JSON：{"paragraphs": [{"original": "原文段落", "translation": "中文翻译"}]}
要求：保持原文段落结构，翻译准确流畅。只返回JSON。''',
        '请翻译这些阅读材料照片中的全文内容$bookHint$pageHint$countHint'
      ),
      // 校准重识别(v1.7.0):用户对首次识别不满意时的"认真重做一遍"。
      // 与首次识别的差别:①逐行扫描的作业流程 ②标记类型清单+排除干扰物
      // ③输出前自检 ④高清图(detail=high,提升小字/浅色笔迹可辨识度)
      _ when calibrate => (
        '''你是严谨的英语学习助手，正在做一次"校准重识别"：用户认为上一次识别有漏识或误识，请重新完整检查图片。
输出JSON，格式：
{"items":[{"word":"完整原文","translation":"中文释义","word_type":"word|phrase|sentence","part_of_speech":"词性(可选)","phonetic_uk":"英式IPA音标(仅单词可选)","phonetic_us":"美式IPA音标(仅单词可选)","original_sentence":"完整句子(短语/句子必填)"}]}

作业流程(必须按此顺序)：
1. 先整体扫一遍图片，找出所有人工标记的位置，再逐个读取被标记的文字。
2. 标记类型包括：圈画、下划线、双下划线、波浪线、荧光笔(黄/绿/粉等彩色底纹)、方框、星号、箭头、书签贴/便签、页边中文批注旁对应的英文。
3. 把标点符号、连字符、缩写、专有名词原样保留；看不清的字母按上下文补全，但不要编造不存在的词。
4. 同一处内容重复标记只输出一次。

识别纪律：
1. 只输出有明确标记痕迹的内容；未标记的正文一律不输出。
2. word 必须与图上文字完全一致，禁止截断、禁止省略号。
3. 短语/句子必须在 original_sentence 给出其所在完整句子。
4. 输出前自检：逐条确认"这个词在图上确实有标记痕迹"，无法确认的删掉——宁可少，不可错。
${imageUris.length > 1 ? '5. 多图格式：{"items_by_image":[{"image_index":0,"items":[...]},...]}' : ''}
无任何标记返回{"items":[]}。只输出JSON。''',
        '请校准重识别这些照片中被标记(批注/圈画/划线/荧光笔等)的英语内容$bookHint$pageHint$countHint'
      ),
      _ => (
        '''你是英语学习助手。识别照片中"被标注"的英语内容。输出JSON，格式：
{"items":[{"word":"完整原文","translation":"中文释义","word_type":"word|phrase|sentence","part_of_speech":"词性(可选)","phonetic_uk":"英式IPA音标(仅单词可选,如 /ˈleɪzi/)","phonetic_us":"美式IPA音标(仅单词可选)","original_sentence":"完整句子(短语/句子必填,单词可选)","line":"该词条所在的整行原文(照抄,用于核对)"}]}
标记定义：手写笔迹圈画、下划线、波浪线、荧光笔、方框、星号、书签贴、页边批注对应的英文等读者标注痕迹。
识别纪律(v1.4.4；v2.4 加固)：
1. **照片可能是任何方向**(横拍/竖拍/倒置)。先按文字方向在心里把它转正,再逐行读;
   不确定方向时,以能读出通顺英文的方向为准。
2. **只输出有明确标记痕迹的内容**;正文中未作任何标记的文字一律不要输出。
3. **页边手写的中文批注也要输出**(用户会自己挑要不要收):它照原样写进 word,
   同时把旁边的英文(如果有)单独作为一条输出。
4. 如果不能确定某个内容是否被标记,宁可漏掉,也不要输出。
5. word 必须与照片中的文本完全一致——单词、短语、句子一律**完整**输出,禁止截断,
   禁止用省略号(…)代替后半部分;跨行的标记要把整段文字接起来写完整。
6. word_type 按长度与结构自己判断:**一个词就是 word**(不要因为页面上有长句就都写成 phrase);
   两三个词的固定搭配是 phrase;带主谓/句末标点的整句是 sentence。
   中文批注的 word_type 写 word。
7. 短语/句子必须在 original_sentence 中给出其所在的完整句子(必填,不可省略)。
8. **translation 要结合语境**(用户实测过"生硬翻译"):
   - 单词:先看它在这句话里的词性与含义再给中文(bank 河岸/银行、issue 问题/发行),
     不要给词典第一个义项;
   - 短语/句子:给整句通顺的中文,不要逐词硬译、不要保留英文语序。
9. 单词给词性,并同时给 phonetic_uk(英式)与 phonetic_us(美式)音标;
   两者一致时照原样各写一遍,拿不准的音标宁可留空。
10. line 必须是**照抄**图上那一行的原文(判分/核对用,不要改写、不要翻译)。
11. 先扫一遍找出所有标记位置,再逐个读取。**同一个词在不同位置被标了两次就输出两次**
    (各自带自己的 line,系统会合并成"出现过 ×2");同一处重复标记只输出一次。${imageUris.length > 1 ? '多图格式：{"items_by_image":[{"image_index":0,"items":[...]},...]}' : ''}
无任何标记返回{"items":[]}。只输出JSON。简洁思考。''',
        '识别标记的英语内容$bookHint$pageHint$countHint$excludeHint'
      ),
    };

    // 请求体统一走 BaseApiService.buildChatBody(v1.9.0):
    // DS 官方省略 max_tokens(思考与正文共享总预算)/temperature、补 stream_options;
    // 方舟等端点显式给 max_tokens 与 temperature,且不发 stream_options。
    return BaseApiService.buildChatBody(
      cfg: config,
      stream: stream,
      temperature: 0, // 识别要确定性
      maxTokens: 4096,
      // v2.4(用户决策):**识图固定低思考档**。识别是"照抄"任务,不需要长推理 ——
      // 实测用户开着"高"档时一次烧掉 6 秒 + 6225 字思考,输出却只有 1 条:
      // 思考预算挤占正文,长思考还容易跑偏(越想越编)。
      thinkingLevel: 'low',
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': [
            for (final uri in imageUris)
              {
                'type': 'image_url',
                // detail 仅豆包系发:DeepSeek 视觉模型不认未知字段(400)。
                // 校准重识别用 high(小字/浅色笔迹更可辨),日常识别用 low 省流量
                'image_url': {
                  'url': uri,
                  if (shouldSendDetailFlag(modelName))
                    'detail': calibrate ? 'high' : 'low',
                },
              },
            {'type': 'text', 'text': userPrompt},
          ],
        },
      ],
    );
  }

  // ── 同步版（保留向下兼容） ──

  // ── 流式版（新增） ──

  /// 拍照取词 — 流式返回（async* 生成器，逐个产出 SseChunk）
  /// [calibrate] true = 校准重识别(v1.7.0):逐行扫描 + 高清图 + 自检提示词,
  /// 结果由调用方整组替换(区别于 [excludeWords] 的"只补漏")。
  Stream<SseChunk> extractVocabularyStream(
    List<File> imageFiles, {
    String? sourceBook,
    String? sourcePage,
    String analysisMode = AppConstants.analysisModeMarked,
    List<String> excludeWords = const [],
    bool calibrate = false,
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
      calibrate: calibrate,
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

  /// 单个 SSE 事件 → SseChunk(null = 无内容 / [DONE] / 解析失败)
  static SseChunk? _chunkFromEventPayload(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty || trimmed == '[DONE]') return null;
    try {
      final data = jsonDecode(trimmed);
      if (data is! Map) return null;
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
      debugPrint('ReadFlow SSE frame parse failed: $e');
      rethrow; // 交由调用方计数,不再静默丢弃
    }
    return null;
  }

  /// SSE 流解析器(v1.9.0 重写,公开以便单测)。
  ///
  /// 相比旧实现(逐块 `utf8.decode(allowMalformed: true)` + 只认 `\n\n`)修掉:
  /// 1. **中文跨包损坏**:改用 `utf8.decoder` 流式解码,被 TCP 包切开的
  ///    多字节字符会保留半个序列等下一块 —— 旧实现会把它们烧成 U+FFFD
  ///    且不可恢复(坏数据静默入库)。
  /// 2. **分帧**:按 SSE 规范以"空行"结束事件,兼容 `\n` / `\r\n` / 孤立 `\r`
  ///    (用 LineSplitter),不再依赖硬编码 `\n\n`。
  /// 3. **同一事件多条 `data:`**:按规范用 `\n` 拼接后解析(旧实现只取第一行,
  ///    会丢掉含 finish_reason/真实 content 的那一段)。
  /// 4. **内存上限**:单事件累计超过 1MB 直接抛错,避免 buffer 无界增长。
  /// 5. **失败可见**:帧解析失败计数;若整条流一个 chunk 都没产出却失败过,
  ///    抛出可诊断错误(旧实现只 debugPrint,表现为"AI 没识别到内容")。
  static Stream<SseChunk> parseSseStream(Stream<List<int>> rawStream) async* {
    final dataLines = <String>[];
    var eventChars = 0;
    var parsedFrames = 0;
    var failedFrames = 0;

    SseChunk? takeEvent() {
      if (dataLines.isEmpty) return null;
      final payload = dataLines.join('\n');
      dataLines.clear();
      eventChars = 0;
      try {
        final chunk = _chunkFromEventPayload(payload);
        parsedFrames++;
        return chunk;
      } catch (_) {
        failedFrames++;
        return null;
      }
    }

    // ⚠️ v1.9.1 真机修复:`rawStream` 的**运行时**类型是 `Stream<Uint8List>`
    // (dio 的 `ResponseBody.stream` 就是这个),而 `utf8.decoder` 是
    // `StreamTransformer<List<int>, String>` —— 直接 transform 会被运行时类型
    // 检查拒绝,真机上识图/追问/推荐全线报:
    //   type 'Utf8Decoder' is not a subtype of type
    //   'StreamTransformer<Uint8List, String>' of 'streamTransformer'
    // 单测当时用 `Stream<List<int>>` 造流,把这个坑测绿了(v1.9.1 起测试改用
    // Uint8List 造流)。`cast<List<int>>()` 让接收者的类型参数变成 List<int>,
    // transform 才能通过检查 —— 这是 Dart 官方推荐的修法。
    final lines = rawStream
        .cast<List<int>>()
        .transform(utf8.decoder) // allowMalformed:false —— 坏字节必须暴露
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.isEmpty) {
        final chunk = takeEvent();
        if (chunk != null) yield chunk;
        continue;
      }
      // SSE 字段格式:`field: value`(冒号后可有可无空格);只有 data 参与内容
      if (line.startsWith('data:')) {
        final raw = line.substring(5);
        dataLines.add(raw.startsWith(' ') ? raw.substring(1) : raw);
        eventChars += raw.length;
        if (eventChars > 1 << 20) {
          throw StateError('SSE 事件超过 1MB,已中止(可能是端点返回了非流式内容)');
        }
      }
      // id/event/retry/注释(以 : 开头)等字段对本应用无用,忽略
    }

    // 流结束但最后一个事件没有以空行收尾 → 收尾处理
    final tail = takeEvent();
    if (tail != null) yield tail;

    if (parsedFrames == 0 && failedFrames > 0) {
      throw Exception(
        '流式响应解析失败($failedFrames 帧无法解析),端点可能未按 SSE 返回',
      );
    }
  }

  /// 历史实例入口(保留调用点不变)
  Stream<SseChunk> _parseSseStream(Stream<List<int>> rawStream) =>
      DoubaoApiService.parseSseStream(rawStream);

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

    final body = BaseApiService.buildChatBody(
      cfg: cfg,
      temperature: 0,
      maxTokens: 1024,
      thinkingLevel: 'disabled',
      messages: [
        {
          'role': 'system',
          'content':
              '你是英语学习助手。用户给出一个英语单词或短语，请返回 JSON：'
              '{"translation":"中文释义","part_of_speech":"词性(如 n./v./adj./phrase)",'
              // v2.0:一次给英/美两套音标(用户决策)——只回一套时词条页面
              // 只能显示一个,用户无处可比;两套都拿不到就都留空。
              '"phonetic_uk":"英式 IPA 音标(用两个斜杠包裹,如 /ˈʌnfetəd/;'
              '英式与美式一致时照原样再写一遍,短语/句子可省)",'
              '"phonetic_us":"美式 IPA 音标(同上格式)",'
              '"original_sentence":"包含该词的完整英文例句",'
              '"grammar_note":"语法要点(可选,单词可省)"}。'
              // v2.4(B3,用户反馈"偶尔是生硬翻译出来的,并不是符合原句中词汇的意思"):
              // 翻译要**结合语境**,不能给词典第一个义项了事。
              'translation 的硬性要求:'
              '① 如果是短语/句子,给**整句通顺**的中文,不要逐词硬译、不要保留英文语序;'
              '② 如果是单词,先判断它在这句话里的词性与含义,再给中文 —— '
              '同一个词在不同语境意思不同(bank 河岸/银行、issue 问题/发行),'
              '给错了等于白背;'
              '③ 拿不准就先给最贴合语境的那个义项,不要罗列一堆义项。'
              '只输出 JSON。',
        },
        {'role': 'user', 'content': word},
      ],
    );

    final response = await postWithReasoningFallback(
        '/chat/completions', body, cfg: cfg);
    final content = BaseApiService.extractContent(response.data);
    // v1.9.0:思考模型可能把 JSON 写在思考通道 → 统一兜底
    return parseWordInfo(
      content.trim().isNotEmpty
          ? content
          : BaseApiService.extractContentWithReasoning(response.data),
    );
  }

  /// 解析 AI 补全返回的 JSON(纯静态,可单测)。
  /// 兼容 ```json 包裹;缺字段回空串,绝不抛异常——用户仍可手动填。
  ///
  /// v2.0:同时解析 phonetic_uk / phonetic_us(英/美双音标)。
  /// 模型只回老字段 `phonetic` 时,把它同时回填到两边(词条页面至少能显示
  /// 一套);`phonetic` 也保持原样返回,老调用方(表单回填)行为不变。
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
      // trim + 去空:模型偶尔给 "  " 或 null,空串在词条页要当"没有"处理
      String s(String key) => parsed[key]?.toString().trim() ?? '';
      final legacy = s('phonetic');
      return {
        'translation': s('translation'),
        'part_of_speech': s('part_of_speech'),
        'phonetic': legacy,
        'phonetic_uk': s('phonetic_uk').isNotEmpty ? s('phonetic_uk') : legacy,
        'phonetic_us': s('phonetic_us').isNotEmpty ? s('phonetic_us') : legacy,
        'original_sentence': s('original_sentence'),
        'grammar_note': s('grammar_note'),
      };
    } catch (_) {
      // 类型不对(如 items 是列表、整体是数组)→ 当作"没解析出",不抛
      return {};
    }
  }

  /// 将图片文件转为 data URI 列表(供追问附带识别图片)。
  /// 复用 [extractVocabularyStream] 同款压缩逻辑,大图缩至 2048 内。
  Future<List<String>> imageDataUrisFor(List<File> files) async {
    return Future.wait(files.map((f) => _imageToDataUri(f)), eagerError: true);
  }

  // ── 写译批改(v1.5.0,多图/错误汇总 v1.6.0) ──

  /// 步骤1:手写英文识别 — 图片(可多张) → 转写文本(保留段落,不点评)。
  /// 走主槽位(视觉)。思考强制 disabled:转写要快,不需要思考。
  /// 多图按上传顺序拼接为一份电子档。
  Future<String> transcribeWriting(
    List<File> imageFiles, {
    ApiEndpointConfig? endpoint,
  }) async {
    if (imageFiles.isEmpty) throw Exception('没有可识别的图片');
    final cfg = endpoint ?? config;
    if (!cfg.isConfigured) {
      throw Exception('请先在设置中配置主 API Key');
    }
    final uris = await imageDataUrisFor(imageFiles);
    final multi = uris.length > 1;
    final body = BaseApiService.buildChatBody(
      cfg: cfg,
      temperature: 0,
      // v1.9.0(P2-18):多页手写稿 + 思考档位会吃预算,2048 太小 → 8192;
      // DS 官方走 buildChatBody 自动省略 max_tokens(交服务端默认)
      maxTokens: 8192,
      thinkingLevel: 'disabled',
      messages: [
        {
          'role': 'system',
          'content':
              '你是手写体识别助手。用户提供手写英文练习的照片(可能多张),请准确转写其中的英文内容,'
              '保留段落与换行。${multi ? '多张图片按顺序拼接为一份完整文稿,不要加"第N张"等标注。' : ''}'
              '只输出转写文本本身,不解释、不翻译、不点评、不加引号。',
        },
        {
          'role': 'user',
          'content': [
            for (final uri in uris)
              {
                'type': 'image_url',
                'image_url': {
                  'url': uri,
                  if (shouldSendDetailFlag(cfg.model)) 'detail': 'low',
                },
              },
            {
              'type': 'text',
              'text': multi
                  ? '请按顺序转写这些图片中的英文手写内容，合并成一份连续文稿'
                  : '请转写这张图片中的英文手写内容',
            },
          ],
        },
      ],
    );

    final response = await postWithReasoningFallback(
        '/chat/completions', body, cfg: cfg);
    final content =
        BaseApiService.extractContentWithReasoning(response.data).trim();
    if (content.isEmpty) {
      throw Exception('AI 未返回转写文本，请重试或手动输入');
    }
    return content;
  }

  /// 步骤2:AI 批改 — 文本输入 → {score, correction, summary, issues, error_summary}。
  /// 优先副槽位(文本模型,便宜快),未配置则用主槽位。
  /// [errorSummary] 要求模型在最后按「词汇/语法/表达优化/其他」四类汇总。
  Future<Map<String, dynamic>> reviewWriting(
    String text, {
    ApiEndpointConfig? endpoint,
  }) async {
    final cfg = endpoint ??
        (ApiEndpointConfig.secondary.isConfigured
            ? ApiEndpointConfig.secondary
            : config);
    if (!cfg.isConfigured) {
      throw Exception('请先在设置中配置 API Key');
    }
    final body = BaseApiService.buildChatBody(
      cfg: cfg,
      temperature: 0,
      maxTokens: 8192, // 长作文 + 逐条点评需要空间(P2-18)
      thinkingLevel: 'disabled',
      messages: [
        {
          'role': 'system',
          'content':
              '你是一名严谨耐心的英语写作老师。请批改用户提交的英文写作,返回 JSON:'
              '{"score":整数0-100,"correction":"修改后的完整英文(保留原意,标点拼写语法修正)",'
              '"issues":[{"original":"原文片段","correction":"修改后",'
              '"type":"词汇|语法|表达优化|其他","reason":"错误原因与中文解释"}],'
              '"error_summary":{"词汇":"这一类问题的汇总(没有则空串)","语法":"...",'
              '"表达优化":"...","其他":"..."},'
              '"summary":"总体评语(中文,60字内)"}。'
              'error_summary 必须四个键齐全,用中文总结每一类错误的共性问题与改进方向(每条 40 字内),'
              '没有该类错误就留空字符串。不输出JSON以外的任何内容。',
        },
        {'role': 'user', 'content': text},
      ],
    );

    final response = await postWithReasoningFallback(
        '/chat/completions', body, cfg: cfg);
    // v1.9.0:统一从"正文或思考通道"取文本(思考模型可能把 JSON 写在思考里)
    final content = BaseApiService.extractContentWithReasoning(response.data);
    final parsed = parseWritingReview(content);
    if (parsed.isEmpty && content.trim().isNotEmpty) {
      // 自诊断:解析失败时把 AI 原文带给用户(前400字)
      final raw = content.trim();
      throw Exception('AI 返回格式异常(原文前400字)：\n'
          '${raw.length > 400 ? raw.substring(0, 400) : raw}');
    }
    return parsed;
  }

  /// 错误汇总的固定四类(顺序即展示顺序)
  static const writingErrorCategories = ['词汇', '语法', '表达优化', '其他'];

  /// 解析批改返回 JSON(纯静态,可单测)。兼容 ```json 包裹;
  /// 缺字段回空串/空列表,绝不抛异常——界面仍可显示部分结果。
  static Map<String, dynamic> parseWritingReview(String content) {
    // v1.9.0(P2-17):统一 extractJsonBlock —— 思考模型常输出
    // "好的,我来批改这份作文:\n```json\n{…}" 这类前置说明,
    // 旧实现只在开头就是 ``` 时剥壳,否则整份解析失败(整轮批改白花钱)。
    var jsonStr = extractJsonBlock(content);
    if (jsonStr.isEmpty) jsonStr = content.trim();
    try {
      final parsed = jsonDecode(jsonStr);
      if (parsed is! Map) return {};
      String s(String key, [String def = '']) =>
          parsed[key]?.toString().trim() ?? def;
      // v1.9.0:score 归一 —— 模型可能回 "85分"/"85/100"/null,
      // 直接 toString 会把这些原样送进 UI(分数圆环显示"85分")。
      final score = _normalizeScore(parsed['score']);
      final issues = <Map<String, String>>[];
      final rawIssues = parsed['issues'];
      if (rawIssues is List) {
        for (final e in rawIssues) {
          if (e is Map) {
            issues.add({
              'original': e['original']?.toString().trim() ?? '',
              'correction': e['correction']?.toString().trim() ?? '',
              'type': e['type']?.toString().trim() ?? '',
              'reason': e['reason']?.toString().trim() ?? '',
            });
          }
        }
      }
      // 错误分类汇总(v1.6.0):四个键固定,缺的补空串
      final rawSummary = parsed['error_summary'];
      final errorSummary = <String, String>{
        for (final c in writingErrorCategories)
          c: (rawSummary is Map ? rawSummary[c]?.toString().trim() : '') ?? '',
      };
      return {
        'score': score,
        'correction': s('correction'),
        'summary': s('summary'),
        'issues': issues,
        'error_summary': errorSummary,
      };
    } catch (_) {
      return {};
    }
  }

  /// 分数归一(纯函数,可单测):从 `85` / `"85分"` / `"85/100"` / `"85.5"`
  /// 里取出 0-100 的整数;取不到返回空串(界面显示 `--`)。
  static String _normalizeScore(Object? raw) {
    if (raw == null) return '';
    final m = RegExp(r'\d+(?:\.\d+)?').firstMatch(raw.toString());
    if (m == null) return '';
    final v = double.tryParse(m.group(0)!);
    if (v == null) return '';
    final clamped = v.clamp(0, 100).round();
    return '$clamped';
  }

  /// 通用流式文本生成(v1.8.0):给「AI 推荐学习材料 / 生成学习内容」这类
  /// 纯文本任务使用——system 提示词原样发送(不像 [followUpStream] 那样
  /// 套"英语学习助手问答"模板)。同样走用户选择的槽位与思考档位。
  Stream<SseChunk> streamPrompt({
    required String system,
    required String user,
    ApiEndpointConfig? endpoint,
    String? thinkingLevel,
    CancelToken? cancelToken,
  }) async* {
    final cfg = endpoint ?? config;
    if (!cfg.isConfigured) {
      throw Exception('请先在设置中配置 API Key');
    }
    final body = BaseApiService.buildChatBody(
      cfg: cfg,
      stream: true,
      temperature: 0.4,
      maxTokens: 8192, // 推荐清单/精读正文都可能较长(P2-18)
      thinkingLevel: thinkingLevel,
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    );
    final response = await postWithReasoningFallback(
      '/chat/completions',
      body,
      cfg: cfg,
      responseType: ResponseType.stream,
      cancelToken: cancelToken, // v1.9.0(P2-34):支持用户取消长生成
    );
    yield* _parseSseStream(_responseStream(response));
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

    final body = BaseApiService.buildChatBody(
      cfg: cfg,
      stream: true,
      temperature: 0.3,
      maxTokens: 4096,
      thinkingLevel: thinkingLevel,
      messages: [
        {'role': 'system', 'content': systemContent},
        // 历史对话(上下楼记忆)— 仅已完成消息,最近 20 条由调用方截断
        for (final h in history)
          {
            'role': h['role'],
            'content': h['content'],
          },
        {'role': 'user', 'content': lastUserContent},
      ],
    );

    try {
      final response = await postWithReasoningFallback(
        '/chat/completions', body, cfg: cfg,
        responseType: ResponseType.stream);
      yield* _parseSseStream(_responseStream(response));
    } catch (e) {
      // 带图但模型确实不支持图片 → 降级纯文本重试**一次**
      // (v1.9.0 P1-4:收紧判据,见 _imageRejected —— 旧实现把任何
      //  含 image 字样的 400 都当成"不支持图片",连"请求体过大"也重发)
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

  /// 判断错误是否"模型不支持图片"(纯函数,可单测)。
  ///
  /// v1.9.0 收紧(审查 P1-4):旧实现(1)把错误串里**任何** `image` 字样都算
  /// 命中——而"request body too large"这类 400 也常带 image 字样,于是会把
  /// 整份 base64 图片重发一次;(2)把**任何** 400/415/422 都算命中——参数错、
  /// 限频边缘也重发。现在只在"明确不支持图片"时降级:
  /// - 415/422(媒体类型/语义错误),或
  /// - 400 且错误体命中 image/vision/multimodal 相关措辞,**且不含**
  ///   too large / rate / length / context 这类与"不支持图片"无关的原因。
  static bool _imageRejected(Object e) {
    final body = _errorBodyText(e).toLowerCase();
    if (_looksLikeOversizeOrRate(body)) return false;

    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 415 || code == 422) return true;
      if (code == 400) return _looksLikeVisionRejection(body);
    }
    return _looksLikeVisionRejection(body);
  }

  /// 从错误对象里取出"服务端返回体"文本(不含 Dio 的堆栈/URL,避免误命中)
  static String _errorBodyText(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map) {
        final err = d['error'];
        if (err is Map) {
          return '${err['code'] ?? ''} ${err['message'] ?? ''} ${err['type'] ?? ''}';
        }
        return d['message']?.toString() ?? d.toString();
      }
      if (d is String) return d;
      return e.message ?? '';
    }
    return e.toString();
  }

  static bool _looksLikeVisionRejection(String body) {
    return body.contains('image') ||
        body.contains('vision') ||
        body.contains('multimodal') ||
        body.contains('picture');
  }

  static bool _looksLikeOversizeOrRate(String body) {
    return body.contains('too large') ||
        body.contains('too long') ||
        body.contains('exceed') ||
        body.contains('rate limit') ||
        body.contains('context length') ||
        body.contains('maximum context');
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
    // v1.9.0(P2-15/A14):统一用 extractJsonBlock —— 兼容 ```围栏(含同行围栏)、
    // 围栏外带解释文字("好的,识别结果如下:{…}")、前后空白。
    // 旧实现只在以 ``` 开头时剥壳且用 substring(start,end) 会带上开围栏,
    // 围栏后还有文字时直接解析失败。
    var jsonStr = extractJsonBlock(content);
    if (jsonStr.isEmpty) jsonStr = content.trim();

    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      // v1.9.0(P2-15):不把整段原文塞进异常 —— 它会一路显示到 UI 并写进
      // 会话快照(用户材料原文/提示词泄漏面);原文只进调试日志。
      debugPrint('ReadFlow parseResponse failed (${content.length} chars): '
          '${content.length > 400 ? '${content.substring(0, 400)}…' : content}');
      throw FormatException('无法解析 AI 返回的 JSON(共 ${content.length} 字)');
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
            'phonetic': e['phonetic']?.toString(),
            // v2.0:识别侧也可能直接给双音标(见上面 prompt)
            'phonetic_uk': e['phonetic_uk']?.toString(),
            'phonetic_us': e['phonetic_us']?.toString(),
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
            'phonetic': e['phonetic']?.toString(),
            // v2.0:识别侧也可能直接给双音标(见识别 prompt)
            'phonetic_uk': e['phonetic_uk']?.toString(),
            'phonetic_us': e['phonetic_us']?.toString(),
            'grammar_note': e['grammar_note']?.toString(),
          };
        })
        .where((m) => m['word']!.isNotEmpty)
        .toList();
  }

  /// 去掉整篇被 ``` 包裹的外壳(v1.8.0):学习内容按 Markdown 展示,
  /// 模型有时会把整篇塞进一个代码块里,这里剥掉。
  static String extractMarkdown(String text) {
    final t = text.trim();
    final m = RegExp(
      r'^```(?:markdown|md)?\s*\n([\s\S]*?)\n?```$',
    ).firstMatch(t);
    if (m != null) return (m.group(1) ?? '').trim();
    return t;
  }

  /// 从一段可能夹带说明文字的文本里取出 JSON 主体(纯函数,可单测)。
  /// 用途(v1.8.0):思考模型有时把最终 JSON 写在 reasoning_content 里
  /// (content 为空),此时应**从思考内容里取结果**,而不是把思考档位砍掉。
  /// 兼容 ```json 代码块;取第一个 '{' 到最后一个 '}'。
  static String extractJsonBlock(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
    if (fence != null) {
      final inner = (fence.group(1) ?? '').trim();
      if (inner.startsWith('{') || inner.startsWith('[')) return inner;
    }
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start >= 0 && end > start) return t.substring(start, end + 1);
    final arrStart = t.indexOf('[');
    final arrEnd = t.lastIndexOf(']');
    if (arrStart >= 0 && arrEnd > arrStart) {
      return t.substring(arrStart, arrEnd + 1);
    }
    return '';
  }

  /// 词条化截断清洗(数据层治本):模型可能把长句 word 截断成
  /// "开头~20字符+省略号"(省略号形态不固定:…/.../⋯/……/.. 等),
  /// original_sentence 字段才是完整句子。word 带截断特征且存在更长的
  /// 完整句时,用完整句替换 word 数据本身——显示/保存/编辑全走完整句子。
  /// 正常单词/短语不带省略号特征,不受影响(如 "compound with" 不匹配)。
  ///
  /// v1.9.0(P2-16):单词型(word)增加长度门槛 —— `etc...` 这类**合法带点
  /// 缩写**不该被替换成整句(否则词与释义错配:"etc..." 配"等等",词条却成了
  /// 一整句话)。短语/句子型保持原样:它们的省略号只可能来自截断。
  static String cleanTruncatedWord(
    String word,
    String wordType,
    String originalSentence,
  ) {
    if (originalSentence.isEmpty) return word;
    if (originalSentence.length <= word.length) return word;
    // 截断特征:尾部 2+ 个点(…/⋯/../.../…… 等任意形态)
    final truncRe = RegExp(r'([…⋯]{1,}|\.{2,})$');
    if (!truncRe.hasMatch(word)) return word;
    if (wordType == 'word') {
      final stripped = word.replaceAll(truncRe, '').trim();
      // 短碎片(≤4 字符,如 etc/eg/i.e)更可能是"本身就带点的词"而不是截断
      if (stripped.length < 5) return word;
    }
    return originalSentence;
  }

  // ── 模型列表（混合：先调API，失败则用内置清单兜底） ──

  /// 最近一次 fetchModels 的摘要(诊断信息展示用,v1.4.1):
  /// 用户"模型选择没读到模型"时,诊断页可直接看到拉取成功/失败的真实原因
  static String lastFetchNote = '尚未拉取';

  /// 最近一次 /models 拉取结果缓存(v1.4.3):
  /// 首页/底部栏/追问菜单优先展示真实模型列表,而非内置清单。
  static List<String>? lastModels;

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
      final respData = response.data;
      // 兼容多种返回结构:OpenAI 标准 {"data":[...]} / {"models":[...]} / 纯数组
      List<dynamic>? rawList;
      if (respData is Map) {
        final d = respData['data'];
        if (d is List) {
          rawList = d;
        } else if (respData['models'] is List) {
          rawList = respData['models'] as List;
        }
      } else if (respData is List) {
        rawList = respData;
      }
      if (rawList != null && rawList.isNotEmpty) {
        final ids = rawList
            .map((e) => e is Map ? e['id']?.toString() ?? '' : '')
            .where((id) => id.isNotEmpty)
            .toList();
        ids.sort();
        if (ids.isNotEmpty && allowPrefixes.isNotEmpty) {
          final filtered = ids
              .where((id) => allowPrefixes.any((p) => id.startsWith(p)))
              .toList();
          if (filtered.isNotEmpty) {
            lastFetchNote = '拉取成功 ${filtered.length} 个模型(已过滤)';
            lastModels = filtered;
            return filtered;
          }
        }
        if (ids.isNotEmpty && keepFilter != null) {
          final kept = ids.where(keepFilter).toList();
          if (kept.isNotEmpty) {
            lastFetchNote = '拉取成功 ${kept.length} 个模型(视觉过滤)';
            lastModels = kept;
            return kept;
          }
          lastFetchNote = '拉取成功但无视觉模型,回退内置清单';
          return List.of(fallback);
        }
        if (ids.isNotEmpty) {
          lastFetchNote = '拉取成功 ${ids.length} 个模型';
          lastModels = ids;
          return ids;
        }
      }
      // 拉取成功但结构/内容异常 → 记录响应便于排查
      // ("模型选择没读到模型"不再盲猜,v1.4.1)
      final respStr = respData.toString();
      lastFetchNote = '响应结构异常: '
          '${respStr.length > 200 ? respStr.substring(0, 200) : respStr}';
      debugPrint('ReadFlow fetchModels 响应结构异常: $lastFetchNote');
    } catch (e) {
      lastFetchNote = '拉取失败: ${BaseApiService.friendlyError(e)}';
      debugPrint('ReadFlow fetchModels 失败: $lastFetchNote');
    }
    return List.of(fallback);
  }
}
