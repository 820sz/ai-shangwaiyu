import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/find_need_context.dart';
import 'package:readflow/services/input_prefs.dart';
import 'package:readflow/services/material_need.dart';
import 'package:readflow/services/material_prefs.dart';
import 'package:readflow/services/tutor_insights.dart';

/// 「找材料 · 按我的情况找」依据数据的单测(2026-11-06)。
///
/// 关心的不是"文案好不好看",而是**诚实性**:
/// 1. 没数据时 4 行必须写「待测」且**不出现任何数字**(与学习助理同一条纪律);
/// 2. 有数据时每个数字都能指回输入字段;
/// 3. "为什么推这些"只允许使用真实字段;
/// 4. 检索词/需求描述在空数据时也有安全兜底(不留空白页)。
void main() {
  group('FindNeedContext 空数据降级', () {
    FindNeedContext empty() => FindNeedContext(
          need: const MaterialNeed(),
          prefs: InputPreferences(),
          model: LearnerModel(),
        );

    test('4 行都为"待测 且不含数字"', () {
      final ctx = empty();
      expect(ctx.rows.length, 4);
      expect(ctx.rows.every((row) => !row.measured), isTrue);
      for (final row in ctx.rows) {
        // 没有数据的行不许出现统计数字(数字只可能来自真实字段)
        expect(
          RegExp(r'[0-9]').hasMatch(row.value),
          isFalse,
          reason: '未测行「${row.label}」出现了数字:${row.value}',
        );
      }
      // 难度档行即使没设置也保持"不限"语义,不假装已选档
      expect(ctx.rows.first.value, contains('不限'));
    });

    test('没数据时"为什么推这些"不编依据,只给兜底说明', () {
      final ctx = empty();
      expect(ctx.reasons.length, 1);
      expect(ctx.reasons.first, contains('还没设置需求'));
      expect(RegExp(r'[0-9]').hasMatch(ctx.reasons.first), isFalse);
    });

    test('检索词/需求描述有安全兜底', () {
      final ctx = empty();
      expect(ctx.queries(), isNotEmpty);
      expect(ctx.queries().first, 'english reading');
      expect(ctx.needText, isNotEmpty);
      expect(ctx.hasTutorData, isFalse);
    });
  });

  group('FindNeedContext 有真实数据时', () {
    FindNeedContext rich() => FindNeedContext(
          need: const MaterialNeed(
            band: MaterialBand.i10,
            goals: <String>['四六级'],
            extra: '想找能读到原文的真题',
          ),
          prefs: InputPreferences(
            examGoals: <String>['四六级', '兴趣阅读'],
            interests: <String>['science', '历史'],
            blockedTopics: <String>['影视娱乐'],
            dailyMinutes: 25,
          ),
          model: LearnerModel(),
          insight: const InsightSource(
            vocabEstimate: 4200,
            vocabCi: 350,
            cefr: 'B1',
            errorTagCounts: <String, int>{'时态': 8, '冠词': 5, '词汇': 2},
            readingWpm: 180,
            materialsFinished30d: 4,
            materialsReading: 2,
            dailyMinutes: 25,
          ),
        );

    test('4 行都测到,数字指回输入字段', () {
      final ctx = rich();
      final rows = ctx.rows;
      expect(rows.length, 4);
      expect(rows.every((row) => row.measured), isTrue);
      expect(rows[0].value, contains('i+10'));
      expect(rows[1].value, contains('四六级'));
      expect(rows[2].value, contains('时态 8 次'));
      expect(rows[3].value, contains('近 30 天读完 4 篇'));
      expect(rows[3].value, contains('180 词/分'));
      expect(ctx.weakTags, <String>['时态', '冠词', '词汇']);
    });

    test('为什么推这些只用真实字段', () {
      final ctx = rich();
      final text = ctx.reasons.join(' ');
      expect(text, contains('i+10'));
      expect(text, contains('四六级'));
      expect(text, contains('时态'));
      expect(text, contains('影视娱乐'));
      // 没有的字段不许出现(复习留存率目前没有聚合口径 → 不许出现)
      expect(text, isNot(contains('留存率')));
    });

    test('检索词包含补充需求/目标/拉丁兴趣,去重且不空', () {
      final queries = rich().queries();
      expect(queries, contains('想找能读到原文的真题'));
      expect(queries, contains('四六级'));
      expect(queries, contains('science'));
      expect(queries, isNot(contains('历史')), reason: '非拉丁兴趣只给 AI 看,不直接当公开源检索词');
      expect(queries.toSet().length, queries.length);
    });

    test('屏蔽题材会真的过滤候选(与材料推荐同一口径)', () {
      final ctx = rich();
      expect(
        ctx.allows(title: '影视娱乐八卦合集', source: 'NPR'),
        isFalse,
        reason: '命中屏蔽题材的候选必须被过滤',
      );
      expect(ctx.allows(title: 'Climate change and cities'), isTrue);
    });

    test('aiHint 带上难度/目标/弱项', () {
      final hint = rich().aiHint;
      expect(hint, contains('i+10'));
      expect(hint, contains('四六级'));
      expect(hint, contains('时态'));
    });
  });
}
