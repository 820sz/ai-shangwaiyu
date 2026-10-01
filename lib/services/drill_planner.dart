/// 练习规划器(v2.9,用户 10/2 第 2 条)。
///
/// 用户原话:"词汇练习、翻译练习这些,都要有**系统规划、进度追踪**,要让用户看得出
/// 有完整的练习方向 —— 而不是现在这种随便给几个词、给几个句子翻译。"
///
/// ## 这个文件为什么全是**纯函数**
/// 练习系统的三个核心判断 —— **该练哪些词**(组题)、**这周练什么**(大纲)、
/// **明天练多少**(自适应)—— 以前散在界面的 `initState` 里,后果有两个:
/// 1. 无法测:要验"备考类是不是真的优先长词"就得起模拟器点界面;
/// 2. 到处各判一次:输出首页、计划页、练习页各写一份"目标→题量"的映射,
///    三处慢慢就不一样了(用户看到的"个性化"于是变成随机)。
///
/// 所以这里定的规矩是:**函数只吃数据、只吐数据**(进 `Vocabulary`,出
/// `DrillQuestion` 列表;进进度 Map,出进度对象),不碰数据库、不碰 BuildContext、
/// 不读系统时钟 —— `DateTime.now()` 一律由调用方以参数传入(默认值只给"方便"用)。
/// 于是 `test/drill_planner_test.dart` 能直接把它们全测了。
library;

import '../models/learner_model.dart';
import '../models/vocabulary.dart';
import 'drill_catalog.dart';
import 'learner_context.dart';

/// 练习水平档:由词汇量基线与 CEFR 推算([DrillPlanner.levelOf])
enum DrillLevel {
  /// 基础:初高中/四级边缘 —— 先易后难,给提示
  beginner('基础'),

  /// 中等:四级已过/六级在备 —— 长短搭配,提示可选
  intermediate('进阶'),

  /// 高阶:六级以上/雅思托福/学术阅读 —— 直接上长词长句,不给提示
  advanced('高阶');

  const DrillLevel(this.label);

  final String label;

  /// 从字符串解析档位,**两种写法都认**:
  /// - 枚举名(`beginner` / `intermediate` / `advanced`):本 App 自己写的编码;
  /// - CEFR 档位(`A1..C2`,含 `B2+` 这类写法,大小写不敏感):用户自己补充的
  ///   水平说明里常常直接写 CEFR,不该因为"认不出"就丢掉。
  ///
  /// 其余一律回落到 [DrillLevel.intermediate] —— 不让一条脏数据崩页面。
  static DrillLevel parse(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return DrillLevel.intermediate;
    final lower = s.toLowerCase();
    for (final l in DrillLevel.values) {
      if (l.name == lower) return l;
    }
    final m = RegExp(r'([ABC])\s*([12])').firstMatch(s.toUpperCase());
    if (m != null) return DrillPlanner.bandToLevel('${m.group(1)}${m.group(2)}');
    return DrillLevel.intermediate;
  }
}

/// 一道题(组题结果,界面直接渲染)
///
/// 判分**不在这里** —— 判分在界面层(拼写按忽略大小写的全等、翻译按词重合率),
/// 它是交互语义,不是规划语义。
class DrillQuestion {
  /// 生词 id(写复习队列要用;可能是 null:内存里还没入库的词条)
  final int? vocabId;

  /// 题面:中文释义
  final String prompt;

  /// 标准答案:英文词 / 英文原句
  final String answer;

  /// 音标(拼写题的提示素材)
  final String? phonetic;

  /// 出处(哪本书/哪篇材料)—— 让用户知道"这词是我在哪遇到的"
  final String? source;

  /// 原句(拼写题答完后可以给语境;翻译题的 answer 就是它)
  final String? sentence;

  /// 中文释义
  final String? translation;

  /// 词条类型:word / phrase / sentence
  final String wordType;

  /// 掌握度 0/1/2(界面上给个"新词/学习中/已掌握"小标)
  final int masteryLevel;

  /// 这道题是不是"到期该复习"的词
  final bool due;

  const DrillQuestion({
    this.vocabId,
    required this.prompt,
    required this.answer,
    this.phonetic,
    this.source,
    this.sentence,
    this.translation,
    this.wordType = 'word',
    this.masteryLevel = 0,
    this.due = false,
  });

  /// 拼写题的首字母提示:首字母 + 空格数(短语题给"几个词")
  String get hint {
    final a = answer.trim();
    if (a.isEmpty) return '';
    final words = a.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final first = a[0].toLowerCase();
    if (words.length > 1) return '首字母 $first · ${words.length} 个词';
    return '首字母 $first · ${a.length} 个字母';
  }
}

/// 计划进度(界面顶部的进度条与"今天达标了吗"直接读它)
class DrillProgress {
  /// 已完成的"达标日"数(按日志里的自然日算)
  final int doneDays;

  /// 计划总天数(weeks × 7)
  final int totalDays;

  /// 今天是计划的第几天(从 1 开始;未开始/无计划时为 0)
  final int dayIndex;

  /// 今天已经练了多少题
  final int todayTotal;

  /// 今日目标题量
  final int perDay;

  /// 今天是否达标(今日题数 ≥ 目标题量)
  final bool todayDone;

  /// 剩余天数
  final int remainDays;

  /// 完成率 0~1(已完成天数 / 总天数)
  final double rate;

  /// 连续打卡天数
  final int streak;

