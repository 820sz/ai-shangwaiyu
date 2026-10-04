import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/bookshelf.dart';
import 'package:readflow/services/database.dart';

/// 书架(v2.10,用户 10/4 第 4/5 条)的回归测试。
///
/// 分两段,理由不同:
/// 1. **纯函数段**:书架的"规矩"全在这里 —— 一层放几本、书脊取哪几个字、
///    进度怎么夹紧。这些是最容易被后续改版悄悄改坏、又最不容易在界面上
///    一眼看出来的东西(不会报错,只会"看着不对"),所以钉死在测试里。
/// 2. **真 SQLite 段**(照 `test/db_v2_queries_test.dart` 的 setup):
///    书架的去重靠 `bookshelf.material_id UNIQUE` + "先查再加"两段逻辑,
///    摆放顺序靠 `MAX(slot)+1` —— 这些只有跑真库才能验证。
///    mock 掉数据库,测出来的只是"我以为 SQL 会这么干"。
void main() {
  // ── 1. 纯函数:布局 ──

  group('booksPerShelf(按屏宽算一层放几本)', () {
    test('窄屏(360):一排 6 本(用户要的 5~7 本)且书本真的占满整层', () {
      final n = booksPerShelf(360);
      expect(n, 6, reason: '360 逻辑像素的手机上一排 6 本,书脊比例最像书');
      // 书位宽度 → 书脊宽度:一排书要真的摆满这层架子,而不是缩在左边
      final usable = 360 - SpineMetrics.framePadding * 2;
      final spine = spineWidthForSlot(usable / n);
      expect(spine, inInclusiveRange(SpineMetrics.minWidth, SpineMetrics.maxWidth));
      expect(spine * n, greaterThan(usable * 0.8),
          reason: '一排书至少要占满 80% 的可用宽度(剩下的才是"还能放"的留白)');
    });

    test('宽屏(1080)也不超过上限 7(否则书脊会变成细条)', () {
      expect(booksPerShelf(1080), 7);
      expect(booksPerShelf(2000), 7);
    });

    test('极窄屏兜到下限 3,宽度非法时不崩', () {
      expect(booksPerShelf(200), 3);
      expect(booksPerShelf(0), 5, reason: '宽度为 0 属于"还没布局",给默认值');
      expect(booksPerShelf(-10), 5);
      expect(booksPerShelf(double.infinity), 5);
      expect(booksPerShelf(double.nan), 5);
    });

    test('单调不减:屏越宽一层放得越多', () {
      var prev = booksPerShelf(320);
      for (var w = 320.0; w <= 900; w += 20) {
        final n = booksPerShelf(w);
        expect(n, greaterThanOrEqualTo(prev));
        prev = n;
      }
    });
  });

  group('spineWidthForSlot(书位宽 → 书脊宽)', () {
    test('夹在 30~40 之间:再宽的书位也不能让书脊变成一块板', () {
      expect(spineWidthForSlot(60), SpineMetrics.maxWidth);
      expect(spineWidthForSlot(200), SpineMetrics.maxWidth);
      expect(spineWidthForSlot(20), SpineMetrics.minWidth);
      expect(spineWidthForSlot(0), SpineMetrics.minWidth);
      expect(spineWidthForSlot(double.nan), SpineMetrics.minWidth);
    });

    test('书位比夹紧上限略宽时跟着走(书与书之间才有缝)', () {
      expect(spineWidthForSlot(38), closeTo(30, 1e-9));
      expect(spineWidthForSlot(44), closeTo(36, 1e-9));
    });
  });

  // ── 2. 纯函数:书脊配色 ──

  group('spinePalette(书脊配色)', () {
    test('同一标题两次取到完全相同的颜色(不能每次冷启动都换色)', () {
      final a = spinePalette('Pride and Prejudice');
      final b = spinePalette('Pride and Prejudice');
      expect(a, equals(b));
      expect(a.first, equals(b.first));
    });

    test('不同标题应当取到不同颜色', () {
      final a = spinePalette('Pride and Prejudice');
      final b = spinePalette('The Old Man and the Sea');
      expect(a.first, isNot(equals(b.first)));
    });

    test('配色稳定且低饱和:每档两色、都带得动白字或黑字', () {
      expect(spinePalette('任意标题'), hasLength(2));
      for (final pair in spinePaletteColors) {
        expect(pair, hasLength(2));
        // 低饱和的判据:两色的明度差不能太夸张(夸张就成了"渐变卡片"而不是"纸脊")
        final lumA = pair.first.computeLuminance();
        final lumB = pair.last.computeLuminance();
        expect((lumA - lumB).abs(), lessThan(0.25));
      }
    });

    test('空标题不抛,回落成第一档', () {
      expect(spinePalette(''), spinePaletteColors.first);
      expect(spinePalette('   '), spinePaletteColors.first);
    });
  });

  // ── 3. 纯函数:书脊取字 ──

  group('spineLabel(书脊上那几个字)', () {
    test('中文标题取前 4 个字,不切断词', () {
      expect(spineLabel('傲慢与偏见', vertical: true), '傲慢与偏');
      expect(spineLabel('双城记', vertical: true), '双城记');
      expect(spineLabel('老人与海的故事很长很长', vertical: true), '老人与海');
    });

    test('中文标题带书名号/引号时先去掉标点', () {
      expect(spineLabel('《了不起的盖茨比》', vertical: true), '了不起的');
      expect(spineLabel('「小王子」', vertical: true), '小王子');
    });

    test('中英混排时中文优先(用户要的是中文书名)', () {
      expect(
        spineLabel('傲慢与偏见 Pride and Prejudice', vertical: true),
        '傲慢与偏',
      );
      expect(
        spineLabel('小王子 The Little Prince', vertical: true),
        '小王子',
      );
    });

    test('英文标题取第一个有意义的词,跳过 the/a/of', () {
      expect(spineLabel('The Great Gatsby', vertical: true), 'Great');
      expect(spineLabel('A Tale of Two Cities', vertical: true), 'Tale');
      expect(spineLabel('Of Mice and Men', vertical: true), 'Mice');
    });

    test('英文单词整体保留,不从单词中间断开(超长才截到 8 字符)', () {
      expect(spineLabel('Inevitable', vertical: true), 'Inevitab');
      expect(spineLabel('Pride', vertical: true), 'Pride');
    });

    test('空标题/纯标点回落成"书",不抛', () {
      expect(spineLabel('', vertical: true), '书');
      expect(spineLabel('   ', vertical: true), '书');
      expect(spineLabel('《》', vertical: true), '书');
    });

    test('横排可以比竖排多给一个字(竖排受书脊高度限制)', () {
      const title = '老人与海的故事';
      expect(spineLabel(title, vertical: true).length, 4);
      expect(spineLabel(title, vertical: false).length, 5);
    });
  });

  // ── 4. 纯函数:进度夹紧 ──

  group('spineProgress(0~100 → 0~1)', () {
    test('正常值换算正确', () {
      expect(spineProgress(0), 0);
      expect(spineProgress(50), closeTo(0.5, 1e-9));
      expect(spineProgress(100), 1);
    });

    test('负数/超过 100/NaN 全部夹紧,不抛', () {
      expect(spineProgress(-30), 0);
      expect(spineProgress(250), 1);
      expect(spineProgress(double.nan), 0);
      expect(spineProgress(double.infinity), 1);
    });
  });

  // ── 5. 纯函数:行 → 模型(脏数据容错)──

  group('BookshelfBook.fromRow(脏数据不能抛)', () {
    test('正常行:字段逐个对上,标题中文优先', () {
      final b = BookshelfBook.fromRow({
        'material_id': 7,
        'title': '傲慢与偏见',
        'title_en': 'Pride and Prejudice',
        'kind': 'book',
        'source': 'gutenberg',
        'cefr': 'c1',
        'word_count': 122000,
        'percent': 0.42,
        'minutes': 35,
        'picked_words': 12,
        'slot': 3,
        'note': '读慢一点',
        'added_at': '2026-10-01T10:00:00.000',
        'finished_at': null,
      });
      expect(b.materialId, 7);
      expect(b.title, '傲慢与偏见');
      expect(b.titleEn, 'Pride and Prejudice');
      expect(b.subtitle, 'Pride and Prejudice');
      expect(b.kind, 'book');
      expect(b.cefr, 'C1', reason: 'CEFR 统一大写,方便匹配');
      expect(b.wordCount, 122000);
      expect(b.percent, closeTo(42, 1e-9), reason: '0.42 是比例口径 → 归一成 42');
      expect(b.minutes, 35);
      expect(b.pickedWords, 12);
      expect(b.slot, 3);
      expect(b.note, '读慢一点');
      expect(b.addedAt, isNotNull);
      expect(b.finished, isFalse);
      expect(b.reading, isTrue);
    });

    test('中文与英文标题相同时不重复显示副标题', () {
      final b = BookshelfBook.fromRow({
        'material_id': 1,
        'title': 'Pride and Prejudice',
        'title_en': 'Pride and Prejudice',
      });
      expect(b.subtitle, isEmpty);
    });

    test('字段缺失:全部走默认值,标题兜底成"未命名材料"', () {
      final b = BookshelfBook.fromRow(const {});
      expect(b.materialId, 0);
      expect(b.title, '未命名材料');
      expect(b.kind, 'article');
      expect(b.percent, 0);
      expect(b.minutes, 0);
      expect(b.finished, isFalse);
      expect(b.addedAt, isNull);
      expect(b.updatedAt, isNull);
      expect(b.progress, 0);
      expect(b.untouched, isTrue);
    });

    test('类型不对(字符串数字 / 奇怪类型 / 字面量 null)也解析得出来', () {
      final b = BookshelfBook.fromRow({
        'material_id': '9',
        'title': null,
        'title_en': 'Something',
        'percent': '55.5',
        'minutes': '20',
        'word_count': 3.7,
        'kind': 123,
        'picked_words': Object(),
        'slot': 'x',
        'added_at': '不是时间',
      });
      expect(b.materialId, 9);
      expect(b.title, 'Something', reason: '中文缺了就取英文原名,不能显示 null');
      expect(b.percent, closeTo(55.5, 1e-9));
      expect(b.minutes, 20);
      expect(b.wordCount, 3);
      expect(b.kind, 'article', reason: '认不出的种类按文章处理,不会出现空图标');
      expect(b.pickedWords, 0);
      expect(b.slot, 0);
      expect(b.addedAt, isNull, reason: '解析不出的时间给 null,界面隐藏那一行');
    });

    test('percent 两套口径都认:比例(0.5)与百分数(50)都得到 50', () {
      expect(
        BookshelfBook.fromRow({'percent': 0.5}).percent,
        closeTo(50, 1e-9),
      );
      expect(BookshelfBook.fromRow({'percent': 50}).percent, 50);
      expect(BookshelfBook.fromRow({'percent': 1.0}).percent, 100);
      expect(BookshelfBook.fromRow({'percent': 100}).percent, 100);
    });

    test('负数/超范围进度夹到 0~100', () {
      expect(BookshelfBook.fromRow({'percent': -5}).percent, 0);
      expect(BookshelfBook.fromRow({'percent': 999}).percent, 100);
      expect(BookshelfBook.fromRow({'percent': 'abc'}).percent, 0);
    });

    test('读完的两种口径都认:有完成时间,或进度到 100', () {
      expect(
        BookshelfBook.fromRow({
          'percent': 0.1,
          'finished_at': '2026-10-02T00:00:00.000',
        }).finished,
        isTrue,
      );
      expect(BookshelfBook.fromRow({'percent': 100}).finished, isTrue);
      expect(BookshelfBook.fromRow({'percent': 99}).finished, isFalse);
    });
  });

  // ── 6. 纯函数:统计 ──

  group('BookshelfStats.statsOf(顶部那四个数字)', () {
    test('总数/读完/在读/未翻开/合计分钟都对得上', () {
      final stats = BookshelfStats.statsOf([
        BookshelfBook.sample(materialId: 1, title: 'A', percent: 100, minutes: 30),
        BookshelfBook.sample(materialId: 2, title: 'B', percent: 40, minutes: 12),
        BookshelfBook.sample(materialId: 3, title: 'C', percent: 10, minutes: 3),
        BookshelfBook.sample(materialId: 4, title: 'D', minutes: 0),
      ]);
      expect(stats.total, 4);
      expect(stats.finished, 1);
      expect(stats.reading, 2);
      expect(stats.untouched, 1);
      expect(stats.minutes, 45);
      expect(stats.minutesLabel, '45 分钟');
    });

    test('finished 标记优先于 percent(读完但进度没写满也算读完)', () {
      final stats = BookshelfStats.statsOf([
        BookshelfBook.sample(
          materialId: 1,
          title: 'A',
          percent: 30,
          finished: true,
        ),
      ]);
      expect(stats.finished, 1);
      expect(stats.reading, 0);
    });

    test('空书架:全是 0,不除零', () {
      final stats = BookshelfStats.statsOf(const []);
      expect(stats.total, 0);
      expect(stats.avgPercent, 0);
      expect(stats.minutesLabel, '0 分钟');
    });

    test('时长人话:跨小时会进位', () {
      expect(const BookshelfStats(minutes: 59).minutesLabel, '59 分钟');
      expect(const BookshelfStats(minutes: 60).minutesLabel, '1 小时');
      expect(const BookshelfStats(minutes: 145).minutesLabel, '2 小时 25 分');
    });

    test('平均进度:读完的按 100 计', () {
      final stats = BookshelfStats.statsOf([
        BookshelfBook.sample(materialId: 1, title: 'A', percent: 100),
        BookshelfBook.sample(materialId: 2, title: 'B', percent: 50),
      ]);
      expect(stats.avgPercent, closeTo(75, 1e-9));
    });
  });

  // ── 7. 真 SQLite:书架表 ──

  group('书架表(真 SQLite)', () {
    late Directory tmp;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rf_bookshelf_test');
      await databaseFactory.setDatabasesPath(tmp.path);
      await DatabaseService.resetForTest();
    });

    tearDown(() async {
      await DatabaseService.resetForTest();
      try {
        await databaseFactory.deleteDatabase(
          p.join(tmp.path, AppConstants.dbName),
        );
      } catch (_) {}
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// 造一篇材料(书架靠 JOIN materials 取标题与元信息,所以必须先有材料)
    Future<int> newMaterial(String title, {String? titleCn}) async {
      final id = await DatabaseService.upsertMaterial({
        'kind': 'book',
        'source': 'gutenberg',
        'source_id': 'pg-$title',
        'title': title,
        'word_count': 1000,
        'cefr': 'B2',
        'created_at': DateTime(2026, 3, 1).toIso8601String(),
      });
      expect(id, greaterThan(0));
      if (titleCn != null) {
        await DatabaseService.setMaterialTitleCn(id, titleCn);
      }
      return id;
    }

    test('addToBookshelf 两次同一本:不重复加,只更新备注,slot 不跳号', () async {
      final id = await newMaterial('Pride and Prejudice');

      final first = await DatabaseService.addToBookshelf(id, note: '第一次');
      expect(first, greaterThan(0));
      expect(await DatabaseService.bookshelfCount(), 1);

      final second = await DatabaseService.addToBookshelf(
        id,
        note: '改主意了',
        fromWhere: 'shelf',
      );
      // 同一行被复用(返回同一个主键),而不是插出第二行
      expect(second, first, reason: '已在架上必须复用原行,不能堆出第二本');
      expect(await DatabaseService.bookshelfCount(), 1, reason: '架上仍然只有一本');

      final rows = await DatabaseService.bookshelfItems();
      expect(rows, hasLength(1));
      expect(rows.first['note'], '改主意了');
      expect(rows.first['slot'], 1, reason: '只有一本,slot 必须是 1');
      expect(await DatabaseService.isOnBookshelf(id), isTrue);
    });

    test('bookshelfItems 按 slot 顺序返回,并带出 percent 与中文标题', () async {
      final a = await newMaterial('Pride and Prejudice', titleCn: '傲慢与偏见');
      final b = await newMaterial('The Old Man and the Sea');
      final c = await newMaterial('A Tale of Two Cities', titleCn: '双城记');

      // 故意乱序放入:加入顺序 = slot 顺序 = 书架上的摆放顺序
      await DatabaseService.addToBookshelf(b);
      await DatabaseService.addToBookshelf(c);
      await DatabaseService.addToBookshelf(a);
      await DatabaseService.upsertMaterialProgress(
        b,
        position: 3,
        percent: 0.66,
        addMinutes: 25,
      );

      final rows = await DatabaseService.bookshelfItems();
      expect(rows, hasLength(3));
      expect(
        rows.map((r) => r['material_id']).toList(),
        [b, c, a],
        reason: '必须严格按 slot 升序(摆放顺序),不是按加入时间倒序',
      );
      expect(rows.map((r) => r['slot']).toList(), [1, 2, 3]);

      final second = rows[1];
      expect(second['material_id'], c);
      expect(second['title'], '双城记', reason: '有中文名就显示中文名');

      final first = rows[0];
      expect(first['percent'], closeTo(0.66, 1e-9));
      expect(first['minutes'], 25);
      expect(
        first['title'],
        'The Old Man and the Sea',
        reason: '没有中文名时回落英文原标题,不能是空',
      );

      // 模型层再走一遍:书架页真正用的是 BookshelfBook
      final books = rows.map(BookshelfBook.fromRow).toList();
      expect(books.first.percent, closeTo(66, 1e-9), reason: '模型层归一成 0~100');
      expect(books.first.minutes, 25);
      expect(BookshelfStats.statsOf(books).total, 3);
      expect(BookshelfStats.statsOf(books).reading, 1);
    });

    test('removeFromBookshelf 后 isOnBookshelf 为 false,书架少一本', () async {
      final a = await newMaterial('Book A');
      final b = await newMaterial('Book B');
      await DatabaseService.addToBookshelf(a);
      await DatabaseService.addToBookshelf(b);
      expect(await DatabaseService.bookshelfCount(), 2);

      await DatabaseService.removeFromBookshelf(a);

      expect(await DatabaseService.isOnBookshelf(a), isFalse);
      expect(await DatabaseService.isOnBookshelf(b), isTrue, reason: '不能误删别人');
      expect(await DatabaseService.bookshelfCount(), 1);
      final rows = await DatabaseService.bookshelfItems();
      expect(rows.map((r) => r['material_id']).toList(), [b]);
    });

    test('setBookshelfOrder:重排后 bookshelfItems 立刻按新顺序返回', () async {
      final a = await newMaterial('Book A');
      final b = await newMaterial('Book B');
      final c = await newMaterial('Book C');
      await DatabaseService.addToBookshelf(a);
      await DatabaseService.addToBookshelf(b);
      await DatabaseService.addToBookshelf(c);

      await DatabaseService.setBookshelfOrder([c, a, b]);

      final rows = await DatabaseService.bookshelfItems();
      expect(rows.map((r) => r['material_id']).toList(), [c, a, b]);
      expect(rows.map((r) => r['slot']).toList(), [1, 2, 3]);
    });

    test('materialsMissingTitleCn:只返回没有中文名的材料', () async {
      final a = await newMaterial('Needs Translation');
      await newMaterial('Has Translation', titleCn: '已有中文');

      final missing = await DatabaseService.materialsMissingTitleCn(limit: 8);
      expect(missing.map((r) => r['id']).toList(), [a]);
      expect(missing.first['title'], 'Needs Translation');
    });
  });
}
