import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../../../config/constants.dart';
import '../../../models/bookmark.dart';
import '../../../providers/bookmark_provider.dart';
import 'follow_up_models.dart';

/// 追问 AI 气泡:模型标签 + 可折叠思考过程 + Markdown 渲染正文。
/// 本地状态承载思考折叠——流式更新重建气泡时状态保留。
///
/// 原为 process_chat.dart 私有类(2026-08-10 拆分重构),跨文件使用故公开。
class AiFollowUpBubble extends StatefulWidget {
  final FollowUpMessage message;
  final Widget avatar;

  const AiFollowUpBubble({
    super.key,
    required this.message,
    required this.avatar,
  });

  @override
  State<AiFollowUpBubble> createState() => _AiFollowUpBubbleState();
}

class _AiFollowUpBubbleState extends State<AiFollowUpBubble> {
  bool _thinkingExpanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = widget.message;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.avatar,
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              // 宽气泡:充分利用抽屉横向空间,缓解 Markdown 表格换行错位
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.88,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 模型名标签 + 收藏星标(流式完成后显示,v1.4.0 问题 8)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        if (msg.model != null)
                          Expanded(
                            child: Text(
                              msg.model!,
                              style: TextStyle(
                                fontSize: 10,
                                // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        if (!msg.streaming && msg.content.isNotEmpty)
                          _AiBookmarkStar(message: msg),
                      ],
                    ),
                  ),
                  // 思考过程（可折叠，标题条点击切换）
                  if (msg.reasoningText != null &&
                      msg.reasoningText!.isNotEmpty)
                    ThinkingBlock(
                      text: msg.reasoningText!,
                      expanded: _thinkingExpanded,
                      streaming: msg.streaming,
                      onToggle: () => setState(
                        () => _thinkingExpanded = !_thinkingExpanded,
                      ),
                    ),
                  // 正文（Markdown 渲染：标题/加粗/表格/列表层级清晰）
                  // v1.4.0 问题 7:SelectionArea 自定义工具栏——
                  // 长按选择后有「复制」和「取消选择」(用户实测:选完只能按返回键)
                  if (msg.content.isNotEmpty)
                    SelectionArea(
                      contextMenuBuilder: (context, state) {
                        // 自定义工具栏:复制全部 + 取消选择
                        // (用户实测:系统选择后没有"叉",只能按返回键)
                        final items = <ContextMenuButtonItem>[
                          ContextMenuButtonItem(
                            label: '复制全部',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: msg.content),
                              );
                              state.hideToolbar();
                            },
                          ),
                          ContextMenuButtonItem(
                            label: '取消选择',
                            onPressed: () {
                              state.hideToolbar();
                              state.clearSelection();
                            },
                          ),
                        ];
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: state.contextMenuAnchors,
                          buttonItems: items,
                        );
                      },
                      child: MarkdownBody(
                        data: msg.content,
                        selectable: false,
                        styleSheet: MarkdownStyleSheet.fromTheme(
                          theme,
                        ).copyWith(
                          p: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            height: 1.5,
                            color: theme.colorScheme.onSurface,
                          ),
                          h1: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          h2: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          h3: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          strong: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                          tableBorder: TableBorder.all(
                            color: theme.colorScheme.outlineVariant,
                            width: 0.5,
                          ),
                          tableHead: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                          tableBody: TextStyle(fontSize: 12, height: 1.4),
                          tableCellsPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          blockquote: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                          code: TextStyle(
                            fontSize: 12,
                            // 深色下 deepOrange[700] 偏暗,浅色下也用主题的 error 系更统一
                            color: theme.colorScheme.tertiary,
                            fontFamily: 'monospace',
                          ),
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (msg.streaming)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '正在思考…',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      '（AI 未返回内容）',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 追问回答的收藏星标:点击收藏/取消收藏该条回答(v1.4.0 问题 8)
class _AiBookmarkStar extends StatelessWidget {
  final FollowUpMessage message;

  const _AiBookmarkStar({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<BookmarkProvider>(
      builder: (ctx, bp, _) {
        final content = message.content;
        final saved = bp.isBookmarked(
          AppConstants.bookmarkSourceFollowUp,
          content,
        );
        return InkWell(
          onTap: () async {
            final title = content
                .split('\n')
                .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
                .trim();
            final nowSaved = await bp.toggle(
              Bookmark(
                source: AppConstants.bookmarkSourceFollowUp,
                title: title.length > 60 ? title.substring(0, 60) : title,
                content: content,
                model: message.model,
              ),
            );
            // await 后按真实结果提示(v1.4.2 修复提示相反)
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(nowSaved ? '已收藏到收藏夹' : '已取消收藏'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(
              saved ? Icons.star : Icons.star_border,
              size: 16,
              color: saved ? Colors.amber[700] : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

/// 可折叠思考过程块：标题条点击切换展开/收起；展开时限制高度可滚动
class ThinkingBlock extends StatelessWidget {
  final String text;
  final bool expanded;
  final bool streaming;
  final VoidCallback onToggle;

  const ThinkingBlock({
    super.key,
    required this.text,
    required this.expanded,
    required this.streaming,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题条
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  const Text('💭', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text(
                    streaming ? '思考过程（生成中）' : '思考过程',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.orange[600],
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange[400],
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
