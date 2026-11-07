/// 输出 · **练习草稿**(生成的题组退出后还能继续)。
///
/// 用户 2026-11-07 真机反馈(第 6 条第 4 点):
/// > 练习材料退出不留存、下次进入又要重新找。
///
/// 事实是题组**已经落库**了(`exercise_sets`/`exercise_items` 在出题时就写入),
/// 真正丢的是"练到第几题、每题写了什么" —— 以及首页没有任何"继续上次练习"入口。
///
/// 这一层解决两件事(都不动数据库结构):
/// 1. **草稿指针**:最近一次未完成练习的 `setId + 当前题号 + 每题作答草稿`,
///    存在现有 Hive settings box(单行 JSON,可重复写);
/// 2. **题组还原**:把 `exercise_sets` + items 行还原成 `OutputSetSpec`,
///    与题库"原样重练"共用同一套字段口径(historically 这段逻辑在题库页里)。
///
/// 已提交的批改结果不重复存:Hive 草稿只存"未提交的作答文本 + 当前位置";
/// 已批改的题从 `output_attempts.score_json` 还原(权威数据在库里)。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import 'database.dart';
import 'output_composer.dart';
import 'output_rubric.dart';

/// 一份未完成练习的草稿(单行 JSON 存 Hive settings box)。
class OutputDraft {
  /// 对应 `exercise_sets.id`
  final int setId;

  /// 题组标题(首页"继续上次练习"卡片直接显示,不用再查库)
  final String title;

  /// 当前停在第几题(0-based)
  final int index;

  /// 每题的作答草稿(index → 文本);只存非空文本
  final Map<int, String> texts;

  /// 最近一次修改时间(按它取"最近一次练习")
  final DateTime updatedAt;

  const OutputDraft({
    required this.setId,
    required this.title,
    required this.index,
    required this.texts,
    required this.updatedAt,
  });

  bool get hasContent => texts.values.any((t) => t.trim().isNotEmpty);
  int get answeredCount => texts.values.where((t) => t.trim().isNotEmpty).length;

  OutputDraft copyWith({int? index, Map<int, String>? texts, String? title}) =>
      OutputDraft(
        setId: setId,
        title: title ?? this.title,
        index: index ?? this.index,
        texts: texts ?? this.texts,
        updatedAt: DateTime.now(),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'set_id': setId,
        'title': title,
        'index': index,
        'texts': <String, String>{
          for (final e in texts.entries) '${e.key}': e.value,
        },
        'updated_at': updatedAt.toIso8601String(),
      };

  static OutputDraft? fromJson(Object? raw) {
    Map<String, dynamic>? map;
    if (raw is Map) {
      map = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    if (map == null) return null;
    final setId = (map['set_id'] as num?)?.toInt();
    // setId 允许 0:测试/未落库题组也能演练草稿恢复;负数视为坏数据
    if (setId == null || setId < 0) return null;
    final texts = <int, String>{};
    final rawTexts = map['texts'];
    if (rawTexts is Map) {
      for (final e in rawTexts.entries) {
        final i = int.tryParse('${e.key}');
        final text = '${e.value}';
        if (i == null || text.trim().isEmpty) continue;
        texts[i] = text;
      }
    }
    return OutputDraft(
      setId: setId,
      title: '${map['title'] ?? ''}'.trim(),
      index: ((map['index'] as num?)?.toInt() ?? 0).clamp(0, 999),
      texts: texts,
      updatedAt:
          DateTime.tryParse('${map['updated_at']}') ?? DateTime.now(),
    );
  }

  @override
  String toString() =>
      'OutputDraft(set=$setId, index=$index, 已写 ${texts.length} 题)';
}

/// 草稿存取(Hive settings box 单行 JSON;box 没打开/读写失败一律静默降级)。
///
/// 为什么用 Hive 而不是新表:本轮纪律是**不加数据库列/表**,而"练到第几题、
/// 每题草稿"是纯客户端状态;库里的 `output_attempts` 已经是权威作答记录,
/// 草稿只是它之前的临时里程。
class OutputDraftStore {
  OutputDraftStore._();

