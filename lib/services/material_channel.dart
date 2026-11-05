import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import 'material_taxonomy.dart';

/// 材料中心「方案 2 · 频道化」里的一个频道(一个入口 = 一个频道)。
///
/// 为什么把 id 与展示信息绑成一个值对象:快照按 id 存 Hive,UI 每次重进频道页
/// 必须拼出**同一个 id** 才能读到上次结果;id 的拼法一旦散落在各页面各写一份,
/// 迟早出现"页面之间差一个子分类,快照再也读不回来"的漂移。
class MaterialChannel {
  /// 稳定 id,形如 `topic:tech,business`(方向 + 子分类/需求摘要)
  final String id;

  /// 展示标题,形如 `按题材 · 科技`
  final String title;

  /// 所属大方向
  final MaterialDirection direction;

  /// 选中的子分类 id(按题材/形式/场景频道用)
  final List<String> subtopicIds;

  /// 检索词(中英混合,来自 taxonomy / 按需求)
  final List<String> queries;

  /// 中文需求描述(给 AI plan 用;按需求频道才有内容)
  final String needText;

  const MaterialChannel({
    required this.id,
    required this.title,
    required this.direction,
    this.subtopicIds = const <String>[],
    this.queries = const <String>[],
    this.needText = '',
  });
}

/// 一次"按频道找材料"的结果快照(只存卡片要用的摘要,**不存正文**)。
///
/// 不存正文的原因:正文动辄几十 KB/篇,一频道几十条会把 settings box 撑大,
/// 且快照的用途只是"下次进频道先显示上次结果",点开时再按 url 抓。
class ChannelRunSnapshot {
  /// 每条字段:title,url,sourceLabel,kind,snippet,imageUrl,authority,
  /// date(ISO8601 字符串),fromSearchApi
  final List<Map<String, Object?>> items;

  /// 这次快照的更新时间(UI 用来显示"上次更新 · N 分钟前")
  final DateTime updatedAt;

  /// 累计官方搜索请求数(计费口径)
  final int apiRequests;

  /// 累计估算花费(人民币)
  final double costCny;

  /// 这几轮实际用到的检索词(去重后)
  final List<String> queriesUsed;

  const ChannelRunSnapshot({
    required this.items,
    required this.updatedAt,
    this.apiRequests = 0,
    this.costCny = 0,
    this.queriesUsed = const <String>[],
  });

  bool get isEmpty => items.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'items': items,
        'updated_at': updatedAt.toIso8601String(),
        'api_requests': apiRequests,
        'cost_cny': costCny,
        'queries_used': queriesUsed,
      };
}

/// URL 归一(去重键):小写、去协议、去 `utm_*` 跟踪参数、去锚点。
///
/// 为什么抽成纯函数:去重规则错一点,"继续找更多"就会把同一篇材料重复堆出来,
/// 而界面上看起来只是"又出现了",很难发现是去重键写错了。
String normalizedUrlKey(String raw) {
  var url = raw.trim().toLowerCase();
  if (url.isEmpty) return '';
  // 协议不参与身份比较:http/https 混用的同一篇文章是同一篇
  url = url.replaceFirst(RegExp(r'^[a-z][a-z0-9+.\-]*://'), '');
  // 锚点(#section)不改变内容,也去掉
  final hash = url.indexOf('#');
  if (hash >= 0) url = url.substring(0, hash);
  final q = url.indexOf('?');
  if (q < 0) return url;
  final path = url.substring(0, q);
  final kept = <String>[];
  for (final piece in url.substring(q + 1).split('&')) {
    if (piece.isEmpty) continue;
    final cut = piece.indexOf('=');
    final name = cut < 0 ? piece : piece.substring(0, cut);
    if (name.startsWith('utm_')) continue; // 跟踪参数纯噪声
    kept.add(piece);
  }
  return kept.isEmpty ? path : '$path?${kept.join('&')}';
}

