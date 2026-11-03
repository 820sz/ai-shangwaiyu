/// 材料配图:自动为材料找**它自己的图**(书封 / 插图),而不是永远画色块。
///
/// 用户 2026-11-03:"材料那些封面尽量能让 AI 抓取并配上材料自身的插图或者封面,
/// 不然整个软件太素了",并明确"书封网上本来就有"。
///
/// 所以这里做的是**抓取优先、生成兜底**,不是无脑 AI 生图(生图有成本):
/// 1. 材料源自带的图(feed 的 media:image / 链接导入时的 og:image / 库里的
///    cover_url)已经在库里,直接展示 —— 不联网、零成本;
/// 2. **书**:豆瓣读书的联想接口按书名搜,拿封面图(豆瓣图床国内可达);
/// 3. **文章/论文/其他**:360 图片搜索拿一张相关插图(国内可达);
/// 4. 都失败且用户打开了 **AI 生图**(默认关,按张计费) → 火山方舟 Seedream 生成;
/// 5. 仍然没有 → 程序化封面(现在的浅色印刷封面)。
///
/// 关键工程决策:
/// - **落盘缓存**:抓到/生成完的图下载成本地文件,按材料 key 永久缓存 ——
///   既避免每次滚列表都联网,也绕开图床防盗链/Referer 限制;
/// - **失败静默**:任何一步失败都返回 null,界面继续用程序化封面,绝不白块/转圈;
/// - **限并发**:同一材料只跑一次(去重),全局最多 [maxConcurrent] 个任务;
/// - **可关**:设置里能整个关掉,或只关"抓不到时 AI 生成"。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';
import 'api_endpoint.dart';
import 'doubao_api.dart';

/// 配图策略(设置项)。
enum CoverArtMode {
  /// 只抓取(免费,默认)
  crawl,

  /// 抓取失败时用 AI 生图兜底(按张计费,默认关闭)
  crawlThenAi,

  /// 完全关闭
  off,
}

class MaterialArt {
  MaterialArt._();

  /// Hive 键:配图策略(存 [CoverArtMode].name)
  static const String settingKey = 'material_art_mode';

