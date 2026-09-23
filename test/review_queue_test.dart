import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/fsrs.dart';
import 'package:readflow/services/review_queue.dart';

/// 今日复习队列测试。
///
/// 队列顺序与配额是"用户今天看到什么"的唯一来源:
/// 把最该复习的排在后面、或者该停新词时继续加,都会直接毁掉坚持率。
void main() {
  final now = DateTime(2026, 9, 22, 9);

  Vocabulary v(int id, String word, {int mastery = 0, int daysAgo = 0}) =>
      Vocabulary(
        id: id,
        word: word,
        masteryLevel: mastery,
        createdAt: now.subtract(Duration(days: daysAgo)),
      );

  FsrsCard card({
    required int dueInDays,
    double stability = 5,
    double difficulty = 5,
    int reps = 2,
  }) =>
      FsrsCard(
        stability: stability,
        difficulty: difficulty,
        due: now.add(Duration(days: dueInDays)),
        lastReview: now.subtract(const Duration(days: 1)),
        reps: reps,
      );

  group('队列构成', () {
    test('到期的进 dueWords,没到期的既不进 due 也不进新词', () {
      final plan = ReviewQueue.build(
        vocab: [v(1, 'alpha'), v(2, 'beta'), v(3, 'gamma')],
        cards: {
          1: card(dueInDays: -3), // 过期 3 天
          2: card(dueInDays: 4), // 还没到期
          3: card(dueInDays: 0), // 今天到期
        },
        now: now,
        dailyMinutes: 30,
      );
      expect(plan.dueWords.map((e) => e.vocab.word), containsAll(['alpha', 'gamma']));
      expect(plan.dueWords.map((e) => e.vocab.word), isNot(contains('beta')));
      expect(plan.newWords, isEmpty);
      expect(plan.total, 2);
      expect(plan.summary, contains('复习 2 个'));
    });

    test('没有卡片的词按新词处理,受配额限制', () {
      final plan = ReviewQueue.build(
        vocab: [for (var i = 1; i <= 10; i++) v(i, 'w$i')],
        cards: const {},
        now: now,
        dailyMinutes: 30,
      );
      expect(plan.dueWords, isEmpty);
      // 30 分钟 / 8 秒 = 225 容量,但新词上限 20
      expect(plan.newWords.length, 10);
      expect(plan.summary, contains('新词 10 个'));
    });
  });

  group('排序:最该复习的排最前', () {
    test('过期越久越靠前', () {
      final plan = ReviewQueue.build(
        vocab: [v(1, 'newer'), v(2, 'older'), v(3, 'middle')],
        cards: {
          1: card(dueInDays: -1),
          2: card(dueInDays: -10),
          3: card(dueInDays: -5),
        },
        now: now,
        dailyMinutes: 30,
      );
      expect(
        plan.dueWords.map((e) => e.vocab.word).toList(),
        ['older', 'middle', 'newer'],
      );
    });

    test('过期天数相同 → 记忆更脆弱的(稳定度低)靠前', () {
      final plan = ReviewQueue.build(
        vocab: [v(1, 'sturdy'), v(2, 'fragile')],
        cards: {
          1: card(dueInDays: -2, stability: 40),
          2: card(dueInDays: -2, stability: 1),
        },
        now: now,
        dailyMinutes: 30,
      );
      expect(plan.dueWords.first.vocab.word, 'fragile');
    });

    test('完全同分时按词面排序(顺序可复现,便于复盘)', () {
      final a = ReviewQueue.build(
        vocab: [v(1, 'zebra'), v(2, 'apple')],
        cards: {1: card(dueInDays: -1), 2: card(dueInDays: -1)},
        now: now,
        dailyMinutes: 30,
      );
      final b = ReviewQueue.build(
        vocab: [v(2, 'apple'), v(1, 'zebra')],
        cards: {2: card(dueInDays: -1), 1: card(dueInDays: -1)},
        now: now,
        dailyMinutes: 30,
      );
      expect(
        a.dueWords.map((e) => e.vocab.word).toList(),
        b.dueWords.map((e) => e.vocab.word).toList(),
      );
    });
  });

  group('配额:复习优先于新词', () {
    test('复习吃满预算 → 今天不给新词', () {
      final plan = ReviewQueue.build(
        vocab: [
          for (var i = 1; i <= 200; i++) v(i, 'due$i'),
          v(999, 'brandnew'),
        ],
        cards: {
          for (var i = 1; i <= 200; i++) i: card(dueInDays: -1),
        },
        now: now,
        dailyMinutes: 5, // 5 分钟 = 37 张容量,而到期有 200 张
      );
      expect(plan.dueWords.length, ReviewQueue.maxDuePerSession,
          reason: '单次队列有上限,避免一次甩几百个');
      expect(plan.newWords, isEmpty);
      expect(plan.buckets.total, 200, reason: '全库真实到期量要如实报告');
    });

    test('复习占用少 → 剩余容量给新词,且不超过上限', () {
      final plan = ReviewQueue.build(
        vocab: [
          v(1, 'due1'),
          for (var i = 10; i < 40; i++) v(i, 'new$i'),
        ],
        cards: {1: card(dueInDays: -1)},
        now: now,
        dailyMinutes: 30,
        maxNewWords: 5,
      );
      expect(plan.dueWords.length, 1);
      expect(plan.newWords.length, 5);
    });

    test('从未复习过的词算新词,不算"到期"(否则复习优先会失效)', () {
      final plan = ReviewQueue.build(
        vocab: [v(1, 'never'), v(2, 'scheduled')],
        cards: {
          // 迁移会给每个生词建卡片:mastery 0 的卡 due=now 但 isNew=true
          2: card(dueInDays: -1),
        },
        now: now,
        dailyMinutes: 30,
      );
      expect(plan.dueWords.map((e) => e.vocab.word), ['scheduled']);
      expect(plan.newWords.map((e) => e.vocab.word), ['never']);
      expect(plan.buckets.total, 1, reason: '新词没有排期,不该算进"到期"');
    });

    test('预计耗时与队列长度一致(向上取整,便于显示)', () {
      final plan = ReviewQueue.build(
        vocab: [for (var i = 1; i <= 7; i++) v(i, 'w$i')],
        cards: {for (var i = 1; i <= 7; i++) i: card(dueInDays: 0)},
        now: now,
        dailyMinutes: 30,
      );
      // 7 张 × 8 秒 = 56 秒 → 1 分钟
      expect(plan.estimatedMinutes, 1);
      expect(plan.summary, contains('1 分钟'));
    });
  });

  group('负荷预测与空队列', () {
    test('forecast 是未来 7 天,过期项并入今天', () {
      final plan = ReviewQueue.build(
        vocab: [v(1, 'a'), v(2, 'b'), v(3, 'c')],
        cards: {
          1: card(dueInDays: -5),
          2: card(dueInDays: 0),
          3: card(dueInDays: 2),
        },
        now: now,
        dailyMinutes: 30,
      );
      expect(plan.forecast.length, 7);
      expect(plan.forecast[0], 2);
      expect(plan.forecast[2], 1);
    });

    test('空队列的文案要区分"还没排到"与"词库是空的"', () {
      final withFuture = ReviewQueue.build(
        vocab: [v(1, 'later')],
        cards: {1: card(dueInDays: 20)},
        now: now,
        dailyMinutes: 30,
      );
      expect(withFuture.isEmpty, isTrue);
      expect(withFuture.summary, contains('排队'));

      final empty = ReviewQueue.build(
        vocab: const [],
        cards: const {},
        now: now,
        dailyMinutes: 30,
      );
      expect(empty.summary, contains('空的'));
    });

    test('没有 id 的词被跳过(不能因为一条坏数据崩掉整个队列)', () {
      final plan = ReviewQueue.build(
        vocab: [Vocabulary(word: 'noid'), v(2, 'ok')],
        cards: {2: card(dueInDays: 0)},
        now: now,
        dailyMinutes: 30,
      );
      expect(plan.dueWords.map((e) => e.vocab.word), ['ok']);
    });
  });

  group('拼写/听写判分(题型扩展)', () {
    test('忽略大小写与首尾空白', () {
      expect(ReviewGrading.isCorrect('  Vocabulary ', 'vocabulary'), isTrue);
      expect(ReviewGrading.isCorrect('VOCABULARY', 'vocabulary'), isTrue);
      expect(ReviewGrading.isCorrect('vocabular', 'vocabulary'), isFalse);
    });

    test('连字符/空格归一:well known 与 well-known 都算对', () {
      expect(ReviewGrading.isCorrect('well known', 'well-known'), isTrue);
      expect(ReviewGrading.isCorrect('well-known', 'well-known'), isTrue);
      expect(ReviewGrading.isCorrect('wellknown', 'well known'), isTrue);
      expect(ReviewGrading.isCorrect('well', 'well-known'), isFalse);
    });

    test('空答案/纯空白一律算错(不能因为没作答给过)', () {
      expect(ReviewGrading.isCorrect('', 'word'), isFalse);
      expect(ReviewGrading.isCorrect('   ', 'word'), isFalse);
      expect(ReviewGrading.isCorrect('-', 'word'), isFalse);
    });

    test('建议档位:拼对给"认识",拼错给"不认识"(不给体面台阶)', () {
      expect(ReviewGrading.suggestRating(correct: true), FsrsRating.good);
      expect(ReviewGrading.suggestRating(correct: false), FsrsRating.again);
    });

    test('结果文案带用户答案,便于回看错在哪', () {
      expect(
        ReviewGrading.resultLine(correct: true, typed: 'word', word: 'word'),
        contains('拼写正确'),
      );
      final wrong = ReviewGrading.resultLine(
        correct: false,
        typed: 'wrod',
        word: 'word',
      );
      expect(wrong, contains('wrod'));
      expect(wrong, contains('word'));
      expect(
        ReviewGrading.resultLine(correct: false, typed: '  ', word: 'word'),
        contains('空'),
      );
    });
  });

  group('与 FSRS 的衔接', () {    test('applyRating 走调度器:答"认识"后 due 往后推且 reps+1', () {
      final c0 = FsrsScheduler.newCard(now);
      final c1 = ReviewQueue.applyRating(c0, FsrsRating.good, now: now);
      expect(c1.reps, 1);
      expect(c1.due.isAfter(now), isTrue);
    });

    test('长期记住的判定:稳定度 ≥30 天且不是刚答错', () {
      expect(ReviewQueue.isLongTermKnown(card(dueInDays: 30, stability: 45)), isTrue);
      expect(ReviewQueue.isLongTermKnown(card(dueInDays: 1, stability: 2)), isFalse);
      final lapsed = FsrsScheduler.review(
        card(dueInDays: 0, stability: 60),
        FsrsRating.again,
        now: now,
      );
      expect(ReviewQueue.isLongTermKnown(lapsed), isFalse);
    });

    test('旧三档 mastery → 卡片初值:与数据库迁移同口径(且不是"永不到期")', () {
      expect(ReviewQueue.cardFromLegacyMastery(0, now: now).isNew, isTrue);
      final learning = ReviewQueue.cardFromLegacyMastery(1, now: now);
      final mastered = ReviewQueue.cardFromLegacyMastery(2, now: now);
      expect(learning.due.difference(now).inDays, 3);
      expect(mastered.due.difference(now).inDays, 14);
      expect(mastered.due.isBefore(now.add(const Duration(days: 30))), isTrue,
          reason: '旧"已掌握"也必须重新排队,不能当永远记住');
    });
  });
}
