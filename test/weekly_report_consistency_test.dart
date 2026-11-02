import 'package:flutter_test/flutter_test.dart';
import 'package:readflow/services/weekly_report.dart';

/// E1-9「周报与助理共用数据层」一致性测试（纯函数，不联网 / 不碰 SQLite）。
///
/// 为什么需要这个测试：周报和助理都能看到"输出练习次数 / rubric 均分"，
/// 两边各写一份解析代码时，最容易出现的不是崩溃，而是**数字差一两个**：
/// - 一边 `(x as num?)?.toInt() ?? 0`，另一边 `int.tryParse` 遇到字符串就变 0；
/// - 一边把 `avgScore == null` 兜底成 0，于是"没写"被显示成"0 分"；
/// - 一边四舍五入、另一边保留小数，"较上周"的差值就对不上。
///
/// 两边唯一的取数入口都是 `OutputFeedback.outputSnapshot(...)`；本测试把
/// **同一份快照 Map** 同时按"助理读法"与"周报读法"解析，断言结果逐字段相同，
/// 并把 null / 脏类型 / 排序这些细节钉死。
void main() {
  /// 助理快照侧的读法（`LearnerSnapshotLoader` 把 outputSnapshot 映射成
  /// `LearnerSnapshot.outputAttempts30d/outputAvgScore/outputLastAt` 时用的规则）。
  /// 故意写成一个**独立实现**，这样周报侧一旦改了口径，本测试立刻失败。
  ({int attempts, double? avgScore, DateTime? lastAt}) assistantRead(
    Map<String, Object?> raw,
  ) {
    final attemptsRaw = raw['attempts'];
    final attempts =
        attemptsRaw is int ? attemptsRaw : (attemptsRaw is num ? attemptsRaw.toInt() : 0);
    final avgRaw = raw['avgScore'];
    final avgScore = avgRaw is num ? avgRaw.toDouble() : null;
    final lastRaw = '${raw['lastAt'] ?? ''}'.trim();
    final lastAt = lastRaw.isEmpty ? null : DateTime.tryParse(lastRaw);
    return (attempts: attempts, avgScore: avgScore, lastAt: lastAt);
  }

  Map<String, Object?> snapshot({
    Object? attempts = 5,
    Object? avgScore = 72.4,
    Object? lastAt = '2026-10-31T09:30:00.000',
    Object? dimensions = const {'language': 68.0, 'content': 80.5},
    Object? errorTags = const {'时态': 3, '词汇': 1},
  }) =>
      {
        'days': 7,
        'attempts': attempts,
        'avgScore': avgScore,
        'lastAt': lastAt,
        'byType': const {'writing': 2, 'translation': 3},
        'recentScores': const [60.0, 72.4],
        'dimensionAvg': dimensions,
        'topErrorTags': errorTags,
      };

  WeeklyReport reportFor(WeeklyOutputBlock block, {DateTime? now}) {
    final at = now ?? DateTime(2026, 11, 2, 12);
    return WeeklyReportBuilder.build(
      now: at,
      inputs: WeeklyInputs(
        activeDates: {DateTime(2026, 11, 1)},
        outputAttempts: block.attempts,
        outputAvgScore: block.avgScore,
        outputPrevAvgScore: block.prevAvgScore,
        outputDimensions: block.dimensions,
        outputErrorTags: block.errorTags,
      ),
    );
  }

  group('周报输出块与助理快照同口径', () {
    test('同一份 outputSnapshot：attempts / avgScore / lastAt 逐字段一致', () {
      final raw = snapshot();
      final block = WeeklyOutputBlock.fromSnapshots(current: raw);
      final assistant = assistantRead(raw);

      expect(block.attempts, assistant.attempts);
      expect(block.attempts, 5);
      expect(block.avgScore, assistant.avgScore);
      // 保留原始精度：谁都不许在这里 round（展示层才 round）
      expect(block.avgScore, 72.4);
      expect(block.lastAt, assistant.lastAt);
    });

    test('avgScore 为 null 时两边都是 null（没作答 ≠ 0 分）', () {
      final raw = snapshot(attempts: 0, avgScore: null, errorTags: const {});
      final block = WeeklyOutputBlock.fromSnapshots(current: raw);
      final assistant = assistantRead(raw);
      expect(block.attempts, 0);
      expect(assistant.attempts, 0);
      expect(block.avgScore, isNull);
      expect(assistant.avgScore, isNull);

      // 周报文案：必须说"本周没有输出练习"，不能出现 0 分
      final report = reportFor(block);
      expect(report.outputLines, ['本周没有输出练习(写作 / 翻译 / 回译)']);
      expect(report.outputLines.join(), isNot(contains('0%')));
    });

    test('有练习但没有可评分作答：次数照报、均分缺席（不编分）', () {
      final block = WeeklyOutputBlock.fromSnapshots(
        current: snapshot(
          attempts: 3,
          avgScore: null,
          dimensions: const {},
          errorTags: const {},
        ),
      );
      expect(block.attempts, 3);
      expect(block.avgScore, isNull);
      final report = reportFor(block);
      expect(report.outputLines.first, '完成 3 次输出练习');
      expect(report.outputLines.join(), isNot(contains('均分')));
    });

    test('周报里显示的数字 == 快照原始数字（周报不改写服务端口径）', () {
      final block = WeeklyOutputBlock.fromSnapshots(
        current: snapshot(attempts: 7, avgScore: 81.4),
      );
      final report = reportFor(block);
      expect(report.outputAttempts, 7);
      expect(report.outputAvgScore, 81.4);
      expect(report.outputLines.first, contains('完成 7 次输出练习'));
      // 展示四舍五入只发生在文案层
      expect(report.outputLines.first, contains('rubric 均分 81%'));
    });

    test('环比只读上一份快照的 avgScore；上一周没数据就不显示"较上周"', () {
      final withPrev = WeeklyOutputBlock.fromSnapshots(
        current: snapshot(avgScore: 81.0),
        previous: snapshot(avgScore: 70.0),
      );
      expect(withPrev.prevAvgScore, 70.0);
      expect(reportFor(withPrev).outputLines.first, contains('较上周 +11%'));

      final noPrev = WeeklyOutputBlock.fromSnapshots(
        current: snapshot(avgScore: 81.0),
        previous: snapshot(avgScore: null),
      );
      expect(noPrev.prevAvgScore, isNull);
      expect(reportFor(noPrev).outputLines.first, isNot(contains('较上周')));
    });

    test('窗口只是参数：7 天 / 30 天的快照用同一解析器，算法不因窗口变化', () {
      // 两个窗口只在"原始数字"上不同；解析逻辑完全相同（同一次调用同一函数）
      final week = WeeklyOutputBlock.fromSnapshots(
        current: snapshot(attempts: 4, avgScore: 70.0),
      );
      final month = WeeklyOutputBlock.fromSnapshots(
        current: snapshot(attempts: 23, avgScore: 70.0),
      );
      expect(week.attempts, 4);
      expect(month.attempts, 23);
      expect(week.avgScore, month.avgScore); // 均分口径与窗口无关
    });

    test('错误热点排序与周报正文一致（次数降序、同次数按名）', () {
      final block = WeeklyOutputBlock.fromSnapshots(
        current: snapshot(
          errorTags: const {'词汇': 1, '时态': 3, '冠词': 3},
        ),
      );
      expect(block.errorTags.map((e) => e.tag).toList(), ['冠词', '时态', '词汇']);
      final report = reportFor(block);
      expect(
        report.outputErrorTags,
        ['冠词(3 次)', '时态(3 次)', '词汇(1 次)'],
      );
    });
  });

  group('脏数据 / 边界（周报不能因为一条坏记录出错或造假）', () {
    test('字符串数字照常解析（历史备份/测试数据里存过字符串）', () {
      final block = WeeklyOutputBlock.fromSnapshots(
        current: snapshot(attempts: '5', avgScore: '72.5'),
      );
      expect(block.attempts, 5);
      expect(block.avgScore, 72.5);
    });

    test('维度 map 里 null/非数字/空 key 被跳过，不崩', () {
      final block = WeeklyOutputBlock.fromSnapshots(
        current: snapshot(
          dimensions: const {
            'language': 60.0,
            'content': null,
            'organization': 'bad',
            '': 50.0,
          },
        ),
      );
      expect(block.dimensions, {'language': 60.0});
    });

    test('错误热点 count<=0 不上榜；lastAt 脏值退化成 null', () {
      final block = WeeklyOutputBlock.fromSnapshots(
        current: snapshot(
          errorTags: const {'时态': 0, '冠词': -2, '介词': 1},
          lastAt: 'not-a-date',
        ),
      );
      expect(block.errorTags.map((e) => e.tag), ['介词']);
      expect(block.lastAt, isNull);
    });

    test('快照缺键（服务降级返回空 map）→ 全默认值，周报照常生成', () {
      final block = WeeklyOutputBlock.fromSnapshots(current: const {});
      expect(block.attempts, 0);
      expect(block.avgScore, isNull);
      expect(block.dimensions, isEmpty);
      expect(block.errorTags, isEmpty);
      final report = reportFor(block);
      expect(report.outputLines, isNotEmpty);
    });

    test('公开解析口径本身可被单测（助理侧也读这两个函数就保证不漂移）', () {
      expect(outputSnapshotInt('bad'), 0);
      expect(outputSnapshotInt(3.9), 3);
      expect(outputSnapshotDouble(null), isNull);
      expect(outputSnapshotDouble(''), isNull);
      expect(outputSnapshotDouble('null'), isNull);
      expect(outputSnapshotDouble('80.25'), 80.25);
    });
  });
}