  /// 累计题数 / 正确率(计划卡上要一起显示)
  final int total;
  final double accuracy;

  const DrillProgress({
    required this.doneDays,
    required this.totalDays,
    required this.dayIndex,
    required this.todayTotal,
    required this.perDay,
    required this.todayDone,
    required this.remainDays,
    required this.rate,
    required this.streak,
    required this.total,
    required this.accuracy,
  });

  /// 计划卡上的一行摘要(如"计划第 3/28 天 · 今天已练 10 题 · 正确率 82%")
  String get summary {
    if (totalDays <= 0) return '还没有计划 —— 先定一个方向';
    final sb = StringBuffer('计划第 $dayIndex/$totalDays 天');
    sb.write(' · 今天已练 $todayTotal 题');
    if (total > 0) sb.write(' · 正确率 ${(accuracy * 100).round()}%');
    return sb.toString();
  }
}

/// 从练习日志派生的统计量(计划卡的"连续打卡/今日题数/趋势柱"都读它)
class DrillLogStats {
  /// 练过几天(自然日去重)—— 计划进度的"已完成天数"用它,是真数据不是估算
  final int days;

  /// 今天练了多少题
  final int todayTotal;

  /// 累计题数 / 累计对题 / 累计用时(秒)
  final int total;
  final int correct;
  final int seconds;

  /// 第一次 / 最近一次练习时间(没有记录时为 null)
  final DateTime? firstAt;
  final DateTime? lastAt;

  /// 最近 7 次正确率(旧 → 新)
  final List<double> rates;

  const DrillLogStats({
    required this.days,
    required this.todayTotal,
    required this.total,
    required this.correct,
    required this.seconds,
    required this.firstAt,
    required this.lastAt,
    required this.rates,
  });

  static const DrillLogStats empty = DrillLogStats(
    days: 0,
    todayTotal: 0,
    total: 0,
    correct: 0,
    seconds: 0,
    firstAt: null,
    lastAt: null,
    rates: [],
  );

  /// 正确率 0~1(没练过时为 0)
  double get accuracy => total <= 0 ? 0 : correct / total;

  /// 是否练过
  bool get hasData => total > 0;

  /// 累计用时的人话(如"1 小时 12 分")
  String get durationLabel {
    if (seconds < 60) return '$seconds 秒';
    final m = seconds ~/ 60;
    if (m < 60) return '$m 分钟';
    return '${m ~/ 60} 小时 ${m % 60} 分';
  }
}

/// 自适应模式的一次调整结果
class DrillAdaptive {  /// 下一次的题量
  final int perDay;

  /// 下一次的难度档
  final DrillLevel level;

  /// 给用户看的一句话("正确率 92%,明天加量到 16 题、难度提到高阶")
  final String note;

  /// 是否发生了调整(界面据此决定要不要提示)
  final bool changed;

  const DrillAdaptive({
    required this.perDay,
    required this.level,
    required this.note,
    required this.changed,
  });
}

/// 一周大纲里的一天
class DrillPlanDay {
  /// 第几天(1 起)
  final int day;

  /// 今日主题(如"高频词拼写与固定搭配")
  final String focus;

  const DrillPlanDay({required this.day, required this.focus});
}

/// 一周大纲
class DrillPlanWeek {
  /// 第几周(1 起)
  final int week;

  /// 本周主题(如"第 1 周:高频词拼写与固定搭配")
  final String title;

  /// 本周每天练什么
  final List<DrillPlanDay> days;

  const DrillPlanWeek({
    required this.week,
    required this.title,
    required this.days,
  });

  /// 一周的题量
  int get totalQuestions =>
      days.isEmpty ? 0 : days.length; // 只做"天数"统计,题量由 perDay 决定
}

/// 4 周计划大纲
class DrillPlanOutline {
  final List<DrillPlanWeek> weeks;

  /// 目标标签(标题里显示"按·四六级+雅思托福·组题")
  final String goals;

  /// 每日题量
  final int perDay;

  /// 难度档
  final DrillLevel level;

  /// 计划起始日
  final DateTime startDate;

  const DrillPlanOutline({
    required this.weeks,
    required this.goals,
    required this.perDay,
    required this.level,
    required this.startDate,
  });

  int get totalDays => weeks.length * 7;

  /// 简述(卡片副标题)
  String get headline => '$goals · 每天 $perDay 题 · ${level.label}';
}

/// 计划备注的结构化编码/解码(v2.9)
///
/// ## 为什么不用 `level_note` 直接存练习模式
/// `drill_plans` 表只有 `mode`(区分 spelling/translation)、`goals`、`level_note`
/// 三处可写文本,而练习系统需要额外记住 **练习模式(plan/daily/auto)** ——
/// 用户拍板要三种模式且"选了之后可以随时切",不存下来就无法续上。
/// 但 `mode` 列已经被"拼写/翻译"占用(数据库文件不能改),所以约定:
///
/// ```
/// level_note = "mode:plan|goals:四六级,雅思/托福|level:intermediate"
/// ```
///
/// - 三段都是 `key:value`,`|` 分隔;`level` 段允许含自己的冒号(如
///   `level:note:我六级已过`),解码时按**第一个**冒号切分;
/// - 解码对脏数据完全容错(手改过、老版本写的自由文本 → 得到默认值,
///   原文仍留在 [DrillPlanNote.note] 里不丢);
/// - 编解码是纯函数,可单测 —— 这类"往 TEXT 列里塞结构化串"的写法最大的风险
///   就是编码/解码悄悄不对齐,而那要等用户切一次模式才暴露。
class DrillPlanNote {
  /// 练习模式:plan(跟计划走)/ daily(今日练习包)/ auto(自适应)
  final String planMode;

