import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/ability_recorder.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/output_rubric.dart';

/// 能力快照记录器(v3 · 批 8 · E1-5)的真 SQLite 回归。
///
/// 这一层是"能力项时间序列"的唯一写入口:词汇量测试、写译批改、输出练习
/// 三个时点都通过它写库。契约必须钉死:
/// ① 写入的值/单位/来源/置信度/证据能被 `latestAbility` 原样读回;
/// ② output 维度统一成 0..100 百分比(不同 rubric 满分不同,不换算没法比);
/// ③ 练习作答用"同日 upsert":同一天多次批改只留一行、取当天最新值,
///    不同天各留一行(趋势图不能一天十几个锯齿点);
/// ④ **失败一律静默**(用户点提交后最该看到的是批改结果,不是统计报错)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_ability_recorder_test');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
  });

  tearDown(() async {
    AbilityRecorder.debugInsertOverride = null;
    await DatabaseService.resetForTest();
    try {
      await databaseFactory.deleteDatabase(p.join(tmp.path, AppConstants.dbName));
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<int> abilityCount() async {
    final db = await DatabaseService.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ability_snapshots',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  test('recordPlacement:vocab/test 来源 + 区间证据,latestAbility 可读回', () async {
    final id = await AbilityRecorder.recordPlacement(
      estimate: 4200,
      low: 3800,
      high: 4600,
      cefr: 'B1',
      falseAlarmRate: 0.05,
      full: true,
    );
    expect(id, greaterThan(0));

    final latest = (await DatabaseService.latestAbility('vocab'))!;
    expect((latest['value'] as num).toDouble(), 4200);
    expect(latest['unit'], 'words');
    expect(latest['source'], 'test', reason: '测试得到的能力必须是 test 来源');
    expect(
      (latest['confidence'] as num).toDouble(),
      closeTo(0.85, 1e-9),
      reason: '伪词误报 5% → 置信度 0.85(与保存基线同一口径)',
    );
    final evidence = latest['evidence'] as Map;
    expect(evidence['low'], 3800);
    expect(evidence['high'], 4600);
    expect(evidence['cefr'], 'B1');
    expect(evidence['mode'], 'full');
  });

  test('recordScoredOutput:value 统一成 0..100 百分比(跨 rubric 可比较)', () async {
    final rubric =
        OutputRubric.byId('cet4_writing') ?? OutputRubric.builtin().first;
    final id = await AbilityRecorder.recordScoredOutput(
      scored: ScoredOutput(
        totalScore: rubric.totalScore / 2,
        bandLabel: '良好',
        dimensions: const [],
      ),
      rubric: rubric,
      taskType: 'writing',
    );
    expect(id, greaterThan(0));

    final latest = (await DatabaseService.latestAbility('output'))!;
    expect(
      (latest['value'] as num).toDouble(),
      closeTo(50, 1e-6),
      reason: '一半满分 → 50 分档;不同 rubric 满分不同,必须换算成百分比',
    );
    expect(latest['unit'], 'score');
    expect(latest['source'], 'inferred', reason: '行为推断不能冒充测量');
    final evidence = latest['evidence'] as Map;
    expect(evidence['rubric_id'], rubric.id);
    expect(evidence['band'], '良好');
    expect(evidence['task_type'], 'writing');
    expect(evidence['raw_score'], closeTo(rubric.totalScore / 2, 1e-9));
  });

  test('练习作答同日 upsert:同一天只留一行取最新值;不同天各留一行', () async {
    final today = DateTime.now();
    await AbilityRecorder.recordOutputScore(
      score: 60,
      maxScore: 100,
      at: today.subtract(const Duration(hours: 2)),
    );
    await AbilityRecorder.recordOutputScore(score: 80, maxScore: 100, at: today);
    expect(await abilityCount(), 1, reason: '同一天两次批改只留一行');

    var latest = (await DatabaseService.latestAbility('output'))!;
    expect(
      (latest['value'] as num).toDouble(),
      closeTo(80, 1e-6),
      reason: '同日 upsert 的值应当是该天最新一次',
    );

    await AbilityRecorder.recordOutputScore(
      score: 70,
      maxScore: 100,
      at: today.subtract(const Duration(days: 1)),
    );
    expect(await abilityCount(), 2);
    final history = await DatabaseService.abilityHistory('output');
    expect(history, hasLength(2));
    expect(
      (history.first['value'] as num).toDouble(),
      closeTo(70, 1e-6),
      reason: 'history 按时间升序(趋势图直接画)',
    );
  });

  test('一次性测试不合并:同一天做两次词汇量测试保留两条(测量要留点)', () async {
    final today = DateTime.now();
    await AbilityRecorder.recordPlacement(
      estimate: 4000,
      low: 3600,
      high: 4400,
      at: today.subtract(const Duration(hours: 1)),
    );
    await AbilityRecorder.recordPlacement(
      estimate: 4300,
      low: 3900,
      high: 4700,
      at: today,
    );
    expect(await abilityCount(), 2, reason: '测试是按真实时刻逐条保留');
  });

  test('失败静默:写入抛异常时 record 返回 -1、不抛、不留行', () async {
    AbilityRecorder.debugInsertOverride = (snapshot) async {
      throw StateError('模拟数据库故障');
    };
    final id = await AbilityRecorder.recordPlacement(
      estimate: 3000,
      low: 2700,
      high: 3300,
    );
    expect(id, -1);
    expect(await abilityCount(), 0, reason: '失败不能留下半条记录');
  });

  test('DB 层拒绝(getter 返回 -1)同样静默返回 -1', () async {
    AbilityRecorder.debugInsertOverride = (snapshot) async => -1;
    expect(
      await AbilityRecorder.record(dimension: 'reading', value: 210),
      -1,
    );
  });

  test('非法维度/非法值静默忽略;非法来源回落 inferred', () async {
    expect(
      await AbilityRecorder.record(dimension: 'not_a_dimension', value: 1),
      -1,
      reason: '维度必须在 DB 白名单里,否则趋势统计无法聚合',
    );
    expect(
      await AbilityRecorder.record(dimension: 'vocab', value: double.nan),
      -1,
    );
    expect(
      await AbilityRecorder.recordPlacement(estimate: 0, low: 0, high: 0),
      -1,
      reason: '估计 0 = 不可信,不能写进趋势',
    );
    expect(await abilityCount(), 0);

    final id = await AbilityRecorder.record(
      dimension: 'reading',
      value: 210,
      source: '瞎写的来源',
    );
    expect(id, greaterThan(0));
    final latest = (await DatabaseService.latestAbility('reading'))!;
    expect(latest['source'], 'inferred', reason: '非法来源回落白名单默认值');
  });
}
