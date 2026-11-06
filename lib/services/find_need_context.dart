import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import '../models/learner_model.dart';
import 'input_prefs.dart';
import 'learner_context.dart';
import 'learner_model_store.dart';
import 'material_need.dart';
import 'material_prefs.dart';
import 'tutor_insights.dart';
import 'tutor_snapshot.dart';

/// 「找材料 · 按我的情况找」的**唯一数据出口**(2026-11-06)。
///
/// 用户要求(设计文档 `docs/FIND-MATERIAL-REDESIGN-2026-11-06.md` §3.1):
/// 按需找必须**真的读取学习助理统计的用户情况**,而且每条依据都要能指回真实字段,
/// 没数据就写「待测」——**不许编数字**(与 `tutor_insights.dart` 的纪律一致:
/// `measured == false` 时 evidence 里不许出现任何统计值)。
///
/// 这一层只做三件事:
/// 1. 把散在四处的事实源收成一份只读快照:
///    `MaterialNeed`(需求:难度档/形式/内容类型/目标/补充需求)、
///    `InputPreferences`(目标/兴趣/屏蔽项/每日时长)、
///    `LearnerModel`(词汇量基线/CEFR/目标/兴趣/屏蔽词)、
///    `TutorDashboard.load()`(学习助理五维现状:弱项/阅读速度/近 30 天读完…);
/// 2. 产出界面的 4 行依据 + 「为什么推这些」一句话(全部来自上面字段);
/// 3. 产出"按需找"要用的检索词/中文需求描述(给 `MaterialDiscovery.discover`)。
///
/// **纯读取,不写任何偏好/模型** —— 页面上改需求仍走既有设置入口。
class FindNeedContext {
  /// 材料中心 v5 的需求事实源(难度档 / 形式 / 内容类型 / 目标 / 补充需求)
  final MaterialNeed need;

  /// 输入偏好(目标多选 / 兴趣 / 屏蔽项 / 每日时长)
  final InputPreferences prefs;

  /// 学习者模型(词汇量基线、CEFR、目标、屏蔽词)
  final LearnerModel model;

  /// 学习助理五维现状的输入快照(可空:助理数据读不到时整块降级)
  final InsightSource? insight;

  const FindNeedContext({
    required this.need,
    required this.prefs,
    required this.model,
    this.insight,
  });

  /// 从现有服务读一份(每次进「找材料」读一次:Hive 两个 key + 助理快照)。
  ///
  /// 任何一块失败都降级:页面照常打开,只是少几行依据/写「待测」。
  /// [dashboard] 可注入(测试/已有助理页数据时省一次 DB 组装)。
  static Future<FindNeedContext> load({
    DateTime? now,
    TutorDashboard? dashboard,
  }) async {
    var need = const MaterialNeed();
    try {
      need = MaterialNeed.load();
    } catch (_) {
      // Hive 未打开/脏数据:用空需求继续(页面仍可用)
    }
    var prefs = InputPreferences();
    try {
      prefs = InputPreferences.load();
    } catch (_) {
      // 同上:用空偏好继续
    }
    var model = LearnerModel();
    try {
      model = LearnerModelStore.load();
    } catch (_) {
      // 同上:用空模型继续
    }
    TutorDashboard? data = dashboard;
    if (data == null) {
      try {
        data = await TutorSnapshotService.load(now: now);
      } catch (_) {
        data = null;
      }
    }
    return FindNeedContext(
      need: need,
      prefs: prefs,
      model: model,
      insight: data?.source,
    );
  }

  // ── 面板要展示的真实字段 ────────────────────────────────────────────

  /// 词汇量估计(测量值优先,其次模型里的推断/自报)
  int? get vocabEstimate =>
      insight?.vocabEstimate ?? model.vocabEstimate?.value;

  /// CEFR(测试来源才有;null = 没测过)
  String? get cefr => insight?.cefr ?? model.cefr?.value;

  /// 基线来源说明(直接给 UI 用,措辞来自 [LearnerContext.describeBaseline])
  String get baselineText => LearnerContext.describeBaseline(model);

  /// 是否已有"测量出来"的词汇量基线(自报不算)
  bool get hasMeasuredBaseline => LearnerContext.hasMeasuredBaseline(model);

  /// 学习目标(多选;来自助理访谈 / 输入偏好)
  List<String> get goals {
    final fromInsight = insight?.examGoals ?? const <String>[];
    if (fromInsight.isNotEmpty) return fromInsight;
    return prefs.examGoals;
  }

  /// 兴趣题材(LearnerModel.interests ∪ MaterialPrefs.genres)
  List<String> get interests => prefs.interests;

  /// 弱项(错误档案 / 写译批改的错误标签 → 累计次数,次数降序)
  Map<String, int> get errorCounts => insight?.errorTagCounts ?? const {};

