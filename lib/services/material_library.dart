import 'dart:convert';

import '../models/learner_model.dart';
import '../models/vocabulary.dart';
import 'database.dart';
import 'learner_context.dart';
import 'material_source.dart';
import 'text_difficulty.dart';
import 'word_frequency.dart';

/// 材料难度分析结果(入库前算好,列表与阅读器直接用)
class MaterialAnalysis {
  final int wordCount;
  final int uniqueWords;
  final int newTypes;
  final int estMinutes;

  /// 已知词覆盖率(按**词形**算,偏保守)
  final double coverage;

  /// 已知词占**词次**比例(泛读体验看这个)
  final double knownTokenRatio;

  /// 每 100 词的生词词次数
  final double newWordDensity;
  final String cefr;
  final List<String> topNewWords;

  const MaterialAnalysis({
    required this.wordCount,
    required this.uniqueWords,
    required this.newTypes,
    required this.estMinutes,
    required this.coverage,
    required this.knownTokenRatio,
    required this.newWordDensity,
    required this.cefr,
    required this.topNewWords,
  });

  /// i+1 判定(阈值与 LearnerContext 单点定义一致)
  bool get tooHard => knownTokenRatio < LearnerContext.tooHardTokenRatio;
  bool get comfortable => LearnerContext.isComfortable(knownTokenRatio);
  bool get tooEasy => knownTokenRatio >= LearnerContext.tooEasyTokenRatio;

  String get hint => LearnerContext.difficultyHint(knownTokenRatio);

  Map<String, Object?> toJson() => {
        'word_count': wordCount,
        'unique_words': uniqueWords,
        'new_types': newTypes,
        'est_minutes': estMinutes,
        'coverage': coverage,
        'known_token_ratio': knownTokenRatio,
        'new_word_density': newWordDensity,
        'cefr': cefr,
        'top_new_words': topNewWords,
      };

  static MaterialAnalysis fromJson(Map<String, Object?> json) => MaterialAnalysis(
        wordCount: _int(json['word_count']),
        uniqueWords: _int(json['unique_words']),
        newTypes: _int(json['new_types']),
        estMinutes: _int(json['est_minutes']),
        coverage: _dbl(json['coverage']),
        knownTokenRatio: _dbl(json['known_token_ratio']),
        newWordDensity: _dbl(json['new_word_density']),
        cefr: '${json['cefr'] ?? ''}',
        // 容错:字段类型不对(比如历史上存成字符串)时当空列表处理,
        // 不能让一条坏记录把书架/阅读器打成白屏
        topNewWords: json['top_new_words'] is List
            ? (json['top_new_words'] as List).map((e) => '$e').toList()
            : const [],
      );

  static int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
  static double _dbl(Object? v) => v is double ? v : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
}

/// 入库结果
class IngestedMaterial {
  final int materialId;
  final MaterialAnalysis analysis;
  final String title;
  const IngestedMaterial({
    required this.materialId,
    required this.analysis,
    required this.title,
  });
}

/// 书架条目(材料库列表用)
class ShelfItem {
  final int id;
  final String title;
  final String kind;
  final String source;
  final String cefr;
  final int wordCount;
  final double? coverage;
  final int estMinutes;
  final double percent;
  final int minutesRead;
  final int pickedWords;
  final String? audioUrl;
  final String url;
  final bool finished;

  const ShelfItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.source,
    required this.cefr,
    required this.wordCount,
    required this.coverage,
    required this.estMinutes,
    required this.percent,
    required this.minutesRead,
    required this.pickedWords,
    required this.url,
    this.audioUrl,
    this.finished = false,
  });

  String get progressLabel => finished
      ? '已读完'
      : (percent > 0 ? '已读 ${percent.round()}%' : '未开始');
}

/// 材料中心的核心逻辑(v2.0)。
///
/// 职责边界:
/// - **难度分析**(覆盖率/生词密度/i+1 判定)全部本地算,零 API 成本;
/// - **入库**统一走 [DatabaseService.upsertMaterial](按 source+source_id 去重),
///   正文分块写 material_content,阅读器按块加载;
/// - **选材**用同一套阈值([LearnerContext]),避免"推荐说不难、阅读器说偏难"。
class MaterialLibrary {
  MaterialLibrary._();

  /// 分析一段文本(纯函数,可单测)。
  /// [knownWords] 由 [LearnerContext.knownWords] 提供(名次 ≤ 词汇量估计的词
  /// + 用户标记已掌握/学习中的词)。
  static Future<MaterialAnalysis> analyze(
    String text, {
    required LearnerModel model,
    List<Vocabulary> vocab = const [],
    int? vocabOverride,
  }) async {
    await WordFrequency.ensureLoaded();
    final known = LearnerContext.knownWords(
      model: model,
      vocab: vocab,
      normalize: TextDifficulty.normalize,
      vocabOverride: vocabOverride,
    );
    final d = TextDifficulty.analyze(
      text,
      knownWords: known,
      wpm: LearnerContext.wpmFor(model),
    );
    return MaterialAnalysis(
      wordCount: d.totalTokens,
      uniqueWords: d.uniqueTypes,
      newTypes: d.newTypes,
      estMinutes: d.estMinutes,
      coverage: d.coverage,
      knownTokenRatio: d.knownTokenRatio,
      newWordDensity: d.newWordDensity,
      cefr: d.cefr,
      topNewWords: d.topNewWords,
    );
  }

