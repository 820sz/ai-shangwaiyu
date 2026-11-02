import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

// 复用输出模块的考试识别(中英混合/四六级泛化/多目标优先级都在那测过),
// 不在这里另写一套中英判断 —— 两套识别早晚会漂移成两个答案。
import 'output_source.dart' show targetExamOf;

/// 一条**考纲/目标考试词**(批 7 · P1-3)。
///
/// 数据来自 `assets/data/exam_vocab.json`(人工整理常用考试词 + 词频 rank)。
/// 字段刻意只有五个:挑词只需要"词/义/词性/属于哪些考试/多高频",
/// 多余字段(音标、例句)属于词条详情层,不该让词表变重。
class ExamWord {
  /// 单词(小写)
  final String word;

  /// 常用中文义项(可能含多个,用「；」分隔)
  final String zh;

  /// 词性缩写(n./v./adj./adv.…;多词性用「/」连接)
  final String pos;

  /// 属于哪些考试:取值见 [ExamVocab.examIds](一词可多标签)
  final List<String> exams;

  /// 全局词频排名(1 最高频;越大越生僻)。排序/挑词都用它。
  final int rank;

  const ExamWord({
    required this.word,
    required this.zh,
    required this.pos,
    required this.exams,
    required this.rank,
  });

  /// 单条容错解析:不是 Map / 缺 word / rank 非法 → null(整表不因一条坏数据报废)。
  ///
  /// 为什么 zh/pos 缺失仍收:词表的主要用途是"按目标挑词"与"估算差距",
  /// 没有中文释义的词仍然能出现在练习里(释义可从词库/上下文补);但 word 与
  /// rank 缺了就没法排序/去重,直接丢。
  static ExamWord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final word = '${raw['word'] ?? ''}'.trim().toLowerCase();
    if (word.isEmpty) return null;
    final rank = _toInt(raw['rank']);
    if (rank == null || rank <= 0) return null;
    final exams = <String>[];
    final rawExams = raw['exams'];
    if (rawExams is List) {
      for (final item in rawExams) {
        final id = '$item'.trim().toLowerCase();
        if (ExamVocab.examIds.contains(id) && !exams.contains(id)) {
          exams.add(id);
        }
      }
    }
    return ExamWord(
      word: word,
      zh: '${raw['zh'] ?? ''}'.trim(),
      pos: '${raw['pos'] ?? ''}'.trim(),
      exams: List.unmodifiable(exams),
      rank: rank,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'word': word,
    'zh': zh,
    'pos': pos,
    'exams': exams,
    'rank': rank,
  };

  @override
  String toString() => 'ExamWord($word, $pos $zh, ${exams.join('/')}, #$rank)';

  static int? _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }
}

/// 解析整张词表(纯函数,可单测;不依赖 assets)。
///
/// 兼容两种顶层形状:`{"meta":{...},"words":[...]}`(当前资产)与裸数组
/// (未来若换数据源,直接给数组也能用)。
/// 容错原则:坏 JSON → 空表 + debugPrint(不抛);单条坏数据 → 跳过;
/// 重复词(不区分大小写)→ 保留 rank 更靠前的一条。
List<ExamWord> parseExamVocab(String raw) {
  try {
    final decoded = jsonDecode(raw);
    final listRaw = decoded is Map ? decoded['words'] : decoded;
    if (listRaw is! List) return const <ExamWord>[];
    final byWord = <String, ExamWord>{};
    for (final item in listRaw) {
      final word = ExamWord.fromJson(item);
      if (word == null) continue;
      final key = word.word.toLowerCase();
      final existing = byWord[key];
      if (existing == null || word.rank < existing.rank) {
        byWord[key] = word;
      }
    }
    final out = byWord.values.toList(growable: false)
      ..sort((a, b) => a.rank.compareTo(b.rank));
    return out;
  } catch (e) {
    debugPrint('ReadFlow 考纲词表解析失败(当空表处理): $e');
    return const <ExamWord>[];
  }
}

/// 考纲/目标考试词表服务(批 7 · P1-3)。
///
/// 背景(审计 C1-10):助理五维里的「距目标词表还差多少词」一直恒为 null,
/// 因为**没有数据源**;练习中心也只有四六级内置精选。这一层补三件事:
/// 1. 加载一份常用考试词资产(五类考试,一词多标签);
/// 2. 按考试/按用户多选目标挑词(给"按考试分表出题"当输入);
/// 3. 用**公开的近似规模常量**估算差距 —— 没有基线就返回 null,绝不编数字。
class ExamVocab {
  ExamVocab._();

  /// 词表资产路径(与 pubspec 的 `assets/data/` 目录声明对应)
  static const String assetPath = 'assets/data/exam_vocab.json';

  /// 支持的考试 id(与 JSON 里的 exams 标签一致)
  static const List<String> examIds = <String>[
    'cet4',
    'cet6',
    'kaoyan',
    'ielts',
    'toefl',
  ];

  /// 考试中文名(UI 展示与提示词共用一份文案)
  static const Map<String, String> examLabels = <String, String>{
    'cet4': '四级',
    'cet6': '六级',
    'kaoyan': '考研',
    'ielts': '雅思',
    'toefl': '托福',
  };

