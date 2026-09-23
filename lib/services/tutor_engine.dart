/// 导师诊断引擎(v2.0)—— **纯函数、无 IO**。
///
/// 为什么要有这一层(而不是"把数据丢给 AI 让它随便说"):
/// v1.9 之前的"AI 学习建议"形同虚设,根因是它只拿到"生词本收藏数"这一个
/// 无信息量的数字,于是只能写"保持节奏、多读多听"这类废话。
/// 2.0 的做法是:**先把数据变成可验证的结论(发现 + 依据 + 动作),再让 AI
/// 负责措辞与排序**。这样每条诊断都能在界面上指到具体数字,
/// 也保证了"无证据不下结论"这条纪律不是靠 prompt 求模型,而是靠代码。
///
/// 可测试性:输入是纯数据快照([LearnerSnapshot]),不碰 Hive/SQLite,
/// 因此"复习堆积""只输入不输出""材料偏难"这些判断都能被单测钉住。
library;

import '../models/learner_model.dart';

/// 诊断结论的严重度(决定 UI 配色与排序)
enum FindingSeverity {
  /// 该立刻做点什么(堆积、断层、严重失衡)
  action,

  /// 值得注意(偏难、偏易、某类错误反复)
  warn,

  /// 正常/鼓励,或"下一步可以更好"
  info,
}

/// 可以一键跳转的目标(UI 据此路由)
enum TutorAction {
  placementTest,
  review,
  materialCenter,
  continueReading,
  writing,
  backTranslation,
  listening,
  profile,
}

/// 一条诊断结论 —— **证据字段是强制要求**,没有证据就不要产生结论
class TutorFinding {
  /// 稳定 id(UI 与测试用;不要用文案当 id)
  final String id;
  final FindingSeverity severity;

  /// 一句话结论(用户看的标题)
  final String title;

  /// 依据:必须包含具体数字/材料名,界面直接显示
  final String evidence;

  /// 建议动作(人话,可选)
  final String? action;

  /// 可跳转目标(可选)
  final TutorAction? jump;
  final String? jumpArg;

  /// 排序权重(越大越靠前);同一严重度内按它排
  final int priority;

  const TutorFinding({
    required this.id,
    required this.severity,
    required this.title,
    required this.evidence,
    this.action,
    this.jump,
    this.jumpArg,
    this.priority = 0,
  });
}

/// 任务卡规格(由诊断推出;落库与完成回填由 UI 层负责)
class TutorTaskSpec {
  final String kind; // read/review/write/listen/placement
  final String title;
  final int targetMinutes;
  final TutorAction? jump;
  final String? jumpArg;
  final String reason; // 为什么给你派这个任务(来自哪条诊断)

  const TutorTaskSpec({
    required this.kind,
    required this.title,
    required this.targetMinutes,
    required this.reason,
    this.jump,
    this.jumpArg,
  });
}

/// 最近在读的材料(用于"偏难/偏易/继续读"的判断)
class RecentMaterial {
  final int id;
  final String title;
  final String kind;

  /// 这份材料对该用户的已知词覆盖率(0..1);未分析时为 null
  final double? coverage;
  final double percent; // 已读百分比 0..100
  const RecentMaterial({
    required this.id,
    required this.title,
    required this.kind,
    this.coverage,
    this.percent = 0,
  });
}

/// 错误标签统计(错误档案)
class ErrorTagStat {
  final String tag;
  final int count;
  final String status; // active | fixed
  const ErrorTagStat({
    required this.tag,
    required this.count,
    this.status = 'active',
  });
}

/// 导师决策所需的**全部证据**(由快照加载器从 Hive + SQLite 组装)
class LearnerSnapshot {
  final LearnerModel model;

  // 词汇
  final int totalVocab;
  final int masteryNew;
  final int masteryLearning;
  final int masteryMastered;
  final int vocabAddedLast7Days;

  // 复习(v2.0 只有状态,队列在 v2.1 生效 —— 但"有没有堆积"现在就能看)
  final int dueReviewCount;
  final int overdueCount;
  final int trackedReviewCount;

  // 输入(阅读/听力)
  final int readingSessions30d;
  final int readingWords30d;
  final int readingMinutes30d;
  final double? avgWpm;
  final int materialsStarted;
  final int materialsFinished;
  final List<RecentMaterial> recentMaterials;

  // 输出与反馈
  final Map<String, double> quizAccuracy; // kind → 正确率(0..1)
  final List<ErrorTagStat> errorTags;

  // 习惯
  final int streakDays;
  final int activeDays30d;

  /// 注入"现在",让时间相关判断可测
  final DateTime now;

