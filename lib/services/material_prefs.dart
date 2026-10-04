import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import 'material_source.dart';

/// **内容层面**的类型(v2.10,用户 10/4 第 2(4) 条)。
///
/// 与 `MaterialSource.kind`(来源:公版书/论文/外刊…)是两个维度:
/// 这个回答"里面是什么东西"(新闻报道/评论社论/科普/文学/学术…),
/// 每一项都带一组**英文检索词** —— 公开源只认英文,中文标签只是给用户看的。
class MaterialContentType {
  final String id;
  final String label;

  /// 一句话说明(界面上当 tooltip:告诉用户选它意味着什么)
  final String hint;

  /// 英文检索词(第一组会拼进实际检索)
  final List<String> queries;

  const MaterialContentType({
    required this.id,
    required this.label,
    required this.hint,
    required this.queries,
  });
}

/// 材料难度档(v2.7,用户第 4 条:材料中心要能"用户难度自选(i+1, i+10, i+100)")。
///
/// **数字怎么定义**:按**未知词率**分档,与 `LearnerContext` 的既有阈值同一口径
/// (98% 可泛读 / 95% 可精读 / 90% 以下过载,见 `learner_context.dart` 的注释),
/// 不另立一套数字 —— 否则"推荐说合适、阅读器说偏难"的老问题会再来一次。
///
/// - **i+1**:未知词率 ≤2%(词次覆盖率 ≥98%)—— 几乎全认识,轻松泛读;
/// - **i+10**:未知词率 2%~10%(覆盖率 90%~98%)—— 舒适精读,当前水平正好够一够;
/// - **i+100**:未知词率 >10%(覆盖率 <90%)—— 硬啃区,建议先预热生词;
/// - **不限**:不做难度约束。
///
/// 边界归属:**0.98 归 i+1、0.90 归 i+10**(区间左闭右开,三档不重不漏)。
/// 这三种档在界面上就是四个 chip,选中后会:①把材料库/今日推荐里**符合档位的
/// 排前面并标注**;②把这个难度作为约束交给 AI 去找材料。用户如果对
/// "i+1/i+10/i+100"的定义有别的理解,改这里的区间即可 —— 阈值只写在这一处。
enum MaterialBand {
  i1('i+1', '几乎全认识(每 100 词 ≤2 个生词)', 0.98, 1.0001),
  i10('i+10', '精读区(每 100 词 2~10 个生词)', 0.90, 0.98),
  i100('i+100', '硬啃区(每 100 词 >10 个生词)', 0.0, 0.90),
  any('不限', '不做难度约束', 0.0, 1.0001);

  const MaterialBand(this.label, this.description, this.min, this.max);

  /// 界面上的档位名(与用户说法一致:i+1 / i+10 / i+100)
  final String label;

  /// 一句话解释(给 chip 的提示与设置说明用)
  final String description;

  /// 词次覆盖率下界(含)
  final double min;

  /// 词次覆盖率上界(不含)
  final double max;

  bool get isAny => this == MaterialBand.any;

  /// 覆盖率是否落在本档(i+1 与 i+100 的边界互不重叠)
  bool contains(double knownTokenRatio) =>
      knownTokenRatio >= min && knownTokenRatio < max;

  /// 一份材料**实际**属于哪一档(用于"这条对你正合适/偏易/偏难"的标注)。
  /// 注意 **0.98 归 i+1**(≥98% 就是"几乎全认识",与 [contains] 的区间一致)。
  static MaterialBand of(double knownTokenRatio) {
    if (knownTokenRatio >= 0.98) return MaterialBand.i1;
    if (knownTokenRatio >= 0.90) return MaterialBand.i10;
    return MaterialBand.i100;
  }

  /// 在当前档位下,这条材料的适配标签(空串 = 不限档,不标注)
  String fitLabel(double knownTokenRatio) {
    if (isAny) return '';
    if (contains(knownTokenRatio)) return '符合 $label';
    return knownTokenRatio >= max ? '偏易' : '偏难';
  }

