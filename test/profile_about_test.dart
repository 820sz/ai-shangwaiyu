import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/screens/profile/about_doc_screen.dart';
import 'package:readflow/screens/profile/about_notice_screen.dart';
import 'package:readflow/screens/profile/about_screen.dart';
import 'package:readflow/services/about_content.dart';
import 'package:readflow/services/about_notice.dart';
import 'package:readflow/services/profile_card.dart';
import 'package:readflow/widgets/profile_name_card.dart';

/// 用户第 7/8 条:名片两态、关于三入口、公告页排版、Markdown 不崩。
///
/// **为什么要写得这么保守(踩坑记录)**:
/// 2026-11-07 曾用 `pumpAndSettle` + Hive 写在 fake-async 里 + LicensePage 实时
/// 汇总裁荷,导致 flutter_tester 挂死 17 分钟、堵住全队 flutter 队列。
/// 现在这里只保留**确定性、快速**的用例:
/// - 不用 `pumpAndSettle`(有界 pump + runAsync);
/// - 不写 Hive(名片两态用 `settingsOverride` 注入);
/// - 不 await rootBundle(内容读取的打包验证放在渲染图 + 真机);
/// - 不开 LicensePage 的异步载荷(开源许可入口在「关于页渲染」用例里断言存在,
///   LicensePage 是 Flutter 自带页面,真机点开即系统行为)。
/// 「只弹一次」的行为在 `test/profile_about_gate_test.dart` 单独验(隔离风险)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_about_test');
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
    AboutContent.resetCache();
  });

  tearDown(() async {
    await Hive.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester, {int rounds = 4}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  void bigView(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1.0;
  }

  group('公告与关于(用户第 8 条)', () {
    test('Hive 标记:首次该弹;markSeen 后不再弹;reset 后恢复(只弹一次的证据)',
        () async {
      expect(AboutNotice.shouldShow, isTrue);
      expect(AboutNotice.seen, isFalse);
      await AboutNotice.markSeen();
      expect(AboutNotice.seen, isTrue);
      expect(AboutNotice.shouldShow, isFalse);
      await AboutNotice.reset();
      expect(AboutNotice.shouldShow, isTrue);
    });

    test('文档元数据:三份文档路径/标题/公告定位齐全，版本号 v2.28.0', () {
      expect(AboutDoc.values.length, 3);
      for (final AboutDoc doc in AboutDoc.values) {
        expect(doc.assetPath, startsWith('assets/about/'));
        expect(doc.assetPath, endsWith('.md'));
        expect(doc.title.trim(), isNotEmpty);
        expect(doc.noticeLabel.trim(), isNotEmpty);
      }
      expect(AboutContent.versionLabel, 'v2.28.0');
    });

    testWidgets('公告页(firstRun):三块摘要 + 「我已阅读并继续」+ 版本号',
        (WidgetTester tester) async {
      bigView(tester);
      await tester.pumpWidget(
        const MaterialApp(home: AboutNoticeScreen()),
      );
      await settle(tester);
      expect(find.text('花一分钟，认识这个软件'), findsOneWidget);
      expect(find.text('软件声明'), findsOneWidget);
      expect(find.text('软件特色'), findsOneWidget);
      expect(find.text('软件思想'), findsOneWidget);
      expect(find.text('我已阅读并继续'), findsOneWidget);
      expect(find.textContaining('v2.28.0'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('公告页(重看):按钮是「关闭」', (WidgetTester tester) async {
      bigView(tester);
      await tester.pumpWidget(
        const MaterialApp(home: AboutNoticeScreen(firstRun: false)),
      );
      await settle(tester);
      expect(find.text('这个软件是什么、怎么想'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);
      expect(find.text('我已阅读并继续'), findsNothing);
    });

    testWidgets('关于页:三入口 + 开屏公告 + 开源许可 + 版本号 都在',
        (WidgetTester tester) async {
      bigView(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: AboutScreen(
            onCheckUpdate: () async {},
            onShowDiagnostics: () async {},
          ),
        ),
      );
      await settle(tester);
      expect(find.text('软件声明'), findsOneWidget);
      expect(find.text('软件特色'), findsOneWidget);
      expect(find.text('软件思想'), findsOneWidget);
      expect(find.text('开屏公告'), findsOneWidget);
      expect(find.text('开源许可'), findsOneWidget);
      expect(find.textContaining('v2.28.0'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('内容页:注入 Markdown 渲染不崩（标题/强调/引用/外链）',
        (WidgetTester tester) async {
      bigView(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: AboutDocScreen(
            doc: AboutDoc.philosophy,
            overrideMarkdown:
                '# 标题\n\n正文 **加粗** 与 [文献](https://example.com)。\n\n> 引用一句\n',
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('正文'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('名片两态(用户第 7 条)', () {
    Widget cardPage({ProfileCardSettings? settings}) => MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: ProfileNameCard(vocabCount: 60, settingsOverride: settings),
            ),
          ),
        );

    testWidgets('无背景图:纸面卡,名字/三栏清晰', (WidgetTester tester) async {
      bigView(tester);
      await tester.pumpWidget(cardPage());
      await settle(tester);
      expect(find.text('PROFILE · 我的名片'), findsOneWidget);
      expect(find.text('未测 · 去测'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('有背景图:scrim 后仍渲染昵称/三栏,不崩', (WidgetTester tester) async {
      bigView(tester);
      final File photo = File('assets/images/whale_tail.png');
      expect(photo.existsSync(), isTrue, reason: '需要一个真实图片文件做背景');
      await tester.pumpWidget(
        cardPage(
          settings: ProfileCardSettings(
            nickname: 'xi283',
            signature: '把英语用起来',
            backgroundPath: photo.absolute.path,
            backgroundId: 'dawn',
          ),
        ),
      );
      await settle(tester, rounds: 5);
      expect(find.text('xi283'), findsOneWidget);
      expect(find.text('PROFILE · 我的名片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
