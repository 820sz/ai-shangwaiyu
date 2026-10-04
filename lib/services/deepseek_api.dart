import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_endpoint.dart';
import 'base_api.dart';
import 'database.dart';
import 'doubao_api.dart';

/// 一批翻译的结果(v2.10)。
///
/// [translations] 是**能安全用**的译文(与输入的前若干段一一对应);
/// [note] 非空表示"这批没全好"(被截断/少给),界面据此把那几段标成可重试,
/// 而不是整批丢掉让用户看到一片失败。
class TranslateOutcome {
  final List<String> translations;
  final String? note;

  const TranslateOutcome({required this.translations, this.note});

  bool get isEmpty => translations.isEmpty;
}

/// 专项文本 API 服务(副槽位):文章生成、回译练习、个性化建议。
///
/// 原 DeepSeek 服务。槽位策略:副槽位已配置 → 用副;未配置 → 全部走主槽位
/// (与用户约定:只填主 API 时所有操作都走主)。
class DeepseekApiService extends BaseApiService {
  @override
  ApiEndpointConfig get config =>
      ApiEndpointConfig.secondary.isConfigured
          ? ApiEndpointConfig.secondary
          : ApiEndpointConfig.primary;

  bool get isConfigured => config.isConfigured;

  // ═══════════════ 生成含生词的英语文章 ═══════════════

  /// 根据生词列表生成一篇英语短文
  Future<Map<String, dynamic>> generateArticle(
    List<Map<String, String>> vocabList,
  ) async {
    if (!config.isConfigured) {
      throw Exception('请先在设置中配置 API Key');
    }

    // 获取用户偏好记忆
    final memory = await DatabaseService.getAllMemory();
    final memoryContext = memory.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');

    // 构建生词列表文本
    final vocabText = vocabList
        .map((v) => '- ${v['word']} (${v['translation'] ?? ''})')
        .join('\n');

    const systemPrompt = '''你是一个专业的英语学习内容生成助手。根据用户正在学习的生词列表，生成一篇自然、有趣、难度适中的英语短文。

要求：
1. 文章必须包含所有给定的生词（至少包含大部分），用自然的方式融入文章
2. 文章长度 200-400 词
3. 难度控制在用户水平（根据记忆信息判断）
4. 题材以故事、科普、日常对话为宜，让读者有兴趣读下去
5. 返回 JSON: {"title": "...", "content": "...", "translation": "..."}
6. translation 为 content 的全文中文翻译，段落用空行分隔，与 content 段落一一对应
7. 只返回 JSON，不要有其他内容''';

    final userPrompt = '''
用户记忆信息：
$memoryContext

当前生词列表：
$vocabText

请生成一篇文章，把这些生词自然地融入进去。''';

    final response = await postWithReasoningFallback(
      '/v1/chat/completions',
      // v1.9.0(P0-3/P1-1):统一走 buildChatBody —— DS 官方省略 max_tokens
      // (它是 reasoning+content 总预算,写死会被思考吃光 → content 为空)
      // 与 temperature,方舟等端点显式给。此前这里硬编码 max_tokens,
      // 导致"思考一长就失败"的根因修复只落在识图侧、文章生成仍复发。
      BaseApiService.buildChatBody(
        cfg: config,
        temperature: 0.8,
        maxTokens: 4096,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      ),
      cfg: config,
    );

    // v1.9.0:正文为空时回退思考通道(思考模型常把结果写在 reasoning_content)
    final content = BaseApiService.extractContentWithReasoning(response.data);
    return _parseJsonResponse(content);
  }

  // ═══════════════ 材料检索:AI 规划 + 标题中文化 + 逐段翻译(v2.6)═══════════════

