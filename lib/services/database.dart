import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import '../config/constants.dart';
import '../models/vocabulary.dart';
import '../models/article.dart';
import '../models/exercise.dart';
import '../models/learning_record.dart';

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
}
