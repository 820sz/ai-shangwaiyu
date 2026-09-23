import 'package:flutter/material.dart';

/// 空态的统一组件 — 对应代码审查 P2-30 / B4。
///
/// 与 [ErrorState] 配对使用:同样一块灰色区域,失败态给「重试」,
/// 空态只说明"怎么才会有数据",两者在视觉上就分得开。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.hint,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  /// 主提示,如「还没有收藏」
  final String title;

  /// 补充说明,如「在追问回答顶部点 ☆ 即可收藏」
  final String? hint;
  final IconData icon;

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
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
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
