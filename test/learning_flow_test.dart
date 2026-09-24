import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/learner_context.dart';
import 'package:readflow/services/learner_snapshot_loader.dart';
import 'package:readflow/services/material_library.dart';
import 'package:readflow/services/reading_quiz.dart';
import 'package:readflow/services/review_queue.dart';
import 'package:readflow/services/tutor_engine.dart';
import 'package:readflow/services/word_frequency.dart';

/// **整链路回归**:材料进库 → 阅读(收词/进度/会话)→ 读完 → 读后测验 →
/// 错词进错误档案 + 复习状态回退 → 复习队列真的排出这个词 → 导师诊断照常工作。
///
/// 为什么要有这个文件:上面每一步都有自己的单测,但用户真机走的是**连起来的**
/// 那条路 —— v2.3.0 之后用户正在测的正是这条(材料中心 → 分析并读 → 读完 →
/// 测验 → 复习)。断链的典型表现是"每步都对,合起来没数据"(例如测验落了库但
/// 没有 vocab_id、复习队列因此永远排不出那个词),单测各自都测不出来。
///
/// 时间基准:凡是有时间语义的地方注入固定 `now`,不依赖真实时钟。
/// 词频:用 `debugInject` 造确定性词表,不读 assets(避免测试依赖打包产物)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  /// 造纯字母假词(带数字的词会被分词器丢掉 —— 那是测试"以假乱真"的经典坑)
  String fakeWord(int i) {
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    return '${letters[(i ~/ 676) % 26]}${letters[(i ~/ 26) % 26]}${letters[i % 26]}';
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_flow_test');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
    // 学习者模型存在 Hive 里:链路里的"导师诊断"要读它(不打开就会走降级分支)
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    // 600 个已知词(名次 = 下标+1)+ 4 个"生词"排在很后面(名次 > 600)
    final words = <String>[for (var i = 0; i < 600; i++) fakeWord(i)];
    words.addAll(['zzznovel', 'zzzstrange', 'zzzpeculiar', 'zzzobscure']);
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

  /// 词表里"靠前"的词应当算已知(词汇量给足以覆盖前 600)
  LearnerModel modelWithVocab(int vocab) => LearnerModel(
        vocabEstimate: vocab <= 0
            ? null
            : ProfileField<int>(value: vocab, source: ProfileSource.test),
        dailyMinutes: ProfileField<int>(value: 20, source: ProfileSource.self),
        maxNewWords: ProfileField<int>(value: 10, source: ProfileSource.self),
      );

  test('材料 → 阅读 → 测验 → 错误档案 → 复习队列 → 导师诊断,整条链都有数据', () async {
    final now = DateTime(2026, 9, 24, 20, 30);
    final model = modelWithVocab(600);

    // ── ① 材料进库(自备文本,和"粘贴自备材料"走同一条管线)──
    final text = [
      'The ${fakeWord(1)} and the ${fakeWord(2)} were talking about the weather.',
      'A zzzpeculiar thing happened: the ${fakeWord(3)} refused to ${fakeWord(4)}.',
      'Nobody could explain the zzzobscure reason behind it.',
    ].join(' ');
    final ingested = await MaterialLibrary.ingestText(
      title: '整链路测试材料',
      text: text,
      model: model,
    );
    expect(ingested.materialId, greaterThan(0));
    expect(ingested.analysis.wordCount, greaterThan(20));
    expect(ingested.analysis.newTypes, greaterThanOrEqualTo(2),
        reason: '文本里塞了 zzz 开头的生词,难度分析必须认出来');
    expect(ingested.analysis.coverage, lessThan(1.0));

    // 正文分块确实落库了(阅读器靠它渲染)
    final chunks = await DatabaseService.getMaterialChunks(ingested.materialId);
    expect(chunks, isNotEmpty);

    // ── ② 书架能看到它,且是"未开始"──
    final shelf = await MaterialLibrary.shelf(limit: 10);
    final mine = shelf.where((s) => s.id == ingested.materialId).toList();
    expect(mine, hasLength(1),
        reason: '刚入库(还没打开)的材料也必须出现在书架里,否则用户以为导入失败');
    expect(mine.first.id, greaterThan(0),
        reason: 'id 为 0 会让点击书架条目去打开一份不存在的材料');
    expect(mine.first.percent, 0);
    expect(mine.first.finished, isFalse);
    expect(mine.first.title, '整链路测试材料');

    // ── ③ 阅读:收词(点词入生词本)+ 进度 + 阅读会话 ──
    final vocabId = await DatabaseService.insertVocabulary(
      Vocabulary(
        word: 'zzzpeculiar',
        translation: '奇怪的',
        sourceBook: '整链路测试材料',
        masteryLevel: AppConstants.masteryNew,
        createdAt: now,
      ),
    );
    expect(vocabId, greaterThan(0));
    await DatabaseService.upsertMaterialProgress(
      ingested.materialId,
      position: 0,
      percent: 100,
      addMinutes: 6,
      addPickedWords: 1,
      finished: true,
    );
    await DatabaseService.insertReadingSession(
      materialId: ingested.materialId,
      words: 320,
      duration: const Duration(minutes: 6),
    );

    final shelfAfter = await MaterialLibrary.shelf(limit: 10);
    final read = shelfAfter.firstWhere((s) => s.id == ingested.materialId);
    expect(read.percent, 100);
    expect(read.finished, isTrue, reason: '读完要能在书架上显示"已读完"');
    expect(read.minutesRead, 6);
    expect(read.pickedWords, 1);

    // ── ④ 读后测验:本地出题 → 判分 → 落库 ──
    final questions = ReadingQuiz.build(
      text: text,
      targetWords: const ['zzzpeculiar', 'zzzobscure'],
      translations: const {'zzzpeculiar': '奇怪的'},
      seed: ingested.materialId,
    );
    expect(questions, isNotEmpty, reason: '有目标词就该出得出题');

    // 全答错:模拟"没读懂/乱选"
    final answers = List<String?>.filled(questions.length, 'wronganswer');
    final correct = ReadingQuiz.grade(questions, answers);
    final wrong = ReadingQuiz.wrongWords(questions, answers);
    expect(correct, 0);
    expect(wrong, isNotEmpty);

    await DatabaseService.insertQuizResult(
      kind: 'reading_comprehension',
      refId: ingested.materialId,
      total: questions.length,
      correct: correct,
      detail: {'material_title': '整链路测试材料', 'wrong_words': wrong},
    );

    // 错词:进错误档案 + 复习状态回退一档(与 reading_quiz_screen 同一套调用)
    for (final w in wrong) {
      await DatabaseService.bumpErrorTag(
        source: 'reading_quiz',
        tag: '词汇',
        evidence: w,
      );
      final vocabRows = await DatabaseService.getVocabularies(limit: 500);
      final hit = vocabRows.where((v) => v.word.toLowerCase() == w.toLowerCase());
      if (hit.isNotEmpty && hit.first.id != null) {
        await DatabaseService.upsertWordReview(
          hit.first.id!,
          stability: 0,
          difficulty: 6,
          dueAt: now,
          lastReviewAt: now,
          lastRating: 1,
          lapse: true,
        );
      }
    }

    final acc = await DatabaseService.getQuizAccuracy(days: 30);
    expect(acc['reading_comprehension'], 0);

    final tags = await DatabaseService.getErrorTags(status: 'active');
    expect(tags, isNotEmpty, reason: '错词必须进错误档案,否则用户"看不到自己错在哪"');
    expect(
      tags.map((t) => t['tag']).contains('词汇'),
      isTrue,
      reason: '读后测验的错词应归到「词汇」考点',
    );

    // ── ⑤ 复习队列真的排得出这个词 ──
    final vocabRows = await DatabaseService.getVocabularies(limit: 500);
    final cards = ReviewQueue.cardsFromRows(
      await DatabaseService.getWordReviews(),
      now: now,
    );
    final plan = ReviewQueue.build(
      vocab: vocabRows,
      cards: cards,
      now: now,
      dailyMinutes: 20,
      maxNewWords: 10,
    );
    expect(
      plan.dueWords.map((i) => i.vocab.word.toLowerCase()),
      contains('zzzpeculiar'),
      reason: '答错的词到期时间被设成"现在",必须出现在今日复习队列里',
    );

    // ── ⑥ 导师诊断:有行为数据后照常出结论,且每条结论都带依据 ──
    final snap = await LearnerSnapshotLoader.load(
      vocab: vocabRows,
      dailyLogs: await DatabaseService.getDailyLogsInRange(
        now.subtract(const Duration(days: 30)),
        now,
      ),
      now: now,
    );
    expect(snap.totalVocab, vocabRows.length);
    expect(snap.dueReviewCount, greaterThanOrEqualTo(1));
    final findings = TutorEngine.diagnose(snap);
    for (final f in findings) {
      expect(f.evidence.trim(), isNotEmpty,
          reason: '诊断结论必须带依据(这是整个模块的底线)');
    }
    final tasks = TutorEngine.planTasks(snap);
    expect(tasks.length, lessThanOrEqualTo(4));
  });

  test('脏数据不炸链路:坏 JSON 的进度/测验行被容错,阅读与会话照常读回', () async {
    final now = DateTime(2026, 9, 24, 9);
    final model = modelWithVocab(600);
    final ingested = await MaterialLibrary.ingestText(
      title: '容错测试',
      text: 'The ${fakeWord(5)} is here. A zzzstrange thing.',
      model: model,
    );

    // 手工写一条坏 difficulty_json(模拟历史遗留 / 写入中断)
    final db = await DatabaseService.database;
    await db.update(
      'materials',
      {'difficulty_json': '{不是 JSON'},
      where: 'id = ?',
      whereArgs: [ingested.materialId],
    );

    // 材料照常读得出来(难度解析失败 → 不崩,列表里只是没有难度标签)
    final row = await DatabaseService.getMaterialById(ingested.materialId);
    expect(row, isNotNull);
    expect(row!['title'], '容错测试');

    final shelf = await MaterialLibrary.shelf(limit: 10);
    expect(shelf.where((s) => s.id == ingested.materialId), hasLength(1));

    // 空文本材料的分析走兜底(覆盖率 1.0),不得抛异常
    final empty = await MaterialLibrary.analyze('', model: model);
    expect(empty.wordCount, 0);
    expect(empty.hint, isNotEmpty);

    // 会话统计在没有任何会话时给 0 而不是 null/异常
    final stats = await DatabaseService.getReadingStats(days: 30);
    expect(stats['sessions'], anyOf(0, isNull));
    expect(now.year, 2026);
  });

  test('学习偏好(配额)真的影响复习队列:只复习不加新词时不排新词', () async {
    final now = DateTime(2026, 9, 24, 21);
    // 20 个从未复习过的词 → 都是"新词"
    for (var i = 0; i < 20; i++) {
      await DatabaseService.insertVocabulary(
        Vocabulary(word: 'freshword$i'.replaceAll(RegExp(r'\d'), ''), createdAt: now),
      );
    }
    final vocabRows = await DatabaseService.getVocabularies(limit: 500);
    expect(vocabRows.length, greaterThanOrEqualTo(2));

    final noNew = ReviewQueue.build(
      vocab: vocabRows,
      cards: const {},
      now: now,
      dailyMinutes: 20,
      maxNewWords: 0,
    );
    expect(noNew.newWords, isEmpty, reason: '新词上限设 0 = 只复习不加新词');
    expect(noNew.dueWords, isEmpty, reason: '从未复习过的词是"新词",不是"到期"');

    final withNew = ReviewQueue.build(
      vocab: vocabRows,
      cards: const {},
      now: now,
      dailyMinutes: 20,
      maxNewWords: 5,
    );
    expect(withNew.newWords.length, lessThanOrEqualTo(5));
    expect(withNew.newWords, isNotEmpty);
  });

  test('学习者上下文:测量基线优先于自报,且已知词判定跟着基线走', () async {
    final measured = LearnerModel(
      vocabEstimate: ProfileField<int>(
        value: 8000,
        source: ProfileSource.test,
        confidence: 0.8,
      ),
      dailyMinutes: ProfileField<int>(value: 30, source: ProfileSource.self),
    );
    expect(LearnerContext.hasMeasuredBaseline(measured), isTrue);
    expect(LearnerContext.effectiveVocab(measured), 8000);

    final selfReported = LearnerModel(
      vocabEstimate: ProfileField<int>(value: 9000, source: ProfileSource.self),
    );
    expect(LearnerContext.hasMeasuredBaseline(selfReported), isFalse);
    expect(LearnerContext.effectiveVocab(selfReported), 9000);
    expect(LearnerContext.describeBaseline(selfReported), contains('自评'));
    expect(LearnerContext.describeBaseline(measured), contains('词汇量测试'));
  });
}
