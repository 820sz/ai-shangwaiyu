/// 输出练习的**内置素材库**(v3 · 批 3 增强,2026-11-01)。
///
/// 用户原话:
/// > "输出功能目前的输出练习不要局限于'和输入闭环',也有给用户提供自选练习方式
/// >  (比如不要现在练四阶都只能从软件内输入的来练习,还要能让用户选择能从自己的
/// >  需求来提供对应的练习材料 —— 比如他要考四六级,练习对应可以提供四六级的
/// >  材料练习 —— 考纲词汇、作文范文句子等等;同理,他要读外刊,则提供一下外刊的
/// >  高频词,以此类推)"
///
/// 所以这一层提供**不依赖已读材料**的练习来源:
/// - 考纲/水平词汇(四六级/考研/雅思托福/新概念/外刊高频) → 写词阶;
/// - 作文范文句(英中对照) → 写句阶(中译英回译);
/// - 范文段落(英中对照 + 提示) → 写段阶(默写/仿写/摘要);
/// - 真题风格作文题(带要点与 rubric) → 写篇阶。
///
/// 为什么内置而不是联网:①用户可能没配 Key,离线也要能练;②考纲词汇/范文句是
/// 稳定公共知识,不该每次让模型现编(现编会漂移);③加载即时,不受限流影响。
///
/// 数据纪律:词表与句库都是**人工筛选的常用内容**,只收能确认中文释义的条目;
/// 词条格式用 `word|中文释义|词性` 单行串,加载时解析 —— 既省文件体积,
/// 也方便后续替换成更大的公开词表(解析逻辑不变)。
library;

import 'dart:math';

import 'exam_vocab.dart';
import 'output_composer.dart';

/// 一个练习来源(界面上的"按目标练"卡片)。
class OutputPracticeSource {
  final String id;
  final String title;
  final String description;

  /// 对应阶(word/sentence/paragraph/essay)
  final OutputTier tier;

  /// 命中哪些用户目标(DrillCatalog 的中文 label 子串或偏好 id);
  /// 空 = 通用来源(任何目标/没有目标都能选)
  final List<String> matchesGoals;

  /// 这个来源里的条目数(界面显示"120 词"等)
  final int itemCount;

  const OutputPracticeSource({
    required this.id,
    required this.title,
    required this.description,
    required this.tier,
    required this.itemCount,
    this.matchesGoals = const [],
  });

  /// 是否命中用户的多选目标(按子串双向匹配,容忍"四六级"/"CET4"/"四级"等写法)
  bool matches(List<String> examGoals) {
    if (matchesGoals.isEmpty) return true;
    if (examGoals.isEmpty) return false;
    for (final goal in examGoals) {
      final g = goal.toLowerCase();
      for (final m in matchesGoals) {
        final k = m.toLowerCase();
        if (g.contains(k) || k.contains(g)) return true;
      }
    }
    return false;
  }
}

/// 一条词汇练习素材。
class WordBankEntry {
  final String word;
  final String meaning;
  final String pos;
  const WordBankEntry(this.word, this.meaning, this.pos);
}

/// 一条英中对照句子(写句阶用:给中文,写英文)。
class SentencePair {
  final String en;
  final String zh;

  /// 该句练的表达点(界面提示用,如"让步状语从句")
  final String hint;
  const SentencePair(this.en, this.zh, [this.hint = '']);
}

/// 一个范文段落(写段阶用)。
class ParagraphModel {
  final String en;
  final String zh;
  final String hint;
  const ParagraphModel(this.en, this.zh, this.hint);
}

/// 一道真题风格作文题(写篇阶用)。
class EssayPrompt {
  final String titleZh;
  final String taskZh;
  final String taskEn;

  /// 参考要点(不是范文全文:给结构提示,避免背模板)
  final List<String> points;
  final String rubricId;
  final int wordCount;
  const EssayPrompt({
    required this.titleZh,
    required this.taskZh,
    required this.taskEn,
    required this.points,
    this.rubricId = 'cet4_writing',
    this.wordCount = 120,
  });
}

/// 内置素材库(纯静态数据 + 纯选择函数,可单测)。
class OutputBank {
  OutputBank._();

