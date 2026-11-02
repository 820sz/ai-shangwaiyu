/// 每周报告(v2.1)—— **纯函数,无 IO**。
///
/// 为什么单独一层、且坚持"输入全是纯数据":
/// 1. 周报的价值在于**结论可信**:每条亮点/建议都必须能追到具体数字。
///    把"取数"和"下结论"分开,下结论这段就能被单测钉死(见
///    test/weekly_report_test.dart),而取数失败(DB 异常)不会污染文案逻辑;
/// 2. 报告不调 AI:本地能算出来的东西不该花钱、也不该等网络;
/// 3. 与 ReviewQueue 同样口径:**复习负荷**这类判断沿用 FsrsScheduler 的结果,
///    不在周报里另写一套算法(否则两处阈值迟早打架)。
///
/// 口径约定(写在这里,免得 UI 与测试各理解一套):
/// - **周期:滚动 7 天**,`[今天-6天 00:00, 今天 23:59:59.999]`(含今天)。
///   为什么不按自然周(周一~周日):学习类 App 的使用是"想起来就学",
///   自然周会让周一早上的用户看到"本周无数据"——实际他昨天刚学了 40 分钟。
///   滚动 7 天永远有完整的一周内容,空态只意味着"真的一周没动"。
library;

/// 周报输入(全部由 UI 从既有数据接口取好,本文件不碰数据库)
class WeeklyInputs {
  /// 有学习记录的自然日(已按天去重)。用于 activeDays,也是"这周动没动"的判据。
  final Set<DateTime> activeDates;

  /// 阅读会话数(getReadingStats().sessions)
  final int readingSessions;

  /// 阅读词数
  final int wordsRead;

  /// 阅读分钟数
  final int minutesRead;

  /// 新收词数(getVocabCountSince(起点))
  final int newWords;

  /// 本周复习过的词数(来自 word_review 的 last_review_at 落点)
  final int reviewsDone;

  /// 复习过的词里自评"忘了"的次数(错误档案 source='review')
  final int reviewsLapsed;

  /// 本周读完的材料数(getRecentMaterials 里 finished_at 落在窗口内)
  final int materialsFinished;

  /// **已开始但没读完**的材料,按进度从高到低(建议"差一点就读完"优先)
  final List<UnfinishedMaterial> unfinishedMaterials;

  /// 本周读后测验正确率;null = 本周没做测验(**不能当成 0**,那是编造)
  final double? quizAccuracy;

  /// 本周还处于 active 的错误标签(最多几类由 build 截断)
  final List<ErrorTagBrief> activeErrors;

  // ── 输出维度(v2.18.0,批 3 收尾)──
  // 以前周报只有"输入"(读了多少),用户天天写译也看不到产出 —— 这一块补上
  // 「写了没有/写得怎么样」,数据来自 output_attempts(UI 用
  // OutputFeedback.outputSnapshot(days: 7) 取好传进来)。
  /// 本周输出练习次数(写作/翻译/回译/rubric 作答)
  final int outputAttempts;

  /// 本周 rubric 均分(0..100 百分比;null = 没有可评分作答,不能写成 0)
  final double? outputAvgScore;

  /// 上周 rubric 均分(可空;有值才显示"较上周 ±x%")
  final double? outputPrevAvgScore;

  /// 本周各评分维度均分(维度 key → 0..100;用于"哪一维最弱")
  final Map<String, double> outputDimensions;

  /// 本周输出的错误热点(已归一成错误档案的既有标签)
  final List<ErrorTagBrief> outputErrorTags;

  /// 全库到期分布(getReviewBuckets)
  final Map<String, int> reviewBuckets;

  /// 未来 7 天每日到期数(index 0 = 今天,过期量已并入今天)
  final List<int> forecast;

  /// 每日目标时间(来自学习者模型 dailyMinutes);0/null = 未知,不硬编目标
  final int? dailyMinutes;

