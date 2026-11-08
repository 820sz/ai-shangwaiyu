import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../services/database.dart';
import '../../services/output_composer.dart';
import '../../services/output_draft.dart';
import '../../services/output_exam_backfill.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/waiting.dart';
import 'practice_flow_screen.dart';
import 'widgets/paper_kit.dart';

/// 题库浏览(v3 · 批 8 D1-8;2026-11-06 视觉 A 纸面工作台重做 + 等级筛选)。
///
/// 为什么需要它:练习器每次出题都会把题组写进 `exercise_sets/items`(v21 起),
/// 但界面上只有"做完就走"一条路 —— 用户想回头重练一套、或者看看自己做过
/// 哪些题,没有入口。这一屏把历史题组列出来,点开就能**原样重练**
/// (题面/参考答案/rubric 都从库里还原,不再花一次出题成本)。
///
/// 本轮(用户 2026-11-06 反馈)补三件事:
/// 1. **等级筛选**(全部 / CET-4 / CET-6 / 考研 / 雅思):以前四六级混排,
///    现在按 `exercise_sets.exam_type` 过滤(`listExerciseSets(examType:)` 已现成);
/// 2. **统一来源行**:等级 · 年份套数 · 来源站点 · 校对状态;
/// 3. **老数据回填**:顶栏「重建题源标签」显式按钮(按标题/来源里的明确写法重判,
///    写不清的保持原样,不隐式迁移)。
class PracticeHistoryScreen extends StatefulWidget {
  const PracticeHistoryScreen({super.key});

  @override
  State<PracticeHistoryScreen> createState() => _PracticeHistoryScreenState();
}

class _PracticeHistoryScreenState extends State<PracticeHistoryScreen> {
  List<Map<String, Object?>> _sets = const [];
  bool _loading = true;
  bool _backfilling = false;
  String? _error;

  /// P0-2:等级筛选值('' = 全部;其余见 [examFilterOptions])
  String _level = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DatabaseService.listExerciseSets(
        examType: _level.isEmpty ? null : _level,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _sets = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 老数据回填(显式操作):先确认,再跑,再报数。
  Future<void> _runBackfill() async {
    if (_backfilling) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重建题源标签？'),
        content: Text(
          examBackfillHint,
          style: AppFont.tagStyle.copyWith(height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('算了'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重建'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _backfilling = true);
    final report = await backfillExerciseExamMeta();
    if (!mounted) return;
    setState(() => _backfilling = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(report.summary)));
    await _load();
  }

  /// 打开一组历史题:把库里的行还原成 `OutputSetSpec` 再进练习器。
  Future<void> _open(Map<String, Object?> row) async {
    final id = (row['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      final full = await DatabaseService.getExerciseSet(id);
      // 与「继续上次练习」共用同一套还原口径(避免两处字段漂移)
      final set = setSpecFromExerciseRow(full);
      if (!mounted || set == null) return;
      await appPush(
        context,
        (_) => PracticeFlowScreen(set: set, savedSetId: id),
      );
      // 回来刷新(可能刚做了新一轮,attempts 变了;题组本身不变)
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('打开题组失败:$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PaperScaffold(
      topBar: PaperTopBar(
        eyebrow: '题库 · 历史题组',
        actions: <Widget>[
          if (_backfilling)
            const SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            PaperIconAction(
              icon: Icons.auto_fix_high_rounded,
              tooltip: '重建题源标签（补等级/年份/套数）',
              onTap: _runBackfill,
            ),
        ],
      ),
      // 用 Builder:让 _buildBody 里的显式取色也拿到纸面主题(否则果冻紫残留)
      body: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, Gap.xl),
        child: SkeletonLines(lines: 5),
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            Gap.page, Gap.md, Gap.page, Gap.xl),
        children: <Widget>[
          PaperEmpty(
            icon: Icons.error_outline_rounded,
            title: '题库读取失败',
            hint: _error!,
            actionLabel: '重试',
            onAction: _load,
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, Gap.xl),
      children: <Widget>[
        PaperTitle(
          title: '题库',
          subtitle: _sets.isEmpty
              ? '做完一组练习就会留在这里。'
              : '共 ${_sets.length} 组 · 点开可重练',
        ),
        const SizedBox(height: Gap.md),
        // P0-2:等级筛选(数据层已支持 examType 过滤)
        PaperLevelTabs(
          value: _level,
          onChanged: (v) {
            if (v == _level) return;
            setState(() => _level = v);
            _load();
          },
        ),
        const SizedBox(height: Gap.lg),
        if (_sets.isEmpty)
          PaperEmpty(
            icon: Icons.inventory_2_outlined,
            title: '这个等级还没有题组',
            hint: _level.isEmpty ? '去四阶练一组。' : '换个等级，或去练一组。',
            actionLabel: '去练习',
            onAction: () => Navigator.maybePop(context),
          )
        else
          for (final row in _sets) ...<Widget>[
            _buildCard(context, row),
            const SizedBox(height: Gap.xs),
          ],
      ],
    );
  }

  Widget _buildCard(BuildContext context, Map<String, Object?> row) {
    final skin = V4Skin.of(context);
    final section = '${row['section'] ?? ''}';
    final tier = outputTierOfItem(section: section, type: '');
    final source = '${row['source'] ?? ''}';
    final sourceLabel = switch (source) {
      'exam' => '真题',
      'builtin' => '内置',
      'user_import' => '我的材料',
      'ai' => 'AI 出题',
      _ => '练习',
    };
    final created = DateTime.tryParse('${row['created_at'] ?? ''}');
    final dateLabel =
        created == null ? '' : '${created.month}/${created.day}';
    final verify = '${row['verify_status'] ?? ''}';
    // P0-1 / P0-2:统一来源行「等级 · 年份套数 · 来源站点 · 校对」。
    // 非真题(内置 / AI / 我的材料)没有等级与卷面,只显示来源与校对状态。
    final examType = '${row['exam_type'] ?? 'none'}';
    final paperYear = (row['paper_year'] as num?)?.toInt();
    final paperLabel = '${row['paper_label'] ?? ''}';
    final sourceSite = siteOfLicenseNote('${row['license_note'] ?? ''}');
    final sourceLine = examSourceLine(
      examType: examType,
      paperYear: paperYear,
      paperLabel: paperLabel,
      sourceSite: sourceSite,
      verifyStatus: verify,
      withExam: source == 'exam',
    );
    final meta2 = <String>[
      sourceLabel,
      sectionLabelFor(section),
      if (dateLabel.isNotEmpty) dateLabel,
    ].where((e) => e.isNotEmpty).join(' · ');

    return PaperRow(
      onTap: () => _open(row),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: skin.pastelAt(tier.index),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: OutputTierGraphic(
            tier: switch (tier) {
              OutputTier.word => OutputTierArt.word,
              OutputTier.sentence => OutputTierArt.sentence,
              OutputTier.paragraph => OutputTierArt.paragraph,
              OutputTier.essay => OutputTierArt.essay,
            },
            size: 24,
          ),
        ),
      ),
      title: '${row['title'] ?? '未命名题组'}',
      meta: sourceLine.isEmpty ? null : sourceLine,
      meta2: meta2,
    );
  }
}