  const LearnerSnapshot({
    required this.model,
    required this.now,
    this.totalVocab = 0,
    this.masteryNew = 0,
    this.masteryLearning = 0,
    this.masteryMastered = 0,
    this.vocabAddedLast7Days = 0,
    this.dueReviewCount = 0,
    this.overdueCount = 0,
    this.trackedReviewCount = 0,
    this.readingSessions30d = 0,
    this.readingWords30d = 0,
    this.readingMinutes30d = 0,
    this.avgWpm,
    this.materialsStarted = 0,
    this.materialsFinished = 0,
    this.recentMaterials = const [],
    this.quizAccuracy = const {},
    this.errorTags = const [],
    this.streakDays = 0,
    this.activeDays30d = 0,
  });
}

/// 诊断与任务规划(纯函数)
class TutorEngine {
  TutorEngine._();

  /// 每日可投入分钟数(没填就给 30)
  static const int defaultDailyMinutes = 30;

  /// 复习堆积阈值:超过就值得提醒,再多就要"先清账"
  static const int reviewWarnThreshold = 50;
  static const int reviewActionThreshold = 200;

  /// 覆盖率阈值(与 PLAN-2.0 §3.2 的 i+1 规则一致,这里只用两端)
  static const double tooHardCoverage = 0.90;
  static const double tooEasyCoverage = 0.99;

