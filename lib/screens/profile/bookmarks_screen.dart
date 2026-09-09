import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../models/bookmark.dart';
import '../../providers/bookmark_provider.dart';

/// 收藏夹页(v1.4.0 问题 9):收集追问洞见与好句子,
/// 独立于生词本,不参与词汇统计。点击看全文,长按/星标删除。
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('收藏夹')),
      body: Consumer<BookmarkProvider>(
        builder: (context, bp, _) {
          if (!bp.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (bp.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_border, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text(
                    '还没有收藏\n在追问回答顶部或词汇卡片上点 ☆ 即可收藏',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: bp.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = bp.items[i];
              return _BookmarkCard(bookmark: b);
            },
          );
        },
      ),
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
                      style: TextStyle(fontSize: 10, color: Colors.grey[400]),
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
                onPressed: () =>
                    context.read<BookmarkProvider>().remove(bookmark.id!),
              ),
            ],
          ),
        ),
      ),
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
