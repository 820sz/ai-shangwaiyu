import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/writing_log.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/learner_snapshot_loader.dart';
import 'package:readflow/services/tutor_engine.dart';

/// v2.18.0(批 3 收尾)回归:输出数据接入助理快照,修"只有输入没有输出"误报。
///
/// 根因(侦察结论):快照里原本只有 quiz_results + error_tags,
/// `output_attempts` / `drill_logs` / `writing_logs` 三张表**完全没进快照** ——
/// 用户天天写译,助理仍报"近 30 天只有输入没有输出"。
///
/// 这里用真 SQLite 造三类输出记录,断言:
/// 1. 快照新增字段真的读到了(次数/均分/最近时间/批改篇数/练习次数/语法薄弱点);
/// 2. tutor_engine 不再误报 input_only,且证据包里有输出数据;
/// 3. 30 天窗口外的旧记录不计入(口径与阅读维度同窗口)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_snapshot_output_test');
    await databaseFactory.setDatabasesPath(tmp.path);
    await DatabaseService.resetForTest();
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
    try {
      await databaseFactory.deleteDatabase(p.join(tmp.path, AppConstants.dbName));
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String scoreJson(double total, {double max = 15}) => jsonEncode({
        'total_score': total,
        'band_label': '',
        'dimensions': [
          {'key': 'language', 'label': '语言准确', 'score': total, 'max_score': max},
        ],
        'issues': const [],
      });

  bool hasFinding(List<TutorFinding> f, String id) =>
      f.any((e) => e.id == id);

  test('三张输出表都进快照;tutor_engine 不再误报 input_only', () async {
    // 输入:读了 5000 词(保证 input_only 的前置条件成立)
    await DatabaseService.insertReadingSession(
      words: 5000,
      duration: const Duration(minutes: 120),
    );

    // 快照基线:有阅读、零输出 → 旧规则应当报 input_only
    final before = await LearnerSnapshotLoader.load(vocab: const <dynamic>[]);
    expect(before.readingWords30d, 5000);
    expect(before.outputAttempts30d, 0);
    expect(before.writeLogs30d, 0);
    expect(before.drillLogs30d, 0);
    expect(before.outputAvgScore, isNull);
    expect(hasFinding(TutorEngine.diagnose(before), 'input_only'), isTrue,
        reason: '没有任何输出记录时，旧提示仍然应该出现');

    // ── 造三类输出记录 ──
    final setId = await DatabaseService.insertExerciseSet(
      {'title': '本周写作', 'section': 'writing', 'rubric_id': 'cet4_writing'},
    );
    await DatabaseService.insertOutputAttempt({
      'set_id': setId,
      'mode': 'ai_rubric',
      'answer': 'My essay.',
      'score_json': scoreJson(12), // 12/15 = 80%
      'seconds': 300,
      'error_tags_json': jsonEncode(['时态不一致', '用词']),
    });
    await DatabaseService.logDrill(
      mode: 'spelling',
      total: 10,
      correct: 8,
      seconds: 90,
    );
    await DatabaseService.insertWritingLog(WritingLog(
      sourceType: 'electronic',
      originalText: 'A short paragraph.',
      score: '85',
      createdAt: DateTime.now(),
    ));
    // 错误档案里的语法薄弱点(错误顺序:先冠词后时态,读的时候要按次数排)
    await DatabaseService.bumpErrorTag(source: 'exercise', tag: '冠词');
    await DatabaseService.bumpErrorTag(source: 'exercise', tag: '时态');
    await DatabaseService.bumpErrorTag(source: 'exercise', tag: '时态');
    await DatabaseService.bumpErrorTag(source: 'review', tag: '词汇');

    final after = await LearnerSnapshotLoader.load(vocab: const <dynamic>[]);
    expect(after.outputAttempts30d, 1);
    expect(after.outputAvgScore, closeTo(80, 1e-9));
    expect(after.outputLastAt, isNotNull);
    expect(after.writeLogs30d, 1, reason: '写译批改篇数');
    expect(after.drillLogs30d, 1, reason: '练习记录次数');
    expect(after.weakGrammarTags, ['时态', '冠词'],
        reason: '只取语法 tag(词汇排除)、按次数倒序');

    // 关键断言:不再误报"只有输入没有输出"
    final findings = TutorEngine.diagnose(after);
    expect(hasFinding(findings, 'input_only'), isFalse);
    // 证据包也要能看到输出数据(助理回答时不能再说"没有输出")
    final prompt = TutorEngine.evidencePrompt(after, findings);
    expect(prompt, contains('输出:近 30 天'));
    expect(prompt, contains('1'));
    expect(prompt, contains('语法薄弱点'));
    expect(prompt, contains('时态'));
  });

  test('30 天窗口外的输出记录不计入快照(口径与阅读窗口一致)', () async {
    // 旧记录:直接写库(绕过"自动 now"的插入接口)
    final db = await DatabaseService.database;
    await db.insert('output_attempts', {
      'mode': 'ai_rubric',
      'score_json': scoreJson(15),
      'created_at': '2020-01-01T00:00:00.000',
    });
    await db.insert('drill_logs', {
      'mode': 'spelling',
      'total': 5,
      'correct': 5,
      'created_at': '2020-01-01T00:00:00.000',
    });
    await DatabaseService.insertWritingLog(WritingLog(
      sourceType: 'electronic',
      originalText: 'old',
      createdAt: DateTime(2020, 1, 1),
    ));

    final snap = await LearnerSnapshotLoader.load(vocab: const <dynamic>[]);
    expect(snap.outputAttempts30d, 0);
    expect(snap.drillLogs30d, 0);
    expect(snap.writeLogs30d, 0);
    expect(snap.outputAvgScore, isNull);
    expect(snap.outputLastAt, isNull);
  });
}
