import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/material_hub/material_hub_home_view.dart';
import 'package:readflow/services/material_library.dart';
import 'package:readflow/services/material_need.dart';
import 'package:readflow/services/material_prefs.dart';
import 'package:readflow/services/material_taxonomy.dart';

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
  );
}

ShelfItem _shelf(int id, String title, String kind, double coverage) =>
    ShelfItem(
      id: id,
      title: title,
      titleCn: title,
      kind: kind,
      source: 'npr',
      cefr: 'B2',
      wordCount: 900 + id * 100,
      estMinutes: 5,
      coverage: coverage,
      percent: 0,
      minutesRead: 0,
      pickedWords: 0,
      url: '',
    );

void main() {
  group('材料分类法', () {
    test('四个方向都存在,且子类 id 不重复', () {
      expect(MaterialTaxonomy.all.map((d) => d.id).toSet(), <MaterialDirection>{
        MaterialDirection.need,
        MaterialDirection.topic,
        MaterialDirection.form,
        MaterialDirection.scene,
      });
      for (final d in MaterialTaxonomy.all) {
        final ids = d.subtopics.map((s) => s.id).toList();
        expect(ids.toSet().length, ids.length, reason: '${d.label} 子类 id 重复');
      }
    });

    test('按形式的外刊子类映射到 news', () {
      final sub =
          MaterialTaxonomy.subtopicOf(MaterialDirection.form, 'news');
      expect(sub, isNotNull);
      expect(sub!.kinds, contains('news'));
    });

    test('按场景四个子类齐全', () {
      final labels = MaterialTaxonomy.scene.subtopics.map((s) => s.label);
      expect(labels, containsAll(<String>['应试', '出国旅游', '生活聊天', '生产力英语']));
    });
  });

  group('MaterialNeed(全局推送)', () {
    test('难度档 i+10:覆盖率在 0.90~0.98 的材料排最前', () {
      final need = const MaterialNeed(band: MaterialBand.i10);
      final ranked = need.rank(<ShelfItem>[
        _shelf(1, 'too easy', 'news', 0.99),
        _shelf(2, 'challenge', 'news', 0.95),
        _shelf(3, 'too hard', 'news', 0.85),
      ]);
      expect(ranked.first.title, 'challenge');
    });

    test('目标会影响加权(四六级让 exam/news 更靠前)', () {
      final need = const MaterialNeed(
        band: MaterialBand.any,
        goals: <String>['四六级'],
      );
      final ranked = need.rank(<ShelfItem>[
        _shelf(1, 'plain article', 'article', 0.96),
        _shelf(2, 'cet-4 真题', 'exam', 0.96),
      ]);
      expect(ranked.first.title, contains('cet-4'));
    });

    test('summary 把需求拼成一行', () {
      const need = MaterialNeed(
        band: MaterialBand.i10,
        goals: <String>['四六级'],
        kinds: <String>{'news'},
      );
      expect(need.summary, contains('i+10'));
      expect(need.summary, contains('四六级'));
      expect(need.summary, contains('外刊新闻'));
    });
  });

  testWidgets('材料中心首页(生产组件)真实渲染', (tester) async {
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
          home: Scaffold(
            backgroundColor: const Color(0xFFF6F6FD),
            body: SafeArea(
              bottom: false,
              child: MaterialHubHomeView(
                need: const MaterialNeed(
                  band: MaterialBand.i10,
                  goals: <String>['四六级'],
                  kinds: <String>{'news'},
                ),
                libraryCount: 128,
                daily: const <MaterialHubDaily>[
                  MaterialHubDaily(
                    title: 'For Ukraine\'s Kherson region, a short ceasefire',
                    titleCn: '对乌克兰赫尔松地区而言,短暂停火',
                    sourceLabel: 'NPR',
                    kind: 'news',
                    cefr: 'B2',
                    wordCount: 1368,
                    estMinutes: 7,
                  ),
                  MaterialHubDaily(
                    title: 'A drag queen brings out the best in a small town',
                    titleCn: '变装皇后让小城看见更好的自己',
                    sourceLabel: '外刊',
                    kind: 'news',
                    cefr: 'B1',
                    wordCount: 382,
                    estMinutes: 2,
                  ),
                  MaterialHubDaily(
                    title: 'More middle-income families are falling behind',
                    titleCn: '更多中等收入家庭正在掉队',
                    sourceLabel: '外刊',
                    kind: 'news',
                    cefr: 'B2',
                    wordCount: 941,
                    estMinutes: 5,
                  ),
                ],
                onOpenDaily: (_) {},
                onShuffleDaily: () {},
                onOpenNeed: () {},
                onOpenDirection: (_) {},
                onOpenLibrary: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('今日精读'), findsOneWidget);
    expect(find.text('按需求找材料'), findsOneWidget);
    expect(find.text('按题材'), findsOneWidget);
    expect(find.text('按形式'), findsOneWidget);
    expect(find.text('按场景'), findsOneWidget);
    expect(find.text('我的材料库'), findsOneWidget);

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/ui_real').createSync(recursive: true);
      File('build/ui_real/material_hub_home.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
