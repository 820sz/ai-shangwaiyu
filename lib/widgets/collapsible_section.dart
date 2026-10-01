import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import '../config/design_tokens.dart';

/// 区块的显示状态(v2.9,用户 10/2 第 3(1) 条)
enum SectionState {
  open('展开'),
  closed('收起'),
  hidden('已隐藏');

  const SectionState(this.label);
  final String label;
}

/// 「材料中心」这类长页面的**区块记忆**(展开 / 收起 / 隐藏)。
///
/// 用户原话:"现在这些子功能每一个功能都展示得太满了,**没有收起和隐藏这些基本逻辑**,
/// 导致现在得往下翻半天,才能把每个子功能给的东西划完,才能看得下一个功能区。"
///
/// 所以每个区块都能:点标题收起/展开、从菜单里**隐藏**、在「区块管理」里恢复。
/// 状态存 Hive,退出再进来还是他上次的布局。
class UiSectionPrefs {
  static Map<String, SectionState> load() {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings)
          .get(AppConstants.keyUiSections);
      if (raw is String && raw.trim().isNotEmpty) {
        final out = <String, SectionState>{};
        for (final kv in raw.split('&')) {
          final i = kv.indexOf('=');
          if (i <= 0) continue;
          final id = kv.substring(0, i);
          final v = kv.substring(i + 1);
          final state = SectionState.values
              .where((s) => s.name == v)
              .cast<SectionState?>()
              .firstWhere((s) => s != null, orElse: () => null);
          if (state != null) out[id] = state;
        }
        return out;
      }
    } catch (e) {
      debugPrint('ReadFlow 读取区块状态失败(用默认): $e');
    }
    return {};
  }

  static Future<void> save(Map<String, SectionState> map) async {
    try {
      final encoded = map.entries.map((e) => '${e.key}=${e.value.name}').join('&');
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyUiSections, encoded);
    } catch (e) {
      debugPrint('ReadFlow 保存区块状态失败: $e');
    }
  }
}

/// 一个可收起 / 可隐藏的区块(v2.9)。
///
/// 用法:
/// ```dart
/// CollapsibleSection(
///   id: 'discover',
///   title: '发现更多',
///   subtitle: '按题材找:公版书 + 论文 + 外媒三路并行',
///   trailing: TextButton(...),
///   child: ...,
/// )
/// ```
/// - 收起时**不构建 child**(长页面滚动才不卡,也真的省高度);
/// - 隐藏后整块消失,靠页面右上角「区块管理」恢复;
/// - 状态由 [SectionPrefsScope] 统一持有,一次改动全局生效(不各写一份 Hive 读)。
class CollapsibleSection extends StatelessWidget {
  final String id;

  /// 显示名(区块管理里也用这个名字)
  final String title;
  final String? subtitle;

  /// 标题右边的动作(如"检测可用源"按钮)
  final Widget? trailing;

  /// 标题左边的图标(可选)
  final IconData? icon;

  final Widget child;

  /// 收起时仍显示的一行摘要(让用户知道里面有什么)
  final String? collapsedHint;

  const CollapsibleSection({
    super.key,
    required this.id,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.icon,
    this.collapsedHint,
  });

  @override
  Widget build(BuildContext context) {
    final prefs = SectionPrefsScope.of(context);
    final state = prefs.stateOf(id);
    if (state == SectionState.hidden) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final open = state == SectionState.open;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行:点标题区即可收放(整行可点,不用瞄准小箭头)
          InkWell(
            borderRadius: Radii.controlRadius,
            onTap: () => prefs.toggle(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.xs, horizontal: 2),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: open ? 0 : -0.25,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: open ? theme.colorScheme.onSurface : muted,
                    ),
                  ),
                  const SizedBox(width: Gap.xxs),
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (open && (subtitle ?? '').isNotEmpty)
                          Text(
                            subtitle!,
                            style: TextStyle(fontSize: 11.5, color: muted),
                          )
                        else if (!open && (collapsedHint ?? subtitle ?? '').isNotEmpty)
                          Text(
                            collapsedHint ?? subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: muted),
                          ),
                      ],
                    ),
                  ),
                  if (open && trailing != null) trailing!,
                  // 隐藏:菜单里的第二级动作,不抢视觉
                  PopupMenuButton<String>(
                    tooltip: '区块设置',
                    icon: Icon(Icons.more_horiz, size: 18, color: muted),
                    onSelected: (v) {
                      switch (v) {
                        case 'close':
                          prefs.set(id, SectionState.closed);
                        case 'open':
                          prefs.set(id, SectionState.open);
                        case 'hide':
                          prefs.hide(id);
                      }
                    },
                    itemBuilder: (_) => [
                      if (open)
                        const PopupMenuItem(value: 'close', child: Text('收起这个区块'))
                      else
                        const PopupMenuItem(value: 'open', child: Text('展开这个区块')),
                      const PopupMenuItem(value: 'hide', child: Text('隐藏(在「区块管理」里可恢复)')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 收起时不构建 child:长列表(图文卡片)真的省掉,不是视觉折叠
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open ? child : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// 区块状态的持有者(页面级一处即可)
class SectionPrefsScope extends InheritedNotifier<SectionPrefsNotifier> {
  const SectionPrefsScope({
    super.key,
    required SectionPrefsNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  static SectionPrefsNotifier of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<SectionPrefsScope>();
    assert(scope != null, 'CollapsibleSection 必须放在 SectionPrefsScope 里');
    return scope!.notifier!;
  }

  static SectionPrefsNotifier? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SectionPrefsScope>()
      ?.notifier;
}

class SectionPrefsNotifier extends ChangeNotifier {
  final Map<String, SectionState> _map;
  SectionPrefsNotifier(this._map);

  SectionState stateOf(String id) => _map[id] ?? SectionState.open;

  bool isHidden(String id) => stateOf(id) == SectionState.hidden;

  void toggle(String id) {
    _map[id] =
        stateOf(id) == SectionState.open ? SectionState.closed : SectionState.open;
    _persist();
  }

  void set(String id, SectionState state) {
    _map[id] = state;
    _persist();
  }

  void hide(String id) => set(id, SectionState.hidden);

  void show(String id) => set(id, SectionState.open);

  void _persist() {
    notifyListeners();
    UiSectionPrefs.save(_map);
  }
}
