import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/backup_service.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/export_service.dart';
import 'package:readflow/services/learner_model_store.dart';

/// 备份格式 v2(批 8 · P2-7)的**真 SQLite 全链路**回归。
///
/// 为什么这一层必须用真库测:备份是这个 App 唯一的数据主权出口,而 v2 补的
/// 恰恰是"以前完全没备份"的十张表(阅读译文/输出题组与作答/能力快照/任务与
/// 事件/错误标签/复习状态原表/rubrics)。这些表的父子关系(题组↔题目、
/// 任务↔事件、vocab↔word_review)在导出/恢复两侧都要重建,用 mock 测不出来。
///
/// 覆盖:
/// ① v2 全量往返:export → 清库 → restore,十张表的行数/内容/关联全部对得上;
/// ② v1 老备份(无 backupVersion / tables)继续可恢复,且不碰新表;
/// ③ 坏 JSON / 坏表结构 / 更新版本备份:解析给可诊断原因,恢复不崩不误写;
/// ④ 截断口径:output_attempts / task_events 只导最近 5000 条,报告里写明,
///    恢复报告也会把截断事实讲给用户;
/// ⑤ 冲突策略:rubrics 不动已有行、重复恢复不重复写、replace 不清 v3 历史;
/// ⑥ 事务:坏行让整块 v3 恢复回滚(留下半套数据的库比没恢复更糟)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Directory hiveDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_backup_v2_test');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
    hiveDir = await Directory.systemTemp.createTemp('hive_backup_v2_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    try {
      await databaseFactory.deleteDatabase(p.join(tmp.path, AppConstants.dbName));
    } catch (_) {}
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  /// 造一份"本机全量数据":v1 的词/复习状态/画像 + v2 十张表都有内容
  Future<Map<String, Object?>> seedAll() async {
    final now = DateTime.now();
    final vocabA = await DatabaseService.insertVocabulary(
      Vocabulary(word: 'alpha', translation: '第一个', createdAt: now),
    );
    final vocabB = await DatabaseService.insertVocabulary(
      Vocabulary(word: 'beta', translation: '第二个', createdAt: now),
    );
    await DatabaseService.upsertWordReview(
      vocabA,
      stability: 12.5,
      difficulty: 5.5,
      dueAt: now.add(const Duration(days: 3)),
      lastReviewAt: now,
      lastRating: 3,
      reps: 4,
      lapses: 1,
    );
    await DatabaseService.upsertWordReview(
      vocabB,
      stability: 30,
      difficulty: 4,
      dueAt: now.subtract(const Duration(days: 1)),
      lastReviewAt: now,
      lastRating: 2,
      reps: 7,
      lapses: 2,
    );
    await LearnerModelStore.save(
      LearnerModel(
        dailyMinutes: ProfileField<int>(value: 45, source: ProfileSource.self),
      ),
    );
    await Hive.box(AppConstants.hiveBoxSettings)
        .put(AppConstants.keyTtsAccent, 'uk');

    final db = await DatabaseService.database;
    // 材料 + 阅读译文(译文挂在 material_id 上;material_translations 是 v2 新备的表)
    final materialId = await db.insert('materials', <String, Object?>{
      'kind': 'article',
      'source': 'test',
      'title': '测试材料',
      'created_at': now.toIso8601String(),
    });
    await DatabaseService.saveMaterialTranslation(
      materialId,
      unitIndex: 0,
      chunkIndex: 0,
      sourceText: 'The first paragraph.',
      translatedText: '第一段。',
      model: 'deepseek-chat',
    );

    // 题组 + 题目 + 作答(恢复时旧 id 会变,关联必须重建)
    final setId = await DatabaseService.insertExerciseSet(
      <String, Object?>{
        'source': 'ai',
        'section': 'writing',
        'title': '测试题组',
        'created_at': now.toIso8601String(),
      },
      items: <Map<String, Object?>>[
        <String, Object?>{
          'idx': 0,
          'type': 'writing',
          'prompt_zh': '写一篇短文',
          'rubric_id': 'cet4_writing',
        },
        <String, Object?>{
          'idx': 1,
          'type': 'summary',
          'prompt_zh': '写摘要',
          'rubric_id': 'summary',
        },
      ],
    );
    expect(setId, greaterThan(0));
    final set = await DatabaseService.getExerciseSet(setId);
    final itemId = ((set!['items'] as List).first as Map)['id'] as int;
    await DatabaseService.insertOutputAttempt(<String, Object?>{
      'set_id': setId,
      'item_id': itemId,
      'mode': 'ai_rubric',
      'answer': 'A short essay.',
      'correct': null,
      'score_json': jsonEncode(<String, Object?>{
        'total_score': 82.0,
        'band_label': '优秀',
      }),
      'seconds': 120,
      'error_tags_json': jsonEncode(<String>['时态']),
      'created_at': now.subtract(const Duration(minutes: 10)).toIso8601String(),
    });

    // 自定义 rubric(内置 4 条由 onCreate seed;两条一起验证"全导 + 只插缺失")
    await db.insert('rubrics', <String, Object?>{
      'id': 'custom_rubric',
      'type': 'writing',
      'scoring_mode': 'ai_rubric',
      'dimensions_json': jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'key': 'x',
          'label': 'X',
          'weight': 1,
          'max_score': 100,
        },
      ]),
      'bands_json': '[]',
      'prompt_template': '自定义评分模板',
      'created_at': now.toIso8601String(),
    });

    // 能力快照
    await DatabaseService.insertAbilitySnapshot(<String, Object?>{
      'dimension': 'vocab',
      'value': 4200,
      'unit': 'words',
      'source': 'test',
      'confidence': 0.85,
      'evidence_json': <String, Object?>{'low': 3800, 'high': 4600},
      'snapshot_at': now.subtract(const Duration(days: 1)).toIso8601String(),
    });
    await DatabaseService.insertAbilitySnapshot(<String, Object?>{
      'dimension': 'output',
      'value': 82.0,
      'unit': 'score',
      'source': 'inferred',
      'snapshot_at': now.toIso8601String(),
    });

    // 助理任务 + 任务事件(create / submit 两条由 DB 层自动写)
    final taskId = await DatabaseService.insertTutorTask(
      planDate: now,
      kind: 'output',
      title: '写一篇作文',
      origin: 'auto',
      goalTag: 'output',
      targetMinutes: 20,
    );
    await DatabaseService.updateTutorTaskStatus(
      taskId,
      'done',
      actualMinutes: 18,
      note: '按时完成',
    );

    // 错误标签(时态同一标签 bump 两次 = count 2;冠词 1 次)
    await DatabaseService.bumpErrorTag(
      source: 'writing',
      tag: '时态',
      evidence: 'I go yesterday',
    );
    await DatabaseService.bumpErrorTag(source: 'writing', tag: '时态');
    await DatabaseService.bumpErrorTag(source: 'writing', tag: '冠词');

    return <String, Object?>{
      'materialId': materialId,
      'setId': setId,
      'itemId': itemId,
      'taskId': taskId,
    };
  }

  /// 可恢复表全清(模拟"换机/清数据";materials 保留 —— 译文按 material_id 对齐)
  Future<void> wipeRestorable() async {
    final db = await DatabaseService.database;
    await db.transaction((txn) async {
      for (final table in <String>[
        'vocabulary',
        'word_review',
        'material_translations',
        'exercise_items',
        'exercise_sets',
        'rubrics',
        'output_attempts',
        'ability_snapshots',
        'task_events',
        'tutor_tasks',
        'error_tags',
      ]) {
        await txn.delete(table);
      }
    });
  }

  group('v2 全量往返', () {
    test('导出→清库→恢复:十张新表的行数/内容/关联都回来', () async {
      final ids = await seedAll();
      final built = await BackupService.buildBackupJson();
      expect(built.formatVersion, 2);
      expect(built.truncation, isEmpty);
      // 新旧两个版本字段都在:旧 App 靠 version=1 兼容读取
      expect(built.json, contains('"version": 1'));
      expect(built.json, contains('"backupVersion": 2'));
      expect(built.counts['vocab'], 2);
      expect(built.counts['material_translations'], 1);
      expect(built.counts['output_attempts'], 1);

      final parsed = ExportService.parseBackup(built.json);
      expect(parsed.ok, isTrue, reason: parsed.error ?? '');
      expect(parsed.backupVersion, 2);
      expect(
        parsed.tables.keys,
        containsAll(<String>[
          'material_translations',
          'exercise_sets',
          'exercise_items',
          'rubrics',
          'output_attempts',
          'ability_snapshots',
          'task_events',
          'tutor_tasks',
          'error_tags',
          'word_review',
        ]),
      );

      await wipeRestorable();
      expect(await DatabaseService.getVocabularies(limit: 10), isEmpty);

      final report = await BackupService.restore(parsed, replace: false);
      expect(report.warnings, isEmpty, reason: report.warnings.join(';'));
      expect(report.backupVersion, 2);
      expect(report.added, 2);
      expect(report.cardsRestored, 2);
      expect(report.replacedModel, isTrue);
      // 报告要能逐表报数,不是一句"导入成功"
      expect(report.tables['output_attempts']!.restored, 1);
      expect(report.tables['exercise_sets']!.restored, 1);
      expect(report.tables['exercise_items']!.restored, 2);
      expect(report.tables['ability_snapshots']!.restored, 2);
      expect(report.summary, contains('恢复'));

      final db = await DatabaseService.database;

      // ① 生词 + 复习状态(FSRS 绝对值)
      final vocab = await DatabaseService.getVocabularies(limit: 10);
      expect(vocab.map((v) => v.word).toSet(), <String>{'alpha', 'beta'});
      final reviews = await DatabaseService.getWordReviews();
      expect(reviews, hasLength(2));
      final reviewByVocab = <int, Map<String, Object?>>{
        for (final r in reviews) (r['vocab_id'] as num).toInt(): r,
      };
      final beta = vocab.firstWhere((v) => v.word == 'beta');
      expect((reviewByVocab[beta.id!]!['reps'] as num).toInt(), 7);
      expect(
        (reviewByVocab[beta.id!]!['lapses'] as num).toInt(),
        2,
        reason: '遗忘次数必须跟着备份回来',
      );

      // ② 阅读译文
      final translations = await db.query('material_translations');
      expect(translations, hasLength(1));
      expect(translations.first['source_text'], 'The first paragraph.');
      expect(translations.first['translated_text'], '第一段。');
      expect(translations.first['material_id'], ids['materialId']);

      // ③ 题组/题目:父子关系用新 id 重建
      final sets = await db.query('exercise_sets');
      expect(sets, hasLength(1));
      expect(sets.first['title'], '测试题组');
      final newSetId = sets.first['id'];
      final items = await db.query('exercise_items', orderBy: 'idx ASC');
      expect(items, hasLength(2));
      expect(items.every((i) => i['set_id'] == newSetId), isTrue);
      expect(items.first['prompt_zh'], '写一篇短文');

      // ④ 作答:set_id/item_id 指向**恢复后**的 id(不是旧 id)
      final attempts = await db.query('output_attempts');
      expect(attempts, hasLength(1));
      expect(attempts.first['set_id'], newSetId);
      expect(attempts.first['item_id'], items.first['id']);
      expect(
        (jsonDecode('${attempts.first['score_json']}') as Map)['total_score'],
        82.0,
      );

      // ⑤ rubrics:内置 6 + 自定义 1 = 7(全导且只插缺失;v2.28 起内置多了六级两套)
      final rubrics = await db.query('rubrics');
      expect(rubrics, hasLength(7));
      expect(rubrics.map((r) => '${r['id']}'), contains('custom_rubric'));
      expect(
        rubrics.map((r) => '${r['id']}'),
        contains('cet4_writing'),
        reason: '内置 seed 也要跟着备份走(否则换机后评分无标准)',
      );

      // ⑥ 能力快照
      final abilities = await db.query(
        'ability_snapshots',
        orderBy: 'snapshot_at ASC, id ASC',
      );
      expect(abilities, hasLength(2));
      expect(abilities.first['dimension'], 'vocab');
      expect((abilities.first['value'] as num).toDouble(), 4200);
      expect(
        (jsonDecode('${abilities.first['evidence_json']}') as Map)['low'],
        3800,
        reason: '证据(区间)也要原样恢复',
      );

      // ⑦ 任务 + 事件:事件父任务 id 必须改成新 id
      final tasks = await db.query('tutor_tasks');
      expect(tasks, hasLength(1));
      expect(tasks.first['title'], '写一篇作文');
      expect(tasks.first['status'], 'done');
      expect((tasks.first['actual_minutes'] as num).toInt(), 18);
      final events = await db.query('task_events', orderBy: 'at ASC, id ASC');
      expect(events, hasLength(2));
      expect(events.every((e) => e['task_id'] == tasks.first['id']), isTrue);
      expect(events.map((e) => '${e['event']}').toList(), <String>[
        'create',
        'submit',
      ]);

      // ⑧ 错误标签:合并后 2 行;时态 count=2 由两次 bump 带过来
      final tags = await db.query('error_tags');
      expect(tags.map((r) => '${r['tag']}').toSet(), <String>{'时态', '冠词'});
      final tense = tags.firstWhere((r) => r['tag'] == '时态');
      expect((tense['count'] as num).toInt(), 2);
      expect(tense['evidence'], 'I go yesterday');
    });
  });

  group('版本兼容', () {
    test('v1 老备份(无 backupVersion/tables)照常恢复,且不碰新表', () async {
      // 本机先有一条 v2 表数据:恢复 v1 备份不能动它
      await DatabaseService.insertAbilitySnapshot(<String, Object?>{
        'dimension': 'vocab',
        'value': 3000,
        'snapshot_at': '2026-11-01T00:00:00.000',
      });
      final now = DateTime.now();
      // 手工造 v1(发布了的老版本 App 产出的格式:没有 backupVersion/tables)
      final v1Json = jsonEncode(<String, Object?>{
        'version': 1,
        'app': 'readflow',
        'exported_at': now.toIso8601String(),
        'counts': <String, Object?>{'vocab': 1},
        'vocab': <Map<String, Object?>>[
          <String, Object?>{
            'word': 'legacy',
            'translation': '旧词',
            'created_at': now.toIso8601String(),
          },
        ],
        'learner_model': LearnerModel(
          dailyMinutes: ProfileField<int>(value: 30, source: ProfileSource.self),
        ).toJson(),
        'settings': <String, String>{},
      });
      final parsed = ExportService.parseBackup(v1Json);
      expect(parsed.ok, isTrue);
      expect(parsed.backupVersion, 1, reason: '没有 backupVersion 字段 → 按 v1 兼容');
      expect(parsed.tables, isEmpty);

      final report = await BackupService.restore(parsed, replace: false);
      expect(report.backupVersion, 1);
      expect(report.tables, isEmpty, reason: 'v1 备份没有 v2 表可恢复');
      expect(report.added, 1);
      expect(report.warnings, isEmpty);

      final vocab = await DatabaseService.getVocabularies(limit: 10);
      expect(vocab.map((v) => v.word), contains('legacy'));
      final db = await DatabaseService.database;
      expect(
        await db.query('ability_snapshots'),
        hasLength(1),
        reason: 'v1 恢复不能动 v2 新表',
      );
      expect(await db.query('material_translations'), isEmpty);
    });

    test('更新版本的备份:解析即拒绝 + 恢复不动本地数据', () async {
      await DatabaseService.insertVocabulary(
        Vocabulary(word: 'keepme', translation: '必须还在'),
      );
      final future = ExportService.parseBackup(
        '{"app":"readflow","version":1,"backupVersion":9}',
      );
      expect(future.ok, isFalse);
      expect(future.error, contains('更新版本'));
      final report = await BackupService.restore(future, replace: false);
      expect(report.warnings, isNotEmpty);
      expect(
        (await DatabaseService.getVocabularies(limit: 10)).map((v) => v.word),
        contains('keepme'),
        reason: '拒绝导入时不能动本地数据',
      );
    });

    test('坏 JSON / 坏表结构不崩', () async {
      await DatabaseService.insertVocabulary(
        Vocabulary(word: 'keepme', translation: '必须还在'),
      );
      for (final raw in <String>['', 'not json', '[1,2,3]', '{"app":"other"}']) {
        final parsed = ExportService.parseBackup(raw);
        final report = await BackupService.restore(parsed, replace: false);
        expect(report.warnings, isNotEmpty, reason: '输入:$raw');
      }
      expect(
        (await DatabaseService.getVocabularies(limit: 10)).map((v) => v.word),
        <String>['keepme'],
      );

      // 能解析但结构脏:tables 不是 Map、行里有非对象、缺关联字段
      final weird = jsonEncode(<String, Object?>{
        'version': 1,
        'backupVersion': 2,
        'app': 'readflow',
        'vocab': <Object?>[],
        'tables': <String, Object?>{
          'rubrics': 'oops',
          'material_translations': <Object?>[
            1,
            'x',
            <String, Object?>{'material_id': 1},
          ],
          'ability_snapshots': <Object?>[
            <String, Object?>{'dimension': 'vocab'},
          ],
        },
      });
      final parsedWeird = ExportService.parseBackup(weird);
      expect(parsedWeird.ok, isTrue);
      final report = await BackupService.restore(parsedWeird, replace: false);
      expect(report.warnings, isEmpty, reason: '脏行被跳过,不应升级成"恢复失败"');
      final db = await DatabaseService.database;
      expect(await db.query('material_translations'), isEmpty);
      expect(await db.query('ability_snapshots'), isEmpty);
    });
  });

  group('截断口径', () {
    test('两张流水表只导最近 5000 条,导出/恢复两侧都写明', () async {
      final db = await DatabaseService.database;
      final now = DateTime.now();
      final taskId = await DatabaseService.insertTutorTask(
        planDate: now,
        kind: 'output',
        title: '截断测试任务',
      );
      // 用单事务批量造 6000 条作答 + 6000 条事件
      await db.transaction((txn) async {
        for (var i = 0; i < 6000; i++) {
          final at = now.subtract(Duration(seconds: i)).toIso8601String();
          await txn.insert('output_attempts', <String, Object?>{
            'mode': 'ai_rubric',
            'answer': 'answer-$i',
            'created_at': at,
          });
          await txn.insert('task_events', <String, Object?>{
            'task_id': taskId,
            'event': 'edit',
            'at': at,
            'created_at': at,
          });
        }
      });

      final built = await BackupService.buildBackupJson();
      expect(built.counts['output_attempts'], BackupService.outputAttemptsLimit);
      expect(built.counts['task_events'], BackupService.taskEventsLimit);
      expect(
        built.truncation.keys,
        containsAll(<String>['output_attempts', 'task_events']),
      );
      expect(built.notes, isNotEmpty, reason: '截断必须在导出报告里写明');
      expect(built.notes.join('\n'), contains('5000'));
      expect(
        (built.truncation['output_attempts'] as Map)['total'],
        6000,
      );

      final parsed = ExportService.parseBackup(built.json);
      expect(parsed.tables['output_attempts'], hasLength(5000));
      // 6000 条手工事件 + insertTutorTask 自动写的 1 条 create 事件
      expect((parsed.truncation['task_events'] as Map)['total'], 6001);

      await wipeRestorable();
      final report = await BackupService.restore(parsed, replace: false);
      expect(
        report.warnings.join('\n'),
        contains('只包含最近 5000 条'),
        reason: '恢复时也要告诉用户"更早的历史不在备份里"',
      );
      expect(report.tables['output_attempts']!.restored, 5000);
      expect(report.tables['task_events']!.restored, 5000);
      expect(await db.query('output_attempts'), hasLength(5000));
      expect(await db.query('task_events'), hasLength(5000));
    });
  });

  group('冲突/事务策略', () {
    test('rubrics 不动已有行;重复恢复不重复写;replace 不清 v3 历史', () async {
      await seedAll();
      final built = await BackupService.buildBackupJson();
      final parsed = ExportService.parseBackup(built.json);
      await wipeRestorable();

      final db = await DatabaseService.database;
      // 模拟"本机已更新过这条评分标准":同 id 不同内容,恢复不能覆盖
      await db.insert('rubrics', <String, Object?>{
        'id': 'custom_rubric',
        'type': 'writing',
        'scoring_mode': 'ai_rubric',
        'dimensions_json': '[]',
        'bands_json': '[]',
        'prompt_template': 'LOCAL 新模板',
        'created_at': DateTime.now().toIso8601String(),
      });
      // 本机已有一条 v3 历史:replace 导入也不能把它删掉
      await DatabaseService.insertAbilitySnapshot(<String, Object?>{
        'dimension': 'reading',
        'value': 210,
        'snapshot_at': '2026-11-02T09:00:00.000',
      });

      final report = await BackupService.restore(parsed, replace: false);
      final rubrics = await db.query(
        'rubrics',
        where: 'id = ?',
        whereArgs: <Object?>['custom_rubric'],
      );
      expect(rubrics, hasLength(1), reason: '同 id 只插缺失,不能插出第二行');
      expect(
        rubrics.single['prompt_template'],
        'LOCAL 新模板',
        reason: '本机已有行不被旧备份覆盖',
      );
      expect(report.tables['rubrics']!.skipped, greaterThanOrEqualTo(1));

      // 重复恢复:行数不翻倍(题组/作答/快照/事件/任务/错误标签/译文)
      const tables = <String>[
        'material_translations',
        'exercise_sets',
        'exercise_items',
        'output_attempts',
        'ability_snapshots',
        'task_events',
        'tutor_tasks',
        'error_tags',
      ];
      final before = <String, int>{
        for (final t in tables) t: (await db.query(t)).length,
      };
      final second = await BackupService.restore(parsed, replace: false);
      for (final table in tables) {
        expect(
          (await db.query(table)).length,
          before[table],
          reason: '$table 重复恢复不能重复写入',
        );
      }
      expect(second.added, 0, reason: '生词已存在 → 全部跳过');

      // replace=true:既有语义只清生词/复习状态;v3 历史是只追加的审计数据,
      // 不因为"覆盖导入"被删(否则用户在旧手机上多出来的历史会丢)
      await BackupService.restore(parsed, replace: true);
      final reading = await db.query(
        'ability_snapshots',
        where: 'dimension = ?',
        whereArgs: <Object?>['reading'],
      );
      expect(reading, hasLength(1), reason: 'replace 不清 v3 历史');
    });

    test('坏行让整块 v3 恢复事务回滚(不写半套数据)并给可读原因', () async {
      final now = DateTime.now().toIso8601String();
      // source_text 是文本列,这里塞一个嵌套对象:备份被手改坏后恢复,
      // sqflite 会在参数绑定阶段抛"不支持的类型",事务整体回滚。
      final raw = jsonEncode(<String, Object?>{
        'version': 1,
        'backupVersion': 2,
        'app': 'readflow',
        'exported_at': now,
        'vocab': <Map<String, Object?>>[
          <String, Object?>{
            'word': 'atomic',
            'translation': '原子的',
            'created_at': now,
          },
        ],
        'tables': <String, Object?>{
          'rubrics': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'rollback_rubric',
              'type': 'writing',
              'scoring_mode': 'ai_rubric',
              'created_at': now,
            },
          ],
          'material_translations': <Map<String, Object?>>[
            <String, Object?>{
              'material_id': 1,
              'unit_index': 0,
              'chunk_index': 0,
              'source_text': <String, Object?>{'oops': true},
              'translated_text': 'x',
              'created_at': now,
            },
          ],
        },
      });
      final parsed = ExportService.parseBackup(raw);
      expect(parsed.ok, isTrue);

      final report = await BackupService.restore(parsed, replace: false);
      expect(report.warnings, isNotEmpty);
      expect(report.warnings.join('\n'), contains('回滚'));
      // 生词恢复在事务之前,照常成功(用户至少拿回生词本)
      expect(report.added, 1);

      final db = await DatabaseService.database;
      expect(
        await DatabaseService.getRubric('rollback_rubric'),
        isNull,
        reason: '事务回滚后 rubrics 也不能留下(宁可整块没有,不要半套)',
      );
      expect(await db.query('material_translations'), isEmpty);
      expect(
        (await DatabaseService.getVocabularies(limit: 10)).map((v) => v.word),
        contains('atomic'),
      );
    });
  });
}
