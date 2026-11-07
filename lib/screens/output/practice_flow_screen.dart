import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../models/learner_model.dart';
import '../../services/ability_recorder.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../services/output_composer.dart';
import '../../services/output_draft.dart';
import '../../services/output_feedback.dart';
import '../../services/output_rubric.dart';
import '../../widgets/answer_image_input.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/waiting.dart';
import 'widgets/paper_kit.dart';
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

  /// 每题批改结果(按题目下标):跳题/草稿恢复都要"回到某题时它已经批过"。
  final Map<int, ScoredOutput> _scored = <int, ScoredOutput>{};

  /// 每题作答草稿(按题目下标):跳题不丢、退出写进草稿(下次继续)。
  final Map<int, String> _texts = <int, String>{};

  /// 当前题的批改结果(UI 唯一读口,保持旧代码语义)
  ScoredOutput? get _result => _scored[_index];

  /// 已批改题数(底部"完成"校验口径)
  int get _scoredCount => _scored.length;

  /// 数据库里的题目 id(与按 idx 对齐;没有就 null,作答仍会保存到 attempts)
  List<int?> _itemIds = const [];

  OutputTaskSpec get _task => widget.set.tasks[_index];

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    if (widget.savedSetId > 0) _loadItemIds();
    _restoreDraft();
  }

  /// 恢复上次练习:**先同步恢复草稿**(题号 + 每题文本,纯 Hive 读取),
  /// 再在后台补"哪些题已经批改"(要读库,慢一步不挡首帧)。
  ///
  /// 只在 `savedSetId` 与草稿对得上时恢复 —— 从题库点开另一套题时不会被旧草稿串台。
  void _restoreDraft() {
    try {
      final draft = OutputDraftStore.load();
      if (draft == null || draft.setId != widget.savedSetId) return;
      setState(() {
        _texts.addAll(draft.texts);
        _index = draft.index.clamp(0, widget.set.tasks.length - 1);
        _answerCtrl.text = _texts[_index] ?? '';
      });
      unawaited(_restoreScored());
    } catch (_) {
      // 恢复失败只是回到第 1 题,不影响练习
    }
  }

  /// 已批改题目的还原(读 `output_attempts`;失败静默,不影响练习)
  Future<void> _restoreScored() async {
    if (widget.savedSetId <= 0) return;
    try {
      final scored = await loadScoredByIndex(widget.savedSetId);
      if (!mounted || scored.isEmpty) return;
      setState(() => _scored.addAll(scored));
    } catch (_) {
      // 历史批改读不到就当作"都没批改过"
    }
  }

  /// 把当前输入落到内存草稿(跳题/提交/退出前调用)
  void _saveCurrentText() {
    final text = _answerCtrl.text;
    if (text.trim().isEmpty) {
      _texts.remove(_index);
    } else {
      _texts[_index] = text;
    }
  }

  /// 写 Hive 草稿:全部题都批改完了 → 清草稿(练习已完成);
  /// 否则记录当前题号 + 每题文本,首页据此显示「继续上次练习」。
  Future<void> _persistDraft() async {
    if (widget.savedSetId <= 0) return;
    _saveCurrentText();
    if (_scoredCount >= widget.set.tasks.length) {
      await OutputDraftStore.clear();
      return;
    }
    await OutputDraftStore.save(OutputDraft(
      setId: widget.savedSetId,
      title: widget.set.title,
      index: _index,
      texts: Map<int, String>.from(_texts),
      updatedAt: DateTime.now(),
    ));
  }

  /// 跳到任意题(不强制顺序):保存当前文本 → 载入目标题文本/清错误/重开计时。
  void _switchTo(int target) {
    if (target < 0 || target >= widget.set.tasks.length || target == _index) {
      return;
    }
    _saveCurrentText();
    setState(() {
      _index = target;
      _answerCtrl.text = _texts[target] ?? '';
      _answerImages.clear();
      _error = null;
      _stopwatch
        ..reset()
        ..start();
    });
    _persistDraft();
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
    // 2026-11-07(P0 真机反馈):按题组的 exam_type 纠正 rubric ——
    // 老数据可能给六级题存了 cet4_writing,等级以题组为准,不把错等级展示给用户。
    return OutputRubric.resolveFor(
          rubricId: task.rubricId,
          examType: widget.set.examType,
          taskType: task.type,
        ) ??
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
        _scored[_index] = scored;
        _texts[_index] = answer;
        _answerImages.clear();
      });
      // 批完就落一次草稿:用户随时退出,下次进来这题已是"已批改"
      unawaited(_persistDraft());
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
    _saveCurrentText();
    if (_index + 1 >= widget.set.tasks.length) {
      _finish();
      return;
    }
    _switchTo(_index + 1);
  }

  /// 上一题(不强制顺序;第 1 题时无动作)
  void _prev() => _switchTo(_index - 1);

  /// 完成:整组校验未批改数;有未完成 → 先确认,不拦死用户。
  Future<void> _finish() async {
    _saveCurrentText();
    final pending = widget.set.tasks.length - _scoredCount;
    if (pending > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('还有题没批改'),
          content: Text(
            '本组共 ${widget.set.tasks.length} 题，已批改 $_scoredCount 题，'
            '还有 $pending 题没提交批改。\n\n'
            '现在完成会影响本次统计（未批改的题不计分），可以先回去补完。',
            style: AppFont.tagStyle.copyWith(height: 1.5),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续作答'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('仍然完成'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    await _persistDraft();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  /// 答题卡:整组题目一览(当前/已批改/已写/未答),点任意题跳转。
  Future<void> _openAnswerSheet() async {
    _saveCurrentText();
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return PaperSkin(
          child: Builder(builder: (ctx) {
            final skin = V4Skin.of(ctx);
            final total = widget.set.tasks.length;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Gap.page, 0, Gap.page, Gap.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '答题卡',
                      style: AppFont.subheadStyle.copyWith(
                        color: skin.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '共 $total 题 · 已批改 $_scoredCount 题 · 点任意题可跳转',
                      style: AppFont.tagStyle.copyWith(
                        color: skin.inkSoft,
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: <Widget>[
                        for (var i = 0; i < total; i++)
                          _answerCell(ctx, i),
                      ],
                    ),
                    const SizedBox(height: Gap.md),
                    Row(
                      children: <Widget>[
                        Text(
                          '图例：',
                          style: AppFont.tagStyle.copyWith(
                            color: skin.inkFaint,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _legend(ctx, skin.ink, '当前'),
                        const SizedBox(width: 10),
                        _legend(ctx, skin.accentAlt, '已批改'),
                        const SizedBox(width: 10),
                        _legend(ctx, skin.surfaceAlt, '已写/未答'),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
    if (picked != null && mounted) _switchTo(picked);
  }

  Widget _answerCell(BuildContext context, int i) {
    final skin = V4Skin.of(context);
    final current = i == _index;
    final done = _scored.containsKey(i);
    final written = (_texts[i] ?? '').trim().isNotEmpty;
    final Color bg;
    final Color fg;
    if (current) {
      bg = skin.ink;
      fg = skin.onAccent;
    } else if (done) {
      bg = skin.accentAlt.withValues(alpha: 0.16);
      fg = skin.accentAlt;
    } else {
      bg = written ? skin.surfaceAlt : Colors.transparent;
      fg = skin.inkSoft;
    }
    return GestureDetector(
      onTap: () => Navigator.pop(context, i),
      child: Container(
        width: 52,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: current ? skin.ink : skin.hairline,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '${i + 1}',
              style: AppFont.subheadStyle.copyWith(
                color: fg,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (done)
              Icon(Icons.check_rounded, size: 11, color: fg)
            else
              Text(
                written ? '已写' : '未答',
                style: AppFont.tagStyle.copyWith(color: fg, fontSize: 8.5),
              ),
          ],
        ),
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, String label) {
    return Row(
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppFont.tagStyle.copyWith(
            color: V4Skin.of(context).inkFaint,
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 纸面:本页所有显式取色也走纸面主题(否则图钉/文字会残留果冻紫)
    final paperTheme = paperThemeOf(context);
    final theme = paperTheme;
    final cs = paperTheme.colorScheme;
    final task = _task;
    final total = widget.set.tasks.length;
    // P0-1:统一的来源行「等级 · 年份套数 · 来源站点 · 校对」——
    // 答题时就要能确认"这题哪来的",而不是只在题库列表里标一下。
    final sourceLine = examSourceLine(
      examType: widget.set.examType,
      paperYear: widget.set.paperYear,
      paperLabel: widget.set.paperLabel,
      sourceSite: widget.set.sourceSite.isNotEmpty
          ? widget.set.sourceSite
          : siteOfLicenseNote(widget.set.licenseNote),
      verifyStatus: widget.set.verifyStatus,
      withExam: widget.set.source == 'exam' || widget.set.examType != 'none',
    );
    final skin = paperTheme.extension<V4Skin>()!;
    final levelLabel = widget.set.examType.trim().toLowerCase() == 'none'
        ? ''
        : examShortLabelFor(widget.set.examType);
    return PopScope(
      // 退出时落草稿:下次从首页「继续上次练习」进来可恢复题号与作答
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_persistDraft());
      },
      child: PaperScaffold(
      topBar: PaperTopBar(
        // 眉标只放"哪一级 · 哪一套",不重复长标题(长标题会被截成省略号)
        eyebrow: <String>[
          if (levelLabel.isNotEmpty) levelLabel,
          if (widget.set.paperLabel.trim().isNotEmpty) widget.set.paperLabel,
          if (levelLabel.isEmpty && widget.set.paperLabel.trim().isEmpty)
            widget.set.title.isEmpty
                ? '${task.tier.label}练习'
                : widget.set.title,
        ].join(' · '),
        actions: <Widget>[
          if (total > 1)
            PaperIconAction(
              icon: Icons.grid_view_rounded,
              tooltip: '答题卡（可跳题）',
              onTap: _openAnswerSheet,
            ),
        ],
      ),
      // 唯一主行动放底部固定条:作答时不被按钮打断,滚动也一直在手边
      bottomBar: _buildBottomBar(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, 120),
        children: [
          // ① 进度:细线 + 第 N 题 + 等级标记(A 纸面:不靠色块抢注意力)
          Row(
            children: [
              Text(
                '第 ${_index + 1}/$total 题',
                style: AppFont.metaStyle.copyWith(
                  color: skin.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: Gap.xs),
              _typeBadge(theme, task.type),
              const Spacer(),
              if (levelLabel.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: skin.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    levelLabel,
                    style: AppFont.tagStyle.copyWith(
                      color: skin.inkSoft,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          PaperProgressLine(
            value: total <= 0
                ? 0
                : (_scoredCount + (_result == null ? 0.5 : 0)) / total,
          ),
          const SizedBox(height: Gap.md),

          // ② 题面(纸面卡)
          PaperCard(
            radius: 20,
            padding: const EdgeInsets.all(18),
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

          // ③ 作答区(纸面:输入区不要边框噪声,靠留白分区)
          if (_result == null) ...[
            PaperCard(
              radius: 20,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '你的作答',
                    style: AppFont.tagStyle.copyWith(
                      color: skin.inkFaint,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _answerCtrl,
                    minLines: _editorMinLines(task),
                    maxLines: _editorMaxLines(task),
                    style: AppFont.bodyStyle.copyWith(height: 1.6),
                    decoration: InputDecoration(
                      hintText: _editorHint(task),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  Container(height: 1, color: skin.hairline),
                  const SizedBox(height: 10),
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
            const SizedBox(height: Gap.sm),
            // ③.5 批改标准预览:作答前就知道会被怎么评(不开盲盒)
            _buildRubricPreview(context, task),
            // ③.6 来源行(P0-1:等级 · 年份套数 · 来源站点 · 校对)
            if (sourceLine.isNotEmpty) ...[
              const SizedBox(height: Gap.sm),
              PaperSourceLine(value: sourceLine),
            ],
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
          ],
          const SizedBox(height: Gap.lg),
        ],
      ),
      ),
    );
  }

  /// 批改标准预览(作答前):只列维度名与权重,不泄露答案。
  Widget _buildRubricPreview(BuildContext context, OutputTaskSpec task) {
    final skin = V4Skin.of(context);
    final rubric = _rubricOf(task);
    if (rubric.dimensions.isEmpty) return const SizedBox.shrink();
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '批改标准',
                style: AppFont.tagStyle.copyWith(
                  color: skin.inkFaint,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              // 显示**中文 rubric 名**(绝不显示 cet4_writing 这种 id)
              Text(
                OutputRubric.displayNameOf(rubric.id),
                style: AppFont.tagStyle.copyWith(
                  color: skin.inkFaint,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final dim in rubric.dimensions)
                PaperMetaChip(
                  label: dim.maxScore > 0
                      ? '${dim.label} ${dim.maxScore.toStringAsFixed(0)}'
                      : dim.label,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 底部:作答态 = 上一题 + 提交批改 + 答题卡;结果态 = 再写一遍 + 下一题。
  Widget _buildBottomBar(BuildContext context) {
    final hasPrev = _index > 0;
    if (_result == null) {
      final canSubmit = !_scoring &&
          !_transcribing &&
          (_answerCtrl.text.trim().isNotEmpty || _answerImages.isNotEmpty);
      return PaperBottomAction(
        child: Row(
          children: <Widget>[
            PaperIconAction(
              icon: Icons.chevron_left_rounded,
              tooltip: '上一题',
              onTap: hasPrev ? _prev : null,
            ),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: PaperPillButton(
                label: _transcribing
                    ? '正在转写图片…'
                    : (_answerImages.isEmpty ? '提交批改' : '转写并提交批改'),
                icon: Icons.fact_check_outlined,
                onTap: canSubmit ? _submit : null,
                expand: true,
              ),
            ),
            const SizedBox(width: Gap.xs),
            PaperIconAction(
              icon: Icons.grid_view_rounded,
              tooltip: '答题卡（可跳题）',
              onTap: _openAnswerSheet,
            ),
          ],
        ),
      );
    }
    return PaperBottomAction(
      child: Row(
        children: <Widget>[
          PaperIconAction(
            icon: Icons.chevron_left_rounded,
            tooltip: '上一题',
            onTap: hasPrev ? _prev : null,
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: PaperPillButton(
              label: '再写一遍',
              primary: false,
              onTap: _resetAnswer,
              expand: true,
            ),
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: PaperPillButton(
              label: _index + 1 >= widget.set.tasks.length ? '完成' : '下一题',
              onTap: _next,
              expand: true,
            ),
          ),
        ],
      ),
    );
  }

  /// 看完结果想再写一遍:清空答案重新作答(计时也重开)。
  void _resetAnswer() {
    setState(() {
      _scored.remove(_index);
      _texts.remove(_index);
      _answerCtrl.clear();
      _answerImages.clear();
      _stopwatch
        ..reset()
        ..start();
    });
    unawaited(_persistDraft());
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
