import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/learner_model.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/drill_catalog.dart';
import 'package:readflow/services/drill_planner.dart';

/// 练习规划器纯函数回归(v2.9,用户 10/2 第 2 条)。
///
/// 为什么这些必须测:练习系统的三个承诺 —— **按目标个性化**、**有系统规划**、
/// **自适应调节** —— 全都落在这个文件的纯函数里。它们错了不会崩,只会"看起来
/// 有用":题的顺序不对 → 用户觉得没个性化;大纲天数不对 → 进度条永远算不准;
/// 自适应边界写反 → 正确率越高题越少。这些都是线上才发现、且用户会直接骂的病。
///
/// 时间一律**注入**(`now` / `startDate`),不读真实时钟 —— 否则跨零点跑测试会偶发红。
void main() {
  /// 造词条:[daysAgo] 控制"新词"判定,默认 30 天前收的(不算新词)
  Vocabulary w(
    String word, {
    String? translation,
    String? sentence,
    String type = 'word',
    int mastery = 0,
    String? book,
    int daysAgo = 30,
    int id = 0,
  }) =>
      Vocabulary(
        id: id,
        word: word,
        translation: translation ?? '释义-$word',
        originalSentence: sentence,
        wordType: type,
        masteryLevel: mastery,
        sourceBook: book,
        createdAt: DateTime(2026, 1, 1).subtract(Duration(days: daysAgo)),
      );

  // 固定基准时间:2026-06-01 12:00
  final base = DateTime(2026, 6, 1, 12);

  // ═══════════════ 目录:目标分类 ═══════════════

  group('DrillCatalog:目标需求目录', () {
    test('至少 7 个目标,标签唯一、说明不空、每个都有出题偏好', () {
      expect(DrillCatalog.goals.length, greaterThanOrEqualTo(7));
      final labels = DrillCatalog.goals.map((g) => g.label).toSet();
      expect(labels.length, DrillCatalog.goals.length, reason: '标签必须唯一');
      final ids = DrillCatalog.goals.map((g) => g.id).toSet();
      expect(ids.length, DrillCatalog.goals.length, reason: 'id 必须唯一');
      for (final g in DrillCatalog.goals) {
        expect(g.what.trim().isNotEmpty, isTrue, reason: '${g.label} 缺"练什么"说明');
        expect(g.keywords, isNotEmpty, reason: '${g.label} 缺筛选关键词');
        expect(g.wordLen.$1 <= g.wordLen.$2, isTrue);
        expect(g.sentenceLen.$1 <= g.sentenceLen.$2, isTrue);
      }
    });

    test('族类齐全:备考 / 应用 / 学术 / 兴趣各有目标', () {
      for (final tag in GoalTag.values) {
        expect(
          DrillCatalog.goals.any((g) => g.tag == tag),
          isTrue,
          reason: '${tag.label} 族一个目标都没有',
        );
      }
    });

    test('名称归一:兼容历史写法与 id,去重保序', () {
      expect(DrillCatalog.normalize('雅思/托福'), '雅思/托福');
      expect(DrillCatalog.normalize('雅思托福'), '雅思/托福', reason: '缺斜杠也要认');
      expect(DrillCatalog.normalize('ielts'), '雅思/托福', reason: 'id 也要认');
      expect(DrillCatalog.normalize(' 四六级 '), '四六级');
      expect(DrillCatalog.normalize('没见过的目标'), '没见过的目标', reason: '不认识的保持原样');
      expect(
        DrillCatalog.normalizeAll(['四六级', 'cet', '', '考研', '四六级']),
        ['四六级', '考研'],
      );
    });

    test('resolve:未命中任何目标时回落到默认目标,不会返回空', () {
      expect(DrillCatalog.resolve(const []).single.label, '兴趣阅读');
      expect(DrillCatalog.resolve(const ['不存在的']).single.id,
          DrillCatalog.defaultGoalId);
      expect(
        DrillCatalog.resolve(const ['四六级', '雅思/托福']).map((g) => g.label),
        ['四六级', '雅思/托福'],
      );
    });

    test('备考类识别:四六级/考研/雅思托福算备考,生活/兴趣不算', () {
      expect(DrillCatalog.hasExam(const ['四六级']), isTrue);
      expect(DrillCatalog.hasExam(const ['考研']), isTrue);
      expect(DrillCatalog.hasExam(const ['雅思/托福']), isTrue);
      expect(DrillCatalog.hasExam(const ['出国生活']), isFalse);
      expect(DrillCatalog.hasExam(const ['看剧看视频']), isFalse);
      // 多选里只要有一个备考目标就算备考(用户同时在备六级和练口语 → 按备考强度)
      expect(DrillCatalog.hasExam(const ['出国生活', '四六级']), isTrue);
    });

    test('偏好确实有差异:备考偏长词长句,生活偏短词短句', () {
      final cet = DrillCatalog.byLabel('四六级')!;
      final life = DrillCatalog.byLabel('出国生活')!;
      final academic = DrillCatalog.byLabel('学术工作')!;
      expect(cet.wordLenCenter, greaterThan(life.wordLenCenter));
      expect(cet.sentenceLenCenter, greaterThan(life.sentenceLenCenter));
      expect(academic.sentenceLenCenter, greaterThan(life.sentenceLenCenter));
      expect(academic.sentenceLenCenter, greaterThan(cet.sentenceLenCenter));
    });
  });

  // ═══════════════ 组题 ═══════════════

  group('buildQuestions:按目标与水平组题', () {
    // 一批混合材料:长词/短词、长句/短句、短语
    final corpus = <Vocabulary>[
      w('cat', translation: '猫', daysAgo: 30, id: 1),
      w('go', translation: '去', daysAgo: 30, id: 2),
      w('sustainable', translation: '可持续的', daysAgo: 30, id: 3),
      w('phenomenon', translation: '现象', daysAgo: 30, id: 4),
      w('implementation', translation: '实施(名词)', daysAgo: 30, id: 5),
      w('global', translation: '全球的', daysAgo: 30, id: 6),
      w('rent', translation: '租金', daysAgo: 30, id: 7),
      w('hang out', translation: '一起玩', type: 'phrase', daysAgo: 30, id: 8),
    ];

    test('备考目标把长词排在前,生活目标把短词排在前', () {
      final exam = DrillPlanner.buildQuestions(
        mode: 'spelling',
        vocab: corpus,
        goals: const ['考研'],
        limit: 3,
        level: DrillLevel.intermediate,
        now: base,
      );
      final life = DrillPlanner.buildQuestions(
        mode: 'spelling',
        vocab: corpus,
        goals: const ['出国生活'],
        limit: 3,
        level: DrillLevel.intermediate,
        now: base,
      );
      // 考研:前 3 个必须都是长词(长度 ≥ 7)
      expect(exam.map((q) => q.answer.length).reduce((a, b) => a < b ? a : b),
          greaterThanOrEqualTo(7));
      // 出国生活:前 3 个必须都是偏短的词(长度 ≤ 8;该目标的喜好区间是 3~9)
      expect(life.map((q) => q.answer.length).reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(8));
      // 两者不该是同一批(否则"按目标个性化"就是假的)
      expect(exam.map((q) => q.answer).toSet(),
          isNot(equals(life.map((q) => q.answer).toSet())));
      // 生活目标的头名要比备考目标的头名短(方向真的反过来了)
      expect(life.first.answer.length, lessThan(exam.first.answer.length));
    });

    test('水平决定方向:初级先易后难,高阶先难后易', () {
      final beginner = DrillPlanner.buildQuestions(
        mode: 'spelling',
        vocab: corpus,
        goals: const ['四六级'],
        limit: 4,
        level: DrillLevel.beginner,
        now: base,
      );
      final advanced = DrillPlanner.buildQuestions(
        mode: 'spelling',
        vocab: corpus,
        goals: const ['四六级'],
        limit: 4,
        level: DrillLevel.advanced,
        now: base,
      );
      expect(beginner.first.answer.length,
          lessThanOrEqualTo(beginner.last.answer.length));
      expect(advanced.first.answer.length,
          greaterThanOrEqualTo(advanced.last.answer.length));
    });

    test('翻译题:只要带英文原句的,过长句被剔除,题面是中文', () {
      final vocab = <Vocabulary>[
        w('alpha', translation: '第一个', sentence: 'This is a short one.', id: 1),
        w('beta', translation: '第二个', id: 2), // 没原句 → 不能出翻译题
        w('gamma',
            translation: '第三个',
            sentence: List.filled(45, 'word').join(' '),
            id: 3), // 超长 → 剔除
      ];
      final qs = DrillPlanner.buildQuestions(
        mode: 'translation',
        vocab: vocab,
        goals: const ['四六级'],
        limit: 10,
        level: DrillLevel.intermediate,
        now: base,
      );
      expect(qs.length, 1);
      expect(qs.single.answer, 'This is a short one.');
      expect(qs.single.prompt, '第一个');
      // 拼写模式下同一批词能出 3 题(原句不是必需的)
      expect(
        DrillPlanner.buildQuestions(
          mode: 'spelling',
          vocab: vocab,
          goals: const ['四六级'],
          limit: 10,
          level: DrillLevel.intermediate,
          now: base,
        ).length,
        3,
      );
    });

    test('拼写题:整句词条不要、无释义不要、超长答案不要', () {
      final vocab = <Vocabulary>[
        w('sentence-entry', translation: '整句', type: 'sentence', id: 1),
        Vocabulary(id: 2, word: 'no-translation', createdAt: DateTime(2026, 1, 1)),
        w('a' * 30, translation: '超长', id: 3),
        w('valid', translation: '有效的', id: 4),
      ];
      final qs = DrillPlanner.buildQuestions(
        mode: 'spelling',
        vocab: vocab,
        goals: const ['四六级'],
        limit: 10,
        level: DrillLevel.intermediate,
        now: base,
      );
      expect(qs.map((q) => q.answer), ['valid']);
    });

    test('onlyDue:只有 dueIds 里的词能进;要求到期却没到期表时返回空', () {
      final qs = DrillPlanner.buildQuestions(
        mode: 'spelling',
        vocab: corpus,
        goals: const ['四六级'],
        limit: 5,
        level: DrillLevel.intermediate,
        onlyDue: true,
        dueIds: {3, 4},
        now: base,
      );
      expect(qs.map((q) => q.answer).toSet(), {'sustainable', 'phenomenon'});
      // 要求"只练到期"但没有到期信息 → 宁可空,也不拿没到期的词充数
      expect(
        DrillPlanner.buildQuestions(
          mode: 'spelling',
          vocab: corpus,
          goals: const ['四六级'],
          limit: 5,
          level: DrillLevel.intermediate,
          onlyDue: true,
          now: base,
        ),
        isEmpty,
      );
    });

    test('到期与新词加权:同长度下到期的词排前面', () {
      final vocab = <Vocabulary>[
        w('olderword', translation: '旧的', daysAgo: 90, id: 1),
        w('newerword', translation: '新的', daysAgo: 0, id: 2),
      ];
      final qs = DrillPlanner.buildQuestions(
        mode: 'spelling',
        vocab: vocab,
        goals: const ['四六级'],
        limit: 2,
        level: DrillLevel.intermediate,
        dueIds: const {1},
        now: base,
      );
      expect(qs.first.answer, 'olderword', reason: '到期的要排在前面');
      expect(qs.first.due, isTrue);
    });

    test('轮转:同一天同 seed 稳定,换一天换一批', () {
      final vocab = [
        for (var i = 0; i < 12; i++)
          w('wordabcd$i', translation: '第 $i 个', daysAgo: 30, id: i),
      ];
      List<String> pick(int seed) => DrillPlanner.buildQuestions(
            mode: 'spelling',
            vocab: vocab,
            goals: const ['四六级'],
            limit: 3,
            level: DrillLevel.intermediate,
            seed: seed,
            now: base,
          ).map((q) => q.answer).toList();

      expect(pick(20612), pick(20612), reason: '同一天组题必须稳定可复现');
      expect(pick(20612), isNot(equals(pick(20613))), reason: '换一天该换词');
      expect(pick(3).length, 3);
    });

    test('limit 与边界:limit<=0 返回空,候选不足时给多少算多少', () {
      expect(
        DrillPlanner.buildQuestions(
          mode: 'spelling',
          vocab: corpus,
          goals: const [],
          limit: 0,
          level: DrillLevel.intermediate,
          now: base,
        ),
        isEmpty,
      );
      final all = DrillPlanner.buildQuestions(
        mode: 'spelling',
        vocab: corpus,
        goals: const [],
        limit: 99,
        level: DrillLevel.intermediate,
        now: base,
      );
      expect(all.length, corpus.length, reason: '候选不足时不该凭空补');
      expect(
        DrillPlanner.buildQuestions(
          mode: 'spelling',
          vocab: const [],
          goals: const ['四六级'],
          limit: 5,
          level: DrillLevel.intermediate,
          now: base,
        ),
        isEmpty,
        reason: '空词表不能崩',
      );
    });

    test('题目自带提示与出处(界面上要有东西可显示)', () {
      final qs = DrillPlanner.buildQuestions(
        mode: 'spelling',
        vocab: [
          w('hang out', translation: '一起玩', type: 'phrase', book: '老友记', id: 1),
        ],
        goals: const ['看剧看视频'],
        limit: 1,
        level: DrillLevel.beginner,
        now: base,
      );
      final q = qs.single;
      expect(q.hint, contains('首字母 h'));
      expect(q.hint, contains('2 个词'), reason: '短语题要说清几个词');
      expect(q.source, '老友记');
      // 单词题:提示给字母数
      final one = DrillPlanner.buildQuestions(
        mode: 'spelling',
        vocab: [w('apple', translation: '苹果', id: 2)],
        goals: const [],
        limit: 1,
        level: DrillLevel.beginner,
        now: base,
      ).single;
      expect(one.hint, contains('5 个字母'));
    });
  });

  // ═══════════════ 计划大纲 ═══════════════

  group('planOutline:4 周大纲', () {
    test('4 周 = 28 天,每周主题不同,每天都有主题', () {
      final outline = DrillPlanner.planOutline(
        goals: const ['四六级'],
        weeks: 4,
        perDay: 12,
        level: DrillLevel.intermediate,
        startDate: DateTime(2026, 9, 28),
      );
      expect(outline.weeks.length, 4);
      expect(outline.totalDays, 28);
      expect(outline.perDay, 12);
      expect(outline.headline, '四六级 · 每天 12 题 · 进阶');
      final titles = outline.weeks.map((w) => w.title).toList();
      expect(titles.first, startsWith('第 1 周:'));
      expect(titles.last, startsWith('第 4 周:'));
      expect(titles.toSet().length, 4, reason: '每周能力面必须不同,否则不叫"系统规划"');
      for (final week in outline.weeks) {
        expect(week.days.length, 7);
        for (final d in week.days) {
          expect(d.focus.trim().isNotEmpty, isTrue);
        }
      }
      // 每日主题按天轮转,且最后一天是复盘(用户能看出"有节奏")
      expect(outline.weeks.first.days.last.focus, contains('复盘'));
    });

    test('目标影响每周练什么:备考练真题句式,生活练场景句', () {
      final exam = DrillPlanner.planOutline(
        goals: const ['考研'],
        weeks: 1,
        perDay: 10,
        level: DrillLevel.advanced,
      );
      final life = DrillPlanner.planOutline(
        goals: const ['出国生活'],
        weeks: 1,
        perDay: 10,
        level: DrillLevel.beginner,
      );
      expect(exam.weeks.single.days[1].focus, contains('真题'));
      expect(life.weeks.single.days[1].focus, contains('场景'));
      expect(exam.goals, '考研');
      expect(life.goals, '出国生活');
    });

    test('参数越界被夹住:题量 5~30、周数 1~12', () {
      final tiny = DrillPlanner.planOutline(
        goals: const [],
        weeks: 0,
        perDay: 0,
        level: DrillLevel.intermediate,
      );
      expect(tiny.weeks.length, 1);
      expect(tiny.perDay, DrillPlanner.minPerDay);
      final huge = DrillPlanner.planOutline(
        goals: const [],
        weeks: 99,
        perDay: 999,
        level: DrillLevel.intermediate,
      );
      expect(huge.weeks.length, 12);
      expect(huge.perDay, DrillPlanner.maxPerDay);
    });

    test('多目标:标题里带全部目标', () {
      final outline = DrillPlanner.planOutline(
        goals: const ['四六级', '雅思/托福'],
        weeks: 4,
        perDay: 10,
        level: DrillLevel.advanced,
      );
      expect(outline.goals, '四六级 + 雅思/托福');
    });
  });

  // ═══════════════ 自适应 ═══════════════

  group('adaptiveNext:自适应调节', () {
    test('正确率 ≥0.9:加量加难', () {
      final r = DrillPlanner.adaptiveNext(
        accuracy: 95,
        currentPerDay: 10,
        level: DrillLevel.beginner,
      );
      expect(r.perDay, greaterThan(10));
      expect(r.level, DrillLevel.intermediate);
      expect(r.changed, isTrue);
      expect(r.note, contains('95%'));
      expect(r.note, contains('难度'));
    });

    test('0.6~0.9:保持题量与难度', () {
      for (final acc in [60, 72, 85, 89]) {
        final r = DrillPlanner.adaptiveNext(
          accuracy: acc,
          currentPerDay: 12,
          level: DrillLevel.intermediate,
        );
        expect(r.perDay, 12, reason: '正确率 $acc% 不该动题量');
        expect(r.level, DrillLevel.intermediate);
        expect(r.changed, isFalse);
      }
    });

    test('正确率 <0.6:减量降难', () {
      final r = DrillPlanner.adaptiveNext(
        accuracy: 40,
        currentPerDay: 20,
        level: DrillLevel.advanced,
      );
      expect(r.perDay, lessThan(20));
      expect(r.level, DrillLevel.intermediate);
      expect(r.changed, isTrue);
    });

    test('阈值边界:0.9 与 0.6 归到"加量/保持"一侧', () {
      expect(
        DrillPlanner.adaptiveNext(accuracy: 90, currentPerDay: 10).perDay,
        greaterThan(10),
      );
      final atSixty = DrillPlanner.adaptiveNext(accuracy: 60, currentPerDay: 10);
      expect(atSixty.perDay, 10);
      final atFiftyNine =
          DrillPlanner.adaptiveNext(accuracy: 59, currentPerDay: 10);
      expect(atFiftyNine.perDay, lessThan(10));
    });

    test('正确率口径统一:0.95 与 95 等价,不同口径不会算出天差地别的结果', () {
      final frac = DrillPlanner.adaptiveNext(accuracy: 1, currentPerDay: 10);
      final pct = DrillPlanner.adaptiveNext(accuracy: 100, currentPerDay: 10);
      expect(frac.perDay, pct.perDay);
      expect(frac.level, pct.level);
      // 0 = 一次没练过 / 没数据 → 保持原题量,不该降难度
      expect(
        DrillPlanner.adaptiveNext(accuracy: 0, currentPerDay: 10).perDay,
        10,
        reason: '0 是"没数据",不是"全错"',
      );
      // 而 0.4(40%)是真的答得不好 → 要降
      expect(
        DrillPlanner.adaptiveNext(accuracy: 40, currentPerDay: 10).perDay,
        lessThan(10),
      );
    });

    test('题量被夹在 5~30,且加满/降到底时 level 不再越界', () {
      final maxed = DrillPlanner.adaptiveNext(
        accuracy: 100,
        currentPerDay: 30,
        level: DrillLevel.advanced,
      );
      expect(maxed.perDay, DrillPlanner.maxPerDay);
      expect(maxed.level, DrillLevel.advanced, reason: '已经是最高档,不能越界');
      expect(maxed.changed, isFalse);
      final bottom = DrillPlanner.adaptiveNext(
        accuracy: 10,
        currentPerDay: 5,
        level: DrillLevel.beginner,
      );
      expect(bottom.perDay, DrillPlanner.minPerDay);
      expect(bottom.level, DrillLevel.beginner);
      expect(bottom.changed, isFalse);
    });
  });

  // ═══════════════ 进度 ═══════════════

  group('progressOf:计划进度', () {
    final start = DateTime(2026, 6, 1); // 与 base 同一天

    test('第 1 天:今日未达标、剩余 28 天、完成率 0', () {
      final p = DrillPlanner.progressOf(
        {'total': 4, 'accuracy': 0.5, 'todayTotal': 4, 'streak': 1},
        perDay: 10,
        startDate: start,
        now: base,
      );
      expect(p.totalDays, 28);
      expect(p.dayIndex, 1);
      expect(p.todayTotal, 4);
      expect(p.todayDone, isFalse);
      expect(p.remainDays, 28);
      expect(p.doneDays, 0, reason: '4 题不足 1 天的量');
      expect(p.rate, 0);
      expect(p.streak, 1);
    });

    test('累计达标:完成天数 = 累计题数 / 每日题量(上限 28 天)', () {
      final p = DrillPlanner.progressOf(
        {'total': 45, 'accuracy': 0.82, 'todayTotal': 10, 'streak': 3},
        perDay: 10,
        startDate: start,
        now: DateTime(2026, 6, 3, 9), // 第 3 天
      );
      expect(p.dayIndex, 3);
      expect(p.doneDays, 4, reason: '45 题 ÷ 10 = 4 天');
      expect(p.todayDone, isTrue);
      expect(p.remainDays, 26);
      expect(p.accuracy, closeTo(0.82, 1e-9));
      // 完成率 = 4/28
      expect(p.rate, closeTo(4 / 28, 1e-9));
      // 累计题数远超总容量时,完成天数不能超过总天数
      final overflow = DrillPlanner.progressOf(
        {'total': 99999},
        perDay: 1,
        startDate: start,
        now: base,
      );
      expect(overflow.doneDays, 28);
      expect(overflow.rate, 1.0);
    });

    test('传了 days(真实达标日数)时以它为准', () {
      final p = DrillPlanner.progressOf(
        {'total': 200, 'todayTotal': 10, 'streak': 6, 'days': 7},
        perDay: 10,
        startDate: start,
        now: DateTime(2026, 6, 8),
      );
      expect(p.doneDays, 7, reason: '有真实达标日数就不该用题量估算');
      expect(p.dayIndex, 8);
      expect(p.remainDays, 21);
    });

    test('没有计划起始日 / 缺键:不崩,数字合理', () {
      final p = DrillPlanner.progressOf(const {}, perDay: 10);
      expect(p.dayIndex, 0);
      expect(p.totalDays, 28);
      expect(p.todayTotal, 0);
      expect(p.total, 0);
      expect(p.accuracy, 0);
      expect(p.todayDone, isFalse);
      expect(p.summary, contains('今天已练 0 题'));
      // 计划还没开始的未来起始日:第 1 天,剩余 = 全部
      final future = DrillPlanner.progressOf(
        const {'todayTotal': 3},
        perDay: 10,
        startDate: DateTime(2026, 6, 10),
        now: base,
      );
      expect(future.dayIndex, 1);
      expect(future.remainDays, 28);
    });

    test('weeks 影响总天数与完成率;perDay<=0 不除零', () {
      final p = DrillPlanner.progressOf(
        {'total': 20},
        perDay: 0,
        weeks: 2,
        startDate: start,
        now: base,
      );
      expect(p.totalDays, 14);
      expect(p.perDay, 10, reason: 'perDay<=0 时回落到 10,不能除零');
      expect(p.doneDays, 2);
    });

    test('summary 文案带主要数字(用户要"一眼看出有方向")', () {
      final p = DrillPlanner.progressOf(
        {'total': 120, 'correct': 98, 'accuracy': 0.82, 'todayTotal': 10},
        perDay: 10,
        startDate: start,
        now: DateTime(2026, 6, 3),
      );
      expect(p.summary, contains('第 3/28 天'));
      expect(p.summary, contains('今天已练 10 题'));
      expect(p.summary, contains('82%'));
    });
  });

  // ═══════════════ 判分 ═══════════════

  group('判分与用时口径', () {
    test('拼写忽略大小写与首尾空白,空输入算错', () {
      expect(DrillPlanner.judgeSpelling('Apple', 'apple'), isTrue);
      expect(DrillPlanner.judgeSpelling('  apple  ', 'apple'), isTrue);
      expect(DrillPlanner.judgeSpelling('aple', 'apple'), isFalse);
      expect(DrillPlanner.judgeSpelling('', 'apple'), isFalse);
      expect(DrillPlanner.judgeSpelling('   ', 'apple'), isFalse);
    });

    test('翻译按词重合率 ≥0.5 判分,并回报命中/总数', () {
      const answer = 'I would like to book a room for two nights';
      // 命中 7/10(输入里的每个词都在标准答案里)
      final (ok, hit, ref) =
          DrillPlanner.judgeTranslation('I would like to book a room', answer);
      expect(ref, 10);
      expect(hit, 7);
      expect(ok, isTrue);
      // 命中 2/10 → 错
      final (ok2, hit2, _) =
          DrillPlanner.judgeTranslation('I want the room', answer);
      expect(hit2, 2);
      expect(ok2, isFalse);
      // 标点与大小写不影响
      final (ok3, hit3, _) = DrillPlanner.judgeTranslation(
          'i WOULD like, to book a room.', answer);
      expect(hit3, 7);
      expect(ok3, isTrue);
      // 空输入:0/10,不是 NaN
      final (ok4, hit4, ref4) = DrillPlanner.judgeTranslation('', answer);
      expect(ok4, isFalse);
      expect(hit4, 0);
      expect(ref4, 10);
      // 标准答案为空(脏数据):不算对,也不崩
      expect(DrillPlanner.judgeTranslation('anything', '').$1, isFalse);
      // 恰好一半 → 判对(≥0.5)
      const four = 'a b c d';
      expect(DrillPlanner.judgeTranslation('a b', four).$1, isTrue);
    });

    test('用时提示按每题秒数分档', () {
      expect(DrillPlanner.paceHint(seconds: 60, total: 10), contains('很熟'));
      expect(DrillPlanner.paceHint(seconds: 150, total: 10), contains('正常节奏'));
      expect(DrillPlanner.paceHint(seconds: 400, total: 10), contains('偏慢'));
      expect(DrillPlanner.paceHint(seconds: 900, total: 10), contains('卡得比较久'));
      expect(DrillPlanner.paceHint(seconds: 0, total: 0), contains('没记到用时'));
    });

    test('小结文案按正确率给不同口径', () {
      expect(DrillPlanner.summaryLine(correct: 10, total: 10), contains('偏简单'));
      expect(DrillPlanner.summaryLine(correct: 8, total: 10), contains('明天'));
      expect(DrillPlanner.summaryLine(correct: 5, total: 10), contains('降一点'));
      expect(DrillPlanner.summaryLine(correct: 2, total: 10), contains('复习'));
      expect(DrillPlanner.summaryLine(correct: 0, total: 0), contains('没有作答'));
    });

    test('最近正确率趋势:按时间倒序的日志算,旧的在前,最多 7 根', () {
      final logs = [
        for (var i = 0; i < 9; i++)
          {'total': 10, 'correct': i}, // 最新在前(库里的顺序)
      ];
      final rates = DrillPlanner.recentRates(logs);
      expect(rates.length, 7);
      expect(rates.last, closeTo(0.0, 1e-9), reason: '旧的在前(画柱状图从左到右)');
      expect(rates.first, closeTo(0.6, 1e-9), reason: '最新一次在最右');
      // 题数为 0 的日志跳过,不产生 NaN
      expect(
        DrillPlanner.recentRates([
          {'total': 0, 'correct': 0},
          {'total': 4, 'correct': 1},
        ]),
        [closeTo(0.25, 1e-9)],
      );
      expect(DrillPlanner.recentRates(const []), isEmpty);
    });

    test('日期范围文案', () {
      expect(DrillPlanner.dateRange(DateTime(2026, 9, 28), 4), '9/28 - 10/25');
      expect(DrillPlanner.dateRange(DateTime(2026, 9, 28), 1), '9/28 - 10/4');
    });

    test('statsFrom:从日志算"练过几天/今天几题/累计与趋势",坏行不崩', () {
      final logs = [
        {'total': 10, 'correct': 8, 'seconds': 120, 'created_at': '2026-06-01T09:00:00'},
        {'total': 10, 'correct': 5, 'seconds': 180, 'created_at': '2026-06-01T20:00:00'},
        {'total': 6, 'correct': 6, 'seconds': 60, 'created_at': '2026-05-31T09:00:00'},
        {'total': 0, 'correct': 0, 'seconds': 0, 'created_at': '坏时间'},
      ];
      final s = DrillPlanner.statsFrom(logs, now: base);
      expect(s.days, 2, reason: '自然日去重:6/1 有两条算一天');
      expect(s.todayTotal, 20);
      expect(s.total, 26);
      expect(s.correct, 19);
      expect(s.seconds, 360);
      expect(s.accuracy, closeTo(19 / 26, 1e-9));
      expect(s.hasData, isTrue);
      expect(s.firstAt, DateTime(2026, 5, 31, 9));
      expect(s.lastAt, DateTime(2026, 6, 1, 20));
      expect(s.rates.length, 3, reason: 'total=0 的那条不进趋势');
      expect(s.rates.last, closeTo(0.8, 1e-9), reason: '最新一次是 8/10(列表末尾)');
      expect(s.rates.first, closeTo(1.0, 1e-9), reason: '更早那次是 6/6');
      expect(s.durationLabel, '6 分钟');
      // 空日志
      final empty = DrillPlanner.statsFrom(const [], now: base);
      expect(empty.hasData, isFalse);
      expect(empty.days, 0);
      expect(empty.accuracy, 0);
      expect(empty.firstAt, isNull);
      expect(DrillLogStats.empty.total, 0);
      // 只有秒数时的档位
      expect(
        DrillPlanner.statsFrom(
          [
            {'total': 1, 'correct': 1, 'seconds': 4000, 'created_at': '2026-06-01T09:00:00'},
          ],
          now: base,
        ).durationLabel,
        '1 小时 6 分',
      );
    });

    test('progressOf 接 logStats:练过的天数直接进完成天数', () {
      final stats = DrillPlanner.statsFrom([
        {'total': 10, 'correct': 9, 'seconds': 100, 'created_at': '2026-06-01T09:00:00'},
        {'total': 10, 'correct': 9, 'seconds': 100, 'created_at': '2026-05-31T09:00:00'},
      ], now: base);
      final p = DrillPlanner.progressOf(
        const {},
        perDay: 10,
        startDate: DateTime(2026, 5, 31),
        now: base,
        logStats: stats,
      );
      expect(p.doneDays, 2);
      expect(p.dayIndex, 2);
      expect(p.todayTotal, 10);
      expect(p.todayDone, isTrue);
      expect(p.accuracy, closeTo(0.9, 1e-9));
      expect(p.total, 20);
    });
  });

  // ═══════════════ 水平推算 ═══════════════

  group('levelOf:由软件内数据推算水平', () {
    test('没有数据 → intermediate(不羞辱新人也不高估)', () {
      expect(DrillPlanner.levelOf(LearnerModel()), DrillLevel.intermediate);
    });

    test('词汇量分界:3500 / 6500', () {
      DrillLevel withVocab(int n, {String? cefr}) => DrillPlanner.levelOf(
            LearnerModel(
              vocabEstimate: ProfileField<int>(
                value: n,
                source: ProfileSource.test,
                confidence: 0.9,
              ),
              cefr: cefr == null
                  ? null
                  : ProfileField<String>(
                      value: cefr,
                      source: ProfileSource.test,
                      confidence: 0.9,
                    ),
            ),
          );
      expect(withVocab(2000), DrillLevel.beginner);
      expect(withVocab(3499), DrillLevel.beginner);
      expect(withVocab(3500), DrillLevel.intermediate);
      expect(withVocab(6000), DrillLevel.intermediate);
      expect(withVocab(6500), DrillLevel.advanced);
      expect(withVocab(12000), DrillLevel.advanced);
    });

    test('CEFR 优先于词汇量(测量出来的能力档最贴)', () {
      final model = LearnerModel(
        vocabEstimate: ProfileField<int>(
          value: 9000,
          source: ProfileSource.test,
          confidence: 0.9,
        ),
        cefr: ProfileField<String>(
          value: 'A2',
          source: ProfileSource.test,
          confidence: 0.9,
        ),
      );
      expect(DrillPlanner.levelOf(model), DrillLevel.beginner);
      // 兼容 "B2+" / 小写写法
      expect(
        DrillPlanner.levelOf(LearnerModel(
          cefr: ProfileField<String>(
            value: 'b2+',
            source: ProfileSource.self,
            confidence: 0.5,
          ),
        )),
        DrillLevel.advanced,
      );
      // 认不出的 CEFR 字符串 → 回落到词汇量判断,而不是崩
      expect(
        DrillPlanner.levelOf(LearnerModel(
          vocabEstimate: ProfileField<int>(
            value: 9000,
            source: ProfileSource.self,
            confidence: 0.5,
          ),
          cefr: ProfileField<String>(
            value: '母语级',
            source: ProfileSource.self,
            confidence: 0.5,
          ),
        )),
        DrillLevel.advanced,
      );
    });

    test('extras 里的推断词汇量也能用(还没测过但系统推断出来了)', () {
      expect(
        DrillPlanner.levelOf(LearnerModel(extras: const {'vocab_inferred': 8000})),
        DrillLevel.advanced,
      );
      expect(
        DrillPlanner.levelOf(LearnerModel(extras: const {'vocab_inferred': 1000})),
        DrillLevel.beginner,
      );
      // 脏类型不能崩
      expect(
        DrillPlanner.levelOf(LearnerModel(extras: const {'vocab_inferred': 'x'})),
        DrillLevel.intermediate,
      );
    });

    test('describeLevel 带档位与依据;建议题量按时间与目标给', () {
      final model = LearnerModel(
        vocabEstimate: ProfileField<int>(
          value: 8000,
          source: ProfileSource.test,
          confidence: 0.9,
        ),
      );
      expect(DrillPlanner.describeLevel(model), contains('高阶'));
      expect(DrillPlanner.describeLevel(model), contains('8000'));
      // 15 分钟 ≈ 45 题 → 夹到 30;备考再乘 1.15 也还是 30
      expect(
        DrillPlanner.suggestPerDay(goals: const ['四六级'], level: DrillLevel.advanced),
        DrillPlanner.maxPerDay,
      );
      // 5 分钟 ≈ 15 题,初级 × 0.8 = 12
      expect(
        DrillPlanner.suggestPerDay(
          goals: const ['出国生活'],
          level: DrillLevel.beginner,
          dailyMinutes: 5,
        ),
        12,
      );
      // 未填每日时间 → 按 15 分钟
      expect(
        DrillPlanner.suggestPerDay(goals: const [], level: DrillLevel.intermediate),
        30,
      );
      expect(DrillPlanner.knownWords(model), greaterThan(0));
    });
  });

  // ═══════════════ 计划备注编解码 ═══════════════

  group('encodePlanNote / decodePlanNote', () {
    test('往返一致:模式、目标、难度、用户备注全部保留', () {
      const note = DrillPlanNote(
        planMode: DrillPlanNote.planAuto,
        goals: ['四六级', '雅思/托福'],
        level: DrillLevel.advanced,
        userNote: '六级已过,主攻听力',
      );
      final raw = encodePlanNote(note);
      expect(raw, startsWith('mode:auto|'));
      expect(raw, contains('goals:四六级,雅思/托福'));
      expect(raw, contains('level:advanced'));
      final back = decodePlanNote(raw);
      expect(back.planMode, DrillPlanNote.planAuto);
      expect(back.goals, ['四六级', '雅思/托福']);
      expect(back.level, DrillLevel.advanced);
      expect(back.userNote, '六级已过,主攻听力');
    });

    test('没有用户备注时不写 note 段;目标为空时段在但不炸', () {
      final raw = encodePlanNote(const DrillPlanNote(
        planMode: DrillPlanNote.planDaily,
        goals: [],
        level: DrillLevel.beginner,
      ));
      expect(raw, 'mode:daily|goals:|level:beginner');
      final back = decodePlanNote(raw);
      expect(back.planMode, DrillPlanNote.planDaily);
      expect(back.goals, isEmpty);
      expect(back.level, DrillLevel.beginner);
      expect(back.userNote, '');
    });

    test('脏数据容错:空串 / 老格式自由文本 / 非法模式 / 备注带竖线', () {
      final empty = decodePlanNote(null);
      expect(empty.planMode, DrillPlanNote.planPlan);
      expect(empty.level, DrillLevel.intermediate);
      // 老版本可能往 level_note 里写过自由文本 → 整段当备注保留,信息不丢
      final legacy = decodePlanNote('备考六级,词汇量偏弱');
      expect(legacy.userNote, '备考六级,词汇量偏弱');
      expect(legacy.planMode, DrillPlanNote.planPlan);
      // 模式非法 → 回落 plan,但其它字段照读
      final bad = decodePlanNote('mode:xyz|goals:考研|level:C1');
      expect(bad.planMode, DrillPlanNote.planPlan);
      expect(bad.goals, ['考研']);
      expect(bad.level, DrillLevel.advanced, reason: 'C1 属于高阶');
      // level 段里的值认不出 → intermediate
      expect(decodePlanNote('mode:plan|level:未知').level, DrillLevel.intermediate);
      // 用户备注里的竖线被替换,结构不坏
      final piped = encodePlanNote(const DrillPlanNote(
        planMode: DrillPlanNote.planPlan,
        goals: ['职场商务'],
        level: DrillLevel.intermediate,
        userNote: '生活|职场都要',
      ));
      expect(piped.split('|').length, 4, reason: '备注里的竖线不能多切出一段');
      expect(decodePlanNote(piped).userNote, '生活,职场都要');
    });

    test('三种模式的中文名与说明都在(界面直接读,不许各页手写)', () {
      expect(DrillPlanNote.planModes.length, 3);
      expect(DrillPlanNote.labelOf(DrillPlanNote.planPlan), '跟计划走');      expect(DrillPlanNote.labelOf(DrillPlanNote.planDaily), '今日练习包');
      expect(DrillPlanNote.labelOf(DrillPlanNote.planAuto), '自适应');
      expect(DrillPlanNote.labelOf('垃圾值'), '跟计划走');
      for (final m in DrillPlanNote.planModes) {
        expect(DrillPlanNote.describeOf(m.$1).trim().isNotEmpty, isTrue);
      }
      expect(DrillPlanNote.isValidMode('plan'), isTrue);
      expect(DrillPlanNote.isValidMode('planx'), isFalse);
    });
  });
}
