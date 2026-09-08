import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/doubao_api.dart';

/// v1.5.0 回归测试:
/// - parseWordInfo 音标字段(phonetic)
/// - Vocabulary.phonetic toMap/fromMap 往返(DB v7 迁移)
/// - parseWritingReview 写译批改 JSON 解析
void main() {
  group('parseWordInfo — 音标字段(v1.5.0)', () {
    test('标准 JSON 含 phonetic → 解析音标', () {
      final info = DoubaoApiService.parseWordInfo(
        '{"translation":"无拘束的","part_of_speech":"adj.",'
        '"phonetic":"/ˈʌnfetəd/","original_sentence":"The mind wants unfettered freedom.","grammar_note":""}',
      );
      expect(info['phonetic'], '/ˈʌnfetəd/');
    });

    test('缺 phonetic(老返回)→ 空串不抛异常', () {
      final info = DoubaoApiService.parseWordInfo(
        '{"translation":"挽歌","part_of_speech":"n."}',
      );
      expect(info['phonetic'], '');
    });
  });

  group('Vocabulary.phonetic — DB 字段往返(v1.5.0)', () {
    test('toMap → fromMap 音标保留', () {
      final v = Vocabulary(
        word: 'unfettered',
        translation: '无拘束的',
        phonetic: '/ˈʌnfetəd/',
      );
      final back = Vocabulary.fromMap(v.toMap());
      expect(back.phonetic, '/ˈʌnfetəd/');
    });

    test('copyWith 可清空音标(置 null)', () {
      final v = Vocabulary(word: 'a', phonetic: '/x/');
      expect(v.copyWith(phonetic: null).phonetic, isNull);
    });

    test('无音标(旧数据)→ null 不崩', () {
      final map = {'word': 'hello', 'word_type': 'word', 'created_at': '2026-01-01T00:00:00'};
      final v = Vocabulary.fromMap(map);
      expect(v.phonetic, isNull);
    });
  });

  group('parseWritingReview — 写译批改 JSON 解析(v1.5.0)', () {
    test('标准 JSON → score/correction/summary/issues 解析', () {
      final r = DoubaoApiService.parseWritingReview(
        '{"score":85,"correction":"I went to school yesterday.","summary":"整体不错,注意时态。",'
        '"issues":[{"original":"I go to school yesterday","correction":"I went to school yesterday",'
        '"type":"语法","reason":"yesterday 是过去时间,动词应用过去式 went"}]}',
      );
      expect(r['score'], '85');
      expect(r['correction'], 'I went to school yesterday.');
      expect(r['summary'], '整体不错,注意时态。');
      final issues = r['issues'] as List;
      expect(issues.length, 1);
      expect(issues.first['original'], 'I go to school yesterday');
      expect(issues.first['type'], '语法');
    });

    test('```json 包裹 → 正常解析', () {
      final r = DoubaoApiService.parseWritingReview(
        '```json\n{"score":72,"issues":[]}\n```',
      );
      expect(r['score'], '72');
      expect((r['issues'] as List), isEmpty);
    });

    test('score 为数字类型 → 转字符串不崩', () {
      final r = DoubaoApiService.parseWritingReview('{"score":90}');
      expect(r['score'], '90');
    });

    test('issues 混入非对象 → 跳过不抛异常', () {
      final r = DoubaoApiService.parseWritingReview(
        '{"issues":["bad",{"original":"a","correction":"b","type":"拼写","reason":"r"}]}',
      );
      expect((r['issues'] as List).length, 1);
    });

    test('畸形返回 → {} 不抛异常', () {
      expect(DoubaoApiService.parseWritingReview('抱歉,我做不了'), isEmpty);
      expect(DoubaoApiService.parseWritingReview('not json'), isEmpty);
      expect(DoubaoApiService.parseWritingReview(''), isEmpty);
    });
  });
}
