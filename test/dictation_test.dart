import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/dictation.dart';

/// 听写判分的回归测试。
///
/// 判分是这个功能唯一的"客观性"来源:算法错了,用户会得到一张假成绩单。
/// 所以断言压在**具体分数与漏词列表**上,而不是"有返回值"。
void main() {
  const sentence =
      'Reading widely is the fastest way to grow a vocabulary.';

  group('句子挑选', () {
    test('挑出长度合适的句子,太短/太长都不要', () {
      final long = List.filled(40, 'word').join(' ');
      final text = 'Too short. '
          'Reading widely is the fastest way to grow a vocabulary quickly. '
          '$long. Another good sentence for dictation practice here.';
      final picked = Dictation.pickSentences(text, count: 5);
      expect(picked, isNotEmpty);
      for (final s in picked) {
        final words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        expect(words, greaterThanOrEqualTo(Dictation.minWords));
        expect(words, lessThanOrEqualTo(Dictation.maxWords));
      }
      expect(picked.any((s) => s.startsWith('Too short')), isFalse);
    });

    test('同 seed 同结果,且顺序跟原文一致(可复现)', () {
      const text = 'First good sentence for dictation practice here. '
          'Second one is also long enough to be picked today. '
          'And the third sentence is fine as well for practice.';
      final a = Dictation.pickSentences(text, count: 3, seed: 7);
      final b = Dictation.pickSentences(text, count: 3, seed: 7);
      expect(a, b);
      final positions = a.map((s) => text.indexOf(s)).toList();
      final sorted = [...positions]..sort();
      expect(positions, sorted, reason: '听写顺序应与阅读顺序一致');
    });

    test('文字太少/全是短句 → 返回空列表(宁缺毋滥)', () {
      expect(Dictation.pickSentences(''), isEmpty);
      expect(Dictation.pickSentences('Hi. Ok. Yes.'), isEmpty);
    });
  });

  group('判分', () {
    test('完全一致 → 100%', () {
      final r = Dictation.grade(sentence, sentence);
      expect(r.accuracy, 1.0);
      expect(r.perfect, isTrue);
      expect(r.missing, isEmpty);
      expect(r.extra, isEmpty);
      expect(r.scoreLine, '100%');
      expect(r.comment, '完全正确');
    });

    test('忽略大小写与标点(听写的重点是词,不是排版)', () {
      final r = Dictation.grade(
        sentence,
        'reading widely is the fastest way to grow a vocabulary',
      );
      expect(r.accuracy, 1.0);
    });

    test('漏词 → 正确率下降,并指出漏了哪个词', () {
      final r = Dictation.grade(sentence, 'Reading widely is the way to grow a vocabulary.');
      expect(r.accuracy, lessThan(1.0));
      expect(r.accuracy, greaterThan(0.7));
      expect(r.missing, contains('fastest'));
      expect(r.comment, contains('fastest'));
    });

    test('多打的词进 extra,不影响漏词判定', () {
      final r = Dictation.grade('the quick brown fox', 'the very quick brown fox jumps');
      expect(r.extra, containsAll(['very', 'jumps']));
      expect(r.missing, isEmpty);
      expect(r.accuracy, 1.0, reason: '原文四个词都打对了');
    });

    test('顺序错乱但词都在 → 用 LCS 扣正确率,并说明是语序问题', () {
      final r = Dictation.grade('one two three four', 'one three two four');
      expect(r.accuracy, greaterThan(0.5));
      expect(r.accuracy, lessThan(1.0));
      // "漏词"的语义是"完全没打出来的词":这里四个词都打了 → 空
      expect(r.missing, isEmpty);
      expect(r.comment, contains('语序'));
    });

    test('空答案 → 0% 并给"再放一遍"的具体建议', () {
      final r = Dictation.grade(sentence, '   ');
      expect(r.accuracy, 0.0);
      expect(r.comment, contains('再放一遍'));
      expect(Dictation.grade(sentence, 'totally unrelated words here now').accuracy,
          lessThan(0.3));
    });

    test('评语分档:每档都给出可执行信息(不是"加油")', () {
      final perfect = Dictation.grade(sentence, sentence);
      final goodish = Dictation.grade(
        sentence,
        'Reading widely is the fastest way grow vocabulary',
      );
      final half = Dictation.grade(sentence, 'Reading widely is the fastest');
      final poor = Dictation.grade(sentence, 'Reading');
      expect(perfect.comment, '完全正确');
      expect(goodish.comment.length, greaterThan(6));
      expect(half.comment, isNot(contains('加油')));
      expect(poor.comment, contains('偏难'));
    });
  });

  group('一轮总结与错词', () {
    test('总结带平均分与全对句数', () {
      final results = [
        Dictation.grade(sentence, sentence),
        Dictation.grade(sentence, 'Reading widely is the fastest way to grow a vocabulary'),
        Dictation.grade('Another sentence for practice here now', 'Another'),
      ];
      final line = Dictation.summaryLine(results);
      expect(line, contains('平均'));
      expect(line, contains('%'));
      expect(line, contains('3 句'));
      expect(Dictation.summaryLine(const []), contains('没有可听写'));
    });

    test('错词汇总:去重、过滤 3 字母以下虚词、有上限', () {
      final results = [
        Dictation.grade('alpha beta gamma delta', 'alpha'),
        Dictation.grade('alpha epsilon zeta', 'alpha'),
      ];
      final words = Dictation.missWords(results);
      expect(words, containsAll(['beta', 'gamma', 'delta', 'epsilon', 'zeta']));
      expect(words.toSet().length, words.length, reason: '不能重复');
      final many = Dictation.missWords(
        [Dictation.grade(List.generate(50, (i) => 'word$i').join(' '), '')],
      );
      // 3 字母以下的被过滤;这里都是 5 字母,受上限约束
      expect(many.length, lessThanOrEqualTo(30));
    });
  });
}
