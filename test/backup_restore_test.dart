import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/backup_service.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/export_service.dart';
import 'package:readflow/services/fsrs.dart';
import 'package:readflow/services/learner_model_store.dart';
import 'package:readflow/services/review_queue.dart';

/// 备份导入的集成测试(真 SQLite + 真 Hive)。
///
/// 这是全项目**最不能出错**的一条路径:导出没人会天天点,但一旦用它,
/// 场景就是"换机/丢机/清数据"—— 导入错了等于数据没了。
/// 所以这里逐条验证:合并去重、覆盖清空、复习状态(含到期时间)是否真的回来了、
/// 画像与设置是否恢复、以及**坏备份不会毁掉现有数据**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Directory hiveDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_backup_test');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
    hiveDir = await Directory.systemTemp.createTemp('hive_backup_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    try {
      await databaseFactory
          .deleteDatabase('${tmp.path}/${AppConstants.dbName}');
    } catch (_) {}
    await Hive.deleteFromDisk();
    tmp.deleteSync(recursive: true);
    hiveDir.deleteSync(recursive: true);
  });

  /// 造一份"本地已有数据"并生成备份 JSON
  Future<String> seedAndBackup() async {
    final alpha = await DatabaseService.insertVocabulary(
      Vocabulary(word: 'alpha', translation: '第一个', phoneticUk: 'ælfə'),
    );
    final beta = await DatabaseService.insertVocabulary(
      Vocabulary(word: 'beta', translation: '第二个', masteryLevel: 2),
    );
    final now = DateTime.now();
    await DatabaseService.upsertWordReview(
      alpha,
      stability: 12.5,
      difficulty: 5.5,
      dueAt: now.add(const Duration(days: 3)),
      lastReviewAt: now.subtract(const Duration(days: 1)),
      lastRating: 3,
    );
    await DatabaseService.upsertWordReview(
      beta,
      stability: 30,
      difficulty: 4,
      dueAt: now.subtract(const Duration(days: 2)),
      lastReviewAt: now.subtract(const Duration(days: 3)),
      lastRating: 2,
    );
    await LearnerModelStore.save(
      LearnerModel(
        dailyMinutes:
            ProfileField<int>(value: 45, source: ProfileSource.self),
        maxNewWords: ProfileField<int>(value: 10, source: ProfileSource.self),
      ),
    );
    await Hive.box(AppConstants.hiveBoxSettings)
        .put(AppConstants.keyTtsAccent, 'uk');

    final vocab = await DatabaseService.getVocabularies(limit: 1000);
    final cards = ReviewQueue.cardsFromRows(
      await DatabaseService.getWordReviews(),
      now: now,
    );
    return ExportService.backupJson(
      vocab: vocab,
      cards: cards,
      model: LearnerModelStore.load(),
      settings: const {'tts_accent': 'uk'},
    );
  }

  test('合并导入:新词进库、重复词跳过、复习状态与到期时间原样恢复', () async {
    final backup = await seedAndBackup();

    // 模拟"换机":清空一切
    final ids = [
      for (final v in await DatabaseService.getVocabularies(limit: 1000))
        if (v.id != null) v.id!,
    ];
    await DatabaseService.deleteVocabularies(ids);
    await DatabaseService.clearWordReviews();
    expect((await DatabaseService.getVocabularies(limit: 1000)), isEmpty);

    final data = ExportService.parseBackup(backup);
    expect(data.ok, isTrue, reason: data.error ?? '');
    final report = await BackupService.restore(data, replace: false);

    expect(report.added, 2);
    expect(report.cardsRestored, 2);
    final restored = await DatabaseService.getVocabularies(limit: 1000);
    expect(restored.map((v) => v.word).toSet(), {'alpha', 'beta'});
    expect(
      restored.firstWhere((v) => v.word == 'alpha').phoneticUk,
      'ælfə',
      reason: '双音标要跟着备份走',
    );

    final cards = ReviewQueue.cardsFromRows(
      await DatabaseService.getWordReviews(),
      now: DateTime.now(),
    );
    expect(cards.length, 2);
    final alphaCard = cards.values.firstWhere((c) => c.stability == 12.5);
    expect(alphaCard.reps, 1, reason: 'DB 的 reps 由写入语义管理(首次写入=1)');
    expect(alphaCard.lastRating, FsrsRating.good);
    // beta 是过期的卡:导入后必须仍然过期(而不是被重置成"今天到期")
    final lateCards = cards.values.where(
      (c) => c.due.isBefore(DateTime.now().subtract(const Duration(days: 1))),
    );
    expect(lateCards, isNotEmpty, reason: '过期的复习状态必须保留');
  });

  test('合并导入不会覆盖本地已有词(按词面去重,大小写不敏感)', () async {
    final backup = await seedAndBackup();
    // 本地先放一个同名词但释义不同
    await DatabaseService.insertVocabulary(
      Vocabulary(word: 'Alpha', translation: '本地版本'),
    );
    final data = ExportService.parseBackup(backup);
    final report = await BackupService.restore(data, replace: false);

    expect(report.skipped, greaterThanOrEqualTo(1));
    final all = await DatabaseService.getVocabularies(limit: 1000);
    final local = all.firstWhere((v) => v.word == 'Alpha');
    expect(local.translation, '本地版本', reason: '合并模式不能改本地数据');
  });

  test('覆盖导入:先清空本地生词与复习状态,再写入备份', () async {
    final backup = await seedAndBackup();
    // 本地再加一个"备份里没有"的词
    await DatabaseService.insertVocabulary(
      Vocabulary(word: 'localonly', translation: '本地独有'),
    );
    final data = ExportService.parseBackup(backup);
    final report = await BackupService.restore(data, replace: true);

    expect(report.added, 2);
    final all = await DatabaseService.getVocabularies(limit: 1000);
    expect(all.map((v) => v.word).toSet(), {'alpha', 'beta'});
    expect(
      all.any((v) => v.word == 'localonly'),
      isFalse,
      reason: '覆盖导入的语义就是"以备份为准"',
    );
  });

  test('画像与设置白名单恢复(每日配额 + 朗读音色)', () async {
    final backup = await seedAndBackup();
    // 换机后本地是空的
    await Hive.box(AppConstants.hiveBoxSettings).delete(AppConstants.keyTtsAccent);
    await LearnerModelStore.save(LearnerModel());

    final data = ExportService.parseBackup(backup);
    final report = await BackupService.restore(data, replace: false);

    expect(report.replacedModel, isTrue);
    final model = LearnerModelStore.load();
    expect(model.dailyMinutes!.value, 45);
    expect(model.maxNewWords!.value, 10);
    expect(
      Hive.box(AppConstants.hiveBoxSettings).get(AppConstants.keyTtsAccent),
      'uk',
    );
  });

  test('坏备份不毁数据:解析失败时不落任何改动', () async {
    await DatabaseService.insertVocabulary(
      Vocabulary(word: 'keepme', translation: '必须还在'),
    );
    final bad = ExportService.parseBackup('{"app":"readflow","version":1,"vocab":"not-a-list"}');
    // vocab 不是列表 → 解析成 0 个词,但仍然是"合法备份"(只是空)
    expect(bad.ok, isTrue);
    final report = await BackupService.restore(bad, replace: false);
    expect(report.added, 0);
    final all = await DatabaseService.getVocabularies(limit: 1000);
    expect(all.map((v) => v.word), contains('keepme'));

    // 真正的坏输入(不是本 App 的备份)必须直接拒绝
    final rejected = ExportService.parseBackup('{"app":"other"}');
    expect(rejected.ok, isFalse);
    final r2 = await BackupService.restore(rejected, replace: false);
    expect(r2.added, 0);
    expect(r2.warnings, isNotEmpty);
    expect(
      (await DatabaseService.getVocabularies(limit: 1000)).length,
      1,
      reason: '拒绝导入时不能动本地数据',
    );
  });
}
