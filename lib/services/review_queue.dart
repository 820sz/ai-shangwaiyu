import '../models/vocabulary.dart';
import 'fsrs.dart';

/// 今日复习队列(v2.1)—— **纯函数、无 IO**。
///
/// 把「生词本 + FSRS 卡片状态 + 每日时间预算」翻译成一份**今天照着做就行**的
/// 列表。为什么要单独一层:
/// 1. 队列顺序直接决定用户先看到哪个词 —— 最该复习的(过期最久、记忆最脆弱)
///    必须排前面,而不是按入库时间;
/// 2. **复习优先于新词**:到期量吃掉预算时不再加新词,否则越学越还不上;
/// 3. 这一层的输入是纯数据,所以"配额怎么算、排序凭什么"都能被单测钉住。
class ReviewQueueItem {
  final Vocabulary vocab;
  final FsrsCard card;

  /// true = 还没有任何复习记录(新词首见)
  final bool isNew;

  const ReviewQueueItem({
    required this.vocab,
    required this.card,
    required this.isNew,
  });

  /// 过期天数(负数=还没到期)
  int overdueDays(DateTime now) =>
      now.difference(card.due).inDays;

  /// 记忆脆弱度:可提取性越低越该先复习
  double fragility(DateTime now) => 1 - FsrsScheduler.retrievability(card, now);
}

class ReviewQueuePlan {
  /// 到期词(含过期与今天到期),已按"最该复习"排序
  final List<ReviewQueueItem> dueWords;

  /// 今日新词(配额内)
  final List<ReviewQueueItem> newWords;

  /// 全库到期分布(未截断,用于展示"后面还有多少")
  final DueBuckets buckets;

  /// 未来 7 天负荷
  final List<int> forecast;

  /// 这份队列的预计耗时(分钟,按 [secondsPerCard] 估算)
  final int estimatedMinutes;

  const ReviewQueuePlan({
    required this.dueWords,
    required this.newWords,
    required this.buckets,
    required this.forecast,
    required this.estimatedMinutes,
  });

  int get total => dueWords.length + newWords.length;

  bool get isEmpty => total == 0;

  /// 一句话总结(UI 直接用,避免各处自己拼文案)
  String get summary {
    if (total == 0) {
      return buckets.total > 0
          ? '今天没有到期的词 —— 后面还有 ${buckets.total} 个排队'
          : '复习队列是空的 —— 去材料里收几个新词吧';
    }
    final parts = <String>[];
    if (dueWords.isNotEmpty) parts.add('复习 ${dueWords.length} 个');
    if (newWords.isNotEmpty) parts.add('新词 ${newWords.length} 个');
    return '${parts.join(' + ')},约 $estimatedMinutes 分钟';
  }
}

class ReviewQueue {
  ReviewQueue._();

  /// 每张卡片的估算耗时(含回忆与看释义)
  static const int secondsPerCard = 8;

  /// 单日队列上限:一次给几百个只会让人放弃
  static const int maxDuePerSession = 60;

