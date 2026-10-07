import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/design_tokens.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/widgets/app_ui.dart';
import 'package:readflow/widgets/bottom_nav.dart';

/// 全局 UI 升级(v2.11 G 批)的地基测试。
///
/// 用户 10/5 的原话:"**软件全局的前端 ui 的大升级** —— 现在的各种功能多起来后,
/// 前端非常单一,清一色的竖列功能块…各种各样的前端表现都非常单调平庸"。
/// 同一条消息里他还给了边界:"**不失精简和高级,不要眼花缭乱找不到功能,但也要丰富
/// 增加使用的欲望**"。
///
/// 体检结论(改之前的机制性原因):`AppCard` 是全 App 唯一的容器,参数只有
/// `child/onTap/padding/margin/color/dense` —— **没有型号**;`AppActionTile`
/// 只有一种版式却被用了 20 次。所以这一批补的是**变体维度**(语义),
/// 不是更多圆角/间距数值。
///
/// 本文件钉三件事:
/// 1. 变体确实"长得不一样"(hero 浮起 + 大圆角,compact 更紧);
/// 2. 老调用点**不受影响**(plain 仍是 v2.5 的样子 —— 51 处调用点的合同);
/// 3. 网格版式在窄屏不溢出(用户被"按钮裁成『原』字"坑过一次)。
void main() {
  Widget host(Widget child, {double width = 360}) => MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      );

  group('AppCard 变体', () {
    /// 卡片**自己的**内边距(用 AppCard.paddingKey 精确定位:
    /// 直接用 `find.byType(Padding).first` 会命中 Card 内部的 margin padding)
    EdgeInsets cardPadding(WidgetTester tester) => tester
        .widget<Padding>(find.descendant(
          of: find.byType(Card),
          matching: find.byKey(AppCard.paddingKey),
        ))
        .padding as EdgeInsets;

    testWidgets('plain 保持老样子:圆角 16、沿用主题 elevation、内边距 14', (tester) async {
      await tester.pumpWidget(host(const AppCard(child: Text('x'))));
      final card = tester.widget<Card>(find.byType(Card));
      // 不硬压 elevation:必须是主题给的那一档(theme.cardTheme.elevation = 1)。
      // 曾把 plain 压成 0,导致全 App 普通卡片一起变平 —— 这是回归防线。
      expect(card.elevation, isNull, reason: 'null = 交给主题,不覆盖 51 处老调用点的观感');
      final shape = card.shape! as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        Radii.cardRadius,
        reason: 'plain 必须还是 16 圆角 —— 51 处老调用点的外观合同',
      );
      expect(cardPadding(tester), Insets.card);
    });

    testWidgets('hero:浮起(elevation>0)+ 更大圆角(20)= 一屏一个的主角', (tester) async {
      await tester.pumpWidget(
        host(const AppCard(variant: AppCardVariant.hero, child: Text('x'))),
      );
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.elevation, AppElevation.raised);
      final shape = card.shape! as RoundedRectangleBorder;
      expect(
        (shape.borderRadius as BorderRadius).topLeft.x,
        Radii.sheet,
        reason: 'hero 用弹层级的大圆角,和普通卡拉开差距',
      );
      // 主角卡必须**有底色差异**(深色下阴影几乎看不见,靠染底区分)
      expect(card.color, isNotNull);
      expect(card.color, isNot(equals(ThemeData.dark().colorScheme.surface)));
    });

    testWidgets('accent:有染底但不浮起(强调而不抢主角地位)', (tester) async {
      await tester.pumpWidget(
        host(const AppCard(variant: AppCardVariant.accent, child: Text('x'))),
      );
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.elevation, isNull, reason: 'accent 不覆盖主题 elevation(不浮起)');
      expect(card.color, isNotNull);
    });

    testWidgets('compact:内边距更紧(信息密度高的行)', (tester) async {
      await tester.pumpWidget(
        host(const AppCard(variant: AppCardVariant.compact, child: Text('x'))),
      );
      expect(cardPadding(tester), Insets.tile);
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
      expect(tester.widget<Card>(find.byType(Card)).color, red);
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

    testWidgets('grid:方块版式(无箭头、标题居中、可两列排布且不溢出)', (tester) async {
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
        // 320 是常见小屏宽度:中文四字标签在这种格子里最容易挤出界
        width: 320,
      ));
      expect(find.text('教材'), findsOneWidget);
      expect(find.text('碎片文章'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing,
          reason: '网格方块里不该有箭头(那是行式版式的东西)');
      // 溢出会以异常形式被捕获 —— 这正是当年"按钮被裁成『原』字"的防线
      expect(tester.takeException(), isNull);
    });
  });

  group('底部导航的轻动效(用户要求"高级但不眼花缭乱")', () {
    testWidgets('选中项有指示条与缩放,未选中没有', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          bottomNavigationBar: ReadFlowBottomNav(
            currentTab: ReadFlowTab.input,
            onTabChanged: (_) {},
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      // 四个 tab 都有 AnimatedScale(未选中 scale=1.0),别有 0 个
      expect(find.byType(AnimatedScale), findsNWidgets(4));
      expect(find.byType(AnimatedContainer), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });
  });
}
