import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/models/writing_log.dart';
import 'package:readflow/services/doubao_api.dart';
import 'package:readflow/utils/material_group.dart';

/// v1.6.0 回归测试:
/// - parseWritingReview:错误分类汇总(error_summary 四类)
/// - material_group:书籍 = 一本书一个文件夹,页/章为子分类
/// - WritingLog:日志序列化往返
void main() {
  group('parseWritingReview — 错误分类汇总(v1.6.0)', () {
    test('四类汇总齐全 → 解析为固定键 Map', () {
      final r = DoubaoApiService.parseWritingReview(
        '{"score":78,"correction":"I went home.","summary":"不错",'
        '"issues":[{"original":"I go home","correction":"I went home","type":"语法","reason":"时态"}],'
        '"error_summary":{"词汇":"用词偏口语","语法":"过去时不统一","表达优化":"句式单调","其他":""}}',
      );
      final summary = r['error_summary'] as Map<String, String>;
      expect(summary['词汇'], '用词偏口语');
      expect(summary['语法'], '过去时不统一');
      expect(summary['表达优化'], '句式单调');
      expect(summary['其他'], '');
    });

    test('缺 error_summary → 四个键都补空串(界面按类渲染不崩)', () {
      final r = DoubaoApiService.parseWritingReview('{"score":60}');
      final summary = r['error_summary'] as Map<String, String>;
      expect(summary.keys.toList(), DoubaoApiService.writingErrorCategories);
      expect(summary.values.every((v) => v.isEmpty), isTrue);
    });

    test('error_summary 是字符串/数组等异常形态 → 不抛异常', () {
      final r1 = DoubaoApiService.parseWritingReview(
        '{"error_summary":"没有分类"}',
      );
      expect((r1['error_summary'] as Map)['语法'], '');
      final r2 = DoubaoApiService.parseWritingReview(
        '{"error_summary":["a","b"]}',
      );
      expect((r2['error_summary'] as Map)['词汇'], '');
    });
  });

  group('material_group — 书籍分组(v1.6.0)', () {
    Vocabulary book(String? path, String? page, String word) => Vocabulary(
      word: word,
      translation: '$word-释义',
      category: '书籍',
      materialPath: path,
      sourcePage: page,
    );

    test('旧数据 书籍/《X》/p3 → 拆成书路径 + 页码', () {
      final split = splitBookMaterialPath('书籍/《Character》/p16 p17');
      expect(split.bookPath, '书籍/《Character》');
      expect(split.page, 'p16 p17');
    });

    test('新数据 书籍/《X》 + sourcePage → 书路径不变、页码取字段', () {
      final split = splitBookMaterialPath('书籍/《Character》');
      expect(split.bookPath, '书籍/《Character》');
      expect(split.page, isNull);
    });

    test('非书籍路径原样返回', () {
      final split = splitBookMaterialPath('教材/新概念英语/第2册');
      expect(split.bookPath, '教材/新概念英语/第2册');
      expect(split.page, isNull);
    });

    test('同一本书的旧/新数据合并到一个文件夹,页为子分类', () {
      final items = [
        book('书籍/《Character》/p16 p17', null, 'a'),
        book('书籍/《Character》/p16 p17', null, 'b'),
        book('书籍/《Character》', 'p13', 'c'),
        book('书籍/《Character》', null, 'd'),
        book(null, null, 'e'),
      ];
      final groups = groupMaterials(items, category: '书籍');
      expect(groups.length, 2); // 《Character》 + 未归类
      final character = groups.firstWhere((g) => g.label.contains('Character'));
      expect(character.totalCount, 4);
      expect(character.subgroups.keys.toList(), ['p13', 'p16 p17', '未标页码']);
    });

    test('页码排序:数字优先,无数字排最后', () {
      expect(pageSortKey('p2'), 2);
      expect(pageSortKey('p10'), 10);
      expect(pageSortKey('第3章'), 3);
      expect(pageSortKey('未标页码'), greaterThan(1000));
    });

    test('非书籍分类:整条 material_path 作一级分组,无二级', () {
      final items = [
        Vocabulary(
          word: 'a',
          category: '教材',
          materialPath: '教材/新概念英语/第2册',
        ),
      ];
      final groups = groupMaterials(items, category: '教材');
      expect(groups.length, 1);
      expect(groups.first.label, '新概念英语/第2册');
      expect(groups.first.subgroups.keys.toList(), ['']);
    });
  });

  group('WritingLog — 日志序列化(v1.6.0)', () {
    test('toMap → fromMap 往返保留四类汇总与点评', () {
      final log = WritingLog(
        sourceType: 'handwritten',
        originalText: 'I go home yesterday.',
        correctedText: 'I went home yesterday.',
        score: '70',
        summary: '时态注意',
        issues: const [
          {'original': 'go', 'correction': 'went', 'type': '语法', 'reason': '过去时'},
        ],
        errorSummary: const {'词汇': '', '语法': '时态', '表达优化': '', '其他': ''},
        model: 'deepseek-v4-flash',
        imagePaths: const ['/tmp/a.jpg'],
        createdAt: DateTime(2026, 8, 26, 9, 5),
      );
      final back = WritingLog.fromMap(log.toMap());
      expect(back.sourceType, 'handwritten');
      expect(back.issues.length, 1);
      expect(back.issues.first['type'], '语法');
      expect(back.errorSummary['语法'], '时态');
      expect(back.imagePaths, ['/tmp/a.jpg']);
      expect(back.dateKey, '2026-08-26');
      expect(back.timeLabel, '09:05');
      expect(back.title, 'I go home yesterday.');
    });

    test('损坏 JSON 字段 → 空列表/空 Map 不抛异常', () {
      final back = WritingLog.fromMap({
        'source_type': 'electronic',
        'original_text': 'hello',
        'issues_json': 'not json',
        'error_summary_json': '{broken',
        'created_at': 'bad-date',
      });
      expect(back.issues, isEmpty);
      expect(back.errorSummary, isEmpty);
    });
  });
}
