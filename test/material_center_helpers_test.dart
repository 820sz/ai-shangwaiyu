import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/input_prefs.dart';
import 'package:readflow/services/material_library.dart';

/// 材料中心收尾（v2.23 · task-31）的纯函数契约：
/// ①「今日推荐」预计难度区间与口径文案；② 黑名单过滤计数；③ url/标题去重。
///
/// 为什么这些要单测：三件事都在界面里直接决定用户看到什么 ——
/// - 难度标签一旦写成"覆盖 96%"，就是把估算冒充成实测（数据造假）；
/// - 过滤计数一旦不对，用户会以为"公开源没内容"；
/// - 去重一旦把不同文章误删，材料会凭空消失。
void main() {
  group('预计难度区间（元数据估算，不冒充覆盖率）', () {
    test('外刊/新闻默认落 B1~B2，标签格式是「预计 X · 程度词」', () {
      final e = MaterialLibrary.estimateDifficulty(
        sourceId: 'npr',
        kind: 'news',
      );
      expect(e.band, 'B1~B2');
      expect(e.difficulty, '中等');
      expect(e.label, '预计 B1~B2 · 中等');
      // 口径必须写清楚：是估算，且不是精确覆盖率
      expect(e.basis, contains('估算'));
      expect(e.basis, contains('非精确覆盖率'));
      // 没有长度信号时不列"长度"（不编依据）
      expect(e.basis, isNot(contains('长度')));
    });

    test('论文最高档、公版书次高、VOA 慢速英语最低档', () {
      expect(
        MaterialLibrary.estimateDifficulty(sourceId: 'arxiv', kind: 'paper')
            .band,
        'C1+',
      );
      expect(
        MaterialLibrary.estimateDifficulty(sourceId: 'gutenberg', kind: 'book')
            .band,
        'B2~C1',
      );
      expect(
        MaterialLibrary.estimateDifficulty(sourceId: 'voa_le', kind: 'podcast')
            .band,
        'A2~B1',
      );
    });

    test('真实词数是长度信号：<300 降一档、>1500 升一档，且依据里出现"长度"', () {
      final short = MaterialLibrary.estimateDifficulty(
        sourceId: 'npr',
        kind: 'news',
        wordCount: 200,
      );
      expect(short.band, 'A2~B1');
      expect(short.basis, contains('长度'));

      final long = MaterialLibrary.estimateDifficulty(
        sourceId: 'npr',
        kind: 'news',
        wordCount: 2000,
      );
      expect(long.band, 'B2~C1');

      // 边界：300 / 1500 本身不触发（严格小于/大于）
      expect(
        MaterialLibrary.estimateDifficulty(
          sourceId: 'npr',
          kind: 'news',
          wordCount: 300,
        ).band,
        'B1~B2',
      );
      expect(
        MaterialLibrary.estimateDifficulty(
          sourceId: 'npr',
          kind: 'news',
          wordCount: 1500,
        ).band,
        'B1~B2',
      );
    });

    test('kind 缺失/未知源 → 按文章(B1~B2)处理，不抛异常', () {
      final a = MaterialLibrary.estimateDifficulty(sourceId: 'no_such_source');
      final b = MaterialLibrary.estimateDifficulty(
        sourceId: 'npr',
        kind: '未知类型',
      );
      expect(a.band, 'B1~B2');
      expect(b.band, 'B1~B2');
    });

    test('标签里绝不出现百分比（估算不许伪装成实测覆盖率）', () {
      for (final kind in ['news', 'book', 'paper', 'podcast', 'wiki']) {
        final e = MaterialLibrary.estimateDifficulty(
          sourceId: 'npr',
          kind: kind,
          wordCount: 800,
        );
        expect(e.label, startsWith('预计 '));
        expect(e.label, isNot(contains('%')));
        expect(e.basis, isNot(contains('%')));
      }
    });
  });

  group('黑名单过滤（C1-14：公开源结果也遵守屏蔽设置）', () {
    InputPreferences prefsWith({
      List<String> topics = const [],
      List<String> keywords = const [],
    }) =>
        InputPreferences.fromSources(
          model: LearnerModel(
            blockedTopics: topics,
            blockedKeywords: keywords,
          ),
        );

    test('没设黑名单：全部保留、过滤计数为 0', () {
      final r = MaterialLibrary.filterBlocked<String>(
        const ['a', 'b', 'c'],
        prefsWith(),
        titleOf: (s) => s,
        sourceOf: (_) => '',
        genresOf: (_) => const [],
      );
      expect(r.kept, ['a', 'b', 'c']);
      expect(r.hidden, 0);
      expect(r.hasHidden, isFalse);
    });

    test('关键词命中标题 / 来源 / 题材任一即过滤，计数正确、顺序保持', () {
      final prefs = prefsWith(keywords: ['crypto']);
      final items = [
        // 标题命中
        ('Bitcoin crypto rally', 'npr', <String>['科技']),
        // 来源命中
        ('A normal article', 'crypto_daily', <String>['科技']),
        // 题材命中
        ('Another article', 'npr', <String>['crypto']),
        // 都不命中
        ('Cooking with herbs', 'npr', <String>['生活']),
      ];
      final r = MaterialLibrary.filterBlocked(
        items,
        prefs,
        titleOf: (e) => e.$1,
        sourceOf: (e) => e.$2,
        genresOf: (e) => e.$3,
      );
      expect(r.hidden, 3);
      expect(r.kept.length, 1);
      expect(r.kept.single.$1, 'Cooking with herbs');
    });

    test('题材黑名单同样生效；被过滤项不会偷偷留在列表里', () {
      final prefs = prefsWith(topics: ['娱乐']);
      final r = MaterialLibrary.filterBlocked(
        ['明星八卦 100 条', '英语听力练习'],
        prefs,
        titleOf: (e) => e,
        sourceOf: (_) => 'npr',
        genresOf: (e) => [e.contains('八卦') ? '娱乐' : '学习'],
      );
      expect(r.hidden, 1);
      expect(r.kept, ['英语听力练习']);
    });
  });

  group('url / 标题去重', () {
    test('同一 url（含尾部斜杠差异）只保留第一条', () {
      final out = MaterialLibrary.dedupeBy<String>(
        const [
          'https://example.com/a/',
          'https://example.com/a',
          'https://example.com/b',
        ],
        urlOf: (s) => s,
        titleOf: (s) => s,
      );
      expect(out, ['https://example.com/a/', 'https://example.com/b']);
    });

    test('url 不同但标题相同（同文不同 entry 地址）也去重', () {
      final items = [
        ('https://a.com/1', 'The Future of Learning'),
        ('https://b.com/2', 'the future of learning  '),
        ('https://c.com/3', 'Another Story'),
      ];
      final out = MaterialLibrary.dedupeBy(
        items,
        urlOf: (e) => e.$1,
        titleOf: (e) => e.$2,
      );
      expect(out.length, 2);
      expect(out.last.$2, 'Another Story');
    });

    test('url 与标题都缺失的条目无法判重 → 保留（宁可多不可误删）', () {
      final out = MaterialLibrary.dedupeBy<String>(
        const ['', '', 'x'],
        urlOf: (s) => s,
        titleOf: (s) => s,
      );
      // 前两条的 url/title 都是空串，无从判断；第三条有值
      expect(out.length, 3);
    });
  });
}
