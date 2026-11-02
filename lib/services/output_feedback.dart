import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'database.dart';
import 'output_rubric.dart';

/// 输出回流层(v2.18.0,批 3 收尾):把「批改结果」变成**可积累的薄弱点**
/// 和**可进快照/周报的输出数据**。
///
/// 为什么这一层必须存在(侦察结论 `docs/research/output-and-tutor.md` §1.3):
/// - 用户天天写译,但错误只留在一次性的批改结果里 → 错误档案不涨、复习不调度,
///   助理快照里"输出"维度恒为空 → 助理报"近 30 天只有输入没有输出";
/// - 评分层拿到的是**模型自由文本**("时态不一致"/"用词不当"/"中式英语"…),
///   而 `error_tags` 已有固定标签体系(复习/读后测验在写)。如果直接把模型原文
///   当 tag 写库,错误档案会被几十种近义写法撕碎,统计与"复发"都失去意义。
///
/// 所以这里只做两件确定性的事:
/// 1. **归一**:模型文本 → 既有 tag(见 [tagKeywords]);**映射不上就丢弃**,
///    宁可不记,也不制造只出现一次、无法聚合的新标签;
/// 2. **聚合**:从 `output_attempts` 算输出维度的行为数据(次数/均分/题型/
///    维度均分/错误热点),供快照与周报使用(只读,不写库)。
class OutputFeedback {
  OutputFeedback._();

  /// 既有错误标签体系里与语法相关的标签(来源:`config/placement_bank.dart`
  /// 的语法小题 + `error_archive_screen.dart` 的来源说明)。
  static const List<String> grammarTags = ['时态', '冠词', '介词', '主谓一致', '虚拟语气'];

  /// 既有标签体系里"输出错误"可以写入的部分:5 个语法点 + 词汇。
  ///
  /// 为什么没有 `reading`:它是读后测验的内部分类,不是写作/翻译错误;
  /// 也没有"拼写/中式英语"这类细分 —— 项目既有体系里它们都归在「词汇」
  /// (错误档案的「词汇」本来就承载"词没掌握"),**不新造标签**。
  static const List<String> knownTags = ['时态', '冠词', '介词', '主谓一致', '虚拟语气', '词汇'];

  /// 归一映射:既有 tag → 命中关键词(小写包含匹配)。
  ///
  /// **顺序即优先级**:先具体语法点,最后才是泛化的「词汇」——
  /// 一条 "时态用错" 应该记「时态」而不是被「用词」抢先。
  static const Map<String, List<String>> tagKeywords = {
    '时态': ['时态', 'tense', '时态不一致', '动词时态'],
    '冠词': ['冠词', 'article'],
    '介词': ['介词', 'preposition'],
    '主谓一致': ['主谓一致', '主谓', 'agreement', '单复数一致'],
    '虚拟语气': ['虚拟语气', '虚拟', 'subjunctive'],
    // 词汇层面(用词/搭配/拼写/词形/中式英语)统一归「词汇」
    '词汇': [
      '用词',
      '词汇',
      '搭配',
      '词性',
      '近义词',
      '中式英语',
      'chinglish',
      '拼写',
      'spelling',
      '词形',
    ],
  };

  /// 单条文本(问题类型 + 中文原因) → 既有 tag;归一不了返回 null。
  ///
  /// 纯函数:不碰 DB、不依赖语言模型 —— 映射规则改了可以立刻单测验证
  /// ("哪些模型写法会被归到哪一类"是这一层最该被钉死的契约)。
  static String? canonicalTagFor(String text) {
    final low = text.toLowerCase();
    if (low.trim().isEmpty) return null;
    for (final entry in tagKeywords.entries) {
      for (final keyword in entry.value) {
        if (low.contains(keyword.toLowerCase())) return entry.key;
      }
    }
    return null;
  }

  /// 一批批改问题 → 本轮要写入错误档案的既有 tag 列表。
  ///
  /// **同轮去重**:一次作文里同一类错误出现 3 次,只算"这次练习又错了这一类"
  /// (+1),不按问题条数累加 —— 错误档案要回答"这个坑反复踩了几次",
  /// 而不是"这篇文章里有多少个逗号用错"。
  static List<String> canonicalErrorTags(List<ScoredIssue> issues) {
    final out = <String>[];
    for (final issue in issues) {
      final tag = canonicalTagFor('${issue.type} ${issue.reason}');
      if (tag != null && !out.contains(tag)) out.add(tag);
    }
    return out;
  }

  /// 纯文本类型列表 → 既有 tag 列表(去重、保持首次出现顺序)。
  ///
  /// 给**没走 ScoredIssue 的旧链路**复用(例如写译批改的
  /// `writing_logs.issues`/`error_summary` 只有 `type: 词汇/语法/表达优化` 文本)。
  static List<String> canonicalTagsFromTexts(Iterable<String> texts) {
    final out = <String>[];
    for (final text in texts) {
      final tag = canonicalTagFor(text);
      if (tag != null && !out.contains(tag)) out.add(tag);
    }
    return out;
  }

