import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'html_text.dart';
import 'material_source.dart';
import 'material_source_status.dart';

/// 一条**真实原文**的检索结果(v2.4,D1 用户要求)。
///
/// 用户原话:「"按你的水平找材料"里的资源全是 ai 二手改写的…应该让用户可以自选 ——
/// 推出来一本书,应该是"ai 总结/整理/编写"or"资料原文"这类的方向」。
/// 所以这一层只做**原文检索**:结果一定来自公开源,每条都能点开原文。
class OriginalHit {
  /// 内容源 id(与 [MaterialSourceService.sources] 对齐,便于走同一套抓取/入库)
  final String sourceId;

  /// 源内 id(Gutenberg 书号 / arXiv id / RSS 条目链接)
  final String sourceId2;

  final String title;
  final String author;

  /// 打开时用的 URL
  final String url;

  /// 一句话说明(作者/日期/摘要片段)
  final String note;

  const OriginalHit({
    required this.sourceId,
    required this.sourceId2,
    required this.title,
    this.author = '',
    required this.url,
    this.note = '',
  });
}

/// 检索结果 + **每个源的真实情况**(v2.5:M1 修"完全找不出任何原版材料")。
///
/// 为什么要带 notes:旧实现只返回一个列表,源不可达和"真的没有结果"看起来一模一样,
/// 用户只会得出"这功能没用"。现在每个源单独报:通没通、拿到几条、为什么没结果。
class OriginalSearchResult {
  final List<OriginalHit> hits;

  /// 每个源一行状态,给界面直接显示
  final List<String> notes;

  const OriginalSearchResult({this.hits = const [], this.notes = const []});

  bool get isEmpty => hits.isEmpty;
}

/// 原文检索(v2.5 修)。
///
/// **教训(实测 2026-09-24)**:上一版用 `gutendex.com` 搜公版书 —— 在大陆网络
/// **实测 12.5 秒超时**,而 `gutenberg.org` 站内检索只要 3.5 秒、arXiv 0.5 秒。
/// 于是"书籍"这类目永远搜不到东西,用户看到的只有"没有结果",功能等于废掉。
/// 现在改成:
/// - 公版书 → **Project Gutenberg 站内检索页解析**(与抓正文同域);
/// - 论文 → arXiv 官方 API(**https**);
/// - 新闻/播客 → RSS 没有检索接口,退化为"拉最新条目 + 关键词本地过滤";
/// - **中文关键词直接给提示**(这些源只认英文),而不是静默返回空。
class OriginalSearch {
  OriginalSearch._();

  static const Duration timeout = Duration(seconds: 20);
  static const int maxPerSource = 10;

  /// 分类 → 源(顺序即检索顺序)
  static List<String> sourcesForCategory(String category) => switch (category) {
        '书籍' || '教材' => ['gutenberg'],
        '论文' => ['arxiv'],
        '外刊' || '碎片文章' => ['npr', 'bbc_le', 'voa_le', 'ted'],
        _ => ['gutenberg', 'arxiv', 'npr'],
      };

  /// 分类 → 没给关键词时的**默认检索**(宁可给经典书单,也不要空页面)
  static String defaultQueryFor(String category) => switch (category) {
        '论文' => 'language learning',
        '外刊' || '碎片文章' => 'english',
        _ => '',
      };

