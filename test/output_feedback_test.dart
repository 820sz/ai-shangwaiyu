import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/services/database.dart';
import 'package:readflow/services/output_feedback.dart';
import 'package:readflow/services/output_rubric.dart';

/// v2.18.0(批 3 收尾 · 输出回流)回归:错误标签归一 + 输出行为聚合。
///
/// 为什么这两件事必须测:
/// 1. **归一映射是契约**:评分模型给的是自由文本("时态不一致"/"中式英语"…),
///    错误档案只认既有 tag。映射错 = 错误档案里长出一堆无法聚合的一次性标签;
///    映射不上就丢弃(宁可不记也不硬造);
/// 2. **聚合口径是周报/快照的数据源**:attempts/均分/题型/错误热点任何一个口径
///    算错,用户会在周报里看到假数字(项目纪律:无证据不下结论)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_output_feedback_test');
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

  ScoredIssue issue(String type, String reason, {String span = ''}) =>
      ScoredIssue(span: span, type: type, reason: reason);

  group('canonicalTagFor:模型自由文本 → 既有 error_tags 标签', () {
    test('5 个语法点各有明确关键词(中英文都认)', () {
      expect(OutputFeedback.canonicalTagFor('时态不一致'), '时态');
      expect(OutputFeedback.canonicalTagFor('tense'), '时态');
      expect(OutputFeedback.canonicalTagFor('冠词误用'), '冠词');
      expect(OutputFeedback.canonicalTagFor('article'), '冠词');
      expect(OutputFeedback.canonicalTagFor('介词搭配'), '介词');
      expect(OutputFeedback.canonicalTagFor('主谓一致'), '主谓一致');
      expect(OutputFeedback.canonicalTagFor('单复数一致错误'), '主谓一致');
      expect(OutputFeedback.canonicalTagFor('虚拟语气用错'), '虚拟语气');
    });

    test('词汇层面统一归「词汇」(不新造拼写/中式英语等标签)', () {
      expect(OutputFeedback.canonicalTagFor('用词不当'), '词汇');
      expect(OutputFeedback.canonicalTagFor('固定搭配错误'), '词汇');
      expect(OutputFeedback.canonicalTagFor('中式英语'), '词汇');
      expect(OutputFeedback.canonicalTagFor('拼写错误'), '词汇');
      expect(OutputFeedback.canonicalTagFor('chinglish'), '词汇');
    });

    test('归一不了的类型返回 null(语序/衔接/标点/其他不硬造)', () {
      expect(OutputFeedback.canonicalTagFor('语序'), isNull);
      expect(OutputFeedback.canonicalTagFor('篇章衔接'), isNull);
      expect(OutputFeedback.canonicalTagFor('标点'), isNull);
      expect(OutputFeedback.canonicalTagFor('其他'), isNull);
      expect(OutputFeedback.canonicalTagFor('   '), isNull);
    });

    test('优先级:同时命中语法点与泛词汇时,先记具体语法点', () {
      // type 是泛化的"用词",但 reason 明确说时态 → 必须是「时态」
      expect(OutputFeedback.canonicalTagFor('用词 时态不一致'), '时态');
    });
  });

  group('canonicalErrorTags:同轮去重、顺序稳定', () {
    test('同类错误出现多次只记一次(一次练习 = 一次踩坑)', () {
      final tags = OutputFeedback.canonicalErrorTags([
        issue('语法', '时态不一致'),
        issue('语法', '时态用错了'),
        issue('用词', '搭配不当'),
        issue('语序', '语序倒装'),
      ]);
      expect(tags, ['时态', '词汇']);
    });

    test('空问题列表 → 空(不会因为"没错误"写任何 tag)', () {
      expect(OutputFeedback.canonicalErrorTags(const []), isEmpty);
    });

    test('canonicalTagsFromTexts:给旧链路(只有类型文本)复用同一套映射', () {
      expect(
        OutputFeedback.canonicalTagsFromTexts(['词汇', '语法', '表达优化', '拼写']),
        ['词汇'],
      );
    });
  });

  group('recordOutputFeedback:写错误档案(真 SQLite)', () {
    test('归一后的 tag 各 bump 一次,带证据,source 可指定', () async {
      final written = await OutputFeedback.recordOutputFeedback(
        source: 'exercise',
        issues: [
          issue('语法', '时态不一致', span: 'I go to school yesterday.'),
          issue('用词', '搭配不当', span: 'do a mistake'),
          issue('语序', '语序'),
        ],
      );
      expect(written, 2, reason: '时态 + 词汇;语序归一不了被丢弃');

      final rows = await DatabaseService.getErrorTags();
      expect(rows.length, 2);
      final byTag = {for (final r in rows) '${r['tag']}': r};
      expect(byTag.keys.toSet(), {'时态', '词汇'});
      expect(byTag['时态']!['source'], 'exercise');
      expect(byTag['时态']!['count'], 1);
      expect('${byTag['时态']!['evidence']}', contains('yesterday'));
    });

    test('同一次练习再批改一次 → 同类 tag 计数累加(错误档案的"复发"依据)', () async {
      await OutputFeedback.recordOutputFeedback(
        source: 'exercise',
        issues: [issue('语法', '时态不一致')],
      );
      await OutputFeedback.recordOutputFeedback(
        source: 'exercise',
        issues: [issue('语法', '时态不一致', span: 'He go home.')],
      );
      final rows = await DatabaseService.getErrorTags();
      expect(rows.single['tag'], '时态');
      expect(rows.single['count'], 2);
    });

    test('全部归一不了 → 返回 0、不写任何行', () async {
      final written = await OutputFeedback.recordOutputFeedback(
        source: 'output',
        issues: [issue('标点', '逗号用错'), issue('其他', '字迹潦草')],
      );
      expect(written, 0);
      expect(await DatabaseService.getErrorTags(), isEmpty);
    });

    test('recordErrorTags:只收既有标签(防调用方塞新造标签)', () async {
      final written = await OutputFeedback.recordErrorTags(
        ['时态', '语序', '词汇', '时态'],
        source: 'writing',
        evidence: 'from writing log',
      );
      expect(written, 2, reason: '时态 + 词汇;语序不是既有标签、时态重复');
      final rows = await DatabaseService.getErrorTags();
      expect(rows.map((r) => '${r['tag']}').toSet(), {'时态', '词汇'});
      expect('${rows.first['source']}', 'writing');
    });
  });

  group('outputSnapshot:输出行为聚合(真 SQLite)', () {
    /// 构造一次 rubric 评分的 score_json(total/max 决定百分比)
    String scoreJson({
      required double total,
      required Map<String, ({double score, double max})> dims,
    }) =>
        jsonEncode({
          'total_score': total,
          'band_label': '',
          'dimensions': [
            for (final e in dims.entries)
              {
                'key': e.key,
                'label': e.key,
                'score': e.value.score,
                'max_score': e.value.max,
              }
          ],
          'issues': const [],
        });

    test('空库 → 安全默认值(avgScore=null,不是 0)', () async {
      final snap = await OutputFeedback.outputSnapshot(days: 30);
      expect(snap['attempts'], 0);
      expect(snap['avgScore'], isNull, reason: '没数据不能编 0 分');
      expect(snap['lastAt'], isNull);
      expect(snap['byType'], isEmpty);
      expect(snap['recentScores'], isEmpty);
      expect(snap['topErrorTags'], isEmpty);
    });

    test('次数/均分/题型/维度/最近5次/错误热点 口径正确,窗口外不计', () async {
      final writingSet = await DatabaseService.insertExerciseSet(
        {'title': '写作', 'section': 'writing'},
      );
      final translationSet = await DatabaseService.insertExerciseSet(
        {'title': '翻译', 'section': 'translation'},
      );

      await DatabaseService.insertOutputAttempt({
        'set_id': writingSet,
        'mode': 'ai_rubric',
        'score_json': scoreJson(total: 12, dims: {
          'content': (score: 7, max: 9),
          'language': (score: 5, max: 6),
        }), // 总分 12/15 = 80%
        'error_tags_json': jsonEncode(['时态不一致', '语序']),
        'created_at': '2026-10-30T10:00:00.000',
      });
      await DatabaseService.insertOutputAttempt({
        'set_id': translationSet,
        'mode': 'ai_rubric',
        'score_json': scoreJson(total: 5, dims: {
          'accuracy': (score: 5, max: 10),
        }), // 5/10 = 50%
        'error_tags_json': jsonEncode(['用词']),
        'created_at': '2026-10-31T10:00:00.000',
      });
      // 窗口外的旧作答(30 天前)→ 必须被过滤
      await DatabaseService.insertOutputAttempt({
        'set_id': writingSet,
        'score_json': scoreJson(total: 0, dims: {
          'content': (score: 0, max: 9),
        }),
        'created_at': '2026-01-01T00:00:00.000',
      });

      final now = DateTime(2026, 11, 1, 12);
      final snap =
          await OutputFeedback.outputSnapshot(days: 30, now: now);

      expect(snap['attempts'], 2, reason: '窗口外那条不计入');
      expect((snap['avgScore'] as double), closeTo(65, 1e-9)); // (80+50)/2
      expect(snap['lastAt'], '2026-10-31T10:00:00.000');
      expect(
        snap['byType'],
        {'writing': 1, 'translation': 1},
        reason: '题型取 exercise_sets.section',
      );
      expect(snap['recentScores'], [80.0, 50.0], reason: '时间升序,便于画趋势');
      expect(
        snap['topErrorTags'],
        {'时态': 1, '词汇': 1},
        reason: '语序归一不了被丢弃;用词归一到词汇',
      );
      final dims = (snap['dimensionAvg'] as Map).cast<String, double>();
      expect(dims['content'], closeTo(7 / 9 * 100, 1e-9));
      expect(dims['language'], closeTo(5 / 6 * 100, 1e-9));
      expect(dims['accuracy'], closeTo(50, 1e-9));
    });
  });
}
