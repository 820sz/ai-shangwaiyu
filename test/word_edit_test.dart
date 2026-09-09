// 词汇编辑联动逻辑测试：
// 1. replaceWordInSentence——修改单词后例句自动替换（保留大小写形态）
// 2. Vocabulary 编辑后总览/追问/保存共用同一数据源（模型层验证 copyWith）
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/screens/input/process_chat.dart';

void main() {
  group('replaceWordInSentence 例句单词替换', () {
    test('普通替换: hi → he', () {
      expect(
        replaceWordInSentence('he is a hi boy', 'hi', 'he'),
        'he is a he boy',
      );
    });

    test('忽略大小写替换,保留原词首字母大小写形态', () {
      // 原文首字母大写(句首),新词首字母跟随大写
      expect(
        replaceWordInSentence('Hi is a boy', 'hi', 'he'),
        'He is a boy',
      );
      // 原文小写,新词保持小写
      expect(
        replaceWordInSentence('a hi there', 'hi', 'he'),
        'a he there',
      );
    });

    test('词边界:不替换单词内部的子串', () {
      expect(
        replaceWordInSentence('this is high school', 'hi', 'he'),
        'this is high school',
      );
    });

    test('同一词出现多次全部替换', () {
      expect(
        replaceWordInSentence('hi and hi again', 'hi', 'he'),
        'he and he again',
      );
    });

    test('新词与旧词相同不变', () {
      final s = 'he is a he boy';
      expect(replaceWordInSentence(s, 'he', 'he'), s);
    });

    test('空句子/空词安全返回', () {
      expect(replaceWordInSentence('', 'hi', 'he'), '');
      expect(replaceWordInSentence('hi there', '', 'he'), 'hi there');
      expect(replaceWordInSentence('hi there', 'hi', ''), 'hi there');
    });

    test('例句不含旧词时原样返回', () {
      final s = 'the cat sat';
      expect(replaceWordInSentence(s, 'dog', 'cat'), s);
    });
  });

  group('Vocabulary 编辑后字段联动', () {
    test('copyWith 改词后例句需手动替换(调用方负责),数据源一致', () {
      final v = Vocabulary(
        word: 'hi',
        translation: '你好',
        originalSentence: 'Hi is a boy.',
      );
      final newSentence = replaceWordInSentence(
        v.originalSentence!,
        v.word,
        'he',
      );
      final edited = v.copyWith(word: 'he', originalSentence: newSentence);
      expect(edited.word, 'he');
      expect(edited.originalSentence, 'He is a boy.');
      // 其余字段保留
      expect(edited.translation, '你好');
      expect(edited.wordType, 'word');
    });

    test('手动添加的词进入列表后序列化往返无损', () {
      final added = Vocabulary(
        word: 'unfettered',
        translation: '不受约束的',
        originalSentence: 'The mind wants unfettered freedom.',
        photoPath: null,
      );
      final restored = Vocabulary.fromMap(added.toMap());
      expect(restored.word, 'unfettered');
      expect(restored.originalSentence, 'The mind wants unfettered freedom.');
      expect(restored.photoPath, isNull);
    });
  });
}
