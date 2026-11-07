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

  /// 按形式(教材/书籍/外刊/论文/四级真题/六级真题/全部真题/碎片文章/其他)
  ///
  /// 第三轮(用户 2026-11-07 真机:真题分不出四级六级):把原来的「应试真题」
  /// 拆成 **四级真题 / 六级真题 / 全部真题** 三个子分类,并给每个子分类配
  /// 分级检索词(CET-4 / CET-6 分开),不再用含糊的 `exam paper` 一条词。
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
      MaterialSubtopic(
        'cet4',
        '四级真题',
        kinds: <String>{'exam'},
        queries: <String>[
          'CET-4 真题阅读',
          'CET-4 past paper reading',
          '大学英语四级真题',
          'CET-4 reading comprehension',
        ],
      ),
      MaterialSubtopic(
        'cet6',
        '六级真题',
        kinds: <String>{'exam'},
        queries: <String>[
          'CET-6 真题阅读',
          'CET-6 past paper reading',
          '大学英语六级真题',
          'CET-6 reading comprehension',
        ],
      ),
      MaterialSubtopic(
        'exam',
        '全部真题',
        kinds: <String>{'exam'},
        queries: <String>[
          'CET-4 真题',
          'CET-6 真题',
          '四六级真题阅读',
        ],
      ),
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

  // ═══════════════════════════════════════════════════════════════════
  // 第三轮(2026-11-07 用户真机反馈):频道检索词 = 分类 + 难度
  // ═══════════════════════════════════════════════════════════════════
  //
  // 用户原话归纳:「材料中心(按题材/形式/场景)只按我选的难度 + 我选的分类找,
  // 别把我填的学习目标/需求全局灌进去」——需求画像只留给独立「找材料」的按需找。
  // 下面的纯函数是唯一口径:频道页只调它,单测直接钉"非需求频道不出现 goals/需求"。

  /// 某方向下的子分类检索词(不掺任何用户画像)。
  ///
  /// 规则与频道页旧实现一致:子分类自带 `queries` 优先;没有就补
  /// [fallbackQueries] 里的 `方向:子分类id` 英文词;最后补展示名(中文给官方搜索)。
  /// 返回去重后的列表,最多 [max] 条。
  static List<String> categoryQueries({
    required MaterialDirection direction,
    required MaterialDirectionDef def,
    List<String> selectedIds = const <String>[],
    Map<String, List<String>> fallbackQueries = const <String, List<String>>{},
    int max = 6,
  }) {
    final subs = <MaterialSubtopic>[];
    if (selectedIds.isEmpty) {
      subs.addAll(def.subtopics);
    } else {
      for (final id in selectedIds) {
        final sub = subtopicOf(direction, id);
        if (sub != null) subs.add(sub);
      }
    }
    final out = <String>[];
    for (final sub in subs) {
      out.addAll(sub.queries);
      out.add(sub.label);
      if (sub.queries.isEmpty) {
        out.addAll(
          fallbackQueries['${direction.name}:${sub.id}'] ??
              const <String>[],
        );
      }
    }
    return dedupeTake(out, max);
  }

  /// 频道检索词(**唯一入口**)。
  ///
  /// - `direction == need`(独立「按需求」频道):需求自由文本 + 学习目标 +
  ///   拉丁字母兴趣(官方搜索认中文),空则 `english reading` 兜底;
  /// - 其它方向(按题材/形式/场景):**只用分类检索词**;`goals` / `interests` /
  ///   `extraNeed` **完全不参与**(用户 2026-11-07 明确要求)。
  static List<String> buildChannelQueries({
    required MaterialDirection direction,
    required MaterialDirectionDef def,
    List<String> selectedIds = const <String>[],
    List<String> goals = const <String>[],
    List<String> interests = const <String>[],
    String extraNeed = '',
    Map<String, List<String>> fallbackQueries = const <String, List<String>>{},
    int max = 6,
  }) {
    if (direction != MaterialDirection.need) {
      return categoryQueries(
        direction: direction,
        def: def,
        selectedIds: selectedIds,
        fallbackQueries: fallbackQueries,
        max: max,
      );
    }
    final out = <String>[];
    final extra = extraNeed.trim();
    if (extra.isNotEmpty) out.add(extra);
    out.addAll(goals);
    for (final interest in interests) {
      if (RegExp(r'[A-Za-z]').hasMatch(interest)) out.add(interest.trim());
    }
    if (out.isEmpty) out.add('english reading');
    return dedupeTake(out, max);
  }

  /// 频道页给 AI 的**中性提示词**:只写「分类 + 难度」。
  ///
  /// [bandHint] 来自 [MaterialBand.hintForAi](难度档);`direction == need` 时
  /// 返回空串(按需找继续用 `InputPreferences.promptHint`,行为不变)。
  static String buildChannelPromptHint({
    required MaterialDirection direction,
    required MaterialDirectionDef def,
    List<String> selectedIds = const <String>[],
    String bandHint = '',
  }) {
    if (direction == MaterialDirection.need) return '';
    final labels = <String>[];
    for (final id in selectedIds) {
      final sub = subtopicOf(direction, id);
      if (sub != null) labels.add(sub.label);
    }
    final category = <String>[
      def.label.replaceAll('找材料', '').trim(),
      if (labels.isNotEmpty) labels.join('、'),
    ].join(' · ');
    final parts = <String>['分类:$category'];
    if (bandHint.trim().isNotEmpty) parts.add(bandHint.trim());
    return '${parts.join(';')}。';
  }

  /// 去空白/去重/截断(检索词构造共用)。
  static List<String> dedupeTake(Iterable<String> raw, int max) {
    final out = <String>[];
    for (final item in raw) {
      final text = item.trim();
      if (text.isEmpty || out.contains(text)) continue;
      out.add(text);
      if (out.length >= max) break;
    }
    return out;
  }

  /// 真题级别(纯函数):从标题/URL 判「四级/六级」。
  ///
  /// 只认明确命中:`四级` / `CET-4` / `cet4` / `CET4` / `TEM-4` 等;
  /// 「四六级」这种**同时含四与六**的写法判不出来,返回空串(不猜)。
  static String examLevelOf(String title, {String url = ''}) {
    final hay = '${title.toLowerCase()} ${url.toLowerCase()}';
    bool has(String pattern) => RegExp(pattern).hasMatch(hay);
    // 「四六级」是同时含四级与六级的口语写法,机器不能替用户选一个级别 → 不猜
    if (hay.contains('四六级') ||
        RegExp(r'四\s*[、/,，]\s*六级').hasMatch(hay) ||
        RegExp(r'四\s*级\s*[、/,，]\s*六\s*级').hasMatch(hay)) {
      return '';
    }
    final four = has(r'四级') ||
        has(r'cet[-_ ]?4') ||
        has(r'\btem[-_ ]?4\b') ||
        has(r'level[-_ ]?4\b');
    final six = has(r'六级') ||
        has(r'cet[-_ ]?6') ||
        has(r'\btem[-_ ]?6\b') ||
        has(r'level[-_ ]?6\b');
    if (four && six) return '';
    if (four) return 'cet4';
    if (six) return 'cet6';
    return '';
  }

  /// 真题卡片级标签:四级真题 / 六级真题;判不出返回空串(不加假标签)。
  static String examLevelTag(String title, {String url = ''}) =>
      switch (examLevelOf(title, url: url)) {
        'cet4' => '四级真题',
        'cet6' => '六级真题',
        _ => '',
      };
}
