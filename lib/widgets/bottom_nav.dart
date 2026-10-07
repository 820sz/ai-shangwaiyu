import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../config/design_tokens.dart';

/// 底部导航。v2.2 起四栏顺序为:**输入 / 输出 / 我的 / 学习助理** ——
/// 用户真机实测后的调整:学习助理(原「导师」)从最左挪到最右,
/// 因为日常最常做的是"拍/读/写"(输入与输出),助理是回头看结论的地方。
/// 枚举顺序与 `IndexedStack.children` 必须一一对应,改这里要同时改 `app.dart`。
///
/// v2.11(用户 10/5:"前端非常单一…非常单调平庸"):给这一条加了**轻动效**。
/// 为什么只加三样、不加更多:
/// - 选中项上方一条 **2px 指示条**(220ms 淡入,`Motion.transition`)——
///   底栏是全天可见的一条,没有指示条时"现在在哪一栏"只能靠颜色深浅猜;
/// - 图标 26 → 27 的**微缩放**与文字字重变化(不弹跳、不旋转,免得廉价);
/// - 点按**一次轻触觉**(`HapticFeedback.selectionClick`),只在真的换栏时触发。
/// 没加:粒子、彩虹色、图标位移动画 —— 用户的要求是"高级但不眼花缭乱"。
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).bottomNavigationBarTheme.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.camera_alt_outlined,
                activeIcon: Icons.camera_alt,
                label: '输入',
                isActive: currentTab == ReadFlowTab.input,
                // 已经在这一栏就不要再触发(否则"点了没反应"还烫一次手)
                onTap: () => _select(context, ReadFlowTab.input),
                indicatorColor: cs.primary,
              ),
              _NavItem(
                icon: Icons.auto_stories_outlined,
                activeIcon: Icons.auto_stories,
                label: '输出',
                isActive: currentTab == ReadFlowTab.output,
                onTap: () => _select(context, ReadFlowTab.output),
                indicatorColor: cs.primary,
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: '我的',
                isActive: currentTab == ReadFlowTab.profile,
                onTap: () => _select(context, ReadFlowTab.profile),
                indicatorColor: cs.primary,
              ),
              _NavItem(
                icon: Icons.assistant_outlined,
                activeIcon: Icons.assistant,
                label: '学习助理',
                isActive: currentTab == ReadFlowTab.tutor,
                onTap: () => _select(context, ReadFlowTab.tutor),
                indicatorColor: cs.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(BuildContext context, ReadFlowTab tab) {
    if (tab == currentTab) return;
    // 轻触觉:只在真的换栏时给（内容已在 navigate 前于 app.dart 切 IndexedStack）
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
  final Color indicatorColor;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.indicatorColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isActive
        ? cs.primary
        // 未选中项用主题的次要文字色:旧写法是 onSurface 40% 透明,
        // 浅色下只有 ~3:1,底部标签(11px)看着发灰
        : cs.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 指示条:选中才出现,220ms 淡入 + 高度从 0 到 2(不占位变化,避免底栏跳动)
            AnimatedContainer(
              duration: Motion.transition,
              curve: Motion.curve,
              height: 2,
              width: isActive ? 22 : 0,
              margin: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                color: indicatorColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 图标:选中 27 / 未选 26 —— 差 1px 只用来"有种轻微抬起来的感觉",
            // 不做弹跳/旋转(用户要求克制)
            AnimatedScale(
              duration: Motion.transition,
              curve: Motion.curve,
              scale: isActive ? 1.06 : 1.0,
              child: Icon(isActive ? activeIcon : icon, size: 26, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: AppFont.micro + 0.5,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
