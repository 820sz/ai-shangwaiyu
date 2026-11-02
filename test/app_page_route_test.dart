import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/widgets/app_page_route.dart';

/// 批 6 · 页面转场助手的最小回归。
///
/// 它被用在"输出 → 选来源 → 练习器"的钻取流里;守两件事:
/// 1. 能正常推入/返回(转场本身不阻塞导航);
/// 2. 系统开启"减少动画"时**画面不再做淡入/位移**(无障碍要求):
///    路由时长仍按 220ms 走,但转场层级里不应再出现 FadeTransition。
void main() {
  testWidgets('appPush 能推入新页面并返回', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => appPush(
                  context,
                  (_) => const Scaffold(body: Center(child: Text('第二页'))),
                ),
                child: const Text('去第二页'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('去第二页'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('第二页'), findsOneWidget);

    // 返回也能正常完成转场
    Navigator.of(tester.element(find.text('第二页'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('去第二页'), findsOneWidget);
  });

  testWidgets('开启"减少动画"时转场不再有淡入层级(无障碍)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // 无障碍开关要挂在整个 App 的 MediaQuery 上(挂在 home 子树里时,
        // Navigator 的 overlay 读不到它,转场照旧做动画)。
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => appPush(
                  context,
                  (_) => const Scaffold(
                    body: Center(child: Text('直接出现')),
                  ),
                ),
                child: const Text('去'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('去'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('直接出现'), findsOneWidget);
    // 转场层级里没有 FadeTransition = 画面不淡入
    expect(
      find.ancestor(
        of: find.text('直接出现'),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });
}
