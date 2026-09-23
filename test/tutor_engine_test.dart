import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/learner_model.dart';
import 'package:readflow/services/tutor_engine.dart';

/// 导师诊断引擎回归测试。
///
/// 这一层是 2.0 的"专业性"所在:每条结论都必须**引用具体数字**,
/// 所以测试重点不是"有没有输出",而是:
/// 1. 特定数据形态 → 必须产出对应结论(id 稳定);
/// 2. 每条结论的 evidence 里必须出现关键数字(否则就又退回"保持节奏、多读多听");
/// 3. 优先级排序与任务卡时长符合设计(先清复习账、没基线先测、总量贴预算)。
void main() {
  final now = DateTime(2026, 9, 22, 12);

  LearnerModel model({
    int? vocab,
    ProfileSource source = ProfileSource.test,
    int? dailyMinutes,
    String goal = '读懂原版书',
  }) =>
      LearnerModel(
        vocabEstimate: vocab == null
            ? null
            : ProfileField<int>(value: vocab, source: source, confidence: 0.9),
        dailyMinutes: dailyMinutes == null
            ? null
            : ProfileField<int>(
                value: dailyMinutes, source: ProfileSource.self),
        goal: ProfileField<String>(value: goal, source: ProfileSource.self),
      );

  LearnerSnapshot snap({
    LearnerModel? m,
    int totalVocab = 0,
    int masteryNew = 0,
    int masteryLearning = 0,
    int masteryMastered = 0,
    int vocabAddedLast7Days = 0,
    int dueReviewCount = 0,
    int overdueCount = 0,
    int trackedReviewCount = 0,
    int readingSessions30d = 0,
    int readingWords30d = 0,
    int readingMinutes30d = 0,
    double? avgWpm,
    int materialsStarted = 0,
    int materialsFinished = 0,
    List<RecentMaterial> recentMaterials = const [],
    Map<String, double> quizAccuracy = const {},
    List<ErrorTagStat> errorTags = const [],
    int streakDays = 0,
    int activeDays30d = 0,
  }) =>
      LearnerSnapshot(
        model: m ?? model(vocab: 5000),
        now: now,
        totalVocab: totalVocab,
        masteryNew: masteryNew,
        masteryLearning: masteryLearning,
        masteryMastered: masteryMastered,
        vocabAddedLast7Days: vocabAddedLast7Days,
        dueReviewCount: dueReviewCount,
        overdueCount: overdueCount,
        trackedReviewCount: trackedReviewCount,
        readingSessions30d: readingSessions30d,
        readingWords30d: readingWords30d,
        readingMinutes30d: readingMinutes30d,
        avgWpm: avgWpm,
        materialsStarted: materialsStarted,
        materialsFinished: materialsFinished,
        recentMaterials: recentMaterials,
        quizAccuracy: quizAccuracy,
        errorTags: errorTags,
        streakDays: streakDays,
        activeDays30d: activeDays30d,
      );

  List<String> ids(List<TutorFinding> f) => f.map((e) => e.id).toList();
  TutorFinding byId(List<TutorFinding> f, String id) =>
      f.firstWhere((e) => e.id == id);

  group('没基线 → 必须先测', () {
    test('完全空白:产出 no_baseline 且排在最前(action)', () {
      final f = TutorEngine.diagnose(snap(m: model()));
      expect(f.first.id, 'no_baseline');
      expect(f.first.severity, FindingSeverity.action);
      expect(f.first.jump, TutorAction.placementTest);
      // 一点数据都没有时,要承认"难度只能靠猜"
      expect(f.first.evidence, contains('只能靠猜'));
    });

    test('有生词本但没测过 → 明确区分"收藏了多少"与"会多少"', () {
      final f = TutorEngine.diagnose(snap(m: model(), totalVocab: 120));
      final finding = byId(f, 'no_baseline');
      expect(finding.evidence, contains('120'));
      expect(finding.evidence, contains('不等于'));
    });

    test('自报水平不算测量基线(自评普遍偏差)', () {
      final f = TutorEngine.diagnose(
        snap(m: model(vocab: 8000, source: ProfileSource.self)),
      );
      expect(ids(f), contains('no_baseline'));
    });

    test('测过之后不再提示(即使词汇量很小)', () {
      final f = TutorEngine.diagnose(snap(m: model(vocab: 900)));
      expect(ids(f), isNot(contains('no_baseline')));
    });
  });

  group('复习堆积', () {
    test('过期 60 → warn,证据含两个数字', () {
      final f = TutorEngine.diagnose(
        snap(dueReviewCount: 80, overdueCount: 60, totalVocab: 200,
            trackedReviewCount: 200),
      );
      final finding = byId(f, 'review_backlog');
      expect(finding.severity, FindingSeverity.warn);
      expect(finding.evidence, contains('80'));
      expect(finding.evidence, contains('60'));
      expect(finding.jump, TutorAction.review);
    });

    test('过期 250 → action(先清账,别加新词)', () {
      final f = TutorEngine.diagnose(
        snap(dueReviewCount: 300, overdueCount: 250, trackedReviewCount: 300),
      );
      final finding = byId(f, 'review_backlog');
      expect(finding.severity, FindingSeverity.action);
      expect(finding.action, contains('先清账'));
    });

    test('过期 10(未到阈值)→ 不产生堆积结论(避免天天唠叨)', () {
      final f = TutorEngine.diagnose(snap(dueReviewCount: 10, overdueCount: 10));
      expect(ids(f), isNot(contains('review_backlog')));
    });
  });

  group('只输入不输出 / 生词本变收藏夹', () {
    test('读了 5000 词但没有任何输出记录 → input_only', () {
      final f = TutorEngine.diagnose(snap(
        readingSessions30d: 8,
        readingWords30d: 5000,
        readingMinutes30d: 120,
        quizAccuracy: const {'vocab_placement': 0.8},
      ));
      final finding = byId(f, 'input_only');
      expect(finding.evidence, contains('5000'));
      expect(finding.jump, TutorAction.writing);
    });

    test('有写译/回译记录就不再提示(只认非词汇量类测验)', () {
      final f = TutorEngine.diagnose(snap(
        readingWords30d: 5000,
        quizAccuracy: const {'back_translation': 0.7},
      ));
      expect(ids(f), isNot(contains('input_only')));
    });

    test('收了 50+ 词却零复习记录 → no_review_system', () {
      final f = TutorEngine.diagnose(snap(totalVocab: 120, trackedReviewCount: 0));
      expect(byId(f, 'no_review_system').title, contains('收藏夹'));
    });
  });

  group('材料难度', () {
    test('覆盖率 86% → 偏难,证据给出每 100 词生词数', () {
      final f = TutorEngine.diagnose(snap(
        recentMaterials: const [
          RecentMaterial(id: 1, title: '经济学人精读', kind: 'news', coverage: 0.86),
        ],
      ));
      final finding = byId(f, 'material_too_hard');
      expect(finding.title, contains('经济学人精读'));
      expect(finding.evidence, contains('86%'));
      expect(finding.evidence, contains('14'), reason: '要给出每 100 词 14 个生词');
    });

    test('覆盖率 99.5% → 偏易(info,不制造焦虑)', () {
      final f = TutorEngine.diagnose(snap(
        recentMaterials: const [
          RecentMaterial(id: 2, title: '儿童读物', kind: 'book', coverage: 0.995),
        ],
      ));
      final finding = byId(f, 'material_too_easy');
      expect(finding.severity, FindingSeverity.info);
      expect(finding.evidence, contains('99.5%'));
    });

    test('覆盖率 96% → 两头都不报(舒适区)', () {
      final f = TutorEngine.diagnose(snap(
        recentMaterials: const [
          RecentMaterial(id: 3, title: '正好', kind: 'book', coverage: 0.96),
        ],
      ));
      expect(ids(f), isNot(contains('material_too_hard')));
      expect(ids(f), isNot(contains('material_too_easy')));
    });
  });

  group('错误档案 / 理解率 / 速度 / 断层', () {
    test('同类错误 ≥3 次 → repeating_errors,取次数最多的两类', () {
      final f = TutorEngine.diagnose(snap(errorTags: const [
        ErrorTagStat(tag: '时态', count: 7),
        ErrorTagStat(tag: '冠词', count: 4),
        ErrorTagStat(tag: '介词', count: 2), // 未达阈值,不计入
        ErrorTagStat(tag: '主谓一致', count: 9, status: 'fixed'), // 已改好,不计入
      ]));
      final finding = byId(f, 'repeating_errors');
      expect(finding.title, contains('时态'));
      expect(finding.evidence, contains('时态(7 次)'));
      expect(finding.evidence, contains('冠词(4 次)'));
      expect(finding.evidence, isNot(contains('主谓一致')));
    });

    test('读后测验正确率 30% → 提示材料偏难', () {
      final f = TutorEngine.diagnose(
        snap(quizAccuracy: const {'reading_comprehension': 0.3}),
      );
      expect(byId(f, 'low_comprehension').evidence, contains('30%'));
    });

    test('实测速度 90 词/分 → info 提示逐词翻译', () {
      final f = TutorEngine.diagnose(snap(avgWpm: 90));
      expect(byId(f, 'slow_reading').title, contains('90'));
    });

    test('近 30 天只活跃 1 天 → long_break 且建议"别定大目标"', () {
      final f = TutorEngine.diagnose(snap(activeDays30d: 1, streakDays: 0));
      final finding = byId(f, 'long_break');
      expect(finding.action, contains('别定大目标'));
    });
  });

  group('健康状态', () {
    test('数据一切正常 → 给"可以加难度"的下一步(而不是空列表)', () {
      final f = TutorEngine.diagnose(snap(
        m: model(vocab: 6000, dailyMinutes: 40),
        totalVocab: 300,
        masteryMastered: 120,
        trackedReviewCount: 300,
        readingSessions30d: 12,
        readingWords30d: 9000,
        readingMinutes30d: 200,
        avgWpm: 190,
        materialsStarted: 6,
        materialsFinished: 3,
        quizAccuracy: const {'reading_comprehension': 0.8, 'back_translation': 0.7},
        activeDays30d: 20,
        streakDays: 6,
      ));
      expect(ids(f), contains('healthy_next_step'));
      expect(f.every((e) => e.severity == FindingSeverity.info), isTrue);
    });

    test('排序:action 在 warn 前,warn 在 info 前', () {
      final f = TutorEngine.diagnose(snap(
        m: model(), // 没基线 → action
        dueReviewCount: 60,
        overdueCount: 60, // warn
        recentMaterials: const [
          RecentMaterial(id: 9, title: '太简单', kind: 'book', coverage: 0.995),
        ], // info
      ));
      final severities = f.map((e) => e.severity).toList();
      final firstInfo = severities.indexOf(FindingSeverity.info);
      final lastAction = severities.lastIndexOf(FindingSeverity.action);
      expect(lastAction, lessThan(firstInfo));
    });
  });

  group('任务卡', () {
    test('没基线 + 有堆积 + 有在读材料 + 没输出 → 4 条,且复习排第一', () {
      final s = snap(
        m: model(dailyMinutes: 40),
        dueReviewCount: 40,
        overdueCount: 40,
        trackedReviewCount: 40,
        totalVocab: 100,
        readingWords30d: 2000,
        readingMinutes30d: 60,
        readingSessions30d: 5,
        recentMaterials: const [
          RecentMaterial(id: 7, title: '小王子', kind: 'book', coverage: 0.96, percent: 35),
        ],
      );
      final tasks = TutorEngine.planTasks(s);
      expect(tasks.length, 4);
      expect(tasks.first.kind, 'review');
      expect(ids(TutorEngine.diagnose(s)), contains('no_baseline'));
      expect(tasks.map((t) => t.kind), containsAll(['placement', 'read', 'write']));
      final read = tasks.firstWhere((t) => t.kind == 'read');
      expect(read.title, contains('小王子'));
      expect(read.jump, TutorAction.continueReading);
      expect(read.jumpArg, '7');
      // 每条任务都必须说明来自哪条诊断(不允许"凭空派活")
      expect(tasks.every((t) => t.reason.isNotEmpty), isTrue);
    });

    test('每日预算 10 分钟 → 任务时长不会离谱地超', () {
      final s = snap(
        m: model(dailyMinutes: 10),
        dueReviewCount: 200,
        overdueCount: 200,
        trackedReviewCount: 200,
        readingWords30d: 3000,
      );
      final tasks = TutorEngine.planTasks(s);
      expect(tasks.length, lessThanOrEqualTo(4));
      final total = tasks.fold<int>(0, (a, t) => a + t.targetMinutes);
      // 复习被限流到 30 个词(3 分钟)+ 阅读(5)+ 写作(5)+ 测试(5)= 18
      expect(total, lessThanOrEqualTo(30));
    });

    test('健康 + 无到期 + 无在读 → 给"从材料中心挑一份"(而不是空任务)', () {
      final tasks = TutorEngine.planTasks(snap(
        m: model(vocab: 5000, dailyMinutes: 30),
        readingWords30d: 1000,
        quizAccuracy: const {'back_translation': 0.6},
      ));
      expect(tasks.map((t) => t.kind), contains('read'));
      final read = tasks.firstWhere((t) => t.kind == 'read');
      expect(read.jump, TutorAction.materialCenter);
    });
  });

  group('给 AI 的证据包', () {
    test('包含关键数字与本地结论,并要求模型不要编造', () {
      final s = snap(
        m: model(vocab: 4200, dailyMinutes: 35),
        totalVocab: 180,
        masteryMastered: 60,
        dueReviewCount: 25,
        overdueCount: 25,
        trackedReviewCount: 180,
        readingWords30d: 4200,
        readingMinutes30d: 90,
        recentMaterials: const [
          RecentMaterial(id: 1, title: 'BBC 6 Minute', kind: 'podcast', coverage: 0.94, percent: 60),
        ],
        errorTags: const [ErrorTagStat(tag: '介词', count: 5)],
      );
      final prompt = TutorEngine.evidencePrompt(s, TutorEngine.diagnose(s));
      expect(prompt, contains('4200'));
      expect(prompt, contains('180'));
      expect(prompt, contains('BBC 6 Minute'));
      expect(prompt, contains('介词×5'));
      expect(prompt, contains('不要编造新结论'));
      expect(prompt, contains('目的 读懂原版书'));
    });

    test('画像为空时也说清楚(而不是留空让模型猜)', () {
      final prompt = TutorEngine.evidencePrompt(
        snap(m: LearnerModel()),
        TutorEngine.diagnose(snap(m: LearnerModel())),
      );
      expect(prompt, contains('画像:未填写'));
    });
  });

  group('顶部摘要', () {
    test('把关键状态压成一行', () {
      final line = TutorEngine.summaryLine(snap(
        m: model(vocab: 5200),
        totalVocab: 210,
        masteryMastered: 88,
        dueReviewCount: 12,
        readingMinutes30d: 130,
        activeDays30d: 14,
      ));
      expect(line, contains('5200'));
      expect(line, contains('210'));
      expect(line, contains('待复习 12'));
      expect(line, contains('130 分钟'));
      expect(line, contains('14 天'));
    });

    test('未测词汇量时明确说"还没有测过"', () {
      expect(
        TutorEngine.summaryLine(snap(m: model())),
        contains('还没有测过词汇量'),
      );
    });
  });
}