  /// **把用户的中文需求变成"能搜到东西"的检索方案**(v2.6,用户第 8 条)。
  ///
  /// 用户原话:"还建议我用英文搜?接的是 AI,能不能智能点 —— 用户提需求,AI 找不就行了"。
  /// 所以这里让 AI 干三件事:
  /// 1. 把中文需求翻成**公开源认的英文检索词**(Gutenberg / arXiv / NPR 这些只认英文);
  /// 2. 直接点名它**确实知道**的作品/论文(中英标题 + 作者 + 一句"为什么适合你");
  /// 3. 给可得的话给出**原文链接**。
  ///
  /// ⚠️ 链接纪律:`url` 只允许来自公开且稳定的地址(Gutenberg `/ebooks/<id>`、
  /// arXiv `/abs/<id>`、期刊/机构官网);**不确定就留空,绝不编造 id** ——
  /// 假链接比没有链接更糟。
  Future<Map<String, dynamic>> planMaterialSearch(
    String userQuery, {
    String? category,
    String? levelHint,
    String? prefsHint,
    String? bandHint,
  }) async {
    if (!config.isConfigured) {
      throw Exception('请先在设置中配置 API Key');
    }
    final categoryHint = (category != null && category.isNotEmpty)
        ? '用户想要的类别:$category。'
        : '';
    final level = (levelHint != null && levelHint.isNotEmpty)
        ? '用户的英语水平:$levelHint(选材时照顾难度)。'
        : '';
    // v2.7(用户第 4/5 条):个性化偏好(类型/题材/补充需求)与难度档要**真的**
    // 进提示词 —— 否则界面上的开关只是装饰,用户一眼就能看出来没生效。
    final prefs = (prefsHint != null && prefsHint.trim().isNotEmpty)
        ? '用户的找材料偏好:${prefsHint.trim()}。这些偏好优先于你的默认口味。'
        : '';
    final band = (bandHint != null && bandHint.trim().isNotEmpty)
        ? '${bandHint.trim()}。按这个难度挑:太难的不要推,太简单的也别凑数。'
        : '';
    const systemPrompt = '''你是英语学习材料的检索助手。用户会用**中文**描述想找什么,
你要把它变成"真的能搜到原文"的检索方案。返回 JSON:
{"queries":["英文检索词1","英文检索词2","英文检索词3"],
 "picks":[{"title_en":"英文原名","title_cn":"中文译名","author":"作者","why":"一句中文说明为什么适合他","url":"原文链接或空串"}],
 "note":"一句中文提示(可选)"}

规则:
1. queries 必须是**英文**关键词(公版书检索站/arXiv/外媒 RSS 都只认英文),
   3 条以内,越具体越好(如 "stoicism meditations aurelius" 而不是 "philosophy")。
2. picks 是**你确实知道**的公版书 / 公开论文 / 公开文章,最多 6 条;
   title_cn 要给通用中文译名(没有通用译名就意译,不要拼音)。
3. url **只允许**这些稳定地址:Gutenberg 书目页 `https://www.gutenberg.org/ebooks/<数字id>`,
   arXiv 摘要页 `https://arxiv.org/abs/<id>`,或期刊/大学/机构官网的公开页面。
   **不确定数字 id 就把 url 写成空串** —— 编一个不存在的 id 会让用户点开 404。
4. why 用中文,一句话,说清"为什么适合他"(题材/难度/篇幅),不要空话。
5. 只输出 JSON。''';
    final userPrompt = '我想找:$userQuery\n$categoryHint$level$prefs$band';
    final response = await postWithReasoningFallback(
      '/v1/chat/completions',
      BaseApiService.buildChatBody(
        cfg: config,
        temperature: 0.3,
        maxTokens: 2048,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      ),
      cfg: config,
    );
    final content = BaseApiService.extractContentWithReasoning(response.data);
    final parsed = _parseJsonResponse(content);
    return {
      'queries': (parsed['queries'] as List?)?.map((e) => '$e').toList() ??
          const <String>[],
      'picks': (parsed['picks'] as List?)
              ?.whereType<Map>()
              .map((e) => {
                    'title_en': '${e['title_en'] ?? ''}',
                    'title_cn': '${e['title_cn'] ?? ''}',
                    'author': '${e['author'] ?? ''}',
                    'why': '${e['why'] ?? ''}',
                    'url': '${e['url'] ?? ''}',
                  })
              .toList() ??
          const <Map<String, String>>[],
      'note': '${parsed['note'] ?? ''}',
    };
  }

