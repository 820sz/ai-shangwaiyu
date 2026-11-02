import 'dart:async';

import '../models/learner_model.dart';
import '../models/vocabulary.dart';
import '../services/deepseek_search.dart';
import '../services/input_prefs.dart';
import '../services/material_library.dart';
import '../services/material_source.dart';
import '../services/original_search.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// **按需找材料 · 发现流水线**(v3 · 批 2 · C1-3/C1-5/C1-6/C1-7)
/// ═══════════════════════════════════════════════════════════════════════
///
/// 用户 2026-11-01 的原话:
/// > "输入里的需要最大程度发挥 AI(尤其是 deepseek v4.1 flash 1017)的适配,
/// >  以及 AI 找资源、爬材料的能力 …… 并且做好在 AI 学习软件这一场景下的
/// >  个性化、可选择化、具有指导性的运用。"
///
/// 旧实现的问题(侦察结论,见 `docs/research/input-ai.md`):
/// - AI 只把中文需求翻成英文检索词,返回 3 条 query **只用第 1 条**;
/// - 模型点名(picks)的作品**不参与检索**;
/// - 检索结果卡的难度是按源类型猜的,真实难度要抓回正文才算;
/// - 没有"官方联网检索"能力(现在有了 `/v1/tools/search` + `/v1/tools/fetch`)。
///
/// 这条流水线把顺序钉死为:
/// ```
/// 需求(InputPreferences)
///   → 检索计划(调用方传入 queries,通常来自 AI)
///   → 多源并发检索(公开源 + DeepSeek 官方 Search)
///   → 抓正文
///   → 本地难度分析(i+1 覆盖率,零 API 成本)
///   → 按"目标难度 + 权威度 + 相关性"排序
///   → 每篇给出**可解释的推荐理由**
/// ```
///
/// 边界(诚实):
/// - 不做浏览器渲染、不绕登录墙/验证码/付费墙 —— 抓不到就如实说;
/// - 不编造来源:没有 url 的结果一律丢弃;没抓到正文的条目会标注"未抓正文";
/// - 难度全部本地算(`MaterialLibrary.analyze`),AI 只负责"检索词/推荐理由的措辞"。
///
/// 可测性:纯函数(去重键、打分、排序、理由)都在文件上层单独导出;
/// 编排部分依赖真实网络,通过构造参数注入 [DeepSeekSearchClient] 与
/// [MaterialSourceService] 以便以后做集成测试。
class DiscoveredCandidate {
  /// 标题(可能是英文;中文标题需要另一条 AI 链路,不在本批)
  final String title;

  /// 出处链接(**必填**,无 url 的候选不会进这个类)
  final String url;

  /// 来源标签(如「NPR」「公版书」「DeepSeek 搜索」)
  final String sourceLabel;

  /// 内容形态(book/paper/news/podcast/wiki/article;决定卡片封面的类型身份图)
  final String kind;

  /// 摘要(公开源 note / 官方搜索 snippet+summary)
  final String snippet;

  /// 配图(公开源自带;官方搜索没给图)
  final String? imageUrl;

  /// 权威度 0~4(只有官方搜索给;公开源记 -1 = 未知)
  final int authority;

  /// 相关性 0~3(只有官方搜索给)
  final double rerankScore;

  /// 是否来自 DeepSeek 官方搜索(用于卡片上的来源标识与"权威度"展示)
  final bool fromSearchApi;

  /// 抓到的正文(没抓到 = null)
  final String? content;

  /// 本地难度分析(有正文才算得出来)
  final MaterialAnalysis? analysis;

  const DiscoveredCandidate({
    required this.title,
    required this.url,
    required this.sourceLabel,
    this.kind = 'article',
    this.snippet = '',
    this.imageUrl,
    this.authority = -1,
    this.rerankScore = 0,
    this.fromSearchApi = false,
    this.content,
    this.analysis,
  });

  bool get hasAnalysis => analysis != null;

  /// 词次覆盖率(泛读体验看这个;分析过才有)
  double? get coverage => analysis?.knownTokenRatio;

  DiscoveredCandidate copyWith({
    String? content,
    MaterialAnalysis? analysis,
  }) {
    return DiscoveredCandidate(
      title: title,
      url: url,
      sourceLabel: sourceLabel,
      kind: kind,
      snippet: snippet,
      imageUrl: imageUrl,
      authority: authority,
      rerankScore: rerankScore,
      fromSearchApi: fromSearchApi,
      content: content ?? this.content,
      analysis: analysis ?? this.analysis,
    );
  }

