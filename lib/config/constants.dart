/// API 端点与全局常量
class AppConstants {
  AppConstants._();

  // ── API 端点 ──
  /// 豆包（火山方舟）视觉模型
  static const String doubaoBaseUrl =
      'https://ark.cn-beijing.volces.com/api/v3';
  static const String doubaoVisionModel = 'doubao-seed-2-1-turbo-260628';

  /// DeepSeek 文本模型
  static const String deepseekBaseUrl = 'https://api.deepseek.com';
  static const String deepseekChatModel = 'deepseek-chat';

  // ── 本地存储 Key ──
  static const String hiveBoxSettings = 'settings';
  static const String keyDoubaoApiKey = 'doubao_api_key';
  static const String keyDoubaoModel = 'doubao_model';
  static const String keyDoubaoBaseUrl = 'doubao_base_url';
  static const String keyDoubaoThinking = 'doubao_thinking';
  static const String keyDeepseekApiKey = 'deepseek_api_key';
  static const String keyDeepseekModel = 'deepseek_model';
  static const String keyDeepseekBaseUrl = 'deepseek_base_url';

  // ── 思考模式 ──
  // disabled → thinking: {type: disabled}，完全跳过推理
  // low/medium/high → thinking: {type: enabled} + reasoning_effort
  static const Map<String, String> thinkingOptions = {
    'disabled': '不思考',
    'low': '低度思考',
    'medium': '中度思考',
    'high': '深度思考',
  };

  // ── 数据库 ──
  static const String dbName = 'readflow.db';
  static const int dbVersion = 3;

  // ── 分类系统 ──
  static const List<String> learningCategories = [
    '教材',
    '书籍',
    '外刊',
    '碎片文章',
    '其他',
  ];
  static const String dbCategoryDefault = '其他';

  // ── Hive 额外 Key ──
  static const String keyMaterialSearchHistory = 'material_search_history';

  // ── 生词类型 ──
  static const String wordTypeWord = 'word';
  static const String wordTypePhrase = 'phrase';
  static const String wordTypeSentence = 'sentence';

  // ── 掌握度 ──
  static const int masteryNew = 0;
  static const int masteryLearning = 1;
  static const int masteryMastered = 2;

  // ── 练习类型 ──
  static const String exerciseBackTranslation = 'back_translation';

  // ── 分析模式 ──
  static const String analysisModeMarked = 'marked';
  static const String analysisModeFullText = 'fullText';
}