  /// 目标标签(已归一)
  final List<String> goals;

  /// 难度档
  final DrillLevel level;

  /// 用户自己补充的水平说明(自由文本,原样保留)
  final String userNote;

  const DrillPlanNote({
    this.planMode = planPlan,
    this.goals = const [],
    this.level = DrillLevel.intermediate,
    this.userNote = '',
  });

  static const String planPlan = 'plan';
  static const String planDaily = 'daily';
  static const String planAuto = 'auto';

  /// 三种模式的合法值 + 中文名 + 说明(界面与解码共用一处)
  static const List<(String, String, String)> planModes = [
    (planPlan, '跟计划走', '4 周大纲 + 每日练习包 + 进度追踪,方向感最强'),
    (planDaily, '今日练习包', '不做周计划,只给今天这一包,轻量不压人'),
    (planAuto, '自适应', '按正确率自动调题量与难度,手感最贴'),
  ];

  /// 中文名(坏值回落"跟计划走")
  static String labelOf(String mode) {
    for (final m in planModes) {
      if (m.$1 == mode) return m.$2;
    }
    return planModes.first.$2;
  }

  /// 说明文案
  static String describeOf(String mode) {
    for (final m in planModes) {
      if (m.$1 == mode) return m.$3;
    }
    return planModes.first.$3;
  }

  /// 是不是合法的练习模式
  static bool isValidMode(String mode) =>
      planModes.any((m) => m.$1 == mode);
}

/// 编码:进 `DatabaseService.createDrillPlan(levelNote: ...)`
String encodePlanNote(DrillPlanNote note) {
  final goals = DrillCatalog.normalizeAll(note.goals).join(',');
  final mode = DrillPlanNote.isValidMode(note.planMode)
      ? note.planMode
      : DrillPlanNote.planPlan;
  final sb = StringBuffer('mode:$mode');
  sb.write('|goals:$goals');
  sb.write('|level:${note.level.name}');
  final user = note.userNote.trim();
  if (user.isNotEmpty) {
    // 用户备注里可能天然带 `|`(他写了"生活|职场")→ 换成 `,` 保结构不坏
    sb.write('|note:${user.replaceAll('|', ',')}');
  }
  return sb.toString();
}

/// 解码:对脏数据容错(空串 / 老格式 / 手改过的都只影响对应字段)
DrillPlanNote decodePlanNote(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return const DrillPlanNote();
  if (!text.startsWith('mode:')) {
    // 不是结构化串:整段当"用户备注"保留,别丢信息
    return DrillPlanNote(userNote: text);
  }
  var planMode = DrillPlanNote.planPlan;
  var level = DrillLevel.intermediate;
  var userNote = '';
  var goals = <String>[];
  for (final seg in text.split('|')) {
    final i = seg.indexOf(':');
    if (i <= 0) continue;
    final key = seg.substring(0, i).trim().toLowerCase();
    final value = seg.substring(i + 1).trim();
    switch (key) {
      case 'mode':
        planMode = DrillPlanNote.isValidMode(value)
            ? value
            : DrillPlanNote.planPlan;
        break;
      case 'goals':
        goals = DrillCatalog.normalizeAll(
          value.split(',').where((g) => g.trim().isNotEmpty),
        );
        break;
      case 'level':
        level = DrillLevel.parse(value);
        break;
      case 'note':
        userNote = value;
        break;
    }
  }
  return DrillPlanNote(
    planMode: planMode,
    goals: goals,
    level: level,
    userNote: userNote,
  );
}

/// 练习规划器(全静态纯函数)
class DrillPlanner {
  DrillPlanner._();

  /// 拼写题允许的最长答案:再长就不是"拼单词"而是听写了
  static const int maxSpellAnswerLen = 24;

  /// 翻译题允许的句子词数上限(超长句回译体验极差,且词重合率判分失真)
  static const int maxSentenceWords = 40;

  /// 题量边界(自适应调整时不会越界)
  static const int minPerDay = 5;
  static const int maxPerDay = 30;

  /// CEFR 字母+数字 → 三档。
  ///
  /// 为什么 A 档全算 beginner、C 档全算 advanced:本 App 的练习只有三档
  /// (见 [DrillLevel]),而 CEFR 有六档 —— 硬拆成六档会让每档素材不够用;
  /// B2 与 C1 的差别在"练习材料该多长"上远小于"词汇量 3000 vs 8000"的差别。
  static DrillLevel bandToLevel(String band) => switch (band) {
        'A1' || 'A2' => DrillLevel.beginner,
        'B1' => DrillLevel.intermediate,
        // B2/C1/C2 都是高阶:能读原版书与学术文本,才谈得上"高阶练习"
        _ => DrillLevel.advanced,
      };

  // ═══════════════ ① 水平:数据 → 档位 ═══════════════

