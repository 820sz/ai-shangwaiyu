import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../../../config/constants.dart';
import '../../../config/design_tokens.dart';
import '../../../config/theme.dart';
import '../../../config/v4_theme.dart';
import '../../../models/bookmark.dart';
import '../../../providers/bookmark_provider.dart';
import '../../../widgets/waiting.dart';
import '../../../widgets/whale_thinking.dart';
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
    final skin = V4Skin.of(context);
    final msg = widget.message;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
              // v4(2026-11-03):AI 气泡从"灰底方角"改成"白卡果冻":
              // 浅色下白 > 页面底,深色下用 skin.surface;思考块/正文/光标
              // 三级信息靠底色与间距分层,不再靠更多颜色。
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: skin.shadow,
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
                                fontWeight: FontWeight.w700,
                                color: skin.inkFaint,
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
                  //
                  // v2.4 修复(A4,用户反馈"只有复制全部和不复制两个选择"):
                  // 原来的自定义菜单把**系统默认的「复制」换掉了**,于是选中一段
                  // 文字反而复制不了那一段。现在先把平台默认项(复制/全选/分享)
                  // 原样接回来 —— "选中哪段复制哪段"就是系统行为 ——
                  // 再补两项:「复制整条」与「取消选择」。
                  if (msg.content.isNotEmpty)
                    SelectionArea(
                      contextMenuBuilder: (context, state) {
                        final items = <ContextMenuButtonItem>[
                          ...state.contextMenuButtonItems,
                          ContextMenuButtonItem(
                            label: '复制整条',
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
                        // 让 Markdown 文本参与外层 SelectionArea 的选择
                        // (此前设成 false,选中范围拿不到内容 → 只能"复制整条")
                        selectable: true,
                        styleSheet: calmMarkdownSheet(theme),
                      ),
                    )
                  else if (msg.streaming)
                    // 流式回答还没吐出第一个字:用三点跳动 + "正在思考…"。
                    // 原来是一个 14×14 的转圈(太小,且违反项目铁律);
                    // ThinkingDots 把文字和点画在同一行,高度与原 Text 基本一致。
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: ThinkingDots(label: '正在思考…'),
                    )
                  else
                    Text(
                      '（AI 未返回内容）',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  // 流式光标 + "生成中":用户随时知道"还在写"以及"写到哪了"。
                  // 停止按钮不放在气泡里 —— 那是输入栏的职责(避免气泡里出现
                  // 会随重渲染闪烁的操作),这里只做状态指示。
                  if (msg.streaming && msg.content.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: <Widget>[
                          const _StreamingCaret(),
                          const SizedBox(width: 6),
                          Text(
                            '生成中…',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: skin.accent,
                            ),
                          ),
                        ],
                      ),
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

/// 流式光标:一条随主色呼吸的细竖线(不做夸张闪烁,避免"眼花缭乱")
class _StreamingCaret extends StatefulWidget {
  const _StreamingCaret();

  @override
  State<_StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<_StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: 0.35 + _c.value * 0.65,
        child: Container(
          width: 2.5,
          height: 14,
          decoration: BoxDecoration(
            color: skin.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
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
              color: saved
                  ? AppTheme.amber(context)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}

/// 可折叠思考过程块(v4,2026-11-03 重做)。
///
/// 变化:
/// - 💭 emoji → **鲸鱼尾**(用户指定的"思考中"形象,与全 App 一致);
/// - 暖黄底 → 果冻淡染卡(淡紫),深/浅色主题都走 skin;
/// - 流式时标题显示 **"思考中 · Ns"** 计时,让"它在想"这件事可感知;
/// - 展开区底部做渐隐,暗示"还有内容、可继续读"(而不是硬截断)。
class ThinkingBlock extends StatefulWidget {
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
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    if (widget.streaming) _startTimer();
  }

  @override
  void didUpdateWidget(covariant ThinkingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming && !oldWidget.streaming) {
      _seconds = 0;
      _startTimer();
    } else if (!widget.streaming && oldWidget.streaming) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final pastel = skin.pastelAt(3);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(pastel.first.withValues(alpha: 0.14), skin.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pastel.first.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 标题条
          InkWell(
            onTap: widget.onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 8, 6),
              child: Row(
                children: <Widget>[
                  WhaleThinking(size: 16, color: skin.accentAlt),
                  const SizedBox(width: 5),
                  Text(
                    widget.streaming
                        ? (_seconds == 0
                            ? '思考中…'
                            : '思考中 · ${_seconds}s')
                        : '思考过程',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: skin.accentAlt,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    widget.expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: skin.accentAlt,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ShaderMask(
                // 底部渐隐:内容长时不会被一条硬线"切掉"
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.black, Colors.transparent],
                  stops: <double>[0.72, 1],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Text(
                    widget.text,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.55,
                      color: skin.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// **克制的 Markdown 样式**(v2.8,用户第 8 条:"回复里各种多余的配色导致很花")。
///
/// 问题:`MarkdownStyleSheet.fromTheme` 会把标题/行内代码/表格头/引用各染一种颜色,
/// 一段正常的 AI 回复里于是同时出现主色蓝、tertiary 紫、成功绿、警示橙 ——
/// 用户的原话是"很花"。
///
/// 规则(只保留两条):**正文一律 onSurface**,**链接用 primary**;
/// 其余全部靠**字重与斜体**区分层级,不用颜色。代码块只给中性底色。
MarkdownStyleSheet calmMarkdownSheet(ThemeData theme) {
  final cs = theme.colorScheme;
  final body = theme.textTheme.bodyMedium?.copyWith(
    fontSize: 13,
    height: 1.55,
    color: cs.onSurface,
  );
  TextStyle head(double size) => TextStyle(
        fontSize: size,
        height: 1.4,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    a: body?.copyWith(
      color: cs.primary,
      decoration: TextDecoration.underline,
      decorationColor: cs.primary.withAlpha(90),
    ),
    em: body?.copyWith(fontStyle: FontStyle.italic),
    strong: body?.copyWith(fontWeight: FontWeight.w700),
    del: body?.copyWith(decoration: TextDecoration.lineThrough),
    h1: head(16),
    h2: head(15),
    h3: head(14),
    h4: head(13.5),
    h5: head(13),
    h6: head(13),
    // 行内代码:中性底色 + 等宽,不用彩色(以前是 tertiary,一片紫)
    code: TextStyle(
      fontSize: 12,
      fontFamily: 'monospace',
      color: cs.onSurface,
      backgroundColor: cs.surfaceContainerHighest,
    ),
    codeblockDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: Radii.controlRadius,
    ),
    codeblockPadding: const EdgeInsets.all(Gap.sm),
    blockquote: body?.copyWith(
      color: cs.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    ),
    blockquoteDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withAlpha(120),
      borderRadius: Radii.controlRadius,
    ),
    blockquotePadding: const EdgeInsets.all(Gap.sm),
    listBullet: body,
    listBulletPadding: const EdgeInsets.only(right: Gap.xxs),
    tableHead: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
    ),
    tableBody: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurface),
    tableBorder: TableBorder.all(color: cs.outlineVariant, width: 0.5),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
    ),
  );
}