import '../models/learning_record.dart';
import 'tutor_insights.dart';
import 'tutor_snapshot.dart';

/// 简报的一条「今天»(从今天任务或任务建议来,不新查库)。
class BriefToday {
  const BriefToday({
    required this.when,
    required this.title,
    required this.detail,
    required this.rawId,
    required this.status,
  });

  /// 时间/时长行,如「3 分钟 · 复习」
  final String when;
  final String title;

  /// 第二行依据(为什么做这件事);可能为空
  final String detail;

  /// tutor_tasks.id(建议行 = null,因为还没落库)
  final int? rawId;

  /// pending / active / done / skipped / suggestion
  final String status;
}

/// 简报里的一个数字(「这周」卡用)。
class BriefFact {
  const BriefFact({
    required this.value,
    required this.label,
    this.tone = BriefTone.neutral,
  });

  final String value;
  final String label;
  final BriefTone tone;
}

enum BriefTone { neutral, good, accent, warn }

/// 助理首页「每日简报」的**纯数据 + 纯文案**。
///
/// 为什么单独一层(而不是在 `tutor_home.build()` 里拼字符串):
/// 1. 简报的"口吻"是设计的一部分,需要被单测锁住(数字对不对、空数据有没有编);
/// 2. 页面只负责排版与跳转,文案变了一处改;
/// 3. **全部数据来自 [TutorDashboard]**(+ 可选的 7 天日志),不新查库、不调 AI。
///
/// 数据纪律(与全项目一致):没有的数据一律「待测」或直接不出现,绝不补 0/编数字。
class Briefing {
  const Briefing({
    required this.at,
    required this.eyebrow,
    required this.dateBig,
    required this.weekday,
    required this.streakText,
    required this.greeting,
    required this.headline,
    required this.lead,
    required this.today,
    required this.todayNote,
    required this.totalMinutes,
    required this.dueWords,
    required this.doneToday,
    required this.weekStats,
    required this.weekNote,
    required this.weekBars,
    required this.weekBarsTotal,
    required this.reminder,
    required this.reminderLabel,
    required this.pendingDimensions,
    required this.pendingHint,
    required this.outputCount,
    required this.outputAvgScore,
  });

  final DateTime at;
  final String eyebrow;
  final String dateBig;
  final String weekday;

  /// 「连续 6 天」/「还没形成连续记录」
  final String streakText;
  final String greeting;

  /// 一句话标题(今天有什么)
  final String headline;

  /// 一段"人写的"正文
  final String lead;
  final List<BriefToday> today;

  /// 时间线口径说明(如「建议 · 还没加进今天」),不需要时为空串
  final String todayNote;
  final int totalMinutes;
  final int dueWords;
  final int doneToday;
  final List<BriefFact> weekStats;

  /// 「这周」卡的说明(数据不足时说明为什么)
  final String weekNote;
  final List<double> weekBars;
  final int weekBarsTotal;

  /// 一句提醒;没有真实依据时为 null(页面不出现这一块)
  final String? reminder;
  final String reminderLabel;

  /// 还没测到的维度(「待测」),页面用一行列出来并给怎么测
  final List<String> pendingDimensions;
  final String pendingHint;

  /// 近 30 天输出次数 / 均分(可空)
  final int? outputCount;
  final double? outputAvgScore;

  bool get hasToday => today.isNotEmpty;

