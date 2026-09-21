import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/screens/input/widgets/word_list_tile.dart';

/// 「词条被拆行/截断」是用户实测回归过 3 次的痛点,守护测试必须压在生产组件上:
/// 之前这里是自己 pumpWidget 一个 Text(maxLines: null) 再断言它的 maxLines,
/// 生产代码改回 maxLines: 2 它照样绿——等于没测。
/// 现在测的是 WordListTile 内部那个 Text(真实渲染路径)。
void main() {
  // 30+ 词的超长词条(模型把长句词条化时会产出这种内容)
  const long = 'The mind wants meaning, but reality offers no clear beginnings, '
      'middles, or ends, and stories do the rest of the work for us.';

  // 构造生产组件的最小可用参数:无 Provider / 无 Hive 依赖,
  // 单词字段走 item.displayWordText,不需要初始化数据库。
  //
  // 注意脚手架:外面必须是"主轴高度不受限"的容器(SingleChildScrollView)。
  // 生产里这个 tile 就活在 ListView 中(高度不受限),而 Center/SizedBox 会把
  // 高度压成 600 —— 那样组件内部的 Column(mainAxisSize.max)在 2× 字号下
  // 必然溢出,测出来的是脚手架失真,不是被测组件的缺陷。
  Widget buildTile({double width = 200}) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              // 固定窄宽度:逼出一排放不下的场景
              width: width,
              child: WordListTile(
                item: Vocabulary(
                  word: long,
                  translation: '心想要意义，但现实没有清晰的开头、中间和结尾。',
                  partOfSpeech: 'sentence',
                  wordType: 'sentence',
                ),
                isSelected: false,
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        ),
      );

  /// 取生产组件内部真正渲染词条文本的那个 Text(长文本、不限行),
  /// 而不是测试自己造的 Text。
  Iterable<Text> wordTextsInTile(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(
        of: find.byType(WordListTile),
        matching: find.byType(Text),
      ))
      .where((t) => t.data == long);

  testWidgets('WordListTile 词条 Text 必须不限行(maxLines:null,一排放不下自动换行)', (tester) async {
    await tester.pumpWidget(buildTile());

    // 先证明取到的确实是生产组件里渲染长词条的那个 Text(取不到就直接失败,
    // 不能让"找不到"被伪装成"通过")
    expect(find.byType(WordListTile), findsOneWidget);
    final texts = wordTextsInTile(tester).toList();
    expect(texts, hasLength(1),
        reason: '必须能定位到 WordListTile 内部渲染长词条的 Text');

    final text = texts.single;
    expect(text.maxLines, isNull,
        reason: '一排放不下必须自动换行(maxLines 一旦被改回 2,这条断言立即失败)');
    expect(text.overflow, TextOverflow.visible,
        reason: '不限行的同时不能打省略号');
  });

  testWidgets('系统字号 2× 时词条换行而非截断(高度超过单行,且无布局异常)', (tester) async {
    // 先量正常字号下的单行高度作为标尺(宽度取窄屏真机的内容宽)
    await tester.pumpWidget(buildTile(width: 320));
    final singleLine = tester.getSize(find.text(long)).height;

    // 放大到 2×:此时若被 maxLines 截断,高度会≈单行;真换行则≈两行
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(buildTile(width: 320));
    await tester.pump();

    expect(tester.takeException(), isNull, reason: '2× 字号下不应有溢出/布局异常');

    final wrapped = tester.getSize(find.text(long)).height;
    expect(wrapped, greaterThan(singleLine),
        reason: '2× 字号下长词条必须换行成多行(高度 > 单行高度),'
            '若被截断则高度只会≈单行');
    // 生产代码里的不限行 Text 是否真的落到了 RenderParagraph:
    // 取渲染对象再确认一遍行高标尺(比单行高度大 ⇒ 至少两行)
    final paragraph = tester.renderObject<RenderParagraph>(find.text(long));
    expect(wrapped, greaterThan(paragraph.preferredLineHeight * 1.2),
        reason: '高度需明显超过一个行高,证明不是被裁成一行');
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
