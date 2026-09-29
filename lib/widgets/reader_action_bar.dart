import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import '../config/design_tokens.dart';
import '../config/theme.dart';
import '../services/api_endpoint.dart';
import '../services/doubao_api.dart' show primaryModelChoices;

/// 阅读器底部动作栏(v2.7,用户第 3 条)。
///
/// 用户原话:"多功能分析(翻译、文本处理…等快捷功能键 —— 快捷键位置位于该功能
/// 进入后的界面下方(就跟原来的拍照识别进入后下方的「模型、保存、追问」的 ui
/// 位置一样)"。所以这一条**照搬拍照识图页底部栏的形态**(同样的芯片样式、
/// 同样的"保存"C 位、同样的高度),只把功能换成阅读需要的:
///
/// `[模型 ▾] [翻译] [保存(N)] [追问] [更多 ▾]` + 上一行「收词存到 …  改」。
///
/// 为什么把模型选择放进阅读器:翻译、点词讲解、追问都走同一个模型,
/// 用户在哪儿读就在哪儿换 —— 不必退回首页切完再进来。
class ReaderActionBar extends StatelessWidget {
  /// 是否已开启逐段翻译(高亮显示)
  final bool translating;

  /// 切换逐段翻译
  final VoidCallback onToggleTranslation;

  /// 本次阅读收了多少个词(显示在"保存"按钮上)
  final int pickedCount;

  /// 把本次收的词再确认一遍(保存/查看)
  final VoidCallback onSave;

  /// 打开追问抽屉
  final VoidCallback onFollowUp;

  /// 「更多」菜单里的动作
  final List<ReaderMoreAction> moreActions;

  /// 收词保存位置的说明(如「书籍 / 红楼梦 · p33」)
  final String saveTargetLabel;

  /// 改保存位置(分类 / 材料名 / 页码)
  final VoidCallback onChangeTarget;

  /// 换了模型/思考档后通知页面重建(否则菜单里的勾还停在旧值)
  final VoidCallback? onModelChanged;

  const ReaderActionBar({
    super.key,
    required this.translating,
    required this.onToggleTranslation,
    required this.pickedCount,
    required this.onSave,
    required this.onFollowUp,
    required this.moreActions,
    required this.saveTargetLabel,
    required this.onChangeTarget,
    this.onModelChanged,
  });

  /// 当前模型(Hive 实时读;与拍照识图页共用同一份设置)
  static String get currentModel {
    final v = Hive.box(AppConstants.hiveBoxSettings)
        .get(AppConstants.keyDoubaoModel);
    return (v is String && v.isNotEmpty) ? v : AppConstants.doubaoVisionModel;
  }

  static String get currentThinking => ApiEndpointConfig.primary.thinking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 保存位置(第 3 条"选择保存位置"):默认跟着材料走,随时可改
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xxs, Gap.xs, 0),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: Gap.xxs),
                Expanded(
                  child: Text(
                    '收词存到:$saveTargetLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onChangeTarget,
                  child: const Text('改', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                // 模型 + 思考档(与拍照识图页同一个弹出菜单)
                Flexible(
                  flex: 2,
                  child: _ModelMenu(
                    theme: theme,
                    onChanged: onModelChanged,
                  ),
                ),
                const SizedBox(width: 4),

                // 翻译(第 2(2) 条的核心按钮)
                Flexible(
                  flex: 2,
                  child: ActionChip(
                    avatar: Icon(
                      translating ? Icons.translate : Icons.translate_outlined,
                      size: 16,
                      color: translating ? cs.primary : cs.onSurfaceVariant,
                    ),
                    label: Text(
                      '翻译',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface,
                        fontWeight:
                            translating ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    onPressed: onToggleTranslation,
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        translating ? cs.primary.withAlpha(20) : cs.surface,
                    side: BorderSide(
                      color: translating ? cs.primary : cs.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // 保存(C 位)
                Flexible(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    label: Text(
                      pickedCount > 0 ? '已收($pickedCount)' : '收词',
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // 追问
                Flexible(
                  flex: 2,
                  child: ActionChip(
                    avatar: Icon(Icons.chat_bubble_outline,
                        size: 16, color: cs.primary),
                    label: Text('追问',
                        style: TextStyle(fontSize: 12, color: cs.onSurface)),
                    onPressed: onFollowUp,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: cs.surface,
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                ),

                // 更多(阅读设置 / 听写 / 导出 / 原文链接 / 读完)
                if (moreActions.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: '更多',
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_vert,
                        size: 20, color: cs.onSurfaceVariant),
                    onSelected: (v) {
                      for (final a in moreActions) {
                        if (a.id == v) {
                          a.onSelected();
                          return;
                        }
                      }
                    },
                    itemBuilder: (_) => [
                      for (final a in moreActions)
                        PopupMenuItem(
                          value: a.id,
                          height: 38,
                          child: Row(
                            children: [
                              Icon(a.icon, size: 17, color: cs.onSurfaceVariant),
                              const SizedBox(width: Gap.xs),
                              Text(a.label, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 「更多」菜单里的一项
class ReaderMoreAction {
  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  const ReaderMoreAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelected,
  });
}

/// 模型 + 思考档位弹出菜单(与拍照识图页同一套视觉与 Hive 键)
class _ModelMenu extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback? onChanged;

  const _ModelMenu({required this.theme, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final model = ReaderActionBar.currentModel;
    final thinking = ReaderActionBar.currentThinking;
    return PopupMenuButton<String>(
      offset: const Offset(0, -360),
      padding: EdgeInsets.zero,
      itemBuilder: (_) => [
        ...primaryModelChoices().map((m) {
          final isSel = m == model;
          return PopupMenuItem(
            value: 'model:$m',
            height: 32,
            child: Row(
              children: [
                if (isSel)
                  Icon(Icons.check, size: 16, color: AppTheme.successColor(context))
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    m,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                      color: isSel ? AppTheme.successColor(context) : null,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const PopupMenuDivider(),
        ...AppConstants.thinkingOptionsFor(model).entries.map((e) {
          final isSel = e.key == thinking;
          return PopupMenuItem(
            value: 'think:${e.key}',
            height: 32,
            child: Row(
              children: [
                Icon(
                  isSel ? Icons.lightbulb : Icons.lightbulb_outline,
                  size: 14,
                  color: isSel
                      ? AppTheme.warningColor(context)
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                    color: isSel ? AppTheme.warningColor(context) : null,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
      onSelected: (v) async {
        if (v.startsWith('model:')) {
          await Hive.box(AppConstants.hiveBoxSettings)
              .put(AppConstants.keyDoubaoModel, v.substring(6));
        } else if (v.startsWith('think:')) {
          await Hive.box(AppConstants.hiveBoxSettings)
              .put(AppConstants.keyDoubaoThinking, v.substring(6));
        }
        // 菜单自己是 StatelessWidget,换了模型要让页面重建 —— 否则菜单里的勾
        // 还停在旧值,用户会以为"点了没生效"
        onChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.model_training,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                '模型',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Icon(Icons.arrow_drop_up,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
