import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/profile/about_doc_screen.dart';
import 'package:readflow/screens/profile/about_notice_screen.dart';
import 'package:readflow/screens/profile/about_screen.dart';
import 'package:readflow/services/about_content.dart';
import 'package:readflow/services/profile_card.dart';
import 'package:readflow/widgets/profile_name_card.dart';

/// 用户第 7/8 条的逐屏渲染(独立文件):
/// 首启公告 / 软件思想内容页 / 名片两态(无背景图 vs 有背景图 + scrim)。
///
/// 为什么不和 `profile_pages_test.dart` 放一起:
/// 那个文件要建 sqflite 假库、跑 14 屏;公告页与内容页依赖 rootBundle、
/// 名片有 `Image.file` 解码 —— 混在一起时任何一处慢都会把整套渲染拖到超时。
/// 这里不建数据库,只开一个 Hive tmp box(名片要读学习者模型)。

const String _ff = 'PreviewCJK';
late Directory _tmp;

Future<void> _loadFonts() async {
  for (final String path in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
  ]) {
    final File f = File(path);
    if (!f.existsSync()) continue;
    for (final String family in <String>[
      'Roboto',
      _ff,
      'monospace',
      'Noto Sans',
      'Noto Sans SC',
      'sans-serif',
    ]) {
      final Future<ByteData> bytes =
          Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
      await (FontLoader(family)..addFont(bytes)).load();
    }
    for (final String lp in <String>[
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\arial.ttf',
    ]) {
      final File lf = File(lp);
      if (!lf.existsSync()) continue;
      final String family = lp.contains('segoeui') ? 'Segoe UI' : 'Arial';
      final Future<ByteData> bytes =
          Future<ByteData>.value(ByteData.sublistView(lf.readAsBytesSync()));
      await (FontLoader(family)..addFont(bytes)).load();
    }
    return;
  }
}

Future<void> _loadIcons() async {
  for (final String path in <String>[
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ]) {
    final File f = File(path);
    if (!f.existsSync()) continue;
    await (FontLoader('MaterialIcons')
          ..addFont(Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()))))
        .load();
    return;
  }
}

