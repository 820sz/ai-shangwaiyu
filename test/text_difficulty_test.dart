import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/services/text_difficulty.dart';
import 'package:readflow/services/word_frequency.dart';

/// 测试用的小词表(80 个词,名次 = 下标 + 1)。
///
/// 刻意**不依赖真实 assets**:所有断言都建立在"这张表长什么样"之上,
/// 真词表换内容、换顺序都不该让这些测试失效(见每个测试的 setUp 注入)。
/// 排名靠后的词(small/work/read/book…)当作"罕见词",用来验排序与罕见度。
const List<String> _baseWords = <String>[
  'the', 'a', 'i', 'and', 'of', 'to', 'in', 'is', 'it', 'you', //
  'that', 'he', 'was', 'for', 'on', 'are', 'as', 'with', 'his', 'they',
  'be', 'at', 'one', 'have', 'this', 'from', 'or', 'had', 'by', 'but',
  'not', 'what', 'all', 'were', 'we', 'when', 'your', 'can', 'said', 'there',
  'quick', 'brown', 'fox', 'jump', 'run', 'make', 'well', 'known', 'table', 'fast',
  'nice', 'big', 'happy', 'study', 'walk', 'want', 'need', 'change', 'fix', 'hope',
  'use', 'bee', 'city', 'very', 'day', 'real', 'only', 'water', 'glass', 'box',
  'watch', 'class', 'pass', 'call', 'stop', 'large', 'small', 'work', 'read', 'book',
];

/// 注入词表(可在末尾追加额外词条,例如把 `well-known` 当成一个词表条目)。
void _inject({List<String> extra = const <String>[]}) {
  final words = <String>[..._baseWords, ...extra];
  WordFrequency.debugInject(
    words: words,
    counts: List<int>.generate(words.length, (i) => 100000 - i * 7),
  );
}

