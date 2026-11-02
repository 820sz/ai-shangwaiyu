import 'package:flutter/material.dart';

import '../../../config/design_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../../widgets/graphics/graphics.dart';

/// 输出四阶里的一阶卡片(v3 · 批 3)。
///
/// 用户 2026-11-01 的明确要求:
/// > "四阶写作阶梯这个不错,不过不要搞成'只有写词过了才写句'这种死人逻辑,
/// >  而是并行逻辑,因为每个人的需求基础想法不一样。"
///
/// 所以四张卡是**平级、并列**的:没有锁、没有"先完成上一阶",只在卡片上标
/// 当前进度;从哪一阶开始由用户自己决定。
///
/// 图形用 [OutputTierGraphic](排版体量递进:短块 → 三块 → 框行 → 两页),
/// 四张卡放在一起,不用读文字也能看出"段位在涨"。
class OutputTierCard extends StatelessWidget {
  final OutputTierArt tier;

  /// 阶名(写词 / 写句 / 写段 / 写篇)
  final String title;

  /// 一句话说明练什么
  final String subtitle;

  /// 当前进度摘要(真实数据拼出来的;没有就传 null,不显示)
  final String? progress;

  /// false = 该阶的题源还在做(卡片灰一点 + "开发中"角标),点了会给说明而不是无反应
  final bool available;

  final VoidCallback? onTap;

  const OutputTierCard({
    super.key,
    required this.tier,
    required this.title,
    required this.subtitle,
    this.progress,
    this.available = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Opacity(
      // 未开放的阶不要装作可用:整体压一点,角标写清楚
      opacity: available ? 1 : 0.72,
      child: AppCard(
        padding: const EdgeInsets.all(Gap.sm),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OutputTierGraphic(
                  tier: tier,
                  size: 40,
                  showPanel: true,
                  semanticLabel: title,
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppFont.subheadStyle.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (!available)
                        Text(
                          '开发中',
                          style: AppFont.tagStyle.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: cs.outline),
              ],
            ),
            // 文字区用 Expanded 吃掉剩余高度:卡片是固定高网格单元,
            // 大字号/长文案下先压缩留白,而不是把卡片撑破(项目铁律)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.tagStyle.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      progress!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.tagStyle.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 四阶的固定顺序(界面/文案唯一事实源)。
///
/// 为什么顺序写死但**不锁**:顺序只决定"卡片怎么排",不决定"用户先做哪个"。
const List<({OutputTierArt tier, String title, String subtitle})>
    outputTierCatalog = [
  (
    tier: OutputTierArt.word,
    title: '写词',
    subtitle: '认词 / 拼写 / 听写',
  ),
  (
    tier: OutputTierArt.sentence,
    title: '写句',
    subtitle: '中译英回译，把句子写对',
  ),
  (
    tier: OutputTierArt.paragraph,
    title: '写段',
    subtitle: '摘要 / 续写 / 观点段',
  ),
  (
    tier: OutputTierArt.essay,
    title: '写篇',
    subtitle: '写译批改，按目标评分',
  ),
];
