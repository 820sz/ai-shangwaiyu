import 'package:flutter/material.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../services/theme_controller.dart';

/// 外观设置(v2.2 深色模式)。
///
/// 为什么单独一个页面而不是塞进「学习偏好」:那个页面是**学习策略**
/// (每天多少分钟、屏蔽哪些题材),外观是**设备/环境**层面的选择,
/// 混在一起两个都找不着。
///
/// 页面自己带预览:用户不用退出设置页再判断"深色到底长什么样"。
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.mode,
        builder: (context, mode, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              '「跟随系统」会随手机的深色开关自动切换(系统设了夜间自动切换时也生效)。',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 8),
            // Flutter 3.32+ 用 RadioGroup 统一管理组值(RadioListTile 的
            // groupValue/onChanged 已废弃)
            RadioGroup<ThemeMode>(
              groupValue: mode,
              onChanged: (v) {
                if (v != null) ThemeController.set(v);
              },
              child: Column(
                children: [
                  for (final entry in AppConstants.themeModeOptions.entries)
                    RadioListTile<ThemeMode>(
                      value: AppTheme.themeModeOf(entry.key),
                      title: Text(entry.value),
                      subtitle: entry.key == 'dark'
                          ? Text(
                              '深底浅字,夜间/弱光下更省眼',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: muted),
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _ThemePreview(),
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('说明',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      '· 深色模式改的是**全局配色**(页面、卡片、正文、阅读页都跟着变),'
                      '不是只换个背景色;\n'
                      '· 彩色标签(生词类型、掌握度、图表)在两种模式下都保留颜色 —— '
                      '它们承担"区分"的信息,不能变成灰;\n'
                      '· 主题偏好会记在本机,重装/换机后需要重新选一次。',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 静态预览:用**当前主题**画一张小卡片,让用户在页面里直接看到效果
class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '预览:Prefrontal cortex',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.volume_up_outlined,
                    size: 18, color: theme.colorScheme.primary),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '/ˌpriːˈfrʌntəl ˈkɔːteks/ n. 前额叶皮层',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 10),
            Text(
              'The prefrontal cortex handles planning and self-control.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(onPressed: () {}, child: const Text('认识')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () {}, child: const Text('模糊')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
