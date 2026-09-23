import 'package:flutter_tts/flutter_tts.dart';

import 'tts_accent.dart';

/// 系统 TTS 朗读服务(v1.5.0 词汇发音)。
/// 懒初始化:首次朗读时才创建 FlutterTts,失败静默降级为"不朗读",
/// 绝不让一个语音引擎缺失拖垮词条页面。
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  FlutterTts? _tts;
  bool _initFailed = false;

  /// 初始化时用的语言码(v1.5 起固定 en-US)。
  /// v2.0:朗读前会按用户选的音色改语言,**改完要还原** —— 下次选择
  /// "跟随系统"时不该残留上一次的英/美设置。
  static const String _defaultLanguage = 'en-US';

  Future<FlutterTts?> _ensureTts() async {
    if (_tts != null) return _tts;
    if (_initFailed) return null;
    try {
      final tts = FlutterTts();
      await tts.setLanguage(_defaultLanguage);
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
  Future<bool> speak(String text) => speakWithLanguage(text, null);

  /// 按用户选择的音色朗读(v2.0):读一次 Hive 里的档位,映射成语言码。
  /// 词条/复习卡/详情页都走这个入口,保证"设置里选什么就念什么"。
  Future<bool> speakPreferred(String text) =>
      speakWithLanguage(text, ttsLanguageForAccent(loadTtsAccent()));

  /// 慢速朗读(v2.2 听写):语速降到 0.35 —— 听写练习里"听不清"的第一反应
  /// 是放慢,而不是反复重放同一速度(后者只是重复听不清)
  Future<bool> speakSlow(String text) => _speak(text, null, rate: 0.35);

  /// 慢速 + 用户音色(听写默认用这个)
  Future<bool> speakSlowPreferred(String text) =>
      _speak(text, ttsLanguageForAccent(loadTtsAccent()), rate: 0.35);

  /// [language] 为 null → 用引擎当前语言(即"跟随系统"),
  /// 同时把语言恢复成默认,避免残留上一次的英/美选择。
  Future<bool> speakWithLanguage(String text, String? language) =>
      _speak(text, language);

  /// 真正的朗读实现(带可选语速):正常 0.5,听写慢速 0.35
  Future<bool> _speak(String text, String? language, {double rate = 0.5}) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final tts = await _ensureTts();
    if (tts == null) return false;
    try {
      // setLanguage 失败不阻断朗读(部分引擎不支持目标口音时,
      // 让它用默认声音念出来,总好过"点了没反应")
      try {
        await tts.setLanguage(language ?? _defaultLanguage);
      } catch (_) {}
      try {
        await tts.setSpeechRate(rate);
      } catch (_) {}
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