  const WeeklyInputs({
    this.activeDates = const {},
    this.readingSessions = 0,
    this.wordsRead = 0,
    this.minutesRead = 0,
    this.newWords = 0,
    this.reviewsDone = 0,
    this.reviewsLapsed = 0,
    this.materialsFinished = 0,
    this.unfinishedMaterials = const [],
    this.quizAccuracy,
    this.activeErrors = const [],
    this.outputAttempts = 0,
    this.outputAvgScore,
    this.outputPrevAvgScore,
    this.outputDimensions = const {},
    this.outputErrorTags = const [],
    this.reviewBuckets = const {},
    this.forecast = const [],
    this.dailyMinutes,
  });
}

/// 一条"没读完"的材料(带进度,建议里要能点名 + 报百分比)
class UnfinishedMaterial {
  final String title;
  final int percent;

  /// 估算总词数(0 = 未知,文案里不报词数)
  final int wordCount;

  const UnfinishedMaterial({
    required this.title,
    required this.percent,
    this.wordCount = 0,
  });
}

/// 一条错误标签(周报只需要"名字 + 次数 + 最近时间")
class ErrorTagBrief {
  final String tag;
  final int count;
  final DateTime? lastAt;

  const ErrorTagBrief({required this.tag, required this.count, this.lastAt});
}

/// 周报「输出」块的取数结果 —— 从 `OutputFeedback.outputSnapshot(...)` 的
/// **原始 Map** 解析而来(纯函数:不碰数据库、不查时间)。
///
/// ## E1-9:周报与助理共用同一份数据层,口径只允许一处
/// 助理侧(`TutorSnapshotService` → `LearnerSnapshotLoader`)和本页都必须:
/// - **只调** `OutputFeedback.outputSnapshot(...)`,不各自写 SQL / 不各自读别的表;
/// - `attempts` 按 int 解析、`avgScore` 按 `double?` 解析 —— **null 保持 null**
///   (没作答 ≠ 0 分,写成 0 会把"没写"误报成"写得烂");
/// - 保留原始精度,不在这里四舍五入 / 不折算百分比(展示层才 round);
/// - 窗口天数由调用方传(周报 7 天、助理 30 天):**差异只在窗口,不在算法**。
///
/// 这三条被 `test/weekly_report_consistency_test.dart` 钉住:哪天有人在周报里
/// 另算一套,测试会立刻指出"哪一边和助理对不上"。
class WeeklyOutputBlock {
  /// 本周输出练习次数(0 = 没做;不是 null:快照口径里 attempts 恒有值)
  final int attempts;

  /// rubric 均分(0..100;null = 没有可评分作答,不能写成 0)
  final double? avgScore;

  /// 上一周均分(可空;用于"较上周 ±x%",没数据就不显示)
  final double? prevAvgScore;

  /// 各评分维度均分百分比(key = 维度 key)
  final Map<String, double> dimensions;

  /// 错误热点(已归一到错误档案的既有标签)
  final List<ErrorTagBrief> errorTags;

  /// 最近一次作答时间(用来把"只做了输出"的那天也算成活跃日)
  final DateTime? lastAt;

  const WeeklyOutputBlock({
    this.attempts = 0,
    this.avgScore,
    this.prevAvgScore,
    this.dimensions = const {},
    this.errorTags = const [],
    this.lastAt,
  });

  /// 把 `OutputFeedback.outputSnapshot(...)` 的两份原始结果解析成周报字段。
  ///
  /// [current] 是本周窗口,`[previous]` 是上周窗口(只取 `avgScore` 做环比)。
  /// 传 null / 缺键 / 脏类型都退化成安全默认值:周报可以少一行结论,
  /// 但不能因为一条脏数据出现假数字。
  factory WeeklyOutputBlock.fromSnapshots({
    required Map<String, Object?> current,
    Map<String, Object?>? previous,
  }) {
    return WeeklyOutputBlock(
      attempts: outputSnapshotInt(current['attempts']),
      avgScore: outputSnapshotDouble(current['avgScore']),
      prevAvgScore:
          previous == null ? null : outputSnapshotDouble(previous['avgScore']),
      dimensions: _dimensionsOf(current['dimensionAvg']),
      errorTags: _errorTagsOf(current['topErrorTags']),
      lastAt: _dateOf(current['lastAt']),
    );
  }
}

