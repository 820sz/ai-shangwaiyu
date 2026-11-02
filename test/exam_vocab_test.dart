import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/exam_vocab.dart';

/// 批 7 · P1-3 考纲词表与「距目标还差多少词」回归。
///
/// 守三件事:
/// 1. **资产是真的**:`assets/data/exam_vocab.json` ≥400 条、五类考试都有词、
///    字段非空、按 rank 升序(用户能看到的每个词都有中文,不拿占位糊弄);
/// 2. **口径不撒谎**:没有目标 / 没有词汇量基线 → null;多目标取最小目标规模;
///    已达标给 0 而不是负数;
/// 3. **容错**:坏 JSON / 单条坏数据不能把整页助理拖垮(降级为空表)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseExamVocab 容错', () {
    test('标准 {"meta","words"} 形状:解析、按 rank 升序、字段完整', () {
      final raw = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'count': 3},
        'words': <Object?>[
          <String, Object?>{
            'word': 'Beta',
            'zh': '乙',
            'pos': 'n.',
            'exams': <String>['cet4'],
            'rank': 20,
          },
          <String, Object?>{
            'word': 'alpha',
            'zh': '甲',
            'pos': 'n.',
            'exams': <String>['cet4', 'cet6'],
            'rank': 10,
          },
          <String, Object?>{
            'word': 'gamma',
            'zh': '丙',
            'pos': 'adj.',
            'exams': <String>['toefl'],
            'rank': 30,
          },
        ],
      });
      final words = parseExamVocab(raw);
      expect(words.map((w) => w.word), <String>[
        'alpha',
        'beta',
        'gamma',
      ], reason: '一律小写 + 按 rank 升序');
      expect(words.first.exams, containsAll(<String>['cet4', 'cet6']));
    });

    test('裸数组也认(未来换数据源不炸)', () {
      final words = parseExamVocab(
        jsonEncode(<Object?>[
          <String, Object?>{
            'word': 'only',
            'zh': '只',
            'pos': 'adj.',
            'exams': <String>['ielts'],
            'rank': 1,
          },
        ]),
      );
      expect(words, hasLength(1));
      expect(words.single.word, 'only');
    });

    test('重复词去重:大小写不敏感,保留 rank 更靠前的一条', () {
      final words = parseExamVocab(
        jsonEncode(<Object?>[
          <String, Object?>{
            'word': 'Beta',
            'zh': '晚',
            'pos': 'n.',
            'exams': <String>['cet4'],
            'rank': 99,
          },
          <String, Object?>{
            'word': 'beta',
            'zh': '早',
            'pos': 'n.',
            'exams': <String>['cet4'],
            'rank': 5,
          },
        ]),
      );
      expect(words, hasLength(1));
      expect(words.single.rank, 5);
      expect(words.single.zh, '早');
    });

    test('坏数据跳过:rank 非法 / word 空 / 非 Map / 未知考试标签被过滤', () {
      final words = parseExamVocab(
        jsonEncode(<Object?>[
          <String, Object?>{
            'word': 'good',
            'zh': '好',
            'pos': 'adj.',
            'exams': <String>['cet4'],
            'rank': 1,
          },
          <String, Object?>{'word': 'bad-rank', 'zh': 'x', 'rank': 'abc'},
          <String, Object?>{'rank': 2},
          'oops',
          <String, Object?>{
            'word': 'mixed',
            'zh': '混',
            'pos': 'n.',
            'exams': <String>['nope', 'CET4'],
            'rank': 3,
          },
        ]),
      );
      expect(words.map((w) => w.word), <String>[
        'good',
        'mixed',
      ], reason: 'rank 非法/缺 word 的条目以及非 Map 值都应被丢弃');
      expect(words.last.exams, <String>['cet4'], reason: '未知考试 id 过滤、大小写归一');
    });

    test('坏 JSON → 空表且不抛(资产损坏时助理页仍能打开)', () {
      expect(parseExamVocab('{not json'), isEmpty);
      expect(parseExamVocab('[]'), isEmpty);
      expect(parseExamVocab('{"meta":{}}'), isEmpty);
    });
  });

  group('wordsFor / wordsForGoals', () {
    setUp(() {
      ExamVocab.seedForTest(<ExamWord>[
        const ExamWord(
          word: 'core',
          zh: '核心',
          pos: 'n.',
          exams: <String>['cet4', 'cet6'],
          rank: 10,
        ),
        const ExamWord(
          word: 'four',
          zh: '四',
          pos: 'n.',
          exams: <String>['cet4'],
          rank: 30,
        ),
        const ExamWord(
          word: 'six',
          zh: '六',
          pos: 'n.',
          exams: <String>['cet6'],
          rank: 20,
        ),
        const ExamWord(
          word: 'abroad',
          zh: '海外',
          pos: 'adv.',
          exams: <String>['ielts', 'toefl'],
          rank: 15,
        ),
        const ExamWord(
          word: 'rare',
          zh: '罕见',
          pos: 'adj.',
          exams: <String>['toefl'],
          rank: 40,
        ),
      ]);
    });

    tearDown(() => ExamVocab.seedForTest(null));

    test('wordsFor:按考试过滤、rank 升序、limit 生效、未知考试空表', () {
      expect(ExamVocab.wordsFor('cet4').map((w) => w.word), <String>[
        'core',
        'four',
      ]);
      expect(
        ExamVocab.wordsFor('CET4', limit: 1).single.word,
        'core',
        reason: 'exam id 大小写不敏感',
      );
      expect(
        ExamVocab.wordsFor('cet4', limit: 99),
        hasLength(2),
        reason: 'limit 超过总数时给全部',
      );
      expect(ExamVocab.wordsFor('nope'), isEmpty);
      expect(ExamVocab.wordsFor('ielts').map((w) => w.word), <String>[
        'abroad',
      ]);
    });

    test('wordsForGoals:多选目标合并去重、按 rank 升序;兴趣类目标 → 空', () {
      expect(
        ExamVocab.wordsForGoals(<String>['四六级']).map((w) => w.word),
        <String>['core', 'four'],
        reason: '「四六级」泛化识别为 cet4(区分不了四/六时按四级算)',
      );
      expect(
        ExamVocab.wordsForGoals(<String>['四六级', '雅思/托福']).map((w) => w.word),
        <String>['core', 'abroad', 'four'],
        reason: 'cet4 ∪ ielts,按 rank 升序;core 在两边都有只出现一次',
      );
      expect(ExamVocab.wordsForGoals(<String>['兴趣阅读']), isEmpty);
      expect(ExamVocab.wordsForGoals(const <String>[]), isEmpty);
    });
  });

  group('goalWordsGap 口径(绝不编数字)', () {
    test('无目标 / 无词汇量基线 → null', () {
      expect(ExamVocab.goalWordsGap(const <String>[], 2000), isNull);
      expect(ExamVocab.goalWordsGap(<String>['四六级'], null), isNull);
      expect(
        ExamVocab.goalWordsGap(<String>['四六级'], 0),
        isNull,
        reason: '词汇量 0 不是有效基线',
      );
      expect(
        ExamVocab.goalWordsGap(<String>['兴趣阅读'], 2000),
        isNull,
        reason: '兴趣类目标没有词表规模,不能硬套',
      );
    });

    test('单目标:目标规模 - 当前词汇量', () {
      expect(
        ExamVocab.goalWordsGap(<String>['四六级'], 3000),
        1500,
        reason: 'cet4≈4500',
      );
      expect(
        ExamVocab.goalWordsGap(<String>['六级'], 3000),
        3000,
        reason: 'cet6≈6000',
      );
      expect(
        ExamVocab.goalWordsGap(<String>['考研'], 5000),
        500,
        reason: 'kaoyan≈5500',
      );
      expect(
        ExamVocab.goalWordsGap(<String>['雅思/托福'], 6500),
        500,
        reason: '雅思≈7000(雅思/托福合并档按雅思算)',
      );
      expect(
        ExamVocab.goalWordsGap(<String>['托福'], 6500),
        1500,
        reason: '托福≈8000',
      );
    });

    test('多目标取最小 target,避免拿最高目标把差距放大', () {
      // cet4 4500 与 ielts 7000 同时选:按 4500 算,不是 7000
      expect(ExamVocab.goalWordsGap(<String>['四六级', '雅思'], 4000), 500);
    });

    test('已达标 → 0(不是负数)', () {
      expect(ExamVocab.goalWordsGap(<String>['四六级'], 5000), 0);
      expect(ExamVocab.goalWordsGap(<String>['四六级'], 99999), 0);
    });

    test('目标里同时有考试与非考试:只取考试目标', () {
      expect(ExamVocab.goalWordsGap(<String>['兴趣阅读', '考研'], 5000), 500);
    });
  });

  group('primaryExam 识别(与 output_source.targetExamOf 对齐)', () {
    test('中文/英文/泛化目标都认', () {
      expect(ExamVocab.primaryExam(<String>['四六级']), 'cet4');
      expect(ExamVocab.primaryExam(<String>['六级']), 'cet6');
      expect(ExamVocab.primaryExam(<String>['考研']), 'kaoyan');
      expect(ExamVocab.primaryExam(<String>['雅思/托福']), 'ielts');
      expect(ExamVocab.primaryExam(<String>['TOEFL']), 'toefl');
      expect(
        ExamVocab.primaryExam(<String>['CET6', 'IELTS']),
        'cet6',
        reason: '明确目标按出现顺序,先命中的算主目标',
      );
    });

    test('识别不出 / 只认出新概念 / 空目标 → null(不硬猜)', () {
      expect(ExamVocab.primaryExam(const <String>[]), isNull);
      expect(ExamVocab.primaryExam(<String>['兴趣阅读', '看剧看视频']), isNull);
      expect(
        ExamVocab.primaryExam(<String>['新概念']),
        isNull,
        reason: '新概念不在本词表五类内',
      );
    });

    test('明确目标压过泛化:四六级+雅思 → ielts', () {
      expect(ExamVocab.primaryExam(<String>['四六级', '雅思']), 'ielts');
    });
  });

  group('真实资产 assets/data/exam_vocab.json', () {
    final file = File('assets/data/exam_vocab.json');
    final words = file.existsSync()
        ? parseExamVocab(file.readAsStringSync())
        : const <ExamWord>[];

    test('资产存在且 ≥400 条', () {
      expect(file.existsSync(), isTrue, reason: '考纲词表资产缺失');
      expect(words.length, greaterThanOrEqualTo(400));
    });

    test('五类考试都有词(每类 ≥40 条)', () {
      for (final exam in ExamVocab.examIds) {
        final count = words.where((w) => w.exams.contains(exam)).length;
        expect(
          count,
          greaterThanOrEqualTo(40),
          reason: '${ExamVocab.examLabels[exam] ?? exam} 词太少,按目标挑词会空',
        );
      }
    });

    test('每条字段非空、rank 为正且全局升序、exams 都是合法 id', () {
      for (final w in words) {
        expect(w.word, isNotEmpty);
        expect(w.zh, isNotEmpty, reason: '用户看到的每个词都必须有中文释义');
        expect(w.pos, isNotEmpty);
        expect(w.rank, greaterThan(0));
        expect(w.exams, isNotEmpty, reason: '${w.word} 至少要属于一个考试');
        for (final exam in w.exams) {
          expect(ExamVocab.examIds, contains(exam));
        }
      }
      for (var i = 1; i < words.length; i++) {
        expect(
          words[i].rank,
          greaterThanOrEqualTo(words[i - 1].rank),
          reason: '词表必须按 rank 升序(挑词按顺序取高频)',
        );
      }
    });

    test('ensureLoaded 走 rootBundle 能加载同一份资产', () async {
      ExamVocab.seedForTest(null); // 先清缓存,真的走一遍资产加载
      await ExamVocab.ensureLoaded();
      expect(ExamVocab.isLoaded, isTrue);
      expect(ExamVocab.all.length, greaterThanOrEqualTo(400));
      expect(ExamVocab.wordsFor('cet4').length, greaterThanOrEqualTo(40));
      expect(ExamVocab.wordsForGoals(<String>['四六级']).isNotEmpty, isTrue);
    });
  });
}
