import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 全局崩溃捕获 + 本地日志落盘。
///
/// 背景(v1.3.2):用户真机"第一次识别必闪退,第二次正常"——没有日志时
/// 只能盲猜,出现"打地鼠"式反复修。安装本捕获后:
/// - Flutter 框架错误(FlutterError.onError)→ 写 文档目录/crash_log.txt
/// - 异步 zone 未捕获异常(PlatformDispatcher.onError)→ 同上
/// - 保留默认打印行为(presentError),不影响调试
/// - 日志文件随下次启动持久可读([readCrashLog]);崩溃后 App 再启动,
///   主屏 A 区若检测到新日志可提示用户(可选,先落盘为主)
class CrashLogger {
  CrashLogger._();

  /// 单条日志上限(字符)。栈回溯动辄上千行,不截断会让文件迅速膨胀。
  static const int maxEntryChars = 4000;

  /// 文件上限 256KB(审查 P2-6)。超过时只保留尾部——最近的崩溃才有诊断价值,
  /// 旧的直接丢弃,避免"循环报错 → 文件无界增长 → 每次写入都在搬大文件"。
  static const int maxFileBytes = 256 * 1024;

  static bool _installed = false;
  static File? _logFile;

  /// 写盘前脱敏(审查 P2-6):诊断页内容常被截图/贴到 Issue,
  /// 而崩溃栈与异常消息里可能夹带请求体中的 Key 或 Authorization 头。
  /// 只保留"是什么类型的凭证",不留任何可用片段。
  static String redact(String text) {
    var out = text;
    for (final re in _secretPatterns) {
      out = out.replaceAll(re, '***');
    }
    return out;
  }

  static final List<RegExp> _secretPatterns = [
    RegExp(r'sk-[A-Za-z0-9_-]{6,}'),
    RegExp(r'ark-[A-Za-z0-9_-]{6,}'),
    RegExp(r'Bearer\s+\S+'),
  ];

  /// 在 main() 中 runApp 前调用一次。
  static Future<void> install() async {
    if (_installed) return;
    _installed = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}${Platform.pathSeparator}crash_log.txt');
    } catch (_) {
      _logFile = null; // 拿不到目录(测试环境)则只打印不落盘
    }

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _append('FlutterError: ${details.exception}\n${details.stack}\n---\n');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _append('ZoneError: $error\n$stack\n---\n');
      // 返回 true = 错误已记录,不让未捕获异常直接终止 App(减少无谓闪退);
      // 关键缺陷仍会通过 FlutterError.onError 打印暴露在调试日志
      return true;
    };
  }

  static void _append(String text) {
    final f = _logFile;
    if (f == null) return;
    try {
      // 脱敏 + 截断都在写盘前做:读日志的人不需要原文,留长度足够定位问题
      var safe = redact(text);
      if (safe.length > maxEntryChars) {
        safe = '${safe.substring(0, maxEntryChars)}…(已截断,原长 ${safe.length})';
      }
      _trimIfTooLarge(f);
      f.writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] $safe\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 日志写入失败绝不影响主流程
    }
  }

  /// 超过上限就把文件重写成"尾部片段 + 截断标记"。
  /// 放在 append 之前做,而不是写完再检查:否则崩溃循环里每次都要写一次大文件。
  static void _trimIfTooLarge(File f) {
    if (!f.existsSync() || f.lengthSync() <= maxFileBytes) return;
    final content = f.readAsStringSync();
    // 按"字符数"取尾简单可靠(中文 3 字节,按字节切会切碎字符)
    final keep = content.length > maxEntryChars * 2
        ? content.substring(content.length - maxEntryChars * 2)
        : content;
    f.writeAsStringSync(
      '…(日志超过 ${maxFileBytes ~/ 1024}KB,已丢弃较早内容)\n$keep',
      mode: FileMode.write,
    );
  }

  /// 读取崩溃日志(为空 = 无崩溃记录);每次读取后不清理,
  /// 由调用方决定是否清空([clearCrashLog])。
  static Future<String> readCrashLog() async {
    final f = _logFile;
    if (f == null || !await f.exists()) return '';
    try {
      return await f.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clearCrashLog() async {
    final f = _logFile;
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
