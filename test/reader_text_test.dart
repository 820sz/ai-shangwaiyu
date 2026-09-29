import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/widgets/reader_text.dart';
import 'package:readflow/widgets/word_action_sheet.dart';

/// v2.7 阅读正文公共件的单测(用户第 2(2) 条)。
///
/// 用户原话:"点击单词,或者长按选中多个词组时,底端提供两个小选项
/// (询问 AI 和 收藏进单词本)"。三个阅读器(材料原文 / AI 改写材料 / 生词成文)
/// 现在共用这套组件,所以这里钉死的每一条都是三处同时生效的行为。
void main() {
  group('点词(TappablePassage)', () {
    testWidgets('点词回调带出被点的那个词(标点不粘进来)', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TappablePassage(
            text: 'The quick brown fox, jumps!',
            style: const TextStyle(fontSize: 16),
            onWordTap: tapped.add,
          ),
        ),
      ));

      // 从渲染出的 span 里直接触发手势识别器:文本点击在测试里没有稳定的坐标,
      // 而"哪个词挂了回调、回调带什么"才是要保证的东西
      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      final root = selectable.textSpan!;
      final words = <String>[];
      root.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null && span.text != null) {
          words.add(span.text!);
        }
        return true;
      });
      expect(words, ['The', 'quick', 'brown', 'fox', 'jumps'],
          reason: '每个英文词都该可点,标点不该被当成词');

      final quickSpan = root.children!
          .whereType<TextSpan>()
          .firstWhere((s) => s.text == 'quick');
      (quickSpan.recognizer as dynamic).onTap();
      expect(tapped, ['quick']);
    });

    testWidgets('超长段落退化成普通可选文本(不挂上万个手势)', (tester) async {
      final long = List.generate(1500, (i) => 'word$i').join(' ');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TappablePassage(
              text: long,
              style: const TextStyle(fontSize: 16),
              onWordTap: (_) {},
              maxSpans: 1200,
            ),
          ),
        ),
      ));
      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.textSpan, isNull, reason: '退化路径直接用纯文本,不切词');
      expect(selectable.data, long);
    });
  });

  group('长按选中后的两个选项', () {
    test('有选中文本 → 两个业务动作在最前,系统项跟在后', () {
      final fired = <String>[];
      final items = TappablePassage.buildSelectionMenuItems(
        selected: '  give up on  ',
        onAction: (text, action) => fired.add('$text|${action.name}'),
        systemItems: [
          ContextMenuButtonItem(label: '复制', onPressed: () {}),
          ContextMenuButtonItem(label: '全选', onPressed: () {}),
        ],
      );
      expect(items.map((e) => e.label).toList(),
          ['询问 AI', '收藏进单词本', '复制', '全选']);
      // 选中文本要先 trim(用户选到前后空格很常见)
      items[0].onPressed!();
      items[1].onPressed!();
      expect(fired, ['give up on|askAi', 'give up on|save']);
    });

    test('没有选中内容 → 只给系统项(不出现两个空动作)', () {
      final items = TappablePassage.buildSelectionMenuItems(
        selected: '   ',
        onAction: (_, _) => fail('不该触发业务动作'),
        systemItems: [
          ContextMenuButtonItem(label: '全选', onPressed: () {}),
        ],
      );
      expect(items.map((e) => e.label).toList(), ['全选']);
    });

    test('触发动作前先收起系统菜单(否则菜单会盖在弹层上)', () {
      var hidden = false;
      final items = TappablePassage.buildSelectionMenuItems(
        selected: 'word',
        onAction: (_, _) {},
        hideToolbar: () => hidden = true,
      );
      items.first.onPressed!();
      expect(hidden, isTrue);
    });
  });

  group('保存位置(WordSaveTarget)', () {
    test('分类 / 材料名 / 页码一起写进词条 —— 这正是"不再掉进未归类"的关键', () {
      const target = WordSaveTarget(
        category: '书籍',
        materialName: '《红楼梦》',
        page: 'p33-35',
      );
      final v = target.toVocabulary(word: 'mirage', translation: '海市蜃楼');

      expect(v.category, '书籍');
      expect(v.sourceBook, '《红楼梦》');
      expect(v.materialPath, '书籍/《红楼梦》');
      expect(v.word, 'mirage');
    });

    test('没填材料名时不写 path(留给用户自己归类),但分类要写对', () {
      const target = WordSaveTarget(category: '外刊');
      final v = target.toVocabulary(word: 'tariff');
      expect(v.category, '外刊');
      expect(v.materialPath, isNull);
      expect(v.sourceBook, isNull);
    });

    test('label:给用户看的"存到哪儿"必须能一眼读懂', () {
      expect(
        const WordSaveTarget(category: '书籍', materialName: '《红楼梦》', page: 'p33')
            .label,
        '书籍 / 《红楼梦》 · p33',
      );
      expect(const WordSaveTarget(category: '其他').label, '其他 / 未指定材料');
    });
  });
}
