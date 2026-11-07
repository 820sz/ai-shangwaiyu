// 阅读器 C 方案 · 逐屏真实渲染(2026-11-06 用户拍板:方案 C + B 的纸张三色)
//
// **本轮纪律**:这些图由**生产组件**渲染,不是设计稿重画一遍。
// 做法:sqflite_common_ffi 起一个真库,种一篇外刊(6 节)+ 难度分析(含生词表),
// 然后直接 pump 生产页 `MaterialReaderScreen`(390×844,pixelRatio 3),
// 逐屏截图;控制台/目录/设置/续读都是从真实交互点进去的。
//
// 出图:`docs/ui-preview/real/reader-c-*.png`(同步 build/ui_real)。
//
// 唯一不用真实交互点进去的屏是「翻译进行中」:那需要真 API Key,测试里假装
// 它会给出"看起来能用其实是假的"图;所以用生产组件 `ReaderTranslationSheet`
// + 真实 `ProgressStageBar` + 假进度单独渲染。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/material_reader_screen.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/reader_settings.dart';
import 'package:readflow/widgets/reader_paper.dart';
import 'package:readflow/widgets/reader_sheets.dart';
import 'package:readflow/widgets/word_action_sheet.dart';
import 'package:readflow/widgets/waiting.dart';

const String _cjk = 'PreviewCJK';

Future<void> _loadFont() async {
  for (final path in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\simhei.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes =
        Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
    await (FontLoader('Roboto')..addFont(bytes)).load();
    await (FontLoader(_cjk)..addFont(bytes)).load();
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
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _cjk),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _cjk),
  );
}

// ── 种子数据:一篇外刊 6 节(与设计稿同一篇文章扩写,够滚到 37%)──
const List<String> _paras = <String>[
  'For decades the office celebrated the busy generalist: the person who '
      'answers email during a call and edits a deck while replying to a '
      'message.',
  'The evidence is unusually consistent. What multitasking produces is not '
      'more output but a thinner, more distracted version of it — and the '
      'cost is paid in working memory.',
  'That is why a quiet hour can feel more productive than a crowded '
      'afternoon: the effort is simply continuous.',
  'A quiet hour does not mean an empty calendar. It means one task, one '
      'window, and a door that is actually shut.',
  'The remedy is unglamorous. Protect one block of the day, close the '
      'inbox, and let attention settle into a single task for ninety '
      'minutes at a stretch.',
  'Teams that tried it reported fewer, better decisions — and the same '
      'amount of work finished by five o’clock.',
  'The habit is hard to start because the reward arrives late. The first '
      'ten minutes feel wasteful; the next eighty do not.',
  'None of this requires heroics. It requires a decision about what not '
      'to do next.',
  'Managers can help by making the quiet block visible: a shared calendar '
      'hold, a status line, a norm that says slow is allowed.',
  'Individuals can help by protecting the block from their own optimism. '
      'It will be the first thing sacrificed to a busy week.',
  'What gets measured gets repeated. If the only metric is response time, '
      'the quiet hour will never survive.',
  'The offices that kept it treated the hour as infrastructure, not as a '
      'perk. It was scheduled like a meeting and defended like a deadline.',
  'The payoff is not dramatic. It is a day that ends with fewer open '
      'loops and a mind that can still read a sentence twice.',
  'That is the whole trick: a thinner to-do list, a longer attention '
      'span, and a quiet hour that belongs to you.',
];

const List<String> _titles = <String>[
  'The quiet hour',
  'What multitasking costs',
  'A practice, not a mood',
  'The unglamorous remedy',
  'Making it survive',
  'What you get back',
];

