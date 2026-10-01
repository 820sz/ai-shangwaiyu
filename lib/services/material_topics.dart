import 'package:flutter/material.dart';

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
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 给 AI 的一句话(选材偏好面板里选题材时用)
  String get hintForAi => '$label(${queries.first})';
}

/// 题材 → 展示用的"题材色"角标色(与封面配色同一套低饱和思路)
Color topicColor(BuildContext context) =>
    Theme.of(context).colorScheme.primary;