  /// 单行 key(与 Hive settings box 里其它设置并列)
  static const String key = 'output_draft_v1';

  static Box? get _box {
    try {
      return Hive.box(AppConstants.hiveBoxSettings);
    } catch (_) {
      return null; // 未初始化(测试/极早期启动):静默降级,不抛
    }
  }

  /// 读草稿;没有/坏数据 → null
  static OutputDraft? load() {
    try {
      final raw = _box?.get(key);
      if (raw == null) return null;
      return OutputDraft.fromJson(raw);
    } catch (e) {
      debugPrint('ReadFlow 练习草稿读取失败(当没有草稿): $e');
      return null;
    }
  }

  /// 写草稿(整份覆盖)。失败静默:草稿丢了大不了重填,不能挡住练习。
  static Future<void> save(OutputDraft draft) async {
    try {
      await _box?.put(key, draft.toJson());
    } catch (e) {
      debugPrint('ReadFlow 练习草稿保存失败(不影响练习): $e');
    }
  }

  /// 清草稿(完成/放弃后调用)
  static Future<void> clear() async {
    try {
      await _box?.delete(key);
    } catch (e) {
      debugPrint('ReadFlow 练习草稿清理失败(忽略): $e');
    }
  }
}

/// 把 `exercise_sets` + items 行还原成 [OutputSetSpec](题库重练与草稿恢复共用)。
///
/// 与旧实现(题库页 `_open`)字段口径完全一致:题面/参考/rubric/来源/卷面身份
/// 全带上,保证"继续上次练习"与"题库原样重练"看到的是同一套题。
OutputSetSpec? setSpecFromExerciseRow(Map<String, Object?>? full) {
  if (full == null) return null;
  final items = (full['items'] as List?) ?? const <Object?>[];
  final tasks = <OutputTaskSpec>[];
  for (final raw in items) {
    if (raw is! Map) continue;
    tasks.add(OutputTaskSpec(
      tier: outputTierOfItem(
        section: '${full['section'] ?? ''}',
        type: '${raw['type'] ?? ''}',
      ),
      type: '${raw['type'] ?? ''}',
      promptZh: '${raw['prompt_zh'] ?? ''}',
      promptEn: '${raw['prompt_en'] ?? ''}',
      reference: '${raw['reference_answer'] ?? ''}',
      rubricId: '${raw['rubric_id'] ?? ''}',
      wordCount: (raw['word_count'] as num?)?.toInt() ?? 0,
      sourceSpan: '${raw['source_span'] ?? ''}',
      source: '${full['source'] ?? 'builtin'}',
      verifyStatus: '${full['verify_status'] ?? 'pending'}',
    ));
  }
  if (tasks.isEmpty) return null;
  return OutputSetSpec(
    title: '${full['title'] ?? '历史题组'}',
    tier: tasks.first.tier,
    source: '${full['source'] ?? 'builtin'}',
    examType: '${full['exam_type'] ?? 'none'}',
    section: '${full['section'] ?? ''}',
    rubricId: '${full['rubric_id'] ?? ''}',
    paperYear: (full['paper_year'] as num?)?.toInt(),
    paperLabel: '${full['paper_label'] ?? ''}',
    sourceSite: siteOfLicenseNote('${full['license_note'] ?? ''}'),
    licenseNote: '${full['license_note'] ?? ''}',
    verifyStatus: '${full['verify_status'] ?? 'pending'}',
    tasks: tasks,
  );
}

/// 题型 → 四阶(与题库页旧逻辑同口径;抽出来避免两处漂移)
OutputTier outputTierOfItem({required String section, required String type}) {
  if (type == 'spelling' || type == 'blank_filling') return OutputTier.word;
  if (type == 'back_translation' ||
      type == 'sentence_rewrite' ||
      type == 'error_correction') {
    return OutputTier.sentence;
  }
  if (type == 'summary' || type == 'paragraph' || type == 'opinion') {
    return OutputTier.paragraph;
  }
  if (type == 'exam_writing' || type == 'writing' || type == 'translation') {
    return OutputTier.essay;
  }
  switch (section) {
    case 'back_translation':
    case 'sentence_rewrite':
      return OutputTier.sentence;
    case 'summary':
      return OutputTier.paragraph;
    case 'writing':
    case 'translation':
      return OutputTier.essay;
    default:
      return OutputTier.paragraph;
  }
}

/// 首页「继续上次练习」用的聚合结果。
class ResumablePractice {
  final OutputSetSpec set;
  final OutputDraft draft;

