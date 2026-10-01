import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';

/// 「我的」个性化名片设置(v2.8 初版;v2.9 按用户反馈大改)。
///
/// v2.8 用户原话:"'我的'界面,在顶部增加个性化名片 —— 头像自定义、名片背景自定义、
/// 签名自定义、词汇量展示"。
///
/// v2.9 用户反馈:"**'我的'的用户名片没法编辑调整背景图,头像也是。没法自定义用户名字。
/// 个性卡片整体的 ui 风要再精美优化一些。**"
/// 于是补上三样:
/// - **昵称**(v2.8 根本没有这个字段 —— 名片上没有名字,用户当然觉得"没法自定义");
/// - **背景图**(除了 6 套渐变,还能从相册选一张图,自动压暗保证白字可读);
/// - 编辑入口从"卡片角落一个小铅笔"改成**整卡可点 + 醒目的「编辑名片」按钮**。
class ProfileCardSettings {
  /// 头像图片路径(复制到 App 目录后的绝对路径;为空则用 [avatarText])
  final String? avatarPath;

  /// 文字头像(单字/emoji,如 "樱"、"🦊");图片为空时用它
  final String avatarText;

  /// 背景 id(见 [backgrounds]);[backgroundPath] 有值时优先用它
  final String backgroundId;

  /// 背景图片路径(用户自选;优先于 [backgroundId])
  final String? backgroundPath;

  /// 个性签名
  final String signature;

  /// 昵称(v2.9:用户点名要能自定义名字)
  final String nickname;

  const ProfileCardSettings({
    this.avatarPath,
    this.avatarText = '',
    this.backgroundId = 'dawn',
    this.backgroundPath,
    this.signature = '',
    this.nickname = '',
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
    Object? backgroundPath = _sentinel,
    String? avatarText,
    String? backgroundId,
    String? signature,
    String? nickname,
  }) =>
      ProfileCardSettings(
        avatarPath:
            identical(avatarPath, _sentinel) ? this.avatarPath : avatarPath as String?,
        backgroundPath: identical(backgroundPath, _sentinel)
            ? this.backgroundPath
            : backgroundPath as String?,
        avatarText: avatarText ?? this.avatarText,
        backgroundId: backgroundId ?? this.backgroundId,
        signature: signature ?? this.signature,
        nickname: nickname ?? this.nickname,
      );

  static const Object _sentinel = Object();

  Map<String, Object?> toJson() => {
        'avatar_path': avatarPath,
        'avatar_text': avatarText,
        'background': backgroundId,
        'background_path': backgroundPath,
        'signature': signature,
        'nickname': nickname,
      };

  /// 坏数据一律回落默认(名片只是装饰,不能把「我的」打崩)
  static ProfileCardSettings fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    try {
      final bg = '${raw['background'] ?? 'dawn'}';
      final path = '${raw['avatar_path'] ?? ''}'.trim();
      final bgPath = '${raw['background_path'] ?? ''}'.trim();
      return ProfileCardSettings(
        avatarPath: path.isEmpty ? null : path,
        backgroundPath: bgPath.isEmpty ? null : bgPath,
        avatarText: '${raw['avatar_text'] ?? ''}',
        backgroundId: backgrounds.any((b) => b['id'] == bg) ? bg : 'dawn',
        signature: '${raw['signature'] ?? ''}',
        nickname: '${raw['nickname'] ?? ''}',
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
  ///
  /// [prefix] 用来区分头像与背景图(各自只保留一张,重复选不会越攒越多)。
  static Future<String?> persistImage(File src, {String prefix = 'avatar'}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = p.extension(src.path);
      final target = File(
        p.join(dir.path, '$prefix${ext.isEmpty ? '.jpg' : ext}'),
      );
      await src.copy(target.path);
      return target.path;
    } catch (e) {
      debugPrint('ReadFlow 保存图片失败: $e');
      return null;
    }
  }

  /// 兼容旧调用(头像)
  static Future<String?> persistAvatar(File src) =>
      persistImage(src, prefix: 'avatar');

  /// 名片上的名字:昵称 → 默认("我")
  String get displayName => nickname.trim().isEmpty ? '我' : nickname.trim();

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
