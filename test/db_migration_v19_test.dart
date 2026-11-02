import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/database.dart';

/// 迁移回归:材料路径/分组名归一(dbVersion 19)+ 阅读器译文落库(dbVersion 20)。
///
/// 背景(用户 2026-11-01 截图):「移动材料」把完整 `material_path` 当材料名
/// 二次拼分类前缀 → `书籍/书籍/《Character》`;而分组键就是原始路径字符串,
/// 于是同一本书被拆成两个分组("移动后不并入老分类,而是重复新建")。
///
/// 为什么必须真跑 SQLite(而不是只测纯函数):迁移一旦写错就**不可自愈** ——
/// 库已经在用户手机上,没有"重装"选项(参见 v1.9.0 审查 P0-2 的教训)。
/// 覆盖:
/// ① 全新安装(版本推到当前 dbVersion、迁移不误伤干净数据);
/// ② 从 v18 旧库升级(onUpgrade 18→19 的路径归一,链路继续到当前版本);
/// ③ 已开库被旧链路写入脏数据后重启(_onOpen 自检兜底),并验证**幂等**;
/// ④ v19 → v20 升级(建 material_translations,老数据不动、译文可写可读、幂等)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_db_migration_v19_test');
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

  Future<Map<String, Object?>> vocabRow(Database db, String word) async {
    final rows = await db.query(
      'vocabulary',
      where: 'word = ?',
      whereArgs: [word],
    );
    expect(rows.length, 1, reason: '迁移只能 UPDATE,不能删行/插行');
    return rows.single;
  }

  test('全新安装:版本推到当前(dbVersion),干净数据不被迁移改写', () async {
    final db = await DatabaseService.database;
    expect(await db.getVersion(), AppConstants.dbVersion);

    final now = DateTime.now().toIso8601String();
    await db.insert('vocabulary', {
      'word': 'apple',
      'category': '书籍',
      'material_path': '书籍/《Character》',
      'source_book': '《Character》',
      'created_at': now,
    });
    // 模拟"再次启动":迁移/自检都会再跑一遍,干净数据必须原样
    await DatabaseService.resetForTest();
    final db2 = await DatabaseService.database;
    final row = await vocabRow(db2, 'apple');
    expect(row['material_path'], '书籍/《Character》');
    expect(row['source_book'], '《Character》');
  });

  test('v18 → v19 升级:清掉重复分类前缀、修 source_book、保留 id 与复习状态', () async {
    final path = p.join(tmp.path, AppConstants.dbName);

    // ① 手工造 v18 库:只建这次迁移要碰的表。其余表由 _onOpen 自检补建 ——
    //    这正是真实"半迁移库"的路径,顺带验证自检不会因为表缺而崩。
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 18,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE vocabulary (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              word TEXT NOT NULL,
              translation TEXT,
              source_book TEXT,
              source_page TEXT,
              original_sentence TEXT,
              photo_path TEXT,
              word_type TEXT DEFAULT 'word',
              mastery_level INTEGER DEFAULT 0,
              category TEXT,
              material_path TEXT,
              created_at TEXT,
              updated_at TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT,
              group_name TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE word_review (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              vocab_id INTEGER,
              stability REAL,
              difficulty REAL,
              due_at TEXT,
              reps INTEGER DEFAULT 0,
              lapses INTEGER DEFAULT 0,
              created_at TEXT,
              updated_at TEXT
            )
          ''');
        },
      ),
    );
    final now = DateTime.now().toIso8601String();
    final appleId = await legacy.insert('vocabulary', {
      'word': 'apple',
      'category': '书籍',
      'material_path': '书籍/《Character》',
      'source_book': '《Character》',
      'mastery_level': 1,
      'created_at': now,
    });
    final bananaId = await legacy.insert('vocabulary', {
      'word': 'banana',
      'category': '书籍',
      // 一次移动产生的脏值
      'material_path': '书籍/书籍/《Character》',
      'source_book': '书籍/《Character》',
      'mastery_level': 2,
      'created_at': now,
    });
    final depositId = await legacy.insert('vocabulary', {
      'word': 'deposit',
      'category': '教材',
      // 更深一层(教材本身两级 + 二次拼接)
      'material_path': '教材/教材/新概念英语/第2册',
      'source_book': '教材/新概念英语/第2册',
      'created_at': now,
    });
    final legitId = await legacy.insert('vocabulary', {
      'word': 'legit',
      'category': '书籍',
      // 合法数据:材料名恰好叫「书籍」,只有两段,不能折
      'material_path': '书籍/书籍',
      'source_book': '书籍',
      'created_at': now,
    });
    await legacy.insert('materials', {
      'title': '材料A',
      'group_name': '书籍/书籍/《Character》',
    });
    await legacy.insert('materials', {
      'title': '材料B',
      'group_name': '新视野教材',
    });
    await legacy.insert('word_review', {
      'vocab_id': bananaId,
      'stability': 3.0,
      'difficulty': 5.0,
      'due_at': now,
      'reps': 2,
      'lapses': 1,
      'created_at': now,
      'updated_at': now,
    });
    await legacy.close();

    // ② 真服务打开 → onUpgrade(18→19) + onOpen 自检
    final db = await DatabaseService.database;
    expect(await db.getVersion(), AppConstants.dbVersion);

    // ③ 路径归一:脏的并回老分类,干净的/合法的原样
    final apple = await vocabRow(db, 'apple');
    final banana = await vocabRow(db, 'banana');
    final deposit = await vocabRow(db, 'deposit');
    final legit = await vocabRow(db, 'legit');
    expect(apple['material_path'], '书籍/《Character》');
    expect(banana['material_path'], '书籍/《Character》',
        reason: '书籍/书籍/《X》必须并回 书籍/《X》,否则永远两个分组');
    expect(deposit['material_path'], '教材/新概念英语/第2册');
    expect(legit['material_path'], '书籍/书籍',
        reason: '两段的「书籍/书籍」是合法材料名,折成单段会掉进未归类');

    // ④ source_book 只修"被写成整条路径"的(以 分类/ 开头),短书名不动
    expect(banana['source_book'], '《Character》');
    expect(apple['source_book'], '《Character》');
    expect(deposit['source_book'], '新概念英语/第2册');
    expect(legit['source_book'], '书籍');

    // ⑤ id 不变 + 掌握度/复习状态不受影响(复习记录按 vocab_id 关联)
    expect(banana['id'], bananaId);
    expect(apple['id'], appleId);
    expect(deposit['id'], depositId);
    expect(legit['id'], legitId);
    expect(banana['mastery_level'], 2);
    final reviews = await db.query('word_review');
    // 迁移只 UPDATE 路径,不能清掉已有复习记录;其余 3 个词由 _onOpen 的
    // "复习状态初始化"补建(那是自检职责,不是迁移 —— 这里只锁"旧记录没丢")
    final bananaReview =
        reviews.where((r) => r['vocab_id'] == bananaId).toList();
    expect(bananaReview.length, 1, reason: '已有复习记录不能被迁移清掉');
    expect(bananaReview.single['reps'], 2);

    // ⑥ materials.group_name 同一份"重复前导段"病,按通用规则折
    final materialA = await db.query('materials',
        where: 'title = ?', whereArgs: ['材料A']);
    final materialB = await db.query('materials',
        where: 'title = ?', whereArgs: ['材料B']);
    expect(materialA.single['group_name'], '书籍/《Character》');
    expect(materialB.single['group_name'], '新视野教材');

    // ⑦ 幂等:再启动一次(迁移/自检重跑)不能改出新值
    await DatabaseService.resetForTest();
    final db2 = await DatabaseService.database;
    expect(await db2.getVersion(), AppConstants.dbVersion);
    final banana2 = await vocabRow(db2, 'banana');
    expect(banana2['material_path'], '书籍/《Character》');
    expect(banana2['source_book'], '《Character》');
  });

  test('_onOpen 自检:旧链路在已开库里写进脏数据,下次启动自动清理(幂等)', () async {
    final db = await DatabaseService.database;
    expect(await db.getVersion(), AppConstants.dbVersion);
    final now = DateTime.now().toIso8601String();

    Future<void> insertDirty() async {
      await db.insert('vocabulary', {
        'word': 'cherry',
        'category': '书籍',
        'material_path': '书籍/书籍/《Character》',
        'source_book': '书籍/《Character》',
        'created_at': now,
      });
    }

    await insertDirty();
    // 重启:走 _onOpen 自检(没有版本升级,也会兜底修)
    await DatabaseService.resetForTest();
    final db2 = await DatabaseService.database;
    expect((await vocabRow(db2, 'cherry'))['material_path'], '书籍/《Character》');
    expect((await vocabRow(db2, 'cherry'))['source_book'], '《Character》');

    // 再写一次脏数据再重启:必须继续能修(幂等,不是"只修一次"的开关)
    await db2.insert('vocabulary', {
      'word': 'date',
      'category': '书籍',
      'material_path': '书籍/书籍/书籍/《Character》',
      'source_book': '书籍/书籍/《Character》',
      'created_at': now,
    });
    await DatabaseService.resetForTest();
    final db3 = await DatabaseService.database;
    final dateRow = await vocabRow(db3, 'date');
    expect(dateRow['material_path'], '书籍/《Character》');
    expect(dateRow['source_book'], '《Character》');
    // 已修过的不能被二次改写
    expect((await vocabRow(db3, 'cherry'))['material_path'], '书籍/《Character》');
  });

  test('v19 旧库升级到当前版本:建 material_translations,旧数据不动、翻译落库(幂等)', () async {
    final path = p.join(tmp.path, AppConstants.dbName);

    // ① 手工造 v19 库:只建迁移/自检要碰的最小表。
    //    v19→v20 是**纯建表**迁移,不读不写旧数据 —— 所以这里故意只给最小 schema,
    //    顺带验证 _onOpen 自检能把其余表/列补齐(半迁移库自愈路径)。
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 19,
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
    final beforeCount = (await legacy.rawQuery('SELECT COUNT(*) AS c FROM vocabulary'))
        .first['c'] as int;
    await legacy.close();

    // ② 真服务打开 → onUpgrade(19→20) + onOpen 自检
    final db = await DatabaseService.database;
    expect(await db.getVersion(), AppConstants.dbVersion);

    // 新表存在且可写
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='material_translations'",
    );
    expect(tables.length, 1, reason: 'v20 必须建出 material_translations');

    // 老数据不动
    final afterCount = (await db.rawQuery('SELECT COUNT(*) AS c FROM vocabulary'))
        .first['c'] as int;
    expect(afterCount, beforeCount);
    expect((await vocabRow(db, 'legacy'))['material_path'], '书籍/《Character》');

    // ③ 翻译能写能读(迁移后功能立即可用)
    await DatabaseService.saveMaterialTranslation(
      7,
      unitIndex: 0,
      chunkIndex: 0,
      sourceText: 'Hello world.',
      translatedText: '你好,世界。',
      model: 'deepseek-flash',
    );
    final saved = await DatabaseService.loadMaterialTranslations(7);
    expect(saved, {0: '你好,世界。'});

    // ④ 幂等:再启动一次(迁移/自检重跑)表与数据都还在,不会重复建/丢数据
    await DatabaseService.resetForTest();
    final db2 = await DatabaseService.database;
    expect(await db2.getVersion(), AppConstants.dbVersion);
    expect((await DatabaseService.loadMaterialTranslations(7))[0], '你好,世界。');
    final rows = await db2.query('material_translations');
    expect(rows.length, 1, reason: '重复打开不能把译文变成多行/丢失');
  });
}