  /// 检索。[query] 为空时会退回该分类的默认检索(见 [defaultQueryFor]);
  /// 仍然为空则取"最受欢迎"书单(总有结果)。
  static Future<OriginalSearchResult> search(
    String query, {
    String category = '其他',
    Dio? dio,
  }) async {
    final client = dio ?? MaterialSourceService.dio;
    var q = query.trim();
    if (q.isEmpty) q = defaultQueryFor(category);
    final wanted = sourcesForCategory(category);
    final hits = <OriginalHit>[];
    final notes = <String>[];

    // 中文关键词:这些源全部是英文库,直接说清楚,别让用户以为是 App 坏了
    final cjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(q);
    if (cjk) {
      notes.add('「$q」是中文关键词 —— 公版书与论文库只认英文,'
          '请用英文(如 economics / climate change / a christmas carol)');
    }

    // **并行**检索各源(v2.5):串行时外刊分类要为 BBC/VOA/TED 各等 20 秒超时,
    // 实测一次搜索要 62 秒 —— 用户等的只是三条失败提示。并行后总耗时 = 最慢那个源。
    final tasks = <Future<({String id, String label, List<OriginalHit> hits, String? error})>>[];
    for (final id in wanted) {
      final label = MaterialSourceService.sourceOf(id)?.label ?? id;
      tasks.add(() async {
        // 最近失败过的源直接跳过:用已有的"源可用性记忆",并如实说明
        if (_recentlyFailed(id)) {
          return (id: id, label: label, hits: const <OriginalHit>[], error: 'skip');
        }
        try {
          final List<OriginalHit> got;
          switch (id) {
            case 'gutenberg':
              got = await searchGutenberg(q, client, allowPopular: q.isEmpty);
              break;
            case 'arxiv':
              if (cjk) {
                return (id: id, label: label, hits: const <OriginalHit>[], error: 'cjk');
              }
              got = await searchArxiv(q, client);
              break;
            default:
              got = await searchRss(id, q, client);
          }
          return (id: id, label: label, hits: got, error: null);
        } catch (e) {
          debugPrint('ReadFlow 原文检索失败($id): $e');
          return (id: id, label: label, hits: const <OriginalHit>[], error: _short(e));
        }
      }()
          // 交互式检索给 12 秒预算:超过就没必要让用户继续等
          .timeout(const Duration(seconds: 12), onTimeout: () {
        return (id: id, label: label, hits: const <OriginalHit>[], error: '超时(12 秒)');
      }));
    }

    for (final r in await Future.wait(tasks)) {
      hits.addAll(r.hits);
      switch (r.error) {
        case null:
          if (r.hits.isNotEmpty) {
            notes.add('${r.label}:${r.hits.length} 条');
          } else if (!cjk) {
            notes.add('${r.label}:没有匹配的原文(换个英文关键词试试)');
          }
          break;
        case 'skip':
          notes.add('${r.label}:上次没连上,已跳过(可在材料中心点「检测可用源」重测)');
          break;
        case 'cjk':
          notes.add('${r.label}:已跳过(只认英文关键词)');
          break;
        default:
          notes.add('${r.label}:这次没连上 —— ${r.error}');
      }
    }
    return OriginalSearchResult(
      hits: hits.take(maxPerSource * 2).toList(),
      notes: notes,
    );
  }

  /// Project Gutenberg 站内检索。
  ///
  /// [allowPopular] = 关键词为空时取**按下载量排序**的书单(经典公版书),
  /// 这样"书籍"分类点进来永远不会是空页面。
  static Future<List<OriginalHit>> searchGutenberg(
    String query,
    Dio dio, {
    bool allowPopular = false,
  }) async {
    final uri = allowPopular
        ? 'https://www.gutenberg.org/ebooks/search/?sort_order=downloads'
        : 'https://www.gutenberg.org/ebooks/search/?query=${Uri.encodeQueryComponent(query)}';
    final resp = await dio.get<dynamic>(uri);
    return parseGutenbergSearchPage('${resp.data ?? ''}');
  }

  /// 解析 Gutenberg 检索结果页(纯函数,便于单测)。
  ///
  /// 结构(实测):每个结果是一个 `<li class="booklink">`,里面有
  /// `<a class="link" href="/ebooks/1342">` + `<span class="title">` +
  /// `<span class="subtitle">`(作者)。
  static List<OriginalHit> parseGutenbergSearchPage(String html) {
    final out = <OriginalHit>[];
    final blocks =
        RegExp(r'<li[^>]*class="[^"]*booklink[^"]*"[\s\S]*?</li>')
            .allMatches(html);
    for (final b in blocks) {
      final block = b.group(0) ?? '';
      final href = RegExp(r'href="(?:https?://[^"]*)?/ebooks/(\d+)"')
          .firstMatch(block)
          ?.group(1);
      final title = _stripTags(
        RegExp(r'<span[^>]*class="[^"]*title[^"]*"[^>]*>([\s\S]*?)</span>')
                .firstMatch(block)
                ?.group(1) ??
            '',
      );
      if (href == null || title.isEmpty) continue;
      final author = _stripTags(
        RegExp(r'<span[^>]*class="[^"]*subtitle[^"]*"[^>]*>([\s\S]*?)</span>')
                .firstMatch(block)
                ?.group(1) ??
            '',
      );
      out.add(OriginalHit(
        sourceId: 'gutenberg',
        sourceId2: href,
        title: title,
        author: author,
        url: 'https://www.gutenberg.org/ebooks/$href',
        note: author.isEmpty ? '公版书全文' : '$author · 公版书全文',
      ));
      if (out.length >= maxPerSource) break;
    }
    return out;
  }