/// 把候选 map 规整成**可 JSON 化、可入库**的规范 map(纯函数)。
///
/// - 只保留契约里的 9 个字段:正文/analysis/rerankScore 一概不存;
/// - 兼容 [DiscoveredCandidate.toMap] 的 snake_case 键(`source` / `image_url` /
///   `from_search_api`),这样 UI 不用手写一层转换;
/// - 没有 url 的条目没有打开价值,返回 null(调用方跳过);
/// - `date` 统一成 ISO8601 字符串(Hive 里只存字符串,读侧再容错解析)。
Map<String, Object?>? candidateJsonFromMap(Map<String, Object?> raw) {
  final url = _str(_pick(raw, const <String>['url', 'link']));
  if (url.isEmpty) return null;

  final title = _str(_pick(raw, const <String>['title', 'name']));
  final kind = _str(_pick(raw, const <String>['kind']));
  final image = _str(
    _pick(raw, const <String>['imageUrl', 'image_url', 'image', 'cover_url']),
  );
  return <String, Object?>{
    // 没有标题的卡片无法辨认,用 url 兜底(总比空标题强)
    'title': title.isEmpty ? url : title,
    'url': url,
    'sourceLabel': _str(
      _pick(
        raw,
        const <String>['sourceLabel', 'source_label', 'source', 'sourceName'],
      ),
    ),
    'kind': kind.isEmpty ? 'article' : kind,
    'snippet': _str(_pick(raw, const <String>['snippet', 'summary', 'note'])),
    'imageUrl': image.isEmpty ? null : image,
    'authority': _intOf(_pick(raw, const <String>['authority']), -1),
    'date': _isoDate(
      _pick(
        raw,
        const <String>['date', 'published_at', 'publish_date', 'pub_date'],
      ),
    ),
    'fromSearchApi': _boolOf(
      _pick(raw, const <String>['fromSearchApi', 'from_search_api']),
    ),
  };
}

/// 从存进 Hive 的 JSON 值还原规范候选 map(纯函数,脏数据返回 null 不抛)。
Map<String, Object?>? candidateMapFromJson(Object? raw) {
  Object? decoded = raw;
  if (decoded is String) {
    if (decoded.trim().isEmpty) return null;
    try {
      decoded = jsonDecode(decoded);
    } catch (_) {
      return null;
    }
  }
  if (decoded is! Map) return null;
  final map = <String, Object?>{};
  decoded.forEach((key, value) => map['$key'] = value);
  return candidateJsonFromMap(map);
}

/// 从 Hive 里的快照 JSON 还原 [ChannelRunSnapshot](纯函数)。
///
/// 容错口径:脏数据一律返回 null / 跳过坏条目,**绝不抛** —— 一条坏快照不该让
/// 用户打开频道页就白屏,最差也只是回到"没有上次结果"。
ChannelRunSnapshot? channelSnapshotFromJson(Object? raw) {
  try {
    Object? decoded = raw;
    if (decoded is String) {
      if (decoded.trim().isEmpty) return null;
      decoded = jsonDecode(decoded);
    }
    if (decoded is! Map) return null;
    final map = <String, Object?>{};
    decoded.forEach((key, value) => map['$key'] = value);

    final updatedAt = DateTime.tryParse(
      _str(_pick(map, const <String>['updated_at', 'updatedAt'])),
    );
    // 没有有效更新时间,快照无法排序/展示,直接当没有
    if (updatedAt == null) return null;

    final items = <Map<String, Object?>>[];
    final rawItems = _pick(map, const <String>['items']);
    if (rawItems is List) {
      for (final entry in rawItems) {
        final candidate = candidateMapFromJson(entry);
        if (candidate != null) items.add(candidate);
      }
    }
    return ChannelRunSnapshot(
      items: items,
      updatedAt: updatedAt,
      apiRequests: _intOf(_pick(map, const <String>['api_requests', 'apiRequests']), 0),
      costCny: _doubleOf(_pick(map, const <String>['cost_cny', 'costCny'])),
      queriesUsed: _stringListOf(
        _pick(map, const <String>['queries_used', 'queriesUsed']),
      ),
    );
  } catch (e) {
    debugPrint('ReadFlow 解析频道快照失败(当没有快照): $e');
    return null;
  }
}

/// 频道快照 + "保存到我的"关系的本地持久化(方案 2 的持久化层)。
///
/// 两套数据分开存:
/// - 快照(`material_channel_<channelId>`):发现 Tab 的上次结果,可清可刷新;
/// - 保存关系(`material_channel_<channelId>@@saved`):我的 Tab 里"这个频道保存
///   过哪些材料",只增删关系,材料本体在 SQLite。
///
/// 为什么关系不放进快照:清空发现快照("这次结果不要了")时用户没想到会一起丢掉
/// 自己保存过的材料,分开存才能让 [clearSnapshot] 只清发现区。
class MaterialChannelStore {
  MaterialChannelStore._();

  /// 所有本 store 的 Hive key 前缀(测试清理/诊断用)
  static const String boxKeyPrefix = 'material_channel_';

  /// 保存关系的 key 后缀(用 `@@` 避免与频道 id 本身拼出的 key 冲突)
  static const String _savedSuffix = '@@saved';
  static const String _hiddenSuffix = '@@hidden';

  static Box get _box => Hive.box(AppConstants.hiveBoxSettings);

  static String _snapshotKey(String channelId) => '$boxKeyPrefix$channelId';

  static String _savedKey(String channelId) =>
      '$boxKeyPrefix$channelId$_savedSuffix';

  static String _hiddenKey(String channelId) =>
      '$boxKeyPrefix$channelId$_hiddenSuffix';