  /// 构建今日队列。
  /// - [vocab] 生词本(用于取词面/释义)
  /// - [cards] vocabId → FSRS 卡片(来自 `word_review`;缺卡的词按新词处理)
  static ReviewQueuePlan build({
    required List<Vocabulary> vocab,
    required Map<int, FsrsCard> cards,
    required DateTime now,
    required int dailyMinutes,
    int maxNewWords = 20,
  }) {
    final due = <ReviewQueueItem>[];
    final fresh = <ReviewQueueItem>[];

    for (final v in vocab) {
      final id = v.id;
      if (id == null) continue;
      final card = cards[id] ?? FsrsScheduler.newCard(now);
      final item = ReviewQueueItem(vocab: v, card: card, isNew: card.isNew);
      // **从未复习过的词算"新词",不算"到期复习"**。
      // 这一条很关键:数据库迁移给每个生词都建了卡片,due 就是当前时间;
      // 如果按 due 判断,用户第一次打开复习页会看到几百个"到期",
      // 而它们其实只是"还没学过"——复习优先的配额逻辑会因此彻底失效。
      if (card.isNew) {
        fresh.add(item);
      } else if (card.isDue(now)) {
        due.add(item);
      }
    }

    // 排序:① 过期最久的优先;② 同等过期则记忆最脆弱的优先;
    // ③ 最后按词面稳定排序(保证同一批数据每次顺序一致,便于复盘)
    due.sort((a, b) {
      final byOverdue = b.overdueDays(now).compareTo(a.overdueDays(now));
      if (byOverdue != 0) return byOverdue;
      final byFragility = b.fragility(now).compareTo(a.fragility(now));
      if (byFragility != 0) return byFragility;
      return a.vocab.word.compareTo(b.vocab.word);
    });

    // 负荷统计只看**已排期的卡片**(新词没有排期,不该算成"今天到期");
    // buckets 报告全库情况 —— "后面还有多少"必须真实,不能被队列截断影响
    final scheduled = <FsrsCard>[
      for (final v in vocab)
        if (v.id != null && cards[v.id!] != null && !cards[v.id!]!.isNew)
          cards[v.id!]!,
    ];
    final buckets = FsrsScheduler.dueBuckets(scheduled, now: now);
    final forecast = FsrsScheduler.loadForecast(scheduled, now: now);

    final dueTruncated = due.length > maxDuePerSession
        ? due.sublist(0, maxDuePerSession)
        : due;

    // 新词配额:复习优先 —— 预算扣掉复习占用后还剩多少容量
    final quota = FsrsScheduler.newWordQuota(
      dueToday: dueTruncated.length,
      dailyMinutes: dailyMinutes,
      secondsPerCard: secondsPerCard,
      maxNewWords: maxNewWords,
    );
    // 新词顺序:按入库时间(先收的先学)+ 词面兜底,保证可复现
    fresh.sort((a, b) {
      final byTime = a.vocab.createdAt.compareTo(b.vocab.createdAt);
      if (byTime != 0) return byTime;
      return a.vocab.word.compareTo(b.vocab.word);
    });
    final newToday = quota <= 0
        ? <ReviewQueueItem>[]
        : fresh.take(quota).toList();

    final minutes =
        ((dueTruncated.length + newToday.length) * secondsPerCard / 60).ceil();

    return ReviewQueuePlan(
      dueWords: dueTruncated,
      newWords: newToday,
      buckets: buckets,
      forecast: forecast,
      estimatedMinutes: minutes,
    );
  }

  /// 复习一个词之后:返回更新后的卡片(封装评分 → FSRS 的单点入口,
  /// 避免 UI 直接调调度器导致"忘记更新 lastReview/due"这类漏字段的错)
  static FsrsCard applyRating(
    FsrsCard card,
    FsrsRating rating, {
    required DateTime now,
  }) =>
      FsrsScheduler.review(card, rating, now: now);

  /// 从评分结果推断"这个词算不算已掌握"(ui 展示用):
  /// 稳定度 ≥ 30 天且不是刚刚答错 → 视为长期记住
  static bool isLongTermKnown(FsrsCard card) =>
      card.stability >= 30 && card.lastRating != FsrsRating.again;

  /// 旧三档 mastery(0/1/2)与 FSRS 卡片的兼容映射:
  /// 迁移期用它把老数据折算成卡片初值(与数据库 `_seedWordReviewFromMastery` 同口径)
  static FsrsCard cardFromLegacyMastery(
    int masteryLevel, {
    required DateTime now,
  }) {
    final days = switch (masteryLevel) {
      2 => 14,
      1 => 3,
      _ => 0,
    };
    return FsrsCard(
      stability: days.toDouble(),
      difficulty: 5,
      due: now.add(Duration(days: days)),
      lastReview: masteryLevel == 0 ? null : now,
      reps: masteryLevel == 0 ? 0 : 1,
      lapses: 0,
    );
  }
}
