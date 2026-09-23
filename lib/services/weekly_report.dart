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

    final isActive = activeDays > 0 ||
        inputs.readingSessions > 0 ||
        inputs.wordsRead > 0 ||
        inputs.newWords > 0 ||
        inputs.reviewsDone > 0 ||
        inputs.materialsFinished > 0 ||
        inputs.quizAccuracy != null;

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
