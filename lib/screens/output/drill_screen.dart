import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/database.dart';
import '../../services/drill_catalog.dart';
import '../../services/drill_planner.dart';
import '../../services/learner_model_store.dart';
import '../../services/tts_service.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/waiting.dart';

/// 练习模式(v2.8 起;v2.9 重做)
enum DrillMode {
  /// 词汇拼写:给中文释义 + 音标,拼出英文单词
  spelling('词汇拼写', Icons.spellcheck, '看中文释义拼英文,错了立刻纠正'),

  /// 翻译练习:给中文句子,写出英文原句(回译)
  translation('翻译练习', Icons.translate, '看中文写英文,系统按词重合率判分');

  const DrillMode(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;

  /// 入库用的 mode 字符串(`drill_plans.mode` / `drill_logs.mode`)
  String get key => name;

  /// 从库里的字符串反解(坏值回落到拼写)
  static DrillMode of(String? raw) {
    for (final m in DrillMode.values) {
      if (m.name == raw) return m;
    }
    return DrillMode.spelling;
  }

  /// 题目提示语
  String get promptHint =>
      this == DrillMode.spelling ? '拼出这个意思的英文' : '把这句话写成英文';

  /// 作答框提示
  String get inputHint =>
      this == DrillMode.spelling ? '输入英文单词' : '写出英文句子(按词重合判分)';

  /// 没有素材时的空态说明(要告诉用户"去哪儿攒素材",而不是只说"没有")
  String get emptyHint => this == DrillMode.spelling
      ? '先去「输入」拍照或读材料收几个词,再回来拼写'
      : '翻译练习要词条带英文原句 —— 从材料阅读器点词收藏的词会自动带原句';
}

/// 一次练习会话(组题结果 + 计划上下文)
///
/// 为什么要先"准备"再"进页面":组题要读生词本与复习队列(异步),
/// 而用户看到的应该是一段**真实步骤**的说明(按目标筛选 → 到期优先 → 组题),
/// 而不是一个转圈。准备完把结果整个交给 [DrillScreen],页面直接开练。
class DrillSession {
  final DrillMode mode;
  final List<DrillQuestion> questions;
  final List<String> goals;

  /// 当前进行中的计划 id(练习记录要挂在它下面;没有计划时为 null)
  final int? planId;

  /// 练习模式:plan / daily / auto(见 [DrillPlanNote])
  final String planMode;

  final DrillLevel level;

  /// 本次题量上限(自适应模式下会按最近正确率调整)
  final int perDay;

  /// 是否只练到期复习的词
  final bool onlyDue;

  /// 至多能组出多少题(候选池大小,用于"素材不够"时的提示)
  final int poolSize;

  /// 复习队列里有多少词到期
  final int dueCount;

  const DrillSession({
    required this.mode,
    required this.questions,
    required this.goals,
    required this.planId,
    required this.planMode,
    required this.level,
    required this.perDay,
    required this.onlyDue,
    required this.poolSize,
    required this.dueCount,
  });

