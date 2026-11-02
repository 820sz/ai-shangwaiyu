import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/placement_bank.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/placement_diagnosis.dart';

/// E1-10「语法诊断分项」：
/// ① 纯函数选取口径（只记错题、按考点去重、证据是题干、未作答不记）；
/// ② 真 SQLite 写入口径（source='placement'、tag=考点、count 累加、证据保留）。
///
/// 为什么两部分都要：纯函数决定"记哪些"，数据库决定"记成什么样"；
/// 只测一边都可能出现"界面说已建档、错误档案里却查不到"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('语法错题 → 分项（纯函数）', () {
    const q = [
      ChoiceQuestion(
        prompt: 'I ______ here for ten years.',
        options: ['live', 'lived', 'have lived', 'living'],
        answerIndex: 2,
        explanation: 'for + 时间段 → 现在完成时',
        tag: '时态',
      ),
      ChoiceQuestion(
        prompt: 'She is ______ honest person.',
        options: ['a', 'an', 'the', '不填'],
        answerIndex: 1,
        explanation: 'honest 首音是元音 → an',
        tag: '冠词',
      ),
      ChoiceQuestion(
        prompt: 'Neither A nor B ______ ready.',
        options: ['was', 'were', 'is', 'has'],
        answerIndex: 1,
        explanation: '就近原则',
        tag: '主谓一致',
      ),
    ];

    test('全对 → 没有任何分项（不给人凭空扣薄弱点）', () {
      final tags = grammarErrorTags(questions: q, answers: const [2, 1, 1]);
      expect(tags, isEmpty);
    });

    test('全错 → 每个考点各一条，证据是题干，顺序按题目顺序', () {
      final tags = grammarErrorTags(questions: q, answers: const [0, 0, 0]);
      expect(tags.keys.toList(), ['时态', '冠词', '主谓一致']);
      expect(tags['时态'], q[0].prompt);
      expect(tags['冠词'], q[1].prompt);
      expect(tags['主谓一致'], q[2].prompt);
    });

    test('同一考点错两题只记一次，证据取第一道错题（不按题数刷计数）', () {
      const duplicate = [
        ChoiceQuestion(
          prompt: '第一道时态题',
          options: ['a', 'b'],
          answerIndex: 0,
          explanation: '',
          tag: '时态',
        ),
        ChoiceQuestion(
          prompt: '第二道时态题',
          options: ['a', 'b'],
          answerIndex: 1,
          explanation: '',
          tag: '时态',
        ),
      ];
      final tags = grammarErrorTags(questions: duplicate, answers: const [1, 0]);
      expect(tags.length, 1);
      expect(tags['时态'], '第一道时态题');
    });

    test('未作答（null）不记为薄弱点；答案数组比题短也不崩', () {
      final tags = grammarErrorTags(questions: q, answers: const [null, 1]);
      expect(tags, isEmpty);
    });

    test('内置题库：5 个语法考点标签齐全，错题能映射成中文分项', () {
      expect(
        kGrammarQuestions.map((e) => e.tag).toList(),
        ['时态', '冠词', '介词', '主谓一致', '虚拟语气'],
      );
      // 只错"冠词"和"虚拟语气"两题（真实题库答案下标 1 / 2）
      final answers = <int?>[
        kGrammarQuestions[0].answerIndex,
        0, // 冠词题错
        kGrammarQuestions[2].answerIndex,
        kGrammarQuestions[3].answerIndex,
        0, // 虚拟语气题错
      ];
      final tags = grammarErrorTags(
        questions: kGrammarQuestions,
        answers: answers,
      );
      expect(tags.keys.toList(), ['冠词', '虚拟语气']);
      expect(tags['冠词'], kGrammarQuestions[1].prompt);
    });
  });

  group('分项写入错误档案（真 SQLite）', () {
    late Directory tmp;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rf_placement_tags_test');
      await databaseFactory.setDatabasesPath(tmp.path);
      await DatabaseService.resetForTest();
    });

    tearDown(() async {
      await DatabaseService.resetForTest();
      try {
        await databaseFactory.deleteDatabase(p.join(tmp.path, AppConstants.dbName));
      } catch (_) {
        // 临时库可能还没建出来:清理失败不影响断言结果
      }
      try {
        await tmp.delete(recursive: true);
      } catch (_) {
        // Windows 上句柄释放可能慢一拍:忽略
      }
    });

    test('按分项 tag 写入：source=placement、count=1、证据=题干', () async {
      // 第 1 题对、第 2 题错(冠词)、第 4 题错(主谓一致)、第 5 题错(虚拟语气)
      final answers = <int?>[
        kGrammarQuestions[0].answerIndex,
        0,
        kGrammarQuestions[2].answerIndex,
        0,
        0,
      ];
      final tags = grammarErrorTags(
        questions: kGrammarQuestions,
        answers: answers,
      );
      expect(tags.keys.toList(), ['冠词', '主谓一致', '虚拟语气']);

      // 与屏幕里 _recordGrammarTags 完全相同的写入方式
      for (final entry in tags.entries) {
        await DatabaseService.bumpErrorTag(
          source: 'placement',
          tag: entry.key,
          evidence: entry.value,
        );
      }

      final rows = await DatabaseService.getErrorTags(status: 'active');
      final placementRows =
          rows.where((r) => r['source'] == 'placement').toList();
      expect(placementRows.length, 3);
      expect(
        placementRows.map((r) => r['tag']).toSet(),
        {'冠词', '主谓一致', '虚拟语气'},
      );
      for (final row in placementRows) {
        expect((row['count'] as num).toInt(), 1);
        final tag = '${row['tag']}';
        expect(row['evidence'], kGrammarQuestions.firstWhere((q) => q.tag == tag).prompt);
      }

      // 不是只存一个 grammar_score:同一份作答里"语法"这个词条不存在
      expect(placementRows.any((r) => r['tag'] == '语法'), isFalse);
    });

    test('同一考点第二次再错：count 累加而不是新增一行（复发可追踪）', () async {
      await DatabaseService.bumpErrorTag(
        source: 'placement',
        tag: '时态',
        evidence: kGrammarQuestions[0].prompt,
      );
      await DatabaseService.bumpErrorTag(
        source: 'placement',
        tag: '时态',
        evidence: kGrammarQuestions[0].prompt,
      );
      final rows = asyncRows(await DatabaseService.getErrorTags());
      final tense = rows.where(
        (r) => r['source'] == 'placement' && r['tag'] == '时态',
      );
      expect(tense.length, 1);
      expect((tense.single['count'] as num).toInt(), 2);
      expect(tense.single['status'], 'active');
    });
  });
}

/// 小工具：把查询结果保持为可迭代的 List（避免上面测试里重复写类型）
List<Map<String, Object?>> asyncRows(List<Map<String, Object?>> rows) => rows;
