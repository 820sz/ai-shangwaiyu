import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/services/vocab_estimator.dart';
import 'package:readflow/services/word_frequency.dart';

/// 合成词表的规模:足够覆盖 6 个档位(1..20000)。
const int kTableSize = 20000;

/// 程序化生成唯一的纯字母"词"。
///
/// 为什么不能用 `w00001` 这种:WordFrequency.isTestableWord 要求**纯字母**且长度 ≥ 3,
/// 带数字的词会被过滤掉,抽样池就空了。这里生成 `aaba`/`aabc`… 这类 4 字母纯小写词:
/// 第 1 位固定 'a'、第 2 位固定 'b'、第 3 位 'a'..'z'、第 4 位 'a'..'z' → 共 676 个,
/// 再把中间位升级成 3 字母前缀继续枚举,凑满 [kTableSize] 个。
/// 第 1 位永远是 'a' → 伪词生成器"改一个字母"不可能撞上任何表内词(改首位即 0 命中)。
List<String> buildSyntheticWords(int count) {
  final out = <String>[];
  final seen = <String>{};
  for (var a = 0; a < 26 && out.length < count; a++) {
    for (var b = 0; b < 26 && out.length < count; b++) {
      for (var c = 0; c < 26 && out.length < count; c++) {
        for (var d = 0; d < 26 && out.length < count; d++) {
          final w = 'a${_l(a)}${_l(b)}${_l(c)}${_l(d)}';
          // 长度 5 且纯字母;isTestableWord 的屏蔽表全是真实语气词/缩略词,不会命中
          if (w.length >= 3 && seen.add(w)) out.add(w);
        }
      }
    }
  }
  if (out.length < count) {
    throw StateError('合成词表只生成了 ${out.length} 个词,需要 $count 个');
  }
  return out;
}

String _l(int i) => String.fromCharCode(97 + i);

/// 注入合成词表(名次 = 下标 + 1)。
void injectTable({int size = kTableSize}) {
  final words = buildSyntheticWords(size);
  // counts 单调递减(仅用于模拟"频次降序"的真实形状,估计器不读 counts)
  final counts = List<int>.generate(size, (i) => size - i);
  WordFrequency.debugInject(words: words, counts: counts);
}

/// "诚实作答"基准:真词全答认识,伪词全答认识(= 完全的虚假警报)。
bool _truthful(PlacementItem it) => !it.isPseudo;

/// 真词名次 ≤ [maxKnownRank] 答"认识",其余(含伪词)答"不认识"。
/// 模拟一个真实学习者:知道自己会到哪个名次为止,伪词一律不认识 → fa = 0。
bool _threshold(PlacementItem it, int maxKnownRank) =>
    !it.isPseudo && it.bandToRank <= maxKnownRank;

/// 按题目顺序作答(必须按 currentIndex 顺序调用 answer)。
void _answerAll(PlacementSession s, bool Function(PlacementItem) decide) {
  while (!s.isComplete) {
    final it = s.currentItem;
    if (it == null) break;
    s.answer(decide(it));
  }
}

