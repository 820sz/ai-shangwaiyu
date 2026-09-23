import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/fsrs.dart';

/// FSRS 复习内核测试。
///
/// 这是 v2.1 的调度基础,错了的代价是"该复习的词不出现 / 不该出现的天天出现",
/// 所以断言压在**行为性质**(单调性、边界、不变量)与**可手算的具体值**上,
/// 而不是"跑起来不报错"。
void main() {
  final now = DateTime(2026, 9, 22, 9);

  group('初始卡片', () {
    test('新词按评分给出初始稳定度与难度(与默认权重一致)', () {
      final easy = FsrsScheduler.newCard(now, firstRating: FsrsRating.easy);
      final again = FsrsScheduler.newCard(now, firstRating: FsrsRating.again);
      expect(easy.stability, FsrsScheduler.defaultWeights[3]);
      expect(again.stability, FsrsScheduler.defaultWeights[0]);
      expect(easy.stability, greaterThan(again.stability));
      expect(easy.difficulty, lessThan(again.difficulty));
      expect(easy.isNew, isTrue);
      expect(easy.due, now, reason: '新词立刻到期,等着第一次复习');
    });

    test('难度被夹在 1..10', () {
      for (final r in FsrsRating.values) {
        final c = FsrsScheduler.newCard(now, firstRating: r);
        expect(c.difficulty, greaterThanOrEqualTo(1.0));
        expect(c.difficulty, lessThanOrEqualTo(10.0));
      }
    });
  });

  group('复习后的更新', () {
    test('第一次"认识"后到期时间在未来,且 reps=1', () {
      final c0 = FsrsScheduler.newCard(now);
      final c1 = FsrsScheduler.review(c0, FsrsRating.good, now: now);
      expect(c1.reps, 1);
      expect(c1.lastReview, now);
      expect(c1.due.isAfter(now), isTrue);
      expect(c1.isNew, isFalse);
      expect(c1.stability, greaterThan(0));
    });

    test('连续"认识"→ 间隔单调变长(这是间隔重复的核心性质)', () {
      var card = FsrsScheduler.newCard(now);
      var at = now;
      final intervals = <int>[];
      for (var i = 0; i < 5; i++) {
        card = FsrsScheduler.review(card, FsrsRating.good, now: at);
        intervals.add(card.due.difference(at).inDays);
        at = card.due; // 到期当天复习
      }
      for (var i = 1; i < intervals.length; i++) {
        expect(intervals[i], greaterThanOrEqualTo(intervals[i - 1]),
            reason: '第 $i 次间隔不应短于上一次($intervals)');
      }
      expect(intervals.last, greaterThan(intervals.first));
      expect(intervals, isNot(contains(0)), reason: '间隔至少 1 天');
    });

    test('"太简单"的间隔比"认识"长,"模糊"比"认识"短', () {
      final base = FsrsScheduler.review(
        FsrsScheduler.newCard(now),
        FsrsRating.good,
        now: now,
      );
      final easy = FsrsScheduler.review(base, FsrsRating.easy, now: base.due);
      final hard = FsrsScheduler.review(base, FsrsRating.hard, now: base.due);
      final good = FsrsScheduler.review(base, FsrsRating.good, now: base.due);
      final daysOf = (FsrsCard c) => c.due.difference(base.due).inDays;
      expect(daysOf(easy), greaterThan(daysOf(good)));
      expect(daysOf(hard), lessThanOrEqualTo(daysOf(good)));
    });

    test('"不认识"→ 稳定度下降、lapses+1、很快再见到', () {
      var card = FsrsScheduler.newCard(now);
      for (var i = 0; i < 4; i++) {
        card = FsrsScheduler.review(card, FsrsRating.good, now: card.due);
      }
      final beforeS = card.stability;
      final beforeDue = card.due;
      final lapsed = FsrsScheduler.review(card, FsrsRating.again, now: beforeDue);
      expect(lapsed.stability, lessThan(beforeS));
      expect(lapsed.lapses, 1);
      expect(
        lapsed.due.difference(beforeDue).inDays,
        lessThan(card.due.difference(now).inDays),
        reason: '忘了的词要明显更快回到队列',
      );
    });

    test('难度随"不认识"上升、随"太简单"下降(且始终在 1..10)', () {
      var card = FsrsScheduler.review(
        FsrsScheduler.newCard(now),
        FsrsRating.good,
        now: now,
      );
      final d0 = card.difficulty;
      var harder = card;
      for (var i = 0; i < 3; i++) {
        harder = FsrsScheduler.review(harder, FsrsRating.again, now: harder.due);
      }
      var easier = card;
      for (var i = 0; i < 3; i++) {
        easier = FsrsScheduler.review(easier, FsrsRating.easy, now: easier.due);
      }
      expect(harder.difficulty, greaterThan(d0));
      expect(easier.difficulty, lessThan(d0));
      for (final c in [harder, easier]) {
        expect(c.difficulty, greaterThanOrEqualTo(1.0));
        expect(c.difficulty, lessThanOrEqualTo(10.0));
      }
    });

    test('间隔有上限,不会被"太简单"推到几年后', () {
      var card = FsrsScheduler.newCard(now);
      for (var i = 0; i < 30; i++) {
        card = FsrsScheduler.review(card, FsrsRating.easy, now: card.due);
      }
      final interval = card.due.difference(card.lastReview!).inDays;
      expect(interval, lessThanOrEqualTo(FsrsScheduler.maxIntervalDays));
    });

    test('权重与状态始终有限(不出现 NaN/Infinity)', () {
      var card = FsrsScheduler.newCard(now);
      for (final r in [
        FsrsRating.good, FsrsRating.hard, FsrsRating.again, FsrsRating.easy,
        FsrsRating.again, FsrsRating.good,
      ]) {
        card = FsrsScheduler.review(card, r, now: card.due);
        expect(card.stability.isFinite, isTrue);
        expect(card.difficulty.isFinite, isTrue);
      }
    });
  });

  group('可提取性(记得的概率)', () {
    test('刚复习完接近 1,时间越久越低', () {
      final card = FsrsScheduler.review(
        FsrsScheduler.newCard(now),
        FsrsRating.good,
        now: now,
      );
      final r0 = FsrsScheduler.retrievability(card, now);
      final r1 = FsrsScheduler.retrievability(
        card,
        now.add(Duration(days: card.stability.round())),
      );
      final r2 = FsrsScheduler.retrievability(
        card,
        now.add(Duration(days: card.stability.round() * 3)),
      );
      expect(r0, closeTo(1.0, 0.02));
      expect(r1, lessThan(r0));
      expect(r2, lessThan(r1));
    });

    test('到"目标保持率"的时间点,可提取性约等于 0.9(公式自洽)', () {
      final card = FsrsScheduler.review(
        FsrsScheduler.newCard(now),
        FsrsRating.good,
        now: now,
      );
      final interval = FsrsScheduler.intervalFor(card.stability);
      final r = FsrsScheduler.retrievability(
        card,
        now.add(Duration(days: interval.round())),
      );
      // 取整到天,允许 5% 误差
      expect(r, closeTo(FsrsScheduler.requestRetention, 0.05));
    });

    test('新词(从未复习)可提取性为 0,不抛异常', () {
      expect(
        FsrsScheduler.retrievability(FsrsScheduler.newCard(now), now),
        0,
      );
    });
  });

  group('到期分布与负荷预测', () {
    FsrsCard cardDue(DateTime due) => FsrsCard(
          stability: 1,
          difficulty: 5,
          due: due,
          lastReview: now,
          reps: 1,
        );

    test('分桶按自然日:昨天=过期、今天=今天、3 天后=本周、10 天后=更晚', () {
      final b = FsrsScheduler.dueBuckets(
        [
          cardDue(now.subtract(const Duration(days: 1))),
          cardDue(now.add(const Duration(hours: 3))),
          cardDue(now.add(const Duration(days: 3))),
          cardDue(now.add(const Duration(days: 10))),
        ],
        now: now,
      );
      expect(b.overdue, 1);
      expect(b.today, 1);
      expect(b.week, 1);
      expect(b.later, 1);
      expect(b.total, 4);
      expect(b.nextSevenDays, 3);
    });

    test('今天凌晨 0 点整到期的算"今天",不算过期', () {
      final startOfDay = DateTime(now.year, now.month, now.day);
      final b = FsrsScheduler.dueBuckets([cardDue(startOfDay)], now: now);
      expect(b.overdue, 0);
      expect(b.today, 1);
    });

    test('未来 7 天负荷:过期项并入今天,更远的条目不计入', () {
      final load = FsrsScheduler.loadForecast(
        [
          cardDue(now.subtract(const Duration(days: 3))),
          cardDue(now),
          cardDue(now.add(const Duration(days: 2))),
          cardDue(now.add(const Duration(days: 30))),
        ],
        now: now,
      );
      expect(load.length, 7);
      expect(load[0], 2, reason: '过期的 1 个 + 今天到期的 1 个');
      expect(load[2], 1);
      expect(load.reduce((a, b) => a + b), 3);
    });
  });

  group('配额规则(复习优先)', () {
    test('待复习量超出每日容量 → 停加新词', () {
      // 30 分钟预算、6 秒/词 = 300 张容量
      expect(
        FsrsScheduler.shouldStopNewWords(
          dueToday: 350,
          dailyMinutes: 30,
          secondsPerCard: 6,
        ),
        isTrue,
      );
      expect(
        FsrsScheduler.shouldStopNewWords(
          dueToday: 100,
          dailyMinutes: 30,
          secondsPerCard: 6,
        ),
        isFalse,
      );
    });

    test('新词配额 = 容量 - 复习占用,且不超过上限', () {
      expect(
        FsrsScheduler.newWordQuota(dueToday: 0, dailyMinutes: 30),
        20,
        reason: '容量足够时按上限给 20 个新词',
      );
      expect(
        FsrsScheduler.newWordQuota(dueToday: 290, dailyMinutes: 30),
        10,
      );
      expect(
        FsrsScheduler.newWordQuota(dueToday: 400, dailyMinutes: 30),
        0,
        reason: '复习已经吃满预算就不加新词',
      );
      expect(FsrsScheduler.newWordQuota(dueToday: 0, dailyMinutes: 0), 0);
    });
  });

  group('评分枚举', () {
    test('四个按钮与数值一一对应,非法值回落 easy(不越界)', () {
      expect(FsrsRating.again.value, 1);
      expect(FsrsRating.hard.value, 2);
      expect(FsrsRating.good.value, 3);
      expect(FsrsRating.easy.value, 4);
      expect(FsrsRating.fromValue(3), FsrsRating.good);
      expect(FsrsRating.fromValue(99), FsrsRating.easy);
      expect(FsrsRating.again.label, '不认识');
    });
  });
}