/// `outputSnapshot['attempts']` 的**唯一**解析口径(助理快照也按这个读)
///
/// 为什么公开:周报与助理同口径这句话必须能被测试/别处引用,而不是各写一个
/// `(x as num?)?.toInt()` —— 那种"看起来一样"的重复实现正是口径分叉的起点。
int outputSnapshotInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('${raw ?? ''}') ?? 0;
}

/// `outputSnapshot['avgScore']` 的**唯一**解析口径。
///
/// 关键纪律:**没有值就返回 null**,绝不兜底成 0 —— "本周没写"和"写了 0 分"
/// 在周报/助理里必须是两句不同的话。
double? outputSnapshotDouble(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  final text = '$raw'.trim();
  if (text.isEmpty || text == 'null') return null;
  return double.tryParse(text);
}

Map<String, double> _dimensionsOf(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, double>{};
  for (final entry in raw.entries) {
    final key = '${entry.key}'.trim();
    final value = outputSnapshotDouble(entry.value);
    if (key.isEmpty || value == null) continue;
    out[key] = value;
  }
  return out;
}

List<ErrorTagBrief> _errorTagsOf(Object? raw) {
  if (raw is! Map) return const [];
  final out = <ErrorTagBrief>[];
  for (final entry in raw.entries) {
    final tag = '${entry.key}'.trim();
    final count = outputSnapshotInt(entry.value);
    if (tag.isEmpty || count <= 0) continue;
    out.add(ErrorTagBrief(tag: tag, count: count));
  }
  // 次数降序、同次数按标签名:与周报正文的排序规则一致,两次渲染不跳
  out.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.tag.compareTo(b.tag);
  });
  return out;
}

DateTime? _dateOf(Object? raw) {
  final text = '${raw ?? ''}'.trim();
  if (text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text);
}

/// 一周报告的内容(纯数据,渲染与文案都在这里定稿)
class WeeklyReport {
  final DateTime from, to;

  /// 有学习记录的天数
  final int activeDays;

  final int wordsRead, minutesRead;

  /// 新收词数 / 复习过的词数
  final int newWords, reviewsDone;

  final int materialsFinished;

  /// 本周读后测验正确率(null = 本周没做测验,文案里必须缺席而不是写 0%)
  final double? quizAccuracy;

  /// 本周最该处理的 2-3 类错误(带次数)
  final List<String> topErrors;

  // ── 输出块(v2.18.0)──
  /// 本周输出练习次数(0 = 没有输出练习)
  final int outputAttempts;

  /// 本周 rubric 均分(0..100;null = 没有可评分作答)
  final double? outputAvgScore;

  /// 本周输出错误热点(已归一成既有标签,格式「时态(3 次)」)
  final List<String> outputErrorTags;

  /// 「输出」块的现成文案(1~4 行)。**没有数据时也有一行明确说明**
  /// ("本周没有输出练习"),UI 直接逐行渲染即可,不必自己拼措辞。
  final List<String> outputLines;

  /// 2-4 条"本周做得好/值得注意"的结论(每条必带数字)
  final List<String> highlights;

  /// 1-3 条下周建议(具体可执行,每条必带数字或材料名)
  final List<String> suggestions;

  /// 未来 7 天负荷(index 0 = 今天)
  final Map<String, int> forecast;

  /// 本周是否有任何学习投入(全部为 0 且没测验 = false)
  final bool isActive;

  /// 本次报告的**数据限额**(说清"这些数字截到哪"):新收词是精确计数,
  /// 材料进度按最近 20 条材料算。UI 用它给一句话脚注,避免用户以为全量统计。
  final int dataWindowDays;

  const WeeklyReport({
    required this.from,
    required this.to,
    required this.activeDays,
    required this.wordsRead,
    required this.minutesRead,
    required this.newWords,
    required this.reviewsDone,
    required this.materialsFinished,
    required this.quizAccuracy,
    required this.topErrors,
    this.outputAttempts = 0,
    this.outputAvgScore,
    this.outputErrorTags = const [],
    this.outputLines = const [],
    required this.highlights,
    required this.suggestions,
    required this.forecast,
    required this.isActive,
    this.dataWindowDays = 7,
  });
}

