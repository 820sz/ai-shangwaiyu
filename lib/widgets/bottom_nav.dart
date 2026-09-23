import 'package:flutter/material.dart';

/// 底部导航。v2.0 起四栏:**导师 / 输入 / 输出 / 我的** ——
/// 导师排第一是产品决策(PLAN-2.0 §8):个性化学习系统的每日入口应该是
/// "今天学什么",而不是"上传图片"。其余三栏保持原有工具属性不变。
enum ReadFlowTab { tutor, input, output, profile }

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
                icon: Icons.assistant_outlined,
                activeIcon: Icons.assistant,
                label: '导师',
                isActive: currentTab == ReadFlowTab.tutor,
                onTap: () => onTabChanged(ReadFlowTab.tutor),
              ),
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
        : Theme.of(context).colorScheme.onSurface.withAlpha(100);

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
