import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 模型名标签
                  if (msg.model != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        msg.model!,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[500],
                        ),
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
                  if (msg.content.isNotEmpty)
                    MarkdownBody(
                      data: msg.content,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        theme,
                      ).copyWith(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          height: 1.5,
                          color: Colors.grey[800],
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
                          color: Colors.black87,
                        ),
                        tableBorder: TableBorder.all(
                          color: Colors.grey.shade300,
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
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                        code: TextStyle(
                          fontSize: 12,
                          color: Colors.deepOrange[700],
                          fontFamily: 'monospace',
                        ),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.grey[300]!, width: 1),
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
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Text(
                      '（AI 未返回内容）',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
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
