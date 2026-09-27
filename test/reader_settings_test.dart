import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/reader_settings.dart';

/// 阅读器显示设置测试(v2.5,U2)。
///
/// 用户本轮要求"阅读器的字号行距"要能调(长时间读英文的场景);
/// 这里守住三件事:①默认值稳定 ②越界/脏数据被夹到合法档位(而不是崩或乱显示)
/// ③存进去能读回来(两个阅读器共用同一份偏好)。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_reader_test');
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('默认值', () {
    test('没设置过 → 100% 字号 + 标准行距(现状观感不变)', () {
      expect(ReaderSettings.fontScale(), ReaderSettings.defaultFontScale);
      expect(ReaderSettings.lineHeight(), ReaderSettings.defaultLineHeight);
      expect(ReaderSettings.baseFontSize, 16);
    });

    test('档位是有限集合:字号 5 档、行距 3 档且带名字', () {
      expect(ReaderSettings.fontScales.length, 5);
      expect(ReaderSettings.lineHeights.length, 3);
      expect(ReaderSettings.lineHeightLabels.length,
          ReaderSettings.lineHeights.length);
      expect(ReaderSettings.lineHeightLabels, ['紧凑', '标准', '宽松']);
      expect(ReaderSettings.lineHeights.contains(ReaderSettings.defaultLineHeight),
          isTrue);
    });
  });

  group('保存与读取', () {
    test('字号存进去能读回来', () async {
      await ReaderSettings.setFontScale(1.3);
      expect(ReaderSettings.fontScale(), 1.3);
    });

    test('行距存进去能读回来', () async {
      await ReaderSettings.setLineHeight(2.0);
      expect(ReaderSettings.lineHeight(), 2.0);
    });

    test('两个设置互不干扰(分别落在不同的 key 上)', () async {
      await ReaderSettings.setFontScale(1.5);
      await ReaderSettings.setLineHeight(1.5);
      expect(ReaderSettings.fontScale(), 1.5);
      expect(ReaderSettings.lineHeight(), 1.5);
    });
  });

  group('脏数据与越界', () {
    test('非法档位被夹到最近的合法档位', () async {
      await ReaderSettings.setFontScale(9);
      expect(ReaderSettings.fontScale(), 1.5);
      await ReaderSettings.setFontScale(0.01);
      expect(ReaderSettings.fontScale(), 0.85);
      await ReaderSettings.setLineHeight(5);
      expect(ReaderSettings.lineHeight(), 2.0);
    });

    test('中间值就近取档(1.2 → 1.15,不是 1.3)', () async {
      await ReaderSettings.setFontScale(1.2);
      expect(ReaderSettings.fontScale(), 1.15);
    });

    test('Hive 里是字符串/垃圾 → 回默认,不炸', () async {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyReaderFontScale, '大一点');
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyReaderLineHeight, <String>['x']);
      expect(ReaderSettings.fontScale(), ReaderSettings.defaultFontScale);
      expect(ReaderSettings.lineHeight(), ReaderSettings.defaultLineHeight);
    });

    test('数字字符串也能读(旧数据/手改配置的容错)', () async {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyReaderFontScale, '1.15');
      expect(ReaderSettings.fontScale(), 1.15);
    });
  });

  group('显示名与下标', () {
    test('字号显示成百分比', () {
      expect(ReaderSettings.scaleLabel(1.0), '100%');
      expect(ReaderSettings.scaleLabel(0.85), '85%');
      expect(ReaderSettings.scaleLabel(1.15), '115%');
    });

    test('行距名字与档位对齐', () {
      expect(ReaderSettings.lineHeightLabel(1.5), '紧凑');
      expect(ReaderSettings.lineHeightLabel(1.7), '标准');
      expect(ReaderSettings.lineHeightLabel(2.0), '宽松');
    });

    test('下标取的是合法档位的位置(段控/上下档要用)', () {
      expect(ReaderSettings.scaleIndex(1.0), 1);
      expect(ReaderSettings.scaleIndex(1.15), 2);
      expect(ReaderSettings.lineHeightIndex(2.0), 2);
    });
  });
}