  Map<String, Object?> toMap() => {
        'title': title,
        'url': url,
        'source': sourceLabel,
        'kind': kind,
        'snippet': snippet,
        'image_url': imageUrl,
        'authority': authority,
        'rerank_score': rerankScore,
        'from_search_api': fromSearchApi,
      };
}

/// 一次"按需找材料"的完整结果。
class DiscoveryRun {
  /// 已抓正文并分析、按推荐度排序的条目
  final List<DiscoveredCandidate> items;

  /// 过程说明(源失败/没搜到/被偏好过滤了几条 —— 直接显示给用户,不隐瞒)
  final List<String> notes;

  /// 本次官方 Search/Fetch 成功请求数(计费口径)与估算花费
  final int searchApiRequests;
  final double estimatedCostCny;

  /// 官方搜索是否可用(未配置 DS 官方 Key 时为 false,此时只用公开源)
  final bool searchApiAvailable;
  final String searchApiUnavailableReason;

  /// 没有进入 items 的候选数(抓取失败/太短/与已有材料重复等)
  final int droppedCount;

  const DiscoveryRun({
    required this.items,
    this.notes = const [],
    this.searchApiRequests = 0,
    this.estimatedCostCny = 0,
    this.searchApiAvailable = false,
    this.searchApiUnavailableReason = '',
    this.droppedCount = 0,
  });

  bool get isEmpty => items.isEmpty;
}

/// 发现流水线。
class MaterialDiscovery {
  final DeepSeekSearchClient? _injectedClient;
  final MaterialSourceService _source;

  MaterialDiscovery({
    DeepSeekSearchClient? searchClient,
    MaterialSourceService? sourceService,
  })  : _injectedClient = searchClient,
        _source = sourceService ?? MaterialSourceService.instance;

