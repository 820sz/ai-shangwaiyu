import 'package:flutter/material.dart';

/// 出处例句组件:限行(默认 3 行)+ 可展开/收起 + 目标词汇标粗。
///
/// 背景:2026-08-07 起 original_sentence 必填,冗长例句把列表/详情页拉得很长
/// (用户反馈"例句框越来越长")。方案1=限行+展开;追加=出处句中目标词加粗。
///
/// 标粗匹配策略(见 [buildHighlightSpans]):大小写不敏感 + 前后非字母数字边界,
/// 找不到/无意义(如 word 与整句相等)时原样显示,绝不影响例句内容本身。
class ExampleSentence extends StatefulWidget {
  const ExampleSentence({
    super.key,
    required this.sentence,
    this.highlightWord,
    this.style,
    this.collapsedLines = 3,
  });

  final String sentence;

  /// 要在例句中标粗的目标词(通常为 Vocabulary.word)。
  /// 为 null/空/匹配不到时例句原样显示,不标粗。
  final String? highlightWord;

  /// 基础样式;标粗段在此样式上加粗,其余段继承原样。
  final TextStyle? style;

  /// 收起态显示行数,超出时显示"展开"。
  final int collapsedLines;

  @override
  State<ExampleSentence> createState() => _ExampleSentenceState();
}

class _ExampleSentenceState extends State<ExampleSentence> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 量真实渲染宽度下,限行是否溢出——溢出才显示"展开/收起"
        final tp = TextPainter(
          text: TextSpan(style: style, text: widget.sentence),
          maxLines: widget.collapsedLines,
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = tp.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: style,
                children: buildHighlightSpans(
                  sentence: widget.sentence,
                  highlightWord: widget.highlightWord,
                  style: style,
                ),
              ),
              maxLines: _expanded ? null : widget.collapsedLines,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (overflows)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded ? '收起' : '展开',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 把 [sentence] 拆成 TextSpan 列表:[highlightWord] 命中的片段加粗,其余继承 [style]。
///
/// 纯函数,供测试覆盖(见 test/example_sentence_test.dart)。
/// 匹配规则:
/// 1. 大小写不敏感
/// 2. 命中位置前后不能是字母/数字/下划线(防 "cat" 标进 "concatenate")
/// 3. 多个命中位置全部标粗
/// 4. 以下情况原样返回单个 span,不标粗:
///    - highlightWord 为 null/空/sentence 为空
///    - word 比句子还长(含 word 与整句相等——sentence 类型标粗整句无意义)
///    - 无命中(如 word 词条化截断带省略号、或句子中是变形词 "runs" vs "run")
List<TextSpan> buildHighlightSpans({
  required String sentence,
  String? highlightWord,
  TextStyle? style,
}) {
  final plain = TextSpan(text: sentence, style: style);
  final word = highlightWord;
  if (word == null || word.isEmpty || sentence.isEmpty) return [plain];

  final lower = sentence.toLowerCase();
  final w = word.toLowerCase();
  if (w.length > lower.length || lower == w) return [plain];

  final bold = (style ?? const TextStyle()).copyWith(fontWeight: FontWeight.bold);
  final spans = <TextSpan>[];
  var cursor = 0;
  var found = false;
  var searchFrom = 0;
  while (true) {
    final idx = lower.indexOf(w, searchFrom);
    if (idx < 0) break;
    final afterEnd = idx + w.length;
    // 前后边界:不是字母/数字/下划线才算词边界(撇号等标点可作边界)
    final before = idx == 0 ? ' ' : lower[idx - 1];
    final after = afterEnd >= lower.length ? ' ' : lower[afterEnd];
    if (!_isWordChar(before) && !_isWordChar(after)) {
      found = true;
      if (cursor < idx) {
        spans.add(TextSpan(text: sentence.substring(cursor, idx), style: style));
      }
      spans.add(TextSpan(text: sentence.substring(idx, afterEnd), style: bold));
      cursor = afterEnd;
    }
    // 从命中末尾继续找,避免重叠
    searchFrom = afterEnd;
  }
  if (!found) return [plain];
  if (cursor < sentence.length) {
    spans.add(TextSpan(text: sentence.substring(cursor), style: style));
  }
  return spans;
}

bool _isWordChar(String ch) {
  final c = ch.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      (c >= 0x30 && c <= 0x39) || // 0-9
      c == 0x5F; // _
}