  /// arXiv 官方检索 API(Atom XML),走 **https**
  static Future<List<OriginalHit>> searchArxiv(String query, Dio dio) async {
    final resp = await dio.get<dynamic>(
      'https://export.arxiv.org/api/query',
      queryParameters: {
        'search_query': 'all:$query',
        'max_results': '$maxPerSource',
      },
    );
    return parseArxivFeed('${resp.data ?? ''}');
  }

  /// 解析 arXiv Atom 结果(纯函数,便于单测)
  static List<OriginalHit> parseArxivFeed(String xml) {
    final out = <OriginalHit>[];
    final entries = RegExp(r'<entry>([\s\S]*?)</entry>').allMatches(xml);
    for (final e in entries) {
      final block = e.group(1) ?? '';
      final id = _tag(block, 'id');
      final title = _tag(block, 'title').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (id.isEmpty || title.isEmpty) continue;
      final shortId = id.split('/abs/').last;
      final summary =
          _tag(block, 'summary').replaceAll(RegExp(r'\s+'), ' ').trim();
      out.add(OriginalHit(
        sourceId: 'arxiv',
        sourceId2: shortId,
        title: title,
        url: id,
        note: summary.length > 90 ? '${summary.substring(0, 90)}…' : summary,
      ));
      if (out.length >= maxPerSource) break;
    }
    return out;
  }

  /// 没有检索接口的 RSS 源:拉最新条目 + 本地关键词过滤
  static Future<List<OriginalHit>> searchRss(
    String sourceId,
    String query,
    Dio dio,
  ) async {
    final source = MaterialSourceService.sourceOf(sourceId);
    if (source == null) return const [];
    final items = await MaterialSourceService.instance.listItems(
      sourceId,
      limit: 30,
    );
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toList();
    final matched = [
      for (final it in items)
        if (words.isEmpty ||
            words.any((w) =>
                it.title.toLowerCase().contains(w) ||
                it.summary.toLowerCase().contains(w)))
          OriginalHit(
            sourceId: sourceId,
            sourceId2: it.link,
            title: it.title,
            url: it.link,
            note: '${source.label} · ${it.published ?? '最新'}',
          ),
    ];
    // 一条都没匹配上时给最新的几条(总比空页面有用;仍然是真实原文)
    final list = matched.isNotEmpty
        ? matched
        : [
            for (final it in items.take(5))
              OriginalHit(
                sourceId: sourceId,
                sourceId2: it.link,
                title: it.title,
                url: it.link,
                note: '${source.label} · ${it.published ?? '最新'}(最新条目)',
              ),
          ];
    return list.take(maxPerSource).toList();
  }

  /// 这个源最近（6 小时内）失败过吗？失败过就先跳过，别让用户干等超时。
  /// 读不到状态（Hive 未打开/没有记录）一律当"没失败过"。
  static bool _recentlyFailed(String sourceId) {
    try {
      final health = MaterialSourceStatus.of(sourceId);
      if (health == null || health.ok) return false;
      return DateTime.now().difference(health.at) < const Duration(hours: 6);
    } catch (_) {
      return false;
    }
  }

  static String _stripTags(String html) {
    final text = html.replaceAll(RegExp(r'<[^>]*>'), '');
    return HtmlText.decodeEntities(text).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _tag(String xml, String name) {
    final m = RegExp('<$name[^>]*>([\\s\\S]*?)</$name>').firstMatch(xml);
    return HtmlText.decodeEntities(m?.group(1) ?? '');
  }

  static String _short(Object e) {
    final flat = '$e'.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > 60 ? '${flat.substring(0, 60)}…' : flat;
  }
}
