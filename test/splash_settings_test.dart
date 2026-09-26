import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/splash_settings.dart';

import 'dart:io';

/// 开屏/退出文案设置测试(v2.5,M3)。
///
/// 用户要求开屏文案**支持自定义**,默认「让语言,回归本质」;
/// 退出提示是两句话固定的字幕,且"一天只问一次"。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_splash_test');
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('开屏文案', () {
    test('默认文案就是用户定的那句', () {
      expect(SplashSettings.defaultTagline, '让语言,回归本质');
      expect(SplashSettings.tagline(), '让语言,回归本质');
    });

    test('自定义后立刻生效', () async {
      await SplashSettings.setTagline('每天一点点,也算数');
      expect(SplashSettings.tagline(), '每天一点点,也算数');
    });

    test('留空/纯空白 → 回到默认(不显示空文案)', () async {
      await SplashSettings.setTagline('先改一个');
      expect(SplashSettings.tagline(), '先改一个');
      await SplashSettings.setTagline('   ');
      expect(SplashSettings.tagline(), '让语言,回归本质');
      await SplashSettings.setTagline('改成别的');
      await SplashSettings.setTagline('');
      expect(SplashSettings.tagline(), '让语言,回归本质');
    });
  });

  group('退出文案与频率', () {
    test('两句话固定(产品语气的一部分,不给改)', () {
      expect(SplashSettings.exitStay, '辛苦啦,再学一会儿?');
      expect(SplashSettings.exitLeave, '累了~休息啦');
    });

    test('一天只问一次:标记后当天为 true', () async {
      expect(SplashSettings.exitPromptShownToday(), isFalse);
      await SplashSettings.markExitPromptShown();
      expect(SplashSettings.exitPromptShownToday(), isTrue);
    });
  });
}
