import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/original_search.dart';

/// 原文检索测试(v2.5,M1)。
///
/// 背景:上一版用 `gutendex.com` 搜公版书,在大陆网络**实测 12.5 秒超时** ——
/// "书籍"分类永远是空页面,用户直接说"AI 完全找不出任何原版材料"。
/// 现在改用 Project Gutenberg 站内检索(与抓正文同域,实测 3.5 秒可达),
/// 这里锁死解析与"每个源如实报告"的行为。
void main() {
  group('分类 → 源映射', () {
    test('书籍/教材 → 公版书;论文 → arXiv;外刊 → 新闻播客', () {
      expect(OriginalSearch.sourcesForCategory('书籍'), ['gutenberg']);
      expect(OriginalSearch.sourcesForCategory('教材'), ['gutenberg']);
      expect(OriginalSearch.sourcesForCategory('论文'), ['arxiv']);
      expect(OriginalSearch.sourcesForCategory('外刊'), contains('npr'));
    });

    test('未知分类给一组能用的大源(不能返回空)', () {
      final s = OriginalSearch.sourcesForCategory('随便什么');
      expect(s, isNotEmpty);
      expect(s, contains('gutenberg'));
    });

    test('默认检索:书籍类留空 → "最受欢迎书单";论文/外刊给英文默认词', () {
      expect(OriginalSearch.defaultQueryFor('书籍'), isEmpty);
      expect(OriginalSearch.defaultQueryFor('论文'), contains('language'));
      expect(OriginalSearch.defaultQueryFor('外刊'), isNotEmpty);
    });
  });

  group('Gutenberg 检索页解析(按真实结构)', () {
    // 取自 gutenberg.org/ebooks/search 的真实片段(裁掉无关部分)
    const html = '''
<div id="search-results">
  <ol class="results-list">
    <li class="booklink">
      <a href="/ebooks/1342" class="link">
        <span class="title">Pride and Prejudice</span>
        <span class="subtitle">Austen, Jane</span>
      </a>
    </li>
    <li class="booklink">
      <a href="/ebooks/2701" class="link">
        <span class="title">Moby Dick; Or, The Whale</span>
        <span class="subtitle">Melville, Herman</span>
      </a>
    </li>
    <li class="booklink">
      <a href="/ebooks/84" class="link">
        <span class="title">Frankenstein; or, the modern prometheus</span>
      </a>
    </li>
  </ol>
</div>
''';

    test('解析出书名/作者/书号/链接', () {
      final hits = OriginalSearch.parseGutenbergSearchPage(html);
      expect(hits, hasLength(3));
      expect(hits.first.sourceId, 'gutenberg');
      expect(hits.first.sourceId2, '1342');
      expect(hits.first.title, 'Pride and Prejudice');
      expect(hits.first.author, 'Austen, Jane');
      expect(hits.first.url, 'https://www.gutenberg.org/ebooks/1342');
      expect(hits.first.note, contains('Austen, Jane'));
      expect(hits.last.note, '公版书全文', reason: '没作者时给通用说明');
    });

    test('HTML 实体与多余空白被清掉', () {
      const messy = '''
<li class="booklink"><a href="/ebooks/1">
  <span class="title">A &amp; B
  &quot;quoted&quot;</span>
  <span class="subtitle">Doe,  John</span></a></li>''';
      final hits = OriginalSearch.parseGutenbergSearchPage(messy);
      expect(hits.single.title, 'A & B "quoted"');
      expect(hits.single.author, 'Doe, John');
    });

    test('坏页面/空页面 → 空列表,不抛异常', () {
      expect(OriginalSearch.parseGutenbergSearchPage(''), isEmpty);
      expect(
          OriginalSearch.parseGutenbergSearchPage('<html>未登录</html>'), isEmpty);
      expect(
        OriginalSearch.parseGutenbergSearchPage(
            '<li class="booklink"><a href="/ebooks/9"></a></li>'),
        isEmpty,
        reason: '有链接没标题 → 跳过(点开也没意义)',
      );
    });
  });

  group('arXiv Atom 解析', () {
    const feed = '''
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>http://arxiv.org/abs/2609.25006v1</id>
    <title>What Does 99% Accuracy
      Measure?</title>
    <summary>We audit reported accuracy &amp; find gaps.</summary>
  </entry>
</feed>
''';

    test('解析标题/id/链接,去掉换行与转义', () {
      final hits = OriginalSearch.parseArxivFeed(feed);
      expect(hits, hasLength(1));
      expect(hits.first.sourceId2, '2609.25006v1');
      expect(hits.first.title, 'What Does 99% Accuracy Measure?');
      expect(hits.first.note, contains('& find gaps'));
    });

    test('缺 id / 缺标题的条目被跳过', () {
      const broken =
          '<feed><entry><title>没有 id</title></entry><entry><id>http://arxiv.org/abs/1</id></entry></feed>';
      expect(OriginalSearch.parseArxivFeed(broken), isEmpty);
    });
  });
}
