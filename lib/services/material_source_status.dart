import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';

/// 单个内容源的"最近一次可用性"
class SourceHealth {
  /// 最近一次是否成功
  final bool ok;

  /// 最近一次发生时间
  final DateTime at;

  /// 失败原因(截断后的可读文案);成功时为 null
  final String? message;

  const SourceHealth({required this.ok, required this.at, this.message});

  Map<String, Object?> toJson() => {
        'ok': ok,
        'at': at.toIso8601String(),
        if (message != null) 'msg': message,
      };

  /// 坏数据一律当"没记录"(返回 null),不要让一条脏 JSON 把整页打成白屏
  static SourceHealth? parse(Object? raw) {
    if (raw is! Map) return null;
    final ok = raw['ok'];
    final at = DateTime.tryParse('${raw['at'] ?? ''}');
    if (ok is! bool || at == null) return null;
    return SourceHealth(
      ok: ok,
      at: at,
      message: raw['msg'] == null ? null : '${raw['msg']}',
    );
  }

  /// 人话状态(给 chip / 说明行用)
  String label(DateTime now) {
    final age = now.difference(at);
    final when = age.inMinutes < 1
        ? '刚刚'
        : age.inMinutes < 60
            ? '${age.inMinutes} 分钟前'
            : age.inHours < 24
                ? '${age.inHours} 小时前'
                : '${age.inDays} 天前';
    return ok ? '最近可用 · $when' : '上次失败 · $when';
  }
}

/// 内容源可用性记忆(v2.2 修"材料中心没法用")。
///
/// 为什么需要它:公开源在不同网络下的可达性差别极大 —— 实测(2026-09-24,
/// 中国大陆家庭宽带)BBC Learning English / VOA / TED / Wikipedia **全部超时**,
/// 而 NPR(2.7s)/ arXiv(0.9s)/ Project Gutenberg(26s,首包慢)可用。
/// 旧实现默认选中列表第一个源(BBC),于是用户打开材料中心看到的**第一屏
/// 必然是失败** —— 这不是网络问题,是默认值选错了。
///
/// 现在:
/// 1. 默认源改成实测可用的 NPR([MaterialSourceService.defaultSourceId]);
/// 2. 每次成功/失败都记下来,下次**优先落到上次成功过的源**;
/// 3. 记录只存在本机(含时间与原因),用来在界面上如实标注"这个源在你这儿
///    上次是超时",而不是让用户一个个点着试。
class MaterialSourceStatus {
  MaterialSourceStatus._();

  /// 一条记录最多留多少字:失败原因可能很长(HTML 错误页),界面上放不下
  static const int maxMessageLength = 120;

  static Map<String, SourceHealth> loadAll() {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings)
          .get(AppConstants.keyMaterialSourceStatus);
      if (raw is! String || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, SourceHealth>{};
      decoded.forEach((k, v) {
        final health = SourceHealth.parse(v);
        if (health != null) out['$k'] = health;
      });
      return out;
    } catch (e) {
      debugPrint('ReadFlow 读取内容源状态失败(当没有记录): $e');
      return {};
    }
  }

  static SourceHealth? of(String sourceId, [Map<String, SourceHealth>? all]) =>
      (all ?? loadAll())[sourceId];

  /// 上次成功过的源 → 没有就退回默认源。
  /// 只在**明确成功过**的源里挑,避免把"从没试过"当可用。
  static String preferredSourceId({
    required List<String> knownIds,
    required String fallback,
    Map<String, SourceHealth>? all,
  }) {
    final state = all ?? loadAll();
    final okOnes = state.entries.where((e) => e.value.ok).toList()
      ..sort((a, b) => b.value.at.compareTo(a.value.at));
    for (final e in okOnes) {
      if (knownIds.contains(e.key)) return e.key;
    }
    return fallback;
  }

  static Future<void> recordOk(String sourceId, {DateTime? at}) =>
      _write(sourceId, SourceHealth(ok: true, at: at ?? DateTime.now()));

  static Future<void> recordFail(
    String sourceId,
    Object error, {
    DateTime? at,
  }) =>
      _write(
        sourceId,
        SourceHealth(
          ok: false,
          at: at ?? DateTime.now(),
          message: shorten('$error'),
        ),
      );

  /// 失败原因截断(HTML 错误页/超长异常都是常见来源)
  static String shorten(String message) {
    final flat = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= maxMessageLength) return flat;
    return '${flat.substring(0, maxMessageLength)}…';
  }

  static Future<void> _write(String sourceId, SourceHealth health) async {
    try {
      final all = loadAll()..[sourceId] = health;
      final encoded = jsonEncode({
        for (final e in all.entries) e.key: e.value.toJson(),
      });
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyMaterialSourceStatus, encoded);
    } catch (e) {
      // 记不住不影响本次使用(下次重试即可),不能因为写 KV 失败打断抓取流程
      debugPrint('ReadFlow 保存内容源状态失败: $e');
    }
  }
}
