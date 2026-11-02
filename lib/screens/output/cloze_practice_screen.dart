import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../services/cloze_practice.dart';
import '../../services/database.dart';
import '../../services/output_feedback.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/graphics/graphics.dart';

/// 语境选词填空练习（v3 · 批 7 · P1-1）。
///
/// 用户核心哲学原话："背单词功能必须基于输入输出闭环与材料语境。"
/// 这一屏把「读过的材料」直接变成「词汇练习」：
/// - 句子来自他读过的文章；
/// - 挖掉的目标词来自他的生词本（或与考纲精选词的交集）；
/// - 干扰项来自同一篇文章/词表的真实英文词；
/// - 答错自动记「词汇」进错误档案，进输出统计。
class ClozePracticeScreen extends StatefulWidget {
  final ClozeSet set;

  const ClozePracticeScreen({super.key, required this.set});

  @override
  State<ClozePracticeScreen> createState() => _ClozePracticeScreenState();
}

class _ClozePracticeScreenState extends State<ClozePracticeScreen> {
  final Stopwatch _stopwatch = Stopwatch();

  int _index = 0;
  String? _choice;
  bool _answered = false;
  int _correctCount = 0;

  /// (题, 选错的选项)
  final List<(ClozeItem, String)> _wrong = [];

  ClozeItem get _item => widget.set.items[_index];
  bool get _finished => _index >= widget.set.items.length;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _answer(String choice) async {
    if (_answered) return;
    final correct = _item.isCorrect(choice);
    setState(() {
      _choice = choice;
      _answered = true;
      if (correct) {
        _correctCount++;
      } else {
        _wrong.add((_item, choice));
      }
    });
    await _log(correct, choice);
  }

  /// 作答落库 + 答错记错误档案(失败静默:不能影响练习)。
  Future<void> _log(bool correct, String choice) async {
    try {
      await DatabaseService.insertOutputAttempt({
        'mode': 'cloze',
        'answer': choice,
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
          evidence: _item.sourceSentence,
        );
      } catch (_) {
        // 同上
      }
    }
  }

  void _next() {
    if (_index + 1 >= widget.set.items.length) {
      setState(() {
        _index = widget.set.items.length;
        _stopwatch.stop();
      });
      return;
    }
    setState(() {
      _index++;
      _choice = null;
      _answered = false;
    });
  }

  void _restart() {
    setState(() {
      _index = 0;
      _choice = null;
      _answered = false;
      _correctCount = 0;
      _wrong.clear();
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
        title: const Text('语境选词填空'),
      ),
      body: _finished ? _buildSummary(theme, cs) : _buildQuestion(theme, cs),
    );
  }

  Widget _buildQuestion(ThemeData theme, ColorScheme cs) {
    final total = widget.set.items.length;
    final revealed = _answered;
    final correct = revealed && _item.isCorrect(_choice ?? '');
    return ListView(
      padding: Insets.page,
      children: [
        Row(
          children: [
            Text(
              '第 ${_index + 1}/$total 题',
              style: AppFont.metaStyle.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: Gap.xs),
            AppTag('来自《${widget.set.materialTitle}》'),
            const Spacer(),
            if (revealed)
              Text(
                correct ? '✓ 正确' : '✗ 错了',
                style: AppFont.tagStyle.copyWith(
                  color: correct
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
              // 题面:句子里的空格用强调色下划线标出,不用等宽字体也能看清
              _buildSentence(theme, cs),
              if (_item.hintZh.isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  '提示：${_item.hintZh}',
                  style: AppFont.tagStyle.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
              if (revealed) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  correct
                      ? '补对了：${_item.answer}'
                      : '正确答案：${_item.answer}（你选了 ${_choice ?? ''}）',
                  style: AppFont.tagStyle.copyWith(
                    color: correct
                        ? AppTheme.successColor(context)
                        : AppTheme.dangerColor(context),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '原句：${_item.sourceSentence}',
                  style: AppFont.tagStyle.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        // 选项:一排用 Wrap,窄屏自动换行(项目铁律)
        Wrap(
          spacing: Gap.xs,
          runSpacing: Gap.xs,
          children: [
            for (final option in _item.options)
              _buildOption(theme, cs, option, revealed),
          ],
        ),
        const SizedBox(height: Gap.md),
        if (revealed)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _next,
              child: Text(
                _index + 1 >= widget.set.items.length ? '看结果' : '下一题',
              ),
            ),
          ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  /// 句子渲染:按 `____` 切开,空格部分画一条强调色下划线。
  Widget _buildSentence(ThemeData theme, ColorScheme cs) {
    final parts = _item.sentence.split('____');
    final spans = <TextSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        spans.add(TextSpan(
          text: parts[i],
          style: AppFont.bodyStyle.copyWith(
            color: cs.onSurface,
            height: 1.6,
            fontSize: 17,
          ),
        ));
      }
      if (i < parts.length - 1) {
        spans.add(TextSpan(
          text: _answered ? _item.answer : '________',
          style: AppFont.bodyStyle.copyWith(
            color: _answered
                ? (_item.isCorrect(_choice ?? '')
                    ? AppTheme.successColor(context)
                    : AppTheme.dangerColor(context))
                : cs.primary,
            fontWeight: FontWeight.w700,
            height: 1.6,
            fontSize: 17,
            decoration: _answered ? null : TextDecoration.underline,
            decorationColor: cs.primary,
            decorationThickness: 2,
          ),
        ));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildOption(
    ThemeData theme,
    ColorScheme cs,
    String option,
    bool revealed,
  ) {
    final selected = _choice == option;
    final isAnswer = _item.isCorrect(option);
    Color? bg;
    Color? fg;
    if (revealed) {
      if (isAnswer) {
        bg = AppTheme.successColor(context).withAlpha(24);
        fg = AppTheme.successColor(context);
      } else if (selected) {
        bg = AppTheme.dangerColor(context).withAlpha(24);
        fg = AppTheme.dangerColor(context);
      }
    }
    return SizedBox(
      width: 150,
      height: 46,
      child: OutlinedButton(
        onPressed: revealed ? null : () => _answer(option),
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: BorderSide(
            color: revealed
                ? (fg ?? cs.outlineVariant)
                : (selected ? cs.primary : cs.outlineVariant),
            width: revealed && (isAnswer || selected) ? 1.6 : 1,
          ),
        ),
        child: Text(
          option,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildSummary(ThemeData theme, ColorScheme cs) {
    final total = widget.set.items.length;
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
                '这组填空题做完了',
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
                          '$_correctCount / $total 题填对',
                          style: AppFont.bodyStyle.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '材料：《${widget.set.materialTitle}》',
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
                  '没填对的词',
                  style: AppFont.subheadStyle.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                for (final (item, choice) in _wrong)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.answer}${item.hintZh.isEmpty ? '' : '  ${item.hintZh}'}'
                          '（你选了 $choice）',
                          style: AppFont.tagStyle.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        Text(
                          item.sourceSentence,
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