Future<int> _seedDatabase() async {
  final db = await DatabaseService.database;
  final materialId = await db.insert('materials', <String, Object?>{
    'kind': 'article',
    'source': 'seed',
    'source_id': 'reader-c-1',
    'title': 'The Quiet Hour',
    'author': 'The Atlantic',
    'url': 'https://example.com/quiet-hour',
    'language': 'en',
    'word_count': 930,
    'unique_words': 410,
    'cefr': 'C1',
    'est_minutes': 8,
    'chapters': 6,
    'difficulty_json': '{"word_count":930,"unique_words":410,"new_types":5,'
        '"est_minutes":8,"coverage":0.92,"known_token_ratio":0.92,'
        '"new_word_density":3.2,"cefr":"C1",'
        '"top_new_words":["generalist","multitasking","distracted",'
        '"unglamorous","remedy"]}',
    'created_at': DateTime.now().toIso8601String(),
    'cached_at': DateTime.now().toIso8601String(),
  });
  // 6 节:每节 2~3 段(阅读器内部会按真段落拆成单元)
  final chunkTexts = <String>[
    '${_paras[0]}\n\n${_paras[1]}',
    _paras[2],
    '${_paras[3]}\n\n${_paras[4]}',
    '${_paras[5]}\n\n${_paras[6]}',
    '${_paras[7]}\n\n${_paras[8]}\n\n${_paras[9]}',
    '${_paras[10]}\n\n${_paras[11]}\n\n${_paras[12]}\n\n${_paras[13]}',
  ];
  for (var i = 0; i < chunkTexts.length; i++) {
    await db.insert('material_content', <String, Object?>{
      'material_id': materialId,
      'chunk_index': i,
      'title': _titles[i],
      'text': chunkTexts[i],
    });
  }
  return materialId;
}

Future<void> _capture(
    WidgetTester tester, GlobalKey key, String fileName) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final data = bytes!.buffer.asUint8List();
    for (final dir in <String>['build/ui_real', 'docs/ui-preview/real']) {
      Directory(dir).createSync(recursive: true);
      File('$dir/$fileName').writeAsBytesSync(data);
    }
    image.dispose();
  });
}

