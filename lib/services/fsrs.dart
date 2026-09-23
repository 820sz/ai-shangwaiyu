/// FSRS 间隔重复调度内核(v2.1)—— **纯函数、无 IO**。
///
/// 为什么换掉 v1.x 的三档 mastery:
/// 旧模型只有"新词/学习中/已掌握"三个格子,没有时间维度 —— 既回答不了
/// "什么时候该复习",也回答不了"会不会忘",复习页只能把整个生词本翻一遍。
///
/// 这里实现 **FSRS-4.5**(Free Spaced Repetition Scheduler)的核心公式:
/// - 每个词维护 `stability`(记忆稳定度,天)与 `difficulty`(1..10);
/// - 由 `retrievability = (1 + FACTOR·t/S)^DECAY` 预测"现在还记得的概率";
/// - 复习后用 rating(1=忘了 2=模糊 3=记得 4=太简单)更新 S 与 D,
///   并算出下次到期时间。
///
/// 权重使用 FSRS-4.5 的**官方默认参数**(见 [defaultWeights] 注释里的出处),
/// 不做个性化训练 —— 训练需要大量复习日志,而我们的用户刚开始积累;
/// 参数可后续按 `word_review` 的真实日志回标。
///
/// 与官方实现的差异(诚实声明):
/// 1. 不做"同日多次复习"的特殊处理(我们一天内很少复习同一个词两次);
/// 2. 不做 fuzzing(官方会给间隔加随机抖动避免同一天堆积)——我们先保证可复现;
/// 3. 不实现 FSRS-5/6 的更多状态(短期记忆、复杂度等)。
library;

import 'dart:math' as math;

/// 评分(与复习页四个按钮一一对应)
enum FsrsRating {
  /// 完全不认识(忘记)
  again(1, '不认识'),

  /// 想起来了但很吃力
  hard(2, '模糊'),

  /// 正常想起
  good(3, '认识'),

  /// 太简单(秒答)
  easy(4, '太简单');

  final int value;
  final String label;
  const FsrsRating(this.value, this.label);

  static FsrsRating fromValue(int v) => switch (v) {
        1 => FsrsRating.again,
        2 => FsrsRating.hard,
        3 => FsrsRating.good,
        _ => FsrsRating.easy,
      };
}

/// 一张卡片的调度状态(与 `word_review` 表字段一一对应)
class FsrsCard {
  /// 记忆稳定度(天):越大越不容易忘
  final double stability;

  /// 难度(1..10):越大越难
  final double difficulty;

  /// 到期时间
  final DateTime due;

  /// 上次复习时间(null = 从未复习)
  final DateTime? lastReview;

  /// 复习次数与遗忘次数
  final int reps;
  final int lapses;

  /// 上次评分
  final FsrsRating? lastRating;

  const FsrsCard({
    required this.stability,
    required this.difficulty,
    required this.due,
    this.lastReview,
    this.reps = 0,
    this.lapses = 0,
    this.lastRating,
  });

  bool get isNew => reps == 0 && lastReview == null;

  bool isDue(DateTime now) => !due.isAfter(now);

  FsrsCard copyWith({
    double? stability,
    double? difficulty,
    DateTime? due,
    DateTime? lastReview,
    int? reps,
    int? lapses,
    FsrsRating? lastRating,
  }) =>
      FsrsCard(
        stability: stability ?? this.stability,
        difficulty: difficulty ?? this.difficulty,
        due: due ?? this.due,
        lastReview: lastReview ?? this.lastReview,
        reps: reps ?? this.reps,
        lapses: lapses ?? this.lapses,
        lastRating: lastRating ?? this.lastRating,
      );

  @override
  String toString() =>
      'FsrsCard(S=${stability.toStringAsFixed(2)}, D=${difficulty.toStringAsFixed(2)}, '
      'due=${due.toIso8601String().substring(0, 10)}, reps=$reps, lapses=$lapses)';
}

/// 下次到期分布(复习负荷预测用)
class DueBuckets {
  final int overdue;
  final int today;
  final int week;
  final int later;
  const DueBuckets({
    this.overdue = 0,
    this.today = 0,
    this.week = 0,
    this.later = 0,
  });