  // ── 词汇:考纲/外刊高频(格式:单词|中文释义|词性)──────────────
  //
  // 选词口径:四六级阅读/写作高频,释义是本 App 常用语境下的第一释义;
  // 只收词形简单、拼写可练的词(不收缩写与专名)。
  static const List<String> _cet4Raw = [
    'abandon|放弃;遗弃|v',
    'absorb|吸收;理解|v',
    'abstract|抽象的;摘要|adj',
    'academic|学术的|adj',
    'accelerate|加速|v',
    'accompany|陪伴;伴随|v',
    'accomplish|完成;实现|v',
    'accurate|准确的|adj',
    'achieve|达到;实现|v',
    'acquire|获得;习得|v',
    'adapt|适应;改编|v',
    'adequate|足够的|adj',
    'adjust|调整|v',
    'admire|钦佩|v',
    'adopt|采用;收养|v',
    'advantage|优势|n',
    'affect|影响|v',
    'afford|负担得起|v',
    'aggressive|好斗的;有进取心的|adj',
    'alter|改变|v',
    'alternative|替代的;备选方案|n',
    'analyze|分析|v',
    'apparent|明显的|adj',
    'appeal|吸引;呼吁|v',
    'appreciate|欣赏;感激|v',
    'approach|接近;方法|v',
    'appropriate|恰当的|adj',
    'approve|批准;赞成|v',
    'argue|争论;主张|v',
    'arrange|安排|v',
    'assess|评估|v',
    'assign|分配;指派|v',
    'assume|假设;承担|v',
    'attach|附上;重视|v',
    'attempt|尝试|v',
    'attitude|态度|n',
    'attract|吸引|v',
    'authority|权威;当局|n',
    'available|可获得的|adj',
    'aware|意识到的|adj',
    'barrier|障碍|n',
    'benefit|好处;受益|n',
    'budget|预算|n',
    'campaign|运动;活动|n',
    'capable|有能力的|adj',
    'capacity|容量;能力|n',
    'challenge|挑战|n',
    'circumstance|情况;环境|n',
    'commit|致力于;承诺|v',
    'communicate|交流|v',
    'compete|竞争|v',
    'complain|抱怨|v',
    'complex|复杂的|adj',
    'concentrate|集中;专注|v',
    'conclude|得出结论|v',
    'conduct|进行;行为|v',
    'confirm|确认|v',
    'consequence|后果|n',
    'consider|考虑|v',
    'consist|由…组成|v',
    'constant|不断的;恒定的|adj',
    'consume|消耗|v',
    'contribute|贡献;促成|v',
    'convenient|方便的|adj',
    'convince|说服;使确信|v',
    'cooperate|合作|v',
    'crucial|关键的|adj',
    'cultivate|培养;耕作|v',
    'curious|好奇的|adj',
    'declare|宣布;声明|v',
    'decline|下降;拒绝|v',
    'dedicate|致力于|v',
    'definitely|肯定地|adv',
    'deliver|递送;发表|v',
    'demand|需求;要求|n',
    'demonstrate|证明;演示|v',
    'deny|否认|v',
    'depend|依赖|v',
    'deserve|值得|v',
    'despite|尽管|prep',
    'determine|确定;决定|v',
    'develop|发展;开发|v',
    'differ|不同|v',
    'display|展示|v',
    'dominate|支配;主导|v',
    'efficient|高效的|adj',
    'eliminate|消除|v',
    'emphasize|强调|v',
    'encounter|遇到|v',
    'encourage|鼓励|v',
    'enhance|提高;增强|v',
    'ensure|确保|v',
    'environment|环境|n',
    'equivalent|等价的|adj',
    'essential|必要的;本质的|adj',
    'establish|建立|v',
    'estimate|估计|v',
    'evidence|证据|n',
    'evident|明显的|adj',
    'exceed|超过|v',
    'exchange|交换|v',
    'exhibit|展出;表现|v',
    'expand|扩大|v',
    'expect|期望|v',
    'experiment|实验|n',
    'expose|暴露;接触|v',
    'extend|延长;扩展|v',
    'external|外部的|adj',
    'facilitate|促进;便利|v',
    'fascinating|迷人的|adj',
    'flexible|灵活的|adj',
    'frequent|频繁的|adj',
    'fundamental|根本的|adj',
    'generate|产生|v',
    'guarantee|保证|v',
    'identify|识别;确认|v',
    'ignore|忽视|v',
    'illustrate|说明;举例|v',
    'impact|影响;冲击|n',
    'imply|暗示|v',
    'impress|使印象深刻|v',
    'improve|改善|v',
    'incline|倾向|v',
    'indicate|表明|v',
    'individual|个人的;个体|adj',
    'influence|影响|n',
    'insist|坚持;强调|v',
    'inspire|激励;启发|v',
    'intend|打算|v',
    'interpret|解释;口译|v',
    'investigate|调查|v',
    'involve|涉及;使参与|v',
    'isolate|隔离|v',
    'maintain|保持;主张|v',
    'majority|多数|n',
    'manage|管理;设法|v',
    'measure|测量;措施|n',
    'minority|少数|n',
    'modify|修改|v',
    'motivate|激励|v',
    'negative|消极的;否定的|adj',
    'neglect|忽视|v',
    'obtain|获得|v',
    'obvious|明显的|adj',
    'occupy|占据|v',
    'occur|发生|v',
    'opportunity|机会|n',
    'participate|参与|v',
    'particular|特别的|adj',
    'perform|表现;执行|v',
    'permanent|永久的|adj',
    'persuade|说服|v',
    'phenomenon|现象|n',
    'potential|潜在的;潜力|adj',
    'practical|实际的|adj',
    'predict|预测|v',
    'prefer|更喜欢|v',
    'prepare|准备|v',
    'preserve|保存;保护|v',
    'prevent|阻止|v',
    'previous|之前的|adj',
    'primary|主要的;初级的|adj',
    'principle|原则|n',
    'priority|优先事项|n',
    'promote|促进;提升|v',
    'propose|提议|v',
    'prove|证明|v',
    'provide|提供|v',
    'purchase|购买|v',
    'pursue|追求|v',
    'reject|拒绝|v',
    'release|释放;发布|v',
    'reliable|可靠的|adj',
    'remarkable|非凡的|adj',
    'replace|取代|v',
    'represent|代表|v',
    'require|要求|v',
    'resent|怨恨|v',
    'resolve|解决;决心|v',
    'respond|回应|v',
    'reveal|揭示|v',
    'satisfy|满足|v',
    'secure|安全的;获得|adj',
    'significant|重要的;显著的|adj',
    'similar|相似的|adj',
    'specific|具体的|adj',
    'stable|稳定的|adj',
    'strategy|策略|n',
    'strengthen|加强|v',
    'struggle|挣扎;努力|v',
    'succeed|成功|v',
    'sufficient|充足的|adj',
    'suggest|建议;表明|v',
    'supply|供应|v',
    'suppose|假设|v',
    'surround|围绕|v',
    'survey|调查|n',
    'survive|幸存|v',
    'suspect|怀疑|v',
    'typical|典型的|adj',
    'undertake|承担|v',
    'unique|独特的|adj',
    'urgent|紧急的|adj',
    'utilize|利用|v',
    'variety|多样性;种类|n',
    'vital|至关重要的|adj',
    'volunteer|志愿者|n',
    'witness|目睹;见证|v',
  ];

