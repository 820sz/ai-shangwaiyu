import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/vocab_occurrence.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/database.dart';

/// B4 回归:同一个词反复出现要**记次数与出处**,而不是又存一行。
///
/// 用户原话:"同一个词反复出现应改为出现次数的记录 —— 比如 apple(×2),
/// 词汇本里把每次出现的地方都列出来,这样也能起到加强记忆的作用"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_occurrence_test');
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

  Vocabulary apple({String book = '', String page = '', String sentence = ''}) =>
      Vocabulary(
        word: 'apple',
        translation: '苹果',
        sourceBook: book,
        sourcePage: page,
        originalSentence: sentence,
        occurrences: [
          if (book.isNotEmpty || page.isNotEmpty || sentence.isNotEmpty)
            VocabOccurrence(
              book: book,
              page: page,
              sentence: sentence,
              at: DateTime(2026, 9, 24),
            ),
        ],
        createdAt: DateTime(2026, 9, 24),
      );

  group('出现记录模型', () {
    test('JSON 往返保留书/页/句/时间', () {
      final occ = VocabOccurrence(
        book: '新概念3',
        page: 'p12',
        sentence: 'An apple a day keeps the doctor away.',
        at: DateTime(2026, 9, 24, 10, 30),
      );
      final decoded = VocabOccurrence.decodeList(
        VocabOccurrence.encodeList([occ]),
      );
      expect(decoded, hasLength(1));
      expect(decoded.single.book, '新概念3');
      expect(decoded.single.page, 'p12');
      expect(decoded.single.sentence, contains('apple'));
      expect(decoded.single.label, '新概念3 · p12');
      expect(decoded.single.at, DateTime(2026, 9, 24, 10, 30));
    });

    test('坏 JSON / 缺字段不炸:坏日期退回 epoch(与词条日期同一容错口径)', () {
      expect(VocabOccurrence.decodeList(null), isEmpty);
      expect(VocabOccurrence.decodeList('不是 JSON'), isEmpty);
      expect(VocabOccurrence.decodeList('{"a":1}'), isEmpty);
      final withBadDate =
          VocabOccurrence.decodeList('[{"book":"X","at":"bad-date"}]');
      expect(withBadDate, hasLength(1), reason: '内容有效,只有时间坏 → 保留');
      expect(
        withBadDate.single.at,
        DateTime.fromMillisecondsSinceEpoch(0),
        reason: '与 Vocabulary._tryParseDate 一致:坏日期退回 epoch',
      );
      expect(VocabOccurrence.decodeList('[{"at":"2026-09-24T10:00:00"}]'), isEmpty,
          reason: '全是空字段 → 不算一次出现');
    });

    test('词条显示:多次出现带(×N),一次不带', () {
      final once = Vocabulary(word: 'apple', createdAt: DateTime(2026, 1, 1));
      expect(once.occurrenceCount, 1);
      expect(once.wordWithCount, 'apple');

      final twice = once.copyWith(occurrences: [
        VocabOccurrence(book: 'A', at: DateTime(2026, 1, 1)),
        VocabOccurrence(book: 'B', at: DateTime(2026, 1, 2)),
      ]);
      expect(twice.occurrenceCount, 2);
      expect(twice.wordWithCount, 'apple(×2)');
    });
  });

  group('入库:再次见到同一个词 → 合并出现,不新增行', () {
    test('第一次入库 = 1 条;第二次入库 = 合并,词条仍只有 1 行', () async {
      final first = await DatabaseService.insertVocabularies([
        apple(book: '新概念3', page: 'p12', sentence: 'An apple a day.'),
      ]);
      expect(first.added, 1);
      expect(first.merged, 0);

      final second = await DatabaseService.insertVocabularies([
        apple(book: '外刊', page: 'p3', sentence: 'She ate an apple.'),
      ]);
      expect(second.added, 0, reason: '同一个词不该再插一行');
      expect(second.merged, 1);
      expect(second.occurrencesAdded, 1);

      final all = await DatabaseService.getVocabularies(limit: 100);
      expect(all, hasLength(1));
      expect(all.single.occurrenceCount, 2);
      expect(all.single.wordWithCount, 'apple(×2)');
      expect(
        all.single.occurrences.map((o) => o.label),
        containsAll(['新概念3 · p12', '外刊 · p3']),
      );
    });

    test('同一处再存一次 → 不重复计数(去重按 书+页+句)', () async {
      await DatabaseService.insertVocabularies([
        apple(book: '新概念3', page: 'p12', sentence: 'An apple a day.'),
      ]);
      final again = await DatabaseService.insertVocabularies([
        apple(book: '新概念3', page: 'p12', sentence: 'An apple a day.'),
      ]);
      expect(again.merged, 1);
      expect(again.occurrencesAdded, 0, reason: '同一处不该记两次');
      final all = await DatabaseService.getVocabularies(limit: 100);
      expect(all.single.occurrenceCount, 1);
    });

    test('合并时**不覆盖**已有的释义/音标(用户数据优先)', () async {
      await DatabaseService.insertVocabularies([
        Vocabulary(
          word: 'apple',
          translation: '苹果(我改过的释义)',
          phoneticUk: '/ˈæp.əl/',
          createdAt: DateTime(2026, 9, 24),
        ),
      ]);
      await DatabaseService.insertVocabularies([
        Vocabulary(
          word: 'Apple',
          translation: 'AI 说的另一种释义',
          sourceBook: '外刊',
          createdAt: DateTime(2026, 9, 24),
        ),
      ]);
      final v = (await DatabaseService.getVocabularies(limit: 10)).single;
      expect(v.translation, '苹果(我改过的释义)');
      expect(v.phoneticUk, '/ˈæp.əl/');
    });

    test('原来为空时才补:第二次带来了释义,第一次没有 → 补上', () async {
      await DatabaseService.insertVocabularies([
        Vocabulary(word: 'reservoir', createdAt: DateTime(2026, 9, 24)),
      ]);
      await DatabaseService.insertVocabularies([
        Vocabulary(
          word: 'reservoir',
          translation: '储备;蓄水池',
          sourceBook: 'AN AUTHOR PREPARES',
          createdAt: DateTime(2026, 9, 24),
        ),
      ]);
      final v = (await DatabaseService.getVocabularies(limit: 10)).single;
      expect(v.translation, '储备;蓄水池');
    });

    test('老调用方没带 occurrences → 用词条自身的出处兜底一次', () async {
      await DatabaseService.insertVocabularies([
        Vocabulary(
          word: 'blur',
          sourceBook: '书籍A',
          sourcePage: 'p7',
          originalSentence: 'sources begin to blur',
          createdAt: DateTime(2026, 9, 24),
        ),
      ]);
      final v = (await DatabaseService.getVocabularies(limit: 10)).single;
      expect(v.occurrenceCount, 1);
      expect(v.occurrences.single.book, '书籍A');
      expect(v.occurrences.single.sentence, 'sources begin to blur');
    });

    test('summary 给人话结果(听写/阅读器提示用)', () async {
      final o1 = await DatabaseService.insertVocabularies([
        Vocabulary(word: 'alpha', createdAt: DateTime(2026, 9, 24)),
      ]);
      expect(o1.summary, contains('新增 1 个'));
      final o2 = await DatabaseService.insertVocabularies([
        Vocabulary(
          word: 'alpha',
          sourceBook: 'B',
          createdAt: DateTime(2026, 9, 24),
        ),
      ]);
      expect(o2.summary, contains('新增 0 个'));
      expect(o2.summary, contains('已在生词本 1 个'));
      expect(o2.summary, contains('记录出现 1 处'));
    });
  });
}
