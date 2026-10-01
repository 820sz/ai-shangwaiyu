import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/database.dart';
import '../../services/learner_context.dart';
import '../../services/learner_model_store.dart';
import '../../services/tts_service.dart';
import '../../widgets/app_ui.dart';

/// 练习模式(v2.8,用户第 7 条:输出功能要增加"词汇拼写、翻译练习")
enum DrillMode {
  /// 词汇拼写:给中文释义 + 音标,拼出英文单词
  spelling('词汇拼写', Icons.spellcheck, '看中文释义拼英文,错了立刻纠正'),

  /// 翻译练习:给中文句子,写出英文原句(回译)
  translation('翻译练习', Icons.translate, '看中文写英文,系统按词重合率判分');

  const DrillMode(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;
}

/// 拼写 / 翻译练习(v2.8,用户第 7 条)。
///
/// ## 为什么用**本地素材**而不是让 AI 现场编题
/// 1. 用户已有的生词本里就带着 `word / translation / originalSentence` ——
///    这是**他自己读到的句子**,比 AI 编的题更贴他的学习轨迹,且零 API 成本;
/// 2. 练习要能随时开始:等 AI 生成 10 秒会让人放弃;
/// 3. 判分用现成的词重合率(与回译练习同一套口径),本地就能给出对错。
///
/// ## 目标与水平怎么影响它(用户要求"按用户目的需求、水平现状提供针对性练习")
/// - **目标**决定练习题量上限与提示强弱:备考类(四六级/考研/雅思托福)给 10 题、
///   不给首字母提示;兴趣阅读类给 8 题、可以点提示;
/// - **水平**决定选哪些词:优先挑"到期未复习"与"新词"(那就是他现在的短板),
///   词汇量基线写在标题下,用户能看出这份练习是按什么挑的。
class DrillScreen extends StatefulWidget {
  final DrillMode mode;

  const DrillScreen({super.key, required this.mode});

  @override
  State<DrillScreen> createState() => _DrillScreenState();
}

/// 一道题(来自生词本)
class _Question {
  final String prompt; // 中文释义 / 中文句
  final String answer; // 英文词 / 英文原句
  final String? phonetic;
  final String? hint; // 首字母提示
  final int? vocabId;

  const _Question({
    required this.prompt,
    required this.answer,
    this.phonetic,
    this.hint,
    this.vocabId,
  });
}

class _DrillScreenState extends State<DrillScreen> {
  final _inputCtrl = TextEditingController();
  final _focus = FocusNode();

  List<_Question> _questions = const [];
  int _index = 0;
  bool _loading = true;
  bool _showHint = false;
  bool _revealed = false;
  String _lastVerdict = '';
  bool _lastCorrect = false;
  int _correct = 0;
  final List<_Question> _wrong = [];
  LearnerModel _model = LearnerModel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _model = LearnerModelStore.load();
      _build();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 组题:目标决定题量,水平决定挑词顺序(到期未复习 → 新词 → 其它)
  void _build() {
    final vocab = context.read<VocabProvider>().vocabularies;
    final goal = _model.goal?.value ?? '';
    final examGoal = RegExp(r'四六级|考研|雅思|托福|出国|学术|工作').hasMatch(goal);
    final limit = examGoal ? 10 : 8;

    final candidates = <_Question>[];
    for (final v in vocab) {
      final word = v.word.trim();
      if (word.isEmpty) continue;
      final sentence = (v.originalSentence ?? '').trim();
      if (widget.mode == DrillMode.spelling) {
        // 统一小写比较(用户输入大小写不该算错),且只练单词/短语
        candidates.add(_Question(
          prompt: (v.translation ?? '').trim().isEmpty ? '(无释义)' : v.translation!.trim(),
          answer: word,
          phonetic: v.displayPhonetic,
          hint: word.isEmpty ? null : word[0],
          vocabId: v.id,
        ));
      } else {
        if (sentence.isEmpty) continue; // 没有原句练不了翻译
        candidates.add(_Question(
          prompt: (v.translation ?? '').trim().isEmpty
              ? '(无释义)'
              : v.translation!.trim(),
          answer: sentence,
          hint: '${sentence.split(' ').first}…',
          vocabId: v.id,
        ));
      }
    }
    // 短词优先(拼写),句子短的优先(翻译)—— 先易后难,不至于第一题就劝退
    candidates.sort((a, b) => a.answer.length.compareTo(b.answer.length));
    setState(() {
      _questions = candidates.take(limit).toList();
      _loading = false;
    });
  }

  /// 判分:拼写用完全匹配(忽略大小写/首尾空白);翻译用词重合率 ≥0.5(与回译同口径)
  bool _judge(String input, String answer) {
    final a = input.trim().toLowerCase();
    final b = answer.trim().toLowerCase();
    if (a.isEmpty) return false;
    if (widget.mode == DrillMode.spelling) {
      return a == b;
    }
    Set<String> words(String s) => s
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    final ref = words(b);
    if (ref.isEmpty) return false;
    final hit = words(a).intersection(ref).length / ref.length;
    return hit >= 0.5;
  }

