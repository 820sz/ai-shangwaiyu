/// W4 · 练习草稿(退出留存/继续上次练习)验收测试。
///
/// 用户 2026-11-07 真机反馈第 6 条第 4 点:练习材料退出不留存、下次重新找。
/// 草稿 = 题组 id + 当前题号 + 每题未提交文本(Hive 单行 JSON);
/// 已批改结果仍以 `output_attempts.score_json` 为权威,不重复存。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/output_draft.dart';
import 'package:readflow/services/output_rubric.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_output_draft');
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

  OutputDraft sample({int index = 1, Map<int, String>? texts}) => OutputDraft(
        setId: 42,
        title: '英语六级(CET-6) · 2023 年 12 月第 1 套 · 写作真题',
        index: index,
        texts: texts ?? <int, String>{0: '第一题的草稿', 2: '第三题写了一半'},
        updatedAt: DateTime.parse('2026-11-07T10:00:00'),
      );

  test('保存 → 读取:题组/题号/每题文本都回来', () async {
    await OutputDraftStore.save(sample());
    final loaded = OutputDraftStore.load();
    expect(loaded, isNotNull);
    expect(loaded!.setId, 42);
    expect(loaded.index, 1);
    expect(loaded.texts[0], '第一题的草稿');
    expect(loaded.texts[2], '第三题写了一半');
    expect(loaded.title, contains('CET-6'));
    expect(loaded.answeredCount, 2);
  });

  test('重复保存是整份覆盖(不残留旧题文本)', () async {
    await OutputDraftStore.save(sample());
    await OutputDraftStore.save(sample(index: 3, texts: <int, String>{3: '只写了第四题'}));
    final loaded = OutputDraftStore.load();
    expect(loaded!.index, 3);
    expect(loaded.texts.length, 1);
    expect(loaded.texts.containsKey(0), isFalse);
  });

  test('清草稿 → load 返回 null(完成/放弃练习)', () async {
    await OutputDraftStore.save(sample());
    await OutputDraftStore.clear();
    expect(OutputDraftStore.load(), isNull);
  });

  test('坏数据/空文本容错:不抛、空文本不占题号', () async {
    expect(OutputDraft.fromJson('not-json'), isNull);
    expect(OutputDraft.fromJson(<String, Object?>{}), isNull);
    final parsed = OutputDraft.fromJson(<String, Object?>{
      'set_id': 7,
      'title': 't',
      'index': 99,
      'texts': <String, String>{'0': '  ', '1': '有内容'},
      'updated_at': '2026-11-07T10:00:00',
    });
    expect(parsed, isNotNull);
    expect(parsed!.texts.containsKey(0), isFalse, reason: '纯空白草稿不占题号');
    expect(parsed.texts[1], '有内容');
    expect(parsed.index, 99);
  });

  test('题号越界由调用方夹取(loadResumablePractice 侧)且 copyWith 刷新时间', () {
    final draft = sample(index: 5);
    final clamped = draft.copyWith(index: 0);
    expect(clamped.index, 0);
    expect(clamped.setId, draft.setId);
    expect(clamped.texts, draft.texts);
  });

  test('题型 → 四阶(草稿恢复与题库重练同口径)', () {
    expect(
      outputTierOfItem(section: 'writing', type: 'exam_writing').id,
      'essay',
    );
    expect(
      outputTierOfItem(section: 'back_translation', type: 'back_translation').id,
      'sentence',
    );
    expect(
      outputTierOfItem(section: 'writing', type: 'summary').id,
      'paragraph',
    );
    expect(
      outputTierOfItem(section: 'blank_filling', type: 'spelling').id,
      'word',
    );
  });

  test('setSpecFromExerciseRow:题组行还原成题组(含来源/卷面身份)', () async {
    final setId = await DatabaseService.insertExerciseSet(<String, Object?>{
      'source': 'exam',
      'exam_type': 'cet6',
      'paper_year': 2023,
      'paper_label': '2023 年 12 月 · 第 1 套',
      'section': 'writing',
      'title': '英语六级(CET-6) · 写作真题',
      'rubric_id': 'cet6_writing',
      'license_note': '题目来自公开网页抓取(https://www.neea.edu.cn/a.htm)。',
      'verify_status': 'pending',
      'created_at': '2026-11-07T10:00:00',
    }, items: <Map<String, Object?>>[
      <String, Object?>{
        'idx': 0,
        'type': 'exam_writing',
        'prompt_zh': 'Write an essay on lifelong learning.',
        'reference_answer': '',
        'rubric_id': 'cet6_writing',
        'word_count': 150,
        'source_span': '',
        'audio_ref': '',
      },
      <String, Object?>{
        'idx': 1,
        'type': 'exam_writing',
        'prompt_zh': 'Write an essay on stress management.',
        'reference_answer': '',
        'rubric_id': 'cet6_writing',
        'word_count': 150,
        'source_span': '',
        'audio_ref': '',
      },
    ]);
    final full = await DatabaseService.getExerciseSet(setId);
    final set = setSpecFromExerciseRow(full);
    expect(set, isNotNull);
    expect(set!.title, contains('CET-6'));
    expect(set.tasks, hasLength(2));
    expect(set.examType, 'cet6');
    expect(set.paperYear, 2023);
    expect(set.paperLabel, '2023 年 12 月 · 第 1 套');
    expect(set.sourceSite, '中国教育考试网');
    expect(set.tasks.first.rubricId, 'cet6_writing');
    expect(set.tasks.first.tier.id, 'essay');
  });

  test('loadScoredByIndex:从 attempts.score_json 还原"已批改题"(按题目序号)',
      () async {
    final setId = await DatabaseService.insertExerciseSet(<String, Object?>{
      'source': 'ai',
      'exam_type': 'cet6',
      'section': 'writing',
      'title': '六级写作练习',
      'rubric_id': 'cet6_writing',
      'verify_status': 'pending',
      'created_at': '2026-11-07T10:00:00',
    }, items: <Map<String, Object?>>[
      <String, Object?>{
        'idx': 0,
        'type': 'exam_writing',
        'prompt_zh': '题一',
        'reference_answer': '',
        'rubric_id': 'cet6_writing',
        'word_count': 0,
        'source_span': '',
        'audio_ref': '',
      },
      <String, Object?>{
        'idx': 1,
        'type': 'exam_writing',
        'prompt_zh': '题二',
        'reference_answer': '',
        'rubric_id': 'cet6_writing',
        'word_count': 0,
        'source_span': '',
        'audio_ref': '',
      },
    ]);
    final full = await DatabaseService.getExerciseSet(setId);
    final firstItemId =
        (((full!['items'] as List).first) as Map)['id'] as int;
    const scored = ScoredOutput(
      totalScore: 78,
      bandLabel: '良好',
      dimensions: <ScoredDimension>[
        ScoredDimension(key: 'content', label: '内容切题', maxScore: 40, score: 33),
      ],
      summary: '整体不错。',
    );
    await DatabaseService.insertOutputAttempt(<String, Object?>{
      'set_id': setId,
      'item_id': firstItemId,
      'mode': 'ai_rubric',
      'answer': 'my answer',
      'score_json': jsonEncode(scored.toJson()),
      'seconds': 120,
      'created_at': '2026-11-07T10:05:00',
    });

    final restored = await loadScoredByIndex(setId);
    expect(restored.keys, contains(0));
    expect(restored.keys.contains(1), isFalse, reason: '没提交的题不应凭空有分数');
    expect(restored[0]!.totalScore, 78);
    expect(restored[0]!.dimensions.single.label, '内容切题');
  });
}
