import 'package:flutter/material.dart';

import '../../../config/design_tokens.dart';
import '../../../services/material_topics.dart';
import '../../../widgets/app_ui.dart';
import '../../../widgets/graphics/graphics.dart';

/// 材料中心的「大分区」卡片(v3 · 批 1,2026-11-01)。
///
/// 为什么抽成独立组件:
/// - 材料中心首页是"按分类找材料"的图形墙,这一批之后二级页/搜索页也可能复用它;
/// - 之前它是 `_buildCategoryGrid` 里的内联 Column(36px 图标块 + 文字),
///   用户截图里那排小图标块就是他反复说"简陋、前端没变"的直接来源;
/// - 抽出来后可以在**预览测试**里单独渲染(见 `test/topic_card_preview_test.dart`),
///   不依赖 Provider/数据库也能"看图验收"。
///
/// 布局约束(为什么是 Column 不是 Row):
/// 2 列网格每格只有约 150dp 宽,横向放 60 的图形 + 文字会把标题挤成"科学与…";
/// 竖向布局让图形占上半、文字占下半,标题有整格宽度。
class MaterialTopicCard extends StatelessWidget {
  final MaterialTopic topic;

  /// 空 = 不可点(预览/禁用态)
  final VoidCallback? onTap;

  const MaterialTopicCard({super.key, required this.topic, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      variant: AppCardVariant.compact,
      padding: const EdgeInsets.all(Gap.sm),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ① 领域身份图形:图形是这一格的主角,不再是一个小图标
          DomainGraphic(
            domain: graphicDomainOfTopic(topic),
            size: 60,
            showPanel: true,
            semanticLabel: topic.label,
          ),
          // ② 文字区用 Expanded 吃掉剩余高度:大字号下先压缩留白,而不是撑破卡片
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.subheadStyle.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    topic.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.tagStyle.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 题材 → 领域身份图形。
///
/// `MaterialTopic` 的 id 用下划线(`sci_tech`),公共映射认 `science/tech`。
/// 这里就地兜一层,不让每个界面各写一遍"题材 id → 图形"的映射。
GraphicDomain graphicDomainOfTopic(MaterialTopic topic) {
  if (topic.id == 'sci_tech') return GraphicDomain.science;
  return GraphicDomain.fromId(topic.id);
}
