import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/models/vocabulary.dart';

void main() {
  Vocabulary make(String word, {String? sentence, String type = 'sentence'}) {
    return Vocabulary(word: word, wordType: type, originalSentence: sentence);
  }

  group('displayWordText — 词条化截断回退', () {
    test('word 以 … 结尾 + 更长完整句 → 回退完整句', () {
      final v = make('Because reality is n…',
          sentence: 'Because reality is never enough.');
      expect(v.displayWordText, 'Because reality is never enough.');
    });

    test('word 以 ...(三个ASCII点)结尾 → 回退', () {
      final v = make('The mind wants me...',
          sentence: 'The mind wants meaning, but reality offers no clear '
              'beginnings, middles, or ends. Stories do.');
      expect(v.displayWordText, contains('The mind wants meaning'));
    });

    test('word 含 ⋯ 变体省略号 → 回退', () {
      final v = make('A long truncated phrase ⋯',
          sentence: 'A long truncated phrase that continues much further '
              'than the word field.');
      expect(v.displayWordText, contains('continues much further'));
    });

    test('word 含省略号但不在末尾(带尾随空格)→ 回退', () {
      final v = make('Because reality is n… ',
          sentence: 'Because reality is never enough.');
      expect(v.displayWordText, 'Because reality is never enough.');
    });

    test('sentence 类型 word 明显短于完整句(无省略号)→ 回退', () {
      final v = make('Because reality',
          sentence: 'Because reality is never enough.');
      expect(v.displayWordText, 'Because reality is never enough.');
    });

    test('word 完整(与例句等长)→ 不回退', () {
      final v = make('Because reality is never enough.',
          sentence: 'Because reality is never enough.');
      expect(v.displayWordText, 'Because reality is never enough.');
    });

    test('单词类型(word)带省略号 + 有更长例句 → 回退', () {
      final v = make('understand…', type: 'word',
          sentence: 'You must understand the rules.');
      expect(v.displayWordText, 'You must understand the rules.');
    });

    test('正常单词 + 例句更长 → 不回退', () {
      final v = make('understand', type: 'word',
          sentence: 'You must understand the rules.');
      expect(v.displayWordText, 'understand');
    });

    test('originalSentence 为空 → 不回退', () {
      final v = make('Because reality is n…');
      expect(v.displayWordText, 'Because reality is n…');
    });
  });
}
