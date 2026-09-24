import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'material_source.dart';

/// 一条**真实原文**的检索结果(v2.4,D1 用户要求)。
///
/// 用户原话:「"按你的水平找材料"里的资源全是 ai 二手改写的…完全不是一手原料。
/// 这个问题要好好解决,应该让用户可以自选 —— 推出来一本书,应该是"ai 总结/整理/编写"
/// or "资料原文"这类的方向」。所以这一层只做**原文检索**:
/// 结果一定来自公开源(Gutendex/Project Gutenberg、arXiv、NPR 等 RSS),
/// 每条都能点开原文、看到来源与许可,不是模型编出来的书名。
class OriginalHit {
  /// 内容源 id(与 [MaterialSourceService.sources] 对齐,便于走同一套抓取/入库)
  final String sourceId;

  /// 源内 id(Gutenberg 书号 / arXiv id / RSS 条目链接)
  final String sourceId2;

  final String title;
  final String author;

  /// 打开时用的 URL(RSS 条目 / arXiv abs 页 / Gutenberg 书页)
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

/// 原文检索(v2.4,D1)。
///
/// 只查**公开、免 key**的检索端点:
/// - `gutendex.com`(Project Gutenberg 的公开检索 API)→ 书籍原文
/// - `export.arxiv.org/api/query`(arXiv 官方 API)→ 论文摘要
/// - 其余 RSS 源没有检索接口,退化为"拉最新条目 + 关键词本地过滤"
///
/// **可达性与主源一致**:大陆网络下 Gutendex/arXiv 实测可直连(与
/// Project Gutenberg/arXiv 同域),bbc/voa/ted/wikipedia 仍不可达 ——
/// 检索不到时给出与材料中心同一套中文提示,不假装"没有结果"。
class OriginalSearch {
  OriginalSearch._();

  static const Duration timeout = Duration(seconds: 20);

  /// 每个源最多取几条(结果页不需要翻很多页)
  static const int maxPerSource = 8;

  /// 按分类挑选适合"找原文"的源
  static List<String> sourcesForCategory(String category) => switch (category) {
        '书籍' => ['gutenberg'],
        '教材' => ['gutenberg'],
        '外刊' => ['npr', 'bbc_le', 'voa_le', 'ted'],
        '碎片文章' => ['npr', 'bbc_le'],
        '论文' => ['arxiv'],
        _ => ['npr', 'gutenberg', 'arxiv'],
      };

  /// 检索:命中"原文"条目(失败只记录,不抛 —— 部分源不可达时仍给出可用的)
  static Future<List<OriginalHit>> search(
    String query, {
    String category = '其他',
    Dio? dio,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final client = dio ?? MaterialSourceService.dio;
    final wanted = sourcesForCategory(category);
    final hits = <OriginalHit>[];
    for (final id in wanted) {
      try {
        switch (id) {
          case 'gutenberg':
            hits.addAll(await searchGutenberg(q, client));
            break;
          case 'arxiv':
            hits.addAll(await searchArxiv(q, client));
            break;
          default:
            hits.addAll(await searchRss(id, q, client));
        }
      } catch (e) {
        debugPrint('ReadFlow 原文检索失败($id): $e');
      }
    }
    return hits.take(maxPerSource * 2).toList();
  }

  /// Project Gutenberg(Gutendex 公开检索)
  static Future<List<OriginalHit>> searchGutenberg(
    String query,
    Dio dio,
  ) async {
    final resp = await dio.get<dynamic>(
      'https://gutendex.com/books',
      queryParameters: {'search': query},
    );
    final data = resp.data;
    final map = data is String ? jsonDecode(data) : data;
    if (map is! Map) return const [];
    final results = map['results'];
    if (results is! List) return const [];
    final out = <OriginalHit>[];
    for (final r in results.take(maxPerSource)) {
      if (r is! Map) continue;
      final id = r['id'];
      final title = '${r['title'] ?? ''}'.trim();
      if (id == null || title.isEmpty) continue;
      final authors = (r['authors'] is List)
          ? (r['authors'] as List)
              .map((a) => a is Map ? '${a['name'] ?? ''}' : '')
              .where((s) => s.isNotEmpty)
              .join('、')
          : '';
      out.add(OriginalHit(
        sourceId: 'gutenberg',
        sourceId2: '$id',
        title: title,
        author: authors,
        url: 'https://www.gutenberg.org/ebooks/$id',
        note: authors.isEmpty ? '公版书全文' : '$authors · 公版书全文',
      ));
    }
    return out;
  }

  /// arXiv 官方检索 API(Atom XML)
  static Future<List<OriginalHit>> searchArxiv(String query, Dio dio) async {
    final resp = await dio.get<dynamic>(
      'http://export.arxiv.org/api/query',
      queryParameters: {
        'search_query': 'all:$query',
        'max_results': '$maxPerSource',
      },
    );
    final text = '${resp.data ?? ''}';
    return parseArxivFeed(text);
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
    final q = query.toLowerCase();
    final words = q.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
    return [
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
    ].take(maxPerSource).toList();
  }

  static String _tag(String xml, String name) {
    final m = RegExp('<$name[^>]*>([\\s\\S]*?)</$name>').firstMatch(xml);
    final raw = m?.group(1) ?? '';
    return raw
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}