  /// 外刊/新闻高频(读外刊的用户练这些)
  static const List<String> _newsRaw = [
    'advocate|主张;倡导|v',
    'agenda|议程|n',
    'ambiguous|模棱两可的|adj',
    'amend|修订|v',
    'amid|在…之中|prep',
    'anticipate|预料|v',
    'appoint|任命|v',
    'assessment|评估|n',
    'attribute|归因于;属性|v',
    'backlash|强烈反对|n',
    'bilateral|双边的|adj',
    'boost|提振|v',
    'ceasefire|停火|n',
    'coalition|联盟|n',
    'coherent|连贯的|adj',
    'collapse|崩溃;倒塌|v',
    'compelling|令人信服的|adj',
    'concede|承认|v',
    'consensus|共识|n',
    'controversial|有争议的|adj',
    'crackdown|严厉打击|n',
    'credibility|公信力|n',
    'deficit|赤字|n',
    'delegation|代表团|n',
    'deploy|部署|v',
    'deteriorate|恶化|v',
    'diplomatic|外交的|adj',
    'disclose|披露|v',
    'disparity|差距|n',
    'dividend|红利|n',
    'drastic|剧烈的|adj',
    'embargo|禁运|n',
    'escalate|升级|v',
    'exempt|免除|v',
    'faction|派系|n',
    'fiscal|财政的|adj',
    'fragile|脆弱的|adj',
    'gridlock|僵局|n',
    'humanitarian|人道主义的|adj',
    'incentive|激励;诱因|n',
    'inflation|通货膨胀|n',
    'initiative|倡议;主动性|n',
    'insurgent|叛乱者|n',
    'jurisdiction|管辖权|n',
    'landmark|里程碑式的|adj',
    'legislation|立法|n',
    'leverage|利用;杠杆|v',
    'mandate|授权;命令|n',
    'negotiate|谈判|v',
    'outbreak|爆发|n',
    'oversight|监督|n',
    'partisan|党派的|adj',
    'pledge|承诺|v',
    'polarized|两极分化的|adj',
    'proliferation|扩散|n',
    'prospect|前景|n',
    'ratify|批准|v',
    'regime|政权;制度|n',
    'reiterate|重申|v',
    'resilient|有韧性的|adj',
    'sanction|制裁|n',
    'scrutiny|审查|n',
    'sovereignty|主权|n',
    'stakeholder|利益相关者|n',
    'subsidy|补贴|n',
    'tariff|关税|n',
    'transparency|透明度|n',
    'turmoil|动荡|n',
    'undermine|削弱|v',
    'unprecedented|前所未有的|adj',
    'volatile|不稳定的|adj',
    'withdraw|撤回;退出|v',
  ];

