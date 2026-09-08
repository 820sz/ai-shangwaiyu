import 'package:flutter_tts/flutter_tts.dart';

/// 系统 TTS 朗读服务(v1.5.0 词汇发音)。
/// 懒初始化:首次朗读时才创建 FlutterTts,失败静默降级为"不朗读",
/// 绝不让一个语音引擎缺失拖垮词条页面。
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  FlutterTts? _tts;
  bool _initFailed = false;

  Future<FlutterTts?> _ensureTts() async {
    if (_tts != null) return _tts;
    if (_initFailed) return null;
    try {
      final tts = FlutterTts();
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.5);
      await tts.setPitch(1.0);
      _tts = tts;
      return tts;
    } catch (e) {
      _initFailed = true;
      return null;
    }
  }

  /// 朗读文本(英语)。连续点击自动打断上一次。
  /// 返回是否成功启动;失败不抛异常,调用方可静默或提示。
  Future<bool> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final tts = await _ensureTts();
    if (tts == null) return false;
    try {
      await tts.stop();
      final result = await tts.speak(t);
      return result == 1;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {
      // 忽略
    }
  }
}
