import '../models/vocabulary.dart';

/// 复习模式的数据逻辑(v1.7.0):筛选(掌握度 + 日期)+ 进度持久化。
/// 全部为纯函数/纯数据,便于单测。

/// 日期筛选档位(用户要求:今天、几天前、一周前、一个月前)
class ReviewDateFilter {
  /// 天数为 0 表示不限
  final int days;
  final String label;

  const ReviewDateFilter(this.days, this.label);

  static const List<ReviewDateFilter> options = [
    ReviewDateFilter(0, '全部'),
    ReviewDateFilter(1, '今天'),
    ReviewDateFilter(3, '近3天'),
    ReviewDateFilter(7, '近一周'),
    ReviewDateFilter(30, '近一月'),
  ];
}

/// 掌握度筛选:level = -1 全部 / 0 新词 / 1 学习中 / 2 已掌握
List<Vocabulary> filterReviewItems(
  List<Vocabulary> items, {
  int level = -1,
  int days = 0,
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  // 只复习带释义的条目(没释义的卡片无法"想义")
  var list = items.where((v) => (v.translation ?? '').isNotEmpty);
  if (level >= 0) {
    list = list.where((v) => v.masteryLevel == level);
  }
  if (days > 0) {
    // "今天"= 当天 00:00 起;近N天 = 最近 N*24 小时(含今天)
    final cutoff = days == 1
        ? DateTime(ref.year, ref.month, ref.day)
        : ref.subtract(Duration(days: days));
    list = list.where((v) => v.createdAt.isAfter(cutoff));
  }
  return list.toList();
}

/// 复习进度(可持久化,退出后再进能续上)
class ReviewProgress {
  /// 本轮卡片顺序(生词 id;复习数据来自词库,必有 id)
  final List<int> deckIds;
  final int index;
  final int countMastered;
  final int countLearning;
  final int countNew;
  final int filterLevel;
  final int filterDays;
  final bool flipped;
  final DateTime updatedAt;

  /// 每张卡已标记的掌握度(word id → 0/1/2)。
  /// v1.9.0(审查 P1-5):必须随进度一起存 —— 旧实现只存计数,续看后
  /// 卡片的"已标记：X"消失,且对同一张卡再点标记会**再计一次数**,
  /// 统计数超过实际卡片数(用户抱怨过的"刷进度"同类缺陷)。
  final Map<int, int> marks;

  /// 断点所在的最后一词 id(v1.9.0):恢复时按 id 定位,
  /// 不再用保存时的下标硬夹(删过词就会跳到"最后一张")。
  final int? lastId;

  const ReviewProgress({
    required this.deckIds,
    required this.index,
    required this.countMastered,
    required this.countLearning,
    required this.countNew,
    required this.filterLevel,
    required this.filterDays,
    required this.flipped,
    required this.updatedAt,
    this.marks = const {},
    this.lastId,
  });

  bool get isEmpty => deckIds.isEmpty;

  /// 卡组是否仍与当前词库一致(词被删掉/新增则视为过期)
  bool matchesDeck(List<Vocabulary> items) {
    final ids = items.map((v) => v.id).whereType<int>().toList()..sort();
    final saved = [...deckIds]..sort();
    if (ids.length != saved.length) return false;
    for (int i = 0; i < ids.length; i++) {
      if (ids[i] != saved[i]) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'deck_ids': deckIds,
    'index': index,
    'mastered': countMastered,
    'learning': countLearning,
    'new': countNew,
    'filter_level': filterLevel,
    'filter_days': filterDays,
    'flipped': flipped,
    'updated_at': updatedAt.toIso8601String(),
    // 标记表按 "id:level" 字符串存:Hive 读回的 Map 键类型会漂,
    // 用字符串编码可避免 int 键读不回来
    if (marks.isNotEmpty)
      'marks': marks.entries.map((e) => '${e.key}:${e.value}').toList(),
    if (lastId != null) 'last_id': lastId,
  };

  factory ReviewProgress.fromJson(Map<String, dynamic> json) {
    final marks = <int, int>{};
    for (final raw in ((json['marks'] as List?) ?? const [])) {
      final s = '$raw';
      final idx = s.indexOf(':');
      if (idx <= 0) continue;
      final id = int.tryParse(s.substring(0, idx));
      final level = int.tryParse(s.substring(idx + 1));
      if (id != null && level != null) marks[id] = level;
    }
    return ReviewProgress(
      deckIds: ((json['deck_ids'] as List?) ?? [])
          .map((e) => e is int ? e : int.tryParse('$e') ?? -1)
          .where((e) => e >= 0)
          .toList(),
      index: (json['index'] as int?) ?? 0,
      countMastered: (json['mastered'] as int?) ?? 0,
      countLearning: (json['learning'] as int?) ?? 0,
      countNew: (json['new'] as int?) ?? 0,
      filterLevel: (json['filter_level'] as int?) ?? -1,
      filterDays: (json['filter_days'] as int?) ?? 0,
      flipped: (json['flipped'] as bool?) ?? false,
      updatedAt: DateTime.tryParse('${json['updated_at']}') ?? DateTime.now(),
      marks: marks,
      lastId: json['last_id'] is int ? json['last_id'] as int : null,
    );
  }
}

/// 把保存的顺序映射回当前卡组(词序可能因刷新变化):
/// 返回 [Vocabulary] 列表 + 起始下标;无法匹配的条目丢弃。
({List<Vocabulary> deck, int index}) restoreDeck(
  List<Vocabulary> current,
  ReviewProgress progress,
) {
  final byId = {
    for (final v in current)
      if (v.id != null) v.id!: v,
  };
  final deck = <Vocabulary>[];
  for (final id in progress.deckIds) {
    final v = byId[id];
    if (v != null) deck.add(v);
  }
  // v1.9.0:优先按"断点词 id"定位(删过词也落在原词附近),
  // 找不到才退回保存时的下标并夹到合法范围
  var index = progress.index;
  if (progress.lastId != null) {
    final byLast = deck.indexWhere((v) => v.id == progress.lastId);
    if (byLast >= 0) index = byLast;
  }
  if (index < 0) index = 0;
  if (index >= deck.length) index = deck.isEmpty ? 0 : deck.length - 1;
  return (deck: deck, index: index);
}
