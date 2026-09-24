/// 桌面小组件的**文案与判据**(纯函数:不碰插件、不碰数据库、不碰 Android)。
///
/// 为什么单独一层:小组件是"用户不打开 App 也能看见"的界面,它最容易犯两种错 ——
/// ① **拿过期数据冒充今天**(用户以为今天只剩 3 个词要复习,其实是三天前的);
/// ② 空数据时显示 "0 / 0 / 0"(没有信息量,还显得 App 坏了)。
/// 所以规则写死成可测的:
/// - 从未同步 → "打开 App 生成今天的计划"(而不是编一个 0);
/// - 同步时间不是今天 → "打开 App 刷新今日任务" + "上次同步 N 天前"
///   (原生侧 `ReadFlowWidgetProvider` 每 30 分钟重绘时会独立做同一判断 —— 那边是
///   "App 一直没打开"时的兜底,两边语义必须一致);
/// - 今天 → 显示今天的任务/到期数/新词额度/连续天数。
class WidgetPayload {
  /// 今天最该做的事(导师任务的第一条,或按到期数兜底生成)
  final String headline;

  /// 第二行:待复习 / 新词额度
  final String dueLine;

  /// 连续学习天数标签(如 `连续 5 天`);没有连续记录时为空
  final String streak;

  /// 右上角小字:任务完成进度(如 `1/3`、`全部完成`);没有任务时为空
  final String badge;

  /// 本次同步时间(原生侧据此重算"多久以前",必须原样传下去)
  final DateTime? syncedAt;

  /// 是否从未同步过(全新安装 / 一次都没打开过 App)
  final bool firstSync;

  const WidgetPayload({
    required this.headline,
    required this.dueLine,
    required this.streak,
    required this.badge,
    required this.syncedAt,
    this.firstSync = false,
  });

  /// 原生 `RemoteViews` 按这些键读 `HomeWidgetPreferences`
  /// (改键名要同步改 `ReadFlowWidgetProvider.kt`)
  static const String keyHeadline = 'rf_headline';
  static const String keyDueLine = 'rf_due_line';
  static const String keyStreak = 'rf_streak';
  static const String keyBadge = 'rf_badge';
  static const String keySyncedAt = 'rf_synced_at';

  /// 写入 SharedPreferences 的键值对。从未同步时**只写一个空时间戳** ——
  /// 让原生侧走"空态"分支,而不是把空串当成有效数据渲染出一片空白。
  Map<String, String> toWidgetData() {
    if (firstSync) return {keySyncedAt: ''};
    return {
      keyHeadline: headline,
      keyDueLine: dueLine,
      keyStreak: streak,
      keyBadge: badge,
      keySyncedAt: (syncedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  /// 隔几天算"过期"(天数差 ≥ 该值就不再拿旧数字当今天)
  static const int staleAfterDays = 2;

  /// 组装小组件文案。
  ///
  /// [dueCount] 现在该复习的词数;[newWordsRemaining] 今天还能加多少新词
  /// (上限 - 今天已加,与复习页同一口径);[tasks] 今天导师排的任务。
  static WidgetPayload build({
    required int dueCount,
    required int newWordsRemaining,
    required int streakDays,
    required List<WidgetTask> tasks,
    required DateTime now,
    DateTime? syncedAt,
    bool firstSync = false,
  }) {
    if (firstSync) {
      return const WidgetPayload(
        headline: '',
        dueLine: '',
        streak: '',
        badge: '',
        syncedAt: null,
        firstSync: true,
      );
    }
    final at = syncedAt ?? now;
    final ageDays = dayDiff(at, now);

    // ── 过期:不拿旧数字冒充今天(原生侧也有同一判断,这里是同步/预览路径) ──
    if (ageDays >= staleAfterDays) {
      return WidgetPayload(
        headline: '打开 App 刷新今日任务',
        dueLine: '上次同步 ${ageLabel(ageDays)}',
        streak: '',
        badge: '',
        syncedAt: at,
      );
    }

    // ── 今天 ──
    final pending = tasks.where((t) => !t.done).toList();
    final doneCount = tasks.length - pending.length;
    String headline;
    if (pending.isNotEmpty) {
      headline = pending.first.title;
      if (pending.length > 1) headline = '$headline 等 ${pending.length} 项';
    } else if (dueCount > 0) {
      headline = '复习 $dueCount 个词';
    } else if (newWordsRemaining > 0) {
      headline = '今天可以加 $newWordsRemaining 个新词';
    } else {
      headline = '今日已清空 —— 读一篇新材料?';
    }

    final dueLine = dueCount > 0
        ? '待复习 $dueCount 个 · 新词额度 $newWordsRemaining'
        : (newWordsRemaining > 0
            ? '没有到期的词 · 新词额度 $newWordsRemaining'
            : '没有到期的词 · 今天不加新词');

    return WidgetPayload(
      headline: headline,
      dueLine: dueLine,
      streak: streakDays > 0 ? '连续 $streakDays 天' : '',
      badge: tasks.isEmpty
          ? ''
          : (doneCount == tasks.length ? '全部完成' : '$doneCount/${tasks.length}'),
      syncedAt: at,
    );
  }

  /// 设置页预览:把"桌面上会看到什么"按行给出来(与原生渲染同序)
  List<String> previewLines() {
    if (firstSync) {
      return const ['打开 App 生成今天的计划', '导师会按你的水平排今天该做什么', '还没同步过'];
    }
    final at = syncedAt;
    final footer = [
      if (streak.isNotEmpty) streak,
      if (at != null) '更新于 ${clock(at)}',
    ].join(' · ');
    return [headline, dueLine, footer];
  }

  /// 自然日差(用日历日而不是 24 小时:23:50 → 次日 00:10 算"隔了一天")
  static int dayDiff(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  static String ageLabel(int days) =>
      days <= 0 ? '刚刚' : (days == 1 ? '昨天' : '$days 天前');

  static String clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 诊断页用:最后同步时间的人话描述。
  /// null = 从没同步过(全新安装或推送一直失败)—— 这两种情况要能分开说,
  /// 否则用户在"桌面上数字是旧的"和"App 根本没推过"之间无从判断。
  static String syncAgeLabel(DateTime? syncedAt, DateTime now) {
    if (syncedAt == null) return '从没同步过';
    final days = dayDiff(syncedAt, now);
    if (days == 0) return '今天 ${clock(syncedAt)}';
    if (days == 1) return '昨天 ${clock(syncedAt)}';
    return '$days 天前(${syncedAt.month}月${syncedAt.day}日 ${clock(syncedAt)})';
  }
}

/// 小组件用到的"今天任务"最小结构(只有标题与完成态,不依赖数据库行)
class WidgetTask {
  final String title;
  final bool done;

  const WidgetTask({required this.title, required this.done});
}
