import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/design_tokens.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/config/v4_theme.dart';
import 'package:readflow/models/learner_model.dart';
import 'package:readflow/screens/input/find_material_screen.dart';
import 'package:readflow/screens/input/free_search_screen.dart';
import 'package:readflow/screens/input/need_search_screen.dart';
import 'package:readflow/services/find_need_context.dart';
import 'package:readflow/services/input_prefs.dart';
import 'package:readflow/services/material_ai_rewrite.dart';
import 'package:readflow/services/material_library.dart';
import 'package:readflow/services/material_need.dart';
import 'package:readflow/services/material_prefs.dart';
import 'package:readflow/services/tutor_insights.dart';
import 'package:readflow/widgets/design_kit.dart';
import 'package:readflow/widgets/material_result_list.dart';

/// 「找材料」实施版 · **逐屏真实渲染**(2026-11-06)。
///
/// 与设计稿 6 张预览图的区别:这 8 张跑的是**生产代码**
/// (`FindMaterialScreen` / `FreeSearchScreen` / `NeedSearchScreen` /
/// `MaterialResultList`),只把"网络与本地库"换成注入数据,所以图上看到的
/// 就是用户点进去会看到的样子(字体/图标真实加载,390×844 @3x)。
///
/// 出图:
/// - build/ui_real/find-material-impl-*.png
/// - docs/ui-preview/real/find-material-impl-*.png
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont();
    await _loadIcons();
    // 卡片封面懒加载:渲染测试不碰网络(确定性);"有封面"对照图用注入的
    // 真实图片源(MemoryImage)画,而不是等一个连不上的站点。
    MaterialCoverProbeCache.debugOverride = (_) async => null;
  });

  testWidgets('入口页(并列大卡 + 最近搜过 + 上次结果)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      FindMaterialScreen(
        initialContext: _richContext(),
        initialHistory: const <String>['climate change', 'new concept english', '四六级真题'],
        initialLastRun: FindMaterialLastRun(
          count: 18,
          updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      ),
      'find-material-impl-entry.png',
    );
  });

  testWidgets('自由搜 · 空态(筛选条 + 使用说明)', (tester) async {
    _phoneView(tester);
    await _shoot(tester, const FreeSearchScreen(), 'find-material-impl-free-empty.png');
  });

  testWidgets('自由搜 · 结果页(分组 + 页码 + 无封面文字版式)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      FreeSearchScreen(
        initialQuery: 'climate change',
        initialResults: _freeResults(),
      ),
      'find-material-impl-free-result.png',
    );
  });

  testWidgets('自由搜 · 空结果(源说明 + 再搜一次)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      const FreeSearchScreen(
        initialQuery: 'zzz no match',
        initialResults: <MaterialResultItem>[],
      ),
      'find-material-impl-free-empty-result.png',
    );
  });

  testWidgets('按情况找 · 依据面板(4 行真实数据 + 为什么推这些)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      NeedSearchScreen(initialContext: _richContext()),
      'find-material-impl-need-panel.png',
    );
  });

  testWidgets('按情况找 · 结果页(每卡"为什么推" + 分组 + 页码)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      NeedSearchScreen(
        initialContext: _richContext(),
        initialResults: _needResults(),
      ),
      'find-material-impl-need-result.png',
    );
  });

  testWidgets('自由搜 · 结果页滚到底(页码控件 + 继续找更多)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      FreeSearchScreen(
        initialQuery: 'climate change',
        initialResults: _freeResults(),
      ),
      'find-material-impl-free-pager.png',
      scroll: 1700,
    );
  });

  testWidgets('按情况找 · 结果页滚到底(页码控件 + 继续找更多)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      NeedSearchScreen(
        initialContext: _richContext(),
        initialResults: _needResults(),
      ),
      'find-material-impl-need-pager.png',
      scroll: 3800,
    );
  });

  testWidgets('按情况找 · 缺数据降级(全部「待测」不显示数字)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      NeedSearchScreen(initialContext: _emptyContext()),
      'find-material-impl-need-empty.png',
    );
  });

  testWidgets('卡片版式:无真封面 → 纯文字(不画假封面)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      const _NoCoverGallery(),
      'find-material-impl-no-cover.png',
    );
  });

  testWidgets('搜索历史 sheet(点一条回填搜索 / 可清空)', (tester) async {
    _phoneView(tester);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: FindMaterialScreen(
            initialContext: _richContext(),
            initialHistory: const <String>[
              'climate change',
              'new concept english',
              'CET-4 真题',
              'TED 演讲',
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    await _capture(tester, key, 'find-material-impl-history.png');
  });

  // ═══════════════════════════════════════════════════════════════════
  // 2026-11-07 第三轮(用户真机反馈第 4/5 条)新增渲染
  // ═══════════════════════════════════════════════════════════════════

  testWidgets('自由搜 · 顶部输入框不裁字(长中英混合关键词)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      const FreeSearchScreen(
        initialQuery: '原子习惯 atomic habits 与微小改变 practice',
      ),
      'find-material-impl-free-input.png',
    );
  });

  testWidgets('自由搜 · 筛选面板展开(限高可滚动,可收起)', (tester) async {
    _phoneView(tester);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: const FreeSearchScreen(initialQuery: 'climate change'),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('free-filter-toggle')));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await _capture(tester, key, 'find-material-impl-free-filters.png');
  });

  testWidgets('结果卡 · 有真封面(缩略图)对照', (tester) async {
    _phoneView(tester);
    final bytes = await tester.runAsync(_coverPngBytes);
    expect(bytes, isNotNull);
    final cover = MemoryImage(bytes!);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: _CoverGallery(coverProvider: cover),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    // 测试环境没有网络:把注入的真实图片先解码进内存,截图里才是真缩略图
    await tester.runAsync(() async {
      final context = tester.element(find.byType(MaterialResultCard));
      await precacheImage(cover, context, onError: (error, stackTrace) {});
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _capture(tester, key, 'find-material-impl-cover-with.png');
  });

  testWidgets('结果卡 · 无封面(纯文字版式)对照', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      const _CoverGallery(coverProvider: null),
      'find-material-impl-cover-without.png',
    );
  });

  testWidgets('自由搜 · 没找到原文(真实原因 + AI 改写入口)', (tester) async {
    _phoneView(tester);
    await _shoot(
      tester,
      FreeSearchScreen(
        initialQuery: '原子习惯',
        initialResults: const <MaterialResultItem>[],
        debugSources: _aiSources(),
        debugNotes: const <String>[
          'Project Gutenberg:没有匹配的原文(换个英文关键词试试)',
          '中文关键词:公版书与论文库只认英文',
        ],
        aiRewriter: _fakeAiRewriter(),
      ),
      'find-material-impl-ai-empty.png',
      scroll: 200,
    );
  });

  testWidgets('自由搜 · AI 改写学习版生成结果(标注/来源/字数/可读可存)', (tester) async {
    _phoneView(tester);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: FreeSearchScreen(
            initialQuery: '原子习惯',
            initialResults: const <MaterialResultItem>[],
            debugSources: _aiSources(),
            debugNotes: const <String>[
              'Project Gutenberg:没有匹配的原文(换个英文关键词试试)',
            ],
            aiRewriter: _fakeAiRewriter(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    final generate = find.text('生成 AI 改写学习版(非原文)');
    await tester.ensureVisible(generate);
    await tester.tap(generate);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    // 滚到 AI 结果卡,让"非原文标注 + 来源 + 真实字数/难度 + 按钮"整块入镜
    final vertical = find.byWidgetPredicate(
      (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
    );
    await tester.drag(vertical.first, const Offset(0, -260), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    await _capture(tester, key, 'find-material-impl-ai-generated.png');
  });
}

/// 渲染 AI 改写结果用的**注入式**模型(不碰网络;正文是真的英文段落)。
MaterialAiRewriter _fakeAiRewriter() {
  final body = List<String>.generate(
    180,
    (i) => switch (i % 6) {
      0 => 'habits',
      1 => 'shape',
      2 => 'small',
      3 => 'changes',
      4 => 'every',
      _ => 'day',
    },
  ).join(' ');
  final json = '```json\n'
      '{"topic": "Small Habits, Big Changes", '
      '"title_cn": "微小习惯,巨大改变", '
      '"summary_cn": "这是 AI 基于你这次搜到的线索改写的学习版,不是原文。", '
      '"body": "$body", '
      '"used_sources": [1, 2]}\n```';
  return MaterialAiRewriter(
    handler: (_, _) async => json,
    measurer: (_) async => const AiRewriteMeasurement(
      wordCount: 180,
      estMinutes: 3,
      coverage: 0.955,
      cefr: 'B1',
    ),
  );
}

List<AiRewriteSource> _aiSources() => const <AiRewriteSource>[
      AiRewriteSource(
        title: 'Atomic Habits — James Clear',
        url: 'https://example.com/atomic-habits',
        site: 'example.com',
        snippet: '习惯养成与微小改变:每天进步 1% 的复利效应。',
        kind: 'book',
      ),
      AiRewriteSource(
        title: 'How Tiny Habits Work',
        url: 'https://example.org/tiny-habits',
        site: 'example.org',
        snippet: '行为设计:提示、惯常行为、奖励。',
        kind: 'article',
      ),
    ];

/// 生成一张用于"有封面"对照渲染的 PNG(渐变 + 标题条 + 红色书脊带)。
///
/// 只是渲染验证用的**真实图片**,不是生产兜底:生产路径永远是页面 og:image
/// 的 `Image.network` 或 Gutenberg 官方封面,抓不到就走文字版式。
Future<Uint8List> _coverPngBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(120, 160);
  final paint = Paint()
    ..shader = ui.Gradient.linear(
      Offset.zero,
      const Offset(120, 160),
      <Color>[const Color(0xFF20465B), const Color(0xFF7FB2C9)],
    );
  canvas.drawRect(Offset.zero & size, paint);
  // 顶部标题条(白)+ 红色书脊带 + 底部两行小条:看起来像一张真封面缩略图
  final white = Paint()..color = const Color(0xFFFFFFFF);
  canvas.drawRect(const Rect.fromLTWH(12, 20, 84, 9), white);
  canvas.drawRect(const Rect.fromLTWH(12, 36, 58, 6), white);
  canvas.drawCircle(const Offset(60, 76), 18, Paint()..color = const Color(0x33FFFFFF));
  canvas.drawRect(
    const Rect.fromLTWH(0, 118, 120, 42),
    Paint()..color = const Color(0xFFB23A2C),
  );
  canvas.drawRect(
    const Rect.fromLTWH(8, 130, 70, 6),
    Paint()..color = const Color(0xCCFFFFFF),
  );
  canvas.drawRect(
    const Rect.fromLTWH(8, 142, 44, 5),
    Paint()..color = const Color(0x88FFFFFF),
  );
  final image = await recorder.endRecording().toImage(120, 160);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// "有封面 / 无封面"两种结果卡并排对照(同一张卡、同一套数据形状)。
class _CoverGallery extends StatelessWidget {
  final ImageProvider? coverProvider;

  const _CoverGallery({required this.coverProvider});

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        child: ListView(
          padding:
              const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xl),
          children: <Widget>[
            Text(
              coverProvider == null ? '结果卡 · 没有抓到封面' : '结果卡 · 有真封面',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
                color: skin.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              coverProvider == null
                  ? '抓不到 og:image / 材料本身无图 → 纯文字版式(标题 + 来源/类型/难度),不画渐变假封面。'
                  : '页面 og:image 抓到真图 → 卡片左侧 58×76 圆角缩略图,右侧文字信息不变。',
              style: TextStyle(fontSize: 11, height: 1.5, color: skin.inkSoft),
            ),
            const SizedBox(height: Gap.md),
            MaterialResultCard(
              title: 'Climate Change and Coastal Cities',
              url: 'https://example.com/npr/climate',
              sourceLabel: 'NPR News',
              kind: 'news',
              snippet: 'NPR 报道:海平面上升正在改变沿海城市的基础设施规划与迁移政策。',
              imageUrl: coverProvider == null
                  ? null
                  : 'https://cdn.example.com/og-cover.jpg',
              coverage: 0.96,
              cefr: 'B1',
              date: DateTime(2026, 11, 4),
              fromSearchApi: true,
              authority: 3,
              // 渲染确定性:不探测网络;有图那张用注入的真实图片源
              enableLazyCoverFetch: false,
              coverImageOverride: coverProvider,
              onRead: () {},
              onSave: () {},
              onOpenOriginal: () {},
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: <Widget>[
                AppTag('无封面 → 文字版式'),
                const SizedBox(width: 6),
                AppTag('有封面 → 58×76 缩略图', tone: AppTagTone.primary),
              ],
            ),
            const SizedBox(height: Gap.md),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: skin.hairline),
              ),
              child: Text(
                '取图顺序:① 数据自带 imageUrl(补抓正文时回填的 og:image)→ '
                '② 公版书按书号现算(Gutenberg 官方封面,零网络)→ '
                '③ 卡片级懒加载:一次轻量 GET 页面拿 og:image(有缓存、失败静默)。'
                '抓不到就保持文字版式,绝不画像书封的假图。',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.5,
                  color: skin.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 假数据(全部来自真实字段的形状,不是给生产喂数据)
// ═══════════════════════════════════════════════════════════════════════

FindNeedContext _richContext() => FindNeedContext(
      need: const MaterialNeed(band: MaterialBand.i10, goals: <String>['四六级']),
      prefs: InputPreferences(
        examGoals: const <String>['四六级', '兴趣阅读'],
        interests: const <String>['science', 'history'],
        blockedTopics: const <String>['影视娱乐'],
        dailyMinutes: 25,
      ),
      model: LearnerModel(),
      insight: const InsightSource(
        vocabEstimate: 4200,
        vocabCi: 350,
        cefr: 'B1',
        errorTagCounts: <String, int>{'时态': 8, '冠词': 5},
        readingWpm: 180,
        materialsFinished30d: 4,
        materialsReading: 2,
        dailyMinutes: 25,
        examGoals: <String>['四六级', '兴趣阅读'],
      ),
    );

FindNeedContext _emptyContext() => FindNeedContext(
      need: const MaterialNeed(),
      prefs: InputPreferences(),
      model: LearnerModel(),
    );

MaterialAnalysis _analysis(double coverage) => MaterialAnalysis(
      wordCount: 760,
      uniqueWords: 320,
      newTypes: 40,
      estMinutes: 6,
      coverage: coverage,
      knownTokenRatio: coverage,
      newWordDensity: 4,
      cefr: 'B1',
      topNewWords: const <String>[],
    );

List<MaterialResultItem> _freeResults() => <MaterialResultItem>[
      MaterialResultItem(
        title: 'Climate Change and Coastal Cities',
        url: 'https://example.com/npr/climate',
        sourceLabel: 'NPR News',
        kind: 'news',
        snippet: 'NPR 报道:海平面上升正在改变沿海城市的基础设施规划与迁移政策。',
        seq: 0,
        estimateLabel: '预计 B1~B2 · 中等',
        estimateBasis: '根据来源/类型估算,非精确覆盖率',
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
      MaterialResultItem(
        title: 'A Christmas Carol',
        url: 'https://example.com/gutenberg/46',
        sourceLabel: 'Project Gutenberg',
        kind: 'book',
        snippet: 'Charles Dickens 经典短篇,分级难度低,适合长篇泛读入门。',
        seq: 2,
        estimateLabel: '预计 B2~C1 · 进阶',
      ),
      MaterialResultItem(
        title: 'Attention Is All You Need',
        url: 'https://example.com/arxiv/1706',
        sourceLabel: 'arXiv',
        kind: 'paper',
        snippet: '预印本论文摘要:Transformer 架构,学术英语真实语料。',
        seq: 3,
        estimateLabel: '预计 C1+ · 高难',
      ),
      MaterialResultItem(
        title: 'New Concept English 3',
        url: 'https://example.com/nce/3',
        sourceLabel: 'DeepSeek 搜索',
        kind: 'textbook',
        snippet: '经典教材系列第三册,适合系统学习语法与表达。',
        seq: 4,
        estimateLabel: '预计 B1~B2 · 中等',
      ),
      MaterialResultItem(
        title: 'CET-4 真题 2024 阅读',
        url: 'https://example.com/cet4/2024',
        sourceLabel: 'DeepSeek 搜索',
        kind: 'exam',
        snippet: '四六级历年真题阅读部分,含答案解析与高频词。',
        seq: 5,
        estimateLabel: '预计 B1~B2 · 中等',
      ),
      MaterialResultItem(
        title: 'The Art of Small Talk',
        url: 'https://example.com/bbc/small-talk',
        sourceLabel: 'BBC Learning English',
        kind: 'podcast',
        snippet: '6 Minute English:TED/播客类口语材料,适合精听与表达积累。',
        seq: 6,
        estimateLabel: '预计 A2~B1 · 入门',
      ),
      MaterialResultItem(
        title: 'How Cities Adapt to Heat',
        url: 'https://example.com/sciencedaily/heat',
        sourceLabel: 'ScienceDaily',
        kind: 'news',
        snippet: '科学新闻:城市热岛与适应策略,科普英语常见句式。',
        seq: 7,
        estimateLabel: '预计 B1~B2 · 中等',
      ),
      MaterialResultItem(
        title: 'NASA: Back to the Moon',
        url: 'https://example.com/nasa/moon',
        sourceLabel: 'NASA 新闻',
        kind: 'news',
        snippet: 'NASA 官方任务报道:技术类真实语料,信息密度适中。',
        seq: 8,
        estimateLabel: '预计 B1~B2 · 中等',
      ),
      MaterialResultItem(
        title: 'The Gift of the Magi',
        url: 'https://example.com/gutenberg/7256',
        sourceLabel: 'Project Gutenberg',
        kind: 'book',
        snippet: 'O. Henry 短篇:词汇跨度大,适合进阶泛读。',
        seq: 9,
        estimateLabel: '预计 B2~C1 · 进阶',
      ),
      MaterialResultItem(
        title: 'Reading Comprehension Strategies',
        url: 'https://example.com/arxiv/reading',
        sourceLabel: 'arXiv',
        kind: 'paper',
        snippet: '预印本:阅读理解策略的实证研究,学术英语。',
        seq: 10,
        estimateLabel: '预计 C1+ · 高难',
      ),
      MaterialResultItem(
        title: 'Why Reading Slowly Helps',
        url: 'https://example.com/article/slow',
        sourceLabel: 'NPR News',
        kind: 'article',
        snippet: '碎片文章:慢读的认知收益,适合通勤十分钟。',
        seq: 11,
        estimateLabel: '预计 B1~B2 · 中等',
      ),
      MaterialResultItem(
        title: 'CET-4 真题 2023 写作',
        url: 'https://example.com/cet4/2023w',
        sourceLabel: 'DeepSeek 搜索',
        kind: 'exam',
        snippet: '四六级写作真题与范文,备考写作时精读用。',
        seq: 12,
        estimateLabel: '预计 B1~B2 · 中等',
      ),
    ];

List<MaterialResultItem> _needResults() => <MaterialResultItem>[
      MaterialResultItem(
        title: 'New Concept English 3',
        url: 'https://example.com/nce/3',
        sourceLabel: 'DeepSeek 搜索',
        kind: 'textbook',
        snippet: '经典教材,长难句密度高,适合系统补语法与表达。',
        seq: 0,
        analysis: _analysis(0.96),
      ),
      MaterialResultItem(
        title: 'English Grammar in Use (Intermediate)',
        url: 'https://example.com/grammar',
        sourceLabel: 'DeepSeek 搜索',
        kind: 'textbook',
        snippet: '按语法点分章,正好补你的弱项「时态」。',
        seq: 1,
        analysis: _analysis(0.94),
      ),
      MaterialResultItem(
        title: 'CET-4 真题 2024 阅读',
        url: 'https://example.com/cet4/2024',
        sourceLabel: 'DeepSeek 搜索',
        kind: 'exam',
        snippet: '含答案解析与高频词表,读前可预热 12 个生词。',
        seq: 2,
        analysis: _analysis(0.93),
      ),
      MaterialResultItem(
        title: 'Climate Change and Coastal Cities',
        url: 'https://example.com/npr/climate',
        sourceLabel: 'NPR News',
        kind: 'news',
        snippet: '外刊报道:海平面上升与沿海城市。',
        seq: 3,
        analysis: _analysis(0.97),
      ),
      MaterialResultItem(
        title: 'The Art of Small Talk',
        url: 'https://example.com/bbc/small-talk',
        sourceLabel: 'BBC Learning English',
        kind: 'podcast',
        snippet: '口语材料:6 Minute English,补口语表达。',
        seq: 4,
        analysis: _analysis(0.95),
      ),
      MaterialResultItem(
        title: 'The Gift of the Magi',
        url: 'https://example.com/gutenberg/7256',
        sourceLabel: 'Project Gutenberg',
        kind: 'book',
        snippet: 'O. Henry 短篇,进阶泛读。',
        seq: 5,
        analysis: _analysis(0.91),
      ),
      MaterialResultItem(
        title: 'Reading Comprehension Strategies',
        url: 'https://example.com/arxiv/reading',
        sourceLabel: 'arXiv',
        kind: 'paper',
        snippet: '预印本:阅读理解策略的实证研究。',
        seq: 6,
        analysis: _analysis(0.90),
      ),
      MaterialResultItem(
        title: 'Why Reading Slowly Helps',
        url: 'https://example.com/article/slow',
        sourceLabel: 'NPR News',
        kind: 'article',
        snippet: '碎片文章:慢读的认知收益。',
        seq: 7,
        analysis: _analysis(0.96),
      ),
      MaterialResultItem(
        title: 'CET-6 真题 2024 阅读',
        url: 'https://example.com/cet6/2024',
        sourceLabel: 'DeepSeek 搜索',
        kind: 'exam',
        snippet: '六级真题阅读,难度偏高。',
        seq: 8,
        analysis: _analysis(0.92),
      ),
      MaterialResultItem(
        title: 'How Cities Adapt to Heat',
        url: 'https://example.com/sciencedaily/heat',
        sourceLabel: 'ScienceDaily',
        kind: 'news',
        snippet: '科普新闻:城市热岛与适应策略。',
        seq: 9,
        analysis: _analysis(0.95),
      ),
      MaterialResultItem(
        title: 'New Concept English 4',
        url: 'https://example.com/nce/4',
        sourceLabel: 'DeepSeek 搜索',
        kind: 'textbook',
        snippet: '教材第四册,长难句更密。',
        seq: 10,
        analysis: _analysis(0.93),
      ),
      MaterialResultItem(
        title: 'CET-4 真题 2023 写作',
        url: 'https://example.com/cet4/2023w',
        sourceLabel: 'DeepSeek 搜索',
        kind: 'exam',
        snippet: '写作真题与范文。',
        seq: 11,
        analysis: _analysis(0.94),
      ),
      MaterialResultItem(
        title: 'NASA: Back to the Moon',
        url: 'https://example.com/nasa/moon',
        sourceLabel: 'NASA 新闻',
        kind: 'news',
        snippet: 'NASA 任务报道,技术类语料。',
        seq: 12,
        analysis: _analysis(0.96),
      ),
    ];

/// 卡片版式对照:左「无真封面 → 文字版式」,右「有真封面」的说明(测试无网络,
/// 所以右卡只示意位置,不画假封面 —— 正是本轮用户定的规则)。
class _NoCoverGallery extends StatelessWidget {
  const _NoCoverGallery();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xl),
          children: <Widget>[
            Text('结果卡 · 封面规则',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: skin.ink,
                )),
            const SizedBox(height: 4),
            Text('有真实封面才显示图;没有就标题 + 中文标题 + 来源/难度文字版式。',
                style: TextStyle(fontSize: 11, color: skin.inkSoft)),
            const SizedBox(height: Gap.md),
            MaterialResultCard(
              title: 'Climate Change and Coastal Cities',
              url: 'https://example.com/a',
              sourceLabel: 'NPR News',
              kind: 'news',
              snippet: '没有抓到 og:image → 不画渐变假封面,直接文字版式。',
              coverage: 0.96,
              cefr: 'B1',
              date: DateTime(2026, 11, 4),
              fromSearchApi: true,
              authority: 3,
              onRead: () {},
              onSave: () {},
              onOpenOriginal: () {},
            ),
            const SizedBox(height: Gap.sm),
            Row(
              children: <Widget>[
                AppTag('无封面 → 文字版式'),
                const SizedBox(width: 6),
                AppTag('有封面 → 58×76 缩略图', tone: AppTagTone.primary),
              ],
            ),
            const SizedBox(height: Gap.md),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: skin.hairline),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.image_outlined, size: 16, color: skin.inkFaint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '真机上有封面时:卡片左侧 58×76 圆角缩略图,右侧仍是标题/来源/难度;'
                      '加载失败回落中性占位,绝不显示像书封的假图。',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.45,
                        color: skin.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 渲染管线(与 test/material_channel_render_test.dart 同一套)
// ═══════════════════════════════════════════════════════════════════════

const String _fontFamily = 'PreviewCJK';

Future<void> _loadFont() async {
  for (final path in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes =
        Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
    await (FontLoader('Roboto')..addFont(bytes)).load();
    await (FontLoader(_fontFamily)..addFont(bytes)).load();
    return;
  }
}

Future<void> _loadIcons() async {
  for (final path in <String>[
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()))))
        .load();
    return;
  }
}

ThemeData _theme() {
  final base = AppTheme.lightTheme;
  // 按钮文字不吃 theme.textTheme 的 fontFamily(按钮主题自带 textStyle),
  // 不显式指定就会回落成测试字体 → 中文变成一团 □(之前 3 张图踩过)。
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _fontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _fontFamily),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(
              fontFamily: _fontFamily, fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(fontFamily: _fontFamily, fontSize: 13),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(fontFamily: _fontFamily, fontSize: 13),
        ),
      ),
    ),
  );
}

