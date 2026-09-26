import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/splash_settings.dart';

/// 退出确认的**字幕式底部弹层**(v2.5,M3 用户要求)。
///
/// 用户原话:「退出软件的提示动画就是字幕选项"辛苦啦,再学一会儿?"和"累了~休息啦"
/// 两个选项」。
///
/// 设计取舍:
/// - 两句话都是**有温度的邀请**,不做成"确定要退出吗?[取消][确定]"那种系统提示;
/// - 「辛苦啦,再学一会儿?」= 留在 App(点它、点空白、按返回键都算留下);
/// - 「累了~休息啦」= 退出;
/// - 动画:弹层从底部滑入 + 内容轻微错峰淡入(与开屏同一套手感);
/// - **一天只问一次**(用户选择的行为):问过之后当天再按返回直接退出,
///   避免每次返回都被拦 —— 提示语再温柔,天天拦也烦。
class ExitPrompt {
  ExitPrompt._();

  /// 展示退出弹层。
  /// 返回 true = 用户选择退出;false = 留下(或今天已经问过、直接退出)。
  static Future<bool> show(BuildContext context, {bool forceAsk = false}) async {
    // 一天只问一次:今天问过 → 直接退出,不再拦
    if (!forceAsk && SplashSettings.exitPromptShownToday()) {
      return true;
    }
    await SplashSettings.markExitPromptShown();
    if (!context.mounted) return true;

    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      // 弹层自己带动画:滑入 + 内容错峰淡入
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 260),
        reverseDuration: const Duration(milliseconds: 180),
      ),
      builder: (ctx) => const _ExitSheet(),
    );
    // 点空白关闭 = 留下
    return result ?? false;
  }
}

class _ExitSheet extends StatefulWidget {
  const _ExitSheet();

  @override
  State<_ExitSheet> createState() => _ExitSheetState();
}

class _ExitSheetState extends State<_ExitSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Animation<double> _fade(double from) => CurvedAnimation(
        parent: _ctrl,
        curve: Interval(from, 1, curve: Curves.easeOut),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _fade(0),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(24),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.nightlight_outlined,
                      size: 24, color: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(height: 14),
              // 字幕一:留下
              FadeTransition(
                opacity: _fade(0.15),
                child: Text(
                  SplashSettings.exitStay,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 6),
              FadeTransition(
                opacity: _fade(0.3),
                child: Text(
                  '今天的任务还差一点点就完成了',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              const SizedBox(height: 16),
              // 字幕二:退出
              FadeTransition(
                opacity: _fade(0.45),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                      // 退出 App(不杀进程,交给系统)
                      SystemNavigator.pop();
                    },
                    child: Text(SplashSettings.exitLeave),
                  ),
                ),
              ),
              FadeTransition(
                opacity: _fade(0.6),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('再学一会儿'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
