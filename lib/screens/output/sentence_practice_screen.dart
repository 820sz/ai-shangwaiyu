import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../services/output_composer.dart';
import '../../services/output_rubric.dart';
import '../../services/sentence_practice.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/waiting.dart';
import 'widgets/practice_result_view.dart';

/// 写句阶多题型练习屏（v3 · 批 8 · P1-5）。
///
/// 一个屏装三种题型（模式切换）:
/// - **句式改写**:AI 出题 + 回译 rubric 批改；没 AI 时自动降级"离线对照"（不评分）;
/// - **错句纠错**:程序化植入真实常见错误，用户改回 → 精确比对 + 逐点对照;
/// - **连词成句**:词块点选拼句 → 顺序比对。
///
/// 写句阶原来只有回译一条路（用户要求"自选练习方式"），这里补齐——
/// 三种题型结果都走 `SentencePracticeRecorder` 回流（attempts + 错误档案）。
class SentencePracticeScreen extends StatefulWidget {
  final SentencePracticeMode mode;

  const SentencePracticeScreen({super.key, required this.mode});

  @override
  State<SentencePracticeScreen> createState() => _SentencePracticeScreenState();
}

class _SentencePracticeScreenState extends State<SentencePracticeScreen> {
  final _generator = SentenceRewriteGenerator();
  final _composer = OutputComposer();
  final _recorder = const SentencePracticeRecorder();
  final _answerCtrl = TextEditingController();
  final _stopwatch = Stopwatch();

  bool _loading = true;
  String? _error;

  // rewrite
  List<OutputTaskSpec> _rewriteTasks = const [];
  List<OfflineRewriteTask> _offlineTasks = const [];
  ScoredOutput? _scored;

  // correction
  List<InjectedError> _corrections = const [];
  CorrectionCheck? _check;

  // word order
  List<WordOrderTask> _wordOrders = const [];
  List<String> _picked = [];
  bool? _orderCorrect;

  int _index = 0;
  int _correctCount = 0;
  int _answeredCount = 0;
  final List<String> _wrongLines = [];

  bool get _isRewrite => widget.mode == SentencePracticeMode.rewrite;
  bool get _isCorrection => widget.mode == SentencePracticeMode.correction;
  bool get _isWordOrder => widget.mode == SentencePracticeMode.wordOrder;

  int get _total => _isRewrite
      ? (_rewriteTasks.isNotEmpty ? _rewriteTasks.length : _offlineTasks.length)
      : _isCorrection
          ? _corrections.length
          : _wordOrders.length;