  int get total => overdue + today + week + later;

  /// 未来 7 天要复习的量(不含"更晚")—— 导师据此判断"今天该不该加新词"
  int get nextSevenDays => overdue + today + week;
}

class FsrsScheduler {
  FsrsScheduler._();

  /// FSRS-4.5 默认权重(17 个)。
  /// 出处:open-spaced-repetition 的 FSRS-4.5 默认参数(公开算法与参数,
  /// 采用 MIT 许可的社区实现文档中的默认值)。
  /// 顺序含义:w0-3 初始稳定度(按 rating)、w4-5 初始难度、w6 难度变化、
  /// w7 难度均值回归、w8-10 成功复习的稳定度增长、w11-14 遗忘后的稳定度、
  /// w15 "模糊"惩罚、w16 "简单"奖励。
  static const List<double> defaultWeights = [
    0.4872, 1.4003, 3.7145, 13.8206, // w0-3 初始 S
    5.1618, 1.2298, // w4-5 初始 D
    0.8975, // w6 D 变化
    0.0310, // w7 D 均值回归
    1.6474, 0.1367, 1.0461, // w8-10 成功复习
    2.1072, 0.0793, 0.3246, 1.5870, // w11-14 遗忘后
    0.2272, 2.8755, // w15-16 模糊/简单
  ];

  /// 记忆衰减常量:官方取 DECAY = -0.5, FACTOR = 19/81
  static const double decay = -0.5;
  static const double factor = 19 / 81;

  /// 目标保持率:0.9 = "希望复习时还有 90% 概率记得"
  static const double requestRetention = 0.9;

  /// 单次复习后的最大间隔(天):防止一条"太简单"把词推到几年后
  static const int maxIntervalDays = 365 * 2;

  /// 新词初始状态(第一次见到它时的卡片)
  static FsrsCard newCard(DateTime now, {FsrsRating? firstRating}) {
    final rating = firstRating ?? FsrsRating.good;
    final s = defaultWeights[rating.value - 1];
    final d = _initialDifficulty(rating);
    return FsrsCard(
      stability: s,
      difficulty: d,
      due: now,
      lastReview: null,
      reps: 0,
      lapses: 0,
      lastRating: null,
    );
  }

  static double _initialDifficulty(FsrsRating g) =>
      (defaultWeights[4] - (g.value - 3) * defaultWeights[5])
          .clamp(1.0, 10.0)
          .toDouble();

  /// 当前还记得的概率(0..1);未复习过的新词按 0 处理
  static double retrievability(FsrsCard card, DateTime now) {
    if (card.lastReview == null || card.stability <= 0) return 0;
    final days = now.difference(card.lastReview!).inMinutes / (60 * 24);
    if (days <= 0) return 1;
    return math.pow(1 + factor * days / card.stability, decay).toDouble();
  }

  /// 给定稳定度,算"保持率达到 [retention] 时的间隔(天)"
  static double intervalFor(double stability, {double retention = requestRetention}) {
    if (stability <= 0) return 1;
    final raw = stability / factor * (math.pow(retention, 1 / decay) - 1);
    return raw;
  }

