import 'package:flutter/material.dart';

/// 追问抽屉 回顶/回底 小按钮:监听滚动位置,↑ 未在顶部时显示,↓ 未到底时显示
///
/// 原为 process_chat.dart 私有类(2026-08-10 拆分重构),跨文件使用故公开。
class FollowUpScrollButtons extends StatefulWidget {
  final ScrollController scrollCtrl;
  const FollowUpScrollButtons({super.key, required this.scrollCtrl});

  @override
  State<FollowUpScrollButtons> createState() => _FollowUpScrollButtonsState();
}

class _FollowUpScrollButtonsState extends State<FollowUpScrollButtons> {
  double _offset = 0;
  double _maxExtent = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollCtrl.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final pos = widget.scrollCtrl.position;
    setState(() {
      _offset = pos.pixels;
      _maxExtent = pos.maxScrollExtent;
    });
  }

  @override
  Widget build(BuildContext context) {
    final atTop = _offset < 40;
    final atBottom = _maxExtent - _offset < 40;
    // 内容不满一屏时隐藏
    if (atTop && atBottom) return const SizedBox.shrink();
    // A5:回顶/回底统一 260ms(原来 200ms 与结果页回顶的 300ms 手感不一致);
    // A3:系统开启"移除动画"时瞬时跳转
    final jump = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 260);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!atTop)
          _smallButton(Icons.keyboard_arrow_up, () {
            widget.scrollCtrl.animateTo(
              0,
              duration: jump,
              curve: Curves.easeOut,
            );
          }),
        if (!atBottom) ...[
          const SizedBox(height: 4),
          _smallButton(Icons.keyboard_arrow_down, () {
            widget.scrollCtrl.animateTo(
              widget.scrollCtrl.position.maxScrollExtent,
              duration: jump,
              curve: Curves.easeOut,
            );
          }),
        ],
      ],
    );
  }

  Widget _smallButton(IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// 回到顶部浮动小按钮 — 仅在结果态显示，点击后平滑滚动到顶部
class ScrollToTopButton extends StatefulWidget {
  final ScrollController scrollCtrl;
  const ScrollToTopButton({super.key, required this.scrollCtrl});

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollCtrl.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final show = widget.scrollCtrl.hasClients && widget.scrollCtrl.offset > 200;
    if (show != _visible && mounted) {
      setState(() => _visible = show);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: cs.primary,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          widget.scrollCtrl.animateTo(
            0,
            // A5:与回底按钮统一 260ms;A3:移除动画时瞬时
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeOut,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          // 图标色跟随主色的 on 色:深色模式下主色是亮蓝,配深色图标才有对比度
          child: Icon(Icons.arrow_upward, size: 18, color: cs.onPrimary),
        ),
      ),
    );
  }
}
