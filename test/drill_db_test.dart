import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/drill_catalog.dart';
import 'package:readflow/services/drill_planner.dart';

/// 练习系统的数据层回归(v2.9,用户 10/2 第 2 条)。
///
/// 为什么必须跑**真 SQLite**:练习进度是"从日志派生"的 —— 天数去重、今日题数、
/// 连续打卡、正确率、计划归档,全靠 SQL 语义与时间字符串的比较。mock 掉数据库
/// 或改断言常量都测不出这些,而它们一旦错,用户看到的是"练了三天进度还是 0"
/// 或"昨天练的算到今天"这类只有他自己会发现的问题。
///
/// 时间一律**注入**(`at` / `now` 参数或固定 DateTime),不依赖跑测试那一刻的
/// 真实时钟 —— 否则跨零点跑测试会偶发红。每个 test 前重建临时库。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_drill_test');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    try {
      await databaseFactory.deleteDatabase(
        p.join(tmp.path, AppConstants.dbName),
      );
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// 从"现在"往前推 n 天(用于构造历史日志)
  DateTime daysAgo(int n, {int hour = 10}) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour)
        .subtract(Duration(days: n));
  }

  test('建计划 → 记两次练习 → drillProgress 的数字对得上 → 关计划', () async {
    // ── 1. 建计划(练习模式与难度存在 level_note 的结构化串里)──
    final goals = DrillCatalog.normalizeAll(const ['四六级', '雅思/托福']);
    final note = DrillPlanNote(
      planMode: DrillPlanNote.planPlan,
      goals: goals,
      level: DrillLevel.intermediate,
      userNote: '六级已过,主攻长难句',
    );
    final planId = await DatabaseService.createDrillPlan(
      mode: 'spelling',
      goals: goals,
      levelNote: encodePlanNote(note),
      weeks: 4,
      perDay: 12,
      startDate: daysAgo(1),
    );
    expect(planId, greaterThan(0));

    final plan = await DatabaseService.activeDrillPlan('spelling');
    expect(plan, isNotNull);
    expect(plan!['mode'], 'spelling');
    expect(plan['weeks'], 4);
    expect(plan['per_day'], 12);
    expect(plan['status'], 'active');
    // 目标 JSON 往返
    expect(jsonDecode(plan['goals'] as String), goals);
    // 结构化串往返(练习模式、难度、用户补充一句都不能丢)
    final back = decodePlanNote(plan['level_note'] as String?);
    expect(back.planMode, DrillPlanNote.planPlan);
    expect(back.goals, goals);
    expect(back.level, DrillLevel.intermediate);
    expect(back.userNote, '六级已过,主攻长难句');

    // 另一个 mode 互不影响(拼写与翻译各有一套计划)
    expect(await DatabaseService.activeDrillPlan('translation'), isNull);

    // ── 2. 记两次练习:今天一次(10 题对 8)、昨天一次(12 题对 6)──
    final todayLog = await DatabaseService.logDrill(
      mode: 'spelling',
      total: 10,
      correct: 8,
      seconds: 120,
      planId: planId,
      goals: goals,
      wrong: const ['phenomenon', 'sustainable'],
    );
    expect(todayLog, greaterThan(0));
    await DatabaseService.logDrill(
      mode: 'spelling',
      total: 12,
      correct: 6,
      seconds: 240,
      planId: planId,
      goals: goals,
      wrong: const ['implementation'],
    );
    // 另一模式的一条,不能被算进 spelling 的进度
    await DatabaseService.logDrill(
      mode: 'translation',
      total: 5,
      correct: 5,
      seconds: 100,
    );
    // 把"12 题那条"挪到昨天(两条 logDrill 之间没有时钟间隔,created_at 会撞在同一毫秒;
    // 直接用 SQL 改时间,才测得出"按时间倒序"与"今天只算今天"这两件事)
    final db = await DatabaseService.database;
    await db.update(
      'drill_logs',
      {'created_at': daysAgo(1, hour: 20).toIso8601String()},
      where: 'mode = ? AND total = ?',
      whereArgs: ['spelling', 12],
    );

    final logs = await DatabaseService.getDrillLogs(mode: 'spelling');
    expect(logs.length, 2);
    expect(logs.first['total'], 10, reason: '最新的在前');
    expect(jsonDecode(logs.first['wrong_words'] as String),
        ['phenomenon', 'sustainable']);
    expect(logs.last['total'], 12);

    // ── 3. 进度:数字必须与上面两条记录严格对应 ──
    final progress = await DatabaseService.drillProgress(mode: 'spelling');
    expect(progress['times'], 2);
    expect(progress['total'], 22);
    expect(progress['correct'], 14);
    expect(progress['seconds'], 360);
    expect(progress['accuracy'], closeTo(14 / 22, 1e-9));
    expect(progress['todayTotal'], 10,
        reason: '昨天那条不该算到今天(两条都在"今天"的话说明时间边界错了)');
    expect(progress['streak'], 2, reason: '今天 + 昨天都练过 → 连续 2 天');

    // 计划进度:第 2 天(起始日 = 昨天),练过 2 天,今日达标(10 < 12 不达标)
    final stats = DrillPlanner.statsFrom(
      await DatabaseService.getDrillLogs(mode: 'spelling'),
    );
    final p = DrillPlanner.progressOf(
      progress,
      perDay: plan['per_day'] as int,
      weeks: plan['weeks'] as int,
      startDate: DateTime.tryParse('${plan['start_date']}'),
      logStats: stats,
    );
    expect(p.dayIndex, 2);
    expect(p.totalDays, 28);
    expect(p.doneDays, 2);
    expect(p.todayTotal, 10);
    expect(p.todayDone, isFalse, reason: '今日目标 12 题,只练了 10 题');
    expect(p.remainDays, 27);
    expect(p.streak, 2);
    expect(p.total, 22);
    expect(p.rate, closeTo(2 / 28, 1e-9));

    // 今天补到 12 题 → 达标
    await DatabaseService.logDrill(
      mode: 'spelling',
      total: 2,
      correct: 2,
      seconds: 20,
      planId: planId,
      goals: goals,
    );
    final progress2 = await DatabaseService.drillProgress(mode: 'spelling');
    expect(progress2['todayTotal'], 12);
    expect(progress2['total'], 24);
    final p2 = DrillPlanner.progressOf(
      progress2,
      perDay: 12,
      startDate: DateTime.tryParse('${plan['start_date']}'),
      logStats: DrillPlanner.statsFrom(
        await DatabaseService.getDrillLogs(mode: 'spelling'),
      ),
    );
    expect(p2.todayDone, isTrue);
    expect(p2.streak, 2, reason: '同一天多练几次不该把连续天数刷上去');

    // ── 4. 到期复习:错题进队列 → 到期计数 +1 ──
    await DatabaseService.upsertWordReview(
      4242,
      stability: 0,
      difficulty: 6,
      dueAt: DateTime.now(),
      lastReviewAt: DateTime.now(),
    );
    expect(await DatabaseService.getDueReviewCount(), 1);
    final buckets = await DatabaseService.getReviewBuckets();
    expect(buckets['today'], 1);

    // ── 5. 换模式:旧计划归档,新计划接上(同模式只留一个 active)──
    final autoNote = encodePlanNote(const DrillPlanNote(
      planMode: DrillPlanNote.planAuto,
      goals: ['四六级'],
      level: DrillLevel.advanced,
    ));
    final newId = await DatabaseService.createDrillPlan(
      mode: 'spelling',
      goals: const ['四六级'],
      levelNote: autoNote,
      weeks: 4,
      perDay: 15,
    );
    expect(newId, greaterThan(0));
    expect(newId, isNot(planId));
    final active = await DatabaseService.activeDrillPlan('spelling');
    expect(active!['id'], newId, reason: '同模式只留一个进行中的计划');
    expect(decodePlanNote(active['level_note'] as String?).planMode,
        DrillPlanNote.planAuto);

    // 旧计划被归档(不是删):它的日志还挂着 plan_id
    final archived = await db.query('drill_plans',
        where: 'id = ?', whereArgs: [planId]);
    expect(archived.single['status'], 'archived');
    expect(
      (await DatabaseService.getDrillLogs(mode: 'spelling'))
          .where((r) => r['plan_id'] == planId)
          .length,
      3,
      reason: '归档不等于抹掉历史',
    );

    // ── 6. 关计划:关掉之后没有 active,日志仍在 ──
    await DatabaseService.closeDrillPlan(newId);
    expect(await DatabaseService.activeDrillPlan('spelling'), isNull);
    expect((await DatabaseService.drillProgress(mode: 'spelling'))['total'], 24);
    expect(
      (await DatabaseService.drillProgress(mode: 'translation'))['total'],
      5,
      reason: '另一种模式的数据不受影响',
    );
  });

  test('drillProgress 空库:全 0 而不是 null/NaN;跨天之后 streak 会断', () async {
    final empty = await DatabaseService.drillProgress(mode: 'spelling');
    expect(empty['times'], 0);
    expect(empty['total'], 0);
    expect(empty['accuracy'], 0.0);
    expect(empty['todayTotal'], 0);
    expect(empty['streak'], 0);
    // 缺键也不会算崩(progressOf 对空 Map 容错)
    final p = DrillPlanner.progressOf(
      const {},
      perDay: 0,
      logStats: DrillPlanner.statsFrom(const []),
    );
    expect(p.total, 0);
    expect(p.perDay, 10, reason: 'perDay<=0 回落到 10,不除零');
    expect(p.accuracy, 0);

    // 只在前天练过 → 连续天数归 0(今天与昨天都没练)
    await DatabaseService.logDrill(
      mode: 'spelling',
      total: 10,
      correct: 10,
      seconds: 60,
    );
    final db = await DatabaseService.database;
    await db.update(
      'drill_logs',
      {'created_at': daysAgo(2, hour: 9).toIso8601String()},
      where: 'mode = ?',
      whereArgs: ['spelling'],
    );
    final stale = await DatabaseService.drillProgress(mode: 'spelling');
    expect(stale['streak'], 0);
    expect(stale['todayTotal'], 0);
    expect(stale['total'], 10, reason: '累计题数不看日期');

    // 跨模式合计(mode 传 null)要把两种都算上
    await DatabaseService.logDrill(
      mode: 'translation',
      total: 4,
      correct: 3,
      seconds: 30,
    );
    final all = await DatabaseService.drillProgress();
    expect(all['total'], 14);
    expect(all['times'], 2);
    expect(all['accuracy'], closeTo(13 / 14, 1e-9));
  });

  test('logDrill 的 wrong 列表被截断到 30 条:一条练习不会撑爆一行', () async {
    final wrong = [for (var i = 0; i < 45; i++) 'word$i'];
    await DatabaseService.logDrill(
      mode: 'spelling',
      total: 45,
      correct: 0,
      seconds: 300,
      wrong: wrong,
    );
    final logs = await DatabaseService.getDrillLogs(mode: 'spelling');
    final saved = (jsonDecode(logs.single['wrong_words'] as String) as List)
        .map((e) => '$e')
        .toList();
    expect(saved.length, 30);
    expect(saved.first, 'word0');
    expect(saved.last, 'word29');
  });
}