void main() {
  group('档位定义', () {
    test('6 个档位连续覆盖 1..20000,无空洞无重叠', () {
      expect(kVocabBands.length, 6);
      expect(kVocabBands.first.fromRank, 1);
      expect(kVocabBands.last.toRank, kVocabCeiling);
      for (var i = 1; i < kVocabBands.length; i++) {
        expect(kVocabBands[i].fromRank, kVocabBands[i - 1].toRank + 1);
      }
      expect(
        kVocabBands.map((b) => b.size).toList(),
        <int>[1000, 1000, 1000, 2000, 5000, 10000],
      );
      expect(kVocabBands.first.label, '1-1000');
      expect(kVocabBands.last.label, '10001-20000');
    });
  });

  group('题目构建', () {
    setUp(() => injectTable());

    test('速测 = 72 真词 + 4 伪词 = 76 题;完整版 = 120 + 8 = 128 题', () {
      final fast = PlacementSession.fast();
      final full = PlacementSession.full();

      expect(fast.items.length, 76);
      expect(full.items.length, 128);

      final fastReal = fast.items.where((e) => !e.isPseudo).length;
      final fastPseudo = fast.items.where((e) => e.isPseudo).length;
      final fullReal = full.items.where((e) => !e.isPseudo).length;
      final fullPseudo = full.items.where((e) => e.isPseudo).length;

      expect(fastReal, 6 * kFastWordsPerBand); // 72
      expect(fullReal, 6 * kFullWordsPerBand); // 120
      // 伪词总数 = 请求值(必须精确,否则题数会漂)
      expect(fastPseudo, kFastPseudo); // 4
      expect(fullPseudo, kFullPseudo); // 8
      expect(fast.pseudoCount, fastPseudo);
      expect(full.pseudoCount, fullPseudo);
      // 总题数 = 真词 + 伪词(伪词不占档位名额)
      expect(fast.items.length, fastReal + fastPseudo);
      expect(full.items.length, fullReal + fullPseudo);

      // 每档真词数精确 = 12 / 20,伪词不占档位名额
      for (final band in kVocabBands) {
        expect(
          fast.items
              .where((e) => !e.isPseudo && e.bandFromRank == band.fromRank)
              .length,
          kFastWordsPerBand,
          reason: '速测 ${band.label} 档真词数',
        );
        expect(
          full.items
              .where((e) => !e.isPseudo && e.bandFromRank == band.fromRank)
              .length,
          kFullWordsPerBand,
          reason: '完整版 ${band.label} 档真词数',
        );
      }
    });

    test('真词名次落在所属档位区间内,伪词不属于任何档位', () {
      final s = PlacementSession.fast();
      final real = s.items.where((e) => !e.isPseudo).toList();
      expect(real.length, 72);
      for (final it in real) {
        expect(WordFrequency.rankOf(it.word), inInclusiveRange(it.bandFromRank, it.bandToRank));
        expect(it.bandToRank, greaterThan(it.bandFromRank));
        expect(it.bandFromRank, inInclusiveRange(1, kVocabCeiling));
      }
      final pseudo = s.items.where((e) => e.isPseudo).toList();
      expect(pseudo.length, 4);
      for (final it in pseudo) {
        // 伪词:名次 0(不在表里) + 空档位区间
        expect(WordFrequency.rankOf(it.word), 0);
        expect(it.bandToRank, lessThan(it.bandFromRank));
        expect(WordFrequency.isTestableWord(it.word), isTrue);
      }
      expect(pseudo.map((e) => e.word).toSet().length, pseudo.length, reason: '伪词不应重复');
    });

    test('伪词穿插:不在开头连出、不堆在结尾,位置符合分块公式', () {
      final s = PlacementSession.fast();
      final items = s.items;

      // 1) 结尾不是伪词(不是"全堆在最后")
      expect(items.last.isPseudo, isFalse, reason: '最后一题不应是伪词');
      // 2) 开头也不是伪词(不是"一上来就考你一个假词")
      expect(items.first.isPseudo, isFalse);

      // 3) 位置 = 每块内 `slot_j = floor(j*n/(k+1)) - 1`,块内伪词数 k_i 由
      //    `floor((i+1)*P/6) - floor(i*P/6)` 决定(P = 伪词总数)
      final pseudoTotal = s.pseudoCount;
      final perBandReal = kFastWordsPerBand;
      final blockPseudo = List<int>.generate(
        6,
        (i) => ((i + 1) * pseudoTotal / 6).floor() - (i * pseudoTotal / 6).floor(),
      );
      expect(blockPseudo.reduce((a, b) => a + b), pseudoTotal);
      expect(blockPseudo, <int>[0, 1, 1, 0, 1, 1],
          reason: '4 个伪词铺到 6 块 → 第 2/3/5/6 档各 1 个');

      final expected = <int>[];
      var base = 0;
      for (var b = 0; b < 6; b++) {
        final k = blockPseudo[b];
        for (var j = 0; j < k; j++) {
          var slot = ((j + 1) * perBandReal / (k + 1)).floor() - 1;
          if (slot < 0) slot = 0;
          if (slot >= perBandReal) slot = perBandReal - 1;
          expected.add(base + slot);
        }
        base += perBandReal + k;
      }
      final actual = <int>[];
      for (var i = 0; i < items.length; i++) {
        if (items[i].isPseudo) actual.add(i);
      }
      expect(actual, expected);
      expect(actual, <int>[17, 30, 55, 68], reason: '实测的伪词位置');

      // 4) 每个伪词都嵌在某一档的真词中间:它前面和后面都还有同档真词,
      //    所以用户不会看出"这一组像是插入的"
      for (final p in actual) {
        expect(p, greaterThan(0));
        expect(p, lessThan(items.length - 1));
        expect(items[p - 1].isPseudo, isFalse);
        expect(items[p + 1].isPseudo, isFalse);
      }
      // 5) 伪词不占档位名额:总题数 = 真词 + 伪词
      expect(items.length, 6 * perBandReal + pseudoTotal);
      expect(actual, hasLength(kFastPseudo));
    });

    test('相同 seed 两次构造完全一致;不同 seed 抽到的词不同', () {
      final a = PlacementSession.full(seed: 7);
      final b = PlacementSession.full(seed: 7);
      expect(b.items.length, a.items.length);
      for (var i = 0; i < a.items.length; i++) {
        expect(b.items[i].word, a.items[i].word, reason: '第 $i 题');
        expect(b.items[i].isPseudo, a.items[i].isPseudo, reason: '第 $i 题');
        expect(b.items[i].bandFromRank, a.items[i].bandFromRank);
        expect(b.items[i].bandToRank, a.items[i].bandToRank);
      }

      final c = PlacementSession.full(seed: 8);
      final wordsA = a.items.map((e) => e.word).toSet();
      final wordsC = c.items.map((e) => e.word).toSet();
      expect(wordsA.length, a.items.length, reason: '同一份卷子内不应出现重复词');
      expect(wordsC.intersection(wordsA).length, lessThan(a.items.length),
          reason: '不同 seed 应抽到不同的词');
    });

    test('词表为空时不抛异常,题目为空、结果为 0', () {
      WordFrequency.debugInject(words: const <String>[], counts: const <int>[]);
      final s = PlacementSession.fast();
      expect(s.items, isEmpty);
      expect(s.isComplete, isTrue);
      expect(s.currentItem, isNull);
      s.answer(true); // 不应抛
      s.skip();
      final r = s.buildResult();
      expect(r, isNotNull);
      expect(r!.estimate, 0);
      expect(r.answeredItems, 0);
    });
  });

  group('估计算法 — 校正', () {
    setUp(() => injectTable());

    test('伪词校正生效:全答"认识"时 fa=1 → estimate 不是 20000 而是 0', () {
      // 完整版(每档 20 真词)才够 6 档都问到:速测在 b1 全认识、fa=0 时会因
      // 提前终止(校正命中率 < 0.15 的判定)而截断,见下一个测试。
      final s = PlacementSession.full();
      _answerAll(s, (it) => true); // 真词、伪词全答"认识"
      final r = s.buildResult();
      expect(r, isNotNull);
      final result = r!;
      expect(result.falseAlarmRate, 1.0, reason: '${s.pseudoCount} 个伪词全答"认识"');
      expect(result.estimate, 0, reason: '校正 h\' = h - fa = 0,不做校正会是 20000');
      expect(result.low, 0);
      expect(result.high, 0);
      expect(result.cefr, 'A1');
      // 校正前的原始命中率仍是满分 —— 证明"扣分"确实来自伪词,而不是抽样偏差
      expect(result.bandHitRate.length, 6);
      expect(result.bandHitRate.values.every((h) => h == 1.0), isTrue);
    });

    test('部分虚报:真词全认识 + 一半伪词答"认识" → estimate = 10000', () {
      // 第一个伪词答"认识"(制造 fa = 1/8),其余伪词诚实答"不认识"
      final s = PlacementSession.full();
      var pseudoSeen = 0;
      _answerAll(s, (it) {
        if (!it.isPseudo) return true; // 真词一律"认识"
        pseudoSeen++;
        return pseudoSeen == 1;
      });
      final r = s.buildResult();
      expect(r, isNotNull);
      final result = r!;
      expect(pseudoSeen, 8, reason: '完整版 8 个伪词全走完');
      expect(result.falseAlarmRate, closeTo(1 / 8, 1e-9));
      expect(result.bandHitRate.values.every((h) => h == 1.0), isTrue);
      expect(result.earlyStopped, isFalse,
          reason: '原始命中率 1.0 ≥ 0.15:虚报不该让人被判定为"低水平"而截断');
      expect(result.bandHitRate.length, 6);
      expect(result.estimate, closeTo(20000 * (1 - 1 / 8), 5),
          reason: '每档 h=1、fa=0.125 → h\'=0.875 → 0.875×20000 = 17500');
      // 与"完全诚实"对照:fa=0 时应顶到上限
      final clean = PlacementSession.full();
      _answerAll(clean, (it) => !it.isPseudo);
      final cleanR = clean.buildResult();
      expect(cleanR, isNotNull);
      expect(cleanR!.falseAlarmRate, 0.0);
      expect(cleanR.estimate, kVocabCeiling);
      expect(result.estimate, lessThan(cleanR.estimate));
    });

    test('诚实作答(= 认识识别到上限)时 estimate 顶到 20000', () {
      final s = PlacementSession.full();
      _answerAll(s, (it) => !it.isPseudo); // 伪词诚实答"不认识" → fa = 0
      final r = s.buildResult();
      expect(r, isNotNull);
      final result = r!;
      expect(result.falseAlarmRate, 0.0);
      expect(result.earlyStopped, isFalse);
      expect(result.estimate, 20000);
      expect(result.cefr, 'C2');
      expect(result.low, inInclusiveRange(19000, 20000));
      expect(result.high, kVocabCeiling);
    });

    test('全答"不认识" → estimate = 0,区间 [0,0],CEFR A1', () {
      final s = PlacementSession.fast();
      _answerAll(s, (it) => false);
      final r = s.buildResult();
      expect(r, isNotNull);
      expect(r!.estimate, 0);
      expect(r.low, 0);
      expect(r.high, 0);
      expect(r.falseAlarmRate, 0.0);
      expect(r.cefr, 'A1');
      expect(r.bandHitRate.values.every((h) => h == 0.0), isTrue);
      // b1 整档全错(0/12 < 0.15)→ 提前终止,卷面被裁到 b1 块(12 个真词)
      expect(r.answeredItems, 12);
      expect(r.earlyStopped, isTrue);
      expect(r.lowConfidence, isTrue, reason: '只答了 12 题 < 20 → 区间退化为 ±50%');
    });

    test('真实模式(低档全认识、高档全不认识)→ estimate 落在正确档位', () {
      // ≤2000 名次:全认识;2001–3000 档:认识 8/12;>3000:全不认识;伪词:不认识(诚实)
      // 于是 b4 命中率 0 < 0.15 → 在 b4 答完时提前终止,estimate 由已答的档位求和。
      final s = PlacementSession.fast();
      // "认识 ≤2000,2001–3000 只认识一半,更高全不认识"这个学习者画像:
      // b3 档前 6 个真词答"认识"、后 6 个答"不认识" → 该档命中率恰好 0.5(稳定 ≥ 0.15)。
      var b3Seen = 0;
      _answerAll(s, (it) {
        if (it.isPseudo) return false; // 伪词诚实答"不认识" → fa = 0
        if (it.bandToRank <= 2000) return true;
        if (it.bandToRank <= 3000) return ++b3Seen <= 6;
        return false;
      });
      final r = s.buildResult();
      expect(r, isNotNull);
      final result = r!;
      expect(b3Seen, kFastWordsPerBand, reason: 'b3 的 12 个真词全答到了');
      expect(result.falseAlarmRate, 0.0, reason: '伪词一律答"不认识"');
      // b3 命中率 0.5 没触发截断;但 b4(3001-5000)命中率 0 → 答完 b4 就提前终止
      expect(result.earlyStopped, isTrue, reason: 'b4 整档 0 命中 < 0.15 → 跳过 b5/b6');
      expect(result.bandHitRate.length, 4, reason: 'b1..b4 答到了,b5/b6 被裁掉');
      expect(result.bandHitRate['1-1000'], 1.0);
      expect(result.bandHitRate['1001-2000'], 1.0);
      expect(result.bandHitRate['2001-3000'], 0.5);
      expect(result.bandHitRate['3001-5000'], 0.0);
      expect(result.bandHitRate.containsKey('5001-10000'), isFalse);
      expect(result.bandHitRate.containsKey('10001-20000'), isFalse);

      // 分层估计 = 1000 + 1000 + 0.5×1000 + 0×2000 = 2500
      expect(result.estimate, closeTo(2500, 1));
      expect(result.cefr, 'B1', reason: 'estimate ∈ [2000,3500) → B1');
      expect(result.lowConfidence, isFalse, reason: '答了 50 题,远超 20 题门槛');
      expect(result.low, lessThanOrEqualTo(result.estimate));
      expect(result.high, greaterThanOrEqualTo(result.estimate));
      // 全部方差只来自 b3:se = sqrt(0.5×0.5/12) × 1000 ≈ 144.3(有限总体校正后可忽略)
      final se = sqrt(0.5 * 0.5 / 12) * 1000;
      expect(result.low, closeTo(result.estimate - 1.96 * se, 2));
      expect(result.high, closeTo(result.estimate + 1.96 * se, 2));
      // b1/b2 命中率 1.0、b3 是 0.5(= 临界值,不算"掉档")、b4 是 0.0 → 掉档点是 b4
      expect(result.summaryLine, contains('3000'));
      expect(result.summaryLine, contains('3001'));
      expect(result.summaryLine, contains('开始吃力'));
    });

    test('低档掉档 → 提前终止与"剩余档位按 0 计入"是同一个假设', () {
      // 完全一样的学习者,只是把 b2 答成全不认识(而不是 8/12):
      // 若"b2 全不认识 ⇒ 更高档位也不会"成立,跳过它们不该改变 estimate 的量级方向。
      final s = PlacementSession.fast();
      var b1Seen = 0;
      while (!s.isComplete) {
        final it = s.currentItem;
        if (it == null) break;
        if (it.isPseudo) {
          s.answer(false);
        } else if (it.bandFromRank == 1) {
          b1Seen++;
          s.answer(true); // b1 全认识(命中率 1.0)
        } else {
          s.answer(false); // b2 及以后全不认识
        }
      }
      final r = s.buildResult();
      expect(r, isNotNull);
      final result = r!;
      expect(b1Seen, kFastWordsPerBand, reason: 'b1 的 12 个真词都答到了');
      expect(result.bandHitRate['1-1000'], 1.0);
      expect(result.bandHitRate['1001-2000'], 0.0);
      // b2 整档答完且校正命中率 0 < 0.15 → 触发提前终止,b3..b6 被裁掉、按 0 计入
      expect(result.earlyStopped, isTrue);
      expect(result.bandHitRate.length, 2, reason: '只答完 b1、b2 两档就停了');
      expect(result.estimate, 1000, reason: '1×1000 + 0×1000 + 0×1000 + 0 + 0 + 0');
      expect(s.earlyStopTriggered, isTrue);
      for (final it in s.items) {
        if (it.isPseudo) continue;
        expect(it.bandToRank, lessThanOrEqualTo(2000), reason: 'b3 及更高的题已被裁掉');
      }
    });
  });

  group('区间与提前终止', () {
    setUp(() => injectTable());

    test('low <= estimate <= high(多种作答模式)', () {
      final patterns = <String, bool Function(PlacementItem)>{
        '全认识真词': _truthful,
        '全不认识': (it) => false,
        '全认识': (it) => true,
        '只认识第一档': (it) => _threshold(it, 1000),
        '只认识前两档': (it) => _threshold(it, 2000),
        '一半真词': (it) => !it.isPseudo && WordFrequency.rankOf(it.word).isEven,
      };
      patterns.forEach((name, decide) {
        for (final full in <bool>[false, true]) {
          final s = full ? PlacementSession.full() : PlacementSession.fast();
          _answerAll(s, decide);
          final r = s.buildResult();
          expect(r, isNotNull, reason: '$name / full=$full');
          expect(r!.low, lessThanOrEqualTo(r.estimate), reason: '$name / full=$full');
          expect(r.high, greaterThanOrEqualTo(r.estimate), reason: '$name / full=$full');
          expect(r.estimate, inInclusiveRange(0, kVocabCeiling));
          expect(r.low, inInclusiveRange(0, kVocabCeiling));
          expect(r.high, inInclusiveRange(0, kVocabCeiling));
          expect(r.falseAlarmRate, inInclusiveRange(0.0, 1.0));
          expect(r.answeredItems, s.items.length);
        }
      });
    });

    test('答题 < 20 → 区间放宽到 ±50% 且 lowConfidence = true', () {
      final s = PlacementSession.full();
      // 答满 b1 的 10 个真词(命中 10/10),伪词即使出现也只占少数
      var realSeen = 0;
      while (realSeen < 10) {
        final it = s.currentItem;
        if (it == null) break;
        if (it.isPseudo) {
          s.answer(false);
          continue;
        }
        realSeen++;
        s.answer(true);
      }
      final r = s.buildResult();
      expect(r, isNotNull);
      // 11 题 < 20 → 走 ±50% 的保守区间
      expect(r!.answeredItems, 11, reason: '10 个真词 + 块内第 1 个伪词(答"不认识")');
      expect(r.lowConfidence, isTrue);
      expect(r.falseAlarmRate, 0.0);
      // 真词命中 10/10、fa=0 → estimate = 1×1000 = 1000(b1 全认识)
      expect(r.bandHitRate['1-1000'], 1.0);
      expect(r.estimate, 1000);
      expect(r.low, 500, reason: '±50% 的保守区间');
      expect(r.high, 1500);
      expect(r.low, lessThanOrEqualTo(r.estimate));
      expect(r.high, greaterThanOrEqualTo(r.estimate));
    });

    test('答题 ≥ 20 → lowConfidence = false,区间用二项近似的窄区间', () {
      final s = PlacementSession.full();
      var realSeen = 0;
      while (realSeen < 20) {
        final it = s.currentItem;
        expect(it, isNotNull);
        if (it!.isPseudo) {
          s.answer(false);
          continue;
        }
        realSeen++;
        s.answer(realSeen <= 18); // b1 档 18/20 认识,2 个不认识
      }
      final r = s.buildResult();
      expect(r, isNotNull);
      // 完整版 b1 块 = 20 真词 + 1 伪词(伪词排在块内第 15 位),所以答满 20 题时多答了 1 个伪词
      expect(r!.answeredItems, 21, reason: '20 个真词 + 落在这一段里的 1 个伪词');
      expect(r.lowConfidence, isFalse, reason: '≥20 题,不走 ±50% 的退路');
      expect(r.estimate, 900, reason: 'h=0.9 → 0.9×1000');
      // se = sqrt(0.9×0.1/20) = 0.0671 → ×1000 → ±1.96×67.1 ≈ ±131(±50% 退路会是 ±450)
      expect(r.low, inInclusiveRange(750, 880));
      expect(r.high, inInclusiveRange(950, 1100));
      expect(r.high - r.low, lessThan(400), reason: '20 题的区间应明显窄于 ±50%(±900)');
      expect(r.high - r.low, greaterThan(0));
    });

    test('低档全错 → 触发提前终止:更高档位不出现,earlyStopped = true', () {
      final s = PlacementSession.fast();
      _answerAll(s, (it) => false);
      expect(s.earlyStopTriggered, isTrue);
      final r = s.buildResult();
      expect(r, isNotNull);
      final result = r!;
      expect(result.earlyStopped, isTrue);
      expect(result.estimate, 0);
      expect(result.cefr, 'A1');
      expect(result.bandHitRate.length, 1, reason: '只答完第一档就停了');
      expect(result.bandHitRate.keys.first, '1-1000');

      // 停在第 1 档:卷面上不应再有名次 > 1000 的题
      for (final it in s.items) {
        if (it.isPseudo) continue;
        expect(it.bandToRank, lessThanOrEqualTo(1000));
      }
      // 已答题数 = 保留下来的题数(裁掉的题不计入,也不该被答到)
      expect(result.answeredItems, s.items.length);
      expect(result.answeredItems, 12 + s.pseudoCount,
          reason: '只答完 b1 的 12 个真词 + 落在 b1 段的伪词');
      expect(s.isComplete, isTrue);
      // 跳过的档位按 0 计入(所以 estimate=0 而不是"缺数据")
      expect(result.estimate, 0);
      // 提前终止也意味着区间退化为一条线(方差为 0)
      expect(result.low, 0);
      expect(result.high, 0);
    });

    test('低档勉强及格(命中率 < 0.15)→ 同样提前终止,不浪费高档题', () {
      final s = PlacementSession.fast();
      // b1 只认识 1/12 ≈ 0.083 < 0.15;伪词全不认识 → 校正不生效
      var seen = 0;
      while (!s.isComplete) {
        final it = s.currentItem;
        if (it == null) break;
        if (it.isPseudo) {
          s.answer(false);
          continue;
        }
        if (it.bandFromRank == 1) {
          seen++;
          s.answer(seen <= 1);
          continue;
        }
        s.answer(false); // 已经答到更高档(理论上不该发生)
      }
      final r = s.buildResult();
      expect(r, isNotNull);
      expect(r!.earlyStopped, isTrue);
      // 提前终止前的唯一数据:1/12 命中 → h' = 0.0833 → 0.0833×1000 ≈ 83;
      // 更高的 5 个档位被跳过 → 按 0 计入(所以不是"缺数据"而是"高概率不认识")
      expect(r.estimate, 83);
      expect(r.cefr, 'A1');
      expect(r.bandHitRate['1-1000'], closeTo(1 / 12, 1e-9));
      expect(s.earlyStopTriggered, isTrue);
      for (final it in s.items) {
        if (it.isPseudo) continue;
        expect(it.bandToRank, lessThanOrEqualTo(1000));
      }
    });

    test('命中率达标(≥0.15)不提前终止,六档都问到', () {
      final s = PlacementSession.fast();
      // 每档只答认识前 6 个真词(按出现顺序)→ 各档命中率恰好 0.5,稳定高于阈值 0.15
      final realByBand = <String, List<PlacementItem>>{};
      for (final it in s.items) {
        if (it.isPseudo) continue;
        realByBand
            .putIfAbsent('${it.bandFromRank}', () => <PlacementItem>[])
            .add(it);
      }
      final known = <String>{};
      for (final band in kVocabBands) {
        final words = realByBand['${band.fromRank}'] ?? const <PlacementItem>[];
        expect(words.length, kFastWordsPerBand, reason: '${band.label} 档真词数');
        for (final it in words.take(6)) {
          known.add(it.word);
        }
      }
      _answerAll(s, (it) => known.contains(it.word));

      final r = s.buildResult();
      expect(r, isNotNull);
      expect(r!.earlyStopped, isFalse, reason: '每档命中率 0.5 ≥ 0.15');
      expect(r.bandHitRate.length, 6, reason: '六档都答到了');
      for (final h in r.bandHitRate.values) {
        expect(h, 0.5);
      }
      expect(r.answeredItems, 76);
      expect(s.isComplete, isTrue);
      // 分层估计 = 0.5×20000 = 10000
      expect(r.estimate, closeTo(10000, 1));
      expect(r.falseAlarmRate, 0.0, reason: '伪词不在 known 集合里 → 诚实');
    });
  });

  group('skip 与未答完', () {
    setUp(() => injectTable());

    test('skip() 按"不认识"计入统计,同时单独计数', () {
      final s = PlacementSession.fast();
      for (var i = 0; i < 10; i++) {
        s.skip();
      }
      expect(s.skippedCount, 10);
      expect(s.answeredCount, 10);
      expect(s.currentIndex, 10);
      // 剩下的真词全答"认识",伪词答"不认识"
      _answerAll(s, (it) => !it.isPseudo);
      expect(s.skippedCount, 10);
      expect(s.isComplete, isTrue);

      final r = s.buildResult();
      expect(r, isNotNull);
      final result = r!;
      expect(result.skippedItems, 10);
      expect(result.answeredItems, 76);
      // 前 10 题里被跳过的真词算"不认识" → b1 命中率 < 1
      expect(result.bandHitRate['1-1000'], lessThan(1.0));
      expect(result.falseAlarmRate, 0.0, reason: '伪词全答"不认识"');
      expect(result.estimate, lessThan(20000));
      expect(result.estimate, greaterThan(0));
    });

    test('全部 skip → estimate 0,skipped 计数 = 实际作答的题数', () {
      final s = PlacementSession.fast();
      while (!s.isComplete) {
        s.skip();
      }
      final r = s.buildResult();
      expect(r, isNotNull);
      expect(r!.estimate, 0);
      // b1 全 skip(= 全不认识)→ 触发提前终止,后面的档位被裁掉
      expect(s.earlyStopTriggered, isTrue);
      expect(s.items.length, lessThan(76));
      expect(r.skippedItems, s.items.length);
      expect(r.answeredItems, s.items.length);
      // b1 块 = 12 个真词,块内没有伪词(速测的 4 个伪词在第 2/3/5/6 块)
      expect(s.items.length, 12);
      expect(r.falseAlarmRate, 0.0);
      expect(r.cefr, 'A1');
    });

    test('未答完可构建结果;一题没答也不抛(estimate 0,lowConfidence)', () {
      final s = PlacementSession.full();
      final empty = s.buildResult();
      expect(empty, isNotNull);
      expect(empty!.estimate, 0);
      expect(empty.answeredItems, 0);
      expect(empty.bandHitRate, isEmpty);
      expect(empty.lowConfidence, isTrue);
      expect(empty.cefr, 'A1');

      final s2 = PlacementSession.fast();
      for (var i = 0; i < 5; i++) {
        s2.answer(i.isEven);
      }
      final partial = s2.buildResult();
      expect(partial, isNotNull);
      expect(partial!.answeredItems, 5);
      expect(partial.lowConfidence, isTrue);
      expect(partial.estimate, inInclusiveRange(0, kVocabCeiling));
      expect(partial.low, lessThanOrEqualTo(partial.estimate));
      expect(partial.high, greaterThanOrEqualTo(partial.estimate));
      expect(partial.bandHitRate.length, 1, reason: '5 题都在 b1');
    });

    test('答完后再 answer/skip 是安全空操作', () {
      final s = PlacementSession.fast();
      _answerAll(s, (it) => !it.isPseudo);
      expect(s.answeredCount, 76);
      s.answer(true);
      s.answer(false);
      s.skip();
      expect(s.answeredCount, 76);
      expect(s.currentIndex, 76);
      expect(s.skippedCount, 0);
      expect(s.currentItem, isNull);
    });

    test('grammarScore / readingScore 注入后可读回', () {
      final s = PlacementSession.full();
      _answerAll(s, (it) => !it.isPseudo);
      final withScores = s.buildResult(grammarScore: 72, readingScore: 85);
      expect(withScores, isNotNull);
      expect(withScores!.grammarScore, 72);
      expect(withScores.readingScore, 85);
      final without = s.buildResult();
      expect(without, isNotNull);
      expect(without!.grammarScore, isNull);
      expect(without.readingScore, isNull);
      expect(without.toJson().containsKey('grammarScore'), isFalse);
      expect(withScores.toJson()['readingScore'], 85);
    });
  });

  group('CEFR 映射与 summaryLine', () {
    test('CEFR 边界值(999/1000/2000/3500/6000/10000)', () {
      expect(PlacementResult.cefrOf(0), 'A1');
      expect(PlacementResult.cefrOf(999), 'A1');
      expect(PlacementResult.cefrOf(1000), 'A2');
      expect(PlacementResult.cefrOf(1999), 'A2');
      expect(PlacementResult.cefrOf(2000), 'B1');
      expect(PlacementResult.cefrOf(3499), 'B1');
      expect(PlacementResult.cefrOf(3500), 'B2');
      expect(PlacementResult.cefrOf(5999), 'B2');
      expect(PlacementResult.cefrOf(6000), 'C1');
      expect(PlacementResult.cefrOf(10000), 'C1');
      expect(PlacementResult.cefrOf(10001), 'C2');
      expect(PlacementResult.cefrOf(kVocabCeiling), 'C2');
    });

    setUp(() => injectTable());

    test('summaryLine 指出"掉档"位置(实测)', () {
      // 只认识 ≤2000 → b3(2001-3000)命中率 0 → 分界点是 2000 / 2001
      final s = PlacementSession.fast();
      _answerAll(s, (it) => !it.isPseudo && it.bandToRank <= 2000);
      final r = s.buildResult();
      expect(r, isNotNull);
      final line = r!.summaryLine;
      expect(line, contains('2000'));
      expect(line, contains('2001'));
      expect(line, contains('开始吃力'));
      expect(line, isNotEmpty);

      // 只认识 ≤1000 → 分界点是 1000 / 1001
      final s2 = PlacementSession.fast();
      _answerAll(s2, (it) => !it.isPseudo && it.bandToRank <= 1000);
      final line2 = s2.buildResult()!.summaryLine;
      expect(line2, contains('1000'));
      expect(line2, contains('1001'));
    });

    test('summaryLine 在全认识 / 全不认识 / 空白三种极端下都不为空且不抛', () {
      final all = PlacementSession.fast();
      _answerAll(all, (it) => !it.isPseudo);
      final allLine = all.buildResult()!.summaryLine;
      expect(allLine, contains('基本认识'));
      expect(allLine.length, greaterThan(6));

      final none = PlacementSession.fast();
      _answerAll(none, (it) => false);
      final noneLine = none.buildResult()!.summaryLine;
      expect(noneLine, contains('基础'));

      final blank = PlacementSession.fast();
      final blankLine = blank.buildResult()!.summaryLine;
      expect(blankLine, contains('无法判断'));
    });

    test('toJson 关键字段齐全且类型正确', () {
      final s = PlacementSession.fast();
      _answerAll(s, (it) => !it.isPseudo);
      final r = s.buildResult(grammarScore: 60, readingScore: 70);
      expect(r, isNotNull);
      final json = r!.toJson();
      expect(json['estimate'], isA<int>());
      expect(json['low'], isA<int>());
      expect(json['high'], isA<int>());
      expect(json['cefr'], isA<String>());
      expect(json['falseAlarmRate'], isA<double>());
      expect(json['bandHitRate'], isA<Map<String, double>>());
      expect(json['answeredItems'], 76);
      expect(json['skippedItems'], 0);
      expect(json['earlyStopped'], isFalse);
      expect(json['grammarScore'], 60);
    });
  });

  group('数值自洽性(随机作答大量样本)', () {
    setUp(() => injectTable());

    test('20 组随机 seed × 随机作答:结果字段恒在合法范围内', () {
      for (var k = 0; k < 20; k++) {
        final rng = Random(k);
        final s = k.isEven ? PlacementSession.fast(seed: k) : PlacementSession.full(seed: k);
        while (!s.isComplete) {
          final it = s.currentItem;
          if (it == null) break;
          if (rng.nextInt(100) < 30) {
            s.skip();
          } else {
            s.answer(rng.nextBool());
          }
        }
        final r = s.buildResult();
        expect(r, isNotNull, reason: 'k=$k');
        expect(r!.estimate, inInclusiveRange(0, kVocabCeiling));
        expect(r.low, inInclusiveRange(0, kVocabCeiling));
        expect(r.high, inInclusiveRange(0, kVocabCeiling));
        expect(r.low, lessThanOrEqualTo(r.estimate));
        expect(r.high, greaterThanOrEqualTo(r.estimate));
        expect(r.falseAlarmRate, inInclusiveRange(0.0, 1.0));
        expect(r.answeredItems, s.items.length);
        expect(r.skippedItems, lessThanOrEqualTo(r.answeredItems));
        expect(<String>['A1', 'A2', 'B1', 'B2', 'C1', 'C2'], contains(r.cefr));
        for (final h in r.bandHitRate.values) {
          expect(h, inInclusiveRange(0.0, 1.0));
        }
        expect(r.summaryLine, isNotEmpty);
      }
    });
  });
}
