import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/config/constants.dart';

void main() {
  test('思考模式选项(2026-08-08 砍中/高,只留 disabled/low)', () {
    expect(AppConstants.thinkingOptions.keys, ['disabled', 'low']);
  });

  test('数据库版本为 9(含 v8 书籍路径/writing_logs、v9 页码归一 + 推荐表)', () {
    expect(AppConstants.dbVersion, 9);
    expect(AppConstants.bookmarkSourceFollowUp, 'follow_up');
    expect(AppConstants.bookmarkSourceVocab, 'vocab');
  });

  test('DeepSeek 默认模型为 v4 系列(chat/reasoner 已停用)', () {
    expect(AppConstants.deepseekChatModel, 'deepseek-v4-flash');
  });
}
