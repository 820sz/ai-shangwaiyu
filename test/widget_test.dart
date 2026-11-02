import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/config/constants.dart';

void main() {
  test('思考模式选项(2026-08-08 砍中/高,只留 disabled/low)', () {
    expect(AppConstants.thinkingOptions.keys, ['disabled', 'low']);
  });

  test('数据库版本已推进到 ≥22(v22 助理数据层:ability_snapshots/task_events)', () {
    // 只断言"下限"而不是等于某个数字:以后每批都会继续 +1,
    // 写等号会让每次升版本都误报(这批已经从 21 → 22 踩过一次)。
    expect(AppConstants.dbVersion, greaterThanOrEqualTo(22));
    expect(AppConstants.bookmarkSourceFollowUp, 'follow_up');
    expect(AppConstants.bookmarkSourceVocab, 'vocab');
  });

  test('DeepSeek 默认模型跟官方最新(V4.1-Flash = deepseek-flash)', () {
    // 2026-09-10 官方发布 V4.1-Flash:模型名 deepseek-flash,原生多模态;
    // 旧名 deepseek-v4-flash / -vision-exp 已退役(仅兼容路由)
    expect(AppConstants.deepseekChatModel, 'deepseek-flash');
    expect(AppConstants.deepseekVisionModel, 'deepseek-flash');
    expect(AppConstants.deepseekFallbackModels, contains('deepseek-flash'));
    expect(AppConstants.deepseekFallbackModels, contains('deepseek-v4-pro'));
  });
}
