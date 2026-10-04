import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/widgets/material_cover.dart';

/// 材料封面(v2.10 重做)的纯函数闸门。
///
/// 只测"规则",不测像素:封面的视觉由 `MaterialCover` 里的 CustomPainter 画,
/// 但**取字、配色、类型/难度标签、尺寸降级**这四件事全是纯函数,
/// 也正是用户两次抱怨(「简陋」「意义不明」)的根因所在 —— 用测试锁死,
/// 免得以后又退回"标题前两个字"那种取法。
void main() {
  // ── WCAG 对比度工具:用来把"深色下可读"变成数字 ──────────────────────
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

  double contrastWithWhite(Color c) => 1.05 / (luminance(c) + 0.05);

  /// 拿一批真实感的标题当样本(中英混排 + 各种前缀)
  final samples = <String>[
    'GENMO: A GENeralist Model for Generalist Speech Recognition',
    'Notes on Nursing: What It Is, and What It Is Not',
    'The Great Gatsby',
    'On the Origin of Species',
    'AI 时代的外语学习',
    '《护眼灯的正确用法》',
    'A 电池管理系统的设计',
    '3 个方法让你记住单词',
    'How to Read a Book',
    'BBC News: Global markets rally',
    'GPT-5 Technical Report',
    '沉默的大多数',
    '第 3 章 边界与索引',
    '',
    '   ',
    '🎉🎉',
  ];

  group('配色稳定(同一篇永远同一张封面)', () {
    test('同一标题连续取 3 次,槽位完全一致', () {
      for (final s in samples) {
        final a = coverPaletteIndex(s);
        expect(coverPaletteIndex(s), a);
        expect(coverPaletteIndex(s), a);
        expect(a, inInclusiveRange(0, 9));
      }
    });

    test('空标题/纯空格不炸,落到 0 号槽', () {
      expect(coverPaletteIndex(''), 0);
      expect(coverPaletteIndex('    '), 0);
      expect(coverPalette('', Brightness.light).length, 2);
    });

    test('散得开:200 个标题至少命中 8 个槽位', () {
      final hit = <int>{};
      for (var i = 0; i < 200; i++) {
        hit.add(coverPaletteIndex('材料标题 #$i 关于语言学习的方法'));
      }
      expect(hit.length, greaterThanOrEqualTo(8));
    });

    test('同一标题 + 同一主题 → 两笔颜色完全相同', () {
      for (final s in samples) {
        expect(coverPalette(s, Brightness.light),
            coverPalette(s, Brightness.light));
        expect(coverPalette(s, Brightness.dark), coverPalette(s, Brightness.dark));
      }
    });

    test('深色主题更暗(两笔都压暗),但槽位不变', () {
      for (final s in samples) {
        final light = coverPalette(s, Brightness.light);
        final dark = coverPalette(s, Brightness.dark);
        expect(luminance(dark[0]), lessThan(luminance(light[0])));
        expect(luminance(dark[1]), lessThan(luminance(light[1])));
        expect(coverPaletteIndex(s), coverPaletteIndex(s));
      }
    });

    test('每套配色都够深:白字对比度浅色 ≥ 5.5:1、深色 ≥ 7:1(亮面)', () {
      // 这是"深色模式不出现深底深字"的硬闸门。当前实测最低:
      // 浅色主题 亮面 5.95:1 / 暗面 11.11:1;深色主题 亮面 7.37:1 / 暗面 13.1:1。
      var minLightFace = 99.0;
      var minLightDeep = 99.0;
      var minDarkFace = 99.0;
      var minDarkDeep = 99.0;
      for (var i = 0; i < 200; i++) {
        final light = coverPalette('样本标题 $i', Brightness.light);
        final dark = coverPalette('样本标题 $i', Brightness.dark);
        minLightFace = math.min(minLightFace, contrastWithWhite(light[0]));
        minLightDeep = math.min(minLightDeep, contrastWithWhite(light[1]));
        minDarkFace = math.min(minDarkFace, contrastWithWhite(dark[0]));
        minDarkDeep = math.min(minDarkDeep, contrastWithWhite(dark[1]));
      }
      expect(minLightFace, greaterThanOrEqualTo(5.5)); // 实测 5.95
      expect(minLightDeep, greaterThanOrEqualTo(10.0)); // 实测 11.11
      expect(minDarkFace, greaterThanOrEqualTo(7.0)); // 实测 7.37
      expect(minDarkDeep, greaterThanOrEqualTo(12.0)); // 实测 13.10
    });

    test('难度胶囊四档配色叠白字也够对比度', () {
      for (final lv in ['Lv1', 'Lv5', 'Lv8', 'Lv10', 'Lv99']) {
        expect(contrastWithWhite(coverLevelTint(lv)), greaterThanOrEqualTo(4.5),
            reason: '$lv 的胶囊底色太浅,白字读不出来');
      }
    });
  });

  group('类型标签(种类图标 + 中文名)', () {
    test('五种种类各有各的图标,未知/文章走同一个兜底', () {
      final icons = {
        for (final k in ['book', 'paper', 'news', 'podcast', 'wiki'])
          k: coverKindIcon(k),
      };
      expect(icons.values.toSet().length, 5);
      expect(coverKindIcon('article'), Icons.article_outlined);
      expect(coverKindIcon('unknown_kind'), Icons.article_outlined);
      expect(coverKindIcon(''), Icons.article_outlined);
    });

    test('中文名:完整档与短名档都覆盖全部种类', () {
      const kinds = ['book', 'paper', 'news', 'podcast', 'wiki', 'article'];
      for (final k in kinds) {
        expect(coverKindLabel(k).runes.length, greaterThanOrEqualTo(2));
        expect(coverKindLabel(k, compact: true).runes.length,
            inInclusiveRange(1, 2),
            reason: '小卡徽标只能放 1~2 个字,否则会把封面撑满');
      }
      expect(coverKindLabel('book'), '原版书');
      expect(coverKindLabel('paper'), '论文');
      expect(coverKindLabel('news', compact: true), '外刊');
      expect(coverKindLabel('nonsense'), '文章');
      expect(coverKindLabel('nonsense', compact: true), '文章');
    });

    test('尺寸分档:52 只留图标,88 图标 + 短名,186 图标 + 全名', () {
      expect(coverBadgeIconOnly(52), isTrue);
      expect(coverBadgeIconOnly(64), isFalse);
      expect(coverBadgeIconOnly(78), isFalse);
      expect(coverBadgeIconOnly(88), isFalse);
      expect(coverBadgeIconOnly(186), isFalse);

      expect(coverBadgeCompact(52), isTrue);
      expect(coverBadgeCompact(88), isTrue);
      expect(coverBadgeCompact(96), isFalse);
      expect(coverBadgeCompact(186), isFalse);
    });
  });

  group('难度胶囊', () {
    test('文案清洗:null / 空串 / 纯空格都视为没有', () {
      expect(coverLevelText(null), '');
      expect(coverLevelText(''), '');
      expect(coverLevelText('   '), '');
      expect(coverLevelText('  Lv7 '), 'Lv7');
    });

    test('52 的小缩略图藏掉胶囊,56 起才画', () {
      expect(coverShowLevelBadge('Lv7', 52), isFalse);
      expect(coverShowLevelBadge('Lv7', 56), isTrue);
      expect(coverShowLevelBadge('Lv7', 78), isTrue);
      expect(coverShowLevelBadge('Lv7', 186), isTrue);
      expect(coverShowLevelBadge(null, 186), isFalse);
      expect(coverShowLevelBadge('  ', 186), isFalse);
    });

    test('同一难度同色,四档两两不同', () {
      expect(coverLevelTint('Lv1'), coverLevelTint('Lv3'));
      expect(coverLevelTint('Lv4'), coverLevelTint('Lv6'));
      expect(coverLevelTint('Lv7'), coverLevelTint('Lv8'));
      expect(coverLevelTint('Lv9'), coverLevelTint('Lv10'));
      final bands = {
        coverLevelTint('Lv2'),
        coverLevelTint('Lv5'),
        coverLevelTint('Lv8'),
        coverLevelTint('Lv10'),
      };
      expect(bands.length, 4);
    });

    test('认不出的标签给中性色,绝不把 A2 当成 Lv2', () {
      final neutral = coverLevelTint('');
      expect(coverLevelTint('A2'), neutral);
      expect(coverLevelTint('B1'), neutral);
      expect(coverLevelTint('未知'), neutral);
      expect(coverLevelTint('Lv3'), isNot(neutral));
    });
  });

  group('小卡取字(第一个有意义的词)', () {
    test('英文:第一个长度 ≥4 的词,首字母大写', () {
      // 用户截图里的对照物:旧规则会给「GG」(取首字母),现在是完整的专名
      expect(
        coverMonogram('GENMO: A GENeralist Model for Generalist Speech',
            small: true),
        'GENMO',
      );
      expect(coverMonogram('Notes on Nursing', small: true), 'Notes');
      expect(coverMonogram('nursing notes', small: true), 'Nursing');
    });

    test('开头冠词/介词没有信息量,必须跳过', () {
      expect(coverMonogram('The Great Gatsby', small: true), 'Great');
      expect(coverMonogram('On the Origin of Species', small: true), 'Origin');
      expect(coverMonogram('A Study in Scarlet', small: true), 'Study');
    });

    test('中文:取前 3 个字,不含书名号与标点', () {
      expect(coverMonogram('《护眼灯的正确用法》', small: true), '护眼灯');
      expect(coverMonogram('护眼灯的正确用法', small: true), '护眼灯');
      // 「A电」这个 bug 的回归测试:冠词 A 必须被丢掉,取的是完整的词
      expect(coverMonogram('A 电池管理系统的设计', small: true), '电池管');
    });

    test('中文:虚词收尾要掐掉,不能像写了一半', () {
      expect(coverMonogram('沉默的大多数', small: true), '沉默');
      expect(coverMonogram('和平与发展的时代', small: true), '和平');
    });

    test('中文:结构字开头要往后找真正有信息量的字', () {
      // 这是自查时发现并修掉的真 bug:旧写法会给「第」,又变成"意义不明"
      expect(coverMonogram('第 3 章 边界与索引', small: true), '边界');
      expect(coverMonogram('第 3 章 边界与索引', small: false), '边界与索');
      // 只有一个字的中文标题仍要给得出字
      expect(coverMonogram('爱', small: true), '爱');
    });

    test('中文:掐结构字必须掐得住手,不能把词掐坏', () {
      // 这些是"多掐一个字就更难懂"的回归样本:「个人成长」不能变成「人成长」
      expect(coverMonogram('个人成长', small: true), '个人成');
      expect(coverMonogram('回忆录', small: true), '回忆录');
      expect(coverMonogram('本能', small: true), '本能');
      expect(coverMonogram('章鱼的故事', small: true), '章鱼');
    });

    test('全长不到 4 个字母时退到第一个实词', () {
      expect(coverMonogram('On War', small: true), 'War');
      expect(coverMonogram('AI 时代', small: true), 'AI');
    });

    test('全大写专名原样保留', () {
      expect(coverMonogram('GENMO Model', small: true), 'GENMO');
      expect(coverMonogram('DeepMind Papers', small: true), 'DeepMind');
    });

    test('数字/符号开头但后面有中文时,取后面的中文', () {
      // 已知不完美:「个方法」里的「个」是量词。量词与词头无法靠规则区分
      // (「个人」里的「个」就是词的一部分),宁可留着也不冒掐坏的风险。
      expect(coverMonogram('3 个方法让你记住单词', small: true), '个方法');
      expect(coverMonogram('GPT-5 Technical Report', small: true), 'GPT-5');
    });

    test('空标题/纯符号绝不返回空串(否则封面是一块什么都没有的色块)', () {
      expect(coverMonogram('', small: true), '·');
      expect(coverMonogram('   ', small: true), '·');
      expect(coverMonogram('🎉🎉', small: true), '·');
      expect(coverMonogram('《》', small: true), '·');
    });

    test('超长单词:先换"放得下的词",实在没有才截断', () {
      // 「Superc」这种半截字本身就是"意义不明",所以宁可换词
      expect(
        coverMonogram('Supercalifragilisticexpialidocious Song', small: true),
        'Song',
      );
      // 只有一个超长词时只能截断(已知局限,报告里写明)
      final solo = coverMonogram('Revolution', small: true);
      expect(solo.runes.length, lessThanOrEqualTo(8));
      expect(solo, 'Revoluti');
    });

    test('任何标题下,小卡单字都不超过 8 个字符', () {
      for (final s in samples) {
        final mono = coverMonogram(s, small: true);
        expect(mono, isNotEmpty);
        expect(mono.runes.length, lessThanOrEqualTo(8), reason: '「$s」取字太长');
      }
    });

    test('大卡兜底档放宽到 4 个汉字', () {
      final mono = coverMonogram('护眼灯的正确用法', small: false);
      expect(mono.runes.length, lessThanOrEqualTo(4));
      expect(mono.startsWith('护眼灯'), isTrue);
    });
  });

  group('大卡取字(标题前 14~18 字)', () {
    test('字数预算落在 14~18 之间', () {
      for (final h in [120.0, 140.0, 168.0, 186.0, 240.0, 400.0]) {
        expect(coverTitleCharBudget(h), inInclusiveRange(14, 18));
      }
      expect(coverTitleCharBudget(186), 18);
      expect(coverTitleCharBudget(140), 16);
      expect(coverTitleCharBudget(120), 14);
    });

    test('行数:高的卡给 3 行,矮的给 2 行', () {
      expect(coverTitleMaxLines(186), 3);
      expect(coverTitleMaxLines(150), 3);
      expect(coverTitleMaxLines(140), 2);
    });

    test('截断一定带省略号,且总长不超预算 +1', () {
      for (final s in samples) {
        final t = coverTitleSnippet(s, maxChars: 18);
        expect(t.runes.length, lessThanOrEqualTo(19), reason: '「$s」超预算');
      }
      expect(coverTitleSnippet('GENMO: A GENeralist Model for Generalist Speech',
              maxChars: 18)
          .endsWith('…'), isTrue);
    });

    test('短标题原样返回,不加省略号', () {
      expect(coverTitleSnippet('On War', maxChars: 18), 'On War');
      expect(coverTitleSnippet('《护眼灯》', maxChars: 18), '护眼灯');
      expect(coverTitleSnippet('', maxChars: 18), '');
      expect(coverTitleSnippet('   ', maxChars: 18), '');
    });

    test('英文标题不在单词中间切开(退到词边界)', () {
      final t = coverTitleSnippet('Generalist Model for Speech', maxChars: 14);
      expect(t, 'Generalist…');
      final body = t.substring(0, t.length - 1);
      expect('Generalist Model for Speech'.startsWith(body), isTrue);
      expect('Generalist Model for Speech'.substring(body.length),
          startsWith(' '));
    });

    test('Markdown 残留不会出现在封面上(方括号/星号/井号)', () {
      expect(coverTitleSnippet('**Bold** Title', maxChars: 18), 'Bold Title');
      expect(coverTitleSnippet('## 标题 #标签', maxChars: 18), '标题 标签');
      expect(coverTitleSnippet('1. 列表项标题', maxChars: 18), '列表项标题');
    });

    test('任何标题下,大卡文字都不含 Markdown 星号(界面文案闸门)', () {
      for (final s in samples) {
        expect(coverTitleSnippet(s, maxChars: 18).contains('**'), isFalse);
      }
    });
  });

  group('尺寸约束与降级', () {
    test('大卡阈值:高 ≥ 120 走标题全文', () {
      expect(coverIsLarge(186), isTrue);
      expect(coverIsLarge(120), isTrue);
      expect(coverIsLarge(119), isFalse);
      expect(coverIsLarge(92), isFalse);
      expect(coverIsLarge(52), isFalse);
    });

    test('大卡右下角那行种类小字:窄卡/有真图/小卡都不画', () {
      expect(coverShowKindText(360, 186, hasImage: false), isTrue);
      expect(coverShowKindText(360, 186, hasImage: true), isFalse);
      expect(coverShowKindText(88, 88, hasImage: false), isFalse);
      expect(coverShowKindText(140, 186, hasImage: false), isFalse);
    });

    test('字号:随尺寸放大但有上限,绝不无限膨胀', () {
      expect(coverTitleFontSize(1000), 21);
      expect(coverTitleFontSize(186), 21);
      expect(coverTitleFontSize(120), 15);
      expect(coverMonogramFontSize(1000), 26);
      expect(coverMonogramFontSize(88), closeTo(24.64, 0.01));
      expect(coverMonogramFontSize(78), closeTo(21.84, 0.01));
      expect(coverMonogramFontSize(52), closeTo(14.56, 0.01));
      expect(coverMonogramFontSize(10), 12); // 下限兜底
      expect(coverMonogramFontSize(186), greaterThan(coverMonogramFontSize(88)));
    });

    test('没有真图时(含空白串/非 http)一律用程序化封面', () {
      expect(coverHasImage(null), isFalse);
      expect(coverHasImage(''), isFalse);
      expect(coverHasImage('   '), isFalse);
      expect(coverHasImage('/data/user/0/readflow/cache/a.jpg'), isFalse);
      expect(coverHasImage('file:///tmp/a.jpg'), isFalse);
      expect(
          coverHasImage(
              'https://www.gutenberg.org/cache/epub/11/pg11.cover.medium.jpg'),
          isTrue);
      expect(coverHasImage('http://example.com/a.jpg'), isTrue);
    });
  });

  // 真实尺寸排版闸门:纯函数只能保证"输入 → 取字/配色"是对的,
  // 但"文字溢不溢出、徽标重不重叠"只有在真尺寸下排一遍才知道。
  // 这里的 5 个尺寸就是调用方实际在用的(52/76/78/88 小卡 + 186 大卡)。
  group('真实尺寸排版闸门(文字不溢出、文字块不重叠)', () {
    Future<void> check(
      WidgetTester tester, {
      required double w,
      required double h,
      required String title,
      required String kind,
      String? level,
      double radius = 10,
      Brightness brightness = Brightness.dark,
      double textScale = 1.0,
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Center(
              child: SizedBox(
                width: w,
                height: h,
                child: MaterialCover(
                  seed: title,
                  kind: kind,
                  levelLabel: level,
                  radius: radius,
                  width: w,
                  height: h,
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$w x $h 抛异常');

      final cover = tester.getRect(find.byType(MaterialCover));
      expect(cover.width, closeTo(w, 0.01));
      expect(cover.height, closeTo(h, 0.01));

      final texts = find.byType(Text);
      final rects = <Rect>[];
      final elements = texts.evaluate().toList();
      for (var i = 0; i < elements.length; i++) {
        final r = tester.getRect(texts.at(i));
        final t = (elements[i].widget as Text).data;
        rects.add(r);
        expect(cover.inflate(-0.5).contains(r.topLeft), isTrue,
            reason: '$w x $h 「$t」左上溢出 $r not in $cover');
        expect(
            cover
                .inflate(-0.5)
                .contains(r.bottomRight - const Offset(0.01, 0.01)),
            isTrue,
            reason: '$w x $h 「$t」右下溢出 $r not in $cover');
        expect(r.width, greaterThan(0));
        expect(r.height, greaterThan(0));
      }
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          final overlap = rects[i].intersect(rects[j]);
          expect(overlap.isEmpty || overlap.width < 0.5 || overlap.height < 0.5,
              isTrue,
              reason: '$w x $h 文字块重叠:${rects[i]} vs ${rects[j]}');
        }
      }
      expect(rects, isNotEmpty, reason: '$w x $h 一个文字块都没画出来');
    }

    testWidgets('78x78', (t) async {
      await check(t,
          w: 78, h: 78, title: 'GENMO: A GENeralist Model', kind: 'book', level: 'Lv7');
    });
    testWidgets('92x92', (t) async {
      await check(t,
          w: 92,
          h: 92,
          title: 'Notes on Nursing: What It Is',
          kind: 'news',
          level: 'Lv9',
          brightness: Brightness.light);
    });
    testWidgets('88x88 中文', (t) async {
      await check(t,
          w: 88, h: 88, title: '《护眼灯的正确用法》', kind: 'wiki', level: 'Lv3');
    });
    testWidgets('52x52', (t) async {
      await check(t, w: 52, h: 52, title: 'A 电池管理系统的设计', kind: 'article');
    });
    testWidgets('186 高 x 360 宽(大卡)', (t) async {
      await check(t,
          w: 360,
          h: 186,
          title: 'GENMO: A GENeralist Model for Generalist Speech Recognition',
          kind: 'paper',
          level: 'Lv7',
          radius: 0);
    });
    testWidgets('186 高 x 200 宽(窄大卡)', (t) async {
      await check(t,
          w: 200,
          h: 186,
          title: '第 3 章 边界与索引:一个很长的中文标题在这里换行',
          kind: 'book',
          level: 'Lv10');
    });
    testWidgets('186 高 + 系统字号 2.0(极端放大)', (t) async {
      await check(t,
          w: 360,
          h: 186,
          title: 'On the Origin of Species by Means of Natural Selection',
          kind: 'book',
          level: 'Lv7',
          radius: 0,
          textScale: 2.0);
    });
    testWidgets('78x78 + 系统字号 2.0', (t) async {
      await check(t,
          w: 78,
          h: 78,
          title: 'On the Origin of Species',
          kind: 'podcast',
          level: 'Lv5',
          textScale: 2.0);
    });
  });
}