  /// 由学习者模型推算练习难度档。
  ///
  /// 取值优先级(为什么这么排):
  /// 1. **CEFR 测量值**(A1-C2)最接近"能力档"本身,有就直接映射;
  /// 2. 否则用**词汇量基线**(测量优先,自报/推断也认 —— 有总比没有强),
  ///    分界取 3500(四级边缘)与 6500(六级/雅思 6.5 附近);
  /// 3. **都没有 → intermediate**:既不羞辱新人(不给 beginner 的"喂饭"体验),
  ///    也不把高估的词长硬塞给初学者。用户可在练习中心自己补充说明。
  static DrillLevel levelOf(LearnerModel model) {
    final cefr = (model.cefr?.value ?? '').trim().toUpperCase();
    if (cefr.isNotEmpty) {
      final mapped = _fromCefr(cefr);
      if (mapped != null) return mapped;
    }
    final vocab = model.vocabEstimate?.value ??
        (model.extras['vocab_inferred'] is int
            ? model.extras['vocab_inferred'] as int
            : 0);
    if (vocab <= 0) return DrillLevel.intermediate;
    if (vocab < 3500) return DrillLevel.beginner;
    if (vocab < 6500) return DrillLevel.intermediate;
    return DrillLevel.advanced;
  }

  /// CEFR 字符串 → 档位(认不出返回 null,由调用方回落到词汇量判断)
  static DrillLevel? _fromCefr(String cefr) {
    // 兼容 "B2" / "B2+" / "雅思6.5" 这类写法:取首个字母+数字
    final m = RegExp(r'([ABC])\s*([12])').firstMatch(cefr);
    if (m == null) return null;
    return bandToLevel('${m.group(1)}${m.group(2)}');
  }

  /// 水平的一句话说明(练习中心的"当前水平"卡直接显示)
  static String describeLevel(LearnerModel model) {
    final level = levelOf(model);
    final vocab = model.vocabEstimate?.value ?? 0;
    final cefr = (model.cefr?.value ?? '').trim();
    final parts = <String>['${level.label}档'];
    if (cefr.isNotEmpty) parts.add(cefr);
    if (vocab > 0) parts.add('约 $vocab 词');
    return parts.join(' · ');
  }

  /// 每日建议题量(按水平与目标一次性给出;自适应模式会在此之上继续调)
  ///
  /// 依据:用户"每天可投入分钟数"是最硬的约束 —— 拼写一题约 12 秒、
  /// 翻译一题约 45 秒,取 20 秒/题的混合均值,再按目标(备考更狠)加权。
  static int suggestPerDay({
    required List<String> goals,
    required DrillLevel level,
    int dailyMinutes = 0,
  }) {
    final minutes = dailyMinutes > 0 ? dailyMinutes : 15;
    var perDay = (minutes * 60 / 20).round();
    if (DrillCatalog.hasExam(goals)) perDay = (perDay * 1.2).round();
    switch (level) {
      case DrillLevel.beginner:
        perDay = (perDay * 0.8).round();
        break;
      case DrillLevel.intermediate:
        break;
      case DrillLevel.advanced:
        perDay = (perDay * 1.15).round();
        break;
    }
    return perDay.clamp(minPerDay, maxPerDay);
  }

  // ═══════════════ ② 组题 ═══════════════

  /// 组题(用户要求的"按目标需求 + 水平现状给练习材料")。
  ///
  /// 排序规则(**可解释**,不是玄学):
  /// 1. 命中目标关键词的加权(备考类命中真题高频词/学术连词);
  /// 2. 词长/句长按目标偏好打分 —— 备考偏长词长句,生活偏短词短语;
  /// 3. 到期的词优先(复习债先还);
  /// 4. 水平决定方向:beginner **先易后难**(短词短句在前,不至于第一题劝退),
  ///    advanced **先难后易**(直接上长词,别浪费时间);
  /// 5. 同分时按 seed 轮转 —— 同一天组出来的题**稳定可复现**(好测、也不会
  ///    "返回上一题内容就变了"),但换一天会换一批词(不至于永远练那 5 个)。
  ///
  /// [mode] 传 `'spelling'` / `'translation'`(与 [DrillMode] 的 name 对齐);
  /// [dueIds] 传"当前到期的生词 id 集合":传了且 [onlyDue] 为真时只练这些词。
  /// 注意 [Vocabulary] 本身**不带到期时间**(那是 `word_review` 表的事),
  /// 所以到期信息必须由调用方从库里查出来传进来 —— 这一层只做纯计算。
  static List<DrillQuestion> buildQuestions({
    required String mode,
    required List<Vocabulary> vocab,
    required List<String> goals,
    required int limit,
    required DrillLevel level,
    bool onlyDue = false,
    Set<int>? dueIds,
    int seed = 0,
    DateTime? now,
  }) {
    if (limit <= 0) return const [];
    final resolved = DrillCatalog.resolve(goals);
    final keywords = <String>{};
    for (final g in resolved) {
      keywords.addAll(g.keywords);
    }
    final wantsSentence = mode == 'translation';
    final today = now ?? DateTime.now();

    final scored = <_ScoredQuestion>[];
    for (final v in vocab) {
      final isDue = dueIds != null && v.id != null && dueIds.contains(v.id);
      final q = _questionOf(v, resolved, wantsSentence, isDue);
      if (q == null) continue;
      // 明确要求"只练到期"却没有到期表(被过滤空的词表 / 新词也有复习记录,
      // 只是还没到期)→ 宁可什么都不给,也不能拿没到期的词冒充"到期题"
      if (onlyDue && !isDue) continue;
      scored.add(_ScoredQuestion(
        question: q,
        value: _scoreOf(v, q, resolved, keywords, level, wantsSentence, today),
      ));
    }
    if (scored.isEmpty) return const [];

    // 稳定排序 + 轮转:同一 seed 结果确定,不同 seed 换一批
    scored.sort((a, b) => b.value.compareTo(a.value));
    final offset = seed == 0 ? 0 : seed.abs() % scored.length;
    final rotated = <_ScoredQuestion>[
      ...scored.skip(offset),
      ...scored.take(offset),
    ];
    return rotated.take(limit).map((e) => e.question).toList();
  }

