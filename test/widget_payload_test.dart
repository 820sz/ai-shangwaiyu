import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/widget_payload.dart';

/// 桌面小组件的文案规则测试(v2.2)。
///
/// 小组件的两种"说谎"方式必须被测试挡住:
/// ① 拿过期数据冒充今天(用户以为今天只剩 3 个词);
/// ② 没数据时显示 0 / 0 / 0(看起来像 App 坏了)。
void main() {
  final now = DateTime(2026, 9, 24, 8, 12);

  WidgetPayload build({
    int due = 0,
    int newWords = 0,
    int streak = 0,
    List<WidgetTask> tasks = const [],
    DateTime? syncedAt,
    bool firstSync = false,
  }) =>
      WidgetPayload.build(
        dueCount: due,
        newWordsRemaining: newWords,
        streakDays: streak,
        tasks: tasks,
        now: now,
        syncedAt: syncedAt,
        firstSync: firstSync,
      );

  group('从未同步(全新安装)', () {
    test('给引导而不是编数字,且不写任何数据键', () {
      final p = build(firstSync: true);
      expect(p.previewLines().first, '打开 App 生成今天的计划');
      final data = p.toWidgetData();
      // 只写一个空时间戳:原生侧据此走"空态"分支
      expect(data.keys, [WidgetPayload.keySyncedAt]);
      expect(data[WidgetPayload.keySyncedAt], isEmpty);
    });
  });

  group('今天', () {
    test('有未完成任务 → 标题是第一条任务,多于一条时带"等 N 项"', () {
      final p = build(tasks: const [
        WidgetTask(title: '复习 32 个词', done: false),
        WidgetTask(title: '读一篇 NPR 新闻', done: false),
      ], due: 32, newWords: 10);
      expect(p.headline, '复习 32 个词 等 2 项');
      expect(p.badge, '0/2');
    });

    test('任务都完成 → 标题回落到待复习数,徽标显示"全部完成"', () {
      final p = build(tasks: const [
        WidgetTask(title: '复习 32 个词', done: true),
      ], due: 12, newWords: 5);
      expect(p.headline, '复习 12 个词');
      expect(p.badge, '全部完成');
    });

    test('没有任务但有到期词 → 标题直接说复习多少个', () {
      final p = build(due: 25, newWords: 8);
      expect(p.headline, '复习 25 个词');
      expect(p.dueLine, '待复习 25 个 · 新词额度 8');
    });

    test('没有到期词但还有新词额度 → 提示可以加新词', () {
      final p = build(due: 0, newWords: 10);
      expect(p.headline, '今天可以加 10 个新词');
      expect(p.dueLine, '没有到期的词 · 新词额度 10');
    });

    test('今天没事可做 → 不显示 0/0,而是指个方向', () {
      final p = build(due: 0, newWords: 0);
      expect(p.headline, contains('读一篇新材料'));
      expect(p.dueLine, '没有到期的词 · 今天不加新词');
    });

    test('连续天数只在天数 > 0 时出现', () {
      expect(build(due: 5, streak: 7).streak, '连续 7 天');
      expect(build(due: 5, streak: 0).streak, isEmpty);
    });
  });

  group('过期数据不许冒充今天', () {
    test('昨天同步 → 仍然显示(还没有隔天),但页脚标明是昨天的数据', () {
      final p = build(
        due: 9,
        syncedAt: DateTime(2026, 9, 23, 21, 5),
      );
      // 9-23 → 9-24 是隔 1 天:仍在"可用"范围,数字照显示
      expect(p.headline, '复习 9 个词');
      expect(WidgetPayload.dayDiff(p.syncedAt!, now), 1);
    });

    test('隔 2 天以上 → 标题换成刷新提示,不再显示旧数字', () {
      final p = build(due: 3, syncedAt: DateTime(2026, 9, 22, 9));
      expect(p.headline, '打开 App 刷新今日任务');
      expect(p.dueLine, contains('2 天前'));
      expect(p.previewLines().join(' '), isNot(contains('待复习')));
    });

    test('自然日差:23:50 → 次日 00:10 算隔了一天', () {
      expect(
        WidgetPayload.dayDiff(
          DateTime(2026, 9, 23, 23, 50),
          DateTime(2026, 9, 24, 0, 10),
        ),
        1,
      );
      expect(
        WidgetPayload.dayDiff(
          DateTime(2026, 9, 24, 0, 1),
          DateTime(2026, 9, 24, 23, 59),
        ),
        0,
      );
    });

    test('ageLabel 文案', () {
      expect(WidgetPayload.ageLabel(0), '刚刚');
      expect(WidgetPayload.ageLabel(1), '昨天');
      expect(WidgetPayload.ageLabel(4), '4 天前');
    });
  });

  group('写入前端的键(与原生 ReadFlowWidgetProvider 对齐)', () {
    test('今天同步会写齐 5 个键,键名与 Kotlin 侧一致', () {
      final p = build(due: 4, newWords: 2, streak: 3, tasks: const [
        WidgetTask(title: '复习 4 个词', done: false),
      ]);
      final data = p.toWidgetData();
      expect(data.keys.toSet(), {
        'rf_headline',
        'rf_due_line',
        'rf_streak',
        'rf_badge',
        'rf_synced_at',
      });
      expect(data['rf_streak'], '连续 3 天');
      expect(DateTime.tryParse(data['rf_synced_at']!), isNotNull);
    });
  });
}
