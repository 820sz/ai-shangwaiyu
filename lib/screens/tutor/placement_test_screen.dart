import 'package:flutter/material.dart';

import '../../config/placement_bank.dart';
import '../../models/learner_model.dart';
import '../../services/learner_model_store.dart';
import '../../services/vocab_estimator.dart';
import '../../services/word_frequency.dart';

/// 词汇量测试(v2.0)：「速测」与「完整版」两个模式。
///
/// 为什么要有这一页(2.0 的核心修正):
/// v1.9 之前"水平"是拿生词本收藏数瞎估的,导师只能写废话。这里是**测量**:
/// Yes/No 词汇测试 + 伪词校准(自称认识但答了编造词 → 扣掉虚报),
/// 给出"认识约 X 词(区间)"与"你在哪一档开始掉",并写进学习者模型。
///
/// 完整版额外含 5 道语法 + 1 段阅读 3 题:不计入词汇量估计,
/// 只用于给语法薄弱点建档(错误标签画像的第一步)。
class PlacementTestScreen extends StatefulWidget {
  /// true = 完整版(约 10 分钟);false = 速测(约 5 分钟)
  final bool full;

  const PlacementTestScreen({super.key, this.full = false});

  @override
  State<PlacementTestScreen> createState() => _PlacementTestScreenState();
}

enum _Phase { intro, vocab, grammar, reading, result }

class _PlacementTestScreenState extends State<PlacementTestScreen> {
  _Phase _phase = _Phase.intro;
  PlacementSession? _session;
  PlacementResult? _result;
  LearnerModel _model = LearnerModel();

  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _saved = false;

  /// 本次作答不可信(伪词误报过半 / 估计为 0):**不写进模型**。
  /// 理由:一条垃圾基线会污染之后所有的难度匹配与导师诊断 ——
  /// "宁可没有基线,也不要一条错的基线"。
  bool _unreliable = false;

  // 语法/阅读作答
  int _gIndex = 0;
  final List<int?> _gAnswers = [];
  final List<int?> _rAnswers = List<int?>.filled(kReadingPassage.questions.length, null);
  DateTime? _readingStartAt;
  bool _readingSlow = false;
  bool _submittingReading = false;

