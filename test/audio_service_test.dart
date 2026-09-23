import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/audio_service.dart';

/// 听力功能的纯函数回归。
///
/// 播放本身依赖原生插件(测试环境没有音频输出),所以这里覆盖的是
/// **能出错又会直接影响体验的部分**:时长显示、倍速循环、地址判断。
void main() {
  group('时长显示', () {
    test('分:秒补零,超过一小时给 h:mm:ss', () {
      expect(AudioService.formatDuration(Duration.zero), '00:00');
      expect(AudioService.formatDuration(const Duration(seconds: 5)), '00:05');
      expect(AudioService.formatDuration(const Duration(minutes: 3, seconds: 7)),
          '03:07');
      expect(
        AudioService.formatDuration(
            const Duration(hours: 1, minutes: 2, seconds: 9)),
        '1:02:09',
      );
    });

    test('未知/负数时长给占位符,不显示 00:00 误导用户', () {
      expect(AudioService.formatDuration(null), '--:--');
      expect(AudioService.formatDuration(const Duration(seconds: -5)), '--:--');
    });
  });

  group('倍速循环', () {
    test('四个档位按顺序循环回 0.75', () {
      expect(AudioService.nextSpeed(0.75), 1.0);
      expect(AudioService.nextSpeed(1.0), 1.25);
      expect(AudioService.nextSpeed(1.25), 1.5);
      expect(AudioService.nextSpeed(1.5), 0.75);
    });

    test('非法值回落到 1.0(而不是崩或跳到奇怪档位)', () {
      expect(AudioService.nextSpeed(3.0), 1.0);
      expect(AudioService.nextSpeed(0), 1.0);
    });

    test('档位表包含听力最需要的慢速档', () {
      expect(AudioService.speedOptions, contains(0.75));
      expect(AudioService.speedOptions.first, lessThan(1.0));
    });
  });

  group('音频地址判断', () {
    test('常见音频后缀与播客域名算可播放', () {
      expect(AudioService.looksPlayable('https://x.com/a.mp3'), isTrue);
      expect(AudioService.looksPlayable('https://x.com/a.m4a'), isTrue);
      expect(AudioService.looksPlayable('http://x.com/ep.opus'), isTrue);
      expect(
        AudioService.looksPlayable('https://feeds.feedburner.com/TEDTalks_audio'),
        isTrue,
      );
    });

    test('非 http、空值、纯网页地址不算音频', () {
      expect(AudioService.looksPlayable(null), isFalse);
      expect(AudioService.looksPlayable(''), isFalse);
      expect(AudioService.looksPlayable('file:///tmp/a.mp3'), isFalse);
      expect(AudioService.looksPlayable('https://example.com/article'), isFalse);
    });

    test('大小写与首尾空白不影响判断', () {
      expect(AudioService.looksPlayable('  HTTPS://X.COM/A.MP3  '), isTrue);
    });
  });
}