  static const List<String> _weekdayEn = <String>[
    'MONDAY BRIEF',
    'TUESDAY BRIEF',
    'WEDNESDAY BRIEF',
    'THURSDAY BRIEF',
    'FRIDAY BRIEF',
    'SATURDAY BRIEF',
    'SUNDAY BRIEF',
  ];
  static const List<String> _weekdayCn = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  /// 组装助理简报。**纯函数**:同样输入永远同样输出(单测用固定 now)。
  static Briefing build(
    TutorDashboard dash, {
    DateTime? now,
    List<LearningRecord>? dailyLogs,
  }) {
    final DateTime at = now ?? dash.snapshot.now;
    final int wd = at.weekday.clamp(1, 7);
    final int streak = dash.snapshot.streakDays;

    // ① 今天要做的事:优先「今天任务」里未完成的,其次「任务建议」
    final List<BriefToday> today = <BriefToday>[];
    var doneToday = 0;
    for (final Map<String, Object?> row in dash.todayTasks) {
      final String status = '${row['status'] ?? (row['done_at'] != null ? 'done' : 'pending')}';
      if (status == 'done') {
        doneToday++;
        continue;
      }
      if (status == 'skipped') continue;
      if (today.length >= 3) continue;
      final int? minutes = _intOrNull(row['target_minutes']);
      final Object? payload = row['payload'];
      final String reason = payload is Map ? '${payload['reason'] ?? ''}'.trim() : '';
      today.add(
        BriefToday(
          when: minutes == null ? _statusLabel(status) : '$minutes 分钟 · ${_statusLabel(status)}',
          title: '${row['title'] ?? ''}'.trim().isEmpty ? '（未命名任务）' : '${row['title']}',
          detail: reason,
          rawId: row['id'] is int ? row['id'] as int : null,
          status: status,
        ),
      );
    }
    var note = '';
    if (today.isEmpty) {
      for (final TaskSuggestion s in dash.suggestions.take(3)) {
        today.add(
          BriefToday(
            when: '建议 · ${s.minutes} 分钟',
            title: s.title,
            detail: s.reason,
            rawId: null,
            status: 'suggestion',
          ),
        );
      }
      if (today.isNotEmpty) note = '下面是助理建议 —— 点进去可以加进今天';
    }

    int totalMinutes = 0;
    for (final BriefToday t in today) {
      final RegExpMatch? m = RegExp(r'(\d+)\s*分钟').firstMatch(t.when);
      if (m != null) totalMinutes += int.tryParse(m.group(1) ?? '') ?? 0;
    }

    // ② 一句话标题 + 一段正文(只用真实数字)
    final int due = dash.snapshot.dueReviewCount;
    final StringBuffer head = StringBuffer();
    if (today.isEmpty) {
      head.write(due > 0 ? '今天还没排任务,先清 $due 个到期词。' : '今天还没有排任务。');
    } else if (due > 0) {
      head.write('今天有 ${today.length} 件事');
      if (totalMinutes > 0) head.write(',大约 $totalMinutes 分钟');
      head.write(';另有 $due 个到期词。');
    } else {
      head.write('今天有 ${today.length} 件事');
      if (totalMinutes > 0) head.write(',大约 $totalMinutes 分钟');
      head.write('。');
    }

    final List<String> leadParts = <String>[];
    if (doneToday > 0) leadParts.add('今天已经完成 $doneToday 件');
    if (streak > 0) leadParts.add('连续第 $streak 天');
    final int mastered = dash.snapshot.masteryMastered;
    if (mastered > 0) leadParts.add('已掌握 $mastered 个词');
    if (dash.snapshot.vocabAddedLast7Days > 0) {
      leadParts.add('近 7 天新收 ${dash.snapshot.vocabAddedLast7Days} 个词');
    }
    String lead;
    if (leadParts.isEmpty) {
      lead = due > 0
          ? '还没有形成固定的学习节奏。先把 $due 个到期词清掉,复习是唯一能立刻看到留存的动作。'
          : '还没有形成固定的学习节奏。从下面任意一件小事开始,做完再来复盘。';
    } else {
      lead = '${leadParts.join(' · ')}。';
      final TutorInsight? top = _firstMeasuredInsight(dash.insights);
      if (top != null && top.title.isNotEmpty) {
        // 用 title(人话结论)而不是 evidence —— evidence 里可能带表名/口径说明,
        // 那是给复盘页看的,不该出现在首页正文里。
        lead = '$lead${top.title}。';
      }
    }

    // ③ 这周:只用 TutorReview.metrics 里真实存在的键
    final Map<String, num> m = dash.review.metrics;
    final List<BriefFact> weekStats = <BriefFact>[];
    final int planned = (m['planned'] ?? 0).toInt();
    final int done = (m['done'] ?? 0).toInt();
    final int skipped = (m['skipped'] ?? 0).toInt();
    final double? completionRate = _doubleOrNull(m['completionRate']);
    final int? outputCount = _intOrNull(m['outputCount']);
    final double? outputAvgScore = _doubleOrNull(m['outputAvgScore']);
    final double? onTimeRate = _doubleOrNull(m['onTimeRate']);
    if (completionRate != null) {
      weekStats.add(BriefFact(
        value: '${(completionRate * 100).round()}%',
        label: '任务完成率',
        tone: completionRate >= 0.8
            ? BriefTone.good
            : (completionRate < 0.5 ? BriefTone.warn : BriefTone.neutral),
      ));
    } else if (planned > 0) {
      weekStats.add(BriefFact(value: '$planned 条', label: '本周计划'));
    }
    if (done > 0) weekStats.add(BriefFact(value: '$done 条', label: '完成任务'));
    if (skipped > 0) weekStats.add(BriefFact(value: '$skipped 条', label: '跳过'));
    if (outputCount != null) {
      weekStats.add(BriefFact(
        value: '$outputCount 次',
        label: '输出练习',
        tone: outputCount > 0 ? BriefTone.accent : BriefTone.warn,
      ));
    }
    final String weekNote;
    if (weekStats.isEmpty) {
      weekNote = '本周还没有结算过的任务 —— 完成或跳过任意一条,这里才会出现完成率。';
    } else if (completionRate == null && planned > 0) {
      weekNote = '计划了 $planned 条,还没有结算 ${planned - done} 条;完成或跳过之后才有完成率。';
    } else if (outputAvgScore != null) {
      weekNote = '输出均分 ${outputAvgScore.round()} 分;共 $outputCount 次作答有评分。';
    } else if (onTimeRate != null) {
      weekNote = '按时完成 ${(onTimeRate * 100).round()}%（实际用时 ≤ 目标时长的 1.2 倍）。';
    } else {
      weekNote = dash.review.lines.isEmpty ? '' : dash.review.lines.first;
    }

    // ④ 近 7 天柱(来自 StatsProvider 的 dailyLogs;没有就空数组,页面不画假柱)
    final List<double> bars = _weekBars(dailyLogs, at);
    int barsTotal = 0;
    for (final double v in bars) {
      barsTotal += v.round();
    }

    // ⑤ 一句提醒:优先用最严重且已测量的五维结论;其次错误档案最多的那一类
    String? reminder;
    String reminderLabel = '一句提醒';
    TutorInsight? worst;
    for (final TutorInsight i in dash.insights) {
      if (!i.measured) continue;
      if (worst == null || i.severity > worst.severity) worst = i;
    }
    if (worst != null && worst.severity >= 1) {
      // 同 lead:用 title 的人话结论,不用 evidence(可能含表名/内部口径)
      final String t = worst.title.trim();
      if (t.isNotEmpty) reminder = '$t —— 今天先把这一条改掉。';
      reminderLabel = '一句提醒';
    } else {
      final Map<String, int> tags = dash.source.errorTagCounts;
      if (tags.isNotEmpty) {
        final List<MapEntry<String, int>> entries = tags.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final MapEntry<String, int> top = entries.first;
        if (top.value > 0) {
          reminder = '「${top.key}」是最近错得最多的类型(${top.value} 次) —— 今天顺手改掉一处就够。';
        }
      }
    }

    // ⑥ 待测维度:没测到的维度明确列出来,并给「怎么测」
    final List<String> pending = <String>[
      for (final TutorInsight i in dash.insights)
        if (!i.measured) TutorDimensions.labelOf(i.dimension),
    ];
    final String pendingHint = pending.isEmpty
        ? ''
        : '${pending.join('、')}还没有数据 —— 做一次词汇量速测(约 5 分钟),就能把这几项变成真实数字。';

    return Briefing(
      at: at,
      eyebrow: _weekdayEn[wd - 1],
      dateBig: '${_two(at.month)} / ${_two(at.day)}',
      weekday: _weekdayCn[wd - 1],
      streakText: streak > 0 ? '连续 $streak 天' : '还没形成连续记录',
      greeting: _greeting(at.hour),
      headline: head.toString(),
      lead: lead,
      today: today,
      todayNote: note,
      totalMinutes: totalMinutes,
      dueWords: due,
      doneToday: doneToday,
      weekStats: weekStats,
      weekNote: weekNote,
      weekBars: bars,
      weekBarsTotal: barsTotal,
      reminder: reminder,
      reminderLabel: reminderLabel,
      pendingDimensions: pending,
      pendingHint: pendingHint,
      outputCount: outputCount,
      outputAvgScore: outputAvgScore,
    );
  }

