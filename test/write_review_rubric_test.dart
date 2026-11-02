import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/screens/writing/write_review_screen.dart';
import 'package:readflow/services/doubao_api.dart';
import 'package:readflow/services/output_rubric.dart';

/// 批 7(P1-4)写译批改接 rubric 的纯逻辑回归测试(不联网)。
///
/// 覆盖:
/// 1. 练习类型 → rubric 映射(写作 cet4_writing / 翻译 cet4_translation);
/// 2. 批改提示词纪律(先依据后分数、同时含 rubric 维度与旧版字段、自定义提示词不被覆盖);
/// 3. `parseScoringResult` 成功/失败两条路径(失败必须能回退旧解析,不能白屏);
/// 4. 旧结构映射(issues/error_summary)不破坏结果页与错误档案回流;
/// 5. `score_json` 并入 rubric 键且不覆盖旧键。
void main() {
  const writingJson = '''
```json
{"dimensions":[
  {"key":"content","score":22,"evidence":"First, the essay states ..."},
  {"key":"organization","score":16,"evidence":"First ... Second ..."},
  {"key":"language","score":18,"evidence":"There are many students"},
  {"key":"vocabulary","score":12,"evidence":"important/essential"},
  {"key":"sentence_variety","score":10,"evidence":"which shows that ..."}
],
"issues":[
  {"span":"There is many students","type":"语法","reason":"主谓不一致","suggestion":"There are many students"},
  {"span":"very important","type":"词汇","reason":"用词单一","suggestion":"crucial"}
],
"correction":"There are many students who ...",
"summary":"结构清楚,主谓一致有 1 处错误",
"score":78,
"error_summary":{"词汇":"用词单一","语法":"主谓不一致","表达优化":"","其他":""}}
```
''';

  group('rubric 选择映射', () {
    test('写作 → cet4_writing,维度是内容/组织/语言/词汇/句式', () {
      final rubric = writeReviewRubric(WriteReviewTaskType.writing);
      expect(rubric.id, 'cet4_writing');
      expect(rubric.type, 'writing');
      expect(rubric.dimensions.map((d) => d.key), [
        'content',
        'organization',
        'language',
        'vocabulary',
        'sentence_variety',
      ]);
      expect(rubric.totalScore, 100);
      expect(rubric.bands, isNotEmpty);
    });

    test('翻译 → cet4_translation,维度是理解/准确/通顺', () {
      final rubric = writeReviewRubric(WriteReviewTaskType.translation);
      expect(rubric.id, 'cet4_translation');
      expect(rubric.type, 'translation');
      expect(rubric.dimensions.map((d) => d.key), [
        'comprehension',
        'accuracy',
        'fluency',
      ]);
      expect(rubric.totalScore, 100);
    });

    test('两种类型都是"先依据后分数"的 ai_rubric 评分', () {
      for (final type in WriteReviewTaskType.values) {
        final rubric = writeReviewRubric(type);
        expect(rubric.scoringMode, ScoringMode.aiRubric);
        expect(rubric.dimensions.every((d) => d.hint.isNotEmpty), isTrue);
      }
    });
  });

  group('批改提示词', () {
    test('写作:同时含 rubric 维度与旧版字段,且带"先依据后分数"纪律', () {
      final prompt = buildWriteReviewPrompt(
        taskType: WriteReviewTaskType.writing,
        rubric: writeReviewRubric(WriteReviewTaskType.writing),
        userPrompt: '',
      );
      expect(prompt, contains('先依据、后分数'));
      expect(prompt, contains('dimensions'));
      expect(prompt, contains('内容切题'));
      expect(prompt, contains('旧版字段'));
      expect(prompt, contains('issues'));
      expect(prompt, contains('error_summary'));
      expect(prompt.contains('transcript'), isFalse,
          reason: '文本批改不要求识别原文(那是手写直批的字段)');
    });

    test('翻译:换成翻译维度(原文理解/译文准确/表达通顺)', () {
      final prompt = buildWriteReviewPrompt(
        taskType: WriteReviewTaskType.translation,
        rubric: writeReviewRubric(WriteReviewTaskType.translation),
        userPrompt: '',
      );
      expect(prompt, contains('原文理解'));
      expect(prompt, contains('译文准确'));
      expect(prompt, contains('表达通顺'));
      expect(prompt, contains('四六级翻译'));
    });

    test('用户在设置里改过提示词:原文保留,评分段追加在后', () {
      final custom = '请特别关注时态错误,并按我的格式批改。';
      final prompt = buildWriteReviewPrompt(
        taskType: WriteReviewTaskType.writing,
        rubric: writeReviewRubric(WriteReviewTaskType.writing),
        userPrompt: custom,
        userCustomized: true,
      );
      expect(prompt.startsWith(custom), isTrue);
      expect(prompt, contains('先依据、后分数'), reason: '自定义也要受 rubric 纪律约束');
    });

    test('没自定义时不会把设置里的默认提示词整段塞进来', () {
      final prompt = buildWriteReviewPrompt(
        taskType: WriteReviewTaskType.writing,
        rubric: writeReviewRubric(WriteReviewTaskType.writing),
        userPrompt: '不该出现的旧提示词',
        userCustomized: false,
      );
      expect(prompt.contains('不该出现的旧提示词'), isFalse);
    });

    test('手写直批:追加 transcript 要求(与旧直批行为一致)', () {
      final prompt = buildWriteReviewPrompt(
        taskType: WriteReviewTaskType.writing,
        rubric: writeReviewRubric(WriteReviewTaskType.writing),
        userPrompt: '',
        imageCount: 2,
      );
      expect(prompt, contains('手写稿照片'));
      expect(prompt, contains('transcript'));
      expect(writeReviewHandwrittenSuffix(1), contains('一张'));
      expect(writeReviewHandwrittenSuffix(3), contains('3 张'));
    });
  });

  group('评分解析:成功路径', () {
    test('维度分相加得总分,档位由本地 rubric 折算(不信任模型自报)', () {
      final scored = parseWriteReviewRubric(
        writingJson,
        taskType: WriteReviewTaskType.writing,
      );
      expect(scored, isNotNull);
      expect(scored!.totalScore, 78);
      expect(scored.ratedDimensionCount, 5);
      expect(scored.dimensions.every((d) => d.hasEvidence), isTrue);
      expect(scored.issues.length, 2);
      expect(scored.correction, contains('There are many students'));
      expect(scored.bandLabel, '良好', reason: '78 分落在 75~90 良好档');
    });

    test('解析围栏/前置说明不影响(extractJsonObject 容错)', () {
      final scored = parseWriteReviewRubric(
        '好的,以下是评分:\n$writingJson\n以上。',
        taskType: WriteReviewTaskType.writing,
      );
      expect(scored, isNotNull);
    });

    test('部分维度没给分:只加已评维度,没评的显示"未评"而不是 0', () {
      const partial = '{"dimensions":[{"key":"content","score":20,'
          '"evidence":"First"}],"issues":[],"summary":"s"}';
      final scored = parseWriteReviewRubric(
        partial,
        taskType: WriteReviewTaskType.writing,
      );
      expect(scored, isNotNull);
      expect(scored!.totalScore, 20);
      expect(scored.dimensions.firstWhere((d) => d.key == 'organization').isScored,
          isFalse);
    });
  });

  group('评分解析:失败与回退路径', () {
    test('非 JSON → rubric 解析 null', () {
      expect(
        parseWriteReviewRubric('这不是 JSON', taskType: WriteReviewTaskType.writing),
        isNull,
      );
    });

    test('旧版 JSON(只有 score 没有 dimensions)→ rubric null,旧解析可用 = 可回退', () {
      const legacy = '{"score":80,"correction":"fixed text","summary":"不错",'
          '"issues":[{"original":"a","correction":"b","type":"语法","reason":"r"}],'
          '"error_summary":{"词汇":"","语法":"主谓","表达优化":"","其他":""}}';
      expect(
        parseWriteReviewRubric(legacy, taskType: WriteReviewTaskType.writing),
        isNull,
        reason: '没有维度分不能硬算 rubric',
      );
      final fallback = DoubaoApiService.parseWritingReview(legacy);
      expect(fallback.isEmpty, isFalse, reason: '旧解析必须能接住,页面不白屏');
      expect(fallback['score'], '80');
      expect(fallback['correction'], 'fixed text');
      expect((fallback['issues'] as List).length, 1);
    });

    test('损坏 JSON → 两套解析都空(调用方走错误态,不会白屏)', () {
      const broken = '{"score":80,"correction":';
      expect(
        parseWriteReviewRubric(broken, taskType: WriteReviewTaskType.writing),
        isNull,
      );
      expect(DoubaoApiService.parseWritingReview(broken), isEmpty);
    });
  });

  group('旧结构映射(结果页/错误档案继续可用)', () {
    late ScoredOutput scored;

    setUp(() {
      scored = parseWriteReviewRubric(
        writingJson,
        taskType: WriteReviewTaskType.writing,
      )!;
    });

    test('issues 映射回 {original, correction, type, reason}', () {
      final issues = legacyIssuesFromScored(scored);
      expect(issues.length, 2);
      expect(issues.first['original'], 'There is many students');
      expect(issues.first['correction'], 'There are many students');
      expect(issues.first['type'], '语法');
      expect(issues.first['reason'], '主谓不一致');
    });

    test('错误四类汇总:rubric 的问题类型能归进旧四类', () {
      final summary = errorSummaryFromScored(scored);
      expect(summary.keys.toList(), ['词汇', '语法', '表达优化', '其他']);
      expect(summary['语法'], contains('主谓'));
      expect(summary['词汇'], contains('用词单一'));
    });
  });

  group('折算档位与 score_json 并入', () {
    test('100 分制 → 四六级官方档位', () {
      final rubric = writeReviewRubric(WriteReviewTaskType.writing);
      const top = ScoredOutput(
        totalScore: 95,
        bandLabel: '',
        dimensions: <ScoredDimension>[],
      );
      expect(writeReviewConvertedBand(top, rubric)?.label, '优秀');
      const mid = ScoredOutput(
        totalScore: 85,
        bandLabel: '',
        dimensions: <ScoredDimension>[],
      );
      expect(writeReviewConvertedBand(mid, rubric)?.label, '良好');

      final translation = writeReviewRubric(WriteReviewTaskType.translation);
      const low = ScoredOutput(
        totalScore: 72,
        bandLabel: '',
        dimensions: <ScoredDimension>[],
      );
      expect(writeReviewConvertedBand(low, translation)?.label, '及格');
    });

    test('score_json 并入 rubric_id/dimensions/band,旧键不被覆盖', () {
      final scored = parseWriteReviewRubric(
        writingJson,
        taskType: WriteReviewTaskType.writing,
      )!;
      final merged = mergeRubricIntoScoreJson(
        existing: const {'score': '80', 'legacy_key': 1},
        scored: scored,
        rubric: writeReviewRubric(WriteReviewTaskType.writing),
      );
      expect(merged['score'], '80', reason: '旧键优先,不被覆盖');
      expect(merged['legacy_key'], 1);
      expect(merged['rubric_id'], 'cet4_writing');
      expect(merged['dimensions'], isA<List<dynamic>>());
      expect((merged['dimensions'] as List).length, 5);
      expect(merged['band'], isA<Map<dynamic, dynamic>>());
      expect((merged['band'] as Map)['label'], '良好');
      expect(merged['total_score'], 78);
    });

    test('没有旧 score_json 时也能新建一份完整载荷', () {
      final scored = parseWriteReviewRubric(
        writingJson,
        taskType: WriteReviewTaskType.writing,
      )!;
      final merged = mergeRubricIntoScoreJson(
        scored: scored,
        rubric: writeReviewRubric(WriteReviewTaskType.writing),
      );
      expect(merged['rubric_id'], 'cet4_writing');
      expect(merged['issues'], isA<List<dynamic>>());
      expect(merged['summary'], '结构清楚,主谓一致有 1 处错误');
    });
  });
}
