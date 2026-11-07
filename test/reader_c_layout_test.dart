// 阅读器第三轮整改(2026-11-07 用户真机反馈第 2 条)· 空间利用率断言
//
// 用户原话:"空间利用率、排版太低,右侧缺失有些稍多"。
// 整改前正文列 = 390 - 26(左) - 46(给竖轨让位) = 318px;
// 整改后 = 390 - 16(左) - 20(右) = **354px**,竖轨改成 3px overlay 悬浮在
// 右侧安全区,不再挤压正文。
//
// 单独成文件的原因:这是"纯布局断言"(不需要出图),与 reader_c_widget_test 的
// 交互用例分开跑,避免多用例连续跑时 DB 收尾互相拖住(历史坑)。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/material_reader_screen.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/reader_settings.dart';
import 'package:readflow/widgets/reader_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  int? materialId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('readflow_reader_c_layout_');
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    final dbPath = p.join(await getDatabasesPath(), AppConstants.dbName);
    try {
      await databaseFactory.deleteDatabase(dbPath);
    } catch (_) {}
    await DatabaseService.resetForTest();
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

  testWidgets('正文宽度 354px + 竖轨 overlay 不压字(390 宽)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    materialId = await tester.runAsync(() async {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      await box.clear();
      await box.put(
          ReaderSettings.keyReaderPaper, ReaderPaper.white.name);
      final db = await DatabaseService.database;
      final id = await db.insert('materials', <String, Object?>{
        'kind': 'article',
        'source': 'seed',
        'source_id': 'reader-c-layout',
        'title': 'The Quiet Hour',
        'author': 'The Atlantic',
        'language': 'en',
        'word_count': 930,
        'cefr': 'C1',
        'est_minutes': 8,
        'created_at': DateTime.now().toIso8601String(),
      });
      final chunks = <String>[
        'For decades the office celebrated the busy generalist: the person '
            'who answers email during a call and edits a deck while replying '
            'to a message.',
        'The evidence is unusually consistent. What multitasking produces is '
            'not more output but a thinner, more distracted version of it.',
        'That is why a quiet hour can feel more productive than a crowded '
            'afternoon: the effort is simply continuous.',
      ];
      for (var i = 0; i < chunks.length; i++) {
        await db.insert('material_content', <String, Object?>{
          'material_id': id,
          'chunk_index': i,
          'title': 'Section ${i + 1}',
          'text': chunks[i],
        });
      }
      return id;
    });

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: MaterialReaderScreen(materialId: materialId!),
    ));
    // 真实 I/O(runAsync 轮转)+ 推帧,直到正文出来
    for (var i = 0; i < 16; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 24));
      });
      await tester.pump(const Duration(milliseconds: 80));
      if (find.text('上滑工具').evaluate().isNotEmpty) break;
    }

    // ① 正文列宽:整改前 318px(26 左 + 46 右让位),整改后 354px
    final passage = tester.getRect(find.byType(TappablePassage).first);
    expect(passage.width, closeTo(354, 1),
        reason: '正文列宽必须恢复满宽(整改前 318px,整改后 354px)');
    expect(passage.width, greaterThan(350));

    // ② 右侧 96px×3px 竖轨是 overlay:不占正文布局,落在右侧安全区
    final track = tester.getRect(
        find.byKey(const ValueKey<String>('reader-rail-track')));
    expect(track.width, closeTo(3, 0.5));
    expect(track.height, closeTo(96, 0.5));
    expect(track.left - passage.right, greaterThanOrEqualTo(8),
        reason: '竖轨与正文之间必须留 8~12px 安全区,不能压字');
    expect(track.left - passage.right, lessThanOrEqualTo(16));

    // ③ 竖轨在正文文字区之外(overlay 只落在右侧留白)
    expect(track.left, greaterThan(passage.right));

    // ④ % 胶囊在顶部安全条里(不压正文、常驻可见)
    final badge = tester.getRect(
        find.byKey(const ValueKey<String>('reader-rail-percent')));
    expect(badge.right, lessThanOrEqualTo(390));
    expect(badge.top, lessThan(passage.top));

    // 收尾:卸掉页面 + 让真实 I/O 完成,避免 pending timer
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 40));
    }
  });
}