  /// 主入口:把快照变成按优先级排好的结论列表
  static List<TutorFinding> diagnose(LearnerSnapshot s) {
    final out = <TutorFinding>[];

    // ① 没有测量过的基线 —— 2.0 一切个性化的前提
    if (!_hasMeasuredBaseline(s.model)) {
      out.add(TutorFinding(
        id: 'no_baseline',
        severity: FindingSeverity.action,
        title: '先花 5 分钟测出你的词汇量基线',
        evidence: s.totalVocab > 0
            ? '你的生词本里有 ${s.totalVocab} 个词,但"收藏了多少"不等于"会多少";'
                '目前只能按最高频的 800 词保守估计难度。'
            : '还没有任何水平数据,现在给你的材料难度只能靠猜。',
        action: '做完速测后,材料难度匹配、复习配额、任务卡都会立刻变得具体。',
        jump: TutorAction.placementTest,
        priority: 100,
      ));
    }

    // ② 复习堆积(到期没清)
    if (s.dueReviewCount > 0) {
      final severe = s.overdueCount >= reviewActionThreshold;
      final warn = s.overdueCount >= reviewWarnThreshold;
      if (severe || warn) {
        out.add(TutorFinding(
          id: 'review_backlog',
          severity: severe ? FindingSeverity.action : FindingSeverity.warn,
          title: '复习堆积:${s.overdueCount} 个词已经过期',
          evidence: '到期共 ${s.dueReviewCount} 个,其中 ${s.overdueCount} 个超过计划时间;'
              '生词本共 ${s.totalVocab} 词。',
          action: severe
              ? '先清账:今天只做复习,别加新词 —— 堆积越大,每次复习的负担越重。'
              : '今天优先把到期的词过一遍(约 ${_estimateReviewMinutes(s.dueReviewCount)} 分钟)。',
          jump: TutorAction.review,
          priority: severe ? 95 : 70,
        ));
      }
    }

    // ③ 收录了却从没复习过 —— 生词本在变成"收藏夹"
    if (s.totalVocab >= 50 && s.trackedReviewCount == 0) {
      out.add(const TutorFinding(
        id: 'no_review_system',
        severity: FindingSeverity.warn,
        title: '生词本在变成"收藏夹"',
        evidence: '已收录 50+ 词,但一条复习记录都没有 —— 收藏不等于记住。',
        action: '从复习页开始,先过一遍标了"新词"的词。',
        jump: TutorAction.review,
        priority: 75,
      ));
    }

    // ④ 只输入不输出(闭环缺一半)
    if (s.readingWords30d > 0 && !_hasAnyOutput(s)) {
      out.add(TutorFinding(
        id: 'input_only',
        severity: FindingSeverity.warn,
        title: '近 30 天只有输入,没有输出',
        evidence: '读了 ${s.readingWords30d} 词 / ${s.readingMinutes30d} 分钟'
            '(${s.readingSessions30d} 次),但没有任何输出练习记录。',
        action: '输出才是检验:用今天读到的内容写 3 句话,或做一次回译。',
        jump: TutorAction.writing,
        priority: 80,
      ));
    }

    // ⑤ 材料偏难(覆盖率低于 90%)
    final hardest = _hardestRecent(s);
    if (hardest != null &&
        hardest.coverage != null &&
        hardest.coverage! < tooHardCoverage) {
      out.add(TutorFinding(
        id: 'material_too_hard',
        severity: FindingSeverity.warn,
        title: '《${hardest.title}》对你偏难',
        evidence: '已知词覆盖率只有 ${(hardest.coverage! * 100).toStringAsFixed(0)}%'
            '(舒适精读建议 95% 以上) —— 每 100 词有 '
            '${((1 - hardest.coverage!) * 100).round()} 个生词。',
        action: '换一份更简单的材料,或先预热生词再读。',
        jump: TutorAction.materialCenter,
        priority: 65,
      ));
    }

    // ⑥ 材料偏易(≥99%)
    final easiest = _easiestRecent(s);
    if (easiest != null &&
        easiest.coverage != null &&
        easiest.coverage! >= tooEasyCoverage) {
      out.add(TutorFinding(
        id: 'material_too_easy',
        severity: FindingSeverity.info,
        title: '《${easiest.title}》几乎没有生词',
        evidence: '覆盖率 ${(easiest.coverage! * 100).toStringAsFixed(1)}%'
            ' —— 泛读没问题,但对词汇增长帮助有限。',
        action: '想涨词汇的话,换一份覆盖率 95-98% 的材料。',
        jump: TutorAction.materialCenter,
        priority: 30,
      ));
    }

    // ⑦ 某类错误反复出现
    final repeating = s.errorTags
        .where((t) => t.status == 'active' && t.count >= 3)
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    if (repeating.isNotEmpty) {
      final top = repeating.take(2).map((t) => '${t.tag}(${t.count} 次)').join('、');
      out.add(TutorFinding(
        id: 'repeating_errors',
        severity: FindingSeverity.warn,
        title: '重复出错:${repeating.first.tag}',
        evidence: '错误档案里 $top 反复出现(已改好的不会计入)。',
        action: '针对这两类考点做一次定向输入 + 重写。',
        jump: TutorAction.writing,
        priority: 60,
      ));
    }

    // ⑧ 测验正确率偏低
    final readingAcc = s.quizAccuracy['reading_comprehension'];
    if (readingAcc != null && readingAcc < 0.5) {
      out.add(TutorFinding(
        id: 'low_comprehension',
        severity: FindingSeverity.warn,
        title: '读后测验正确率偏低',
        evidence: '近 30 天读后测验正确率 ${(readingAcc * 100).round()}% —— '
            '能读下去但没真正读懂,通常是材料偏难。',
        action: '把材料难度降一档,读完先用中文复述一遍再答题。',
        jump: TutorAction.materialCenter,
        priority: 55,
      ));
    }

    // ⑨ 阅读速度(有实测才判断)
    final wpm = s.avgWpm;
    if (wpm != null && wpm > 0 && wpm < 120) {
      out.add(TutorFinding(
        id: 'slow_reading',
        severity: FindingSeverity.info,
        title: '阅读速度偏慢(实测 ${wpm.round()} 词/分)',
        evidence: '一般学习者的英文默读速度在 150-250 词/分;'
            '低于 120 往往说明在逐词翻译。',
        action: '先用"不查词泛读一遍"练速度,第二遍再精读。',
        priority: 25,
      ));
    }

    // ⑩ 断层
    if (s.activeDays30d <= 2 && s.streakDays == 0) {
      out.add(TutorFinding(
        id: 'long_break',
        severity: FindingSeverity.warn,
        title: '最近几乎没有学习记录',
        evidence: '近 30 天只有 ${s.activeDays30d} 天有记录,连续天数为 ${s.streakDays}。',
        action: '别定大目标:今天只读 5 分钟或清 10 个复习词,先把节奏接回来。',
        jump: TutorAction.materialCenter,
        priority: 85,
      ));
    }

    // ⑪ 一切正常 → 给"下一步该加码"的建议(而不是空着)
    if (out.every((f) => f.severity == FindingSeverity.info)) {
      out.add(TutorFinding(
        id: 'healthy_next_step',
        severity: FindingSeverity.info,
        title: '节奏是稳的,可以加一点难度',
        evidence: '近 30 天活跃 ${s.activeDays30d} 天、读了 ${s.readingWords30d} 词、'
            '生词 ${s.totalVocab} 个(已掌握 ${s.masteryMastered})。',
        action: '把材料覆盖率目标从 98% 调到 95-96%,让每 100 词出现 4-5 个新词。',
        jump: TutorAction.materialCenter,
        priority: 10,
      ));
    }

    out.sort((a, b) {
      final bySeverity = a.severity.index.compareTo(b.severity.index);
      if (bySeverity != 0) return bySeverity;
      return b.priority.compareTo(a.priority);
    });
    return out;
  }