  /// 复习一次:更新 S/D/到期时间。这是整个复习内核的唯一入口。
  static FsrsCard review(
    FsrsCard card,
    FsrsRating rating, {
    required DateTime now,
  }) {
    // 从未复习过 → 用初始公式(此时没有可用的 R)
    if (card.isNew) {
      final s = defaultWeights[rating.value - 1];
      final d = _initialDifficulty(rating);
      final interval = _clampInterval(intervalFor(s));
      return FsrsCard(
        stability: s,
        difficulty: d,
        due: now.add(Duration(days: interval)),
        lastReview: now,
        reps: 1,
        lapses: rating == FsrsRating.again ? 1 : 0,
        lastRating: rating,
      );
    }

    final r = retrievability(card, now);
    final d = card.difficulty;
    // 难度:先按评分调整,再向"初始难度"做均值回归(避免难度一路飘走)
    final dDelta = d - defaultWeights[6] * (rating.value - 3);
    final dNext = (defaultWeights[7] * _initialDifficulty(FsrsRating.good) +
            (1 - defaultWeights[7]) * dDelta)
        .clamp(1.0, 10.0)
        .toDouble();

    final double sNext;
    if (rating == FsrsRating.again) {
      // 忘了:稳定度按遗忘公式重算(与旧 S 相关,但不完全清零)
      sNext = defaultWeights[11] *
          math.pow(d, -defaultWeights[12]) *
          (math.pow(card.stability + 1, defaultWeights[13]) - 1) *
          math.exp(defaultWeights[14] * (1 - r));
    } else {
      final hardPenalty = rating == FsrsRating.hard ? defaultWeights[15] : 1.0;
      final easyBonus = rating == FsrsRating.easy ? defaultWeights[16] : 1.0;
      final growth = math.exp(defaultWeights[8]) *
          (11 - d) *
          math.pow(card.stability, -defaultWeights[9]) *
          (math.exp((1 - r) * defaultWeights[10]) - 1) *
          hardPenalty *
          easyBonus;
      sNext = card.stability * (1 + growth);
    }

    final safeS = sNext.isFinite && sNext > 0 ? sNext : 1.0;
    final interval = _clampInterval(intervalFor(safeS));
    return FsrsCard(
      stability: safeS,
      difficulty: dNext,
      due: now.add(Duration(days: interval)),
      lastReview: now,
      reps: card.reps + 1,
      lapses: card.lapses + (rating == FsrsRating.again ? 1 : 0),
      lastRating: rating,
    );
  }

  /// 间隔下限 1 天、上限 [maxIntervalDays]
  static int _clampInterval(double days) {
    final rounded = days.round();
    if (rounded < 1) return 1;
    if (rounded > maxIntervalDays) return maxIntervalDays;
    return rounded;
  }

  /// 到期分布(纯函数;用注入的 [now] 便于测试)
  static DueBuckets dueBuckets(
    Iterable<FsrsCard> cards, {
    required DateTime now,
  }) {
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfDay.add(const Duration(days: 1));
    final weekEnd = startOfDay.add(const Duration(days: 7));
    var overdue = 0;
    var today = 0;
    var week = 0;
    var later = 0;
    for (final c in cards) {
      final due = c.due;
      if (due.isBefore(startOfDay)) {
        overdue++;
      } else if (due.isBefore(endOfToday)) {
        today++;
      } else if (!due.isAfter(weekEnd)) {
        week++;
      } else {
        later++;
      }
    }
    return DueBuckets(overdue: overdue, today: today, week: week, later: later);
  }

  /// 未来 7 天的每日复习量(负荷预测:防止某天突然堆几百个)
  static List<int> loadForecast(
    Iterable<FsrsCard> cards, {
    required DateTime now,
    int days = 7,
  }) {
    final startOfDay = DateTime(now.year, now.month, now.day);
    final out = List<int>.filled(days, 0);
    for (final c in cards) {
      final diff = c.due.difference(startOfDay).inDays;
      if (diff < 0) {
        out[0]++; // 已经过期的算在今天
      } else if (diff < days) {
        out[diff]++;
      }
    }
    return out;
  }

  /// 是否"该停止加新词了":待复习量已经超过每日预算
  /// (导师诊断与复习配额都用这一条规则,避免两处各写一份阈值)
  static bool shouldStopNewWords({
    required int dueToday,
    required int dailyMinutes,
    required int secondsPerCard,
  }) {
    if (dailyMinutes <= 0) return false;
    final capacity = (dailyMinutes * 60 / secondsPerCard).floor();
    return dueToday > capacity;
  }

  /// 今日新词配额:每日预算扣掉复习占用后的剩余容量
  /// (复习优先 —— 这是间隔重复能被坚持下来的前提)
  static int newWordQuota({
    required int dueToday,
    required int dailyMinutes,
    int secondsPerCard = 6,
    int maxNewWords = 20,
  }) {
    if (dailyMinutes <= 0) return 0;
    final capacity = (dailyMinutes * 60 / secondsPerCard).floor();
    final left = capacity - dueToday;
    if (left <= 0) return 0;
    return left > maxNewWords ? maxNewWords : left;
  }
}
