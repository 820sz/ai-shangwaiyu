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
}
