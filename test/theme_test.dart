import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';

/// 深色模式(v2.2)的回归测试。
///
/// 主题这种"看一眼就知道对不对"的东西,**恰恰最难自动化** —— 但它是可以测的:
/// 1. 亮度关系(页面 < 卡片 < 输入框)是设计约定,可以断言;
/// 2. WCAG 对比度是可以算的(正文 4.5:1),深色最容易在这里翻车
///    (配色好看但看不清);
/// 3. 散落在 40 多个界面文件里的**浅色专用硬编码颜色**(`Colors.grey[800]`
///    这种)不会因为改了主题就自动适配 —— 它们必须被清扫干净,
///    否则深色模式下会冒出亮块和看不清的黑字。下面第 3 组就是这道闸门。
void main() {
  double contrast(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final hi = l1 > l2 ? l1 : l2;
    final lo = l1 > l2 ? l2 : l1;
    return (hi + 0.05) / (lo + 0.05);
  }

  group('主题色板', () {
    test('明暗两套主题各自报告正确的 brightness', () {
      expect(AppTheme.lightTheme.brightness, Brightness.light);
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
      expect(AppTheme.lightTheme.colorScheme.brightness, Brightness.light);
      expect(AppTheme.darkTheme.colorScheme.brightness, Brightness.dark);
    });

    test('深色:页面/卡片/输入框三层亮度递增(层次靠亮度,不靠阴影)', () {
      final t = AppTheme.darkTheme;
      final scaffold = t.scaffoldBackgroundColor.computeLuminance();
      final card = t.cardTheme.color!.computeLuminance();
      final fill = t.inputDecorationTheme.fillColor!.computeLuminance();
      expect(scaffold, lessThan(0.05), reason: '深色页面底不能是浅色');
      expect(card, greaterThan(scaffold), reason: '卡片要在页面之上"浮起"');
      expect(fill, greaterThan(scaffold), reason: '输入框填充要与页面有色差');
      // 纯黑底会放大白色光晕:深色底不许用纯黑
      expect(t.scaffoldBackgroundColor, isNot(const Color(0xFF000000)));
    });

    test('浅色:页面/卡片都在亮端,输入框靠描边区分层级', () {
      final t = AppTheme.lightTheme;
      expect(t.scaffoldBackgroundColor.computeLuminance(), greaterThan(0.7));
      expect(t.cardTheme.color!.computeLuminance(), greaterThan(0.7));
      // 浅色下输入框填充与页面同色(原有设计,靠描边区分),所以这里只要求
      // "不比页面更亮" —— 深色下必须更亮,浅色下不能更亮,两边都不能反
      expect(
        t.inputDecorationTheme.fillColor!.computeLuminance(),
        lessThanOrEqualTo(t.scaffoldBackgroundColor.computeLuminance()),
      );
      expect(t.inputDecorationTheme.enabledBorder, isNotNull);
    });

    test('两套主题的正文对比度都达到 WCAG AA(4.5:1)', () {
      for (final entry in {
        'light': AppTheme.lightTheme,
        'dark': AppTheme.darkTheme,
      }.entries) {
        final cs = entry.value.colorScheme;
        final bg = entry.value.scaffoldBackgroundColor;
        final card = entry.value.cardTheme.color!;
        expect(
          contrast(cs.onSurface, bg),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}:正文/页面底',
        );
        expect(
          contrast(cs.onSurface, card),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}:正文/卡片',
        );
        expect(
          contrast(cs.onSurfaceVariant, card),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}:次要文字/卡片',
        );
        expect(
          contrast(cs.onPrimary, cs.primary),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}:实心按钮文字/按钮底',
        );
      }
    });

    test('深色主色必须是亮色(浅色的近黑主色在深底上等于隐形)', () {
      final dark = AppTheme.darkTheme.colorScheme;
      expect(dark.primary.computeLuminance(), greaterThan(0.2));
      // 深色模式的实心按钮 = 亮底深字(M3 规则),不能是亮底白字
      expect(
        dark.onPrimary.computeLuminance(),
        lessThan(dark.primary.computeLuminance()),
      );
      final light = AppTheme.lightTheme.colorScheme;
      expect(
        light.onPrimary.computeLuminance(),
        greaterThan(light.primary.computeLuminance()),
      );
    });

    // ── 浅色模式看不清(v2.4 用户反馈"很多地方都看不清")────────────────
    // 用户在真机上看到:识图保存弹窗里的目录/词性标签"完全是泛白的"。
    // 根因是浅色下把次要文字压在带色阶的容器色上 —— 数值一算就现形:
    // onSurfaceVariant(#6C757D) 压 surfaceContainerHighest 只有 ~3.7:1,
    // 小字号下就是"看不清"。这组断言把**实际会用到的每一对**都量一遍。
    test('浅色:次要文字在容器色上必须达到 4.5:1(修"泛白看不清")', () {
      final t = AppTheme.lightTheme;
      final cs = t.colorScheme;
      final pairs = <String, List<Color>>{
        '次要文字/卡片': [cs.onSurfaceVariant, t.cardTheme.color!],
        '次要文字/页面': [cs.onSurfaceVariant, t.scaffoldBackgroundColor],
        // 复选/筛选 chip 的未选中底(材料中心、学习偏好、保存弹窗都在用)
        '次要文字/浅色容器': [cs.onSurfaceVariant, cs.surfaceContainerHighest],
        '次要文字/输入框底': [
          cs.onSurfaceVariant,
          t.inputDecorationTheme.fillColor!,
        ],
        '正文/浅色容器': [cs.onSurface, cs.surfaceContainerHighest],
        '实心按钮文字/主色': [cs.onPrimary, cs.primary],
      };
      final failures = <String>[];
      pairs.forEach((label, colors) {
        final ratio = contrast(colors[0], colors[1]);
        if (ratio < 4.5) failures.add('$label = ${ratio.toStringAsFixed(2)}:1');
      });
      expect(failures, isEmpty,
          reason: '浅色下这些组合低于 WCAG AA 4.5:1,真机上就是"看不清":\\n'
              '${failures.join('\\n')}');
    });

    test('浅色:描边/分隔线对底色的对比 ≥3:1(WCAG 非文字元素标准)', () {
      final t = AppTheme.lightTheme;
      final cs = t.colorScheme;
      final fill = t.inputDecorationTheme.fillColor!;
      final card = t.cardTheme.color!;
      final cases = <String, List<Color>>{
        'outline/卡片': [cs.outline, card],
        'outlineVariant/卡片': [cs.outlineVariant, card],
        '输入框描边/填充底': [
          t.inputDecorationTheme.enabledBorder!.borderSide.color,
          fill,
        ],
        'chip 描边/卡片': [
          t.chipTheme.side!.color,
          card,
        ],
      };
      final failures = <String>[];
      cases.forEach((label, colors) {
        final ratio = contrast(colors[0], colors[1]);
        if (ratio < 3.0) failures.add('$label = ${ratio.toStringAsFixed(2)}:1');
      });
      expect(failures, isEmpty,
          reason: '浅色下描边太淡会看不出边界(卡片/输入框/标签都会"泛白"):\\n'
              '${failures.join('\\n')}');
    });

    // ── 语义色(v2.5,U2)──────────────────────────────────────────
    // 写译批改的分数、材料源可用性、任务状态都用这三个色。以前直接用
    // `Colors.green/orange/red` —— 在白底上只有 2.5~3.1:1,真机上就是"看不清"。
    // 语义色必须**随明暗切换**(同一档不可能两头都对),这组把两档都量一遍。
    test('语义色:浅色档对白卡片、深色档对深卡片都达到 4.5:1', () {
      final lightCard = AppTheme.lightTheme.cardTheme.color!;
      final darkCard = AppTheme.darkTheme.cardTheme.color!;
      final cases = <String, List<Color>>{
        'success(浅)': [AppTheme.lightSuccess, lightCard],
        'warning(浅)': [AppTheme.lightWarning, lightCard],
        'danger(浅)': [AppTheme.lightDanger, lightCard],
        'success(深)': [AppTheme.darkSuccess, darkCard],
        'warning(深)': [AppTheme.darkWarning, darkCard],
        'danger(深)': [AppTheme.darkDanger, darkCard],
      };
      final failures = <String>[];
      cases.forEach((label, colors) {
        final ratio = contrast(colors[0], colors[1]);
        if (ratio < 4.5) failures.add('$label = ${ratio.toStringAsFixed(2)}:1');
      });
      expect(failures, isEmpty,
          reason: '语义色在真机上会变成看不清的字(且深浅两档都要达标):\\n'
              '${failures.join('\\n')}');
    });
  });

  // ── 全 App 取色入口(v2.5,U3 收敛)──────────────────────────────
  // 掌握度色与词条类型色以前在 5 个文件里各写一份 Colors.orange/blue/green;
  // 现在只允许走这两个入口。这里守住"同一个语义在明暗两套主题下都取到语义色"。
  group('语义取色入口', () {
    Future<Map<String, Color>> capture(
      WidgetTester tester, {
      required bool dark,
    }) async {
      final result = <String, Color>{};
      await tester.pumpWidget(
        // 直接用 Theme 而不是 MaterialApp:MaterialApp 会套一层 AnimatedTheme
        // 做 200ms 明暗过渡,而 brightness 在插值时取的是"过半才切",
        // 第一帧读到的可能还是旧亮度 —— 这里要的是确定的主题数据
        Theme(
          data: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          child: Builder(
            builder: (ctx) {
              result['mastery0'] = AppTheme.masteryColor(ctx, 0);
              result['mastery1'] = AppTheme.masteryColor(ctx, 1);
              result['mastery2'] = AppTheme.masteryColor(ctx, 2);
              result['word'] = AppTheme.wordTypeColor(ctx, 'word');
              result['phrase'] = AppTheme.wordTypeColor(ctx, 'phrase');
              result['sentence'] = AppTheme.wordTypeColor(ctx, 'sentence');
              result['success'] = AppTheme.successColor(ctx);
              result['warning'] = AppTheme.warningColor(ctx);
              result['danger'] = AppTheme.dangerColor(ctx);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('掌握度:新词=琥珀 / 学习中=主色 / 已掌握=成功', (tester) async {
      final light = await capture(tester, dark: false);
      expect(light['mastery0'], AppTheme.lightWarning);
      expect(light['mastery2'], AppTheme.lightSuccess);
      expect(light['mastery0'], isNot(light['mastery2']),
          reason: '新词与已掌握必须能一眼区分');
      final dark = await capture(tester, dark: true);
      expect(dark['mastery0'], AppTheme.darkWarning);
      expect(dark['mastery2'], AppTheme.darkSuccess);
    });

    testWidgets('词条类型:单词/短语/句子三种颜色互不相同,且随明暗切换', (tester) async {
      final light = await capture(tester, dark: false);
      expect(light['word'], isNot(light['phrase']));
      expect(light['phrase'], isNot(light['sentence']));
      final dark = await capture(tester, dark: true);
      expect(dark['phrase'], AppTheme.darkWarning);
      expect(dark['phrase'], isNot(light['phrase']),
          reason: '深色下必须换成深色档,否则对比度不够');
    });

    testWidgets('语义色在深色主题下取的是深色档(不是浅色档)', (tester) async {
      final dark = await capture(tester, dark: true);
      expect(dark['success'], AppTheme.darkSuccess);
      expect(dark['warning'], AppTheme.darkWarning);
      expect(dark['danger'], AppTheme.darkDanger);
    });
  });

  // ── 品牌色点亮(v2.5)──────────────────────────────────────────
  // AI 厂商头像用品牌色(不能换主题色,换了分不清是谁),但深色下
  // 百度蓝 #2932E1 对深卡片只有 2.07:1、通义紫 #6B4CE6 2.99:1,
  // 低于 WCAG 非文字元素的 3:1 —— readableOn 只提亮度让它达标。
  group('品牌色在深色下可见', () {
    const brandColors = <String, Color>{
      'baidu': Color(0xFF2932E1),
      'qwen': Color(0xFF6B4CE6),
      'deepseek': Color(0xFF4A6CF7),
      'doubao': Color(0xFF3D7A5C),
      'kimi': Color(0xFF8B5CF6),
    };

    testWidgets('深色:每个品牌色都对卡片底达到 3:1', (tester) async {
      late Map<String, Color> adjusted;
      await tester.pumpWidget(
        Theme(
          data: AppTheme.darkTheme,
          child: Builder(builder: (ctx) {
            adjusted = {
              for (final e in brandColors.entries)
                e.key: AppTheme.readableOn(ctx, e.value),
            };
            return const SizedBox.shrink();
          }),
        ),
      );
      final bg = AppTheme.darkTheme.cardTheme.color!;
      final failures = <String>[];
      adjusted.forEach((name, color) {
        final r = AppTheme.contrastRatio(color, bg);
        if (r < 3.0) {
          failures.add('$name = ${r.toStringAsFixed(2)}:1');
        }
      });
      expect(failures, isEmpty, reason: '深色下这些品牌色会发闷到看不出边界:\n${failures.join('\n')}');
    });

    testWidgets('深色:只提亮度不改色相(仍是同一个色系)', (tester) async {
      late Color changed;
      await tester.pumpWidget(
        Theme(
          data: AppTheme.darkTheme,
          child: Builder(builder: (ctx) {
            changed = AppTheme.readableOn(ctx, const Color(0xFF2932E1));
            return const SizedBox.shrink();
          }),
        ),
      );
      // 蓝分量应仍是最高的(没被提成灰色)
      expect(changed.b, greaterThan(changed.r));
      expect(changed.b, greaterThan(changed.g));
      expect(changed, isNot(const Color(0xFF2932E1)), reason: '原本不达标就必须被点亮');
    });

    testWidgets('浅色:原样返回(白底上品牌色本来就够)', (tester) async {
      late Color same;
      await tester.pumpWidget(
        Theme(
          data: AppTheme.lightTheme,
          child: Builder(builder: (ctx) {
            same = AppTheme.readableOn(ctx, const Color(0xFF2932E1));
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(same, const Color(0xFF2932E1));
    });
  });

  // ── 图表系列色(v2.5)──────────────────────────────────────────
  group('图表系列色', () {
    testWidgets('明暗两档都达标,且都还是"蓝"', (tester) async {
      late Color light;
      late Color dark;
      await tester.pumpWidget(
        Theme(
          data: AppTheme.lightTheme,
          child: Builder(builder: (ctx) {
            light = AppTheme.chartSeries(ctx);
            return const SizedBox.shrink();
          }),
        ),
      );
      await tester.pumpWidget(
        Theme(
          data: AppTheme.darkTheme,
          child: Builder(builder: (ctx) {
            dark = AppTheme.chartSeries(ctx);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(
        AppTheme.contrastRatio(light, AppTheme.lightTheme.cardTheme.color!),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        AppTheme.contrastRatio(dark, AppTheme.darkTheme.cardTheme.color!),
        greaterThanOrEqualTo(3.0),
      );
      // 保留蓝色调:蓝分量最高(以前写死 #4A90D9 就是蓝)
      for (final c in [light, dark]) {
        expect(c.b, greaterThan(c.r));
        expect(c.b, greaterThan(c.g));
      }
      expect(light, isNot(dark), reason: '两档必须不同,否则总有一档看不清');
    });
  });

  group('主题档位解析', () {
    test('三种档位互转且可往返', () {
      for (final id in AppConstants.themeModeOptions.keys) {
        final mode = AppTheme.themeModeOf(id);
        expect(AppTheme.themeModeId(mode), id, reason: '$id 往返必须一致');
      }
      expect(AppTheme.themeModeOf('light'), ThemeMode.light);
      expect(AppTheme.themeModeOf('dark'), ThemeMode.dark);
      expect(AppTheme.themeModeOf('system'), ThemeMode.system);
    });

    test('脏数据/缺失一律回退到跟随系统(宁可跟随系统,不能崩)', () {
      expect(AppTheme.themeModeOf(null), ThemeMode.system);
      expect(AppTheme.themeModeOf(''), ThemeMode.system);
      expect(AppTheme.themeModeOf('DARK'), ThemeMode.system);
      expect(AppTheme.themeModeOf('深色'), ThemeMode.system);
    });
  });

  group('硬编码浅色闸门', () {
    /// 允许保留的行(判断依据是"它在两种模式下都成立")
    ///
    /// 逐条给理由,不做整体豁免 —— 豁免范围一旦写宽,闸门就失效了。
    /// `Colors.black54` + `Colors.white` 不在这里:它们是"叠在图片上的角标"
    /// 专用(黑白在两种模式下都对),所以干脆没进 forbidden 列表。
    const allowed = <String>[
      // 全屏看图/预览时的黑色遮罩,与主题无关
      'barrierColor: Colors.black87',
      // 全屏预览里的"白底按钮 + 深色字":它压在黑色遮罩上,浅色主题下反而看不清
      'foregroundColor: Colors.black87',
    ];

    /// 一律禁止:这些颜色在浅色下正常、在深色下必然出问题
    ///
    /// 两类:
    /// 1. 灰阶的极端档位(grey[50..800] / black87):深色下变成亮块或黑字;
    /// 2. **淡彩色填充**(`Colors.blue[50]` 这种 ≤200 的档位):浅色下是"淡淡的
    ///    语义底色",深色下就是一整块近白的面板 —— 这类最容易漏,因为它看起来
    ///    "很语义"。正确写法是半透明色相(`Colors.blue.withAlpha(28)`):
    ///    浅色下观感几乎一致,深色下自动变成深底上的淡色调。
    final forbidden = RegExp(
      r'Colors\.(black87|black45|black38)'
      r'|Colors\.grey\[(50|100|200|300|400|500|600|700|800|850)\]'
      r'|Colors\.grey\.shade(50|100|200|300|400|500|600|700|800|850)'
      r'|Colors\.[a-z]+\[(50|100|200)\]'
      // v2.4:文字色别再自己调透明度 —— onSurface/onSurfaceVariant 打 47%~70%
      // 透明后,浅色下只有 3.0~3.9:1,正是用户说的"看不清/发灰"。
      // 次要文字直接用 onSurfaceVariant(主题已保证 ≥4.5:1)。
      r'|onSurface\.withAlpha\(|onSurfaceVariant\.withAlpha\(',
    );

    test('lib/ 下不再有浅色专用硬编码颜色(theme.dart 除外)', () {
      final offenders = <String>[];
      final root = Directory('lib');
      expect(root.existsSync(), isTrue, reason: '测试必须从项目根目录运行');

      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path.endsWith('config/theme.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!forbidden.hasMatch(line)) continue;
          if (allowed.any(line.contains)) continue;
          offenders.add('$path:${i + 1}  ${line.trim()}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: '这些颜色在深色模式下会变成亮块或看不清的字,'
            '请改成 theme.colorScheme.*(文字 onSurface/onSurfaceVariant、'
            '边框 outlineVariant、浅底填充 surfaceContainerHighest)。'
            '确有语义上必须写死颜色的,把理由写进本测试的 allowed 列表:\n'
            '${offenders.join('\n')}',
      );
    });
  });
}
