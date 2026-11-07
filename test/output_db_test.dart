import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/database.dart';

/// v2.17.0(批 3 · 输出重建 P0 数据层)回归:四张表 + dbVersion 21 + CRUD + 内置 rubric。
///
/// 为什么用真 SQLite:这批表是"输出/评分/统计"三条链路的共同地基 —— 迁移写错
/// 或事务没回滚,用户会看到"有卷面没题目"/"做题记录消失",而且库已经在手机上,
/// 没有重装这个选项。测试覆盖:
/// ① 全新安装(版本/四表/6 条内置 rubric 的结构与权重);
/// ② v20 → v21 升级(建表 + seed,旧数据不丢,重复打开幂等);
/// ③ insertExerciseSet 事务(items 全进 / 失败整体回滚);
/// ④ getExerciseSet(含 items)+ listExerciseSets 过滤;
/// ⑤ 作答记录 + outputStats 口径(主观题 correct=NULL 不进正确率分母);
/// ⑥ 内置 rubric seed 重复执行不重复插入、也不覆盖已修改内容。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_output_db_test');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    try {
      await databaseFactory.deleteDatabase(p.join(tmp.path, AppConstants.dbName));
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<Set<String>> tableNames(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    return rows.map((r) => '${r['name']}').toSet();
  }

  Future<int> count(Database db, String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  test('全新安装:版本为当前 dbVersion + 四张新表 + 6 条内置 rubric(权重和=1、档位非空)', () async {
    final db = await DatabaseService.database;
    expect(await db.getVersion(), AppConstants.dbVersion);
    // 只锁下限:v21 才引入输出四表;以后每批继续升版本不能把这条测试打红
    expect(AppConstants.dbVersion, greaterThanOrEqualTo(21));

    final tables = await tableNames(db);
    expect(
      tables,
      containsAll([
        'exercise_sets',
        'exercise_items',
        'rubrics',
        'output_attempts',
      ]),
    );

    final rubrics = await DatabaseService.listRubrics();
    expect(rubrics.length, 6, reason: '内置 rubric 只能 seed 一次（v2.28 起含六级写作/翻译两套）');
    expect(
      rubrics.map((r) => r['id']).toSet(),
      {
        'cet4_writing',
        'cet4_translation',
        'cet6_writing',
        'cet6_translation',
        'back_translation',
        'summary',
      },
      reason: '出题器/评分层按固定 id 对齐,不能改名',
    );
    for (final r in rubrics) {
      expect(r['scoring_mode'], 'ai_rubric');
      expect((r['prompt_template'] as String).isNotEmpty, isTrue);
      final dims = (jsonDecode('${r['dimensions_json']}') as List)
          .cast<Map<String, dynamic>>();
      expect(dims, isNotEmpty);
      var weight = 0.0;
      for (final d in dims) {
        expect('${d['key']}'.isNotEmpty, isTrue);
        expect('${d['label']}'.isNotEmpty, isTrue);
        weight += (d['weight'] as num).toDouble();
      }
      expect(weight, closeTo(1.0, 1e-9), reason: '${r['id']} 维度权重必须归一');
      final bands = (jsonDecode('${r['bands_json']}') as List);
      expect(bands, isNotEmpty, reason: '${r['id']} 必须有分档描述给 UI 显示');
    }
    // 索引也要建出来(顺序/统计查询依赖)
    final indexes = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    ))
        .map((r) => '${r['name']}')
        .toSet();
    expect(indexes, contains('idx_exercise_items_set'));
    expect(indexes, contains('idx_output_attempts_created'));
    expect(indexes, contains('idx_output_attempts_set'));
  });

  test('v20 → v21 迁移:四表 + seed 建好,旧数据不丢,重复打开幂等', () async {
    final path = p.join(tmp.path, AppConstants.dbName);

    // ① 手工造 v20 库:上一批(V2.16)的真实表 + 一行旧数据。
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 20,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE vocabulary (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              word TEXT NOT NULL,
              mastery_level INTEGER DEFAULT 0,
              category TEXT,
              material_path TEXT,
              source_book TEXT,
              created_at TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE material_translations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              material_id INTEGER NOT NULL,
              unit_index INTEGER NOT NULL,
              chunk_index INTEGER NOT NULL,
              source_text TEXT NOT NULL,
              translated_text TEXT NOT NULL,
              model TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT,
              UNIQUE(material_id, unit_index)
            )
          ''');
        },
      ),
    );
    final now = DateTime.now().toIso8601String();
    await legacy.insert('vocabulary', {
      'word': 'legacy',
      'mastery_level': 1,
      'category': '书籍',
      'material_path': '书籍/《Character》',
      'source_book': '《Character》',
      'created_at': now,
    });
    await legacy.insert('material_translations', {
      'material_id': 7,
      'unit_index': 0,
      'chunk_index': 0,
      'source_text': 'Hello.',
      'translated_text': '你好。',
      'created_at': now,
      'updated_at': now,
    });
    await legacy.close();

    // ② 真服务打开 → onUpgrade(20→21) + onOpen 自检
    final db = await DatabaseService.database;
    expect(await db.getVersion(), AppConstants.dbVersion);
    final tables = await tableNames(db);
    expect(
      tables,
      containsAll(
          ['exercise_sets', 'exercise_items', 'rubrics', 'output_attempts']),
    );
    expect(await count(db, 'rubrics'), 6);

    // ③ 旧数据不丢(词汇 + 上一批的译文)
    expect(await count(db, 'vocabulary'), 1);
    expect(await DatabaseService.loadMaterialTranslations(7), {0: '你好。'});

    // ④ 幂等:再启动一次,表/seed/旧数据都保持原样
    await DatabaseService.resetForTest();
    final db2 = await DatabaseService.database;
    expect(await db2.getVersion(), AppConstants.dbVersion);
    expect(await count(db2, 'rubrics'), 6, reason: 'seed 不能重复插入');
    expect(await count(db2, 'vocabulary'), 1);
    expect(await DatabaseService.loadMaterialTranslations(7), {0: '你好。'});
  });

  test('insertExerciseSet 事务:题目自动 set_id/idx;任一题失败整组回滚', () async {
    final setId = await DatabaseService.insertExerciseSet(
      {
        'source': 'ai',
        'exam_type': 'cet4',
        'section': 'writing',
        'title': 'CET-4 写作练习 1',
        'difficulty_cefr': 'B1',
        'goals_json': jsonEncode(['cet4']),
        'rubric_id': 'cet4_writing',
      },
      items: [
        {
          'type': 'writing',
          'prompt_zh': '写一篇关于环境保护的短文。',
          'word_count': 120,
        },
        {'type': 'writing', 'prompt_zh': '写一封建议信。'},
      ],
    );
    expect(setId, greaterThan(0));

    final saved = await DatabaseService.getExerciseSet(setId);
    expect(saved, isNotNull);
    final setRow = saved!;
    expect(setRow['title'], 'CET-4 写作练习 1');
    expect(setRow['rubric_id'], 'cet4_writing');
    expect('${setRow['created_at'] ?? ''}', isNot(isEmpty),
        reason: '题组 created_at 由方法兜底写入');
    final items = (setRow['items'] as List).cast<Map<String, Object?>>();
    expect(items.length, 2);
    expect(items[0]['set_id'], setId);
    expect(items[1]['set_id'], setId);
    expect(items[0]['idx'], 0);
    expect(items[1]['idx'], 1);

    // 第二题带未知列 → items 插入抛错 → 整个事务回滚:卷面也不能留下
    final badId = await DatabaseService.insertExerciseSet(
      {'title': '会被回滚的题组', 'source': 'ai'},
      items: [
        {'type': 'writing', 'prompt_zh': '正常题'},
        {'type': 'writing', 'bad_column_xyz': 1},
      ],
    );
    expect(badId, 0, reason: '失败返回 0');
    final all = await DatabaseService.listExerciseSets(limit: 200);
    expect(
      all.where((r) => r['title'] == '会被回滚的题组'),
      isEmpty,
      reason: 'items 失败必须把 exercise_sets 也回滚(单事务)',
    );
    expect(await DatabaseService.getExerciseSet(999999), isNull);
  });

  test('listExerciseSets:按 examType / section 过滤,limit 生效', () async {
    final cet4 = await DatabaseService.insertExerciseSet({
      'source': 'exam',
      'exam_type': 'cet4',
      'section': 'writing',
      'title': 'CET-4 2023 写作',
      'paper_year': 2023,
      'paper_label': '2023年6月',
    });
    final ielts = await DatabaseService.insertExerciseSet({
      'source': 'ai',
      'exam_type': 'ielts',
      'section': 'translation',
      'title': 'IELTS 翻译练习',
    });
    expect(cet4, greaterThan(0));
    expect(ielts, greaterThan(0));

    final all = await DatabaseService.listExerciseSets(limit: 200);
    expect(all.length, greaterThanOrEqualTo(2));
    final cet4Only =
        await DatabaseService.listExerciseSets(examType: 'cet4', limit: 200);
    expect(cet4Only.length, 1);
    expect(cet4Only.single['title'], 'CET-4 2023 写作');
    final translationOnly = await DatabaseService.listExerciseSets(
        section: 'translation', limit: 200);
    expect(translationOnly.length, 1);
    expect((await DatabaseService.listExerciseSets(limit: 1)).length, 1);
  });

  test('insertOutputAttempt / listOutputAttempts / outputStats 口径', () async {
    final setId = await DatabaseService.insertExerciseSet(
      {'title': '统计测试题组', 'section': 'spelling'},
      items: [
        {'type': 'spelling', 'idx': 0, 'prompt_zh': 'apple', 'reference_answer': 'apple'},
        {'type': 'back_translation', 'idx': 1, 'prompt_zh': '苹果'},
      ],
    );
    final items = ((await DatabaseService.getExerciseSet(setId))!['items']
            as List)
        .cast<Map<String, Object?>>();
    final spellingId = items[0]['id'] as int;
    final backId = items[1]['id'] as int;

    await DatabaseService.insertOutputAttempt({
      'set_id': setId,
      'item_id': spellingId,
      'mode': 'spelling',
      'answer': 'apple',
      'correct': 1,
      'seconds': 10,
    });
    await DatabaseService.insertOutputAttempt({
      'set_id': setId,
      'item_id': spellingId,
      'mode': 'spelling',
      'answer': 'aple',
      'correct': 0,
      'seconds': 20,
    });
    await DatabaseService.insertOutputAttempt({
      'set_id': setId,
      'item_id': backId,
      'mode': 'back_translation',
      'answer': 'The apple is red.',
      'correct': null, // 主观题:只有维度分,不判对错
      'score_json': jsonEncode([
        {'key': 'accuracy', 'score': 4},
        {'key': 'fluency', 'score': 4},
      ]),
      'seconds': 30,
    });
    // 一条"很久以前的作答"用来验证 since 过滤
    await DatabaseService.insertOutputAttempt({
      'set_id': setId,
      'item_id': spellingId,
      'mode': 'spelling',
      'correct': 1,
      'seconds': 999,
      'created_at': '2020-01-01T00:00:00.000',
    });

    final all = await DatabaseService.listOutputAttempts(limit: 100);
    expect(all.length, 4);
    expect(
      (await DatabaseService.listOutputAttempts(setItemId: spellingId)).length,
      3,
    );
    expect((await DatabaseService.listOutputAttempts(setId: setId)).length, 4);

    // 全量口径:4 条作答,correct 非空 3 条(1/0/1) → 2/3;秒数 10+20+30+999
    final stats = await DatabaseService.outputStats();
    expect(stats['sets'], greaterThanOrEqualTo(1));
    expect(stats['attempts'], 4);
    expect((stats['correctRate'] as double), closeTo(2 / 3, 1e-9));
    expect(stats['totalSeconds'], 1059);
    expect(
      (stats['byType'] as Map<String, int>)['spelling'],
      3,
      reason: '两条 spelling + 一条旧 spelling;byType 按 exercise_items.type 聚合',
    );
    expect((stats['byType'] as Map<String, int>)['back_translation'], 1);

    // since 口径:排除 2020 那条 → 3 条 / correct 非空 2 条(1、0)→ 1/2
    final recent = await DatabaseService.outputStats(since: DateTime(2021));
    expect(recent['attempts'], 3);
    expect((recent['correctRate'] as double), closeTo(0.5, 1e-9));
    expect(recent['totalSeconds'], 60);
    expect((recent['byType'] as Map<String, int>)['spelling'], 2);
  });

  test('内置 rubric seed:重复打开不重复插入,也不覆盖已被修改的内容', () async {
    final db = await DatabaseService.database;
    expect(await count(db, 'rubrics'), 6);

    // 模拟用户/后续版本修改了内置 rubric(比如换了提示词)
    await db.update(
      'rubrics',
      {'prompt_template': '自定义评分提示词'},
      where: 'id = ?',
      whereArgs: ['cet4_writing'],
    );
    expect((await DatabaseService.getRubric('cet4_writing'))!['prompt_template'],
        '自定义评分提示词');

    // 重启:seed 必须 INSERT OR IGNORE(不重复插入、不覆盖手改内容)
    await DatabaseService.resetForTest();
    final db2 = await DatabaseService.database;
    expect(await count(db2, 'rubrics'), 6);
    expect((await DatabaseService.getRubric('cet4_writing'))!['prompt_template'],
        '自定义评分提示词');
    expect(await DatabaseService.getRubric('not_exist_rubric'), isNull);
  });
}
