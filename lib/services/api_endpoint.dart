import 'package:hive_flutter/hive_flutter.dart';
import '../config/constants.dart';

/// API 槽位配置(主=多模态 / 副=专项文本)。
///
/// 主槽位复用原豆包 Hive key,副槽位复用原 DeepSeek Hive key ——
/// 老用户已填的配置无需迁移,自动成为主/副。
class ApiEndpointConfig {
  final String hiveKey;
  final String hiveModel;
  final String hiveBaseUrl;
  final String hiveThinking;
  final String defaultBaseUrl;
  final String defaultModel;

  /// 槽位模型是否支持 reasoning_effort 的 minimal 分档。
  /// 豆包/Ark 支持 minimal;DeepSeek 只认 low/medium/high——
  /// 发错枚举直接 400,且流式路径的降级逻辑读不到错误体(F6),
  /// 所以必须在这里发对,不能指望降级兜底。
  /// 2026-08-21:主槽位可能被用户配成 DeepSeek 视觉模型
  /// (deepseek-v4-flash-vision-exp),按当前模型名推断,不再写死豆包。
  bool get supportsMinimalEffort => !model.toLowerCase().contains('deepseek');

  const ApiEndpointConfig({
    required this.hiveKey,
    required this.hiveModel,
    required this.hiveBaseUrl,
    required this.hiveThinking,
    required this.defaultBaseUrl,
    required this.defaultModel,
  });

  /// 主槽位:多模态(识图/全文翻译/素材推荐/追问默认)
  static const primary = ApiEndpointConfig(
    hiveKey: AppConstants.keyDoubaoApiKey,
    hiveModel: AppConstants.keyDoubaoModel,
    hiveBaseUrl: AppConstants.keyDoubaoBaseUrl,
    hiveThinking: AppConstants.keyDoubaoThinking,
    defaultBaseUrl: AppConstants.doubaoBaseUrl,
    defaultModel: AppConstants.doubaoVisionModel,
  );

  /// 副槽位:专项文本(文章生成/回译/建议),未配置则全部走主。
  /// DeepSeek 只认 low/medium/high,不认 minimal。
  static const secondary = ApiEndpointConfig(
    hiveKey: AppConstants.keyDeepseekApiKey,
    hiveModel: AppConstants.keyDeepseekModel,
    hiveBaseUrl: AppConstants.keyDeepseekBaseUrl,
    hiveThinking: AppConstants.keyDeepseekThinking,
    defaultBaseUrl: AppConstants.deepseekBaseUrl,
    defaultModel: AppConstants.deepseekChatModel,
  );

  Box get _box => Hive.box(AppConstants.hiveBoxSettings);

  /// 清洗用户粘贴的 Base URL(纯函数,可单测)— v1.3.2:
  /// 真机粘贴常带 全角冒号(:)/空格/换行/BOM → Dio 抛
  /// "Illegal scheme character (at character 5)"(用户实测截图实锤)。
  /// 规则:去 BOM/首尾空白/全部内部空白/全角冒号与斜杠 → 半角。
  static String cleanBaseUrl(String raw) {
    var s = raw.replaceAll('\uFEFF', '');
    s = s.replaceAll('\uFF1A', ':'); // 全角冒号
    s = s.replaceAll('\uFF0F', '/'); // 全角斜杠
    s = s.replaceAll(RegExp(r'\s+'), ''); // 所有空白(含空格/换行/制表)
    return s.trim();
  }

  /// 清洗后的 URL 是否可作请求端点,并归一协议(v1.4.1):
  /// 云端 API 全站强制 https——用户存的 http://api.deepseek.com 会被
  /// CloudFront 301/302 重定向,Dio 跨协议跳转抛 bad response
  /// (用户真机截图:302 Redirection 实锤)。http:// → https:// 直接归一。
  static String? normalizedBaseUrl(String raw) {
    var cleaned = cleanBaseUrl(raw);
    if (cleaned.isEmpty) return null;
    final lower = cleaned.toLowerCase();
    if (lower.startsWith('http://')) {
      cleaned = 'https://${cleaned.substring('http://'.length)}';
    }
    if (!(cleaned.toLowerCase().startsWith('http://') ||
        cleaned.toLowerCase().startsWith('https://'))) {
      return null;
    }
    return cleaned;
  }