  /// 作文范文句(英中对照):写句阶回译用。
  ///
  /// 选句口径:四六级作文里**自己也能用上**的句式(观点表达/让步/因果/建议),
  /// 不是华丽的"高级替换",而是能迁移到别的题目的骨架句。
  static const List<SentencePair> essaySentences = [
    SentencePair(
      'It is widely acknowledged that reading plays a vital role in shaping one\'s way of thinking.',
      '众所周知,阅读在塑造一个人的思维方式中起着至关重要的作用。',
      '观点表达 · 形式主语',
    ),
    SentencePair(
      'With the rapid development of technology, our daily lives have been changed in many ways.',
      '随着科技的快速发展,我们的日常生活已在许多方面被改变。',
      '背景句 · With 短语',
    ),
    SentencePair(
      'While some people argue that online learning is convenient, others worry about its lack of interaction.',
      '虽然有人主张线上学习方便,但另一些人担心它缺乏互动。',
      '让步 · While 对比',
    ),
    SentencePair(
      'The reason why this phenomenon is common lies in the pressure young people face today.',
      '这一现象之所以普遍,原因在于如今年轻人面临的压力。',
      '因果 · The reason why',
    ),
    SentencePair(
      'Taking effective measures is the key to solving this problem.',
      '采取有效措施是解决这个问题的关键。',
      '建议句 · 动名词作主语',
    ),
    SentencePair(
      'From my perspective, the advantages of this trend far outweigh its disadvantages.',
      '在我看来,这一趋势的优点远大于缺点。',
      '个人观点 · outweigh',
    ),
    SentencePair(
      'Only by balancing study and life can students maintain long-term motivation.',
      '只有平衡学习与生活,学生才能保持长期动力。',
      '倒装 · Only by',
    ),
    SentencePair(
      'It is high time that we took action to protect the environment.',
      '现在是我们采取行动保护环境的时候了。',
      '虚拟语气 · It is high time',
    ),
    SentencePair(
      'Compared with traditional classes, online courses offer greater flexibility.',
      '与传统课堂相比,线上课程提供了更大的灵活性。',
      '比较 · Compared with',
    ),
    SentencePair(
      'There is no denying that a healthy lifestyle contributes to both physical and mental well-being.',
      '不可否认,健康的生活方式有助于身心健康。',
      '强调句 · There is no denying',
    ),
    SentencePair(
      'What matters most is not how fast we learn, but whether we keep learning.',
      '最重要的不是我们学得多快,而是我们是否持续学习。',
      '主语从句 · not...but',
    ),
    SentencePair(
      'In conclusion, we should treat this issue in a rational and balanced way.',
      '总之,我们应当理性、平衡地看待这一问题。',
      '结尾 · In conclusion',
    ),
  ];

