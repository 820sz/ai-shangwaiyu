import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../models/learner_model.dart';
import '../../services/database.dart';
import '../../services/output_composer.dart';
import '../../services/output_feedback.dart';
import '../../services/output_rubric.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/waiting.dart';
import 'widgets/practice_result_view.dart';

/// 练习器(v3 · 批 3 · 骨架 b「篇章任务」+ 骨架 c「对照复盘」)。
///
/// 一次练一组题([OutputSetSpec]):逐题展示 → 用户写 → 提交 → **按 rubric 批改**
/// (维度分 + 依据 + 逐条错误) → 写库(attempts) → 下一题。
///
/// 为什么逐题而不是一屏全铺:
/// 写作练习是"专注一件事"的场景 —— 一屏一题、题面在上、作答在下,
/// 用户的注意力只有一处;结果页复用 [PracticeResultView](维度分先给依据再给分)。
class PracticeFlowScreen extends StatefulWidget {
  /// 由 [PracticeSetupScreen] 生成的题组
  final OutputSetSpec set;

  /// 已保存到数据库的题组 id(0 = 保存失败,仍可练但不进统计)
  final int savedSetId;

  const PracticeFlowScreen({
    super.key,
    required this.set,
    this.savedSetId = 0,
  });

  @override
  State<PracticeFlowScreen> createState() => _PracticeFlowScreenState();
}

class _PracticeFlowScreenState extends State<PracticeFlowScreen> {
  final TextEditingController _answerCtrl = TextEditingController();
  final Stopwatch _stopwatch = Stopwatch();
  final OutputComposer _composer = OutputComposer();

  int _index = 0;
  bool _scoring = false;
  String? _error;
  ScoredOutput? _result;

  /// 数据库里的题目 id(与按 idx 对齐;没有就 null,作答仍会保存到 attempts)
  List<int?> _itemIds = const [];

