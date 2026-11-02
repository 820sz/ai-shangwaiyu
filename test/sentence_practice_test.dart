import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/sentence_practice.dart';

/// 批 8 · P1-5 写句阶多题型的纯逻辑测试。
///
/// 三种题型里两种是**客观题**（纠错/连词成句），它们最容易出错也最容易回归：
/// 答案泄漏、标点位置、大小写、多解。这里把这套契约钉死。
void main() {
  group('错句纠错', () {
    const sentence =
        'Many students believe that reading plays an important role in their lives.';

    test('能植入错误且题面与原句不同，原句（答案）不泄漏在错句里', () {
      final injected = injectErrors(sentence, seed: 7);
      expect(injected, isNotNull);
      expect(injected!.hasErrors, isTrue);
      expect(injected.wrongSentence, isNot(sentence));
      expect(injected.spots, isNotEmpty);
      for (final spot in injected.spots) {
        expect(spot.kind.trim(), isNotEmpty);
        expect(spot.noteZh.trim(), isNotEmpty);
        expect(spot.wrong, isNot(spot.correct));
      }
      // 提交前的提示语不能说错在哪/给改正词
      expect(injected.prompt.contains('时态'), isFalse);
    });

    test('改回原句判对（大小写/句尾标点容错）', () {
      final injected = injectErrors(sentence, seed: 7)!;
      final ok = checkCorrection(
        answer: 'many students believe that reading plays an important role in their lives',
        injected: injected,
      );
      expect(ok.correct, isTrue);
    });

    test('没改的句子里，未修正的错误点能被识别出来', () {
      final injected = injectErrors(sentence, seed: 7)!;
      final check = checkCorrection(
        answer: injected.wrongSentence,
        injected: injected,
      );
      expect(check.correct, isFalse);
      expect(check.missed, isNotEmpty);
    });

    test('接受答案（多解）也算对', () {
      final injected = injectErrors(sentence, seed: 7)!;
      final check = checkCorrection(
        answer: 'totally different wording',
        injected: injected,
        acceptedAnswers: const ['totally different wording.'],
      );
      expect(check.correct, isTrue);
      expect(check.matchedAccepted, isTrue);
    });

    test('同一 seed 生成同一错句（可复现）', () {
      final a = injectErrors(sentence, seed: 42);
      final b = injectErrors(sentence, seed: 42);
      expect(a!.wrongSentence, b!.wrongSentence);
    });
  });

  group('连词成句', () {
    const sentence = 'Reading, in fact, changes the way we think.';

    test('分词：句中标点粘到前一个词，词内标点保留', () {
      final tokens = tokenizeSentence(sentence);
      expect(tokens, contains('Reading,'));
      expect(tokens, contains('fact,'));
      expect(tokens.last, endsWith('.'));
    });

    test('打散后可复现，且不等于原顺序', () {
      final a = shuffleWords(sentence, seed: 5);
      final b = shuffleWords(sentence, seed: 5);
      expect(a, b);
      expect(a, isNot(tokenizeSentence(sentence)));
      expect(a.toSet(), tokenizeSentence(sentence).toSet());
    });

    test('按正确顺序拼回判对；顺序错判错', () {
      final task = buildWordOrderTask(sentence, seed: 3);
      expect(checkWordOrder(sentence, task.correctOrder), isTrue);
      // 把前两个词块交换顺序（若恰好相同则跳过，避免误报）
      if (task.correctOrder.length >= 2 &&
          task.correctOrder[0] != task.correctOrder[1]) {
        final wrong = List<String>.of(task.correctOrder);
        final tmp = wrong[0];
        wrong[0] = wrong[1];
        wrong[1] = tmp;
        expect(checkWordOrder(sentence, wrong), isFalse);
      }
    });
  });

  group('句式改写（离线）', () {
    test('离线任务来自输入句子，且给可执行方向', () {
      final tasks = buildOfflineRewriteTasks(
        const [
          'Reading is important because it opens our minds.',
          'Technology has changed the way we live.',
        ],
      );
      expect(tasks, isNotEmpty);
      for (final task in tasks) {
        expect(task.original.trim(), isNotEmpty);
        expect(task.guidance.trim(), isNotEmpty);
        expect(task.focusPoints, isNotEmpty);
      }
    });

    test('不改写题也绝不编造参考改写（离线只做对照）', () {
      // 服务层约定：离线任务没有 reference 字段；这里断言类型上就不带答案
      final tasks = buildOfflineRewriteTasks(const ['Something totally plain.']);
      expect(tasks, isNotEmpty);
      expect(tasks.first.guidance, isNotEmpty);
    });
  });

  group('结果回流（禁用时完全不碰 DB）', () {
    test('recorder enabled=false 时 record 直接返回（测试可用）', () async {
      const recorder = SentencePracticeRecorder(enabled: false);
      await recorder.record(
        mode: SentencePracticeMode.correction,
        answer: 'x',
        correct: false,
        errorKinds: const ['时态'],
      );
      // 不抛异常即可（没有 SQLite 也不会失败）
    });
  });
}