  /// 把抓到的原始文档分析 + 入库,返回 materialId 与分析结果
  static Future<IngestedMaterial> ingestDoc(
    MaterialDoc doc, {
    required LearnerModel model,
    List<Vocabulary> vocab = const [],
  }) async {
    final analysis = await analyze(
      doc.plainText.isEmpty
          ? doc.chunks.map((c) => c.text).join('\n\n')
          : doc.plainText,
      model: model,
      vocab: vocab,
    );
    final id = await DatabaseService.upsertMaterial(
      {
        'kind': doc.kind,
        'source': doc.sourceId,
        'source_id': doc.sourceId2,
        'title': doc.title,
        'author': doc.author,
        'url': doc.url,
        'license': doc.license,
        'language': doc.language,
        'word_count': analysis.wordCount,
        'unique_words': analysis.uniqueWords,
        'cefr': analysis.cefr,
        'coverage': analysis.coverage,
        'new_word_density': analysis.newWordDensity,
        'est_minutes': analysis.estMinutes,
        'chapters': doc.chunks.length,
        'audio_url': doc.audioUrl,
        'difficulty_json': jsonEncode(analysis.toJson()),
        'cached_at': DateTime.now().toIso8601String(),
      },
      chunks: [
        for (final c in doc.chunks)
          {
            'chunk_index': c.index,
            'title': c.title,
            'text': c.text,
          },
      ],
    );
    return IngestedMaterial(materialId: id, analysis: analysis, title: doc.title);
  }

  /// 粘贴文本 / 手动材料入库(source=manual)
  static Future<IngestedMaterial> ingestText({
    required String title,
    required String text,
    required LearnerModel model,
    List<Vocabulary> vocab = const [],
    String kind = 'article',
    String? url,
    String? author,
  }) async {
    final analysis = await analyze(text, model: model, vocab: vocab);
    final id = await DatabaseService.upsertMaterial(
      {
        'kind': kind,
        'source': 'manual',
        // 手动材料用标题做身份,避免同一篇重复入库
        'source_id': title.trim(),
        'title': title.trim(),
        'author': author,
        'url': url,
        'license': '用户自备材料(仅个人学习使用)',
        'language': 'en',
        'word_count': analysis.wordCount,
        'unique_words': analysis.uniqueWords,
        'cefr': analysis.cefr,
        'coverage': analysis.coverage,
        'new_word_density': analysis.newWordDensity,
        'est_minutes': analysis.estMinutes,
        'chapters': 1,
        'difficulty_json': jsonEncode(analysis.toJson()),
        'cached_at': DateTime.now().toIso8601String(),
      },
      chunks: [
        {'chunk_index': 0, 'title': null, 'text': text},
      ],
    );
    return IngestedMaterial(
      materialId: id,
      analysis: analysis,
      title: title.trim(),
    );
  }

  /// 材料库列表(带进度),按最近更新时间倒序
  static Future<List<ShelfItem>> shelf({int limit = 50}) async {
    final rows = await DatabaseService.getRecentMaterials(limit: limit);
    return rows.map(_toShelfItem).toList();
  }

  static ShelfItem _toShelfItem(Map<String, Object?> r) {
    double? cov;
    final rawCov = r['coverage'];
    if (rawCov is num) cov = rawCov.toDouble();
    return ShelfItem(
      id: _asInt(r['id']),
      title: '${r['title'] ?? '(未命名材料)'}',
      kind: '${r['kind'] ?? 'article'}',
      source: '${r['source'] ?? ''}',
      cefr: '${r['cefr'] ?? ''}',
      wordCount: _asInt(r['word_count']),
      coverage: cov,
      estMinutes: _asInt(r['est_minutes']),
      percent: _asDouble(r['percent']),
      minutesRead: _asInt(r['minutes']),
      pickedWords: _asInt(r['picked_words']),
      url: '${r['url'] ?? ''}',
      audioUrl: (r['audio_url'] as String?)?.isEmpty ?? true
          ? null
          : '${r['audio_url']}',
      finished: r['finished_at'] != null,
    );
  }

  static int _asInt(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
  static double _asDouble(Object? v) =>
      v is double ? v : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  /// 材料种类的中文名(列表与推荐共用同一份文案)
  static String kindLabel(String kind) => switch (kind) {
        'news' => '外刊/新闻',
        'book' => '原版书',
        'podcast' => '播客/听力',
        'wiki' => '百科',
        'paper' => '论文',
        _ => '文章',
      };

  /// 按 i+1 给书架排序:优先"正好合适且未读完"的材料
  /// (纯函数,便于单测:列表顺序直接影响用户先读什么)
  static List<ShelfItem> rankForToday(List<ShelfItem> items) {
    final score = <ShelfItem, int>{};
    for (final it in items) {
      var s = 0;
      if (it.finished) {
        s -= 40;
      } else if (it.percent > 0) {
        s += 30; // 还没读完:继续读比新开一份更容易启动
      }
      if (it.coverage != null) {
        final c = it.coverage!;
        if (c >= 0.95 && c < 0.98) {
          s += 50; // 舒适精读区
        } else if (c >= 0.98) {
          s += 20; // 偏易:能读但收益低
        } else if (c >= 0.90) {
          s += 10; // 挑战区
        } else {
          s -= 30; // 过载
        }
      }
      score[it] = s;
    }
    final sorted = List<ShelfItem>.from(items);
    sorted.sort((a, b) {
      final byScore = (score[b] ?? 0).compareTo(score[a] ?? 0);
      if (byScore != 0) return byScore;
      return b.id.compareTo(a.id);
    });
    return sorted;
  }
}