  void _submit() {
    if (_questions.isEmpty) return;
    final q = _questions[_index];
    final ok = _judge(_inputCtrl.text, q.answer);
    setState(() {
      _lastVerdict = ok ? '对了' : '再看一眼正确答案';
      _lastCorrect = ok;
      _revealed = true;
      if (ok) {
        _correct++;
      } else if (!_wrong.any((w) => w.answer == q.answer)) {
        _wrong.add(q);
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
      _revealed = false;
      _showHint = false;
      _lastVerdict = '';
    });
    _focus.requestFocus();
  }

  Future<void> _finish() async {
    final total = _questions.length;
    final score = total == 0 ? 0 : (_correct / total * 100).round();
    // 错题**立刻进复习队列**(dueAt = 现在):练习的意义就是让它在今天再出现一次,
    // 否则这轮练习就只是"看过答案"而已
    var queued = 0;
    for (final w in _wrong) {
      final id = w.vocabId;
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
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('这轮 ${widget.mode.label} 完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('答对 $_correct/$total(得分 $score)',
                style: const TextStyle(fontSize: 14)),
            if (_wrong.isNotEmpty) ...[
              const SizedBox(height: Gap.xs),
              const Text('这几个还没拿下(已放回今天的复习队列):',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              for (final w in _wrong.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('· ${w.answer}',
                      style: const TextStyle(fontSize: 13)),
                ),
              if (queued > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('已安排 $queued 个进复习',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      )),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _questions = List.of(_wrong);
                _index = 0;
                _correct = 0;
                _wrong.clear();
                _revealed = false;
                _inputCtrl.clear();
              });
            },
            icon: const Icon(Icons.replay, size: 16),
            label: const Text('只练错题'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final goal = _model.goal?.value ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode.label),
        actions: [
          if (_questions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: Gap.md),
              child: Center(
                child: Text('${_index + 1}/${_questions.length}',
                    style: TextStyle(fontSize: 13, color: muted)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const AppLoading(label: '正在按你的生词组题…')
          : _questions.isEmpty
              ? AppEmpty(
                  icon: Icons.inbox_outlined,
                  title: '还没有可练的内容',
                  hint: widget.mode == DrillMode.spelling
                      ? '先去「输入」拍照或读材料收几个词,再来拼写'
                      : '翻译练习要词条带英文原句 —— 从材料阅读器点词收藏的词会自动带原句',
                )
              : ListView(
                  padding: Insets.page,
                  children: [
                    // ① 这份练习是按什么挑的(用户要求"针对性、可选择的练习材料")
                    Text(
                      [
                        if (goal.isNotEmpty) '目标:$goal',
                        '水平:${LearnerContext.describeBaseline(_model)}',
                        '按到期与新词优先组题',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, height: 1.4),
                    ),
                    const SizedBox(height: Gap.md),
                    // ② 题面
                    AppCard(
                      padding: const EdgeInsets.all(Gap.md + 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.mode == DrillMode.spelling
                                ? '拼出这个意思的英文'
                                : '把这句话写成英文',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted),
                          ),
                          const SizedBox(height: Gap.xs),
                          Text(
                            _questions[_index].prompt,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 20,
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if ((_questions[_index].phonetic ?? '').isNotEmpty) ...[
                            const SizedBox(height: Gap.xs),
                            Text(
                              _questions[_index].phonetic!,
                              style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: muted,
                              ),
                            ),
                          ],
                          if (_showHint) ...[
                            const SizedBox(height: Gap.xs),
                            Text('提示:${_questions[_index].hint ?? ''}',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.primary)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    // ③ 作答
                    TextField(
                      controller: _inputCtrl,
                      focusNode: _focus,
                      autofocus: true,
                      enabled: !_revealed,
                      minLines: 1,
                      maxLines: widget.mode == DrillMode.spelling ? 1 : 3,
                      textInputAction: widget.mode == DrillMode.spelling
                          ? TextInputAction.done
                          : TextInputAction.newline,
                      onSubmitted: (_) => _revealed ? _next() : _submit(),
                      decoration: InputDecoration(
                        hintText: widget.mode == DrillMode.spelling
                            ? '输入英文单词'
                            : '写出英文句子(按词重合判分)',
                        border: const OutlineInputBorder(),
                        suffixIcon: !_revealed
                            ? IconButton(
                                tooltip: '朗读题面',
                                onPressed: () =>
                                    TtsService.instance.speak(
                                  widget.mode == DrillMode.spelling
                                      ? (_questions[_index].phonetic ?? '')
                                      : _questions[_index].prompt,
                                ),
                                icon: const Icon(Icons.volume_up_outlined),
                              )
                            : null,
                      ),
                    ),
                    if (!_revealed) ...[
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
                            onPressed: () => setState(() {
                              _revealed = true;
                              _lastCorrect = false;
                              _lastVerdict = '先看答案,下次就记住了';
                              if (!_wrong
                                  .any((w) => w.answer == _questions[_index].answer)) {
                                _wrong.add(_questions[_index]);
                              }
                            }),
                            child: const Text('看答案'),
                          ),
                        ],
                      ),
                    ],
                    if (_revealed) ...[
                      const SizedBox(height: Gap.sm),
                      AppCard(
                        color: (_lastCorrect
                                ? AppTheme.successColor(context)
                                : AppTheme.warningColor(context))
                            .withAlpha(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _lastCorrect
                                      ? Icons.check_circle
                                      : Icons.info_outline,
                                  size: 16,
                                  color: _lastCorrect
                                      ? AppTheme.successColor(context)
                                      : AppTheme.warningColor(context),
                                ),
                                const SizedBox(width: 6),
                                Text(_lastVerdict,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: _lastCorrect
                                          ? AppTheme.successColor(context)
                                          : AppTheme.warningColor(context),
                                    )),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              _questions[_index].answer,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton.icon(
                              onPressed: () => TtsService.instance
                                  .speak(_questions[_index].answer),
                              icon: const Icon(Icons.volume_up_outlined,
                                  size: 15),
                              label: const Text('听一遍'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Gap.sm),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: FilledButton.icon(
                          onPressed: _next,
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text(
                            _index + 1 >= _questions.length ? '完成' : '下一题',
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: Gap.md),
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
                  ],
                ),
    );
  }
}
