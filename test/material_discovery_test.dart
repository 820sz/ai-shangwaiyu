import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/input_prefs.dart';
import 'package:readflow/services/material_discovery.dart';
import 'package:readflow/services/material_library.dart';

/// 批 2「按需找材料」流水线的纯函数回归。
///
/// 这一层不联网,守的是"以后改 UI/换检索源时最容易悄悄改错"的口径:
/// 1. 同一篇文章在 RSS 与搜索结果里 URL 写法不同 → 必须去重成一条;
/// 2. 官方 Fetch 返回 Markdown → 纯文本提取不能把 `##`/`**` 算成"生词";
/// 3. 推荐排序:先抓官方搜索的高权威结果,再补公开源;
/// 4. 推荐理由必须可验证(覆盖率/难度档/时长/来源),没正文就写"未抓正文";
/// 5. 难度档判定与 MaterialBand 同一口径(0.98 / 0.90)。
void main() {
  group('dedupeKeyOf — 同一篇文章的不同 URL 写法', () {
    test('http/https、大小写、尾斜杠视为同一篇', () {
      expect(
        dedupeKeyOf('http://Example.com/a/'),
        dedupeKeyOf('https://example.com/a'),
      );
    });

    test('去掉 #锚点 与 utm_/ref/source 追踪参数', () {
      expect(
        dedupeKeyOf('https://x.com/post?id=1&utm_source=rss&utm_medium=a'),
        dedupeKeyOf('https://x.com/post?id=1'),
      );
      expect(
        dedupeKeyOf('https://x.com/post#comments'),
        dedupeKeyOf('https://x.com/post'),
      );
    });

    test('不同文章不能误合并', () {
      expect(
        dedupeKeyOf('https://x.com/a'),
        isNot(dedupeKeyOf('https://x.com/b')),
      );
    });

    test('空串 → 空键(调用方据此丢弃)', () {
      expect(dedupeKeyOf('  '), '');
    });
  });

  group('plainTextFromMarkdown — 难度分析前的纯文本提取', () {
    test('去掉标题井号/粗体/反引号,链接只留文字', () {
      const md = '''
# The Science of Sleep

**Sleep** is important. Read [this study](https://example.com/x) for `details`.
''';
      final text = plainTextFromMarkdown(md);
      expect(text, contains('The Science of Sleep'));
      expect(text, contains('Sleep is important.'));
      expect(text, contains('this study'));
      expect(text, isNot(contains('##')));
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains('https://example.com')));
    });

    test('表格行/代码块/图片行不参与(不是正文)', () {
      const md = '''
| a | b |
|---|---|
| 1 | 2 |

```dart
void main() {}
```

![cover](https://example.com/a.png)

Real paragraph here.
''';
      final text = plainTextFromMarkdown(md);
      expect(text, contains('Real paragraph here.'));
      expect(text, isNot(contains('| a |')));
      expect(text, isNot(contains('void main')));
      expect(text, isNot(contains('.png')));
    });
  });

  group('comparePreFetch — 先抓谁', () {
    DiscoveredCandidate c({
      required String url,
      bool fromApi = false,
      int authority = -1,
      double rerank = 0,
    }) =>
        DiscoveredCandidate(
          title: url,
          url: url,
          sourceLabel: fromApi ? 'DeepSeek 搜索' : 'NPR',
          fromSearchApi: fromApi,
          authority: authority,
          rerankScore: rerank,
        );

    test('官方搜索优先于公开源', () {
      final sorted = [
        c(url: 'https://pub.com/1'),
        c(url: 'https://api.com/1', fromApi: true, authority: 2),
      ]..sort(comparePreFetch);
      expect(sorted.first.url, 'https://api.com/1');
    });

    test('官方搜索内部:权威度 > 相关性 > 原序', () {
      final sorted = [
        c(url: 'https://a.com/1', fromApi: true, authority: 1, rerank: 2.9),
        c(url: 'https://a.com/2', fromApi: true, authority: 3, rerank: 0.5),
        c(url: 'https://a.com/3', fromApi: true, authority: 3, rerank: 1.5),
      ]..sort(comparePreFetch);
      expect(sorted.map((e) => e.url).toList(), [
        'https://a.com/3', // 同权威度时相关性高者先
        'https://a.com/2',
        'https://a.com/1',
      ]);
    });
  });

  group('scoreOf — 推荐打分口径', () {
    final prefsI10 = InputPreferences(band: DifficultyBand.challenge);

    DiscoveredCandidate analyzed({
      required double knownTokenRatio,
      bool fromApi = false,
      int authority = -1,
      double rerank = 0,
    }) =>
        DiscoveredCandidate(
          title: 't',
          url: 'https://x.com/1',
          sourceLabel: fromApi ? 'DeepSeek 搜索' : 'NPR',
          fromSearchApi: fromApi,
          authority: authority,
          rerankScore: rerank,
          content: 'text',
          analysis: MaterialAnalysis(
            wordCount: 1000,
            uniqueWords: 400,
            newTypes: 30,
            estMinutes: 8,
            coverage: knownTokenRatio,
            knownTokenRatio: knownTokenRatio,
            newWordDensity: 3,
            cefr: 'B2',
            topNewWords: const ['sleep'],
          ),
        );

    test('落在难度档内(+100)比偏难(-30)高一个量级', () {
      final inBand = scoreOf(analyzed(knownTokenRatio: 0.93), prefsI10);
      final tooHard = scoreOf(analyzed(knownTokenRatio: 0.80), prefsI10);
      expect(inBand, greaterThan(tooHard + 100));
    });

    test('官方搜索的权威度与相关性加分,但压不过难度档', () {
      final api = scoreOf(
        analyzed(knownTokenRatio: 0.80, fromApi: true, authority: 4, rerank: 3),
        prefsI10,
      );
      final inBandPublic = scoreOf(analyzed(knownTokenRatio: 0.93), prefsI10);
      expect(inBandPublic, greaterThan(api));
    });

    test('没抓到正文的候选拿不到"可读性"加分', () {
      const bare = DiscoveredCandidate(
        title: 't',
        url: 'https://x.com/2',
        sourceLabel: 'NPR',
      );
      // 在难度档内的已分析候选,必须明显高于"没正文所以算不出难度"的候选
      expect(scoreOf(analyzed(knownTokenRatio: 0.93), prefsI10),
          greaterThan(scoreOf(bare, prefsI10)));
    });
  });

  group('reasonOf — 每条推荐都必须说得清为什么', () {
    final prefs = InputPreferences(band: DifficultyBand.challenge);

    DiscoveredCandidate withAnalysis({bool fromApi = false, int authority = -1}) =>
        DiscoveredCandidate(
          title: 't',
          url: 'https://x.com/1',
          sourceLabel: fromApi ? 'DeepSeek 搜索 · NPR' : '外媒新闻',
          fromSearchApi: fromApi,
          authority: authority,
          content: 'text',
          analysis: const MaterialAnalysis(
            wordCount: 900,
            uniqueWords: 350,
            newTypes: 40,
            estMinutes: 7,
            coverage: 0.93,
            knownTokenRatio: 0.93,
            newWordDensity: 4,
            cefr: 'B2',
            topNewWords: ['a'],
          ),
        );

    test('有正文:覆盖率 + 难度档 + 时长 + CEFR + 来源', () {
      final r = reasonOf(withAnalysis(), prefs);
      expect(r, contains('覆盖率 93%'));
      expect(r, contains('符合 i+10'));
      expect(r, contains('约 7 分钟'));
      expect(r, contains('B2'));
      expect(r, contains('来源'));
    });

    test('官方搜索额外给出权威度', () {
      final r = reasonOf(withAnalysis(fromApi: true, authority: 3), prefs);
      expect(r, contains('权威度 3/4'));
    });

    test('没抓正文 → 明确写"未抓正文",不假装有难度', () {
      const bare = DiscoveredCandidate(
        title: 't',
        url: 'https://x.com/2',
        sourceLabel: 'NPR',
      );
      expect(reasonOf(bare, prefs), contains('未抓正文'));
      expect(reasonOf(bare, prefs), isNot(contains('覆盖率')));
    });
  });
}
