import 'package:flutter/material.dart';

import '../../services/database.dart';
import '../../services/reading_quiz.dart';

/// 读后测验页(v2.0)。
///
/// 为什么要有这一步(PLAN-2.0 §6 的"读后动作"):
/// 读完不检验 = 输入没有反馈。这一页只做两件能客观评分的事:
/// **完形填空**(语境中的词义)与**中译英回想**(主动回忆),题目全部由
/// [ReadingQuiz] 从材料原文本地生成 —— 不花钱、离线可用、可复现。
///
/// 结果写两处:
/// - `quiz_results`:导师诊断"读后理解率"读它(正确率 <50% 会建议降低难度);
/// - 错题的词:更新复习状态(lapse)并进错误档案(标签"词汇"),
///   这样"读懂了吗"与"记住了吗"是同一条数据链。
class ReadingQuizScreen extends StatefulWidget {
  final int materialId;
  final String title;
  final List<QuizQuestion> questions;

  const ReadingQuizScreen({
    super.key,
    required this.materialId,
    required this.title,
    required this.questions,
  });

  @override
  State<ReadingQuizScreen> createState() => _ReadingQuizScreenState();
}

class _ReadingQuizScreenState extends State<ReadingQuizScreen> {
  int _index = 0;
  final List<String?> _answers = [];
  final _textCtrl = TextEditingController();
  bool _submitted = false;
  bool _saving = false;
  int _correct = 0;
  List<String> _wrongWords = const [];

  @override
  void initState() {
    super.initState();
    _answers.addAll(List<String?>.filled(widget.questions.length, null));
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _record(String? answer) {
    _answers[_index] = answer;
    _textCtrl.clear();
    if (_index + 1 >= widget.questions.length) {
      _submit();
    } else {
      setState(() => _index++);
    }
  }

  Future<void> _submit() async {
    final correct = ReadingQuiz.grade(widget.questions, _answers);
    final wrong = ReadingQuiz.wrongWords(widget.questions, _answers);
    setState(() {
      _submitted = true;
      _correct = correct;
      _wrongWords = wrong;
      _saving = true;
    });

    // 落库:测验结果 + 错题进复习与错误档案
    try {
      await DatabaseService.insertQuizResult(
        kind: 'reading_comprehension',
        refId: widget.materialId,
        total: widget.questions.length,
        correct: correct,
        detail: {
          'material_title': widget.title,
          'wrong_words': wrong,
          'kinds': widget.questions.map((q) => q.kind).toList(),
        },
      );
      for (final w in wrong) {
        await DatabaseService.bumpErrorTag(
          source: 'reading_quiz',
          tag: '词汇',
          evidence: w,
        );
        // 错词的复习状态回退一档(下次更早出现)—— 只对已在生词本里的词操作
        final vocab = await DatabaseService.getVocabularies(limit: 500);
        final hit = vocab.where((v) => v.word.toLowerCase() == w.toLowerCase());
        if (hit.isNotEmpty && hit.first.id != null) {
          await DatabaseService.upsertWordReview(
            hit.first.id!,
            stability: 0,
            difficulty: 6,
            dueAt: DateTime.now(),
            lastReviewAt: DateTime.now(),
            lastRating: 1,
            lapse: true,
          );
        }
      }
    } catch (e) {
      debugPrint('读后测验落库失败: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (_submitted) return _buildResult(theme, muted);

    final q = widget.questions[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text('读后测验 · ${_index + 1}/${widget.questions.length}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: _index / widget.questions.length,
            minHeight: 4,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(q.isCloze ? '选一个词填进空里' : '回想这个词怎么写',
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 10),
          if (q.isCloze)
            Text(q.prompt,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.6))
          else
            Text(q.prompt, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          if (q.isCloze)
            for (var i = 0; i < q.options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  onPressed: () => _record(q.options[i]),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    alignment: Alignment.centerLeft,
                  ),
                  child: Text('${String.fromCharCode(65 + i)}. ${q.options[i]}'),
                ),
              )
          else ...[
            TextField(
              controller: _textCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '输入英文单词',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => _record(v),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => _record(_textCtrl.text),
              child: const Text('提交'),
            ),
          ],
          const SizedBox(height: 16),
          Text('题目来自你刚读的那份材料;答错的词会回到复习队列。',
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
  }

  Widget _buildResult(ThemeData theme, Color muted) {
    return Scaffold(
      appBar: AppBar(title: const Text('读后测验结果')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text('$_correct / ${widget.questions.length}',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(ReadingQuiz.summary(_correct, widget.questions.length),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium),
                  if (_saving) ...[
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.questions.length; i++)
            _buildReviewCard(theme, muted, i),
          const SizedBox(height: 12),
          Text(
            _wrongWords.isEmpty
                ? '这次没有错词 —— 去导师页看看今天的任务完成了没有。'
                : '错词已回到复习队列(${_wrongWords.length} 个),并记进错误档案。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(ThemeData theme, Color muted, int i) {
    final q = widget.questions[i];
    final given = i < _answers.length ? _answers[i] : null;
    final ok = q.isCorrect(given);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.check_circle : Icons.cancel,
                    size: 18, color: ok ? Colors.green : Colors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    q.isCloze ? '完形填空' : '中译英',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(q.isCloze ? q.prompt : '${q.prompt} → ${q.answer}',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              ok ? '你的答案:${given ?? '(未作答)'}' : '正确答案:${q.answer}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: ok ? muted : Colors.red,
              ),
            ),
            if (q.contextSentence != null) ...[
              const SizedBox(height: 6),
              Text('原文:${q.contextSentence}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ],
        ),
      ),
    );
  }
}
