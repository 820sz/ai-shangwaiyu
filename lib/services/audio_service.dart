import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 音频播放服务(v2.2 听力)。
///
/// 为什么用单例 + 极薄包装:
/// 1. 听力材料与复习卡的发音不能同时出声(两个播放器会互相打架),
///    所以全 App 只留一个播放实例;
/// 2. 只暴露本项目真正要用的能力(载入/播放/暂停/跳转/倍速),
///    第三方插件的 API 变化不会蔓延到 UI 层;
/// 3. 网络音频要能被 **暂停/续播** 而不是每次重新下载 —— just_audio 自带缓冲。
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  AudioPlayer? _player;
  String? _currentUrl;
  bool _sessionConfigured = false;

  AudioPlayer get _p => _player ??= AudioPlayer();

  /// 当前载入的音频地址(null = 没载入)
  String? get currentUrl => _currentUrl;

  bool get isLoaded => _currentUrl != null;

  Stream<Duration> get positionStream => _p.positionStream;
  Stream<Duration?> get durationStream => _p.durationStream;
  Stream<PlayerState> get stateStream => _p.playerStateStream;

  /// 一次性的音频会话配置:按"语音内容"处理(而不是音乐),
  /// 这样接电话/其它 App 播放时会正确让路
  Future<void> _ensureSession() async {
    if (_sessionConfigured) return;
    _sessionConfigured = true;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    } catch (e) {
      // 某些设备/模拟器没有音频会话服务:不影响播放,记日志即可
      debugPrint('ReadFlow 音频会话配置失败(忽略): $e');
    }
  }

  /// 载入音频;重复载入同一个地址会直接复用(避免从头下载)
  Future<void> load(String url) async {
    if (url.trim().isEmpty) throw Exception('音频地址为空');
    if (!looksPlayable(url)) throw Exception('这个地址看起来不是音频:${_short(url)}');
    if (_currentUrl == url) return;
    await _ensureSession();
    try {
      await _p.setUrl(url.trim());
      _currentUrl = url.trim();
    } catch (e) {
      _currentUrl = null;
      throw Exception('音频打不开:${_friendly(e)}');
    }
  }

  Future<void> play() async {
    if (!isLoaded) throw Exception('还没有载入音频');
    try {
      await _p.play();
    } catch (e) {
      throw Exception('播放失败:${_friendly(e)}');
    }
  }

  Future<void> pause() => _p.pause();

  Future<void> seek(Duration position) => _p.seek(position);

  /// 前进/后退 [seconds] 秒(听不清时回退重听是高频操作)
  Future<void> skip({required int seconds}) async {
    final now = _p.position;
    final target = now + Duration(seconds: seconds);
    await _p.seek(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> setSpeed(double speed) => _p.setSpeed(speed);

  double get speed => _p.speed;

  Future<void> disposePlayer() async {
    await _player?.dispose();
    _player = null;
    _currentUrl = null;
  }

  // ── 纯函数(可单测) ──

  /// 倍速档位:听力练习常用 0.75(听不清)/1.0/1.25/1.5
  static const List<double> speedOptions = [0.75, 1.0, 1.25, 1.5];

  /// 下一个倍速档(循环切换)
  static double nextSpeed(double current) {
    final i = speedOptions.indexOf(current);
    if (i < 0) return speedOptions[1]; // 非法值回 1.0
    return speedOptions[(i + 1) % speedOptions.length];
  }

  /// 时长显示:mm:ss(超过 1 小时给 h:mm:ss)
  static String formatDuration(Duration? d) {
    if (d == null || d < Duration.zero) return '--:--';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// 地址是否像音频:必须是 http(s),且路径带常见音频后缀
  /// (RSS 里音频也不总是带后缀,所以**只做提示性判断**,不做硬拦截 ——
  /// 真正能不能播出以播放器为准)
  static bool looksPlayable(String? url) {
    if (url == null) return false;
    final u = url.trim().toLowerCase();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    return u.contains('.mp3') ||
        u.contains('.m4a') ||
        u.contains('.aac') ||
        u.contains('.ogg') ||
        u.contains('.opus') ||
        u.contains('.wav') ||
        u.contains('/audio') ||
        u.contains('podcast') ||
        u.contains('feedburner') ||
        u.contains('mp3');
  }

  static String _short(String url) =>
      url.length <= 40 ? url : '${url.substring(0, 40)}…';

  static String _friendly(Object e) {
    final s = '$e';
    if (s.contains('SocketException') || s.contains('Connection')) {
      return '网络连不上(该音频源可能被墙,换一个源或稍后再试)';
    }
    if (s.contains('404')) return '音频不存在(可能已下架)';
    if (s.contains('403')) return '音频被拒绝访问(可能需要登录)';
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }
}
