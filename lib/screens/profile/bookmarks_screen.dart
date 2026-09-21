import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../models/bookmark.dart';
import '../../providers/bookmark_provider.dart';
import '../../widgets/confirm_destructive.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';

/// 收藏夹页(v1.4.0 问题 9):收集追问洞见与好句子,
/// 独立于生词本,不参与词汇统计。点击看全文,长按/星标删除。
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

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
        hint: '在追问回答顶部或词汇卡片上点 ☆ 即可收藏',
      );
    }
    return ListView.separated(
      key: const ValueKey('bookmarks-list'),
      padding: const EdgeInsets.all(12),
      itemCount: bp.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final b = bp.items[i];
        return _BookmarkCard(bookmark: b);
      },
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final Bookmark bookmark;

  const _BookmarkCard({required this.bookmark});

  String _sourceLabel(BuildContext context) {
    if (bookmark.source == AppConstants.bookmarkSourceVocab) return '词汇';
    return '追问';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVocab = bookmark.source == AppConstants.bookmarkSourceVocab;
    final sourceColor =
        isVocab ? Colors.purple[300]! : const Color(0xFF4A90D9);

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
                isVocab ? Icons.bookmark : Icons.chat_bubble_outline,
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
                      // P2-31:正文灰阶对比度 <4.5:1,提到 grey[600] 达 WCAG AA
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bookmark.content.length > 80
                          ? '${bookmark.content.substring(0, 80)}…'
                          : bookmark.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey[400]),
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