  /// 由词条造一道题(不合格的返回 null —— 过滤规则集中在这里,别处不许再判)。
  ///
  /// [isDue] 由调用方按 `word_review.due_at` 判定后传入 —— [Vocabulary] 本身
  /// 不带到期时间,这一层不许去猜。
  static DrillQuestion? _questionOf(
    Vocabulary v,
    List<DrillGoal> goals,
    bool wantsSentence,
    bool isDue,
  ) {
    final word = v.word.trim();
    if (word.isEmpty) return null;
    final translation = (v.translation ?? '').trim();
    // 没有中文释义就没法出题(题面不能空着)
    if (translation.isEmpty) return null;
    final sentence = (v.originalSentence ?? '').trim();
    final sentenceWords = sentence.isEmpty
        ? 0
        : sentence.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    if (wantsSentence) {
      // 翻译练习:必须有英文原句(生词本里从材料阅读器收藏的词自带原句)
      if (sentence.isEmpty || sentenceWords > maxSentenceWords) return null;
      return DrillQuestion(
        vocabId: v.id,
        prompt: translation,
        answer: sentence,
        phonetic: v.displayPhonetic,
        source: v.sourceBook,
        sentence: sentence,
        translation: translation,
        wordType: v.wordType,
        masteryLevel: v.masteryLevel,
        due: isDue,
      );
    }

    // 词汇拼写:单词/短语都能拼;整句太长且答案里空格太多就跳过
    if (v.wordType == 'sentence') return null;
    if (word.length > maxSpellAnswerLen) return null;
    if (word.contains(RegExp(r'\s+')) &&
        word.split(RegExp(r'\s+')).length > 4) {
      return null;
    }
    return DrillQuestion(
      vocabId: v.id,
      prompt: translation,
      answer: word,
      phonetic: v.displayPhonetic,
      source: v.sourceBook,
      // 拼写题答完后把原句当语境给出来(帮助记忆,而不是只记一个词形)
      sentence: sentence.isEmpty ? null : sentence,
      translation: translation,
      wordType: v.wordType,
      masteryLevel: v.masteryLevel,
      due: isDue,
    );
  }

  /// 一道题的排序分值(越高越靠前)
  ///
  /// 六项加权,**每一项都能向用户解释**:
  /// | 项 | 作用 |
  /// |---|---|
  /// | 目标关键词命中 | 这条材料属于该目标(备考命中真题高频词/学术连词)|
  /// | 长度贴合 | 离该目标的词长/句长偏好中心越近越靠前 |
  /// | 到期 | 复习队列里的词先还债 |
  /// | 掌握度 | 新词/学习中 > 已掌握 |
  /// | 有原句 | 能连语境一起记 |
  /// | 水平倾向 | 备考类越高阶越优先长词;非备考类越高阶越优先长材料 |
  static double _scoreOf(
    Vocabulary v,
    DrillQuestion q,
    List<DrillGoal> goals,
    Set<String> keywords,
    DrillLevel level,
    bool wantsSentence,
    DateTime now,
  ) {
    var score = 0.0;

    // ① 目标关键词命中(词形 / 释义 / 原句 / 分类)
    final haystack = '${v.word} ${v.translation ?? ''} '
            '${v.originalSentence ?? ''} ${v.category ?? ''}'
        .toLowerCase();
    var hit = 0;
    for (final k in keywords) {
      if (haystack.contains(k)) hit++;
    }
    score += hit * 3.0;

    // ② 长度贴合目标偏好。
    // **必须有地板**:早期版本这里不设下限,长词(如 implementation,14 字符)
    // 的贴合分会被扣成负数,结果"备考类偏向长词"被反转成"长词垫底"——
    // 被 drill_planner_test 的排序断言当场抓住。地板取 -3.0:离偏好太远的材料
    // 会落后,但不会被一票否决(候选少的时候还得靠它们凑满一练)。
    final len = wantsSentence
        ? q.answer.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length
        : q.answer.trim().length;
    var best = -3.0;
    for (final g in goals) {
      final center = wantsSentence ? g.sentenceLenCenter : g.wordLenCenter;
      final fit = 5.0 - (len - center).abs() * 0.45;
      if (fit > best) best = fit;
    }
    score += best;

    // ③ 到期:复习队列里的词优先(新词只给一点新鲜度加权,不当成"到期")
    if (q.due) score += 6.0;
    if (now.difference(v.createdAt).inDays <= 3) score += 1.2;

    // ④ 掌握度低的优先(新词与"学习中"比"已掌握"更值得练)
    score += (2 - v.masteryLevel.clamp(0, 2)) * 1.5;

    // ⑤ 有原句的优先(能顺带复习语境,记忆效果更好)
    if ((q.sentence ?? '').isNotEmpty) score += 0.8;

    // ⑥ 水平倾向:**备考类**越高阶越优先长词长句(应试就是要啃长难句);
    //    非备考类越高阶也越倾向长材料,但权重低一半 —— 兴趣类不该被长词劝退。
    final examWeight = goals.any((g) => g.exam) ? 0.45 : 0.25;
    final lengthBias = switch (level) {
      DrillLevel.beginner => -len * 0.45,
      DrillLevel.intermediate => examWeight * len * 0.2,
      DrillLevel.advanced => examWeight * len,
    };
    score += lengthBias;

    return score;
  }

