/// 词汇量测试「完整版」里的语法与阅读小题(内置题库)。
///
/// 定位(PLAN-2.0 §9):
/// - 这两部分**不计入词汇量估计**,只用于:① 把绝对档位从"词量"往"实际运用"
///   上校准一点;② 给错误标签画像起步(语法题带 [tag],答错即记一次该类薄弱)。
/// - 题量刻意很小(5 + 3):完整版的总时长目标是 10 分钟,主体仍是词汇部分。
/// - 题目是自编的,不涉及版权材料;难度大致 B1-B2。
library;

/// 一道四选一小题
class ChoiceQuestion {
  /// 题干(语法题为句子填空,阅读题为问题)
  final String prompt;

  /// 选项(A/B/C/D 由 UI 加前缀)
  final List<String> options;

  /// 正确选项下标
  final int answerIndex;

  /// 解析(答完给用户看,也是"专业评估"的一部分:不只给分,还说为什么)
  final String explanation;

  /// 语法错误标签(仅语法题有;阅读题为 'reading')
  final String tag;

  const ChoiceQuestion({
    required this.prompt,
    required this.options,
    required this.answerIndex,
    required this.explanation,
    required this.tag,
  });
}

/// 语法小题(覆盖时态/冠词/介词/主谓一致/虚拟语气 —— 中国学习者高频薄弱点)
const List<ChoiceQuestion> kGrammarQuestions = [
  ChoiceQuestion(
    prompt: 'I ______ in this city for ten years, and I still love it.',
    options: ['live', 'am living', 'have lived', 'lived'],
    answerIndex: 2,
    explanation: '"for + 时间段" 且与现在仍有联系 → 用现在完成时 have lived。'
        '一般过去时 lived 会暗示"已经不住这儿了"。',
    tag: '时态',
  ),
  ChoiceQuestion(
    prompt: 'She is ______ honest person; you can trust her.',
    options: ['a', 'an', 'the', '不填'],
    answerIndex: 1,
    explanation: 'honest 的 h 不发音,首音节是元音 /ɒ/ → 用 an。'
        '冠词看的是**读音**不是字母。',
    tag: '冠词',
  ),
  ChoiceQuestion(
    prompt: 'We discussed the plan ______ the phone last night.',
    options: ['in', 'on', 'at', 'by'],
    answerIndex: 1,
    explanation: '固定搭配:on the phone(通电话)。'
        'in 用于语言/媒介(如 in English),by 用于手段(by phone = 通过电话这种方式)。',
    tag: '介词',
  ),
  ChoiceQuestion(
    prompt: 'Neither the teacher nor the students ______ aware of the change.',
    options: ['was', 'were', 'is', 'has been'],
    answerIndex: 1,
    explanation: 'neither A nor B 作主语时,谓语与**就近**的 B 一致:'
        'students 是复数 → were。',
    tag: '主谓一致',
  ),
  ChoiceQuestion(
    prompt: 'If I ______ you, I would take the offer without hesitation.',
    options: ['am', 'was', 'were', 'will be'],
    answerIndex: 2,
    explanation: '与现在事实相反的虚拟条件句:if + 过去式(be 用 were),'
        '主句 would + 动词原形。',
    tag: '虚拟语气',
  ),
];

/// 阅读小题用的一段短文(自编,约 130 词,难度约 B1-B2)
class ReadingPassage {
  final String title;
  final String text;

  /// 建议阅读时限(秒),超时不影响计分,只在结果里提示"偏慢"
  final int suggestedSeconds;
  final List<ChoiceQuestion> questions;

  const ReadingPassage({
    required this.title,
    required this.text,
    required this.questions,
    this.suggestedSeconds = 150,
  });
}

const ReadingPassage kReadingPassage = ReadingPassage(
  title: 'The Cost of Convenience',
  text: '''
When people talk about progress, they usually mean speed. Food arrives in minutes,
answers appear in seconds, and almost anything can be bought with a single tap. It is
hard to argue that these changes have made daily life easier.

But convenience has a quieter cost. When a task becomes effortless, the skill behind it
fades. Drivers who always rely on navigation often struggle to describe a route they
have taken a hundred times. Readers who skim short posts find it harder to sit with a
long argument. The ability is not lost overnight; it simply stops being practised.

None of this means we should reject useful tools. The point is to notice what we are
trading away, and to keep a few difficult things difficult on purpose -- because some
abilities only grow when we refuse to take the easy path.
''',
  questions: [
    ChoiceQuestion(
      prompt: 'What is the main idea of the passage?',
      options: [
        'Technology has made daily life worse overall.',
        'Convenience can quietly weaken skills we stop practising.',
        'People should stop using navigation apps.',
        'Reading long texts is no longer necessary.',
      ],
      answerIndex: 1,
      explanation: '全文承认便利的好处,转而讨论"技能因不再练习而退化"这个代价 —— '
          'B 是主旨;A/C 把作者立场夸大成了"反对技术/反对导航"。',
      tag: 'reading',
    ),
    ChoiceQuestion(
      prompt: 'The phrase "keep a few difficult things difficult on purpose" suggests that the author wants people to:',
      options: [
        'avoid all new tools',
        'deliberately practise demanding skills',
        'make life harder for others',
        'give up short posts entirely',
      ],
      answerIndex: 1,
      explanation: '该句是作者的建议:有意保留一些"需要费力"的事,'
          '因为能力只在不愿意走捷径时才生长 → 即刻意练习。',
      tag: 'reading',
    ),
    ChoiceQuestion(
      prompt: 'Which example does the author use to support the argument?',
      options: [
        'Cooks who order food online',
        'Drivers who depend on navigation',
        'Students who read short posts',
        'Shoppers who buy with one tap',
      ],
      answerIndex: 1,
      explanation: '第二段明确给出的例子是"总靠导航的司机说不清走过上百次的路"。'
          '其余选项是首段提到的便利现象,不是支撑论点的论据。',
      tag: 'reading',
    ),
  ],
);
