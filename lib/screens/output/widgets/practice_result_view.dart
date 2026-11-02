import 'package:flutter/material.dart';

import '../../../config/design_tokens.dart';
import '../../../services/output_rubric.dart';
import '../../../widgets/app_ui.dart';
import '../../../widgets/graphics/graphics.dart';

/// 批改结果视图(v3 · 批 3 · 骨架 c「对照复盘」)。
///
/// 用户 2026-11-01 的要求:
/// > "评分:维度分 + 折算四六级官方档位都给"(他要求**两个都给**)
///
/// 所以这块按"先给可解释的维度分与依据,再折算考场档位"排:
/// 1. 顶部分数环(满分 100,中心显示总分,下方显示档位);
/// 2. 每个维度一条:维度名 + 分数/满分 + **依据**(模型必须引用作答原文);
/// 3. 逐条错误:原文片段 → 问题类型 → 建议改法;
/// 4. 参考改写(有就显示) + 一句话总评。
///
/// 纪律:没有依据的维度显示"未评"而不是 0 分(0 分是"评了但很烂",两者不同)。
class PracticeResultView extends StatelessWidget {
  final ScoredOutput result;

  /// 顶部标题(如「第 2 题 · 回译」)
  final String? title;

  /// 再看一次参考答案
  final String? reference;

  const PracticeResultView({
    super.key,
    required this.result,
    this.title,
    this.reference,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxTotal = result.dimensions.fold<double>(
      0,
      (sum, d) => sum + d.maxScore,
    );
    final totalMax = maxTotal <= 0 ? 100.0 : maxTotal;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: AppFont.subheadStyle.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Gap.xs),
          ],
          // ① 总分 + 档位
          Row(
            children: [
              RadialGauge(
                value: (result.totalScore / totalMax).clamp(0.0, 1.0),
                size: 88,
                centerText: result.totalScore.toStringAsFixed(0),
                caption: '满分 ${totalMax.toStringAsFixed(0)}',
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.bandLabel.isEmpty ? '未给档位' : result.bandLabel,
                      style: AppFont.subheadStyle.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '共评 ${result.ratedDimensionCount} 个维度',
                      style: AppFont.tagStyle.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          // ② 维度分 + 依据
          for (final d in result.dimensions) ...[
            _dimensionRow(theme, d),
            const SizedBox(height: 6),
          ],
          // ③ 错误逐条
          if (result.issues.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Text(
              '需要改的地方',
              style: AppFont.metaStyle.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (final issue in result.issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.all(Gap.xs),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withAlpha(60),
                    borderRadius: BorderRadius.circular(Radii.control - 2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (issue.span.trim().isNotEmpty)
                        Text(
                          issue.span,
                          style: AppFont.tagStyle.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      if (issue.span.trim().isNotEmpty)
                        const SizedBox(height: 2),
                      Text(
                        '${issue.type.isEmpty ? '问题' : issue.type}：${issue.reason}',
                        style: AppFont.tagStyle.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      if (issue.suggestion.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '建议：${issue.suggestion}',
                          style: AppFont.tagStyle.copyWith(
                            color: cs.primary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
          // ④ 参考改写
          if ((result.correction ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Text(
              '参考改写',
              style: AppFont.metaStyle.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            SelectableText(
              result.correction!,
              style: AppFont.bodyStyle.copyWith(
                color: cs.onSurface,
                height: 1.45,
              ),
            ),
          ],
          // ⑤ 总评
          if (result.summary.trim().isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            Text(
              result.summary,
              style: AppFont.tagStyle.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          // ⑥ 参考答案(可选;回译题这里是英文原句)
          if (reference != null && reference!.trim().isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                '看参考答案',
                style: AppFont.tagStyle.copyWith(color: cs.primary),
              ),
              children: [
                SelectableText(
                  reference!,
                  style: AppFont.bodyStyle.copyWith(
                    color: cs.onSurface,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _dimensionRow(ThemeData theme, ScoredDimension d) {
    final cs = theme.colorScheme;
    final scored = d.isScored && d.score != null;
    final ratio = d.maxScore <= 0 ? 0.0 : ((d.score ?? 0) / d.maxScore).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                d.label.isEmpty ? d.key : d.label,
                style: AppFont.tagStyle.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              scored
                  ? '${d.score!.toStringAsFixed(1)} / ${d.maxScore.toStringAsFixed(0)}'
                  : '未评',
              style: AppFont.tagStyle.copyWith(
                color: scored ? cs.primary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: cs.outlineVariant.withAlpha(80),
          ),
        ),
        if (d.evidence.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            '依据：${d.evidence}',
            style: AppFont.tagStyle.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}
