import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/output_source.dart';

/// 批 3(P1 语境化素材来源)的回归测试。
///
/// 这里只测**纯函数**(不连 DB、不联网):分句、挑回译句、挑摘要段、
/// 挑写作用词、挑薄弱语法点、识别考试类型、来源描述。
/// 只读查询 `OutputSourceService.recentMaterials/activeErrorTags` 依赖真库,
/// 按任务约定不做真库测试(避免 flaky),留给真机/集成测试。
void main() {
  group('splitSentences:基础分句', () {
    test('空串 / 纯空白 → 空列表', () {
      expect(splitSentences(''), isEmpty);
      expect(splitSentences('   \n\n  '), isEmpty);
    });

    test('英文句号/感叹号/问号都断句', () {
      final s = splitSentences('Hello world. This is a test! Really?');
      expect(s, ['Hello world.', 'This is a test!', 'Really?']);
    });

    test('中文句末标点断句(中文不写空格也断)', () {
      final s = splitSentences('这是第一句。这是第二句！第三句？');
      expect(s, ['这是第一句。', '这是第二句！', '第三句？']);
    });

    test('中英混排:英文句点也断,中文内容照原样保留', () {
      final s = splitSentences('I love 中文. Me too.');
      expect(s.length, 2);
      expect(s.first, contains('中文'));
    });
  });

  group('splitSentences:缩写 / 小数 / URL 不误切', () {
    test('Mr. / Dr. 缩写后不断句', () {
      final s = splitSentences(
        'Mr. Smith went to Washington. Dr. Lee stayed home.',
      );
      expect(s.length, 2);
      expect(s.first.startsWith('Mr. Smith'), isTrue);
      expect(s.last.startsWith('Dr. Lee'), isTrue);
    });

    test('e.g. / i.e. 不误切', () {
      final s = splitSentences(
        'Some fruits, e.g. apples and pears, are cheap. Others are not.',
      );
      expect(s.length, 2);
      expect(s.first, contains('e.g. apples'));
    });

    test('小数点不切(3.14)', () {
      final s = splitSentences('The price is 3.14 dollars. That is cheap.');
      expect(s.length, 2);
      expect(s.first, contains('3.14 dollars'));
    });

    test('URL 里的点与问号不切', () {
      final s = splitSentences(
        'Visit https://example.com/a.b?x=1 now. It works.',
      );
      expect(s.length, 2);
      expect(s.first, contains('https://example.com/a.b?x=1'));
    });

    test('省略号不切(等真正的句末标点)', () {
      final s = splitSentences('Wait... what happened? Nothing.');
      expect(s.length, 2);
      expect(s.first, 'Wait... what happened?');
    });

    test('收尾引号吸附到当前句,不单独成句', () {
      final s = splitSentences('He said "Stop!" Then left.');
      expect(s.length, 2);
      expect(s.first, 'He said "Stop!"');
    });
  });

  group('splitSentences:换行(软硬边界)', () {
    test('下一行大写开头 → 硬断句', () {
      final s = splitSentences('Hello world\nThis is a test.');
      expect(s, ['Hello world', 'This is a test.']);
    });

    test('下一行小写开头 → 视为折行,粘成一句(真实材料常按列硬折行)', () {
      final s = splitSentences(
        'the quick brown fox\njumps over the lazy dog. Done.',
      );
      expect(s.length, 2);
      expect(s.first, 'the quick brown fox jumps over the lazy dog.');
    });

    test('空行必然是段落/句子边界', () {
      final s = splitSentences('First paragraph line.\n\nSecond paragraph.');
      expect(s.length, 2);
    });
  });

  group('pickBackTranslationSentences', () {
    const text = 'Simple words only. '
        'Learning a new language requires patience and consistent daily practice. '
        'This is too short. '
        'Reading widely exposes learners to varied sentence structures and '
        'vocabulary that textbooks rarely cover. '
        'Learning a new language requires patience and consistent daily practice. ';

    test('长度过滤 + 保持原文顺序 + 去重', () {
      final picked = pickBackTranslationSentences(text, count: 2);
      expect(picked.length, 2);
      expect(picked.first, contains('Learning a new language'));
      expect(picked.last, contains('Reading widely exposes'));
      // 重复句只出一次
      expect(
        picked.where((s) => s.contains('Learning a new language')).length,
        1,
      );
    });

    test('从句/连接词开头、小写开头的残句不选', () {
      const fragmentText = 'Because he was late and the traffic was terrible. '
          'She finished the report before the deadline.';
      final picked = pickBackTranslationSentences(fragmentText, count: 3);
      expect(picked.any((s) => s.contains('Because')), isFalse);
      expect(picked.any((s) => s.contains('She finished')), isTrue);
    });

    test('数量不足时放宽:长句上限翻倍,且结果仍按原文顺序', () {
      const relaxText = 'The plan was simple and very clear. '
          'Regular writing practice makes it easier for every learner to improve.';
      // 第一句 7 词 < 8,默认第一轮选不到;第二句 11 词能选到
      final picked = pickBackTranslationSentences(relaxText, count: 2);
      expect(picked.length, 2, reason: '放宽后应把 7 词那句也捞回来');
      expect(picked.first.startsWith('The plan'), isTrue,
          reason: '按原文顺序,较短但在前的那句排第一');
    });

    test('超长句第一轮不选、放宽后允许到 2 倍上限', () {
      final longSentence =
          'This sentence is ${List.filled(35, 'word').join(' ')}.';
      final picked =
          pickBackTranslationSentences(longSentence, count: 1, maxWords: 32);
      expect(picked.length, 1, reason: '38 词在放宽上限 64 内应被选中');
    });

    test('count=0 / 空文本 → 空列表(不编句子)', () {
      expect(pickBackTranslationSentences('', count: 3), isEmpty);
      expect(pickBackTranslationSentences(text, count: 0), isEmpty);
    });
  });

  group('pickSummaryParagraphs', () {
    const article = '''
The Great Gatsby

This is a short intro.

Reading widely exposes learners to varied sentence structures and vocabulary that textbooks rarely cover, and it also builds the background knowledge that makes advanced texts easier to understand over time.

Chapter 2

Another paragraph that is long enough to be useful for summarization practice because it contains several connected ideas and enough context for a learner to reconstruct the main point in their own words.
''';

    test('跳过标题/过短段,保留长正文段', () {
      final paragraphs = pickSummaryParagraphs(article);
      expect(paragraphs.length, 2);
      expect(paragraphs.first.startsWith('Reading widely'), isTrue);
      expect(paragraphs.last.startsWith('Another paragraph'), isTrue);
      expect(paragraphs.any((p) => p.contains('Great Gatsby')), isFalse);
      expect(paragraphs.any((p) => p.contains('Chapter 2')), isFalse);
      expect(paragraphs.any((p) => p.contains('short intro')), isFalse);
    });

    test('总字数受控:第一段超长时在句子/空格边界截断并加省略号', () {
      final paragraphs = pickSummaryParagraphs(article, maxChars: 120);
      expect(paragraphs.length, 1);
      expect(paragraphs.first.length, lessThanOrEqualTo(121));
      expect(paragraphs.first.endsWith('…'), isTrue);
      // 截断必须落在原文已有的内容边界上(不能把单词切成"vocabular"这种半截)
      final head = paragraphs.first.substring(0, paragraphs.first.length - 1);
      expect(article.contains(head), isTrue);
    });

    test('空文本 / maxChars<=0 → 空列表', () {
      expect(pickSummaryParagraphs('', maxChars: 100), isEmpty);
      expect(pickSummaryParagraphs(article, maxChars: 0), isEmpty);
    });
  });

  group('pickWritingVocab', () {
    final vocab = <Vocabulary>[
      Vocabulary(word: 'abandon', translation: '放弃', masteryLevel: 0),
      Vocabulary(word: 'implement', translation: '实施', masteryLevel: 0),
      Vocabulary(
        word: 'sustainability',
        translation: '可持续性',
        masteryLevel: 2,
      ),
      Vocabulary(
        word: 'look up',
        wordType: 'phrase',
        translation: '查阅',
        masteryLevel: 0,
      ),
      Vocabulary(word: 'a', translation: '一个'),
      Vocabulary(word: 'London', translation: '伦敦'),
      Vocabulary(word: 'mystery', translation: ''),
      Vocabulary(word: 'Abandon', translation: '放弃的重复'),
    ];

    test('过滤超短/专有名词/无释义/重复;未掌握优先;单词排在短语之前', () {
      final words = pickWritingVocab(vocab, count: 4);
      expect(words, ['implement', 'abandon', 'sustainability', 'look up']);
    });

    test('只取 2 个时不会把短语塞进来(单词够用)', () {
      final words = pickWritingVocab(vocab, count: 2);
      expect(words, ['implement', 'abandon']);
    });

    test('空生词本 / count=0 → 空列表', () {
      expect(pickWritingVocab(const <Vocabulary>[], count: 5), isEmpty);
      expect(pickWritingVocab(vocab, count: 0), isEmpty);
    });
  });

  group('weakGrammarPoints', () {
    final rows = <Map<String, Object?>>[
      {'tag': '时态', 'count': 8, 'status': 'active', 'last_at': '2026-10-01T10:00:00'},
      {'tag': '冠词', 'count': 5, 'status': 'active', 'last_at': '2026-10-20T10:00:00'},
      // 同一 tag 来自另一个来源:合并计次(2+8=10)
      {'tag': '时态', 'count': 2, 'status': 'active', 'last_at': '2026-10-25T10:00:00'},
      {'tag': '已修好', 'count': 99, 'status': 'fixed'},
      {'tag': '', 'count': 3, 'status': 'active'},
    ];

    test('合并同 tag、排除 fixed/空 tag、按次数降序', () {
      expect(weakGrammarPoints(rows), ['时态', '冠词']);
    });

    test('limit 生效', () {
      expect(weakGrammarPoints(rows, limit: 1), ['时态']);
    });

    test('次数相同看最近一次更近的', () {
      final tie = <Map<String, Object?>>[
        {'tag': '介词', 'count': 2, 'status': 'active', 'last_at': '2026-09-01T00:00:00'},
        {'tag': '搭配', 'count': 2, 'status': 'active', 'last_at': '2026-10-01T00:00:00'},
      ];
      expect(weakGrammarPoints(tie).first, '搭配');
    });

    test('空输入 / limit=0 → 空列表', () {
      expect(weakGrammarPoints(const []), isEmpty);
      expect(weakGrammarPoints(rows, limit: 0), isEmpty);
    });
  });

  group('targetExamOf:多选目标 → 统一考试类型', () {
    test('中英文写法都认', () {
      expect(targetExamOf(['CET-4']), 'cet4');
      expect(targetExamOf(['CET6']), 'cet6');
      expect(targetExamOf(['考研']), 'kaoyan');
      expect(targetExamOf(['IELTS']), 'ielts');
      expect(targetExamOf(['TOEFL']), 'toefl');
      expect(targetExamOf(['新概念英语']), 'nce');
    });

    test('中文目标(含期限复合串)也能认', () {
      expect(targetExamOf(['雅思(3 个月内)']), 'ielts');
      expect(targetExamOf(['六级']), 'cet6');
      expect(targetExamOf(['四级']), 'cet4');
    });

    test('"四六级"区分不了级数:作为兜底给 cet4', () {
      expect(targetExamOf(['四六级']), 'cet4');
      expect(targetExamOf(['四六级(半年内)']), 'cet4');
    });

    test('同批有更具体目标时以具体目标为准(泛化不压过明确)', () {
      expect(targetExamOf(['四六级', '雅思']), 'ielts');
      expect(targetExamOf(['四六级', '考研']), 'kaoyan');
    });

    test('识别不出 / 空 → null(不猜)', () {
      expect(targetExamOf(const []), isNull);
      expect(targetExamOf(['兴趣阅读', '看剧看视频']), isNull);
      expect(targetExamOf(['']), isNull);
    });
  });

  group('describeSources / OutputSourceMaterial', () {
    OutputSourceMaterial material({
      String title = '人类简史',
      String cefr = 'B2',
      double? coverage = 0.96,
    }) =>
        OutputSourceMaterial(
          materialId: 1,
          title: title,
          text: 'Some article body long enough to be used.',
          cefr: cefr,
          coverage: coverage,
          kind: 'book',
        );

    test('有难度与覆盖率时:书名 · CEFR · 覆盖率', () {
      expect(
        describeSources(material()),
        '《人类简史》 · B2 · 覆盖率 96%',
      );
    });

    test('缺难度/覆盖率时不留空槽', () {
      expect(
        describeSources(material(cefr: '', coverage: null)),
        '《人类简史》',
      );
      expect(
        describeSources(material(cefr: '  ', coverage: 0.999)),
        '《人类简史》 · 覆盖率 100%',
      );
    });

    test('空标题有兜底;NaN 覆盖率不显示', () {
      expect(describeSources(material(title: '')), '《未命名材料》 · B2 · 覆盖率 96%');
      expect(
        describeSources(material(coverage: double.nan)),
        '《人类简史》 · B2',
      );
    });

    test('hasText 判空(空白正文不能被当成可用素材)', () {
      const empty = OutputSourceMaterial(
        materialId: 2,
        title: 'x',
        text: '   ',
        cefr: '',
        coverage: null,
        kind: 'article',
      );
      expect(empty.hasText, isFalse);
      expect(material().hasText, isTrue);
    });
  });
}
