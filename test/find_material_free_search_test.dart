import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/free_search_screen.dart';
import 'package:readflow/services/material_ai_rewrite.dart';
import 'package:readflow/services/original_search.dart';
import 'package:readflow/widgets/material_result_list.dart';

/// 自由搜(2026-11-07 第三轮 · 用户真机反馈第 4 条)的交互单测。
///
/// 覆盖三件事:
/// 1. 顶部输入框**不裁字**(真机截过:输入后文字上半截被圆角框切掉);
/// 2. 筛选区**默认收起**、可展开/收起、搜索后自动收起(真机:悬置挡半屏且关不掉);
/// 3. 没找到原文时:先用真实检索信息说明原因,再给「AI 改写学习版(非原文)」
///    保底链路(注入 handler/measurer,单测不碰网络、不碰词频库)。
void main() {
  setUp(() {
    // 卡片封面懒加载在单测里彻底禁用网络:注入"抓不到"的实现(确定性)
    MaterialCoverProbeCache.debugReset();
    MaterialCoverProbeCache.debugOverride = (_) async => null;
  });

  tearDown(MaterialCoverProbeCache.debugReset);

  void phoneView(WidgetTester tester, {double height = 844}) {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: screen),
    );
    // 有界 pump(fake-async 里不用 pumpAndSettle 死等)
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  List<MaterialResultItem> freeItems() => <MaterialResultItem>[
        MaterialResultItem(
          title: 'Climate Change and Coastal Cities',
          url: 'https://example.com/npr/climate',
          sourceLabel: 'NPR News',
          kind: 'news',
          snippet: 'NPR 报道:海平面上升正在改变沿海城市的基础设施规划。',
          seq: 0,
          estimateLabel: '预计 B1~B2 · 中等',
        ),
        MaterialResultItem(
          title: 'The Future of Language Learning',
          url: 'https://example.com/npr/learning',
          sourceLabel: 'NPR News',
          kind: 'news',
          snippet: '教育技术报道:AI 正在如何改变外语学习者的输入方式。',
          seq: 1,
          estimateLabel: '预计 B1~B2 · 中等',
        ),
      ];

  const sources = <AiRewriteSource>[
    AiRewriteSource(
      title: 'Atomic Habits — James Clear',
      url: 'https://example.com/atomic-habits',
      site: 'example.com',
      snippet: '习惯养成与微小改变。',
      kind: 'book',
    ),
    AiRewriteSource(
      title: 'How Tiny Habits Work',
      url: 'https://example.org/tiny-habits',
      site: 'example.org',
      snippet: '行为设计。',
      kind: 'article',
    ),
  ];

  String aiBody() => List<String>.generate(
        140,
        (i) => i.isEven ? 'habit' : 'change',
      ).join(' ');

  String validAiJson() => '```json\n'
      '{"topic": "Small Habits, Big Changes", '
      '"title_cn": "微小习惯,巨大改变", '
      '"summary_cn": "基于搜索线索改写的学习版,不是原文。", '
      '"body": "${aiBody()}", '
      '"used_sources": [1, 2]}\n```';

  MaterialAiRewriter fakeRewriter({
    String? content,
    bool noAnswer = false,
    bool throwError = false,
  }) =>
      MaterialAiRewriter(
        handler: (_, _) async {
          if (throwError) throw Exception('network down');
          if (noAnswer) return null;
          return content ?? validAiJson();
        },
        measurer: (_) async => const AiRewriteMeasurement(
          wordCount: 140,
          estMinutes: 2,
          coverage: 0.955,
          cefr: 'B1',
        ),
      );

  group('顶部输入框不再裁字（真机反馈第 4 条 ①）', () {
    testWidgets('输入长中英混合关键词:无布局异常,文字区高度容得下整行',
        (tester) async {
      phoneView(tester);
      await pumpScreen(
        tester,
        const FreeSearchScreen(initialQuery: '原子习惯 atomic habits practice'),
      );
      expect(tester.takeException(), isNull);

      final field = tester.getSize(find.byType(TextField));
      expect(field.height, greaterThanOrEqualTo(40),
          reason: '搜索框内高必须 >= 文字行高 + 上下内边距,否则会裁字');
      final editable = tester.getSize(find.byType(EditableText));
      // 字号 13 + 行高 1.35 ≈ 17.6;真机裁字时这里会被压到更小
      expect(editable.height, greaterThanOrEqualTo(17),
          reason: '输入区高度不足以显示 13px 行高 → 上半截会被裁掉');

      // 全局 InputDecorationTheme 是"填充+描边"表单样式:搜索框必须显式关掉,
      // 否则输入文字外会多套一个灰色圆角框(真机截图里很明显)
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.decoration?.filled, isFalse);
      expect(textField.decoration?.border, InputBorder.none);
      expect(textField.decoration?.enabledBorder, InputBorder.none);
      expect(textField.decoration?.focusedBorder, InputBorder.none);

      await tester.enterText(find.byType(TextField), 'climate change 与城市规划');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('搜索按钮与输入框同高,行内不溢出', (tester) async {
      phoneView(tester);
      await pumpScreen(tester, const FreeSearchScreen());
      final button = tester.getSize(find.byType(FilledButton).first);
      expect(button.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });
  });

  group('筛选区默认收起、可展开/收起（真机反馈第 4 条 ②）', () {
    testWidgets('默认只有一行「筛选」;点开出现面板,再点收起', (tester) async {
      phoneView(tester);
      await pumpScreen(tester, const FreeSearchScreen());
      expect(find.byKey(const ValueKey('free-filter-panel')), findsNothing);
      expect(find.text('筛选'), findsOneWidget);
      expect(find.text('来源'), findsNothing, reason: '默认不应展开筛选分组');

      await tester.tap(find.byKey(const ValueKey('free-filter-toggle')));
      await tester.pump();
      expect(find.byKey(const ValueKey('free-filter-panel')), findsOneWidget);
      expect(find.text('来源'), findsOneWidget);
      expect(find.text('难度'), findsOneWidget);
      expect(find.text('场景'), findsOneWidget);
      expect(find.text('收起筛选'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('free-filter-collapse')));
      await tester.pump();
      expect(find.byKey(const ValueKey('free-filter-panel')), findsNothing);
    });

    testWidgets('选了条件 → 收起后显示「筛选(1)」+ 条件摘要 chip', (tester) async {
      phoneView(tester);
      await pumpScreen(tester, const FreeSearchScreen());
      await tester.tap(find.byKey(const ValueKey('free-filter-toggle')));
      await tester.pump();
      await tester.ensureVisible(find.text('书籍'));
      await tester.tap(find.text('书籍'));
      await tester.pump();
      expect(find.text('筛选(1)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('free-filter-collapse')));
      await tester.pump();
      expect(find.byKey(const ValueKey('free-filter-panel')), findsNothing);
      expect(find.text('筛选(1)'), findsOneWidget);
      // 收起态还应该能看到已选条件摘要(点一下可清掉)
      expect(find.text('书籍'), findsOneWidget);
      expect(find.text('清空'), findsOneWidget);
    });

    testWidgets('搜索一开始就自动收起筛选面板', (tester) async {
      phoneView(tester);
      await pumpScreen(
        tester,
        FreeSearchScreen(
          initialQuery: 'climate change',
          debugRun: ({
            required String query,
            required String kind,
            required String band,
            required Set<String> sourceIds,
          }) async =>
              FreeSearchRun(
            items: freeItems(),
            rawHits: 2,
            sources: sources,
            searchedSourceLabels: const <String>['NPR News'],
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('free-filter-toggle')));
      await tester.pump();
      expect(find.byKey(const ValueKey('free-filter-panel')), findsOneWidget);

      await tester.tap(find.text('搜索'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('free-filter-panel')), findsNothing,
          reason: '结果出来后筛选区必须自动收起');
      expect(find.text('第 1 / 1 页'), findsOneWidget);
      expect(find.text('Climate Change and Coastal Cities'), findsOneWidget);
    });
  });

  group('没找到原文:真实原因 + AI 改写保底（真机反馈第 4 条 ③）', () {
    Widget emptyScreen({MaterialAiRewriter? rewriter, List<AiRewriteSource>? src}) =>
        FreeSearchScreen(
          initialQuery: '原子习惯',
          initialResults: const <MaterialResultItem>[],
          debugSources: src ?? sources,
          debugNotes: const <String>[
            'Project Gutenberg:没有匹配的原文(换个英文关键词试试)',
            '中文关键词:公版书与论文库只认英文',
          ],
          aiRewriter: rewriter,
        );

    testWidgets('说清"为什么没找到"(真实命中数/源说明),并给 AI 入口', (tester) async {
      phoneView(tester);
      await pumpScreen(tester, emptyScreen());
      expect(find.text('这次没找到能读的结果'), findsOneWidget);
      expect(find.textContaining('没有可读正文'), findsWidgets);
      expect(find.textContaining('原始命中 2 条'), findsOneWidget);
      expect(find.textContaining('Project Gutenberg'), findsWidgets);
      expect(find.textContaining('依据:2 条真实线索'), findsOneWidget);
      expect(find.text('生成 AI 改写学习版(非原文)'), findsOneWidget);
    });

    testWidgets('线索少于 2 条要明说"依据有限",不装充分', (tester) async {
      phoneView(tester);
      await pumpScreen(
        tester,
        emptyScreen(src: <AiRewriteSource>[sources.first]),
      );
      expect(find.textContaining('依据有限'), findsWidgets);
    });

    testWidgets('没有任何线索时仍可生成(按主题写,不冒充来源)', (tester) async {
      phoneView(tester);
      await pumpScreen(
        tester,
        const FreeSearchScreen(
          initialQuery: 'zzz',
          initialResults: <MaterialResultItem>[],
        ),
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '生成 AI 改写学习版(非原文)'),
      );
      expect(button.onPressed, isNotNull, reason: '2026-11-08 用户要求兜底必须可用');
    });

    testWidgets('点生成 → 出现"AI 改写学习版(非原文)"卡:标注/来源/真实字数/难度/可读可存',
        (tester) async {
      phoneView(tester);
      await pumpScreen(
        tester,
        emptyScreen(rewriter: fakeRewriter()),
      );
      final generate = find.text('生成 AI 改写学习版(非原文)');
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // 2026-11-08：生成前先弹「字数/难度」选项，这里用默认值直接开始生成。
      await tester.pump(const Duration(milliseconds: 400));
      final confirm =
          find.text('开始生成 AI 改写学习版（非原文）');
      expect(confirm, findsOneWidget, reason: '应先弹改写选项');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('AI 改写学习版(非原文)'), findsOneWidget);
      expect(find.text('Small Habits, Big Changes'), findsOneWidget);
      expect(find.text('微小习惯,巨大改变'), findsOneWidget);
      expect(find.textContaining('全文 140 词'), findsOneWidget);
      expect(find.textContaining('覆盖率 96%'), findsOneWidget);
      expect(find.textContaining('条真实来源'), findsOneWidget);
      expect(find.text('开始读'), findsOneWidget);
      expect(find.text('保存到我的'), findsOneWidget);
      expect(find.text('重新生成'), findsOneWidget);
    });

    testWidgets('模型失败 → 人话原因 + 重试(不假装生成成功)', (tester) async {
      phoneView(tester);
      await pumpScreen(
        tester,
        emptyScreen(rewriter: fakeRewriter(noAnswer: true)),
      );
      final generate = find.text('生成 AI 改写学习版(非原文)');
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 400));
      final confirm =
          find.text('开始生成 AI 改写学习版（非原文）');
      expect(confirm, findsOneWidget, reason: '应先弹改写选项');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.textContaining('API'), findsWidgets);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('AI 改写学习版(非原文)'), findsNothing);
    });

    testWidgets('有原文时:原文优先显示,AI 只是明确分隔的可选兜底(不混淆)', (tester) async {
      phoneView(tester, height: 1600);
      await pumpScreen(
        tester,
        FreeSearchScreen(
          initialQuery: 'climate change',
          initialResults: freeItems(),
          aiRewriter: fakeRewriter(),
        ),
      );
      expect(find.text('Climate Change and Coastal Cities'), findsOneWidget);
      expect(find.text('第 1 / 1 页'), findsOneWidget);
      expect(find.text('这些都不合适?'), findsOneWidget);
      expect(find.text('AI 改写 · 非原文'), findsOneWidget);
      // AI 兜底在原文结果**下面**(不抢原文位置)
      final originalTop = tester.getTopLeft(
        find.text('Climate Change and Coastal Cities'),
      );
      final aiTop = tester.getTopLeft(find.text('这些都不合适?'));
      expect(aiTop.dy, greaterThan(originalTop.dy));
      // 没有自动生成(不花钱、不混淆)
      expect(find.text('AI 改写学习版(非原文)'), findsNothing);
    });
  });

  group('搜索过程与结果页(回归)', () {
    testWidgets('注入运行结果后:过程卡可折叠 + 结果卡三动作都在', (tester) async {
      phoneView(tester);
      await pumpScreen(
        tester,
        FreeSearchScreen(
          initialQuery: 'climate change',
          initialResults: freeItems(),
          initialEvents: <SearchEvent>[
            const SearchEvent(stage: SearchStage.searching, label: 'NPR News:5 条'),
          ],
        ),
      );
      expect(find.textContaining('搜索过程 · 1 步'), findsOneWidget);
      // 初始是展开的(带事件进入):先看到真实进度,再点收起
      expect(find.textContaining('NPR News:5 条'), findsWidgets);
      await tester.tap(find.textContaining('搜索过程 · 1 步'));
      await tester.pump();
      expect(find.textContaining('NPR News:5 条'), findsNothing);
      await tester.tap(find.textContaining('搜索过程 · 1 步'));
      await tester.pump();
      expect(find.textContaining('NPR News:5 条'), findsWidgets);
      expect(find.text('开始读'), findsWidgets);
      expect(find.text('保存到我的'), findsWidgets);
      expect(find.text('打开原文'), findsWidgets);
    });
  });
}