  /// 题量是否被候选池卡住(界面据此提示"素材只够 X 题")
  bool get poolLimited => poolSize > 0 && poolSize < perDay;
}

/// 组题的**真实步骤**时间线(每个真实动作一步,不编造进度)。
///
/// 顺序就是代码真实执行的顺序:
/// 1. 读生词本(`VocabProvider.vocabularies`);
/// 2. 读复习状态表 `word_review`(异步查库);
/// 3. 筛出"到期"的词;
/// 4. 按目标 × 水平组题([DrillPlanner.buildQuestions]);
/// 5. 出结果(候选池大小、题量、复习队列里到期的词数)。
///
/// [onTick] 每一步都会被调用一次,让调用方把 [steps] 画成 [AiWaitingTimeline]。
///
/// 硬规则(v2.9):**每一步都真的发生过** —— 没有假进度,也不为"动画好看"
/// 硬等多余时间;每步那 600ms 只是为了让用户看清"读了多少词"。
Future<DrillSession> prepareDrillSession({
  required DrillMode mode,
  required List<String> goals,
  required DrillLevel level,
  required int limit,
  String planMode = DrillPlanNote.planPlan,
  bool onlyDue = false,
  int? planId,
  required void Function(List<AiStep> steps) onTick,
  required VocabProvider vocabProvider,
}) async {
  final steps = <AiStep>[];
  void tick() => onTick(List<AiStep>.unmodifiable(steps));

  void addStep(String label, {String? detail}) {
    steps.add(AiStep(
      label: label,
      state: AiStepState.running,
      detail: detail,
    ));
    tick();
  }

  void doneStep({String? detail}) {
    if (steps.isEmpty) return;
    final last = steps.removeLast();
    steps.add(AiStep(
      label: last.label,
      state: AiStepState.done,
      detail: detail ?? last.detail,
    ));
    tick();
  }

  /// 每步至少显示 600ms(与 waiting.dart 的约定一致:再快也要让人看清)
  Future<void> breathe() => Future<void>.delayed(
        const Duration(milliseconds: 620),
      );

  // ── 1. 生词本 ──
  addStep('读取生词本');
  await breathe();
  if (vocabProvider.vocabularies.isEmpty) {
    await vocabProvider.loadVocabularies();
  }
  final vocab = vocabProvider.vocabularies;
  doneStep(detail: '${vocab.length} 个词条');

  // ── 2. 复习队列 ──
  addStep('查看今天的复习队列');
  await breathe();
  var reviews = <Map<String, Object?>>[];
  try {
    reviews = await DatabaseService.getWordReviews();
  } catch (_) {
    reviews = const [];
  }
  final now = DateTime.now();
  final dueIds = <int>{};
  final newIds = <int>{};
  for (final r in reviews) {
    final id = r['vocab_id'];
    if (id is! int) continue;
    final due = DateTime.tryParse('${r['due_at'] ?? ''}');
    if (due != null && !due.isAfter(now)) dueIds.add(id);
    final last = DateTime.tryParse('${r['last_review_at'] ?? ''}');
    if (last == null || now.difference(last).inDays <= 3) newIds.add(id);
  }
  doneStep(detail: '${reviews.length} 条复习状态');

  // ── 3. 筛到期 ──
  addStep('到期与新词优先');
  await breathe();
  final effectiveOnlyDue = onlyDue && dueIds.isNotEmpty;
  doneStep(
    detail: effectiveOnlyDue
        ? '只练到期的 ${dueIds.length} 个'
        : '到期 ${dueIds.length} 个 · 近 3 天新收 ${newIds.length} 个',
  );

  // ── 4. 组题 ──
  // 题量:只练到期词时就是"有多少到期词"(这才是"只练到期"的意思),
  // 否则按目标 + 水平 + 每日可投入时间给建议值(limit > 0 时以调用方为准)
  final perDay = effectiveOnlyDue
      ? (limit <= 0 ? dueIds.length : limit)
      : (limit > 0
          ? limit
          : DrillPlanner.suggestPerDay(goals: goals, level: level));
  addStep('按目标与水平组题');
  await breathe();
  final pool = DrillPlanner.buildQuestions(
    mode: mode.key,
    vocab: vocab,
    goals: goals,
    limit: 9999,
    level: level,
    now: now,
    dueIds: dueIds,
  );
  final questions = DrillPlanner.buildQuestions(
    mode: mode.key,
    vocab: vocab,
    goals: goals,
    limit: perDay,
    level: level,
    onlyDue: effectiveOnlyDue,
    dueIds: dueIds,
    seed: _seedFor(now, perDay),
    now: now,
  );
  doneStep(detail: DrillCatalog.describe(goals));

  // ── 5. 出结果 ──
  addStep('组好 ${questions.length} 题');
  tick();
  await breathe();
  doneStep(detail: pool.length < perDay ? '素材只够 ${pool.length} 题' : null);

  return DrillSession(
    mode: mode,
    questions: questions,
    goals: DrillCatalog.normalizeAll(goals),
    planId: planId,
    planMode: planMode,
    level: level,
    perDay: perDay,
    onlyDue: effectiveOnlyDue,
    poolSize: pool.length,
    dueCount: dueIds.length,
  );
}

/// 同一天组出来的题稳定、换一天换一批
int _seedFor(DateTime now, int perDay) =>
    now.year * 10000 + now.month * 100 + now.day + perDay;

/// 拼写 / 翻译练习(v2.9 重做)。
///
/// ## 这一版和 v2.8 的区别(用户 10/2:"现在这些东西完全只能说'看上去有用'")
/// | 维度 | v2.8 | 现在 |
/// |---|---|---|
/// | 组题 | 按长度排序取前 N 个 | 目标关键词 + 词长/句长偏好 + 到期 + 掌握度 + 水平方向,六项加权 |
/// | 反馈 | "对了 / 再看一眼正确答案" | 说清**为什么**(拼写逐字对照;翻译给"词重合 6/9") |
/// | 进度 | AppBar 里一行 "3/10" | ProgressStageBar(第几题/共几题 + 已用时 + 可退出) |
/// | 结束 | 弹个对话框就退页 | **完整小结卡**:正确率/用时分布/错题清单/只练错题/明天继续 |
/// | 落库 | 只写错题复习 | 写 drill_logs(带 planId 与 goals)+ 错题回今天的复习队列 |
class DrillScreen extends StatefulWidget {
  final DrillMode mode;