  /// 接 [TutorInsight.dimension] 的 id → 中文名(与 `TutorDimensions` 同源)
  static String dimensionLabel(String dimension) =>
      TutorDimensions.labelOf(dimension);

  static TutorInsight? _firstMeasuredInsight(List<TutorInsight> insights) {
    for (final TutorInsight i in insights) {
      if (i.measured && i.valueText.isNotEmpty) return i;
    }
    return null;
  }

  static String _greeting(int hour) {
    if (hour >= 5 && hour < 11) return '早上好。';
    if (hour >= 11 && hour < 14) return '中午好。';
    if (hour >= 14 && hour < 18) return '下午好。';
    if (hour >= 18 && hour < 23) return '晚上好。';
    return '夜深了。';
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return '进行中';
      case 'suggestion':
        return '助理建议';
      default:
        return '待做';
    }
  }

  static List<double> _weekBars(List<LearningRecord>? logs, DateTime at) {
    if (logs == null) return const <double>[];
    final Map<String, double> byDay = <String, double>{};
    for (final LearningRecord r in logs) {
      final String key = _dayKey(r.date);
      byDay[key] = (byDay[key] ?? 0) + r.totalActivity.toDouble();
    }
    final List<double> out = <double>[];
    for (var i = 6; i >= 0; i--) {
      out.add(byDay[_dayKey(at.subtract(Duration(days: i)))] ?? 0);
    }
    return out;
  }

  static String _dayKey(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  static int? _intOrNull(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final String s = '$v'.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.round();
  }

  static double? _doubleOrNull(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final double? parsed = double.tryParse('$v'.trim());
    return parsed;
  }
}

