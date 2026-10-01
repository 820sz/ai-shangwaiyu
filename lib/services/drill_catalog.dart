/// 练习目标需求目录(v2.9,用户 10/2 第 2 条)。
///
/// 用户原话:"目标需求:四六级/雅思/托福/出国/学术工作/其他,等等哈,你自行想一下
/// 怎么分类,**支持多选**…… 词汇练习、翻译练习这些,都要有系统规划、进度追踪"。
///
/// ## 为什么要有这个文件(单一事实源)
/// "目标"这个词在本 App 里已经出现过三次(访谈自报 / 学习者模型 `goals` /
/// 找材料的目标),如果练习系统再各写一份列表,就会出现"设置页叫·雅思托福·
/// 练习页叫·雅思/托福·"这种对不上的情况 —— 用户勾了目标却没生效,
/// 而根因只是两处字符串不一样。所以:
/// - **标签的写法只在这里定义一次**(`DrillCatalog.goals`),别处一律引用
///   [DrillGoal.label],不要自己手写中文;
/// - **"练什么"的差异也在这里定义一次**([DrillGoal.wordLen] / [sentenceLen] /
///   [keywords])。备考类偏"长词 + 长难句",生活类偏"高频短语 + 短句",
///   这个差异必须能被 [DrillPlanner.buildQuestions] 直接读出来排序,
///   否则"按目标个性化"就只是 UI 上多了一个 chip 而已。
library;

/// 目标需求的族类(界面上按族分组显示,避免 8 个 chip 平铺成一堵墙)
enum GoalTag {
  /// 应试备考(四六级 / 考研 / 雅思托福)
  exam('备考'),

  /// 生活与职场应用(出国生活 / 职场商务)
  practical('应用'),

  /// 学术与工作阅读写作(文献 / 报告 / 论文)
  academic('学术'),

  /// 兴趣驱动(原版书 / 美剧播客)
  interest('兴趣');

  const GoalTag(this.label);

  final String label;
}

/// 一个目标需求:标签 + "练什么" + 出题偏好
class DrillGoal {
  /// 稳定 id(英文,入库与解析用;中文标签改名不影响历史数据)
  final String id;

  /// 中文标签(界面显示、存进学习者模型 `goals` 的就是它)
  final String label;

  /// 一句"这个目标到底练什么"(点 chip 时显示,让用户知道勾了会变什么)
  final String what;

  /// 族类(界面分组)
  final GoalTag tag;

  /// 是否应试备考类:备考类题量更多、提示更少、优先长词长句
  final bool exam;

  /// 偏好的单词长度区间(字符数)。备考偏长词,生活口语偏短词
  final (int, int) wordLen;

  /// 偏好的句子长度区间(词数)
  final (int, int) sentenceLen;

  /// 给筛选用的关键词(小写子串匹配词条/释义/原句):
  /// 命中即认为"这条材料属于该目标",排序时加权
  final List<String> keywords;

  const DrillGoal({
    required this.id,
    required this.label,
    required this.what,
    required this.tag,
    required this.exam,
    required this.wordLen,
    required this.sentenceLen,
    required this.keywords,
  });

  /// 词长偏好中心值(排序时按"离中心多远"扣分)
  double get wordLenCenter => (wordLen.$1 + wordLen.$2) / 2;

  /// 句长偏好中心值(词数)
  double get sentenceLenCenter => (sentenceLen.$1 + sentenceLen.$2) / 2;
}

/// 目标需求目录
class DrillCatalog {
  DrillCatalog._();

