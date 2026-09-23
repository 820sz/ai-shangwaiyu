import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/reading_quiz.dart';

/// 读后测验生成器测试。
///
/// 出题是"读后动作"的核心,出错的代价很具体:
/// 干扰项里混进正确答案的同义词、句子切得太碎(挖空后无法推断)、
/// 或者每次都出同一批题(用户背题)。所以断言压在生成规则上。
void main() {
  const text = '''
Reading widely is the fastest way to grow a vocabulary. When you meet a new word
in a real sentence, your brain stores the context along with the meaning.
Deliberate practice, on the other hand, forces you to retrieve the word without
help. Retrieval is uncomfortable, but that discomfort is exactly what makes the
memory durable. A learner who only reads may recognise a word and still fail to
produce it in speech or writing. That is why every serious study routine pairs
input with output, and why feedback matters more than volume.
''';

  List<String> basicTargets() => [
        'vocabulary',
        'context',
        'retrieve',
        'durable',
        'feedback',
        'discomfort',
      ];

  group('完形填空', () {
    test('用材料原句挖空,并把答案放进选项', () {
      final qs = ReadingQuiz.build(text: text, targetWords: basicTargets(), seed: 3);
      expect(qs, isNotEmpty);
      final cloze = qs.firstWhere((q) => q.isCloze);
      expect(cloze.prompt, contains('______'));
      expect(cloze.prompt, isNot(contains(cloze.answer)));
      expect(cloze.options, hasLength(4));
      expect(cloze.options[cloze.answerIndex], cloze.answer);
      expect(cloze.contextSentence, contains(cloze.answer));
    });

    test('干扰项来自同一份材料的其它目标词,不重复且不等于答案', () {
      final qs = ReadingQuiz.build(text: text, targetWords: basicTargets(), seed: 3);
      for (final q in qs.where((e) => e.isCloze)) {
        expect(q.options.toSet(), hasLength(4), reason: '选项不能重复');
        expect(q.options.where((o) => o == q.answer), hasLength(1));
        for (final o in q.options) {
          expect(o, isNot('______'));
          expect(o.trim(), isNotEmpty);
        }
      }
    });

    test('同 seed 出题可复现,不同 seed 会换题(复盘与防背题都要)', () {
      final a = ReadingQuiz.build(text: text, targetWords: basicTargets(), seed: 7);
      final b = ReadingQuiz.build(text: text, targetWords: basicTargets(), seed: 7);
      expect(a.map((e) => e.prompt).toList(), b.map((e) => e.prompt).toList());
      final c = ReadingQuiz.build(text: text, targetWords: basicTargets(), seed: 99);
      // 题目集合(句子)至少有一处不同 —— 干扰项顺序或选句会变
      expect(
        a.map((e) => '${e.prompt}|${e.options.join(",")}').toList(),
        isNot(c.map((e) => '${e.prompt}|${e.options.join(",")}').toList()),
      );
    });

    test('目标词太短(<4 字母)不挖空 —— 挖了也推断不出来', () {
      final qs = ReadingQuiz.build(text: text, targetWords: ['way', 'the'], seed: 1);
      expect(qs.where((e) => e.isCloze && e.sourceWord.length < 4), isEmpty);
    });

    test('目标词不在材料里 → 不出题(宁缺毋滥)', () {
      final qs = ReadingQuiz.build(
        text: text,
        targetWords: ['photosynthesis', 'quantum'],
        seed: 1,
      );
      // 没有可挖空的句子,也没有中文释义 → 空列表而不是硬凑题
      expect(qs, isEmpty);
    });

    test('题量上限生效', () {
      final qs = ReadingQuiz.build(
        text: text,
        targetWords: basicTargets(),
        maxQuestions: 2,
        seed: 5,
      );
      expect(qs.length, lessThanOrEqualTo(2));
    });
  });

  group('中译英回想', () {
    test('有中文释义但材料里没有的词 → 出回想题(不硬凑完形)', () {
      final qs = ReadingQuiz.build(
        text: text,
        targetWords: ['vocabulary', 'photosynthesis'],
        translations: {'photosynthesis': '光合作用'},
        maxQuestions: 5,
        seed: 2,
      );
      final recalls = qs.where((q) => !q.isCloze).toList();
      expect(recalls, hasLength(1));
      expect(recalls.first.sourceWord, 'photosynthesis');
      expect(recalls.first.prompt, contains('光合作用'));
      // 同一个词不会既出完形又出回想
      final clozeWords = qs.where((q) => q.isCloze).map((q) => q.sourceWord).toSet();
      expect(clozeWords.intersection(recalls.map((q) => q.sourceWord).toSet()), isEmpty);
    });

    test('没有中文释义就不出回想题(没有答案依据)', () {
      final qs = ReadingQuiz.build(
        text: text,
        targetWords: ['vocabulary'],
        seed: 2,
      );
      expect(qs.where((q) => !q.isCloze), isEmpty);
    });
  });

  group('评分与错词', () {
    test('完形按选项判分(忽略大小写与空白)', () {
      final qs = ReadingQuiz.build(
        text: text,
        targetWords: basicTargets(),
        seed: 11,
      );
      final cloze = qs.firstWhere((q) => q.isCloze);
      expect(cloze.isCorrect(cloze.options[cloze.answerIndex]), isTrue);
      expect(
        cloze.isCorrect('   ${cloze.options[cloze.answerIndex].toUpperCase()}  '),
        isTrue,
      );
      expect(cloze.isCorrect('definitely-not-an-option'), isFalse);
      expect(cloze.isCorrect(null), isFalse);
    });

    test('回想按拼写判分(忽略大小写与空白)', () {
      // 用一个"材料里没有、但有中文释义"的词,强制生成回想题
      final qs = ReadingQuiz.build(
        text: text,
        targetWords: ['photosynthesis'],
        translations: {'photosynthesis': '光合作用'},
        seed: 11,
      );
      final recall = qs.firstWhere((q) => !q.isCloze);
      expect(recall.isCorrect(' ${recall.answer.toUpperCase()} '), isTrue);
      expect(recall.isCorrect(''), isFalse);
      expect(recall.isCorrect('wrongword'), isFalse);
    });

    test('grade 与 wrongWords 一致(未作答算错)', () {
      final qs = ReadingQuiz.build(
        text: text,
        targetWords: basicTargets(),
        seed: 4,
      );
      final answers = <String?>[
        qs[0].isCloze ? qs[0].options[qs[0].answerIndex] : qs[0].answer,
        null, // 未作答
        ...List<String?>.filled(qs.length - 2, 'wrong'),
      ];
      final correct = ReadingQuiz.grade(qs, answers);
      expect(correct, 1);
      final wrong = ReadingQuiz.wrongWords(qs, answers);
      expect(wrong, hasLength(qs.length - 1));
      expect(wrong.contains(qs[0].sourceWord), isFalse);
    });

    test('summary 按正确率给不同建议(而不是永远"继续加油")', () {
      expect(ReadingQuiz.summary(5, 5), contains('真读懂了'));
      expect(ReadingQuiz.summary(4, 5), contains('大意抓住'));
      expect(ReadingQuiz.summary(2, 5), contains('降低材料难度'));
      expect(ReadingQuiz.summary(0, 5), contains('偏难'));
      expect(ReadingQuiz.summary(0, 0), contains('没有生成题目'));
    });
  });

  group('句子切分', () {
    test('丢掉过短/过长句子,保留适合挖空的句子', () {
      final s = ReadingQuiz.splitSentences(
        'Too short. ${'A' * 300}. '
        'This is a reasonably long sentence with enough words to be worth blanking.',
      );
      expect(s, hasLength(1));
      expect(s.first, contains('reasonably long'));
    });

    test('空文本/纯标点不抛异常', () {
      expect(ReadingQuiz.splitSentences(''), isEmpty);
      expect(ReadingQuiz.splitSentences('...!!??'), isEmpty);
      expect(ReadingQuiz.build(text: '', targetWords: ['vocabulary']), isEmpty);
      expect(ReadingQuiz.build(text: text, targetWords: const []), isEmpty);
    });
  });
}
