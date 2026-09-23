import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/weekly_report.dart';

/// 每周报告(纯函数)测试。
///
/// 这一层的价值全在"结论文案是否诚实":
/// - **每条亮点/建议必须带数字或材料名** —— 项目纪律是"无证据不下结论",
///   一条"继续保持"混进报告就等于把报告的可信度整体拉低;
/// - **没数据不能编**:正确率缺失时不能出现 0%/100%,没学习时不能
///   把 0 包装成鼓励;
/// - **周期口径**:本实现采用**滚动 7 天**(`[now-6天 00:00, now 当天 23:59:59.999]`,
///   含今天),不是自然周(周一~周日)。理由:自然周会让周一早上的用户
///   看到"本周无数据",而他昨天刚学过。边界测试见「周期边界」组。
void main() {
  // 基准时刻:2026-09-21(周一)14:30
  final now = DateTime(2026, 9, 21, 14, 30);

  /// 便捷构造:只填关心的字段
  WeeklyInputs inputs({
    Set<DateTime>? activeDates,
    int readingSessions = 0,
    int wordsRead = 0,
    int minutesRead = 0,
    int newWords = 0,
    int reviewsDone = 0,
    int reviewsLapsed = 0,
    int materialsFinished = 0,
    List<UnfinishedMaterial> unfinishedMaterials = const [],
    double? quizAccuracy,
    List<ErrorTagBrief> activeErrors = const [],
    Map<String, int> reviewBuckets = const {},
    List<int> forecast = const [],
    int? dailyMinutes,
  }) =>
      WeeklyInputs(
        activeDates: activeDates ?? const {},
        readingSessions: readingSessions,
        wordsRead: wordsRead,
        minutesRead: minutesRead,
        newWords: newWords,
        reviewsDone: reviewsDone,
        reviewsLapsed: reviewsLapsed,
        materialsFinished: materialsFinished,
        unfinishedMaterials: unfinishedMaterials,
        quizAccuracy: quizAccuracy,
        activeErrors: activeErrors,
        reviewBuckets: reviewBuckets,
        forecast: forecast,
        dailyMinutes: dailyMinutes,
      );

  /// 文案里是否出现了某个数字(按"数字本身"匹配,避免 7 命中 70)
  Matcher containsNumber(int n) => predicate<String>(
        (s) => RegExp('(?<![0-9])$n(?![0-9])').hasMatch(s),
        '文案包含数字 $n',
      );

  group('日期区间(滚动 7 天,含今天)', () {
    test('from = now-6 天的 00:00,to = now 当天 23:59:59.999', () {
      final r = WeeklyReportBuilder.build(now: now, inputs: inputs());
      expect(r.from, DateTime(2026, 9, 15));
      expect(r.to, DateTime(2026, 9, 21, 23, 59, 59, 999));
      expect(r.to.difference(r.from).inDays, 6); // 含首尾共 7 天
    });

    test('当天 00:05 与 23:55 得到同一个窗口(按自然日切,不按时刻)', () {
      final early = WeeklyReportBuilder.build(
        now: DateTime(2026, 9, 21, 0, 5),
        inputs: inputs(),
      );
      final late = WeeklyReportBuilder.build(
        now: DateTime(2026, 9, 21, 23, 55),
        inputs: inputs(),
      );
      expect(early.from, late.from);
      expect(early.to, late.to);
    });

    test('跨月边界:10-02 的窗口回退到 09-26', () {
      final r = WeeklyReportBuilder.build(
        now: DateTime(2026, 10, 2, 9),
        inputs: inputs(),
      );
      expect(r.from, DateTime(2026, 9, 26));
      expect(r.to.day, 2);
      expect(r.to.month, 10);
    });

    test('activeDays 只算窗口内的天:窗口外的活跃日不计入', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(activeDates: {
          DateTime(2026, 9, 15, 8), // 窗口第一天:算
          DateTime(2026, 9, 21, 23), // 今天:算
          DateTime(2026, 9, 14, 22), // 昨天窗口外:不算
          DateTime(2026, 8, 30), // 上个月:不算
        }),
      );
      expect(r.activeDays, 2);
    });

    test('同一天的多条记录只算一天', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(activeDates: {
          DateTime(2026, 9, 20, 8),
          DateTime(2026, 9, 20, 12, 30),
          DateTime(2026, 9, 20, 21),
        }),
      );
      expect(r.activeDays, 1);
    });
  });

  group('空数据:不能编造结论', () {
    final empty = WeeklyReportBuilder.build(now: now, inputs: inputs());

    test('isActive=false,activeDays/词数/分钟均为 0', () {
      expect(empty.isActive, isFalse);
      expect(empty.activeDays, 0);
      expect(empty.wordsRead, 0);
      expect(empty.minutesRead, 0);
      expect(empty.topErrors, isEmpty);
    });

    test('正确率缺失就是 null —— 不能伪造 0% 或 100%', () {
      expect(empty.quizAccuracy, isNull);
      final text = empty.highlights.join('|');
      expect(text.contains('正确率'), isFalse);
      expect(text.contains('0%'), isFalse);
      expect(text.contains('100%'), isFalse);
    });

    test('亮点明确说"还没有学习记录",而不是把 0 当成绩', () {
      expect(empty.highlights, hasLength(1));
      expect(empty.highlights.first, contains('还没有学习记录'));
      // 只出现在"还没学习"这一条,不掺"继续保持""加油"之类的空话
      final text = empty.highlights.join('|');
      expect(text.contains('继续保持'), isFalse);
      expect(text.contains('加油'), isFalse);
    });

    test('空数据也给出带数字的下周目标(默认 20 分钟/天)', () {
      expect(empty.suggestions, hasLength(1));
      // 20 分钟/天 × 7 天 = 140 分钟;20×30 = 600 词/天 ⇒ 4200 词
      expect(empty.suggestions.first, containsNumber(140));
      expect(empty.suggestions.first, containsNumber(20));
      expect(empty.suggestions.first, contains('读'));
    });
  });

  group('亮点:每条都带数字', () {
    test('阅读量 + 速度:词数/分钟/次数/词每分钟全都出现', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(
          activeDates: {DateTime(2026, 9, 20), DateTime(2026, 9, 21)},
          readingSessions: 8,
          wordsRead: 4200,
          minutesRead: 90,
        ),
      );
      final joined = r.highlights.join('\n');
      expect(joined, containsNumber(4200));
      expect(joined, containsNumber(90));
      expect(joined, containsNumber(8));
      expect(joined, contains('47')); // 4200/90 = 46.7 → 47 词/分
      expect(r.activeDays, 2);
    });

    test('正确率 78% 原样呈现,不四舍五入成 80', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(quizAccuracy: 0.78, readingSessions: 3, wordsRead: 300, minutesRead: 10),
      );
      expect(r.highlights.join('|'), contains('78%'));
    });

    test('新收词 + 复习词同一句里都报出来', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(newWords: 42, reviewsDone: 60),
      );
      final h = r.highlights.firstWhere((s) => s.contains('新收'));
      expect(h, containsNumber(42));
      expect(h, containsNumber(60));
    });

    test('有词数没会话(旧数据)也能出亮点,但不编次数', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(wordsRead: 1500),
      );
      final h = r.highlights.firstWhere((s) => s.contains('读了'));
      expect(h, containsNumber(1500));
      expect(h.contains('次'), isFalse); // 没有会话就不编"读了几次"
    });

    test('复习全对才算亮点;有过"不认识"就不生成这条', () {
      final clean = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(reviewsDone: 30, reviewsLapsed: 0),
      );
      expect(clean.highlights.join('|'), contains('复习的 30 个词里没有一次"不认识"'));

      final lapsed = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(reviewsDone: 30, reviewsLapsed: 5),
      );
      expect(lapsed.highlights.join('|'), isNot(contains('没有一次')));
    });

    test('亮点最多 4 条,且优先报产值高的(阅读量排在活跃天数前)', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(
          activeDates: {DateTime(2026, 9, 20), DateTime(2026, 9, 21)},
          readingSessions: 5,
          wordsRead: 2000,
          minutesRead: 40,
          newWords: 10,
          reviewsDone: 25,
          materialsFinished: 2,
          quizAccuracy: 0.9,
        ),
      );
      expect(r.highlights.length, lessThanOrEqualTo(4));
      expect(r.highlights.first, contains('读了'));
      expect(r.highlights.join('|'), contains('读完 2 篇材料'));
      expect(r.highlights.join('|'), contains('90%'));
    });
  });

  group('topErrors:按次数排序、带次数、最多 3 类', () {
    test('排序与格式化(次数 DESC)', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(activeErrors: const [
          ErrorTagBrief(tag: '冠词', count: 2),
          ErrorTagBrief(tag: '时态', count: 7),
          ErrorTagBrief(tag: '介词', count: 4),
        ]),
      );
      expect(r.topErrors, ['时态(7 次)', '介词(4 次)', '冠词(2 次)']);
    });

    test('次数相同按最近发生时间排前;时间缺失排最后', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(activeErrors: [
          const ErrorTagBrief(tag: '拼写', count: 3, lastAt: null),
          ErrorTagBrief(tag: '词汇', count: 3, lastAt: DateTime(2026, 9, 21)),
          ErrorTagBrief(tag: '介词', count: 3, lastAt: DateTime(2026, 9, 18)),
        ]),
      );
      expect(r.topErrors, ['词汇(3 次)', '介词(3 次)', '拼写(3 次)']);
    });

    test('超过 3 类只取前 3', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(activeErrors: const [
          ErrorTagBrief(tag: 'A', count: 9),
          ErrorTagBrief(tag: 'B', count: 8),
          ErrorTagBrief(tag: 'C', count: 7),
          ErrorTagBrief(tag: 'D', count: 6),
        ]),
      );
      expect(r.topErrors, hasLength(3));
      expect(r.topErrors.join('|'), isNot(contains('D(')));
    });
  });

  group('建议:具体、可执行、带数字或材料名', () {
    test('有过期词 → 先清债,并给出容量换算', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(
          reviewsDone: 12,
          reviewBuckets: const {'overdue': 60, 'today': 5, 'week': 10, 'later': 3},
          dailyMinutes: 20,
        ),
      );
      final first = r.suggestions.first;
      expect(first, contains('先清 60 个过期词'));
      expect(first, containsNumber(20)); // 每天 20 分钟
      expect(first, containsNumber(150)); // 20*60/8 = 150 个容量
    });

    test('高频错误 → 点名 tag 与次数', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(activeErrors: const [
          ErrorTagBrief(tag: '时态', count: 7),
          ErrorTagBrief(tag: '介词', count: 3),
        ]),
      );
      expect(r.suggestions.join('|'), contains('优先处理「时态」(7 次)'));
      expect(r.suggestions.join('|'), containsNumber(2)); // 待处理 2 类
    });

    test('没读完的材料 → 报名 + 百分比 + 剩余词数', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(unfinishedMaterials: const [
          UnfinishedMaterial(title: 'The Economist', percent: 62, wordCount: 1000),
        ]),
      );
      final s = r.suggestions.join('|');
      expect(s, contains('The Economist'));
      expect(s, contains('62%'));
      expect(s, containsNumber(380)); // 1000 * 38%
    });

    test('正确率 55% → 给"重读再测"的目标 80%;缺失时不谈正确率', () {
      final low = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(quizAccuracy: 0.55, readingSessions: 2, wordsRead: 400, minutesRead: 20),
      );
      expect(low.suggestions.join('|'), contains('55%'));
      expect(low.suggestions.join('|'), contains('80%'));

      final none = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(readingSessions: 2, wordsRead: 400, minutesRead: 20),
      );
      expect(none.suggestions.join('|'), contains('这周没做读后测验'));
      expect(none.suggestions.join('|'), isNot(contains('正确率')));
    });

    test('最多 3 条,按优先级取(过期债 > 错误档案 > 未读完)', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(
          readingSessions: 4,
          wordsRead: 900,
          minutesRead: 30,
          reviewsDone: 5,
          unfinishedMaterials: const [
            UnfinishedMaterial(title: '小王子', percent: 80, wordCount: 500),
          ],
          activeErrors: const [ErrorTagBrief(tag: '拼写', count: 4)],
          reviewBuckets: const {'overdue': 30},
        ),
      );
      expect(r.suggestions, hasLength(3));
      expect(r.suggestions[0], contains('过期词'));
      expect(r.suggestions[1], contains('拼写'));
      expect(r.suggestions[2], contains('小王子'));
    });

    test('每条建议都有数字或材料名(全字段齐备时逐条校验)', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(
          readingSessions: 3,
          wordsRead: 800,
          minutesRead: 25,
          newWords: 12,
          reviewsDone: 6,
          materialsFinished: 1,
          unfinishedMaterials: const [
            UnfinishedMaterial(title: '国家地理', percent: 40, wordCount: 1200),
          ],
          quizAccuracy: 0.6,
          activeErrors: const [ErrorTagBrief(tag: '时态', count: 5)],
          reviewBuckets: const {'overdue': 12},
          dailyMinutes: 15,
        ),
      );
      for (final s in r.suggestions) {
        final hasNumber = RegExp(r'[0-9]').hasMatch(s);
        expect(hasNumber, isTrue, reason: '建议必须带数字:$s');
      }
      for (final s in r.highlights) {
        expect(RegExp(r'[0-9]').hasMatch(s), isTrue, reason: '亮点必须带数字:$s');
      }
    });
  });

  group('未来负荷 forecast', () {
    test('逐日数组转成 index 字符串键(index 0 = 今天)', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(forecast: const [3, 0, 5, 1, 0, 0, 2]),
      );
      expect(r.forecast, {'0': 3, '1': 0, '2': 5, '3': 1, '4': 0, '5': 0, '6': 2});
    });

    test('没有逐日预测时,至少给出今天的数(用过期量兜底)', () {
      final r = WeeklyReportBuilder.build(
        now: now,
        inputs: inputs(reviewBuckets: const {'overdue': 9}),
      );
      expect(r.forecast, {'0': 9});
    });
  });
}