  /// 已经组好的题(从练习中心带过来,省掉重复组题)
  final DrillSession? session;

  const DrillScreen({super.key, required this.mode, this.session});

  @override
  State<DrillScreen> createState() => _DrillScreenState();
}

/// 一题的作答结果(小结卡要用)
class _Verdict {
  final bool correct;

  /// 为什么对/为什么错(给用户看的一句话)
  final String why;

  /// 翻译题的词重合统计(拼写题为 null)
  final (int, int)? overlap;

  /// 拼写题的逐字对照(每个字符 + 是否对)
  final List<(String, bool)>? charDiff;

  const _Verdict({
    required this.correct,
    required this.why,
    this.overlap,
    this.charDiff,
  });
}

class _DrillScreenState extends State<DrillScreen> {
  final _inputCtrl = TextEditingController();
  final _focus = FocusNode();

  DrillSession? _session;
  List<DrillQuestion> _questions = const [];
  int _index = 0;

  /// 组题阶段(只在本页自己组题时发生)
  bool _preparing = false;
  List<AiStep> _steps = const [];

  bool _answered = false;
  bool _showHint = false;
  _Verdict? _verdict;

  /// 本轮(可能是一轮"只练错题")与整场的计数分开记:
  /// 整场计数进 drill_logs(重练也算同一场练习),本轮计数只用于题内显示
  int _grandTotal = 0;
  int _grandCorrect = 0;

  /// 错题:用 vocabId 去重(同一个词错两次只算一道)
  final Map<int, DrillQuestion> _wrong = {};

  bool _finished = false;
  DateTime _startedAt = DateTime.now();
  int _elapsedSeconds = 0;
  LearnerModel _model = LearnerModel();
  List<String> _goals = const [];

  /// 小结卡上的自适应建议(自适应模式才有)
  DrillAdaptive? _adaptive;

  /// 这一轮有多少错题成功排进了复习队列(小结卡上如实说明)
  int _queuedCount = 0;

