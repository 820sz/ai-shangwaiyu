import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';

/// 「我的」个性化名片设置(v2.8,用户第 9 条)。
///
/// 用户原话:"'我的'界面,在顶部增加个性化名片 —— 头像自定义、名片背景自定义、
/// 签名自定义、词汇量展示"。
///
/// 设计取舍:
/// - **头像两种都支持**:相册选一张真图(复制进 App 目录,不依赖原图还在不在),
///   或者选一个自带的文字/emoji 头像 —— 不是每个人都愿意放照片;
/// - **背景只给 6 套渐变**而不是任意取色:任意取色很容易做出"看不清字"的组合,
///   渐变盘是挑过的,深浅色模式下都有足够对比度;
/// - 全部落在 Hive(字符串 + 路径),坏数据一律回落默认值(名片不能把「我的」打崩)。
class ProfileCardSettings {
  /// 头像图片路径(复制到 App 目录后的绝对路径;为空则用 [avatarText])
  final String? avatarPath;

  /// 文字头像(单字/emoji,如 "樱"、"🦊");图片为空时用它
  final String avatarText;

  /// 背景 id(见 [backgrounds])
  final String backgroundId;

  /// 个性签名
  final String signature;

  const ProfileCardSettings({
    this.avatarPath,
    this.avatarText = '',
    this.backgroundId = 'dawn',
    this.signature = '',
  });

  static const ProfileCardSettings defaults = ProfileCardSettings();

  /// 背景盘(挑过的 6 套渐变:名字 → 两个色值)
  static const List<Map<String, Object>> backgrounds = [
    {'id': 'dawn', 'label': '拂晓', 'colors': [0xFF2F4A6D, 0xFF5B7FA6]},
    {'id': 'moss', 'label': '苔原', 'colors': [0xFF3F5A47, 0xFF6E8F72]},
    {'id': 'clay', 'label': '陶土', 'colors': [0xFF6A4A3C, 0xFFA6785E]},
    {'id': 'iris', 'label': '鸢尾', 'colors': [0xFF4A3F63, 0xFF7E6FA3]},
    {'id': 'ink', 'label': '石墨', 'colors': [0xFF37474F, 0xFF6B8A96]},
    {'id': 'rose', 'label': '玫瑰', 'colors': [0xFF6B4A55, 0xFFA3768A]},
  ];

  static Map<String, Object> backgroundOf(String id) =>
      backgrounds.firstWhere(
        (b) => b['id'] == id,
        orElse: () => backgrounds.first,
      );

  /// 头像候选(不想放照片时的文字/emoji 头像)
  static const List<String> avatarTexts = [
    '樱', '読', '🦊', '🐱', '🐼', '📚', '🌱', '⭐', '🧠', '☕',
  ];

  ProfileCardSettings copyWith({
    Object? avatarPath = _sentinel,
    String? avatarText,
    String? backgroundId,
    String? signature,
  }) =>
      ProfileCardSettings(
        avatarPath:
            identical(avatarPath, _sentinel) ? this.avatarPath : avatarPath as String?,
        avatarText: avatarText ?? this.avatarText,
        backgroundId: backgroundId ?? this.backgroundId,
        signature: signature ?? this.signature,
      );

  static const Object _sentinel = Object();

  Map<String, Object?> toJson() => {
        'avatar_path': avatarPath,
        'avatar_text': avatarText,
        'background': backgroundId,
        'signature': signature,
      };

  /// 坏数据一律回落默认(名片只是装饰,不能把「我的」打崩)
  static ProfileCardSettings fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    try {
      final bg = '${raw['background'] ?? 'dawn'}';
      final path = '${raw['avatar_path'] ?? ''}'.trim();
      return ProfileCardSettings(
        avatarPath: path.isEmpty ? null : path,
        avatarText: '${raw['avatar_text'] ?? ''}',
        backgroundId: backgrounds.any((b) => b['id'] == bg) ? bg : 'dawn',
        signature: '${raw['signature'] ?? ''}',
      );
    } catch (e) {
      debugPrint('ReadFlow 读取名片设置失败(用默认): $e');
      return defaults;
    }
  }

  static ProfileCardSettings load() {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings)
          .get(AppConstants.keyProfileCard);
      if (raw is String && raw.trim().isNotEmpty) {
        return fromJson(_decode(raw));
      }
      if (raw is Map) return fromJson(raw);
    } catch (e) {
      debugPrint('ReadFlow 读取名片设置失败(用默认): $e');
    }
    return defaults;
  }

  Future<void> save() async {
    try {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyProfileCard, _encode(toJson()));
    } catch (e) {
      debugPrint('ReadFlow 保存名片设置失败: $e');
    }
  }

  /// 把用户选的图片**复制进 App 目录**再记录路径。
  ///
  /// 为什么必须复制:相册里那张图随时可能被用户删掉/移动,`XFile.path` 是临时缓存
  /// 或外部存储路径 —— 只记路径的名片过几天就变白块。
  static Future<String?> persistAvatar(File src) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = p.extension(src.path);
      final target = File(
        p.join(dir.path, 'avatar${ext.isEmpty ? '.jpg' : ext}'),
      );
      await src.copy(target.path);
      return target.path;
    } catch (e) {
      debugPrint('ReadFlow 保存头像失败: $e');
      return null;
    }
  }

  static String _encode(Map<String, Object?> m) {
    final parts = m.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${Uri.encodeComponent('${e.value}')}')
        .join('&');
    return parts;
  }

  static Map<String, Object?> _decode(String s) {
    final out = <String, Object?>{};
    for (final kv in s.split('&')) {
      final i = kv.indexOf('=');
      if (i <= 0) continue;
      out[kv.substring(0, i)] = Uri.decodeComponent(kv.substring(i + 1));
    }
    return out;
  }
}
