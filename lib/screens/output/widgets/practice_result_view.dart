import 'package:flutter/material.dart';

import '../../../config/design_tokens.dart';
import '../../../config/v4_theme.dart';
import '../../../services/output_rubric.dart';
import '../../../widgets/graphics/graphics.dart';
import '../widgets/paper_kit.dart';

/// 批改结果视图(v3 初版;2026-11-06 视觉 A 纸面工作台重做)。
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
/// 视觉 A(纸面):白面 + 1px 细边 + 编号区块;错误条不再用大块脏红,
/// 改成"中性面 + 左侧 2px 主色细条",让"需要改的地方"抢注意力但不刺眼。
///
/// 纪律:没有依据的维度显示"未评"而不是 0 分(0 分是"评了但很烂",两者不同)。
class PracticeResultView extends StatelessWidget {
  final ScoredOutput result;

  /// 顶部标题(如「第 2 题 · 回译」)
  final String? title;

  /// 再看一次参考答案
  final String? reference;

  /// 本轮的评分标准:用来把 100 分制总分**折算成考场档位**
  /// (用户 2026-11-01:"维度分 + 折算四六级官方档位都要")。
  ///
  /// 为什么不从 [ScoredOutput] 里拿:`ScoredOutput` 只解析模型给的档位文字,
  /// 而"13~15 分档"这类官方区间在 rubric 的 band.description 里 ——
  /// rubric 是本地唯一事实源,不该让模型复述(会漂移)。
  final OutputRubric? rubric;

  const PracticeResultView({
    super.key,
    required this.result,
    this.title,
    this.reference,
    this.rubric,
  });

  /// 把 100 分制总分折算到 rubric 的档位(没有 rubric 或档位为空时 null)。
  RubricBand? get _convertedBand {
    final rub = rubric;
    if (rub == null || rub.bands.isEmpty) return null;
    return bandOf(result.totalScore, rub.bands);
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final maxTotal = result.dimensions.fold<double>(
      0,
      (sum, d) => sum + d.maxScore,
    );
    final totalMax = maxTotal <= 0 ? 100.0 : maxTotal;
    final converted = _convertedBand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null && title!.trim().isNotEmpty) ...<Widget>[
          Text(
            title!,
            style: AppFont.tagStyle.copyWith(
              color: skin.inkFaint,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: Gap.xs),
        ],
        // ① 总分:环 + 档位 + 折算官方档位(A 纸面:一张白卡讲清一个结论)
        PaperCard(
          radius: 20,
          padding: const EdgeInsets.all(18),
          child: Row(
            children: <Widget>[
              RadialGauge(
                value: (result.totalScore / totalMax).clamp(0.0, 1.0),
                size: 84,
                color: skin.accent,
                centerText: result.totalScore.toStringAsFixed(0),
                caption: '满分 ${totalMax.toStringAsFixed(0)}',
                semanticLabel: '总分 ${result.totalScore.toStringAsFixed(0)} 分',
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      result.bandLabel.isEmpty ? '未给档位' : result.bandLabel,
                      style: AppFont.subheadStyle.copyWith(
                        color: skin.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '共评 ${result.ratedDimensionCount} 个维度',
                      style: AppFont.tagStyle.copyWith(
                        color: skin.inkSoft,
                        fontSize: 11,
                      ),
                    ),
                    if (converted != null) ...<Widget>[
                      const SizedBox(height: 5),
                      Text(
                        '折算档位：${converted.label}'
                        '${converted.description.isEmpty ? '' : ' · ${converted.description}'}',
                        style: AppFont.tagStyle.copyWith(
                          color: skin.accent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        // ② 维度分 + 依据
        if (result.dimensions.isNotEmpty) ...<Widget>[
          const SizedBox(height: Gap.lg),
          const PaperSectionHead(index: '01', title: '维度分'),
          const SizedBox(height: Gap.sm),
          for (final d in result.dimensions) ...<Widget>[
            _dimensionRow(context, d),
            const SizedBox(height: 6),
          ],
        ],
        // ③ 错误逐条(低干扰:中性面 + 左侧细条,不用脏红大块)
        if (result.issues.isNotEmpty) ...<Widget>[
          const SizedBox(height: Gap.md),
          PaperSectionHead(
            index: '02',
            title: '需要改的地方',
            trailing: '${result.issues.length} 处',
          ),
          const SizedBox(height: Gap.sm),
          for (final issue in result.issues) ...<Widget>[
            _issueCard(context, issue),
            const SizedBox(height: 8),
          ],
        ],
        // ④ 参考改写
        if ((result.correction ?? '').trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: Gap.md),
          const PaperSectionHead(index: '03', title: '参考改写'),
          const SizedBox(height: Gap.sm),
          PaperCard(
            radius: 18,
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              result.correction!,
              style: AppFont.bodyStyle.copyWith(
                color: skin.ink,
                height: 1.55,
              ),
            ),
          ),
        ],
        // ⑤ 总评
        if (result.summary.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: Gap.md),
          PaperCard(
            radius: 18,
            padding: const EdgeInsets.all(16),
            color: skin.surfaceAlt,
            child: Text(
              result.summary,
              style: AppFont.tagStyle.copyWith(
                color: skin.inkSoft,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ),
        ],
        // ⑥ 参考答案(可选;回译题这里是英文原句)
        if (reference != null && reference!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: Gap.sm),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                '看参考答案',
                style: AppFont.tagStyle.copyWith(
                  color: skin.accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: <Widget>[
                PaperCard(
                  radius: 18,
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    reference!,
                    style: AppFont.bodyStyle.copyWith(
                      color: skin.ink,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 一个维度:名称 + 分数 + 细进度条 + 依据(没评就不画 0 分条)
  Widget _dimensionRow(BuildContext context, ScoredDimension d) {
    final skin = V4Skin.of(context);
    final scored = d.isScored && d.score != null;
    final ratio =
        d.maxScore <= 0 ? 0.0 : ((d.score ?? 0) / d.maxScore).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                d.label.isEmpty ? d.key : d.label,
                style: AppFont.tagStyle.copyWith(
                  color: skin.ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              scored
                  ? '${d.score!.toStringAsFixed(1)} / ${d.maxScore.toStringAsFixed(0)}'
                  : '未评',
              style: AppFont.tagStyle.copyWith(
                color: scored ? skin.accent : skin.inkFaint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (scored)
          PaperProgressLine(value: ratio)
        else
          Container(height: 3, decoration: BoxDecoration(
            color: skin.hairline,
            borderRadius: BorderRadius.circular(999),
          )),
        if (d.evidence.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            '依据：${d.evidence}',
            style: AppFont.tagStyle.copyWith(
              color: skin.inkSoft,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  /// 一条问题:原文片段 → 类型/原因 → 建议(左侧 2px 主色细条,不抢注意力)
  Widget _issueCard(BuildContext context, ScoredIssue issue) {
    final skin = V4Skin.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: skin.hairline, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 2,
            height: 34,
            decoration: BoxDecoration(
              color: skin.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (issue.span.trim().isNotEmpty) ...<Widget>[
                  Text(
                    issue.span,
                    style: AppFont.tagStyle.copyWith(
                      color: skin.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  '${issue.type.isEmpty ? '问题' : issue.type}：${issue.reason}',
                  style: AppFont.tagStyle.copyWith(
                    color: skin.inkSoft,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                ),
                if (issue.suggestion.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    '建议：${issue.suggestion}',
                    style: AppFont.tagStyle.copyWith(
                      color: skin.accent,
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
