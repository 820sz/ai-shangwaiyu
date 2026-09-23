import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/learner_model.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/learner_context.dart';
import 'package:readflow/services/word_frequency.dart';

/// 粘合层测试:它决定了"难度分析到底拿谁当已知词"。
/// 这一层错了,覆盖率数字会好看但没意义 —— 比没有更糟。
void main() {
  setUp(() {
    // 造一张 20 词的小词表:名次 1..20(the=1, …, 第 20 个最罕见)
    final words = [
      'the', 'of', 'and', 'to', 'a', 'in', 'is', 'it', 'you', 'that',
      'he', 'was', 'for', 'on', 'are', 'with', 'as', 'his', 'they', 'quixotic',
    ];
    WordFrequency.debugInject(
      words: words,
      counts: List<int>.generate(words.length, (i) => 1000 - i * 10),
    );
  });

  LearnerModel measured(int vocab, {double confidence = 0.9}) => LearnerModel(
        vocabEstimate: ProfileField<int>(
          value: vocab,
          source: ProfileSource.test,
          confidence: confidence,
        ),
      );

  Vocabulary word(String w, int mastery, {int id = 1}) => Vocabulary(
        id: id,
        word: w,
        masteryLevel: mastery,
        createdAt: DateTime(2026, 9, 1),
      );

  group('有效词汇量与基线描述', () {
    test('测量值优先于保底;未测时用保底并说明"尚未测"', () {
      expect(LearnerContext.effectiveVocab(measured(6500)), 6500);
      expect(
        LearnerContext.effectiveVocab(LearnerModel()),
        LearnerContext.floorWhenUnmeasured,
      );
      expect(LearnerContext.hasMeasuredBaseline(measured(6500)), isTrue);
      expect(LearnerContext.hasMeasuredBaseline(LearnerModel()), isFalse);
    });

    test('自报不算"测量基线"(自评普遍偏差 1-2 级)', () {
      final self = LearnerModel(
        vocabEstimate: ProfileField<int>(
          value: 8000,
          source: ProfileSource.self,
          confidence: 0.5,
        ),
      );
      expect(LearnerContext.hasMeasuredBaseline(self), isFalse);
      expect(LearnerContext.describeBaseline(self), contains('你的自评'));
    });

    test('describeBaseline 把依据与可信度摆给用户看', () {
      final withRange = LearnerModel(
        vocabEstimate: ProfileField<int>(
          value: 6800,
          source: ProfileSource.test,
          confidence: 0.9,
        ),
        vocabLow: 6100,
        vocabHigh: 7500,
      );
      final s = LearnerContext.describeBaseline(withRange);
      expect(s, contains('词汇量测试'));
      expect(s, contains('6800'));
      expect(s, contains('6100-7500'));
      expect(s, contains('较可信'));

      final untested = LearnerContext.describeBaseline(LearnerModel());
      expect(untested, contains('尚未测'));
      expect(untested, contains('5 分钟'), reason: '要给出可执行的下一步');
    });
  });

  group('已知词集合', () {
    test('名次 ≤ 估计词汇量的词全部计入', () {
      final known = LearnerContext.knownWords(model: measured(10));
      // 名次 1..10 共 10 个词
      expect(known.length, 10);
      expect(known.contains('the'), isTrue);
      expect(known.contains('that'), isTrue);
      expect(known.contains('he'), isFalse, reason: '名次 11 不该被推定认识');
      expect(known.contains('quixotic'), isFalse);
    });

    test('生词本里已掌握/学习中的词额外计入(超出估计名次也算)', () {
      final known = LearnerContext.knownWords(
        model: measured(3),
        vocab: [
          word('quixotic', 2), // 已掌握 → 计入
          word('they', 1, id: 2), // 学习中 → 计入
          word('his', 0, id: 3), // 新词 → 不计入(那正是要学的)
        ],
      );
      expect(known.contains('quixotic'), isTrue);
      expect(known.contains('they'), isTrue);
      expect(known.contains('his'), isFalse);
    });

    test('normalize 钩子能把变形词对上(否则会低估覆盖率)', () {
      final withHook = LearnerContext.knownWords(
        model: measured(3),
        vocab: [word('Jumped', 2)],
        normalize: (w) => w.endsWith('ed') ? w.substring(0, w.length - 2) : w,
      );
      expect(withHook.contains('jump'), isTrue);
      // 不传钩子时保留原始小写形式(保守)
      final without = LearnerContext.knownWords(
        model: measured(3),
        vocab: [word('Jumped', 2)],
      );
      expect(without.contains('jumped'), isTrue);
      expect(without.contains('jump'), isFalse);
    });

    test('vocabOverride 允许"用某个假设词汇量试算"', () {
      final a = LearnerContext.knownWords(model: measured(5));
      final b = LearnerContext.knownWords(model: measured(5), vocabOverride: 15);
      expect(b.length, greaterThan(a.length));
      expect(b.length, 15);
    });
  });

  group('阅读速度与难度提示', () {
    test('wpm 实测优先,越界或缺失回落默认值', () {
      expect(LearnerContext.wpmFor(LearnerModel()), LearnerContext.defaultWpm);
      expect(
        LearnerContext.wpmFor(LearnerModel(extras: const {'reading_wpm': 240})),
        240,
      );
      expect(
        LearnerContext.wpmFor(LearnerModel(extras: const {'reading_wpm': 5})),
        LearnerContext.defaultWpm,
        reason: '明显不合理的实测值不能拿去算时长',
      );
    });

    test('难度提示与 i+1 阈值一致(阈值只有一处)', () {
      expect(LearnerContext.difficultyHint(0.99), contains('轻松'));
      expect(LearnerContext.difficultyHint(0.96), contains('舒适'));
      expect(LearnerContext.difficultyHint(0.92), contains('挑战'));
      expect(LearnerContext.difficultyHint(0.80), contains('偏难'));
      expect(LearnerContext.isComfortable(0.96), isTrue);
      expect(LearnerContext.isComfortable(0.99), isFalse);
      expect(LearnerContext.isComfortable(0.90), isFalse);
    });
  });
}