  @override
  void initState() {
    super.initState();
    _gAnswers.addAll(List<int?>.filled(kGrammarQuestions.length, null));
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await WordFrequency.ensureLoaded();
      _model = LearnerModelStore.load();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '词频数据加载失败:$e';
      });
    }
  }

  void _start() {
    final session = widget.full
        ? PlacementSession.full(seed: DateTime.now().millisecondsSinceEpoch)
        : PlacementSession.fast(seed: DateTime.now().millisecondsSinceEpoch);
    setState(() {
      _session = session;
      _phase = _Phase.vocab;
    });
  }

  void _answerVocab(bool known) {
    final s = _session;
    if (s == null || s.isComplete) return;
    s.answer(known);
    if (s.isComplete) {
      if (widget.full) {
        setState(() => _phase = _Phase.grammar);
      } else {
        _finish();
      }
    } else {
      setState(() {});
    }
  }

  void _answerGrammar(int optionIndex) {
    setState(() {
      _gAnswers[_gIndex] = optionIndex;
    });
  }

  void _nextGrammar() {
    if (_gIndex + 1 < kGrammarQuestions.length) {
      setState(() => _gIndex++);
      return;
    }
    setState(() {
      _phase = _Phase.reading;
      _readingStartAt = DateTime.now();
    });
  }

  int _countCorrect(List<ChoiceQuestion> qs, List<int?> answers) {
    var ok = 0;
    for (var i = 0; i < qs.length; i++) {
      if (answers[i] == qs[i].answerIndex) ok++;
    }
    return ok;
  }

  void _finish() {
    final s = _session;
    if (s == null) return;
    final totalG = kGrammarQuestions.length;
    final totalR = kReadingPassage.questions.length;
    final grammarScore = widget.full
        ? (_countCorrect(kGrammarQuestions, _gAnswers) * 100 / totalG).round()
        : null;
    final readingScore = widget.full
        ? (_countCorrect(kReadingPassage.questions, _rAnswers) * 100 / totalR)
            .round()
        : null;
    final result = s.buildResult(
      grammarScore: grammarScore,
      readingScore: readingScore,
    );
    setState(() {
      _result = result;
      _phase = _Phase.result;
      _submittingReading = false;
    });
    if (result != null) _persist(result, grammarScore, readingScore);
  }

  Future<void> _persist(
    PlacementResult result,
    int? grammarScore,
    int? readingScore,
  ) async {
    // 作答不可信的判定放在最前面:伪词误报 ≥ 50%(可能乱点/自评失真)
    // 或估计为 0(全答不认识)时,不覆盖已有的好基线
    if (result.falseAlarmRate >= 0.5 || result.estimate <= 0) {
      setState(() {
        _unreliable = true;
        _saving = false;
        _saved = false;
      });
      return;
    }
    setState(() {
      _saving = true;
      _unreliable = false;
    });
    try {
      var model = await LearnerModelStore.savePlacement(
        base: _model,
        estimate: result.estimate,
        low: result.low,
        high: result.high,
        cefr: result.cefr,
        falseAlarmRate: result.falseAlarmRate,
      );
      // 完整版的语法/阅读只做记录:不参与词汇量估计,但要留给导师当证据
      final extras = Map<String, dynamic>.from(model.extras);
      extras['last_placement'] = {
        'mode': widget.full ? 'full' : 'fast',
        'estimate': result.estimate,
        'low': result.low,
        'high': result.high,
        'cefr': result.cefr,
        'false_alarm_rate': result.falseAlarmRate,
        'band_hit_rate': result.bandHitRate,
        'answered': result.answeredItems,
        'skipped': result.skippedItems,
        'early_stopped': result.earlyStopped,
        // 空值用 null-aware element(Dart 3.9+ 语法,避免 if 判空)
        'grammar_score': ?grammarScore,
        'reading_score': ?readingScore,
        'at': DateTime.now().toIso8601String(),
      };
      model = model.copyWith(extras: extras);
      await LearnerModelStore.save(model);
      if (!mounted) return;
      setState(() {
        _model = model;
        _saving = false;
        _saved = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // 保存失败不能吞:用户做完 100 题却白做是最糟的体验
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('结果保存失败,请重试:$e')),
      );
    }
  }

  Future<bool> _confirmQuit() async {
    if (_phase == _Phase.intro || _phase == _Phase.result) return true;
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('要放弃这次测试吗?'),
        content: const Text('退出后本次作答不会保存 —— 词汇量测试的价值就在于一次答完,中途退出会得到偏低的估计。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续测试'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃退出'),
          ),
        ],
      ),
    );
    return quit ?? false;
  }

  @override
  Widget build(BuildContext ctx) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // 注意:这里必须用 State 的 context(不能用 build 的参数),
        // 否则 mounted 会被判定为"无关的检查"(analyzer 的
        // use_build_context_synchronously 就是为此报的)
        final quit = await _confirmQuit();
        if (!mounted) return;
        if (quit) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.full ? '词汇量测试 · 完整版' : '词汇量测试 · 速测'),
          bottom: _phase == _Phase.intro || _phase == _Phase.result
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(value: _progress, minHeight: 4),
                ),
        ),
        body: _buildBody(),
      ),
    );
  }

  double get _progress {
    switch (_phase) {
      case _Phase.intro:
        return 0;
      case _Phase.vocab:
        final s = _session;
        if (s == null || s.items.isEmpty) return 0;
        return (s.currentIndex / s.items.length).clamp(0, 1);
      case _Phase.grammar:
        return (_gIndex / kGrammarQuestions.length).clamp(0, 1);
      case _Phase.reading:
        return 0.5;
      case _Phase.result:
        return 1;
    }
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _bootstrap();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    switch (_phase) {
      case _Phase.intro:
        return _buildIntro();
      case _Phase.vocab:
        return _buildVocab();
      case _Phase.grammar:
        return _buildGrammar();
      case _Phase.reading:
        return _buildReading();
      case _Phase.result:
        return _buildResult();
    }
  }

  // ── 说明页 ──
  Widget _buildIntro() {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('先测出你的真实基线', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '接下来会出现一串英文词。认识就点「认识」,不认识就点「不认识」。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _bullet(theme, '凭第一反应作答', '不要为了好看而点"认识" —— 里面混了编造出来的词,'
            '全点认识会被识别出来,估计值反而更低。'),
        _bullet(theme, '用区间而不是单一数字', '测试给出的是"约 X 词(区间)",'
            '这个区间会用于给你挑材料和布置任务。'),
        _bullet(theme, '随时可以重测', '水平会变,隔一段时间重测一次,基线会更新。'),
        if (widget.full)
          _bullet(theme, '末尾还有 5 道语法 + 1 段阅读', '这两部分不计入词汇量,'
              '只用来找出你的语法薄弱点(比如时态、冠词、介词)。'),
        const SizedBox(height: 20),
        Text(
          '预计用时:${widget.full ? '约 10 分钟(含语法与阅读)' : '约 5 分钟'}',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _start,
          child: Text(widget.full ? '开始完整版' : '开始速测'),
        ),
        const SizedBox(height: 8),
        Text(
          '当前基线:${_baselineLine()}',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }

  String _baselineLine() {
    final f = _model.vocabEstimate;
    if (f == null || f.value <= 0) return '尚未测过';
    return '约 ${f.value} 词'
        '${_model.vocabLow != null && _model.vocabHigh != null ? '(${_model.vocabLow}-${_model.vocabHigh})' : ''}';
  }

  Widget _bullet(ThemeData theme, String title, String body) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 6, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 词汇作答 ──
  Widget _buildVocab() {
    final s = _session!;
    final item = s.currentItem;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (item == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final reduce = MediaQuery.of(context).disableAnimations;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${s.currentIndex + 1} / ${s.items.length}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              Text('认识就点认识', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
            child: Text(
              item.word,
              key: ValueKey('${s.currentIndex}-${item.word}'),
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _answerVocab(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('不认识'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _answerVocab(true),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('认识'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '不知道就点"不认识" —— 猜对不猜错都会让结果失真',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }

  // ── 语法小题 ──
  Widget _buildGrammar() {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final q = kGrammarQuestions[_gIndex];
    final picked = _gAnswers[_gIndex];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('语法 · ${_gIndex + 1}/${kGrammarQuestions.length}',
            style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: 8),
        Text(q.prompt, style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _optionTile(
              theme,
              label: String.fromCharCode(65 + i),
              text: q.options[i],
              selected: picked == i,
              // 选完立刻显示对错与解析(即时反馈比攒到最后更有学习价值)
              revealed: picked != null,
              correct: i == q.answerIndex,
              onTap: picked == null ? () => _answerGrammar(i) : null,
            ),
          ),
        if (picked != null) ...[
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(q.explanation, style: theme.textTheme.bodySmall),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _nextGrammar,
            child: Text(_gIndex + 1 == kGrammarQuestions.length ? '进入阅读' : '下一题'),
          ),
        ],
      ],
    );
  }

  Widget _optionTile(
    ThemeData theme, {
    required String label,
    required String text,
    required bool selected,
    required bool revealed,
    required bool correct,
    VoidCallback? onTap,
  }) {
    Color? border;
    if (revealed) {
      if (correct) {
        border = Colors.green;
      } else if (selected) {
        border = Colors.red;
      }
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: border ?? theme.colorScheme.outlineVariant,
            width: border != null ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Text('$label. ', style: theme.textTheme.bodyMedium),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            if (revealed && correct) const Icon(Icons.check, size: 18, color: Colors.green),
          ],
        ),
      ),
    );
  }

  // ── 阅读小题 ──
  //
  // 布局:短文与题目可滚动,**提交按钮固定在底部** ——
  // 材料长的时候,提交入口不应该被埋在列表末尾(用户得先滚到底才知道能不能交)。
  Widget _buildReading() {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final answered = _rAnswers.where((e) => e != null).length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            children: [
              Text('阅读 · 1 段短文 ${kReadingPassage.questions.length} 题',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              const SizedBox(height: 8),
              Text(kReadingPassage.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    kReadingPassage.text.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (var qi = 0; qi < kReadingPassage.questions.length; qi++) ...[
                Text('${qi + 1}. ${kReadingPassage.questions[qi].prompt}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                for (var i = 0;
                    i < kReadingPassage.questions[qi].options.length;
                    i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _optionTile(
                      theme,
                      label: String.fromCharCode(65 + i),
                      text: kReadingPassage.questions[qi].options[i],
                      selected: _rAnswers[qi] == i,
                      // 阅读题不即时判对错(那样后面的题会被提示带偏),
                      // 统一在结果页给分
                      revealed: false,
                      correct: false,
                      onTap: () => setState(() => _rAnswers[qi] = i),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    (_submittingReading || answered < kReadingPassage.questions.length)
                        ? null
                        : () {
                            setState(() => _submittingReading = true);
                            final elapsed = DateTime.now()
                                .difference(_readingStartAt ?? DateTime.now())
                                .inSeconds;
                            _readingSlow =
                                elapsed > kReadingPassage.suggestedSeconds;
                            _finish();
                          },
                child: Text(answered < kReadingPassage.questions.length
                    ? '还有 ${kReadingPassage.questions.length - answered} 题未答'
                    : '提交,看结果'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── 结果页 ──
  Widget _buildResult() {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final r = _result;
    if (r == null) {
      return const Center(child: Text('没有拿到结果,请重新测试'));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('你的词汇量', style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                const SizedBox(height: 4),
                Text('约 ${r.estimate} 词',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('区间 ${r.low} - ${r.high}'
                    '${r.lowConfidence ? '(作答较少,仅供参考)' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(24),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('对应档位 ${r.cefr}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.primary)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('你在哪一档开始掉', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final e in r.bandHitRate.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: Text(_bandLabel(e.key),
                              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: e.value.clamp(0, 1).toDouble(),
                            minHeight: 6,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 40,
                          child: Text('${(e.value * 100).round()}%',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(r.summaryLine, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_unreliable)
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('这次作答不可信,结果没有保存',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    _result!.falseAlarmRate >= 0.5
                        ? '超过一半的"编造词"被判成了认识 —— 这通常意味着作答时在猜或者没看清题。'
                            '为了不污染你的学习画像,这次结果不会写入模型,建议重测一次。'
                        : '这次没有测出有效基线(全答"不认识"或几乎全错)。'
                            '如果确实很多词都不认识,那就从更简单的材料开始 —— 但请重测一次确认。',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          )
        else if (r.falseAlarmRate > 0.01) ...[
          Card(
            color: theme.colorScheme.errorContainer.withAlpha(120),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '有 ${(r.falseAlarmRate * 100).round()}% 的"编造词"被你判成认识 —— '
                '这部分已从估计值里扣掉。作答越诚实,这个数字越接近 0,基线越准。',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.full)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('语法与阅读(不计入词汇量)', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text('语法 ${r.grammarScore ?? 0} 分 · 阅读 ${r.readingScore ?? 0} 分'
                      '${_readingSlow ? ' · 阅读偏慢' : ''}',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Text(_weakGrammarHint(r), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() {
                  _phase = _Phase.intro;
                  _result = null;
                  _saved = false;
                  _gIndex = 0;
                  for (var i = 0; i < _gAnswers.length; i++) {
                    _gAnswers[i] = null;
                  }
                  for (var i = 0; i < _rAnswers.length; i++) {
                    _rAnswers[i] = null;
                  }
                }),
                child: const Text('再测一次'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(_saving
                    ? '保存中…'
                    : (_unreliable ? '知道了' : (_saved ? '完成' : '完成(结果未保存)'))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _saved
              ? '已写入你的学习者模型 —— 导师与材料推荐都会用这个基线。'
              : (_unreliable
                  ? '本次结果未写入模型:你的旧基线(如果有)保持不变。'
                  : '结果将用于:材料难度匹配(i+1)、复习配额、导师诊断。'),
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }

  String _bandLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key;
    final from = int.tryParse(parts[0]) ?? 0;
    final to = int.tryParse(parts[1]) ?? 0;
    String fmt(int v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k' : '$v';
    return '${fmt(from)}-${fmt(to)} 词';
  }

  String _weakGrammarHint(PlacementResult r) {
    final wrong = <String>[];
    for (var i = 0; i < kGrammarQuestions.length; i++) {
      if (_gAnswers[i] != kGrammarQuestions[i].answerIndex) {
        wrong.add(kGrammarQuestions[i].tag);
      }
    }
    if (wrong.isEmpty) return '语法全对 —— 这批高频考点你已经掌握,可以直接进入材料精读。';
    return '错题考点:${wrong.toSet().join('、')} —— 这些已记进你的薄弱点,后续导师会安排针对性输入。';
  }
}
