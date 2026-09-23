import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/word_frequency.dart';

/// 词频资产冒烟测试(v2.0 地基)。
///
/// 这条测试的价值:**验证 assets 管道真的通了** ——
/// `flutter test` 与真机都会从 asset bundle 读 `assets/data/*`,
/// 一旦 pubspec 漏声明目录、文件被 .gitignore 吃掉、或解析函数退化,
/// 这里会立刻红,而不是等到用户点开"词汇量测试"才发现是空的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('两份词频数据能从 asset bundle 加载并解析', () async {
    await WordFrequency.ensureLoaded();

    expect(WordFrequency.isLoaded, isTrue);
    // 50k 表:至少 4 万条被保留(过滤掉纯数字/非法行后仍有 5 万)
    expect(WordFrequency.rankedSize, greaterThan(40000));
    // 干净 10k 池:书面语抽样池,至少 9 千条
    expect(WordFrequency.clean10k.length, greaterThan(9000));
  });

  test('名次与频次查询符合语料常识(the 第一档、罕见词名次靠后)', () async {
    await WordFrequency.ensureLoaded();

    // the/you/i 一定在最常用的前几名里(OpenSubtitles 语料实测如此)
    expect(WordFrequency.rankOf('the'), lessThanOrEqualTo(5));
    expect(WordFrequency.countOf('the'), greaterThan(1000000));

    // 名次越大频次越低(抽查两处单调性)
    final r100 = WordFrequency.rankOf('time');
    expect(r100, greaterThan(0));
    expect(WordFrequency.countOf('time'), lessThan(WordFrequency.countOf('the')));

    // 不存在的词 → 名次 0、频次 0(调用方据此判"更罕见")
    expect(WordFrequency.rankOf('zzzzqqqxx'), 0);
    expect(WordFrequency.countOf('zzzzqqqxx'), 0);
  });

  test('确定性抽样:同 seed 同结果、片区内词名次正确、通过可测词过滤', () async {
    await WordFrequency.ensureLoaded();

    final a = WordFrequency.sampleBand(1, 1000, count: 12, seed: 7);
    final b = WordFrequency.sampleBand(1, 1000, count: 12, seed: 7);
    final c = WordFrequency.sampleBand(1, 1000, count: 12, seed: 8);

    expect(a.length, 12);
    expect(a, equals(b), reason: '同 seed 必须完全可复现(测试结果要能被复盘)');
    expect(a, isNot(equals(c)), reason: '不同 seed 应给出不同题目(避免背题)');

    for (final w in a) {
      expect(WordFrequency.isTestableWord(w), isTrue, reason: '$w 不该出现在测试里');
      final r = WordFrequency.rankOf(w);
      expect(r, greaterThanOrEqualTo(1));
      expect(r, lessThanOrEqualTo(1000));
    }
  });

  test('伪词生成:形状像真词、但确实不在词表里(否则校准会失真)', () async {
    await WordFrequency.ensureLoaded();

    final made = <String>[];
    for (var i = 0; i < 20; i++) {
      final w = WordFrequency.makePseudoword(_SeqRandom(i * 31 + 7));
      if (w != null) made.add(w);
    }
    expect(made.length, greaterThan(10), reason: '伪词生成不应大面积失败');
    for (final w in made) {
      expect(WordFrequency.contains(w), isFalse, reason: '$w 撞到真词了');
      expect(RegExp(r'^[a-z]{3,}$').hasMatch(w), isTrue, reason: '$w 不像英文词');
    }
  });

  test('rankedUpTo(不过滤)与 bandWords(出题过滤)必须分得清', () async {
    await WordFrequency.ensureLoaded();

    // 出题用:短词/语气词被滤掉,不会拿去问用户
    final forQuiz = WordFrequency.bandWords(1, 50, cleanOnly: true);
    for (final w in forQuiz) {
      expect(WordFrequency.isTestableWord(w), isTrue);
    }
    // 判"已知词"用:功能词必须保留 —— 否则 the/of/to 会被算成生词,
    // 覆盖率(以及基于它的难度评估/材料推荐)会全线低估
    final forCoverage = WordFrequency.rankedUpTo(50);
    expect(forCoverage.length, 50);
    expect(forCoverage.contains('the'), isTrue);
    expect(
      forCoverage.where((w) => w.length <= 2).isNotEmpty,
      isTrue,
      reason: '前 50 名里必然有 of/to/in 这类 2 字母功能词',
    );
    expect(
      forCoverage.length,
      greaterThanOrEqualTo(forQuiz.length),
      reason: '不过滤的数量只会更多,不可能更少',
    );
  });
}

/// 测试内联的确定性随机源(避免依赖 dart:math 的实现细节)
class _SeqRandom implements Random {
  _SeqRandom(this._seed);
  int _seed;
  int _next() {
    _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
    return _seed;
  }

  @override
  bool nextBool() => _next().isEven;

  @override
  double nextDouble() => _next() / 0x7fffffff;

  @override
  int nextInt(int max) => _next() % max;
}
