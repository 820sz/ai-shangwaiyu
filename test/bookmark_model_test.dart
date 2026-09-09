import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/bookmark.dart';

/// 收藏夹模型回归测试(v1.4.0 问题 8/9)
void main() {
  test('toMap/fromMap 往返无损(追问来源)', () {
    final b = Bookmark(
      source: AppConstants.bookmarkSourceFollowUp,
      title: '这个词组的意思',
      content: '答案全文\n第二行',
      model: 'deepseek-v4-flash',
      createdAt: DateTime(2026, 8, 26, 12, 30),
    );
    final back = Bookmark.fromMap(b.toMap());
    expect(back.source, 'follow_up');
    expect(back.title, '这个词组的意思');
    expect(back.content, contains('第二行'));
    expect(back.model, 'deepseek-v4-flash');
    expect(back.createdAt, DateTime(2026, 8, 26, 12, 30));
  });

  test('toMap/fromMap 往返无损(词汇来源,可空字段)', () {
    final b = Bookmark(
      source: AppConstants.bookmarkSourceVocab,
      title: 'unfettered',
      content: 'unfettered\n释义：无拘束的',
      sourceWord: 'unfettered',
    );
    final back = Bookmark.fromMap(b.toMap());
    expect(back.source, 'vocab');
    expect(back.sourceWord, 'unfettered');
    expect(back.model, isNull);
    expect(back.content, contains('无拘束的'));
  });

  test('畸形数据安全回退(不崩)', () {
    final back = Bookmark.fromMap({'id': 1, 'content': '只有内容'});
    expect(back.source, 'follow_up'); // 默认来源
    expect(back.title, '');
    expect(back.createdAt, isNotNull);
  });
}
