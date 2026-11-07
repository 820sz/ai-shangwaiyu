// 阅读器 C 方案(2026-11-06):纸张调色板 / C 字阶 / 纸张持久化 —— 纯函数 + Hive 单测。
//
// 「三张纸都要可读」是用户拍板的验收标准,这里用 WCAG 对比度把它变成可核对的
// 数字:正文、译文次要色、砖红强调、选中态,逐项过 AA(≥4.5;正文要求更高)。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/reader_settings.dart';
import 'package:readflow/widgets/reader_paper.dart';
import 'package:readflow/widgets/reader_progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('C 字阶:6 档(标题/栏目标签/署名/首段/正文/译文)', () {
    test('默认设置 = 正文 18 / 标题 28 / 首段 20 / 译文 13.5 / 标签 9.5 / 署名 10.5',
        () {
      final t = ReaderType.fromSettings();
      expect(t.body, 18);
      expect(t.lineHeight, 1.8);
      expect(t.title, closeTo(28, 0.01));
      expect(t.lead, closeTo(20, 0.01));
      expect(t.translation, closeTo(13.5, 0.01));
      expect(t.kicker, closeTo(9.5, 0.01));
      expect(t.signature, closeTo(10.5, 0.01));
      expect(ReaderType.titleHeight, 1.1);
      expect(ReaderType.leadHeight, 1.82);
      expect(ReaderType.translationHeight, 1.8);
      expect(ReaderType.kickerSpacing, 1.6);
      expect(ReaderType.titleSpacing, -0.8);
    });
  });

  group('三张纸的对比度(WCAG AA)', () {
    for (final paper in ReaderPaper.values) {
      test('${paper.label}:正文 / 译文 / 强调 / 选中态都达标', () {
        final p = paletteOf(paper);
        // 正文:近黑/纸白,远高于 AA(设计要求"读得下去")
        expect(contrastRatio(p.ink, p.page), greaterThan(7),
            reason: '${paper.label} 正文字色在纸底上太浅');
        // 译文用次要色,小字必须 ≥4.5
        expect(contrastRatio(p.inkSoft, p.page), greaterThanOrEqualTo(4.5),
            reason: '${paper.label} 译文色对比度不足');
        // 砖红强调(进度/下划线/主行动)在纸底上 ≥4.5
        expect(contrastRatio(p.accent, p.page), greaterThanOrEqualTo(4.5),
            reason: '${paper.label} 砖红在纸底上对比度不足');
        // 强调色放在译文块底 / 选中底上也要看得清
        expect(contrastRatio(p.accent, p.transBg), greaterThanOrEqualTo(4.0),
            reason: '${paper.label} 译文块上的砖红太弱');
        expect(
            contrastRatio(p.accent, p.selectedBg), greaterThanOrEqualTo(4.0),
            reason: '${paper.label} 选中态上的砖红太弱');
        // 极淡色(元信息)是装饰层,只要求 ≥2.5,不能和正文抢
        expect(contrastRatio(p.inkFaint, p.page), greaterThan(2.5));
        // 主按钮(ink 底)上的字:浅纸白字、墨夜深字
        expect(contrastRatio(p.onInk, p.ink), greaterThanOrEqualTo(7));
      });
    }

    test('竖轨「未填充」三纸都能看见,且与「已填充砖红」可区分(第三轮 QA)', () {
      for (final paper in ReaderPaper.values) {
        final p = paletteOf(paper);
        final track = ReaderProgressRail.trackColor(p);
        // 0% 时未填充轨道对纸底:比 hairline(1.23)深一档,但不抢眼
        final trackOnPage = contrastRatio(track, p.page);
        expect(trackOnPage, greaterThanOrEqualTo(1.35),
            reason: '${paper.label} 未填充轨道太淡(0% 时看不清进度轨)');
        expect(trackOnPage, lessThanOrEqualTo(2.6),
            reason: '${paper.label} 未填充轨道太抢眼(会和已填充砖红打架)');
        // 已填充 vs 未填充:必须一眼能分出"读到哪"
        expect(contrastRatio(p.accent, track), greaterThanOrEqualTo(2.5),
            reason: '${paper.label} 已填充砖红与未填充轨道区分度不足');
        // 也不能退化成和 hairline 几乎一样(等价于没改)
        expect(track, isNot(p.hairline));
      }
    });

    test('墨夜纸的砖红是提亮版(原色 #B23A2C 在深纸上只有 2.9:1)',
        () {
      final night = paletteOf(ReaderPaper.night);
      final original = const Color(0xFFB23A2C);
      expect(night.accent, isNot(original));
      expect(contrastRatio(original, night.page), lessThan(3));
      expect(contrastRatio(night.accent, night.page), greaterThanOrEqualTo(4.5));
    });
  });

  group('纸张三色:持久化(复用 reader_settings 的 settings Hive box)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rf_reader_c_paper');
      Hive.init(tmp.path);
      await Hive.openBox(AppConstants.hiveBoxSettings);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('默认纸白(C 方案基底)', () {
      expect(ReaderSettings.paper(), ReaderPaper.white);
      expect(paletteOf(ReaderSettings.paper()).page, const Color(0xFFEEEFEA));
    });

    test('切到米黄 / 墨夜后能读回来', () async {
      await ReaderSettings.setPaper(ReaderPaper.beige);
      expect(ReaderSettings.paper(), ReaderPaper.beige);
      expect(paletteOf(ReaderPaper.beige).page, const Color(0xFFF4EFE3));
      await ReaderSettings.setPaper(ReaderPaper.night);
      expect(ReaderSettings.paper(), ReaderPaper.night);
      expect(paletteOf(ReaderPaper.night).page, const Color(0xFF16181C));
    });

    test('Hive 里是脏数据 → 回默认,不炸', () async {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(ReaderSettings.keyReaderPaper, '不是一张纸');
      expect(ReaderSettings.paper(), ReaderPaper.white);
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(ReaderSettings.keyReaderPaper, 99);
      expect(ReaderSettings.paper(), ReaderPaper.white);
    });
  });
}
