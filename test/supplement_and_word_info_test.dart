import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/doubao_api.dart';
import 'package:readflow/utils/supplement_merge.dart';

/// v1.3.0 阶段 2 回归测试:
/// - parseWordInfo:AI 补全 JSON 解析(问题 2)
/// - mergeSupplementResults:补充识别去重合并(问题 3)
void main() {
  group('parseWordInfo — AI 补全 JSON 解析', () {
    test('标准 JSON → 四字段回填', () {
      final info = DoubaoApiService.parseWordInfo(
        '{"translation":"无拘束的","part_of_speech":"adj.",'
        '"original_sentence":"The mind wants unfettered freedom.",'
        '"grammar_note":"常用于书面语"}',
      );
      expect(info['translation'], '无拘束的');
      expect(info['part_of_speech'], 'adj.');
      expect(info['original_sentence'], 'The mind wants unfettered freedom.');
      expect(info['grammar_note'], '常用于书面语');
    });

    test('```json 包裹 → 正常解析', () {
      final info = DoubaoApiService.parseWordInfo(
        '```json\n{"translation":"挽歌","part_of_speech":"n.","original_sentence":"","grammar_note":""}\n```',
      );
      expect(info['translation'], '挽歌');
      expect(info['part_of_speech'], 'n.');
    });

    test('缺字段 → 空串不抛异常(用户仍可手动填)', () {
      final info = DoubaoApiService.parseWordInfo(
        '{"translation":"只给了释义"}',
      );
      expect(info['translation'], '只给了释义');
      expect(info['part_of_speech'], '');
      expect(info['original_sentence'], '');
    });

    test('畸形返回 → {} 不抛异常', () {
      expect(DoubaoApiService.parseWordInfo('抱歉,我无法'), isEmpty);
      expect(DoubaoApiService.parseWordInfo('not json at all'), isEmpty);
      expect(DoubaoApiService.parseWordInfo(''), isEmpty);
    });
  });

  group('mergeSupplementResults — 补充识别去重合并', () {
    Vocabulary v(String word, String type) =>
        Vocabulary(word: word, wordType: type, translation: '$word-释义');

    test('新词追加,词序保持:旧结果在前,新词在后', () {
      final existing = [v('apple', 'word'), v('orange', 'word')];
      final fresh = [v('pear', 'word'), v('apple', 'word'), v('grape', 'word')];
      final merged = mergeSupplementResults(existing, fresh);
      expect(merged.map((e) => e.word).toList(), ['apple', 'orange', 'pear', 'grape']);
    });

    test('忽略大小写去重(Apple 与 apple 视为同一词)', () {
      final merged = mergeSupplementResults(
        [v('Apple', 'word')],
        [v('apple', 'word')],
      );
      expect(merged.length, 1);
    });

    test('相同 word 不同 wordType 不算重复(word vs sentence)', () {
      final merged = mergeSupplementResults(
        [v('Let it be.', 'sentence')],
        [v('Let it be.', 'word')],
      );
      expect(merged.length, 2);
    });

    test('空列表安全:existing 空/fresh 空', () {
      expect(mergeSupplementResults([], [v('a', 'word')]).length, 1);
      expect(mergeSupplementResults([v('a', 'word')], []).length, 1);
    });
  });
}