  /// 范文段落(写段阶:默写 / 仿写 / 摘要)
  static const List<ParagraphModel> paragraphModels = [
    ParagraphModel(
      'Reading opens a door to a world we have never seen. Through books, we meet people '
          'from different cultures and learn to see problems from more than one angle. '
          'A single hour of reading can change the way we think for years.',
      '阅读为我们打开一扇通往未曾见过的世界的门。通过书籍,我们遇见来自不同文化的人,'
          '学会从不止一个角度看待问题。仅仅一小时的阅读,可能改变我们多年的思考方式。',
      '观点段:主题句 → 展开 → 收尾',
    ),
    ParagraphModel(
      'Although online courses save time and money, they require strong self-discipline. '
          'Without a teacher beside us, distraction is always one click away. '
          'Therefore, students must set clear goals before they start.',
      '虽然线上课程节省时间和金钱,但它们要求很强的自律。没有老师在身边,干扰总是近在点击之间。'
          '因此,学生必须在开始前设定清晰的目标。',
      '让步段:承认优点 → 转折 → 结论',
    ),
    ParagraphModel(
      'Many young people say they have no time to exercise, yet spend hours on their phones. '
          'The problem is not the lack of time, but the lack of priority. '
          'Once exercise becomes a daily habit, it takes less effort than people imagine.',
      '许多年轻人说没时间锻炼,却在手机上花掉数小时。问题不在于缺少时间,而在于缺少优先级。'
          '一旦锻炼成为日常习惯,它比人们想象的要省力。',
      '现象-分析段:现象 → 归因 → 论证',
    ),
    ParagraphModel(
      'A good habit is built on small, repeatable actions. Ten minutes of reading every night '
          'may seem insignificant, but over a year it adds up to sixty hours. '
          'That is why we should start small instead of waiting for the perfect plan.',
      '好习惯建立在微小、可重复的行动上。每晚十分钟阅读看似微不足道,但一年下来就是六十小时。'
          '这就是为什么我们应当从小处开始,而不是等待完美的计划。',
      '论证段:论点 → 举例计算 → 结论',
    ),
    ParagraphModel(
      'Technology has made communication easier, but not necessarily better. '
          'Messages are sent faster than ever, while real conversations become shorter. '
          'What we need is not more channels, but more attention.',
      '科技让沟通变得更容易,但未必更好。信息发送得比以往更快,而真正的对话却更短了。'
          '我们需要的不是更多渠道,而是更多注意力。',
      '辩证段:肯定 → 转折 → 主张',
    ),
    ParagraphModel(
      'Before choosing a major, students should ask themselves three questions: what they enjoy, '
          'what they are good at, and what the world needs. '
          'The best choice is usually where these three circles overlap.',
      '在选择专业之前,学生应当问自己三个问题:自己喜欢什么、擅长什么,以及世界需要什么。'
          '最好的选择通常是这三个圆圈重叠的地方。',
      '建议段:三分法 → 建议',
    ),
  ];