  /// 读某个频道的上次发现结果;没有/脏数据 → null(不抛)。
  static Future<ChannelRunSnapshot?> loadSnapshot(String channelId) async {
    try {
      final raw = _box.get(_snapshotKey(channelId));
      if (raw == null) return null;
      return channelSnapshotFromJson(raw);
    } catch (e) {
      debugPrint('ReadFlow 读取频道快照失败($channelId): $e');
      return null;
    }
  }

  /// 存一次发现结果。
  ///
  /// [append] = true 用于「继续找更多」:旧条目原序保留,新条目按 URL 归一后
  /// 追加(重复的丢弃),累计 apiRequests / costCny,合并 queriesUsed。
  /// [append] = false 用于「重新找」:整体替换。
  static Future<void> saveRun(
    String channelId, {
    required List<Map<String, Object?>> items,
    required int apiRequests,
    required double costCny,
    required List<String> queriesUsed,
    bool append = false,
  }) async {
    try {
      final incoming = _normalizeItems(items);
      final ChannelRunSnapshot snapshot;
      if (append) {
        final old = await loadSnapshot(channelId);
        final merged = <Map<String, Object?>>[];
        final seen = <String>{};
        // 旧条目先占位:UI 按"上次看到的顺序"渲染,追加不能把老结果顶乱
        for (final item in old?.items ?? const <Map<String, Object?>>[]) {
          final key = normalizedUrlKey(_str(item['url']));
          if (key.isNotEmpty && !seen.add(key)) continue;
          merged.add(item);
        }
        for (final item in incoming) {
          final key = normalizedUrlKey(_str(item['url']));
          if (key.isNotEmpty && !seen.add(key)) continue;
          merged.add(item);
        }
        snapshot = ChannelRunSnapshot(
          items: merged,
          updatedAt: DateTime.now(),
          apiRequests: (old?.apiRequests ?? 0) + apiRequests,
          costCny: (old?.costCny ?? 0) + costCny,
          queriesUsed: _mergeQueries(
            old?.queriesUsed ?? const <String>[],
            queriesUsed,
          ),
        );
      } else {
        snapshot = ChannelRunSnapshot(
          items: incoming,
          updatedAt: DateTime.now(),
          apiRequests: apiRequests,
          costCny: costCny,
          queriesUsed: _mergeQueries(const <String>[], queriesUsed),
        );
      }
      await _box.put(_snapshotKey(channelId), jsonEncode(snapshot.toJson()));
    } catch (e) {
      // 存不上最多是"下次要重搜",不能把这次已经拿到的结果页打断
      debugPrint('ReadFlow 保存频道快照失败($channelId): $e');
    }
  }

  /// 清掉某个频道的发现快照;已保存的材料关系**保留**(见类注释)。
  static Future<void> clearSnapshot(String channelId) async {
    try {
      await _box.delete(_snapshotKey(channelId));
    } catch (e) {
      debugPrint('ReadFlow 清理频道快照失败($channelId): $e');
    }
  }

  /// 某频道"保存到我的"材料 id 集合。
  ///
  /// 返回 String 是契约定的(UI 侧用 `contains('$materialId')` 判断是否已保存),
  /// 存储内部仍按 int 存,读的时候容错(脏值跳过)。
  static Future<Set<String>> savedMaterialIds(String channelId) async {
    try {
      final raw = _box.get(_savedKey(channelId));
      final ids = _parseSavedIds(raw);
      return <String>{for (final id in ids) '$id'};
    } catch (e) {
      debugPrint('ReadFlow 读取频道保存关系失败($channelId): $e');
      return <String>{};
    }
  }

  /// 记一条"保存到我的"关系(重复保存是幂等的)。
  static Future<void> addSavedMaterial(String channelId, int materialId) async {
    await _mutateSaved(channelId, (ids) => ids..add(materialId));
  }

  /// 删一条"保存到我的"关系(不存在时无副作用)。
  static Future<void> removeSavedMaterial(
    String channelId,
    int materialId,
  ) async {
    await _mutateSaved(channelId, (ids) => ids..remove(materialId));
  }

  /// 某频道**被用户移除**的材料 id 集合(频道级持久隐藏,不删材料本体)。
  ///
  /// 为什么需要它:频道「我的」里除了显式保存的材料,还有按子分类旧逻辑匹配到的
  /// 历史材料。"从频道移除"如果只删保存关系,重进频道那些旧匹配项又会冒出来,
  /// 用户会觉得移除没生效(质检 P1-5)。
  static Future<Set<String>> hiddenMaterialIds(String channelId) async {
    try {
      final ids = _parseSavedIds(_box.get(_hiddenKey(channelId)));
      return <String>{for (final id in ids) '$id'};
    } catch (e) {
      debugPrint('ReadFlow 读取频道移除表失败($channelId): $e');
      return <String>{};
    }
  }

