import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../models/learner_model.dart';
import '../../services/ability_recorder.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../services/output_composer.dart';
import '../../services/output_feedback.dart';
import '../../services/output_rubric.dart';
import '../../widgets/answer_image_input.dart';
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
  final DoubaoApiService _api = DoubaoApiService();

  /// v2.24:作答可以拍照上传(用户 2026-11-03 要求)—— 提交时先转写再批改
  final List<File> _answerImages = <File>[];
  bool _transcribing = false;

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
    var answer = _answerCtrl.text.trim();
    final images = List<File>.of(_answerImages);
    if ((answer.isEmpty && images.isEmpty) || _scoring || _transcribing) return;
    setState(() {
      _scoring = true;
      _transcribing = images.isNotEmpty;
      _error = null;
    });
    try {
      // ① 有图片 → 先转写成文字(中英/手写/截图都行),再走同一套 rubric 批改。
      //    这样评分口径不变,图片只是另一种输入方式。
      if (images.isNotEmpty) {
        final transcript = await _api.transcribeAnswer(images);
        answer = mergeAnswerWithTranscript(answer, transcript);
        if (!mounted) return;
        setState(() => _transcribing = false);
      }
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
          _transcribing = false;
          _error = '批改没有返回可用结果。可以再点一次「提交批改」重试。';
        });
        return;
      }
      await _saveAttempt(scored, answer);
      if (!mounted) return;
      setState(() {
        _scoring = false;
        _transcribing = false;
        _result = scored;
        _answerImages.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scoring = false;
        _transcribing = false;
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
    // ② E1-5(v3 批 8):练习批改完成 → 能力快照 output(inferred,同日 upsert)。
    //    放在"批改成功"这个时刻、且在"题组没落库"的提前返回**之前** ——
    //    批改本身已经产生了一次能力证据,不能因为题组保存失败就不记;
    //    同日 upsert 保证一天多次练习只留当天最新值,趋势图不被锯齿淹没。
    //    AbilityRecorder 内部失败静默,不影响作答落库与结果展示。
    try {
      await AbilityRecorder.recordScoredOutput(
        scored: scored,
        rubric: _rubricOf(_task),
        taskType: widget.set.section.isNotEmpty
            ? widget.set.section
            : _task.type,
      );
    } catch (_) {
      // 双保险:能力快照绝不能反过来影响练习结果
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
      _answerImages.clear();
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
                // v3 批 8:四阶练习形态差异化 —— 每阶给与题型匹配的引导,
                // 而不是四个阶都长成同一个文本框(D1-13)。
                _buildTierGuidance(theme, cs, task),
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
                    minLines: _editorMinLines(task),
                    maxLines: _editorMaxLines(task),
                    style: AppFont.bodyStyle.copyWith(height: 1.5),
                    decoration: InputDecoration(
                      hintText: _editorHint(task),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Gap.xs),
                  // v2.24:不想打字/手写稿 → 拍照或从相册选,提交时先转写再批改
                  AnswerImageInput(
                    images: _answerImages,
                    enabled: !_scoring && !_transcribing,
                    onChanged: (next) => setState(() {
                      _answerImages
                        ..clear()
                        ..addAll(next);
                    }),
                  ),
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: [
                      Text(
                        '${_wordCount(_answerCtrl.text)} 词'
                        '${_answerImages.isEmpty ? '' : ' · 附图 ${_answerImages.length} 张'}',
                        style: AppFont.tagStyle.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (_transcribing)
                        Text(
                          '正在转写图片…',
                          style: AppFont.tagStyle.copyWith(color: cs.primary),
                        )
                      else if (_scoring)
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
                      onPressed: (_scoring ||
                              _transcribing ||
                              (_answerCtrl.text.trim().isEmpty &&
                                  _answerImages.isEmpty))
                          ? null
                          : _submit,
                      icon: const Icon(Icons.fact_check_outlined, size: 18),
                      label: Text(_transcribing
                          ? '正在转写图片…'
                          : (_answerImages.isEmpty ? '提交批改' : '转写并提交批改')),
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
            // 结果出现时做一次入场(AppStagger 本身尊重系统"减少动态"设置):
            // 批改结果信息密度高,淡入+上滑让用户知道"这是刚出来的新东西"。
            AppStagger(
              index: 0,
              child: PracticeResultView(
                result: _result!,
                title: '第 ${_index + 1} 题 · 批改结果',
                reference: task.reference,
                // 折算档位用本轮实际使用的 rubric(区间/描述是本地事实源)
                rubric: _rubricOf(task),
              ),
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
                      _answerImages.clear();
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

  // ── 四阶形态差异(批 8 · D1-13)────────────────────────────────

  /// 每阶给"这个题型该怎么写"的引导,而不是四个阶都同一句提示。
  Widget _buildTierGuidance(
    ThemeData theme,
    ColorScheme cs,
    OutputTaskSpec task,
  ) {
    final muted = cs.onSurfaceVariant;
    final (String title, String body) = switch (task.tier) {
      OutputTier.sentence => (
          '写句',
          '先把主干(主谓宾)写对,再补修饰与连接词;写完读一遍,看时态与主谓是否一致。',
        ),
      OutputTier.paragraph => (
          '写段',
          '先列 2~3 个要点(或用题面给的提示),再连成一段:主题句 → 展开 → 收尾。',
        ),
      OutputTier.essay => (
          '写篇',
          '先花 2 分钟定结构(立场 → 两个理由配例子 → 收尾),再落笔;写按评分维度自检。',
        ),
      OutputTier.word => ('写词', '把词写对,再看它在句子里怎么用。'),
    };
    final dims = task.tier == OutputTier.essay
        ? _rubricOf(task).dimensions.map((d) => d.label).toList()
        : const <String>[];
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Container(
        padding: const EdgeInsets.all(Gap.xs),
        decoration: BoxDecoration(
          color: cs.primary.withAlpha(10),
          borderRadius: BorderRadius.circular(Radii.control - 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title要点',
              style: AppFont.tagStyle.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              body,
              style: AppFont.tagStyle.copyWith(color: muted, height: 1.4),
            ),
            if (dims.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '评分维度：${dims.join(' / ')}',
                style: AppFont.tagStyle.copyWith(color: muted, height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 作答框高度按阶给:句子短、作文长(形态差异的一部分,不只是换文字)。
  int _editorMinLines(OutputTaskSpec task) => switch (task.tier) {
        OutputTier.word => 3,
        OutputTier.sentence => 4,
        OutputTier.paragraph => 8,
        OutputTier.essay => 14,
      };

  int _editorMaxLines(OutputTaskSpec task) => switch (task.tier) {
        OutputTier.word => 6,
        OutputTier.sentence => 8,
        OutputTier.paragraph => 18,
        OutputTier.essay => 28,
      };

  String _editorHint(OutputTaskSpec task) => switch (task.tier) {
        OutputTier.word => '写出英文单词…',
        OutputTier.sentence => '写出英文句子（先主干，再修饰）…',
        OutputTier.paragraph => '写一段英文（2~4 句，先要点后展开）…',
        OutputTier.essay => '写一篇英文短文（先结构，再落笔）…',
      };

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