  static const int maxConcurrent = 3;
  static int _running = 0;
  static final Map<String, Future<File?>> _inflight = <String, Future<File?>>{};
  static String? _dirPath;

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 25),
    followRedirects: true,
    maxRedirects: 3,
    headers: <String, String>{'User-Agent': _ua},
  ));

  // ── 设置 ────────────────────────────────────────────────────────────

  static CoverArtMode get mode {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings)
          .get(settingKey, defaultValue: CoverArtMode.crawl.name);
      for (final m in CoverArtMode.values) {
        if (m.name == raw) return m;
      }
    } catch (_) {
      // Hive 未就绪(测试/启动早期):按默认策略,不炸
    }
    return CoverArtMode.crawl;
  }

  static Future<void> setMode(CoverArtMode mode) async {
    try {
      await Hive.box(AppConstants.hiveBoxSettings).put(settingKey, mode.name);
    } catch (_) {
      // 保存失败不阻断界面
    }
  }

  /// AI 生图是否可用:方舟端点 + 有 Key(DeepSeek 官方无生图能力)
  static bool get aiAvailable {
    try {
      final cfg = ApiEndpointConfig.primary;
      if (!cfg.isConfigured) return false;
      return cfg.baseUrl.contains('volces.com');
    } catch (_) {
      // Hive 未就绪(启动早期/测试):一律视为不可用,绝不因此抛异常
      return false;
    }
  }

  // ── 缓存 ────────────────────────────────────────────────────────────

  /// 材料标识 → 稳定文件名(标题相同 = 同一张图;换版本会重新抓)
  static String cacheName({required String title, String kind = 'article'}) {
    var h = 2166136261;
    for (final r in '${kind.trim()}|${title.trim()}'.runes) {
      h ^= r;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return 'matart_${h.toRadixString(16)}.jpg';
  }

  static Future<Directory?> _dir() async {
    if (_dirPath != null) return Directory(_dirPath!)..createSync(recursive: true);
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}${Platform.pathSeparator}material_art');
      d.createSync(recursive: true);
      _dirPath = d.path;
      return d;
    } catch (_) {
      return null;
    }
  }

  /// 已缓存的图(不联网)
  static Future<File?> cached({required String title, String kind = 'article'}) async {
    final dir = await _dir();
    if (dir == null) return null;
    final f = File('${dir.path}${Platform.pathSeparator}${cacheName(title: title, kind: kind)}');
    return f.existsSync() ? f : null;
  }

  // ── 主入口 ──────────────────────────────────────────────────────────

  /// 给材料找一张自己的图;失败返回 null(界面继续用程序化封面)。
  ///
  /// [sourceUrl] 只用于日志/判断(不重复抓已入库的图);[author] 提高书封命中率。
  static Future<File?> resolve({
    required String title,
    String kind = 'article',
    String? author,
  }) {
    if (title.trim().isEmpty) return Future<File?>.value();
    if (mode == CoverArtMode.off) return Future<File?>.value();
    return _inflight.putIfAbsent(
      cacheName(title: title, kind: kind),
      () => _resolve(title: title, kind: kind, author: author)
          .whenComplete(() => _inflight.remove(cacheName(title: title, kind: kind))),
    );
  }

  static Future<File?> _resolve({
    required String title,
    required String kind,
    String? author,
  }) async {
    final existing = await cached(title: title, kind: kind);
    if (existing != null) return existing;
    if (_running >= maxConcurrent) return null; // 队列满了:本帧不抢网络
    _running++;
    try {
      // ① 书:豆瓣书封(国内可达,命中率最高)
      if (_isBookish(kind, title)) {
        final f = await _fromDouban(title: title, author: author);
        if (f != null) return f;
      }
      // ② 其他:360 图片搜索(国内可达)
      final f2 = await _from360(title: title, kind: kind);
      if (f2 != null) return f2;
      // ③ AI 生图兜底(用户显式开启 + 方舟可用)
      if (mode == CoverArtMode.crawlThenAi && aiAvailable) {
        return _fromAi(title: title, kind: kind);
      }
      return null;
    } finally {
      _running--;
    }
  }

  static bool _isBookish(String kind, String title) {
    if (kind == 'book') return true;
    // 公版书/AI 生成的文章之外,长标题也常是书名;这里只做保守判断
    return kind == 'article' && title.runes.length <= 28 &&
        !RegExp(r'[。!?]').hasMatch(title);
  }

  // ── 豆瓣书封 ────────────────────────────────────────────────────────

  static String doubanSearchUrl(String title) =>
      'https://book.douban.com/j/subject_suggest?q=${Uri.encodeQueryComponent(title)}';

  /// 从豆瓣联想接口的 JSON 里取第一张封面图(纯函数,便于单测)
  static String? firstDoubanCover(String? json) {
    if (json == null || json.trim().isEmpty) return null;
    try {
      final data = jsonDecode(json);
      if (data is! List) return null;
      for (final item in data) {
        if (item is Map && item['type'] == 'b') {
          final pic = '${item['pic'] ?? ''}'.trim();
          if (pic.startsWith('https://') || pic.startsWith('http://')) {
            return _upgradeDoubanCover(pic);
          }
        }
      }
    } catch (_) {
      // 脏数据/风控页:当作没找到
    }
    return null;
  }

  /// 豆瓣图床的小图路径 `/s/public/` → 大图 `/l/public/`(实测都返回同一张,
  /// 但 l 是官方大图档;拿不到时调用方会退回原 URL)
  static String _upgradeDoubanCover(String url) =>
      url.replaceFirst('/s/public/', '/l/public/');

  static Future<File?> _fromDouban({required String title, String? author}) async {
    try {
      final resp = await _dio.get<String>(
        doubanSearchUrl(title),
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, String>{'Referer': 'https://book.douban.com/'},
        ),
      );
      final pic = firstDoubanCover(resp.data);
      if (pic == null) return null;
      return await _download(
        pic,
        title: title,
        kind: 'book',
        headers: <String, String>{'Referer': 'https://book.douban.com/'},
      );
    } catch (_) {
      return null;
    }
  }

  // ── 360 图片搜索(文章/论文/其他) ─────────────────────────────────

  static String so360SearchUrl(String query) =>
      'https://image.so.com/j?q=${Uri.encodeQueryComponent(query)}'
      '&src=srp&sn=0&pn=8';

  /// 从 360 图片搜索 JSON 里取**候选图**(纯函数,按优先级排好)。
  ///
  /// 实测(2026-11,用户网络):`img` 指向的原图常被源站防盗链(下载回来是
  /// 几百字节的拦截页),`thumb` 所在的 360 图床(qhimgs1)稳定可达 ——
  /// 所以候选顺序是 img → thumb_bak → thumb,由下载层的"必须是真图片且
  /// ≥2KB"把拦截页筛掉,自动落到下一张。
  /// 宽度 <480 的图直接跳过(封面/头图会放大显示,太糊不如程序化封面)。
  static List<String> so360ImageCandidates(String? json) {
    final out = <String>[];
    if (json == null || json.trim().isEmpty) return out;
    try {
      final data = jsonDecode(json);
      if (data is! Map) return out;
      final list = data['list'];
      if (list is! List) return out;
      for (final item in list) {
        if (item is! Map) continue;
        final w = int.tryParse('${item['width'] ?? ''}') ?? 0;
        if (w > 0 && w < 480) continue;
        for (final key in <String>['img', 'thumb_bak', 'thumb']) {
          final u = '${item[key] ?? ''}'.trim();
          if ((u.startsWith('https://') || u.startsWith('http://')) &&
              !out.contains(u)) {
            out.add(u);
          }
        }
      }
    } catch (_) {
      // 风控/空数据:当作没找到
    }
    return out;
  }

  /// 取第一张可用图(兼容旧入口;内部按候选顺序试下载)
  static String? firstSo360Image(String? json) {
    final list = so360ImageCandidates(json);
    return list.isEmpty ? null : list.first;
  }

  static Future<File?> _from360({required String title, required String kind}) async {
    try {
      final query = _searchQuery(title: title, kind: kind);
      final resp = await _dio.get<String>(
        so360SearchUrl(query),
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, String>{'Referer': 'https://image.so.com/'},
        ),
      );
      for (final url in so360ImageCandidates(resp.data)) {
        final f = await _download(
          url,
          title: title,
          kind: kind,
          headers: <String, String>{'Referer': 'https://image.so.com/'},
        );
        if (f != null) return f;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 搜索词:去掉书名号/序号,书加"封面",其他类型加"插图"提高命中质量。
  static String _searchQuery({required String title, required String kind}) {
    var t = title
        .replaceAll(RegExp(r'[《》〈〉「」『』【】]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isEmpty) t = title;
    return switch (kind) {
      'book' => '$t 封面',
      'news' => '$t 新闻 图片',
      'paper' => '$t 科学 图解',
      'podcast' => '$t 播客 封面',
      'wiki' => t,
      _ => '$t 插图',
    };
  }

  // ── 下载与落盘 ──────────────────────────────────────────────────────

  static const int _maxBytes = 6 * 1024 * 1024;

  static Future<File?> _download(
    String url, {
    required String title,
    required String kind,
    Map<String, String>? headers,
  }) async {
    try {
      final resp = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          validateStatus: (c) => c != null && c >= 200 && c < 300,
        ),
      );
      final bytes = resp.data;
      if (bytes == null || bytes.length < 2048) return null;
      if (bytes.length > _maxBytes) return null;
      // 基础格式校验:JPEG/PNG/WebP 才落盘(防止风控页/HTML 被当图缓存)
      if (!_looksLikeImage(bytes)) return null;
      final dir = await _dir();
      if (dir == null) return null;
      final f = File('${dir.path}${Platform.pathSeparator}${cacheName(title: title, kind: kind)}');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
      return f;
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeImage(List<int> b) {
    if (b.length < 12) return false;
    final jpeg = b[0] == 0xFF && b[1] == 0xD8;
    final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    final webp = b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46;
    return jpeg || png || webp;
  }

  // ── AI 生图兜底(火山方舟 Seedream,按张计费) ─────────────────────

  /// 候选模型:优先用户账号 /models 里真实存在的 seedream,再退到已知型号
  static List<String> aiModelCandidates() {
    final out = <String>[];
    final discovered = DoubaoApiService.lastModels;
    if (discovered != null) {
      for (final m in discovered) {
        if (m.toLowerCase().contains('seedream')) out.add(m);
      }
    }
    for (final m in const <String>[
      'doubao-seedream-4-0-250828',
      'doubao-seedream-3-0-t2i-250415',
    ]) {
      if (!out.contains(m)) out.add(m);
    }
    return out;
  }

  /// 生图提示词(纯函数):**不要文字/字母**,统一到 App 的糖果纸面气质
  static String aiPrompt({required String title, required String kind}) {
    final type = switch (kind) {
      'book' => '公版书/图书',
      'news' => '外刊新闻',
      'paper' => '学术论文',
      'podcast' => '播客',
      'wiki' => '百科词条',
      _ => '英语学习文章',
    };
    return '为「$title」($type)生成一张封面插图。'
        '风格:现代编辑插画,柔和的糖果色调(薰衣草紫/蜜桃粉/薄荷绿/天蓝),'
        '干净留白,几何化纸感,像一本精致的杂志封面;'
        '画面中不要出现任何文字、字母、数字、logo、水印;'
        '不要照片写实,不要高对比霓虹色;横向构图,主体偏右,左侧留出标题空间。';
  }

  static Future<File?> _fromAi({required String title, required String kind}) async {
    final cfg = ApiEndpointConfig.primary;
    final key = cfg.apiKey;
    if (key == null || key.isEmpty) return null;
    for (final model in aiModelCandidates()) {
      try {
        final resp = await _dio.post<Map<String, dynamic>>(
          '${cfg.baseUrl}/images/generations',
          options: Options(
            responseType: ResponseType.json,
            headers: <String, String>{'Authorization': 'Bearer $key'},
          ),
          data: <String, dynamic>{
            'model': model,
            'prompt': aiPrompt(title: title, kind: kind),
            'size': '1024x576',
            'response_format': 'url',
            'watermark': false,
          },
        );
        final url = firstAiImageUrl(resp.data);
        if (url == null) continue;
        final f = await _download(url, title: title, kind: kind);
        if (f != null) return f;
      } catch (_) {
        // 模型不存在/未开通/风控:换下一个候选,全部失败就静默回落
        continue;
      }
    }
    return null;
  }

  /// 从方舟生图响应里取第一张图 URL(纯函数)
  static String? firstAiImageUrl(Map<String, dynamic>? json) {
    if (json == null) return null;
    final data = json['data'];
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    if (first is! Map) return null;
    final u = '${first['url'] ?? ''}'.trim();
    if (u.startsWith('https://') || u.startsWith('http://')) return u;
    // 部分端点返回 b64_json:交给上层忽略(不支持 b64 落盘,保持简单)
    return null;
  }
}