/// 对外出口(设计文档与任务约定的名字):`TutorBriefing.build(TutorDashboard)`。
///
/// 内部实现是 [Briefing](纯数据 + 纯文案,可单测);这一层只是把入口收成
/// 一个语义明确的名字,避免页面直接依赖数据类的构造细节。
abstract final class TutorBriefing {
  static Briefing build(
    TutorDashboard dash, {
    DateTime? now,
    List<LearningRecord>? dailyLogs,
  }) =>
      Briefing.build(dash, now: now, dailyLogs: dailyLogs);
}

/// 「我的」首页「本周简报」的纯数据 + 纯文案。
///
/// 与助理简报同一套语言与纪律:只用传入的真实数字(来自 `StatsProvider` /
/// `LearnerModel` / 错误档案条数 / 写译记录条数),缺数据就写明缺什么。
class MineBriefing {
  const MineBriefing({
    required this.at,
    required this.eyebrow,
    required this.dateBig,
    required this.weekday,
    required this.greeting,
    required this.headline,
    required this.lead,
    required this.facts,
    required this.weekBars,
    required this.weekBarsTotal,
    required this.vocabText,
    required this.streakDays,
    required this.activeErrorKinds,
    required this.writingLogCount,
    required this.gaps,
  });

  final DateTime at;
  final String eyebrow;
  final String dateBig;
  final String weekday;
  final String greeting;
  final String headline;
  final String lead;
  final List<BriefFact> facts;
  final List<double> weekBars;
  final int weekBarsTotal;

  /// 词汇量基线文案:「约 4,200 词 · B1」/「尚未测量」
  final String vocabText;
  final int streakDays;
  final int activeErrorKinds;
  final int writingLogCount;

  /// 缺的数据(明确写出来,不假装有)
  final List<String> gaps;