  /// 该档位给 AI 的难度说明(选材 prompt 用)
  String get hintForAi => switch (this) {
        MaterialBand.i1 =>
          '目标难度 i+1:未知词率 ≤2%(每 100 词最多 2 个生词)'
              '—— 请选词汇简单、句子短、篇幅不长的材料',
        MaterialBand.i10 =>
          '目标难度 i+10:未知词率 2%~10%(每 100 词 2~10 个生词)'
              '—— 常规难度即可,不要刻意挑太简单的',
        MaterialBand.i100 =>
          '目标难度 i+100:未知词率 >10%(每 100 词 10 个以上生词)'
              '—— 可以挑有难度的原文(学术论文、文学原著)',
        MaterialBand.any => '',
      };

  /// 从 Hive 里读回的字符串还原(不认识的值 → 不限,不抛)
  static MaterialBand parse(Object? raw) {
    final id = '$raw'.trim();
    for (final b in MaterialBand.values) {
      if (b.name == id) return b;
    }
    return MaterialBand.any;
  }
}

/// 材料中心的个性化找资源偏好(v2.7,用户第 5 条)。
///
/// 用户原话:"在材料中心界面上方增加个性化找资源需求 —— 用户能自选不同材料的
/// 倾向偏好、类型、难度、以及补充/调整个性化需求给 ai"。
///
/// 所以这里存四样东西:难度档([band])、内容类型([kinds],公版书/论文/外刊/播客/百科)、
/// 题材倾向([genres])、补充需求([extra])。**全部只影响"找材料"的检索方案**,
/// 不会去动用户已有的生词/材料数据 —— 偏好是"给 AI 的约束",不是"数据过滤器"。
class MaterialPrefs {
  /// 用户自选难度档(i+1 / i+10 / i+100 / 不限)
  final MaterialBand band;

  /// 内容类型偏好(kind 集合,空 = 不限制)。取值同 [MaterialSource.kind]
  final Set<String> kinds;

  /// 题材偏好(自由文本,如"哲学散文、英式幽默";空 = 不限制)
  final String genres;

  /// 补充/调整需求(自由文本,如"不要学术腔,每篇别超过 10 分钟")
  final String extra;

  /// **内容层面**的类型偏好(v2.10,用户 10/4 第 2(4) 条)。
  ///
  /// 用户原话:"'个性化找资源'的内容类型**再提高多一些**,现在只有体裁分类,
  /// 没有**内容层面**的分类。"
  /// 体裁(kinds)回答的是"这材料从哪来"(公版书/论文/外刊…),
  /// 这里回答的是"里面是什么东西"(新闻/评论/科普/文学/商务/学术/演讲/访谈…),
  /// 两者是**两个维度**,都可以多选,一起交给 AI 当检索约束。
  final Set<String> contentTypes;

  const MaterialPrefs({
    this.band = MaterialBand.any,
    this.kinds = const {},
    this.contentTypes = const {},
    this.genres = '',
    this.extra = '',
  });

  static const MaterialPrefs empty = MaterialPrefs();

  /// 类型的中文名(界面 chip 与 AI 提示共用一份文案)
  static const Map<String, String> kindLabels = {
    'book': '公版书',
    'paper': '论文',
    'news': '外刊新闻',
    'podcast': '播客/听力',
    'wiki': '百科',
  };

