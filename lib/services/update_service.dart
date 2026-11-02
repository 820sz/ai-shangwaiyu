import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
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

  /// 官方给出的 sha256 十六进制串(v1.9.0,审查 P0-1)。
  /// 来自 GitHub Release asset 的 `digest` 字段;取不到时为空串,
  /// 此时下载后至少校验字节数。
  final String sha256;
  /// 官方给出的字节数(0 = 未知)
  final int sizeBytes;
  /// 本次元数据的来源:'github'(直连)或镜像域名(审查 P0-1/P2-9 的知情权)
  final String source;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.currentVersion,
    this.sha256 = '',
    this.sizeBytes = 0,
    this.source = 'github',
  });

  /// 远程版本是否比当前新(v1.9.0:比较四段,含 build 号)
  bool get hasUpdate => UpdateService.compareVersions(version, currentVersion) > 0;

  /// 是否走第三方镜像(用于界面上如实告知下载来源)
  bool get viaMirror => source != 'github';
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
  /// 返回 [UpdateInfo]；未配置仓库返回 null(静默);网络全失败抛异常(调用方提示),
  /// 绝不谎报"已是最新"。
  /// 2026-08-09 修复:检查接口裸连 api.github.com(国内经常连不上,
  /// 用户实测"收不到自动更新")——改为直连 + 镜像前缀竞速。
  /// 2026-08-10 修复:竞速"先到先得"会拿镜像缓存的旧 latest 响应(用户实测
  /// "自动更新还是 20 版本")——改为收集所有成功响应,取 tag 版本号最大者。
  /// 2026-08-11 修复(F3):直连(权威)被 15s 截断收割——直连 >15s 时 stale
  /// 镜像响应胜出,又回到"自动更新还是 20 版本"。改直连独立等 20s 优先,
  /// 直连失败才用镜像;全失败抛异常,不再静默 null。
  static Future<UpdateInfo?> checkLatestRelease() async {
    if (AppConstants.githubOwner.isEmpty) return null;
    final base =
        'https://api.github.com/repos/'
        '${AppConstants.githubOwner}/${AppConstants.githubRepo}/releases/latest';

    // 权威直连独立等待(Dio 自带 10s receiveTimeout,外框 20s 兜底),
    // 不被镜像的竞速截断打断——直连成功就完全信任它
    final direct = await _fetchRelease(base).timeout(
      const Duration(seconds: 20),
      onTimeout: () => null,
    );
    if (direct != null) return _buildInfo(direct, source: 'github');

    // 直连失败:并发收镜像(15s 截断),取版本最高者(可能 stale,但优于无响应)
    final mirrorResponses = <Map<String, dynamic>>[];
    final pending = <Future<void>>[];
    for (final p in _mirrorPrefixes) {
      pending.add(_fetchRelease('$p$base').then((d) {
        if (d != null) mirrorResponses.add(d);
      }));
    }
    await Future.wait(pending).timeout(
      const Duration(seconds: 15),
      onTimeout: () => <void>[],
    );
    if (mirrorResponses.isEmpty) {
      throw Exception('无法连接 GitHub,请检查网络后重试');
    }
    return _buildInfo(pickLatest(mirrorResponses));
  }

  static Future<Map<String, dynamic>?> _fetchRelease(String url) async {
    try {
      final resp = await _dio.get(url, options: _apiOpts());
      final d = resp.data as Map<String, dynamic>?;
      return (d != null && d.isNotEmpty) ? d : null;
    } catch (_) {
      return null; // 单候选失败:忽略,等别的候选
    }
  }

  static Future<UpdateInfo?> _buildInfo(
    Map<String, dynamic> d, {
    String source = 'github',
  }) async {
    final tag = (d['tag_name'] as String? ?? '').replaceFirst(
      RegExp(r'^v'), '',
    );
    final body = d['body'] as String? ?? '';
    final assets = d['assets'] as List? ?? [];

    // 找第一个 APK 资源;v1.9.0(审查 P0-1):同时取 GitHub 提供的
    // digest(sha256) 与 size,作为下载后完整性校验的依据
    String? apkUrl;
    var sha256 = '';
    var sizeBytes = 0;
    for (final asset in assets) {
      if (asset is Map && (asset['name'] as String? ?? '').endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        final digest = asset['digest']?.toString() ?? '';
        if (digest.startsWith('sha256:')) {
          sha256 = digest.substring('sha256:'.length).toLowerCase();
        }
        final size = asset['size'];
        if (size is int) sizeBytes = size;
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
      sha256: sha256,
      sizeBytes: sizeBytes,
      source: source,
    );
  }

  /// 从多个 latest 响应中取 tag 版本号最高者。
  /// 镜像节点可能缓存旧响应,不能"先到先得",必须取最新。
  static Map<String, dynamic> pickLatest(List<Map<String, dynamic>> responses) {
    return responses.reduce((a, b) {
      final va = (a['tag_name'] as String? ?? '').replaceFirst(
        RegExp(r'^v'),
        '',
      );
      final vb = (b['tag_name'] as String? ?? '').replaceFirst(
        RegExp(r'^v'),
        '',
      );
      return compareVersions(va, vb) >= 0 ? a : b;
    });
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
  /// v1.9.0(审查 P2-9):**纳入 `+build` 号** —— 旧实现 `split('+').first`
  /// 把 build 号整个丢掉,于是"只升 build 号的修复版"会被判成"无更新",
  /// 用户永远收不到(README 的发布流程也没约束必须改 versionName)。
  static int compareVersions(String a, String b) {
    final na = _parseVersion(a);
    final nb = _parseVersion(b);
    for (int i = 0; i < 4; i++) {
      if (na[i] != nb[i]) return na[i].compareTo(nb[i]);
    }
    return 0;
  }

  /// 解析版本号为 [major, minor, patch, build](缺失补 0)
  static List<int> _parseVersion(String v) {
    final clean = v.replaceFirst(RegExp(r'^v'), '').trim();
    final plusIdx = clean.indexOf('+');
    final namePart = plusIdx >= 0 ? clean.substring(0, plusIdx) : clean;
    final buildPart = plusIdx >= 0 ? clean.substring(plusIdx + 1) : '';
    final parts = namePart.split('.');
    final out = [0, 0, 0, 0];
    for (int i = 0; i < parts.length && i < 3; i++) {
      out[i] = int.tryParse(parts[i].trim()) ?? 0;
    }
    out[3] = int.tryParse(buildPart.trim()) ?? 0;
    return out;
  }

  // ═══════════ 自动检查更新(2026-11-01 用户 11/01 新增要求) ═══════════

  /// 用户原话:"软件的内置更新按钮现在是只有手动点才会推送新版本,而不是点进软件
  /// 自动提示;而且更新内容播报是属于'给我汇报工作的提示词'而不是规规矩矩的
  /// 升级的地方'1,xxx。2,xxx'"。
  ///
  /// 这里放"自动检查"的节流开关:默认 **24 小时**最多自动查一次,
  /// 避免每次冷启动都打一次 GitHub(国内网络一次要等 10~20s)。
  /// 手动「检查更新」按钮不走这个节流,随点随查。
  static const String _autoCheckKey = 'update_last_auto_check_at';

  /// 纯函数:距离上次自动检查是否已超过 [interval]。抽出来是为了可单测。
  static bool isAutoCheckDue(
    int? lastCheckMs,
    DateTime now, {
    Duration interval = const Duration(hours: 24),
  }) {
    if (lastCheckMs == null) return true;
    // 时钟回拨(用户改时间/时区)按"该查"处理,宁查勿漏
    final elapsed = now.millisecondsSinceEpoch - lastCheckMs;
    if (elapsed < 0) return true;
    return elapsed >= interval.inMilliseconds;
  }

  /// 上次自动检查的时间戳(ms)。Hive 不可用时返回 null(=视为该检查)。
  static Future<int?> lastAutoCheckMs() async {
    try {
      final box = await Hive.openBox(AppConstants.hiveBoxSettings);
      return box.get(_autoCheckKey) as int?;
    } catch (e) {
      debugPrint('ReadFlow 读取更新检查时间失败: $e');
      return null;
    }
  }

  /// 记下"这次自动检查已完成"的时间戳(成功拿到响应后才调,失败下次还能重试)。
  static Future<void> markAutoCheckDone([DateTime? at]) async {
    try {
      final box = await Hive.openBox(AppConstants.hiveBoxSettings);
      await box.put(
        _autoCheckKey,
        (at ?? DateTime.now()).millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('ReadFlow 记录更新检查时间失败: $e');
    }
  }

  // ═══════════ Release 说明 → 用户可读的编号清单 ═══════════

  /// 把 GitHub Release 的 markdown 正文解析成"给用户看的短句清单"。
  ///
  /// 为什么要有这个纯函数:更新弹窗以前把 Release body 原样塞进 `Text`,
  /// 用户看到的是带 `#`、`**`、引用块的长文(像写给自己看的工作汇报)。
  /// 现在统一归一成"1、2、3"的升级清单。
  ///
  /// 规则(从宽到严,兼容老版本说明):
  /// 1. 优先取「## 更新内容 / 更新说明 / 本次更新」小节(本轮起发版说明的统一格式,
  ///    见 docs/RELEASE-NOTES-FORMAT.md);
  /// 2. 老正文没有该小节时,退化为"收集顶层列表项"(`- ` / `1. ` / `1、`);
  /// 3. 遇到「验证/测试/还没做/风险/附录/后记/技术细节」这类非用户向小节就停止收集;
  /// 4. 去掉 markdown 标记与链接 URL,只留纯文本;去重;最多 [maxItems] 条。
  static List<String> parseReleaseNotesForDisplay(
    String body, {
    int maxItems = 8,
  }) {
    if (body.trim().isEmpty || maxItems <= 0) return const <String>[];
    final lines = body.replaceAll('\r\n', '\n').split('\n');

    // 非用户向小节:命中标题后,下面的列表项不再进更新弹窗
    const stopHeadingWords = [
      '验证',
      '测试',
      '还没做',
      '未做',
      '风险',
      '附录',
      '后记',
      '技术细节',
      '签名',
    ];
    bool isStopHeading(String line) {
      final t = line.trim();
      if (!t.startsWith('#')) return false;
      final title = t.replaceFirst(RegExp(r'^#+\s*'), '');
      return stopHeadingWords.any(title.contains);
    }

    // ① 先找「更新内容」小节起点
    var sectionStart = -1;
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (!t.startsWith('#')) continue;
      final title = t.replaceFirst(RegExp(r'^#+\s*'), '');
      if (title.contains('更新内容') ||
          title.contains('更新说明') ||
          title.contains('本次更新')) {
        sectionStart = i + 1;
        break;
      }
    }

    final out = <String>[];
    var inStopSection = false;
    // 全文兜底模式(没有「更新内容」小节)只认**列表行**:
    // 普通段落交给下面的"取第一段前两句"兜底,避免整段正文被当成一条。
    final bool listOnly = sectionStart < 0;
    final listMarker = RegExp(r'^(?:[-*+]\s+|\d+[.、)）]\s*)');
    for (var i = sectionStart >= 0 ? sectionStart : 0; i < lines.length; i++) {
      final raw = lines[i];
      final t = raw.trim();
      if (t.startsWith('#')) {
        // 小节模式下:下一个标题 = 更新内容结束
        if (sectionStart >= 0) break;
        // 全文模式下:进入/离开"非用户向"小节
        inStopSection = isStopHeading(raw);
        continue;
      }
      if (inStopSection) continue;
      if (listOnly && !listMarker.hasMatch(t)) continue;
      final item = _cleanNotesLine(raw);
      if (item == null) continue;
      if (!out.contains(item)) out.add(item);
      if (out.length >= maxItems) break;
    }

    // ② 兜底:没有列表项时取第一段正文的前两句
    if (out.isEmpty) {
      for (final line in lines) {
        final t = line.trim();
        if (t.isEmpty ||
            t.startsWith('#') ||
            t.startsWith('>') ||
            t.startsWith('|') ||
            t.startsWith('```') ||
            t.startsWith('![')) {
          continue;
        }
        for (final sentence in t.split(RegExp(r'[。！？]'))) {
          final item = _cleanNotesLine(sentence);
          if (item == null) continue;
          if (!out.contains(item)) out.add(item);
          if (out.length >= 2) break;
        }
        if (out.isNotEmpty) break;
      }
    }
    return out;
  }

  /// 清洗一行更新说明:去掉列表符号/markdown 标记/链接 URL。
  /// 返回 null = 这一行不适合进"用户可读清单"(嵌套细节/表格/引用/纯链接)。
  static String? _cleanNotesLine(String line) {
    final raw = line.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('>') ||
        raw.startsWith('|') ||
        raw.startsWith('```') ||
        raw.startsWith('![')) {
      return null;
    }
    // 缩进的子项属于上一条的细节,不单独成条
    if (RegExp(r'^\s{2,}[-*+]\s').hasMatch(line)) return null;
    if (RegExp(r'^\s{2,}\d+[.、)）]').hasMatch(line)) return null;

    var t = raw;
    t = t.replaceFirst(RegExp(r'^[-*+]\s+'), '');
    t = t.replaceFirst(RegExp(r'^\d+[.、)）]\s*'), '');
    t = t.replaceFirst(RegExp(r'^\[[ xX]\]\s*'), '');
    // [文字](链接) 只留文字;裸 <html> 标签去掉
    t = t.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]*\)'),
      (m) => m.group(1) ?? '',
    );
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    t = t.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    // 句尾的"。"删掉更清爽(问号/叹号保留)
    t = t.replaceFirst(RegExp(r'[。；;]+$'), '').trim();
    if (t.length < 2) return null;
    if (RegExp(r'^https?://\S+$').hasMatch(t)) return null;
    if (RegExp(r'^[|:\-\s]+$').hasMatch(t)) return null;
    return t;
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
  /// 并发竞速:所有候选(**直连优先**)同时下载到独立临时文件,
  /// 首个完成者胜出,其余立即取消——串行试错会卡死在
  /// "连接成功但吐数据极慢"的镜像上,竞速模式不会。
  /// 进度取所有节点中的最大值(最快节点的进展)。
  ///
  /// v1.9.0(审查 P0-1):下载完成后**校验完整性** ——
  /// 优先比对 GitHub 给出的 sha256(官方 digest),取不到时至少比字节数;
  /// 不一致就删文件并抛错,绝不把来路不明的字节交给系统安装器。
  /// 另外默认**只信直连**:只有直连失败才退回镜像(镜像按公开公益节点维护,
  /// 被投毒/抢注时用户无从察觉)。
  static Future<String> downloadApk(
    String url, {
    void Function(int received, int total)? onProgress,
    String expectedSha256 = '',
    int expectedSize = 0,
  }) async {
    // P2-24:APK 下到缓存目录的 updates/ 子目录 —— FileProvider(file_paths.xml)
    // 只声明这一层,不再把 cache/files/外部存储整根暴露给系统安装器。
    final cacheRoot = await getApplicationCacheDirectory();
    final dir = Directory('${cacheRoot.path}/updates');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    // 候选顺序:直连在前,镜像兜底(去重)
    final candidates = <String>[];
    if (!candidates.contains(url)) candidates.add(url);
    for (final p in _mirrorPrefixes) {
      final c = '$p$url';
      if (!candidates.contains(c)) candidates.add(c);
    }

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
          // v1.9.0(审查 P0-1):竞速窗口内先校验完整性,不合格的候选直接淘汰
          final verify = await verifyApk(
            file,
            expectedSha256: expectedSha256,
            expectedSize: expectedSize,
          );
          if (verify != null) {
            debugPrint('ReadFlow 更新包校验失败($candidate): $verify');
            try {
              if (file.existsSync()) file.deleteSync();
            } catch (_) {}
            return; // 让其它候选继续;全都不合格 → 总预算超时报错
          }
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

  /// 校验下载到的安装包(v1.9.0,审查 P0-1)。
  /// 返回 null = 通过;返回字符串 = 失败原因(调用方据此淘汰该候选)。
  ///
  /// 规则:
  /// - 有官方 sha256 → **必须**匹配(这是唯一能挡住"镜像被投毒"的手段);
  /// - 没有 sha256 但有官方字节数 → 比对字节数;
  /// - 两者都没有 → 拒绝(宁可让用户手动下载,也不静默安装未知文件)。
  static Future<String?> verifyApk(
    File file, {
    required String expectedSha256,
    required int expectedSize,
  }) async {
    if (!file.existsSync()) return '文件不存在';
    final actualSize = await file.length();
    if (actualSize <= 0) return '文件为空';
    if (expectedSize > 0 && actualSize != expectedSize) {
      return '字节数不符(期望 $expectedSize,实际 $actualSize)';
    }
    if (expectedSha256.isEmpty) {
      return expectedSize > 0 ? null : '发布方未提供校验信息(sha256/size),已拒绝安装';
    }
    try {
      final digest = await sha256.bind(file.openRead()).first;
      final actual = digest.toString().toLowerCase();
      if (actual != expectedSha256.toLowerCase()) {
        return 'sha256 不符(期望 ${expectedSha256.substring(0, 12)}…,'
            '实际 ${actual.substring(0, 12)}…)';
      }
    } catch (e) {
      return '计算 sha256 失败: $e';
    }
    return null;
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