ThemeData _theme() {
  final ThemeData base = AppTheme.lightTheme;
  const List<String> fallback = <String>[
    _ff,
    'Noto Sans',
    'Segoe UI',
    'Arial',
    'sans-serif',
  ];
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: _ff,
      fontFamilyFallback: fallback,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: _ff,
      fontFamilyFallback: fallback,
    ),
  );
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String fileName) async {
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 3);
    final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/ui_real').createSync(recursive: true);
    File('build/ui_real/$fileName').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _render(WidgetTester tester, String fileName, Widget screen) async {
  addTearDown(tester.view.reset);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: 44),
          viewPadding: EdgeInsets.only(top: 44),
          devicePixelRatio: 1,
        ),
        child: RepaintBoundary(key: key, child: screen),
      ),
    ),
  );
  await tester.pump();
  // 有界等待:公告摘要/内容页走 rootBundle，名片背景图走 Image.file 解码
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }
  await _capture(tester, key, fileName);
  // 拆树后再推进计时器，避免 teardown 报 pending timer
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 直接读文件拿摘要/正文:渲染链路里 rootBundle 的完成时机不稳定，
  /// 注入真实文本才能保证截图里是**真实内容**而不是"…"骨架。
  String readDoc(AboutDoc doc) {
    final File f = File(doc.assetPath);
    if (!f.existsSync()) return doc.subtitle;
    return f.readAsStringSync();
  }

  /// 与 `AboutContent.summaryOf` 同一套过滤（渲染链路不能 await rootBundle，
  /// 所以这里直接读文件；但"跳过 Markdown 表格/符号"的规则必须一致，
  /// 否则渲出来的公告摘要会和线上不一致）。
  String summaryOf(AboutDoc doc) {
    final List<String> lines = readDoc(doc).split('\n');
    final StringBuffer out = StringBuffer();
    for (final String raw in lines) {
      final String line = raw.trim();
      if (line.isEmpty ||
          line.startsWith('#') ||
          line.startsWith('>') ||
          line.startsWith('---') ||
          line.startsWith('<!--') ||
          line.startsWith('```') ||
          line.startsWith('![')) {
        continue;
      }
      // Markdown 表格整行跳过（QA 首屏 bug：`| 项目 | 内容 | --- |` 被当摘要）
      if (line.contains('|')) continue;
      if (RegExp(r'^[\s\-:_]+$').hasMatch(line)) continue;
      String plain = line
          .replaceAll(RegExp(r'^[-*+]\s+'), '')
          .replaceAll(RegExp(r'^\d+[.)]\s+'), '')
          .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1')
          .replaceAll('**', '')
          .replaceAll('__', '')
          .replaceAll('`', '')
          .replaceAll('|', '')
          .replaceAll(RegExp(r'\[([^\]]*)\]'), r'$1')
          .trim();
      if (plain.length < 8) continue;
      if (plain.contains('**') || plain.contains('`') || plain.contains('](')) {
        continue;
      }
      out.write(plain);
      if (out.length >= 54) break;
    }
    final String s = out.toString().trim();
    if (s.isEmpty) return doc.noticeLabel;
    return s.length <= 54 ? s : '${s.substring(0, 54)}…';
  }

  setUpAll(() async {
    await _loadFonts();
    await _loadIcons();
    _tmp = await Directory.systemTemp.createTemp('rf_about_render');
    Hive.init(_tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    AboutContent.resetCache();
  });

  tearDownAll(() async {
    await Hive.close();
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  testWidgets(
    'render 关于与更新(三入口 + 公告重看 + 开源许可)',
    (WidgetTester tester) async {
      await _render(
        tester,
        'assist-mine-impl-about.png',
        AboutScreen(onCheckUpdate: () async {}, onShowDiagnostics: () async {}),
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  testWidgets(
    'render 首启公告(B 语言)',
    (WidgetTester tester) async {
      final Map<AboutDoc, String> overrides = <AboutDoc, String>{
        for (final AboutDoc d in AboutDoc.values) d: summaryOf(d),
      };
      await _render(tester, 'assist-mine-impl-about-notice.png',
          AboutNoticeScreen(summaryOverrides: overrides));
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  testWidgets(
    'render 软件思想内容页(Markdown 纸面排版)',
    (WidgetTester tester) async {
      await _render(
        tester,
        'assist-mine-impl-about-doc.png',
        AboutDocScreen(
          doc: AboutDoc.philosophy,
          overrideMarkdown: readDoc(AboutDoc.philosophy),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  testWidgets(
    'render 名片·无背景图(纸面卡)',
    (WidgetTester tester) async {
      await _render(
        tester,
        'assist-mine-impl-namecard-plain.png',
        // 必须放在可滚动容器里:Scaffold body 给的是紧约束,直放会把卡片
        // 拉满整屏(照片态会露出一大片 scrim);ScrollView 让高度跟随内容
        const Scaffold(
          backgroundColor: Color(0xFFFBF7F0),
          body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(22, 60, 22, 22),
            child: ProfileNameCard(vocabCount: 60),
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'render 名片·有背景图(scrim 后仍清晰)',
    (WidgetTester tester) async {
      final File photo = File('assets/images/whale_tail.png');
      await _render(
        tester,
        'assist-mine-impl-namecard-photo.png',
        Scaffold(
          backgroundColor: const Color(0xFFFBF7F0),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 60, 22, 22),
            child: ProfileNameCard(
              vocabCount: 60,
              settingsOverride: ProfileCardSettings(
                nickname: 'xi283',
                signature: '把英语用起来',
                backgroundPath: photo.absolute.path,
                backgroundId: 'dawn',
              ),
            ),
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
