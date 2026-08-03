import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/config/constants.dart';
import 'package:readflow/services/doubao_api.dart';

void main() {
  group('parseResponse — 圈画模式(marked)', () {
    test('单图 items 格式', () {
      const raw = '{"items":[{"word":"apple","translation":"苹果",'
          '"word_type":"word","part_of_speech":"n."},'
          '{"word":"take off","translation":"起飞","word_type":"phrase"}]}';
      final result = DoubaoApiService.parseResponse(raw);
      expect(result.length, 2);
      expect(result[0]['word'], 'apple');
      expect(result[0]['image_index'], isNull);
      expect(result[1]['word_type'], 'phrase');
    });

    test('多图 items_by_image 格式带 image_index', () {
      const raw =
          '{"items_by_image":[{"image_index":0,"items":[{"word":"cat","translation":"猫"}]},'
          '{"image_index":2,"items":[{"word":"dog","translation":"狗"}]}]}';
      final result = DoubaoApiService.parseResponse(raw);
      expect(result.length, 2);
      expect(result[0]['image_index'], 0);
      expect(result[1]['image_index'], 2);
    });

    test('items_by_image 缺 image_index → 兜底 0', () {
      const raw = '{"items_by_image":[{"items":[{"word":"cat","translation":"猫"}]}]}';
      final result = DoubaoApiService.parseResponse(raw);
      expect(result.single['image_index'], 0);
    });

    test('空 items → 空列表', () {
      expect(DoubaoApiService.parseResponse('{"items":[]}'), isEmpty);
    });

    test('```json 代码块包裹可解析', () {
      const raw = '```json\n{"items":[{"word":"book","translation":"书"}]}\n```';
      final result = DoubaoApiService.parseResponse(raw);
      expect(result.single['word'], 'book');
    });

    test('word 为空的项目被过滤', () {
      const raw =
          '{"items":[{"word":"","translation":"空"},{"word":"ok","translation":"好"}]}';
      final result = DoubaoApiService.parseResponse(raw);
      expect(result.single['word'], 'ok');
    });

    test('非法 JSON → FormatException', () {
      expect(() => DoubaoApiService.parseResponse('这不是JSON'),
          throwsFormatException);
    });
  });

  group('parseResponse — 全文翻译模式(fullText)', () {
    test('paragraphs 格式', () {
      const raw = '{"paragraphs":[{"original":"Hello world","translation":"你好世界"},'
          '{"original":"Second line","translation":"第二行"}]}';
      final result = DoubaoApiService.parseResponse(raw,
          analysisMode: AppConstants.analysisModeFullText);
      expect(result.length, 2);
      expect(result[0]['original'], 'Hello world');
    });

    test('original 为空被过滤', () {
      const raw = '{"paragraphs":[{"original":"","translation":"空"},'
          '{"original":"Real","translation":"真"}]}';
      final result = DoubaoApiService.parseResponse(raw,
          analysisMode: AppConstants.analysisModeFullText);
      expect(result.single['original'], 'Real');
    });

    test('无 paragraphs → 空列表', () {
      expect(
          DoubaoApiService.parseResponse('{"items":[]}',
              analysisMode: AppConstants.analysisModeFullText),
          isEmpty);
    });
  });
}
