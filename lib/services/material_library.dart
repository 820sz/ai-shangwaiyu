import 'dart:convert';

import '../models/learner_model.dart';
import '../models/vocabulary.dart';
import 'database.dart';
import 'input_prefs.dart';
import 'learner_context.dart';
import 'material_prefs.dart';
import 'material_source.dart';
import 'original_search.dart';
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

  /// 用户自定义分类名(v2.9:材料导入的分组,如「新视野教材」)
  final String? group;

  /// 材料来路(v2.9:import 导入 / gutenberg 等公开源 / ai 生成)
  final String origin;

  /// 中文标题(v2.10:标题中文化要落库,任何界面都能显示中文)
  final String titleCn;

  /// 封面/配图地址(v2.11:入库时存下**源头自带的图** —— 公版书封面、
  /// RSS 头图、文章 og:image)。为空时界面回落程序化封面。
  final String? coverUrl;

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
    this.group,
    this.origin = '',
    this.titleCn = '',
    this.coverUrl,
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
  /// 材料来路(v2.10,用户 10/4 第 3 条)。
  ///
  /// 用户原话:"'输入界面'的'材料导入',**为什么会默认保存在材料中心点过的文章**?
  /// 我说了啊,这个功能是用来保存用户**自己手动导入**的东西啊,不是材料中心那些东西。"
  ///
  /// 所以入库时就把来路写清楚:手动导入(paste/file/image/link)记 `import`,
  /// 公开源(公版书/论文/外媒)记 `feed`,AI 生成记 `ai`。
  /// 「材料导入」列表**只认 import**,材料中心的公开源一律不进那里。
  static String originOf(String sourceId) {
    const imported = {'paste', 'file', 'import', 'image', 'link', 'clipboard'};
    if (imported.contains(sourceId)) return 'import';
    if (sourceId == 'ai' || sourceId == 'ai_article') return 'ai';
    return 'feed';
  }

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
        // v2.11:封面/配图 —— 入库时把源头自带的图存下来(公版书封面、RSS 头图、
        // 文章 og:image)。用户 10/5 原话:"很多材料明明链接点开里面自己就有配图啊,
        // 把原材料的原插图作为材料的封面不就行了吗?" 不落库的话,重启后
        // 材料库/书架又只剩程序化色块。空的写 null,让界面回落程序化封面。
        'cover_url': _coverUrlOf(doc),
        // v2.10:来路(材料导入 vs 材料中心的公开源)
        'origin': originOf(doc.sourceId),
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

  /// **只取用户自己导入的材料**(v2.10,用户 10/4 第 3 条)。
  ///
  /// 「材料导入」这一块只该显示他手动导进来的东西(教材/粘贴的文本/图片/链接),
  /// 材料中心里点过的公版书、论文、外刊**不属于这里**(那是"材料库"的事)。
  /// 判据是 `materials.origin`;老数据没有 origin 的按 source 反推(见 [originOf])。
  static Future<List<ShelfItem>> importedShelf({int limit = 200}) async {
    final all = await shelf(limit: limit);
    return all
        .where((s) => s.origin == 'import' || originOf(s.source) == 'import')
        .toList();
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
      group: (r['group_name'] as String?)?.trim().isEmpty ?? true
          ? null
          : '${r['group_name']}'.trim(),
      origin: '${r['origin'] ?? ''}',
      titleCn: (r['title_cn'] as String?)?.trim() ?? '',
      coverUrl: (r['cover_url'] as String?)?.trim().isEmpty ?? true
          ? null
          : '${r['cover_url']}'.trim(),
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

  /// 入库时要落库的封面地址(v2.11,纯函数)。
  ///
  /// 优先级:
  /// 1. 文档自己带的图(抓取时从 RSS 头图 / 文章 og:image 拿到的);
  /// 2. 公版书:**按书号现算**官方封面 —— 实测 `cache/epub/<id>/pg<id>.cover.medium.jpg`
  ///    12/12 全部 200 + image/jpeg(含 1/2/3/11/55/1000),无 404 风险;
  ///    ⚠️ 这是 PG **自动排版生成**的封面(不是原书插图),但它是"有脸"的成本最低来源;
  /// 3. 拿不到就 null → 界面回落程序化封面(`MaterialCover`),永不白块。
  static String? _coverUrlOf(MaterialDoc doc) {
    final own = (doc.coverUrl ?? '').trim();
    if (own.startsWith('http')) return own;
    if (doc.sourceId == 'gutenberg') {
      final id = MaterialSourceService.gutenbergIdOf(doc.sourceId2);
      if (id != null) return OriginalHit.gutenbergCoverUrl('$id');
    }
    return null;
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
        'textbook' => '教材',
        'exam' => '应试真题',
        _ => '文章',
      };

  /// 材料种类 → 学习分类(存生词时的默认分类,v2.7)。
  ///
  /// 为什么需要:阅读器收藏生词时必须带上"分类 + 材料名",否则词会掉进
  /// 「未归类」(用户第 6(2) 条抱怨的就是这个现象)。这里给一个合理默认,
  /// 用户在阅读器里可以随时改「保存位置」。
  static String categoryOfKind(String kind) => switch (kind) {
        'book' => '书籍',
        'news' => '外刊',
        'podcast' => '外刊',
        'paper' => '碎片文章',
        'article' => '碎片文章',
        'wiki' => '其他',
        _ => '其他',
      };

  /// 按**用户自选的难度档**排序(v2.7,用户第 4 条)。
  ///
  /// 与 [rankForToday] 的区别:那个按"通用 i+1 舒适区"打分,这个把用户选的档位
  /// 当第一优先级 —— 符合档位的排最前,偏易/偏难靠后(而不是隐藏:用户可能
  /// 就是想读那本难书)。读了一半的材料仍然加权,避免"换档位后进度材料沉底"。
  static List<ShelfItem> rankForBand(
    List<ShelfItem> items,
    MaterialBand band,
  ) {
    if (band.isAny) return rankForToday(items);
    final score = <ShelfItem, int>{};
    for (final it in items) {
      var s = 0;
      final c = it.coverage;
      if (c != null) s += band.contains(c) ? 100 : -20;
      if (it.finished) {
        s -= 40;
      } else if (it.percent > 0) {
        s += 20;
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

  /// 按**用户目标**排序(v3 批 8 · 拍板 #1 后半:目标要影响材料排序)。
  ///
  /// 为什么需要有这一层:书架原来只按难度档/进度排,用户选了"四六级"之后
  /// 并没有看到"和考试相关的东西更靠前"。这里用**可解释的信号**加分:
  /// - kind:exam(真题/考卷)命中考试目标 = 最大加分;news 命中"读外刊/看新闻";
  /// - 标题/中文标题里出现目标关键词(四六级/cet/真题/雅思/托福/考研/外刊…);
  /// - 已在读的继续加权(不让目标排序把在读材料挤下去)。
  ///
  /// 纯函数、稳定排序(同分保持传入顺序),便于单测与"关掉按目标优先"时复用。
  static List<ShelfItem> rankForGoals(
    List<ShelfItem> items,
    List<String> examGoals,
  ) {
    if (examGoals.isEmpty || items.isEmpty) return items;
    final goals = examGoals.map((g) => g.toLowerCase()).toList();
    bool goalHas(Iterable<String> keys) => goals.any(
          (g) => keys.any((k) => g.contains(k)),
        );
    final wantsExam = goalHas(const ['四六级', '四级', '六级', 'cet', '考研', '雅思', '托福']);
    final wantsNews = goalHas(const ['外刊', '新闻', '阅读']);
    final wantsAcademic = goalHas(const ['学术', '工作', '论文', '考研']);

    int scoreOf(ShelfItem it) {
      var s = 0;
      final title = '${it.title} ${it.titleCn}'.toLowerCase();
      final kind = it.kind.toLowerCase();
      if (wantsExam && (kind == 'exam' || title.contains('真题') || title.contains('cet'))) {
        s += 100;
      }
      if (wantsNews && (kind == 'news' || kind == 'article')) s += 40;
      if (wantsAcademic && (kind == 'paper' || title.contains('论文'))) s += 40;
      for (final keyword in const [
        '四六级', '四级', '六级', 'cet', '考研', '雅思', '托福', '外刊', '真题',
        'exam', 'news',
      ]) {
        if (title.contains(keyword)) {
          s += 12;
        }
      }
      // 在读材料不因"目标排序"沉底
      if (it.percent > 0 && !it.finished) s += 8;
      return s;
    }

    final indexed = <(int, ShelfItem)>[
      for (var i = 0; i < items.length; i++) (i, items[i]),
    ];
    indexed.sort((a, b) {
      final byScore = scoreOf(b.$2).compareTo(scoreOf(a.$2));
      if (byScore != 0) return byScore;
      return a.$1.compareTo(b.$1); // 同分保持原顺序(稳定)
    });
    return [for (final e in indexed) e.$2];
  }

  /// 列表去重(按 id,保留首次出现)—— 材料中心曾出现重复条目。
  static List<ShelfItem> dedupeShelf(List<ShelfItem> items) {
    final seen = <int>{};
    final out = <ShelfItem>[];
    for (final it in items) {
      if (seen.add(it.id)) out.add(it);
    }
    return out;
  }

  /// 回译句/摘要段的原始选取逻辑等不在本文件;这里只放"排序/去重"这类纯函数。
  static List<ShelfItem> rankForToday(List<ShelfItem> items) {    final score = <ShelfItem, int>{};
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

  // ═══════════════════════════════════════════════════════════════════
  // 目标影响排序(v3 批 8 · P1-6 / 用户批注 #1 后半)
  // ═══════════════════════════════════════════════════════════════════

  /// 考试目标 → 命中关键词表(用小写英文 + 中文同义词)。
  ///
  /// 为什么需要翻译同义词:材料元数据里既有中文也有英文(`考研`/`kaoyan`、
  /// `四六级`/`cet-4`),只按目标原文匹配会漏掉一半;表只覆盖 App 访谈里
  /// 出现过的目标,未知目标用目标原文本身兜底(不硬猜)。
  static const Map<String, List<String>> goalKeywordTable = {
    '四六级': ['四六级', '四级', '六级', 'cet-4', 'cet4', 'cet-6', 'cet6'],
    '考研': ['考研', '研究生', 'kaoyan', 'postgraduate'],
    '雅思': ['雅思', 'ielts'],
    '托福': ['托福', 'toefl'],
    '高考': ['高考', 'gaokao'],
    '中考': ['中考'],
    '出国': ['出国', '留学', 'abroad', 'overseas'],
    '工作': ['工作', '职场', '商务', 'business', 'career', 'workplace'],
    '日常': ['日常', '口语', '生活', 'daily', 'conversation'],
  };

  /// 目标 → 更该读的材料形态(kind):写作/应试类偏好新闻与教材书籍,
  /// 学术目标偏好论文。只影响排序权重,不做硬过滤(用户仍能看到全部材料)。
  static const Map<String, Set<String>> _goalKindAffinity = {
    '四六级': {'news', 'book', 'podcast'},
    '考研': {'paper', 'news', 'book'},
    '雅思': {'news', 'podcast', 'book'},
    '托福': {'paper', 'news', 'podcast'},
    '高考': {'book', 'news'},
    '中考': {'book', 'news'},
    '出国': {'news', 'podcast', 'paper'},
    '工作': {'news', 'podcast'},
    '日常': {'podcast', 'news'},
  };

  /// 按"与考试目标的相关度"给材料库排序(纯函数,可单测)。
  ///
  /// 信号(从强到弱,全部来自本地元数据,不额外请求):
  /// 1. **标题/分类里命中目标关键词**(含同义词)→ +40;
  /// 2. **材料形态与目标匹配**(如考研→论文、四六级→外刊/书籍)→ +15;
  /// 3. **难度档符合用户自选档** → +25(与"只看符合"是两回事:这里是软排序);
  /// 4. 正在读的材料 +10(目标相关且已开始,最该继续);已读完 -15(不是目标问题,
  ///    只是优先级让给没读的)。
  ///
  /// 没有目标时**保持原顺序**(只做去重)—— 不能凭空重排材料库,否则用户会
  /// 觉得列表在随机跳。排序是稳定排序,同分按 id 倒序(与其它 rank 函数一致)。
  static List<ShelfItem> rankShelfForGoals(
    List<ShelfItem> items,
    InputPreferences prefs,
  ) {
    final unique = dedupeBy(
      items,
      urlOf: (it) => it.url,
      titleOf: (it) => '${it.titleCn} ${it.title}',
    );
    final goals = prefs.examGoals
        .map(_goalHead)
        .where((g) => g.isNotEmpty)
        .toList(growable: false);
    if (goals.isEmpty) return List<ShelfItem>.from(unique);

    final keywords = <String>{};
    final kinds = <String>{};
    for (final goal in goals) {
      keywords.add(goal.toLowerCase());
      final table = goalKeywordTable.entries.where(
        (e) => goal.toLowerCase().contains(e.key.toLowerCase()) ||
            e.value.any((v) => goal.toLowerCase().contains(v)),
      );
      for (final entry in table) {
        keywords.addAll(entry.value);
        kinds.addAll(_goalKindAffinity[entry.key] ?? const <String>{});
      }
    }

    final score = <ShelfItem, int>{};
    for (final it in unique) {
      var s = 0;
      final haystack = '${it.title} ${it.titleCn} ${it.group ?? ''} '
              '${it.kind} ${it.source} ${it.origin}'
          .toLowerCase();
      if (keywords.any((k) => k.length >= 2 && haystack.contains(k))) s += 40;
      if (kinds.contains(it.kind)) s += 15;
      final c = it.coverage;
      if (c != null && !prefs.band.isAny && prefs.band.materialBand.contains(c)) {
        s += 25;
      }
      if (it.finished) {
        s -= 15;
      } else if (it.percent > 0) {
        s += 10;
      }
      score[it] = s;
    }
    final sorted = List<ShelfItem>.from(unique);
    sorted.sort((a, b) {
      final byScore = (score[b] ?? 0).compareTo(score[a] ?? 0);
      if (byScore != 0) return byScore;
      return b.id.compareTo(a.id);
    });
    return sorted;
  }

  /// 去掉目标串里的期限括号(`四六级(半年内)` → `四六级`),与偏好层的口径一致
  static String _goalHead(String raw) {
    var head = raw.trim();
    final paren = head.indexOf(RegExp(r'[（(]'));
    if (paren > 0) head = head.substring(0, paren).trim();
    head = head.split(RegExp(r'[+＋、]')).first.trim();
    return head;
  }

  // ═══════════════════════════════════════════════════════════════════
  // 今日推荐难度标签(元数据区间,不伪造精确覆盖率)
  // ═══════════════════════════════════════════════════════════════════

  /// 难度区间从低到高(A2→C1),用于"预计难度"标签。
  static const List<String> difficultyBands = [
    'A2~B1',
    'B1~B2',
    'B2~C1',
    'C1+',
  ];

  /// 区间 → 一句用户能看懂的程度词(与区间一起显示,如"预计 B1~B2 · 中等")。
  ///
  /// 用"入门/中等/进阶/高难"而不是"简单/困难":难度是相对的,带价值判断的词
  /// 会让用户觉得被冒犯(尤其 i+100 快反馈档的用户就爱读难的)。
  static const Map<String, String> difficultyBandDesc = {
    'A2~B1': '入门',
    'B1~B2': '中等',
    'B2~C1': '进阶',
    'C1+': '高难',
  };

  /// 用**源元数据**给一条材料一个"预计难度区间"(纯函数,可单测)。
  ///
  /// ## 为什么只给区间、不冒充覆盖率
  /// 列表页拿不到正文,真实覆盖率必须抓全文 + 本地词频分析(一次网络往返,
  /// 且可能失败)。所以这里只根据**来源形态 / 材料类型 / 已知长度**给出一个
  /// 诚实的区间,并把口径写进 [basis](界面必须原样展示"非精确覆盖率")。
  /// 真正分析过的卡(例如今日精读有 `MaterialAnalysis`)继续显示真实认知率,
  /// 不用这个估算 —— 两者在界面上必须能区分开。
  ///
  /// ## 信号与方向
  /// - 类型:论文最高(学术英语)、公版书/百科次高(长句多)、播客口语最低
  ///   (VOA 慢速英语再降一档)、外刊新闻居中;
  /// - 长度:只有**真实词数**才参考(<300 词降一档,>1500 词升一档);
  ///   摘要字数不算长度 —— 摘要常常只有一句导语,按它判长短会系统性误判。
  static ({String label, String band, String difficulty, String basis})
      estimateDifficulty({
    required String sourceId,
    String kind = '',
    int? wordCount,
  }) {
    final k = kind.trim().isNotEmpty
        ? kind.trim()
        : (MaterialSourceService.sourceOf(sourceId)?.kind ?? 'article');
    var idx = switch (k) {
      // 论文摘要:学术英语,默认最高档
      'paper' => 3,
      // 公版书/百科:长句多、词汇跨度大
      'book' || 'wiki' => 2,
      // 播客:VOA 慢速英语降一档,其它口语材料按中档
      'podcast' => sourceId == 'voa_le' ? 0 : 1,
      // 外刊/新闻/文章(含 NASA、ScienceDaily 这类科普新闻)
      _ => 1,
    };
    // 长度信号:有真实词数才参考 —— 短摘要往往只是"标题党",长文跨度更大
    final wc = wordCount ?? 0;
    if (wc > 0) {
      if (wc < 300) {
        idx -= 1;
      } else if (wc > 1500) {
        idx += 1;
      }
    }
    final band = difficultyBands[idx.clamp(0, difficultyBands.length - 1)];
    final difficulty = difficultyBandDesc[band] ?? '中等';
    // 口径文案是给用户看的,必须说清"估算"与"非精确覆盖率"两件事;
    // 有真实词数时把"长度"也列进依据,没有就不列(不编信号)
    final basis = wc > 0
        ? '根据来源/长度/类型估算,非精确覆盖率'
        : '根据来源/类型估算,非精确覆盖率';
    return (
      label: '预计 $band · $difficulty',
      band: band,
      difficulty: difficulty,
      basis: basis,
    );
  }

  /// 从摘要估算词数(纯函数)。
  ///
  /// ⚠️ 只用于"摘要大概多长"这类展示,不作为 [estimateDifficulty] 的长度信号
  /// (理由见那个函数:摘要长度 ≠ 正文长度)。
  static int excerptWordCount(String text) {
    final matches = RegExp(r"[A-Za-z][A-Za-z'-]*").allMatches(text);
    return matches.length;
  }

  // ═══════════════════════════════════════════════════════════════════
  // 用户黑名单过滤(C1-14:公开源结果也要遵守「学习偏好」里的屏蔽词)
  // ═══════════════════════════════════════════════════════════════════

  /// 黑名单过滤的结果:保留项 + 被过滤条数。
  ///
  /// 为什么要把"过滤掉几条"一起带出来:用户设了屏蔽词,列表变短时必须告诉他
  /// "是你自己的设置过滤掉的",否则他会以为公开源没内容了(静默缩短 = 信息丢失)。
  static BlocklistFilterResult<T> filterBlocked<T>(
    Iterable<T> items,
    InputPreferences prefs, {
    required String Function(T) titleOf,
    required String? Function(T) sourceOf,
    required List<String> Function(T) genresOf,
  }) {
    final all = items.toList(growable: false);
    if (prefs.blockedKeywords.isEmpty && prefs.blockedTopics.isEmpty) {
      return BlocklistFilterResult<T>(kept: all, hidden: 0);
    }
    final kept = <T>[];
    var hidden = 0;
    for (final item in all) {
      // 判断口径唯一事实源是 [InputPreferences.allowsMaterial]:
      // 标题 / 来源 / 题材任一命中屏蔽词即过滤(含大小写不敏感、包含匹配)。
      if (prefs.allowsMaterial(
        title: titleOf(item),
        source: sourceOf(item),
        genres: genresOf(item),
      )) {
        kept.add(item);
      } else {
        hidden++;
      }
    }
    return BlocklistFilterResult<T>(kept: kept, hidden: hidden);
  }

  /// 通用的"按链接/标题去重"(纯函数)。
  ///
  /// 为什么把去重放在这里:今日推荐(RSS 偶尔同一篇发两次)、材料库(同一材料
  /// 从不同链接入库)、分类页(多组检索词命中同一篇)都需要它 —— 三处各写一遍
  /// 就会出现"这里去了那里没去"的半吊子去重。
  ///
  /// 判定:链接**或**标题任一重复即视为重复(链接不同但标题相同的,多半是同一
  /// 篇被不同 entry 地址收了第二次)。没有链接也没有标题的条目无法判断,保留。
  static List<T> dedupeBy<T>(
    Iterable<T> items, {
    required String Function(T) urlOf,
    required String Function(T) titleOf,
  }) {
    final seenUrls = <String>{};
    final seenTitles = <String>{};
    final out = <T>[];
    for (final item in items) {
      final url = _dedupeKey(urlOf(item));
      final title = _dedupeKey(titleOf(item));
      final dupUrl = url.isNotEmpty && seenUrls.contains(url);
      final dupTitle = title.isNotEmpty && seenTitles.contains(title);
      if (dupUrl || dupTitle) continue;
      if (url.isNotEmpty) seenUrls.add(url);
      if (title.isNotEmpty) seenTitles.add(title);
      out.add(item);
    }
    return out;
  }

  static String _dedupeKey(String raw) {
    var key = raw.trim().toLowerCase();
    if (key.isEmpty) return '';
    while (key.endsWith('/')) {
      key = key.substring(0, key.length - 1);
    }
    return key;
  }
}

/// [MaterialLibrary.filterBlocked] 的返回值(纯数据,便于界面显示过滤计数)
class BlocklistFilterResult<T> {
  /// 通过黑名单的条目(保持原顺序)
  final List<T> kept;

  /// 被用户自己的屏蔽设置过滤掉的条数(0 = 没过滤)
  final int hidden;

  const BlocklistFilterResult({required this.kept, required this.hidden});

  /// 有没有条被过滤(界面据此显示"已按你的屏蔽设置过滤 N 条")
  bool get hasHidden => hidden > 0;

  @override
  String toString() =>
      'BlocklistFilterResult(kept: ${kept.length}, hidden: $hidden)';
}
