import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/output_rubric.dart';

/// 输出模块 · 评分标准层测试(批 3 · P2)。
///
/// 覆盖(用户点名要盯的三条):
/// 1. 4 套内置 rubric 与数据库 seed 同口径(id/权重/满分/分档);
/// 2. 评分提示词必须"**先给依据项再给分**",且明确禁止无依据打分;
/// 3. 解析全容错(围栏/夹带说明/坏 JSON/分值越界/维度缺失),
///    **解析失败返回 null 不抛** —— 不能因为模型多说一句话就打崩批改页。
///
/// 纯函数测试,不联网、不读 Hive。
void main() {
  // ── 测试夹具:一份"合规"的模型评分输出 ──────────────────────────────
  const goodScoring = '''
{"dimensions":[
  {"key":"content","score":22,"evidence":"First, online courses save time."},
  {"key":"organization","score":17,"evidence":"First ... Second ..."},
  {"key":"language","score":20,"evidence":"students can learns -> 错误"},
  {"key":"vocabulary","score":11,"evidence":"save time / convenient"},
  {"key":"sentence_variety","score":10,"evidence":"First...; What is more..."}
],
"issues":[{"span":"students can learns","type":"语法","reason":"情态动词后应用动词原形",
"suggestion":"students can learn"}],
"correction":"First, online courses save time. Second, students can learn anywhere.",
"summary":"内容切题、结构清楚;语言有 2 处主谓一致错误,词汇与句式基本够用。"}
''';

  group('ScoringMode.parse', () {
    test('三种数据库取值都能解析;未知值回落 aiRubric', () {
      expect(ScoringMode.parse('objective'), ScoringMode.objective);
      expect(ScoringMode.parse('ai_rubric'), ScoringMode.aiRubric);
      expect(ScoringMode.parse('manual'), ScoringMode.manual);
      expect(ScoringMode.parse('什么鬼'), ScoringMode.aiRubric);
      expect(ScoringMode.parse(null), ScoringMode.aiRubric);
    });
  });

  group('内置 rubric(与数据库 seed 同一口径)', () {
    test('恰好 6 套(2026-11-07 补六级),id 与 DB seed 一致', () {
      final builtin = OutputRubric.builtin();
      expect(builtin, hasLength(6));
      expect(
        builtin.map((r) => r.id).toList(),
        <String>[
          'cet4_writing',
          'cet4_translation',
          'back_translation',
          'summary',
          'cet6_writing',
          'cet6_translation',
        ],
        reason: 'id 必须与 exercise_sets.rubric_id / rubrics seed 对齐',
      );
      for (final rubric in builtin) {
        expect(OutputRubric.byId(rubric.id)?.id, rubric.id);
      }
      expect(OutputRubric.byId('不存在的'), isNull);
    });

    test('每套:维度权重和为 1、满分和为 100、维度 key 不重复', () {
      for (final rubric in OutputRubric.builtin()) {
        expect(rubric.dimensions, isNotEmpty, reason: '${rubric.id} 没有维度');
        expect(
          rubric.weightSum,
          closeTo(1.0, 1e-9),
          reason: '${rubric.id} 权重和应为 1(实际 ${rubric.weightSum})',
        );
        expect(
          rubric.totalScore,
          closeTo(100, 1e-9),
          reason: '${rubric.id} 满分和应为 100(实际 ${rubric.totalScore})',
        );
        final keys = rubric.dimensions.map((d) => d.key).toList();
        expect(
          keys.toSet().length,
          keys.length,
          reason: '${rubric.id} 维度 key 重复',
        );
        for (final dimension in rubric.dimensions) {
          expect(dimension.label, isNotEmpty, reason: '维度必须有中文名');
          expect(dimension.hint, isNotEmpty, reason: '维度必须有评分提示(写进提示词)');
        }
        expect(rubric.bands, isNotEmpty, reason: '${rubric.id} 没有分档');
        expect(rubric.scoringMode, ScoringMode.aiRubric);
        expect(rubric.promptTemplate, isNotEmpty);
      }
    });

    test('分档从高到低、覆盖 0~100(最高档含 100)', () {
      for (final rubric in OutputRubric.builtin()) {
        expect(rubric.bands.first.minScore, greaterThanOrEqualTo(90));
        expect(rubric.bands.last.minScore, 0);
        expect(bandOf(100, rubric.bands)?.label, isNotEmpty);
        expect(bandOf(0, rubric.bands)?.label, isNotEmpty);
      }
    });
  });

  group('fromJson / toJson 容错', () {
    test('合法 JSON 往返不丢字段', () {
      final original = OutputRubric.builtin().first;
      final restored = OutputRubric.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, original.id);
      expect(restored.type, original.type);
      expect(restored.scoringMode, original.scoringMode);
      expect(restored.dimensions, hasLength(original.dimensions.length));
      expect(restored.dimensions.first.key, original.dimensions.first.key);
      expect(restored.weightSum, closeTo(1.0, 1e-9));
    });

    test('脏数据:缺字段/类型不对/坏维度 → 容错不抛', () {
      final rubric = OutputRubric.fromJson(<String, dynamic>{
        'id': 'dirty_rubric',
        'type': 123, // 类型不对
        'scoring_mode': null,
        'dimensions': <dynamic>[
          <String, dynamic>{
            'key': 'a',
            'label': '维度A',
            'weight': '0.5',
            'max_score': '50',
            'hint': null,
          },
          <String, dynamic>{'key': '', 'label': '无 key 会被跳过'},
          'not-a-map',
        ],
      });
      expect(rubric, isNotNull);
      expect(rubric!.id, 'dirty_rubric');
      expect(rubric.scoringMode, ScoringMode.aiRubric);
      expect(rubric.dimensions, hasLength(1));
      expect(rubric.dimensions.first.weight, closeTo(0.5, 1e-9));
      expect(rubric.dimensions.first.maxScore, closeTo(50, 1e-9));
    });

    test('没有 id / 维度全坏 → null(这条 rubric 不可用)', () {
      expect(OutputRubric.fromJson(const <String, dynamic>{}), isNull);
      expect(OutputRubric.fromJson(null), isNull);
      expect(
        OutputRubric.fromJson(<String, dynamic>{
          'id': 'x',
          'dimensions': 'oops',
        }),
        isNull,
      );
    });

    test('RubricBand.fromJson 容错:坏区间/空 label 跳过', () {
      expect(RubricBand.fromJson(null), isNull);
      expect(RubricBand.fromJson(<String, dynamic>{'min_score': 10}), isNull);
      expect(
        RubricBand.fromJson(<String, dynamic>{
          'min_score': 90,
          'max_score': 100,
          'label': '优秀',
        })?.label,
        '优秀',
      );
    });
  });

  group('clampScore:分数归一', () {
    test('null / 解析不出 → null(不是 0)', () {
      expect(clampScore(null, 25), isNull);
      expect(clampScore('无', 25), isNull);
      expect(clampScore('', 25), isNull);
    });

    test('越界 clamp、字符串抠数字、保留 1 位小数', () {
      expect(clampScore(30, 25), 25);
      expect(clampScore(-5, 25), 0);
      expect(clampScore('22分', 25), 22);
      expect(clampScore('22/25', 25), 22);
      expect(clampScore(22.333, 25), closeTo(22.3, 1e-9));
      expect(clampScore(22.36, 25), closeTo(22.4, 1e-9));
    });
  });

  group('bandOf:总分 → 档位', () {
    final bands = OutputRubric.builtin().first.bands;

    test('100 落最高档(最高档包含上限)、边界值正确', () {
      expect(bandOf(100, bands)!.label, '优秀');
      expect(bandOf(90, bands)!.label, '优秀');
      expect(bandOf(89.9, bands)!.label, '良好');
      expect(bandOf(75, bands)!.label, '良好');
      expect(bandOf(74.9, bands)!.label, '及格');
      expect(bandOf(60, bands)!.label, '及格');
      expect(bandOf(59.9, bands)!.label, '待提高');
      expect(bandOf(0, bands)!.label, '待提高');
    });

    test('band 列表为空 → null;乱序也安全', () {
      expect(bandOf(80, const <RubricBand>[]), isNull);
      final messy = <RubricBand>[
        const RubricBand(minScore: 0, maxScore: 60, label: '低'),
        const RubricBand(minScore: 60, maxScore: 100, label: '高'),
      ];
      expect(bandOf(80, messy)?.label, '高');
    });
  });

  group('buildScoringPrompt:先依据后分数', () {
    test('包含题目/作答/全部维度/总分,且写明"先依据、后分数"硬约束', () {
      final rubric = OutputRubric.builtin().first;
      final prompt = buildScoringPrompt(
        rubric: rubric,
        task: 'Write a short essay about online learning.',
        answer: 'First, online courses save time.',
        notes: '这是四六级写作练习',
      );
      for (final dimension in rubric.dimensions) {
        expect(
          prompt.contains(dimension.label),
          isTrue,
          reason: '提示词缺维度 ${dimension.label}',
        );
        expect(
          prompt.contains(dimension.key),
          isTrue,
          reason: '提示词缺维度 key ${dimension.key}',
        );
        expect(
          prompt.contains('${dimension.maxScore.round()}'),
          isTrue,
          reason: '提示词缺维度满分',
        );
      }
      expect(prompt, contains('先依据、后分数'));
      expect(prompt, contains('evidence'));
      expect(prompt, contains('禁止无依据打分'));
      expect(prompt, contains('Write a short essay about online learning.'));
      expect(prompt, contains('First, online courses save time.'));
      expect(prompt, contains('这是四六级写作练习'));
      expect(prompt, contains('只输出 JSON'));
    });

    test('没有题目/没有补充说明时也能生成可用提示词', () {
      final prompt = buildScoringPrompt(
        rubric: OutputRubric.byId('summary')!,
        task: '',
        answer: 'The article mainly discusses AI.',
      );
      expect(prompt, contains('(未提供题目要求)'));
      expect(prompt, contains('The article mainly discusses AI.'));
      expect(prompt, contains('要点覆盖')); // summary rubric 的维度
    });
  });

  group('parseScoringResult:解析容错', () {
    final rubric = OutputRubric.builtin().first;

    test('正常 JSON:维度分/依据/issues/correction/summary 全部解析', () {
      final result = parseScoringResult(goodScoring, rubric: rubric);
      expect(result, isNotNull);
      expect(result!.dimensions, hasLength(rubric.dimensions.length));
      expect(result.dimensions.first.score, 22);
      expect(result.dimensions.first.evidence, contains('online courses'));
      // 总分 = 各维度分相加(22+17+20+11+10 = 80),档位由此计算
      expect(result.totalScore, 80);
      expect(result.bandLabel, '良好');
      expect(result.issues, hasLength(1));
      expect(result.issues.first.type, '语法');
      expect(result.issues.first.span, contains('students can learns'));
      expect(result.correction, isNotNull);
      expect(result.summary, contains('内容切题'));
      expect(result.ratedDimensionCount, 5);
    });

    test('```json 围栏 + 前置说明也能解析', () {
      final wrapped = '好的,我来评分:\n```json\n$goodScoring\n```\n以上。';
      final result = parseScoringResult(wrapped, rubric: rubric);
      expect(result, isNotNull);
      expect(result!.totalScore, 80);
    });

    test('坏 JSON / 空内容 / JSON 数组 → null(不抛)', () {
      expect(parseScoringResult('', rubric: rubric), isNull);
      expect(parseScoringResult('模型说了一堆话但没有 JSON', rubric: rubric), isNull);
      expect(parseScoringResult('{"broken": ', rubric: rubric), isNull);
      expect(parseScoringResult('[{"score":1}]', rubric: rubric), isNull);
    });

    test('总分会 clamp 到 rubric 满分;极端分值不虚高', () {
      final inflated = jsonEncode(<String, dynamic>{
        'dimensions': <dynamic>[
          for (final d in rubric.dimensions)
            <String, dynamic>{'key': d.key, 'score': 999, 'evidence': 'x'},
        ],
      });
      final result = parseScoringResult(inflated, rubric: rubric);
      expect(result, isNotNull);
      // 每维先 clamp 到自己的满分,再求和 → 不可能超过 100
      expect(result!.totalScore, closeTo(100, 1e-9));
      expect(result.dimensions.every((d) => d.score! <= d.maxScore), isTrue);
    });

    test('维度缺失:缺的维度 score=null(不编 0 分),总分只算已给维度', () {
      final partial = jsonEncode(<String, dynamic>{
        'dimensions': <dynamic>[
          <String, dynamic>{'key': 'content', 'score': 20, 'evidence': 'e1'},
          <String, dynamic>{'key': 'language', 'score': 18, 'evidence': 'e2'},
        ],
        'summary': '只有两维',
      });
      final result = parseScoringResult(partial, rubric: rubric);
      expect(result, isNotNull);
      expect(result!.totalScore, 38);
      expect(result.ratedDimensionCount, 2);
      final missing = result.dimensions.where((d) => !d.isScored).toList();
      expect(missing, hasLength(rubric.dimensions.length - 2));
      expect(missing.first.score, isNull);
    });

    test('模型给的维度 key 完全对不上 rubric → null(等于没评)', () {
      final wrongKeys = jsonEncode(<String, dynamic>{
        'dimensions': <dynamic>[
          <String, dynamic>{'key': 'fluency', 'score': 30, 'evidence': 'e'},
          <String, dynamic>{'key': 'coherence', 'score': 20, 'evidence': 'e'},
        ],
      });
      expect(parseScoringResult(wrongKeys, rubric: rubric), isNull);
    });

    test('字符串分数/越界分数被容错处理', () {
      final dirty = jsonEncode(<String, dynamic>{
        'dimensions': <dynamic>[
          <String, dynamic>{'key': 'content', 'score': '22分', 'evidence': 'e'},
          <String, dynamic>{
            'key': 'organization',
            'score': 999,
            'evidence': 'e',
          },
          <String, dynamic>{'key': 'language', 'score': 'bad', 'evidence': 'e'},
        ],
      });
      final result = parseScoringResult(dirty, rubric: rubric);
      expect(result, isNotNull);
      expect(result!.dimensions[0].score, 22);
      expect(result.dimensions[1].score, 20, reason: '越界要 clamp 到该维度满分');
      expect(result.dimensions[2].score, isNull, reason: '解析不出 → 未评');
    });

    test('issues 脏数据跳过;correction 空串 → null', () {
      final dirty = jsonEncode(<String, dynamic>{
        'dimensions': <dynamic>[
          <String, dynamic>{'key': 'content', 'score': 10, 'evidence': 'e'},
        ],
        'issues': <dynamic>[
          'not-a-map',
          <String, dynamic>{},
          <String, dynamic>{
            'span': 'bad sentence',
            'type': '语法',
            'reason': '主谓不一致',
            'suggestion': 'fix',
          },
        ],
        'correction': '   ',
      });
      final result = parseScoringResult(dirty, rubric: rubric);
      expect(result, isNotNull);
      expect(result!.issues, hasLength(1));
      expect(result.correction, isNull);
    });

    test('ScoredOutput.toJson 可直接入库(score_json)', () {
      final result = parseScoringResult(goodScoring, rubric: rubric)!;
      final json = result.toJson();
      expect(json['total_score'], 80);
      expect(json['band_label'], '良好');
      expect(json['dimensions'], isA<List<dynamic>>());
      expect(json['issues'], isA<List<dynamic>>());
      expect(json['summary'], isNotEmpty);
    });
  });
}
