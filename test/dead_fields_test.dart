import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/learner_context.dart';
import 'package:readflow/services/learner_extras_sync.dart';
import 'package:readflow/services/learner_model_store.dart';

/// 死字段回写(C1-15)的**真 SQLite + 真 Hive** 回归。
///
/// 以前 `LearnerModel.extras` 的 `reading_wpm` / `vocab_inferred` 是**只读死字段**:
/// `LearnerContext` 在难度分析与阅读速度预估里读它们,却没有任何写入点 ——
/// 阅读速度永远回落默认 200wpm。这里钉死回写契约:
/// ① 有真实数据才写(`avg_wpm > 0` 且在读取端合法区间内;只有 test 测量基线才写词汇量);
/// ② 幂等:值没变不重复写盘(打开助理/统计页是高频动作);
/// ③ 回写不覆盖 extras 里其它键,也不会因为写失败影响页面。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Directory hiveDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_dead_fields_test');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
    hiveDir = await Directory.systemTemp.createTemp('hive_dead_fields_test');
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

  group('reading_wpm', () {
    test('近 30 天 avg_wpm > 0 时回写;值没变不重复写;新数据会更新', () async {
      // 没有任何阅读会话:不写(0 不是"速度为 0",是"没有数据")
      expect(await LearnerExtrasSync.syncReadingWpm(), isFalse);
      expect(
        LearnerModelStore.load().extras.containsKey(
              LearnerExtrasSync.readingWpmKey,
            ),
        isFalse,
      );

      // 300 词 / 2 分钟 = 150 wpm
      await DatabaseService.insertReadingSession(
        words: 300,
        duration: const Duration(minutes: 2),
      );
      expect(await LearnerExtrasSync.syncReadingWpm(), isTrue);
      final model = LearnerModelStore.load();
      expect(model.extras[LearnerExtrasSync.readingWpmKey], 150);
      // 回写后要真的被读取端用上(死字段复活 = 读取处拿到实测值而不是默认 200)
      expect(LearnerContext.wpmFor(model), 150);

      // 幂等:再同步一次不写盘
      expect(
        await LearnerExtrasSync.syncReadingWpm(),
        isFalse,
        reason: '值没变就不该重复写 Hive',
      );

      // 新会话把均值抬到 (150+300)/2 = 225 → 应当更新
      await DatabaseService.insertReadingSession(
        words: 600,
        duration: const Duration(minutes: 2),
      );
      expect(await LearnerExtrasSync.syncReadingWpm(), isTrue);
      expect(LearnerModelStore.load().extras[LearnerExtrasSync.readingWpmKey], 225);
    });

    test('时长为 0 / 速度不在读取端合法区间:不写(不藏脏值)', () async {
      // 时长为 0 → wpm 存 NULL → avg_wpm = 0 → 不写
      await DatabaseService.insertReadingSession(
        words: 300,
        duration: Duration.zero,
      );
      expect(await LearnerExtrasSync.syncReadingWpm(), isFalse);

      // 10 词 / 10 分钟 = 1 wpm:数值上 > 0,但读取端只认 60..1000,
      // 写进去等于藏一个永远不生效的脏值 → 这里先挡住
      await DatabaseService.insertReadingSession(
        words: 10,
        duration: const Duration(minutes: 10),
      );
      expect(await LearnerExtrasSync.syncReadingWpm(), isFalse);
      expect(
        LearnerModelStore.load().extras.containsKey(
              LearnerExtrasSync.readingWpmKey,
            ),
        isFalse,
      );
    });

    test('调用方传入快照算好的 avgWpm 时不再查库,同样生效', () async {
      expect(
        await LearnerExtrasSync.syncReadingWpm(avgWpm: 180.6),
        isTrue,
      );
      expect(LearnerModelStore.load().extras[LearnerExtrasSync.readingWpmKey], 181);
      expect(await LearnerExtrasSync.syncReadingWpm(avgWpm: 180.6), isFalse);
    });

    test('回写不覆盖 extras 里其它键', () async {
      await LearnerModelStore.save(
        LearnerModel(
          extras: <String, dynamic>{'legacy_note': '别动我', 'custom': 42},
        ),
      );
      await DatabaseService.insertReadingSession(
        words: 240,
        duration: const Duration(minutes: 2), // 120 wpm
      );
      expect(await LearnerExtrasSync.syncReadingWpm(), isTrue);
      final extras = LearnerModelStore.load().extras;
      expect(extras['legacy_note'], '别动我');
      expect(extras['custom'], 42);
      expect(extras[LearnerExtrasSync.readingWpmKey], 120);
    });
  });

  group('vocab_inferred', () {
    test('只有 test 来源的测量基线才写;自报不写;幂等', () async {
      // 自报来源(用户自己填的水平)不是测量 → 不写成"推断值"
      await LearnerModelStore.save(
        LearnerModel(
          vocabEstimate: ProfileField<int>(
            value: 5000,
            source: ProfileSource.self,
            confidence: 0.5,
          ),
        ),
      );
      expect(await LearnerExtrasSync.syncVocabInferred(), isFalse);
      expect(
        LearnerModelStore.load().extras.containsKey(
              LearnerExtrasSync.vocabInferredKey,
            ),
        isFalse,
      );

      // 无基线同样不写
      await LearnerModelStore.save(LearnerModel());
      expect(await LearnerExtrasSync.syncVocabInferred(), isFalse);

      // 测试得到的基线 → 写
      await LearnerModelStore.save(
        LearnerModel(
          vocabEstimate: ProfileField<int>(
            value: 4200,
            source: ProfileSource.test,
            confidence: 0.85,
          ),
        ),
      );
      expect(await LearnerExtrasSync.syncVocabInferred(), isTrue);
      expect(
        LearnerModelStore.load().extras[LearnerExtrasSync.vocabInferredKey],
        4200,
      );
      expect(
        await LearnerExtrasSync.syncVocabInferred(),
        isFalse,
        reason: '值没变不重复写',
      );
    });

    test('调用方传入助理快照里的模型时同样按同一口径写', () async {
      final model = LearnerModel(
        vocabEstimate: ProfileField<int>(
          value: 3600,
          source: ProfileSource.test,
          confidence: 0.8,
        ),
      );
      await LearnerModelStore.save(model);
      expect(
        await LearnerExtrasSync.syncVocabInferred(model: model),
        isTrue,
      );
      expect(
        LearnerModelStore.load().extras[LearnerExtrasSync.vocabInferredKey],
        3600,
      );
    });
  });

  test('syncAll:两个键一次补齐(打开统计页/助理的时机)', () async {
    await DatabaseService.insertReadingSession(
      words: 300,
      duration: const Duration(minutes: 2), // 150 wpm
    );
    await LearnerModelStore.save(
      LearnerModel(
        vocabEstimate: ProfileField<int>(
          value: 3000,
          source: ProfileSource.test,
          confidence: 0.8,
        ),
      ),
    );
    await LearnerExtrasSync.syncAll();
    final extras = LearnerModelStore.load().extras;
    expect(extras[LearnerExtrasSync.readingWpmKey], 150);
    expect(extras[LearnerExtrasSync.vocabInferredKey], 3000);
  });
}
