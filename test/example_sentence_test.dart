import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/screens/input/widgets/example_sentence.dart';

/// 出处例句标粗匹配逻辑回归测试。
/// 重点:边界守卫(防 "cat" 标进 "concatenate")、变形词不标、词条化截断不标。
void main() {
  TextStyle style = const TextStyle(fontSize: 12, color: Colors.grey);

  /// 断言:命中目标词时,返回的 spans 中含一个加粗段且文本为 [word]
  void expectBold(List<TextSpan> spans, String word) {
    final bold = spans.where((s) => s.style?.fontWeight == FontWeight.bold);
    expect(bold.length, 1,
        reason: '应恰好一个加粗段,实际: ${spans.map((s) => s.text).join("|")}');
    expect(bold.first.text, word);
  }

  /// 断言:无命中/无意义时,原样单个 span 且不加粗
  void expectPlain(List<TextSpan> spans) {
    expect(spans.length, 1);
    expect(spans.first.style?.fontWeight, isNot(FontWeight.bold));
  }

  group('buildHighlightSpans', () {
    test('单词命中加粗,前后段保留原样式', () {
      final spans = buildHighlightSpans(
        sentence: 'The cat sat on the mat.',
        highlightWord: 'cat',
        style: style,
      );
      expect(spans.map((s) => s.text).toList(), ['The ', 'cat', ' sat on the mat.']);
      expectBold(spans, 'cat');
      expect(spans.first.style, style); // 非加粗段继承原样式
    });

    test('大小写不敏感', () {
      final spans = buildHighlightSpans(
        sentence: 'The CAT sat.',
        highlightWord: 'cat',
        style: style,
      );
      expectBold(spans, 'CAT');
    });

    test('词边界守卫:不标进 concatenate 之类长词', () {
      final spans = buildHighlightSpans(
        sentence: 'Do not concatenate the strings; keep cat separate.',
        highlightWord: 'cat',
        style: style,
      );
      expectBold(spans, 'cat'); // 只标独立出现的 cat,不标 concatenate 里的
      // 验证 concatenate 未被标粗:唯一加粗段文本是 'cat'
    });

    test('多个命中全部标粗', () {
      final spans = buildHighlightSpans(
        sentence: 'cat and cat again.',
        highlightWord: 'cat',
        style: style,
      );
      final bold = spans.where((s) => s.style?.fontWeight == FontWeight.bold);
      expect(bold.length, 2);
      expect(bold.every((s) => s.text == 'cat'), true);
    });

    test('短语命中', () {
      final spans = buildHighlightSpans(
        sentence: 'A compound with water forms this.',
        highlightWord: 'compound with',
        style: style,
      );
      expectBold(spans, 'compound with');
    });

    test('带撇号词:don\'t 命中', () {
      final spans = buildHighlightSpans(
        sentence: "I don't know the answer.",
        highlightWord: "don't",
        style: style,
      );
      expectBold(spans, "don't");
    });

    test('变形词不标(run vs runs)', () {
      final spans = buildHighlightSpans(
        sentence: 'He runs fast every morning.',
        highlightWord: 'run',
        style: style,
      );
      expectPlain(spans);
    });

    test('词条化截断词不标(省略号在句子里匹配不到)', () {
      final spans = buildHighlightSpans(
        sentence: 'Because reality is never as simple as it seems.',
        highlightWord: 'Because reality is n…',
        style: style,
      );
      expectPlain(spans);
    });

    test('word 与整句相等不标(标粗整句无意义)', () {
      final spans = buildHighlightSpans(
        sentence: 'I love this book.',
        highlightWord: 'I love this book.',
        style: style,
      );
      expectPlain(spans);
    });

    test('word 为空或 null 原样显示', () {
      expectPlain(buildHighlightSpans(sentence: 'Any text here.', highlightWord: null, style: style));
      expectPlain(buildHighlightSpans(sentence: 'Any text here.', highlightWord: '', style: style));
    });

    test('sentence 为空安全返回', () {
      expectPlain(buildHighlightSpans(sentence: '', highlightWord: 'cat', style: style));
    });

    test('style 为 null 也能工作(默认加粗样式)', () {
      final spans = buildHighlightSpans(sentence: 'a cat', highlightWord: 'cat');
      expectBold(spans, 'cat');
    });
  });
}
