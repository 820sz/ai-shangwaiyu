import 'learner_model_store.dart';
import 'material_library.dart';
import 'material_prefs.dart';

/// 材料中心 v5 的**唯一需求事实源**(2026-11-04 用户拍板):
///
/// "按需求找材料"这一需求要影响材料中心**全局的材料推送机制** —— 不只是某个页面。
/// 所以把原来三处分散的需求收口到这里:
/// - 输入首页的难度胶囊(i+1/i+10/i+100/不限)
/// - 材料中心"我的需求"(难度 + 形式 kinds + 内容类型 contentTypes + 补充需求)
/// - 学习者目标(LearnerModel.goals:四六级/考研/雅思/托福/出国/学术工作…)
///
/// 读的是 Hive(`keyMaterialPrefs` + `learner_model_v2`),**不新增数据库表、不改 dbVersion**。
/// 全局推送统一走 [rank]:先按难度档排,再按目标加权(复用 MaterialLibrary 的纯函数),
/// 这样今日精读、各维度二级页、材料库排序都用同一套口径。
class MaterialNeed {
  final MaterialBand band;
  final Set<String> kinds;
  final Set<String> contentTypes;
  final List<String> goals;

  /// 用户补充需求(自由文本,会进 AI 检索提示)
  final String extra;

  const MaterialNeed({
    this.band = MaterialBand.any,
    this.kinds = const <String>{},
    this.contentTypes = const <String>{},
    this.goals = const <String>[],
    this.extra = '',
  });

  /// 从 Hive 读(每次进入材料中心调一次即可,内部很快:两个 key)
  static MaterialNeed load() {
    final prefs = MaterialPrefs.load();
    final learner = LearnerModelStore.load();
    return MaterialNeed(
      band: prefs.band,
      kinds: prefs.kinds,
      contentTypes: prefs.contentTypes,
      goals: learner.goals.isEmpty
          ? <String>[
              if ((learner.goal?.value ?? '').isNotEmpty) learner.goal!.value,
            ]
          : learner.goals,
      extra: prefs.extra,
    );
  }

  bool get isEmpty =>
      band.isAny &&
      kinds.isEmpty &&
      contentTypes.isEmpty &&
      goals.isEmpty &&
      extra.trim().isEmpty;

  /// 界面上的一行摘要 chip("i+10 挑战 · 四六级 · 外刊")
  List<String> get chips => <String>[
        if (!band.isAny) '${band.label} ${band == MaterialBand.i1 ? "舒适" : band == MaterialBand.i10 ? "挑战" : "快反馈"}',
        for (final g in goals) g,
        for (final k in kinds) MaterialPrefs.kindLabels[k] ?? k,
        if (extra.trim().isNotEmpty) extra.trim(),
      ];

  String get summary => isEmpty ? '还没设置需求' : chips.join(' · ');

  /// 全局推送排序:难度档优先,其次目标加权;同分保持原顺序。
  ///
  /// 这是"需求影响全局推送"的落点 —— 材料中心各列表、材料库、今日精读候选
  /// 都调它,不再各写一套排序。
  List<ShelfItem> rank(List<ShelfItem> items) {
    if (items.isEmpty) return items;
    final byBand = MaterialLibrary.rankForBand(items, band);
    if (goals.isEmpty) return byBand;
    return MaterialLibrary.rankForGoals(byBand, goals);
  }

  /// 交给 AI 搜索的补充提示(场景/补充需求),没有就空串
  String get aiHint {
    final parts = <String>[
      if (!band.isAny) '难度档:${band.label}(${band.description})',
      if (goals.isNotEmpty) '学习目标:${goals.join("、")}',
      if (extra.trim().isNotEmpty) extra.trim(),
    ];
    return parts.join(';');
  }

  MaterialNeed copyWith({
    MaterialBand? band,
    Set<String>? kinds,
    Set<String>? contentTypes,
    List<String>? goals,
    String? extra,
  }) =>
      MaterialNeed(
        band: band ?? this.band,
        kinds: kinds ?? this.kinds,
        contentTypes: contentTypes ?? this.contentTypes,
        goals: goals ?? this.goals,
        extra: extra ?? this.extra,
      );
}