  /// 真题风格作文题(写篇阶)
  static const List<EssayPrompt> essayPrompts = [
    EssayPrompt(
      titleZh: '线上学习与线下学习',
      taskZh: '有人认为线上学习更高效,也有人认为线下课堂不可替代。请就这两种观点写一篇短文,并说明你的看法。',
      taskEn: 'Some people believe online learning is more efficient, while others think '
          'traditional classroom learning cannot be replaced. Write a short essay on your view.',
      points: ['两种模式的优缺点各写一点', '用一例支撑', '给出自己的取舍与条件'],
    ),
    EssayPrompt(
      titleZh: '如何缓解大学生的就业焦虑',
      taskZh: '近年来大学生就业压力增大。请分析原因,并提出两条可行建议。',
      taskEn: 'College students are facing increasing pressure in the job market. '
          'Analyze the causes and offer two suggestions.',
      points: ['原因:竞争、信息不对称、期望偏差', '建议要具体可执行', '避免空喊口号'],
    ),
    EssayPrompt(
      titleZh: '手机与专注力',
      taskZh: '手机让我们随时随地获取信息,也让我们越来越难专注。请谈谈你的看法。',
      taskEn: 'Smartphones give us information anywhere, but also make concentration harder. '
          'What is your opinion?',
      points: ['承认便利', '指出代价:切换成本、碎片化', '给出一个具体做法'],
    ),
    EssayPrompt(
      titleZh: '一次难忘的经历',
      taskZh: '写一件让你印象深刻的经历,并说明它带给你的改变。',
      taskEn: 'Write about an unforgettable experience and explain how it changed you.',
      points: ['时间地点一句话交代', '细节场景描写', '结尾点出改变'],
    ),
    EssayPrompt(
      titleZh: '是否应该给大学生更多实践机会',
      taskZh: '有人认为大学生应多参加实践活动,也有人担心影响学业。请表达你的观点。',
      taskEn: 'Should college students take more practical activities, even at the expense '
          'of study time? Give your opinion.',
      points: ['给出立场', '用 1 条理由 + 1 个反例条件', '结尾重申'],
    ),
    EssayPrompt(
      titleZh: '城市与乡村生活',
      taskZh: '有人喜欢城市的便利,有人向往乡村的宁静。请比较并给出你的选择。',
      taskEn: 'Some prefer the convenience of cities, others the peace of the countryside. '
          'Compare and give your choice.',
      points: ['两边各一句', '说明你的需求', '承认代价'],
    ),
    EssayPrompt(
      titleZh: '阅读习惯的养成',
      taskZh: '很多人想读书却没有时间。请谈谈如何养成阅读习惯。',
      taskEn: 'Many people want to read but claim they have no time. '
          'Discuss how to build a reading habit.',
      points: ['指出"没时间"实为优先级问题', '给 2 条可执行方法', '强调从小处开始'],
    ),
    EssayPrompt(
      titleZh: '网络信息的真假',
      taskZh: '网络让信息传播更快,也让谣言扩散更快。请谈谈如何辨别信息。',
      taskEn: 'The Internet spreads both information and rumors quickly. '
          'How can we tell facts from falsehood?',
      points: ['现象一句', '方法:交叉验证/溯源/看动机', '强调个人责任'],
    ),
    EssayPrompt(
      titleZh: '人工智能与我们的工作',
      taskZh: '人工智能正在改变许多职业。请谈谈这对年轻人意味着什么,应如何准备。',
      taskEn: 'AI is changing many jobs. What does it mean for young people, and how should '
          'they prepare?',
      points: ['变化要具体', '提出不可替代的能力', '准备方式要可执行'],
    ),
    EssayPrompt(
      titleZh: '坚持一件小事',
      taskZh: '请写一段你坚持做一件小事的经历,并说明坚持带来的收获。',
      taskEn: 'Describe a small habit you kept, and what you gained from it.',
      points: ['具体到频率与时长', '中间的困难', '收获别说空话'],
      rubricId: 'cet4_writing',
      wordCount: 120,
    ),
  ];

  // ── 解析与选择(纯函数)──────────────────────────────────

  static List<WordBankEntry> _parse(List<String> raw) {
    final out = <WordBankEntry>[];
    for (final line in raw) {
      final parts = line.split('|');
      if (parts.length < 2) continue;
      final word = parts[0].trim();
      final meaning = parts[1].trim();
      if (word.isEmpty || meaning.isEmpty) continue;
      out.add(WordBankEntry(
        word,
        meaning,
        parts.length >= 3 ? parts[2].trim() : '',
      ));
    }
    return out;
  }

