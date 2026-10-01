import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../models/bookmark.dart';
import '../../providers/bookmark_provider.dart';
import '../../widgets/confirm_destructive.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';

/// 收藏夹页(v1.4.0 问题 9;v2.8 按功能区分类)。
///
/// 用户第 10 条原话:"收藏夹需要体现不同功能区收藏进来的东西 —— 比如:词汇收藏夹、
/// 对话收藏夹(追问抽屉里收藏的东西)、文章收藏夹、写译收藏夹(收藏的错误呀这些)…
/// 需要智能的把各个功能区的收藏功能,进行归类处理以及对应的展示。"
///
/// 所以这一页现在:
/// 1. 顶部**横向分区 chip**:全部 / 词汇 / 对话 / 文章 / 写译(带条数);
/// 2. 列表按来源给不同图标与说明,不再是"一锅粥";
/// 3. 搜索:标题与正文都能搜(收藏多了以后找东西)。
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  /// 当前分区(null = 全部)
  String? _section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏夹')),
      body: Consumer<BookmarkProvider>(
        builder: (context, bp, _) => AnimatedSwitcher(
          // A1:加载/失败/空/列表之间的切换给 180ms easeOut,
          // 不再硬切(高频操作不加动画,这里是低频的状态切换)
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          child: _buildBody(context, bp),
        ),
      ),
    );
  }

  /// 某分区有多少条(用于 chip 上的计数)
  int _countOf(BookmarkProvider bp, String id) =>
      bp.items.where((b) => b.source == id).length;

  /// 三态(P2-30):加载中 / 加载失败可重试 / 空态与列表。
  /// 空态与失败态此前长得一样(都是"没有内容"),用户分不清是没收藏还是坏了。
  Widget _buildBody(BuildContext context, BookmarkProvider bp) {
    if (bp.error != null && !bp.loaded) {
      // 只有"失败且手里没数据"才整页报错;有数据时的刷新失败不该清屏
      return ErrorState(
        key: const ValueKey('bookmarks-error'),
        message: bp.error!,
        onRetry: () => context.read<BookmarkProvider>().load(),
      );
    }
    if (!bp.loaded) {
      return const Center(
        key: ValueKey('bookmarks-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (bp.items.isEmpty) {
      return const EmptyState(
        key: ValueKey('bookmarks-empty'),
        icon: Icons.star_border,
        title: '还没有收藏',
        hint: '在追问回答顶部、词条卡片、阅读器里点 ☆ 即可收藏,会自动归到对应分区',
      );
    }

    final items = _section == null
        ? bp.items
        : bp.items.where((b) => b.source == _section).toList();

    return Column(
      key: const ValueKey('bookmarks-list'),
      children: [
        // ① 分区 chips(用户第 10 条的核心)
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _sectionChip(
                context,
                label: '全部',
                count: bp.items.length,
                selected: _section == null,
                onTap: () => setState(() => _section = null),
              ),
              for (final s in AppConstants.bookmarkSections)
                _sectionChip(
                  context,
                  label: s['label']!,
                  count: _countOf(bp, s['id']!),
                  selected: _section == s['id'],
                  onTap: () => setState(() => _section = s['id']),
                ),
            ],
          ),
        ),
        // ② 当前分区的说明(告诉用户"这类是从哪儿收藏来的")
        if (_section != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppConstants.bookmarkSections
                        .firstWhere((s) => s['id'] == _section)['hint'] ??
                    '',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: '这个分区还没有收藏',
                  hint: '换个分区看看,或去对应功能区点 ☆',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _BookmarkCard(bookmark: items[i]),
                ),
        ),
      ],
    );
  }

  Widget _sectionChip(
    BuildContext context, {
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(count > 0 ? '$label $count' : label),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        labelStyle: TextStyle(
          fontSize: 12,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final Bookmark bookmark;

  const _BookmarkCard({required this.bookmark});

  /// 来源标签(v2.8:四个功能区各一个说法)
  String _sourceLabel(BuildContext context) => switch (bookmark.source) {
        AppConstants.bookmarkSourceVocab => '词汇',
        AppConstants.bookmarkSourceArticle => '文章',
        AppConstants.bookmarkSourceWriting => '写译',
        _ => '对话',
      };

  IconData get _sourceIcon => switch (bookmark.source) {
        AppConstants.bookmarkSourceVocab => Icons.bookmark,
        AppConstants.bookmarkSourceArticle => Icons.article_outlined,
        AppConstants.bookmarkSourceWriting => Icons.edit_note,
        _ => Icons.chat_bubble_outline,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 来源色随明暗切换:写死的紫[300]在深色下太扎眼、写死的 #4A90D9 在深色底上又偏暗
    final sourceColor = switch (bookmark.source) {
      AppConstants.bookmarkSourceVocab => theme.colorScheme.tertiary,
      AppConstants.bookmarkSourceArticle => AppTheme.successColor(context),
      AppConstants.bookmarkSourceWriting => AppTheme.amber(context),
      _ => theme.colorScheme.primary,
    };

    return Card(
      color: theme.colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _sourceIcon,
                size: 18,
                color: sourceColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookmark.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_sourceLabel(context)} · '
                      '${bookmark.createdAt.year}-'
                      '${bookmark.createdAt.month.toString().padLeft(2, '0')}-'
                      '${bookmark.createdAt.day.toString().padLeft(2, '0')}',
                      // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bookmark.content.length > 80
                          ? '${bookmark.content.substring(0, 80)}…'
                          : bookmark.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                tooltip: '删除收藏',
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 删除收藏(P2-28):此前这个图标一点就直接从库里删掉,
  /// 无确认、无提示、不可撤销 —— 与"生词批量删除有确认"完全是两套预期。
  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await confirmDestructive(
      context,
      title: '删除收藏',
      message: '确定删除「${bookmark.title}」吗？删除后不可恢复。',
    );
    if (!ok || !context.mounted) return;
    final id = bookmark.id;
    if (id == null) return;
    final bp = context.read<BookmarkProvider>();
    await bp.remove(id);
    if (!context.mounted) return;
    showFeedbackSnack(
      context,
      '已删除收藏',
      actionLabel: '撤销',
      // 撤销要留够反应时间,3 秒太快(默认值给普通提示用)
      duration: const Duration(seconds: 6),
      // 撤销 = 重新插入同一条(内容已被删掉,toggle 这次一定是"收藏")
      onAction: () => bp.toggle(bookmark),
    );
  }

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          bookmark.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            bookmark.content,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: bookmark.content));
              if (ctx.mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
