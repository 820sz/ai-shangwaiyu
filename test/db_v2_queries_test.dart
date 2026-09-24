import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/services/database.dart';

/// v2.0 数据访问层回归(材料中心 / 阅读进度与会话 / 测验 / 错误档案 / 复习 / 导师)。
///
/// 为什么必须跑**真 SQLite**:这一层的坑几乎全在 SQL 语义上 —— 去重的唯一键、
/// `+=` 累加 vs 绝对值覆盖、ON CONFLICT 的 upsert、按自然日分桶、julianday 算时长、
/// 坏 JSON 的容错。mock 掉数据库或断言常量都测不出这些,而它们一旦错,
/// 表现是"复习队列永不空/进度每次归零/导师页整页崩"这种线上才发现的病。
///
/// 时间基准:**凡是有时间语义的断言都注入 `at` / `now` 参数或固定 DateTime**,
/// 不依赖跑测试那一刻的真实时钟(否则跨零点/跨月会偶发红)。
/// 每个 test 前重建临时库 + `resetForTest()`:测试之间不共享连接,也不共享数据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rf_db_v2_test');
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

  // ── 1. 材料中心:去重 + 正文分块 ──

  test('upsertMaterial:(source, source_id) 去重、元数据更新、chunks 按序读回', () async {
    final id1 = await DatabaseService.upsertMaterial(
      {
        'kind': 'book',
        'source': 'gutenberg',
        'source_id': 'pg-1342',
        'title': 'Pride and Prejudice',
        'author': 'Austen',
        'word_count': 122000,
        'cefr': 'C1',
        'coverage': 0.92,
        'difficulty_json': jsonEncode({'cefr': 'C1', 'flesch': 70.5}),
        'created_at': DateTime(2026, 3, 1).toIso8601String(),
      },
      chunks: [
        {'chunk_index': 1, 'title': 'Chapter 2', 'text': 'second chunk'},
        {'chunk_index': 0, 'title': 'Chapter 1', 'text': 'first chunk'},
      ],
    );
    expect(id1, greaterThan(0));

    // 第二次:同 (source, source_id),只带了一部分元数据(模拟"刷新标题/字数")
    final id2 = await DatabaseService.upsertMaterial({
      'kind': 'book',
      'source': 'gutenberg',
      'source_id': 'pg-1342',
      'title': 'Pride and Prejudice (rev)',
      'word_count': 123456,
      'cefr': 'C2',
    });
    expect(id2, id1, reason: '同一材料必须复用原 id,不能堆出第二行');

    final all = await DatabaseService.getMaterials();
    expect(all.length, 1);
    expect(all.first['id'], id1);
    expect(all.first['title'], 'Pride and Prejudice (rev)');
    expect(all.first['word_count'], 123456);
    expect(all.first['cefr'], 'C2');
    expect(all.first['author'], 'Austen', reason: '没传的字段保留原值');
    expect(all.first['coverage'], closeTo(0.92, 1e-9));
    expect(all.first['difficulty'], {'cefr': 'C1', 'flesch': 70.5});
    expect(
      all.first['created_at'],
      DateTime(2026, 3, 1).toIso8601String(),
      reason: '更新元数据不能改写首次入库时间',
    );
    expect(
      (await DatabaseService.getMaterialChunks(id1)).length,
      2,
      reason: '没传 chunks 时正文必须原样保留',
    );

    final chunks = await DatabaseService.getMaterialChunks(id1);
    expect(chunks.map((c) => c['chunk_index']).toList(), [0, 1]);
    expect(chunks.map((c) => c['text']).toList(), [
      'first chunk',
      'second chunk',
    ]);
    expect(chunks.first['title'], 'Chapter 1');
    expect(chunks.first['material_id'], id1);

    // 传了 chunks = 这批就是权威正文(重新抓取后覆盖),且不新增材料行
    await DatabaseService.upsertMaterial(
      {
        'kind': 'book',
        'source': 'gutenberg',
        'source_id': 'pg-1342',
        'title': 'Pride and Prejudice (rev)',
      },
      chunks: [
        {'title': 'Chapter 1', 'text': 'rewritten first chunk'},
      ],
    );
    final replaced = await DatabaseService.getMaterialChunks(id1);
    expect(replaced.length, 1, reason: '传了 chunks 就整体替换');
    expect(replaced.first['chunk_index'], 0, reason: 'chunk_index 缺省时按列表下标补');
    expect(replaced.first['text'], 'rewritten first chunk');
    expect((await DatabaseService.getMaterials()).length, 1);

    // 列表筛选 + 分页(created_at DESC, id DESC 兜底)
    final idOther = await DatabaseService.upsertMaterial({
      'kind': 'article',
      'source': 'guardian',
      'source_id': 'g-2026-03-10',
      'title': 'A short article',
    });
    final idLocal = await DatabaseService.upsertMaterial({
      'kind': 'article',
      'source': 'local',
      'source_id': 'upload-1',
      'title': 'My upload',
    });
    expect(
      (await DatabaseService.getMaterials(
        kind: 'article',
      )).map((m) => m['id']).toList(),
      [idLocal, idOther],
    );
    expect(await DatabaseService.getMaterials(kind: 'book'), hasLength(1));
    expect(
      (await DatabaseService.getMaterials(
        limit: 2,
      )).map((m) => m['id']).toList(),
      [idLocal, idOther],
    );
    expect(
      (await DatabaseService.getMaterials(
        limit: 2,
        offset: 2,
      )).map((m) => m['id']).toList(),
      [id1],
    );

    // 单条读取 + 缺失 id + 缺难度的 null 语义
    final one = await DatabaseService.getMaterialById(idOther);
    expect(one!['title'], 'A short article');
    expect(one['kind'], 'article');
    expect(one['difficulty'], isNull, reason: '没写难度就是 null,而不是抛异常');
    expect(await DatabaseService.getMaterialById(99999), isNull);

    // 参数不合法:返回 -1 而不是抛异常/写脏行
    expect(
      await DatabaseService.upsertMaterial({'source': 'x', 'title': 'no kind'}),
      -1,
    );
    expect(
      await DatabaseService.upsertMaterial({
        'kind': 'article',
        'source': 'x',
        'title': '   ',
      }),
      -1,
    );
    expect((await DatabaseService.getMaterials()).length, 3);
  });

  // ── 2. 阅读进度:累加语义 + JOIN ──

  test('upsertMaterialProgress:分钟/查词/拾词累加,percent 覆盖,finished 写完成时间', () async {
    final mid = await DatabaseService.upsertMaterial({
      'kind': 'article',
      'source': 'local',
      'source_id': 'a1',
      'title': 'Local A',
      'cefr': 'B1',
      'word_count': 800,
      'coverage': 0.8,
    });
    await DatabaseService.upsertMaterial({
      'kind': 'article',
      'source': 'local',
      'source_id': 'a2',
      'title': 'B 未读',
    });

    await DatabaseService.upsertMaterialProgress(
      mid,
      position: 120,
      percent: 0.2,
      addMinutes: 5,
      addLookups: 3,
      addPickedWords: 1,
    );
    final firstRead = await DatabaseService.getMaterialProgress(mid);
    final startedAt = firstRead!['started_at'];
    expect(firstRead['minutes'], 5);
    expect(firstRead['lookups'], 3);
    expect(firstRead['picked_words'], 1);
    expect(firstRead['percent'], closeTo(0.2, 1e-9));

    await DatabaseService.upsertMaterialProgress(
      mid,
      position: 300,
      percent: 0.5,
      addMinutes: 7,
      addLookups: 2,
      addPickedWords: 4,
    );
    final prog = await DatabaseService.getMaterialProgress(mid);
    expect(prog!['position'], 300, reason: 'position 是绝对值,覆盖');
    expect(prog['percent'], closeTo(0.5, 1e-9), reason: 'percent 是绝对值,覆盖');
    expect(prog['minutes'], 12, reason: '5 + 7,分钟必须累加');
    expect(prog['lookups'], 5);
    expect(prog['picked_words'], 5);
    expect(prog['finished_at'], isNull);
    expect(prog['started_at'], startedAt, reason: 'started_at 只在首行写入,累加不能刷新它');
    expect(await DatabaseService.countMaterialsFinished(), 0);

    // 第三次:故意只加 0 分钟(不动),并标记读完
    await DatabaseService.upsertMaterialProgress(
      mid,
      position: 800,
      percent: 1.0,
      addMinutes: 3,
      finished: true,
    );
    final done = await DatabaseService.getMaterialProgress(mid);
    expect(done!['percent'], 1.0);
    expect(done['minutes'], 15);
    expect(done['lookups'], 5, reason: '不传的增量按 0 处理,不能把已有计数清零');
    final finishedAt = DateTime.parse('${done['finished_at']}');
    expect(
      finishedAt.isAfter(DateTime.now().subtract(const Duration(minutes: 1))),
      isTrue,
    );
    expect(
      DateTime.parse('${done['updated_at']}').isBefore(finishedAt),
      isFalse,
    );
    expect(await DatabaseService.countMaterialsFinished(), 1);

    // 读第二遍:finished:false 不能把"已读完"抹掉
    await DatabaseService.upsertMaterialProgress(
      mid,
      position: 10,
      percent: 0.01,
      addMinutes: 1,
    );
    final reread = await DatabaseService.getMaterialProgress(mid);
    expect(reread!['finished_at'], done['finished_at']);
    expect(reread['minutes'], 16);

    // 材料库查询 = materials LEFT JOIN material_progress。
    // 旧期望是 `length == 1`("没有进度的材料不算读过")—— 那条断言把 bug 锁死了:
    // 用户入库一份材料却没立刻打开,书架里就看不到它,看起来像导入失败。
    // v2.3.2 起:材料库里**所有**材料都要出现,没读过的进度字段为空(NOT 0),
    // 由展示层兜底成"未开始";而且必须带出 `id`(旧实现只给 `material_id`,
    // 而 ShelfItem 读 `id` → 每条 id 都是 0,点书架条目会去打开 id=0 的材料)。
    final recent = await DatabaseService.getRecentMaterials();
    expect(recent.length, 2, reason: '有进度与没进度的材料都要出现在材料库里');
    final withProgress = recent.firstWhere((r) => r['id'] == mid);
    expect(withProgress['id'], mid, reason: 'id 必须带出来,否则点击打开会失效');
    expect(withProgress['material_id'], mid);
    expect(withProgress['title'], 'Local A');
    expect(withProgress['kind'], 'article');
    expect(withProgress['cefr'], 'B1');
    expect(withProgress['word_count'], 800);
    expect(withProgress['coverage'], closeTo(0.8, 1e-9));
    expect(withProgress['percent'], closeTo(0.01, 1e-9));
    expect(withProgress['minutes'], 16);
    expect(withProgress['position'], 10);
    expect(withProgress['finished_at'], done['finished_at']);

    final noProgress = recent.firstWhere((r) => r['id'] != mid);
    expect(noProgress['percent'], isNull, reason: '没读过 → 进度为空,由 UI 显示"未开始"');
    expect(noProgress['finished_at'], isNull);
    expect(noProgress['id'], greaterThan(0));
    expect(await DatabaseService.getMaterialProgress(99999), isNull);
  });

  // ── 3. 阅读会话与统计 ──

  test('insertReadingSession:wpm 计算、时长为 0 存空;getReadingStats 窗口与均值', () async {
    final mid = await DatabaseService.upsertMaterial({
      'kind': 'article',
      'source': 'local',
      'source_id': 'sess',
      'title': 'Session host',
    });
    final fast = await DatabaseService.insertReadingSession(
      materialId: mid,
      words: 300,
      lookups: 4,
      duration: const Duration(minutes: 2),
    );
    expect(fast, greaterThan(0));

    final db = await DatabaseService.database;
    final row = (await db.query(
      'reading_sessions',
      where: 'id = ?',
      whereArgs: [fast],
    )).first;
    expect(row['wpm'], 150.0, reason: '300 词 / 2 分钟');
    expect(row['words'], 300);
    expect(row['lookups'], 4);
    expect(row['material_id'], mid);
    expect(
      DateTime.parse(
        '${row['ended_at']}',
      ).difference(DateTime.parse('${row['started_at']}')).inSeconds,
      120,
    );

    // 边界:时长为 0 → wpm 存 NULL(不是抛异常,也不是 Infinity)
    final instant = await DatabaseService.insertReadingSession(
      words: 300,
      duration: Duration.zero,
    );
    final instantRow = (await db.query(
      'reading_sessions',
      where: 'id = ?',
      whereArgs: [instant],
    )).first;
    expect(instantRow['wpm'], isNull);
    expect(instantRow['words'], 300);
    expect(
      instantRow['started_at'],
      instantRow['ended_at'],
      reason: '零时长:开始=结束,不写未来时间',
    );

    // 90 秒 → 200 wpm(非整分钟也不能算错)
    final mid90 = await DatabaseService.insertReadingSession(
      words: 300,
      duration: const Duration(seconds: 90),
    );
    final row90 = (await db.query(
      'reading_sessions',
      where: 'id = ?',
      whereArgs: [mid90],
    )).first;
    expect(row90['wpm'], 200.0);

    // 统计:4 次会话 / 1560 词 / 9 分钟 / 平均 (150+120)/2
    // (时长刻意用 2 + 0 + 1.5 + 5.5 的整分和:julianday 是浮点,正好落在 X.5 上
    //  会因尾差在 .round() 处抖动,测试要的是"分钟算得对",不是浮点舍入行为)
    await DatabaseService.insertReadingSession(
      words: 660,
      duration: const Duration(minutes: 5, seconds: 30),
    );
    final stats = await DatabaseService.getReadingStats();
    expect(stats['sessions'], 4);
    expect(stats['words'], 1560);
    expect(stats['minutes'], 9);
    expect(
      stats['avg_wpm'],
      156.7,
      reason: '(150 + 200 + 120) / 3:wpm 为 NULL 的会话不参与平均',
    );

    // 窗口:40 天前的会话不进近 30 天统计
    final old = await DatabaseService.insertReadingSession(
      words: 200,
      duration: const Duration(minutes: 2),
    );
    final oldStart = DateTime.now().subtract(const Duration(days: 40));
    await db.update(
      'reading_sessions',
      {
        'started_at': oldStart.toIso8601String(),
        'ended_at': oldStart.add(const Duration(minutes: 2)).toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [old],
    );
    final stats30 = await DatabaseService.getReadingStats();
    expect(stats30['sessions'], 4, reason: '40 天前的会话不进 30 天窗口');
    expect(stats30['words'], 1560);
    expect(stats30['minutes'], 9);
    expect(stats30['avg_wpm'], 156.7);
    final stats60 = await DatabaseService.getReadingStats(days: 60);
    expect(stats60['sessions'], 5);
    expect(stats60['words'], 1760);
    expect(stats60['minutes'], 11);
    expect(stats60['avg_wpm'], 142.5, reason: '(150 + 200 + 120 + 100) / 4');
  });

  // ── 4. 错误标签 ──

  test(
    'bumpErrorTag:累加 + evidence 覆盖;getErrorTags 过滤;fixed 后离开 active',
    () async {
      await DatabaseService.bumpErrorTag(
        source: 'writing',
        tag: 'article_missing',
        evidence: 'I go to school yesterday.',
      );
      await DatabaseService.bumpErrorTag(
        source: 'writing',
        tag: 'article_missing',
        evidence: 'He go home.',
      );
      await DatabaseService.bumpErrorTag(source: 'quiz', tag: 'tense');

      final active = await DatabaseService.getErrorTags(status: 'active');
      expect(active.length, 2);
      expect(
        active.first['tag'],
        'article_missing',
        reason: 'count DESC,错得多的在前',
      );
      expect(active.first['source'], 'writing');
      expect(active.first['count'], 2);
      expect(
        active.first['evidence'],
        'He go home.',
        reason: 'evidence 覆盖成最新一次',
      );
      expect(active.first['status'], 'active');
      expect(
        DateTime.parse(
          '${active.first['last_at']}',
        ).isBefore(DateTime.parse('${active.first['first_at']}')),
        isFalse,
      );
      expect(active.last['tag'], 'tense');
      expect(active.last['count'], 1);
      expect(active.last['evidence'], isNull);

      expect(await DatabaseService.getErrorTags(), hasLength(2));
      expect(
        (await DatabaseService.getErrorTags(
          minCount: 2,
        )).map((r) => r['tag']).toList(),
        ['article_missing'],
      );
      expect(await DatabaseService.getErrorTags(status: 'fixed'), isEmpty);

      // 标 fixed → 离开 active 列表
      final id = active.first['id'] as int;
      expect(await DatabaseService.setErrorTagStatus(id, 'fixed'), 1);
      expect(
        (await DatabaseService.getErrorTags(
          status: 'active',
        )).map((r) => r['tag']).toList(),
        ['tense'],
      );
      expect(
        (await DatabaseService.getErrorTags(
          status: 'fixed',
        )).map((r) => r['tag']).toList(),
        ['article_missing'],
      );
      expect(await DatabaseService.getErrorTags(), hasLength(2));

      // 非法状态不落库(否则按 status 过滤时这条会凭空消失)
      expect(await DatabaseService.setErrorTagStatus(id, 'weird'), 0);
      expect(await DatabaseService.setErrorTagStatus(99999, 'fixed'), 0);
      expect(await DatabaseService.getErrorTags(status: 'fixed'), hasLength(1));

      // 又错了 = 没修好:复发自动回到 active,且不传 evidence 时保留旧证据
      await DatabaseService.bumpErrorTag(
        source: 'writing',
        tag: 'article_missing',
      );
      final afterRelapse = await DatabaseService.getErrorTags(status: 'active');
      expect(afterRelapse.map((r) => r['tag']).toList(), [
        'article_missing',
        'tense',
      ]);
      expect(afterRelapse.first['count'], 3);
      expect(afterRelapse.first['evidence'], 'He go home.');
      expect(
        afterRelapse.first['first_at'],
        active.first['first_at'],
        reason: 'first_at 记的是第一次犯错,不能被刷新',
      );
    },
  );

  // ── 5. 复习状态:upsert + 到期分桶 ──

  test('upsertWordReview:vocab_id 冲突时更新;到期计数与分桶边界(注入 now)', () async {
    final now = DateTime(2026, 3, 10, 10, 0);

    // vocab 1:两次复习 → 必须只有一行
    await DatabaseService.upsertWordReview(
      1,
      stability: 1.0,
      difficulty: 5.0,
      dueAt: DateTime(2026, 3, 8, 9, 0),
      lastRating: 1,
      lastReviewAt: DateTime(2026, 3, 8, 8, 55),
    );
    await DatabaseService.upsertWordReview(
      1,
      stability: 4.5,
      difficulty: 6.5,
      dueAt: DateTime(2026, 3, 9, 8, 0),
      lastRating: 3,
      lastReviewAt: DateTime(2026, 3, 9, 7, 0),
      lapse: true,
    );
    // vocab 2 今天稍晚 / vocab 3 本周内 / vocab 4 更晚
    await DatabaseService.upsertWordReview(
      2,
      stability: 2.0,
      difficulty: 5.0,
      dueAt: DateTime(2026, 3, 10, 21, 0),
      lastReviewAt: now,
    );
    await DatabaseService.upsertWordReview(
      3,
      stability: 3.0,
      difficulty: 5.0,
      dueAt: DateTime(2026, 3, 15, 9, 0),
      lastReviewAt: now,
    );
    await DatabaseService.upsertWordReview(
      4,
      stability: 9.0,
      difficulty: 5.0,
      dueAt: DateTime(2026, 3, 20, 9, 0),
      lastReviewAt: now,
    );
    // 边界:今天 00:00 整 → today;恰好 now + 7 天 → week(闭区间)
    await DatabaseService.upsertWordReview(
      5,
      stability: 1.0,
      difficulty: 5.0,
      dueAt: DateTime(2026, 3, 10, 0, 0),
      lastReviewAt: now,
    );
    await DatabaseService.upsertWordReview(
      6,
      stability: 1.0,
      difficulty: 5.0,
      dueAt: DateTime(2026, 3, 17, 10, 0),
      lastReviewAt: now,
    );
    // vocab 7:第二次不传 lastRating → 保留上一次评级
    await DatabaseService.upsertWordReview(
      7,
      stability: 2.0,
      difficulty: 5.0,
      dueAt: DateTime(2026, 3, 25, 9, 0),
      lastRating: 2,
      lastReviewAt: now,
    );
    await DatabaseService.upsertWordReview(
      7,
      stability: 8.0,
      difficulty: 4.0,
      dueAt: DateTime(2026, 3, 25, 9, 0),
      lastReviewAt: now,
    );

    final db = await DatabaseService.database;
    final rows = await db.query('word_review');
    expect(rows.length, 7, reason: 'vocab_id 冲突必须更新而不是插两行');

    final w1 = (await db.query(
      'word_review',
      where: 'vocab_id = ?',
      whereArgs: [1],
    )).first;
    expect(w1['stability'], 4.5);
    expect(w1['difficulty'], 6.5);
    expect(w1['due_at'], DateTime(2026, 3, 9, 8, 0).toIso8601String());
    expect(w1['last_review_at'], DateTime(2026, 3, 9, 7, 0).toIso8601String());
    expect(w1['last_rating'], 3);
    expect(w1['reps'], 2, reason: '复习一次 reps +1');
    expect(w1['lapses'], 1);

    final w7 = (await db.query(
      'word_review',
      where: 'vocab_id = ?',
      whereArgs: [7],
    )).first;
    expect(w7['stability'], 8.0);
    expect(w7['reps'], 2);
    expect(w7['last_rating'], 2, reason: 'lastRating 传 null = 不覆盖历史评级');

    expect(await DatabaseService.getTrackedReviewCount(), 7);

    // 到期数:3/10 10:00 为止 → vocab1(3/9)+ vocab5(今天 00:00)
    expect(await DatabaseService.getDueReviewCount(at: now), 2);
    // 3/16 00:00 为止 → 再算上 vocab2(3/10 21:00)与 vocab3(3/15)
    expect(
      await DatabaseService.getDueReviewCount(at: DateTime(2026, 3, 16)),
      4,
    );
    expect(
      await DatabaseService.getDueReviewCount(at: DateTime(2026, 3, 1)),
      0,
    );

    // 分桶:overdue 1 / today 2 / week 2 / later 2
    expect(await DatabaseService.getReviewBuckets(now: now), {
      'overdue': 1,
      'today': 2,
      'week': 2,
      'later': 2,
    });
    // 基准挪到 3/17 10:00:前四个词都成了"过期",v6 变成"今天",v4 落进"本周内"
    expect(
      await DatabaseService.getReviewBuckets(now: DateTime(2026, 3, 17, 10, 0)),
      {'overdue': 4, 'today': 1, 'week': 1, 'later': 1},
    );
  });

  // ── 6. 导师任务卡 ──

  test(
    'insertTutorTask/getTutorTasks:只取当天;completeTutorTask 写完成;deleteTutorTask',
    () async {
      final t1 = await DatabaseService.insertTutorTask(
        planDate: DateTime(2026, 3, 10, 8, 0),
        kind: 'review',
        title: '复习 20 个到期词',
        payload: {
          'vocab_ids': [1, 2, 3],
        },
        targetMinutes: 15,
      );
      final t2 = await DatabaseService.insertTutorTask(
        planDate: DateTime(2026, 3, 10, 23, 30),
        kind: 'reading',
        title: '读 800 词精读',
        targetMinutes: 20,
      );
      final t3 = await DatabaseService.insertTutorTask(
        planDate: DateTime(2026, 3, 11, 9, 0),
        kind: 'review',
        title: '明天的卡',
      );
      await DatabaseService.insertTutorTask(
        planDate: DateTime(2026, 3, 9, 9, 0),
        kind: 'review',
        title: '昨天的卡',
      );
      expect([t1, t2, t3].every((id) => id > 0), isTrue);

      final day = await DatabaseService.getTutorTasks(DateTime(2026, 3, 10));
      expect(day.map((t) => t['title']).toList(), [
        '复习 20 个到期词',
        '读 800 词精读',
      ], reason: 'created_at ASC,且相邻日期的卡不能混进来');
      expect(day.first['payload'], {
        'vocab_ids': [1, 2, 3],
      });
      expect(day.first['kind'], 'review');
      expect(day.first['target_minutes'], 15);
      expect(day.first['done_at'], isNull);
      expect(day.first['result'], isNull);
      expect(day[1]['target_minutes'], 20);
      expect(
        (await DatabaseService.getTutorTasks(
          DateTime(2026, 3, 11),
        )).map((t) => t['id']).toList(),
        [t3],
      );
      // plan_date 带时分秒也要能正确归到当天
      expect(
        (await DatabaseService.getTutorTasks(
          DateTime(2026, 3, 10, 15, 45),
        )).map((t) => t['id']).toList(),
        [t1, t2],
      );

      expect(
        await DatabaseService.completeTutorTask(
          t1,
          result: {'correct': 18, 'total': 20},
        ),
        1,
      );
      final afterDone = await DatabaseService.getTutorTasks(
        DateTime(2026, 3, 10),
      );
      final done = afterDone.firstWhere((t) => t['id'] == t1);
      expect(done['result'], {'correct': 18, 'total': 20});
      expect(
        DateTime.parse(
          '${done['done_at']}',
        ).isAfter(DateTime.now().subtract(const Duration(minutes: 1))),
        isTrue,
      );
      expect(
        afterDone.firstWhere((t) => t['id'] == t2)['done_at'],
        isNull,
        reason: '只勾掉被点的那张卡',
      );
      expect(await DatabaseService.completeTutorTask(99999), 0);

      // v2.4(A5):勾选要能来回切换 —— 用户实测"划去任务后没法再点回来"
      expect(await DatabaseService.reopenTutorTask(t1), 1);
      final afterReopen = await DatabaseService.getTutorTasks(
        DateTime(2026, 3, 10),
      );
      final reopened = afterReopen.firstWhere((t) => t['id'] == t1);
      expect(reopened['done_at'], isNull, reason: '取消完成后要回到待办');
      expect(reopened['result'], isNull, reason: '结果一并清掉,不留半截状态');
      expect(reopened['title'], done['title'], reason: '任务本身不能被动到');
      expect(await DatabaseService.reopenTutorTask(99999), 0);

      expect(await DatabaseService.deleteTutorTask(t1), 1);
      expect(
        (await DatabaseService.getTutorTasks(
          DateTime(2026, 3, 10),
        )).map((t) => t['title']).toList(),
        ['读 800 词精读'],
      );
      expect(await DatabaseService.deleteTutorTask(t1), 0);
    },
  );

  // ── 7. 导师对话 ──

  test(
    'insertTutorMessage/getTutorMessages:时间正序、limit 取最新 N 条;clearTutorMessages',
    () async {
      final base = DateTime(2026, 3, 10, 9, 0);
      await DatabaseService.insertTutorMessage(
        role: 'user',
        content: 'm1',
        at: base,
      );
      await DatabaseService.insertTutorMessage(
        role: 'assistant',
        content: 'm2',
        toolCalls: 'lookup_word',
        at: base.add(const Duration(minutes: 1)),
      );
      await DatabaseService.insertTutorMessage(
        role: 'user',
        content: 'm3',
        at: base.add(const Duration(minutes: 2)),
      );

      final all = await DatabaseService.getTutorMessages();
      expect(all.map((m) => m['content']).toList(), ['m1', 'm2', 'm3']);
      expect(all.map((m) => m['role']).toList(), ['user', 'assistant', 'user']);
      expect(all[1]['tool_calls'], 'lookup_word');
      expect(all.first['created_at'], base.toIso8601String());
      expect(
        all.last['created_at'],
        base.add(const Duration(minutes: 2)).toIso8601String(),
      );

      final latest2 = await DatabaseService.getTutorMessages(limit: 2);
      expect(
        latest2.map((m) => m['content']).toList(),
        ['m2', 'm3'],
        reason: 'limit 作用在最新的 N 条上,返回仍是时间正序',
      );

      await DatabaseService.clearTutorMessages();
      expect(await DatabaseService.getTutorMessages(), isEmpty);
    },
  );

  // ── 8. 导师长期记忆 ──

  test('tutor_memory:新增、按时间倒序读取、删除', () async {
    final id1 = await DatabaseService.addTutorMemory(
      kind: 'preference',
      text: '喜欢外刊精读,不喜欢背单词表',
    );
    final id2 = await DatabaseService.addTutorMemory(
      kind: 'obstacle',
      text: '虚拟语气总出错',
    );
    expect([id1, id2].every((id) => id > 0), isTrue);

    final memories = await DatabaseService.getTutorMemories();
    expect(memories.length, 2);
    expect(memories.first['text'], '虚拟语气总出错', reason: 'created_at DESC,新的在前');
    expect(memories.first['kind'], 'obstacle');
    expect(memories.last['kind'], 'preference');
    expect(memories.last['text'], '喜欢外刊精读,不喜欢背单词表');
    expect(
      (await DatabaseService.getTutorMemories(limit: 1)).single['text'],
      '虚拟语气总出错',
    );

    expect(await DatabaseService.deleteTutorMemory(id2), 1);
    final left = await DatabaseService.getTutorMemories();
    expect(left.length, 1);
    expect(left.single['text'], '喜欢外刊精读,不喜欢背单词表');
    expect(await DatabaseService.deleteTutorMemory(id2), 0);
  });

  // ── 9. 快照聚合 ──

  test('聚合:mastery 分布、近 N 天生词、按 word_type 计数', () async {
    await DatabaseService.insertVocabularies([
      Vocabulary(word: 'alpha', masteryLevel: 0),
      Vocabulary(word: 'beta', masteryLevel: 0),
      Vocabulary(word: 'gamma', masteryLevel: 1),
      Vocabulary(word: 'delta', masteryLevel: 2),
      Vocabulary(word: 'give up', wordType: 'phrase', masteryLevel: 2),
      Vocabulary(
        word: 'It is what it is.',
        wordType: 'sentence',
        masteryLevel: 1,
      ),
    ]);

    expect(await DatabaseService.getMasteryDistribution(), {
      '0': 2,
      '1': 2,
      '2': 2,
    });
    expect(await DatabaseService.getVocabCountByWordType('word'), 4);
    expect(await DatabaseService.getVocabCountByWordType('phrase'), 1);
    expect(await DatabaseService.getVocabCountByWordType('sentence'), 1);
    expect(await DatabaseService.getVocabCountByWordType('idiom'), 0);

    expect(
      await DatabaseService.getVocabCountSince(
        DateTime.now().subtract(const Duration(days: 1)),
      ),
      6,
    );
    expect(
      await DatabaseService.getVocabCountSince(
        DateTime.now().add(const Duration(days: 1)),
      ),
      0,
    );

    // 把 alpha 挪到 30 天前:7 天窗口里不该再有它
    final db = await DatabaseService.database;
    await db.update(
      'vocabulary',
      {
        'created_at': DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String(),
      },
      where: 'word = ?',
      whereArgs: ['alpha'],
    );
    final recent = await DatabaseService.getRecentVocabularies();
    expect(recent.length, 5);
    expect(recent.map((v) => v.word), isNot(contains('alpha')));
    expect(recent.first.word, 'It is what it is.', reason: 'created_at DESC');
    expect(recent.first.wordType, 'sentence');
    expect(recent.map((v) => v.word).toList(), [
      'It is what it is.',
      'give up',
      'delta',
      'gamma',
      'beta',
    ], reason: '逆序入库 → 倒序读回;挪走 alpha 后剩 5 条');
    expect(
      (await DatabaseService.getRecentVocabularies(
        limit: 2,
      )).map((v) => v.word).toList(),
      ['It is what it is.', 'give up'],
    );
    expect(
      await DatabaseService.getVocabCountSince(
        DateTime.now().subtract(const Duration(days: 1)),
      ),
      5,
      reason: '挪走的那条不再计入近一天',
    );
  });

  // ── 10. 坏数据不崩 ──

  test('坏数据/坏 JSON:解析失败给 null,不抛异常', () async {
    final db = await DatabaseService.database;
    final id = await DatabaseService.insertTutorTask(
      planDate: DateTime(2026, 3, 10),
      kind: 'review',
      title: '带坏的 JSON 的卡',
      payload: {
        'vocab_ids': [1],
      },
    );
    await db.rawUpdate(
      "UPDATE tutor_tasks SET payload_json = '{坏', result_json = 'not json' "
      'WHERE id = ?',
      [id],
    );

    final tasks = await DatabaseService.getTutorTasks(DateTime(2026, 3, 10));
    expect(tasks.length, 1);
    expect(tasks.first['payload'], isNull, reason: '坏 JSON → null,不是抛异常');
    expect(tasks.first['result'], isNull);
    expect(tasks.first['payload_json'], '{坏', reason: '原始串保留,便于排查');
    expect(tasks.first['title'], '带坏的 JSON 的卡');

    final quizId = await DatabaseService.insertQuizResult(
      kind: 'reading_quiz',
      total: 5,
      correct: 4,
      detail: {'q1': true},
    );
    await db.rawUpdate(
      "UPDATE quiz_results SET detail_json = '{{' WHERE id = ?",
      [quizId],
    );
    final quizzes = await DatabaseService.getQuizResults();
    expect(quizzes.length, 1);
    expect(quizzes.first['detail'], isNull);
    expect(quizzes.first['total'], 5);
    expect(quizzes.first['correct'], 4);
    expect(await DatabaseService.getQuizAccuracy(), {'reading_quiz': 0.8});

    final mid = await DatabaseService.upsertMaterial({
      'kind': 'article',
      'source': 's',
      'source_id': 'x',
      'title': '坏难度',
    });
    await db.rawUpdate(
      "UPDATE materials SET difficulty_json = 'x{' WHERE id = ?",
      [mid],
    );
    final material = await DatabaseService.getMaterialById(mid);
    expect(material!['difficulty'], isNull);
    expect(material['title'], '坏难度');
    expect((await DatabaseService.getMaterials()).length, 1);

    // 非法入参不该抛异常,也不该写脏行
    expect(
      await DatabaseService.insertTutorTask(
        planDate: DateTime(2026, 3, 10),
        kind: 'review',
        title: '好卡',
      ),
      greaterThan(0),
    );
    final dayTasks = await DatabaseService.getTutorTasks(DateTime(2026, 3, 10));
    expect(dayTasks.length, 2);
    expect(dayTasks.last['title'], '好卡');
  });

  // ── 11. deleteMaterial 级联 ──

  test('deleteMaterial:级联删掉 chunks 与 progress,不误伤其它材料', () async {
    final mid = await DatabaseService.upsertMaterial(
      {
        'kind': 'book',
        'source': 'gutenberg',
        'source_id': 'pg-1',
        'title': '要被删的材料',
      },
      chunks: [
        {'chunk_index': 0, 'text': 'chunk 0'},
        {'chunk_index': 1, 'text': 'chunk 1'},
      ],
    );
    await DatabaseService.upsertMaterialProgress(
      mid,
      position: 100,
      percent: 0.5,
      addMinutes: 4,
      addLookups: 2,
    );
    await DatabaseService.insertReadingSession(
      materialId: mid,
      words: 100,
      duration: const Duration(minutes: 1),
    );

    final keep = await DatabaseService.upsertMaterial(
      {
        'kind': 'book',
        'source': 'gutenberg',
        'source_id': 'pg-2',
        'title': '要留下的材料',
      },
      chunks: [
        {'chunk_index': 0, 'text': 'keep chunk'},
      ],
    );
    await DatabaseService.upsertMaterialProgress(
      keep,
      position: 10,
      percent: 1.0,
      finished: true,
    );

    expect(await DatabaseService.countMaterialsFinished(), 1);
    expect((await DatabaseService.getMaterialChunks(mid)).length, 2);
    expect((await DatabaseService.getRecentMaterials()).length, 2);

    expect(await DatabaseService.deleteMaterial(mid), 1);

    final db = await DatabaseService.database;
    expect(await DatabaseService.getMaterialById(mid), isNull);
    expect(await DatabaseService.getMaterialChunks(mid), isEmpty);
    expect(await DatabaseService.getMaterialProgress(mid), isNull);
    expect(
      (await db.query(
        'material_content',
        where: 'material_id = ?',
        whereArgs: [mid],
      )).length,
      0,
      reason: '正文分块不能留孤儿行',
    );
    expect(
      (await db.query(
        'material_progress',
        where: 'material_id = ?',
        whereArgs: [mid],
      )).length,
      0,
    );
    expect(
      (await db.query(
        'reading_sessions',
        where: 'material_id = ?',
        whereArgs: [mid],
      )).length,
      1,
      reason: '会话是行为历史:删材料不等于抹掉"我读过"',
    );

    // 不误伤邻居
    expect(
      (await DatabaseService.getMaterialChunks(keep)).single['text'],
      'keep chunk',
    );
    final keepProgress = await DatabaseService.getMaterialProgress(keep);
    expect(keepProgress!['percent'], 1.0);
    expect(keepProgress['minutes'], 0);
    expect(await DatabaseService.countMaterialsFinished(), 1);
    expect(
      (await DatabaseService.getRecentMaterials()).single['title'],
      '要留下的材料',
    );
    expect(await DatabaseService.deleteMaterial(mid), 0, reason: '重复删除返回 0');
  });

  // ── 12. 测验记录与正确率 ──

  test('quiz_results:按 kind 过滤/排序,正确率按 kind 合计,窗口外不计', () async {
    await DatabaseService.insertQuizResult(
      kind: 'vocab_placement',
      total: 25,
      correct: 18,
      detail: {'band': 1},
    );
    await DatabaseService.insertQuizResult(
      kind: 'vocab_placement',
      total: 25,
      correct: 20,
      detail: {'band': 2},
    );
    await DatabaseService.insertQuizResult(
      kind: 'reading_quiz',
      refId: 7,
      total: 10,
      correct: 10,
    );

    expect(await DatabaseService.getQuizResults(), hasLength(3));
    final placements = await DatabaseService.getQuizResults(
      kind: 'vocab_placement',
    );
    expect(placements.length, 2);
    expect(placements.first['detail'], {'band': 2}, reason: '新的在前');
    expect(placements.last['detail'], {'band': 1});
    final newest = await DatabaseService.getQuizResults(limit: 1);
    expect(newest.single['kind'], 'reading_quiz');
    expect(newest.single['ref_id'], 7);

    // 正确率:按 kind 先合计再相除(38/50),零题的 kind 不进表
    expect(await DatabaseService.getQuizAccuracy(), {
      'vocab_placement': 0.76,
      'reading_quiz': 1.0,
    });
    await DatabaseService.insertQuizResult(
      kind: 'empty_quiz',
      total: 0,
      correct: 0,
    );
    expect(
      (await DatabaseService.getQuizAccuracy()).containsKey('empty_quiz'),
      isFalse,
      reason: 'total=0 不能算出 NaN/除零',
    );

    // 40 天前的历史不进 30 天窗口
    final db = await DatabaseService.database;
    await db.update(
      'quiz_results',
      {
        'created_at': DateTime.now()
            .subtract(const Duration(days: 40))
            .toIso8601String(),
      },
      where: 'kind = ?',
      whereArgs: ['reading_quiz'],
    );
    expect(await DatabaseService.getQuizAccuracy(), {'vocab_placement': 0.76});
    expect(await DatabaseService.getQuizAccuracy(days: 60), {
      'vocab_placement': 0.76,
      'reading_quiz': 1.0,
    });
  });
}