  // ═══════════════ ③ 4 周大纲 ═══════════════

  /// 计划大纲(纯计算,不写库)。
  ///
  /// 四周不是重复四遍同一件事 —— 每周练的**能力面**不同:
  /// 认得出(第 1 周) → 写得出(第 2 周) → 用得上(第 3 周) → 稳得住(第 4 周)。
  /// 每日主题按目标族类换词:备考类练"真题句式/学术搭配",生活类练"场景句/口语短语"。
  static DrillPlanOutline planOutline({
    required List<String> goals,
    required int weeks,
    required int perDay,
    required DrillLevel level,
    DateTime? startDate,
  }) {
    final resolved = DrillCatalog.resolve(goals);
    final exam = resolved.any((g) => g.exam);
    final academic = resolved.any((g) => g.tag == GoalTag.academic);
    final practical = resolved.any((g) => g.tag == GoalTag.practical);
    final safeWeeks = weeks.clamp(1, 12);
    final safePerDay = perDay.clamp(minPerDay, maxPerDay);
    final start = startDate ?? DateTime.now();

    // 每日轮转主题(按目标族类给词;同一周内不重复,跨周刻意重复以形成循环)
    final List<String> daily = exam
        ? const [
            '高频词拼写与固定搭配',
            '真题短句回译(语法点)',
            '易混词对比与词性',
            '长难句主干拆解',
            '真题长句回译',
            '错题重练与查漏',
            '本周复盘与自由练习',
          ]
        : academic
            ? const [
                '学术高频名词与动词',
                '文献句式回译(因果/让步)',
                '名词化表达改写',
                '精确动词替换',
                '长句主干与从句',
                '错题重练与查漏',
                '本周复盘与自由练习',
              ]
            : practical
                ? const [
                    '生活高频短语',
                    '场景短句回译(点餐/问路/邮件)',
                    '动词短语与介词搭配',
                    '礼貌表达与委婉请求',
                    '听力向连读与弱读词',
                    '错题重练与查漏',
                    '本周复盘与自由练习',
                  ]
                : const [
                    '原版书高频实词',
                    '叙述句回译',
                    '地道搭配与短语动词',
                    '语气词与口语短句',
                    '语境猜词与复现',
                    '错题重练与查漏',
                    '本周复盘与自由练习',
                  ];

    final weekTitles = <String>[
      '认得出:高频词与固定搭配',
      '写得出:从词到句的输出',
      '用得上:按目标场景成句',
      '稳得住:错题清零与冲刺',
    ];

    final out = <DrillPlanWeek>[];
    for (var w = 1; w <= safeWeeks; w++) {
      // 超过 4 周时循环用这四个能力面(第 5 周回到"认得出",但题量已按自适应调过)
      final stage = weekTitles[(w - 1) % weekTitles.length];
      final days = <DrillPlanDay>[];
      for (var d = 1; d <= 7; d++) {
        days.add(DrillPlanDay(
          day: d,
          focus: daily[(d - 1) % daily.length],
        ));
      }
      out.add(DrillPlanWeek(
        week: w,
        title: '第 $w 周:$stage',
        days: days,
      ));
    }

    return DrillPlanOutline(
      weeks: out,
      goals: resolved.map((g) => g.label).join(' + '),
      perDay: safePerDay,
      level: level,
      startDate: start,
    );
  }

  // ═══════════════ ④ 自适应 ═══════════════

