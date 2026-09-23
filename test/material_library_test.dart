import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/learner_context.dart';
import 'package:readflow/services/material_library.dart';
import 'package:readflow/services/word_frequency.dart';

/// 材料中心核心逻辑测试:难度分析 + i+1 排序 + 书架标签。
///
/// 这一层直接决定"今天给你读什么",所以断言必须压在**具体数值**上:
/// 覆盖率算错一点,推荐就会把过载材料推给用户。
void main() {
  /// 生成纯字母假词(名次 i → 词):
  /// 注意**不能用带数字的词**(如 w001)——难度引擎的分词器只认 `[A-Za-z]+`,
  /// 数字会被丢掉,于是 token 退化成单字母 'w' 再被丢弃 → 整篇文本变成 0 个词,
  /// 覆盖率变成"空文本兜底 1.0",测试会以假乱真。
  String fakeWord(int i) {
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    final a = letters[(i ~/ 676) % 26];
    final b = letters[(i ~/ 26) % 26];
    final c = letters[i % 26];
    return '$a$b$c';
  }

  setUp(() {
    // 400 个纯字母词:名次 = 下标+1,便于手算覆盖率
    final words = <String>[for (var i = 0; i < 380; i++) fakeWord(i)];
    // 再加一些真实词,让 tokenize/normalize 的正常路径也被覆盖(名次 381+)
    words.addAll([
      'the', 'of', 'and', 'to', 'a', 'in', 'is', 'it', 'you', 'that',
      'time', 'people', 'water', 'run', 'jump',
    ]);
    WordFrequency.debugInject(
      words: words,
      counts: List<int>.generate(words.length, (i) => 10000 - i),
    );
  });

  LearnerModel model({int vocab = 0, int? minutes}) => LearnerModel(
        vocabEstimate: vocab <= 0
            ? null
            : ProfileField<int>(value: vocab, source: ProfileSource.test),
        dailyMinutes: minutes == null
            ? null
            : ProfileField<int>(value: minutes, source: ProfileSource.self),
      );

  group('难度分析', () {
    test('全是已知词 → 覆盖率 100%、生词 0、判定偏易', () async {
      final text = List.filled(50, 'the time people water run').join(' ');
      final a = await MaterialLibrary.analyze(text, model: model(vocab: 400));
      expect(a.wordCount, 250);
      expect(a.newTypes, 0);
      expect(a.coverage, 1.0);
      expect(a.knownTokenRatio, 1.0);
      expect(a.tooEasy, isTrue);
      expect(a.comfortable, isFalse);
      expect(a.hint, contains('轻松'));
    });

    test('全是生词 → 覆盖率 0、判定偏难(且能列出最该学的词)', () async {
      final text = List.filled(30, 'zzqqxx wwppvv').join(' ');
      final a = await MaterialLibrary.analyze(text, model: model(vocab: 100));
      expect(a.wordCount, 60);
      expect(a.newTypes, 2);
      expect(a.coverage, 0.0);
      expect(a.knownTokenRatio, 0.0);
      expect(a.tooHard, isTrue);
      expect(a.hint, contains('偏难'));
      expect(a.topNewWords, containsAll(['zzqqxx', 'wwppvv']));
    });

    test('覆盖率落在舒适区(95-98%)时既不算难也不算易', () async {
      // 100 个词次里放 3 个生词 → 词次覆盖率 97%
      final known = List.filled(97, 'the').join(' ');
      final text = '$known zzqqxx wwppvv yyxxzz';
      final a = await MaterialLibrary.analyze(text, model: model(vocab: 400));
      expect(a.knownTokenRatio, closeTo(0.97, 0.001));
      expect(a.comfortable, isTrue);
      expect(a.tooHard, isFalse);
      expect(a.tooEasy, isFalse);
      expect(a.hint, contains('舒适'));
    });

    test('词汇量估计越高,同一篇文章覆盖率越高(分析确实用了基线)', () async {
      // 用名次 50/60/70/80 的假词:估计 40 时全不认识,估计 200 时全认识
      final text = List.filled(40, '${fakeWord(49)} ${fakeWord(59)} '
              '${fakeWord(69)} ${fakeWord(79)}')
          .join(' ');
      final low = await MaterialLibrary.analyze(text, model: model(vocab: 40));
      final high = await MaterialLibrary.analyze(text, model: model(vocab: 200));
      expect(low.knownTokenRatio, 0.0);
      expect(high.knownTokenRatio, 1.0);
    });

    test('预计阅读时长随文本长度增长,且至少 1 分钟', () async {
      final short = await MaterialLibrary.analyze('the of and', model: model(vocab: 400));
      expect(short.estMinutes, greaterThanOrEqualTo(1));
      final long = await MaterialLibrary.analyze(
        List.filled(1200, 'the of and to a in is it you that').join(' '),
        model: model(vocab: 400),
      );
      expect(long.estMinutes, greaterThan(short.estMinutes));
      expect(long.estMinutes, greaterThanOrEqualTo(10));
    });

    test('分析结果可 JSON 往返(入库后列表与阅读器都要读回它)', () async {
      final a = await MaterialLibrary.analyze(
        'the time people water run jump',
        model: model(vocab: 200),
      );
      final back = MaterialAnalysis.fromJson(a.toJson());
      expect(back.wordCount, a.wordCount);
      expect(back.coverage, closeTo(a.coverage, 1e-9));
      expect(back.knownTokenRatio, closeTo(a.knownTokenRatio, 1e-9));
      expect(back.cefr, a.cefr);
      expect(back.topNewWords, a.topNewWords);
    });

    test('坏 JSON 不崩:缺字段/类型错都给安全默认值', () {
      final back = MaterialAnalysis.fromJson({
        'word_count': '120',
        'coverage': 'abc',
        'cefr': 7,
        'top_new_words': 'not-a-list',
      });
      expect(back.wordCount, 120);
      expect(back.coverage, 0);
      expect(back.cefr, '7');
      expect(back.topNewWords, isEmpty);
    });
  });

  group('书架排序(rankForToday)', () {
    ShelfItem item({
      required int id,
      double? coverage,
      double percent = 0,
      bool finished = false,
    }) =>
        ShelfItem(
          id: id,
          title: 'M$id',
          kind: 'news',
          source: 'npr',
          cefr: 'B1',
          wordCount: 500,
          coverage: coverage,
          estMinutes: 5,
          percent: percent,
          minutesRead: 0,
          pickedWords: 0,
          url: 'https://x/$id',
          finished: finished,
        );

    test('未读完的舒适区材料排最前,过载的排最后', () {
      final ranked = MaterialLibrary.rankForToday([
        item(id: 1, coverage: 0.96), // 舒适区未开始
        item(id: 2, coverage: 0.96, percent: 40), // 舒适区在读
        item(id: 3, coverage: 0.85), // 过载
        item(id: 4, coverage: 0.995), // 偏易
        item(id: 5, coverage: 0.96, percent: 100, finished: true), // 已读完
      ]);
      expect(ranked.first.id, 2);
      expect(ranked.first.progressLabel, '已读 40%');
      // 排序意图:过载材料**最末**(推读不懂的材料是最差的结果),
      // 已读完的其次(不推荐,但至少不会白费力气)
      expect(ranked.last.id, 3);
      expect(ranked[ranked.length - 2].id, 5);
      expect(ranked[ranked.length - 2].progressLabel, '已读完');
    });

    test('过载材料即使未读也排在偏易之后(避免推荐读不懂的)', () {
      final ranked = MaterialLibrary.rankForToday([
        item(id: 1, coverage: 0.80),
        item(id: 2, coverage: 0.995),
      ]);
      expect(ranked.first.id, 2);
    });

    test('没有覆盖率数据时也能排序(不抛异常,按 id 倒序兜底)', () {
      final ranked = MaterialLibrary.rankForToday([
        item(id: 1),
        item(id: 3),
      ]);
      expect(ranked.map((e) => e.id).toList(), [3, 1]);
    });
  });

  group('阈值单一事实源', () {
    test('材料库的判定与 LearnerContext 阈值一致(不各写一份)', () {
      expect(LearnerContext.tooHardTokenRatio, 0.90);
      expect(LearnerContext.comfortableMin, 0.95);
      expect(LearnerContext.comfortableMax, 0.98);
      expect(LearnerContext.tooEasyTokenRatio, 0.99);
      expect(LearnerContext.isComfortable(0.96), isTrue);
      expect(LearnerContext.difficultyHint(0.85), contains('偏难'));
    });

    test('材料种类中文名齐全', () {
      expect(MaterialLibrary.kindLabel('news'), '外刊/新闻');
      expect(MaterialLibrary.kindLabel('book'), '原版书');
      expect(MaterialLibrary.kindLabel('podcast'), '播客/听力');
      expect(MaterialLibrary.kindLabel('wiki'), '百科');
      expect(MaterialLibrary.kindLabel('paper'), '论文');
      expect(MaterialLibrary.kindLabel('whatever'), '文章');
    });
  });
}