void main() {
  setUp(_inject);

  group('tokenize — 分词边界与 Markdown 噪声', () {
    test('空文本 / 纯空白 → 0 个 token', () {
      expect(TextDifficulty.tokenize(''), isEmpty);
      expect(TextDifficulty.tokenize('   \n\t  '), isEmpty);
    });

    test('纯标点与表情 → 0 个 token', () {
      expect(TextDifficulty.tokenize('!!! ... ,,; ?? -- 😀🔥'), isEmpty);
    });

    test('纯中文 → 0 个 token(汉字不是英文词,不许凑数)', () {
      expect(TextDifficulty.tokenize('这是一段中文材料,没有任何英文。'), isEmpty);
    });

    test('中英混排只取英文词', () {
      expect(TextDifficulty.tokenize('这本书 the fox 很好看'), ['the', 'fox']);
    });

    test('数字与缩写:数字丢弃、单字母缩写碎片丢弃', () {
      expect(
        TextDifficulty.tokenize('Chapter 12 — 3.14 apples, 1,234 pears.'),
        ['chapter', 'apples', 'pears'],
      );
      expect(TextDifficulty.tokenize('U.S. Army'), ['army']);
    });

    test('撇号:弯引号归一成 ASCII,缩写/所有格保持整体', () {
      expect(
        TextDifficulty.tokenize("Don't stop the fox's run"),
        ["don't", 'stop', 'the', "fox's", 'run'],
      );
      expect(TextDifficulty.tokenize('Don\u2019t stop'), ["don't", 'stop']);
    });

    test('连字符复合词:不在词表 → 拆开;整词在词表 → 保留整体', () {
      expect(
        TextDifficulty.tokenize('a well-known trick'),
        ['a', 'well', 'known', 'trick'],
      );
      _inject(extra: ['well-known']);
      expect(
        TextDifficulty.tokenize('a well-known trick'),
        ['a', 'well-known', 'trick'],
      );
    });

    test('Markdown 噪声:标题/加粗/围栏代码块/URL/链接目标全部清掉', () {
      const md = '''
# The Quick Fox

**The** quick *brown* fox jumps over the lazy dog.

```dart
void main() { runApp(MakingStuff()); }
```

Read more at https://example.com/brown-fox or [the docs](https://dart.dev/guides).
''';
      final tokens = TextDifficulty.tokenize(md);
      expect(tokens, [
        'the', 'quick', 'fox', //
        'the', 'quick', 'brown', 'fox', 'jumps', 'over', 'the', 'lazy', 'dog',
        'read', 'more', 'at', 'or', 'the', 'docs',
      ]);
      // 围栏代码块:整段丢弃
      expect(tokens, isNot(contains('main')));
      expect(tokens, isNot(contains('runapp')));
      expect(tokens, isNot(contains('makingstuff')));
      // URL 与链接目标:丢弃(链接文字保留)
      expect(tokens, isNot(contains('example')));
      expect(tokens, isNot(contains('dart')));
      expect(tokens, isNot(contains('guides')));
      expect(tokens, isNot(contains('https')));
    });

    test('行内代码:只去掉反引号,内容保留(刻意的取舍)', () {
      expect(
        TextDifficulty.tokenize('run `flutter test` now'),
        ['run', 'flutter', 'test', 'now'],
      );
    });
  });

  group('normalize — 词形归一启发式', () {
    test('原词在词表 → 原样返回(大小写不敏感)', () {
      expect(TextDifficulty.normalize('fox'), 'fox');
      expect(TextDifficulty.normalize('THE'), 'the');
    });

    test('复数:-s / -es / -ies / 所有格', () {
      expect(TextDifficulty.normalize('jumps'), 'jump');
      expect(TextDifficulty.normalize('boxes'), 'box');
      expect(TextDifficulty.normalize('studies'), 'study');
      expect(TextDifficulty.normalize("fox's"), 'fox');
    });

    test('-ing:双写字母还原、结尾 e 还原', () {
      expect(TextDifficulty.normalize('running'), 'run');
      expect(TextDifficulty.normalize('making'), 'make');
      expect(TextDifficulty.normalize('walking'), 'walk');
    });

    test('-ed:补 e / 裸词干 / 去双写', () {
      expect(TextDifficulty.normalize('changed'), 'change');
      expect(TextDifficulty.normalize('walked'), 'walk');
      expect(TextDifficulty.normalize('stopped'), 'stop');
      expect(TextDifficulty.normalize('wanted'), 'want');
      expect(TextDifficulty.normalize('studied'), 'study');
    });

    test('-ly / -er / -est', () {
      expect(TextDifficulty.normalize('quickly'), 'quick');
      expect(TextDifficulty.normalize('nicer'), 'nice');
      expect(TextDifficulty.normalize('bigger'), 'big');
      expect(TextDifficulty.normalize('happier'), 'happy');
      expect(TextDifficulty.normalize('biggest'), 'big');
    });

    test('保守性:不规则形式、未知词、短词都不许瞎还原', () {
      expect(TextDifficulty.normalize('gone'), 'gone'); // 不还原成 go
      expect(TextDifficulty.normalize('children'), 'children');
      expect(TextDifficulty.normalize('zorblat'), 'zorblat');
      expect(TextDifficulty.normalize('thing'), 'thing'); // 不能还成 the
      expect(TextDifficulty.normalize('used'), 'used'); // 不能还成 us
    });

    test('连字符复合词不在这里拆(tokenize 负责)', () {
      expect(TextDifficulty.normalize('well-known'), 'well-known');
    });
  });

  group('analyze — 计数与比率(可手算的例子)', () {
    test('空/纯标点/纯中文:全 0、比率兜底 1.0、不抛异常、时长至少 1', () {
      for (final text in ['', '!!! ...', '这是一段中文材料。']) {
        final d = TextDifficulty.analyze(text, knownWords: const <String>{});
        expect(d.totalTokens, 0, reason: '文本=$text');
        expect(d.uniqueTypes, 0);
        expect(d.knownTypes, 0);
        expect(d.newTypes, 0);
        expect(d.newTokens, 0);
        expect(d.coverage, 1.0);
        expect(d.knownTokenRatio, 1.0);
        expect(d.newWordDensity, 0.0);
        expect(d.fleschReadingEase, 0.0);
        expect(d.fleschKincaidGrade, 0.0);
        expect(d.estMinutes, 1);
        expect(d.topNewWords, isEmpty);
        expect(d.isEmpty, isTrue);
      }
    });

    test('手算例:The the QUICK zzz.(4 词 / 3 词形 / 2 已知)', () {
      final d = TextDifficulty.analyze(
        'The the QUICK zzz.',
        knownWords: const <String>{'the', 'quick'},
      );
      expect(d.totalTokens, 4);
      expect(d.uniqueTypes, 3);
      expect(d.knownTypes, 2);
      expect(d.newTypes, 1);
      expect(d.newTokens, 1);
      expect(d.coverage, closeTo(2 / 3, 1e-12));
      expect(d.knownTokenRatio, closeTo(0.75, 1e-12));
      expect(d.newWordDensity, closeTo(25.0, 1e-12));
      expect(d.topNewWords, ['zzz']);
    });

    test('同一个生词出现 3 次:类型算 1、词次算 3(密度按词次)', () {
      final d = TextDifficulty.analyze(
        'zzz the zzz the zzz',
        knownWords: const <String>{'the'},
      );
      expect(d.totalTokens, 5);
      expect(d.uniqueTypes, 2);
      expect(d.knownTypes, 1);
      expect(d.newTypes, 1);
      expect(d.newTokens, 3);
      expect(d.coverage, closeTo(0.5, 1e-12));
      expect(d.knownTokenRatio, closeTo(0.4, 1e-12));
      expect(d.newWordDensity, closeTo(60.0, 1e-12));
    });

    test('覆盖率边界:全部已知 → 1.0;全部生词 → 0.0', () {
      final all = TextDifficulty.analyze(
        'The quick brown fox jumps.',
        knownWords: const <String>{'the', 'quick', 'brown', 'fox', 'jump'},
      );
      expect(all.totalTokens, 5);
      expect(all.newTypes, 0);
      expect(all.newTokens, 0);
      expect(all.coverage, 1.0);
      expect(all.knownTokenRatio, 1.0);
      expect(all.newWordDensity, 0.0);
      expect(all.topNewWords, isEmpty);
      expect(all.cefr, 'A1');

      final none = TextDifficulty.analyze(
        'the quick',
        knownWords: const <String>{},
      );
      expect(none.uniqueTypes, 2);
      expect(none.knownTypes, 0);
      expect(none.coverage, 0.0);
      expect(none.knownTokenRatio, 0.0);
      expect(none.newWordDensity, 100.0);
    });
  });

  group('topNewWords — 排序与专有名词', () {
    test('高频生词优先;次数相同 → 词频名次更靠后的优先', () {
      // class(72) 比 glass(69) 更罕见;quick(41) 只出现 1 次 → 排最后
      final d = TextDifficulty.analyze(
        'glass small glass small glass small quick',
        knownWords: const <String>{},
      );
      expect(d.newTypes, 3);
      expect(d.topNewWords, ['small', 'glass', 'quick']);
    });

    test('topNewWordsLimit 截断', () {
      final d = TextDifficulty.analyze(
        'glass small quick',
        knownWords: const <String>{},
        topNewWordsLimit: 2,
      );
      expect(d.topNewWords, ['small', 'glass']);
    });

    test('专有名词仍算生词,但排在最后', () {
      // uses → use(归一);daily / readflow 不在表里 → 更罕见 → 先于 use;
      // Readflow 句中大写 → 专有名词 → 垫底
      final d = TextDifficulty.analyze(
        'The fox uses Readflow daily.',
        knownWords: const <String>{'the', 'fox'},
      );
      expect(d.totalTokens, 5);
      expect(d.newTypes, 3);
      expect(d.topNewWords, ['daily', 'use', 'readflow']);
    });

    test('同一词形既作专有名词又作普通词 → 按普通词排', () {
      final d = TextDifficulty.analyze(
        'The Fox company sells fox food.',
        knownWords: const <String>{'the'},
      );
      expect(d.topNewWords, ['fox', 'company', 'food', 'sells']);
    });

    test('looksLikeProperNoun:句中大写 / 缩写算,句首与全小写不算', () {
      expect(TextDifficulty.looksLikeProperNoun('Fox', sentenceInitial: false),
          isTrue);
      expect(TextDifficulty.looksLikeProperNoun('fox', sentenceInitial: false),
          isFalse);
      expect(TextDifficulty.looksLikeProperNoun('Fox', sentenceInitial: true),
          isFalse);
      expect(TextDifficulty.looksLikeProperNoun('NASA', sentenceInitial: true),
          isTrue);
      expect(TextDifficulty.looksLikeProperNoun('a', sentenceInitial: false),
          isFalse);
    });
  });

  group('Flesch / 音节 / 句子', () {
    test('音节启发式:结尾 e、-le、-ed、-es 的具体取值', () {
      expect(TextDifficulty.estimateSyllables('the'), 1);
      expect(TextDifficulty.estimateSyllables('jumps'), 1);
      expect(TextDifficulty.estimateSyllables('make'), 1);
      expect(TextDifficulty.estimateSyllables('makes'), 1);
      expect(TextDifficulty.estimateSyllables('walked'), 1);
      expect(TextDifficulty.estimateSyllables('while'), 1);
      expect(TextDifficulty.estimateSyllables('style'), 1);
      expect(TextDifficulty.estimateSyllables('rhythm'), 1);
      expect(TextDifficulty.estimateSyllables('table'), 2);
      expect(TextDifficulty.estimateSyllables('wanted'), 2);
      expect(TextDifficulty.estimateSyllables('boxes'), 2);
      expect(TextDifficulty.estimateSyllables('walking'), 2);
      expect(TextDifficulty.estimateSyllables('quickly'), 2);
      expect(TextDifficulty.estimateSyllables('well-known'), 2);
      expect(TextDifficulty.estimateSyllables('beautiful'), 3);
    });

    test('句子切分:`.!?` + 空白/结尾,兜底 1 句', () {
      expect(TextDifficulty.countSentences('One. Two! Three?'), 3);
      expect(TextDifficulty.countSentences('No terminator here'), 1);
      expect(TextDifficulty.countSentences(''), 1);
      // 已知偏差:缩写里的点也算句末(取舍:不引入缩写表,宁可多算句)
      expect(TextDifficulty.countSentences('Dr. Smith went home.'), 2);
    });

    test('Flesch 数值可手算:4 个单音节词 + 1 句 → 118.175 / -2.23', () {
      final d = TextDifficulty.analyze(
        'The fox can jump.',
        knownWords: const <String>{'the', 'fox', 'can', 'jump'},
      );
      expect(d.totalTokens, 4);
      expect(d.fleschReadingEase, closeTo(118.175, 0.001));
      expect(d.fleschKincaidGrade, closeTo(-2.23, 0.001));
    });

    test('短句 + 单音节 明显比 长句 + 多音节 易读', () {
      final easy = TextDifficulty.analyze(
        'The fox can jump. The dog can run. A cat can sit.',
        knownWords: const <String>{},
      );
      final hard = TextDifficulty.analyze(
        'The extraordinary international organizations demonstrated '
        'considerable responsibilities.',
        knownWords: const <String>{},
      );
      expect(easy.fleschReadingEase, greaterThan(hard.fleschReadingEase));
      expect(easy.fleschKincaidGrade, lessThan(hard.fleschKincaidGrade));
      expect(easy.fleschReadingEase, greaterThan(100));
      expect(hard.fleschReadingEase, lessThan(0));
    });

    test('Flesch 的句子数不受 URL 影响(URL 整段丢弃)', () {
      expect(
        TextDifficulty.countSentences('See https://example.com/a.b. Next one.'),
        2,
      );
    });
  });

  group('estMinutes / wpm', () {
    final t400 = List<String>.filled(400, 'the').join(' ');
    final t201 = List<String>.filled(201, 'the').join(' ');
    final t200 = List<String>.filled(200, 'the').join(' ');

    test('向上取整,200 词/分钟为默认', () {
      expect(TextDifficulty.analyze(t400, knownWords: const {'the'}).estMinutes,
          2);
      expect(
        TextDifficulty.analyze(t400, knownWords: const {'the'}, wpm: 100)
            .estMinutes,
        4,
      );
      expect(TextDifficulty.analyze(t201, knownWords: const {'the'}).estMinutes,
          2);
      expect(TextDifficulty.analyze(t200, knownWords: const {'the'}).estMinutes,
          1);
      expect(TextDifficulty.analyze('the', knownWords: const {'the'}).estMinutes,
          1);
    });

    test('wpm <= 0 按 200 处理(配置脏数据不该让分析失败)', () {
      expect(
        TextDifficulty.analyze(t400, knownWords: const {'the'}, wpm: 0)
            .estMinutes,
        2,
      );
      expect(
        TextDifficulty.analyze(t400, knownWords: const {'the'}, wpm: -5)
            .estMinutes,
        2,
      );
    });
  });

  group('CEFR 映射', () {
    test('合成易读分的切档边界', () {
      expect(TextDifficulty.cefrFromCoverage(1.0, 0.0), 'A1'); // 1.000
      expect(TextDifficulty.cefrFromCoverage(0.9, 0.0), 'A1'); // 0.925
      expect(TextDifficulty.cefrFromCoverage(0.8, 0.0), 'A2'); // 0.850
      expect(TextDifficulty.cefrFromCoverage(0.6, 0.0), 'B1'); // 0.700 边界
      expect(TextDifficulty.cefrFromCoverage(0.5, 0.0), 'B2'); // 0.625
      expect(TextDifficulty.cefrFromCoverage(0.4, 0.0), 'C1'); // 0.550
      expect(TextDifficulty.cefrFromCoverage(0.2, 0.0), 'C2'); // 0.400
      expect(TextDifficulty.cefrFromCoverage(0.0, 1.0), 'C2'); // 0.000
    });

    test('同覆盖率下生词越罕见 → 级别越高', () {
      expect(TextDifficulty.cefrFromCoverage(0.9, 0.0), 'A1'); // 0.925
      expect(TextDifficulty.cefrFromCoverage(0.9, 0.5), 'A2'); // 0.800
      expect(TextDifficulty.cefrFromCoverage(0.9, 0.7), 'B1'); // 0.750
      expect(TextDifficulty.cefrFromCoverage(0.9, 1.0), 'B2'); // 0.675
    });

    test('单调性:覆盖率往下掉,级别不许回头', () {
      const order = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
      var last = -1;
      for (var c = 1.0; c >= -0.01; c -= 0.05) {
        final idx = order.indexOf(TextDifficulty.cefrFromCoverage(c, 0.3));
        expect(idx, greaterThanOrEqualTo(last), reason: 'coverage=$c');
        last = idx;
      }
      expect(last, 5); // 最低端必须落到 C2
    });

    test('cefrNotes 覆盖 A1..C2 且每条都有解释', () {
      expect(
        TextDifficulty.cefrNotes.keys.toSet(),
        {'A1', 'A2', 'B1', 'B2', 'C1', 'C2'},
      );
      for (final v in TextDifficulty.cefrNotes.values) {
        expect(v.trim(), isNotEmpty);
      }
    });

    test('analyze 里的级别是"相对该用户"的:全认识 → A1;全生词且罕见 → C2', () {
      final easy = TextDifficulty.analyze(
        'The quick brown fox jumps.',
        knownWords: const {'the', 'quick', 'brown', 'fox', 'jump'},
      );
      expect(easy.cefr, 'A1');

      // 三个词都在表尾(69/72/73 名),对"谁都不认识"的用户属于最难档
      final hard = TextDifficulty.analyze(
        'glass pass class',
        knownWords: const <String>{},
      );
      expect(hard.newTypes, 3);
      expect(hard.cefr, 'C2');
    });
  });

  group('不变量(一段有真实感的英文材料)', () {
    const paragraph = '''
# Why We Read Slowly

Reading in a **second language** is not simply slower; it is different.
Researchers have found that readers need to recognize roughly 98 percent of
the words in a text to understand it without help. When the coverage drops,
comprehension collapses — not gradually, but suddenly.

For learners, the practical question is therefore: how many unfamiliar words
does this article contain, and do they repeat often enough to be worth learning?
''';
    const knownWords = <String>{
      'the', 'a', 'in', 'is', 'it', 'to', 'of', 'and', 'that', 'for', 'not',
      'we', 'this', 'do', 'are', 'when', 'how', 'many', 'words', 'second',
      'question', 'help', 'read', 'language',
    };

    test('各计数/比率互相自洽,且都落在合法区间', () {
      final d = TextDifficulty.analyze(paragraph, knownWords: knownWords);
      expect(d.totalTokens, greaterThan(50));
      expect(d.knownTypes + d.newTypes, d.uniqueTypes);
      expect(d.newTypes, lessThanOrEqualTo(d.uniqueTypes));
      expect(d.newTokens, lessThanOrEqualTo(d.totalTokens));
      expect(d.coverage, inInclusiveRange(0.0, 1.0));
      expect(d.knownTokenRatio, inInclusiveRange(0.0, 1.0));
      expect(d.newWordDensity, inInclusiveRange(0.0, 100.0));
      expect(
        d.newWordDensity,
        closeTo(d.newTokens * 100 / d.totalTokens, 1e-9),
      );
      expect(
        d.knownTokenRatio,
        closeTo((d.totalTokens - d.newTokens) / d.totalTokens, 1e-9),
      );
      expect(d.coverage, closeTo(d.knownTypes / d.uniqueTypes, 1e-9));
      expect(d.estMinutes, greaterThanOrEqualTo(1));
      expect(TextDifficulty.cefrNotes.containsKey(d.cefr), isTrue);
    });

    test('topNewWords 都是归一化后的词形,来自本文且不重复', () {
      final d = TextDifficulty.analyze(paragraph, knownWords: knownWords);
      final types = TextDifficulty.tokenize(paragraph)
          .map(TextDifficulty.normalize)
          .toSet();
      expect(types.containsAll(d.topNewWords), isTrue);
      expect(d.topNewWords.toSet().length, d.topNewWords.length);
      expect(d.topNewWords.length, lessThanOrEqualTo(30));
      // 已知词不该出现在生词推荐里
      expect(d.topNewWords.any(knownWords.contains), isFalse);
    });
  });

  group('词表注入 / 百分位', () {    test('rankPercentile:表内按名次,表外与空表 = 1.0', () {
      expect(
        TextDifficulty.rankPercentile('the'),
        closeTo(1 / _baseWords.length, 1e-12),
      );
      expect(TextDifficulty.rankPercentile('book'), closeTo(1.0, 1e-12));
      expect(TextDifficulty.rankPercentile('zzz'), 1.0);
    });

    test('注入后 WordFrequency 与引擎读到的是同一张表', () {
      expect(WordFrequency.isLoaded, isTrue);
      expect(WordFrequency.rankedSize, _baseWords.length);
      expect(WordFrequency.rankOf('fox'), 43);
    });

    test('toString 不抛异常且带上关键指标', () {
      final d = TextDifficulty.analyze(
        'The quick brown fox.',
        knownWords: const {'the', 'quick'},
      );
      expect(d.toString(), contains('tokens=4'));
      expect(d.toString(), contains('cefr='));
    });
  });
}
