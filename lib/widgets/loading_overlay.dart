import 'package:flutter/material.dart';

import 'waiting.dart';

/// 全局处理中遮罩(v2.9 改版:不再是"一个圈")。
///
/// 用户 10/2:"所有让 AI 思考或干活的地方,把转圈换成更可感、更高级的形式。"
/// 这个遮罩是用户最常看到的等待界面(AI 批改 / 生成 / 分析都走它),所以:
/// - 有**真实步骤**时传 [steps] → 流式过程时间线(每步都是真发生的);
/// - 否则 → 呼吸的三点 + 一句"在做什么",而不是一个转圈。
class LoadingOverlay extends StatelessWidget {
  final String message;

  /// 真实步骤(v2.9):传了就显示时间线
  final List<AiStep>? steps;

  const LoadingOverlay({
    super.key,
    this.message = '处理中…',
    this.steps,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSteps = steps != null && steps!.isNotEmpty;
    return Container(
      color: Colors.black.withAlpha(77),
      child: Center(
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: hasSteps ? 20 : 32,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasSteps)
                    AiWaitingTimeline(steps: steps!, running: true)
                  else ...[
                    ThinkingDots(label: message),
                    const SizedBox(height: 12),
                    Text(
                      '网络请求通常几秒到十几秒;超过 8 秒还没好,通常是在等模型的深度思考。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 显示加载遮罩
  static void show(
    BuildContext context, {
    String message = '处理中…',
    List<AiStep>? steps,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      builder: (_) => LoadingOverlay(message: message, steps: steps),
    );
  }

  /// 隐藏加载遮罩
  static void hide(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}
