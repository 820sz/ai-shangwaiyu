import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/material_channel_screen.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/material_channel.dart';
import 'package:readflow/services/material_taxonomy.dart';

/// 频道页「结果真分页 / 顶部分类条随滚动收起」的测试(2026-11-06 用户真机反馈)。
///
/// 三层口径,分别锁不同的错法:
/// 1. **纯函数**:页数/页码夹紧/页区间 —— 这些一旦算错,界面会"翻页翻到空白页"
///    或"最后一页点不动",而且不会报错,只能靠断言;
/// 2. **滚动收起**:分类条(chips)不再固定占位,滚走后出现紧凑范围条;
///    用紧凑条的目标 opacity 断言(0 = 未滚走 / 1 = 已滚走);
/// 3. **翻页行为**:12 条结果 → 第 1 页 10 条、第 2 页 2 条;上一页/下一页在
///    首末页不可用;切页后列表滚回顶部(否则用户看不到新一页的开头)。
void main() {
  group('分页纯函数', () {
    test('页数:0 条也算 1 页(不会出现"第 1 / 0 页")', () {
      expect(materialChannelPageCount(0), 1);
      expect(materialChannelPageCount(-3), 1);
    });

    test('页数:按每页 10 条向上取整', () {
      expect(materialChannelPageCount(1), 1);
      expect(materialChannelPageCount(10), 1);
      expect(materialChannelPageCount(11), 2);
      expect(materialChannelPageCount(20), 2);
      expect(materialChannelPageCount(21), 3);
      expect(materialChannelPageCount(120), 12);
    });

    test('页数:pageSize 非法时退化成 1 页(防御脏参数)', () {
      expect(materialChannelPageCount(50, pageSize: 0), 1);
      expect(materialChannelPageCount(50, pageSize: -5), 1);
    });

    test('页码夹紧:负数 → 0,越界 → 最后一页', () {
      expect(materialChannelPageClamp(-1, 12), 0);
      expect(materialChannelPageClamp(0, 12), 0);
      expect(materialChannelPageClamp(1, 12), 1);
      expect(materialChannelPageClamp(9, 12), 1);
      expect(materialChannelPageClamp(0, 0), 0);
    });

    test('页区间:第 2 页取 10..12(末页不满也正确)', () {
      expect(
        materialChannelPageRange(0, 12),
        (start: 0, end: 10),
      );
      expect(
        materialChannelPageRange(1, 12),
        (start: 10, end: 12),
      );
      expect(
        materialChannelPageRange(5, 12), // 越界页码先夹紧再取区间
        (start: 10, end: 12),
      );
      expect(
        materialChannelPageRange(0, 0),
        (start: 0, end: 0),
      );
    });
  });

  group('频道页真分页(渲染)', () {
    late Directory tmp;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmp = await Directory.systemTemp.createTemp('rf_channel_paging');
      await databaseFactory.setDatabasesPath(tmp.path);
      await DatabaseService.resetForTest();
      Hive.init(tmp.path);
      await Hive.openBox(AppConstants.hiveBoxSettings);

      // 12 条发现结果(全是 article,单分组):第 1 页 10 条、第 2 页 2 条
      await MaterialChannelStore.saveRun(
        'topic:all',
        items: <Map<String, Object?>>[
          for (var i = 1; i <= 12; i++)
            <String, Object?>{
              'title': '测试材料 ${i.toString().padLeft(2, '0')}',
              'url': 'https://example.com/item/$i',
              'sourceLabel': '测试源',
              'kind': 'article',
              'snippet': '',
            },
        ],
        apiRequests: 1,
        costCny: 0.01,
        queriesUsed: const <String>['test'],
      );
    });

    tearDown(() async {
      await DatabaseService.resetForTest();
      await Hive.close();
      try {
        await databaseFactory
            .deleteDatabase(p.join(tmp.path, AppConstants.dbName));
      } catch (_) {}
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// 发现 Tab 列表的可滚动区(注意别拿到 TabBarView 自己那条**横向** Scrollable)
    Finder _listScrollable() => find
        .descendant(
          of: find.byType(CustomScrollView).first,
          matching: find.byType(Scrollable),
        )
        .first;

    /// 紧凑范围条「改范围」的 AnimatedOpacity 目标值:
    /// 0 = 分类条还没滚走(紧凑条不可见),1 = 已滚走(紧凑条出现)
    double? _compactBarTarget(WidgetTester tester) {
      final finder = find.ancestor(
        of: find.text('改范围'),
        matching: find.byType(AnimatedOpacity),
      );
      final elements = finder.evaluate();
      if (elements.isEmpty) return null;
      return (elements.first.widget as AnimatedOpacity).opacity;
    }

    Future<void> _pumpScreen(WidgetTester tester) async {
      addTearDown(tester.view.reset);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: const MaterialChannelScreen(direction: MaterialDirection.topic),
        ),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      // 等本地快照/材料库读完(纯 widget test 里要走真实的 FFI SQLite + Hive)
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('分类条随滚动滚走,滚走后出现紧凑范围条', (tester) async {
      await _pumpScreen(tester);
      expect(find.text('第 1 / 2 页'), findsNothing, reason: '页码在列表底部,首屏看不到');

      // 未滚动:chips 条照常占位,紧凑条 opacity = 0
      expect(find.text('全部'), findsOneWidget);
      expect(_compactBarTarget(tester), 0);

      // 往上滚 260px(超过 120px 的收起阈值):紧凑条出现
      await tester.drag(
        find.descendant(
          of: find.byType(TabBarView),
          matching: find.byType(CustomScrollView),
        ).first,
        const Offset(0, -260),
      );
      await tester.pumpAndSettle();
      expect(_compactBarTarget(tester), 1, reason: '滚走后要能一眼看到当前频道范围');

      // 点「改范围」→ 滚回顶部 → chips 回来、紧凑条重新隐藏
      await tester.tap(find.text('改范围'));
      await tester.pumpAndSettle();
      expect(_compactBarTarget(tester), 0);
    });

    testWidgets('12 条结果分 2 页:第 1 页 10 条 / 第 2 页 2 条', (tester) async {
      await _pumpScreen(tester);

      // 第 1 页:分组头写"本页 10 条 · 共 12 条"
      expect(find.text('本页 10 条 · 共 12 条'), findsOneWidget);
      // 同组第一页里的第一条一定在;第 11 条属于第 2 页,不该出现
      expect(find.text('测试材料 01'), findsOneWidget);
      expect(find.text('测试材料 11'), findsNothing);

      // 滚到底部,页码控件出现(第 1 / 2 页)
      await tester.scrollUntilVisible(
        find.text('下一页'),
        400,
        scrollable: _listScrollable(),
      );
      expect(find.text('第 1 / 2 页'), findsOneWidget);
      expect(find.text('上一页'), findsOneWidget);
      expect(find.text('下一页'), findsOneWidget);

      // 首页点「上一页」不应该翻页(禁用态)
      await tester.tap(find.text('上一页'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 / 2 页'), findsOneWidget);

      // 翻到第 2 页:内容换成最后 2 条,且滚回列表顶(能看到顶部 chips)
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 / 2 页'), findsOneWidget);
      expect(find.text('测试材料 11'), findsOneWidget);
      expect(find.text('测试材料 01'), findsNothing);

      // 末页点「下一页」不翻页(禁用态)
      await tester.scrollUntilVisible(
        find.text('下一页'),
        400,
        scrollable: _listScrollable(),
      );
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 / 2 页'), findsOneWidget);
    });
  });
}