  /// 四六级/考研通用考纲词
  static final List<WordBankEntry> cet4Words = _parse(_cet4Raw);

  /// 按考试等级取词池(四级/六级拆桶)。
  ///
  /// 数据来自 `assets/data/exam_vocab.json`:同一份词表里每个词带 `exams` 多标签,
  /// 所以"四级词"与"六级词"是**同一事实源的两个视图**,不是两张各自维护的表。
  /// 词表未加载(离线首屏/测试未注入)时返回空,调用方回落内置精选池。
  static List<WordBankEntry> wordsForLevel(String examId) {
    try {
      final id = examId.trim().toLowerCase();
      if (id.isEmpty || !ExamVocab.isLoaded) return const <WordBankEntry>[];
      final words = ExamVocab.wordsFor(id, limit: 400);
      return <WordBankEntry>[
        for (final w in words) WordBankEntry(w.word, w.zh, w.pos),
      ];
    } catch (_) {
      return const <WordBankEntry>[];
    }
  }

  /// 六级来源卡显示的词数:词表未加载时退回精选池规模(不显示 0)
  static int get cet6WordCount {
    final words = wordsForLevel('cet6');
    return words.isEmpty ? cet4Words.length : words.length;
  }

  /// 外刊/新闻高频词
  static final List<WordBankEntry> newsWords = _parse(_newsRaw);

  /// 所有来源(界面按用户目标排序展示)
  static List<OutputPracticeSource> sources() => [
        // 2026-11-06 二期:四六级拆成两个来源(词池按考纲词表 exams 标签切分;
        // 词表未加载时回落内置四六级精选池,不空手)。
        OutputPracticeSource(
          id: 'cet4_words',
          title: '四级高频词',
          description: '四级考纲高频词，练拼写与中译英',
          tier: OutputTier.word,
          itemCount: cet4Words.length,
          matchesGoals: const ['四级', 'CET-4', '四六级', 'cet'],
        ),
        OutputPracticeSource(
          id: 'cet6_words',
          title: '六级高频词',
          description: '六级考纲高频词，词更长、更抽象',
          tier: OutputTier.word,
          itemCount: cet6WordCount,
          matchesGoals: const ['六级', 'CET-6', '四六级', 'cet'],
        ),
        OutputPracticeSource(
          id: 'news_words',
          title: '外刊高频词',
          description: '读外刊/新闻常遇到的词',
          tier: OutputTier.word,
          itemCount: newsWords.length,
          matchesGoals: const ['外刊', '新闻', '阅读', '雅思', '托福', '考研'],
        ),
        OutputPracticeSource(
          id: 'essay_sentences',
          title: '作文范文句',
          description: '英中对照,给中文写英文(回译)',
          tier: OutputTier.sentence,
          itemCount: essaySentences.length,
          matchesGoals: const ['四六级', '四级', '六级', 'cet', '考研', '雅思', '托福'],
        ),
        OutputPracticeSource(
          id: 'paragraph_models',
          title: '范文段落',
          description: '模仿结构与句式的段落练习',
          tier: OutputTier.paragraph,
          itemCount: paragraphModels.length,
          matchesGoals: const ['四六级', '四级', '六级', 'cet', '考研', '雅思', '托福'],
        ),
        OutputPracticeSource(
          id: 'essay_prompts',
          title: '四六级作文题',
          description: '真题风格题目 + 参考要点,按 rubric 评分',
          tier: OutputTier.essay,
          itemCount: essayPrompts.length,
          matchesGoals: const ['四六级', '四级', '六级', 'cet'],
        ),
      ];

  /// 按用户目标排序:命中的在前,通用来源在后(没有目标时给全部)。
  static List<OutputPracticeSource> recommendedSources(List<String> examGoals) {
    final all = sources();
    final hit = <OutputPracticeSource>[];
    final rest = <OutputPracticeSource>[];
    for (final s in all) {
      (s.matches(examGoals) ? hit : rest).add(s);
    }
    return [...hit, ...rest];
  }

