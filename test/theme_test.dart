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
      r'|Colors\.[a-z]+\[(50|100|200)\]',
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
