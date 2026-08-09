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
    if (v == 'medium' || v == 'high') {
      return 'low'; // 2026-08-08 砍掉中/高档,存量设置自动迁移到低
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
    switch (thinking) {
      case 'disabled':
        return {'thinking': {'type': 'disabled'}};
      case 'low':
        return {'thinking': {'type': 'enabled'}, 'reasoning_effort': 'minimal'};
      default:
        return {'thinking': {'type': 'disabled'}};
    }
  }
}
