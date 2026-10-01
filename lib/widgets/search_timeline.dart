import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../config/theme.dart';
import '../services/original_search.dart';
import 'waiting.dart';

/// 检索过程的**流式时间线**(v2.8,用户第 6(4) 条)。
///
/// 用户原话:"找材料时,要有像 ai 软件网页版那样,能看到'查阅了 xxx'这种流式输出!
/// 现在所有搜索材料,进去都是非常单一简略的转圈等待"。
///
/// 这里只负责渲染 —— 每一条都是后端**真实发生**的事(哪个源、通没通、几条、
/// 用时多久),没有假进度条:用户看到"NPR:没连上"就知道是网络而不是 App 坏了。
/// 材料中心与分类页共用。
class SearchTimeline extends StatelessWidget {
  final List<SearchEvent> events;

  /// 是否还在检索(尾部显示一个转圈)
  final bool loading;

  const SearchTimeline({
    super.key,
    required this.events,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty && !loading) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(150),
        borderRadius: Radii.controlRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < events.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == events.length - 1 ? 0 : 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    events[i].icon,
                    size: 14,
                    color: switch (events[i].stage) {
                      SearchStage.sourceFailed => AppTheme.warningColor(context),
                      SearchStage.done => AppTheme.successColor(context),
                      _ => theme.colorScheme.primary,
                    },
                  ),
                  const SizedBox(width: Gap.xxs + 2),
                  Expanded(
                    child: Text(
                      events[i].label,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: events[i].stage == SearchStage.done
                            ? theme.colorScheme.onSurface
                            : muted,
                        fontWeight: events[i].stage == SearchStage.done
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (events[i].total > 0 &&
                      events[i].done > 0 &&
                      events[i].done <= events[i].total)
                    Text(
                      '${events[i].done}/${events[i].total}',
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                ],
              ),
            ),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: const ThinkingDots(label: '还在检索', compact: true),
            ),
        ],
      ),
    );
  }
}
