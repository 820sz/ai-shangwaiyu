/// W4 · 输出「rubric 分级」验收测试(2026-11-07 真机反馈第 6 条第 2 点)。
///
/// 钉死三件事:
/// 1. **六级 → 六级 rubric**(cet6_writing / cet6_translation),不再借 cet4_*;
/// 2. **UI 只显示中文名**(绝不把 `cet4_writing` 这种 id 打到界面);
/// 3. 数据库 seed **幂等**(老库开库即补、重复执行安全)。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/output_bank.dart';
import 'package:readflow/services/output_composer.dart';
import 'package:readflow/services/output_rubric.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_cet6_rubric');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    await Hive.close();
    try {
      await databaseFactory
          .deleteDatabase('${tmp.path}/${AppConstants.dbName}');
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('rubric 选择 · 等级优先', () {
    test('cet6 → cet6_writing / cet6_translation', () {
      expect(
        OutputRubric.rubricIdFor(examType: 'cet6', kind: 'writing'),
        'cet6_writing',
      );
      expect(
        OutputRubric.rubricIdFor(examType: 'cet6', kind: 'translation'),
        'cet6_translation',
      );
    });

    test('非六级沿用通用四级口径(不虚构等级标准)', () {
      for (final exam in <String>['cet4', 'kaoyan', 'ielts', 'toefl', 'none']) {
        expect(
          OutputRubric.rubricIdFor(examType: exam, kind: 'writing'),
          'cet4_writing',
          reason: '$exam 暂无独立写作维度,应回退通用口径',
        );
      }
    });

    test('老数据纠正:六级题存了 cet4_writing → 解析成 cet6_writing', () {
      final rubric = OutputRubric.resolveFor(
        rubricId: 'cet4_writing',
        examType: 'cet6',
      );
      expect(rubric?.id, 'cet6_writing');
      expect(rubric?.dimensions.length, 5);
    });

    test('没有 rubricId 时按题型推:翻译 → 翻译标准、回译 → 回译标准', () {
      expect(
        OutputRubric.resolveFor(
          examType: 'cet6',
          taskType: 'exam_translation',
        )?.id,
        'cet6_translation',
      );
      expect(
        OutputRubric.resolveFor(
          examType: 'cet6',
          taskType: 'back_translation',
        )?.id,
        'back_translation',
      );
      expect(
        OutputRubric.resolveFor(taskType: 'summary')?.id,
        'summary',
      );
    });
  });

  group('rubric 中文显示名', () {
    test('四个等级 rubric 都有中文名', () {
      expect(OutputRubric.displayNameOf('cet4_writing'), '四级写作评分标准');
      expect(OutputRubric.displayNameOf('cet6_writing'), '六级写作评分标准');
      expect(OutputRubric.displayNameOf('cet6_translation'), '六级翻译评分标准');
      expect(OutputRubric.displayNameOf('summary'), '摘要评分标准');
    });

    test('未知 id 不把裸 id 显示给用户', () {
      final name = OutputRubric.displayNameOf('custom_xxx');
      expect(name, isNot(contains('custom_xxx')));
      expect(name, '评分标准');
    });
  });

  group('出题链路按等级落 rubric', () {
    test('真题解析:cet6 写作/翻译都用六级标准', () {
      const json = '{"tasks":[{"prompt_zh":"写一篇关于校园生活的短文",'
          '"reference":"","word_count":120,"hint":"先定结构"}]}';
      final writing = parseExamWritingTasks(
        json,
        examType: 'cet6',
        section: 'writing',
        sourceUrls: const <String>['https://example.com/cet6-2023'],
      );
      expect(writing, isNotEmpty);
      expect(writing.first.rubricId, 'cet6_writing');

      final translation = parseExamWritingTasks(
        '{"tasks":[{"prompt_zh":"将下面段落译成英文","reference":""}]}',
        examType: 'cet6',
        section: 'translation',
        sourceUrls: const <String>['https://example.com/cet6-tr'],
      );
      expect(translation.first.rubricId, 'cet6_translation');
    });

    test('内置作文题:cet6 时题组与题目都落 cet6_writing', () {
      final prompts = OutputBank.essayPrompts.take(1).toList();
      final set = OutputBank.buildEssaySet(
        prompts: prompts,
        examType: 'cet6',
      );
      expect(set.examType, 'cet6');
      expect(set.rubricId, 'cet6_writing');
      expect(set.tasks.first.rubricId, 'cet6_writing');

      // 不传等级时保持原行为(通用四级口径)
      final plain = OutputBank.buildEssaySet(prompts: prompts);
      expect(plain.tasks.first.rubricId, startsWith('cet4_'));
    });
  });

  group('ScoredOutput 可反序列化(草稿恢复用)', () {
    test('toJson → fromJson 往返', () {
      const scored = ScoredOutput(
        totalScore: 78,
        bandLabel: '良好',
        dimensions: <ScoredDimension>[
          ScoredDimension(
            key: 'content',
            label: '内容切题',
            maxScore: 40,
            score: 33,
            evidence: '原文依据',
          ),
          ScoredDimension(key: 'language', label: '语言准确', maxScore: 40),
        ],
        issues: <ScoredIssue>[
          ScoredIssue(span: 'is benefit for', type: '用词', reason: '应为 beneficial'),
        ],
        correction: 'It is beneficial.',
        summary: '整体不错。',
      );
      final restored = ScoredOutput.fromJson(scored.toJson());
      expect(restored, isNotNull);
      expect(restored!.totalScore, 78);
      expect(restored.bandLabel, '良好');
      expect(restored.dimensions.length, 2);
      expect(restored.dimensions[1].isScored, isFalse, reason: '未评维度不能变成 0 分');
      expect(restored.issues.single.type, '用词');
      expect(restored.correction, 'It is beneficial.');
    });

    test('坏 JSON / 缺总分 → null(不抛)', () {
      expect(ScoredOutput.fromJson('not-json'), isNull);
      expect(ScoredOutput.fromJson(<String, Object?>{'band_label': 'x'}), isNull);
      expect(ScoredOutput.fromJson(null), isNull);
    });
  });

  group('数据库 rubric seed · 幂等补六级', () {
    test('开库即有六级 rubric;重复 seed 不重复/不覆盖', () async {
      // 首次打开会走自检 seed
      var rubrics = await DatabaseService.listRubrics();
      final ids = rubrics.map((r) => '${r['id']}').toSet();
      expect(ids.contains('cet6_writing'), isTrue);
      expect(ids.contains('cet6_translation'), isTrue);
      final countAfterFirst = rubrics.length;

      // 再触发一次自检(断开连接后重新打开):数量不变、内容不重复
      await DatabaseService.resetForTest();
      rubrics = await DatabaseService.listRubrics();
      expect(rubrics.length, countAfterFirst);

      final cet6 = rubrics.firstWhere((r) => '${r['id']}' == 'cet6_writing');
      expect('${cet6['type']}', 'writing');
      final dims = '${cet6['dimensions_json']}';
      expect(dims.contains('内容切题'), isTrue);
      expect(dims.contains('句式多样'), isTrue);
    });
  });
}