  /// **内容层面**的分类(用户 10/4 第 2(4) 条):每个都给一句"适合谁/练什么",
  /// 并且带一组英文检索词 —— 点一下就能真的影响检索,不是装饰。
  static const List<MaterialContentType> contentCatalog = [
    MaterialContentType(
      id: 'news_report',
      label: '新闻报道',
      hint: '时事、硬新闻;练信息提取',
      queries: ['news report', 'breaking news'],
    ),
    MaterialContentType(
      id: 'opinion',
      label: '评论社论',
      hint: '观点与论证;练立场判断',
      queries: ['opinion editorial', 'op-ed'],
    ),
    MaterialContentType(
      id: 'science',
      label: '科普',
      hint: '把复杂事讲清楚;练说明文',
      queries: ['popular science', 'science explained'],
    ),
    MaterialContentType(
      id: 'literature',
      label: '文学小说',
      hint: '叙事与描写;练语感',
      queries: ['short story', 'classic novel'],
    ),
    MaterialContentType(
      id: 'academic',
      label: '学术论文',
      hint: '摘要与论证;备考/科研',
      queries: ['research paper abstract', 'academic study'],
    ),
    MaterialContentType(
      id: 'business',
      label: '商业财经',
      hint: '市场与公司;职场英语',
      queries: ['business news', 'market analysis'],
    ),
    MaterialContentType(
      id: 'speech',
      label: '演讲致辞',
      hint: '成段的正式口语;练跟读',
      queries: ['famous speech transcript', 'commencement address'],
    ),
    MaterialContentType(
      id: 'interview',
      label: '访谈对话',
      hint: '真实口语节奏;练听说',
      queries: ['interview transcript', 'conversation'],
    ),
    MaterialContentType(
      id: 'howto',
      label: '教程指南',
      hint: '步骤与说明;练指令句',
      queries: ['how-to guide', 'tutorial'],
    ),
    MaterialContentType(
      id: 'history',
      label: '历史人文',
      hint: '时间线与因果;练长句',
      queries: ['history essay', 'historical account'],
    ),
  ];

  bool get isEmpty =>
      band.isAny &&
      kinds.isEmpty &&
      contentTypes.isEmpty &&
      genres.trim().isEmpty &&
      extra.trim().isEmpty;

  /// 有几项偏好生效(界面上的小角标:N 项偏好)
  int get activeCount =>
      (band.isAny ? 0 : 1) +
      kinds.length +
      contentTypes.length +
      (genres.trim().isEmpty ? 0 : 1) +
      (extra.trim().isEmpty ? 0 : 1);

  MaterialPrefs copyWith({
    MaterialBand? band,
    Set<String>? kinds,
    Set<String>? contentTypes,
    String? genres,
    String? extra,
  }) =>
      MaterialPrefs(
        band: band ?? this.band,
        kinds: kinds ?? this.kinds,
        contentTypes: contentTypes ?? this.contentTypes,
        genres: genres ?? this.genres,
        extra: extra ?? this.extra,
      );

  /// 内容类型的中文名清单
  List<String> get contentLabels => [
        for (final t in contentCatalog)
          if (contentTypes.contains(t.id)) t.label,
      ];

  /// 内容类型对应的英文检索词(第一组就够用;拿去当检索词比中文标签有效)
  List<String> get contentQueries => [
        for (final t in contentCatalog)
          if (contentTypes.contains(t.id)) t.queries.first,
      ];

  /// 偏好的源清单(空 = 全部源)。用户选了"论文"就只去 arXiv 找 —— 这比在
  /// 结果里过滤更省一次网络往返,而且能让 AI 的检索词一开始就对路。
  List<MaterialSource> get preferredSources {
    if (kinds.isEmpty) return MaterialSourceService.sources;
    final out = [
      for (final s in MaterialSourceService.sources)
        if (kinds.contains(s.kind)) s,
    ];
    // 偏好里的 kind 在源清单里一个都找不到(数据脏了)→ 回落全部,不要让界面空白
    return out.isEmpty ? MaterialSourceService.sources : out;
  }

  /// 给 AI 的一段话(拼进选材 prompt;没有偏好时返回空串)
  String get hintForAi {
    final parts = <String>[];
    if (kinds.isNotEmpty) {
      final names = [
        for (final k in kinds) kindLabels[k] ?? k,
      ];
      parts.add('来源类型偏好:${names.join('、')}');
    }
    // v2.10(第 2(4) 条):内容层面的偏好单独说一句,并带上英文检索词 ——
    // "科普"这种中文标签对公开源没用,给英文词才真的影响检索结果
    if (contentTypes.isNotEmpty) {
      parts.add('内容类型偏好:${contentLabels.join('、')}'
          '(建议检索词:${contentQueries.join(' / ')})');
    }
    if (genres.trim().isNotEmpty) parts.add('题材倾向:${genres.trim()}');
    if (extra.trim().isNotEmpty) parts.add('补充要求:${extra.trim()}');
    if (!band.isAny) parts.add(band.hintForAi);
    return parts.join(';');
  }

