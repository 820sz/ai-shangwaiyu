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
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // 生词表
    await db.execute('''
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
        category TEXT DEFAULT '其他',
        material_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    // 文章表
    await db.execute('''
      CREATE TABLE articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        translation TEXT,
        vocab_ids TEXT DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');

    // 练习表
    await db.execute('''
      CREATE TABLE exercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        article_id INTEGER NOT NULL,
        type TEXT DEFAULT 'back_translation',
        source_sentences TEXT NOT NULL,
        reference_answers TEXT,
        user_answers TEXT,
        score REAL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (article_id) REFERENCES articles (id)
      )
    ''');

    // 每日学习记录
    await db.execute('''
      CREATE TABLE daily_log (
        date TEXT PRIMARY KEY,
        new_words_count INTEGER DEFAULT 0,
        reviewed_count INTEGER DEFAULT 0,
        exercise_completed INTEGER DEFAULT 0,
        study_minutes INTEGER DEFAULT 0
      )
    ''');

    // 记忆表格（AI 个性化）
    await db.execute('''
      CREATE TABLE memory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        category TEXT DEFAULT 'general',
        created_at TEXT NOT NULL
      )
    ''');

    // 收藏夹(v1.4.0 问题 8/9):追问答案 + 词汇卡片,碎片知识收集
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        title TEXT,
        content TEXT NOT NULL,
        source_word TEXT,
        model TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // 写译练习日志(v1.6.0):每次批改可保存,按日期文件夹查阅复盘
    await db.execute('''
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
    ''');

    // AI 学习资源推荐(v1.8.0):推荐清单 + 生成的学习内容都落库,可复用
    await db.execute('''
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
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      // 用 try-catch 防止列/表已存在导致崩溃
      try {
        await db.execute("ALTER TABLE vocabulary ADD COLUMN part_of_speech TEXT");
      } catch (e) { debugPrint('ReadFlow DB migration v2 part_of_speech: $e'); }
      try {
        await db.execute("ALTER TABLE vocabulary ADD COLUMN grammar_note TEXT");
      } catch (e) { debugPrint('ReadFlow DB migration v2 grammar_note: $e'); }
      // 旧版可能没有 daily_log 表，补建
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS daily_log (
            date TEXT PRIMARY KEY,
            new_words_count INTEGER DEFAULT 0,
            reviewed_count INTEGER DEFAULT 0,
            exercise_completed INTEGER DEFAULT 0,
            study_minutes INTEGER DEFAULT 0
          )
        ''');
      } catch (e) { debugPrint('ReadFlow DB migration v2 daily_log: $e'); }
    }
    if (oldV < 3) {
      try {
        await db.execute("ALTER TABLE vocabulary ADD COLUMN category TEXT DEFAULT '其他'");
      } catch (e) { debugPrint('ReadFlow DB migration v3 category: $e'); }
      try {
        await db.execute("ALTER TABLE vocabulary ADD COLUMN material_path TEXT");
      } catch (e) { debugPrint('ReadFlow DB migration v3 material_path: $e'); }
    }
    if (oldV < 4) {
      // 回译练习英文参考答案(旧练习无此列,评分为估算)
      try {
        await db.execute("ALTER TABLE exercises ADD COLUMN reference_answers TEXT");
      } catch (e) { debugPrint('ReadFlow DB migration v4 reference_answers: $e'); }
    }
    if (oldV < 5) {
      // 文章全文中文翻译(旧文章无此列,阅读器"显示翻译"会提示)
      try {
        await db.execute("ALTER TABLE articles ADD COLUMN translation TEXT");
      } catch (e) { debugPrint('ReadFlow DB migration v5 translation: $e'); }
    }
    if (oldV < 6) {
      // 收藏夹表(v1.4.0)——老用户升级补建
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL,
            title TEXT,
            content TEXT NOT NULL,
            source_word TEXT,
            model TEXT,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (e) { debugPrint('ReadFlow DB migration v6 bookmarks: $e'); }
    }
    if (oldV < 7) {
      // 音标列(v1.5.0,AI 补全生成;旧词无音标显示时留空)
      try {
        await db.execute("ALTER TABLE vocabulary ADD COLUMN phonetic TEXT");
      } catch (e) { debugPrint('ReadFlow DB migration v7 phonetic: $e'); }
    }
    if (oldV < 8) {
      // 书籍路径归一(v1.6.0):旧数据把页码拼进 material_path
      // ('书籍/《X》/p16 p17'),同一本书被按页拆成多个文件夹。
      // 归一为 '书籍/《X》' + source_page='p16 p17' → 一本书一个文件夹,
      // 页/章成为其下的子分类。
      try {
        final rows = await db.query(
          'vocabulary',
          columns: ['id', 'material_path', 'source_page'],
          where: "category = ? AND material_path LIKE ?",
          whereArgs: ['书籍', '书籍/%/%'],
        );
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
          await db.update(
            'vocabulary',
            {
              'material_path': bookPath,
              if (existingPage.isEmpty && page.isNotEmpty) 'source_page': page,
            },
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      } catch (e) { debugPrint('ReadFlow DB migration v8 book path: $e'); }
      // 写译练习日志表(v1.6.0)
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS writing_logs (
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
        ''');
      } catch (e) { debugPrint('ReadFlow DB migration v8 writing_logs: $e'); }
    }
    if (oldV < 9) {
      // 页码归一(v1.8.0):历史数据存在「pp9页」「第9页」「9」「p16 p17」等写法,
      // 统一成 p9 / p16-17(与 normalizePageLabel 同规则),修显示杂乱。
      try {
        final rows = await db.query(
          'vocabulary',
          columns: ['id', 'source_page'],
          where: "source_page IS NOT NULL AND source_page != ''",
        );
        for (final r in rows) {
          final raw = (r['source_page'] as String?) ?? '';
          final normalized = normalizePageLabel(raw);
          if (normalized.isNotEmpty && normalized != raw) {
            await db.update(
              'vocabulary',
              {'source_page': normalized},
              where: 'id = ?',
              whereArgs: [r['id']],
            );
          }
        }
      } catch (e) { debugPrint('ReadFlow DB migration v9 page label: $e'); }
      // AI 学习资源推荐表(v1.8.0)
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS recommendations (
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
        ''');
      } catch (e) { debugPrint('ReadFlow DB migration v9 recommendations: $e'); }
    }
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
      GROUP BY category
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

  /// 重命名书籍文件夹(v1.8.0):更新该书下所有词条的 material_path 与
  /// source_book。返回受影响行数。
  static Future<int> renameBookPath({
    required String oldPath,
    required String newPath,
    required String newBookName,
  }) async {
    final db = await database;
    return db.update(
      'vocabulary',
      {'material_path': newPath, 'source_book': newBookName},
      where: 'material_path = ?',
      whereArgs: [oldPath],
    );
  }

  /// 批量改页码/章节标签(v1.8.0):页码写入前先归一。
  static Future<int> updateSourcePageByIds(
    List<int> ids,
    String page,
  ) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    final normalized = normalizePageLabel(page);
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.update(
      'vocabulary',
      {'source_page': normalized.isEmpty ? null : normalized},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
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
        'user_answers': answers.join('|||'),
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
    final rows = await db.query('memory', orderBy: 'category, key');
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
