import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
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

  /// 下载用 Dio:必须带超时——GitHub 直连在国内可能挂起,无超时则卡 0% 不动
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 20),
  ));

  /// 请求 Options:公开仓库匿名访问即可
  static Options _apiOpts() => Options(
        headers: {'Accept': 'application/vnd.github+json'},
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      );

  /// 检查 GitHub 最新 Release。
  /// 返回 [UpdateInfo]；未配置仓库/无 APK 资源/网络失败均返回 null(静默)。
  /// 2026-08-09 修复:检查接口裸连 api.github.com(国内经常连不上,
  /// 用户实测"收不到自动更新")——改为直连 + 镜像前缀竞速,谁先回谁胜。
  static Future<UpdateInfo?> checkLatestRelease() async {
    if (AppConstants.githubOwner.isEmpty) return null;
    final base =
        'https://api.github.com/repos/'
        '${AppConstants.githubOwner}/${AppConstants.githubRepo}/releases/latest';
    final candidates = <String>[
      base,
      for (final p in _mirrorPrefixes) '$p$base',
    ];

    Map<String, dynamic>? data;
    final completer = Completer<void>();
    for (final url in candidates) {
      unawaited(() async {
        try {
          final resp = await _dio.get(url, options: _apiOpts());
          final d = resp.data as Map<String, dynamic>?;
          if (d != null && !completer.isCompleted) {
            data = d;
            completer.complete();
          }
        } catch (_) {
          // 单候选失败:等别的候选
        }
      }());
    }
    // 总预算 15s:到点还没有任何候选成功 → 静默返回 null
    await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
    if (data == null) return null;
    final d = data!; // 竞速闭包内赋值,编译期无法收窄,此处强制非空

    final tag = (d['tag_name'] as String? ?? '').replaceFirst(
      RegExp(r'^v'), '',
    );
    final body = d['body'] as String? ?? '';
    final assets = d['assets'] as List? ?? [];

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

  /// GitHub 加速代理前缀(2026-03 国内实测可用/高速,按前缀式代理格式)。
  /// 全部为公共节点,随时可能失效——并发竞速 + 直连兜底,不依赖单点。
  static const List<String> _mirrorPrefixes = [
    'https://gh.zwy.one/',          // 实测 7119 KB/s
    'https://gh.llkk.cc/',          // 实测 6211 KB/s
    'https://ghproxy.cxkpro.top/',  // 实测 5292 KB/s
    'https://gh.h233.eu.org/',      // 实测 4918 KB/s
    'https://ghfast.top/',          // 多国 CDN,实测 2972 KB/s
    'https://gh-proxy.com/',        // 老牌稳定
  ];

  /// 下载 APK 到应用缓存目录,返回本地文件路径。
  /// 并发竞速:所有候选(镜像 + 直连)同时下载到独立临时文件,
  /// 首个完成者胜出,其余立即取消——串行试错会卡死在
  /// "连接成功但吐数据极慢"的镜像上,竞速模式不会。
  /// 进度取所有节点中的最大值(最快节点的进展)。
  static Future<String> downloadApk(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await getApplicationCacheDirectory();

    // 候选去重(镜像前缀 + 直连)
    final candidates = <String>[];
    for (final p in _mirrorPrefixes) {
      final c = '$p$url';
      if (!candidates.contains(c)) candidates.add(c);
    }
    if (!candidates.contains(url)) candidates.add(url);

    // 总预算:120s 内没有任一候选完成 → 报错让用户重试
    const totalBudget = Duration(seconds: 120);

    final cancelTokens = <CancelToken>[];
    final complete = Completer<String>();
    var settled = false;
    var maxReceived = 0;

    Future<void> tryCandidate(String candidate, int idx) async {
      final cancel = CancelToken();
      cancelTokens.add(cancel);
      final file = File('${dir.path}/readflow-update-$idx.part');
      try {
        if (file.existsSync()) file.deleteSync();
        await _dio.download(
          candidate,
          file.path,
          cancelToken: cancel,
          onReceiveProgress: (received, total) {
            if (settled) return;
            // 上报全部节点中的最大进度(哪个快显示哪个)
            if (received > maxReceived) {
              maxReceived = received;
              onProgress?.call(received, total);
            }
          },
        );
        if (!settled) {
          settled = true;
          // 竞速临时名是 .part——PackageInstaller 按 URI 文件名扩展名
          // 判断是否 APK,非 .apk 会静默拒绝打开(进度满但不跳安装界面)。
          // 必须改回 .apk 再交给系统安装器。
          final apkPath = file.path.replaceFirst(RegExp(r'\.part$'), '.apk');
          if (file.existsSync()) {
            try {
              await file.rename(apkPath);
            } catch (_) {
              try {
                await file.copy(apkPath);
              } catch (_) {}
            }
          }
          complete.complete(apkPath);
          // 胜出后取消其余候选,停止占用带宽
          for (final c in cancelTokens) {
            if (!identical(c, cancel)) c.cancel();
          }
        }
      } catch (_) {
        // 单节点失败:等别的候选,总预算兜底
      }
    }

    // 启动所有候选(不 await,竞速)
    for (int i = 0; i < candidates.length; i++) {
      tryCandidate(candidates[i], i);
    }
    onProgress?.call(0, 1);

    return complete.future.timeout(totalBudget, onTimeout: () {
      for (final c in cancelTokens) {
        c.cancel();
      }
      throw Exception('下载超时(120s),请检查网络后重试');
    });
  }

  /// 调起系统安装器安装 APK(Android 会引导"未知来源"授权)。
  /// 自写 MethodChannel(app/install_apk,见 MainActivity.kt)替代 open_filex——
  /// open_filex 在部分路径下不回调 result 导致 await 永久挂起
  /// (用户看到"正在打开安装器"卡死,无超时无错误)。
  /// 自写通道同步返回成功/失败,并加 15s 超时兜底,任何情况都快速可见。
  static const MethodChannel _installChannel = MethodChannel(
    'app/install_apk',
  );

  static Future<void> installApk(String path) async {
    try {
      await _installChannel
          .invokeMethod('installApk', {'path': path})
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception(
              '打开安装器 15 秒无响应,可能被系统拦截。'
              '请在设置中允许「安装未知应用」后重试',
            ),
          );
    } on PlatformException catch (e) {
      throw Exception('打开安装器失败: ${e.message ?? e.code}');
    }
  }
}
