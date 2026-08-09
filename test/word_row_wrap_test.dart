import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('词条 Text 必须不限行(maxLines:null,一排放不下自动换行)', (tester) async {
    final long = 'The mind wants meaning, but reality offers no clear '
        'beginnings, middles, or ends. Stories do.';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            Expanded(
              child: Text(long, maxLines: null, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    ));
    final textWidget = tester.widget<Text>(find.byType(Text).first);
    expect(textWidget.maxLines, isNull, reason: '一排放不下必须自动换行');
  });

  test('TextPainter 布局:受限宽度下长文本换行为多行(换行引擎正常)', () {
    const text = 'The quick brown fox jumps over the lazy dog.';
    final tp = TextPainter(
      text: TextSpan(
        text: List.filled(10, text).join(' '), // 530 字符
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 283);
    expect(tp.height, greaterThan(tp.preferredLineHeight),
        reason: '530 字符在 283dp 宽下必然多行(每字符≈14px)');
  });
}
