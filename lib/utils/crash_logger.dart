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

  static bool _installed = false;
  static File? _logFile;

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
      f.writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] $text\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 日志写入失败绝不影响主流程
    }
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
