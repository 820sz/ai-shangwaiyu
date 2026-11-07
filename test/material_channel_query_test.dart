import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/material_taxonomy.dart';

/// W1a（2026-11-07 用户真机反馈第 1 条）：
/// **材料中心只按「选的难度 + 选的分类」找，不注入用户目标/需求。**
///
/// 这里钉住的是"检索词到底由什么构成"的纯函数口径（频道页只调用它）：
/// ① 非「按需求」方向：queries 只含分类检索词，**不含 goals / interests / 补充需求**；
/// ② 「按需求」方向：需求画像仍可用（独立入口的个性化不能被误删）；
/// ③ 真题 queries 必须拆出 CET-4 / CET-6 两组，且卡片能按标题/URL 判级别。
void main() {
  group('buildChannelQueries — 频道检索词口径', () {
    test('按形式·四级真题：只有分类检索词，不出现目标/兴趣/补充需求', () {
      final queries = MaterialTaxonomy.buildChannelQueries(
        direction: MaterialDirection.form,
        def: MaterialTaxonomy.form,
        selectedIds: const <String>['cet4'],
        goals: const <String>['四六级', '雅思'],
        interests: const <String>['science'],
        extraNeed: '只看真题',
      );
      expect(queries, contains('CET-4 真题阅读'));
      for (final banned in <String>['四六级', '雅思', 'science', '只看真题']) {
        expect(
          queries.any((q) => q.contains(banned)),
          isFalse,
          reason: '材料中心检索词不该包含用户画像「$banned」:$queries',
        );
      }
    });

    test('按题材（不选子分类）：queries 来自 6 个题材，不含用户目标', () {
      final queries = MaterialTaxonomy.buildChannelQueries(
        direction: MaterialDirection.topic,
        def: MaterialTaxonomy.topic,
        goals: const <String>['四六级'],
        extraNeed: '想练考试',
      );
      expect(queries, isNotEmpty);
      expect(queries.any((q) => q.contains('四六级')), isFalse);
      expect(queries.any((q) => q.contains('想练考试')), isFalse);
      // 题材子分类的展示名会进检索词（中文给官方搜索）
      expect(queries, contains('科学与技术'));
    });

    test('按场景：真实英文预设词优先，不掺用户画像', () {
      final queries = MaterialTaxonomy.buildChannelQueries(
        direction: MaterialDirection.scene,
        def: MaterialTaxonomy.scene,
        selectedIds: const <String>['exam'],
        goals: const <String>['四六级'],
      );
      expect(queries, contains('exam preparation'));
      expect(queries.any((q) => q.contains('四六级')), isFalse);
    });

    test('按需求方向：需求画像仍参与（独立入口行为不变）', () {
      final queries = MaterialTaxonomy.buildChannelQueries(
        direction: MaterialDirection.need,
        def: MaterialTaxonomy.need,
        goals: const <String>['四六级'],
        interests: const <String>['science'],
        extraNeed: '想找真题',
      );
      expect(queries, contains('想找真题'));
      expect(queries, contains('四六级'));
      expect(queries, contains('science'));
    });

    test('按需求方向空需求时有安全兜底', () {
      final queries = MaterialTaxonomy.buildChannelQueries(
        direction: MaterialDirection.need,
        def: MaterialTaxonomy.need,
      );
      expect(queries, <String>['english reading']);
    });

    test('子分类没配 queries 时用 fallbackQueries 补真实英文检索词', () {
      final queries = MaterialTaxonomy.categoryQueries(
        direction: MaterialDirection.form,
        def: MaterialTaxonomy.form,
        selectedIds: const <String>['textbook'],
        fallbackQueries: const <String, List<String>>{
          'form:textbook': <String>['english textbook'],
        },
      );
      expect(queries, contains('english textbook'));
    });
  });

  group('buildChannelPromptHint — 只写分类 + 难度', () {
    test('非需求频道：分类 + 难度，不含目标', () {
      final hint = MaterialTaxonomy.buildChannelPromptHint(
        direction: MaterialDirection.form,
        def: MaterialTaxonomy.form,
        selectedIds: const <String>['cet4'],
        bandHint: '目标难度 i+10:未知词率 2%~10%',
      );
      expect(hint, contains('分类:按形式 · 四级真题'));
      expect(hint, contains('i+10'));
      expect(hint.contains('目标:四六级'), isFalse);
    });

    test('按需求方向返回空串（交给按需找自己的 promptHint）', () {
      expect(
        MaterialTaxonomy.buildChannelPromptHint(
          direction: MaterialDirection.need,
          def: MaterialTaxonomy.need,
          bandHint: 'x',
        ),
        isEmpty,
      );
    });
  });

  group('真题分级（queries + 卡片标签）', () {
    test('应试真题类目已拆成 四级真题 / 六级真题 / 全部真题', () {
      final ids = MaterialTaxonomy.form.subtopics.map((s) => s.id).toList();
      expect(ids, containsAll(<String>['cet4', 'cet6', 'exam']));
      final cet4 = MaterialTaxonomy.subtopicOf(
        MaterialDirection.form,
        'cet4',
      )!;
      final cet6 = MaterialTaxonomy.subtopicOf(
        MaterialDirection.form,
        'cet6',
      )!;
      expect(cet4.label, '四级真题');
      expect(cet6.label, '六级真题');
      expect(cet4.queries.any((q) => q.contains('CET-4')), isTrue);
      expect(cet6.queries.any((q) => q.contains('CET-6')), isTrue);
      // 两组词不能互相串（四级组不该出现 CET-6）
      expect(cet4.queries.any((q) => q.contains('CET-6')), isFalse);
      expect(cet6.queries.any((q) => q.contains('CET-4')), isFalse);
    });

    test('examLevelOf：标题/URL 判级别，判不出不猜', () {
      expect(MaterialTaxonomy.examLevelOf('CET-4 真题 2024 阅读'), 'cet4');
      expect(MaterialTaxonomy.examLevelOf('2024年6月大学英语六级真题'), 'cet6');
      expect(
        MaterialTaxonomy.examLevelOf(
          'Reading practice',
          url: 'https://x.com/cet4',
        ),
        'cet4',
      );
      // 「四六级」同时含四/六 → 不猜
      expect(MaterialTaxonomy.examLevelOf('四六级真题 2024'), '');
      expect(MaterialTaxonomy.examLevelOf('New Concept English 3'), '');
    });

    test('examLevelTag：给卡片用的中文级标', () {
      expect(MaterialTaxonomy.examLevelTag('CET-4 真题 2024'), '四级真题');
      expect(MaterialTaxonomy.examLevelTag('CET-6 真题 2024'), '六级真题');
      expect(MaterialTaxonomy.examLevelTag('Climate change'), '');
    });
  });
}
