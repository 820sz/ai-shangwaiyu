import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/doubao_api.dart';

/// AI 补全单词信息的 JSON 解析回归。
///
/// v1.9.0:原 `mergeSupplementResults` 用例随 `_supplementMode` 死代码一起删除
/// ——「补充识别」在 v1.8.0 已并入唯一的「重新识别」，那条合并分支不再可达
/// （审查报告 §4.3 死代码项）。
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
      final info = DoubaoApiService.parseWordInfo('{"translation":"只给了释义"}');
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
}
