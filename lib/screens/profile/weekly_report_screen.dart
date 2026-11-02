import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/learning_record.dart';
import '../../services/database.dart';
import '../../services/fsrs.dart';
import '../../services/learner_model_store.dart';
import '../../services/output_feedback.dart';
import '../../services/review_queue.dart';
import '../../services/weekly_report.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/stats_chart.dart';
import '../../widgets/waiting.dart';

/// 每周报告页(v2.1)。
///
/// 学习统计页给的是曲线与热力图 —— 那回答"我做了多少";这一页回答
/// **"这周做的到底有没有用,下周该改什么"**,所以每条结论都必须带数字
/// (文案在 WeeklyReportBuilder 里生成,本页只负责取数与渲染,不自己造句)。
///
/// 为什么报告不调 AI:这里的结论全是本地可算的确定性事实(读了多少、
/// 正确率多少、欠多少复习)。让模型复述一遍数字既慢又可能编,凡是能算的
/// 就不该问模型 —— 这就是"无证据不下结论"的具体做法。
class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  WeeklyReport? _report;
  bool _loading = true;
  String? _error;

  /// 这份报告是"补算"的旧周期(null = 就是当前这 7 天)
  DateTime? _asOf;

  /// 近 35 天的每日学习日志(周报顶部两张图用)。
  ///
  /// 为什么单独取一份而不是塞进 [WeeklyReport]:报告是给"结论"的模型,
  /// 顶部图是"原始数据"的可视化;把逐日数组塞进报告模型会让 builder 多背
  /// 一个只给渲染用的字段。这里只读 `daily_log`(新收词 + 练习量),
  /// 复习结果按词存 `word_review`、没有逐日历史,所以不画复习曲线。
  List<LearningRecord> _dailyLogs = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final anchor = _asOf ?? DateTime.now();
      final report = await _buildReport(anchor);
      // 顶部两张图要"逐日"数据:范围覆盖热力图的 5 周(35 天)并**止于报告末日**,
      // 这样回看「上一个 7 天」时图上的日期与报告区间对得上,而不是画今天的。
      final end = DateTime(anchor.year, anchor.month, anchor.day);
      final logs = await DatabaseService.getDailyLogsInRange(
        end.subtract(const Duration(days: 34)),
        end,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _dailyLogs = logs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '生成周报失败:$e';
        _loading = false;
      });
    }
  }

  /// 取数:全部来自既有接口,本页不写 SQL。
  /// 取数失败(DB 异常)会抛出去 → 上游走失败态给「重试」,而不是渲染一份
  /// 全是 0 的假报告 —— "读不到数据"和"这周没学习"必须能区分。
  Future<WeeklyReport> _buildReport(DateTime now) async {
    final to = _endOfDay(now);
    final from = _startOfDay(now).subtract(const Duration(days: 6));

    final reading = await DatabaseService.getReadingStats(days: 7);
    final vocab = await DatabaseService.getRecentVocabularies(days: 7, limit: 200);
    final materials = await DatabaseService.getRecentMaterials(limit: 20);
    final accuracy = await DatabaseService.getQuizAccuracy(days: 7);
    final activeErrors = await DatabaseService.getErrorTags(status: 'active');
    final buckets = await DatabaseService.getReviewBuckets(now: now);
    final reviews = await DatabaseService.getWordReviews();
    final tasks = await DatabaseService.getTutorTasks(now);

    // v3 批 3 收尾:本周输出练习(写作/翻译/回译)聚合 —— 以前周报只有输入侧,
    // 用户"天天写译、周报里一个字都没有"(数据孤岛)。这里读最近 7 天,
    // 并对上一周同一窗口再读一次,用于"较上周 ±x%"。
    final output = await OutputFeedback.outputSnapshot(days: 7, now: to);
    final prevOutput = await OutputFeedback.outputSnapshot(
      days: 7,
      now: from.subtract(const Duration(milliseconds: 1)),
    );
    final outputAttempts = (output['attempts'] as num?)?.toInt() ?? 0;
    final outputAvgScore = (output['avgScore'] as num?)?.toDouble();
    final outputPrevAvgScore = (prevOutput['avgScore'] as num?)?.toDouble();
    final outputDimensions = <String, double>{};
    final dimRaw = output['dimensionAvg'];
    if (dimRaw is Map) {
      for (final entry in dimRaw.entries) {
        if (entry.value is num) {
          outputDimensions['${entry.key}'] = (entry.value as num).toDouble();
        }
      }
    }
    final outputErrorTags = <ErrorTagBrief>[];
    final tagRaw = output['topErrorTags'];
    if (tagRaw is Map) {
      for (final entry in tagRaw.entries) {
        if (entry.value is num && (entry.value as num) > 0) {
          outputErrorTags.add(ErrorTagBrief(
            tag: '${entry.key}',
            count: (entry.value as num).toInt(),
          ));
        }
      }
    }
    // 有输出练习的那几天也算活跃(以前"只做了输出"会被周报当成没学习)
    final lastOutRaw = '${output['lastAt'] ?? ''}'.trim();
    final lastOutputAt = lastOutRaw.isEmpty ? null : DateTime.tryParse(lastOutRaw);

    // ── 活跃日:把各数据源里"有动作"的自然日并起来 ──
    // 为什么这么拼:没有任何一个接口直接给逐日活跃度(getReadingStats 只有
    // 合计),而"这周动了几天"恰恰是习惯类报告最该说的数字。宁可多源并集
    // (可能略微高估:一次复习 + 一次收藏同一天只算一天,不会重复计),
    // 也不要漏掉用户真实做过的日子。
    final activeDates = <DateTime>{};
    int newWords = 0;
    for (final v in vocab) {
      if (!v.createdAt.isBefore(from) && !v.createdAt.isAfter(to)) {
        newWords++;
        activeDates.add(_startOfDay(v.createdAt));
      }
    }

    int reviewsDone = 0;
    int reviewsLapsed = 0;
    for (final row in reviews) {
      final at = DateTime.tryParse('${row['last_review_at']}');
      if (at == null || at.isBefore(from) || at.isAfter(to)) continue;
      // 注意口径:word_review 每个词只有一行,所以这里数的是"本周复习过的词数"
      // (不是复习次数)—— 同一个词本周复习 3 次只算 1 个,这个保守口径是对的
      reviewsDone++;
      activeDates.add(_startOfDay(at));
      final reps = (row['reps'] as num?)?.toInt() ?? 0;
      final lapses = (row['lapses'] as num?)?.toInt() ?? 0;
      if (lapses > 0 && reps > 0 && lapses >= reps) reviewsLapsed++;
    }
    // "本周有过忘词"的更稳判据:错误档案里 source='review' 的最近时间落在窗口内
    final lapsedFromErrors = activeErrors
        .where((r) => '${r['source']}' == 'review')
        .map((r) => DateTime.tryParse('${r['last_at']}'))
        .whereType<DateTime>()
        .where((t) => !t.isBefore(from) && !t.isAfter(to))
        .length;
    reviewsLapsed = reviewsLapsed > 0 ? reviewsLapsed : lapsedFromErrors;

    int materialsFinished = 0;
    final unfinished = <UnfinishedMaterial>[];
    for (final m in materials) {
      final finishedAt = DateTime.tryParse('${m['finished_at']}');
      final updatedAt = DateTime.tryParse('${m['updated_at']}');
      if (updatedAt != null && !updatedAt.isBefore(from) && !updatedAt.isAfter(to)) {
        activeDates.add(_startOfDay(updatedAt));
      }
      final title = '${m['title'] ?? '未命名材料'}';
      if (finishedAt != null && !finishedAt.isBefore(from) && !finishedAt.isAfter(to)) {
        materialsFinished++;
        activeDates.add(_startOfDay(finishedAt));
        continue;
      }
      final percent = (m['percent'] as num?)?.toInt() ?? 0;
      // 只把"开了头又没读完"的算进来:0% 等于没读,不该出现在建议里
      if (finishedAt == null && percent > 0) {
        unfinished.add(UnfinishedMaterial(
          title: title,
          percent: percent,
          wordCount: (m['word_count'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    // 进度高的优先("差一点就读完"投入产出比最高)
    unfinished.sort((a, b) => b.percent.compareTo(a.percent));

    // 导师任务卡:勾掉的那些也是"学过"的证据
    for (final t in tasks) {
      final doneAt = DateTime.tryParse('${t['done_at']}');
      if (doneAt != null && !doneAt.isBefore(from) && !doneAt.isAfter(to)) {
        activeDates.add(_startOfDay(doneAt));
      }
    }

    // 只做了输出练习的那天同样是活跃日(数据孤岛修好后,输出也该算学习)
    if (lastOutputAt != null &&
        !lastOutputAt.isBefore(from) &&
        !lastOutputAt.isAfter(to)) {
      activeDates.add(_startOfDay(lastOutputAt));
    }

    final model = LearnerModelStore.load();

    return WeeklyReportBuilder.build(
      now: now,
      inputs: WeeklyInputs(
        activeDates: activeDates,
        readingSessions: (reading['sessions'] as num?)?.toInt() ?? 0,
        wordsRead: (reading['words'] as num?)?.toInt() ?? 0,
        minutesRead: (reading['minutes'] as num?)?.toInt() ?? 0,
        newWords: newWords,
        reviewsDone: reviewsDone,
        reviewsLapsed: reviewsLapsed,
        materialsFinished: materialsFinished,
        unfinishedMaterials: unfinished,
        // 键缺失 = 本周没做读后测验 → null(绝不能写成 0,那是编造)
        quizAccuracy: accuracy['reading_comprehension'],
        activeErrors: activeErrors
            .take(WeeklyReportBuilder.maxTopErrors)
            .map((r) => ErrorTagBrief(
                  tag: '${r['tag'] ?? ''}',
                  count: (r['count'] as num?)?.toInt() ?? 0,
                  lastAt: DateTime.tryParse('${r['last_at']}'),
                ))
            .toList(),
        reviewBuckets: buckets,
        forecast: _forecastFor(reviews, now),
        dailyMinutes: model.dailyMinutes?.value,
        // 输出侧(写作/翻译/回译):次数、rubric 均分与上周对比、维度均分、错误热点
        outputAttempts: outputAttempts,
        outputAvgScore: outputAvgScore,
        outputPrevAvgScore: outputPrevAvgScore,
        outputDimensions: outputDimensions,
        outputErrorTags: outputErrorTags,
      ),
    );
  }

  /// 未来 7 天负荷(逐日到期数,index 0 = 今天)。
  ///
  /// 直接喂 FsrsScheduler.loadForecast,不在周报里另写一套分桶 —— 复习页
  /// 看到的负荷和这里必须是同一个数,否则用户会怀疑哪个是真的。
  /// 本页已经读过 word_review(用于统计本周复习量),这里复用同一批行,
  /// 不再多查一次库;坏数据(解析不出 due_at 的行)直接跳过,不至于把
  /// 到期量全堆到今天。
  List<int> _forecastFor(List<Map<String, Object?>> rows, DateTime now) {
    final cards = <FsrsCard>[];
    for (final r in rows) {
      // 前面先筛 due_at:cardFromRow 对坏 due 会回退成"现在"(即今天),
      // 那会把脏数据全堆到今天,让负荷图看起来像"今天突然 300 个到期"
      if (DateTime.tryParse('${r['due_at']}') == null) continue;
      cards.add(ReviewQueue.cardFromRow(r, now: now));
    }
    return FsrsScheduler.loadForecast(cards, now: now);
  }

  static DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

  static DateTime _endOfDay(DateTime t) =>
      DateTime(t.year, t.month, t.day + 1).subtract(const Duration(milliseconds: 1));

  // ── 渲染 ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本周报告'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: '复制为文本',
            onPressed: _report == null ? null : _copyAsText,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 三态:加载中 / 失败可重试 / 内容(内容里再分空态)
    if (_loading) {
      // v2.10:整页加载态不再转圈 —— 骨架屏先铺出报告各区块的形状;
      // 内边距与下面真正的 ListView 完全一致,数据到达时布局不跳。
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 24),
        child: SkeletonLines(lines: 6, seed: 3),
      );
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    final report = _report!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _buildRange(report),
          const SizedBox(height: 12),
          if (!report.isActive) _buildEmptyHint(),
          // v2.13(图形资产系统 · 批 1):周报顶部先把"这周的数据形状"画出来,
          // 再给文字结论 —— 图看趋势、数字看事实、句子看结论。
          _Section(
            icon: Icons.bar_chart,
            title: '近 7 天收词',
            child: _buildWeekBars(report),
          ),
          _Section(
            icon: Icons.grid_on_outlined,
            title: '近 5 周打卡(35 天)',
            child: _buildHeatmap(report),
          ),
          _Section(
            icon: Icons.insights,
            title: '本周概览',
            child: _buildOverview(report),
          ),
          // v3 批 3 收尾:输出侧(写作/翻译/回译)也进周报 —— 以前只有输入,
          // 用户天天写译却在这页看不见自己的产出。
          _Section(
            icon: Icons.edit_note,
            title: '本周输出',
            child: _buildBullets(
              report.outputLines,
              fallback: '本周没有输出练习(写作 / 翻译 / 回译)',
            ),
          ),
          _Section(
            icon: Icons.emoji_events_outlined,
            title: '亮点',
            child: _buildBullets(
              report.highlights,
              fallback: '这周没有可称为亮点的事 —— 从下面的第一条建议开始',
            ),
          ),
          _Section(
            icon: Icons.tips_and_updates_outlined,
            title: '下周建议',
            child: _buildBullets(report.suggestions, fallback: '暂无建议'),
          ),
          _Section(
            icon: Icons.event_repeat,
            title: '未来 7 天负荷',
            child: _buildForecast(report),
          ),
          const SizedBox(height: 8),
          Text(
            '本周报告由本机数据算出(不联网、不调用 AI);'
            '历史周报会在后续版本以「选周期」的方式补算。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  /// 空态:本周完全没有学习记录时,在概览前给一条明确的说明
  /// (报告本身仍然渲染 —— 用户需要看到"0 是因为没做",而不是一片空白)
  Widget _buildEmptyHint() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: EmptyState(
        icon: Icons.calendar_today_outlined,
        title: '本周还没有学习记录',
        hint: '读一篇材料或复习几个词,这里就会有内容',
      ),
    );
  }

  /// 近 7 天"每日新收词"柱状图(左旧右新,末端 = 报告末日)。
  ///
  /// 为什么用"新收词"当输入量:它是 `daily_log` 里**逐日真实存在**的输入指标
  /// (阅读词数/时长在周报里只有周合计,没有逐日拆分 —— 不为了画图去猜)。
  /// 整周为 0 时不画一排 0 柱,直接给空态,避免被读成"系统评了 0 分"。
  Widget _buildWeekBars(WeeklyReport report) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    const days = 7;
    final anchor = DateTime(report.to.year, report.to.month, report.to.day);
    final series = dailySeriesOf(
      _dailyLogs,
      days: days,
      pick: (r) => r.newWordsCount,
      now: anchor,
    );
    final total = series.fold<double>(0, (sum, v) => sum + v).round();
    if (total <= 0) {
      return const ChartEmptyHint(label: '暂无数据', hint: '这 7 天没有新收词记录');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SparkBars(
          values: series,
          height: 60,
          semanticLabel: '近 7 天每日新收词,合计 $total 个',
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = days - 1; i >= 0; i--)
              Expanded(
                child: Text(
                  _mdLabel(anchor.subtract(Duration(days: i))),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '每根柱 = 当天新收词数(共 $total 个)· 左旧右新',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }

  /// 近 5 周(35 天)学习热力图。
  ///
  /// 为什么是 35 天而不是 30 天:[HeatmapCalendar] 是"周 × 7"网格,30 天没法
  /// 整除;硬凑 30 天要么补 5 个假 0(看起来像"那 5 天没学")、要么截半周
  /// (网格错位)。取 35 天 = 完整的 5 周,每个格子都是真实记录。
  Widget _buildHeatmap(WeeklyReport report) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    const weeks = 5;
    const gap = 4.0;
    final anchor = DateTime(report.to.year, report.to.month, report.to.day);
    final counts = dailySeriesOf(
      _dailyLogs,
      days: weeks * 7,
      pick: (r) => r.totalActivity,
      now: anchor,
    ).map((v) => v.round()).toList(growable: false);
    final total = counts.fold<int>(0, (sum, v) => sum + v);
    if (total <= 0) {
      return const ChartEmptyHint(label: '暂无数据', hint: '这 5 周还没有收词或练习记录');
    }
    final levels = HeatmapCalendar.tiersOf(counts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) {
            // 组件宽度 = weeks*cell + (weeks-1)*gap:用卡片宽度反推单格边长,
            // 夹在 [12,24] —— 5 周只有 5 列,太小会缩在角落、太大又像马赛克。
            final raw = (constraints.maxWidth - (weeks - 1) * gap) / weeks;
            final cell = raw.clamp(12.0, 24.0);
            return Center(
              child: HeatmapCalendar(
                levels: levels,
                weeks: weeks,
                cell: cell,
                gap: gap,
                semanticLabel: '近 5 周学习热力图:颜色越深当天新收词与练习越多',
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '颜色越深 = 当天新收词 + 练习量越多(复习结果按词存,没有逐日历史,不在此图)',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }

  /// 图上的日期短标签(如 11/3)
  String _mdLabel(DateTime d) => '${d.month}/${d.day}';

  Widget _buildRange(WeeklyReport report) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.date_range, size: 16, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${_fmtDate(report.from)} ~ ${_fmtDate(report.to)}'
            ' · 滚动 7 天含今天',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
        // 日期区间是报告的一部分:同一个页面刷新后区间会变,必须写死在页面上
        TextButton(
          onPressed: _pickPeriod,
          child: const Text('选周期'),
        ),
      ],
    );
  }

  /// 选周期:默认是"最近 7 天",也允许回看上一周。
  /// 为什么不做日历选择器:周报是**周期性复盘**的行为,给"上一周/最近 7 天"
  /// 两个档位就够,多出来的自由度只会让用户挑来挑去。
  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final choice = await showModalBottomSheet<DateTime?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('最近 7 天'),
              onTap: () => Navigator.pop(ctx, now),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('上一个 7 天'),
              onTap: () => Navigator.pop(ctx, now.subtract(const Duration(days: 7))),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    _asOf = choice;
    await _load();
  }

  Widget _buildOverview(WeeklyReport report) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // 概览用数字格子:这些是"事实",不要写成句子(句子留给亮点/建议)
    final items = <List<String>>[
      ['${report.activeDays}', '学习天数'],
      ['${report.wordsRead}', '阅读词数'],
      ['${report.minutesRead}', '阅读分钟'],
      ['${report.newWords}', '新收词'],
      ['${report.reviewsDone}', '复习词数'],
      ['${report.materialsFinished}', '读完材料'],
    ];
    if (report.quizAccuracy != null) {
      items.add(['${(report.quizAccuracy! * 100).round()}%', '读后测验正确率']);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((e) => _StatChip(value: e[0], label: e[1]))
              .toList(),
        ),
        if (report.topErrors.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '本周最该处理的错误:${report.topErrors.join('、')}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ],
    );
  }

  Widget _buildBullets(List<String> lines, {required String fallback}) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (lines.isEmpty) {
      return Text(fallback, style: theme.textTheme.bodySmall?.copyWith(color: muted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines
          .map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(s, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildForecast(WeeklyReport report) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final days = report.forecast.keys.map(int.tryParse).whereType<int>().toList()
      ..sort();
    if (days.isEmpty) {
      return Text('暂无复习排期', style: theme.textTheme.bodySmall?.copyWith(color: muted));
    }
    final maxV = days
        .map((d) => report.forecast['$d'] ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    // 周报对未来负荷只需要一个判断:有没有某天会突然堆起来
    final peakDay = days.firstWhere(
      (d) => (report.forecast['$d'] ?? 0) == maxV,
      orElse: () => days.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...days.map((d) {
          final v = report.forecast['$d'] ?? 0;
          final date = _startOfDay(report.from).add(Duration(days: d));
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  child: Text(
                    '${date.month}-${date.day}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      // maxV 为 0 时给 0:没有分母就不画进度,免得所有条都是满格
                      value: maxV == 0 ? 0 : v / maxV,
                      minHeight: 8,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 34,
                  child: Text(
                    '$v',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: v > 0 ? FontWeight.w600 : FontWeight.normal,
                      color: v > 0 ? null : muted,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        if (maxV > 0)
          Text(
            '最重的一天是 ${_startOfDay(report.from).add(Duration(days: peakDay)).month}-'
            '${_startOfDay(report.from).add(Duration(days: peakDay)).day}'
            '($maxV 个到期)',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
      ],
    );
  }

  String _fmtDate(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  /// 复制为文本:纯文本比截图更好用(可以发给老师/贴进笔记),
  /// 用系统剪贴板即可,不引入任何依赖。
  Future<void> _copyAsText() async {
    final report = _report;
    if (report == null) return;
    final buf = StringBuffer()
      ..writeln('本周报告(${_fmtDate(report.from)} ~ ${_fmtDate(report.to)})')
      ..writeln()
      ..writeln('【本周概览】')
      ..writeln('学习天数:${report.activeDays}');
    buf
      ..writeln('阅读:${report.wordsRead} 词 / ${report.minutesRead} 分钟')
      ..writeln('新收词:${report.newWords} 个;复习:${report.reviewsDone} 个词')
      ..writeln('读完材料:${report.materialsFinished} 篇');
    if (report.quizAccuracy != null) {
      buf.writeln('读后测验正确率:${(report.quizAccuracy! * 100).round()}%');
    }
    if (report.topErrors.isNotEmpty) {
      buf.writeln('最该处理的错误:${report.topErrors.join('、')}');
    }
    buf
      ..writeln()
      ..writeln('【亮点】');
    for (final h in report.highlights) {
      buf.writeln('· $h');
    }
    buf
      ..writeln()
      ..writeln('【下周建议】');
    for (final s in report.suggestions) {
      buf.writeln('· $s');
    }
    if (report.forecast.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('【未来 7 天到期】');
      final days = report.forecast.keys.map(int.tryParse).whereType<int>().toList()
        ..sort();
      for (final d in days) {
        final date = _startOfDay(report.from).add(Duration(days: d));
        buf.writeln('${_fmtDate(date)}:${report.forecast['$d']}');
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制本周报告'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// 分节卡片(报告的四块内容用同一套壳,避免每块各写一遍内边距)
class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _Section({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// 概览里的数字格子
class _StatChip extends StatelessWidget {
  final String value;
  final String label;

  const _StatChip({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
