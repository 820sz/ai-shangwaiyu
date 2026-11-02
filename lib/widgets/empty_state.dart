import 'package:flutter/material.dart';

import 'graphics/graphics.dart';

/// 空态的统一组件 — 对应代码审查 P2-30 / B4。
///
/// 与 [ErrorState] 配对使用:同样一块灰色区域,失败态给「重试」,
/// 空态只说明"怎么才会有数据",两者在视觉上就分得开。
///
/// 批 1(B1-4)起,空态的"一个灰图标"换成图形资产系统的几何插图
/// ([EmptyArt]):图形按语义选(见 [EmptyArtKind.fromIcon]),文案仍由
/// 调用方给 —— 空态文案必须结合上下文,不能写死在图形里。
/// 旧的 [icon] 参数保留并作为**语义种子**,现有调用点一行不用改。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.hint,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.art,
  });

  /// 主提示,如「还没有收藏」
  final String title;

  /// 补充说明,如「在追问回答顶部点 ☆ 即可收藏」
  final String? hint;
  final IconData icon;

  /// 显式指定空态插图;null = 按 [icon] 语义自动选([EmptyArtKind.fromIcon])
  final EmptyArtKind? art;

  /// 可选的操作入口(如「去添加」按钮)
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        // 同 ErrorState:字号放大/文案变长时不裁切(B3)
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 96 = 图形资产的标准中档(GraphicsPalette.sizes):
            // 比旧图标(48)视觉重量更稳,又不到整页 hero 的 120/160
            EmptyArt(kind: art ?? EmptyArtKind.fromIcon(icon), size: 96),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
