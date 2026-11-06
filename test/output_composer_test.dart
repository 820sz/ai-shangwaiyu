import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/output_composer.dart';
import 'package:readflow/services/output_rubric.dart';

/// 输出模块 · 出题层测试(批 3 · P1)。
///
/// 覆盖用户点名的两条:
/// 1. **禁止编造题源**:四条提示词都必须带这条硬约束;真题解析没有来源 URL
///    就生成空列表(宁可不练,不能背假题);
/// 2. 解析全容错(围栏/夹带说明/坏 JSON/少题/无参考),失败返回空列表/null。
///
/// 不联网:提示词与解析全是纯函数;compose/score 的联网方法不在本文件调用
/// (它们依赖注入的 [DeepseekApiService],由 UI 层集成时验证)。
void main() {
  // ── 夹具:模型返回的合规出题 JSON ───────────────────────────────────
  const backTranslationJson = '''
{"tasks":[
  {"prompt_zh":"首先,在线课程节省时间。","reference":"First, online courses save time.",
   "hint":"first 引导的列举结构","grammar_points":["一般现在时"]},
  {"prompt_zh":"其次,学生可以在任何地方学习。","reference":"Second, students can learn anywhere.",
   "hint":"情态动词 can 表能力","grammar_points":["情态动词"]}
]}
''';

  const paragraphJson = '''
{"tasks":[{"prompt_zh":"用约 120 词概括本文主旨与两个支撑点。",
"reference":"① 主旨:在线学习让学习更灵活;② 支撑:省时间、可回看。","hint":"先主旨后分点",
"word_count":120}]}
''';

  const examJson = '''
{"tasks":[{"prompt_zh":"For this part, write a short essay on the importance of reading.",
"reference":"","word_count":150,"hint":"三段式:观点-理由-结论"}],
"note":"来源:公开真题页"}
''';

  group('OutputTier.fromId', () {
    test('四阶 id / 中文 / 未知值容错', () {
      expect(OutputTier.fromId('word'), OutputTier.word);
      expect(OutputTier.fromId('sentence'), OutputTier.sentence);
      expect(OutputTier.fromId('paragraph'), OutputTier.paragraph);
      expect(OutputTier.fromId('essay'), OutputTier.essay);
      expect(OutputTier.fromId('写句'), OutputTier.sentence);
      expect(OutputTier.fromId('作文'), OutputTier.essay);
      expect(OutputTier.fromId('什么鬼'), OutputTier.paragraph);
      expect(OutputTier.fromId(null), OutputTier.paragraph);
    });
  });

  group('数据模型 JSON 容错', () {
    test('OutputTaskSpec 往返 + 类型脏值不崩', () {
      final spec = OutputTaskSpec(
        tier: OutputTier.sentence,
        type: 'back_translation',
        promptZh: '首先,在线课程节省时间。',
        reference: 'First, online courses save time.',
        rubricId: 'back_translation',
        grammarPoints: const <String>['一般现在时'],
        sourceSpan: 'First, online courses save time.',
        sourceUrl: 'https://example.com',
        source: 'exam',
        verifyStatus: 'pending',
        wordCount: 0,
      );
      final restored = OutputTaskSpec.fromJson(spec.toJson());
      expect(restored, isNotNull);
      expect(restored!.promptZh, spec.promptZh);
      expect(restored.rubricId, 'back_translation');
      expect(restored.grammarPoints, <String>['一般现在时']);
      expect(restored.hasReference, isTrue);
      expect(restored.isExam, isTrue);

      final dirty = OutputTaskSpec.fromJson(<String, dynamic>{
        'prompt': '题干',
        'word_count': '150 词',
        'ability_tags': '词汇,语法',
        'material_id': '12',
      });
      expect(dirty, isNotNull);
      expect(dirty!.promptZh, '题干');
      expect(dirty.wordCount, 150);
      expect(dirty.abilityTags, <String>['词汇', '语法']);
      expect(dirty.materialId, 12);
    });

    test('题干全空的题 → null;OutputSetSpec 空 tasks → null', () {
      expect(OutputTaskSpec.fromJson(const <String, dynamic>{}), isNull);
      expect(OutputTaskSpec.fromJson(null), isNull);
      expect(
        OutputSetSpec.fromJson(const <String, dynamic>{'title': 'x'}),
        isNull,
      );
    });

    test('OutputSetSpec 往返不丢题与来源', () {
      final set = OutputSetSpec(
        title: '四级写作真题',
        tier: OutputTier.essay,
        source: 'exam',
        examType: 'cet4',
        section: 'writing',
        rubricId: 'cet4_writing',
        sourceUrls: const <String>['https://example.com/exam'],
        tasks: const <OutputTaskSpec>[
          OutputTaskSpec(
            tier: OutputTier.essay,
            type: 'exam_writing',
            promptZh: 'Write an essay.',
            sourceUrl: 'https://example.com/exam',
            source: 'exam',
          ),
        ],
      );
      final restored = OutputSetSpec.fromJson(set.toJson());
      expect(restored, isNotNull);
      expect(restored!.tasks, hasLength(1));
      expect(restored.hasExamSource, isTrue);
      expect(restored.examType, 'cet4');
    });
  });

  group('四条提示词:必须禁止编造题源', () {
    test('回译提示词:带原句/数量/JSON 结构 + 题源纪律', () {
      final prompt = buildBackTranslationPrompt(
        englishSentences: const <String>[
          'First, online courses save time.',
          'Second, students can learn anywhere.',
        ],
        levelHint: 'B1',
        bandHint: 'i+10',
        count: 2,
      );
      expect(prompt.system, contains('禁止编造题源'));
      expect(prompt.system, contains('返回 JSON'));
      expect(prompt.system, contains('prompt_zh'));
      expect(prompt.system, contains('reference'));
      expect(prompt.user, contains('First, online courses save time.'));
      expect(prompt.user, contains('2 题'));
      expect(prompt.user, contains('B1'));
      expect(prompt.user, contains('i+10'));
      // 回译的"参考"就是英文原句,不允许模型自己改句
      expect(prompt.system, contains('不要改写英文原句'));
    });

    test('句式改写提示词:带改写方向 + 纪律', () {
      final prompt = buildSentenceRewritePrompt(
        originalSentences: const <String>['The book is very good.'],
        rewriteFocus: '合并从句',
        levelHint: 'B2',
        count: 1,
      );
      expect(prompt.system, contains('禁止编造题源'));
      expect(prompt.system, contains('参考改写'));
      expect(prompt.user, contains('合并从句'));
      expect(prompt.user, contains('The book is very good.'));
    });

    test('段落任务提示词:材料按 1500 词截断 + 字数要求 + 纪律', () {
      final longText = List<String>.generate(1800, (i) => 'word$i').join(' ');
      final prompt = buildParagraphTaskPrompt(
        materialText: longText,
        taskKind: 'summary',
        wordCount: 120,
        levelHint: 'B1',
      );
      expect(prompt.system, contains('禁止编造题源'));
      expect(prompt.system, contains('摘要写作'));
      expect(prompt.user, contains('已截断到约 1500 词'));
      expect(prompt.user, contains('约 120 词'));
      // 截断后不能把 1800 词原件整个塞进去
      expect(prompt.user.length, lessThan(longText.length));
      expect(prompt.user, contains('word0'));
      expect(prompt.user, isNot(contains('word1799')));
    });

    test('真题提示词:带考试/题型/来源 URL/正文 + 纪律', () {
      final prompt = buildExamWritingPrompt(
        examType: 'cet4',
        section: 'writing',
        sourceText: 'For this part, write an essay about reading.',
        sourceUrls: const <String>['https://example.com/cet4-2023'],
        year: 2023,
        levelHint: 'B2',
      );
      expect(prompt.system, contains('禁止编造题源'));
      expect(prompt.system, contains('参考范文'));
      expect(prompt.user, contains('四级'));
      expect(prompt.user, contains('2023'));
      expect(prompt.user, contains('写作'));
      expect(prompt.user, contains('https://example.com/cet4-2023'));
      expect(
        prompt.user,
        contains('For this part, write an essay about reading.'),
      );
      expect(prompt.user, contains('B2'));
    });
  });

  group('parseTaskList:通用出题解析', () {
    test('围栏 JSON 正常解析;默认值来自参数', () {
      final tasks = parseTaskList(
        '好的,题目如下:\n```json\n$backTranslationJson\n```',
        tier: OutputTier.sentence,
        type: 'back_translation',
        rubricId: 'back_translation',
      );
      expect(tasks, hasLength(2));
      expect(tasks.first.promptZh, contains('在线课程'));
      expect(tasks.first.reference, contains('online courses'));
      expect(tasks.first.tier, OutputTier.sentence);
      expect(tasks.first.rubricId, 'back_translation');
      expect(tasks.first.source, 'ai');
      expect(tasks.first.verifyStatus, 'pending');
      // 回译题:材料原文 = 英文原句
      expect(tasks.first.sourceSpan, contains('online courses'));
      expect(tasks.first.grammarPoints, <String>['一般现在时']);
    });

    test('少题:模型只给 1 题就只要 1 题(不补、不编)', () {
      final tasks = parseTaskList(
        '{"tasks":[{"prompt_zh":"只有一题","reference":"Only one."}]}',
        tier: OutputTier.sentence,
        type: 'back_translation',
        rubricId: 'back_translation',
      );
      expect(tasks, hasLength(1));
    });

    test('无参考:题目保留,reference 为空串(UI 显示"参考暂缺")', () {
      final tasks = parseTaskList(
        '{"tasks":[{"prompt_zh":"无参考的题","prompt_en":"Some sentence."}]}',
        tier: OutputTier.sentence,
        type: 'sentence_rewrite',
      );
      expect(tasks, hasLength(1));
      expect(tasks.first.hasReference, isFalse);
      expect(tasks.first.promptEn, 'Some sentence.');
    });

    test('坏 JSON / 没有 tasks / 空内容 → 空列表(不抛)', () {
      for (final content in <String>[
        '',
        '模型没给 JSON',
        '{"tasks": ',
        '{"foo": []}',
        '{"tasks": []}',
        '{"tasks": "oops"}',
      ]) {
        expect(
          parseTaskList(content, tier: OutputTier.paragraph, type: 'summary'),
          isEmpty,
          reason: '输入应解析为空:$content',
        );
      }
    });

    test('题源 URL 防编造:模型给的 URL 必须与调用方一致,否则用调用方的', () {
      final tasks = parseTaskList(
        '{"tasks":[{"prompt_zh":"题","source_url":"https://fake.example.com"}]}',
        tier: OutputTier.essay,
        type: 'exam_writing',
        source: 'exam',
        sourceUrl: 'https://real.example.com',
        verifyStatus: 'pending',
      );
      expect(tasks, hasLength(1));
      expect(
        tasks.single.sourceUrl,
        'https://real.example.com',
        reason: '模型编造的 URL 必须被替换成真实抓取来源',
      );
    });
  });

  group('四条路径专用解析', () {
    test('回译:中文题面 + 英文参考 + back_translation rubric', () {
      final tasks = parseBackTranslationTasks(backTranslationJson);
      expect(tasks, hasLength(2));
      expect(tasks.first.type, 'back_translation');
      expect(tasks.first.rubricId, 'back_translation');
      expect(tasks.first.promptZh, contains('首先'));
      expect(tasks.first.reference, contains('First'));
    });

    test('句式改写:无 rubric(用对照批改),参考改写保留', () {
      final tasks = parseSentenceRewriteTasks(
        '{"tasks":[{"prompt_zh":"把两句合并为一句","prompt_en":"The book is good. It is cheap.",'
        '"reference":"The book is good and cheap.","hint":"用 and 连接"}]}',
      );
      expect(tasks, hasLength(1));
      expect(tasks.single.type, 'sentence_rewrite');
      expect(tasks.single.rubricId, isEmpty);
      expect(tasks.single.reference, contains('good and cheap'));
    });

    test('段落:摘要用 summary rubric;观点段用 cet4_writing', () {
      final summary = parseParagraphTasks(paragraphJson, taskKind: 'summary');
      expect(summary, hasLength(1));
      expect(summary.single.rubricId, 'summary');
      expect(summary.single.tier, OutputTier.paragraph);
      expect(summary.single.wordCount, 120);

      final opinion = parseParagraphTasks(
        '{"tasks":[{"prompt_zh":"写一个观点段"}]}',
        taskKind: 'opinion',
      );
      expect(opinion.single.rubricId, 'cet4_writing');
      expect(opinion.single.type, 'opinion');
    });

    test('真题:没有来源 URL → 空列表(无来源不生成)', () {
      expect(
        parseExamWritingTasks(
          examJson,
          examType: 'cet4',
          section: 'writing',
          sourceUrls: const <String>[],
        ),
        isEmpty,
      );
    });

    test('真题:有来源 → 每题带 URL/source=exam/verify=pending', () {
      final tasks = parseExamWritingTasks(
        examJson,
        examType: 'cet4',
        section: 'writing',
        sourceUrls: const <String>['https://example.com/cet4-2023'],
      );
      expect(tasks, hasLength(1));
      expect(tasks.single.source, 'exam');
      expect(tasks.single.sourceUrl, 'https://example.com/cet4-2023');
      expect(tasks.single.verifyStatus, 'pending');
      expect(tasks.single.rubricId, 'cet4_writing');
      expect(tasks.single.tier, OutputTier.essay);
    });

    test('真题翻译题型自动换 rubric/type', () {
      final tasks = parseExamWritingTasks(
        '{"tasks":[{"prompt_zh":"把下面这段中文译成英文"}]}',
        examType: 'cet4',
        section: 'translation',
        sourceUrls: const <String>['https://example.com/trans'],
      );
      expect(tasks.single.type, 'exam_translation');
      expect(tasks.single.rubricId, 'cet4_translation');
    });
  });

  group('纯函数小工具', () {
    test('extractSentences:过滤短句/长句、去重、按原文顺序、限量', () {
      final material =
          '''
# A title

First, online courses can save a lot of time. Second, students can learn anywhere they want.
Too short.
${List<String>.generate(50, (i) => 'word$i').join(' ')}.
First, online courses can save a lot of time.
''';
      final sentences = extractSentences(material, max: 3);
      expect(sentences, hasLength(2), reason: '超长句与短句应被过滤,重复句应去重');
      expect(sentences.first, contains('First'));
      expect(sentences[1], contains('Second'));
    });

    test('truncateWords:不超限不改动,超限截断并加省略号', () {
      expect(truncateWords('a b c', 5), 'a b c');
      final cut = truncateWords('a b c d e f', 3);
      expect(cut, 'a b c…');
    });

    test('examTypeFromGoalIds:学习目标 → 数据库考试类型', () {
      expect(examTypeFromGoalIds(const <String>[]), 'none');
      expect(examTypeFromGoalIds(const <String>['cet']), 'cet4');
      // 2026-11-06(P0-2):泛化目标不压过明确目标 —— 与 targetExamOf 的两趟语义一致,
      // 「cet(四六级) + kaoyan」应取更明确的 kaoyan,而不是笼统的 cet4。
      expect(examTypeFromGoalIds(const <String>['cet', 'kaoyan']), 'kaoyan');
      expect(examTypeFromGoalIds(const <String>['kaoyan']), 'kaoyan');
      expect(examTypeFromGoalIds(const <String>['ielts']), 'ielts');
      expect(examTypeFromGoalIds(const <String>['business']), 'none');
    });

    test('buildExamSearchQuery:英文 query,年份可选', () {
      expect(
        buildExamSearchQuery(examType: 'cet4', section: 'writing', year: 2023),
        'CET-4 writing prompts past exam 2023',
      );
      expect(
        buildExamSearchQuery(examType: 'kaoyan', section: 'translation'),
        contains('Postgraduate English'),
      );
      expect(
        buildExamSearchQuery(examType: 'ielts', section: 'writing'),
        isNot(contains('past exam ')),
      );
    });

    test('sectionForTier / paragraphKindForGoals', () {
      expect(sectionForTier(OutputTier.sentence), 'back_translation');
      expect(sectionForTier(OutputTier.essay), 'writing');
      expect(paragraphKindForGoals(const <String>['cet']), 'opinion');
      expect(paragraphKindForGoals(const <String>['reading']), 'summary');
    });
  });

  group('OutputComposer 纯逻辑(不触发网络的方法)', () {
    test('禁用真题检索时 examSearchAvailable=false,且不读真配置', () {
      final composer = OutputComposer(autoResolveSearch: false);
      expect(composer.examSearchAvailable, isFalse);
    });

    test('空材料/写词档直接返回 null(在发请求之前就拦住)', () async {
      final composer = OutputComposer(autoResolveSearch: false);
      expect(
        await composer.composeFromMaterial(
          materialText: '   ',
          examGoals: const <String>['cet'],
          levelHint: 'B1',
          bandHint: '',
          tier: 'sentence',
        ),
        isNull,
      );
      expect(
        await composer.composeFromMaterial(
          materialText: 'First, online courses save time.',
          examGoals: const <String>['cet'],
          levelHint: 'B1',
          bandHint: '',
          tier: 'word',
        ),
        isNull,
        reason: '写词档应走生词本,不走 AI 出题(PLAN-V3 §2.3)',
      );
    });

    test('评分:空作答直接返回 null(不发请求)', () async {
      final composer = OutputComposer(autoResolveSearch: false);
      expect(
        await composer.score(
          rubric: OutputRubric.builtin().first,
          task: 'Write an essay.',
          answer: '   ',
        ),
        isNull,
      );
    });
  });
}
