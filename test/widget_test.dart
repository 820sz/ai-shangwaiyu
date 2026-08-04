import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/config/constants.dart';

void main() {
  test('思考模式选项完整(disabled/low/medium/high)', () {
    expect(AppConstants.thinkingOptions.keys,
        containsAll(['disabled', 'low', 'medium', 'high']));
  });

  test('数据库版本为 5(含 reference_answers + article translation 迁移)', () {
    expect(AppConstants.dbVersion, 5);
  });

  test('DeepSeek 默认模型为 v4 系列(chat/reasoner 已停用)', () {
    expect(AppConstants.deepseekChatModel, 'deepseek-v4-flash');
  });
}