  /// 界面上的摘要行(不开面板也能一眼看到当前偏好在管什么)
  String get summary {
    if (isEmpty) return '还没设置偏好 —— 点这里告诉 AI 你想读什么';
    final parts = <String>[];
    if (!band.isAny) parts.add(band.label);
    if (kinds.isNotEmpty) {
      parts.add([
        for (final k in kinds) kindLabels[k] ?? k,
      ].join('/'));
    }
    if (contentTypes.isNotEmpty) parts.add(contentLabels.join('/'));
    if (genres.trim().isNotEmpty) parts.add(genres.trim());
    if (extra.trim().isNotEmpty) parts.add(extra.trim());
    return parts.join(' · ');
  }

  Map<String, Object?> toJson() => {
        'band': band.name,
        'kinds': kinds.toList(),
        'content_types': contentTypes.toList(),
        'genres': genres,
        'extra': extra,
      };

  /// 坏数据一律当"没有偏好"(不要让一条脏 JSON 把材料中心打成白屏)
  static MaterialPrefs fromJson(Object? raw) {
    if (raw is! Map) return empty;
    try {
      final kinds = <String>{};
      final rawKinds = raw['kinds'];
      if (rawKinds is List) {
        for (final k in rawKinds) {
          final id = '$k'.trim();
          if (kindLabels.containsKey(id)) kinds.add(id);
        }
      }
      // 内容类型:只认目录里的 id(旧的偏好串里没有这个 key → 空集合,天然兼容)
      final contentTypes = <String>{};
      final rawContent = raw['content_types'];
      if (rawContent is List) {
        for (final c in rawContent) {
          final id = '$c'.trim();
          if (contentCatalog.any((t) => t.id == id)) contentTypes.add(id);
        }
      }
      return MaterialPrefs(
        band: MaterialBand.parse(raw['band']),
        kinds: kinds,
        contentTypes: contentTypes,
        genres: '${raw['genres'] ?? ''}',
        extra: '${raw['extra'] ?? ''}',
      );
    } catch (e) {
      debugPrint('ReadFlow 读取材料偏好失败(当空处理): $e');
      return empty;
    }
  }

  // ── 持久化(Hive;任何异常都不能影响找材料本身)──

  static MaterialPrefs load() {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings)
          .get(AppConstants.keyMaterialPrefs);
      if (raw is String && raw.trim().isNotEmpty) {
        return fromJson(jsonDecode(raw));
      }
      if (raw is Map) return fromJson(raw);
    } catch (e) {
      debugPrint('ReadFlow 读取材料偏好失败(当空处理): $e');
    }
    return empty;
  }

  Future<void> save() async {
    try {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyMaterialPrefs, jsonEncode(toJson()));
    } catch (e) {
      debugPrint('ReadFlow 保存材料偏好失败: $e');
    }
  }

  // ── 搜索框记忆(用户第 2(3) 条)──
  //
  // 用户原话:"每次找材料,不管我上一次搜了啥,搜索框都有个'小说故事'这个死数据挂着"。
  // 之前那口"死数据"其实是**学习画像里的兴趣词**(`_defaultQuery()` 读 interests),
  // 根本不是搜索历史。现在:搜索框只记"用户上次在这个分类里真的搜过什么",
  // 没有记录就留空(靠 hint 提示可以中文说需求),不再拿画像词冒充。

  /// 某分类上一次的搜索词(没搜过 → 空串)
  static String lastQueryFor(String category) {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings)
          .get(AppConstants.keyMaterialSearchHistory);
      if (raw is String && raw.trim().isNotEmpty) {
        final map = jsonDecode(raw);
        if (map is Map) return '${map[category] ?? ''}';
      }
      if (raw is Map) return '${raw[category] ?? ''}';
    } catch (e) {
      debugPrint('ReadFlow 读取搜索历史失败(当空处理): $e');
    }
    return '';
  }

  static Future<void> rememberQuery(String category, String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    try {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      final map = <String, String>{};
      final raw = box.get(AppConstants.keyMaterialSearchHistory);
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) => map['$k'] = '$v');
        }
      }
      map[category] = q;
      await box.put(AppConstants.keyMaterialSearchHistory, jsonEncode(map));
    } catch (e) {
      debugPrint('ReadFlow 保存搜索历史失败: $e');
    }
  }
}
