import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../services/database.dart';
import '../../services/output_composer.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/waiting.dart';
import 'practice_flow_screen.dart';

/// 题库浏览（v3 · 批 8 · D1-8 「题库浏览」骨架）。
///
/// 为什么需要它:练习器每次出题都会把题组写进 `exercise_sets/items`(v21 起),
/// 但界面上只有"做完就走"一条路 —— 用户想回头重练一套、或者看看自己做过
/// 哪些题,没有入口。这一屏把历史题组列出来,点开就能**原样重练**
/// (题面/参考答案/rubric 都从库里还原,不再花一次出题成本)。
class PracticeHistoryScreen extends StatefulWidget {
  const PracticeHistoryScreen({super.key});

  @override
  State<PracticeHistoryScreen> createState() => _PracticeHistoryScreenState();
}

class _PracticeHistoryScreenState extends State<PracticeHistoryScreen> {
  List<Map<String, Object?>> _sets = const [];
  bool _loading = true;
  String? _error;

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
      final rows = await DatabaseService.listExerciseSets(limit: 100);
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

  /// 打开一组历史题:把库里的行还原成 `OutputSetSpec` 再进练习器。
  Future<void> _open(Map<String, Object?> row) async {
    final id = (row['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      final full = await DatabaseService.getExerciseSet(id);
      final items = (full?['items'] as List?) ?? const [];
      final tasks = <OutputTaskSpec>[];
      for (final raw in items) {
        if (raw is! Map) continue;
        final tier = _tierOf('${full?['section'] ?? ''}', '${raw['type'] ?? ''}');
        tasks.add(OutputTaskSpec(
          tier: tier,
          type: '${raw['type'] ?? ''}',
          promptZh: '${raw['prompt_zh'] ?? ''}',
          promptEn: '${raw['prompt_en'] ?? ''}',
          reference: '${raw['reference_answer'] ?? ''}',
          rubricId: '${raw['rubric_id'] ?? ''}',
          wordCount: _int(raw['word_count']),
          sourceSpan: '${raw['source_span'] ?? ''}',
          source: '${full?['source'] ?? 'builtin'}',
          verifyStatus: '${full?['verify_status'] ?? 'pending'}',
        ));
      }
      if (!mounted || tasks.isEmpty) return;
      final set = OutputSetSpec(
        title: '${full?['title'] ?? '历史题组'}',
        tier: tasks.first.tier,
        source: '${full?['source'] ?? 'builtin'}',
        examType: '${full?['exam_type'] ?? 'none'}',
        section: '${full?['section'] ?? ''}',
        rubricId: '${full?['rubric_id'] ?? ''}',
        tasks: tasks,
      );
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

  OutputTier _tierOf(String section, String type) {
    if (type == 'spelling' || type == 'blank_filling') return OutputTier.word;
    if (type == 'back_translation' ||
        type == 'sentence_rewrite' ||
        type == 'error_correction') {
      return OutputTier.sentence;
    }
    if (type == 'summary' || type == 'paragraph' || type == 'opinion') {
      return OutputTier.paragraph;
    }
    if (type == 'exam_writing' || type == 'writing' || type == 'translation') {
      return OutputTier.essay;
    }
    switch (section) {
      case 'back_translation':
      case 'sentence_rewrite':
        return OutputTier.sentence;
      case 'summary':
        return OutputTier.paragraph;
      case 'writing':
      case 'translation':
        return OutputTier.essay;
      default:
        return OutputTier.paragraph;
    }
  }

  int _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('题库')),
      body: _loading
          ? const Padding(padding: Insets.page, child: SkeletonLines(lines: 5))
          : _error != null
              ? ListView(
                  padding: Insets.page,
                  children: [
                    AppErrorCard(message: '题库读取失败:$_error', onRetry: _load),
                  ],
                )
              : ListView(
                  padding: Insets.page,
                  children: [
                    if (_sets.isEmpty)
                      AppEmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: '还没有做过的题组',
                        hint: '去输出四阶任意一阶练一组,这里就会留下题库,以后能原样重练',
                        action: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('去练习'),
                        ),
                      )
                    else ...[
                      Text(
                        '共 ${_sets.length} 组 · 点开可原样重练（不重新出题）',
                        style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: Gap.xs),
                      for (final row in _sets) _buildCard(theme, cs, row),
                    ],
                    const SizedBox(height: Gap.lg),
                  ],
                ),
    );
  }

  Widget _buildCard(ThemeData theme, ColorScheme cs, Map<String, Object?> row) {
    final section = '${row['section'] ?? ''}';
    final tier = _tierOf(section, '');
    final source = '${row['source'] ?? ''}';
    final sourceLabel = switch (source) {
      'exam' => '真题',
      'builtin' => '内置',
      'user_import' => '我的材料',
      'ai' => 'AI 出题',
      _ => '练习',
    };
    final created = DateTime.tryParse('${row['created_at'] ?? ''}');
    final dateLabel = created == null
        ? ''
        : '${created.month}/${created.day}';
    final verify = '${row['verify_status'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: AppCard(
        variant: AppCardVariant.compact,
        onTap: () => _open(row),
        child: Row(
          children: [
            OutputTierGraphic(
              tier: switch (tier) {
                OutputTier.word => OutputTierArt.word,
                OutputTier.sentence => OutputTierArt.sentence,
                OutputTier.paragraph => OutputTierArt.paragraph,
                OutputTier.essay => OutputTierArt.essay,
              },
              size: 40,
              showPanel: true,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['title'] ?? '未命名题组'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.subheadStyle.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      sourceLabel,
                      '${row['section'] ?? ''}'.isEmpty
                          ? ''
                          : '${row['section']}',
                      dateLabel,
                      verify == 'pending' ? '待校对' : '',
                    ].where((e) => e.isNotEmpty).join(' · '),
                    style: AppFont.tagStyle.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: cs.outline),
          ],
        ),
      ),
    );
  }
}
