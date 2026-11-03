import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../config/design_tokens.dart';
import '../config/v4_theme.dart';

/// 底部导航。v3 起四栏文案为:**输入 / 输出 / 我的 / 助理** ——
/// 顺序沿用 v2.2 用户真机实测后的调整:学习助理(原「导师」)从最左挪到最右,
/// 因为日常最常做的是"拍/读/写"(输入与输出),助理是回头看结论的地方。
///
/// v4(2026-11-03 用户选定「明亮果冻」):整条改成**悬浮玻璃胶囊** ——
/// - 用 [BackdropFilter] 做磨砂玻璃(只在浮层用,性能成本可接受);
/// - 选中项不是"换颜色",而是**一整颗果冻胶囊**(渐变底 + 白字),指哪打哪;
/// - 触觉反馈保留(真的换栏才触发),动画 220ms,不做弹跳。
///
/// 枚举顺序与 `IndexedStack.children` 必须一一对应,改这里要同时改 `app.dart`。
enum ReadFlowTab { input, output, profile, tutor }

class ReadFlowBottomNav extends StatelessWidget {
  final ReadFlowTab currentTab;
  final ValueChanged<ReadFlowTab> onTabChanged;

  const ReadFlowBottomNav({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: skin.glass,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: skin.dark
                      ? skin.hairline
                      : Colors.white.withValues(alpha: 0.9),
                  width: 1,
                ),
                boxShadow: skin.heroShadow,
              ),
              child: Row(
                children: <Widget>[
                  _NavItem(
                    icon: Icons.auto_stories_outlined,
                    activeIcon: Icons.auto_stories_rounded,
                    // v3(B0-5):从"材料"改回"输入"—— 四个 tab 收敛成语言学习的
                    // **输入 / 输出**闭环(输入=读/听与收词,输出=说/写与练习)。
                    label: '输入',
                    isActive: currentTab == ReadFlowTab.input,
                    onTap: () => _select(context, ReadFlowTab.input),
                  ),
                  _NavItem(
                    icon: Icons.assignment_outlined,
                    activeIcon: Icons.assignment_rounded,
                    label: '输出',
                    isActive: currentTab == ReadFlowTab.output,
                    onTap: () => _select(context, ReadFlowTab.output),
                  ),
                  _NavItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person_rounded,
                    label: '我的',
                    isActive: currentTab == ReadFlowTab.profile,
                    onTap: () => _select(context, ReadFlowTab.profile),
                  ),
                  _NavItem(
                    icon: Icons.assistant_outlined,
                    activeIcon: Icons.assistant_rounded,
                    // "学习助理" → "助理":底栏宽度有限,四个字会挤。
                    label: '助理',
                    isActive: currentTab == ReadFlowTab.tutor,
                    onTap: () => _select(context, ReadFlowTab.tutor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _select(BuildContext context, ReadFlowTab tab) {
    if (tab == currentTab) return;
    // 轻触觉:只在真的换栏时给(内容已在 onTabChanged 里切 IndexedStack)
    HapticFeedback.selectionClick();
    onTabChanged(tab);
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final idleColor = skin.inkSoft;
    final child = isActive
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: skin.accentFill,
              borderRadius: BorderRadius.circular(999),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: skin.accent.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(activeIcon, size: 18, color: skin.onAccent),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: skin.onAccent,
                  ),
                ),
              ],
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedScale(
                duration: Motion.transition,
                curve: Motion.curve,
                scale: 1.0,
                child: Icon(icon, size: 21, color: idleColor),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  color: idleColor,
                ),
              ),
            ],
          );

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          // 换栏动画:胶囊从"无"到"有",用尺寸+透明度过渡(不做位移动画)
          child: AnimatedSwitcher(
            duration: Motion.transition,
            switchInCurve: Motion.curve,
            switchOutCurve: Motion.curve,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1).animate(anim),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey<bool>(isActive), child: child),
          ),
        ),
      ),
    );
  }
}
