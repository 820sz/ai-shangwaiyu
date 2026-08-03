import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/utils/scoring.dart';

void main() {
  group('scoreBackTranslation — 英文参考答案(新练习)', () {
    test('逐句完全正确 → 100 分', () {
      final score = scoreBackTranslation(
        ['The cat sat on the mat', 'I love reading books'],
        ['The cat sat on the mat', 'I love reading books'],
      );
      expect(score, 100.0);
    });

    test('全部空白 → 0 分', () {
      final score = scoreBackTranslation(
        ['', '   '],
        ['The cat sat on the mat', 'I love reading books'],
      );
      expect(score, 0.0);
    });

    test('答对一半句子(词覆盖≥50%)→ 50 分', () {
      // 第 1 句覆盖 3/6 = 50% 词,算对;第 2 句空白算错
      final score = scoreBackTranslation(
        ['the cat sat mat table chair', ''],
        ['The cat sat on the mat', 'I love reading books'],
      );
      expect(score, 50.0);
    });

    test('词序不同但词全对 → 仍算对(词集合评分)', () {
      final score = scoreBackTranslation(
        ['mat the on sat cat The'],
        ['The cat sat on the mat'],
      );
      expect(score, 100.0);
    });

    test('时态/拼写差异导致覆盖不足 → 算错', () {
      // 只覆盖 2/6 词,不足 50%
      final score = scoreBackTranslation(
        ['The cat is here now'],
        ['The cat sat on the mat'],
      );
      expect(score, 0.0);
    });
  });

  group('scoreBackTranslation — 中文题面(旧练习,长度启发式)', () {
    test('长度达标 → 算对', () {
      final score = scoreBackTranslation(
        ['A reasonably long english answer'],
        ['一只猫坐在垫子上。'],
      );
      expect(score, 100.0);
    });

    test('答太短 → 算错', () {
      final score = scoreBackTranslation(
        ['hi'],
        ['一只猫坐在垫子上。'],
      );
      expect(score, 0.0);
    });
  });

  group('边界', () {
    test('参考答案列表为空 → 0 分不崩溃', () {
      expect(scoreBackTranslation(['a'], []), 0.0);
    });

    test('答案少于参考句数 → 按最小长度计分', () {
      final score = scoreBackTranslation(
        ['The cat sat on the mat'],
        ['The cat sat on the mat', 'I love reading books'],
      );
      expect(score, 50.0);
    });

    test('参考答案为空串 → 跳过不计分', () {
      final score = scoreBackTranslation(['anything'], ['']);
      expect(score, 0.0);
    });
  });
}
