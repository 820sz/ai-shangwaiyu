/// API 端点与全局常量
class AppConstants {
  AppConstants._();

  // ── API 端点 ──
  /// 豆包（火山方舟）视觉模型
  static const String doubaoBaseUrl =
      'https://ark.cn-beijing.volces.com/api/v3';
  static const String doubaoVisionModel = 'doubao-seed-2-1-turbo-260628';

  /// DeepSeek 文本模型(2026-07-24 起 deepseek-chat/reasoner 已停用,仅剩 v4 系列)
  static const String deepseekBaseUrl = 'https://api.deepseek.com';
  static const String deepseekChatModel = 'deepseek-v4-flash';
  /// DeepSeek 多模态(视觉)模型 — 2026-08-21 官方上线,OpenAI 兼容 /chat/completions
  static const String deepseekVisionModel = 'deepseek-v4-flash-vision-exp';

  /// 副槽位(专项文本)内置模型清单 — 拉取 /models 失败时的兜底
  static const List<String> deepseekFallbackModels = [
    'deepseek-v4-flash', // 快速通用,默认
    'deepseek-v4-pro',   // 高能力,思考模式
  ];

  /// 主槽位(多模态)内置模型清单 — 拉取 /models 失败时的兜底。
  /// 2026-08-21:主槽位不再绑死豆包——加入 DeepSeek 视觉模型(用户可配 DS key 走识图)。
  static const List<String> primaryFallbackModels = [
    'doubao-seed-2-0-mini-260715',   // 最快：速度和成本优先
    'doubao-seed-1-6-flash-250615',  // 闪推：上一代极速
    'doubao-seed-2-1-turbo-260628',  // 新 turbo
    'doubao-seed-2-0-lite-260428',   // 当前默认
    'doubao-seed-2-1-pro-260628',
    'doubao-seed-2-0-pro-260215',
    'doubao-seed-1-6-vision-250815',
    'doubao-seed-1-6-250615',
    'doubao-seed-evolving',
    'deepseek-v4-flash-vision-exp',  // DeepSeek 视觉(2026-08-21 上线)
  ];

  // ── 本地存储 Key ──
  static const String hiveBoxSettings = 'settings';
  static const String keyDoubaoApiKey = 'doubao_api_key';
  static const String keyDoubaoModel = 'doubao_model';
  static const String keyDoubaoBaseUrl = 'doubao_base_url';
  static const String keyDoubaoThinking = 'doubao_thinking';
  static const String keyDeepseekApiKey = 'deepseek_api_key';
  static const String keyDeepseekModel = 'deepseek_model';
  static const String keyDeepseekBaseUrl = 'deepseek_base_url';
  /// 副槽位(专项文本)思考模式,默认 disabled
  static const String keyDeepseekThinking = 'deepseek_thinking';
  /// 追问对话使用的槽位:primary=多模态 / secondary=专项文本
  static const String keyFollowUpSlot = 'follow_up_slot';
  /// 追问对话的思考档位(独立于识图档位)— v1.3.0 起追问恢复 4 档:
  /// 识图(槽位 thinking)只留 2 档是 2026-08-08 用户对应识别延迟的决策,
  /// 追问抽屉不该连坐,v1.3.0 拆分独立存储。
  static const String keyFollowUpThinking = 'follow_up_thinking';
  /// 追问思考档位(4 档,跨模型族通用文案;识图仍用 [thinkingOptions] 2 档)
  static const Map<String, String> followUpThinkingOptions = {
    'disabled': '不思考',
    'low': '低',
    'medium': '中',
    'high': '高',
  };
  /// 暂存的识图会话列表(SavedSession.toJson 的 List)
  static const String keySavedSessions = 'saved_sessions';
  /// 最多保留的暂存会话数
  static const int maxSavedSessions = 5;

  // ── 思考模式 ──
  // (2026-08-08 用户决策:识图只留 不思考/低度 两档——中/高思考调了多轮仍慢,
  //   存量 medium/high 设置自动迁移到 low)
  // disabled → thinking: {type: disabled},完全跳过推理
  // low → thinking: {type: enabled} + reasoning_effort: minimal
  //   (2026-08-07 实测 doubao-seed-2-0-lite-260428:minimal≈3s 复杂图;
  //    budget_tokens 对豆包完全无效)
  // 文案带预估耗时——思考模式实测速度差异大,选择时心里有数
  static const Map<String, String> thinkingOptions = {
    'disabled': '不思考',
    'low': '低·约3s',
  };

  /// DeepSeek 系思考档位(v1.4.4 修正):
  /// DS 官方 reasoning_effort 只有 **low / high / max**(无 medium!
  /// 官方 llm-deepseek 源码 serialize.ts 明确校验:非 low/high/max 直接报错)。
  /// 参考:https://api-docs.deepseek.com/zh-cn/guides/thinking_mode/
  static const Map<String, String> deepseekThinkingOptions = {
    'disabled': '不思考',
    'low': '低',
    'high': '高',
    'max': '极致',
  };

  /// 按模型族取思考档位表:
  /// DeepSeek 系 4 档(官方 low/high/max);豆包/其他维持 2 档。
  static Map<String, String> thinkingOptionsFor(String model) {
    return model.toLowerCase().contains('deepseek')
        ? deepseekThinkingOptions
        : thinkingOptions;
  }

  /// 追问思考档位(按模型族):
  /// DS 与识图同源(disabled/low/high/max,官方无 medium);
  /// 豆包系保留 disabled/low/medium/high 4 档。
  /// v1.7.0 修复:此前追问与设置页共用一张含 medium 的表,
  /// DS 下选「极致」/「高」会被校验打回 disabled(用户实测"点了变不思考")。
  static Map<String, String> followUpThinkingOptionsFor(String model) {
    return model.toLowerCase().contains('deepseek')
        ? deepseekThinkingOptions
        : followUpThinkingOptions;
  }

  // ── 数据库 ──
  static const String dbName = 'readflow.db';
  static const int dbVersion = 11;

  // ── 收藏夹 ──
  /// 收藏来源:追问答案 / 词汇卡片
  static const String bookmarkSourceFollowUp = 'follow_up';
  static const String bookmarkSourceVocab = 'vocab';

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

  /// 朗读音色(v2.0):'system' | 'uk' | 'us',默认跟随系统。
  /// 存的是**语义档位**而不是 BCP-47 语言码:'system' 要按手机当前语区解析
  /// (解析不了才回退 en-US),存语言码就把这层信息丢了。
  static const String keyTtsAccent = 'tts_accent';

  /// 音色档位 → 设置页文案(顺序即展示顺序:默认项在第一个)
  static const Map<String, String> ttsAccentOptions = {
    'system': '跟随系统',
    'uk': '英式发音',
    'us': '美式发音',
  };

  /// 深浅色(v2.2):'system' | 'light' | 'dark',默认跟随系统。
  /// 存语义档位而不是 `Brightness`:'跟随系统' 是用户意图,
  /// 存成当时的亮/暗就把这层意图丢了(系统夜间切换后 App 不会跟着变)。
  static const String keyThemeMode = 'theme_mode';

  static const Map<String, String> themeModeOptions = {
    'system': '跟随系统',
    'light': '浅色',
    'dark': '深色',
  };

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

  // ── 自动更新(GitHub Release)──
  /// GitHub 用户名,为空则跳过更新检查
  static const String githubOwner = '820sz';
  static const String githubRepo = 'ai-shangwaiyu';
}
