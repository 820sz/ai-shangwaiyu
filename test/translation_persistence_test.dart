import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/database.dart';

/// v2.16.0 回归(阅读器翻译根治):译文落库。
///
/// 用户原话:「翻译永远没法用」—— 旧实现译文只存内存,退出阅读器再进就全没了,
/// 每次都得从 0 重翻、每次都可能再失败一次。这里用**真 SQLite** 锁住落库语义:
/// - 写 → 读(按 material 隔离);
/// - 重翻同一段 = UPSERT 覆盖(不产生第二行、updated_at 更新);
/// - source_text 快照不匹配 → [DatabaseService.alignTranslationsToUnits] 不返回
///   (材料重新导入/切段变化后 unit 下标会漂移;错位的译文比没有更糟);
/// - 重复打开数据库幂等(表在/数据在,不会重复迁移)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_translation_persist_test');
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

  Future<int> countRows(int materialId) async {
    final db = await DatabaseService.database;
    final rows = await db.query(
      'material_translations',
      where: 'material_id = ?',
      whereArgs: [materialId],
    );
    return rows.length;
  }

  test('写 → 读:按材料隔离,记录带 source_text / model / updated_at', () async {
    await DatabaseService.saveMaterialTranslation(
      7,
      unitIndex: 0,
      chunkIndex: 0,
      sourceText: 'First paragraph.',
      translatedText: '第一段。',
      model: 'deepseek-flash',
    );
    await DatabaseService.saveMaterialTranslation(
      7,
      unitIndex: 2,
      chunkIndex: 1,
      sourceText: 'Third paragraph.',
      translatedText: '第三段。',
    );
    await DatabaseService.saveMaterialTranslation(
      8,
      unitIndex: 0,
      chunkIndex: 0,
      sourceText: 'Other material.',
      translatedText: '别的材料。',
    );

    expect(await DatabaseService.loadMaterialTranslations(7),
        {0: '第一段。', 2: '第三段。'});
    expect(await DatabaseService.loadMaterialTranslations(8), {0: '别的材料。'});
    expect(await DatabaseService.loadMaterialTranslations(999), isEmpty);

    final records = await DatabaseService.loadMaterialTranslationRecords(7);
    expect(records.length, 2);
    final first = records.firstWhere((r) => r.unitIndex == 0);
    expect(first.sourceText, 'First paragraph.');
    expect(first.model, 'deepseek-flash');
    expect(first.updatedAt, isNotNull);
  });

  test('重翻同一段 = UPSERT 覆盖:不产生第二行,updated_at 前进、created_at 不变', () async {
    await DatabaseService.saveMaterialTranslation(
      7,
      unitIndex: 1,
      chunkIndex: 0,
      sourceText: 'Rewrite me.',
      translatedText: '旧译文',
    );
    final db = await DatabaseService.database;
    final before = (await db.query('material_translations')).single;
    final createdAt = '${before['created_at']}';
    final oldUpdatedAt = '${before['updated_at']}';

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await DatabaseService.saveMaterialTranslation(
      7,
      unitIndex: 1,
      chunkIndex: 0,
      sourceText: 'Rewrite me.',
      translatedText: '新译文(重翻)',
      model: 'deepseek-flash',
    );

    expect(await countRows(7), 1, reason: '同一段只能一行(UNIQUE 约束)');
    final after = (await db.query('material_translations')).single;
    expect(after['translated_text'], '新译文(重翻)');
    expect(after['created_at'], createdAt, reason: 'created_at 记第一次翻成功的时间');
    expect('${after['updated_at']}'.compareTo(oldUpdatedAt), greaterThan(0),
        reason: '重翻必须刷新 updated_at');
    expect(after['model'], 'deepseek-flash');
  });

  test('source_text 防错位:文本一致才返回,切段变化后不返回', () async {
    await DatabaseService.saveMaterialTranslation(
      7,
      unitIndex: 0,
      chunkIndex: 0,
      sourceText: 'The quick brown fox.',
      translatedText: '敏捷的棕色狐狸。',
    );

    final records = await DatabaseService.loadMaterialTranslationRecords(7);

    // 目录①:当前切段与落库时一致 → 返回
    expect(
      DatabaseService.alignTranslationsToUnits(records, ['The quick brown fox.']),
      {0: '敏捷的棕色狐狸。'},
    );
    // 只差空白(重新导入常带换行/多空格)→ 仍算一致
    expect(
      DatabaseService.alignTranslationsToUnits(
          records, ['  The  quick\nbrown fox.  ']),
      {0: '敏捷的棕色狐狸。'},
    );
    // 目录②:材料重新导入/切段变化 → 同下标是别的段落 → 丢弃(宁可重翻)
    expect(
      DatabaseService.alignTranslationsToUnits(
          records, ['A completely different paragraph.']),
      isEmpty,
    );
    // 目录③:文本变短导致下标越界 → 丢弃,不越界崩溃
    expect(DatabaseService.alignTranslationsToUnits(records, []), isEmpty);
  });

  test('脏输入不落库(空译文/空原文/负下标),不会占住 UNIQUE 槽位', () async {
    await DatabaseService.saveMaterialTranslation(
      7,
      unitIndex: 0,
      chunkIndex: 0,
      sourceText: 'Keep me.',
      translatedText: '   ',
    );
    await DatabaseService.saveMaterialTranslation(
      7,
      unitIndex: -1,
      chunkIndex: 0,
      sourceText: 'Bad index.',
      translatedText: '不该落库',
    );
    expect(await countRows(7), 0);

    await DatabaseService.saveMaterialTranslation(
      7,
      unitIndex: 0,
      chunkIndex: 0,
      sourceText: 'Keep me.',
      translatedText: '保留。',
    );
    expect(await countRows(7), 1);
  });

  test('deleteMaterialTranslations 只清指定材料;重复打开数据库幂等', () async {
    await DatabaseService.saveMaterialTranslation(7,
        unitIndex: 0, chunkIndex: 0, sourceText: 'A', translatedText: '甲');
    await DatabaseService.saveMaterialTranslation(8,
        unitIndex: 0, chunkIndex: 0, sourceText: 'B', translatedText: '乙');

    expect(await DatabaseService.deleteMaterialTranslations(7), 1);
    expect(await DatabaseService.loadMaterialTranslations(7), isEmpty);
    expect(await DatabaseService.loadMaterialTranslations(8), {0: '乙'});

    // 模拟"再次启动":关连接重开(onUpgrade/onOpen 重跑)后数据必须还在
    await DatabaseService.resetForTest();
    final db = await DatabaseService.database;
    expect(await db.getVersion(), AppConstants.dbVersion);
    expect(await DatabaseService.loadMaterialTranslations(8), {0: '乙'});
    expect(await countRows(7), 0);
  });
}
