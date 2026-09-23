import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/exercise.dart';
import '../../providers/article_provider.dart';

class ExerciseScreen extends StatefulWidget {
  final Exercise exercise;

  const ExerciseScreen({super.key, required this.exercise});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  late List<TextEditingController> _controllers;
  late List<String?> _answers;
  bool _submitted = false;
  double? _score;

  @override
  void initState() {
    super.initState();
    final existing = widget.exercise.userAnswers;
    int idx = 0;
    _controllers = widget.exercise.sourceSentences.map((s) {
      final text = (existing != null && existing.length > idx)
          ? (existing[idx++] ?? '')
          : '';
      return TextEditingController(text: text);
    }).toList();
    _answers = existing != null
        ? List.from(existing)
        : List.filled(widget.exercise.sourceSentences.length, null);

    if (existing != null &&
        existing.any((a) => a != null && a.isNotEmpty)) {
      _submitted = true;
      _score = widget.exercise.score;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sentences = widget.exercise.sourceSentences;

    return Scaffold(
      appBar: AppBar(
        title: const Text('回译练习'),
        actions: [
          if (_submitted && _score != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '得分：${_score!.toInt()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _score! >= 60 ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 说明
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.primary.withAlpha(10),
            child: const Text(
              '📝 将下列中文句子翻译回英语。完成后点击"提交"查看结果。',
              style: TextStyle(fontSize: 14),
            ),
          ),

          // 句子列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sentences.length,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 序号 + 中文
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor:
                                  theme.colorScheme.primary,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                sentences[index],
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // 文本框
                        TextField(
                          controller: _controllers[index],
                          decoration: InputDecoration(
                            hintText: _submitted ? '' : '输入英语译文…',
                            border: _submitted
                                ? OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: Colors.transparent),
                                  )
                                : null,
                            filled: _submitted,
                            fillColor: _submitted
                                ? theme.colorScheme.surfaceContainerHighest
                                : null,
                          ),
                          maxLines: 2,
                          enabled: !_submitted,
                          onChanged: (v) {
                            _answers[index] = v;
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 提交按钮
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: _submitted
                    ? OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('返回'),
                      )
                    : FilledButton(
                        onPressed: _allEmpty() ? null : () => _submit(),
                        child: const Text('提交答案'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _allEmpty() {
    return _answers.every((a) => a == null || a.trim().isEmpty);
  }

  Future<void> _submit() async {
    if (widget.exercise.id == null) return;

    // 从 controllers 同步答案
    for (int i = 0; i < _controllers.length; i++) {
      _answers[i] = _controllers[i].text;
    }

    final provider = context.read<ArticleProvider>();
    final score = await provider.submitExerciseAnswers(
      widget.exercise.id!,
      _answers,
      widget.exercise.referenceAnswers, // 英文参考答案;旧练习为 null → 估算
    );

    setState(() {
      _submitted = true;
      _score = score;
    });
  }
}
