import 'package:flutter/material.dart';

/// 加载失败的统一三态组件 — 对应代码审查 P2-30 / B4。
///
/// 为什么需要:DB/IO 失败时各页此前要么自己拼一个裸 `Text`,
/// 要么永久停在转圈(provider 的 `_loading` 没复位)。用户分不清
/// "还没有数据"和"加载失败"。这里固定给出「原因 + 重试」,
/// 与 [EmptyState] 配对:失败可重试、空态只提示。
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = '重试',
    this.icon = Icons.error_outline,
  });

  /// 展示给用户的失败原因(调用方负责把异常翻成人话)
  final String message;

  /// 为空则不显示重试按钮(纯告知型错误)
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        // 可滚动:错误文案很长 + 系统字号放大时不会被裁掉(B3)
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            SelectableText(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
