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

/// 书架两形态的真实渲染 + 交互回归(2026-11-07 用户真机第 3 条:
/// 「书架 3D 老毛病——每次点进去都会有一本书横档」)。
///
/// 3 张 3D 书架图:
/// 1. `shelf-carousel-initial.png` —— 初始态:只有一排书脊 + 底部提示,
///    **没有**任何"抽出的封面卡"(旧实现一进页面就把封面横在书脊前);
/// 2. `shelf-carousel-open.png` —— 点书脊后:封面抽出并浮在书架排**上方**,
///    不遮挡任何书脊/底部提示;
/// 3. `shelf-carousel-swiped.png` —— 左右滑动后:书脊照常滚动,封面不会变成
///    "横在中间的挡板"。
///
/// 交互断言:初始无封面 → 点书脊出现 → 再点同一书脊收回 → 点空白收回。
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
  String fileName, {
  /// 兼容文档里引用的旧文件名(如 shelf-carousel.png),同一张图写多份
  List<String> aliases = const <String>[],
}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final data = bytes!.buffer.asUint8List();
    // 同时写两处:
    // - build/ui_real/:渲染中间产物(惯例)
    // - docs/ui-preview/real/:交付给用户看的真实渲染图(任务要求 shelf-*.png)
    // 直接写两处,避免依赖 shell cp(多 agent 并发时 shell 经常排队超时)
    for (final dir in <String>['build/ui_real', 'docs/ui-preview/real']) {
      Directory(dir).createSync(recursive: true);
      for (final name in <String>[fileName, ...aliases]) {
        File('$dir/$name').writeAsBytesSync(data);
      }
    }
    image.dispose();
  });
}

/// 有界推帧:书架里有 AnimatedSize/AnimatedContainer,用固定帧数代替
/// pumpAndSettle(避免任何持续动画把测试挂住)
Future<void> _pumpFrames(
  WidgetTester tester, {
  int frames = 4,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
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

    // ① 详细书架(封面网格)—— 回归:文字版式封面不受 3D 改动影响
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
    await _pumpFrames(tester);
    expect(find.text('The Elements of Style'), findsWidgets);
    await _capture(tester, keyDetail, 'shelf-detail.png');

    // ② 3D 轮播书架:用户"一进去就有书横档"的回归用例
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
    await _pumpFrames(tester);
    expect(find.text('Moby Dick'), findsWidgets);

    // 初始态:**没有**抽出封面(只有一排书脊 + hint)——这就是"横档"回归
    expect(
      find.byKey(ShelfCarouselView.featuredCoverKey),
      findsNothing,
      reason: '初始态不应该有抽出的封面卡(用户真机第 3 条)',
    );
    await _capture(tester, keyCarousel, 'shelf-carousel-initial.png');

    // 点书脊 → 该本抽出并浮在书架排上方
    await tester.tap(find.byKey(ShelfCarouselView.spineKey(1)));
    await _pumpFrames(tester);
    expect(find.byKey(ShelfCarouselView.featuredCoverKey), findsOneWidget);
    await _capture(
      tester,
      keyCarousel,
      'shelf-carousel-open.png',
      // 文档(V5-INPUT-STATUS / V5-BOOKSHELF-REDESIGN)里引用的是旧文件名,
      // 同一张图再写一份,保证文档里的图也是修好后的界面
      aliases: const <String>['shelf-carousel.png'],
    );

    // 再点同一本书脊 → 收回
    await tester.tap(find.byKey(ShelfCarouselView.spineKey(1)));
    await _pumpFrames(tester);
    expect(find.byKey(ShelfCarouselView.featuredCoverKey), findsNothing);

    // 点书架空白 → 也收回
    await tester.tap(find.byKey(ShelfCarouselView.spineKey(3)));
    await _pumpFrames(tester);
    expect(find.byKey(ShelfCarouselView.featuredCoverKey), findsOneWidget);
    final surfaceTopLeft =
        tester.getTopLeft(find.byKey(ShelfCarouselView.surfaceKey));
    await tester.tapAt(surfaceTopLeft + const Offset(8, 8));
    await _pumpFrames(tester);
    expect(find.byKey(ShelfCarouselView.featuredCoverKey), findsNothing);

    // 左右滑动:书脊照常滚,封面不会跟着变成"横在中间的挡板"
    await tester.tap(find.byKey(ShelfCarouselView.spineKey(3)));
    await _pumpFrames(tester);
    expect(find.byKey(ShelfCarouselView.featuredCoverKey), findsOneWidget);
    await tester.drag(
      find.byKey(ShelfCarouselView.spineKey(3)),
      const Offset(-120, 0),
    );
    await _pumpFrames(tester);
    expect(
      find.byKey(ShelfCarouselView.featuredCoverKey),
      findsOneWidget,
      reason: '滑动只滚书脊,不应把抽出的封面弄丢或变成遮挡',
    );
    await _capture(tester, keyCarousel, 'shelf-carousel-swiped.png');
  });
}
