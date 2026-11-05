import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_endpoint.dart';
import 'base_api.dart';
import 'database.dart';
import 'doubao_api.dart';
import 'translation_policy.dart';

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
  /// 翻译实际使用的槽位:**副槽位已配置 → 副(DeepSeek);否则回落主槽位**。
  ///
  /// 抽成静态是让「控制条标注 / 诊断信息 / 真实请求」共用**同一份判定** ——
  /// 旧实现这三处各 if 一遍,曾经出过"界面显示用 A、实际请求用 B"的误导
  /// (阅读器的模型菜单改主槽位,但翻译走副槽位,用户以为换模型没生效)。
  static ApiEndpointConfig get activeConfig =>
      ApiEndpointConfig.secondary.isConfigured
          ? ApiEndpointConfig.secondary
          : ApiEndpointConfig.primary;

  /// 槽位中文名(界面/诊断标注用)
  static String get slotLabel =>
      ApiEndpointConfig.secondary.isConfigured ? '副槽位' : '主槽位';

  /// 一行摘要:「副槽位 · deepseek-flash」(拿不到模型名就写"当前模型")
  static String get targetSummary {
    final m = activeConfig.model.trim();
    return '$slotLabel · ${m.isEmpty ? '当前模型' : m}';
  }

  /// 翻译端点的 host(诊断用)。**只取 host,绝不含 key/路径/查询参数** ——
  /// 诊断页整屏会被用户截图外发。
  static String get baseHost {
    final raw = activeConfig.baseUrl.trim();
    if (raw.isEmpty) return '(默认端点)';
    final host = Uri.tryParse(raw)?.host ?? '';
    return host.isEmpty ? '(无法解析)' : host;
  }

  @override
  ApiEndpointConfig get config => activeConfig;

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
6. translation 为 content 的全文中文翻译，段落用空行分隔，与 content 段落一一对应；
   译文同样受下面的翻译纪律约束（它是给学习者对照阅读的，不能为了顺口损失信息）

${TranslationPolicy.discipline}

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
{"queries":["检索词1","检索词2",...],
 "picks":[{"title_en":"英文原名","title_cn":"中文译名","author":"作者","why":"一句中文说明为什么适合他","url":"原文链接或空串"}],
 "note":"一句中文提示(可选)"}

规则:
0. 这是**用户个人学习使用**(非商用),可以找教材、真题、教辅、书籍、论文等任何能找到
   原文的公开网页;不要因为版权顾虑而只给"公版书"或含糊推荐。目标是**找到用户想要的
   那一类东西**,不是找"看起来相关"的泛内容。
1. queries 最多 6 条,中英文混合、**具体到系列/书名/考试名**:
   - 用户说"教材" → 给具体教材系列:如 "新概念英语 第三册 课文原文",
     "New Concept English 3 pdf", "人教版高中英语 必修一 课文";
   - 用户说"真题/应试" → 给具体考试+年份/题型:如 "CET-4 历年真题 pdf",
     "四级真题 2024 阅读", "IELTS Cambridge 18 academic reading pdf";
   - 用户说"书" → 书名+作者(中英文各一条),公版书补 Gutenberg;
   - 用户说"论文" → topic + survey/review + arxiv;
   - 用户说"外刊/新闻" → 具体媒体+题材:NPR technology, The Economist ...;
   - 允许在 query 里带中文,官方搜索能搜中文网页;公开源(RSS/arXiv/Gutenberg)过滤时
     只取英文 query。
2. queries 要**能组合覆盖需求**:先给 2~3 条"精准系列/书名",再给 2~3 条"同义/长尾"。
   不要只给 "textbook"、"exam"、"english" 这种空泛词。
3. picks 是你确实知道的公版书/公开论文/公开文章,最多 6 条;不确定的 URL 留空。
4. why 用中文,一句话说清"为什么适合他"(题材/难度/篇幅),不要空话。
5. title_cn 是**翻译**,不是重新起名:书名/论文名用通用译名,学术术语不得改成
   口语化说法;遵守下面的翻译纪律:
${TranslationPolicy.discipline}
6. 只输出 JSON。''';
    final userPrompt = '我想找:$userQuery\n$categoryHint$level$prefs$band';
    final response = await postWithReasoningFallback(
      '/v1/chat/completions',
      BaseApiService.buildChatBody(
        cfg: config,
        temperature: 0.3,
        maxTokens: 2048,
        // 批 8 · P2-3:检索计划输出短、结构固定 → JSON mode + 轻思考
        // (low 对 3 条 query 足够,重思考只会让"找材料"多等几秒)
        jsonMode: true,
        thinkingLevel: BaseApiService.thinkingForTask('plan'),
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      ),
      cfg: config,
      jsonMode: true,
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
规则:中文用**通用译名**(书用常见中译本名,论文/文章意译);不确定就给直译,不要音译、不要留空。
标题也是翻译,同样按下面的纪律来(尤其是学术标题里的术语与限定):

${TranslationPolicy.discipline}

只输出 JSON。''';
    final response = await postWithReasoningFallback(
      '/v1/chat/completions',
      BaseApiService.buildChatBody(
        cfg: config,
        temperature: 0.2,
        maxTokens: 2048,
        // 批 8 · P2-3:标题译名是"固定 {"items":[...]}"结构 → JSON mode
        jsonMode: true,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': titles.take(20).join('\n')},
        ],
      ),
      cfg: config,
      jsonMode: true,
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
  ///
  /// v2.13.1(用户 2026-11-01:"翻译永远没法用、进度永远是死的"):
  /// - 调用方(阅读器)改成**一次只发一个真段落**(≤600 字符,见 reader_units.dart),
  ///   不再把 2500 词的整块当"1 段"发 —— 这是"段数对不上/只翻第一段"的根;
  /// - 新增 [receiveTimeout](默认 45s):非流式请求的首字节=整段算完才发,
  ///   旧默认 180s 会让用户对着一句没反应干等 3 分钟;单段超时就标该段失败可重试;
  /// - 解析/段数校验抽成可单测的纯函数 [parseTranslationOutcome]。
  Future<TranslateOutcome> translateParagraphsRich(
    List<String> paragraphs, {
    CancelToken? cancelToken,
    Duration receiveTimeout = const Duration(seconds: 45),
  }) async {
    if (paragraphs.isEmpty || !config.isConfigured) {
      return const TranslateOutcome(translations: [], note: 'AI 未配置');
    }
    // v2.12.2(用户 2026-10-20):旧提示词第一句就是"请逐段翻译成**通顺的中文**",
    // 模型于是把"通顺"当最高目标 —— 学术段落里的限定、否定、术语常被抹平。
    // 现在把翻译纪律整段插进来,并明确它优先于"通顺/地道";段数与 JSON 结构
    // 一个字都没动(调用方按固定结构解析)。
    const systemPrompt = '''你是严谨的翻译助手。用户给一段英文(可能多段,用空行分隔),
请逐段翻译成中文。返回 JSON:{"translations":["第一段译文","第二段译文",...]}

${TranslationPolicy.discipline}

本任务的附加规则:
1. 段数必须与输入**完全一致**,顺序对应,不许合并或拆分;
2. 不要逐词硬译,也不要为顺口保留英文语序;语序调整只服务于把原意说清楚;
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
      // 单段翻译(≤600 字符)不该等 180s:超时立刻让调用方把这一段标成
      // "没翻出来 · 可重试",而不是让整条进度条僵在那里。
      receiveTimeout: receiveTimeout,
    );
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : const <String, dynamic>{};
    final content = BaseApiService.extractContentWithReasoning(data);
    return parseTranslationOutcome(
      content,
      paragraphs.length,
      finishReason: finishReasonOf(data),
    );
  }

  /// 从 chat/completions 响应里取 `finish_reason`(纯函数,可单测)。
  ///
  /// `finish_reason == 'length'` = 模型**被输出上限截断**。旧实现完全不看它:
  /// 用户只看到"少了一段/只有第一段",却不知道是截断 —— 诊断信息与段下提示
  /// 都必须把这件事说出来(可重试 / 可缩小分段)。
  static String? finishReasonOf(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final reason = first['finish_reason'];
        if (reason != null) return '$reason';
      }
    }
    return null;
  }

  /// 解析翻译返回并做**段数对账**(纯函数,可单测)。
  ///
  /// 规则(与 v2.10 的抢救逻辑一致,只是抽出来可测):
  /// - 解析失败/没有译文 → `note: 'AI 没返回译文(可能被截断)'`;
  /// - 段数 > 期望:多出来的丢掉(绝不把译文错位到别的段落上),给 note;
  /// - 段数 < 期望:保留能对上的前 k 段,给 note(界面必须显示它,不能静默
  ///   取 `.first` —— 旧实现就是这样让用户以为"只有第一段翻了");
  /// - [finishReason] == `'length'`:note 明确写「输出被截断」(而不是含糊的
  ///   "可能被截断"),让用户知道重试/缩小分段才有用;
  /// - 完全匹配 → 无 note。
  static TranslateOutcome parseTranslationOutcome(
    String content,
    int expectedCount, {
    String? finishReason,
  }) {
    final truncated = finishReason == 'length';
    final jsonStr = DoubaoApiService.extractJsonBlock(content);
    final parsed = <String, dynamic>{};
    if (jsonStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map) parsed.addAll(Map<String, dynamic>.from(decoded));
      } catch (_) {
        // JSON 坏(被截断/夹带说明):按"没译文"处理,note 会提示可能被截断
      }
    }
    final list = (parsed['translations'] as List? ?? const [])
        .map((e) => '$e')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (list.isEmpty) {
      return TranslateOutcome(
        translations: const [],
        note: truncated
            ? '输出被截断(达到模型输出上限),没有可用的译文'
            : 'AI 没返回译文(可能被截断)',
      );
    }
    if (expectedCount > 0 && list.length != expectedCount) {
      final kept = list.length > expectedCount
          ? list.sublist(0, expectedCount)
          : list;
      final base = '只翻好了前 ${kept.length}/$expectedCount 段';
      return TranslateOutcome(
        translations: kept,
        note: truncated
            ? '$base(输出被截断:达到模型输出上限,可重试或分段再翻)'
            : '$base(可能被截断)',
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
2. 每个句子给出**准确、可对照**的中文翻译 —— 它是判分参照,不是随手写的参考译文;
   译文按下面的翻译纪律来（术语、限定、否定、时态都不能为了顺口而丢）

${TranslationPolicy.discipline}

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

  // ═══════════════ 通用 JSON 补全(批 8:找材料补救的统一入口)═══════════════

  /// 一次"只返回 JSON"的非流式补全。
  ///
  /// 为什么单独抽一个公开入口:批 8 的工具调用补救(找材料换关键词)需要和
  /// 出题/评分同一套能力 —— 端点/路径判定、JSON mode、任务级思考档、参数不
  /// 兼容时的自动降级。这些逻辑原本只埋在 output_composer 的私有方法里;
  /// 抽到服务上后,后续其它 JSON 链路(材料卡/结构抽取)可直接复用,
  /// 不会再出现"同一类重试逻辑抄两遍、只修一处"的老问题。
  ///
  /// 返回模型正文(可能带围栏/说明,由调用方的容错解析器处理);
  /// 未配置/失败返回 null(调用方自行降级,不抛)。
  Future<String?> completeJson({
    required String system,
    required String user,
    int maxTokens = 2048,
    double temperature = 0.3,
    String? thinkingLevel,
    bool jsonMode = true,
    Duration receiveTimeout = const Duration(seconds: 90),
  }) async {
    if (!config.isConfigured) return null;
    final cfg = config;
    final path = cfg.isDeepSeekOfficial
        ? '/v1/chat/completions'
        : '/chat/completions';
    try {
      final response = await postWithReasoningFallback(
        path,
        BaseApiService.buildChatBody(
          cfg: cfg,
          temperature: temperature,
          maxTokens: maxTokens,
          jsonMode: jsonMode,
          thinkingLevel: thinkingLevel,
          messages: [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
        ),
        cfg: cfg,
        jsonMode: jsonMode,
        receiveTimeout: receiveTimeout,
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      return BaseApiService.extractContentWithReasoning(data);
    } catch (e) {
      debugPrint('ReadFlow JSON 补全失败: $e');
      return null;
    }
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