  /// 记一条"从频道移除"关系(重复移除幂等)。
  static Future<void> addHiddenMaterial(String channelId, int materialId) async {
    await _mutateHidden(channelId, (ids) => ids..add(materialId));
  }

  /// 取消"从频道移除"(重新保存/手动恢复时用)。
  static Future<void> removeHiddenMaterial(
    String channelId,
    int materialId,
  ) async {
    await _mutateHidden(channelId, (ids) => ids..remove(materialId));
  }

  /// 测试专用:清空本 store 的所有 key(快照 + 保存关系)。
  ///
  /// 只删 [boxKeyPrefix] 前缀的 key,不碰 settings box 里的其他设置。
  static Future<void> clearAllForTest() async {
    try {
      final box = _box;
      for (final key in box.keys.toList()) {
        if ('$key'.startsWith(boxKeyPrefix)) {
          await box.delete(key);
        }
      }
    } catch (e) {
      debugPrint('ReadFlow 清理频道测试数据失败: $e');
    }
  }

  static Future<void> _mutateSaved(
    String channelId,
    void Function(Set<int> ids) mutate,
  ) async {
    try {
      final ids = _parseSavedIds(_box.get(_savedKey(channelId)));
      mutate(ids);
      final sorted = ids.toList()..sort();
      await _box.put(_savedKey(channelId), jsonEncode(sorted));
    } catch (e) {
      debugPrint('ReadFlow 写入频道保存关系失败($channelId): $e');
    }
  }

  static Future<void> _mutateHidden(
    String channelId,
    void Function(Set<int> ids) mutate,
  ) async {
    try {
      final ids = _parseSavedIds(_box.get(_hiddenKey(channelId)));
      mutate(ids);
      final sorted = ids.toList()..sort();
      await _box.put(_hiddenKey(channelId), jsonEncode(sorted));
    } catch (e) {
      debugPrint('ReadFlow 写入频道移除表失败($channelId): $e');
    }
  }

  /// 规整 + 去重一次传入的候选(同一批里重复的 URL 只留第一条)。
  static List<Map<String, Object?>> _normalizeItems(
    Iterable<Map<String, Object?>> items,
  ) {
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final raw in items) {
      final candidate = candidateJsonFromMap(raw);
      if (candidate == null) continue;
      final key = normalizedUrlKey(_str(candidate['url']));
      if (!seen.add(key)) continue;
      out.add(candidate);
    }
    return out;
  }

  /// 检索词去重合并(保持出现顺序;空串跳过)。
  static List<String> _mergeQueries(
    List<String> old,
    Iterable<String> incoming,
  ) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in <String>[...old, ...incoming]) {
      final q = raw.trim();
      if (q.isEmpty || !seen.add(q)) continue;
      out.add(q);
    }
    return out;
  }

  /// 保存关系的容错解析:整串坏 → 空集合;坏元素跳过。
  static Set<int> _parseSavedIds(Object? raw) {
    Object? decoded = raw;
    if (decoded is String) {
      if (decoded.trim().isEmpty) return <int>{};
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return <int>{};
      }
    }
    if (decoded is! List) return <int>{};
    final out = <int>{};
    for (final entry in decoded) {
      if (entry is int) {
        out.add(entry);
      } else if (entry is num) {
        out.add(entry.toInt());
      } else {
        final parsed = int.tryParse('$entry'.trim());
        if (parsed != null) out.add(parsed);
      }
    }
    return out;
  }
}

Object? _pick(Map<String, Object?> raw, List<String> keys) {
  for (final key in keys) {
    final value = raw[key];
    if (value != null) return value;
  }
  return null;
}

String _str(Object? value) => value == null ? '' : '$value'.trim();

int _intOf(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? fallback;
}

double _doubleOf(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? 0;
}

bool _boolOf(Object? value) {
  if (value is bool) return value;
  final text = '${value ?? ''}'.toLowerCase();
  return text == 'true' || text == '1';
}

/// 日期统一成 ISO8601 字符串;解析不了就是 null(界面显示"未知日期")
String? _isoDate(Object? value) {
  if (value is DateTime) return value.toIso8601String();
  if (value == null) return null;
  return DateTime.tryParse('$value'.trim())?.toIso8601String();
}

List<String> _stringListOf(Object? value) {
  if (value is! List) return const <String>[];
  // 去重:queriesUsed 的语义是"这几轮实际用到哪些检索词",重复项没有信息量
  final out = <String>[];
  final seen = <String>{};
  for (final entry in value) {
    if (entry == null) continue;
    final text = '$entry'.trim();
    if (text.isEmpty || !seen.add(text)) continue;
    out.add(text);
  }
  return out;
}