  /// 按需求找材料。
  ///
  /// [queries] 来自检索计划(通常由 AI 把中文需求翻成英文检索词;2~3 条最合适,
  /// 这里**全部用上**,不再只取第一条)。
  /// [maxFetch] 控制抓正文的条数 —— 每篇都有时延(1~5s),默认 5 篇 ≈ 10~20s。
  Future<DiscoveryRun> discover({
    required List<String> queries,
    required InputPreferences prefs,
    required LearnerModel model,
    List<Vocabulary> vocab = const [],
    int maxFetch = 5,
    bool usePublicSources = true,
    bool useSearchApi = true,
    void Function(String label)? onEvent,
  }) async {
    final notes = <String>[];
    final raw = <DiscoveredCandidate>[];
    final seen = <String>{};

    void addAll(Iterable<DiscoveredCandidate> list) {
      for (final c in list) {
        final key = dedupeKeyOf(c.url);
        if (key.isEmpty) continue;
        if (!seen.add(key)) continue;
        // 用户黑名单:标题/来源里出现屏蔽词就整条丢掉(C1-14 的落点)
        if (!prefs.allowsMaterial(
          title: c.title,
          source: c.sourceLabel,
          genres: const [],
        )) {
          continue;
        }
        raw.add(c);
      }
    }

    final plan = queries
        .map((q) => q.trim())
        .where((q) => q.isNotEmpty)
        .toSet()
        .take(3)
        .toList();

    // ── ① 公开源并发检索(可达性实测过的三个源,零 API 成本) ──
    if (usePublicSources) {
      for (final q in plan) {
        onEvent?.call('在公开源里检索「$q」…');
        try {
          final result = await OriginalSearch.search(q, category: '其他');
          if (result.notes.isNotEmpty) notes.addAll(result.notes.take(2));
          addAll([
            for (final hit in result.hits)
              DiscoveredCandidate(
                title: hit.title.trim().isEmpty ? hit.url : hit.title,
                url: hit.url,
                sourceLabel:
                    MaterialSourceService.sourceOf(hit.sourceId)?.label ??
                        hit.sourceId,
                kind: MaterialSourceService.sourceOf(hit.sourceId)?.kind ??
                    'article',
                snippet: hit.note.trim(),
                imageUrl: hit.imageUrl,
              ),
          ]);
        } catch (e) {
          notes.add('公开源检索失败:$e');
        }
      }
    }

    // ── ② DeepSeek 官方搜索(长尾/时效性内容的来源) ──
    final client = _injectedClient ?? DeepSeekSearchClient();
    final apiAvailable = client.available;
    var apiRequests = 0;
    var apiCost = 0.0;
    if (useSearchApi) {
      if (!apiAvailable) {
        notes.add(
          'DeepSeek 官方搜索未配置,本次只用公开源 —— ${client.unavailableReason}',
        );
      } else {
        client.resetCost();
        for (final q in plan.take(2)) {
          onEvent?.call('用 DeepSeek 搜索「$q」…');
          final hits = await client.search(q, count: 5, oriQuestion: q);
          final err = client.lastError;
          if (hits.isEmpty && err != null) notes.add('搜索失败:${err.message}');
          addAll([
            for (final r in hits)
              DiscoveredCandidate(
                title: r.title.trim().isEmpty ? r.url : r.title,
                url: r.url,
                sourceLabel: r.siteName.trim().isEmpty
                    ? 'DeepSeek 搜索'
                    : 'DeepSeek 搜索 · ${r.siteName}',
                snippet: r.summary.isNotEmpty ? r.summary : r.snippet,
                authority: r.authority,
                rerankScore: r.rerankScore,
                fromSearchApi: true,
              ),
          ]);
        }
        apiRequests = client.requestCount;
        apiCost = client.estimatedCostCny;
      }
    }

    if (raw.isEmpty) {
      notes.add('这些渠道都没有找到合适的材料。可以换个关键词,或降低/提高难度档再试。');
      return DiscoveryRun(
        items: const [],
        notes: notes,
        searchApiRequests: apiRequests,
        estimatedCostCny: apiCost,
        searchApiAvailable: apiAvailable,
        searchApiUnavailableReason: client.unavailableReason,
      );
    }

    // ── ③ 选抓取目标:官方搜索优先(有权威度/相关性),再补公开源 ──
    final ordered = List<DiscoveredCandidate>.from(raw)
      ..sort(comparePreFetch);
    final targets = ordered.take(maxFetch.clamp(1, 10)).toList();

    // ── ④ 抓正文 + 本地难度分析(串行:内存/网络都稳,不做并发解码) ──
    final analyzed = <DiscoveredCandidate>[];
    var dropped = 0;
    for (var i = 0; i < targets.length; i++) {
      final c = targets[i];
      onEvent?.call('抓取正文 ${i + 1}/${targets.length}:${c.title}');
      try {
        final text = c.fromSearchApi
            ? await _fetchViaSearchApi(client, c.url)
            : await _fetchViaPublicSource(c);
        if (text == null || text.trim().length < 200) {
          dropped++;
          continue;
        }
        final analysis = await MaterialLibrary.analyze(
          text,
          model: model,
          vocab: vocab,
        );
        analyzed.add(c.copyWith(content: text, analysis: analysis));
      } catch (e) {
        dropped++;
        notes.add('抓取失败:${c.title}($e)');
      }
    }

    // ── ⑤ 排序 + 解释性推荐理由 ──
    final ranked = List<DiscoveredCandidate>.from(analyzed)
      ..sort((a, b) => scoreOf(b, prefs).compareTo(scoreOf(a, prefs)));
    notes.add('有效候选 ${ranked.length} 篇(抓取/分析失败 $dropped 篇)。');
    return DiscoveryRun(
      items: ranked,
      notes: notes,
      searchApiRequests: apiRequests,
      estimatedCostCny: apiCost,
      searchApiAvailable: apiAvailable,
      searchApiUnavailableReason: client.unavailableReason,
      droppedCount: dropped,
    );
  }

  Future<String?> _fetchViaSearchApi(
    DeepSeekSearchClient client,
    String url,
  ) async {
    final page = await client.fetch(url);
    if (page == null) return null;
    return plainTextFromMarkdown(page.content);
  }