  const ResumablePractice({required this.set, required this.draft});

  /// 「第 N/M 题」展示(草稿题号越界时夹到最后一题)
  String get progressLabel => '第 ${draft.index + 1}/${set.tasks.length} 题';

  /// 已写草稿的题数(首页卡片上给"写了一半"的证据)
  String get answeredLabel =>
      draft.answeredCount == 0 ? '还没作答' : '已写 ${draft.answeredCount} 题';
}

/// 读"最近一次未完成的练习":草稿存在 + 题组还能从库里还原才算。
///
/// 任何一步失败都返回 null(首页不显示入口,不弹错)。
Future<ResumablePractice?> loadResumablePractice() async {
  final draft = OutputDraftStore.load();
  if (draft == null) return null;
  try {
    final full = await DatabaseService.getExerciseSet(draft.setId);
    final set = setSpecFromExerciseRow(full);
    if (set == null) return null;
    // 题号越界(题组被改短/旧草稿)→ 夹回可用范围
    final safeIndex = draft.index.clamp(0, set.tasks.length - 1);
    final safeDraft =
        safeIndex == draft.index ? draft : draft.copyWith(index: safeIndex);
    return ResumablePractice(set: set, draft: safeDraft);
  } catch (e) {
    debugPrint('ReadFlow 继续上次练习读取失败(隐藏入口): $e');
    return null;
  }
}

/// 草稿里已批改题目的还原:从 `output_attempts` 读 score_json,按**题目序号**返回。
///
/// 为什么从库里读而不是存 Hive:批改结果是权威数据(统计/错误档案都靠它),
/// 存两份必然漂移;草稿只负责"没提交的文本"。
Future<Map<int, ScoredOutput>> loadScoredByIndex(int setId) async {
  final out = <int, ScoredOutput>{};
  if (setId <= 0) return out;
  try {
    final full = await DatabaseService.getExerciseSet(setId);
    final items = (full?['items'] as List?) ?? const <Object?>[];
    final itemIdToIndex = <int, int>{};
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is! Map) continue;
      final id = (item['id'] as num?)?.toInt();
      if (id != null) itemIdToIndex[id] = i;
    }
    final attempts = await DatabaseService.listOutputAttempts(
      setId: setId,
      limit: 200,
    );
    // attempts 按 created_at 倒序;同一题多次提交取最新一次
    for (final row in attempts) {
      final itemId = (row['item_id'] as num?)?.toInt();
      if (itemId == null) continue;
      final index = itemIdToIndex[itemId];
      if (index == null || out.containsKey(index)) continue;
      final scored = ScoredOutput.fromJson(row['score_json']);
      if (scored != null) out[index] = scored;
    }
  } catch (e) {
    debugPrint('ReadFlow 历史批改读取失败(不影响练习): $e');
  }
  return out;
}

/// 顺手把 `LearnerModel` 的字段搬出来给草稿标题用(避免 UI 再引一层)。
String draftTitleOf(OutputSetSpec set, {String fallback = '上次的练习'}) {
  final title = set.title.trim();
  return title.isEmpty ? fallback : title;
}
