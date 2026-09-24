import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/original_search.dart';

/// 原文检索测试(v2.4,D1)。
///
/// 用户反馈「按你的水平找材料」里全是 AI 二手改写、无法考究 —— 这一层的职责
/// 就是**只给真实原文**:来源、链接、可点开。所以测试压在
/// ①解析正确(源站返回什么就解析出什么)②分类到源的映射(别给用户找不到的东西)。
void main() {
  group('分类 → 源映射', () {
    test('书籍/教材 → 公版书;论文 → arXiv;外刊 → 新闻/播客', () {
      expect(OriginalSearch.sourcesForCategory('书籍'), contains('gutenberg'));
      expect(OriginalSearch.sourcesForCategory('教材'), contains('gutenberg'));
      expect(OriginalSearch.sourcesForCategory('论文'), contains('arxiv'));
      expect(OriginalSearch.sourcesForCategory('外刊'), contains('npr'));
    });

    test('未知分类给一组能用的大源(不能返回空)', () {
      final s = OriginalSearch.sourcesForCategory('随便什么');
      expect(s, isNotEmpty);
      expect(s, contains('gutenberg'));
    });
  });

  group('arXiv Atom 解析(原文=论文本身)', () {
    const feed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>http://arxiv.org/abs/2609.25006v1</id>
    <title>What Does 99% Accuracy
      Measure?</title>
    <summary>We audit reported accuracy &amp; find gaps.</summary>
  </entry>
  <entry>
    <id>http://arxiv.org/abs/2609.25008v1</id>
    <title>Training a Language Model End-to-End in Rust</title>
    <summary>A practical report.</summary>
  </entry>
</feed>
''';

    test('解析出标题/id/链接,并去掉换行与转义', () {
      final hits = OriginalSearch.parseArxivFeed(feed);
      expect(hits, hasLength(2));
      expect(hits.first.sourceId, 'arxiv');
      expect(hits.first.sourceId2, '2609.25006v1');
      expect(hits.first.title, 'What Does 99% Accuracy Measure?');
      expect(hits.first.url, 'http://arxiv.org/abs/2609.25006v1');
      expect(hits.first.note, contains('audit reported accuracy & find gaps'));
    });

    test('坏 XML / 空 feed → 空列表,不抛异常', () {
      expect(OriginalSearch.parseArxivFeed(''), isEmpty);
      expect(OriginalSearch.parseArxivFeed('<feed></feed>'), isEmpty);
      expect(OriginalSearch.parseArxivFeed('不是 XML'), isEmpty);
    });

    test('缺 id 或缺标题的条目被跳过(宁可少给,不给点不开的)', () {
      const broken = '''
<feed>
  <entry><title>没有 id</title></entry>
  <entry><id>http://arxiv.org/abs/1</id></entry>
</feed>''';
      expect(OriginalSearch.parseArxivFeed(broken), isEmpty);
    });
  });

  group('检索入口的兜底行为', () {
    test('空关键词直接返回空(不发请求)', () async {
      expect(await OriginalSearch.search(''), isEmpty);
      expect(await OriginalSearch.search('   '), isEmpty);
    });
  });
}
