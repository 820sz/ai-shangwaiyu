import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/design_tokens.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/widgets/app_ui.dart';
import 'package:readflow/widgets/bottom_nav.dart';

/// 全局 UI 升级的地基测试(v2.11 建立,v2.12 按新设计重写)。
///
/// 用户 2026-10-23 的原则:「**精简和高级、实用是第一位**,在此基础上,
/// 去增加软件前端的丰富性和趣味性」。同一条消息里还要求"整个软件的前端都要升级,
/// 不只是 ui,交互、分类逻辑等等"。
///
/// 本文件钉的是**地基的合同** —— 所有页面共享的卡片/版式规则:
/// 1. 新卡片是"真阴影 + 大圆角"(v2.12 的核心视觉变化;深色下无阴影);
/// 2. 变体之间确实长得不一样(hero 更圆更浮、compact 更紧);
/// 3. 网格版式在 320 宽不溢出(用户被"按钮被裁成『原』字"坑过);
/// 4. 底栏有轻动效,但只有既有那三样(不弹跳)。
void main() {
  Widget host(Widget child, {double width = 360, bool dark = false}) =>
      MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  group('AppCard 变体(v2.12:真阴影 + 大圆角)', () {
    Material surf(WidgetTester t) =>
        t.widget<Material>(find.byKey(AppCard.surfaceKey));

    EdgeInsets padOf(WidgetTester t) => t
        .widget<Padding>(find.byKey(AppCard.paddingKey))
        .padding as EdgeInsets;

    BoxDecoration decoOf(WidgetTester t) {
      final container = t.widget<Container>(
        find
            .ancestor(
              of: find.byKey(AppCard.surfaceKey),
              matching: find.byType(Container),
            )
            .first,
      );
      return container.decoration! as BoxDecoration;
    }

    testWidgets('plain:圆角 20 + 柔和小阴影 + 内边距 16(浅色)', (tester) async {
      await tester.pumpWidget(host(const AppCard(child: Text('x'))));
      final m = surf(tester);
      expect(
        (m.borderRadius as BorderRadius).topLeft.x,
        Radii.card,
        reason: 'v2.12 卡片圆角从 16 提到 20(样图的大卡圆角)',
      );
      expect(
        decoOf(tester).boxShadow,
        isNotEmpty,
        reason: '浅色下必须能看到柔和阴影 —— 这是"高级感"的主要来源之一',
      );
      expect(padOf(tester), Insets.card);
    });

    testWidgets('plain 在深色下没有阴影(层级靠表面亮度差)', (tester) async {
      await tester.pumpWidget(
        host(const AppCard(child: Text('x')), dark: true),
      );
      expect(
        decoOf(tester).boxShadow,
        isEmpty,
        reason: '深色下阴影几乎看不见,堆了只会变脏 —— 既有主题原则',
      );
    });

    testWidgets('hero:圆角 24 + 更重的阴影 + 染底(一屏一个的主角)', (tester) async {
      await tester.pumpWidget(
        host(const AppCard(variant: AppCardVariant.hero, child: Text('x'))),
      );
      final m = surf(tester);
      expect((m.borderRadius as BorderRadius).topLeft.x, Radii.hero);
      expect(decoOf(tester).boxShadow, isNotEmpty);
      // 主角卡必须有底色差异(深色下阴影为空时,靠这层染底区分)
      expect(m.color, isNotNull);
    });

    testWidgets('accent:有染底,但阴影仍是静置档(不抢主角地位)', (tester) async {
      await tester.pumpWidget(
        host(const AppCard(variant: AppCardVariant.accent, child: Text('x'))),
      );
      expect(surf(tester).color, isNotNull);
      expect(
        (surf(tester).borderRadius as BorderRadius).topLeft.x,
        Radii.card,
        reason: 'accent 不该变大圆角 —— 那是 hero 的待遇',
      );
    });

    testWidgets('compact:内边距更紧(信息密度高的行)', (tester) async {
      await tester.pumpWidget(
        host(const AppCard(variant: AppCardVariant.compact, child: Text('x'))),
      );
      expect(padOf(tester), Insets.tile);
    });

    testWidgets('显式 color 仍然优先(老调用点传色的场景不能被变体覆盖)', (tester) async {
      const red = Color(0xFF112233);
      await tester.pumpWidget(
        host(const AppCard(
          variant: AppCardVariant.hero,
          color: red,
          child: Text('x'),
        )),
      );
      expect(surf(tester).color, red);
    });
  });

  group('AppActionTile 版式', () {
    testWidgets('row:默认版式,图标 + 标题 + 箭头', (tester) async {
      await tester.pumpWidget(host(
        AppActionTile(icon: Icons.school, title: '教材', onTap: () {}),
      ));
      expect(find.text('教材'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.school), findsOneWidget);
    });

    testWidgets('grid:方块版式(无箭头、标题居中、320 宽不溢出)', (tester) async {
      await tester.pumpWidget(host(
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          mainAxisSpacing: Gap.xs,
          crossAxisSpacing: Gap.xs,
          childAspectRatio: 1.35,
          children: [
            for (final t in ['教材', '书籍', '外刊', '碎片文章'])
              AppActionTile(
                style: AppActionTileStyle.grid,
                icon: Icons.menu_book,
                title: t,
                onTap: () {},
              ),
          ],
        ),
        width: 320,
      ));
      expect(find.text('教材'), findsOneWidget);
      expect(find.text('碎片文章'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing,
          reason: '网格方块里不该有箭头(那是行式版式的东西)');
      expect(tester.takeException(), isNull);
    });
  });

  group('底部导航的轻动效(用户要求"高级但不眼花缭乱")', () {
    testWidgets('选中项有指示条与缩放,未选中没有', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          bottomNavigationBar: ReadFlowBottomNav(
            currentTab: ReadFlowTab.input,
            onTabChanged: (_) {},
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AnimatedScale), findsNWidgets(4));
      expect(find.byType(AnimatedContainer), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  });
}