  /// 今日任务卡:由诊断推出,总数控制在 3-4 条、总时长贴近用户设定的每日投入
  static List<TutorTaskSpec> planTasks(
    LearnerSnapshot s, {
    List<TutorFinding>? findings,
  }) {
    final f = findings ?? diagnose(s);
    final budget =
        (s.model.dailyMinutes?.value ?? defaultDailyMinutes).clamp(5, 240);
    final tasks = <TutorTaskSpec>[];
    final ids = f.map((e) => e.id).toSet();

    // 1) 先清复习账(有堆积时永远是第一优先)
    if (s.dueReviewCount > 0) {
      final n = s.dueReviewCount > 30 ? 30 : s.dueReviewCount;
      tasks.add(TutorTaskSpec(
        kind: 'review',
        title: '复习 $n 个词(今日到期 ${s.dueReviewCount})',
        targetMinutes: _estimateReviewMinutes(n),
        reason: '来自诊断:复习堆积',
        jump: TutorAction.review,
      ));
    }

    // 2) 没基线 → 先测(这是唯一"必须先做"的任务)
    if (ids.contains('no_baseline')) {
      tasks.add(const TutorTaskSpec(
        kind: 'placement',
        title: '做一次词汇量速测(约 5 分钟)',
        targetMinutes: 5,
        reason: '来自诊断:还没有测量过的基线',
        jump: TutorAction.placementTest,
      ));
    }

    // 3) 继续没读完的材料(比"再找新材料"更容易启动)
    final unfinished =
        s.recentMaterials.where((m) => m.percent > 0 && m.percent < 99.5).toList();
    if (unfinished.isNotEmpty) {
      final m = unfinished.first;
      final minutes = (budget * 0.5).round().clamp(5, 40);
      tasks.add(TutorTaskSpec(
        kind: 'read',
        title: '继续读《${m.title}》(已读 ${m.percent.round()}%)',
        targetMinutes: minutes,
        reason: '来自诊断:把在读的材料读完',
        jump: TutorAction.continueReading,
        jumpArg: '${m.id}',
      ));
    } else {
      tasks.add(TutorTaskSpec(
        kind: 'read',
        title: '从材料中心挑一份 95-98% 覆盖率的材料精读',
        targetMinutes: (budget * 0.5).round().clamp(5, 40),
        reason: '来自诊断:保持输入(i+1)',
        jump: TutorAction.materialCenter,
      ));
    }

    // 4) 输出任务:30 天没输出 → 必排;否则新词多时排一条写作
    if (!_hasAnyOutput(s) || ids.contains('input_only')) {
      tasks.add(TutorTaskSpec(
        kind: 'write',
        title: '用今天的新词写 3 句话(或做一次回译)',
        targetMinutes: (budget * 0.25).round().clamp(5, 20),
        reason: '来自诊断:只有输入没有输出',
        jump: TutorAction.writing,
      ));
    } else if (s.masteryNew >= 10) {
      tasks.add(const TutorTaskSpec(
        kind: 'write',
        title: '把 10 个新词各写一个句子',
        targetMinutes: 10,
        reason: '未掌握的词偏多:写作是最快的固化方式',
        jump: TutorAction.writing,
      ));
    }

    // 只保留前 4 条:**按插入顺序(=优先级)截断**,不要按时长排序 ——
    // 排序会让"先清复习账"这种最重要的任务被一条长阅读任务挤到后面
    if (tasks.length > 4) {
      tasks.removeRange(4, tasks.length);
    }
    return tasks;
  }

  /// 顶部一句话总结(给导师页头部)
  static String summaryLine(LearnerSnapshot s) {
    final parts = <String>[];
    final v = s.model.vocabEstimate;
    if (v != null && v.value > 0) {
      parts.add('词汇量约 ${v.value} 词');
    } else {
      parts.add('还没有测过词汇量');
    }
    if (s.totalVocab > 0) {
      parts.add('生词本 ${s.totalVocab}(已掌握 ${s.masteryMastered})');
    }
    if (s.dueReviewCount > 0) parts.add('待复习 ${s.dueReviewCount}');
    if (s.readingMinutes30d > 0) parts.add('近 30 天阅读 ${s.readingMinutes30d} 分钟');
    if (s.activeDays30d > 0) parts.add('活跃 ${s.activeDays30d} 天');
    return parts.join(' · ');
  }

