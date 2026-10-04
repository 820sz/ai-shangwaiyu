import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/models/bookmark.dart';
import 'package:readflow/providers/bookmark_provider.dart';
import 'package:readflow/screens/profile/bookmarks_screen.dart';

/// 收藏阅读页回归测试(v2.10,用户第 7 条)。
///
/// 用户原话:"'收藏夹'功能里收藏的内容,需**增加精美的阅读界面**,现在的太简陋了,
/// 而且**有一堆 ai 符号残留**。"
/// 前者是 UI 的事(全屏阅读页),后者是真 bug:详情页用 `SelectableText` 直接显示
/// AI 原文,而 Text 不渲染 Markdown —— 用户看到的是字面的 `**重点**`、`## 标题`。
/// 所以这里的重点是 **cleanMarkdownForDisplay** 的各种脏输入,以及渲染结果里
/// "再也不出现裸奔符号"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Bookmark bookmark({
    String title = 'unfettered 的用法',
    String content = '',
    String source = AppConstants.bookmarkSourceFollowUp,
    String? model = 'deepseek-v4-flash',
    String? sourceWord,
    int? id = 7,
    DateTime? createdAt,
  }) =>
      Bookmark(
        id: id,
        source: source,
        title: title,
        content: content,
        model: model,
        sourceWord: sourceWord,
        createdAt: createdAt ?? DateTime(2026, 10, 4, 20, 15),
      );

  /// 把整棵树上的文字抓平 —— 用它来断言"裸符号没有出现在屏幕上"。
  ///
  /// 为什么要收三种控件:正文可能是 `Text`(MarkdownBody 非 selectable 分支)、
  /// 也可能是 `SelectableText`(**它内部是 EditableText,不是 RichText**),
  /// 只抓 RichText 会漏掉正文,断言就变成了假通过。
  String plainText(WidgetTester tester) {
    final buf = StringBuffer();
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      buf.writeln(w.data ?? w.textSpan?.toPlainText() ?? '');
    }
    for (final w in tester.widgetList<EditableText>(find.byType(EditableText))) {
      buf.writeln(w.controller.text);
    }
    for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
      buf.writeln(w.text.toPlainText());
    }
    return buf.toString();
  }

  // ─────────────────────────────────────────────────────────
  // 清洗函数(纯函数,规则逐条钉住)
  // ─────────────────────────────────────────────────────────
  group('cleanMarkdownForDisplay', () {
    test('正常 Markdown 原样保留(不能"修"坏本来就对的内容)', () {
      const raw = '# 标题\n\n正文一段。\n\n- 列表项\n- 列表项2\n\n> 引用\n\n'
          '| a | b |\n| - | - |\n| 1 | 2 |';
      expect(cleanMarkdownForDisplay(raw), raw);
    });

    test('换行统一:\\r\\n 与 \\r 都变 \\n', () {
      expect(cleanMarkdownForDisplay('a\r\nb'), 'a\nb');
      expect(cleanMarkdownForDisplay('a\rb'), 'a\nb');
      // 老 Mac 换行 + 结尾空行也不留尾巴
      expect(cleanMarkdownForDisplay('a\r\nb\r\n'), 'a\nb');
    });

    test('行尾空白去掉(含全角空格)', () {
      expect(cleanMarkdownForDisplay('句子  \n下一句'), '句子\n下一句');
      expect(cleanMarkdownForDisplay('句子\t\n下一句\u3000'), '句子\n下一句');
    });

    test('全角星号/井号转半角', () {
      expect(cleanMarkdownForDisplay('＃＃ 标题'), '## 标题');
      expect(cleanMarkdownForDisplay('＊重点＊'), '*重点*');
      expect(cleanMarkdownForDisplay('这是＊＊重点＊＊'), '这是**重点**');
    });

    test('行首裸项目符号 • ● ▪ · 统一成 Markdown 的 "- "', () {
      expect(cleanMarkdownForDisplay('• 第一点\n• 第二点'), '- 第一点\n- 第二点');
      expect(cleanMarkdownForDisplay('●没有空格的写法'), '- 没有空格的写法');
      expect(cleanMarkdownForDisplay('· 第三点'), '- 第三点');
      // 正文中间的圆点不能动(它不是项目符号)
      expect(cleanMarkdownForDisplay('第一点 • 第二点'), '第一点 • 第二点');
    });

    test('补结构:列表/标题紧跟正文时中间补空行', () {
      expect(
        cleanMarkdownForDisplay('开头一句:\n- 第一点\n- 第二点'),
        '开头一句:\n\n- 第一点\n- 第二点',
      );
      // 有序列表最需要这一手:CommonMark 里 "文字\n1. 项" 会被当成同一段
      expect(
        cleanMarkdownForDisplay('说明如下:\n1. 第一\n2. 第二'),
        '说明如下:\n\n1. 第一\n2. 第二',
      );
      expect(
        cleanMarkdownForDisplay('铺垫\n## 小标题'),
        '铺垫\n\n## 小标题',
      );
      // 连续列表项之间**不该**被塞空行
      expect(
        cleanMarkdownForDisplay('- a\n- b\n- c'),
        '- a\n- b\n- c',
      );
    });

    test('半截加粗:一行里 ** 是奇数个 → 删掉那个没配对的', () {
      expect(cleanMarkdownForDisplay('这是**重点内容'), '这是重点内容');
      expect(cleanMarkdownForDisplay('**开头没闭合'), '开头没闭合');
      expect(cleanMarkdownForDisplay('正常**加粗**不动'), '正常**加粗**不动');
      expect(
        cleanMarkdownForDisplay('**对的** 和 **没配对的'),
        '**对的** 和 没配对的',
      );
    });

    test('代码围栏里的内容一个字符都不改', () {
      const raw = '说明:\n\n```\n- 不是列表\n*  尾巴有空格  \n＃＃ 全角也不动\n```\n\n结束';
      expect(cleanMarkdownForDisplay(raw), raw);
    });

    test('去 AI 开场客套(最多两行,不误伤正常句子)', () {
      expect(
        cleanMarkdownForDisplay('好的,以下是关于这个词的解析:\n\n它表示「无拘无束」。'),
        '它表示「无拘无束」。',
      );
      expect(
        cleanMarkdownForDisplay('当然可以!\n\n下面是三种常见用法:\n\n- 用法一'),
        '- 用法一',
      );
      expect(cleanMarkdownForDisplay('以下是重点:\n\n内容'), '内容');
      // 正常句子不能被当成客套删掉
      expect(
        cleanMarkdownForDisplay('好的方法就是多读多练。'),
        '好的方法就是多读多练。',
      );
      expect(
        cleanMarkdownForDisplay('当然,语言学习需要时间。'),
        '当然,语言学习需要时间。',
      );
    });

    test('去 AI 结尾客套', () {
      expect(
        cleanMarkdownForDisplay('内容是这些。\n\n希望对你有所帮助'),
        '内容是这些。',
      );
      expect(
        cleanMarkdownForDisplay('内容是这些。\n\n如果还有疑问,随时问我'),
        '内容是这些。',
      );
      expect(
        cleanMarkdownForDisplay('内容是这些。\n\n祝学习愉快!'),
        '内容是这些。',
      );
      // 正文里出现"希望对你有帮助"这类字样且不是结尾行 → 不动
      expect(
        cleanMarkdownForDisplay('希望对你有所帮助这句话,是 AI 的口头禅。'),
        '希望对你有所帮助这句话,是 AI 的口头禅。',
      );
    });

    test('连续空行最多留一个', () {
      expect(cleanMarkdownForDisplay('a\n\n\n\n\nb'), 'a\n\nb');
      expect(cleanMarkdownForDisplay('a\n\n\n\n\n\n\n\nb'), 'a\n\nb');
    });

    test('空/纯空白 → 空串', () {
      expect(cleanMarkdownForDisplay(''), '');
      expect(cleanMarkdownForDisplay('   '), '');
      expect(cleanMarkdownForDisplay('\n\n  \n\t\n'), '');
      expect(cleanMarkdownForDisplay('\r\n\r\n'), '');
    });

    test('整条都是客套时不清空(宁可显示原文,也不能给用户一片空白)', () {
      const only = '好的,以下是内容';
      expect(cleanMarkdownForDisplay(only), only);
      expect(cleanMarkdownForDisplay('希望对你有所帮助'), '希望对你有所帮助');
    });

    test('清洗结果不会二次变化(幂等:清两遍 = 清一遍)', () {
      const raw = '好的,以下是解析:\n\n＃＃ 标题\n\n**重点**内容\n\n• 项目一\n\n'
          '这是**半截\n\n\n\n希望对你有所帮助';
      final once = cleanMarkdownForDisplay(raw);
      expect(cleanMarkdownForDisplay(once), once);
    });
  });

  group('bookmarkLengthLabel', () {
    test('中文按字、英文按词、空内容说实话', () {
      expect(bookmarkLengthLabel('这是一段中文内容'), '8 字');
      expect(bookmarkLengthLabel('Hello world, this is a test.'), '6 词');
      expect(bookmarkLengthLabel(''), '没有正文');
      expect(bookmarkLengthLabel('   \n '), '没有正文');
    });
  });

  // ─────────────────────────────────────────────────────────
  // 阅读页
  // ─────────────────────────────────────────────────────────
  group('阅读页', () {
    Future<void> pumpReader(WidgetTester tester, Bookmark b) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<BookmarkProvider>(
          create: (_) => BookmarkProvider(),
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => BookmarkReaderScreen(bookmark: b),
                      ),
                    ),
                    child: const Text('打开收藏'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开收藏'));
      await tester.pumpAndSettle();
    }

    testWidgets('正文按 Markdown 渲染:星号/井号不再裸奔,标题真的成了标题', (tester) async {
      await pumpReader(
        tester,
        bookmark(
          content: '## 词的用法\n\n**unfettered** 表示「无拘无束的」。\n\n'
              '- 例句一\n- 例句二\n\n希望对你有所帮助',
        ),
      );

      final plain = plainText(tester);
      expect(plain, contains('词的用法'));
      expect(plain, contains('unfettered'));
      expect(plain, contains('例句一'));
      expect(plain, isNot(contains('**')), reason: '裸奔的加粗标记不能出现在屏幕上');
      expect(plain, isNot(contains('##')), reason: '裸奔的标题标记不能出现在屏幕上');
      expect(plain, isNot(contains('- 例句一')), reason: '列表渲染后不该还带着 "- "');
      expect(plain, isNot(contains('希望对你有所帮助')), reason: '结尾客套已被清掉');
    });

    testWidgets('顶部信息卡:来源徽标 + 标题 + 时间 + 字数', (tester) async {
      await pumpReader(
        tester,
        bookmark(
          title: 'unfettered 的用法',
          source: AppConstants.bookmarkSourceVocab,
          sourceWord: 'unfettered',
          content: 'unfettered\n释义:无拘束的',
        ),
      );
      expect(find.text('词汇收藏'), findsOneWidget, reason: 'AppBar 标题带来源');
      expect(find.text('词汇'), findsOneWidget, reason: '来源徽标');
      expect(find.text('unfettered 的用法'), findsOneWidget);
      expect(find.textContaining('2026-10-04 20:15'), findsOneWidget);
      expect(find.textContaining('原词 unfettered'), findsOneWidget);
      expect(find.textContaining('deepseek-v4-flash'), findsOneWidget);
    });

    testWidgets('四种来源各有各的徽标文案', (tester) async {
      for (final pair in <List<String>>[
        [AppConstants.bookmarkSourceVocab, '词汇收藏'],
        [AppConstants.bookmarkSourceFollowUp, '对话收藏'],
        [AppConstants.bookmarkSourceArticle, '文章收藏'],
        [AppConstants.bookmarkSourceWriting, '写译收藏'],
      ]) {
        // 每个来源单独一棵树:pumpWidget 会复用同类型的 State(Navigator 的路由栈
        // 也会留着),所以先关掉阅读页再重开,免得第二条用例还在看第一条的内容
        await pumpReader(
          tester,
          bookmark(source: pair[0], title: '标题', content: '正文'),
        );
        expect(find.text(pair[1]), findsOneWidget, reason: '来源 ${pair[0]}');
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('复制全文:复制的是清洗后的正文(没有裸符号)', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpReader(
        tester,
        bookmark(content: '## 标题\n\n**重点**在这里'),
      );
      await tester.tap(find.text('复制全文'));
      await tester.pumpAndSettle();

      final setData =
          calls.firstWhere((c) => c.method == 'Clipboard.setData');
      final text = (setData.arguments as Map)['text'] as String;
      expect(text, contains('标题'));
      // 复制保留 Markdown 结构(方便贴到别处仍能成文),但 AI 客套已经被清掉
      expect(text, contains('**重点**在这里'));
      expect(find.text('已复制全文'), findsOneWidget);
    });

    testWidgets('空正文有兜底(不显示一块白板)', (tester) async {
      await pumpReader(tester, bookmark(content: '   \n\n  '));
      expect(find.text('这条收藏没有正文'), findsOneWidget);
      expect(find.text('复制全文'), findsOneWidget, reason: '动作条照旧,别让用户无路可走');
    });

    testWidgets('删除:先弹确认;确认后关闭阅读页并给出撤销入口', (tester) async {
      await pumpReader(tester, bookmark(content: '正文内容'));
      await tester.tap(find.widgetWithText(OutlinedButton, '删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除收藏'), findsOneWidget, reason: '危险操作必须先确认');
      expect(find.textContaining('删除后不可恢复'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.byType(BookmarkReaderScreen), findsNothing,
          reason: '删掉后应该退回收藏列表');
      expect(find.text('打开收藏'), findsOneWidget);
      expect(find.text('已删除收藏'), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget, reason: '删除要可反悔');

      // 放掉 SnackBar 的定时器
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
    });

    testWidgets('取消删除:什么都不发生,人还在阅读页', (tester) async {
      await pumpReader(tester, bookmark(content: '正文内容'));
      await tester.tap(find.widgetWithText(OutlinedButton, '删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(BookmarkReaderScreen), findsOneWidget);
      expect(find.text('已删除收藏'), findsNothing);
    });

    testWidgets('关闭按钮回到列表', (tester) async {
      await pumpReader(tester, bookmark(content: '正文内容'));
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(BookmarkReaderScreen), findsNothing);
    });

    testWidgets('正文可以长按选择(SelectionArea 在树上)', (tester) async {
      await pumpReader(tester, bookmark(content: '这是一段可以选中的正文。'));
      expect(find.byType(SelectionArea), findsWidgets);
    });
  });
}