  /// 从词库抽 [count] 个词(按词长由短到长优先,便于从易到难;seed 可复现)。
  static List<WordBankEntry> pickWords(
    List<WordBankEntry> pool,
    int count, {
    int? seed,
  }) {
    if (pool.isEmpty || count <= 0) return const [];
    final copy = List<WordBankEntry>.of(pool);
    // 先按词长排序(短词先练),再在"同长度段"内用给定种子打散。
    // 注意:count 不小于词库时返回整个词库(调用方要"全都要"时不该被窗口截断)。
    copy.sort((a, b) {
      final byLen = a.word.length.compareTo(b.word.length);
      if (byLen != 0) return byLen;
      return a.word.compareTo(b.word);
    });
    // 取前 2/3 的"常规难度"区间后随机抽,避免总是练同一批最短词
    final cut = (copy.length * 2 / 3).ceil().clamp(1, copy.length);
    final window = count >= copy.length ? copy : copy.take(cut).toList();
    window.shuffle(Random(seed ?? DateTime.now().millisecondsSinceEpoch));
    return window.take(count).toList();
  }

  /// 写句阶任务:给中文译文,写英文原句。
  static OutputSetSpec buildSentenceSet({
    required List<SentencePair> pairs,
    String title = '作文范文句 · 回译',
  }) {
    final tasks = <OutputTaskSpec>[
      for (final p in pairs)
        OutputTaskSpec(
          tier: OutputTier.sentence,
          type: 'back_translation',
          promptZh: p.zh,
          reference: p.en,
          rubricId: 'back_translation',
          abilityTags: const ['写作', '语法'],
          hint: p.hint,
          wordCount: p.en.split(RegExp(r'\s+')).length,
          source: 'builtin',
          verifyStatus: 'verified',
        ),
    ];
    return OutputSetSpec(
      title: title,
      tier: OutputTier.sentence,
      source: 'builtin',
      section: 'back_translation',
      rubricId: 'back_translation',
      tasks: tasks,
      licenseNote: 'App 内置范文句(人工筛选)',
      verifyStatus: 'verified',
    );
  }

  /// 写段阶任务:默写/仿写范文段,按摘要 rubric 评分。
  static OutputSetSpec buildParagraphSet({
    required List<ParagraphModel> models,
    String title = '范文段落 · 仿写',
  }) {
    final tasks = <OutputTaskSpec>[
      for (final m in models)
        OutputTaskSpec(
          tier: OutputTier.paragraph,
          type: 'paragraph',
          promptZh: m.zh,
          reference: m.en,
          rubricId: 'summary',
          abilityTags: const ['写作', '篇章'],
          hint: m.hint,
          wordCount: m.en.split(RegExp(r'\s+')).length,
          source: 'builtin',
          verifyStatus: 'verified',
        ),
    ];
    return OutputSetSpec(
      title: title,
      tier: OutputTier.paragraph,
      source: 'builtin',
      section: 'writing',
      rubricId: 'summary',
      tasks: tasks,
      licenseNote: 'App 内置范文段落(人工筛选)',
      verifyStatus: 'verified',
    );
  }

  /// 写篇阶任务:给出作文题目 + 要点提示,按写作 rubric 评分。
  static OutputSetSpec buildEssaySet({
    required List<EssayPrompt> prompts,
    String title = '四六级作文题 · 按 rubric 批改',
  }) {
    final tasks = <OutputTaskSpec>[
      for (final p in prompts)
        OutputTaskSpec(
          tier: OutputTier.essay,
          type: 'exam_writing',
          promptZh: '${p.titleZh}\n\n${p.taskZh}\n\n参考要点:\n'
              '${p.points.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}',
          promptEn: p.taskEn,
          rubricId: p.rubricId,
          abilityTags: const ['写作', '篇章'],
          wordCount: p.wordCount,
          source: 'builtin',
          verifyStatus: 'verified',
        ),
    ];
    return OutputSetSpec(
      title: title,
      tier: OutputTier.essay,
      source: 'builtin',
      section: 'writing',
      rubricId: 'cet4_writing',
      tasks: tasks,
      licenseNote: 'App 内置真题风格题目(人写,非官方原题)',
      verifyStatus: 'verified',
    );
  }
}
