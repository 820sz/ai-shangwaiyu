import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/cloze_practice.dart';

/// 批 7 · P1-1 语境选词填空的纯逻辑测试。
///
/// 用户核心哲学:"背单词必须基于输入输出闭环与材料语境"。
/// 守的是"题真的来自材料句子、且选项是真实词而不是编造"这几条契约:
/// - 句子挖空位置正确、目标词不在选项里重复;
/// - 4 个选项含答案,干扰项是真实英文词、不与答案形近;
/// - 同一 seed 可复现,材料里命中不够就少给/不给(绝不编句子);
/// - 大小写/词边界匹配(Happens/Unprecedented 这类句首词也能挖)。
void main() {
  const material = '''
Reading opens a door to a world we have never seen. Through books, we meet people
from different cultures and learn to see problems from more than one angle.

A single hour of reading can change the way we think for years. This is why many
successful people devote at least thirty minutes to reading every day.

They insist that reading is not a task but a habit, and that the habit needs patience
and practice. Without practice, even a simple habit fades away.
''';

  Map<String, String> meanings() => {
        'reading': '阅读',
        'habits': '习惯',
        'patience': '耐心',
        'practice': '练习',
        'successful': '成功的',
        'different': '不同的',
        'problems': '问题',
        'through': '通过',
        'simple': '简单的',
      };

  List<String> wordsInMaterial(String text) =>
      ClozePractice.wordsIn(text).where((w) => w.length >= 3).toList();

  List<String> pool() => wordsInMaterial(material);

  test('造题:句子来自材料、挖空正确、答案在选项里且不重复', () {
    final set = ClozePractice.build(
      materialTitle: '测试材料',
      materialText: material,
      candidateMeanings: meanings(),
      poolWords: pool(),
      count: 5,
      seed: 7,
    );
    expect(set.items, isNotEmpty);
    expect(set.items.length, lessThanOrEqualTo(5));
    for (final item in set.items) {
      // 题面必须含空位、原句含答案
      expect(item.sentence.contains('____'), isTrue);
      expect(item.sentence.contains('____'), isTrue);
      expect(item.sourceSentence.toLowerCase(), contains(item.answer.toLowerCase()));
      // 选项:4 个、去重、包含答案
      expect(item.options.length, 4);
      expect(item.options.toSet().length, 4);
      expect(
        item.options.map((o) => o.toLowerCase()),
        contains(item.answer.toLowerCase()),
      );
      // 干扰项不是答案的形近词(不做成拼写题)
      for (final o in item.options) {
        if (o.toLowerCase() == item.answer.toLowerCase()) continue;
        expect(o.toLowerCase().startsWith(item.answer.toLowerCase()), isFalse);
        expect(item.answer.toLowerCase().startsWith(o.toLowerCase()), isFalse);
      }
    }
  });

  test('同一 seed 生成同一组题(再来一轮可复现)', () {
    final a = ClozePractice.build(
      materialTitle: 'm',
      materialText: material,
      candidateMeanings: meanings(),
      poolWords: pool(),
      count: 4,
      seed: 42,
    );
    final b = ClozePractice.build(
      materialTitle: 'm',
      materialText: material,
      candidateMeanings: meanings(),
      poolWords: pool(),
      count: 4,
      seed: 42,
    );
    expect(
      a.items.map((e) => e.answer).toList(),
      b.items.map((e) => e.answer).toList(),
    );
    expect(
      a.items.map((e) => e.sentence).toList(),
      b.items.map((e) => e.sentence).toList(),
    );
  });

  test('候选词在材料里不存在时返回空题组(绝不编句子)', () {
    final set = ClozePractice.build(
      materialTitle: 'm',
      materialText: material,
      candidateMeanings: const {'astronaut': '宇航员', 'quantum': '量子'},
      poolWords: pool(),
      count: 3,
      seed: 1,
    );
    expect(set.items, isEmpty);
    expect(set.isEmpty, isTrue);
  });

  test('干扰项不足 3 个时宁可少给题,不硬凑', () {
    // 只给 2 个真实词做池:干扰项只有 1 个 → 该题不能出
    final set = ClozePractice.build(
      materialTitle: 'm',
      materialText: 'She likes reading books.',
      candidateMeanings: const {'reading': '阅读'},
      poolWords: const ['reading', 'books'],
      count: 3,
      seed: 2,
    );
    expect(set.items, isEmpty);
  });

  test('句首大写词也能挖空,且答案保留原大小写', () {
    final set = ClozePractice.build(
      materialTitle: 'm',
      materialText:
          'Reading is a habit that rewards people who keep at it every single day.',
      candidateMeanings: const {'reading': '阅读'},
      poolWords: const ['books', 'habit', 'people', 'rewards', 'keep', 'single'],
      count: 1,
      seed: 3,
    );
    expect(set.items, hasLength(1));
    expect(set.items.first.answer, 'Reading');
    expect(set.items.first.sentence.startsWith('____'), isTrue);
    expect(set.items.first.isCorrect('reading'), isTrue,
        reason: '判分要大小写不敏感');
  });

  test('太短的句子不挖空(避免没有语境)', () {
    final set = ClozePractice.build(
      materialTitle: 'm',
      materialText: 'I like reading.',
      candidateMeanings: const {'reading': '阅读'},
      poolWords: const ['books', 'habit', 'people', 'rewards'],
      count: 1,
      seed: 4,
    );
    expect(set.items, isEmpty);
  });
}
