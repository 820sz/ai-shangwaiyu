import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/services/material_library.dart';
import 'package:readflow/widgets/material_result_list.dart';

/// 公共结果件(分组 / 分页 / 卡片 / 控制器)的单测(2026-11-06)。
///
/// 频道页与「自由搜 / 按需找」两个新结果页**共用**这一份实现,所以这里钉住的是
/// "三个入口行为一致"的底座:
/// - 分页数学(0 条=1 页、夹紧、区间);
/// - 分组顺序与组内排序(有真实覆盖率的在前 → 权威度 → 原始顺序);
/// - 页内分组切片(全局页码 + 页内小标题,不重复不丢条);
/// - 类型推断(教材/真题靠标题关键词);
/// - 卡片:无真封面时**不许画图**(用户本轮硬规则);
/// - 页码控件首末页禁用、点击回调;
/// - 控制器:去重合并 / 追加跳页 / 分页夹紧。
void main() {
  setUp(() {
    // 2026-11-07:卡片会对"没有 imageUrl"的结果做页面级封面懒加载。
    // 单测/渲染不许真打网络 —— 默认注入"抓不到",需要验证的用例自己换实现。
    MaterialCoverProbeCache.debugReset();
    MaterialCoverProbeCache.debugOverride = (_) async => null;
  });

  tearDown(MaterialCoverProbeCache.debugReset);

  group('分页纯函数', () {
    test('0 条也算 1 页,永远不出现 第 1 / 0 页', () {
      expect(materialResultPageCount(0), 1);
      expect(materialResultPageCount(1), 1);
      expect(materialResultPageCount(10), 1);
      expect(materialResultPageCount(11), 2);
      expect(materialResultPageCount(21), 3);
    });

    test('页码夹紧:越界回最后一页,负数回第 0 页', () {
      expect(materialResultPageClamp(-3, 11), 0);
      expect(materialResultPageClamp(5, 11), 1);
      expect(materialResultPageClamp(1, 11), 1);
      expect(materialResultPageClamp(0, 11), 0);
      expect(materialResultPageClamp(9, 0), 0);
    });

    test('页区间 [start, end)', () {
      expect(materialResultPageRange(0, 12), (start: 0, end: 10));
      expect(materialResultPageRange(1, 12), (start: 10, end: 12));
      expect(materialResultPageRange(2, 12), (start: 10, end: 12),
          reason: '越界页要夹回最后一页,而不是给空区间');
      expect(materialResultPageRange(0, 0), (start: 0, end: 0));
    });
  });

  group('分组 + 组内排序', () {
    MaterialAnalysis analysisOf(double coverage) => MaterialAnalysis(
          wordCount: 1000,
          uniqueWords: 400,
          newTypes: 50,
          estMinutes: 6,
          coverage: coverage,
          knownTokenRatio: coverage,
          newWordDensity: 5,
          cefr: 'B1',
          topNewWords: const <String>[],
        );

    MaterialResultItem item(
      String title, {
      required String kind,
      double? coverage,
      int authority = -1,
      int seq = 0,
    }) =>
        MaterialResultItem(
          title: title,
          url: 'https://example.com/$title',
          sourceLabel: 'test',
          kind: kind,
          seq: seq,
          authority: authority,
          analysis: coverage == null ? null : analysisOf(coverage),
        );

    test('组顺序固定:教材 → 真题 → 书籍 → 论文 → 外刊/新闻 → 文章 → 其他', () {
      final groups = groupMaterialResultItems<MaterialResultItem>(
        <MaterialResultItem>[
          item('a', kind: 'article'),
          item('b', kind: 'news'),
          item('c', kind: 'book'),
          item('d', kind: 'textbook'),
          item('e', kind: 'exam'),
          item('f', kind: 'paper'),
        ],
        kindOf: (i) => i.kind,
        coverageOf: (i) => i.analysis?.knownTokenRatio,
        authorityOf: (i) => i.authority,
        seqOf: (i) => i.seq,
      );
      expect(
        groups.map((g) => g.label).toList(),
        <String>['教材', '应试真题', '书籍', '论文', '外刊/新闻', '文章'],
      );
    });

    test('组内有真实覆盖率的在前(降序),没有分析的排后面', () {
      final groups = groupMaterialResultItems<MaterialResultItem>(
        <MaterialResultItem>[
          item('无分析', kind: 'article'),
          item('低', kind: 'article', coverage: 0.90),
          item('高', kind: 'article', coverage: 0.99),
        ],
        kindOf: (i) => i.kind,
        coverageOf: (i) => i.analysis?.knownTokenRatio,
        authorityOf: (i) => i.authority,
        seqOf: (i) => i.seq,
      );
      final names = groups.first.items.map((i) => i.title).toList();
      expect(names.first, '高');
      expect(names.last, '无分析');
    });

    test('同分按权威度降序、再按原始顺序(稳定)', () {
      final groups = groupMaterialResultItems<MaterialResultItem>(
        <MaterialResultItem>[
          item('权威0', kind: 'article', authority: 0, seq: 1),
          item('权威3', kind: 'article', authority: 3, seq: 2),
          item('同权威先来', kind: 'article', authority: 3, seq: 0),
        ],
        kindOf: (i) => i.kind,
        coverageOf: (i) => i.analysis?.knownTokenRatio,
        authorityOf: (i) => i.authority,
        seqOf: (i) => i.seq,
      );
      expect(
        groups.first.items.map((i) => i.title).toList(),
        <String>['同权威先来', '权威3', '权威0'],
      );
    });

    test('页内分组切片:全局页码,页内小标题,总数不丢不重', () {
      final groups = groupMaterialResultItems<MaterialResultItem>(
        <MaterialResultItem>[
          for (var i = 0; i < 8; i++) item('教材$i', kind: 'textbook', seq: i),
          for (var i = 0; i < 7; i++) item('真题$i', kind: 'exam', seq: 8 + i),
        ],
        kindOf: (i) => i.kind,
        coverageOf: (i) => i.analysis?.knownTokenRatio,
        authorityOf: (i) => i.authority,
        seqOf: (i) => i.seq,
      );
      final page0 = materialResultPageSlices(groups, 0, 15);
      final page1 = materialResultPageSlices(groups, 1, 15);
      expect(page0.fold<int>(0, (sum, s) => sum + s.items.length), 10);
      expect(page1.fold<int>(0, (sum, s) => sum + s.items.length), 5);
      // 第 2 页(0 基 1)只剩真题组的后 5 条,组名与总数仍在
      expect(page1.length, 1);
      expect(page1.first.label, '应试真题');
      expect(page1.first.groupTotal, 7);
      expect(page1.first.items.length, 5);
    });
  });

  group('类型推断与卡片胶囊', () {
    test('教材/真题靠标题关键词分出来,已有 kind 不覆盖', () {
      expect(inferMaterialKind('CET-4 真题 2024', 'https://x/cet4'), 'exam');
      expect(inferMaterialKind('新概念英语 第三册', 'https://x/nce'), 'textbook');
      expect(inferMaterialKind('Climate change', 'https://x/a'), 'article');
      expect(
        inferMaterialKind('Climate change', 'https://x/a', fallback: 'news'),
        'news',
      );
    });

    test('卡片胶囊用分组口径,其他类型回落材料库文案', () {
      expect(materialResultKindChipLabel('textbook'), '教材');
      expect(materialResultKindChipLabel('exam'), '应试真题');
      expect(materialResultKindChipLabel('news'), '外刊/新闻');
      expect(materialResultKindChipLabel('unknown-kind'), isNotEmpty);
    });
  });

  group('卡片:没有真封面就不画图(用户硬规则)', () {
    testWidgets('无 imageUrl → 不出现任何 Image,标题/来源/类型仍在', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MaterialResultCard(
                title: 'Climate Change and Coastal Cities',
                url: 'https://example.com/a',
                sourceLabel: 'NPR News',
                kind: 'news',
                snippet: '海平面上升正在改变沿海城市的基础设施规划。',
                onRead: () {},
                onSave: () {},
                onOpenOriginal: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('Climate Change and Coastal Cities'), findsOneWidget);
      expect(find.text('NPR News'), findsOneWidget);
      expect(find.text('开始读'), findsOneWidget);
      expect(find.text('保存到我的'), findsOneWidget);
      expect(find.text('打开原文'), findsOneWidget);
    });
  });

  group('页码控件', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      required int page,
      required int pageCount,
      required ValueChanged<int> onGo,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: MaterialResultPageBar(
              page: page,
              pageCount: pageCount,
              total: 12,
              onGo: onGo,
            ),
          ),
        ),
      );
    }

    testWidgets('首页:上一页禁用(点了不回调),下一页可点', (tester) async {
      final calls = <int>[];
      await pumpBar(tester, page: 0, pageCount: 2, onGo: calls.add);
      expect(find.text('第 1 / 2 页'), findsOneWidget);
      await tester.tap(find.text('上一页'));
      expect(calls, isEmpty);
      await tester.tap(find.text('下一页'));
      expect(calls, <int>[1]);
    });

    testWidgets('末页:下一页禁用', (tester) async {
      final calls = <int>[];
      await pumpBar(tester, page: 1, pageCount: 2, onGo: calls.add);
      expect(find.text('第 2 / 2 页'), findsOneWidget);
      await tester.tap(find.text('下一页'));
      expect(calls, isEmpty);
      await tester.tap(find.text('上一页'));
      expect(calls, <int>[0]);
    });
  });

  group('MaterialResultList', () {
    MaterialResultItem item(String title, String kind, int seq) =>
        MaterialResultItem(
          title: title,
          url: 'https://example.com/$title',
          sourceLabel: 'test',
          kind: kind,
          seq: seq,
        );

    testWidgets('12 条 → 2 页;页内分组小标题 + 页码控件都在', (tester) async {
      final items = <MaterialResultItem>[
        for (var i = 0; i < 6; i++) item('教材$i', 'textbook', i),
        for (var i = 0; i < 6; i++) item('真题$i', 'exam', 6 + i),
      ];
      final pages = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MaterialResultList(
                items: items,
                page: 0,
                busyUrl: null,
                onPageChanged: pages.add,
                onRead: (_) {},
                onSave: (_) {},
                onOpenOriginal: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('第 1 / 2 页'), findsOneWidget);
      // 组标题和每张卡的类型胶囊都会出现「教材」→ 这里只要求"有分组"
      expect(find.text('教材'), findsWidgets);
      expect(find.text('第 2 页'), findsNothing);
      await tester.ensureVisible(find.text('下一页'));
      await tester.pump();
      await tester.tap(find.text('下一页'));
      expect(pages, <int>[1]);
    });
  });

  group('MaterialResultController:合并/去重/分页', () {
    MaterialResultItem item(String url, {int seq = 0}) => MaterialResultItem(
          title: url,
          url: url,
          sourceLabel: 'test',
          kind: 'article',
          seq: seq,
        );

    test('首轮替换、追加去重、追加后跳到第一条新结果所在页', () async {
      final controller = MaterialResultController(storeId: 'test:all');
      await controller.applyRun(
        fresh: <MaterialResultItem>[
          for (var i = 0; i < 10; i++) item('https://a.com/$i', seq: i),
        ],
        queriesUsed: const <String>['q'],
        runApiRequests: 0,
        runCostCny: 0,
        runNotes: const <String>[],
      );
      expect(controller.items.length, 10);
      expect(controller.page, 0);
      expect(controller.pageCount, 1);

      // 同一批再跑一次(替换):不会翻倍
      await controller.applyRun(
        fresh: <MaterialResultItem>[
          for (var i = 0; i < 10; i++) item('https://a.com/$i', seq: i),
        ],
        queriesUsed: const <String>['q'],
        runApiRequests: 0,
        runCostCny: 0,
        runNotes: const <String>[],
      );
      expect(controller.items.length, 10);

      // 追加 3 条新的(含 1 条重复)→ 只加 2 条,并跳到第一条新结果所在页
      await controller.applyRun(
        fresh: <MaterialResultItem>[
          item('https://a.com/0', seq: 10),
          item('https://a.com/new-1', seq: 11),
          item('https://a.com/new-2', seq: 12),
        ],
        queriesUsed: const <String>['q2'],
        runApiRequests: 1,
        runCostCny: 0.005,
        runNotes: const <String>['note'],
        append: true,
      );
      expect(controller.items.length, 12);
      expect(controller.pageCount, 2);
      expect(controller.page, 1, reason: '追加后应跳到第一条新结果所在页');
      expect(controller.apiRequests, 1);
      expect(controller.costCny, closeTo(0.005, 1e-9));
      controller.dispose();
    });

    test('goPage 越界夹紧', () {
      final controller = MaterialResultController(storeId: 'test:all');
      controller.items.addAll(<MaterialResultItem>[
        for (var i = 0; i < 3; i++) item('https://b.com/$i', seq: i),
      ]);
      controller.goPage(5);
      expect(controller.page, 0);
      controller.dispose();
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // 封面懒加载(2026-11-07 用户真机反馈第 5 条:材料卡普遍不显示封面)
  // ═════════════════════════════════════════════════════════════════════
  group('封面懒加载:能抓到就显示,抓不到不画假封面', () {
    Future<void> pumpCard(
      WidgetTester tester,
      MaterialResultCard card,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(child: card),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    MaterialResultCard card({
      String? imageUrl,
      String url = 'https://example.com/article',
      bool enableLazyCoverFetch = true,
    }) =>
        MaterialResultCard(
          title: 'Climate Change and Coastal Cities',
          url: url,
          sourceLabel: 'NPR News',
          kind: 'news',
          snippet: '海平面上升正在改变沿海城市的基础设施规划。',
          imageUrl: imageUrl,
          enableLazyCoverFetch: enableLazyCoverFetch,
          onRead: () {},
          onSave: () {},
          onOpenOriginal: () {},
        );

    testWidgets('有 imageUrl → 直接显示真封面,不发探测请求', (tester) async {
      var probes = 0;
      MaterialCoverProbeCache.debugOverride = (_) async {
        probes++;
        return null;
      };
      await pumpCard(
        tester,
        card(imageUrl: 'https://cdn.example.com/cover.jpg'),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(probes, 0, reason: '已有封面就不该再抓页面');
    });

    testWidgets('imageUrl 空 → 懒加载拿到 og:image 后显示缩略图', (tester) async {
      MaterialCoverProbeCache.debugOverride =
          (_) async => 'https://cdn.example.com/og-cover.jpg';
      await pumpCard(tester, card());
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('抓不到 → 保持文字版式(没有 Image,更没有渐变假封面)', (tester) async {
      MaterialCoverProbeCache.debugOverride = (_) async => null;
      await pumpCard(tester, card());
      expect(find.byType(Image), findsNothing);
      expect(find.text('Climate Change and Coastal Cities'), findsOneWidget);
      expect(find.text('NPR News'), findsWidgets);
    });

    testWidgets('同一 URL 只抓一次(会话内缓存,翻页/重建不重复打站点)',
        (tester) async {
      var probes = 0;
      MaterialCoverProbeCache.debugOverride = (_) async {
        probes++;
        return 'https://cdn.example.com/og-cover.jpg';
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  card(),
                  card(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(probes, 1, reason: '同 URL 的第二次卡片必须命中缓存');
    });

    testWidgets('公版书按书号现算封面(零网络);enableLazyCoverFetch=false 完全不探测',
        (tester) async {
      var probes = 0;
      MaterialCoverProbeCache.debugOverride = (_) async {
        probes++;
        return null;
      };
      await pumpCard(
        tester,
        card(url: 'https://www.gutenberg.org/ebooks/1342'),
      );
      expect(find.byType(Image), findsOneWidget,
          reason: 'Gutenberg 书号能直接推出官方封面,不该等网络');
      expect(probes, 0);

      await pumpCard(tester, card(enableLazyCoverFetch: false));
      expect(find.byType(Image), findsNothing);
      expect(probes, 0);
    });

    testWidgets('探测结果是脏 URL(非 http) → 丢弃,不显示假封面', (tester) async {
      MaterialCoverProbeCache.debugOverride = (_) async => 'ftp://bad/cover.jpg';
      await pumpCard(tester, card());
      expect(find.byType(Image), findsNothing);
    });
  });
}
