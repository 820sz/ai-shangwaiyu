import 'package:flutter/material.dart';

/// 材料中心的**四维分类法**(v5,2026-11-04 用户拍板"先定架构再动前端")。
///
/// 用户原话:
/// "材料中心的分类逻辑应该是——按需求、然后基于需求之上衍生出几种并行的不同的方向——
///  按材料题材分类、按形式、按场景；这些分类只是给用户提高一个进入方向,并不是彼此对立,
///  甚至用户可以多选后,再推送非常垂直精准的材料需求；然后这些大分类里面,
///  又衍生出对应的子分类,然后就呈现材料了"。
///
/// 本文件只放**纯常量 + 纯函数**,不碰 BuildContext / 数据库 / 网络:
/// - 大方向:按需求 / 按题材 / 按形式 / 按场景;
/// - 每个方向下是子分类 [MaterialSubtopic];
/// - 子分类带 `queries`(给"AI 补长尾"/来源检索用)与 `kinds`(材料库过滤用)。
///
/// 为什么单独成文件:四个维度会在材料中心首页、二级页、书架、AI 找材料里复用,
/// 分散写必然出现"题材名改了这里没改"的漂移(v3 就发生过)。
enum MaterialDirection { need, topic, form, scene }

/// 一个子分类(如 题材·科技报道 / 形式·外刊 / 场景·出国旅游)。
class MaterialSubtopic {
  /// 稳定 id(存 Hive / 路由参数用,别改)
  final String id;

  /// 展示名
  final String label;

  /// 检索词(给公开源/AI 补长尾用;中文展示、英文检索)
  final List<String> queries;

  /// 该子分类大致对应材料库里的 kind(可空:空 = 不过滤)
  final Set<String> kinds;

  const MaterialSubtopic(
    this.id,
    this.label, {
    this.queries = const <String>[],
    this.kinds = const <String>{},
  });
}

/// 一个方向(按题材 / 按形式 / 按场景;按需求是特殊页,不列子分类)。
class MaterialDirectionDef {
  final MaterialDirection id;
  final String label;
  final String subtitle;
  final IconData icon;
  final List<MaterialSubtopic> subtopics;

  const MaterialDirectionDef({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.subtopics,
  });
}

/// 材料分类法(纯常量)。
abstract final class MaterialTaxonomy {
  /// 按需求(特殊页:难度 + 目标 + 形式 + 补充需求 → 全局推送)
  ///
  /// 2026-11-06 用户选型后改名为「找材料」:入口不再直接进频道页,而是走
  /// `FindMaterialScreen` 的并列大卡(自由搜 / 按我的情况找);这个定义仍被
  /// 频道页「按需求」方向与需求设置页复用,`label` 只影响展示。
  static const MaterialDirectionDef need = MaterialDirectionDef(
    id: MaterialDirection.need,
    label: '找材料',
    subtitle: '自由搜 · 或按你的学习情况找',
    icon: Icons.travel_explore_rounded,
    subtopics: <MaterialSubtopic>[],
  );

  /// 按题材(6 大题材 → 子分类)
  static const MaterialDirectionDef topic = MaterialDirectionDef(
    id: MaterialDirection.topic,
    label: '按题材找材料',
    subtitle: '先选想读的内容领域,再看子分类',
    icon: Icons.category_outlined,
    subtopics: <MaterialSubtopic>[
      MaterialSubtopic('sci_tech', '科学与技术', kinds: <String>{
        'news',
        'paper',
        'book',
        'article',
      }),
      MaterialSubtopic('business', '商业与政治', kinds: <String>{
        'news',
        'article',
        'book',
      }),
      MaterialSubtopic('health', '健康与生活', kinds: <String>{
        'news',
        'article',
        'book',
      }),
      MaterialSubtopic('culture', '文化与艺术', kinds: <String>{
        'book',
        'news',
        'article',
      }),
      MaterialSubtopic('travel', '旅行与体验', kinds: <String>{
        'article',
        'news',
        'book',
      }),
      MaterialSubtopic('language', '语言与学习', kinds: <String>{
        'book',
        'article',
        'news',
      }),
    ],
  );

  /// 按形式(教材/书籍/外刊/论文/应试真题/碎片文章/其他)
  static const MaterialDirectionDef form = MaterialDirectionDef(
    id: MaterialDirection.form,
    label: '按形式找材料',
    subtitle: '教材、书、外刊、论文、真题……按载体挑',
    icon: Icons.auto_stories_outlined,
    subtopics: <MaterialSubtopic>[
      MaterialSubtopic('textbook', '教材', kinds: <String>{'book'}),
      MaterialSubtopic('book', '书籍', kinds: <String>{'book'}),
      MaterialSubtopic('news', '外刊', kinds: <String>{'news'}),
      MaterialSubtopic('paper', '论文', kinds: <String>{'paper'}),
      MaterialSubtopic('exam', '应试真题', kinds: <String>{'exam'}),
      MaterialSubtopic('fragment', '碎片文章', kinds: <String>{'article'}),
      MaterialSubtopic('other', '其他', kinds: <String>{}),
    ],
  );

  /// 按场景(应试 / 出国旅游 / 生活聊天 / 生产力英语)
  static const MaterialDirectionDef scene = MaterialDirectionDef(
    id: MaterialDirection.scene,
    label: '按场景找材料',
    subtitle: '你接下来要在什么场合用英语',
    icon: Icons.explore_outlined,
    subtopics: <MaterialSubtopic>[
      MaterialSubtopic('exam', '应试', queries: <String>[
        'exam preparation',
        'CET reading',
        'IELTS reading',
      ]),
      MaterialSubtopic('travel', '出国旅游', queries: <String>[
        'travel airport hotel',
        'travel guide conversation',
      ]),
      MaterialSubtopic('daily', '生活聊天', queries: <String>[
        'daily conversation',
        'small talk',
      ]),
      MaterialSubtopic('productivity', '生产力英语', queries: <String>[
        'workplace English',
        'business email meeting',
        'technical documentation',
      ]),
    ],
  );

  /// 首页"材料库"入口(不参与四维过滤)
  static const List<MaterialDirectionDef> all = <MaterialDirectionDef>[
    need,
    topic,
    form,
    scene,
  ];

  static MaterialDirectionDef of(MaterialDirection id) =>
      all.firstWhere((d) => d.id == id);

  static MaterialSubtopic? subtopicOf(MaterialDirection id, String subId) {
    for (final s in of(id).subtopics) {
      if (s.id == subId) return s;
    }
    return null;
  }
}