  /// 弱项标签(最多 3 个,按次数降序;空 = 还没建过档 → 显示"待测")
  List<String> get weakTags {
    final entries = errorCounts.entries
        .where((entry) => entry.key.trim().isNotEmpty && entry.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(3).map((entry) => entry.key).toList();
  }

  /// 近 30 天读完的材料数(null = 没有真实统计)
  int? get materialsFinished30d => insight?.materialsFinished30d;

  /// 在读材料数(null = 没有真实统计)
  int? get materialsReading => insight?.materialsReading;

  /// 实测阅读速度(词/分;null = 没测过)
  int? get readingWpm {
    final wpm = insight?.readingWpm;
    if (wpm != null && wpm > 0) return wpm.round();
    final extra = model.extras['reading_wpm'];
    if (extra is int && extra >= 60 && extra <= 1000) return extra;
    if (extra is num && extra >= 60 && extra <= 1000) return extra.toInt();
    return null;
  }

  /// 每日可投入分钟数(null = 没设置)
  int? get dailyMinutes => insight?.dailyMinutes ?? prefs.dailyMinutes;

  /// 屏蔽题材(命中即过滤)
  List<String> get blockedTopics => prefs.blockedTopics;

  /// 屏蔽关键词(包含匹配,忽略大小写)
  List<String> get blockedKeywords => prefs.blockedKeywords;

  /// 助理数据是否整块为空(空 → 面板全部"待测",并引导去测一次)
  bool get hasTutorData => insight != null && !insight!.isEmpty;

  // ── 面板 4 行(设计文档 §3.1 的界面口径)────────────────────────────

  /// 4 行依据:难度档 / 学习目标 / 弱项 / 最近阅读。
  ///
  /// [measured] = false 的行,界面上**只显示"待测 + 怎么测"**,不显示任何数字。
  List<FindNeedRow> get rows {
    final bandRow = FindNeedRow(
      key: 'band',
      label: '难度档',
      value: need.band.isAny
          ? '不限(还没选档)'
          : '${need.band.label} · ${need.band.description}',
      measured: !need.band.isAny,
      hint: need.band.isAny ? '去设置里选 i+1 / i+10 / i+100,推荐会更准' : null,
    );

    final goalList = goals;
    final goalRow = FindNeedRow(
      key: 'goals',
      label: '学习目标',
      value: goalList.isEmpty ? '待测 · 还没设置学习目标' : goalList.join(' · '),
      measured: goalList.isNotEmpty,
      hint: goalList.isEmpty ? '在学习偏好里选目标(四六级/雅思/兴趣阅读…)或让助理问你' : null,
    );

    final tags = weakTags;
    final weakRow = FindNeedRow(
      key: 'weak',
      label: '弱项',
      value: tags.isEmpty
          ? '待测 · 做一次写译批改或测验就能算'
          : '语法:${tags.map((tag) => '$tag ${errorCounts[tag] ?? 0} 次').join(' · ')}',
      measured: tags.isNotEmpty,
      hint: tags.isEmpty ? '读完一篇做读后测验,或做一次写译批改,错误标签会进错误档案' : null,
    );

    final finished = materialsFinished30d;
    final wpm = readingWpm;
    final readingParts = <String>[
      if (finished != null) '近 30 天读完 $finished 篇',
      if (wpm != null) '$wpm 词/分',
    ];
    final readingRow = FindNeedRow(
      key: 'reading',
      label: '最近阅读',
      value: readingParts.isEmpty ? '待测 · 先读完一篇,这里会出现你的语速' : readingParts.join(' · '),
      measured: readingParts.isNotEmpty,
      hint: readingParts.isEmpty ? '阅读器会记录进度与阅读时长,读一篇就有了' : null,
    );

    return <FindNeedRow>[bandRow, goalRow, weakRow, readingRow];
  }

  // ── "为什么推这些"(设计文档 §3.2 级别 1:只用画像 + 需求字段)──────

  /// 「为什么推这些」:一句到两句,每段都来自上面的真实字段。
  ///
  /// 空数据时**不编**:只说"还没设置需求,先按普遍适合中级学习者的难度找"。
  List<String> get reasons {
    final out = <String>[];
    final bandPart = need.band.isAny
        ? ''
        : '按 ${need.band.label} 档';
    final goalsPart = goals.isEmpty ? '' : '对准目标 ${goals.take(2).join('、')}';
    if (bandPart.isNotEmpty || goalsPart.isNotEmpty) {
      final lead = <String>[
        if (bandPart.isNotEmpty) bandPart,
        if (goalsPart.isNotEmpty) goalsPart,
      ].join('、');
      out.add('$lead 挑材料,优先找真正能读到原文的。');
    }
    if (weakTags.isNotEmpty) {
      out.add('语法弱项「${weakTags.first}」会在阅读里标出来,读完顺手复习。');
    }
    final blocked = <String>[
      ...blockedTopics.take(2),
      ...blockedKeywords.take(2),
    ].where((item) => item.trim().isNotEmpty).toList();
    if (blocked.isNotEmpty) {
      out.add('已避开你屏蔽的:${blocked.join('、')}。');
    }
    if (out.isEmpty) {
      out.add('还没设置需求 —— 先按普遍适合中级学习者的难度找,读完再按真实数据校准。');
    }
    return out;
  }

  // ── 检索输入(给 MaterialDiscovery.discover)─────────────────────

  /// 按需找的检索词:需求里的补充文本 + 目标 + 拉丁字母兴趣(与频道页同一口径)。
  ///
  /// 空 → `english reading` 兜底(保证有东西可搜,而不是给用户空白页)。
  List<String> queries() {
    final out = <String>[];
    final extra = need.extra.trim();
    if (extra.isNotEmpty) out.add(extra);
    for (final goal in goals) {
      final text = goal.trim();
      if (text.isNotEmpty) out.add(text);
    }
    for (final interest in interests) {
      if (RegExp(r'[A-Za-z]').hasMatch(interest)) out.add(interest.trim());
    }
    final unique = <String>[];
    for (final item in out) {
      if (item.isEmpty || unique.contains(item)) continue;
      unique.add(item);
      if (unique.length >= 6) break;
    }
    if (unique.isEmpty) unique.add('english reading');
    return unique;
  }

  /// 给 AI 规划 / 补救轮的中文需求描述(不要把它当英文检索词)。
  String get needText {
    final parts = <String>[
      if (need.summary.trim().isNotEmpty) need.summary.trim(),
      if (weakTags.isNotEmpty) '想补语法弱项:${weakTags.join('、')}',
      if (dailyMinutes != null) '每天可读 $dailyMinutes 分钟',
    ];
    if (parts.isEmpty) return '按我的水平找能读到原文的真实材料';
    return '按我的需求找真实材料:${parts.join(';')}';
  }

  /// 交给 AI 的完整提示(难度/目标/补充需求 + 弱项;空项自动省略)
  String get aiHint {
    final parts = <String>[
      if (need.aiHint.trim().isNotEmpty) need.aiHint.trim(),
      if (weakTags.isNotEmpty) '语法弱项:${weakTags.join('、')}',
      if (readingWpm != null) '阅读速度约 $readingWpm 词/分',
    ];
    return parts.join(';');
  }

  /// 这条候选能不能展示:黑名单(题材/关键词)命中就过滤 —— 与材料推荐同一口径
  /// (`InputPreferences.allowsMaterial` 是唯一事实源)。
  bool allows({required String title, String source = '', List<String> genres = const []}) =>
      prefs.allowsMaterial(title: title, source: source, genres: genres);
}

/// 面板的一行依据(界面只用它渲染,不自己拼文案)。
class FindNeedRow {
  /// 稳定 id(`band` / `goals` / `weak` / `reading`,UI 用它配图标)
  final String key;

