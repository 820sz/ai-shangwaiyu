// 开屏页行为测试(2026-11-07 · 方案 A「琉璃凝结」落地后新增)。
//
// 钉住四件**用户能感觉到**的事(动画本身在渲染测试里看图,这里只测行为):
// 1. 动画结束自动进主界面;
// 2. 点任意处**立刻跳过**(不想等的人不该被强制看动画);
// 3. 减少动效(disableAnimations)时**不等 1.5s**,直接终帧 + 200ms 进主界面;
// 4. 文案可自定义(读 SplashSettings.tagline(),默认「让语言,回归本质」)。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/screens/splash_screen.dart';
import 'package:readflow/services/splash_settings.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_splash_ui');
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(Widget child, {bool reduceMotion = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: child,
      ),
    );
  }

  Widget splash() => SplashScreen(child: const Scaffold(body: Text('MAIN')));

  testWidgets('动画结束后自动进入主界面', (tester) async {
    await tester.pumpWidget(wrap(splash()));
    // 动画中:还在开屏
    expect(find.text('MAIN'), findsNothing);
    expect(find.text('轻触任意处跳过'), findsOneWidget);

    // 1.5s 动画 + 250ms 交叉淡出
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MAIN'), findsOneWidget);
  });

  testWidgets('点击任意处立即跳过', (tester) async {
    await tester.pumpWidget(wrap(splash()));
    await tester.pump(const Duration(milliseconds: 120));

    // 屏幕正中点一下(整屏 GestureDetector 的判定区)
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(); // setState(_done = true)
    await tester.pump(const Duration(milliseconds: 300)); // 交叉淡出

    expect(find.text('MAIN'), findsOneWidget);
  });

  testWidgets('减少动效:不等动画,直接终帧 + 200ms 进主界面', (tester) async {
    await tester.pumpWidget(wrap(splash(), reduceMotion: true));
    // 终帧先画出来（disableAnimations 时 t 直接=1.0），此时还没到 200ms 自动进入
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('AI上外语'), findsOneWidget);
    // 200ms 后进主界面（+250ms 交叉淡出）
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MAIN'), findsOneWidget);
  });

  testWidgets('文案可自定义(读 SplashSettings)', (tester) async {
    // 2026-11-07 修复：Hive 真实 I/O 在 testWidgets 的 fake-async zone 里 await 会**永久挂起**
    // （历史上已踩过一次）。写设置必须放进 tester.runAsync。
    await tester.runAsync(() => SplashSettings.setTagline('每天一点点,也算数'));
    await tester.pumpWidget(wrap(splash()));
    await tester.pump(const Duration(milliseconds: 1500));

    expect(find.text('AI上外语'), findsOneWidget);
    expect(find.text('每天一点点,也算数'), findsOneWidget);
    expect(find.text(SplashSettings.defaultTagline), findsNothing);
  });

  testWidgets('默认文案就是用户定的那句', (tester) async {
    await tester.pumpWidget(wrap(splash()));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('让语言,回归本质'), findsOneWidget);
  });
}
