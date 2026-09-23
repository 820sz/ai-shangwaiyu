import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import '../config/constants.dart';
import '../models/vocabulary.dart';
import '../models/article.dart';
import '../models/exercise.dart';
import '../models/learning_record.dart';
import '../models/bookmark.dart';
import '../models/writing_log.dart';
import '../models/material_recommendation.dart';
import '../utils/page_label.dart';

/// 本地 SQLite 数据库服务 — 生词、文章、练习、学习记录全部落本地
class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  /// 仅供测试:关掉缓存连接,让下一次 [database] 重新走 open/onCreate/onUpgrade。
  /// 迁移测试需要在同一个测试进程里连续验证"全新安装"与"从旧版本升级"两条路径,
  /// 没有这个钩子就只能测到第一条。
  @visibleForTesting
  static Future<void> resetForTest() async {
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
  }

  /// 连接级配置:开外键约束(v1.9.0,审查 P1-9)。
  /// sqlite 默认关闭外键 → `deleteArticle` 删文章后 exercises 变成孤儿行,
  /// 还被 `getTotalExerciseCount` 计入"已完成练习"(用户看到练习数虚高)。
  static Future<void> _onConfigure(Database db) async {
    try {
      await db.execute('PRAGMA foreign_keys = ON');
    } catch (e) {
      debugPrint('ReadFlow PRAGMA foreign_keys failed: $e');
    }
  }

  // ═══════════════ 表结构(单一事实源) ═══════════════
  // onCreate 与「自检补建」共用同一份 SQL —— 审查 P0-2 的延伸:
  // 旧实现 onCreate 里的 vocabulary **没有 phonetic 列**(只在 v7 迁移里加),
  // 于是"全新安装"的库缺列,而 Vocabulary.toMap 无条件写 phonetic →
  // 新装用户保存生词直接抛 "no such column: phonetic"(换签名重装必然踩到)。

  static const String _vocabularyTableSql = '''
      CREATE TABLE vocabulary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL,
        translation TEXT,
        source_book TEXT,
        source_page TEXT,
        original_sentence TEXT,
        photo_path TEXT,
        word_type TEXT DEFAULT 'word',
        mastery_level INTEGER DEFAULT 0,
        part_of_speech TEXT,
        grammar_note TEXT,
        phonetic TEXT,
        -- v2.0:英式/美式双音标(学习偏好里可切音色;两列与迁移里的 _ensureColumn 同名)
        phonetic_uk TEXT,
        phonetic_us TEXT,
        category TEXT DEFAULT '其他',
        material_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''';

  static const String _articlesTableSql = '''
      CREATE TABLE articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        translation TEXT,
        vocab_ids TEXT DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''';

  static const String _exercisesTableSql = '''
      CREATE TABLE exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        article_id INTEGER NOT NULL,
        type TEXT DEFAULT 'back_translation',
        source_sentences TEXT NOT NULL,
        reference_answers TEXT,
        user_answers TEXT,
        score REAL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (article_id) REFERENCES articles (id) ON DELETE CASCADE
      )
    ''';

  static const String _dailyLogTableSql = '''
      CREATE TABLE daily_log (
        date TEXT PRIMARY KEY,
        new_words_count INTEGER DEFAULT 0,
        reviewed_count INTEGER DEFAULT 0,
        exercise_completed INTEGER DEFAULT 0,
        study_minutes INTEGER DEFAULT 0
      )
    ''';

  static const String _memoryTableSql = '''
      CREATE TABLE memory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        category TEXT DEFAULT 'general',
        created_at TEXT NOT NULL
      )
    ''';

  static const String _bookmarksTableSql = '''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        title TEXT,
        content TEXT NOT NULL,
        source_word TEXT,
        model TEXT,
        created_at TEXT NOT NULL
      )
    ''';

  static const String _writingLogsTableSql = '''
      CREATE TABLE writing_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_type TEXT NOT NULL DEFAULT 'electronic',
        original_text TEXT NOT NULL,
        corrected_text TEXT,
        score TEXT,
        summary TEXT,
        issues_json TEXT,
        error_summary_json TEXT,
        model TEXT,
        image_paths TEXT,
        created_at TEXT NOT NULL
      )
    ''';

  static const String _recommendationsTableSql = '''
      CREATE TABLE recommendations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        summary TEXT,
        level TEXT,
        reason TEXT,
        keywords TEXT,
        content TEXT,
        profile_snapshot TEXT,
        created_at TEXT NOT NULL
      )
    ''';

  /// 索引清单(v1.9.0,审查 P1-9):新库直接建,老库在打开自检里补。
  /// 此前 9 张表**零索引**,热路径全是全表扫描 + 临时排序:
  /// 生词按时间倒序、按书/分类筛选、分类计数、练习按文章查、各列表倒序。
  static const List<String> _indexStatements = [
    'CREATE INDEX IF NOT EXISTS idx_vocab_created ON vocabulary(created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_vocab_book ON vocabulary(source_book)',
    'CREATE INDEX IF NOT EXISTS idx_vocab_category ON vocabulary(category, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_vocab_material ON vocabulary(category, material_path)',
    'CREATE INDEX IF NOT EXISTS idx_exercise_article ON exercises(article_id, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_article_created ON articles(created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_bookmark_created ON bookmarks(created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_writing_log_created ON writing_logs(created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_recommend_category ON recommendations(category, created_at DESC)',
    // ── v2.0(dbVersion 11)──
    // 复习队列按到期时间取词是最热的查询(每次打开导师页/复习页都要算)
    'CREATE INDEX IF NOT EXISTS idx_word_review_due ON word_review(due_at)',
    'CREATE INDEX IF NOT EXISTS idx_materials_kind ON materials(kind, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_materials_source ON materials(source, source_id)',
    'CREATE INDEX IF NOT EXISTS idx_material_progress_updated ON material_progress(updated_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_reading_started ON reading_sessions(started_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_quiz_kind ON quiz_results(kind, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_error_tag ON error_tags(tag, status)',
    'CREATE INDEX IF NOT EXISTS idx_tutor_task_date ON tutor_tasks(plan_date, done_at)',
    'CREATE INDEX IF NOT EXISTS idx_tutor_msg_created ON tutor_messages(created_at DESC)',
  ];

  // ═══════════════ v2.0(dbVersion 11)新增表 ═══════════════
  // 设计原则(对应 PLAN-2.0 §7):
  // - **明细进 SQL,单行配置留在 Hive**(学习者模型是单行 JSON,放 Hive 更合适);
  // - 每张表都带 `created_at`,便于"按时间倒序"与复盘;
  // - 外键暂不声明:SQLite 的外键需要每次连接开启,而历史数据里有孤儿行,
  //   这里用**定期清理**代替硬约束(与 v1.9.0 清孤儿练习同一思路)。

  /// 词级复习状态(FSRS):v2.1 起驱动复习队列,先建表并在迁移时初始化
  static const String _wordReviewTableSql = '''
    CREATE TABLE IF NOT EXISTS word_review (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      vocab_id INTEGER NOT NULL UNIQUE,
      stability REAL NOT NULL DEFAULT 0,
      difficulty REAL NOT NULL DEFAULT 0,
      due_at TEXT,
      last_review_at TEXT,
      reps INTEGER NOT NULL DEFAULT 0,
      lapses INTEGER NOT NULL DEFAULT 0,
      last_rating INTEGER,
      created_at TEXT,
      updated_at TEXT
    )
  ''';

  /// 材料元数据(材料中心):不存正文,正文分块在 material_content
  static const String _materialsTableSql = '''
    CREATE TABLE IF NOT EXISTS materials (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      source TEXT NOT NULL,
      source_id TEXT,
      title TEXT NOT NULL,
      author TEXT,
      url TEXT,
      license TEXT,
      language TEXT DEFAULT 'en',
      word_count INTEGER DEFAULT 0,
      unique_words INTEGER DEFAULT 0,
      cefr TEXT,
      flesch REAL,
      coverage REAL,
      new_word_density REAL,
      est_minutes INTEGER,
      chapters INTEGER DEFAULT 0,
      audio_url TEXT,
      transcript_ref TEXT,
      difficulty_json TEXT,
      created_at TEXT,
      cached_at TEXT
    )
  ''';

  /// 材料正文分块(按章/段):阅读器按块加载,避免整本进内存
  static const String _materialContentTableSql = '''
    CREATE TABLE IF NOT EXISTS material_content (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL,
      chunk_index INTEGER NOT NULL,
      title TEXT,
      text TEXT NOT NULL,
      UNIQUE(material_id, chunk_index)
    )
  ''';

  /// 阅读进度(一份材料一行)
  static const String _materialProgressTableSql = '''
    CREATE TABLE IF NOT EXISTS material_progress (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL UNIQUE,
      position INTEGER DEFAULT 0,
      percent REAL DEFAULT 0,
      minutes INTEGER DEFAULT 0,
      lookups INTEGER DEFAULT 0,
      picked_words INTEGER DEFAULT 0,
      started_at TEXT,
      finished_at TEXT,
      updated_at TEXT
    )
  ''';

  /// 阅读/听力会话(行为数据的原子记录:导师与统计都读它)
  static const String _readingSessionsTableSql = '''
    CREATE TABLE IF NOT EXISTS reading_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER,
      article_id INTEGER,
      started_at TEXT,
      ended_at TEXT,
      words INTEGER DEFAULT 0,
      lookups INTEGER DEFAULT 0,
      wpm REAL,
      created_at TEXT
    )
  ''';

  /// 测验结果(词汇量测试 / 读后测验 / 回译 / 听写统一进这张表)
  static const String _quizResultsTableSql = '''
    CREATE TABLE IF NOT EXISTS quiz_results (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      ref_id INTEGER,
      total INTEGER DEFAULT 0,
      correct INTEGER DEFAULT 0,
      detail_json TEXT,
      created_at TEXT
    )
  ''';

  /// 错误标签画像(v2.1 错误档案的地基;现在就开始记,历史越早越值钱)
  static const String _errorTagsTableSql = '''
    CREATE TABLE IF NOT EXISTS error_tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source TEXT NOT NULL,
      tag TEXT NOT NULL,
      count INTEGER NOT NULL DEFAULT 1,
      first_at TEXT,
      last_at TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      evidence TEXT
    )
  ''';

  /// 导师任务卡
  static const String _tutorTasksTableSql = '''
    CREATE TABLE IF NOT EXISTS tutor_tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      plan_date TEXT NOT NULL,
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      payload_json TEXT,
      target_minutes INTEGER DEFAULT 0,
      done_at TEXT,
      result_json TEXT,
      created_at TEXT
    )
  ''';

  /// 导师会话(长期记忆的另一半:短期对话)
  static const String _tutorMessagesTableSql = '''
    CREATE TABLE IF NOT EXISTS tutor_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      tool_calls TEXT,
      created_at TEXT
    )
  ''';

  /// 导师长期记忆(用户偏好/承诺/障碍/结论)
  static const String _tutorMemoryTableSql = '''
    CREATE TABLE IF NOT EXISTS tutor_memory (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      text TEXT NOT NULL,
      created_at TEXT
    )
  ''';

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute(_vocabularyTableSql);
    await db.execute(_articlesTableSql);
    await db.execute(_exercisesTableSql);
    await db.execute(_dailyLogTableSql);
    await db.execute(_memoryTableSql);
    await db.execute(_bookmarksTableSql);
    await db.execute(_writingLogsTableSql);
    await db.execute(_recommendationsTableSql);
    // v2.0
    await db.execute(_wordReviewTableSql);
    await db.execute(_materialsTableSql);
    await db.execute(_materialContentTableSql);
    await db.execute(_materialProgressTableSql);
    await db.execute(_readingSessionsTableSql);
    await db.execute(_quizResultsTableSql);
    await db.execute(_errorTagsTableSql);
    await db.execute(_tutorTasksTableSql);
    await db.execute(_tutorMessagesTableSql);
    await db.execute(_tutorMemoryTableSql);
    await _createIndexes(db);
  }

  /// 迁移(v1.9.0 重写,审查 P0-2):
  /// - **每一步都是幂等写法**(先查 `PRAGMA table_info` / `sqlite_master`,
  ///   缺什么补什么),不再靠 catch 兜"列已存在"这种正常情况;
  /// - **真正的失败一律向上抛** —— sqflite 只在 onUpgrade 正常返回后才写
  ///   `user_version`,旧实现把异常吞成 debugPrint 会让"半迁移"被永久固化;
  /// - 大批量改写(material_path / source_page 归一)放进**单事务**,
  ///   失败整体回滚,下次启动重跑。
  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await _ensureColumn(db, 'vocabulary', 'part_of_speech', 'TEXT');
      await _ensureColumn(db, 'vocabulary', 'grammar_note', 'TEXT');
      await _ensureTable(db, 'daily_log', _dailyLogTableSql);
    }
    if (oldV < 3) {
      await _ensureColumn(db, 'vocabulary', 'category', "TEXT DEFAULT '其他'");
      await _ensureColumn(db, 'vocabulary', 'material_path', 'TEXT');
    }
    if (oldV < 4) {
      await _ensureColumn(db, 'exercises', 'reference_answers', 'TEXT');
    }
    if (oldV < 5) {
      await _ensureColumn(db, 'articles', 'translation', 'TEXT');
    }
    if (oldV < 6) {
      await _ensureTable(db, 'bookmarks', _bookmarksTableSql);
    }
    if (oldV < 7) {
      await _ensureColumn(db, 'vocabulary', 'phonetic', 'TEXT');
    }
    if (oldV < 8) {
      // 书籍路径归一:旧数据把页码拼进 material_path,同一本书被按页拆成
      // 多个文件夹 → 归一为 '书籍/《X》' + source_page。
      await _normalizeBookPaths(db);
      await _ensureTable(db, 'writing_logs', _writingLogsTableSql);
    }
    if (oldV < 9) {
      // 页码归一:pp9页/第9页/9 → p9(与 normalizePageLabel 同规则)
      await _normalizePageLabels(db);
      await _ensureTable(db, 'recommendations', _recommendationsTableSql);
    }
    if (oldV < 10) {
      await _createIndexes(db);
      await _cleanOrphanExercises(db);
    }
    if (oldV < 11) {
      // v2.0:材料中心 / 复习状态 / 导师 的明细表,外加英式美式两套音标列。
      // 全部是"新建表 + 加列",不动既有数据 → 失败回滚也不会丢东西。
      await _ensureTable(db, 'word_review', _wordReviewTableSql);
      await _ensureTable(db, 'materials', _materialsTableSql);
      await _ensureTable(db, 'material_content', _materialContentTableSql);
      await _ensureTable(db, 'material_progress', _materialProgressTableSql);
      await _ensureTable(db, 'reading_sessions', _readingSessionsTableSql);
      await _ensureTable(db, 'quiz_results', _quizResultsTableSql);
      await _ensureTable(db, 'error_tags', _errorTagsTableSql);
      await _ensureTable(db, 'tutor_tasks', _tutorTasksTableSql);
      await _ensureTable(db, 'tutor_messages', _tutorMessagesTableSql);
      await _ensureTable(db, 'tutor_memory', _tutorMemoryTableSql);
      // v2.0 决策:音标英式美式都给(词条同时显示两套)
      await _ensureColumn(db, 'vocabulary', 'phonetic_uk', 'TEXT');
      await _ensureColumn(db, 'vocabulary', 'phonetic_us', 'TEXT');
      await _createIndexes(db);
      await _seedWordReviewFromMastery(db);
    }
  }

  /// 打开后自检(v1.9.0,审查 P0-2 的兜底):
  /// 万一历史迁移曾经静默失败(旧版本吞过异常),这里把缺的列/表/索引补上,
  /// 让"半迁移库"能自愈,而不是永久坏在用户手机上。
  static Future<void> _onOpen(Database db) async {
    final repaired = <String>[];
    try {
      await _ensureColumn(db, 'vocabulary', 'part_of_speech', 'TEXT', repaired);
      await _ensureColumn(db, 'vocabulary', 'grammar_note', 'TEXT', repaired);
      await _ensureColumn(db, 'vocabulary', 'category', "TEXT DEFAULT '其他'", repaired);
      await _ensureColumn(db, 'vocabulary', 'material_path', 'TEXT', repaired);
      await _ensureColumn(db, 'vocabulary', 'phonetic', 'TEXT', repaired);
      await _ensureColumn(db, 'vocabulary', 'phonetic_uk', 'TEXT', repaired);
      await _ensureColumn(db, 'vocabulary', 'phonetic_us', 'TEXT', repaired);
      await _ensureColumn(db, 'exercises', 'reference_answers', 'TEXT', repaired);
      await _ensureColumn(db, 'articles', 'translation', 'TEXT', repaired);
      await _ensureTable(db, 'daily_log', _dailyLogTableSql, repaired);
      await _ensureTable(db, 'bookmarks', _bookmarksTableSql, repaired);
      await _ensureTable(db, 'writing_logs', _writingLogsTableSql, repaired);
      await _ensureTable(db, 'recommendations', _recommendationsTableSql, repaired);
      // v2.0 的十张表也在自检范围内:历史库若曾静默失败,这里补上
      await _ensureTable(db, 'word_review', _wordReviewTableSql, repaired);
      await _ensureTable(db, 'materials', _materialsTableSql, repaired);
      await _ensureTable(db, 'material_content', _materialContentTableSql, repaired);
      await _ensureTable(db, 'material_progress', _materialProgressTableSql, repaired);
      await _ensureTable(db, 'reading_sessions', _readingSessionsTableSql, repaired);
      await _ensureTable(db, 'quiz_results', _quizResultsTableSql, repaired);
      await _ensureTable(db, 'error_tags', _errorTagsTableSql, repaired);
      await _ensureTable(db, 'tutor_tasks', _tutorTasksTableSql, repaired);
      await _ensureTable(db, 'tutor_messages', _tutorMessagesTableSql, repaired);
      await _ensureTable(db, 'tutor_memory', _tutorMemoryTableSql, repaired);
      await _createIndexes(db);
      // v2.0 不变式:每个生词都有一条复习状态(word_review)。
      // 放在自检里而不是只放迁移里:这样"迁移后新增的词"也有状态,
      // v2.1 的复习队列不会因为缺少记录而漏词(幂等,只补缺的)。
      await _seedWordReviewFromMastery(db);
    } catch (e) {
      // 自检是"尽力而为":绝不因为补建失败而让 App 起不来
      debugPrint('ReadFlow DB 自检失败: $e');
    }
    if (repaired.isNotEmpty) {
      debugPrint('ReadFlow DB 自检补建: ${repaired.join(', ')}');
    }
  }

  /// 用旧的 `mastery_level` 给 FSRS 状态一个**保守初值**(v2.0 → v2.1 的衔接)。
  ///
  /// 语义:新词(0) = 从未复习,due 立刻;学习中(1) = 刚接触,3 天后到期;
  /// 已掌握(2) = 给 14 天稳定期,但**绝不设成永不到期** —— 旧数据没有复习
  /// 历史,把它当"已经记住"正是 v1.9 复习模式的病根(用户实测"点认识能一直
  /// 刷进度")。宁可让老词重新排队,也不要让复习队列永远空着。
  ///
  /// 幂等:只为还没有 word_review 记录的词插入(LEFT JOIN ... IS NULL)。
  static Future<void> _seedWordReviewFromMastery(Database db) async {
    try {
      final rows = await db.rawQuery('''
        SELECT v.id AS vid, v.mastery_level AS m
        FROM vocabulary v
        LEFT JOIN word_review r ON r.vocab_id = v.id
        WHERE r.id IS NULL
      ''');
      if (rows.isEmpty) return;
      final now = DateTime.now();
      final iso = now.toIso8601String();
      final batch = db.batch();
      for (final r in rows) {
        final vid = r['vid'] as int?;
        if (vid == null) continue;
        final m = (r['m'] as int?) ?? 0;
        final int days = switch (m) {
          2 => 14,
          1 => 3,
          _ => 0,
        };
        batch.insert('word_review', {
          'vocab_id': vid,
          'stability': days.toDouble(),
          'difficulty': 5.0,
          'due_at': now.add(Duration(days: days)).toIso8601String(),
          'reps': m == 0 ? 0 : 1,
          'lapses': 0,
          'created_at': iso,
          'updated_at': iso,
        });
      }
      await batch.commit(noResult: true);
      debugPrint('ReadFlow 复习状态初始化: ${rows.length} 个词');
    } catch (e) {
      // 初值失败不能挡住启动:复习队列下一版会自己补
      debugPrint('ReadFlow 复习状态初始化失败(不影响启动): $e');
    }
  }

  /// 幂等补列:先查 `PRAGMA table_info`,缺了才 ALTER
  static Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String type, [
    List<String>? repaired,
  ]) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (info.isEmpty) {
      // 表都不存在:交给 _ensureTable 处理
      return;
    }
    final has = info.any((r) => (r['name'] as String?) == column);
    if (has) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    repaired?.add('$table.$column');
  }

  /// 幂等建表:不存在才建(表结构来自上面的常量)
  static Future<void> _ensureTable(
    Database db,
    String table,
    String createSql, [
    List<String>? repaired,
  ]) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    if (rows.isNotEmpty) return;
    await db.execute(createSql);
    repaired?.add(table);
  }

  static Future<void> _createIndexes(Database db) async {
    for (final sql in _indexStatements) {
      try {
        await db.execute(sql);
      } catch (e) {
        // 索引缺失只影响性能,不影响正确性:单条失败不阻断打开
        debugPrint('ReadFlow create index failed ($sql): $e');
      }
    }
  }

  /// v8:书籍材料路径归一(单事务批量,失败整体回滚)
  static Future<void> _normalizeBookPaths(Database db) async {
    final rows = await db.query(
      'vocabulary',
      columns: ['id', 'material_path', 'source_page'],
      where: "category = ? AND material_path LIKE ?",
      whereArgs: ['书籍', '书籍/%/%'],
    );
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in rows) {
        final path = (r['material_path'] as String?) ?? '';
        final parts = path
            .split('/')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.length < 3 || parts[0] != '书籍') continue;
        final bookPath = '${parts[0]}/${parts[1]}';
        final page = parts.sublist(2).join('/').trim();
        final existingPage = (r['source_page'] as String?)?.trim() ?? '';
        batch.update(
          'vocabulary',
          {
            'material_path': bookPath,
            if (existingPage.isEmpty && page.isNotEmpty) 'source_page': page,
          },
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// v9:页码/章节标签归一(单事务批量)
  static Future<void> _normalizePageLabels(Database db) async {
    final rows = await db.query(
      'vocabulary',
      columns: ['id', 'source_page'],
      where: "source_page IS NOT NULL AND source_page != ''",
    );
    if (rows.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in rows) {
        final raw = (r['source_page'] as String?) ?? '';
        final normalized = normalizePageLabel(raw);
        if (normalized.isEmpty || normalized == raw) continue;
        batch.update(
          'vocabulary',
          {'source_page': normalized},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// v10:清理孤儿练习行(开外键前积累的历史脏数据)
  static Future<void> _cleanOrphanExercises(Database db) async {
    await db.rawDelete(
      'DELETE FROM exercises WHERE article_id NOT IN (SELECT id FROM articles)',
    );
  }

  // ═══════════════ 生词 CRUD ═══════════════

  static Future<int> insertVocabulary(Vocabulary v) async {
    final db = await database;
    return db.insert('vocabulary', v.toMap());
  }

  /// 批量插入生词（用于 AI 返回多条结果时）
  static Future<int> insertVocabularies(List<Vocabulary> list) async {
    final db = await database;
    int count = 0;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final v in list) {
        batch.insert('vocabulary', v.toMap());
        count++;
      }
      await batch.commit(noResult: true);
    });
    return count;
  }

  static Future<List<Vocabulary>> getVocabularies({
    String? sourceBook,
    int? masteryLevel,
    String? wordType,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    final where = <String>['1=1'];
    final whereArgs = <dynamic>[];

    if (sourceBook != null && sourceBook.isNotEmpty) {
      where.add('source_book = ?');
      whereArgs.add(sourceBook);
    }
    if (masteryLevel != null) {
      where.add('mastery_level = ?');
      whereArgs.add(masteryLevel);
    }
    if (wordType != null) {
      where.add('word_type = ?');
      whereArgs.add(wordType);
    }

    final rows = await db.query(
      'vocabulary',
      where: where.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => Vocabulary.fromMap(r)).toList();
  }

  /// 按 ID 精准查询（生词→原文跳转用）
  static Future<Vocabulary?> getVocabularyById(int id) async {
    final db = await database;
    final rows = await db.query('vocabulary', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Vocabulary.fromMap(rows.first);
  }

  /// 获取所有书籍名称列表
  static Future<List<String>> getBookList() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT source_book FROM vocabulary WHERE source_book IS NOT NULL AND source_book != '' ORDER BY source_book",
    );
    return rows.map((r) => r['source_book'] as String).toList();
  }

  /// 按书籍统计词汇量
  static Future<Map<String, int>> getVocabCountByBook() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT source_book, COUNT(*) as cnt
      FROM vocabulary
      WHERE source_book IS NOT NULL AND source_book != ''
      GROUP BY source_book
      ORDER BY cnt DESC
    ''');
    return {for (final r in rows) r['source_book'] as String: r['cnt'] as int};
  }

  /// 更新掌握度
  static Future<int> updateMastery(int id, int level) async {
    final db = await database;
    return db.update(
      'vocabulary',
      {
        'mastery_level': level,
        'updated_at': DateTime.now().toIso8601String()
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 更新生词的分类/来源信息（用于批量移动）
  static Future<int> updateVocabulary(int id,
      {String? category,
      String? materialPath,
      String? sourceBook,
      String? sourcePage}) async {
    final db = await database;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (category != null) updates['category'] = category;
    if (materialPath != null) updates['material_path'] = materialPath;
    if (sourceBook != null) updates['source_book'] = sourceBook;
    if (sourcePage != null) updates['source_page'] = sourcePage;
    return db.update('vocabulary', updates,
        where: 'id = ?', whereArgs: [id]);
  }

  /// 删除生词
  static Future<int> deleteVocabulary(int id) async {
    final db = await database;
    return db.delete('vocabulary', where: 'id = ?', whereArgs: [id]);
  }

  /// 批量删除生词(v1.9.0,审查 P1-7):单事务一次 `IN` 查询。
  /// 旧实现由调用方 `Future.wait` 扇出 N 路并发删除,每一路都触发一次
  /// `_refresh()`(4 次全表查询 + notify),既慢又产生"已删数据被旧结果写回"
  /// 的竞态。
  static Future<int> deleteVocabularies(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    var affected = 0;
    await db.transaction((txn) async {
      for (final chunk in _chunkIds(ids)) {
        final placeholders = List.filled(chunk.length, '?').join(',');
        affected += await txn.delete(
          'vocabulary',
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
      }
    });
    return affected;
  }

  /// 批量移动分类/出处(v1.9.0,审查 P1-7):单事务 + 分片(避免
  /// `SQLITE_MAX_VARIABLE_NUMBER` 上限,旧版 sqlite 只有 999)。
  static Future<int> updateVocabulariesCategory(
    List<int> ids, {
    String? category,
    String? materialPath,
    String? sourceBook,
    String? sourcePage,
  }) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (category != null) updates['category'] = category;
    if (materialPath != null) updates['material_path'] = materialPath;
    if (sourceBook != null) updates['source_book'] = sourceBook;
    if (sourcePage != null) updates['source_page'] = sourcePage;
    var affected = 0;
    await db.transaction((txn) async {
      for (final chunk in _chunkIds(ids)) {
        final placeholders = List.filled(chunk.length, '?').join(',');
        affected += await txn.update(
          'vocabulary',
          updates,
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
      }
    });
    return affected;
  }

  /// 把 id 列表切成安全大小的分片(SQLite 变量上限保护)
  static List<List<int>> _chunkIds(List<int> ids, {int size = 400}) {
    final out = <List<int>>[];
    for (var i = 0; i < ids.length; i += size) {
      out.add(ids.sublist(i, i + size > ids.length ? ids.length : i + size));
    }
    return out;
  }

  /// 总词汇量
  static Future<int> getTotalVocabCount() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM vocabulary');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 按分类统计词汇量
  static Future<Map<String, int>> getVocabCountByCategory() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(category, '其他') as category, COUNT(*) as cnt
      FROM vocabulary
      -- v1.9.0(P2-1):分组键必须与 SELECT 一致 —— 旧实现 GROUP BY category
      -- 让 NULL 自成一组、SELECT 再 coalesce 成 '其他',两批在 Map 里互相覆盖,
      -- 「其他」的标题数字与点进去的列表条数对不上
      GROUP BY COALESCE(category, '其他')
      ORDER BY cnt DESC
    ''');
    return {for (final r in rows) r['category'] as String: r['cnt'] as int};
  }

  /// 获取所有不重复的分类名
  static Future<List<String>> getCategoryList() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT category FROM vocabulary WHERE category IS NOT NULL AND category != '' ORDER BY category",
    );
    return rows.map((r) => r['category'] as String).toList();
  }

  /// 某分类下已用过的素材路径(子分类记忆:去重、按名称排序)
  static Future<List<String>> getMaterialPathsByCategory(
      String category) async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT material_path FROM vocabulary "
      "WHERE category = ? AND material_path IS NOT NULL AND material_path != '' "
      "ORDER BY material_path",
      [category],
    );
    return rows.map((r) => r['material_path'] as String).toList();
  }

  /// 按分类获取生词
  static Future<List<Vocabulary>> getVocabulariesByCategory(
    String category, {
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.query(
      'vocabulary',
      where: "COALESCE(category, '其他') = ?",
      whereArgs: [category],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => Vocabulary.fromMap(r)).toList();
  }

  /// 重命名书籍文件夹(v1.8.0 新增 / v1.9.0 加固,审查 P1-7):
  /// 同时更新**子路径**(旧数据可能残留 `书籍/《X》/p9`,迁移未覆盖的行),
  /// 并在单事务里完成 —— 旧实现只精确匹配 `material_path = ?`,会让同一本书
  /// 裂成"新名 + 旧名"两个文件夹;且多行 UPDATE 无事务,中断即部分改名。
  static Future<int> renameBookPath({
    required String oldPath,
    required String newPath,
    required String newBookName,
  }) async {
    final db = await database;
    var affected = 0;
    await db.transaction((txn) async {
      // 1) 精确匹配(书籍/《X》)
      affected += await txn.update(
        'vocabulary',
        {'material_path': newPath, 'source_book': newBookName},
        where: 'material_path = ?',
        whereArgs: [oldPath],
      );
      // 2) 子路径(书籍/《X》/p9 → 书籍/《新》/p9):LIKE 的通配符需转义,
      //    书名里完全可能出现 % 或 _
      final escaped = oldPath
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      affected += await txn.rawUpdate(
        "UPDATE vocabulary SET material_path = ? || substr(material_path, ?), "
        "source_book = ? WHERE material_path LIKE ? ESCAPE '\\'",
        [newPath, oldPath.length + 1, newBookName, '$escaped/%'],
      );
    });
    return affected;
  }

  /// 批量改页码/章节标签(v1.8.0):页码写入前先归一;v1.9.0 分片避免
  /// 变量上限(旧版 sqlite 999 个占位符,选 1000+ 词会抛 too many SQL variables)。
  static Future<int> updateSourcePageByIds(
    List<int> ids,
    String page,
  ) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    final normalized = normalizePageLabel(page);
    var affected = 0;
    await db.transaction((txn) async {
      for (final chunk in _chunkIds(ids)) {
        final placeholders = List.filled(chunk.length, '?').join(',');
        affected += await txn.update(
          'vocabulary',
          {'source_page': normalized.isEmpty ? null : normalized},
          where: 'id IN ($placeholders)',
          whereArgs: chunk,
        );
      }
    });
    return affected;
  }

  // ═══════════════ 文章 CRUD ═══════════════

  static Future<int> insertArticle(Article a) async {
    final db = await database;
    return db.insert('articles', a.toMap());
  }

  static Future<List<Article>> getArticles({int limit = 50, int offset = 0}) async {
    final db = await database;
    final rows = await db.query(
      'articles',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => Article.fromMap(r)).toList();
  }

  static Future<Article?> getArticleById(int id) async {
    final db = await database;
    final rows = await db.query('articles', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Article.fromMap(rows.first);
  }

  static Future<int> deleteArticle(int id) async {
    final db = await database;
    return db.delete('articles', where: 'id = ?', whereArgs: [id]);
  }

  // ═══════════════ 练习 CRUD ═══════════════

  static Future<int> insertExercise(Exercise e) async {
    final db = await database;
    return db.insert('exercises', e.toMap());
  }

  /// 保存用户的练习答案
  static Future<int> saveExerciseAnswer(int exerciseId,
      List<String?> answers, double score) async {
    final db = await database;
    return db.update(
      'exercises',
      {
        // v1.9.0(P2-3):改 JSON 编码(旧数据里的 '|||' 仍可被 decodeAnswers 读出)
        'user_answers': Exercise.encodeAnswers(answers),
        'score': score,
      },
      where: 'id = ?',
      whereArgs: [exerciseId],
    );
  }

  /// 已完成练习总数(已评分的练习)
  static Future<int> getTotalExerciseCount() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM exercises WHERE score IS NOT NULL');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<List<Exercise>> getExercisesByArticle(int articleId) async {
    final db = await database;
    final rows = await db.query(
      'exercises',
      where: 'article_id = ?',
      whereArgs: [articleId],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => Exercise.fromMap(r)).toList();
  }

  /// 一次取多篇文章的练习(v1.9.0,审查 P1-9):替代 N+1 查询。
  static Future<List<Exercise>> getExercisesByArticleIds(
    List<int> articleIds,
  ) async {
    if (articleIds.isEmpty) return [];
    final db = await database;
    final out = <Exercise>[];
    for (final chunk in _chunkIds(articleIds)) {
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'exercises',
        where: 'article_id IN ($placeholders)',
        whereArgs: chunk,
        orderBy: 'created_at DESC',
      );
      out.addAll(rows.map((r) => Exercise.fromMap(r)));
    }
    return out;
  }

  // ═══════════════ 学习记录 ═══════════════

  static Future<void> upsertDailyLog(LearningRecord record) async {
    final db = await database;
    await db.insert(
      'daily_log',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> incrementDailyWords(DateTime date, int count) async {
    final db = await database;
    final dateKey = LearningRecord.dateKey(date);
    await db.rawInsert('''
      INSERT INTO daily_log (date, new_words_count, reviewed_count, exercise_completed, study_minutes)
      VALUES (?, ?, 0, 0, 0)
      ON CONFLICT(date) DO UPDATE SET
        new_words_count = new_words_count + ?
    ''', [dateKey, count, count]);
  }

  static Future<List<LearningRecord>> getDailyLogsInRange(
      DateTime start, DateTime end) async {
    final db = await database;
    final rows = await db.query(
      'daily_log',
      where: 'date >= ? AND date <= ?',
      whereArgs: [
        LearningRecord.dateKey(start),
        LearningRecord.dateKey(end),
      ],
      orderBy: 'date ASC',
    );
    return rows.map((r) => LearningRecord.fromMap(r)).toList();
  }

  // ═══════════════ 记忆表格（AI 记忆） ═══════════════

  static Future<void> setMemory(
      String key, String value, {String category = 'general'}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('memory', where: 'key = ?', whereArgs: [key]);
      await txn.insert('memory', {
        'key': key,
        'value': value,
        'category': category,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  static Future<String?> getMemory(String key) async {
    final db = await database;
    final rows =
        await db.query('memory', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  static Future<Map<String, String>> getAllMemory() async {
    final db = await database;
    // 上限保护(v1.9.0):记忆会整段进 AI prompt,不能无界增长
    final rows = await db.query('memory', orderBy: 'category, key', limit: 200);
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  static Future<void> deleteMemory(String key) async {
    final db = await database;
    await db.delete('memory', where: 'key = ?', whereArgs: [key]);
  }

  // ═══════════════ 收藏夹 CRUD ═══════════════

  static Future<int> insertBookmark(Bookmark b) async {
    final db = await database;
    return db.insert('bookmarks', b.toMap());
  }

  static Future<int> deleteBookmark(int id) async {
    final db = await database;
    return db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  /// 按来源+内容查找(判断是否已收藏,避免重复收藏)
  static Future<Bookmark?> findBookmark(
      String source, String content) async {
    final db = await database;
    final rows = await db.query(
      'bookmarks',
      where: 'source = ? AND content = ?',
      whereArgs: [source, content],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Bookmark.fromMap(rows.first);
  }

  static Future<List<Bookmark>> getBookmarks() async {
    final db = await database;
    final rows =
        await db.query('bookmarks', orderBy: 'created_at DESC, id DESC');
    return rows.map((r) => Bookmark.fromMap(r)).toList();
  }

  // ═══════════════ 写译练习日志 CRUD(v1.6.0) ═══════════════

  static Future<int> insertWritingLog(WritingLog log) async {
    final db = await database;
    return db.insert('writing_logs', log.toMap());
  }

  static Future<List<WritingLog>> getWritingLogs({int limit = 200}) async {
    final db = await database;
    final rows = await db.query(
      'writing_logs',
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map((r) => WritingLog.fromMap(r)).toList();
  }

  static Future<int> deleteWritingLog(int id) async {
    final db = await database;
    return db.delete('writing_logs', where: 'id = ?', whereArgs: [id]);
  }

  // ═══════════════ AI 学习资源推荐 CRUD(v1.8.0) ═══════════════

  static Future<int> insertRecommendation(
    MaterialRecommendation rec,
  ) async {
    final db = await database;
    return db.insert('recommendations', rec.toMap());
  }

  static Future<List<MaterialRecommendation>> getRecommendations({
    String? category,
    int limit = 100,
  }) async {
    final db = await database;
    final rows = await db.query(
      'recommendations',
      where: category == null ? null : 'category = ?',
      whereArgs: category == null ? null : [category],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map((r) => MaterialRecommendation.fromMap(r)).toList();
  }

  /// 更新学习内容(首次流式生成后缓存)
  static Future<int> updateRecommendationContent(
    int id,
    String content,
  ) async {
    final db = await database;
    return db.update(
      'recommendations',
      {'content': content},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<int> deleteRecommendation(int id) async {
    final db = await database;
    return db.delete('recommendations', where: 'id = ?', whereArgs: [id]);
  }

  /// 用一批新推荐**原子替换**某分类的旧推荐(v1.9.0,审查 P2-2)。
  ///
  /// 旧实现是调用方先 `clearRecommendations` 再逐条 `insert`:插入中途失败
  /// (磁盘满/DB 锁/进程被杀)会留下"旧推荐已删、新推荐没写全"的空窗,
  /// 而已生成的学习正文(`content`)跟着一起没了 —— 那个按钮等于数据毁灭键。
  /// 现在 delete + batch insert 在同一个事务里,失败整体回滚。
  static Future<int> replaceRecommendations(
    String category,
    List<MaterialRecommendation> items,
  ) async {
    final db = await database;
    var inserted = 0;
    await db.transaction((txn) async {
      await txn.delete(
        'recommendations',
        where: 'category = ?',
        whereArgs: [category],
      );
      final batch = txn.batch();
      for (final item in items) {
        batch.insert('recommendations', item.toMap());
        inserted++;
      }
      await batch.commit(noResult: true);
    });
    return inserted;
  }

  /// 清掉某分类的旧推荐(重新推荐前调用)
  static Future<int> clearRecommendations(String category) async {
    final db = await database;
    return db.delete(
      'recommendations',
      where: 'category = ?',
      whereArgs: [category],
    );
  }

  // ═══════════════ v2.0 数据访问层(材料中心 / 复习内核 / 导师) ═══════════════
  //
  // 这一层被导师(AI 诊断/任务卡)、材料中心、复习内核共享,先把约定钉死,
  // 免得三个模块各写各的:
  // - 时间列**一律 ISO8601 字符串**(`DateTime.toIso8601String()`,本地时区无偏移)。
  //   同一进程/同一台机器格式恒定,于是字符串比较 == 时间比较,范围查询能走索引;
  // - `*_json` 列读出来时**额外**附带一个解析后的键(payload/result/detail/difficulty),
  //   坏 JSON 解析失败给 null 而不是抛异常 —— 一条坏行不能让导师页整页崩。
  //   原始串仍然保留(排查用),所以写库侧(upsertMaterial)只认白名单列,
  //   避免把派生键原样写回 SQLite 变成 "no such column";
  // - 每个方法都 try/catch,失败 `debugPrint('ReadFlow ...')` 并返回安全空值:
  //   列表 → []、Map → null / 四个键全 0、计数 → 0、写入 → -1(表 id 自增,不会撞 -1)。

  // ── 材料中心 ──

  /// materials 表的可写列白名单(与建表 SQL 一一对应)。
  /// 为什么需要:调用方常把 `getMaterialById` 的返回原样回传(里面带派生键
  /// `difficulty`),不做白名单就会写库报 "no such column: difficulty";
  /// 顺带挡住拼错的键静默入库(字段写错了但没人发现,比报错更难查)。
  static const List<String> _materialWritableColumns = [
    'kind',
    'source',
    'source_id',
    'title',
    'author',
    'url',
    'license',
    'language',
    'word_count',
    'unique_words',
    'cefr',
    'flesch',
    'coverage',
    'new_word_density',
    'est_minutes',
    'chapters',
    'audio_url',
    'transcript_ref',
    'difficulty_json',
    'created_at',
    'cached_at',
  ];

  /// 材料入库(材料中心唯一写入口)。
  ///
  /// 去重键是 **(source, source_id)**:同一篇材料会被反复抓取(换源重试、
  /// 用户重进详情页、缓存刷新),不去重就会在列表里堆出 N 份一模一样的行。
  /// `source_id` 为空时**不去重**(没有身份就宁可重复,也不能把同源的两篇
  /// 不同材料误合并成一篇)。
  ///
  /// 已存在时:只覆盖本次传进来的元数据(没传的字段保留原值 —— 上次算好的
  /// coverage / 难度不能被"只更新标题"的调用抹掉),`created_at` 保留首次入库
  /// 时间,`cached_at` 刷新;只有**传了 chunks 才重写正文**(不传 = 不动正文,
  /// 免得一次元数据刷新把全书正文清空)。
  ///
  /// 返回材料 id;参数不合法(kind/source/title 任一为空)或写库失败返回 **-1**。
  static Future<int> upsertMaterial(
    Map<String, Object?> row, {
    List<Map<String, Object?>> chunks = const [],
  }) async {
    try {
      final data = <String, Object?>{};
      for (final entry in row.entries) {
        if (!_materialWritableColumns.contains(entry.key)) continue;
        final value = entry.value;
        // DateTime 直接进 sqflite 会抛"不支持的类型",这里统一转 ISO8601
        data[entry.key] = value is DateTime ? value.toIso8601String() : value;
      }
      final kind = data['kind']?.toString().trim() ?? '';
      final source = data['source']?.toString().trim() ?? '';
      final title = data['title']?.toString().trim() ?? '';
      if (kind.isEmpty || source.isEmpty || title.isEmpty) {
        debugPrint('ReadFlow upsertMaterial 参数不合法(kind/source/title 不能为空)');
        return -1;
      }
      final sourceId = data['source_id']?.toString().trim() ?? '';
      data['source_id'] = sourceId.isEmpty ? null : sourceId;
      final nowIso = DateTime.now().toIso8601String();
      data['created_at'] = data['created_at']?.toString() ?? nowIso;
      data['cached_at'] = data['cached_at']?.toString() ?? nowIso;

      final db = await database;
      return await db.transaction<int>((txn) async {
        int? existingId;
        if (sourceId.isNotEmpty) {
          final found = await txn.query(
            'materials',
            columns: ['id'],
            where: 'source = ? AND source_id = ?',
            whereArgs: [source, sourceId],
            limit: 1,
          );
          if (found.isNotEmpty) existingId = found.first['id'] as int?;
        }

        if (existingId == null) {
          final id = await txn.insert('materials', data);
          await _writeMaterialChunks(txn, id, chunks);
          return id;
        }

        // 更新时不动 created_at(它记的是"何时第一次入库")
        final updates = Map<String, Object?>.from(data)..remove('created_at');
        await txn.update(
          'materials',
          updates,
          where: 'id = ?',
          whereArgs: [existingId],
        );
        if (chunks.isNotEmpty) {
          await txn.delete(
            'material_content',
            where: 'material_id = ?',
            whereArgs: [existingId],
          );
          await _writeMaterialChunks(txn, existingId, chunks);
        }
        return existingId;
      });
    } catch (e) {
      debugPrint('ReadFlow upsertMaterial failed: $e');
      return -1;
    }
  }

  /// 写正文分块(调用方负责在外层事务里)。
  /// `chunk_index` 缺省时用列表下标补齐 —— 抓取层通常只切好了顺序,不想自己数;
  /// `text` 为空的分块直接跳过:该列是 NOT NULL,硬插会让整篇材料入库失败,
  /// 而"少一段空正文"比"整篇材料进不来"轻得多。
  static Future<void> _writeMaterialChunks(
    DatabaseExecutor txn,
    int materialId,
    List<Map<String, Object?>> chunks,
  ) async {
    if (chunks.isEmpty) return;
    final batch = txn.batch();
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final text = chunk['text']?.toString() ?? '';
      final index = int.tryParse(chunk['chunk_index']?.toString() ?? '') ?? i;
      if (text.isEmpty) {
        debugPrint('ReadFlow 跳过空正文分块: material=$materialId index=$index');
        continue;
      }
      batch.insert('material_content', {
        'material_id': materialId,
        'chunk_index': index,
        'title': chunk['title']?.toString(),
        'text': text,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// 材料列表(材料中心首页),created_at DESC(新入库在前)。
  /// 加 `id DESC` 兜底:同一毫秒入库的多行顺序才稳定,分页不会重复/漏行。
  static Future<List<Map<String, Object?>>> getMaterials({
    String? kind,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final db = await database;
      final filter = (kind == null || kind.isEmpty) ? null : 'kind = ?';
      final rows = await db.query(
        'materials',
        where: filter,
        whereArgs: filter == null ? null : [kind],
        orderBy: 'created_at DESC, id DESC',
        limit: limit,
        offset: offset,
      );
      return rows.map(_decorateMaterial).toList();
    } catch (e) {
      debugPrint('ReadFlow getMaterials failed: $e');
      return [];
    }
  }

  static Future<Map<String, Object?>?> getMaterialById(int id) async {
    try {
      final db = await database;
      final rows = await db.query(
        'materials',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _decorateMaterial(rows.first);
    } catch (e) {
      debugPrint('ReadFlow getMaterialById failed: $e');
      return null;
    }
  }

  /// 材料的正文分块,chunk_index ASC(阅读器必须按原顺序拼回正文)
  static Future<List<Map<String, Object?>>> getMaterialChunks(
    int materialId,
  ) async {
    try {
      final db = await database;
      return await db.query(
        'material_content',
        where: 'material_id = ?',
        whereArgs: [materialId],
        orderBy: 'chunk_index ASC',
      );
    } catch (e) {
      debugPrint('ReadFlow getMaterialChunks failed: $e');
      return [];
    }
  }

  /// 删材料:同时清掉它的正文分块与阅读进度(单事务,不留孤儿行)。
  /// **不删 reading_sessions** —— 那是行为历史(导师判断"读过什么/速度多少"
  /// 的依据),删材料不等于抹掉"我读过它";真要清历史另有入口。
  /// 返回被删掉的材料行数(0 = 本来就没有)。
  static Future<int> deleteMaterial(int id) async {
    try {
      final db = await database;
      return await db.transaction<int>((txn) async {
        await txn.delete(
          'material_content',
          where: 'material_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'material_progress',
          where: 'material_id = ?',
          whereArgs: [id],
        );
        return txn.delete('materials', where: 'id = ?', whereArgs: [id]);
      });
    } catch (e) {
      debugPrint('ReadFlow deleteMaterial failed: $e');
      return 0;
    }
  }

  /// 给 materials 行补一个解析后的 `difficulty` 键(坏 JSON → null,原串保留)
  static Map<String, Object?> _decorateMaterial(Map<String, Object?> row) {
    return {
      ...row,
      'difficulty': _tryDecodeJson(row['difficulty_json']?.toString()),
    };
  }

  /// JSON 列的安全解析:坏数据返回 null,绝不向上抛。
  /// 导师页/材料页一次要读几十行,一行坏 JSON 不该让整页打不开。
  static Object? _tryDecodeJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (e) {
      debugPrint('ReadFlow JSON 解析失败(已忽略该字段): $e');
      return null;
    }
  }

  // ── 阅读进度与会话 ──

  /// 阅读进度(累加式更新)。
  ///
  /// 为什么 minutes/lookups/picked_words 是 `+=`:阅读器每翻一屏、每查一个词
  /// 都会上报一次**增量**,直接写会把"这次读了 3 分钟"覆盖成总时长。
  /// 传 0 = 本次没有新增(不动)。position/percent 相反是**绝对值**
  /// (当前位置只有一个,覆盖才对)。
  /// `started_at` 只在首行写入;`finished` 为 true 时写 finished_at,
  /// 为 false 时**保留**已有的完成时间(读第二遍不能把"已读完"抹掉)。
  static Future<void> upsertMaterialProgress(
    int materialId, {
    required int position,
    required double percent,
    int addMinutes = 0,
    int addLookups = 0,
    int addPickedWords = 0,
    bool finished = false,
  }) async {
    try {
      final db = await database;
      final nowIso = DateTime.now().toIso8601String();
      await db.rawInsert(
        '''
        INSERT INTO material_progress
          (material_id, position, percent, minutes, lookups, picked_words,
           started_at, finished_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(material_id) DO UPDATE SET
          position = excluded.position,
          percent = excluded.percent,
          minutes = COALESCE(material_progress.minutes, 0) + ?,
          lookups = COALESCE(material_progress.lookups, 0) + ?,
          picked_words = COALESCE(material_progress.picked_words, 0) + ?,
          finished_at = CASE WHEN ? = 1 THEN ?
                             ELSE material_progress.finished_at END,
          updated_at = ?
      ''',
        [
          materialId,
          position,
          percent,
          addMinutes,
          addLookups,
          addPickedWords,
          nowIso,
          finished ? nowIso : null,
          nowIso,
          addMinutes,
          addLookups,
          addPickedWords,
          finished ? 1 : 0,
          nowIso,
          nowIso,
        ],
      );
    } catch (e) {
      debugPrint('ReadFlow upsertMaterialProgress failed: $e');
    }
  }

  static Future<Map<String, Object?>?> getMaterialProgress(
    int materialId,
  ) async {
    try {
      final db = await database;
      final rows = await db.query(
        'material_progress',
        where: 'material_id = ?',
        whereArgs: [materialId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first;
    } catch (e) {
      debugPrint('ReadFlow getMaterialProgress failed: $e');
      return null;
    }
  }

  /// 最近读过的材料(材料中心"继续阅读")。
  /// INNER JOIN:没进度的材料不算"读过";每项含 materials 的
  /// title/kind/cefr/word_count/coverage 与 progress 的
  /// percent/minutes/position/updated_at/finished_at —— 列表页一次查询够用,不做 N+1。
  static Future<List<Map<String, Object?>>> getRecentMaterials({
    int limit = 10,
  }) async {
    try {
      final db = await database;
      return await db.rawQuery(
        '''
        SELECT m.id AS material_id,
               m.title AS title,
               m.kind AS kind,
               m.cefr AS cefr,
               m.word_count AS word_count,
               m.coverage AS coverage,
               m.est_minutes AS est_minutes,
               p.position AS position,
               p.percent AS percent,
               p.minutes AS minutes,
               p.updated_at AS updated_at,
               p.finished_at AS finished_at
        FROM material_progress p
        JOIN materials m ON m.id = p.material_id
        ORDER BY p.updated_at DESC, m.id DESC
        LIMIT ?
      ''',
        [limit],
      );
    } catch (e) {
      debugPrint('ReadFlow getRecentMaterials failed: $e');
      return [];
    }
  }

  /// 记一次阅读会话(行为数据的原子记录:统计与导师都读它)。
  /// wpm = words ÷ 分钟数;**时长为 0(或负数)时存 NULL** —— 除零要么抛异常,
  /// 要么写出 Infinity,统计页会显示"Infinity 词/分";NULL 表示"这次不知道速度"。
  static Future<int> insertReadingSession({
    int? materialId,
    int? articleId,
    required int words,
    int lookups = 0,
    required Duration duration,
  }) async {
    try {
      final db = await database;
      final safe = duration.isNegative ? Duration.zero : duration;
      final seconds = safe.inSeconds;
      final now = DateTime.now();
      final wpm = seconds <= 0 ? null : words * 60 / seconds;
      return await db.insert('reading_sessions', {
        'material_id': materialId,
        'article_id': articleId,
        'started_at': now.subtract(safe).toIso8601String(),
        'ended_at': now.toIso8601String(),
        'words': words,
        'lookups': lookups,
        'wpm': wpm,
        'created_at': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('ReadFlow insertReadingSession failed: $e');
      return -1;
    }
  }

  /// 近 [days] 天的阅读统计(快照/导师日报)。
  /// 分钟数用 julianday 差值现算(表里没有 duration 列,started/ended 才是事实源);
  /// `avg_wpm` 用 AVG 自动跳过 NULL(时长为 0 的那些会话不该拉低平均速度)。
  /// 没有数据时四个键仍是 0 / 0 / 0 / 0.0,调用方不用判空。
  static Future<Map<String, Object?>> getReadingStats({int days = 30}) async {
    try {
      final db = await database;
      final cutoff = DateTime.now()
          .subtract(Duration(days: days <= 0 ? 0 : days))
          .toIso8601String();
      final rows = await db.rawQuery(
        '''
        SELECT COUNT(*) AS sessions,
               COALESCE(SUM(words), 0) AS words,
               COALESCE(SUM((julianday(ended_at) - julianday(started_at)) * 1440.0), 0)
                 AS minutes,
               AVG(wpm) AS avg_wpm
        FROM reading_sessions
        WHERE started_at IS NOT NULL AND started_at >= ?
      ''',
        [cutoff],
      );
      final r = rows.isEmpty ? const <String, Object?>{} : rows.first;
      final avg = (r['avg_wpm'] as num?)?.toDouble();
      return {
        'sessions': (r['sessions'] as num?)?.toInt() ?? 0,
        'words': (r['words'] as num?)?.toInt() ?? 0,
        'minutes': (r['minutes'] as num?)?.round() ?? 0,
        'avg_wpm': avg == null ? 0.0 : double.parse(avg.toStringAsFixed(1)),
      };
    } catch (e) {
      debugPrint('ReadFlow getReadingStats failed: $e');
      return {'sessions': 0, 'words': 0, 'minutes': 0, 'avg_wpm': 0.0};
    }
  }

  // ── 测验 ──

  /// 存一次测验结果(词汇量测试 / 读后测验 / 回译 / 听写统一进这张表)。
  /// `detail` 是自由结构(逐题对错、能力维度),坏数据的容错在读侧兜。
  static Future<int> insertQuizResult({
    required String kind,
    int? refId,
    required int total,
    required int correct,
    Map<String, Object?>? detail,
  }) async {
    try {
      final db = await database;
      return await db.insert('quiz_results', {
        'kind': kind,
        'ref_id': refId,
        'total': total,
        'correct': correct,
        'detail_json': detail == null ? null : jsonEncode(detail),
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('ReadFlow insertQuizResult failed: $e');
      return -1;
    }
  }

  /// 测验历史(新在前),可按 kind 过滤;附解析后的 `detail` 键
  static Future<List<Map<String, Object?>>> getQuizResults({
    String? kind,
    int limit = 20,
  }) async {
    try {
      final db = await database;
      final filter = (kind == null || kind.isEmpty) ? null : 'kind = ?';
      final rows = await db.query(
        'quiz_results',
        where: filter,
        whereArgs: filter == null ? null : [kind],
        orderBy: 'created_at DESC, id DESC',
        limit: limit,
      );
      return rows
          .map(
            (row) => {
              ...row,
              'detail': _tryDecodeJson(row['detail_json']?.toString()),
            },
          )
          .toList();
    } catch (e) {
      debugPrint('ReadFlow getQuizResults failed: $e');
      return [];
    }
  }

  /// 近 [days] 天按 kind 的正确率:`{'vocab_placement': 0.72, ...}`。
  /// 按 kind 先合计再相除(不是"每次测验正确率的平均" —— 那样 3 题的测验
  /// 会和 50 题的测验一样重)。total 为 0 的 kind 直接跳过,避免除零。
  static Future<Map<String, double>> getQuizAccuracy({int days = 30}) async {
    try {
      final db = await database;
      final cutoff = DateTime.now()
          .subtract(Duration(days: days <= 0 ? 0 : days))
          .toIso8601String();
      final rows = await db.rawQuery(
        '''
        SELECT kind,
               COALESCE(SUM(correct), 0) AS c,
               COALESCE(SUM(total), 0) AS t
        FROM quiz_results
        WHERE created_at IS NOT NULL AND created_at >= ?
        GROUP BY kind
      ''',
        [cutoff],
      );
      final out = <String, double>{};
      for (final r in rows) {
        final total = (r['t'] as num?)?.toDouble() ?? 0;
        if (total <= 0) continue;
        var ratio = ((r['c'] as num?)?.toDouble() ?? 0) / total;
        // 脏数据(correct > total)不让正确率超过 100%,否则拱到导师文案里很扎眼
        if (ratio.isNaN || ratio < 0) ratio = 0;
        if (ratio > 1) ratio = 1;
        out['${r['kind']}'] = double.parse(ratio.toStringAsFixed(4));
      }
      return out;
    } catch (e) {
      debugPrint('ReadFlow getQuizAccuracy failed: $e');
      return {};
    }
  }

  // ── 错误标签(错误档案) ──

  /// 记一次同类错误(错误档案的唯一写入口)。
  ///
  /// 为什么按 (source, tag) 累加而不是一次一行:错误档案要回答的是"这个考点
  /// 错过几次、最近一次什么时候" —— 一次一行会让统计退化成全表 GROUP BY,
  /// 也体现不出"同一个坑反复踩"。
  /// `evidence` 传了才覆盖(不传保留上一次的证据,免得把唯一的例句擦掉);
  /// **复发会把 status 拉回 'active'** —— 标过 fixed 的考点又错了,就是没修好。
  static Future<void> bumpErrorTag({
    required String source,
    required String tag,
    String? evidence,
  }) async {
    try {
      final db = await database;
      final nowIso = DateTime.now().toIso8601String();
      await db.transaction((txn) async {
        final found = await txn.query(
          'error_tags',
          columns: ['id', 'count'],
          where: 'source = ? AND tag = ?',
          whereArgs: [source, tag],
          limit: 1,
        );
        if (found.isEmpty) {
          await txn.insert('error_tags', {
            'source': source,
            'tag': tag,
            'count': 1,
            'first_at': nowIso,
            'last_at': nowIso,
            'status': 'active',
            'evidence': evidence,
          });
          return;
        }
        final updates = <String, Object?>{
          'count': ((found.first['count'] as num?)?.toInt() ?? 0) + 1,
          'last_at': nowIso,
          'status': 'active',
        };
        // evidence 传了才覆盖:不传时保留上一次的例句(唯一证据不能被擦掉)
        if (evidence != null) updates['evidence'] = evidence;
        await txn.update(
          'error_tags',
          updates,
          where: 'id = ?',
          whereArgs: [found.first['id']],
        );
      });
    } catch (e) {
      debugPrint('ReadFlow bumpErrorTag failed: $e');
    }
  }

  /// 错误标签列表(错得最多的在前)。
  /// [status] 为 null 取全部;`minCount` 用来过滤"只错过一次的偶发错误"。
  static Future<List<Map<String, Object?>>> getErrorTags({
    String? status,
    int minCount = 1,
  }) async {
    try {
      final db = await database;
      final where = <String>['count >= ?'];
      final args = <Object?>[minCount];
      if (status != null && status.isNotEmpty) {
        where.add('status = ?');
        args.add(status);
      }
      return await db.query(
        'error_tags',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'count DESC, last_at DESC, id DESC',
      );
    } catch (e) {
      debugPrint('ReadFlow getErrorTags failed: $e');
      return [];
    }
  }

  /// 标记错误考点状态('active' | 'fixed')。
  /// 返回受影响行数(0 = id 不存在,或状态不在允许集合内 —— 非法值不落库,
  /// 免得下游按 status 过滤时漏掉这条)。
  static Future<int> setErrorTagStatus(int id, String status) async {
    if (status != 'active' && status != 'fixed') {
      debugPrint('ReadFlow setErrorTagStatus 非法状态(已忽略): $status');
      return 0;
    }
    try {
      final db = await database;
      return await db.update(
        'error_tags',
        {'status': status},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('ReadFlow setErrorTagStatus failed: $e');
      return 0;
    }
  }

  // ── 复习状态(v2.1 内核先用最小接口;v2.0 导师诊断要读到"到期数") ──

  /// 写一次复习结果(FSRS 状态的 upsert)。
  ///
  /// 为什么用 ON CONFLICT 而不是"先查再插":`word_review.vocab_id` 是 UNIQUE,
  /// 每次复习都 insert 会直接撞约束;而"取词 → 评级 → 写回"是复习页最热的路径,
  /// 单语句原子完成,不会出现"查到没有、写时已被别的路径插入"的竞态。
  /// `reps` / `lapses` 是**累加**的(复习一次 reps+1,lapse 时 lapses+1);
  /// `stability` / `difficulty` / `due_at` 是调度器算完传进来的**绝对值**。
  /// `lastRating` 传 null = 不覆盖上一次评级(手动改期之类的操作不该抹掉历史)。
  static Future<void> upsertWordReview(
    int vocabId, {
    required double stability,
    required double difficulty,
    required DateTime dueAt,
    int? lastRating,
    required DateTime lastReviewAt,
    bool lapse = false,
  }) async {
    try {
      final db = await database;
      final nowIso = DateTime.now().toIso8601String();
      await db.rawInsert(
        '''
        INSERT INTO word_review
          (vocab_id, stability, difficulty, due_at, last_review_at,
           reps, lapses, last_rating, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
        ON CONFLICT(vocab_id) DO UPDATE SET
          stability = excluded.stability,
          difficulty = excluded.difficulty,
          due_at = excluded.due_at,
          last_review_at = excluded.last_review_at,
          reps = word_review.reps + 1,
          lapses = word_review.lapses + ?,
          last_rating = COALESCE(excluded.last_rating, word_review.last_rating),
          updated_at = excluded.updated_at
      ''',
        [
          vocabId,
          stability,
          difficulty,
          dueAt.toIso8601String(),
          lastReviewAt.toIso8601String(),
          lapse ? 1 : 0,
          lastRating,
          nowIso,
          nowIso,
          lapse ? 1 : 0,
        ],
      );
    } catch (e) {
      debugPrint('ReadFlow upsertWordReview failed: $e');
    }
  }

  /// 已到期(含已过期)的复习条数 —— 导师诊断"复习堆积"的核心指标。
  /// `due_at` 为 NULL 的词(从未排期)不算到期;[at] 便于测试/复盘注入时间基准。
  static Future<int> getDueReviewCount({DateTime? at}) async {
    try {
      final db = await database;
      final cutoff = (at ?? DateTime.now()).toIso8601String();
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM word_review '
        'WHERE due_at IS NOT NULL AND due_at <= ?',
        [cutoff],
      );
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (e) {
      debugPrint('ReadFlow getDueReviewCount failed: $e');
      return 0;
    }
  }

  /// 到期分布(导师据此排今天的复习量),分桶口径**按自然日**而非"此刻":
  /// - overdue 过期:due_at < 今天 00:00 —— 今天早上该复习的词不算"堆积",
  ///   否则导师每天上午都在报"你堆积了 X 个",用户会被吓到;
  /// - today 今天:[今天 00:00, 今天 23:59:59.999];
  /// - week 本周内:今天之后 ~ now + 7 天(含边界);
  /// - later 更晚:再往后的。
  /// 四个键**永远都在**(没有的词数补 0),调用方不用判空。
  static Future<Map<String, int>> getReviewBuckets({DateTime? now}) async {
    const empty = <String, int>{
      'overdue': 0,
      'today': 0,
      'week': 0,
      'later': 0,
    };
    try {
      final db = await database;
      final ref = now ?? DateTime.now();
      final dayStart = DateTime(ref.year, ref.month, ref.day);
      final dayEnd = dayStart
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      final weekEnd = ref.add(const Duration(days: 7));
      final rows = await db.rawQuery(
        '''
        SELECT
          COUNT(CASE WHEN due_at < ? THEN 1 END) AS overdue,
          COUNT(CASE WHEN due_at >= ? AND due_at <= ? THEN 1 END) AS today,
          COUNT(CASE WHEN due_at > ? AND due_at <= ? THEN 1 END) AS week,
          COUNT(CASE WHEN due_at > ? THEN 1 END) AS later
        FROM word_review
        WHERE due_at IS NOT NULL
      ''',
        [
          dayStart.toIso8601String(),
          dayStart.toIso8601String(),
          dayEnd.toIso8601String(),
          dayEnd.toIso8601String(),
          weekEnd.toIso8601String(),
          weekEnd.toIso8601String(),
        ],
      );
      if (rows.isEmpty) return Map<String, int>.from(empty);
      final r = rows.first;
      return {
        'overdue': (r['overdue'] as num?)?.toInt() ?? 0,
        'today': (r['today'] as num?)?.toInt() ?? 0,
        'week': (r['week'] as num?)?.toInt() ?? 0,
        'later': (r['later'] as num?)?.toInt() ?? 0,
      };
    } catch (e) {
      debugPrint('ReadFlow getReviewBuckets failed: $e');
      return Map<String, int>.from(empty);
    }
  }

  /// 有复习状态的词数(与生词总数一起判断"复习体系是否已建立":
  /// 有词但一条状态都没有 = 复习队列是空的,导师该先补这个洞)
  static Future<int> getTrackedReviewCount() async {
    try {
      final db = await database;
      final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM word_review');
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (e) {
      debugPrint('ReadFlow getTrackedReviewCount failed: $e');
      return 0;
    }
  }

  /// 读取全部复习卡片(v2.1 队列调度需要逐词状态)。
  ///
  /// 为什么一次性读全表:生词本规模是千级、一行几十字节,读全表比"按 due 分批查"
  /// 更简单也更快,而且排序/配额/负荷预测都能在内存里算(便于单测)。
  /// 将来词量上万再改成按窗口查询。
  static Future<List<Map<String, Object?>>> getWordReviews() async {
    try {
      final db = await database;
      return await db.query('word_review');
    } catch (e) {
      debugPrint('ReadFlow getWordReviews failed: $e');
      return const [];
    }
  }

  // ── 导师 ──

  /// 新建导师任务卡。`plan_date` 存完整 ISO8601(与全表约定一致),
  /// 取"当天"靠 [getTutorTasks] 的 [当天 00:00, 次日 00:00) 半开区间
  /// (走 idx_tutor_task_date)。返回任务 id,失败 -1。
  static Future<int> insertTutorTask({
    required DateTime planDate,
    required String kind,
    required String title,
    Map<String, Object?>? payload,
    int targetMinutes = 0,
  }) async {
    try {
      final db = await database;
      return await db.insert('tutor_tasks', {
        'plan_date': planDate.toIso8601String(),
        'kind': kind,
        'title': title,
        'payload_json': payload == null ? null : jsonEncode(payload),
        'target_minutes': targetMinutes,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('ReadFlow insertTutorTask failed: $e');
      return -1;
    }
  }

  /// 某**自然日**的任务卡,created_at ASC(与当天时间线的顺序一致)。
  /// 用半开区间 [day 00:00, day+1 00:00):带时分秒的 planDate 也能正确归到当天,
  /// 又不会把次日 00:00 的卡算进来。[day] 传 `DateTime.now()` 也行,内部只取日期部分。
  static Future<List<Map<String, Object?>>> getTutorTasks(DateTime day) async {
    try {
      final db = await database;
      final start = DateTime(day.year, day.month, day.day);
      // 用 DateTime(y, m, d+1) 而不是 add(Duration(days: 1)):后者遇上夏令时会偏 1 小时
      final end = DateTime(day.year, day.month, day.day + 1);
      final rows = await db.query(
        'tutor_tasks',
        where: 'plan_date >= ? AND plan_date < ?',
        whereArgs: [start.toIso8601String(), end.toIso8601String()],
        orderBy: 'created_at ASC, id ASC',
      );
      return rows.map(_decorateTutorTask).toList();
    } catch (e) {
      debugPrint('ReadFlow getTutorTasks failed: $e');
      return [];
    }
  }

  /// 勾掉任务卡:写 done_at,有 [result] 时一并写入(不传 = 保留已有结果)。
  /// 返回受影响行数(0 = id 不存在)。
  static Future<int> completeTutorTask(
    int id, {
    Map<String, Object?>? result,
  }) async {
    try {
      final db = await database;
      return await db.update(
        'tutor_tasks',
        {
          'done_at': DateTime.now().toIso8601String(),
          if (result != null) 'result_json': jsonEncode(result),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('ReadFlow completeTutorTask failed: $e');
      return 0;
    }
  }

  static Future<int> deleteTutorTask(int id) async {
    try {
      final db = await database;
      return await db.delete('tutor_tasks', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('ReadFlow deleteTutorTask failed: $e');
      return 0;
    }
  }

  /// 给 tutor_tasks 行补解析后的 `payload` / `result` 键(坏 JSON → null,原串保留)
  static Map<String, Object?> _decorateTutorTask(Map<String, Object?> row) {
    return {
      ...row,
      'payload': _tryDecodeJson(row['payload_json']?.toString()),
      'result': _tryDecodeJson(row['result_json']?.toString()),
    };
  }

  /// 追加一条导师对话。[at] 用于补齐历史(导入/测试),不传就是"现在"。
  static Future<int> insertTutorMessage({
    required String role,
    required String content,
    String? toolCalls,
    DateTime? at,
  }) async {
    try {
      final db = await database;
      return await db.insert('tutor_messages', {
        'role': role,
        'content': content,
        'tool_calls': toolCalls,
        'created_at': (at ?? DateTime.now()).toIso8601String(),
      });
    } catch (e) {
      debugPrint('ReadFlow insertTutorMessage failed: $e');
      return -1;
    }
  }

  /// 最近 [limit] 条导师对话,按**时间正序**返回(老的在前,新的在后)。
  /// 为什么要"查 DESC 再反转":limit 必须作用在最新的 N 条上,直接 ASC + LIMIT
  /// 会取到最早的 N 条(聊得越久上下文越跑偏);反转是为了喂模型时顺序正确。
  static Future<List<Map<String, Object?>>> getTutorMessages({
    int limit = 50,
  }) async {
    try {
      final db = await database;
      final rows = await db.query(
        'tutor_messages',
        orderBy: 'created_at DESC, id DESC',
        limit: limit,
      );
      return rows.reversed.toList();
    } catch (e) {
      debugPrint('ReadFlow getTutorMessages failed: $e');
      return [];
    }
  }

  /// 清空短期对话(长期记忆 tutor_memory 不受影响:那是导师的"人格档案")
  static Future<void> clearTutorMessages() async {
    try {
      final db = await database;
      await db.delete('tutor_messages');
    } catch (e) {
      debugPrint('ReadFlow clearTutorMessages failed: $e');
    }
  }

  /// 记一条导师长期记忆(kind: preference/commitment/obstacle/insight)。
  /// 与 tutor_messages 分表:对话可以清,偏好/承诺/障碍/结论必须留着。
  static Future<int> addTutorMemory({
    required String kind,
    required String text,
  }) async {
    try {
      final db = await database;
      return await db.insert('tutor_memory', {
        'kind': kind,
        'text': text,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('ReadFlow addTutorMemory failed: $e');
      return -1;
    }
  }

  /// 导师长期记忆,新的在前(喂 prompt 时通常再按 kind 分组)
  static Future<List<Map<String, Object?>>> getTutorMemories({
    int limit = 50,
  }) async {
    try {
      final db = await database;
      return await db.query(
        'tutor_memory',
        orderBy: 'created_at DESC, id DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('ReadFlow getTutorMemories failed: $e');
      return [];
    }
  }

  static Future<int> deleteTutorMemory(int id) async {
    try {
      final db = await database;
      return await db.delete('tutor_memory', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('ReadFlow deleteTutorMemory failed: $e');
      return 0;
    }
  }

  // ── 快照用聚合 ──

  /// 掌握度分布(GROUP BY mastery_level):`{'0':n,'1':n,'2':n}`。
  /// 0/1/2 三个键**永远存在**(没数据补 0):快照/导师文案直接取用不用判空;
  /// 另外出现的非预期等级(NULL 或脏数据)也原样带出来,不静默丢。
  static Future<Map<String, int>> getMasteryDistribution() async {
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT COALESCE(mastery_level, 0) AS level, COUNT(*) AS cnt
        FROM vocabulary
        GROUP BY COALESCE(mastery_level, 0)
      ''');
      final out = <String, int>{'0': 0, '1': 0, '2': 0};
      for (final r in rows) {
        final level = (r['level'] as num?)?.toInt() ?? 0;
        out['$level'] = (r['cnt'] as num?)?.toInt() ?? 0;
      }
      return out;
    } catch (e) {
      debugPrint('ReadFlow getMasteryDistribution failed: $e');
      return {'0': 0, '1': 0, '2': 0};
    }
  }

  /// 近 [days] 天新增的生词(快照/日报),created_at DESC + id DESC 兜底
  static Future<List<Vocabulary>> getRecentVocabularies({
    int days = 7,
    int limit = 50,
  }) async {
    try {
      final db = await database;
      final since = DateTime.now()
          .subtract(Duration(days: days <= 0 ? 0 : days))
          .toIso8601String();
      final rows = await db.query(
        'vocabulary',
        where: 'created_at >= ?',
        whereArgs: [since],
        orderBy: 'created_at DESC, id DESC',
        limit: limit,
      );
      return rows.map((r) => Vocabulary.fromMap(r)).toList();
    } catch (e) {
      debugPrint('ReadFlow getRecentVocabularies failed: $e');
      return [];
    }
  }

  /// [since] 之后新增的生词数(快照"本周新增"/周报用)
  static Future<int> getVocabCountSince(DateTime since) async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM vocabulary '
        'WHERE created_at IS NOT NULL AND created_at >= ?',
        [since.toIso8601String()],
      );
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (e) {
      debugPrint('ReadFlow getVocabCountSince failed: $e');
      return 0;
    }
  }

  /// 已读完的材料数(`finished_at` 非空)。区别于"有进度":翻了两页不算读完。
  static Future<int> countMaterialsFinished() async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM material_progress '
        'WHERE finished_at IS NOT NULL',
      );
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (e) {
      debugPrint('ReadFlow countMaterialsFinished failed: $e');
      return 0;
    }
  }

  /// 按词条类型计数(审计"学了多少短语/句子" —— 用户容易只囤单词,
  /// 导师据此提醒"该整句输入了")。NULL 当 'word':与 `Vocabulary.fromMap`
  /// 的默认值一致,否则老数据在列表里算单词、在统计里算隐身。
  static Future<int> getVocabCountByWordType(String wordType) async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM vocabulary "
        "WHERE COALESCE(word_type, 'word') = ?",
        [wordType],
      );
      return Sqflite.firstIntValue(rows) ?? 0;
    } catch (e) {
      debugPrint('ReadFlow getVocabCountByWordType failed: $e');
      return 0;
    }
  }
}
