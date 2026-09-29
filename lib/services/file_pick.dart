import 'package:flutter/services.dart';

/// 系统文件选择器(v2.7,用户第 2(4) 条:材料导入要支持"文件")。
///
/// **为什么不用 file_picker**:实测它的 11.0.3 在 AGP 9 下不 apply Kotlin 插件
/// (而它源码是 `.kt`)→ Kotlin 源根本不编译,`flutter build apk` 报
/// 「找不到符号 FilePickerPlugin」;退到 10.0.0 又因它把 compileSdk 写死 34、
/// 与 `flutter_plugin_android_lifecycle` 要求的 36 冲突而构建失败。
/// 两版都过不了构建,而这一段只需要 SAF 一个 Intent ——
/// 与 `app/open_url`(v2.6)同一套写法:**自写原生通道,零新依赖**。
///
/// 实现见 `android/app/src/main/kotlin/com/readflow/readflow/MainActivity.kt`
/// 的 `app/pick_file` 通道:ACTION_OPEN_DOCUMENT(**不需要任何存储权限**,
/// 用户通过系统选择器逐个授权),名字取 `OpenableColumns.DISPLAY_NAME`,
/// 内容读成字节回传。
class FilePickService {
  FilePickService._();

  static const MethodChannel _channel = MethodChannel('app/pick_file');

  /// 大小上限与原生侧一致(8MB);Dart 侧也拦一道,提示语更具体
  static const int maxBytes = 8 * 1024 * 1024;

  /// 打开系统文件选择器。
  ///
  /// 返回 null = 用户取消(不是错误)。原生侧已把超过 8MB 的情况变成
  /// `TOO_LARGE` 错误,这里解析成中文原因抛给调用方显示。
  static Future<PickedLocalFile?> pickFile() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('pickFile');
      if (raw == null) return null;
      final name = '${raw['name'] ?? ''}'.trim();
      final bytes = raw['bytes'];
      if (bytes is! Uint8List) {
        throw const FilePickException('系统没有返回文件内容(可能是云盘文件还没下载完)');
      }
      return PickedLocalFile(
        name: name.isEmpty ? '未命名文件' : name,
        bytes: bytes,
      );
    } on PlatformException catch (e) {
      throw FilePickException(_friendly(e));
    } on MissingPluginException {
      throw const FilePickException('这台设备不支持系统文件选择器,请改用「粘贴材料」');
    }
  }

  /// 原生错误码 → 人话(用户看到的每一句都要能指导下一步)
  static String _friendly(PlatformException e) {
    switch (e.code) {
      case 'TOO_LARGE':
        return e.message ?? '文件太大,建议切成几份再导入';
      case 'READ_FAILED':
        return e.message ?? '读不到这个文件(可能没有读取权限)';
      case 'NO_PICKER':
        return e.message ?? '这台设备没有可用的文件选择器';
      case 'BUSY':
        return e.message ?? '上一次选择还没结束,请稍候';
      default:
        return e.message ?? '选择文件失败(${e.code})';
    }
  }
}

/// 用户选中的本地文件(名字 + 内容字节)
class PickedLocalFile {
  final String name;
  final Uint8List bytes;

  const PickedLocalFile({required this.name, required this.bytes});

  int get sizeBytes => bytes.length;
}

/// 选文件/读文件失败。**中文可读**,直接给界面显示。
class FilePickException implements Exception {
  final String message;
  const FilePickException(this.message);

  @override
  String toString() => message;
}