/// 等真实异步(DB/Hive)settle。
///
/// 为什么是"轮转"而不是一个长 runAsync:页面 `_load()` 里是一串 `await` 的
/// sqflite 查询,续体注册在 fake-async zone —— 一个 await 要在 runAsync 里完成
/// 真实 I/O、再由 pump 推一帧把续体跑起来,才会发起下一个查询。
/// 所以"runAsync 一下 + pump 一帧"重复到正文真的出来;**不用 pumpAndSettle**。
Future<void> _settle(WidgetTester tester, {int rounds = 16}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 24));
    });
    await tester.pump(const Duration(milliseconds: 80));
    if (find.text('上滑工具').evaluate().isNotEmpty) return;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late int materialId;

  setUpAll(() async {
    await _loadFont();
    await _loadIcons();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('readflow_reader_c_');
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    final dbPath = p.join(await getDatabasesPath(), AppConstants.dbName);
    try {
      await databaseFactory.deleteDatabase(dbPath);
    } catch (_) {}
    await DatabaseService.resetForTest();
    materialId = await _seedDatabase();
  });

  tearDownAll(() async {
    try {
      await DatabaseService.resetForTest()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 每张图都从"没读过 / 指定纸张"的干净状态开始
  Future<GlobalKey> pumpReader(
    WidgetTester tester, {
    required ReaderPaper paper,
    bool seedProgress = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.clear();
      await box.put(ReaderSettings.keyReaderPaper, paper.name);
      final db = await DatabaseService.database;
      await db.delete('material_progress',
          where: 'material_id = ?', whereArgs: [materialId]);
      if (seedProgress) {
        await db.insert('material_progress', <String, Object?>{
          'material_id': materialId,
          'position': 1,
          'percent': 37.0,
          'minutes': 6,
          'lookups': 0,
          'picked_words': 0,
          'started_at': DateTime.now()
              .subtract(const Duration(minutes: 6))
              .toIso8601String(),
        });
      }
    });
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: MaterialReaderScreen(materialId: materialId),
      ),
    ));
    await _settle(tester);
    return key;
  }

  /// 用真实滚动位置把进度滚到 [ratio],让图里的 37% 是真值(不是写死的)
  ///
  /// 注意:滚动会触发 `_onScroll → _persist` 落库(sqflite 真实 I/O)。
  /// 这个 await 注册在 fake-async zone,必须 runAsync 让 I/O 真完成再 pump,
  /// 否则测试结束时会有 pending timer / 未完成的写库。
  Future<void> jumpToRatio(WidgetTester tester, double ratio) async {
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    final pos = scrollable.position;
    pos.jumpTo(pos.maxScrollExtent * ratio);
    await tester.pump(const Duration(milliseconds: 80));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> openConsole(WidgetTester tester) async {
    await tester.tap(find.text('上滑工具'));
    await tester.pump(const Duration(milliseconds: 340));
    await tester.pump(const Duration(milliseconds: 120));
  }

  /// 把控制台内容滚到底(材料组),用于"4 组都能看到"的验证图
  Future<void> scrollConsoleToBottom(WidgetTester tester) async {
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -320),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('首屏:刊头双线 / 首段 20 / 顶部安全条 / 底部零按钮', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.white);
    await _capture(tester, key, 'reader-c-first-white.png');
  });

  testWidgets('纸白(C 基底)阅读中 · 右侧 37% 胶囊 + 96px 竖轨', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.white);
    await jumpToRatio(tester, 0.37);
    await _capture(tester, key, 'reader-c-paper-white.png');
  });

  testWidgets('米黄(搬 B 的暖纸)', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.beige);
    await jumpToRatio(tester, 0.37);
    await _capture(tester, key, 'reader-c-paper-beige.png');
  });

  testWidgets('墨夜(深色纸)', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.night);
    await jumpToRatio(tester, 0.37);
    await _capture(tester, key, 'reader-c-paper-night.png');
  });

  testWidgets('上滑阅读控制台 · 4 组(进度 / 学习 / 目录 / 材料)', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.white);
    await jumpToRatio(tester, 0.37);
    await openConsole(tester);
    await _capture(tester, key, 'reader-c-console.png');
  });

  testWidgets('控制台滚到底 · 材料组完整可见(不被裁)', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.white);
    await jumpToRatio(tester, 0.37);
    await openConsole(tester);
    await scrollConsoleToBottom(tester);
    await _capture(tester, key, 'reader-c-console-material.png');
  });

  testWidgets('阅读设置 · 三张色卡 + 实时预览', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.white);
    await jumpToRatio(tester, 0.37);
    await openConsole(tester);
    await scrollConsoleToBottom(tester);
    await tester.tap(find.text('字号与行距'));
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump(const Duration(milliseconds: 160));
    await _capture(tester, key, 'reader-c-settings.png');
  });

  testWidgets('完整目录 · 每节 %', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.white);
    await jumpToRatio(tester, 0.37);
    await openConsole(tester);
    await scrollConsoleToBottom(tester);
    await tester.tap(find.text('全部 6 节'));
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump(const Duration(milliseconds: 160));
    await _capture(tester, key, 'reader-c-toc.png');
  });

  testWidgets('续读弹层 · 上次读到 37%', (tester) async {
    final key = await pumpReader(
      tester,
      paper: ReaderPaper.white,
      seedProgress: true,
    );
    // 有进度 → 打开即弹「继续 / 从头」(不静默跳转)
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump(const Duration(milliseconds: 160));
    await _capture(tester, key, 'reader-c-resume.png');
  });

  testWidgets('墨夜纸上的阅读设置(弹层跟着换纸)', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.night);
    await jumpToRatio(tester, 0.37);
    await openConsole(tester);
    await scrollConsoleToBottom(tester);
    await tester.tap(find.text('字号与行距'));
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump(const Duration(milliseconds: 160));
    await _capture(tester, key, 'reader-c-settings-night.png');
  });

  testWidgets('墨夜纸上的阅读控制台', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.night);
    await jumpToRatio(tester, 0.37);
    await openConsole(tester);
    await _capture(tester, key, 'reader-c-console-night.png');
  });

  testWidgets('翻译进行中 · 生产弹层 + 真实进度条', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    final key = GlobalKey();
    final palette = paletteOf(ReaderPaper.white);
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: Stack(
          children: <Widget>[
            Positioned.fill(child: ColoredBox(color: palette.page)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ReaderTranslationSheet(
                palette: palette,
                editing: true,
                done: 3,
                total: 8,
                failed: 1,
                status: '已翻 3/8 段 · 1 段没翻出来',
                autoTranslate: true,
                translateTarget: 'deepseek-chat · 标准',
                progressBar: ProgressStageBar(
                  stage: '正在翻译 · 已完成 3/8 段',
                  value: 0.375,
                  detail: '已翻 3/8 段 · 1 段待重试',
                  startedAt:
                      DateTime.now().subtract(const Duration(seconds: 12)),
                  onCancel: () {},
                ),
                lastError: '连接超时,请检查网络后重试',
                onContinueNext: () {},
                onWholeChapter: () {},
                onRetryFailed: () {},
                onToggleOff: () {},
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    // 主题探针:这张图必须证明 C 纸色主题真的作用到共享进度组件
    // (否则共享件的按钮/进度条会漏出全局果冻蓝 —— 用户会一眼看到)
    final barCtx = tester.element(find.byType(LinearProgressIndicator).last);
    expect(Theme.of(barCtx).colorScheme.primary, palette.accent);
    await _capture(tester, key, 'reader-c-translating.png');
  });

  testWidgets('查词弹层(共享件 · C 纸色主题 · 假词条预览)', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    // 用生产共享件 `showWordActionSheet` 的 `previewWordInfo`(默认 null,
    // 生产零影响)注入一条假词条:展示正常查词结果,不联网、不碰真实 API。
    await tester.runAsync(() async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.clear();
      await box.put(ReaderSettings.keyReaderPaper, ReaderPaper.white.name);
    });
    final key = GlobalKey();
    final palette = paletteOf(ReaderPaper.white);
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: Builder(
          builder: (outer) => Theme(
            data: readerTheme(outer, palette),
            child: Scaffold(
              backgroundColor: palette.page,
              body: Builder(builder: (inner) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  showWordActionSheet(
                    inner,
                    word: 'generalist',
                    sentence:
                        'For decades the office celebrated the busy generalist.',
                    target: const WordSaveTarget(
                      category: '外刊',
                      materialName: 'The Quiet Hour',
                    ),
                    sourceTitle: 'The Quiet Hour',
                    previewWordInfo: const <String, String>{
                      'translation': '多面手;通才',
                      'part_of_speech': 'n.',
                      'phonetic_uk': '/ˈdʒenərəlɪst/',
                      'phonetic_us': '/ˈdʒenərəlɪst/',
                      'original_sentence':
                          'For decades the office celebrated the busy generalist.',
                      'grammar_note': '可数名词;常与 busy 搭配。',
                    },
                  );
                });
                return const SizedBox.expand();
              }),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 420));
    await tester.pump(const Duration(milliseconds: 420));
    expect(find.textContaining('多面手'), findsOneWidget);
    await _capture(tester, key, 'reader-c-word.png');
  });
  testWidgets('进度落库:滚到末尾写真实比例(未读完 <=99)', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.white);
    expect(key, isNotNull);
    await jumpToRatio(tester, 1.0);
    final percent = await tester.runAsync(() async {
      final db = await DatabaseService.database;
      final rows = await db.query('material_progress',
          where: 'material_id = ?', whereArgs: [materialId]);
      if (rows.isEmpty) return -1.0;
      return (rows.first['percent'] as num?)?.toDouble() ?? -1.0;
    });
    expect(percent, isNotNull);
    expect(percent!, greaterThan(90), reason: '滚到末尾应写入接近真实比例');
    expect(percent, lessThanOrEqualTo(99), reason: '未点读完了前落库最多 99');
    final rail = tester.widget<Text>(
      find.byKey(const ValueKey<String>('reader-rail-percent')),
    );
    expect(rail.data, isNot('100%'));
  });
  testWidgets('改后 · 首屏(空间利用率整改:正文 354px)', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.white);
    await _capture(tester, key, 'reader-c-after-first.png');
  });

  testWidgets('改后 · 滚动中(竖轨悬浮不挤压正文)', (tester) async {
    final key = await pumpReader(tester, paper: ReaderPaper.white);
    await jumpToRatio(tester, 0.37);
    await _capture(tester, key, 'reader-c-after-scroll.png');
  });
}