  /// 把一次批改的问题写进错误档案(错误档案 → 助理诊断 → 周报 的数据起点)。
  ///
  /// [source] 用错误档案已有的来源名,界面才会显示中文:
  /// - `'writing'` → 写译批改;
  /// - `'exercise'` → 回译练习;
  /// - 默认 `'output'`(通用输出; 错误档案暂未给它中文标签,接线时优先传前两个)。
  ///
  /// 返回**成功 bump 的标签数**(归一不上或写库失败都不计入);
  /// 失败静默 —— 错误档案写失败绝不能影响用户刚做完的练习结果页面。
  static Future<int> recordOutputFeedback({
    required List<ScoredIssue> issues,
    String source = 'output',
  }) async {
    final tags = canonicalErrorTags(issues);
    if (tags.isEmpty) return 0;
    var written = 0;
    for (final tag in tags) {
      try {
        await DatabaseService.bumpErrorTag(
          source: source,
          tag: tag,
          evidence: _evidenceFor(tag, issues),
        );
        written++;
      } catch (_) {
        // 静默:错误档案只是"锦上添花的复盘",不能反过来影响练习结果
      }
    }
    return written;
  }

  /// 直接把**已归一好的**标签列表写进错误档案。
  ///
  /// 给"批改结果不是 [ScoredIssue]"的旧链路用(例如写译批改的
  /// `writing_logs.issues` 是 `{type, reason}` 文本 Map):
  /// ```dart
  /// await OutputFeedback.recordErrorTags(
  ///   OutputFeedback.canonicalTagsFromTexts(
  ///     log.issues.map((e) => '${e['type']} ${e['reason']}'),
  ///   ),
  ///   source: 'writing',
  /// );
  /// ```
  /// 不在 [knownTags] 里的标签会被拒收(防调用方顺手塞进新造的标签)。
  static Future<int> recordErrorTags(
    Iterable<String> tags, {
    String source = 'output',
    String? evidence,
  }) async {
    var written = 0;
    final seen = <String>{};
    for (final tag in tags) {
      if (!knownTags.contains(tag) || !seen.add(tag)) continue;
      try {
        await DatabaseService.bumpErrorTag(
          source: source,
          tag: tag,
          evidence: evidence,
        );
        written++;
      } catch (_) {
        // 同上:写错误档案失败不影响用户正在做的事
      }
    }
    return written;
  }

  /// 从问题里挑一条能支撑这个 tag 的原文片段作为证据(错误档案要能"想起来")。
  /// 没有 span 时退化成中文原因;再长就截断(证据列是给人看的一句话)。
  static String? _evidenceFor(String tag, List<ScoredIssue> issues) {
    for (final issue in issues) {
      if (canonicalTagFor('${issue.type} ${issue.reason}') != tag) continue;
      final span = issue.span.trim();
      final text = span.isNotEmpty ? span : issue.reason.trim();
      if (text.isEmpty) continue;
      return text.length > 80 ? '${text.substring(0, 80)}…' : text;
    }
    return null;
  }