  /// 行名(难度档 / 学习目标 / 弱项 / 最近阅读)
  final String label;

  /// 值文案(没数据时以「待测 · …」开头,**不含任何数字**)
  final String value;

  /// 这一行是否有真实数据
  final bool measured;

  /// 没数据时告诉用户"怎么测"(有数据的行可为 null)
  final String? hint;

  const FindNeedRow({
    required this.key,
    required this.label,
    required this.value,
    required this.measured,
    this.hint,
  });

  @override
  String toString() => 'FindNeedRow($key, measured=$measured, $value)';
}

/// 「找材料」入口的**搜索历史**(设计方向 A 右上角 `[历史]`)。
///
/// 复用 `MaterialPrefs` 已经在用的那份 Hive 数据
/// (`AppConstants.keyMaterialSearchHistory`,格式 `{分类: 上次搜索词}`),
/// 因为 `MaterialPrefs` 只暴露了 [MaterialPrefs.lastQueryFor] /
/// [MaterialPrefs.rememberQuery](单分类),而入口页要"列出全部 + 清空"。
/// 读写同一 key、同一 JSON 格式,两边互相兼容;不新增存储、不改 MaterialPrefs。
class FindSearchHistory {
  /// 自由搜用的分类 key(与 [MaterialPrefs.rememberQuery] 的 category 参数对应)
  static const String freeCategory = 'find:free';

  static Box get _box => Hive.box(AppConstants.hiveBoxSettings);

  /// 全部历史搜索词(**新的在前**,去重;读不到返回空)。
  static List<String> load() {
    try {
      final raw = _box.get(AppConstants.keyMaterialSearchHistory);
      final map = <String, String>{};
      if (raw is String && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) => map['$key'] = '$value');
        }
      } else if (raw is Map) {
        raw.forEach((key, value) => map['$key'] = '$value');
      }
      final out = <String>[];
      for (final value in map.values.toList().reversed) {
        final text = value.trim();
        if (text.isEmpty || out.contains(text)) continue;
        out.add(text);
      }
      return out;
    } catch (_) {
      return const <String>[];
    }
  }

  /// 记一条自由搜关键词(与 MaterialPrefs 共用实现,格式不会漂)
  static Future<void> remember(String query) =>
      MaterialPrefs.rememberQuery(freeCategory, query);

  /// 清空全部历史(写回空 map,不删 key —— 与 MaterialPrefs 的读法兼容)
  static Future<void> clear() async {
    try {
      await _box.put(AppConstants.keyMaterialSearchHistory, jsonEncode(<String, String>{}));
    } catch (_) {
      // 清空失败不抛:UI 刷新后仍显示旧历史,用户可再点一次
    }
  }
}