  Future<String?> _fetchViaPublicSource(DiscoveredCandidate c) async {
    final doc = await _source.fetchAnyUrl(c.url, titleHint: c.title);
    final text = doc.chunks.map((chunk) => chunk.text).join('\n\n');
    return text.trim().isEmpty ? null : text;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 纯函数层(可单测;UI 与联调都依赖这里的口径)
// ═══════════════════════════════════════════════════════════════════════

/// 候选去重键:URL 归一(去协议差异/大小写/尾斜杠/常见追踪参数)。
///
/// 为什么不能直接比原串:同一篇文章在 RSS 里是 `http://x/a?id=1`、在搜索结果里
/// 是 `https://x/a/` —— 不去重会同一篇出现两次,用户点开发现是同一篇。
String dedupeKeyOf(String url) {
  var s = url.trim();
  if (s.isEmpty) return '';
  s = s.replaceFirst(RegExp(r'^https?://'), '');
  final hash = s.indexOf('#');
  if (hash >= 0) s = s.substring(0, hash);
  // 追踪参数对"是不是同一篇"没有影响
  s = s.replaceAll(RegExp(r'[?&](utm_[^&]*|ref=[^&]*|source=[^&]*)'), '');
  s = s.replaceAll(RegExp(r'/+$'), '');
  s = s.toLowerCase();
  return s;
}

/// 抓取前排序:官方搜索按"权威度 + 相关性",公开源按可达性优先级。
///
/// 目的只是决定"先抓哪 5 篇",真正的推荐排序在拿到覆盖率后由 [scoreOf] 决定。
int comparePreFetch(DiscoveredCandidate a, DiscoveredCandidate b) {
  if (a.fromSearchApi != b.fromSearchApi) return a.fromSearchApi ? -1 : 1;
  final byAuthority = b.authority.compareTo(a.authority);
  if (byAuthority != 0) return byAuthority;
  final byRerank = b.rerankScore.compareTo(a.rerankScore);
  if (byRerank != 0) return byRerank;
  return 0;
}

/// 推荐打分(越大越靠前)。规则公开、可解释:
/// - 落在用户难度档内:+100;偏易/偏难:-30(不隐藏,只是排后面);
/// - 官方搜索权威度:每级 +6(0~4);
/// - 相关性 rerank:×10(0~3);
/// - 有正文/分析:+20(能给出难度的优先);
/// - 公开源(公版书/外媒)+5(实测可达、无需计费)。
int scoreOf(DiscoveredCandidate c, InputPreferences prefs) {
  var score = 0;
  final coverage = c.coverage;
  if (coverage != null) {
    if (prefs.band.isAny || coverageInBand(coverage, prefs.band)) {
      score += 100;
    } else {
      score -= 30;
    }
    score += 20;
  }
  if (c.fromSearchApi) {
    if (c.authority >= 0) score += c.authority * 6;
    score += (c.rerankScore * 10).round();
  } else {
    score += 5;
  }
  return score;
}

/// 可解释的推荐理由(每条都必须能被数据验证,不许空话)。
///
/// 例:`覆盖率 96% · 符合 i+1 · 约 8 分钟 · 来源 NPR`;
/// 官方搜索还会带 `权威度 3/4`。没抓到正文时明确写"未抓正文",不假装有难度。
String reasonOf(DiscoveredCandidate c, InputPreferences prefs) {
  final parts = <String>[];
  final analysis = c.analysis;
  if (analysis != null) {
    final pct = (analysis.knownTokenRatio * 100).round();
    parts.add('覆盖率 $pct%');
    final fit = prefs.band.isAny
        ? ''
        : prefs.band.materialBand.fitLabel(analysis.knownTokenRatio);
    if (fit.isNotEmpty) parts.add(fit);
    if (analysis.estMinutes > 0) parts.add('约 ${analysis.estMinutes} 分钟');
    if (analysis.cefr.isNotEmpty) parts.add(analysis.cefr);
  } else {
    parts.add('未抓正文');
  }
  if (c.fromSearchApi && c.authority >= 0) {
    parts.add('权威度 ${c.authority}/4');
  }
  parts.add('来源 ${c.sourceLabel}');
  return parts.join(' · ');
}

/// 从 Markdown 里抽纯文本(给难度分析用)。
///
/// 官方 Fetch 返回 Markdown;直接拿 `##`/`**`/链接去算覆盖率会把符号算成生词。
/// 只做保守清理:去标题井号、强调符号、链接只留文字、图片/代码块整行丢。
String plainTextFromMarkdown(String markdown) {
  final out = <String>[];
  // 代码块状态:``` 之间的内容不是正文(旧实现只跳过 ``` 行本身,
  // 块内的 `void main()` 会被当成"生词密度"算进难度分析)。
  var inFence = false;
  for (final rawLine in markdown.replaceAll('\r\n', '\n').split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    if (line.isEmpty) continue;
    if (line.startsWith('![')) continue;
    if (RegExp(r'^[-*_]{3,}$').hasMatch(line)) continue;
    if (RegExp(r'^\|').hasMatch(line)) continue; // 表格行不是正文
    var t = line.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    t = t.replaceFirst(RegExp(r'^>\s*'), '');
    t = t.replaceFirst(RegExp(r'^[-*+]\s+'), '');
    t = t.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]*\)'),
      (m) => m.group(1) ?? '',
    );
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    t = t.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length >= 2) out.add(t);
  }
  return out.join('\n\n');
}
