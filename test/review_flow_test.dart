import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/dictation.dart';
import 'package:readflow/services/fsrs.dart';
import 'package:readflow/services/material_library.dart';
import 'package:readflow/services/review_queue.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/word_frequency.dart';

/// 复习链路与听写链路的**整链路**回归(真 SQLite)。
///
/// 为什么这两个也要整链路测:`learning_flow_test` 一轮就换回三个真 bug,
/// 说明"每个模块单测都绿"不等于"用户那条路走得通"。这里按用户实际动作
/// **逐个复刻界面里的调用序列**(`_rate` / `_saveMissedWords`),再断言
/// "下一次打开页面时看到的东西"对不对 —— 数据写歪一点,单测看不出来,
/// 但用户在复习队列里会看到重复的词、或者收了词却永远不进复习。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_review_flow');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    // 难度分析要词频表:注入确定性词表(纯字母,名次=下标+1)
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    final words = <String>[
      for (var i = 0; i < 400; i++)
        '${letters[(i ~/ 676) % 26]}${letters[(i ~/ 26) % 26]}${letters[i % 26]}',
      'the', 'of', 'and', 'to', 'a', 'in', 'is', 'it', 'you', 'that',
      'weather', 'refused', 'strange', 'peculiar', 'obscure',
    ];
    WordFrequency.debugInject(
      words: words,
      counts: List<int>.generate(words.length, (i) => 100000 - i),
    );
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    await Hive.deleteFromDisk();
    try {
      await databaseFactory.deleteDatabase(p.join(tmp.path, AppConstants.dbName));
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 复刻 `review_screen._rate`:算下一张卡 → 落库 → 更新 mastery → 记错误档案
  Future<void> rateWord(
    ReviewQueueItem item,
    FsrsRating rating,
    DateTime now,
  ) async {
    final next = ReviewQueue.applyRating(item.card, rating, now: now);
    final id = item.vocab.id!;
    await DatabaseService.upsertWordReview(
      id,
      stability: next.stability,
      difficulty: next.difficulty,
      dueAt: next.due,
      lastReviewAt: now,
      lastRating: rating.value,
      lapse: rating == FsrsRating.again,
    );
    final mastery = ReviewQueue.isLongTermKnown(next)
        ? 2
        : (rating == FsrsRating.again ? 0 : 1);
    await DatabaseService.updateMastery(id, mastery);
    if (rating == FsrsRating.again) {
      await DatabaseService.bumpErrorTag(
        source: 'review',
        tag: '词汇',
        evidence: item.vocab.word,
      );
    }
  }

  Future<ReviewQueuePlan> buildQueue(DateTime now, {int maxNewWords = 10}) async {
    final vocab = await DatabaseService.getVocabularies(limit: 500);
    final cards = ReviewQueue.cardsFromRows(
      await DatabaseService.getWordReviews(),
      now: now,
    );
    return ReviewQueue.build(
      vocab: vocab,
      cards: cards,
      now: now,
      dailyMinutes: 20,
      maxNewWords: maxNewWords,
    );
  }

  group('复习链路', () {
    test('评分后:到期时间前移、lapses 累加、错误档案留痕,且队列不再当天重复出它', () async {
      final now = DateTime(2026, 9, 24, 20);
      final dueId = await DatabaseService.insertVocabulary(
        Vocabulary(word: 'weather', translation: '天气', createdAt: now),
      );
      // 一张"到期"的卡(昨天到期)
      await DatabaseService.upsertWordReview(
        dueId,
        stability: 5,
        difficulty: 5,
        dueAt: now.subtract(const Duration(days: 1)),
        lastReviewAt: now.subtract(const Duration(days: 6)),
        lastRating: 3,
      );

      var plan = await buildQueue(now);
      expect(plan.dueWords.map((i) => i.vocab.word), contains('weather'));
      final item = plan.dueWords.firstWhere((i) => i.vocab.word == 'weather');
      expect(item.card.lapses, 0, reason: '新建立的卡还没有遗忘记录');

      // 用户点「不认识」
      await rateWord(item, FsrsRating.again, now);

      final row = (await DatabaseService.getWordReviews())
          .firstWhere((r) => r['vocab_id'] == dueId);
      expect(row['lapses'], greaterThanOrEqualTo(1), reason: '不认识必须记一次遗忘');
      expect(DateTime.parse('${row['due_at']}').isAfter(now), isTrue,
          reason: '评分后到期时间要往后走(不能停在过去,否则队列永远清不完)');
      expect(row['last_rating'], FsrsRating.again.value);

      // 掌握度回退到"新词",并且进了错误档案
      final vocabRow = (await DatabaseService.getVocabularies(limit: 10))
          .firstWhere((v) => v.id == dueId);
      expect(vocabRow.masteryLevel, AppConstants.masteryNew);
      final tags = await DatabaseService.getErrorTags(status: 'active');
      expect(tags.map((t) => t['evidence']), contains('weather'));

      // 再次打开复习页:这个词不该马上又出现(到期时间已推到未来)
      plan = await buildQueue(now);
      expect(
        plan.dueWords.map((i) => i.vocab.word),
        isNot(contains('weather')),
        reason: '刚评过"不认识"的词到期时间在将来,不该立刻再出现',
      );
    });

    test('新词评"认识"后不再是新词:复习页的"新词额度"真实消耗', () async {
      final now = DateTime(2026, 9, 24, 21);
      final id = await DatabaseService.insertVocabulary(
        Vocabulary(word: 'peculiar', createdAt: now),
      );

      var plan = await buildQueue(now);
      expect(plan.newWords.map((i) => i.vocab.word), contains('peculiar'));

      final item = plan.newWords.firstWhere((i) => i.vocab.word == 'peculiar');
      await rateWord(item, FsrsRating.good, now);

      plan = await buildQueue(now);
      expect(
        plan.newWords.map((i) => i.vocab.word),
        isNot(contains('peculiar')),
        reason: '评过分的词已建立记忆状态,不能再算"新词"(否则额度永远用不完)',
      );
      expect(
        plan.dueWords.map((i) => i.vocab.word),
        isNot(contains('peculiar')),
        reason: '刚评分 → 到期时间在将来',
      );
      final row = (await DatabaseService.getWordReviews())
          .firstWhere((r) => r['vocab_id'] == id);
      expect(row['stability'], greaterThan(0), reason: '评分要真的写进稳定度');
      expect(double.parse('${row['stability']}'), greaterThan(0));
    });

    test('到期分桶与 7 天负荷预测和刚写进去的到期时间一致(小结页的数字不能凭空来)', () async {
      final now = DateTime(2026, 9, 24, 9);
      final id = await DatabaseService.insertVocabulary(
        Vocabulary(word: 'strange', createdAt: now),
      );
      await DatabaseService.upsertWordReview(
        id,
        stability: 10,
        difficulty: 5,
        dueAt: now.add(const Duration(days: 3)),
        lastReviewAt: now,
        lastRating: 3,
      );
      final rows = await DatabaseService.getWordReviews();
      final cards = ReviewQueue.cardsFromRows(rows, now: now);
      final buckets = FsrsScheduler.dueBuckets(cards.values.toList(), now: now);
      final forecast = FsrsScheduler.loadForecast(cards.values.toList(), now: now);
      expect(buckets.overdue, 0);
      expect(forecast.length, greaterThanOrEqualTo(4));
      expect(forecast[3], 1, reason: '第 4 天(索引 3)应当有 1 张到期卡');
      expect(forecast.take(3).every((n) => n == 0), isTrue);
    });
  });

  group('听写链路', () {
    test('抽句 → 打字(漏词)→ 判分 → 一键收词 → 真的进复习队列', () async {
      final now = DateTime(2026, 9, 24, 22);
      final model = LearnerModel(
        vocabEstimate: ProfileField<int>(value: 400, source: ProfileSource.test),
      );
      final text = 'The weather was strange that morning. '
          'Nobody could explain the peculiar noise. '
          'The old man refused to open the door.';
      final ingested = await MaterialLibrary.ingestText(
        title: '听写材料',
        text: text,
        model: model,
      );
      expect(ingested.materialId, greaterThan(0));

      final sentences = Dictation.pickSentences(text, seed: ingested.materialId);
      expect(sentences, isNotEmpty);

      // 用户听了一句,漏掉一个词
      final target = sentences.first;
      final words = target.split(' ');
      final typed = words.skip(1).join(' '); // 故意漏第一个词
      final result = Dictation.grade(target, typed);
      expect(result.accuracy, lessThan(1.0));
      // 判分把词面归一成小写(听写比的是词,不是大小写)
      expect(result.missing, contains(words.first.toLowerCase()));

      // 一键收词(复刻 dictation_screen._saveMissedWords 的落库部分)
      final missed = Dictation.missWords([result]);
      expect(missed, isNotEmpty);
      final inserted = await DatabaseService.insertVocabularies([
        for (final w in missed)
          Vocabulary(
            word: w,
            sourceBook: '听写材料',
            category: '其他',
            wordType: 'word',
            createdAt: now,
          ),
      ]);
      expect(inserted, missed.length);
      final saved = await DatabaseService.getVocabularies(limit: 100);
      var linked = 0;
      for (final w in missed) {
        final hit = saved.where((v) => v.word.toLowerCase() == w);
        if (hit.isEmpty || hit.first.id == null) continue;
        await DatabaseService.upsertWordReview(
          hit.first.id!,
          stability: 0,
          difficulty: 6,
          dueAt: now,
          lastReviewAt: now,
        );
        linked++;
      }
      expect(linked, missed.length, reason: '每个漏词都要挂上复习状态');

      // 复习页:漏词以"到期"身份出现(入库即建立复习状态)
      final plan = await buildQueue(now);
      final dueWords = plan.dueWords.map((i) => i.vocab.word.toLowerCase()).toSet();
      for (final w in missed) {
        expect(dueWords, contains(w), reason: '收进来的漏词必须出现在复习队列:$w');
      }
    });

    test('重复收同一批漏词不会造出重复词条(用户会重复点那个按钮)', () async {
      final now = DateTime(2026, 9, 24, 23);
      final batch = [
        Vocabulary(word: 'refused', createdAt: now),
        Vocabulary(word: 'obscure', createdAt: now),
      ];
      final first = await DatabaseService.insertVocabularies(batch);
      expect(first, 2);

      // 第二次点「收进生词本」(界面不会因为成功就禁用按钮 → 用户真的会点第二次)
      final second = await DatabaseService.insertVocabularies(batch);
      expect(second, 0, reason: '已存在的词不该再插一行');

      final all = await DatabaseService.getVocabularies(limit: 100);
      expect(all.where((v) => v.word == 'refused').length, 1,
          reason: '同一个词只能有一条词条,否则词库与复习队列都会出现重复');
      expect(all.where((v) => v.word == 'obscure').length, 1);
    });

    test('同一批里重复的词只插一条(一次听写可能两句漏同一个词)', () async {
      final now = DateTime(2026, 9, 24, 23, 30);
      final inserted = await DatabaseService.insertVocabularies([
        Vocabulary(word: 'weather', createdAt: now),
        Vocabulary(word: 'Weather', createdAt: now),
        Vocabulary(word: ' weather ', createdAt: now),
      ]);
      expect(inserted, 1);
      final all = await DatabaseService.getVocabularies(limit: 100);
      expect(all.where((v) => v.word.toLowerCase().trim() == 'weather').length, 1);
    });
  });
}
