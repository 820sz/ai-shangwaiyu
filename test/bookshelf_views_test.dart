import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/services/bookshelf.dart';
import 'package:readflow/widgets/shelf_carousel_view.dart';
import 'package:readflow/widgets/shelf_cover_grid.dart';

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

List<BookshelfBook> _books() => const <BookshelfBook>[
      BookshelfBook(
          materialId: 1,
          title: 'The Elements of Style',
          kind: 'book',
          cefr: 'C1',
          percent: 38,
          wordCount: 1200),
      BookshelfBook(
          materialId: 2,
          title: 'Moby Dick',
          kind: 'book',
          cefr: 'B2',
          percent: 12,
          wordCount: 940),
      BookshelfBook(
          materialId: 3,
          title: 'The Great Gatsby',
          kind: 'book',
          cefr: 'B2',
          percent: 100,
          finished: true,
          wordCount: 1300),
      BookshelfBook(
          materialId: 4,
          title: 'Walden',
          kind: 'book',
          cefr: 'C1',
          percent: 0,
          wordCount: 1500),
      BookshelfBook(
          materialId: 5,
          title: 'For Ukraine\'s Kherson region',
          kind: 'news',
          cefr: 'B1',
          percent: 64,
          wordCount: 1368),
      BookshelfBook(
          materialId: 6,
          title: 'Pride and Prejudice',
          kind: 'book',
          cefr: 'B2',
          percent: 22,
          wordCount: 1600),
      BookshelfBook(
          materialId: 7,
          title: 'The Old Man and the Sea',
          kind: 'book',
          cefr: 'B1',
          percent: 88,
          wordCount: 800),
      BookshelfBook(
          materialId: 8,
          title: 'Science News Weekly',
          kind: 'news',
          cefr: 'C1',
          percent: 6,
          wordCount: 700),
      BookshelfBook(
          materialId: 9,
          title: 'Walden Two',
          kind: 'book',
          cefr: 'C1',
          percent: 45,
          wordCount: 1100),
    ];

Future<void> _capture(
  WidgetTester tester,
  GlobalKey key,
  String fileName,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/ui_real').createSync(recursive: true);
    File('build/ui_real/$fileName')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  test('书脊几何纯函数:书越多书脊越接近 2.6 的宽高比上限', () {
    expect(ShelfCarouselMetrics.spineAspect(1), 2.5);
    expect(ShelfCarouselMetrics.spineAspect(10), closeTo(2.4, 1e-9));
    expect(ShelfCarouselMetrics.spineAspect(100), lessThanOrEqualTo(2.6));
  });

  testWidgets('书架双形态真实渲染(详细 / 3D 轮播)', (tester) async {
    await _loadFont();
    await _loadIcons();
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    // ① 详细书架(封面网格)
    final keyDetail = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: keyDetail,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: Scaffold(
            backgroundColor: const Color(0xFFF6F6FD),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                ShelfCoverGrid(
                  books: _books(),
                  enableCoverFetch: false,
                  onTapBook: (_) {},
                  onLongPressBook: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('The Elements of Style'), findsWidgets);
    await _capture(tester, keyDetail, 'shelf_detail.png');

    // ② 3D 轮播书架(书脊)
    final keyCarousel = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: keyCarousel,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: Scaffold(
            backgroundColor: const Color(0xFFF6F6FD),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(0, 40, 0, 20),
              children: <Widget>[
                ShelfCarouselView(
                  books: _books(),
                  enableCoverFetch: false,
                  onTapBook: (_) {},
                  onLongPressBook: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Moby Dick'), findsWidgets);
    await _capture(tester, keyCarousel, 'shelf_carousel.png');
  });
}
