import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/lemma.dart';
import 'package:readflow/services/word_frequency.dart';

/// 原型备注测试(v2.4,B2 用户要求:`taming` → `taming(tame)`)。
///
/// 关键在"**没有把握就别写**":宁可没有括号,也不能给错原型 ——
/// 用户是照着这个背的。所以这里既测"该还原的还原对",也测"不该猜的不猜"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 注入确定性词表:名次 = 下标 + 1
    const words = [
      'tame', 'take', 'run', 'study', 'watch', 'box', 'go', 'walk', 'love',
      'stop', 'child', 'tooth', 'life', 'knife', 'person', 'be', 'good',
      'make', 'have', 'write', 'eat', 'swim', 'sing', 'analysis', 'criterion',
      'news', 'bus', 'business', 'artist', 'art', 'the', 'apple', 'time',
    ];
    WordFrequency.debugInject(
      words: words,
      counts: List<int>.generate(words.length, (i) => 10000 - i),
    );
  });

  group('该还原的还原对', () {
    test('进行时:去 e / 直接加 / 双写还原', () {
      expect(Lemma.baseOf('taming'), 'tame');
      expect(Lemma.baseOf('taking'), 'take');
      expect(Lemma.baseOf('walking'), 'walk');
      expect(Lemma.baseOf('running'), 'run');
      expect(Lemma.baseOf('studying'), 'study');
      expect(Lemma.baseOf('swimming'), 'swim');
    });

    test('过去式:-ed / -ied / 双写 / 加 e', () {
      expect(Lemma.baseOf('walked'), 'walk');
      expect(Lemma.baseOf('loved'), 'love');
      expect(Lemma.baseOf('stopped'), 'stop');
      expect(Lemma.baseOf('studied'), 'study');
    });

    test('复数/三单:-s / -es / -ies', () {
      expect(Lemma.baseOf('apples'), 'apple');
      expect(Lemma.baseOf('watches'), 'watch');
      expect(Lemma.baseOf('boxes'), 'box');
      expect(Lemma.baseOf('goes'), 'go');
      expect(Lemma.baseOf('studies'), 'study');
    });

    test('不规则表:动词与不规则复数', () {
      expect(Lemma.baseOf('written'), 'write');
      expect(Lemma.baseOf('ate'), 'eat');
      expect(Lemma.baseOf('children'), 'child');
      expect(Lemma.baseOf('teeth'), 'tooth');
      expect(Lemma.baseOf('lives'), 'life');
      expect(Lemma.baseOf('was'), 'be');
    });
  });

  group('没有把握时不给原型(宁可少写也不能写错)', () {
    test('候选不是真词 → 不还原', () {
      // bus 去掉 s 是 "bu"(不是词);business 去掉 es 是 "busine"(不是词)
      expect(Lemma.baseOf('bus'), isNull);
      expect(Lemma.baseOf('business'), isNull);
      expect(Lemma.baseOf('news'), isNull);
    });

    test('原型等于自身 → 不给', () {
      expect(Lemma.baseOf('tame'), isNull);
      expect(Lemma.baseOf('walk'), isNull);
      expect(Lemma.baseOf('apple'), isNull);
    });

    test('短语/句子/带连字符/专有名词/数字都不猜', () {
      expect(Lemma.baseOf('began to blur'), isNull);
      expect(Lemma.baseOf("don't"), isNull);
      expect(Lemma.baseOf('nature-versus-nurture'), isNull);
      expect(Lemma.baseOf('APPLE'), isNull);
      expect(Lemma.baseOf('p12'), isNull);
      expect(Lemma.baseOf(''), isNull);
    });

    test('词表里没有候选词 → 一律不还原(等价于"没把握",不给错原型)', () {
      WordFrequency.debugInject(words: const [], counts: const []);
      expect(Lemma.baseOf('taming'), isNull);
      expect(Lemma.baseOf('studies'), isNull);
      expect(Lemma.baseOf('children'), isNull, reason: '不规则表也要过"真词"校验');
    });
  });

  group('词条显示:textWithLemma / displayFull', () {
    Vocabulary word(String w, {String type = 'word', List<dynamic> occ = const []}) =>
        Vocabulary(word: w, wordType: type);

    test('单词带原型备注', () {
      expect(word('taming').wordWithLemma, 'taming(tame)');
      expect(word('children').wordWithLemma, 'children(child)');
    });

    test('短语/句子不加备注(不是词形变化问题)', () {
      expect(word('began to blur', type: 'phrase').wordWithLemma, isNull);
      expect(word('It never is.', type: 'sentence').wordWithLemma, isNull);
    });

    test('原型推不出来时不加括号,但词条照常显示', () {
      expect(word('news').wordWithLemma, isNull);
      expect(word('news').displayFull, 'news');
    });
  });
}