  /// 全部目标(界面顺序即此处顺序:先备考,再应用,后兴趣)
  static const List<DrillGoal> goals = [
    DrillGoal(
      id: 'cet',
      label: '四六级',
      what: '练考试高频词与固定搭配的拼写,翻译按真题句式(短句为主、语法点密集)',
      tag: GoalTag.exam,
      exam: true,
      wordLen: (6, 13),
      sentenceLen: (8, 20),
      keywords: [
        'campus', 'student', 'study', 'education', 'college', 'university',
        'tradition', 'culture', 'society', 'economy', 'environment',
        'technology', 'develop', 'improve', 'benefit', 'challenge',
        '课程', '校园', '社会', '文化', '经济', '环境', '科技', '发展',
        '传统', '教育', '大学', '学生', '考试',
      ],
    ),
    DrillGoal(
      id: 'kaoyan',
      label: '考研',
      what: '练长难句里的核心词与学术固定搭配,句子偏长、重逻辑连接词',
      tag: GoalTag.exam,
      exam: true,
      wordLen: (7, 15),
      sentenceLen: (12, 32),
      keywords: [
        'however', 'moreover', 'therefore', 'consequently', 'nevertheless',
        'phenomenon', 'significant', 'substantial', 'mechanism', 'hypothesis',
        'analysis', 'conclude', 'evidence', 'assumption',
        '然而', '因此', '现象', '显著', '机制', '假设', '分析', '证据',
        '论证', '逻辑', '推断',
      ],
    ),
    DrillGoal(
      id: 'ielts',
      label: '雅思/托福',
      what: '练学术词汇与同义替换,句子按议论文句式(因果、让步、对比)',
      tag: GoalTag.exam,
      exam: true,
      wordLen: (7, 16),
      sentenceLen: (14, 36),
      keywords: [
        'research', 'survey', 'data', 'evidence', 'global', 'decline',
        'increase', 'proportion', 'population', 'urban', 'resource',
        'alternative', 'sustainable', 'consume', 'rate',
        '研究', '调查', '数据', '证据', '全球', '下降', '上升', '比例',
        '人口', '城市', '资源', '可持续', '消耗', '趋势',
      ],
    ),
    DrillGoal(
      id: 'life_abroad',
      label: '出国生活',
      what: '练生活高频短语与短句(租房、点餐、问路、看医生),说得出口为先',
      tag: GoalTag.practical,
      exam: false,
      wordLen: (3, 9),
      sentenceLen: (4, 12),
      keywords: [
        'rent', 'bill', 'ticket', 'menu', 'order', 'appointment', 'address',
        'luggage', 'pharmacy', 'laundry', 'deposit', 'landlord',
        '预约', '账单', '房租', '菜单', '点餐', '地址', '行李', '药房',
        '排队', '超市', '刷卡', '打车',
      ],
    ),
    DrillGoal(
      id: 'business',
      label: '职场商务',
      what: '练邮件与会议里的动词短语,句子按"请对方做某事"的商务句式',
      tag: GoalTag.practical,
      exam: false,
      wordLen: (4, 12),
      sentenceLen: (6, 18),
      keywords: [
        'meeting', 'schedule', 'deadline', 'budget', 'client', 'proposal',
        'confirm', 'attach', 'follow up', 'report', 'contract', 'invoice',
        '会议', '排期', '截止', '预算', '客户', '方案', '确认', '附件',
        '跟进', '报告', '合同', '报价',
      ],
    ),
    DrillGoal(
      id: 'academic',
      label: '学术工作',
      what: '练论文与文献里的名词化表达与精确动词,句子长、信息密度高',
      tag: GoalTag.academic,
      exam: false,
      wordLen: (8, 17),
      sentenceLen: (16, 40),
      keywords: [
        'study', 'method', 'result', 'framework', 'theory', 'empirical',
        'correlation', 'indicate', 'demonstrate', 'implication', 'paradigm',
        'quantitative', 'literature',
        '方法', '结果', '框架', '理论', '实证', '相关', '表明', '论证',
        '启示', '范式', '定量', '文献',
      ],
    ),
    DrillGoal(
      id: 'reading',
      label: '兴趣阅读',
      what: '练原版书里的高频实词与地道搭配,句子按叙述句(能读懂为主)',
      tag: GoalTag.interest,
      exam: false,
      wordLen: (4, 12),
      sentenceLen: (8, 22),
      keywords: [
        'said', 'thought', 'felt', 'looked', 'story', 'chapter', 'novel',
        'character', 'journey', 'memory', 'wonder', 'silence',
        '说', '想', '感觉', '看', '故事', '章节', '小说', '人物', '旅程',
        '记忆', '沉默',
      ],
    ),
    DrillGoal(
      id: 'screen',
      label: '看剧看视频',
      what: '练口语化短语与俚语短句(能听懂、能接话),句短、语气词多',
      tag: GoalTag.interest,
      exam: false,
      wordLen: (3, 10),
      sentenceLen: (3, 11),
      keywords: [
        'gonna', 'wanna', 'gotta', 'kind of', 'sort of', 'stuff', 'guys',
        'hang out', 'figure out', 'come on', 'whatever', 'awesome',
        '口语', '俚语', '别急', '糟糕', '天哪', '算了', '一起', '搞定',
      ],
    ),
  ];

  /// 默认目标(用户一个都没勾时的兜底:兴趣阅读最安全 —— 备考导向会平白
  /// 提高难度,对"只想读点东西"的人是劝退)
  static const String defaultGoalId = 'reading';

  /// 按 id 找(找不到返回 null)
  static DrillGoal? byId(String id) {
    final key = id.trim().toLowerCase();
    for (final g in goals) {
      if (g.id == key) return g;
    }
    return null;
  }

  /// 按标签找(库里存的是标签)
  static DrillGoal? byLabel(String label) {
    final key = label.trim();
    if (key.isEmpty) return null;
    for (final g in goals) {
      if (g.label == key) return g;
    }
    // 兼容历史写法(v2.8 的输出页用过「雅思/托福」「工作/学术」等)
    for (final g in goals) {
      if (g.label.replaceAll('/', '') == key.replaceAll('/', '')) return g;
    }
    return null;
  }

  /// 把任意来源的目标字符串(标签或 id)归一成目录里的标准标签
  static String normalize(String raw) {
    final g = byLabel(raw) ?? byId(raw);
    return g?.label ?? raw.trim();
  }

  /// 归一一批(去重、保序、丢掉空串)
  static List<String> normalizeAll(Iterable<String> raw) {
    final out = <String>[];
    for (final r in raw) {
      final n = normalize(r);
      if (n.isEmpty || out.contains(n)) continue;
      out.add(n);
    }
    return out;
  }

  /// 命中一批目标(未命中过任何目标时回落到默认目标):
  /// 组题与计划大纲都走它,保证"没勾目标也能练,但不会把备考难度硬塞给你"
  static List<DrillGoal> resolve(List<String> labels) {
    final out = <DrillGoal>[];
    for (final l in normalizeAll(labels)) {
      final g = byLabel(l);
      if (g != null && !out.contains(g)) out.add(g);
    }
    if (out.isEmpty) {
      final fallback = byId(defaultGoalId);
      if (fallback != null) out.add(fallback);
    }
    return out;
  }

  /// 这批目标里有没有应试备考类(决定题量、提示强弱、先易后难还是直接上强度)
  static bool hasExam(List<String> labels) =>
      resolve(labels).any((g) => g.exam);

  /// 一句话概括"这批目标练什么"(界面文案,避免每页自己拼)
  static String describe(List<String> labels) {
    final gs = resolve(labels);
    return gs.map((g) => g.label).join(' + ');
  }

  /// 所有关键词(小写去重),供组题时做一次性的文本匹配
  static Set<String> get allKeywords {
    final out = <String>{};
    for (final g in goals) {
      out.addAll(g.keywords);
    }
    return out;
  }
}