  OutputTaskSpec get _task => widget.set.tasks[_index];

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    if (widget.savedSetId > 0) _loadItemIds();
  }

  Future<void> _loadItemIds() async {
    try {
      final set = await DatabaseService.getExerciseSet(widget.savedSetId);
      final items = (set?['items'] as List?) ?? const [];
      final ids = <int?>[
        for (final item in items)
          if (item is Map) item['id'] as int?,
      ];
      if (!mounted) return;
      setState(() => _itemIds = ids);
    } catch (_) {
      // 拿不到 id 只影响"按题统计",不影响练习本身
    }
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  OutputRubric _rubricOf(OutputTaskSpec task) {
    final id = task.rubricId.isNotEmpty
        ? task.rubricId
        : (task.tier == OutputTier.sentence ? 'back_translation' : 'summary');
    return OutputRubric.byId(id) ??
        OutputRubric.byId('summary') ??
        OutputRubric.builtin().first;
  }

  Future<void> _submit() async {
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty || _scoring) return;
    setState(() {
      _scoring = true;
      _error = null;
    });
    try {
      final rubric = _rubricOf(_task);
      final scored = await _composer.score(
        rubric: rubric,
        task: _task.promptZh.isEmpty ? _task.promptEn : _task.promptZh,
        answer: answer,
      );
      if (!mounted) return;
      if (scored == null) {
        setState(() {
          _scoring = false;
          _error = '批改没有返回可用结果。可以再点一次「提交批改」重试。';
        });
        return;
      }
      await _saveAttempt(scored, answer);
      if (!mounted) return;
      setState(() {
        _scoring = false;
        _result = scored;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scoring = false;
        _error = '批改失败:$e';
      });
    }
  }

  /// 作答落库(失败静默:不能因为统计写失败把用户刚写完的东西弄丢)。
  Future<void> _saveAttempt(ScoredOutput scored, String answer) async {
    // ① 批改出的错误 → 既有错误标签体系(错误档案 → 助理诊断 → 周报的数据起点)。
    //    放在这里而不是结果页按钮上:用户"又踩了一次这个坑"应该是自动记账的。
    try {
      await OutputFeedback.recordOutputFeedback(
        issues: scored.issues,
        source: 'exercise',
      );
    } catch (_) {
      // 回流失败不影响练习结果展示
    }
    if (widget.savedSetId <= 0) return;
    try {
      final itemId = _index < _itemIds.length ? _itemIds[_index] : null;
      await DatabaseService.insertOutputAttempt({
        'set_id': widget.savedSetId,
        'item_id': itemId,
        'mode': 'ai_rubric',
        // 主观题没有客观对错:correct 留 null(不污染正确率分母)
        'answer': answer,
        'score_json': jsonEncode(scored.toJson()),
        'seconds': _stopwatch.elapsed.inSeconds,
        // 存**归一后的既有标签**而不是模型原文:周报"错误热点 top3"、
        // 错误档案聚合都按这套标签统计(原文会造成几十种近义写法各算一类)。
        'error_tags_json': jsonEncode(
          OutputFeedback.canonicalErrorTags(scored.issues),
        ),
      });
    } catch (_) {
      // 统计失败不影响练习结果展示
    }
  }

  void _next() {
    if (_index + 1 >= widget.set.tasks.length) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _index++;
      _result = null;
      _error = null;
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
    final task = _task;
    final total = widget.set.tasks.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.set.title.isEmpty
              ? '${task.tier.label}练习'
              : widget.set.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: Insets.page,
        children: [
          // ① 进度 + 题源标注(真题必须显示来源)
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
              _typeBadge(theme, task.type),
              const Spacer(),
              if (widget.set.source == 'exam')
                Text(
                  '真题来源 · 已标注',
                  style: AppFont.tagStyle.copyWith(color: cs.primary),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),

          // ② 题面
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.promptZh.trim().isNotEmpty)
                  SelectableText(
                    task.promptZh,
                    style: AppFont.bodyStyle.copyWith(
                      color: cs.onSurface,
                      height: 1.5,
                    ),
                  ),
                if (task.promptEn.trim().isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  SelectableText(
                    task.promptEn,
                    style: AppFont.bodyStyle.copyWith(
                      color: cs.onSurface,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (task.hint.trim().isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    '提示：${task.hint}',
                    style: AppFont.tagStyle.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: Gap.xs),
                Wrap(
                  spacing: Gap.xs,
                  runSpacing: 4,
                  children: [
                    if (task.wordCount > 0)
                      _metaChip(theme, '不少于 ${task.wordCount} 词'),
                    for (final tag in task.abilityTags.take(3))
                      _metaChip(theme, tag),
                    for (final g in task.grammarPoints.take(2))
                      _metaChip(theme, '语法 · $g'),
                  ],
                ),
                if (task.sourceSpan.trim().isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      '看原文出处',
                      style: AppFont.tagStyle.copyWith(color: cs.primary),
                    ),
                    children: [
                      SelectableText(
                        task.sourceSpan,
                        style: AppFont.tagStyle.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),

          // ③ 作答区
          if (_result == null) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _answerCtrl,
                    minLines: 6,
                    maxLines: 14,
                    style: AppFont.bodyStyle.copyWith(height: 1.5),
                    decoration: const InputDecoration(
                      hintText: '用英文写下你的答案…',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: [
                      Text(
                        '${_wordCount(_answerCtrl.text)} 词',
                        style: AppFont.tagStyle.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (_scoring)
                        Text(
                          '正在按 rubric 批改…',
                          style: AppFont.tagStyle.copyWith(color: cs.primary),
                        ),
                    ],
                  ),
                  if (_scoring) ...[
                    const SizedBox(height: Gap.xs),
                    const SkeletonLines(lines: 3, seed: 4),
                  ],
                  const SizedBox(height: Gap.sm),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: (_scoring || _answerCtrl.text.trim().isEmpty)
                          ? null
                          : _submit,
                      icon: const Icon(Icons.fact_check_outlined, size: 18),
                      label: const Text('提交批改'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Gap.xs),
                    Text(
                      _error!,
                      style: AppFont.tagStyle.copyWith(color: cs.error),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            // ④ 批改结果
            PracticeResultView(
              result: _result!,
              title: '第 ${_index + 1} 题 · 批改结果',
              reference: task.reference,
              // 折算档位用本轮实际使用的 rubric(区间/描述是本地事实源)
              rubric: _rubricOf(task),
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      // 看完结果想再写一遍:清空答案重新作答
                      _result = null;
                      _answerCtrl.clear();
                      _stopwatch
                        ..reset()
                        ..start();
                    }),
                    child: const Text('再写一遍'),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: FilledButton(
                    onPressed: _next,
                    child: Text(
                      _index + 1 >= total ? '完成' : '下一题',
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }

  Widget _typeBadge(ThemeData theme, String type) {
    final cs = theme.colorScheme;
    final label = switch (type) {
      'back_translation' => '回译',
      'sentence_rewrite' => '改写',
      'summary' => '摘要',
      'paragraph' => '段落',
      'opinion' => '观点段',
      'continuation' => '续写',
      'chart' => '图表描述',
      'exam_writing' => '写作真题',
      'exam_translation' => '翻译真题',
      _ => type,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withAlpha(16),
        borderRadius: BorderRadius.circular(Radii.control - 4),
      ),
      child: Text(
        label,
        style: AppFont.tagStyle.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _metaChip(ThemeData theme, String text) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(140),
        borderRadius: BorderRadius.circular(Radii.control - 4),
      ),
      child: Text(
        text,
        style: AppFont.tagStyle.copyWith(
          color: cs.onSurfaceVariant,
          fontSize: 10,
        ),
      ),
    );
  }

  int _wordCount(String text) {
    final matches = RegExp(r"[A-Za-z0-9']+").allMatches(text);
    return matches.length;
  }
}

/// 让 levelHint 在 setup 页与 flow 页用同一口径(只需要"大致水平"描述)。
String levelHintOf(LearnerModel model) {
  if (model.hasVocabBaseline) {
    final v = model.vocabEstimate?.value ?? 0;
    final cefr = model.cefr?.value;
    if (cefr != null && cefr.isNotEmpty) return '$cefr(词汇量约 $v)';
    return '词汇量约 $v';
  }
  return '未测(按中级处理)';
}
