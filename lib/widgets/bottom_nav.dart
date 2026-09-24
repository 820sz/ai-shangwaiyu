import 'package:flutter/material.dart';

/// 底部导航。v2.2 起四栏顺序为:**输入 / 输出 / 我的 / 学习助理** ——
/// 用户真机实测后的调整:学习助理(原「导师」)从最左挪到最右,
/// 因为日常最常做的是"拍/读/写"(输入与输出),助理是回头看结论的地方。
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
                onTap: () => onTabChanged(ReadFlowTab.input),
              ),
              _NavItem(
                icon: Icons.auto_stories_outlined,
                activeIcon: Icons.auto_stories,
                label: '输出',
                isActive: currentTab == ReadFlowTab.output,
                onTap: () => onTabChanged(ReadFlowTab.output),
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: '我的',
                isActive: currentTab == ReadFlowTab.profile,
                onTap: () => onTabChanged(ReadFlowTab.profile),
              ),
              _NavItem(
                icon: Icons.assistant_outlined,
                activeIcon: Icons.assistant,
                label: '学习助理',
                isActive: currentTab == ReadFlowTab.tutor,
                onTap: () => onTabChanged(ReadFlowTab.tutor),
              ),
            ],
          ),
        ),
      ),
    );
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
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        // 未选中项用主题的次要文字色:旧写法是 onSurface 40% 透明,
        // 浅色下只有 ~3:1,底部标签(11px)看着发灰
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isActive ? activeIcon : icon, size: 26, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
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