  String? get apiKey {
    final v = _box.get(hiveKey);
    return (v is String && v.isNotEmpty) ? v : null;
  }

  String get baseUrl {
    final v = _box.get(hiveBaseUrl);
    if (v is String && v.isNotEmpty) {
      // 清洗后合法 → 用;非法(残留全角/坏链接)回默认,绝不让 Dio 解析崩
      return normalizedBaseUrl(v) ?? defaultBaseUrl;
    }
    // 未填 URL → 按 Key 前缀自动配对端点(v1.4.0,用户实测"方舟 key + DS 模型"错配):
    // sk- = DeepSeek 官方(api.deepseek.com,deepseek-v4-flash-vision-exp 只在这家);
    // ark-/其他 = 槽位默认(主=方舟,副=DeepSeek 官方)
    final key = apiKey ?? '';
    if (key.toLowerCase().startsWith('sk-')) {
      return AppConstants.deepseekBaseUrl;
    }
    return defaultBaseUrl;
  }

  String get model {
    final v = _box.get(hiveModel);
    return (v is String && v.isNotEmpty) ? v : defaultModel;
  }

  String get thinking {
    final v = _box.get(hiveThinking);
    if (v == 'medium' || v == 'high') {
      // 2026-08-08 砍掉中/高档,存量设置自动迁移到低。
      // 必须写回 Hive:否则设置页/状态条读原始值显示"不思考",
      // 实际请求却带着 thinking:enabled(F4)——UI 与行为打架。
      _box.put(hiveThinking, 'low');
      return 'low';
    }
    if (v == 'minimal') {
      _box.put(hiveThinking, 'disabled'); // 更早版本的 minimal 档已并入不思考
      return 'disabled';
    }
    return (v == 'low' || v == 'disabled') ? v : 'disabled';
  }

  bool get isConfigured => apiKey != null;

  /// 思考参数。
  /// 2026-08-07 实测(doubao-seed-2-0-lite-260428,同图同 prompt 6 组对照):
  /// - thinking.budget_tokens 完全无效:512/1024/2048 耗时 27-37s,
  ///   reasoning 长度不随预算走(334/615/494),服务端按默认深度思考
  /// - 不传 thinking 最糟:默认开启深度思考,61.8s
  /// - 正确参数 reasoning_effort(官方分档 minimal/low/medium/high):
  ///   disabled≈3.7s / minimal≈3s / low≈14s / medium≈25s(复杂图)
  /// 2026-08-08 用户决策:识图只留 不思考/低度 两档(中/高砍掉)。
  /// 低→reasoning_effort=minimal(≈3s)。存量 medium/high 由 [thinking] getter 迁移到 low。
  /// 副槽位(DeepSeek)若不认 reasoning_effort,postWithReasoningFallback
  /// 会自动移除它降级重试(保留 thinking: enabled),不会报错。
  Map<String, dynamic> buildThinkingParams() {
    return buildThinkingParamsFor(thinking);
  }

  /// 按指定档位构建思考参数(纯函数,供追问等独立档位场景复用)。
  /// [level]: disabled / low / medium / high
  /// - disabled → thinking.type=disabled,完全跳过推理
  /// - low → 豆包系发 minimal(≈3s);DeepSeek 系发 low(不认 minimal,F6)
  /// - medium/high → 两族都认(豆包 minimal/low/medium/high;DS low/medium/high)
  Map<String, dynamic> buildThinkingParamsFor(String level) {
    switch (level) {
      case 'low':
        return {
          'thinking': {'type': 'enabled'},
          'reasoning_effort': supportsMinimalEffort ? 'minimal' : 'low',
        };
      case 'medium':
        return {
          'thinking': {'type': 'enabled'},
          'reasoning_effort': 'medium',
        };
      case 'high':
        return {
          'thinking': {'type': 'enabled'},
          'reasoning_effort': 'high',
        };
      case 'disabled':
      default:
        return {'thinking': {'type': 'disabled'}};
    }
  }
}