  /// 目标规模(词数)**公开口径的近似值**,只用于"距目标还差多少词"的估算:
  /// 四六级 4500/6000、考研 5500、雅思 7000、托福 8000 是常见培训口径,
  /// 官方从未发布过精确词表;所以这里写成常量并明确标注"近似",不冒充考纲。
  static const Map<String, int> targetSizes = <String, int>{
    'cet4': 4500,
    'cet6': 6000,
    'kaoyan': 5500,
    'ielts': 7000,
    'toefl': 8000,
  };

  static List<ExamWord>? _cache;

  /// 资产是否已加载(含"加载失败但已标记为空"的降级状态)
  static bool get isLoaded => _cache != null;

  /// 已加载的全部词(按 rank 升序;未加载时为空表)
  static List<ExamWord> get all =>
      List<ExamWord>.unmodifiable(_cache ?? const <ExamWord>[]);

  /// 首次读资产;失败降级为空表(不抛,不阻塞助理首页)。
  ///
  /// 可注入 [bundle] 便于单测;正常调用不传。
  static Future<void> ensureLoaded({AssetBundle? bundle}) async {
    if (_cache != null) return;
    try {
      final raw = await (bundle ?? rootBundle).loadString(assetPath);
      _cache = parseExamVocab(raw);
      if (_cache!.isEmpty) {
        debugPrint('ReadFlow 考纲词表为空(资产缺失或全部条目被过滤)');
      }
    } catch (e) {
      // 资产缺失/打包漏了都不能让"距目标差多少词"把整页拖垮
      debugPrint('ReadFlow 考纲词表加载失败(降级为空表): $e');
      _cache = const <ExamWord>[];
    }
  }

  /// 测试注入词表(传 null 清空缓存);生产代码不要调用。
  @visibleForTesting
  static void seedForTest(List<ExamWord>? words) {
    _cache = words == null
        ? null
        : List<ExamWord>.unmodifiable(
            List<ExamWord>.of(words)..sort((a, b) => a.rank.compareTo(b.rank)),
          );
  }

  /// 按考试筛选(rank 升序)。[limit] > 0 时只取前 N 个;未知考试 → 空表。
  static List<ExamWord> wordsFor(String examId, {int limit = 0}) {
    final id = examId.trim().toLowerCase();
    if (!examIds.contains(id)) return const <ExamWord>[];
    final out = <ExamWord>[
      for (final w in _cache ?? const <ExamWord>[])
        if (w.exams.contains(id)) w,
    ];
    out.sort((a, b) => a.rank.compareTo(b.rank));
    if (limit > 0 && out.length > limit) {
      return List<ExamWord>.unmodifiable(out.sublist(0, limit));
    }
    return out;
  }

  /// 按用户多选目标合并挑词(去重,按 rank 升序)。
  ///
  /// 目标识别复用 [targetExamOf](四六级泛化/中英混合/明确目标优先都在那里);
  /// 未识别出考试(如「兴趣阅读」「新概念」)→ 空表,不瞎猜。
  static List<ExamWord> wordsForGoals(List<String> examGoals) {
    final ids = <String>{};
    for (final goal in examGoals) {
      final exam = _examForGoal(goal);
      if (exam != null) ids.add(exam);
    }
    if (ids.isEmpty) return const <ExamWord>[];
    final seen = <String>{};
    final out = <ExamWord>[];
    for (final w in _cache ?? const <ExamWord>[]) {
      if (!w.exams.any(ids.contains)) continue;
      if (!seen.add(w.word.toLowerCase())) continue;
      out.add(w);
    }
    out.sort((a, b) => a.rank.compareTo(b.rank));
    return out;
  }

  /// 距目标词表还差多少词(助理五维「词汇量」维度的依据)。
  ///
  /// 口径(**绝不编数字**):
  /// - 没有目标(全是兴趣类目标)→ null;
  /// - 没有词汇量基线([vocabEstimate] null/≤0)→ null(不能拿 0 当基线);
  /// - 多目标时 targetSize 取**最小**的那个(避免拿最高的托福规模把差距放大);
  /// - 已达标 → 0(不是负数)。
  static int? goalWordsGap(List<String> examGoals, int? vocabEstimate) {
    if (examGoals.isEmpty) return null;
    if (vocabEstimate == null || vocabEstimate <= 0) return null;
    final sizes = <int>[];
    for (final goal in examGoals) {
      final exam = _examForGoal(goal);
      final size = exam == null ? null : targetSizes[exam];
      if (size != null) sizes.add(size);
    }
    if (sizes.isEmpty) return null;
    sizes.sort();
    final minTarget = sizes.first;
    final gap = minTarget - vocabEstimate;
    return gap > 0 ? gap : 0;
  }

  /// 主目标考试(助理/出题优先用这个);识别不出或只认出"新概念" → null。
  ///
  /// 注意用 `targetExamOf` 的**两趟**语义:明确目标压过泛化目标,
  /// 所以 `['四六级','雅思']` 会得到 ielts 而不是 cet4。
  static String? primaryExam(List<String> examGoals) {
    final exam = targetExamOf(examGoals);
    if (exam == null) return null;
    return examIds.contains(exam) ? exam : null;
  }

  /// 某个考试的目标规模(近似口径);未知考试 → null。
  static int? targetSizeOf(String examId) =>
      targetSizes[examId.trim().toLowerCase()];

  /// 单个目标文本 → 考试 id;不是五类考试之一(兴趣/新概念) → null。
  static String? _examForGoal(String goal) {
    final exam = targetExamOf(<String>[goal]);
    if (exam == null) return null;
    return examIds.contains(exam) ? exam : null;
  }
}
