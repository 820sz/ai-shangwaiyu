import 'dart:convert';
import 'api_endpoint.dart';
import 'base_api.dart';
import 'database.dart';

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
      {
        'model': config.model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.8,
        'max_tokens': 4096,
        ...config.buildThinkingParams(),
      },
      cfg: config,
    );

    final content = BaseApiService.extractContent(response.data);
    return _parseJsonResponse(content);
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
      {
        'model': config.model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': '请为以下文章生成回译练习句子：\n\n$articleContent'
          },
        ],
        'temperature': 0.5,
        'max_tokens': 4096,
        ...config.buildThinkingParams(),
      },
      cfg: config,
    );

    final content = BaseApiService.extractContent(response.data);
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

  // ═══════════════ 个性化学习建议 ═══════════════

  /// 基于学习数据给出个性化建议
  Future<String> getPersonalizedAdvice({
    required int totalVocab,
    required int masteredVocab,
    required int streakDays,
    required Map<String, int> vocabByBook,
    required Map<String, String> memory,
  }) async {
    if (!config.isConfigured) {
      throw Exception('请先在设置中配置 API Key');
    }

    final memoryContext = memory.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
    final bookStats = vocabByBook.entries
        .map((e) => '  《${e.key}》: ${e.value}词')
        .join('\n');

    const systemPrompt = '''你是一个专业的英语学习导师。根据用户的学习数据，给出个性化建议。

建议方向包括但不限于：
- 学习节奏是否合理
- 推荐下一本阅读材料（i+1 原则）
- 当前薄弱环节
- 具体的学习方法论改进

保持鼓励的语气，建议要具体可行。200字以内。''';

    final response = await postWithReasoningFallback(
      '/v1/chat/completions',
      {
        'model': config.model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': '''
用户学习数据：
- 总词汇量：$totalVocab
- 已掌握：$masteredVocab
- 连续学习天数：$streakDays
- 按书籍分布：
$bookStats

用户记忆表格：
$memoryContext

请给出个性化学习建议。'''
          },
        ],
        'temperature': 0.7,
        'max_tokens': 1024,
        ...config.buildThinkingParams(),
      },
      cfg: config,
    );

    return BaseApiService.extractContent(response.data);
  }

  // ═══════════════ 通用 JSON 解析 ═══════════════

  Map<String, dynamic> _parseJsonResponse(String content) {
    String jsonStr = content.trim();
    if (jsonStr.startsWith('```')) {
      final start = jsonStr.indexOf('\n');
      final end = jsonStr.lastIndexOf('```');
      if (start != -1 && end != -1) {
        jsonStr = jsonStr.substring(start, end).trim();
      }
    }
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }
}
