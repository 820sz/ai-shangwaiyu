import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';

/// 远程更新信息
class UpdateInfo {
  /// 远程版本号(不含 v 前缀),如 1.0.1
  final String version;
  /// APK 下载地址
  final String downloadUrl;
  /// 更新说明(Release body)
  final String releaseNotes;
  /// 当前安装版本
  final String currentVersion;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.currentVersion,
  });

  /// 远程版本是否比当前新
  bool get hasUpdate => UpdateService.compareVersions(version, currentVersion) > 0;
}

/// 自动更新服务:检查 GitHub Release → 下载 APK → 调起系统安装器
class UpdateService {
  UpdateService._();

  static final Dio _dio = Dio();

  /// 检查 GitHub 最新 Release。
  /// 返回 [UpdateInfo]；未配置仓库/无 APK 资源/网络失败均返回 null(静默)。
  static Future<UpdateInfo?> checkLatestRelease() async {
    if (AppConstants.githubOwner.isEmpty) return null;
    try {
      final resp = await _dio.get(
        'https://api.github.com/repos/'
        '${AppConstants.githubOwner}/${AppConstants.githubRepo}/releases/latest',
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final data = resp.data as Map<String, dynamic>?;
      if (data == null) return null;

      final tag = (data['tag_name'] as String? ?? '').replaceFirst(
        RegExp(r'^v'), '',
      );
      final body = data['body'] as String? ?? '';
      final assets = data['assets'] as List? ?? [];

      // 找第一个 APK 资源
      String? apkUrl;
      for (final asset in assets) {
        if (asset is Map && (asset['name'] as String? ?? '').endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          break;
        }
      }
      if (tag.isEmpty || apkUrl == null) return null;

      final current = await _currentVersion();
      return UpdateInfo(
        version: tag,
        downloadUrl: apkUrl,
        releaseNotes: body,
        currentVersion: current,
      );
    } catch (_) {
      return null; // 检查失败不打扰用户
    }
  }

  /// 当前安装版本号,如 "1.0.0"
  static Future<String> _currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0.0.0';
    }
  }

  /// 版本号比较:a > b 返回正数,a < b 返回负数,相等返回 0。
  /// 支持 "1.2.3" / "1.2.3+4" / "v1.2.3" 格式。
  static int compareVersions(String a, String b) {
    final na = _parseVersion(a);
    final nb = _parseVersion(b);
    for (int i = 0; i < 3; i++) {
      if (na[i] != nb[i]) return na[i].compareTo(nb[i]);
    }
    return 0;
  }

  static List<int> _parseVersion(String v) {
    final clean = v.replaceFirst(RegExp(r'^v'), '').split('+').first;
    final parts = clean.split('.');
    final out = [0, 0, 0];
    for (int i = 0; i < parts.length && i < 3; i++) {
      out[i] = int.tryParse(parts[i]) ?? 0;
    }
    return out;
  }

  /// 下载 APK 到应用缓存目录,返回本地文件路径
  static Future<String> downloadApk(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await getApplicationCacheDirectory();
    final file = File('${dir.path}/readflow-update.apk');
    await _dio.download(
      url,
      file.path,
      onReceiveProgress: onProgress,
    );
    return file.path;
  }

  /// 调起系统安装器安装 APK(Android 会引导"未知来源"授权)
  static Future<void> installApk(String path) async {
    await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
  }
}