  /// 给 AI 的**结构化证据包**(不是原文,只是数字与结论)——
  /// 导师会话把它塞进 system prompt,保证模型有据可依。
  static String evidencePrompt(LearnerSnapshot s, List<TutorFinding> findings) {
    final b = StringBuffer();
    b.writeln('【学习者数据快照】');
    b.writeln(learnerContextLine(s));
    b.writeln('生词:共 ${s.totalVocab} 词(新词 ${s.masteryNew} / 学习中 '
        '${s.masteryLearning} / 已掌握 ${s.masteryMastered}),近 7 天新增 '
        '${s.vocabAddedLast7Days}');
    b.writeln('复习:到期 ${s.dueReviewCount}(过期 ${s.overdueCount}),'
        '已有复习状态 ${s.trackedReviewCount} 词');
    b.writeln('输入:近 30 天 ${s.readingSessions30d} 次 / ${s.readingWords30d} 词 / '
        '${s.readingMinutes30d} 分钟'
        '${s.avgWpm != null ? ',均速 ${s.avgWpm!.round()} 词/分' : ''}');
    b.writeln('材料:在学 ${s.materialsStarted} 份,读完 ${s.materialsFinished} 份');
    for (final m in s.recentMaterials.take(3)) {
      b.writeln('  · 《${m.title}》${m.kind} 覆盖率 '
          '${m.coverage == null ? '未分析' : '${(m.coverage! * 100).toStringAsFixed(0)}%'}'
          ' 已读 ${m.percent.round()}%');
    }
    if (s.quizAccuracy.isNotEmpty) {
      final acc = s.quizAccuracy.entries
          .map((e) => '${e.key} ${(e.value * 100).round()}%')
          .join('、');
      b.writeln('测验正确率:$acc');
    }
    if (s.errorTags.isNotEmpty) {
      final tags = s.errorTags
          .where((t) => t.status == 'active')
          .take(5)
          .map((t) => '${t.tag}×${t.count}')
          .join('、');
      if (tags.isNotEmpty) b.writeln('错误热点:$tags');
    }
    b.writeln('习惯:连续 ${s.streakDays} 天,近 30 天活跃 ${s.activeDays30d} 天,'
        '每日可投入 ${s.model.dailyMinutes?.value ?? defaultDailyMinutes} 分钟');
    b.writeln();
    b.writeln('【本地诊断引擎已得出的结论(必须优先遵守,不要编造新结论)】');
    for (final f in findings) {
      b.writeln('- [${f.severity.name}] ${f.title} —— 依据:${f.evidence}');
    }
    return b.toString();
  }

  /// 画像一行(与 LearnerModel.summaryText 互补:这里只放导师必需的)
  static String learnerContextLine(LearnerSnapshot s) {
    final m = s.model;
    final parts = <String>[];
    if ((m.cefr?.value ?? '').isNotEmpty) parts.add('水平 ${m.cefr!.value}');
    if ((m.goal?.value ?? '').isNotEmpty) parts.add('目的 ${m.goal!.value}');
    if ((m.interests?.value ?? const []).isNotEmpty) {
      parts.add('偏好 ${m.interests!.value.join('、')}');
    }
    if (m.blockedTopics.isNotEmpty) parts.add('屏蔽 ${m.blockedTopics.join('、')}');
    return parts.isEmpty ? '画像:未填写' : '画像:${parts.join(';')}';
  }

  // ── 内部工具 ──

  static bool _hasMeasuredBaseline(LearnerModel m) {
    final f = m.vocabEstimate;
    return f != null && f.value > 0 && f.source == ProfileSource.test;
  }

  static bool _hasAnyOutput(LearnerSnapshot s) =>
      s.quizAccuracy.keys.any((k) => k != 'vocab_placement');

  static RecentMaterial? _hardestRecent(LearnerSnapshot s) {
    final withCoverage =
        s.recentMaterials.where((m) => m.coverage != null).toList();
    if (withCoverage.isEmpty) return null;
    withCoverage.sort((a, b) => a.coverage!.compareTo(b.coverage!));
    return withCoverage.first;
  }

  static RecentMaterial? _easiestRecent(LearnerSnapshot s) {
    final withCoverage =
        s.recentMaterials.where((m) => m.coverage != null).toList();
    if (withCoverage.isEmpty) return null;
    withCoverage.sort((a, b) => b.coverage!.compareTo(a.coverage!));
    return withCoverage.first;
  }

  /// 复习时长估算:约 6 秒/词(认词卡片实测量级),至少 1 分钟
  static int _estimateReviewMinutes(int count) {
    final m = (count * 6 / 60).ceil();
    return m < 1 ? 1 : m;
  }
}
