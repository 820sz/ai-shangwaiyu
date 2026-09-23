import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/database.dart';

/// 数据库迁移回归(v2.0 起)。
///
/// 为什么必须真跑 SQLite(而不是断言常量):
/// 迁移是**一旦错就不可自愈**的代码 —— v1.9.0 审查里最贵的一条(P0-2)就是
/// "迁移失败被吞掉、user_version 照推,失败的步骤永不重跑",用户只能清数据。
/// 这个文件用 sqflite_common_ffi 在纯 Dart 里跑真 SQLite,覆盖两条路径:
/// ① 全新安装(onCreate);② 从 v10 旧库升级(onUpgrade),并检查旧词被正确地
/// 初始化成复习状态(而不是"永不到期")。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_db_migration_test');
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

  Future<Set<String>> indexNames(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    );
    return rows.map((r) => '${r['name']}').toSet();
  }

  Future<Set<String>> columns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => '${r['name']}').toSet();
  }

  const v2Tables = [
    'word_review',
    'materials',
    'material_content',
    'material_progress',
    'reading_sessions',
    'quiz_results',
    'error_tags',
    'tutor_tasks',
    'tutor_messages',
    'tutor_memory',
  ];

  test('全新安装:v11 的十张 v2.0 表 + 双音标列 + 索引全部建好', () async {
    final db = await DatabaseService.database;

    final tables = await tableNames(db);
    expect(tables, containsAll(v2Tables));
    // 老表一张都不能少(自检/建表改动最容易误删)
    expect(
      tables,
      containsAll([
        'vocabulary', 'articles', 'exercises', 'daily_log', 'memory',
        'bookmarks', 'writing_logs', 'recommendations',
      ]),
    );

    final vocabCols = await columns(db, 'vocabulary');
    expect(vocabCols, containsAll(['phonetic', 'phonetic_uk', 'phonetic_us']));
    // v1.9.0 修过的坑:phonetic 必须在 onCreate 里就有
    expect(vocabCols, contains('material_path'));

    final indexes = await indexNames(db);
    expect(
      indexes,
      containsAll([
        'idx_vocab_created',
        'idx_word_review_due',
        'idx_materials_kind',
        'idx_tutor_task_date',
      ]),
    );

    // user_version 必须已经推到当前版本,否则下次启动会重跑迁移
    final version = await db.getVersion();
    expect(version, AppConstants.dbVersion);
  });

  test('从 v10 旧库升级:表补齐、旧词初始化复习状态、due 不是"永不到期"', () async {
    final path = p.join(tmp.path, AppConstants.dbName);

    // ① 手工造一个 v10 库:只有老表(且 vocabulary 没有双音标列)
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE vocabulary (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              word TEXT NOT NULL,
              translation TEXT,
              mastery_level INTEGER DEFAULT 0,
              phonetic TEXT,
              category TEXT,
              material_path TEXT,
              created_at TEXT,
              updated_at TEXT
            )
          ''');
        },
      ),
    );
    final now = DateTime.now().toIso8601String();
    await legacy.insert('vocabulary', {
      'word': 'fresh',
      'mastery_level': 0,
      'created_at': now,
      'updated_at': now,
    });
    await legacy.insert('vocabulary', {
      'word': 'learning',
      'mastery_level': 1,
      'created_at': now,
      'updated_at': now,
    });
    await legacy.insert('vocabulary', {
      'word': 'mastered',
      'mastery_level': 2,
      'created_at': now,
      'updated_at': now,
    });
    await legacy.close();

    // ② 用真实服务打开 → 触发 onUpgrade(10 → 11)
    final db = await DatabaseService.database;
    expect(await db.getVersion(), AppConstants.dbVersion);

    final tables = await tableNames(db);
    expect(tables, containsAll(v2Tables));

    final cols = await columns(db, 'vocabulary');
    expect(cols, containsAll(['phonetic_uk', 'phonetic_us']));

    // ③ 旧词必须有复习状态,且到期时间符合"保守初值"的约定
    final seeded = await db.query('word_review', orderBy: 'vocab_id');
    expect(seeded.length, 3, reason: '三个旧词都该被初始化');

    final byWord = <String, Map<String, Object?>>{};
    for (final row in seeded) {
      final v = await db.query(
        'vocabulary',
        columns: ['word'],
        where: 'id = ?',
        whereArgs: [row['vocab_id']],
      );
      byWord['${v.first['word']}'] = row;
    }

    for (final row in seeded) {
      final due = DateTime.parse('${row['due_at']}');
      // 关键断言:没有任何词被设成"永不到期"(NULL/空/遥远未来)
      expect('${row['due_at']}'.isNotEmpty, isTrue);
      expect(
        due.isBefore(DateTime.now().add(const Duration(days: 30))),
        isTrue,
        reason: '旧词必须重新排队,不能因为"已掌握"就永不复习',
      );
    }
    expect(byWord['fresh']!['reps'], 0);
    expect(byWord['learning']!['reps'], 1);
    expect(byWord['mastered']!['reps'], 1);
    expect(
      DateTime.parse('${byWord['mastered']!['due_at']}')
          .isAfter(DateTime.parse('${byWord['learning']!['due_at']}')),
      isTrue,
      reason: '已掌握的词给更长的稳定期',
    );
  });

  test('重复打开不会重复初始化(迁移幂等)', () async {
    final db1 = await DatabaseService.database;
    await db1.insert('vocabulary', {
      'word': 'idempotent',
      'mastery_level': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
    // 模拟"再次启动":关掉连接重新打开(onOpen 自检 + 迁移都会再跑一遍)
    await DatabaseService.resetForTest();
    final db2 = await DatabaseService.database;
    final rows = await db2.query('word_review');
    expect(rows.length, 1, reason: '同一个词不能出现两条复习记录');
  });
}
