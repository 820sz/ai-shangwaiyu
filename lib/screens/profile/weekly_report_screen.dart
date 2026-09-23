import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/database.dart';
import '../../services/fsrs.dart';
import '../../services/learner_model_store.dart';
import '../../services/review_queue.dart';
import '../../services/weekly_report.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';

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
      final report = await _buildReport(_asOf ?? DateTime.now());
      if (!mounted) return;
      setState(() {
        _report = report;
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
    if (_loading) return const Center(child: CircularProgressIndicator());
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
          _Section(
            icon: Icons.insights,
            title: '本周概览',
            child: _buildOverview(report),
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