  /// 近 [days] 天的输出行为聚合(只读,供快照/周报/首页使用)。
  ///
  /// 返回:
  /// - `attempts`        本轮窗口内作答次数;
  /// - `avgScore`        rubric 均分(0..100 百分比;**null = 没有可评分作答**,
  ///                     不能写成 0 —— 与周报"没数据不能编"的纪律一致);
  /// - `lastAt`          最近一次作答时间(ISO 字符串,可空);
  /// - `byType`          按题型分布(取 `exercise_sets.section`;缺省 'unknown');
  /// - `recentScores`    最近 5 次得分百分比(时间升序,便于画趋势);
  /// - `dimensionAvg`    各评分维度均分百分比(key = 维度 key,如 language);
  /// - `topErrorTags`    归一后的高频错误标签(次数降序;映射不上的类型已丢弃);
  /// - `days`            实际统计窗口(调用方可知口径)。
  ///
  /// 失败返回安全默认值(空数据),绝不让快照/周报因一处查询失败而崩。
  static Future<Map<String, Object?>> outputSnapshot({
    int days = 30,
    DateTime? now,
  }) async {
    final windowDays = days < 1 ? 1 : (days > 365 ? 365 : days);
    final at = now ?? DateTime.now();
    final from = at.subtract(Duration(days: windowDays));
    final empty = <String, Object?>{
      'days': windowDays,
      'attempts': 0,
      'avgScore': null,
      'lastAt': null,
      'byType': <String, int>{},
      'recentScores': <double>[],
      'dimensionAvg': <String, double>{},
      'topErrorTags': <String, int>{},
    };
    try {
      final rows = await DatabaseService.listOutputAttempts(limit: 500);
      final inWindow = <(DateTime, Map<String, Object?>)>[];
      for (final row in rows) {
        final t = DateTime.tryParse('${row['created_at'] ?? ''}');
        if (t == null || t.isBefore(from) || t.isAfter(at)) continue;
        inWindow.add((t, row));
      }
      if (inWindow.isEmpty) return empty;

      // 题型在 exercise_sets.section;attempts 只有 set_id → 一次读题组做映射
      final sectionOf = <int, String>{};
      final setRows = await DatabaseService.listExerciseSets(limit: 200);
      for (final s in setRows) {
        final id = (s['id'] as num?)?.toInt();
        if (id != null) sectionOf[id] = '${s['section'] ?? ''}'.trim();
      }

      final byType = <String, int>{};
      final errorCounts = <String, int>{};
      final dimSum = <String, double>{};
      final dimCount = <String, int>{};
      final scoredPoints = <(DateTime, double)>[];
      var scoredTotal = 0.0;
      DateTime? lastAt;

      for (final (t, row) in inWindow) {
        if (lastAt == null || t.isAfter(lastAt)) lastAt = t;

        final setId = (row['set_id'] as num?)?.toInt();
        final section = setId == null ? '' : (sectionOf[setId] ?? '');
        final type = section.isEmpty ? 'unknown' : section;
        byType[type] = (byType[type] ?? 0) + 1;

        final score = _parseScoreJson('${row['score_json'] ?? ''}');
        if (score != null) {
          scoredTotal += score.percent;
          scoredPoints.add((t, score.percent));
          score.dimPercents.forEach((key, value) {
            dimSum[key] = (dimSum[key] ?? 0) + value;
            dimCount[key] = (dimCount[key] ?? 0) + 1;
          });
        }

        // 错误类型当时存的是模型原文(practice_flow 写入),这里再归一一次:
        // 保持"预览统计"与"错误档案"同一套标签,不让两处各有一套口径。
        final seen = <String>{};
        for (final raw in _decodeStringList(row['error_tags_json'])) {
          final tag = canonicalTagFor(raw);
          if (tag == null || !seen.add(tag)) continue;
          errorCounts[tag] = (errorCounts[tag] ?? 0) + 1;
        }
      }

      scoredPoints.sort((a, b) => a.$1.compareTo(b.$1));
      final recentScores = [
        for (final p in scoredPoints.length <= 5
            ? scoredPoints
            : scoredPoints.sublist(scoredPoints.length - 5))
          p.$2,
      ];
      final dimensionAvg = <String, double>{
        for (final key in dimSum.keys)
          if ((dimCount[key] ?? 0) > 0) key: dimSum[key]! / dimCount[key]!,
      };
      final topErrorTags = errorCounts.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        });

      return {
        'days': windowDays,
        'attempts': inWindow.length,
        'avgScore': scoredPoints.isEmpty ? null : scoredTotal / scoredPoints.length,
        'lastAt': lastAt?.toIso8601String(),
        'byType': byType,
        'recentScores': recentScores,
        'dimensionAvg': dimensionAvg,
        'topErrorTags': <String, int>{for (final e in topErrorTags) e.key: e.value},
      };
    } catch (e) {
      // 输出数据是"锦上添花":查询失败退化成空数据,快照/周报照常生成,
      // 对应结论自然缺席(而不是报一行假数字)。
      debugPrint('ReadFlow outputSnapshot 读取失败(已降级): $e');
      return empty;
    }
  }

  /// 解析 `output_attempts.score_json` → 总分百分比 + 各维度百分比。
  ///
  /// 口径:百分比 = total_score ÷ (各维度 max_score 之和) × 100。
  /// 为什么不用固定分母(15/5):不同 rubric 满分不同,百分比才能跨题型比较;
  /// 维度 max 缺失/为 0 的条目直接跳过(宁可不计入,也不按 0 分冤枉用户)。
  static ({double percent, Map<String, double> dimPercents})? _parseScoreJson(
    String raw,
  ) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final total = (decoded['total_score'] as num?)?.toDouble();
      if (total == null) return null;
      final dims = decoded['dimensions'];
      if (dims is! List) return null;
      var maxTotal = 0.0;
      final dimPercents = <String, double>{};
      for (final d in dims) {
        if (d is! Map) continue;
        final max = (d['max_score'] as num?)?.toDouble() ?? 0;
        if (max <= 0) continue;
        maxTotal += max;
        final key = '${d['key'] ?? ''}'.trim();
        final score = (d['score'] as num?)?.toDouble();
        if (key.isNotEmpty && score != null) {
          dimPercents[key] = (score / max * 100).clamp(0, 100).toDouble();
        }
      }
      if (maxTotal <= 0) return null;
      return (
        percent: (total / maxTotal * 100).clamp(0, 100).toDouble(),
        dimPercents: dimPercents,
      );
    } catch (_) {
      return null;
    }
  }

  static List<String> _decodeStringList(Object? raw) {
    if (raw is List) {
      return [for (final e in raw) '${e ?? ''}'.trim()].where((s) => s.isNotEmpty).toList();
    }
    final text = '${raw ?? ''}'.trim();
    if (text.isEmpty || text == 'null') return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return [for (final e in decoded) '${e ?? ''}'.trim()]
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}
