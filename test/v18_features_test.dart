import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/material_recommendation.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/doubao_api.dart';
import 'package:readflow/services/learner_profile_store.dart';
import 'package:readflow/services/material_recommend_service.dart';
import 'package:readflow/utils/page_label.dart';

/// v1.8.0 回归测试:
/// - 页码智能归一(用户实测「p9页」被录成「pp9页」)
/// - 思考模型把 JSON 写在思考通道时的提取
/// - AI 推荐清单解析 / 学习画像推断
void main() {
  group('normalizePageLabel — 页码智能归一(v1.8.0)', () {
    test('用户实测的脏输入全部归一成 p9', () {
      for (final raw in ['p9页', 'P9', '第9页', '9页', '9', ' p 9 ', 'pp9页']) {
        expect(normalizePageLabel(raw), 'p9', reason: '输入「$raw」');
      }
    });

    test('范围写法统一成 p9-12', () {
      expect(normalizePageLabel('p9-12'), 'p9-12');
      expect(normalizePageLabel('第9至12页'), 'p9-12');
      expect(normalizePageLabel('9~12'), 'p9-12');
      expect(normalizePageLabel('p9—12'), 'p9-12');
    });

    test('多页输入:连续数字压缩成区间', () {
      expect(normalizePageLabel('p16 p17'), 'p16-17');
      expect(normalizePageLabel('p16,p17,p18'), 'p16-18');
      expect(normalizePageLabel('16 20'), 'p16,p20');
    });

    test('非页码内容原样保留(序章/前言/Chapter One)', () {
      expect(normalizePageLabel('序章'), '序章');
      expect(normalizePageLabel('前言'), '前言');
      expect(normalizePageLabel(''), '');
    });

    test('重复数字去重', () {
      expect(normalizePageLabel('p9 p9'), 'p9');
    });
  });

  group('DoubaoApiService 文本提取(v1.8.0)', () {
    test('extractJsonBlock:从思考散文里抠出 JSON', () {
      const reasoning =
          '让我先看一下这张图…… 好，图上标了三个词。\n'
          '{"items":[{"word":"unfettered","translation":"无拘束的"}]}\n'
          '再检查一遍，没有遗漏。';
      final json = DoubaoApiService.extractJsonBlock(reasoning);
      expect(json.startsWith('{'), isTrue);
      expect(json.endsWith('}'), isTrue);
      expect(json.contains('unfettered'), isTrue);
    });

    test('extractJsonBlock:```json 包裹也能取', () {
      final json = DoubaoApiService.extractJsonBlock(
        '```json\n{"items":[]}\n```',
      );
      expect(json, '{"items":[]}');
    });

    test('extractJsonBlock:没有 JSON 返回空串', () {
      expect(DoubaoApiService.extractJsonBlock('只有思考过程'), '');
      expect(DoubaoApiService.extractJsonBlock(''), '');
    });

    test('extractMarkdown:剥掉整篇代码块外壳', () {
      expect(
        DoubaoApiService.extractMarkdown('```markdown\n## 选段\nHello\n```'),
        '## 选段\nHello',
      );
      expect(DoubaoApiService.extractMarkdown('## 选段\nHello'), '## 选段\nHello');
    });
  });

  group('MaterialRecommendService — 推荐解析与画像(v1.8.0)', () {
    test('parseRecommendations:标准 JSON → 推荐列表', () {
      final list = MaterialRecommendService.parseRecommendations(
        '{"items":[{"title":"《Animal Farm》","summary":"寓言小说","level":"B1",'
        '"reason":"你在《Character》里的生词偏文学","keywords":"小说,寓言"}]}',
        category: '书籍',
        profileSnapshot: '水平:中级',
      );
      expect(list.length, 1);
      expect(list.first.title, '《Animal Farm》');
      expect(list.first.level, 'B1');
      expect(list.first.category, '书籍');
      expect(list.first.profileSnapshot, '水平:中级');
    });

    test('parseRecommendations:缺 title 的条目被丢弃,坏 JSON 不抛异常', () {
      final list = MaterialRecommendService.parseRecommendations(
        '{"items":[{"summary":"没有标题"},{"title":"有效"}]}',
        category: '外刊',
      );
      expect(list.map((e) => e.title).toList(), ['有效']);
      expect(
        MaterialRecommendService.parseRecommendations('抱歉我做不到', category: '外刊'),
        isEmpty,
      );
    });

    test('vocabFingerprint:空词库/有词库都能生成指纹', () {
      expect(MaterialRecommendService.vocabFingerprint([]), contains('词库为空'));
      final fp = MaterialRecommendService.vocabFingerprint([
        Vocabulary(
          word: 'unfettered',
          translation: '无拘束的',
          sourceBook: '《Character》',
          category: '书籍',
          masteryLevel: 1,
        ),
        Vocabulary(word: 'spin', translation: '扭转', category: '书籍'),
      ]);
      expect(fp.contains('收藏词汇总数:2'), isTrue);
      expect(fp.contains('《Character》'), isTrue);
    });
  });

  group('LearnerProfileStore.suggestFromVocab — 画像推断(v1.8.0)', () {
    List<Vocabulary> many(int n, {String book = '', String category = ''}) =>
        List.generate(
          n,
          (i) => Vocabulary(
            word: 'w$i',
            translation: 'x',
            sourceBook: book,
            category: category,
          ),
        );

    test('词汇量 → 水平档', () {
      expect(
        LearnerProfileStore.suggestFromVocab(many(20)).level,
        '入门（A1-A2）',
      );
      expect(
        LearnerProfileStore.suggestFromVocab(many(200)).level,
        '中级（B1-B2）',
      );
      expect(
        LearnerProfileStore.suggestFromVocab(many(900)).level,
        '高级（C1-C2）',
      );
    });

    test('来源关键词 → 兴趣题材', () {
      final p = LearnerProfileStore.suggestFromVocab(
        many(100, book: 'The Economist 外刊', category: '外刊'),
      );
      expect(p.interests.contains('新闻时事'), isTrue);
    });

    test('不覆盖用户已填内容', () {
      final p = LearnerProfileStore.suggestFromVocab(
        many(200, book: 'Character', category: '书籍'),
        base: const LearnerProfile(level: '备考（雅思/托福）', goal: '应试提分'),
      );
      expect(p.level, '备考（雅思/托福）');
      expect(p.goal, '应试提分');
    });

    test('空词库 → 原样返回', () {
      const base = LearnerProfile(level: '中级（B1-B2）');
      expect(LearnerProfileStore.suggestFromVocab([], base: base).level, base.level);
    });
  });
}
