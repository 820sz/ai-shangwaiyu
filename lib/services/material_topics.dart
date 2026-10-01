import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';

/// 材料题材分类(v2.8,用户第 6(2)(5) 条:"分类逻辑清晰""找到的材料太少")。
///
/// ## 为什么要自己定题材,而不是直接用内容源的分类
/// 内容源(公版书 / arXiv / 外媒 RSS)是**按渠道**分的,用户想的是**按题材**找:
/// 参考软件(扇贝阅读)顶部就是「科学与技术 / 商业与政治 / 旅行与体验」这种题材 tab。
/// 所以这里给一套题材:每个题材带一组**英文检索词**(公开源只认英文,见 v2.6 的教训),
/// 一个图标与一句人话说明。
///
/// ## 每个题材怎么"找到很多材料"
/// [queries] 是**多组检索词**:公版书站内检索查第一组、arXiv 查第二组、
/// 外媒 RSS 用本地关键词过滤 —— 三路并行,一屏就能铺满图文卡片(用户第 6(5) 条)。
class MaterialTopic {
  /// 稳定 id(存 Hive / 状态用)
  final String id;

  /// 中文题材名(tab 上显示)
  final String label;

  /// 图标
  final IconData icon;

  /// 英文检索词(2~3 组,越多路搜得越广)
  final List<String> queries;

  /// 一句话说明(不做成黑箱:告诉用户这个题里都有什么)
  final String description;

  const MaterialTopic({
    required this.id,
    required this.label,
    required this.icon,
    required this.queries,
    required this.description,
  });

  /// 默认题材清单(顺序即 tab 顺序)
  static const List<MaterialTopic> all = [
    MaterialTopic(
      id: 'sci_tech',
      label: '科学与技术',
      icon: Icons.science_outlined,
      queries: ['science technology', 'artificial intelligence', 'space exploration'],
      description: '科技报道、科学论文、科普公版书',
    ),
    MaterialTopic(
      id: 'business',
      label: '商业与政治',
      icon: Icons.trending_up,
      queries: ['business economy', 'politics government', 'international trade'],
      description: '经济、商业、时政新闻与社科论文',
    ),
    MaterialTopic(
      id: 'health',
      label: '健康与生活',
      icon: Icons.favorite_border,
      queries: ['health lifestyle', 'mental health', 'nutrition fitness'],
      description: '健康、心理、生活方式',
    ),
    MaterialTopic(
      id: 'culture',
      label: '文化与艺术',
      icon: Icons.palette_outlined,
      queries: ['literature classics', 'art history', 'culture society'],
      description: '文学名著、艺术史、文化随笔',
    ),
    MaterialTopic(
      id: 'travel',
      label: '旅行与体验',
      icon: Icons.flight_takeoff,
      queries: ['travel adventure', 'exploration journey', 'nature wilderness'],
      description: '旅行见闻、探险、自然',
    ),
    MaterialTopic(
      id: 'language',
      label: '语言与学习',
      icon: Icons.translate,
      queries: ['language learning', 'linguistics', 'education psychology'],
      description: '语言学习、语言学、教育',
    ),
  ];

  static MaterialTopic? byId(String id) {
    for (final t in MaterialTopic.all) {
      if (t.id == id) return t;
    }
    for (final t in CustomTopics.load()) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 给 AI 的一句话(选材偏好面板里选题材时用)
  String get hintForAi => '$label(${queries.first})';
}

/// **用户自定义分区**(v2.9,用户 10/2 第 3(3) 条)。
///
/// 用户原话:"'发现更多'里的子分类**没法让用户自定义添加分区**,没法多选分区。"
///
/// 所以:用户可以加自己的题材(一个中文名 + 一到几组英文检索词),
/// 加完它就和内置题材一样出现在 tab 里,并且可以**多选**一起搜。
/// 存 Hive(JSON 字符串,自己编码,不引依赖)。
class CustomTopics {
  static List<MaterialTopic>? _cache;

  static const List<IconData> iconChoices = [
    Icons.interests,
    Icons.science,
    Icons.history_edu,
    Icons.psychology,
    Icons.rocket_launch,
    Icons.music_note,
    Icons.sports_esports,
    Icons.theater_comedy,
  ];

  static List<MaterialTopic> load() {
    if (_cache != null) return _cache!;
    try {
      final raw =
          Hive.box(AppConstants.hiveBoxSettings).get(AppConstants.keyCustomTopics);
      final list = <MaterialTopic>[];
      if (raw is String && raw.trim().isNotEmpty) {
        for (final block in raw.split('\n')) {
          final parts = block.split('\t');
          if (parts.length < 4) continue;
          final queries = parts[3]
              .split('|')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (queries.isEmpty) continue;
          final iconIndex = int.tryParse(parts.length > 4 ? parts[4] : '0') ?? 0;
          list.add(MaterialTopic(
            id: parts[0],
            label: parts[1],
            icon: iconChoices[iconIndex % iconChoices.length],
            queries: queries,
            description: parts[2],
          ));
        }
      }
      _cache = list;
      return list;
    } catch (e) {
      debugPrint('ReadFlow 读取自定义分区失败(当作没有): $e');
      return const [];
    }
  }

  static Future<void> _save(List<MaterialTopic> list) async {
    final encoded = list
        .map((t) => [
              t.id,
              t.label,
              t.description,
              t.queries.join('|'),
              '${iconChoices.contains(t.icon) ? iconChoices.indexOf(t.icon) : 0}',
            ].join('\t'))
        .join('\n');
    await Hive.box(AppConstants.hiveBoxSettings)
        .put(AppConstants.keyCustomTopics, encoded);
    _cache = list;
  }

  /// 新增一个自定义分区。[queriesText] 允许用逗号/换行分隔多个检索词
  static Future<MaterialTopic?> add({
    required String label,
    required String queriesText,
    String description = '',
    IconData? icon,
  }) async {
    final name = label.trim();
    if (name.isEmpty) return null;
    final queries = queriesText
        .split(RegExp(r'[,,\n;；]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (queries.isEmpty) return null;
    final list = [...load()];
    final topic = MaterialTopic(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      label: name,
      icon: icon ?? iconChoices[list.length % iconChoices.length],
      queries: queries,
      description: description.trim().isEmpty ? '自定义分区' : description.trim(),
    );
    list.add(topic);
    await _save(list);
    return topic;
  }

  static Future<void> remove(String id) async {
    final list = [...load()]..removeWhere((t) => t.id == id);
    await _save(list);
  }
}

/// 题材 → 展示用的"题材色"角标色(与封面配色同一套低饱和思路)
Color topicColor(BuildContext context) =>
    Theme.of(context).colorScheme.primary;
