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

  /// 副槽位:专项文本(文章生成/回译/建议),未配置则全部走主
  static const secondary = ApiEndpointConfig(
    hiveKey: AppConstants.keyDeepseekApiKey,
    hiveModel: AppConstants.keyDeepseekModel,
    hiveBaseUrl: AppConstants.keyDeepseekBaseUrl,
    hiveThinking: AppConstants.keyDeepseekThinking,
    defaultBaseUrl: AppConstants.deepseekBaseUrl,
    defaultModel: AppConstants.deepseekChatModel,
  );

  Box get _box => Hive.box(AppConstants.hiveBoxSettings);

  String? get apiKey {
    final v = _box.get(hiveKey);
    return (v is String && v.isNotEmpty) ? v : null;
  }

  String get baseUrl {
    final v = _box.get(hiveBaseUrl);
    return (v is String && v.isNotEmpty) ? v : defaultBaseUrl;
  }

  String get model {
    final v = _box.get(hiveModel);
    return (v is String && v.isNotEmpty) ? v : defaultModel;
  }

  String get thinking {
    final v = _box.get(hiveThinking);
    return (v is String &&
            (v == 'disabled' || v == 'low' || v == 'medium' || v == 'high'))
        ? v
        : 'disabled';
  }

  bool get isConfigured => apiKey != null;

  /// 思考参数。豆包/火山方舟原生字段是 thinking.budget_tokens
  /// (限制思考 token 数)——之前用 reasoning_effort 不被火山方舟识别,
  /// 思考无上限,中度思考一张图 3 分钟+(用户实测)。
  /// budget_tokens: low≈几秒 / medium≈20-40s / high≈1 分钟
  Map<String, dynamic> buildThinkingParams() {
    switch (thinking) {
      case 'disabled':
        return {'thinking': {'type': 'disabled'}};
      case 'low':
        return {'thinking': {'type': 'enabled', 'budget_tokens': 1024}};
      case 'medium':
        return {'thinking': {'type': 'enabled', 'budget_tokens': 2048}};
      case 'high':
        return {'thinking': {'type': 'enabled', 'budget_tokens': 4096}};
      default:
        return {'thinking': {'type': 'disabled'}};
    }
  }
}