  bool get _finished => _index >= _total;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isRewrite) {
        final sentences = await SentencePracticeSource.load(count: 5);
        if (!mounted) return;
        if (_generator.available) {
          final tasks = await _generator.generate(
            sentences: sentences,
            rewriteFocus: '升级句式',
            count: 5,
          );
          if (tasks != null && tasks.isNotEmpty && mounted) {
            setState(() {
              _rewriteTasks = tasks;
              _loading = false;
            });
            return;
          }
        }
        // 离线对照模式:AI 不可用/出题失败都不白屏
        final offline = buildOfflineRewriteTasks(sentences, count: 5);
        if (!mounted) return;
        setState(() {
          _offlineTasks = offline;
          _loading = false;
        });
      } else if (_isCorrection) {
        final sentences = await SentencePracticeSource.load(count: 8);
        final out = <InjectedError>[];
        for (var i = 0; i < sentences.length && out.length < 5; i++) {
          final injected = injectErrors(sentences[i], seed: i * 17 + 3);
          if (injected != null) out.add(injected);
        }
        if (!mounted) return;
        setState(() {
          _corrections = out;
          _loading = false;
        });
      } else {
        final sentences = await SentencePracticeSource.load(count: 5);
        final out = <WordOrderTask>[
          for (var i = 0; i < sentences.length; i++)
            buildWordOrderTask(sentences[i], seed: i * 11 + 1),
        ];
        if (!mounted) return;
        setState(() {
          _wordOrders = out;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _submitRewrite() async {
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty) return;
    final task = _rewriteTasks[_index];
    setState(() => _answeredCount++);
    // 有 AI 才评分;没有就纯对照(不编分数)
    if (_rewriteTasks.isNotEmpty) {
      try {
        final scored = await _composer.score(
          rubric: OutputRubric.byId('back_translation') ??
              OutputRubric.builtin().first,
          task: '${task.promptEn}\n改写方向：${task.hint}',
          answer: answer,
        );
        await _recorder.record(
          mode: SentencePracticeMode.rewrite,
          answer: answer,
          scored: scored,
        );
        if (!mounted) return;
        setState(() => _scored = scored);
        if (scored != null) setState(() => _correctCount++);
        return;
      } catch (_) {
        // 评分失败 → 走对照模式
      }
    }
    await _recorder.record(
      mode: SentencePracticeMode.rewrite,
      answer: answer,
    );
    if (!mounted) return;
    setState(() => _answeredCount--);
    _showReference();
  }

  void _showReference() {
    final task = _rewriteTasks[_index];
    final offline = _offlineTasks[_index];
    final ref = _rewriteTasks.isNotEmpty ? task.reference : '';
    setState(() {
      _scored = null;
      _offlineReference = _rewriteTasks.isNotEmpty
          ? '参考改写：$ref'
          : '改写方向：${offline.guidance}\n可改写点：${offline.focusPoints.join(' / ')}';
      _offlineShown = true;
    });
  }

  String? _offlineReference;
  bool _offlineShown = false;

  Future<void> _submitCorrection() async {
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty) return;
    final injected = _corrections[_index];
    final check = checkCorrection(answer: answer, injected: injected);
    final wrong = !check.correct;
    await _recorder.record(
      mode: SentencePracticeMode.correction,
      answer: answer,
      correct: check.correct,
      errorKinds: wrong ? injected.spots.map((s) => s.kind) : const [],
      evidence: wrong ? injected.wrongSentence : null,
    );
    if (!mounted) return;
    setState(() {
      _check = check;
      _answeredCount++;
      if (check.correct) {
        _correctCount++;
      } else {
        _wrongLines.add(injected.wrongSentence);
      }
    });
  }

  Future<void> _submitWordOrder() async {
    final task = _wordOrders[_index];
    if (_picked.length != task.correctOrder.length) return;
    final ok = checkWordOrder(task.sentence, _picked);
    await _recorder.record(
      mode: SentencePracticeMode.wordOrder,
      answer: _picked.join(' '),
      correct: ok,
      errorKinds: ok ? const [] : const ['词汇'],
      evidence: ok ? null : task.sentence,
    );
    if (!mounted) return;
    setState(() {
      _orderCorrect = ok;
      _answeredCount++;
      if (ok) {
        _correctCount++;
      } else {
        _wrongLines.add(task.sentence);
      }
    });
  }

  void _next() {
    if (_index + 1 >= _total) {
      setState(() {
        _index = _total;
        _stopwatch.stop();
      });
      return;
    }
    setState(() {
      _index++;
      _scored = null;
      _check = null;
      _orderCorrect = null;
      _picked = [];
      _answerCtrl.clear();
      _offlineReference = null;
      _offlineShown = false;
    });
  }

  void _restart() {
    setState(() {
      _index = 0;
      _scored = null;
      _check = null;
      _orderCorrect = null;
      _picked = [];
      _answerCtrl.clear();
      _offlineReference = null;
      _offlineShown = false;
      _correctCount = 0;
      _answeredCount = 0;
      _wrongLines.clear();
      _stopwatch
        ..reset()
        ..start();
    });
  }

  String get _title => widget.mode.label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('写句 · $_title')),
      body: _loading
          ? const Padding(padding: Insets.page, child: SkeletonLines(lines: 5))
          : _error != null
              ? ListView(
                  padding: Insets.page,
                  children: [
                    AppErrorCard(message: '素材加载失败:$_error', onRetry: _load),
                  ],
                )
              : _finished
                  ? _buildSummary(theme, cs)
                  : (_isRewrite
                      ? _buildRewrite(theme, cs)
                      : _isCorrection
                          ? _buildCorrection(theme, cs)
                          : _buildWordOrder(theme, cs)),
    );
  }

  // ── 句式改写 ────────────────────────────────────────────────

  Widget _buildRewrite(ThemeData theme, ColorScheme cs) {
    final aiMode = _rewriteTasks.isNotEmpty;
    final task = aiMode ? _rewriteTasks[_index] : null;
    final offline = aiMode ? null : _offlineTasks[_index];
    return ListView(
      padding: Insets.page,
      children: [
        _progressHeader(cs, aiMode ? 'AI 改写' : '离线对照'),
        const SizedBox(height: Gap.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '原句',
                style: AppFont.tagStyle.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                aiMode ? task!.promptEn : offline!.original,
                style: AppFont.bodyStyle.copyWith(
                  color: cs.onSurface,
                  height: 1.55,
                  fontSize: 16.5,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Text(
                aiMode
                    ? '改写方向：${task!.hint.isEmpty ? '升级句式' : task.hint}'
                    : '改写方向：${offline!.guidance}',
                style: AppFont.tagStyle.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              if (!aiMode) ...[
                const SizedBox(height: 2),
                Text(
                  '可改写点：${offline!.focusPoints.join(' / ')}',
                  style: AppFont.tagStyle.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        if (_scored != null)
          PracticeResultView(
            result: _scored!,
            title: '第 ${_index + 1} 题 · 评分',
            reference: aiMode ? (task?.reference ?? '') : null,
            rubric: OutputRubric.byId('back_translation'),
          )
        else
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _answerCtrl,
                  minLines: 4,
                  maxLines: 8,
                  style: AppFont.bodyStyle.copyWith(height: 1.5),
                  decoration: InputDecoration(
                    hintText: aiMode ? '用英文改写这句话…' : '写下你的改写（不评分，只做对照）…',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (_offlineShown && _offlineReference != null) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    _offlineReference!,
                    style: AppFont.tagStyle.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: Gap.sm),
                if (!_offlineShown)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed:
                          _answerCtrl.text.trim().isEmpty ? null : _submitRewrite,
                      child: const Text('提交'),
                    ),
                  ),
              ],
            ),
          ),
        if (_scored != null || _offlineShown) ...[
          const SizedBox(height: Gap.sm),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: _next,
              child: Text(_index + 1 >= _total ? '看结果' : '下一题'),
            ),
          ),
        ],
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  // ── 错句纠错 ────────────────────────────────────────────────

  Widget _buildCorrection(ThemeData theme, ColorScheme cs) {
    final injected = _corrections[_index];
    final check = _check;
    return ListView(
      padding: Insets.page,
      children: [
        _progressHeader(cs, '纠错'),
        const SizedBox(height: Gap.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                injected.prompt,
                style: AppFont.tagStyle.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: Gap.xs),
              SelectableText(
                injected.wrongSentence,
                style: AppFont.bodyStyle.copyWith(
                  color: cs.onSurface,
                  height: 1.6,
                  fontSize: 16.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _answerCtrl,
                minLines: 3,
                maxLines: 6,
                enabled: check == null,
                style: AppFont.bodyStyle.copyWith(height: 1.5),
                decoration: const InputDecoration(
                  hintText: '写出正确的英文句子…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Gap.sm),
              if (check == null)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: _answerCtrl.text.trim().isEmpty
                        ? null
                        : _submitCorrection,
                    child: const Text('提交'),
                  ),
                )
              else ...[
                Text(
                  check.correct ? '✓ 改对了' : '✗ 还没全改对',
                  style: AppFont.subheadStyle.copyWith(
                    color: check.correct
                        ? AppTheme.successColor(context)
                        : AppTheme.dangerColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '正确句：${injected.correctSentence}',
                  style: AppFont.bodyStyle.copyWith(
                    color: cs.onSurface,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                for (final spot in injected.spots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      check.missed.contains(spot)
                          ? '✗ ${spot.kind}：${spot.wrong} → ${spot.correct}（${spot.noteZh}）'
                          : '✓ ${spot.kind}：${spot.wrong} → ${spot.correct}',
                      style: AppFont.tagStyle.copyWith(
                        color: check.missed.contains(spot)
                            ? AppTheme.dangerColor(context)
                            : AppTheme.successColor(context),
                        height: 1.4,
                      ),
                    ),
                  ),
                const SizedBox(height: Gap.xs),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(_index + 1 >= _total ? '看结果' : '下一题'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  // ── 连词成句 ────────────────────────────────────────────────

  Widget _buildWordOrder(ThemeData theme, ColorScheme cs) {
    final task = _wordOrders[_index];
    final answered = _orderCorrect != null;
    final remaining = <String>[];
    final pool = List<String>.of(task.chunks);
    for (final p in _picked) {
      final idx = pool.indexOf(p);
      if (idx >= 0) pool.removeAt(idx);
    }
    remaining.addAll(pool);
    return ListView(
      padding: Insets.page,
      children: [
        _progressHeader(cs, '连词成句'),
        const SizedBox(height: Gap.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '把词块按正确顺序点成一句话（标点跟着词走）',
                style: AppFont.tagStyle.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: Gap.xs),
              // 已选区域
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Gap.xs),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withAlpha(120),
                  borderRadius: BorderRadius.circular(Radii.control - 2),
                ),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: _picked.isEmpty
                      ? [
                          Text(
                            '点下面的词块开始拼句…',
                            style: AppFont.tagStyle
                                .copyWith(color: cs.onSurfaceVariant),
                          ),
                        ]
                      : [
                          for (var i = 0; i < _picked.length; i++)
                            InputChip(
                              label: Text(_picked[i]),
                              onDeleted: answered
                                  ? null
                                  : () => setState(
                                        () => _picked.removeAt(i),
                                      ),
                            ),
                        ],
                ),
              ),
              if (answered) ...[
                const SizedBox(height: Gap.xs),
                Text(
                  _orderCorrect!
                      ? '✓ 顺序正确'
                      : '✗ 顺序不对，正确句子是：${task.sentence}',
                  style: AppFont.tagStyle.copyWith(
                    color: _orderCorrect!
                        ? AppTheme.successColor(context)
                        : AppTheme.dangerColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Gap.xs,
                runSpacing: Gap.xs,
                children: [
                  for (final chunk in remaining)
                    ActionChip(
                      label: Text(chunk),
                      onPressed: answered
                          ? null
                          : () => setState(() => _picked.add(chunk)),
                    ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              if (!answered)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: _picked.length == task.correctOrder.length
                        ? _submitWordOrder
                        : null,
                    child: Text(
                      _picked.length == task.correctOrder.length
                          ? '提交'
                          : '还差 ${task.correctOrder.length - _picked.length} 个词块',
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(_index + 1 >= _total ? '看结果' : '下一题'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  Widget _progressHeader(ColorScheme cs, String modeLabel) {
    return Row(
      children: [
        Text(
          '第 ${_index + 1}/$_total 题',
          style: AppFont.metaStyle.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: Gap.xs),
        AppTag(modeLabel),
        const Spacer(),
        Text(
          '已答 $_answeredCount',
          style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildSummary(ThemeData theme, ColorScheme cs) {
    final answered = _answeredCount;
    final accuracy = answered == 0 ? 0 : (_correctCount / answered * 100).round();
    final objective = _isCorrection || _isWordOrder;
    return ListView(
      padding: Insets.page,
      children: [
        AppCard(
          variant: AppCardVariant.hero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '这组写句练习做完了',
                style: AppFont.subheadStyle.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Row(
                children: [
                  if (objective)
                    RadialGauge(
                      value: accuracy / 100,
                      size: 96,
                      centerText: '$accuracy%',
                      caption: '正确率',
                    )
                  else
                    OutputTierGraphic(
                      tier: OutputTierArt.sentence,
                      size: 96,
                      showPanel: true,
                    ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          objective
                              ? '$_correctCount / $answered 题改对'
                              : '完成 $answered 题改写',
                          style: AppFont.bodyStyle.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isRewrite && _rewriteTasks.isEmpty
                              ? '离线对照模式：没有评分，只做思路对照'
                              : '错题与改写记录已进输出统计/错误档案',
                          style: AppFont.tagStyle.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_wrongLines.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '需要再看的题',
                  style: AppFont.subheadStyle.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                for (final line in _wrongLines.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '· $line',
                      style: AppFont.tagStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Gap.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _restart,
                child: const Text('再来一轮'),
              ),
            ),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}
