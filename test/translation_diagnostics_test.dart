import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/translation_diagnostics.dart';

/// v2.16.0 回归:翻译失败诊断缓存。
///
/// 背景:阅读器翻译失败时,旧实现只在段下显示一行英文异常,用户反馈"翻译坏了"
/// 时排障全靠猜。「我的 → 诊断信息」现在会显示最近 3 条失败原因 —— 这里锁住
/// 缓存语义(环形只留 3 条、时间顺序、脱敏、可清空),并确保**不会缓存 API Key**。
void main() {
  setUp(() => TranslationDiagnostics.clear());
  tearDown(() => TranslationDiagnostics.clear());

  test('空状态:没有失败时给一行明确文案', () {
    expect(TranslationDiagnostics.failures, isEmpty);
    expect(TranslationDiagnostics.failureLines(), ['(本次运行没有翻译失败)']);
  });

  test('最多保留 3 条:环形丢最早的,顺序为旧→新', () {
    for (var i = 1; i <= 5; i++) {
      TranslationDiagnostics.recordFailure('失败原因 $i');
    }
    final failures = TranslationDiagnostics.failures;
    expect(failures.length, TranslationDiagnostics.maxFailures);
    expect(failures.map((f) => f.reason).toList(),
        ['失败原因 3', '失败原因 4', '失败原因 5']);
    expect(TranslationDiagnostics.failureLines().length, 3);
  });

  test('每条带 HH:mm:ss 时间戳,便于和用户操作时间对齐', () {
    TranslationDiagnostics.recordFailure(
      '网络超时：请检查网络后重试',
      now: DateTime(2026, 11, 1, 14, 3, 22),
    );
    final line = TranslationDiagnostics.failureLines().single;
    expect(line, contains('14:03:22'));
    expect(line, contains('网络超时'));
  });

  test('脱敏:错误文本里的 key / Bearer token 不会进诊断缓存', () {
    TranslationDiagnostics.recordFailure(
      'API 返回错误：key=sk-abc123def456, header=Bearer eyJhbGciOi.xxx',
    );
    TranslationDiagnostics.recordFailure('ark-9876543210 无效');
    final text = TranslationDiagnostics.failureLines().join('\n');
    expect(text, isNot(contains('sk-abc123def456')));
    expect(text, isNot(contains('Bearer eyJhbGciOi.xxx')));
    expect(text, isNot(contains('ark-9876543210')));
    expect(text, contains('***'));
  });

  test('空原因被忽略;clear 后回到空状态', () {
    TranslationDiagnostics.recordFailure('   ');
    expect(TranslationDiagnostics.failures, isEmpty);
    TranslationDiagnostics.recordFailure('某段没翻出来');
    expect(TranslationDiagnostics.failures.length, 1);
    TranslationDiagnostics.clear();
    expect(TranslationDiagnostics.failures, isEmpty);
  });
}