  static const List<String> _weekdayEn = <String>[
    'THIS WEEK',
    'THIS WEEK',
    'THIS WEEK',
    'THIS WEEK',
    'THIS WEEK',
    'THIS WEEK',
    'THIS WEEK',
  ];
  static const List<String> _weekdayCn = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  static MineBriefing build({
    required int totalVocab,
    required int streakDays,
    required int totalExercises,
    required List<LearningRecord> dailyLogs,
    required int activeErrorKinds,
    required int writingLogCount,
    String? cefr,
    int? vocabEstimate,
    int? vocabLow,
    int? vocabHigh,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    final int wd = at.weekday.clamp(1, 7);

    final List<double> bars = Briefing._weekBars(dailyLogs, at);
    int total = 0;
    for (final double v in bars) {
      total += v.round();
    }

    // 本周事实:只放真实存在的数字
    final List<BriefFact> facts = <BriefFact>[];
    if (total > 0) {
      int activeDays = 0;
      for (final double v in bars) {
        if (v > 0) activeDays++;
      }
      facts.add(BriefFact(value: '$activeDays 天', label: '本周有记录'));
      facts.add(BriefFact(value: '$total', label: '本周活动量'));
    }
    if (streakDays > 0) facts.add(BriefFact(value: '$streakDays 天', label: '连续打卡', tone: BriefTone.accent));
    if (totalExercises > 0) {
      facts.add(BriefFact(value: '$totalExercises 次', label: '累计练习'));
    }

    final StringBuffer head = StringBuffer();
    if (total > 0) {
      head.write('这周你有 $total 点学习量');
      if (streakDays > 0) head.write(',已经连续 $streakDays 天');
      head.write('。');
    } else if (totalVocab > 0) {
      head.write('词库里已经有 $totalVocab 个词');
      head.write(',这周还没有新的学习记录。');
    } else {
      head.write('还没有学习记录 —— 从输入页收第一个词开始。');
    }

    final List<String> leadParts = <String>[];
    if (totalVocab > 0) leadParts.add('词库 $totalVocab 个词');
    if (vocabEstimate != null && vocabEstimate > 0) {
      final String range = (vocabLow != null && vocabHigh != null)
          ? '($vocabLow-$vocabHigh)'
          : '';
      leadParts.add('词汇量约 $vocabEstimate 词$range');
    }
    if (cefr != null && cefr.isNotEmpty) leadParts.add('CEFR $cefr');
    if (activeErrorKinds > 0) leadParts.add('待处理错误 $activeErrorKinds 类');
    if (writingLogCount > 0) leadParts.add('写译记录 $writingLogCount 篇');
    final String lead = leadParts.isEmpty
        ? '统计页会按真实记录画出趋势 —— 现在还没有可画的数据。'
        : '${leadParts.join(' · ')}。';

    final StringBuffer vocabText = StringBuffer();
    if (vocabEstimate != null && vocabEstimate > 0) {
      vocabText.write('约 $vocabEstimate 词');
      if (vocabLow != null && vocabHigh != null) {
        vocabText.write('($vocabLow-$vocabHigh)');
      }
      if (cefr != null && cefr.isNotEmpty) vocabText.write(' · $cefr');
      vocabText.write(' · 点击可重测');
    } else {
      vocabText.write('尚未测量 · 约 5 分钟,给出词汇量与 CEFR 区间');
    }

    final List<String> gaps = <String>[
      if (vocabEstimate == null || vocabEstimate <= 0) '词汇量基线',
      if (total == 0) '本周学习记录',
    ];

    return MineBriefing(
      at: at,
      eyebrow: _weekdayEn[wd - 1],
      dateBig: '${Briefing._two(at.month)} / ${Briefing._two(at.day)}',
      weekday: _weekdayCn[wd - 1],
      greeting: Briefing._greeting(at.hour),
      headline: head.toString(),
      lead: lead,
      facts: facts,
      weekBars: bars,
      weekBarsTotal: total,
      vocabText: vocabText.toString(),
      streakDays: streakDays,
      activeErrorKinds: activeErrorKinds,
      writingLogCount: writingLogCount,
      gaps: gaps,
    );
  }
}
