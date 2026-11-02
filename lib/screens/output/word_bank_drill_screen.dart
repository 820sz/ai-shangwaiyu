import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../services/database.dart';
import '../../services/output_bank.dart';
import '../../services/output_feedback.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/graphics/graphics.dart';

/// 写词阶 · 按目标练词汇(v3 · 批 3 增强,2026-11-01)。
///
/// 用户原话:"输出练习不要局限于和输入闭环……他要考四六级,练习对应可以提供
/// 四六级的材料练习——考纲词汇……同理要读外刊,则提供外刊的高频词"。
///
/// 所以这一屏不读生词本、不依赖已读材料:直接用内置词表(四六级高频/外刊高频)
/// 做**中译英拼写**。答错自动记「词汇」错误标签(与写译/回译同一套错误档案),
/// 结果页给准确率与错词清单,可再来一轮或换来源。
class WordBankDrillScreen extends StatefulWidget {
  /// 本轮要练的词(已按来源抽好;空 = 什么都不练)
  final List<WordBankEntry> words;

  /// 来源名(结果页/标题用)
  final String sourceTitle;

  const WordBankDrillScreen({
    super.key,
    required this.words,
    this.sourceTitle = '按目标练词汇',
  });

  @override
  State<WordBankDrillScreen> createState() => _WordBankDrillScreenState();
}

class _WordBankDrillScreenState extends State<WordBankDrillScreen> {
  final TextEditingController _answerCtrl = TextEditingController();
  final Stopwatch _stopwatch = Stopwatch();

  int _index = 0;
  bool? _lastCorrect;
  bool _revealed = false;

  final List<WordBankEntry> _wrong = [];
  int _correctCount = 0;

  WordBankEntry get _word => widget.words[_index];
  bool get _finished => _index >= widget.words.length;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  String get _hint {
    final w = _word.word;
    if (w.length <= 2) return '${w[0]} __';
    // 首字母 + 第二个字母(单词够长时)+ 剩余长度:够提示但不白给
    final second = w.length >= 4 ? w[1] : '_';
    return '${w[0]}$second${'_' * (w.length - 2)}  (${w.length} 个字母)';
  }

  Future<void> _submit() async {
    final answer = _answerCtrl.text.trim().toLowerCase();
    if (answer.isEmpty || _revealed) return;
    final target = _word.word.toLowerCase();
    final correct = answer == target;
    setState(() {
      _revealed = true;
      _lastCorrect = correct;
      if (correct) {
        _correctCount++;
      } else {
        _wrong.add(_word);
      }
    });
    await _log(correct);
  }

  /// 记一条作答(输出统计)+ 答错时把「词汇」记进错误档案。
  Future<void> _log(bool correct) async {
    try {
      await DatabaseService.insertOutputAttempt({
        'mode': 'spelling',
        'answer': _answerCtrl.text.trim(),
        'correct': correct ? 1 : 0,
        'error_tags_json': jsonEncode(correct ? const <String>[] : ['词汇']),
        'seconds': _stopwatch.elapsed.inSeconds,
      });
    } catch (_) {
      // 统计失败不影响练习
    }
    if (!correct) {
      try {
        await OutputFeedback.recordErrorTags(
          const ['词汇'],
          source: 'output',
          evidence: '${_word.word} → ${_word.meaning}',
        );
      } catch (_) {
        // 同上
      }
    }
  }

  void _next() {
    if (_index + 1 >= widget.words.length) {
      setState(() {
        _index = widget.words.length;
        _stopwatch.stop();
      });
      return;
    }
    setState(() {
      _index++;
      _revealed = false;
      _lastCorrect = null;
      _answerCtrl.clear();
    });
  }

  void _restart() {
    setState(() {
      _index = 0;
      _revealed = false;
      _lastCorrect = null;
      _correctCount = 0;
      _wrong.clear();
      _answerCtrl.clear();
      _stopwatch
        ..reset()
        ..start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sourceTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _finished ? _buildSummary(theme, cs) : _buildQuestion(theme, cs),
    );
  }

  Widget _buildQuestion(ThemeData theme, ColorScheme cs) {
    final total = widget.words.length;
    final correct = _lastCorrect == true;
    return ListView(
      padding: Insets.page,
      children: [
        Row(
          children: [
            Text(
              '第 ${_index + 1}/$total 词',
              style: AppFont.metaStyle.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: Gap.xs),
            AppTag('中译英 · 拼写'),
            const Spacer(),
            if (_lastCorrect != null)
              Text(
                _lastCorrect! ? '✓ 正确' : '✗ 错了',
                style: AppFont.tagStyle.copyWith(
                  color: _lastCorrect!
                      ? AppTheme.successColor(context)
                      : AppTheme.dangerColor(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _word.meaning,
                style: AppFont.displayStyle.copyWith(
                  color: cs.onSurface,
                  fontSize: 26,
                  height: 1.3,
                ),
              ),
              if (_word.pos.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '词性：${_word.pos}',
                  style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: Gap.sm),
              Text(
                _revealed ? '正确答案：${_word.word}' : '提示：$_hint',
                style: AppFont.tagStyle.copyWith(
                  color: _revealed && !correct ? cs.error : cs.primary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              if (_revealed && !correct) ...[
                const SizedBox(height: 4),
                Text(
                  '刚才写的是「${_answerCtrl.text.trim()}」—— 这个词错了会记进错误档案，'
                  '之后复习和助理分析都会带上它。',
                  style: AppFont.tagStyle.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        AppCard(
          child: Column(
            children: [
              TextField(
                controller: _answerCtrl,
                autofocus: true,
                enabled: !_revealed,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _revealed ? _next() : _submit(),
                decoration: const InputDecoration(
                  hintText: '写出英文单词…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Gap.sm),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: _revealed
                    ? FilledButton(
                        onPressed: _next,
                        child: Text(
                          _index + 1 >= total ? '看结果' : '下一个',
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('提交'),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(ThemeData theme, ColorScheme cs) {
    final total = widget.words.length;
    final accuracy = total == 0 ? 0 : (_correctCount / total * 100).round();
    return ListView(
      padding: Insets.page,
      children: [
        AppCard(
          variant: AppCardVariant.hero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '这轮练完了',
                style: AppFont.subheadStyle.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: Gap.xs),
              Row(
                children: [
                  RadialGauge(
                    value: accuracy / 100,
                    size: 96,
                    centerText: '$accuracy%',
                    caption: '正确率',
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_correctCount / $total 个词拼对',
                          style: AppFont.bodyStyle.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '用时 ${_stopwatch.elapsed.inMinutes} 分 '
                          '${_stopwatch.elapsed.inSeconds % 60} 秒',
                          style: AppFont.tagStyle
                              .copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (_wrong.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${_wrong.length} 个词记进了错误档案',
                            style: AppFont.tagStyle.copyWith(
                              color: AppTheme.dangerColor(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_wrong.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '这些词没过关',
                  style: AppFont.subheadStyle.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                for (final w in _wrong)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.close, size: 14, color: AppTheme.dangerColor(context)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${w.word}  ${w.meaning}',
                            style: AppFont.tagStyle.copyWith(
                              color: cs.onSurface,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
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
