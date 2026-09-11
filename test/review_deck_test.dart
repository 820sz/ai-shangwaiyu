import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/utils/review_deck.dart';

/// v1.7.0 复习模式回归测试:
/// - filterReviewItems:掌握度筛选 + 日期筛选(今天/近3天/近一周/近一月)
/// - ReviewProgress:序列化往返、卡组一致性校验、进度恢复
void main() {
  Vocabulary v(
    String word, {
    int? id,
    int mastery = 0,
    String translation = '释义',
    int daysAgo = 0,
  }) => Vocabulary(
    id: id,
    word: word,
    translation: translation,
    masteryLevel: mastery,
    createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
  );

  group('filterReviewItems — 筛选(v1.7.0)', () {
    test('无释义的条目不进复习卡组', () {
      final items = [
        v('keep', translation: '有释义'),
        v('drop', translation: ''),
      ];
      expect(filterReviewItems(items).map((e) => e.word), ['keep']);
    });

    test('掌握度筛选:0 新词 / 1 学习中 / 2 已掌握 / -1 全部', () {
      final items = [
        v('a', mastery: 0),
        v('b', mastery: 1),
        v('c', mastery: 2),
      ];
      expect(filterReviewItems(items, level: 0).map((e) => e.word), ['a']);
      expect(filterReviewItems(items, level: 2).map((e) => e.word), ['c']);
      expect(filterReviewItems(items, level: -1).length, 3);
    });

    test('日期筛选:今天只含当天存的词', () {
      final items = [
        v('today', daysAgo: 0),
        v('yesterday', daysAgo: 1),
        v('lastWeek', daysAgo: 6),
      ];
      expect(filterReviewItems(items, days: 1).map((e) => e.word), ['today']);
    });

    test('日期筛选:近3天/近一周/近一月按窗口取', () {
      final items = [
        v('d0', daysAgo: 0),
        v('d2', daysAgo: 2),
        v('d5', daysAgo: 5),
        v('d20', daysAgo: 20),
        v('d60', daysAgo: 60),
      ];
      expect(filterReviewItems(items, days: 3).map((e) => e.word), ['d0', 'd2']);
      expect(
        filterReviewItems(items, days: 7).map((e) => e.word),
        ['d0', 'd2', 'd5'],
      );
      expect(
        filterReviewItems(items, days: 30).map((e) => e.word),
        ['d0', 'd2', 'd5', 'd20'],
      );
    });

    test('掌握度 + 日期可叠加', () {
      final items = [
        v('a', mastery: 0, daysAgo: 0),
        v('b', mastery: 0, daysAgo: 10),
        v('c', mastery: 2, daysAgo: 0),
      ];
      expect(
        filterReviewItems(items, level: 0, days: 3).map((e) => e.word),
        ['a'],
      );
    });
  });

  group('ReviewProgress — 进度持久化(v1.7.0)', () {
    final progress = ReviewProgress(
      deckIds: const [3, 1, 2],
      index: 2,
      countMastered: 1,
      countLearning: 1,
      countNew: 0,
      filterLevel: 0,
      filterDays: 7,
      flipped: true,
      updatedAt: DateTime(2026, 8, 26, 10, 30),
    );

    test('toJson → fromJson 往返保留全部字段', () {
      final back = ReviewProgress.fromJson(progress.toJson());
      expect(back.deckIds, [3, 1, 2]);
      expect(back.index, 2);
      expect(back.countMastered, 1);
      expect(back.countLearning, 1);
      expect(back.filterLevel, 0);
      expect(back.filterDays, 7);
      expect(back.flipped, isTrue);
    });

    test('matchesDeck:同一批词(顺序不同)算一致,数量或成员变化算过期', () {
      final same = [v('a', id: 1), v('b', id: 2), v('c', id: 3)];
      expect(progress.matchesDeck(same), isTrue);
      expect(progress.matchesDeck([v('a', id: 1), v('b', id: 2)]), isFalse);
      expect(
        progress.matchesDeck([v('a', id: 1), v('b', id: 2), v('x', id: 9)]),
        isFalse,
      );
    });

    test('restoreDeck:按保存顺序还原卡组与下标', () {
      final current = [v('a', id: 1), v('b', id: 2), v('c', id: 3)];
      final restored = restoreDeck(current, progress);
      expect(restored.deck.map((e) => e.word), ['c', 'a', 'b']);
      expect(restored.index, 2);
    });

    test('restoreDeck:词被删除后下标收敛到末尾,不越界', () {
      final current = [v('a', id: 1)];
      final restored = restoreDeck(current, progress);
      expect(restored.deck.length, 1);
      expect(restored.index, 0);
    });

    test('损坏 JSON → 空进度不抛异常', () {
      final back = ReviewProgress.fromJson(const {});
      expect(back.deckIds, isEmpty);
      expect(back.isEmpty, isTrue);
      expect(back.index, 0);
    });
  });
}
