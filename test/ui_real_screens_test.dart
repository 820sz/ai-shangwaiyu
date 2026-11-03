/// 真机级「实拍」通道:直接 pump **生产 App 屏幕**（不是手绘面板）渲染成 PNG。
///
/// 背景(2026-11-04 用户反馈):之前很多"预览图"是用新组件在测试里**手摆**的页面示意,
/// 组件是真的但页面布局另写,所以和手机上不一致。本文件改成:
/// 用真实屏幕 widget + 假数据（不走网络的恢复模式）→ 渲出与真机同布局的截图。
///
/// 产物:`build/ui_real/real_process_results.png`(识图结果,真实屏幕渲染)
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/models/saved_session.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/providers/bookmark_provider.dart';
import 'package:readflow/providers/vocab_provider.dart';
import 'package:readflow/screens/input/material_center_screen.dart';
import 'package:readflow/screens/input/process_chat.dart';
import 'package:readflow/services/database.dart';

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
    final loader = FontLoader('MaterialIcons')
      ..addFont(
          Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
    return;
  }
}

ThemeData _theme() {
  final base = AppTheme.lightTheme;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _fontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _fontFamily),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(
              fontFamily: _fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}

SavedSession _sampleSession() {
  const words = <(String, String, String, String, String)>[
    ('cities', '城市', 'n.', '/ˈsɪtiz/', 'As cities balloon with growth, access to nature for people living in urban areas is becoming rarer.'),
    ('balloon', '膨胀；激增', 'v.', '/bəˈluːn/', 'As cities balloon with growth, access to nature for people living in urban areas is becoming rarer.'),
    ('ubiquitous', '无处不在的', 'adj.', '/juːˈbɪkwɪtəs/', 'Smartphones have become ubiquitous in daily life.'),
    ('resilient', '有韧性的', 'adj.', '/rɪˈzɪliənt/', 'Children are surprisingly resilient after setbacks.'),
    ('serendipity', '意外之喜', 'n.', '/ˌserənˈdɪpəti/', 'Meeting her was pure serendipity.'),
    ('diligent', '勤勉的', 'adj.', '/ˈdɪlɪdʒənt/', 'A diligent student reviews every day.'),
  ];
  final results = <Map<String, dynamic>>[
    for (var i = 0; i < words.length; i++)
      Vocabulary(
        word: words[i].$1,
        translation: words[i].$2,
        wordType: 'word',
        partOfSpeech: words[i].$3,
        phonetic: words[i].$4,
        originalSentence: words[i].$5,
      ).toMap(),
  ];
  return SavedSession(
    id: 'real-render',
    createdAt: DateTime.now(),
    analysisMode: AppConstants.analysisModeMarked,
    results: results,
    fullTextParagraphs: const [],
    followUpMessages: const [],
  );
}

void main() {
  late Directory hiveDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_real_render');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    await databaseFactory.setDatabasesPath(hiveDir.path);
    await DatabaseService.resetForTest();
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    await Hive.deleteFromDisk();
    hiveDir.deleteSync(recursive: true);
  });

  testWidgets('真实屏幕渲染:识图结果', (tester) async {
    await _loadFont();
    await _loadIcons();
    addTearDown(tester.view.reset);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    final key = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: ChangeNotifierProvider(
            create: (_) => BookmarkProvider(),
            child: ProcessChatScreen(
              imageFiles: const <File>[],
              analysisMode: AppConstants.analysisModeMarked,
              restoreSession: _sampleSession(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 让真实屏幕里的异步布局/图片解码跑完
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pump(const Duration(milliseconds: 300));

    final err = tester.takeException();
    if (err != null) {
      // ignore: avoid_print
      print('REAL SCREEN EXCEPTION: $err');
    }

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/ui_real').createSync(recursive: true);
      File('build/ui_real/real_process_results.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });

  // 材料中心会真的去拉网络源;测试环境里 Dio 的超时 timer 会拖住 testWidgets,
  // 所以默认跳过(截图用于人工核对新样式):需要出图时跑
  // `flutter test --run-skipped test/ui_real_screens_test.dart`。
  testWidgets('真实屏幕渲染:材料中心', skip: true, (tester) async {
    await _loadFont();
    await _loadIcons();
    addTearDown(tester.view.reset);

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<VocabProvider>(
                  create: (_) => VocabProvider()),
              ChangeNotifierProvider<BookmarkProvider>(
                  create: (_) => BookmarkProvider()),
            ],
            child: const MaterialCenterScreen(),
          ),
        ),
      ),
    );
    // 真实屏幕会异步读 SQLite / 拉源;测试环境里网络请求会快速失败,
    // 多 pump 几轮把"加载中"跑成"真实空态/错误态"(这也是真机弱网时的样子)。
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
    }
    final err = tester.takeException();
    if (err != null) {
      // ignore: avoid_print
      print('REAL SCREEN EXCEPTION: $err');
    }

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/ui_real').createSync(recursive: true);
      File('build/ui_real/real_material_center.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