void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _shoot(WidgetTester tester, Widget screen, String fileName,
    {double scroll = 0}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        // 兜底:任何没有 Material 祖先的文字都不该被 Flutter 的
        // `_errorTextStyle`(红字+黄下划线)污染
        home: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: _fontFamily,
            decoration: TextDecoration.none,
          ),
          child: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  // 任何 RenderFlex overflow / 布局异常都会进异常队列:这里显式断言为空,
  // 避免"图能出但边缘被裁"这类问题漏过去(筛选区曾把末尾 chip 裁掉过)。
  expect(tester.takeException(), isNull, reason: '$fileName 有布局异常(overflow?)');
  if (scroll != 0) {
    // 截"滚到底"的状态:让页码控件/继续找更多也进画面(验收要看分页)。
    // 注意:筛选条是横向 ListView,必须只拖**竖向**的那个,否则截出来没动。
    final vertical = find.byWidgetPredicate(
      (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
    );
    if (vertical.evaluate().isNotEmpty) {
      await tester.drag(
        vertical.first,
        Offset(0, -scroll),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
    }
  }
  await _capture(tester, key, fileName);
}

Future<void> _capture(
    WidgetTester tester, GlobalKey key, String fileName) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final data = bytes!.buffer.asUint8List();
    Directory('build/ui_real').createSync(recursive: true);
    File('build/ui_real/$fileName').writeAsBytesSync(data);
    Directory('docs/ui-preview/real').createSync(recursive: true);
    File('docs/ui-preview/real/$fileName').writeAsBytesSync(data);
    image.dispose();
  });
}
