import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocab_occurrence.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/screens/input/widgets/word_list_tile.dart';

/// 总览卡片(WordListTile)排版回归(v2.6)。
///
/// 用户实测的原始现象:"总览模式下句子显示非常难看 —— 非常长的一竖列,
/// UI 利用率太低"(截图里单词还从中间断开:"mas / tering")。
///
/// 根因:类型标签用了 `Flexible(...)`,而 **Flexible 默认 flex:1** ——
/// 它和 `Expanded(词条)` 各分走一半剩余宽度,长句子只能塞进 ~140px 的窄列,
/// 于是每个词都得换行、长词还得拦腰断。这条测试就是钉死这个 bug。
void main() {
  const longSentence =
      'Taoism teaches that mastering others requires force, while mastering '
      'the self requires strength; knowing others is wisdom, while knowing '
      'yourself is enlightenment.';

  Vocabulary sentenceItem() => Vocabulary(
        word: longSentence,
        translation: '道家教导说:胜者有力,自胜者强;知人者智,自知者明。',
        wordType: 'sentence',
        originalSentence: longSentence,
      );

  Widget wrap(Widget child, {double width = 360, double textScale = 1.0}) {
    return MaterialApp(
      home: Builder(
        builder: (ctx) => MediaQuery(
          // 必须 copyWith:直接 new MediaQueryData() 会把 size 变成 0×0,
          // 那样测出来的溢出是测试自己的问题,不是组件的
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            // 真实场景里这些条目在**可滚动列表**里(高度不受屏幕限制)——
            // 用 SingleChildScrollView 复刻,否则长句子在 600 高的测试屏上
            // 会因为"放不下"报 overflow,那是测试环境的锅不是组件的
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(width: width, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('长句子必须占满可用宽度,不能被挤成一竖列', (tester) async {
    await tester.pumpWidget(
      wrap(WordListTile(
        item: sentenceItem(),
        isSelected: false,
        index: 22,
        onTap: () {},
        onLongPress: () {},
      )),
    );
    final size = tester.getSize(find.text(longSentence));
    // 360 宽里扣掉序号/图标/标签,词条至少应拿到 200 以上
    expect(size.width, greaterThan(200),
        reason: '句子被挤窄就是"一竖列"那个 bug(Flexible 默认 flex:1 抢宽)');
    // 宽度够的话不该排成 20 行以上
    expect(size.height, lessThan(320), reason: '过高的文本块说明宽度仍被挤压');
  });

  testWidgets('2× 系统字号下不溢出(标签可省略、词条仍完整)', (tester) async {
    await tester.pumpWidget(
      wrap(
        WordListTile(
          item: sentenceItem(),
          isSelected: false,
          index: 22,
          onTap: () {},
          onLongPress: () {},
        ),
        textScale: 2.0,
      ),
    );
    expect(tester.takeException(), isNull,
        reason: '2× 字号下不允许 Row overflow(此前实测 overflowed by 25px)');
  });

  testWidgets('单词条目照常显示类型/词性标签', (tester) async {
    await tester.pumpWidget(
      wrap(WordListTile(
        item: Vocabulary(
          word: 'blur',
          translation: '模糊',
          wordType: 'word',
          partOfSpeech: 'noun',
        ),
        isSelected: false,
        index: 0,
        onTap: () {},
        onLongPress: () {},
      )),
    );
    expect(find.text('noun'), findsOneWidget);
    expect(find.text('blur'), findsOneWidget);
  });

  testWidgets('待确认条目带「待确认」标(v2.6 宁可多收的可见出口)', (tester) async {
    await tester.pumpWidget(
      wrap(WordListTile(
        item: Vocabulary(
          word: 'mirage',
          translation: '海市蜃楼',
          wordType: 'word',
          needsReview: true,
        ),
        isSelected: false,
        index: 3,
        onTap: () {},
        onLongPress: () {},
      )),
    );
    expect(find.text('待确认'), findsOneWidget);
  });

  testWidgets('出现多次的词条显示 ×N(v2.4 行为不回归)', (tester) async {
    await tester.pumpWidget(
      wrap(WordListTile(
        item: Vocabulary(
          word: 'apple',
          translation: '苹果',
          wordType: 'word',
          occurrences: [
            for (var i = 0; i < 3; i++)
              VocabOccurrence(
                book: 'b',
                page: 'p$i',
                sentence: 'sentence $i',
                at: DateTime(2026, 9, 28),
              ),
          ],
        ),
        isSelected: false,
        index: 1,
        onTap: () {},
        onLongPress: () {},
      )),
    );
    expect(find.textContaining('×3'), findsOneWidget);
  });
}