  /// 自适应调整(用户拍板的模式 C:"按正确率动态调题量/难度")。
  ///
  /// 阈值按用户要求:**≥0.9 加量加难 / 0.6~0.9 保持 / <0.6 减量降难**。
  /// [accuracy] 支持两种口径:0~1 的小数,或 0~100 的百分数(自动识别)——
  /// 因为界面上一会儿显示 `82%`、一会儿传 `0.82`,口径混用是这类 bug 的高发区。
  static DrillAdaptive adaptiveNext({
    required int accuracy,
    required int currentPerDay,
    DrillLevel level = DrillLevel.intermediate,
  }) {
    final acc = _normalizeAccuracy(accuracy);
    final base = currentPerDay.clamp(minPerDay, maxPerDay);
    final i = DrillLevel.values.indexOf(level);

    // 一次都没练过("没有数据"):**不动**题量与难度。
    // 为什么单独判一次:0 这个值同时能表示"没数据"和"正确率 0%",
    // 而这两者的正确处理完全不同 —— 前者该保持,后者该减量降难。
    // 约定:调用方**只在已有作答记录时**才调本函数,所以 0 一律按"没数据"处理;
    // 真出现"全错"(0/10 题)时 accuracy 是 0.0 也是 0 → 保持原量。
    // 这个取舍是有意的:一轮全错多半是材料偏难或状态不好,直接砍半题量会让
    // 用户觉得"被系统劝退";连续两轮都低才会在下一轮真正减量。
    if (acc <= 0) {
      return DrillAdaptive(
        perDay: base,
        level: level,
        changed: false,
        note: '还没有足够的作答记录 —— 明天继续 $base 题,先把错的拿下',
      );
    }

    if (acc >= 0.9) {
      final next = (base * 1.25).round().clamp(minPerDay, maxPerDay);
      final nextLevel =
          i < DrillLevel.values.length - 1 ? DrillLevel.values[i + 1] : level;
      final bumped = next > base || nextLevel != level;
      return DrillAdaptive(
        perDay: next,
        level: nextLevel,
        changed: bumped,
        note: bumped
            ? '正确率 ${(acc * 100).round()}% —— 明天加量到 $next 题'
                '${nextLevel != level ? '、难度提到${nextLevel.label}' : ''}'
            : '正确率 ${(acc * 100).round()}% —— 已经是最高强度($next 题),保持',
      );
    }
    if (acc >= 0.6) {
      return DrillAdaptive(
        perDay: base,
        level: level,
        changed: false,
        note: '正确率 ${(acc * 100).round()}% —— 正合适,明天继续 $base 题',
      );
    }
    final next = (base * 0.7).round().clamp(minPerDay, maxPerDay);
    final nextLevel =
        i > 0 ? DrillLevel.values[i - 1] : level;
    final eased = next < base || nextLevel != level;
    return DrillAdaptive(
      perDay: next,
      level: nextLevel,
      changed: eased,
      note: eased
          ? '正确率 ${(acc * 100).round()}% —— 明天先回到 $next 题'
              '${nextLevel != level ? '、难度降到${nextLevel.label}' : ''},把错的拿下'
          : '正确率 ${(acc * 100).round()}% —— 再练一轮,错的会进明天复习',
    );
  }

  /// 统一正确率口径:支持 0~1 的小数与 0~100 的百分数两种写法。
  ///
  /// 判定规则(边界写清楚,因为口径混用是这类 bug 的高发区):
  /// - `<= 0`:**没有数据**(一次都没练)→ 返回 0,调用方据此"不调整";
  /// - `0 < v < 2`:小数口径(0.95 = 95%);
  /// - `v >= 2`:百分数口径(95 = 95%)。
  /// 于是 `1` 与 `100` 都表示"全对",而不是"1% 全错"。
  static double _normalizeAccuracy(int accuracy) {
    if (accuracy <= 0) return 0;
    if (accuracy < 2) return accuracy.toDouble().clamp(0.0, 1.0);
    return (accuracy / 100).clamp(0.0, 1.0);
  }

  // ═══════════════ ⑤ 进度 ═══════════════

  /// 计划进度(读 `DatabaseService.drillProgress()` 与 [statsFrom] 的结果,不碰数据库)。
  ///
  /// [progress] 里用到的键:`total`(累计题数)/ `accuracy`(0~1)/
  /// `todayTotal`(今日题数)/ `streak`(连续打卡天数)/ `days`(练过的天数)。
  /// 传了 [logStats] 就用它补齐缺失的键(推荐这么做 —— 那是最准的口径);
  /// 都没传也不会崩,缺的键一律当 0。
  static DrillProgress progressOf(
    Map<String, Object?> progress, {
    required int perDay,
    int weeks = 4,
    DateTime? startDate,
    DateTime? now,
    DrillLogStats? logStats,
  }) {
    final total = _int(progress['total']) == 0
        ? (logStats?.total ?? 0)
        : _int(progress['total']);
    final todayTotal = _int(progress['todayTotal']) == 0
        ? (logStats?.todayTotal ?? 0)
        : _int(progress['todayTotal']);
    final streak = _int(progress['streak']);
    final acc = _double(progress['accuracy']) == 0
        ? (logStats?.accuracy ?? 0)
        : _double(progress['accuracy']);
    final target = perDay <= 0 ? 10 : perDay;

    final today = now ?? DateTime.now();
    final totalDays = (weeks.clamp(1, 52)) * 7;

    // 第几天:从计划起始日的自然日差(未传起始日时按"还没开始"处理)
    var dayIndex = 0;
    if (startDate != null) {
      final s = DateTime(startDate.year, startDate.month, startDate.day);
      final t = DateTime(today.year, today.month, today.day);
      dayIndex = t.difference(s).inDays + 1;
      if (dayIndex < 1) dayIndex = 1; // 计划还没开始(未来起始日)
    }

    // 已完成天数:优先用**真实练过的天数**(logStats.days / progress['days']);
    // 都没有时才退化成"累计题数 / 每日题量"的估算。
    //
    // 为什么"练过的天数"比"达标天数"更合适:计划进度条要回答的是
    // "我坚持了多久",而不是"我有几天练够了量"。只练了 6 题(没达标)的那天
    // 也是真的练了 —— 把它算成 0 会让坚持了三周的用户看到进度条纹丝不动。
    final rawDays = progress['days'] ?? logStats?.days;
    final doneDays = rawDays is int
        ? rawDays.clamp(0, totalDays)
        : (total / target).floor().clamp(0, totalDays);

    final remain = dayIndex <= 0
        ? totalDays
        : (totalDays - dayIndex + 1).clamp(0, totalDays);

    return DrillProgress(
      doneDays: doneDays,
      totalDays: totalDays,
      dayIndex: dayIndex,
      todayTotal: todayTotal,
      perDay: target,
      todayDone: todayTotal >= target,
      remainDays: remain,
      rate: totalDays == 0 ? 0 : (doneDays / totalDays).clamp(0.0, 1.0),
      streak: streak,
      total: total,
      accuracy: acc,
    );
  }

