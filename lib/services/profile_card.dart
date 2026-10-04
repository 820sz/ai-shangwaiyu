import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';

/// 「我的」个性化名片设置(v2.8 初版;v2.9 按用户反馈大改;v2.10 补"大小与形状")。
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
///
/// v2.10 用户反馈(第 6 条,**第二次**提名片):"'我的'界面的个人名片无法编辑呀,
/// 用户导入的头像、背景,**全都无法编辑大小和形状**。"
/// 看清楚了:v2.9 补的是"能不能换",用户要的是"换进来之后能不能调"。所以再补七个维度 ——
/// 头像(尺寸/形状/边框)与背景图(缩放/位置/暗度/模糊)。
///
/// **向后兼容是硬要求**:老用户的 Hive 串里没有这七个 key,`fromJson` 必须逐个回落默认值
/// (老名片长什么样,升级后就该还是什么样),脏数据(NaN、越界、乱填的形状名)同样回落。
/// 具体默认值见各字段注释,汇总一句:**头像中号(64)/圆形/无边框,背景 1.0× 居中 / 压暗 0.45 / 不模糊**。
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

  // ── v2.10 新增:头像的"大小与形状" ─────────────────────────────

  /// 头像直径(卡片上的**实际**像素直径,如 48 / 64 / 84)。
  /// 默认 64 = v2.9 卡片上写死的那个尺寸,所以老用户升级后卡片不会变形。
  final double avatarSize;

  /// 头像形状:`circle`(圆形)/ `rounded`(圆角方形)/ `square`(方形)。
  /// 默认圆形 —— 与 v2.9 的 `BoxShape.circle` 完全一致。
  final String avatarShape;

  /// 头像边框:`none` / `thin` / `thick`。默认无 —— v2.9 那一圈白边是"双环描边"的
  /// 装饰,现在交给用户决定要不要。
  final String avatarBorder;

  // ── v2.10 新增:背景图(仅自选图有意义)的调整 ──────────────────

  /// 背景图缩放:0.8× ~ 2.0×。默认 1.0×。
  ///
  /// 为什么 < 1 也要给:铺满(cover)会把竖图裁得只剩中间一条,0.8× 能"看到更多画面"。
  /// 实现上不是把图缩小留白(那会在卡片边上露出底色),而是**把图片铺进一个更大的
  /// 虚拟画布再整体缩回可视区**,所以缩小时仍然是铺满的,只是视野更宽。
  final double bgScale;

  /// 背景图位置(取景中心):`center` / `top` / `bottom`。默认居中。
  /// 人像照的脸通常在偏上位置,封面图的重心常在偏下 —— 所以至少要这三档。
  final String bgAlign;

  /// 背景图压暗程度:0.0 ~ 0.8(白字可读的前提)。默认 0.45。
  ///
  /// 0.45 ≈ v2.9 写死的那层压暗(黑 130/90 两档的均值),老用户升级后观感不变;
  /// 上限 0.8 是因为再深就把图压成一团黑,"用自选图"就没意义了。
  final double bgDim;

  /// 背景图模糊:0 ~ 12(高斯 sigma)。默认 0 = 不模糊。
  /// 给这个开关的理由:照片越清楚越抢字,一档轻度模糊能把背景"退到后面去"。
  final double bgBlur;

  const ProfileCardSettings({
    this.avatarPath,
    this.avatarText = '',
    this.backgroundId = 'dawn',
    this.backgroundPath,
    this.signature = '',
    this.nickname = '',
    this.avatarSize = defaultAvatarSize,
    this.avatarShape = 'circle',
    this.avatarBorder = 'none',
    this.bgScale = 1.0,
    this.bgAlign = 'center',
    this.bgDim = 0.45,
    this.bgBlur = 0,
  });

  static const ProfileCardSettings defaults = ProfileCardSettings();

  // ── 档位与取值范围(界面与校验共用同一份,避免两边各写一套) ────────

  /// 头像直径的默认值(= v2.9 卡片上写死的尺寸)
  static const double defaultAvatarSize = 64;

  /// 头像直径的合法区间(界面只给 48/64/84 三档,区间留宽一点,
  /// 是为了让老数据里可能存在的自定义值不至于被"夹"成别的档)
  static const double minAvatarSize = 40;
  static const double maxAvatarSize = 96;

  static const double minBgScale = 0.8;
  static const double maxBgScale = 2.0;
  static const double minBgDim = 0.0;
  static const double maxBgDim = 0.8;
  static const double minBgBlur = 0;
  static const double maxBgBlur = 12;

  /// 头像尺寸三档(界面上的"小 / 中 / 大")
  static const List<Map<String, Object>> avatarSizes = [
    {'id': 'sm', 'label': '小', 'size': 48.0},
    {'id': 'md', 'label': '中', 'size': 64.0},
    {'id': 'lg', 'label': '大', 'size': 84.0},
  ];

  /// 头像形状三档
  static const List<Map<String, String>> avatarShapes = [
    {'id': 'circle', 'label': '圆形'},
    {'id': 'rounded', 'label': '圆角'},
    {'id': 'square', 'label': '方形'},
  ];

  /// 头像边框三档
  static const List<Map<String, String>> avatarBorders = [
    {'id': 'none', 'label': '无边框'},
    {'id': 'thin', 'label': '细边框'},
    {'id': 'thick', 'label': '粗边框'},
  ];

  /// 背景图位置三档
  static const List<Map<String, String>> bgAligns = [
    {'id': 'center', 'label': '居中'},
    {'id': 'top', 'label': '偏上'},
    {'id': 'bottom', 'label': '偏下'},
  ];

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

  // ── 校验/归一化(全部 public:界面、测试、老数据读取共用一套口径) ──

  /// 头像直径:脏数据(NaN/无穷/非数字/越界)一律回归默认 64。
  ///
  /// 为什么要连 NaN 都管:Hive 里存的是字符串,升级/手改/写到一半断电都可能留下
  /// `NaN` 或 `Infinity` —— 这两个值一旦进了 `SizedBox(width:)`,整张名片会渲染成空白
  /// 而不报错,是最难查的一类 bug。
  static double normalizeAvatarSize(Object? raw) {
    final v = _toDouble(raw);
    if (v == null) return defaultAvatarSize;
    return v.clamp(minAvatarSize, maxAvatarSize).toDouble();
  }

  static String normalizeAvatarShape(Object? raw) {
    final v = '${raw ?? ''}'.trim().toLowerCase();
    return avatarShapes.any((s) => s['id'] == v) ? v : 'circle';
  }

  static String normalizeAvatarBorder(Object? raw) {
    final v = '${raw ?? ''}'.trim().toLowerCase();
    return avatarBorders.any((b) => b['id'] == v) ? v : 'none';
  }

  static double normalizeBgScale(Object? raw) {
    final v = _toDouble(raw);
    if (v == null) return 1.0;
    return v.clamp(minBgScale, maxBgScale).toDouble();
  }

  static String normalizeBgAlign(Object? raw) {
    final v = '${raw ?? ''}'.trim().toLowerCase();
    return bgAligns.any((a) => a['id'] == v) ? v : 'center';
  }

  static double normalizeBgDim(Object? raw) {
    final v = _toDouble(raw);
    if (v == null) return defaults.bgDim;
    return v.clamp(minBgDim, maxBgDim).toDouble();
  }

  static double normalizeBgBlur(Object? raw) {
    final v = _toDouble(raw);
    if (v == null) return 0;
    return v.clamp(minBgBlur, maxBgBlur).toDouble();
  }

  /// 数字解析的地基:同时吃 num 与字符串(老串是 `key=value` 文本),
  /// 且**只认有限值** —— NaN/Infinity 一律当"没给"。
  static double? _toDouble(Object? raw) {
    final double? v;
    if (raw is num) {
      v = raw.toDouble();
    } else {
      v = double.tryParse('${raw ?? ''}'.trim());
    }
    if (v == null || v.isNaN || v.isInfinite) return null;
    return v;
  }

  // ── 界面渲染直接要用的换算(放在这里而不是各页各写一份) ──────────

  /// 头像实际直径
  double get avatarDiameter => normalizeAvatarSize(avatarSize);

  /// 头像圆角半径:圆形 = 半边长;圆角方形 = 22% 边长(视觉上"圆但不软");
  /// 方形 = 0(v2.10 之前只有圆形,这两个值是照着 iOS 头像样式定的)
  double get avatarRadius => switch (normalizeAvatarShape(avatarShape)) {
        'square' => 0,
        'rounded' => avatarDiameter * 0.22,
        _ => avatarDiameter / 2,
      };

  /// 头像边框宽度(none = 0,即不画边框)
  double get avatarBorderWidth =>
      switch (normalizeAvatarBorder(avatarBorder)) {
        'thin' => 1.5,
        'thick' => 3,
        _ => 0,
      };

  /// 背景图的取景/缩放锚点
  Alignment get backgroundAlignment =>
      switch (normalizeBgAlign(bgAlign)) {
        'top' => Alignment.topCenter,
        'bottom' => Alignment.bottomCenter,
        _ => Alignment.center,
      };

  /// 压暗层的 alpha(0~255)。只作用于**自选背景图** ——
  /// 6 套渐变是挑过的(本来就保证白字可读),再压一层等于把老用户的名片变暗。
  int get backgroundDimAlpha => (normalizeBgDim(bgDim) * 255).round();

  ProfileCardSettings copyWith({
    Object? avatarPath = _sentinel,
    Object? backgroundPath = _sentinel,
    String? avatarText,
    String? backgroundId,
    String? signature,
    String? nickname,
    double? avatarSize,
    String? avatarShape,
    String? avatarBorder,
    double? bgScale,
    String? bgAlign,
    double? bgDim,
    double? bgBlur,
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
        avatarSize: avatarSize ?? this.avatarSize,
        avatarShape: avatarShape ?? this.avatarShape,
        avatarBorder: avatarBorder ?? this.avatarBorder,
        bgScale: bgScale ?? this.bgScale,
        bgAlign: bgAlign ?? this.bgAlign,
        bgDim: bgDim ?? this.bgDim,
        bgBlur: bgBlur ?? this.bgBlur,
      );

  static const Object _sentinel = Object();

  Map<String, Object?> toJson() => {
        'avatar_path': avatarPath,
        'avatar_text': avatarText,
        'background': backgroundId,
        'background_path': backgroundPath,
        'signature': signature,
        'nickname': nickname,
        // v2.10 七个新 key:老版本读到会当未知键忽略,新版本读老串则走默认值
        'avatar_size': avatarSize,
        'avatar_shape': avatarShape,
        'avatar_border': avatarBorder,
        'bg_scale': bgScale,
        'bg_align': bgAlign,
        'bg_dim': bgDim,
        'bg_blur': bgBlur,
      };

  /// 坏数据一律回落默认(名片只是装饰,不能把「我的」打崩)。
  ///
  /// 兼容性说明:老用户的串里**没有** v2.10 的七个 key,这里的每个字段都走
  /// `normalizeXxx(null)`,逐个回落到"v2.9 的样子";任何一个字段是脏数据,
  /// 也只影响它自己,不会把其它已设置好的项一起打回默认。
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
        avatarSize: normalizeAvatarSize(raw['avatar_size']),
        avatarShape: normalizeAvatarShape(raw['avatar_shape']),
        avatarBorder: normalizeAvatarBorder(raw['avatar_border']),
        bgScale: normalizeBgScale(raw['bg_scale']),
        bgAlign: normalizeBgAlign(raw['bg_align']),
        bgDim: normalizeBgDim(raw['bg_dim']),
        bgBlur: normalizeBgBlur(raw['bg_blur']),
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
        return fromEncodedString(raw);
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
          .put(AppConstants.keyProfileCard, toEncodedString());
    } catch (e) {
      debugPrint('ReadFlow 保存名片设置失败: $e');
    }
  }

  /// 落库用的串(测试与调试也走这一条路径,保证"测的就是存的")
  String toEncodedString() => encodeMap(toJson());

  /// 从落库串还原;解析失败/空串 → 默认值
  static ProfileCardSettings fromEncodedString(String raw) =>
      fromJson(decodeMap(raw));

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

  /// Map → `key=value&key=value` 串。
  ///
  /// 为什么用这种朴素格式而不是 JSON:这是 v2.8 就落库的格式,换格式就得写迁移;
  /// 而这里只有十来个短字段,`Uri.encodeComponent` 已能保证 `&`/`=`/换行/emoji
  /// 都不会把串拆坏(测试里逐条钉住了这一点)。
  static String encodeMap(Map<String, Object?> m) {
    final parts = m.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${Uri.encodeComponent('${e.value}')}')
        .join('&');
    return parts;
  }

  /// `key=value&...` 串 → Map。任何一段坏掉只丢那一段,不整体失败。
  static Map<String, Object?> decodeMap(String s) {
    final out = <String, Object?>{};
    for (final kv in s.split('&')) {
      final i = kv.indexOf('=');
      if (i <= 0) continue;
      final key = kv.substring(0, i);
      final rawValue = kv.substring(i + 1);
      try {
        out[key] = Uri.decodeComponent(rawValue);
      } catch (_) {
        // 半个百分号(写到一半断电/被外部工具改过)会让 decodeComponent 抛错。
        // 这里退化成"原样保留"而不是丢掉整条 —— 昵称里出现 %26 也不算灾难,
        // 但整张名片回默认值是用户能看见的损失。
        out[key] = rawValue;
      }
    }
    return out;
  }
}
