import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/text_difficulty.dart';

/// 阅读正文里的"选词动作"(v2.7,用户第 2(2) 条)。
///
/// 用户原话:"点击单词,或者长按选中多个词组时,底端提供两个小选项
/// (**询问 AI** 和 **收藏进单词本**)"。这两个动作在三个阅读器里语义相同,
/// 所以做成枚举,由调用方决定怎么实现。
enum ReaderTextAction {
  /// 询问 AI:就这一处讲清楚
  askAi,

  /// 收藏进单词本
  save,
}

/// 可点词 + 可长按选词的正文段落(v2.7 抽出)。
///
/// **为什么抽成公共件**:材料原文阅读器、特色功能生词成文、AI 改写材料详情页
/// 以前是**三套各写一份**——结果只有材料阅读器能点词,另外两个是死文本。
/// 用户第 2(2) 条明确要求"这点在 AI 改写的材料和特色功能生词成文中也要有"。
/// 抽出来后:点词/选词/两个动作只实现一次,以后加功能不会再"只加在一个地方"。
///
/// 实现取舍(沿用 v2.0 材料阅读器的做法):
/// 把段落按词切成 TextSpan + TapGestureRecognizer。超长段落(> [maxSpans] 个词)
/// 不切词 —— 上万个 span 会让低端机掉帧,这时退化成普通可选文本
/// (长按仍可选中 + 两个动作仍可用)。
class TappablePassage extends StatefulWidget {
  /// 段落原文
  final String text;

  /// 正文样式(字号/行距由阅读设置决定,调用方传入)
  final TextStyle style;

  /// 点某个词
  final void Function(String word) onWordTap;

  /// 长按选中后点「询问 AI」/「收藏进单词本」时回调(选中文本,动作)。
  /// 为空则只显示系统默认菜单(复制/全选)。
  final void Function(String selection, ReaderTextAction action)? onSelectionAction;

  /// 超过这么多个词就不再逐词挂手势(性能保护)
  final int maxSpans;

  /// 词本身的颜色(C 方案:保持正文墨色,不再是"满屏主色链接感")。
  /// 为空时退回旧行为(主题 primary),保证另外两个阅读器零改动。
  final Color? wordColor;

  /// 生词下划线的颜色(C 方案传砖红)。
  /// 为空时退回旧行为(主题 primary 60% 虚线)。
  final Color? underlineColor;

  /// 下划线粗细(C 方案 1.5~1.6)
  final double underlineThickness;

  /// 生词高亮集合(小写)。为空 = 旧行为(每个词都画线,材料阅读器现状);
  /// 非空 = 只给集合里的词画砖红实线 + w600(C 方案:满屏红线等于没重点,
  /// 只有真生词配得上强调色;其余词仍然可点,只是不画线)。
  final Set<String>? highlightWords;

  const TappablePassage({
    super.key,
    required this.text,
    required this.style,
    required this.onWordTap,
    this.onSelectionAction,
    this.maxSpans = 1200,
    this.wordColor,
    this.underlineColor,
    this.underlineThickness = 1.5,
    this.highlightWords,
  });

  /// 选中菜单的按钮表(纯函数,便于单测)。
  ///
  /// 单独抽出来是因为"两个动作是否出现、回调里带的文本对不对"是这个功能的
  /// 全部价值所在,而它藏在 `contextMenuBuilder` 里 —— 那地方只有真人长按
  /// 才会跑到,单测很难触达。抽成纯函数后可以逐项断言。
  static List<ContextMenuButtonItem> buildSelectionMenuItems({
    required String selected,
    required void Function(String selection, ReaderTextAction action) onAction,
    List<ContextMenuButtonItem> systemItems = const [],
    VoidCallback? hideToolbar,
  }) {
    final text = selected.trim();
    if (text.isEmpty) return systemItems;
    return [
      ContextMenuButtonItem(
        label: '询问 AI',
        onPressed: () {
          hideToolbar?.call();
          onAction(text, ReaderTextAction.askAi);
        },
      ),
      ContextMenuButtonItem(
        label: '收藏进单词本',
        onPressed: () {
          hideToolbar?.call();
          onAction(text, ReaderTextAction.save);
        },
      ),
      ...systemItems,
    ];
  }

  @override
  State<TappablePassage> createState() => _TappablePassageState();
}

class _TappablePassageState extends State<TappablePassage> {
  final List<TapGestureRecognizer> _recognizers = [];

  static final RegExp _wordPattern =
      RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)*(?:-[A-Za-z]+)*");

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tooLong =
        TextDifficulty.tokenize(widget.text).length > widget.maxSpans;
    if (tooLong) {
      return SelectableText(
        widget.text,
        style: widget.style,
        contextMenuBuilder: _buildMenu,
      );
    }

    // 用正则切分并保留原标点与空格(只在词上挂手势)
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in _wordPattern.allMatches(widget.text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, m.start)));
      }
      final word = m.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onWordTap(word);
      _recognizers.add(recognizer);
      // 三种画法:
      // - highlightWords == null:旧行为(全部主色虚线,外观不变);
      // - highlightWords 命中:生词 = w600 + 砖红实线;
      // - 未命中:普通词,**不画线**(仍是可点热区)。
      final highlight = widget.highlightWords;
      final marked =
          highlight == null || highlight.contains(word.toLowerCase());
      TextStyle? wordStyle;
      if (!marked) {
        wordStyle = null;
      } else if (highlight == null) {
        wordStyle = TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: theme.colorScheme.primary.withAlpha(60),
        );
      } else {
        wordStyle = TextStyle(
          color: widget.wordColor ?? theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.solid,
          decorationColor: widget.underlineColor,
          decorationThickness: widget.underlineThickness,
        );
      }
      spans.add(TextSpan(
        text: word,
        recognizer: recognizer,
        style: wordStyle,
      ));
      cursor = m.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return SelectableText.rich(
      TextSpan(style: widget.style, children: spans),
      contextMenuBuilder: _buildMenu,
    );
  }

  /// 选中菜单:两个**业务动作**排在最前,再挂上系统默认的复制/全选。
  ///
  /// 顺序有讲究:用户要的是"选一段就能问 AI / 收藏",复制是附带能力;
  /// 把复制放最前会让人以为只能复制。
  Widget _buildMenu(BuildContext context, EditableTextState state) {
    final action = widget.onSelectionAction;
    if (action == null) {
      return AdaptiveTextSelectionToolbar.editableText(
        editableTextState: state,
      );
    }
    final value = state.textEditingValue;
    final sel = value.selection;
    final selected =
        (sel.isValid && !sel.isCollapsed) ? sel.textInside(value.text) : '';
    if (selected.trim().isEmpty) {
      return AdaptiveTextSelectionToolbar.editableText(
        editableTextState: state,
      );
    }
    final system = state.contextMenuButtonItems
        .where((b) =>
            b.type == ContextMenuButtonType.copy ||
            b.type == ContextMenuButtonType.selectAll)
        .toList();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: TappablePassage.buildSelectionMenuItems(
        selected: selected,
        onAction: action,
        systemItems: system,
        hideToolbar: state.hideToolbar,
      ),
    );
  }
}