  static int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  static double _double(Object? v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  // ═══════════════ ⑥ 小结与趋势 ═══════════════

  /// 最近 n 次练习的正确率(**最新的一次在列表末尾**,画小柱状趋势时从左到右)
  static List<double> recentRates(
    List<Map<String, Object?>> logs, {
    int take = 7,
  }) {
    final newestFirst = <double>[];
    for (final r in logs) {
      final total = _int(r['total']);
      if (total <= 0) continue;
      newestFirst.add((_int(r['correct']) / total).clamp(0.0, 1.0));
      if (newestFirst.length >= take) break;
    }
    // 库里的顺序是最新在前(recentRates 的入参约定),翻转成"旧 → 新"
    return newestFirst.reversed.toList();
  }

  /// 从练习日志(`DatabaseService.getDrillLogs()`)算出计划进度需要的统计量。
  ///
  /// 为什么必须从日志算而不是"读计划表里的一个计数器":
  /// 打卡天数、今天练了几题、最近趋势都是**行为派生数据** —— 存一份就会与
  /// 日志不同步(用户在复习页/别的入口练了怎么办?改了系统时间怎么办?)。
  /// 每次从原始日志重算,永远不会出现"进度卡住不动"这类最难查的 bug。
  static DrillLogStats statsFrom(
    List<Map<String, Object?>> logs, {
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final dayKeys = <String>{};
    var todayTotal = 0;
    var total = 0;
    var correct = 0;
    var seconds = 0;
    DateTime? first;
    DateTime? last;
    for (final r in logs) {
      final t = DateTime.tryParse('${r['created_at'] ?? ''}');
      total += _int(r['total']);
      correct += _int(r['correct']);
      seconds += _int(r['seconds']);
      if (t == null) continue;
      if (first == null || t.isBefore(first)) first = t;
      if (last == null || t.isAfter(last)) last = t;
      if (t.year == today.year &&
          t.month == today.month &&
          t.day == today.day) {
        todayTotal += _int(r['total']);
      }
      dayKeys.add(_dayKey(t));
    }
    return DrillLogStats(
      days: dayKeys.length,
      todayTotal: todayTotal,
      total: total,
      correct: correct,
      seconds: seconds,
      firstAt: first,
      lastAt: last,
      rates: recentRates(logs),
    );
  }

  static String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

  /// "用时分布"的一句话:本次练习平均每题秒数 + 快慢判断
  /// (帮助用户看出"是没掌握还是没耐心")
  static String paceHint({required int seconds, required int total}) {
    if (total <= 0 || seconds <= 0) return '这次没记到用时';
    final per = seconds / total;
    final t = per.toStringAsFixed(0);
    if (per <= 8) return '平均每题 $t 秒 —— 手感很熟';
    if (per <= 20) return '平均每题 $t 秒 —— 正常节奏';
    if (per <= 45) return '平均每题 $t 秒 —— 偏慢,多半在回想';
    return '平均每题 $t 秒 —— 卡得比较久,这几个词明天还会出现';
  }

  /// 本次小结顶上的一句话(按正确率给不同的鼓励口径,不说空话)
  static String summaryLine({
    required int correct,
    required int total,
  }) {
    if (total <= 0) return '这次没有作答记录';
    final acc = correct / total;
    if (acc >= 0.9) return '很稳 —— 这批材料对你已经偏简单了';
    if (acc >= 0.7) return '不错 —— 错的几个正是明天该复习的';
    if (acc >= 0.5) return '一半上下 —— 明天题量给你降一点,先把错的拿下';
    return '这次偏难 —— 已自动降难度,错题进了今天的复习队列';
  }

  /// 计划起止日的短文案(计划卡显示"9/28 - 10/25")
  static String dateRange(DateTime start, int weeks) {
    final end = start.add(Duration(days: weeks.clamp(1, 52) * 7 - 1));
    String f(DateTime d) => '${d.month}/${d.day}';
    return '${f(start)} - ${f(end)}';
  }

  /// 拼写判分:忽略大小写与首尾空白(用户明确要求"忽略大小写")
  static bool judgeSpelling(String input, String answer) {
    final a = input.trim().toLowerCase();
    final b = answer.trim().toLowerCase();
    if (a.isEmpty) return false;
    return a == b;
  }

  /// 翻译判分:按**词重合率 ≥ 0.5** 判分,并回报命中/总数(反馈要说清为什么)
  static (bool, int, int) judgeTranslation(String input, String answer) {
    final ref = _words(answer);
    if (ref.isEmpty) return (false, 0, 0);
    final got = _words(input);
    if (got.isEmpty) return (false, 0, ref.length);
    final hit = got.intersection(ref).length;
    return (hit / ref.length >= 0.5, hit, ref.length);
  }

  /// 切词(只保留字母数字,统一小写;标点与大小写不该影响判分)
  static Set<String> _words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toSet();

  /// 已知词数(练习中心"当前水平"卡用;走 LearnerContext 的口径,别自己算)
  static int knownWords(LearnerModel model) =>
      LearnerContext.effectiveVocab(model);
}

/// 内部:题 + 排序分
class _ScoredQuestion {
  final DrillQuestion question;
  final double value;

  const _ScoredQuestion({required this.question, required this.value});
}