  /// **把一批英文标题翻成「中文(英文)」**(v2.6,用户第 8(3) 条)。
  ///
  /// 用户原话:"材料中心你整全屏英文,谁看得懂?标题都要按照「中文(英文)」的格式"。
  /// 返回 {英文原标题: 中文译名};某条翻不出来就不出现在结果里(界面回落成纯英文)。
  Future<Map<String, String>> translateTitles(List<String> titles) async {
    if (titles.isEmpty || !config.isConfigured) return const {};
    const systemPrompt = '''你给英语学习材料的标题配中文译名。返回 JSON:{"items":[{"en":"原标题","cn":"中文译名"}]}
规则:中文用**通用译名**(书用常见中译本名,论文/文章意译);不确定就给直译,不要音译、不要留空;只输出 JSON。''';
    final response = await postWithReasoningFallback(
      '/v1/chat/completions',
      BaseApiService.buildChatBody(
        cfg: config,
        temperature: 0.2,
        maxTokens: 2048,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': titles.take(20).join('\n')},
        ],
      ),
      cfg: config,
    );
    final content = BaseApiService.extractContentWithReasoning(response.data);
    final parsed = _parseJsonResponse(content);
    final out = <String, String>{};
    for (final e in (parsed['items'] as List? ?? const [])) {
      if (e is! Map) continue;
      final en = '${e['en'] ?? ''}'.trim();
      final cn = '${e['cn'] ?? ''}'.trim();
      if (en.isNotEmpty && cn.isNotEmpty) out[en] = cn;
    }
    return out;
  }

  /// **逐段翻译**(v2.6,用户第 8(4) 条:材料阅读器的「翻译」)。
  ///
  /// 返回与输入等长的中文数组(段落一一对应);数量对不上就抛错,由调用方
  /// 决定是否退回整段直译 —— 宁可不显示,也不能把译文错位到别的段落上。
  Future<List<String>> translateParagraphs(List<String> paragraphs) async {
    final rich = await translateParagraphsRich(paragraphs);
    return rich.translations;
  }

  /// 逐段翻译(可取消、按需抢救版)。
  ///
  /// v2.10 修(用户 10/4 原话:"翻译的进度条是死的,而且点击取消后仍然在翻译取消不掉,
  /// 而且翻译功能几乎没法用"):
  /// 1. **[cancelToken] 真的中断网络请求** —— 旧实现只在"下一批开始前"看一眼标志位,
  ///    当前这批还在跑,用户点了取消界面依旧"正在翻译"(这就是"取消不掉");
  /// 2. **maxTokens 随输入长度自适应** —— 旧实现固定 4096,公版书那种长段很容易把
  ///    自己截断 → JSON 不完整 → 整批丢弃 → 用户看到的就是"0% 卡死 + 一直报错";
  /// 3. **段数对不上时抢救**(能对上前 k 段就先给前 k 段),而不是整批扔掉。
  Future<TranslateOutcome> translateParagraphsRich(
    List<String> paragraphs, {
    CancelToken? cancelToken,
  }) async {
    if (paragraphs.isEmpty || !config.isConfigured) {
      return const TranslateOutcome(translations: [], note: 'AI 未配置');
    }
    const systemPrompt = '''你是翻译助手。用户给一段英文(可能多段,用空行分隔),
请逐段翻译成**通顺的中文**。返回 JSON:{"translations":["第一段译文","第二段译文",...]}
规则:1. 段数必须与输入**完全一致**,顺序对应,不许合并或拆分;
2. 不要逐词硬译,不要保留英文语序;
3. 只输出 JSON。''';
    // 输出预算按输入长度给:英文 1 字符≈0.25 token,中文译文≈0.5 token,再留 600 余量
    final chars = paragraphs.fold<int>(0, (a, s) => a + s.length);
    final budget = (700 + chars * 2).clamp(1200, 8192);
    final response = await postWithReasoningFallback(
      '/v1/chat/completions',
      BaseApiService.buildChatBody(
        cfg: config,
        temperature: 0.3,
        maxTokens: budget,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': paragraphs.join('\n\n')},
        ],
      ),
      cfg: config,
      cancelToken: cancelToken,
    );
    final content = BaseApiService.extractContentWithReasoning(response.data);
    final parsed = _parseJsonResponse(content);
    final list = (parsed['translations'] as List? ?? const [])
        .map((e) => '$e')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (list.isEmpty) {
      return const TranslateOutcome(translations: [], note: 'AI 没返回译文(可能被截断)');
    }
    if (list.length != paragraphs.length) {
      // 抢救:AI 少给了就丢弃后面几段(那几段标失败可重试),绝不把译文错位
      final kept = list.length > paragraphs.length
          ? list.sublist(0, paragraphs.length)
          : list;
      return TranslateOutcome(
        translations: kept,
        note: '只翻好了前 ${kept.length}/${paragraphs.length} 段(可能被截断)',
      );
    }
    return TranslateOutcome(translations: list);
  }

  // ═══════════════ 生成回译练习 ═══════════════

  /// 根据文章内容生成中→英回译练习
  Future<List<Map<String, String>>> generateBackTranslationExercise(
      String articleContent) async {
    if (!config.isConfigured) {
      throw Exception('请先在设置中配置 API Key');
    }

    const systemPrompt = '''你是一个专业的英语教学助手。根据给定的英语文章，从中挑选5-8个关键句子，生成回译练习。

要求：
1. 从文章中挑选5-8个有学习价值的句子（不要太长，15-30词为宜）
2. 每个句子给出地道的中文翻译
3. 返回 JSON: {"sentences": [{"english": "...", "chinese": "..."}]}
4. 只返回 JSON，不要有其他内容''';

    final response = await postWithReasoningFallback(
      '/v1/chat/completions',
      BaseApiService.buildChatBody(
        cfg: config,
        temperature: 0.5,
        maxTokens: 4096,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': '请为以下文章生成回译练习句子：\n\n$articleContent'
          },
        ],
      ),
      cfg: config,
    );

    final content = BaseApiService.extractContentWithReasoning(response.data);
    final parsed = _parseJsonResponse(content);
    final sentences = parsed['sentences'] as List<dynamic>?;
    if (sentences == null) return [];

    return sentences
        .map((s) => {
              'english': s['english']?.toString() ?? '',
              'chinese': s['chinese']?.toString() ?? '',
            })
        .where((m) => m['english']!.isNotEmpty && m['chinese']!.isNotEmpty)
        .toList();
  }

  // ═══════════════ 通用 JSON 解析 ═══════════════

  /// 解析模型返回的 JSON(v1.9.0 加固):
  /// - 统一用 `extractJsonBlock` 抠 JSON(兼容 ```围栏/前置说明文字)
  /// - **绝不抛异常**:失败返回 `{}`,原文只进调试日志(旧实现抛
  ///   FormatException 且把整段原文拼进 message,一路显示到 UI)
  Map<String, dynamic> _parseJsonResponse(String content) {
    final jsonStr = DoubaoApiService.extractJsonBlock(content);
    if (jsonStr.isEmpty) {
      debugPrint('ReadFlow deepseek parse: 未找到 JSON(共 ${content.length} 字)');
      return const {};
    }
    try {
      final parsed = jsonDecode(jsonStr);
      if (parsed is! Map) return const {};
      return Map<String, dynamic>.from(parsed);
    } catch (e) {
      debugPrint('ReadFlow deepseek parse failed: $e');
      return const {};
    }
  }
}
