import 'package:flutter/material.dart';

/// 危险操作(永久删除类)的统一确认与反馈 — 对应代码审查 P2-28。
///
/// 为什么抽出来:删收藏、清空历史追问、删写译记录此前是四种形态并存
/// (有的弹确认、有的单击即生效、有的删完毫无提示),用户无法建立
/// "要不要确认"的预期。这里统一成一套:红底 FilledButton +
/// 「删除后不可恢复」默认提示,永久删除永远是两段式 —— 先问、再做。
///
/// 用法:
/// ```dart
/// final ok = await confirmDestructive(
///   context,
///   title: '删除收藏',
///   message: '确定删除「$title」吗？删除后不可恢复。',
/// );
/// if (!ok || !context.mounted) return;
/// await provider.remove(id);
/// showFeedbackSnack(context, '已删除收藏', actionLabel: '撤销', onAction: undo);
/// ```
///
/// 返回 true = 用户确认执行;false = 取消或点了遮罩。
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '删除',
  String cancelText = '取消',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message ?? '删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelText),
          ),
          FilledButton(
            // 用主题错误语义色而不是各页自己写 Colors.red:
            // 暗色/换肤时红色才不会跑偏
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmText),
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// 删除/清空类操作完成后的统一反馈(P2-28 要求"删除后要有反馈")。
///
/// [actionLabel] + [onAction] 用来给出「撤销」这类补救入口 ——
/// 删除已经从"不可逆"变成"可反悔",这是安全网而不是锦上添花。
void showFeedbackSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}