/// 周报结论生成器(纯函数)
class WeeklyReportBuilder {
  WeeklyReportBuilder._();

  /// 一次建议里最多列几类错误
  static const int maxTopErrors = 3;

  /// 报告天数(滚动窗口)
  static const int windowDays = 7;

  /// 没填过每日目标时的兜底:一句话目标也要有数字,才不至于变成"加油"
  static const int defaultDailyMinutes = 20;

  /// 生成报告。
  ///
  /// [now] 注入时间基准,便于单测;窗口是 `[now-6天 00:00, now 当天 23:59:59.999]`。
  static WeeklyReport build({
    required DateTime now,
    required WeeklyInputs inputs,
  }) {
    final to = _endOfDay(now);
    final from = _startOfDay(now).subtract(const Duration(days: windowDays - 1));

    // 窗口内的活跃日才计数:UI 若把 30 天的数据传进来,也不该虚增 activeDays
    final activeDays = inputs.activeDates
        .map(_startOfDay)
        .where((d) => !d.isBefore(from) && !d.isAfter(to))
        .toSet()
        .length;

    final buckets = inputs.reviewBuckets;
    final overdue = buckets['overdue'] ?? 0;

    final activeErrors = [...inputs.activeErrors]
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        // 次数相同时"最近的更急"优先(last_at 缺失排最后)
        final at = a.lastAt, bt = b.lastAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

    final topErrors = activeErrors
        .take(maxTopErrors)
        .map((e) => '${e.tag}(${e.count} 次)')
        .toList();

    // 输出错误热点:与错误档案同一套标签(已由 OutputFeedback 归一),
    // 次数相同时按名称排序 —— 同一份数据两次生成必须完全一致。
    final outputErrors = [...inputs.outputErrorTags]
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.tag.compareTo(b.tag);
      });
    final outputErrorTags = outputErrors
        .take(maxTopErrors)
        .map((e) => '${e.tag}(${e.count} 次)')
        .toList();

    final isActive = activeDays > 0 ||
        inputs.readingSessions > 0 ||
        inputs.wordsRead > 0 ||
        inputs.newWords > 0 ||
        inputs.reviewsDone > 0 ||
        inputs.materialsFinished > 0 ||
        inputs.quizAccuracy != null ||
        // v2.18.0:只做了输出练习(没阅读)也是"本周活跃" —— 否则周报会
        // 一边列出"完成 5 次写作",一边说"近 7 天还没有学习记录"。
        inputs.outputAttempts > 0 ||
        inputs.outputAvgScore != null;

    // 未来 7 天负荷:index 0 = 今天(与 FsrsScheduler.loadForecast 同口径)
    final forecast = <String, int>{};
    for (var i = 0; i < inputs.forecast.length; i++) {
      forecast['$i'] = inputs.forecast[i];
    }
    // 兜底:没有逐日预测时,起码让"今天"有个数(过期量也是今天要还的债)
    if (forecast.isEmpty) forecast['0'] = overdue;

    return WeeklyReport(
      from: from,
      to: to,
      activeDays: activeDays,
      wordsRead: inputs.wordsRead,
      minutesRead: inputs.minutesRead,
      newWords: inputs.newWords,
      reviewsDone: inputs.reviewsDone,
      materialsFinished: inputs.materialsFinished,
      quizAccuracy: inputs.quizAccuracy,
      topErrors: topErrors,
      outputAttempts: inputs.outputAttempts,
      outputAvgScore: inputs.outputAvgScore,
      outputErrorTags: outputErrorTags,
      outputLines: _outputLines(
        outputAttempts: inputs.outputAttempts,
        outputAvgScore: inputs.outputAvgScore,
        outputPrevAvgScore: inputs.outputPrevAvgScore,
        outputDimensions: inputs.outputDimensions,
        outputErrors: outputErrors,
      ),
      highlights: _highlights(
        activeDays: activeDays,
        inputs: inputs,
        isActive: isActive,
      ),
      suggestions: _suggestions(
        inputs: inputs,
        activeErrors: activeErrors,
        overdue: overdue,
        isActive: isActive,
      ),
      forecast: forecast,
      isActive: isActive,
    );
  }

  // ── 输出块 ──

  /// 评分维度 key → 中文标签(与 rubrics.dimensions_json 的 key 对齐)。
  /// 未知 key 直接显示原 key(宁可露出英文,也不猜一个错标签)。
  static const Map<String, String> _dimLabels = {
    'content': '内容切题',
    'organization': '组织连贯',
    'language': '语言准确',
    'vocabulary': '词汇丰富',
    'sentence': '句式多样',
    'comprehension': '原文理解',
    'accuracy': '准确',
    'fluency': '表达通顺',
    'coverage': '要点覆盖',
    'coherence': '连贯',
  };

  /// 生成「输出」块文案(1~4 行)。
  ///
  /// 关键纪律:**没有数据也要明说**("本周没有输出练习"),而不是像旧周报那样
  /// 整块省略 —— 用户要的是"数据追踪复盘":看不见 = 以为没记录。
  static List<String> _outputLines({
    required int outputAttempts,
    required double? outputAvgScore,
    required double? outputPrevAvgScore,
    required Map<String, double> outputDimensions,
    required List<ErrorTagBrief> outputErrors,
  }) {
    if (outputAttempts <= 0 && outputAvgScore == null) {
      return const ['本周没有输出练习(写作 / 翻译 / 回译)'];
    }
    final lines = <String>[];
    final parts = <String>['完成 $outputAttempts 次输出练习'];
    if (outputAvgScore != null) {
      parts.add('rubric 均分 ${outputAvgScore.round()}%');
      if (outputPrevAvgScore != null) {
        final delta = (outputAvgScore - outputPrevAvgScore).round();
        parts.add('较上周 ${delta >= 0 ? '+' : ''}$delta%');
      }
    }
    lines.add(parts.join(','));

    if (outputDimensions.isNotEmpty) {
      final dims = outputDimensions.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final shown = dims.take(3).map((e) {
        final label = _dimLabels[e.key] ?? e.key;
        return '$label ${e.value.round()}%';
      }).join('、');
      // 只列前三:维度是"看方向"的,列全反而看不清重点
      lines.add('维度均分:$shown');
      // 已按分数降序,最弱的就是最后一项;低于 60% 才点出来(否则是噪声)
      final weakKey = outputDimensions.entries.isEmpty
          ? null
          : (outputDimensions.entries.toList()
                ..sort((a, b) => a.value.compareTo(b.value)))
              .first
              .key;
      if (weakKey != null && outputDimensions[weakKey]! < 60) {
        lines.add(
          '最弱维度:${_dimLabels[weakKey] ?? weakKey}'
          '(${outputDimensions[weakKey]!.round()}%)',
        );
      }
    }

    if (outputErrors.isNotEmpty) {
      final top = [...outputErrors]
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.tag.compareTo(b.tag);
        });
      lines.add(
        '错误热点:${top.take(3).map((e) => '${e.tag}(${e.count} 次)').join('、')}',
      );
    }
    return lines;
  }

  /// 最弱的评分维度 key(空 map / 全 null → null)。抽成函数是为了让
  /// 「输出块」与「下周建议」用同一个判据,不各写一套排序。
  static String? _weakestDimension(Map<String, double> dims) {
    if (dims.isEmpty) return null;
    final sorted = dims.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return sorted.first.key;
  }

  // ── 亮点 ──

  /// 2-4 条,按"含金量"打分取前 4。
  /// 每条都由**数字驱动**:分数为 0 的条目直接不生成 —— 宁缺毋滥,
  /// "本周复习了 0 个词"这种句子放进"亮点"里是自我欺骗。
  static List<String> _highlights({
    required int activeDays,
    required WeeklyInputs inputs,
    required bool isActive,
  }) {
    final scored = <_Scored>[];

    if (inputs.readingSessions > 0) {
      // 有速度就报速度:说明"读得又多又快"这句话是有依据的
      final wpm = inputs.minutesRead > 0
          ? (inputs.wordsRead / inputs.minutesRead).round()
          : 0;
      scored.add(_Scored(
        100,
        '读了 ${inputs.wordsRead} 词 / ${inputs.minutesRead} 分钟'
        '(${inputs.readingSessions} 次)${wpm > 0 ? ',约 $wpm 词/分' : ''}',
      ));
    } else if (isActive && inputs.wordsRead > 0) {
      // 有词数没会话(旧数据):仍然报事实,但不编次数
      scored.add(_Scored(60, '读了 ${inputs.wordsRead} 词'));
    }

    if (inputs.quizAccuracy != null) {
      final pct = (inputs.quizAccuracy! * 100).round();
      scored.add(_Scored(
        pct >= 70 ? 95 : 30,
        '读后测验正确率 $pct%',
      ));
    }

    // 输出练习(v2.18.0):有产出就是亮点 —— 它是"闭环另一半"的直接证据
    if (inputs.outputAttempts > 0) {
      final avg = inputs.outputAvgScore;
      scored.add(_Scored(
        90,
        '完成 ${inputs.outputAttempts} 次输出练习'
        '${avg != null ? '(rubric 均分 ${avg.round()}%)' : ''}',
      ));
    }

    if (inputs.newWords > 0) {
      scored.add(_Scored(
        70,
        '新收 ${inputs.newWords} 个词'
        '${inputs.reviewsDone > 0 ? ',复习了 ${inputs.reviewsDone} 个词' : ''}',
      ));
    } else if (inputs.reviewsDone > 0) {
      scored.add(_Scored(65, '复习了 ${inputs.reviewsDone} 个词'));
    }

    if (inputs.materialsFinished > 0) {
      scored.add(_Scored(80, '读完 ${inputs.materialsFinished} 篇材料'));
    }

    if (activeDays > 0) {
      scored.add(_Scored(50, '有 $activeDays 天打开过应用学习'));
    }

    if (inputs.reviewsDone > 0 && inputs.reviewsLapsed == 0) {
      // "复习全对"才是亮点;有忘记的词就不算,免得把漏词包装成成绩。
      // 必须带数字:没有数字的结论在这份报告里不可信(也无从验证)
      scored.add(_Scored(40, '复习的 ${inputs.reviewsDone} 个词里没有一次"不认识"'));
    }

    if (!isActive) {
      // 零投入也要有数字:给出目标,让用户知道"多少才算开始"
      final daily = _dailyMinutes(inputs);
      scored
        ..clear()
        ..add(_Scored(
          10,
          '近 $windowDays 天还没有学习记录(建议每天 $daily 分钟)',
        ));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.text.compareTo(b.text);
    });
    return scored.take(4).map((e) => e.text).toList();
  }

  // ── 建议 ──

  /// 1-3 条,按优先级打分取前 3。每条都点名**具体数字/材料**:
  /// "继续保持""多读多练"这类句子在这里写不出来 —— 因为每个分支都必须
  /// 先把待办量算成一个数。
  static List<String> _suggestions({
    required WeeklyInputs inputs,
    required List<ErrorTagBrief> activeErrors,
    required int overdue,
    required bool isActive,
  }) {
    final scored = <_Scored>[];

    // ① 过期债最急:过期不清,新词的记忆会被复习量挤掉
    if (overdue > 0) {
      scored.add(_Scored(
        100,
        '先清 $overdue 个过期词,再加新词'
        '${_dailyMinutes(inputs) > 0 ? '(每天 ${_dailyMinutes(inputs)} 分钟大约能复习 ${_reviewCapacity(inputs)} 个)' : ''}',
      ));
    }

    // ② 复发/高频错误:点名字 + 次数,让用户知道"改哪个最划算"
    if (activeErrors.isNotEmpty) {
      final top = activeErrors.first;
      scored.add(_Scored(
        top.count >= 3 ? 92 : 55,
        '错误档案还有 ${activeErrors.length} 类待处理,'
        '优先处理「${top.tag}」(${top.count} 次)',
      ));
    }

    // ③ 差一点就读完的材料:投入产出比最高的一条建议(带书名与百分比)
    if (inputs.unfinishedMaterials.isNotEmpty) {
      final m = inputs.unfinishedMaterials.first;
      final left = m.wordCount > 0
          ? ',还剩约 ${(m.wordCount * (100 - m.percent) / 100).round()} 词'
          : '';
      scored.add(_Scored(85, '把「${m.title}」读完后半段(已读 ${m.percent}%$left)'));
    }

    // ④ 正确率低:先补材料再测验;本周没测:先测一次才知道效果
    final acc = inputs.quizAccuracy;
    if (acc != null && acc < 0.7) {
      final pct = (acc * 100).round();
      scored.add(_Scored(80, '读后测验正确率只有 $pct%,重读一遍再测,目标 80%'));
    } else if (acc == null && isActive) {
      scored.add(_Scored(45, '这周没做读后测验 —— 读完 1 篇后做一次,才能看出效果'));
    }

    // ⑤ 复习量偏少:复习是"不遗忘"的唯一手段
    final daily = _dailyMinutes(inputs);
    if (inputs.reviewsDone > 0 && inputs.reviewsDone < daily) {
      scored.add(_Scored(50, '复习了 ${inputs.reviewsDone} 个词,'
          '低于每天 $daily 分钟的容量(约 ${_reviewCapacity(inputs)} 个/天)'));
    }

    // ⑦ 输出闭环(v2.18.0):有输入没输出 → 点名补一次输出;均分偏低 → 按最弱维度改
    // 优先级刻意排在"过期债/未读完材料"之后:**周报只有 3 条建议位**,
    // 不能让"补一次输出"挤掉"差一点读完"这种投入产出比更高的行动项;
    // 该说的事实由「输出块」那条"本周没有输出练习"承担,不依赖建议位。
    final outputAvg = inputs.outputAvgScore;
    if (isActive && inputs.outputAttempts <= 0 && outputAvg == null) {
      scored.add(_Scored(
        45,
        '本周还没有输出练习:写 3 句话或做 1 次回译(约 10 分钟),才能检验读到的内容',
      ));
    } else if (outputAvg != null && outputAvg < 60) {
      final weak = _weakestDimension(inputs.outputDimensions);
      scored.add(_Scored(
        75,
        '输出均分 ${outputAvg.round()}%'
        '${weak != null ? ',${_dimLabels[weak] ?? weak}最弱' : ''}'
        ':按 rubric 改 1 次,先改证据项最多的那条',
      ));
    }

    // ⑥ 一条建议都没有(本周空转或一切正常)时,给一个带数字的基准目标:
    //    周报不能以"加油"收尾,必须告诉用户下周具体做到多少
    if (scored.isEmpty) {
      final weekWords = daily * 30; // 20 分钟 ≈ 600 词 ⇒ 词/分钟 ≈ 30
      scored.add(_Scored(
        20,
        '下周目标:读 $weekWords 词 / ${daily * windowDays} 分钟'
        '(每天 $daily 分钟);读完 1 篇材料后做一次读后测验',
      ));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.text.compareTo(b.text);
    });
    return scored.take(3).map((e) => e.text).toList();
  }

  /// 每日目标分钟数:模型没填过就用兜底值(0 会让所有阈值失效)
  static int _dailyMinutes(WeeklyInputs inputs) {
    final m = inputs.dailyMinutes ?? 0;
    return m > 0 ? m : defaultDailyMinutes;
  }

  /// 一天的复习容量(个):与 ReviewQueue.secondsPerCard 同口径(8 秒/张)
  static int _reviewCapacity(WeeklyInputs inputs) =>
      (_dailyMinutes(inputs) * 60 / 8).floor();

  // ── 日期工具(与 database.dart 的 getTutorTasks 同思路:用 DateTime(y,m,d±n)
  //    而不是 add(Duration(days:1)),后者遇夏令时会偏 1 小时)──

  static DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

  static DateTime _endOfDay(DateTime t) =>
      DateTime(t.year, t.month, t.day + 1).subtract(const Duration(milliseconds: 1));
}

/// 打分条目(同分时按文案排序,保证结果可复现)
class _Scored {
  final int score;
  final String text;
  const _Scored(this.score, this.text);
}