  bool _logged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _model = LearnerModelStore.load();
      _goals = _model.goals.isEmpty
          ? [if ((_model.goal?.value ?? '').isNotEmpty) _model.goal!.value]
          : _model.goals;
      _startedAt = DateTime.now();
      final given = widget.session;
      if (given != null) {
        _adopt(given);
        return;
      }
      await _prepare();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _adopt(DrillSession s) {
    setState(() {
      _session = s;
      _questions = s.questions;
      _index = 0;
      _grandTotal = 0;
      _grandCorrect = 0;
      _wrong.clear();
      _finished = false;
      _answered = false;
      _verdict = null;
      _startedAt = DateTime.now();
    });
    if (_questions.isNotEmpty) _focus.requestFocus();
  }

  /// 自己组题(从"练一练"直接进来时走这条路)
  Future<void> _prepare() async {
    setState(() {
      _preparing = true;
      _steps = const [AiStep(label: '正在按你的目标与水平组题')];
    });
    try {
      final session = await prepareDrillSession(
        mode: widget.mode,
        goals: _goals,
        level: DrillPlanner.levelOf(_model),
        limit: 0,
        planMode: DrillPlanNote.planPlan,
        vocabProvider: context.read<VocabProvider>(),
        onTick: (steps) {
          if (mounted) setState(() => _steps = steps);
        },
      );
      if (!mounted) return;
      setState(() => _preparing = false);
      _adopt(session);
    } catch (e) {
      debugPrint('ReadFlow 组题失败: $e');
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _questions = const [];
      });
    }
  }

  // ═══════════════ 作答与判分 ═══════════════

  /// 逐字对照(拼写反馈"为什么错"):只标出**第一个不同的位置**之前/之后,
  /// 不做完整 diff —— 用户要的是"我少写了一个 t",不是一份算法报告
  List<(String, bool)> _charDiff(String input, String answer) {
    final a = input.trim().toLowerCase();
    final b = answer.trim().toLowerCase();
    final out = <(String, bool)>[];
    final maxLen = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < maxLen; i++) {
      if (i < b.length) {
        final ok = i < a.length && a[i] == b[i];
        out.add((b[i], ok));
      } else {
        out.add(('_', false)); // 输入多出来的部分
      }
    }
    return out;
  }

  void _submit() {
    if (_questions.isEmpty || _answered) return;
    final q = _questions[_index];
    final input = _inputCtrl.text;
    if (input.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('先写点什么再提交 —— 想不起来可以点「给点提示」或「看答案」'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _record(q, _judge(q, input));
  }

  /// 看答案 = 记一次错(它就是"我没写出来")
  void _reveal() {
    if (_questions.isEmpty || _answered) return;
    final q = _questions[_index];
    _record(
      q,
      _Verdict(
        correct: false,
        why: widget.mode == DrillMode.spelling
            ? '这次没拼出来 —— 它已经放回今天的复习队列'
            : '这次没写出来 —— 它已经放回今天的复习队列',
      ),
    );
  }

  _Verdict _judge(DrillQuestion q, String input) {
    if (widget.mode == DrillMode.spelling) {
      final ok = DrillPlanner.judgeSpelling(input, q.answer);
      if (ok) {
        return const _Verdict(correct: true, why: '拼写正确');
      }
      final diff = _charDiff(input, q.answer);
      final wrongCount = diff.where((d) => !d.$2).length;
      return _Verdict(
        correct: false,
        why: wrongCount == 1
            ? '差一个字母 —— 对照下面标红的位置'
            : '有 $wrongCount 处对不上 —— 对照下面标红的位置',
        charDiff: diff,
      );
    }
    final (ok, hit, ref) = DrillPlanner.judgeTranslation(input, q.answer);
    final why = ref == 0
        ? '这条参考答案是空的(词条没带原句),先跳过'
        : ok
            ? '词重合 $hit/$ref —— 达到一半,判对'
            : '词重合 $hit/$ref —— 不到一半,再看看标准答案的用词';
    return _Verdict(correct: ok, why: why, overlap: (hit, ref));
  }

  void _record(DrillQuestion q, _Verdict verdict) {
    setState(() {
      _verdict = verdict;
      _answered = true;
      _grandTotal++;
      if (verdict.correct) {
        _grandCorrect++;
      } else {
        // 去重靠 vocabId;没入库的词条(内存里才有)用答案文本当 key 的哈希
        // —— 这里直接跳过:没有 id 就没法排复习,记在题目列表里也没意义
        final id = q.vocabId;
        if (id != null) _wrong[id] = q;
      }
    });
  }

  void _next() {
    if (_index + 1 >= _questions.length) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _inputCtrl.clear();
      _answered = false;
      _verdict = null;
      _showHint = false;
    });
    _focus.requestFocus();
  }

  // ═══════════════ 结束:落库 + 小结 ═══════════════

  Future<void> _finish() async {
    final seconds = DateTime.now().difference(_startedAt).inSeconds;
    final session = _session;
    final wrongList = _wrong.values.toList();

    // ① 错题**立刻**回今天的复习队列(dueAt = 现在):练习的意义就是让它今天再出现一次,
    //    否则这一轮只是"看过答案"而已
    var queued = 0;
    for (final q in wrongList) {
      final id = q.vocabId;
      if (id == null) continue;
      try {
        await DatabaseService.upsertWordReview(
          id,
          stability: 0,
          difficulty: 6,
          dueAt: DateTime.now(),
          lastReviewAt: DateTime.now(),
        );
        queued++;
      } catch (e) {
        debugPrint('ReadFlow 错题入复习队列失败: $e');
      }
    }

    // ② 写练习记录(带 planId 与 goals —— 进度追踪与趋势图都靠它)
    if (!_logged && _grandTotal > 0) {
      _logged = true;
      try {
        await DatabaseService.logDrill(
          mode: widget.mode.key,
          total: _grandTotal,
          correct: _grandCorrect,
          seconds: seconds,
          planId: session?.planId,
          goals: session?.goals ?? _goals,
          wrong: wrongList.map((q) => q.answer).toList(),
        );
      } catch (e) {
        debugPrint('ReadFlow 写练习记录失败: $e');
      }
    }

    // ③ 自适应:算下一次的题量与难度(session 里没有就按当前建议值起算)
    DrillAdaptive? adaptive;
    if ((session?.planMode ?? '') == DrillPlanNote.planAuto && _grandTotal > 0) {
      adaptive = DrillPlanner.adaptiveNext(
        accuracy: (_grandCorrect / _grandTotal * 100).round(),
        currentPerDay: session?.perDay ?? 10,
        level: session?.level ?? DrillLevel.intermediate,
      );
    }

    if (!mounted) return;
    setState(() {
      _elapsedSeconds = seconds;
      _adaptive = adaptive;
      _finished = true;
      _queuedCount = queued;
    });
  }

  /// 只练错题:把错题当成新的题单再来一轮。
  ///
  /// 这一轮**也要单独写一条记录**(新练习 = 新一轮)。为什么不合并成一条:
  /// "只练错题"是用户主动开始的一次新练习 —— 合并会让趋势柱少一根,
  /// 打卡与正确率的口径也变得不可解释(一条记录横跨两轮)。
  /// 所以先把第一轮的账落了,再开始重练。
  Future<void> _retryWrong() async {
    final list = _wrong.values.toList();
    if (list.isEmpty) return;
    final session = _session;
    final seconds = DateTime.now().difference(_startedAt).inSeconds;
    if (!_logged && _grandTotal > 0) {
      _logged = true;
      try {
        await DatabaseService.logDrill(
          mode: widget.mode.key,
          total: _grandTotal,
          correct: _grandCorrect,
          seconds: seconds,
          planId: session?.planId,
          goals: session?.goals ?? _goals,
          wrong: list.map((q) => q.answer).toList(),
        );
      } catch (e) {
        debugPrint('ReadFlow 写练习记录失败: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _questions = list;
      _index = 0;
      _wrong.clear();
      _finished = false;
      _answered = false;
      _verdict = null;
      _inputCtrl.clear();
      _startedAt = DateTime.now();
      // 新一轮从头计数:这条记录只反映"重练这一轮"的成绩
      _grandTotal = 0;
      _grandCorrect = 0;
      _elapsedSeconds = 0;
      _queuedCount = 0;
      _adaptive = null;
      _logged = false;
    });
    _focus.requestFocus();
  }

  // ═══════════════ 界面 ═══════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 练完(或还没作答)直接退;练到一半要先确认 —— 半途退出这一轮不记进度,
      // 用户有权在不知情的情况下不被吞掉一次练习
      canPop: _finished || _grandTotal == 0,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('先练完这一轮?'),
            content: Text(
              '已经答了 $_grandTotal 题(对 $_grandCorrect 题)。'
              '现在退出,这一轮不会记进进度。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('继续练'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('退出'),
              ),
            ],
          ),
        );
        // 用**进入异步前捕获**的 navigator,不在 await 之后碰 context
        // (use_build_context_synchronously 抓的就是这个)
        if (leave == true) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.mode.label),
          actions: [
            if (!_finished && _questions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: Gap.md),
                child: Center(
                  child: Text(
                    '${_index + 1}/${_questions.length}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_preparing) {
      return ListView(
        padding: Insets.page,
        children: [
          AppCard(
            child: AiWaitingTimeline(steps: _steps, running: true),
          ),
        ],
      );
    }
    if (_questions.isEmpty) {
      return Center(
        child: AppEmpty(
          icon: Icons.inbox_outlined,
          title: '还没有可练的内容',
          hint: widget.mode.emptyHint,
        ),
      );
    }
    if (_finished) return _buildSummary();
    return _buildQuestion();
  }

  /// 练习中的进度条:第几题 / 共几题(不是转圈)
  Widget _progressBar() {
    final answered = _index;
    return ProgressStageBar(
      stage: '第 ${_index + 1} / ${_questions.length} 题',
      value: _questions.isEmpty ? 0 : answered / _questions.length,
      detail: _grandTotal > 0
          ? '已答 $_grandTotal 题 · 对 $_grandCorrect 题'
          : '作答后立刻给出为什么对/为什么错',
      startedAt: _startedAt,
      onCancel: () => _confirmQuit(),
    );
  }

  Future<void> _confirmQuit() async {
    if (_grandTotal == 0) {
      Navigator.pop(context);
      return;
    }
    final navigator = Navigator.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('这一轮还没结束'),
        content: Text('已答 $_grandTotal 题。退出后这一轮不记进进度,要现在退吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续练'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (leave == true) navigator.pop();
  }

  Widget _buildQuestion() {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final q = _questions[_index];
    final isSpelling = widget.mode == DrillMode.spelling;
    return ListView(
      padding: Insets.page,
      children: [
        // ① 进度(真实百分比,可退出)
        AppStagger(
          index: 0,
          child: AppCard(child: _progressBar()),
        ),

        // ② 这份练习是按什么挑的(让用户看得出"有方向")
        if (_session != null)
          AppStagger(
            index: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, Gap.xs),
              child: Text(
                '按「${_session!.goals.isEmpty ? DrillCatalog.describe(_goals) : _session!.goals.join(' + ')}」'
                '· ${_session!.level.label}'
                '${_session!.onlyDue ? ' · 只练到期词' : ''}组题',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: muted, fontSize: 11.5, height: 1.4),
              ),
            ),
          ),

        // ③ 题面
        AppStagger(
          index: 2,
          child: AppCard(
            padding: const EdgeInsets.all(Gap.md + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _chip(
                      theme,
                      isSpelling ? '拼写' : '翻译',
                      isSpelling ? Icons.spellcheck : Icons.translate,
                    ),
                    const SizedBox(width: Gap.xxs),
                    _chip(theme, q.masteryLevel == 0
                        ? '新词'
                        : (q.masteryLevel == 1 ? '学习中' : '已掌握'),
                        Icons.flag_outlined),
                    if (q.due) ...[
                      const SizedBox(width: Gap.xxs),
                      _chip(theme, '到期复习', Icons.alarm, warn: true),
                    ],
                    const Spacer(),
                    IconButton(
                      tooltip: '朗读题面',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => TtsService.instance.speak(
                        isSpelling ? q.answer : q.prompt,
                      ),
                      icon: const Icon(Icons.volume_up_outlined, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.xxs),
                Text(
                  widget.mode.promptHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  q.prompt,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 20,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isSpelling && (q.phonetic ?? '').isNotEmpty) ...[
                  const SizedBox(height: Gap.xxs),
                  Text(
                    q.phonetic!,
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: muted,
                    ),
                  ),
                ],
                if ((q.source ?? '').isNotEmpty || q.wordType != 'word') ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    [
                      if (q.wordType != 'word')
                        q.wordType == 'phrase' ? '短语' : '句子',
                      if ((q.source ?? '').isNotEmpty) '出自 ${q.source}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
                if (_showHint && !_answered) ...[
                  const SizedBox(height: Gap.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.sm,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.amber(context).withAlpha(28),
                      borderRadius: Radii.controlRadius,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline,
                            size: 15, color: AppTheme.amber(context)),
                        const SizedBox(width: 6),
                        Text(
                          q.hint,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.amber(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.sm),

        // ④ 作答
        TextField(
          controller: _inputCtrl,
          focusNode: _focus,
          autofocus: true,
          enabled: !_answered,
          minLines: 1,
          maxLines: isSpelling ? 1 : 3,
          textInputAction:
              isSpelling ? TextInputAction.done : TextInputAction.newline,
          onSubmitted: (_) => _answered ? _next() : _submit(),
          decoration: InputDecoration(
            hintText: widget.mode.inputHint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Gap.sm + 2,
              vertical: Gap.sm,
            ),
          ),
        ),

        if (!_answered) ...[
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _showHint = true),
                icon: const Icon(Icons.lightbulb_outline, size: 16),
                label: const Text('给点提示'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _reveal,
                child: const Text('看答案'),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('提交'),
            ),
          ),
        ],

        // ⑤ 反馈:说清为什么(用户明确要求)
        if (_answered && _verdict != null) ...[
          const SizedBox(height: Gap.md),
          _feedbackCard(theme, muted, q, _verdict!),
          const SizedBox(height: Gap.sm),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _next,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(
                _index + 1 >= _questions.length ? '完成本轮' : '下一题',
              ),
            ),
          ),
        ],
        const SizedBox(height: Gap.xl),
      ],
    );
  }

  Widget _chip(ThemeData theme, String label, IconData icon,
      {bool warn = false}) {
    final color =
        warn ? AppTheme.warningColor(context) : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(Radii.control - 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedbackCard(
    ThemeData theme,
    Color muted,
    DrillQuestion q,
    _Verdict v,
  ) {
    final ok = v.correct;
    final color =
        ok ? AppTheme.successColor(context) : AppTheme.warningColor(context);
    return AppCard(
      color: color.withAlpha(16),
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.info_outline,
                  size: 17, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  v.why,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          // 拼写:逐字对照(标出不对的位置)
          if (v.charDiff != null) ...[
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: 1.5,
              runSpacing: 2,
              children: [
                for (final (ch, good) in v.charDiff!)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    decoration: BoxDecoration(
                      color: good
                          ? AppTheme.successColor(context).withAlpha(26)
                          : AppTheme.dangerColor(context).withAlpha(30),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      ch,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: good
                            ? AppTheme.successColor(context)
                            : AppTheme.dangerColor(context),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Gap.sm),
          Text('标准答案',
              style: TextStyle(fontSize: 11, color: muted)),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  q.answer,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
              ),
              IconButton(
                tooltip: '朗读答案',
                visualDensity: VisualDensity.compact,
                onPressed: () => TtsService.instance.speak(q.answer),
                icon: const Icon(Icons.volume_up_outlined, size: 19),
              ),
            ],
          ),
          // 拼写题:顺带给语境原句(不是只记一个词形)
          if (widget.mode == DrillMode.spelling &&
              (q.sentence ?? '').isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Gap.xs + 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(150),
                borderRadius: Radii.controlRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('它在原文里是这样用的',
                      style: TextStyle(fontSize: 10.5, color: muted)),
                  const SizedBox(height: 3),
                  Text(
                    q.sentence!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════ 小结卡 ═══════════════

  Widget _buildSummary() {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final total = _grandTotal;
    final correct = _grandCorrect;
    final acc = total == 0 ? 0.0 : correct / total;
    final wrongList = _wrong.values.toList();
    final color = acc >= 0.9
        ? AppTheme.successColor(context)
        : (acc >= 0.6
            ? theme.colorScheme.primary
            : AppTheme.warningColor(context));

    return ListView(
      padding: Insets.page,
      children: [
        // ① 成绩:数字要大(用户要求"数字要突出")
        AppStagger(
          index: 0,
          child: AppCard(
            color: color.withAlpha(16),
            padding: const EdgeInsets.all(Gap.md + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本轮完成',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                const SizedBox(height: Gap.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(acc * 100).round()}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 46,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5, left: 2),
                      child: Text('%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: color,
                          )),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('对 $correct / $total 题',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          _elapsedSeconds < 60
                              ? '用时 $_elapsedSeconds 秒'
                              : '用时 ${_elapsedSeconds ~/ 60} 分 ${_elapsedSeconds % 60} 秒',
                          style: TextStyle(fontSize: 11.5, color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  DrillPlanner.summaryLine(correct: correct, total: total),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(height: 1.45, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),

        // ② 用时分布 + 落库回执(说实话:错题去哪了)
        AppStagger(
          index: 1,
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 16, color: muted),
                    const SizedBox(width: 6),
                    Text('用时分布',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: Gap.xxs),
                Text(
                  DrillPlanner.paceHint(
                    seconds: _elapsedSeconds,
                    total: total,
                  ),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: muted, height: 1.45),
                ),
                if (wrongList.isNotEmpty) ...[
                  const SizedBox(height: Gap.sm),
                  Row(
                    children: [
                      Icon(Icons.replay, size: 16, color: muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _queuedCount > 0
                              ? '$_queuedCount 个错题已放回今天的复习队列,今天还会再见到'
                              : '错题已记下(这条词条还没入库,下次收藏后再排复习)',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_adaptive != null) ...[
                  const SizedBox(height: Gap.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Gap.xs + 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(16),
                      borderRadius: Radii.controlRadius,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 15, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _adaptive!.note,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // ③ 错题清单
        if (wrongList.isNotEmpty) ...[
          const AppSectionTitle(
            title: '这次的错题',
            subtitle: '点右边喇叭可以听一遍',
          ),
          for (var i = 0; i < wrongList.length; i++)
            AppStagger(
              index: 2 + i,
              child: AppCard(
                dense: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            wrongList[i].answer,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            wrongList[i].prompt,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '朗读',
                      onPressed: () =>
                          TtsService.instance.speak(wrongList[i].answer),
                      icon: const Icon(Icons.volume_up_outlined, size: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],

        // ④ 下一步:只练错题 / 明天继续
        const SizedBox(height: Gap.sm),
        if (wrongList.isNotEmpty)
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: _retryWrong,
              icon: const Icon(Icons.replay, size: 18),
              label: Text('只练错题(${wrongList.length} 题)'),
            ),
          ),
        const SizedBox(height: Gap.xs),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.event_available_outlined, size: 18),
            label: const Text('明天继续'),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Center(
          child: Text(
            '明天的题量会按今天的正确率自动调整',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}
