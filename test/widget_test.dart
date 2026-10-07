import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/config/constants.dart';

void main() {
  test('思考模式选项(2026-08-08 砍中/高,只留 disabled/low)', () {
    expect(AppConstants.thinkingOptions.keys, ['disabled', 'low']);
  });

  test('数据库版本为 18(v16 练习与内容块、v17 书架与中文标题、v18 封面地址)', () {
    expect(AppConstants.dbVersion, 18);
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
