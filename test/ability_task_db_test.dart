import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/database.dart';

/// 批 4 · 助理数据层回归(dbVersion 22):能力快照 + 任务事件 + 任务状态机。
///
/// 为什么用真 SQLite:迁移一旦写错**不可自愈**(库已经在用户手机上,没有重装
/// 这个选项);任务状态机与完成率口径又直接决定助理复盘的数字,必须拿真表格
/// 断言。覆盖:
/// ① 全新安装:版本推到 AppConstants.dbVersion、两新表/索引/7 个新列存在、
///   旧列一个不少(向后兼容 —— 周报/小组件仍读 done_at/result_json);
/// ② v21→v22 升级:老任务按 done_at 回填 status、旧数据不丢、重复打开幂等、
///   已改成 skipped 的行不会被回填覆盖;
/// ③ 能力快照 upsert / latest / previous / history(升序、limit、证据解析);
/// ④ 任务事件只追加、非法事件静默跳过;
/// ⑤ 状态机:active/done/pending 的字段联动 + 每次变化同写事件;
/// ⑥ 完成率口径:expired **进分母**、pending/active 不进(research §2.4.4);
/// ⑦ 旧 API(completeTutorTask/reopenTutorTask)也同步 status + 事件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_ability_task_db_test');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    try {
      await databaseFactory.deleteDatabase(
        p.join(tmp.path, AppConstants.dbName),
      );
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<Set<String>> tableNames(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    return rows.map((r) => '${r['name']}').toSet();
  }

  Future<Set<String>> columnNames(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => '${r['name']}').toSet();
  }

  Future<Set<String>> indexNames(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    );
    return rows.map((r) => '${r['name']}').toSet();
  }

  Future<Map<String, Object?>?> taskRow(int id) async {
    final db = await DatabaseService.database;
    final rows = await db.query(
      'tutor_tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// 最近 N 天(含今天)的日期字符串
  String dayText(int offsetDays) {
    final day = DateTime.now().add(Duration(days: offsetDays));
    return '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  group('全新安装 22', () {
    test('版本 / 两新表 + 索引 / tutor_tasks 新列与旧列都在', () async {
      final db = await DatabaseService.database;
      expect(await db.getVersion(), AppConstants.dbVersion);

      final tables = await tableNames(db);
      expect(tables, containsAll(['ability_snapshots', 'task_events']));

      final indexes = await indexNames(db);
      expect(indexes, contains('idx_ability_dim_time'));
      expect(indexes, contains('idx_task_events_task'));

      final tutorColumns = await columnNames(db, 'tutor_tasks');
      // v22 新增 7 列
      expect(
        tutorColumns,
        containsAll(<String>[
          'origin',
          'status',
          'started_at',
          'actual_minutes',
          'note',
          'parent_id',
          'goal_tag',
        ]),
        reason: '状态机/追踪/自定义任务所需的列',
      );
      // 旧列一个不能少:周报、桌面小组件、旧 tutor_home 仍读它们
      expect(
        tutorColumns,
        containsAll(<String>[
          'id',
          'plan_date',
          'kind',
          'title',
          'payload_json',
          'target_minutes',
          'done_at',
          'result_json',
          'created_at',
        ]),
        reason: '向后兼容:扩列不删旧列',
      );

      final abilityColumns = await columnNames(db, 'ability_snapshots');
      expect(
        abilityColumns,
        containsAll(<String>[
          'id',
          'snapshot_at',
          'dimension',
          'value',
          'unit',
          'source',
          'confidence',
          'evidence_json',
          'created_at',
        ]),
      );
      final eventColumns = await columnNames(db, 'task_events');
      expect(
        eventColumns,
        containsAll(<String>[
          'id',
          'task_id',
          'event',
          'at',
          'payload_json',
          'created_at',
        ]),
      );
    });

    test('旧 insertTutorTask 调用点:origin 默认 auto、status 默认 pending', () async {
      final id = await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: 'read',
        title: '读 10 分钟',
      );
      expect(id, greaterThan(0));
      final row = (await taskRow(id))!;
      expect(row['origin'], 'auto');
      expect(row['status'], 'pending');
    });
  });

  group('v21 → v22 迁移', () {
    test('老任务按 done_at 回填 status、旧数据不丢、重复打开幂等', () async {
      final path = p.join(tmp.path, AppConstants.dbName);

      // ① 手工造 v21 库:只有 tutor_tasks(旧 schema)与最小 vocabulary。
      //    其余表由 _onOpen 自检补建 —— 顺带验证"半迁移库"自愈路径。
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 21,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE tutor_tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                plan_date TEXT NOT NULL,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                payload_json TEXT,
                target_minutes INTEGER DEFAULT 0,
                done_at TEXT,
                result_json TEXT,
                created_at TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE vocabulary (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word TEXT NOT NULL,
                mastery_level INTEGER DEFAULT 0,
                created_at TEXT
              )
            ''');
          },
        ),
      );
      final now = DateTime.now().toIso8601String();
      final doneLegacyId = await legacy.insert('tutor_tasks', {
        'plan_date': now,
        'kind': 'review',
        'title': '老任务·已完成',
        'done_at': now,
        'result_json': '{"words":12}',
        'created_at': now,
      });
      final openLegacyId = await legacy.insert('tutor_tasks', {
        'plan_date': now,
        'kind': 'read',
        'title': '老任务·未完成',
        'created_at': now,
      });
      await legacy.insert('vocabulary', {
        'word': 'legacy',
        'mastery_level': 1,
        'created_at': now,
      });
      await legacy.close();

      // ② 真服务打开 → onUpgrade(21→22) + onOpen 自检
      final db = await DatabaseService.database;
      expect(await db.getVersion(), AppConstants.dbVersion);

      final doneRow = (await taskRow(doneLegacyId))!;
      final openRow = (await taskRow(openLegacyId))!;
      expect(doneRow['status'], 'done', reason: 'done_at 非空 → status=done');
      expect(openRow['status'], 'pending');
      // 旧列数据原样保留
      expect(doneRow['title'], '老任务·已完成');
      expect(doneRow['done_at'], now);
      expect(doneRow['result_json'], '{"words":12}');
      expect(openRow['done_at'], isNull);
      expect((await db.query('tutor_tasks')).length, 2, reason: '迁移不能删/插行');
      expect((await db.query('vocabulary')).length, 1);

      // 新表/新列已就绪
      expect(
        await tableNames(db),
        containsAll(['ability_snapshots', 'task_events']),
      );
      expect(await columnNames(db, 'tutor_tasks'), contains('goal_tag'));

      // 回填后的老任务已经能进状态机统计:done=1
      final stats = await DatabaseService.taskCompletionStats();
      expect(stats['done'], 1);
      expect(stats['planned'], 2);

      // ③ 用户改成 skipped 后,下次启动的回填不能把它改回 done
      await DatabaseService.updateTutorTaskStatus(doneLegacyId, 'skipped');
      expect((await taskRow(doneLegacyId))!['status'], 'skipped');

      // ④ 幂等:再启动一次(迁移/自检重跑)
      await DatabaseService.resetForTest();
      final db2 = await DatabaseService.database;
      expect(await db2.getVersion(), AppConstants.dbVersion);
      expect(
        (await taskRow(doneLegacyId))!['status'],
        'skipped',
        reason: '回填只改 pending 行,不能覆盖用户后来设的 skipped',
      );
      expect((await taskRow(openLegacyId))!['status'], 'pending');
      expect((await db2.query('tutor_tasks')).length, 2);
    });
  });

  group('能力快照 ability_snapshots', () {
    test('upsert:同 dimension+snapshot_at 只留一条;不同时间逐条保留', () async {
      final at1 = '2026-11-01T09:00:00.000';
      final at2 = '2026-11-02T09:00:00.000';

      final id1 = await DatabaseService.insertAbilitySnapshot(<String, Object?>{
        'dimension': 'vocab',
        'value': 4200,
        'unit': '词',
        'source': 'test',
        'confidence': 0.85,
        'snapshot_at': at1,
        'evidence_json': <String, Object?>{'placement_items': 40},
      });
      expect(id1, greaterThan(0));

      // 同一天重复写(例如周报重算)→ 覆盖值,不新增行
      await DatabaseService.insertAbilitySnapshot(<String, Object?>{
        'dimension': 'vocab',
        'value': 4300,
        'snapshot_at': at1,
      });
      var history = await DatabaseService.abilityHistory('vocab');
      expect(history, hasLength(1), reason: 'upsert:同维度同时间只能一条');

      await DatabaseService.insertAbilitySnapshot(<String, Object?>{
        'dimension': 'vocab',
        'value': 4400,
        'snapshot_at': at2,
      });
      history = await DatabaseService.abilityHistory('vocab');
      expect(history, hasLength(2));
      expect(
        (history.first['value'] as num).toDouble(),
        4300,
        reason: 'history 按时间升序,画趋势图可直接用',
      );
      expect((history.last['value'] as num).toDouble(), 4400);
    });

    test('latest / previous:没有历史时给 null(不伪造"变化 0")', () async {
      expect(await DatabaseService.latestAbility('grammar'), isNull);
      expect(await DatabaseService.previousAbility('grammar'), isNull);

      await DatabaseService.insertAbilitySnapshot(<String, Object?>{
        'dimension': 'grammar',
        'value': 62,
        'snapshot_at': '2026-11-01T00:00:00.000',
      });
      expect(
        await DatabaseService.previousAbility('grammar'),
        isNull,
        reason: '只有一条时不能拿自己跟自己比',
      );

      await DatabaseService.insertAbilitySnapshot(<String, Object?>{
        'dimension': 'grammar',
        'value': 71,
        'snapshot_at': '2026-11-03T00:00:00.000',
      });
      final latest = (await DatabaseService.latestAbility('grammar'))!;
      final previous = (await DatabaseService.previousAbility('grammar'))!;
      expect((latest['value'] as num).toDouble(), 71);
      expect((previous['value'] as num).toDouble(), 62);
    });

    test('字段解析与容错:evidence_json 解析成对象;空维度返回 -1', () async {
      await DatabaseService.insertAbilitySnapshot(<String, Object?>{
        'dimension': 'output',
        'value': '78.5', // 脏值:字符串数字也能收
        'unit': '分',
        'source': 'inferred',
        'confidence': '0.6',
        'snapshot_at': '2026-11-01T12:00:00.000',
        'evidence_json': <String, Object?>{'attempts': 3, 'avg_score': 78.5},
      });
      final latest = (await DatabaseService.latestAbility('output'))!;
      expect((latest['value'] as num).toDouble(), 78.5);
      expect((latest['confidence'] as num).toDouble(), 0.6);
      final evidence = latest['evidence'] as Map?;
      expect(evidence?['attempts'], 3);

      expect(
        await DatabaseService.insertAbilitySnapshot(<String, Object?>{
          'value': 1,
        }),
        -1,
        reason: 'dimension 必填',
      );
    });

    test('history 支持 limit,且取"最近 N 条"而不是最早 N 条', () async {
      for (var i = 0; i < 5; i++) {
        await DatabaseService.insertAbilitySnapshot(<String, Object?>{
          'dimension': 'reading',
          'value': i * 10,
          'snapshot_at': '2026-11-0${i + 1}T00:00:00.000',
        });
      }
      final history = await DatabaseService.abilityHistory('reading', limit: 2);
      expect(history, hasLength(2));
      expect(
        (history.first['value'] as num).toDouble(),
        30,
        reason: 'limit=2 要取最近两天(11-04/11-05),不是 11-01/11-02',
      );
      expect((history.last['value'] as num).toDouble(), 40);
      expect(await DatabaseService.abilityHistory('nothing'), isEmpty);
    });
  });

  group('任务事件 task_events', () {
    test('插入任务自动写 create 事件;listTaskEvents 按时间正序并解析 payload', () async {
      final id = await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: 'read',
        title: '读材料 10 分钟',
        origin: 'custom',
        note: '自己加的',
        goalTag: 'cet4',
      );
      var events = await DatabaseService.listTaskEvents(id);
      expect(events, hasLength(1));
      expect(events.single['event'], 'create');
      expect((events.single['payload'] as Map?)?['origin'], 'custom');

      await DatabaseService.insertTaskEvent(<String, Object?>{
        'task_id': id,
        'event': 'edit',
        'payload_json': <String, Object?>{'field': 'title'},
      });
      events = await DatabaseService.listTaskEvents(id);
      expect(events, hasLength(2));
      expect(events.last['event'], 'edit');
      expect((events.last['payload'] as Map?)?['field'], 'title');
    });

    test('非法事件静默跳过(不抛、不写脏行)', () async {
      await DatabaseService.insertTaskEvent(<String, Object?>{
        'event': 'create',
      });
      await DatabaseService.insertTaskEvent(<String, Object?>{
        'task_id': 0,
        'event': 'create',
      });
      await DatabaseService.insertTaskEvent(<String, Object?>{
        'task_id': 1,
        'event': '   ',
      });
      final db = await DatabaseService.database;
      expect((await db.query('task_events')).length, 0);
    });

    test('任务删除后事件仍保留(审计只追加,跟随任务生命周期无关)', () async {
      final id = await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: 'custom',
        title: '待删任务',
      );
      await DatabaseService.deleteTutorTask(id);
      expect(
        await DatabaseService.listTaskEvents(id),
        hasLength(1),
        reason: 'deleteTutorTask 删的是任务行,审计事件不级联删除',
      );
    });
  });

  group('任务状态机 updateTutorTaskStatus', () {
    test('pending → active → done → pending:字段联动 + 每次变化落事件', () async {
      final id = await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: 'read',
        title: '状态机任务',
      );

      await DatabaseService.updateTutorTaskStatus(id, 'active');
      var row = (await taskRow(id))!;
      expect(row['status'], 'active');
      expect('${row['started_at'] ?? ''}', isNotEmpty, reason: '开始任务要自动记开始时间');

      await DatabaseService.updateTutorTaskStatus(
        id,
        'done',
        actualMinutes: 12,
        note: '比预计快',
        resultJson: '{"words":120}',
      );
      row = (await taskRow(id))!;
      expect(row['status'], 'done');
      expect('${row['done_at'] ?? ''}', isNotEmpty, reason: 'done 要补 done_at');
      expect(row['actual_minutes'], 12);
      expect(row['note'], '比预计快');
      expect(row['result_json'], '{"words":120}');

      // 撤销完成:状态回 pending,同时清掉完成时间与结果(避免自相矛盾行)
      await DatabaseService.updateTutorTaskStatus(id, 'pending');
      row = (await taskRow(id))!;
      expect(row['status'], 'pending');
      expect(row['done_at'], isNull);
      expect(row['result_json'], isNull);

      final events = await DatabaseService.listTaskEvents(id);
      expect(events.map((e) => e['event']).toList(), <String>[
        'create',
        'start',
        'submit',
        'reopen',
      ], reason: '状态机每次变化都要留审计事件');
    });

    test('非法状态/不存在的 id:静默忽略,不改行也不写事件', () async {
      final id = await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: 'read',
        title: 'x',
      );
      await DatabaseService.updateTutorTaskStatus(id, '不存在的状态');
      expect((await taskRow(id))!['status'], 'pending');
      expect(
        await DatabaseService.listTaskEvents(id),
        hasLength(1),
        reason: '只有 create 一条,非法状态不能落事件',
      );

      await DatabaseService.updateTutorTaskStatus(999999, 'done');
      final db = await DatabaseService.database;
      expect((await db.query('task_events')).length, 1);
    });

    test('skipped / expired 转换也落对应事件', () async {
      final skipId = await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: 'review',
        title: '要跳过的',
      );
      await DatabaseService.updateTutorTaskStatus(skipId, 'skipped');
      expect((await taskRow(skipId))!['status'], 'skipped');
      expect(
        (await DatabaseService.listTaskEvents(skipId)).last['event'],
        'skip',
      );

      final expireId = await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: 'review',
        title: '要过期的',
      );
      await DatabaseService.updateTutorTaskStatus(expireId, 'expired');
      expect(
        (await DatabaseService.listTaskEvents(expireId)).last['event'],
        'expire',
      );
    });
  });

  group('旧 API 兼容(completeTutorTask / reopenTutorTask)', () {
    test('旧勾选也同步 status 与事件;撤销完成回 pending', () async {
      final id = await DatabaseService.insertTutorTask(
        planDate: DateTime.now(),
        kind: 'read',
        title: '旧 UI 勾选',
      );
      expect(await DatabaseService.completeTutorTask(id, result: {'x': 1}), 1);
      var row = (await taskRow(id))!;
      expect(row['status'], 'done');
      expect('${row['done_at'] ?? ''}', isNotEmpty);
      expect(
        (await DatabaseService.listTaskEvents(id)).last['event'],
        'submit',
      );

      expect(await DatabaseService.reopenTutorTask(id), 1);
      row = (await taskRow(id))!;
      expect(row['status'], 'pending');
      expect(row['done_at'], isNull);
      expect(row['result_json'], isNull);
      expect(
        (await DatabaseService.listTaskEvents(id)).last['event'],
        'reopen',
      );
    });
  });

  group('listTutorTasks 筛选', () {
    test('按日期/状态筛选,非法筛选值忽略而不是返回空', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final a = await DatabaseService.insertTutorTask(
        planDate: today,
        kind: 'read',
        title: '今天 A',
      );
      final b = await DatabaseService.insertTutorTask(
        planDate: today,
        kind: 'review',
        title: '今天 B',
      );
      await DatabaseService.updateTutorTaskStatus(b, 'active');
      final c = await DatabaseService.insertTutorTask(
        planDate: yesterday,
        kind: 'read',
        title: '昨天 C',
      );

      final todayList = await DatabaseService.listTutorTasks(
        planDate: dayText(0),
      );
      expect(todayList.map((r) => r['id']).toSet(), {a, b});

      final active = await DatabaseService.listTutorTasks(status: 'active');
      expect(active.map((r) => r['id']).toList(), [b]);

      final ignored = await DatabaseService.listTutorTasks(status: '不存在的状态');
      expect(ignored, hasLength(3), reason: '非法状态应忽略筛选,不能静默返回空');

      final limited = await DatabaseService.listTutorTasks(limit: 1);
      expect(limited, hasLength(1));

      // 昨天任务仍在全部列表里(默认 limit 50,plan_date DESC → 今天在前)
      final all = await DatabaseService.listTutorTasks();
      expect(all.map((r) => r['id']).toSet(), {a, b, c});
      expect(all.first['plan_date'], startsWith(dayText(0)));
    });
  });

  group('taskCompletionStats 完成率口径(research §2.4.4)', () {
    test('expired 进分母、pending/active 不进;avg 只算 done 的实际分钟', () async {
      final today = DateTime.now();
      final ids = <int>[];
      for (final title in [
        'done1',
        'done2',
        'skip1',
        'expire1',
        'pending1',
        'active1',
      ]) {
        ids.add(
          await DatabaseService.insertTutorTask(
            planDate: today,
            kind: 'read',
            title: title,
          ),
        );
      }
      await DatabaseService.updateTutorTaskStatus(
        ids[0],
        'done',
        actualMinutes: 10,
      );
      await DatabaseService.updateTutorTaskStatus(
        ids[1],
        'done',
        actualMinutes: 20,
      );
      await DatabaseService.updateTutorTaskStatus(ids[2], 'skipped');
      await DatabaseService.updateTutorTaskStatus(ids[3], 'expired');
      await DatabaseService.updateTutorTaskStatus(ids[5], 'active');

      final stats = await DatabaseService.taskCompletionStats();
      expect(stats['planned'], 6, reason: 'planned 含 pending/active');
      expect(stats['done'], 2);
      expect(stats['skipped'], 1);
      expect(stats['expired'], 1);
      // 2 / (2+1+1) = 0.5 —— expired 若被排除会变成 2/3,复盘数字就是骗人的
      expect(stats['completionRate'] as double, closeTo(0.5, 1e-9));
      expect(stats['avgActualMinutes'] as double, closeTo(15, 1e-9));
    });

    test('since 过滤:只统计该日期起的任务;空库给 0/null 不崩', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final oldId = await DatabaseService.insertTutorTask(
        planDate: yesterday,
        kind: 'read',
        title: '昨天的任务',
      );
      await DatabaseService.updateTutorTaskStatus(
        oldId,
        'done',
        actualMinutes: 30,
      );
      final todayId = await DatabaseService.insertTutorTask(
        planDate: today,
        kind: 'read',
        title: '今天的任务',
      );
      await DatabaseService.updateTutorTaskStatus(todayId, 'skipped');

      final allStats = await DatabaseService.taskCompletionStats();
      expect(allStats['planned'], 2);
      expect(allStats['done'], 1);
      expect(allStats['completionRate'] as double, closeTo(0.5, 1e-9));

      final sinceToday = await DatabaseService.taskCompletionStats(
        since: today,
      );
      expect(sinceToday['planned'], 1);
      expect(sinceToday['done'], 0);
      expect(sinceToday['skipped'], 1);
      expect(
        sinceToday['completionRate'] as double,
        0.0,
        reason: '只有 skipped → 完成率 0',
      );
      expect(
        sinceToday['avgActualMinutes'],
        isNull,
        reason: '没有 done 实际分钟样本 → null,不伪造 0',
      );

      // 全部为空的新库
      await DatabaseService.resetForTest();
      final db = await DatabaseService.database;
      await db.delete('tutor_tasks');
      final emptyStats = await DatabaseService.taskCompletionStats();
      expect(emptyStats['planned'], 0);
      expect(emptyStats['completionRate'] as double, 0.0);
      expect(emptyStats['avgActualMinutes'], isNull);
    });
  });
}
