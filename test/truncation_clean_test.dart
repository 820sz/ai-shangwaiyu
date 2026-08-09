import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/services/doubao_api.dart';

void main() {
  group('cleanTruncatedWord — 词条化截断清洗(数据层治本)', () {
    test('word 以 … 结尾 → 用完整句替换', () {
      final w = DoubaoApiService.cleanTruncatedWord(
        'Because reality is n…', 'sentence',
        'Because reality is never enough.');
      expect(w, 'Because reality is never enough.');
    });

    test('word 以 ... 结尾 → 替换', () {
      final w = DoubaoApiService.cleanTruncatedWord(
        'The mind wants me...', 'sentence',
        'The mind wants meaning, but reality offers no clear '
            'beginnings, middles, or ends. Stories do.');
      expect(w, contains('The mind wants meaning'));
    });

    test('word 以 ⋯ / 双点 .. / 中文省略号 …… 结尾 → 替换', () {
      for (final end in ['⋯', '..', '……']) {
        final w = DoubaoApiService.cleanTruncatedWord(
          'A long truncated sentence$end', 'sentence',
          'A long truncated sentence that continues much further than '
              'the word field.');
        expect(w, contains('continues much further'),
            reason: '省略号形态 $end 应触发清洗');
      }
    });

    test('正常短语无省略号 → 不清洗(防误伤 compound with)', () {
      final w = DoubaoApiService.cleanTruncatedWord(
        'compound with', 'phrase',
        'The compound with the longest chain is unstable.');
      expect(w, 'compound with');
    });

    test('word 完整(与例句等长)→ 不清洗', () {
      final w = DoubaoApiService.cleanTruncatedWord(
        'Because reality is never enough.', 'sentence',
        'Because reality is never enough.');
      expect(w, 'Because reality is never enough.');
    });

    test('originalSentence 为空 → 不清洗', () {
      final w = DoubaoApiService.cleanTruncatedWord(
        'Because reality is n…', 'sentence', '');
      expect(w, 'Because reality is n…');
    });

    test('单词类型带省略号 + 例句更长 → 也替换', () {
      final w = DoubaoApiService.cleanTruncatedWord(
        'understand…', 'word',
        'You must understand the rules.');
      expect(w, 'You must understand the rules.');
    });

    test('单点结尾(正常缩写句点)不清洗', () {
      final w = DoubaoApiService.cleanTruncatedWord(
        'It is true.', 'sentence',
        'It is true that the world keeps spinning.');
      expect(w, 'It is true.');
    });

    test('parseResponse 集成:识别结果自动清洗截断词条', () {
      const raw = '{"items":[{"word":"Because reality is n…",'
          '"translation":"因为现实永远不够。","word_type":"sentence",'
          '"original_sentence":"Because reality is never enough."},'
          '{"word":"compound with","translation":"与…结合","word_type":"phrase",'
          '"original_sentence":"The compound with the longest chain is unstable."}]}';
      final result = DoubaoApiService.parseResponse(raw);
      expect(result[0]['word'], 'Because reality is never enough.');
      expect(result[1]['word'], 'compound with'); // 短语不误伤
    });
  });
}
