import 'deepseek_api.dart';

/// 一条翻译失败记录(进程内缓存,不落库)。
class TranslationFailure {
  /// 发生时间(诊断页显示到秒,够定位"哪次翻译炸的")
  final DateTime at;

  /// 人话化的失败原因(由 `BaseApiService.friendlyError` / 段下提示产出,
  /// 已脱敏 —— 见 [TranslationDiagnostics.recordFailure])
  final String reason;

  const TranslationFailure({required this.at, required this.reason});

  /// 诊断页一行:`14:03:22 网络超时：请检查网络后重试`
  String get line => '${_hhmmss(at)} $reason';

  static String _hhmmss(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// 翻译链路的**进程内**诊断缓存(v2.16.0,阅读器翻译根治配套)。
///
/// 为什么只在内存(不落库):
/// - 失败原因是一次性排障信息,**不需要跨重启**;落库还要单独设计清理与隐私;
/// - 错误文本可能夹带服务端返回片段,写盘/外发前必须脱敏 —— 内存缓存只在
///   「我的 → 诊断信息」展示,**展示前统一脱敏**(key 只保留"是哪一家")。
///
/// 槽位 / 端点信息从 [DeepseekApiService] 的静态判定读取,保证与**真实请求**
/// 同源(项目里出过"界面显示一套、请求走另一套"的事故);且只给 host,
/// **绝不包含 API Key / 路径 / 查询参数** —— 诊断页会被用户整屏截图外发。
class TranslationDiagnostics {
  TranslationDiagnostics._();

  /// 诊断页最多展示几条失败(最近 N 条)
  static const int maxFailures = 3;

  static final List<TranslationFailure> _failures = <TranslationFailure>[];

  /// 记录一次翻译失败(阅读器每段失败时调用)。
  ///
  /// [reason] 会先脱敏:`sk-*` / `ark-*` / `Bearer *` 一律替换成 `***`
  /// (与 crash_logger.redact 同一套规则 —— 诊断信息可能被截图外发)。
  static void recordFailure(String reason, {DateTime? now}) {
    final raw = reason.trim();
    if (raw.isEmpty) return;
    _failures.add(TranslationFailure(at: now ?? DateTime.now(), reason: _redact(raw)));
    while (_failures.length > maxFailures) {
      _failures.removeAt(0);
    }
  }

  /// 最近失败(旧→新,最多 [maxFailures] 条;只读视图)
  static List<TranslationFailure> get failures => List.unmodifiable(_failures);

  /// 诊断页用文案:最近 3 条失败(时间 + 中文原因);没有则给一行"(无)"
  static List<String> failureLines() {
    if (_failures.isEmpty) return const ['(本次运行没有翻译失败)'];
    return [for (final f in _failures) '· ${f.line}'];
  }

  /// 翻译实际使用的槽位 · 模型(如 `副槽位 · deepseek-flash`)
  static String get targetSummary => DeepseekApiService.targetSummary;

  /// 翻译端点 host(如 `api.deepseek.com`;不含 key)
  static String get baseHost => DeepseekApiService.baseHost;

  /// 清空(诊断页"清空日志"顺带调用,或测试用)
  static void clear() => _failures.clear();

  /// 与 crash_logger.redact 同一套脱敏规则(这里不依赖 dart:io,纯字符串处理)
  static String _redact(String text) {
    var out = text;
    out = out.replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{6,}'), '***');
    out = out.replaceAll(RegExp(r'ark-[A-Za-z0-9_-]{6,}'), '***');
    out = out.replaceAll(RegExp(r'Bearer\s+\S+'), '***');
    return out;
  }
}
