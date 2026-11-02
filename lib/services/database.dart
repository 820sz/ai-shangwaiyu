import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import '../config/constants.dart';
import '../models/vocab_occurrence.dart';
import '../models/vocabulary.dart';
import '../models/article.dart';
import '../models/exercise.dart';
import '../models/learning_record.dart';
import '../models/bookmark.dart';
import '../models/writing_log.dart';
import '../models/material_recommendation.dart';
import '../utils/material_group.dart';
import '../utils/page_label.dart';

/// 本地 SQLite 数据库服务 — 生词、文章、练习、学习记录全部落本地
/// 批量收词的结果(v2.4):新增几条 / 合并了几次"又见到" / 累计新增多少处出处
class VocabInsertOutcome {
  /// 真正新插入的词条数
  final int added;

  /// 命中已有词条(合并出现记录)的词条数
  final int merged;

  /// 新记录的"出现次数"总数(同一词在不同位置被标多次时 >1)
  final int occurrencesAdded;

  const VocabInsertOutcome({
    this.added = 0,
    this.merged = 0,
    this.occurrencesAdded = 0,
  });

  bool get isEmpty => added == 0 && merged == 0;

  /// 人话结果(听写/阅读器保存后的提示用)
  String get summary {
    if (isEmpty) return '没有可保存的词';
    final parts = <String>['新增 $added 个'];
    if (merged > 0) parts.add('已在生词本 $merged 个');
    if (occurrencesAdded > 0) parts.add('记录出现 $occurrencesAdded 处');
    return parts.join(' · ');
  }
}

/// 一条已落库的阅读器译文(v2.16.0 / dbVersion 20)。
///
/// 为什么单独建模:译文是"**某份材料某一段**的翻译",不是生词属性;而且必须带
/// [sourceText](落库时的原文快照) —— 材料重新导入/重新切段后 unit 下标会漂移,
/// 靠快照比对才能避免把 A 段的译文显示到 B 段下面(错位比没有更糟)。
class MaterialTranslation {
  final int unitIndex;
  final int chunkIndex;
  final String sourceText;
  final String translatedText;
  final String? model;
  final DateTime? updatedAt;

  const MaterialTranslation({
    required this.unitIndex,
    required this.chunkIndex,
    required this.sourceText,
    required this.translatedText,
    this.model,
    this.updatedAt,
  });
}

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
        -- v2.4(B4):同一个词每次出现的出处记录(JSON 数组:book/page/sentence/at)
        occurrences_json TEXT,
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
        -- v2.5(M2):AI 内容的生成来源与思考过程,详情页要展示(用户反馈"全都看不到")
        model TEXT,
        reasoning TEXT,
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
    // ── v2.16(dbVersion 20)──
    // 阅读器打开时一次性读整份材料的译文(material_id 过滤 + unit_index 排序)
    'CREATE INDEX IF NOT EXISTS idx_material_trans_material ON material_translations(material_id, unit_index)',
    // ── v2.17(dbVersion 21)──
    // 做题页按 set 拉全部题目(按 idx 排);列表页按时间倒序;统计按 set 聚合
    'CREATE INDEX IF NOT EXISTS idx_exercise_items_set ON exercise_items(set_id, idx)',
    'CREATE INDEX IF NOT EXISTS idx_output_attempts_created ON output_attempts(created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_output_attempts_set ON output_attempts(set_id)',
    // ── v2.18(dbVersion 22)──
    // 能力项趋势:按维度取最近 N 条(latest / previous / history 都走它)
    'CREATE INDEX IF NOT EXISTS idx_ability_dim_time ON ability_snapshots(dimension, snapshot_at DESC)',
    // 任务事件:按任务拉完整时间线(复盘页)
    'CREATE INDEX IF NOT EXISTS idx_task_events_task ON task_events(task_id, at)',
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
      -- v2.11(dbVersion 18):封面/配图地址。用户 10/5 原话:
      -- "不需要 ai 生图啊,很多材料明明链接点开里面自己就有配图啊!
      --  把原材料的原插图作为材料的封面不就行了吗?"
      -- 所以入库时把**源头自带的图**存下来(公版书封面、RSS 头图、文章 og:image),
      -- 列表/书架/材料库才有真图可显示 —— 不落库的话重启就退化成色块。
      cover_url TEXT,
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

  /// 阅读器译文(v2.16.0 / dbVersion 20):「翻过一次就永久在」。
  ///
  /// 为什么单独一张表而不是塞进 material_content:
  /// - 译文与正文是**两条独立生命周期**:正文是事实源(重新导入会换掉),
  ///   译文是可复用资产(能保留、能整材料清空、能覆盖重翻);
  /// - [source_text] 存落库时的原文快照:重导入/切段变化后 unit 下标会漂移,
  ///   读取时比对快照不一致就丢弃该条(宁可重翻,也不显示错位的译文);
  /// - UNIQUE(material_id, unit_index) = 同一段只有一条译文,重翻走 UPSERT 覆盖。
  static const String _materialTranslationsTableSql = '''
    CREATE TABLE IF NOT EXISTS material_translations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL,
      unit_index INTEGER NOT NULL,
      chunk_index INTEGER NOT NULL,
      source_text TEXT NOT NULL,
      translated_text TEXT NOT NULL,
      model TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT,
      UNIQUE(material_id, unit_index)
    )
  ''';

  // ═══════════════ v2.17(dbVersion 21)输出重建:题组 / 题目 / rubric / 作答 ═══════════════
  //
  // 为什么新开四张表,而不是复用旧的 exercises / drill_logs:
  // - 旧 `exercises` 的结构是"一次练习 = 一批句子 + 一份总分",且 article_id 绑死文章,
  //   承载不了"逐题 rubric / 能力标签 / 分档 / 依据"(见 docs/research/output-and-tutor.md §1.6);
  // - 旧 `drill_logs` 只有对错计数,没有逐题作答、没有维度分、没有用时;
  // - 新结构按"题组(set)→ 题目(item)→ 作答(attempt)"三层拆开:出题器只写
  //   set/items,评分层只读 rubrics,统计层只读 attempts —— 三块可以各自演进。
  //
  // 枚举值(数据库只存字符串,由服务层校验;这样以后加题型不用改表):
  // - source: ai / builtin / user_import / exam
  // - exam_type: cet4 / cet6 / kaoyan / ielts / nce / none
  // - section: writing / translation / back_translation / summary / sentence_rewrite
  // - item.type: spelling / back_translation / sentence_rewrite / error_correction /
  //              summary / writing / translation / blank_filling
  // - verify_status: pending / verified(AI 生成默认 pending,等校对后再算"可信任题源")
  // - rubric.scoring_mode: objective / ai_rubric / manual

  /// 题组/卷面(一套题一行;题目在 exercise_items)
  static const String _exerciseSetsTableSql = '''
    CREATE TABLE IF NOT EXISTS exercise_sets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source TEXT NOT NULL DEFAULT 'ai',
      exam_type TEXT DEFAULT 'none',
      paper_year INTEGER,
      paper_label TEXT,
      section TEXT,
      title TEXT NOT NULL,
      difficulty_cefr TEXT,
      goals_json TEXT,
      rubric_id TEXT,
      material_id INTEGER,
      license_note TEXT,
      verify_status TEXT DEFAULT 'pending',
      created_at TEXT NOT NULL
    )
  ''';

  /// 单题(一套题 N 行;idx = 展示顺序)
  static const String _exerciseItemsTableSql = '''
    CREATE TABLE IF NOT EXISTS exercise_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      set_id INTEGER NOT NULL,
      idx INTEGER NOT NULL DEFAULT 0,
      type TEXT NOT NULL,
      prompt_zh TEXT,
      prompt_en TEXT,
      reference_answer TEXT,
      accepted_answers_json TEXT,
      rubric_id TEXT,
      ability_tags_json TEXT,
      grammar_points_json TEXT,
      word_count INTEGER DEFAULT 0,
      source_span TEXT,
      audio_ref TEXT
    )
  ''';

  /// 评分标准(id 用 TEXT:内置 4 条固定 id + 以后可注入自定义 rubric)
  ///
  /// 为什么不做自增 id:出题器/评分层按 **rubric_id 名称**对齐
  /// (cet4_writing / cet4_translation / back_translation / summary),
  /// 自增 id 跨设备/备份恢复后不稳定;固定 id 才能"内置 rubric 一处定义、
  /// 迁移 seed、两处引用"。
  /// - dimensions_json: [{key,label,weight}] —— 维度权重(评分层按它算总分)
  /// - bands_json:      [{score_range,label,desc}] —— 分档描述(UI 显示"你在哪一档")
  /// - prompt_template: 注入题目的评分提示词模板(评分层拼好后发模型)
  static const String _rubricsTableSql = '''
    CREATE TABLE IF NOT EXISTS rubrics (
      id TEXT PRIMARY KEY NOT NULL,
      type TEXT NOT NULL,
      scoring_mode TEXT NOT NULL DEFAULT 'ai_rubric',
      dimensions_json TEXT,
      bands_json TEXT,
      prompt_template TEXT,
      created_at TEXT NOT NULL
    )
  ''';

  /// 作答明细(一题一行)
  ///
  /// correct 三态:1 = 客观题答对 / 0 = 答错 / NULL = 主观题(未判对错,
  /// 只有 score_json 维度分)。统计口径必须把 NULL 排除在正确率分母外。
  static const String _outputAttemptsTableSql = '''
    CREATE TABLE IF NOT EXISTS output_attempts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      set_id INTEGER,
      item_id INTEGER,
      mode TEXT,
      answer TEXT,
      correct INTEGER,
      score_json TEXT,
      seconds INTEGER DEFAULT 0,
      plan_id INTEGER,
      error_tags_json TEXT,
      created_at TEXT NOT NULL
    )
  ''';

  /// **能力项快照**(v2.18 / dbVersion 22):能力维度的时间序列。
  ///
  /// 为什么单独成表,而不是塞进 `learner_model`(Hive 单行 JSON):
  /// - 能力项要的是**时间序列**("这周写作维度 +6"),单行 JSON 存不下趋势;
  /// - 每条带 source / confidence / evidence_json —— 沿用 `ProfileField` 那套
  ///   "来源与置信度"纪律,UI 才能区分"测出来的 / 自报的 / 推断的",不把推断
  ///   伪装成实测;
  /// - **只读派生**:由词汇量测试、写作批改、drill 完成、周报等算出来写,
  ///   不是用户手填(手填的是目标,不是能力值)。
  static const String _abilitySnapshotsTableSql = '''
    CREATE TABLE IF NOT EXISTS ability_snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      snapshot_at TEXT NOT NULL,
      dimension TEXT NOT NULL,
      value REAL NOT NULL DEFAULT 0,
      unit TEXT,
      source TEXT,
      confidence REAL,
      evidence_json TEXT,
      created_at TEXT
    )
  ''';

  /// **任务事件流**(v2.18 / dbVersion 22):任务状态变化的**只追加审计**。
  ///
  /// 为什么不直接改 `tutor_tasks` 的一列了事:复盘要回答"这个任务是跳过了还是
  /// 过期了、改过几次、跳过几次" —— 只存当前状态会把历史抹掉。事件只追加、
  /// 不修改、不删除,与 `done_at/result_json/status` 这些"当前快照"并存。
  static const String _taskEventsTableSql = '''
    CREATE TABLE IF NOT EXISTS task_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id INTEGER NOT NULL,
      event TEXT NOT NULL,
      at TEXT NOT NULL,
      payload_json TEXT,
      created_at TEXT
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

  /// 练习计划(v2.9,用户第 2 条:练习要有"系统规划")
  ///
  /// 一个模式(spelling/translation)同时只保留一个"进行中"的计划;
  /// goals 是**多选**的目标需求(四六级/雅思/学术…),JSON 数组存字符串。
  static const String _drillPlansTableSql = '''
    CREATE TABLE IF NOT EXISTS drill_plans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mode TEXT NOT NULL,
      goals TEXT,
      level_note TEXT,
      weeks INTEGER DEFAULT 4,
      per_day INTEGER DEFAULT 10,
      start_date TEXT,
      status TEXT DEFAULT 'active',
      created_at TEXT,
      updated_at TEXT
    )
  ''';

  /// 每次练习的记录(v2.9:进度追踪与正确率趋势的原始数据)
  static const String _drillLogsTableSql = '''
    CREATE TABLE IF NOT EXISTS drill_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mode TEXT NOT NULL,
      plan_id INTEGER,
      goals TEXT,
      total INTEGER DEFAULT 0,
      correct INTEGER DEFAULT 0,
      seconds INTEGER DEFAULT 0,
      wrong_words TEXT,
      created_at TEXT
    )
  ''';

  /// 材料里的 AI 内容块(v2.9,用户第 3(5) 条:阅读形式要更丰富)
  ///
  /// kind: table(表格)/mindmap(思维导图)/timeline(时间线)/points(要点卡)/quiz(自测)
  /// payload 存 JSON(各 kind 自己的结构);chunk_index = -1 表示"整篇级"
  static const String _materialBlocksTableSql = '''
    CREATE TABLE IF NOT EXISTS material_blocks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL,
      chunk_index INTEGER DEFAULT -1,
      kind TEXT NOT NULL,
      title TEXT,
      payload TEXT,
      created_at TEXT,
      UNIQUE(material_id, chunk_index, kind)
    )
  ''';

  /// 书架(v2.10,用户 10/4 第 4/5 条:"材料中心里的书架,像真书架一样,放一篇多一本")
  ///
  /// 为什么单独一张表而不是给 materials 加一列:
  /// 书架是**用户自己挑选**的结果(materials 里混着公版书/论文/外刊/导入件),
  /// 还要有摆放顺序与加入时间 —— "我挑进来的"这层语义独立成表最干净。
  static const String _bookshelfTableSql = '''
    CREATE TABLE IF NOT EXISTS bookshelf (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL UNIQUE,
      slot INTEGER DEFAULT 0,
      note TEXT,
      added_at TEXT,
      from_where TEXT
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
  ///
  /// v2.18(dbVersion 22)在原表上**扩列**(旧库由迁移里的 `_ensureColumn` 补,
  /// 不删旧列):
  /// - origin(任务来源 auto=助理派 / custom=用户自建)
  /// - status(状态机 pending/active/done/skipped/expired)
  /// - started_at / actual_minutes(追踪"实际投入"与复盘偏差)
  /// - note(用户备注)/ parent_id(周期模板父任务)/ goal_tag(关联目标需求)
  ///
  /// 新建库直接建全列;老库靠迁移/自检补 —— 两条路径的最终 schema 必须一致,
  /// 否则"新装用户能用、老用户升级缺列"这种最难查的 bug 会出现。
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
      created_at TEXT,
      origin TEXT DEFAULT 'auto',
      status TEXT DEFAULT 'pending',
      started_at TEXT,
      actual_minutes INTEGER,
      note TEXT,
      parent_id INTEGER,
      goal_tag TEXT
    )
  ''';

  /// 导师会话(长期记忆的另一半:短期对话)
  ///
  /// v2.8(用户第 5(2) 条"无法清除聊天或者新建、多开对话、编辑对话标题"):
  /// 加 `conversation_id` —— 以前所有消息平铺在**一条**会话里,想"多开"根本没有概念。
  static const String _tutorMessagesTableSql = '''
    CREATE TABLE IF NOT EXISTS tutor_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      tool_calls TEXT,
      conversation_id INTEGER,
      created_at TEXT
    )
  ''';
  static const String _tutorConversationsTableSql = '''
    CREATE TABLE IF NOT EXISTS tutor_conversations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      kind TEXT,
      created_at TEXT,
      updated_at TEXT
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
    await db.execute(_tutorConversationsTableSql);
    // v2.9(用户 10/2 的 2/3(5)/5 条)
    await db.execute(_drillPlansTableSql);
    await db.execute(_drillLogsTableSql);
    await db.execute(_materialBlocksTableSql);
    await db.execute(_bookshelfTableSql);
    // v2.16(用户:C1-19 翻译"永远没法用")
    await db.execute(_materialTranslationsTableSql);
    // v2.17(输出重建:题组/题目/rubric/作答)
    await db.execute(_exerciseSetsTableSql);
    await db.execute(_exerciseItemsTableSql);
    await db.execute(_rubricsTableSql);
    await db.execute(_outputAttemptsTableSql);
    // v2.18(批 4 助理数据层:能力快照 + 任务事件)
    await db.execute(_abilitySnapshotsTableSql);
    await db.execute(_taskEventsTableSql);
    await _seedBuiltinRubrics(db);
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
      await _ensureTable(db, 'tutor_conversations', _tutorConversationsTableSql);
      await _ensureColumn(db, 'tutor_messages', 'conversation_id', 'INTEGER');
      // v2.0 决策:音标英式美式都给(词条同时显示两套)
      await _ensureColumn(db, 'vocabulary', 'phonetic_uk', 'TEXT');
      await _ensureColumn(db, 'vocabulary', 'phonetic_us', 'TEXT');
      await _createIndexes(db);
      await _seedWordReviewFromMastery(db);
    }
    if (oldV < 12) {
      // v2.4(B4,用户要求):同一个词反复出现要**记次数与出处** —— 词条不再
      // "再存一行",而是往 occurrences_json 追加一次出现记录(书/页/原句/时间)。
      // 纯加列、不动既有数据;老词条解析出来是空列表,显示行为与以前一致。
      await _ensureColumn(db, 'vocabulary', 'occurrences_json', 'TEXT');
    }
    if (oldV < 13) {
      // v2.5(M2):AI 推荐内容要能看到"用哪个模型生成的、思考过程是什么"
      await _ensureColumn(db, 'recommendations', 'model', 'TEXT');
      await _ensureColumn(db, 'recommendations', 'reasoning', 'TEXT');
    }
    if (oldV < 14) {
      // v2.8(用户第 2 条):页边中文批注并到英文词条上,需要一列来存它。
      // 纯加列、不动既有数据 —— 老词条 annotation 为空,显示与以前一致。
      await _ensureColumn(db, 'vocabulary', 'annotation', 'TEXT');
    }
    if (oldV < 15) {
      // v2.8(用户第 5(2) 条):助理对话要能**新建/多开/改名/删除** ——
      // 加一张会话表 + 消息上的 conversation_id。
      // 老消息没有会话归属:留给界面按"默认对话"处理(不迁移,避免猜错)。
      await _ensureTable(db, 'tutor_conversations', _tutorConversationsTableSql);
      await _ensureColumn(db, 'tutor_messages', 'conversation_id', 'INTEGER');
    }
    if (oldV < 16 || oldV < 17) {
      // v2.9 / v2.10 的两列以前**只在 _onOpen 自检里补**(见那里的注释)。
      // 在这里也写一遍:自检是"尽力而为 + 静默",而版本迁移是显式的 ——
      // 老库跨版本升级时不该依赖"下次打开才补上"。
      // 两处都是幂等的(_ensureColumn 自己检查存在性)。
      await _ensureColumn(db, 'materials', 'origin', 'TEXT');
      await _ensureColumn(db, 'materials', 'group_name', 'TEXT');
      await _ensureColumn(db, 'materials', 'title_cn', 'TEXT');
    }
    if (oldV < 18) {
      // v2.11(用户 10/5 第 2 条):封面/配图地址落库。
      // 用户原话:"不需要 ai 生图啊,很多材料明明链接点开里面自己就有配图啊!
      // 把原材料的原插图作为材料的封面不就行了吗?"
      // 纯加列、不动既有数据 —— 老材料 cover_url 为空,界面回落程序化封面,
      // 显示行为与以前完全一致(不会因为升级而"多出一堆图"或"图错位")。
      await _ensureColumn(db, 'materials', 'cover_url', 'TEXT');
    }
    if (oldV < 19) {
      // v2.13.1(用户 2026-11-01 截图):「移动材料」把完整 material_path 当
      // 材料名二次拼前缀 → `书籍/书籍/《Character》`;分组键就是原始路径字符串,
      // 于是同一本书被拆成两个分组("移动后不并入老分类,而是重复新建")。
      // 这里只做本地确定性归一(纯函数与 utils/material_group.dart 同一份),
      // 幂等;失败整体回滚,下次启动 _onOpen 自检会重跑。
      await _normalizeDuplicatedMaterialPaths(db);
    }
    if (oldV < 20) {
      // v2.16.0(阅读器翻译根治第一段):译文落库。
      // 纯建表、不动既有数据 —— 老用户首次打开任意材料时表已就绪,没有译文
      // (= 行为与以前完全一致,照常翻;翻完这次之后就永久在了)。
      // 索引交给 _createIndexes(单条失败不阻断,与既有约定一致)。
      await _ensureTable(db, 'material_translations', _materialTranslationsTableSql);
      await _createIndexes(db);
    }
    if (oldV < 21) {
      // v2.17.0(批 3 输出重建 P0 数据层):题组/题目/rubric/作答四张表 +
      // 内置 rubric seed。纯建表 + 幂等 seed,不动既有数据 —— 老用户升级后
      // "输出"页数据为空,首次做题才开始写;内置 rubric 用 INSERT OR IGNORE,
      // 用户/后续版本改过的同 id rubric 不会被覆盖。
      await _ensureTable(db, 'exercise_sets', _exerciseSetsTableSql);
      await _ensureTable(db, 'exercise_items', _exerciseItemsTableSql);
      await _ensureTable(db, 'rubrics', _rubricsTableSql);
      await _ensureTable(db, 'output_attempts', _outputAttemptsTableSql);
      await _seedBuiltinRubrics(db);
      await _createIndexes(db);
    }
    if (oldV < 22) {
      // v2.18(dbVersion 22,批 4 助理数据层):
      // ① 新建 ability_snapshots(能力项时间序列)/ task_events(任务事件审计);
      // ② tutor_tasks **扩列**(状态机/追踪/自定义任务)——只加列、不删旧列:
      //    周报、桌面小组件、旧 tutor_home 仍在读 done_at/result_json;
      // ③ 老任务 status 回填:done_at 非空 = 历史上勾过 → 'done'。
      //    只改 status 仍是默认 'pending' 的行,重复迁移/自检不会把用户后来
      //    设成 skipped/expired 的任务又改回 done(幂等)。
      await _ensureTable(db, 'ability_snapshots', _abilitySnapshotsTableSql);
      await _ensureTable(db, 'task_events', _taskEventsTableSql);
      await _ensureColumn(db, 'tutor_tasks', 'origin', "TEXT DEFAULT 'auto'");
      await _ensureColumn(db, 'tutor_tasks', 'status', "TEXT DEFAULT 'pending'");
      await _ensureColumn(db, 'tutor_tasks', 'started_at', 'TEXT');
      await _ensureColumn(db, 'tutor_tasks', 'actual_minutes', 'INTEGER');
      await _ensureColumn(db, 'tutor_tasks', 'note', 'TEXT');
      await _ensureColumn(db, 'tutor_tasks', 'parent_id', 'INTEGER');
      await _ensureColumn(db, 'tutor_tasks', 'goal_tag', 'TEXT');
      await _backfillTutorTaskStatus(db);
      await _createIndexes(db);
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
      // v2.4:出现记录列(半迁移/老库自愈)
      await _ensureColumn(db, 'vocabulary', 'occurrences_json', 'TEXT', repaired);
      // v2.8:页边中文批注列(同上)
      await _ensureColumn(db, 'vocabulary', 'annotation', 'TEXT', repaired);
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
      // v2.16:阅读器译文表(半迁移/历史迁移被吞过的库也能自愈)
      await _ensureTable(db, 'material_translations', _materialTranslationsTableSql, repaired);
      await _ensureTable(db, 'material_progress', _materialProgressTableSql, repaired);
      await _ensureTable(db, 'reading_sessions', _readingSessionsTableSql, repaired);
      await _ensureTable(db, 'quiz_results', _quizResultsTableSql, repaired);
      await _ensureTable(db, 'error_tags', _errorTagsTableSql, repaired);
      await _ensureTable(db, 'tutor_tasks', _tutorTasksTableSql, repaired);
      await _ensureTable(db, 'tutor_messages', _tutorMessagesTableSql, repaired);
      await _ensureTable(db, 'tutor_memory', _tutorMemoryTableSql, repaired);
      await _ensureTable(db, 'tutor_conversations', _tutorConversationsTableSql, repaired);
      await _ensureColumn(db, 'tutor_messages', 'conversation_id', 'INTEGER', repaired);
      // v2.9:练习计划/记录、材料内容块、材料来源与分组
      await _ensureTable(db, 'drill_plans', _drillPlansTableSql, repaired);
      await _ensureTable(db, 'drill_logs', _drillLogsTableSql, repaired);
      await _ensureTable(db, 'material_blocks', _materialBlocksTableSql, repaired);
      await _ensureColumn(db, 'materials', 'origin', 'TEXT', repaired);
      await _ensureColumn(db, 'materials', 'group_name', 'TEXT', repaired);
      // v2.10:书架表 + 材料中文标题缓存
      await _ensureTable(db, 'bookshelf', _bookshelfTableSql, repaired);
      await _ensureColumn(db, 'materials', 'title_cn', 'TEXT', repaired);
      // v2.11:封面/配图地址(老库补列;新库由建表 SQL 带出来)
      await _ensureColumn(db, 'materials', 'cover_url', 'TEXT', repaired);
      // v2.17:输出重建四表(半迁移/历史迁移被吞过的库也能自愈)
      await _ensureTable(db, 'exercise_sets', _exerciseSetsTableSql, repaired);
      await _ensureTable(db, 'exercise_items', _exerciseItemsTableSql, repaired);
      await _ensureTable(db, 'rubrics', _rubricsTableSql, repaired);
      await _ensureTable(db, 'output_attempts', _outputAttemptsTableSql, repaired);
      // v2.18(批 4 助理数据层):两张新表 + tutor_tasks 七列,
      // 半迁移/历史迁移被吞过的库在这里自愈;回填幂等(只改 pending 行)。
      await _ensureTable(db, 'ability_snapshots', _abilitySnapshotsTableSql, repaired);
      await _ensureTable(db, 'task_events', _taskEventsTableSql, repaired);
      await _ensureColumn(db, 'tutor_tasks', 'origin', "TEXT DEFAULT 'auto'", repaired);
      await _ensureColumn(db, 'tutor_tasks', 'status', "TEXT DEFAULT 'pending'", repaired);
      await _ensureColumn(db, 'tutor_tasks', 'started_at', 'TEXT', repaired);
      await _ensureColumn(db, 'tutor_tasks', 'actual_minutes', 'INTEGER', repaired);
      await _ensureColumn(db, 'tutor_tasks', 'note', 'TEXT', repaired);
      await _ensureColumn(db, 'tutor_tasks', 'parent_id', 'INTEGER', repaired);
      await _ensureColumn(db, 'tutor_tasks', 'goal_tag', 'TEXT', repaired);
      await _backfillTutorTaskStatus(db);
      await _createIndexes(db);
      // 内置 rubric seed:幂等(INSERT OR IGNORE),放在自检里保证
      // "表在但 rubric 缺失"的半迁移库也能补齐默认评分标准。
      await _seedBuiltinRubrics(db);
      // v2.13.1:材料路径/分组名归一兜底(幂等)。
      // 放在自检而不是只放版本迁移:① 半迁移/历史迁移被吞过的库也能自愈;
      // ② 老版本 App 与新版混用(用户装了旧包又升回来)时,旧链路可能又写进
      //    重复前缀,下次启动直接再清一遍。
      await _normalizeDuplicatedMaterialPaths(db);
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

  /// 内置 rubric seed(v2.17.0 / dbVersion 21)。
  ///
  /// 幂等:`INSERT OR IGNORE` + 固定 id ——
  /// ① 新装/升级都只插一次(启动自检也会调,重复执行安全);
  /// ② 以后同 id 的 rubric 被用户/后续版本改过,再启动**不会覆盖**(内置只是默认值);
  /// ③ 失败静默:rubric 缺失时界面回落"无档位描述",不能因为 seed 失败让 App 起不来。
  static Future<void> _seedBuiltinRubrics(Database db) async {
    try {
      final now = DateTime.now().toIso8601String();
      final batch = db.batch();
      for (final row in _builtinRubricRows(now)) {
        batch.rawInsert(
          'INSERT OR IGNORE INTO rubrics '
          '(id, type, scoring_mode, dimensions_json, bands_json, prompt_template, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            row['id'],
            row['type'],
            row['scoring_mode'],
            row['dimensions_json'],
            row['bands_json'],
            row['prompt_template'],
            row['created_at'],
          ],
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('ReadFlow 内置 rubric 初始化失败(不影响启动): $e');
    }
  }

  /// 内置 4 条 rubric 的默认内容(纯数据生成,便于测试与以后调整文案)。
  ///
  /// 固定 id(出题器/评分层按名称对齐,**不要改名**):
  /// `cet4_writing` / `cet4_translation` / `back_translation` / `summary`。
  ///
  /// 维度与档位对齐考试习惯:
  /// - CET-4 写作 15 分制:内容切题 30% / 组织连贯 25% / 语言准确 30% /
  ///   词汇丰富 10% / 句式多样 5%;
  /// - CET-4 翻译 15 分制:原文理解 40% / 译文准确 40% / 表达通顺 20%;
  /// - 回译 5 分制:准确 60% / 通顺 40%;
  /// - 摘要 5 分制:要点覆盖 50% / 连贯 30% / 语言 20%。
  static List<Map<String, Object?>> _builtinRubricRows(String createdAt) {
    List<Map<String, Object?>> dims(List<(String, String, double)> list) => [
          for (final (key, label, weight) in list)
            {'key': key, 'label': label, 'weight': weight},
        ];
    List<Map<String, Object?>> bands(List<(String, String, String)> list) => [
          for (final (range, label, desc) in list)
            {'score_range': range, 'label': label, 'desc': desc},
        ];

    final bands15 = bands([
      ('13-15', '优秀', '内容完整切题,结构清晰,语言基本无误,表达得体'),
      ('10-12', '良好', '内容较完整,结构较清楚,少量语言错误但不影响理解'),
      ('7-9', '及格', '基本完成任务,有明显语言错误,部分表达影响理解'),
      ('4-6', '较差', '内容残缺或偏题,错误较多,阅读困难'),
      ('0-3', '差', '几乎无法理解或未作答'),
    ]);
    final bands5 = bands([
      ('5', '优秀', '意思完整准确,表达自然通顺'),
      ('4', '良好', '基本准确,仅个别小错'),
      ('3', '及格', '主要意思仍在,有影响理解的错误'),
      ('2', '较差', '多处错误,部分意思丢失'),
      ('0-1', '差', '偏离原意或未作答'),
    ]);

    return [
      {
        'id': 'cet4_writing',
        'type': 'writing',
        'scoring_mode': 'ai_rubric',
        'dimensions_json': jsonEncode(dims([
          ('content', '内容切题', 0.30),
          ('organization', '组织连贯', 0.25),
          ('language', '语言准确', 0.30),
          ('vocabulary', '词汇丰富', 0.10),
          ('sentence', '句式多样', 0.05),
        ])),
        'bands_json': jsonEncode(bands15),
        'prompt_template': '''你是 CET-4 写作阅卷员。先给依据、再给分,不许只给总分。
评分维度(权重见括号):{维度}
分档参考:{档位}
题目:{题目}
学生作文:{学生答案}
只输出 JSON:
{"score":总分(0-15),"dimensions":[{"key":"维度key","score":0-15,"band":"档位","evidence":"原文依据"}],"issues":[{"span":"原文片段","type":"语法/词汇/结构/内容","reason":"中文说明"}],"correction":"修改后的完整作文","summary":"一句中文总评"}''',
        'created_at': createdAt,
      },
      {
        'id': 'cet4_translation',
        'type': 'translation',
        'scoring_mode': 'ai_rubric',
        'dimensions_json': jsonEncode(dims([
          ('comprehension', '原文理解', 0.40),
          ('accuracy', '译文准确', 0.40),
          ('fluency', '表达通顺', 0.20),
        ])),
        'bands_json': jsonEncode(bands15),
        'prompt_template': '''你是 CET-4 汉译英阅卷员。逐句核对原文信息是否完整、准确、通顺。
评分维度(权重见括号):{维度}
分档参考:{档位}
题目(中文原文):{题目}
学生译文:{学生答案}
只输出 JSON:
{"score":总分(0-15),"dimensions":[{"key":"维度key","score":0-15,"band":"档位","evidence":"学生译文中的依据"}],"issues":[{"span":"学生译文片段","type":"误译/漏译/语法/搭配","reason":"中文说明","suggestion":"建议译法"}],"correction":"参考译文","summary":"一句中文总评"}''',
        'created_at': createdAt,
      },
      {
        'id': 'back_translation',
        'type': 'back_translation',
        'scoring_mode': 'ai_rubric',
        'dimensions_json': jsonEncode(dims([
          ('accuracy', '准确', 0.60),
          ('fluency', '通顺', 0.40),
        ])),
        'bands_json': jsonEncode(bands5),
        'prompt_template': '''你是回译练习评分员。用户先读英文原句,再只看中文把英文写回来;
请对照"英文原句"判断还原度,不要因为学生用了同义表达就扣分。
评分维度(权重见括号):{维度}
分档参考:{档位}
英文原句(标准答案):{参考}
中文提示:{题目}
学生写回的英文:{学生答案}
只输出 JSON:
{"score":总分(0-5),"dimensions":[{"key":"维度key","score":0-5,"band":"档位","evidence":"学生译文中的依据"}],"issues":[{"span":"片段","type":"语法/词汇/漏信息","reason":"中文说明"}],"correction":"更自然的英文版本","summary":"一句中文总评"}''',
        'created_at': createdAt,
      },
      {
        'id': 'summary',
        'type': 'summary',
        'scoring_mode': 'ai_rubric',
        'dimensions_json': jsonEncode(dims([
          ('coverage', '要点覆盖', 0.50),
          ('coherence', '连贯', 0.30),
          ('language', '语言', 0.20),
        ])),
        'bands_json': jsonEncode(bands5),
        'prompt_template': '''你是英文摘要评分员。先列出原文的关键要点,再检查学生摘要覆盖了哪些。
评分维度(权重见括号):{维度}
分档参考:{档位}
原文:{题目}
学生摘要:{学生答案}
只输出 JSON:
{"score":总分(0-5),"dimensions":[{"key":"维度key","score":0-5,"band":"档位","evidence":"学生摘要中的依据"}],"issues":[{"span":"片段","type":"漏要点/冗余/语言","reason":"中文说明"}],"correction":"参考摘要","summary":"一句中文总评"}''',
        'created_at': createdAt,
      },
    ];
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

  /// v2.18:老 `tutor_tasks` 回填 `status`(done_at 非空 → 'done'),**幂等**。
  ///
  /// 为什么只改 `status` 仍是默认 'pending' 的行:迁移重跑/自检重跑时,
  /// 不能把用户后来设成 skipped/expired 的任务又改回 done;而 'pending'
  /// 等价于"从未写过状态"(v22 之前所有行都是默认值)。
  /// 失败只记日志不阻断启动 —— 任务卡照常显示,只是状态少回填一次。
  static Future<int> _backfillTutorTaskStatus(DatabaseExecutor db) async {
    try {
      return await db.update(
        'tutor_tasks',
        {'status': 'done'},
        where: "done_at IS NOT NULL AND done_at != '' "
            "AND (status IS NULL OR status = 'pending')",
      );
    } catch (e) {
      debugPrint('ReadFlow 回填 tutor_tasks.status 失败(不影响启动): $e');
      return 0;
    }
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

  /// v19:清理「移动材料」二次拼前缀留下的脏路径(用户 2026-11-01 截图:
  /// 移动弹层同时出现「书籍/《Character》」和「书籍/书籍/《Character》」)。
  ///
  /// 病根:移动弹层选项本身就是完整 `material_path`,旧 `_moveInto` 又把它当
  /// "材料名"交给 `buildMaterialPath` 二次拼分类前缀 → `书籍/书籍/《X》`;
  /// 而分组键(`groupMaterials`)就是原始路径字符串 → 脏串与干净串永远不相等,
  /// 同一本书被拆成两个分组("移动后不并入老分类,而是重复新建")。
  /// `vocabulary.source_book` 也被同一条链路写成了整条路径。
  ///
  /// 只做**本地确定性判定**的归一(纯函数与 `utils/material_group.dart` 同一份,
  /// 单一事实来源),不做模糊猜测:
  /// - 只处理至少 3 段的路径 —— 二次拼前缀必然产生 ≥3 段;
  /// - 两段的 `书籍/书籍`(材料名恰好叫「书籍」)是合法数据,不折;
  /// - 不改 id/掌握度/created_at/occurrences_json;`word_review` 按 vocab_id
  ///   关联,id 不变 → 复习状态天然不受影响;
  /// - 单事务 + batch,失败整体回滚(下次启动 `_onOpen` 会重跑,幂等)。
  ///
  /// ⚠️ 为什么不复用 v8 的 [_normalizeBookPaths]:它是"把第三段当页码"的旧
  /// 规则,会把 `书籍/书籍/《X》` 归成 `书籍/书籍` + `source_page=《X》`,
  /// 越修越脏 —— 重复前缀必须按"折掉重复前导段"单独处理。
  ///
  /// 返回实际修复的条数(0 = 库是干净的;测试与诊断日志用)。
  static Future<int> _normalizeDuplicatedMaterialPaths(Database db) async {
    // 1) vocabulary:先按"至少 3 段"粗筛(LIKE 用不上索引,但 5000 词上限的
    //    全表扫描在启动时只花几毫秒),再用纯函数确认是否真的需要改。
    final vocabCols = await db.rawQuery('PRAGMA table_info(vocabulary)');
    final hasSourceBook =
        vocabCols.any((r) => (r['name'] as String?) == 'source_book');
    final vocabRows = await db.query(
      'vocabulary',
      columns: [
        'id',
        'category',
        'material_path',
        if (hasSourceBook) 'source_book',
      ],
      where: "material_path IS NOT NULL AND material_path != '' "
          "AND material_path LIKE '%/%/%'",
    );

    // 2) materials.group_name:没有分类前缀的自由文本,按通用"重复前导段"折。
    //    表/列都先确认存在 —— 老库/半迁移库里这两个都可能缺。
    var materialRows = const <Map<String, Object?>>[];
    final hasMaterials = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='materials'",
    )).isNotEmpty;
    if (hasMaterials) {
      final cols = await db.rawQuery('PRAGMA table_info(materials)');
      if (cols.any((r) => (r['name'] as String?) == 'group_name')) {
        materialRows = await db.query(
          'materials',
          columns: ['id', 'group_name'],
          where: "group_name IS NOT NULL AND group_name LIKE '%/%'",
        );
      }
    }
    if (vocabRows.isEmpty && materialRows.isEmpty) return 0;

    var fixed = 0;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in vocabRows) {
        final id = r['id'] as int?;
        if (id == null) continue;
        final category = (r['category'] as String?)?.trim() ?? '';
        final rawPath = (r['material_path'] as String?) ?? '';
        final fixedPath = normalizeMaterialPath(category, rawPath);
        if (fixedPath.isEmpty || fixedPath == rawPath) continue;
        final updates = <String, Object?>{'material_path': fixedPath};
        if (hasSourceBook) {
          final book = ((r['source_book'] as String?) ?? '').trim();
          // 旧实现 source_book = 完整路径(必然以 `分类/` 开头)。只修这种
          // 确定脏的;用户自己填的书名即使带斜杠也不动。
          if (book.isNotEmpty &&
              category.isNotEmpty &&
              book.startsWith('$category/')) {
            updates['source_book'] = materialDisplayName(fixedPath, category);
          }
        }
        batch.update('vocabulary', updates, where: 'id = ?', whereArgs: [id]);
        fixed++;
      }
      for (final r in materialRows) {
        final id = r['id'] as int?;
        if (id == null) continue;
        final raw = (r['group_name'] as String?) ?? '';
        final normalized = normalizeGroupName(raw);
        if (normalized.isEmpty || normalized == raw) continue;
        batch.update(
          'materials',
          {'group_name': normalized},
          where: 'id = ?',
          whereArgs: [id],
        );
        fixed++;
      }
      if (fixed > 0) await batch.commit(noResult: true);
    });
    if (fixed > 0) {
      debugPrint('ReadFlow 材料路径归一:修复 $fixed 处重复分类前缀');
    }
    return fixed;
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

  /// 批量插入生词（AI 识别结果 / 听写收词 / 阅读器收词 / 追问存词）。
  ///
  /// **一个词一行,但出现次数要记**(v2.4,B4 用户要求):
  /// - 库里没有这个词 → 插一条;
  /// - 已经有 → **不插新行**,而是把这次的出处(书/页/原句/时间)追加到
  ///   `occurrences_json`,词汇本显示 `apple(×2)` 并列出每处出现;
  /// - 已有的释义/音标/掌握度**不被覆盖**(用户改过的数据不能被"又见一次"冲掉),
  ///   只有原来为空时才用新值补上。
  ///
  /// 词面按 `trim().toLowerCase()` 比较(用户手打的词常带空格)。
  /// 返回 [VocabInsertOutcome]:新增几条、合并几次出现。
  ///
  /// 为什么放在这一层:所有收词入口最终都走这里,而它们都没有查重
  /// (v2.3.3 先做了"跳过重复",v2.4 升级为"合并出现")。
  static Future<VocabInsertOutcome> insertVocabularies(
    List<Vocabulary> list,
  ) async {
    if (list.isEmpty) return const VocabInsertOutcome();
    final db = await database;
    var added = 0;
    var merged = 0;
    var occurrencesAdded = 0;
    await db.transaction((txn) async {
      // 读出已有词条(整行:合并出现时要保留原有释义/音标/掌握度)
      final existing = <String, Map<String, Object?>>{};
      final rows = await txn.query('vocabulary');
      for (final r in rows) {
        existing[_dedupeKey('${r['word'] ?? ''}')] = Map<String, Object?>.from(r);
      }

      final batch = txn.batch();
      var pending = 0;
      for (final v in list) {
        final key = _dedupeKey(v.word);
        if (key.isEmpty) continue;
        final prev = existing[key];
        if (prev == null) {
          // 新词条:把这次的出处写进去(自带 occurrences 优先,否则用词条自身出处)
          final seeds = _occurrencesOf(v);
          final row = v.toMap();
          if (seeds.isNotEmpty && row['occurrences_json'] == null) {
            row['occurrences_json'] = VocabOccurrence.encodeList(seeds);
          }
          batch.insert('vocabulary', row);
          existing[key] = row;
          added++;
          pending++;
          continue;
        }
        // 已存在 → 合并出现记录
        final prevList = VocabOccurrence.decodeList(prev['occurrences_json']);
        final keys = {for (final o in prevList) o.key};
        final incoming = _occurrencesOf(v);
        final fresh = [
          for (final o in incoming)
            if (!o.isEmpty && keys.add(o.key)) o,
        ];
        final updates = <String, Object?>{};
        if (fresh.isNotEmpty) {
          final all = [...prevList, ...fresh];
          updates['occurrences_json'] = VocabOccurrence.encodeList(all);
          occurrencesAdded += fresh.length;
        }
        // 只在原来为空时补字段(不覆盖用户/历史的既有值)
        void fillIfEmpty(String column, String? value) {
          final cur = '${prev[column] ?? ''}'.trim();
          final next = (value ?? '').trim();
          if (cur.isEmpty && next.isNotEmpty) updates[column] = next;
        }

        fillIfEmpty('translation', v.translation);
        fillIfEmpty('phonetic_uk', v.phoneticUk);
        fillIfEmpty('phonetic_us', v.phoneticUs);
        fillIfEmpty('original_sentence', v.originalSentence);
        fillIfEmpty('part_of_speech', v.partOfSpeech);
        if (updates.isNotEmpty || fresh.isNotEmpty) {
          updates['updated_at'] = DateTime.now().toIso8601String();
          batch.update(
            'vocabulary',
            updates,
            where: 'id = ?',
            whereArgs: [prev['id']],
          );
          pending++;
        }
        merged++;
      }
      if (pending > 0) await batch.commit(noResult: true);
    });
    return VocabInsertOutcome(
      added: added,
      merged: merged,
      occurrencesAdded: occurrencesAdded,
    );
  }

  /// 词面去重键:忽略大小写与首尾空白(用户手打的词经常带空格)
  static String _dedupeKey(String word) => word.trim().toLowerCase();

  /// 这个词条这次带来的"出现"记录:自带 occurrences 优先,
  /// 否则用词条自身的出处兜底(老调用方只传 source_book/source_page/原句)
  static List<VocabOccurrence> _occurrencesOf(Vocabulary v) {
    if (v.occurrences.isNotEmpty) return v.occurrences;
    final fallback = VocabOccurrence(
      book: v.sourceBook ?? '',
      page: v.sourcePage ?? '',
      sentence: v.originalSentence ?? '',
      at: v.createdAt,
    );
    return fallback.isEmpty ? const [] : [fallback];
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

  /// 把一批词从当前材料分组里"摘出来"(v2.7,用户第 6(1) 条):
  /// `material_path` 与 `source_book` 置空、词本身保留 —— 用在「解散分组」上
  /// (分组没了,词还在,回到「未归类」)。
  ///
  /// 为什么不复用 [updateVocabulariesCategory]:那个方法的 null 语义是
  /// **"这一列不改"**,表达不了"清空";这里必须显式写 NULL,所以单独一个方法,
  /// 免得将来有人顺手把 null 传进去结果什么都没发生。
  static Future<int> detachMaterialPath(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final db = await database;
    var affected = 0;
    await db.transaction((txn) async {
      for (final chunk in _chunkIds(ids)) {
        final placeholders = List.filled(chunk.length, '?').join(',');
        affected += await txn.update(
          'vocabulary',
          {
            'material_path': null,
            'source_book': null,
            'updated_at': DateTime.now().toIso8601String(),
          },
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
    'cover_url',
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

  // ── 阅读器译文(v2.16.0 / dbVersion 20)──
  //
  // 设计口径:
  // - 一段一条(UNIQUE(material_id, unit_index)),重翻 = UPSERT 覆盖并刷新 updated_at
  //   (created_at 保留第一次翻成功的时间 —— "这条译文是什么时候第一次有的")；
  // - 读出来必须带 source_text:材料重新导入/切段变化后 unit 下标会漂移,
  //   只有快照一致才敢显示(见 [alignTranslationsToUnits])；
  // - 所有方法失败都**静默降级**(返回空/不抛):译文是"阅读的辅助",
  //   落库失败不能让阅读器打不开,下次翻到这段会再试一次。

  /// 写入/覆盖一条阅读器译文。重翻同一段 → 覆盖译文并刷新 updated_at。
  static Future<void> saveMaterialTranslation(
    int materialId, {
    required int unitIndex,
    required int chunkIndex,
    required String sourceText,
    required String translatedText,
    String? model,
  }) async {
    final source = sourceText.trim();
    final translated = translatedText.trim();
    if (materialId <= 0 || unitIndex < 0 || source.isEmpty || translated.isEmpty) {
      return; // 空内容不落库(避免脏行占住 UNIQUE 槽位)
    }
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      await db.rawInsert(
        '''
        INSERT INTO material_translations
          (material_id, unit_index, chunk_index, source_text, translated_text,
           model, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(material_id, unit_index) DO UPDATE SET
          chunk_index = excluded.chunk_index,
          source_text = excluded.source_text,
          translated_text = excluded.translated_text,
          model = excluded.model,
          updated_at = excluded.updated_at
        ''',
        [
          materialId,
          unitIndex,
          chunkIndex,
          source,
          translated,
          (model ?? '').trim().isEmpty ? null : model!.trim(),
          now,
          now,
        ],
      );
    } catch (e) {
      debugPrint('ReadFlow saveMaterialTranslation failed: $e');
    }
  }

  /// 读出某份材料已落库的译文**原始记录**(含 source_text 快照)。
  ///
  /// 阅读器应该用这个 + [alignTranslationsToUnits] 做防错位过滤;
  /// [loadMaterialTranslations] 只是"不关心错位风险"的便捷 Map 版本。
  static Future<List<MaterialTranslation>> loadMaterialTranslationRecords(
    int materialId,
  ) async {
    try {
      final db = await database;
      final rows = await db.query(
        'material_translations',
        where: 'material_id = ?',
        whereArgs: [materialId],
        orderBy: 'unit_index ASC',
      );
      return [
        for (final r in rows)
          if ('${r['translated_text'] ?? ''}'.trim().isNotEmpty)
            MaterialTranslation(
              unitIndex: (r['unit_index'] as num?)?.toInt() ?? -1,
              chunkIndex: (r['chunk_index'] as num?)?.toInt() ?? -1,
              sourceText: '${r['source_text'] ?? ''}',
              translatedText: '${r['translated_text'] ?? ''}',
              model: r['model'] as String?,
              updatedAt: DateTime.tryParse('${r['updated_at'] ?? ''}'),
            ),
      ];
    } catch (e) {
      debugPrint('ReadFlow loadMaterialTranslationRecords failed: $e');
      return [];
    }
  }

  /// 某份材料已落库译文:`unit_index → 译文`(不做 source_text 校验)。
  static Future<Map<int, String>> loadMaterialTranslations(
    int materialId,
  ) async {
    final records = await loadMaterialTranslationRecords(materialId);
    return {
      for (final r in records)
        if (r.unitIndex >= 0) r.unitIndex: r.translatedText,
    };
  }

  /// **纯函数**:把已落库译文对齐到"当前切段"(防错位)。
  ///
  /// 规则:只有 [MaterialTranslation.sourceText] 与当前 [currentUnitTexts] 同下标
  /// 的段落**内容一致**(仅忽略首尾与连续空白差异)时才采用;不一致说明材料
  /// 重新导入/切段变了,宁可当没翻过(重翻),也不能把别的段落译文显示过来。
  static Map<int, String> alignTranslationsToUnits(
    List<MaterialTranslation> saved,
    List<String> currentUnitTexts,
  ) {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final out = <int, String>{};
    for (final t in saved) {
      final i = t.unitIndex;
      if (i < 0 || i >= currentUnitTexts.length) continue;
      if (norm(t.sourceText) != norm(currentUnitTexts[i])) continue;
      if (t.translatedText.trim().isEmpty) continue;
      out[i] = t.translatedText;
    }
    return out;
  }

  /// 清掉某份材料的全部译文(材料被彻底删除/用户想重翻时用)。
  /// 本轮阅读器不调用它(材料删除流程不动),只是把能力先提供出来。
  static Future<int> deleteMaterialTranslations(int materialId) async {
    try {
      final db = await database;
      return await db.delete(
        'material_translations',
        where: 'material_id = ?',
        whereArgs: [materialId],
      );
    } catch (e) {
      debugPrint('ReadFlow deleteMaterialTranslations failed: $e');
      return 0;
    }
  }

  // ═══════════════ 输出模块 CRUD(v2.17.0 / dbVersion 21)═══════════════
  //
  // 统一约定:失败**静默降级** —— 查询返回 null/空列表、写入返回 0/void。
  // 理由:输出/做题页是"锦上添花"的功能,一次 DB 异常不该让整页崩溃;
  // 需要确认写入成功的场景(出题器)看返回值(0 = 没写进去,事务已回滚)。

  /// 插入一个题组(可带题目)。**单事务**:先插 set 再逐条插 items,
  /// 任何一条失败整体回滚 —— 避免"有卷面没题目"的半套题出现在列表里。
  ///
  /// 返回新题组 id;失败返回 0。
  /// [items] 不需要 set_id(自动注入)与 idx(缺省按数组顺序 0..N-1)。
  static Future<int> insertExerciseSet(
    Map<String, Object?> set, {
    List<Map<String, Object?>> items = const [],
  }) async {
    try {
      final db = await database;
      return await db.transaction<int>((txn) async {
        final setRow = Map<String, Object?>.from(set);
        setRow.putIfAbsent('created_at', () => DateTime.now().toIso8601String());
        final setId = await txn.insert('exercise_sets', setRow);
        for (var i = 0; i < items.length; i++) {
          final itemRow = Map<String, Object?>.from(items[i]);
          itemRow['set_id'] = setId;
          itemRow.putIfAbsent('idx', () => i);
          await txn.insert('exercise_items', itemRow);
        }
        return setId;
      });
    } catch (e) {
      debugPrint('ReadFlow insertExerciseSet failed: $e');
      return 0;
    }
  }

  /// 读一个题组:题组字段 + `items`(题目列表,按 idx 升序)。
  /// 不存在/失败返回 null。
  static Future<Map<String, Object?>?> getExerciseSet(int id) async {
    try {
      final db = await database;
      final rows = await db.query(
        'exercise_sets',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final items = await db.query(
        'exercise_items',
        where: 'set_id = ?',
        whereArgs: [id],
        orderBy: 'idx ASC, id ASC',
      );
      return {...rows.first, 'items': items};
    } catch (e) {
      debugPrint('ReadFlow getExerciseSet failed: $e');
      return null;
    }
  }

  /// 题组列表(创建时间倒序)。[examType]/[section] 非空时过滤。
  static Future<List<Map<String, Object?>>> listExerciseSets({
    String? examType,
    String? section,
    int limit = 50,
  }) async {
    try {
      final db = await database;
      final where = <String>[];
      final args = <Object?>[];
      if (examType != null && examType.trim().isNotEmpty) {
        where.add('exam_type = ?');
        args.add(examType.trim());
      }
      if (section != null && section.trim().isNotEmpty) {
        where.add('section = ?');
        args.add(section.trim());
      }
      final safeLimit = limit < 1 ? 1 : (limit > 200 ? 200 : limit);
      return await db.query(
        'exercise_sets',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: where.isEmpty ? null : args,
        orderBy: 'created_at DESC, id DESC',
        limit: safeLimit,
      );
    } catch (e) {
      debugPrint('ReadFlow listExerciseSets failed: $e');
      return [];
    }
  }

  /// 单条 rubric(内置 4 条固定 id:cet4_writing / cet4_translation /
  /// back_translation / summary);不存在返回 null。
  static Future<Map<String, Object?>?> getRubric(String id) async {
    try {
      final db = await database;
      final rows = await db.query(
        'rubrics',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (e) {
      debugPrint('ReadFlow getRubric failed: $e');
      return null;
    }
  }

  /// 全部 rubric(id 升序:内置 4 条在前,自定义按名称排在后面)。
  static Future<List<Map<String, Object?>>> listRubrics() async {
    try {
      final db = await database;
      return await db.query('rubrics', orderBy: 'created_at ASC, id ASC');
    } catch (e) {
      debugPrint('ReadFlow listRubrics failed: $e');
      return [];
    }
  }

  /// 记录一条作答(失败静默:写不进去不该挡住用户继续做下一题)。
  static Future<void> insertOutputAttempt(Map<String, Object?> attempt) async {
    try {
      final db = await database;
      final row = Map<String, Object?>.from(attempt);
      row.putIfAbsent('created_at', () => DateTime.now().toIso8601String());
      await db.insert('output_attempts', row);
    } catch (e) {
      debugPrint('ReadFlow insertOutputAttempt failed: $e');
    }
  }

  /// 作答列表(created_at 倒序)。
  /// [setItemId] = 只看某一道题(exercise_items.id);
  /// [setId] = 只看某一套题(exercise_sets.id)。
  static Future<List<Map<String, Object?>>> listOutputAttempts({
    int limit = 100,
    int? setItemId,
    int? setId,
  }) async {
    try {
      final db = await database;
      final where = <String>[];
      final args = <Object?>[];
      if (setItemId != null) {
        where.add('item_id = ?');
        args.add(setItemId);
      }
      if (setId != null) {
        where.add('set_id = ?');
        args.add(setId);
      }
      final safeLimit = limit < 1 ? 1 : (limit > 500 ? 500 : limit);
      return await db.query(
        'output_attempts',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: where.isEmpty ? null : args,
        orderBy: 'created_at DESC, id DESC',
        limit: safeLimit,
      );
    } catch (e) {
      debugPrint('ReadFlow listOutputAttempts failed: $e');
      return [];
    }
  }

  /// 输出模块统计(首页/周报/教练页用)。
  ///
  /// 口径(必须写清,否则"正确率"永远对不上 UI):
  /// - `sets` = 题组数(受 [since] 过滤);
  /// - `attempts` = 作答条数(受 [since] 过滤);
  /// - `correctRate` = correct=1 的条数 ÷ **correct 非空**的条数 ——
  ///   主观题 correct=NULL(只有维度分),**不进分母**,否则正确率永远被拉低;
  /// - `totalSeconds` = SUM(seconds);
  /// - `byType` = 按题型(取 exercise_items.type;缺失时回落 exercise_sets.section)
  ///   的作答条数。
  static Future<Map<String, Object?>> outputStats({DateTime? since}) async {
    try {
      final db = await database;
      final sinceIso = since?.toIso8601String();
      final filter = sinceIso == null ? '' : 'WHERE created_at >= ?';
      final args = <Object?>[?sinceIso];

      final setsRow = (await db.rawQuery(
        'SELECT COUNT(*) AS c FROM exercise_sets $filter',
        args,
      )).first;
      final sets = (setsRow['c'] as num?)?.toInt() ?? 0;

      final attemptRow = (await db.rawQuery('''
        SELECT COUNT(*) AS total,
               SUM(CASE WHEN correct IS NULL THEN 0 ELSE 1 END) AS graded,
               SUM(CASE WHEN correct = 1 THEN 1 ELSE 0 END) AS ok,
               COALESCE(SUM(seconds), 0) AS sec
        FROM output_attempts $filter
      ''', args)).first;
      final attempts = (attemptRow['total'] as num?)?.toInt() ?? 0;
      final graded = (attemptRow['graded'] as num?)?.toInt() ?? 0;
      final ok = (attemptRow['ok'] as num?)?.toInt() ?? 0;
      final totalSeconds = (attemptRow['sec'] as num?)?.toInt() ?? 0;
      final correctRate = graded == 0 ? 0.0 : ok / graded;

      final typeRows = await db.rawQuery('''
        SELECT COALESCE(NULLIF(TRIM(i.type), ''),
                        NULLIF(TRIM(s.section), ''),
                        'unknown') AS t,
               COUNT(*) AS c
        FROM output_attempts a
        LEFT JOIN exercise_items i ON i.id = a.item_id
        LEFT JOIN exercise_sets s ON s.id = a.set_id
        ${sinceIso == null ? '' : 'WHERE a.created_at >= ?'}
        GROUP BY t
        ORDER BY c DESC, t ASC
      ''', args);

      return {
        'sets': sets,
        'attempts': attempts,
        'correctRate': correctRate,
        'totalSeconds': totalSeconds,
        'byType': <String, int>{
          for (final r in typeRows)
            '${r['t'] ?? 'unknown'}': (r['c'] as num?)?.toInt() ?? 0,
        },
      };
    } catch (e) {
      debugPrint('ReadFlow outputStats failed: $e');
      return {
        'sets': 0,
        'attempts': 0,
        'correctRate': 0.0,
        'totalSeconds': 0,
        'byType': <String, int>{},
      };
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

  /// 材料库里"最近的材料"(材料中心书架 / 导师的最近材料)。
  ///
  /// ⚠️ 两个都必须对,否则书架整个是坏的(2026-09-24 由整链路测试
  /// `learning_flow_test` 发现,此前一直没被覆盖):
  /// 1. **materials LEFT JOIN material_progress**,不能 INNER JOIN ——
  ///    旧实现从 material_progress 出发,于是"入库但还没打开过"的材料在书架里
  ///    完全不可见,用户粘贴一份材料没立刻读就会看到"还没有材料",像导入失败;
  /// 2. **必须选出 `id`**(以及 source/url/audio_url),旧查询只给了
  ///    `material_id` 别名,而 `ShelfItem` 读的是 `id` → 每一条的 id 都是 0,
  ///    点书架里任何一份材料都会去打开 id=0 的材料(打不开)。
  /// 排序用 COALESCE:读过的按最近阅读时间,没读过的按入库时间。
  static Future<List<Map<String, Object?>>> getRecentMaterials({
    int limit = 10,
  }) async {
    try {
      final db = await database;
      return await db.rawQuery(
        '''
        SELECT m.id AS id,
               m.id AS material_id,
               m.title AS title,
               m.kind AS kind,
               m.source AS source,
               m.url AS url,
               m.audio_url AS audio_url,
               m.cefr AS cefr,
               m.word_count AS word_count,
               m.coverage AS coverage,
               m.est_minutes AS est_minutes,
               m.origin AS origin,
               m.group_name AS group_name,
               m.title_cn AS title_cn,
               m.cover_url AS cover_url,
               p.position AS position,
               p.percent AS percent,
               p.minutes AS minutes,
               p.picked_words AS picked_words,
               COALESCE(p.updated_at, m.created_at) AS updated_at,
               p.finished_at AS finished_at
        FROM materials m
        LEFT JOIN material_progress p ON p.material_id = m.id
        ORDER BY COALESCE(p.updated_at, m.created_at) DESC, m.id DESC
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
  ///
  /// **恢复备份**(P2 修复):传 `reps` / `lapses` = 按**绝对值**写入,而不是累加。
  /// 以前这里写死 `reps = 1`,所以从备份恢复的词全部丢掉复习次数与遗忘次数
  /// (调度结果还在,但"这个词我复习过 12 次"这类信息没了)。备份 JSON 里
  /// 一直带着这两个数,只是恢复时没被用上。
  static Future<void> upsertWordReview(
    int vocabId, {
    required double stability,
    required double difficulty,
    required DateTime dueAt,
    int? lastRating,
    required DateTime lastReviewAt,
    bool lapse = false,
    int? reps,
    int? lapses,
  }) async {
    try {
      final db = await database;
      final nowIso = DateTime.now().toIso8601String();
      // 恢复模式:两个计数都按传入值写死;正常复习:按累加语义
      final conflictReps =
          reps != null ? 'excluded.reps' : 'word_review.reps + 1';
      final conflictLapses =
          lapses != null ? 'excluded.lapses' : 'word_review.lapses + ?';
      await db.rawInsert(
        '''
        INSERT INTO word_review
          (vocab_id, stability, difficulty, due_at, last_review_at,
           reps, lapses, last_rating, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(vocab_id) DO UPDATE SET
          stability = excluded.stability,
          difficulty = excluded.difficulty,
          due_at = excluded.due_at,
          last_review_at = excluded.last_review_at,
          reps = $conflictReps,
          lapses = $conflictLapses,
          last_rating = COALESCE(excluded.last_rating, word_review.last_rating),
          updated_at = excluded.updated_at
      ''',
        [
          vocabId,
          stability,
          difficulty,
          dueAt.toIso8601String(),
          lastReviewAt.toIso8601String(),
          reps ?? 1,
          lapses ?? (lapse ? 1 : 0),
          lastRating,
          nowIso,
          nowIso,
          // 只有走"累加"分支时才有这个占位符
          if (lapses == null) (lapse ? 1 : 0),
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

  /// 清空全部复习状态(v2.2 备份"覆盖恢复"用:先清空再导入,
  /// 否则旧卡的到期时间会与新数据打架)
  static Future<int> clearWordReviews() async {
    try {
      final db = await database;
      return await db.delete('word_review');
    } catch (e) {
      debugPrint('ReadFlow clearWordReviews failed: $e');
      return 0;
    }
  }

  // ── 导师 ──

  /// 新建导师任务卡。`plan_date` 存完整 ISO8601(与全表约定一致),
  /// 取"当天"靠 [getTutorTasks] 的 [当天 00:00, 次日 00:00) 半开区间
  /// (走 idx_tutor_task_date)。返回任务 id,失败 -1。
  ///
  /// v2.18 起支持任务来源与状态机字段(全部可选,旧调用点不用改):
  /// - [origin]:`auto`(助理计划生成,默认)/ `custom`(用户自建);
  /// - [status]:默认 `pending`;`custom` 任务可直接从 `active` 开始;
  /// - [note]/[goalTag]/[parentId]:自定义备注、关联目标、周期模板父任务。
  ///
  /// 每次插入都会写一条 `task_events(event='create')` —— 复盘要能回答
  /// "这个任务是哪来的、什么时候建的",而不是只看一条当前行。
  static Future<int> insertTutorTask({
    required DateTime planDate,
    required String kind,
    required String title,
    Map<String, Object?>? payload,
    int targetMinutes = 0,
    String origin = 'auto',
    String status = 'pending',
    String? note,
    String? goalTag,
    int? parentId,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('tutor_tasks', {
        'plan_date': planDate.toIso8601String(),
        'kind': kind,
        'title': title,
        'payload_json': payload == null ? null : jsonEncode(payload),
        'target_minutes': targetMinutes,
        'origin': origin,
        'status': status,
        'note': note,
        'goal_tag': goalTag,
        'parent_id': parentId,
        'created_at': now,
      });
      if (id > 0) {
        await insertTaskEvent(<String, Object?>{
          'task_id': id,
          'event': 'create',
          'at': now,
          'payload_json': <String, Object?>{
            'origin': origin,
            'status': status,
            'kind': kind,
          },
        });
      }
      return id;
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

  /// 勾掉任务卡:写 done_at + `status='done'`,有 [result] 时一并写入
  /// (不传 = 保留已有结果);**同时写一条 submit 事件**。
  ///
  /// 为什么旧方法也要同步 status/事件:旧 tutor_home 的"手动勾"仍在调用它,
  /// 若只写 done_at 不写 status,新状态机统计会把"做完的任务"算成 pending。
  /// 返回受影响行数(0 = id 不存在)。
  static Future<int> completeTutorTask(
    int id, {
    Map<String, Object?>? result,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      var affected = 0;
      await db.transaction((txn) async {
        final before = await txn.query(
          'tutor_tasks',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final from = before.isEmpty ? null : '${before.first['status'] ?? ''}';
        affected = await txn.update(
          'tutor_tasks',
          {
            'done_at': now,
            'status': 'done',
            if (result != null) 'result_json': jsonEncode(result),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        if (affected > 0) {
          await txn.insert('task_events', {
            'task_id': id,
            'event': 'submit',
            'at': now,
            'payload_json': jsonEncode(<String, Object?>{
              'from': from,
              'to': 'done',
              'manual': true,
              if (result != null) 'has_result': true,
            }),
            'created_at': now,
          });
        }
      });
      return affected;
    } catch (e) {
      debugPrint('ReadFlow completeTutorTask failed: $e');
      return 0;
    }
  }

  /// 取消完成(v2.4,A5):把 done_at 与 result 清掉,任务回到"待办"。
  /// 用户实测"划去任务后没法再点回来" —— 勾选必须能来回切换。
  ///
  /// v2.18:同步把 status 回 `pending` 并记一条 reopen 事件(审计口径:
  /// "撤销完成"是一次 reopen,不是删除历史)。
  static Future<int> reopenTutorTask(int id) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      var affected = 0;
      await db.transaction((txn) async {
        final before = await txn.query(
          'tutor_tasks',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final from = before.isEmpty ? null : '${before.first['status'] ?? ''}';
        affected = await txn.update(
          'tutor_tasks',
          {'done_at': null, 'result_json': null, 'status': 'pending'},
          where: 'id = ?',
          whereArgs: [id],
        );
        if (affected > 0) {
          await txn.insert('task_events', {
            'task_id': id,
            'event': 'reopen',
            'at': now,
            'payload_json': jsonEncode(<String, Object?>{
              'from': from,
              'to': 'pending',
              'manual': true,
            }),
            'created_at': now,
          });
        }
      });
      return affected;
    } catch (e) {
      debugPrint('ReadFlow reopenTutorTask failed: $e');
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

  // ═══════════════ v2.18(dbVersion 22):助理数据层 ═══════════════
  //
  // 三块能力(批 4 · 助理重做):
  // ① ability_snapshots:能力项(vocab/grammar/reading/output/habit)的时间
  //    序列,带来源/置信度/证据 —— "现状分析"从"报行为债"升级为"报能力项变化";
  // ② task_events:状态机每次变化的**只追加审计**,复盘能回答"跳了几次/改过几次";
  // ③ tutor_tasks 状态机 CRUD:任务可编辑/跳过/过期/撤销,并留痕。
  //
  // 与旧方法的关系:getTutorTasks/completeTutorTask/reopenTutorTask 保留;
  // complete/reopen 内部同步 status 与事件 —— 新旧两条 UI 链路读同一份事实。

  /// 合法任务状态(顺序即 UI 状态点/筛选项顺序)
  static const List<String> tutorTaskStatuses = <String>[
    'pending',
    'active',
    'done',
    'skipped',
    'expired',
  ];

  /// 合法任务事件(只追加审计)
  static const List<String> tutorTaskEvents = <String>[
    'create',
    'start',
    'submit',
    'skip',
    'reopen',
    'edit',
    'expire',
  ];

  /// 任务来源:auto = 助理按诊断派的任务;custom = 用户自建
  static const List<String> tutorTaskOrigins = <String>['auto', 'custom'];

  /// 能力项维度(固定顺序:现状分析/复盘图表都按它渲染)
  static const List<String> abilityDimensions = <String>[
    'vocab',
    'grammar',
    'reading',
    'output',
    'habit',
  ];

  /// 能力项来源:test=测出来 / self_report=自报 / inferred=行为推断
  static const List<String> abilitySources = <String>[
    'test',
    'self_report',
    'inferred',
  ];

  static bool isValidTutorTaskStatus(String status) =>
      tutorTaskStatuses.contains(status.trim());

  /// 状态 → 审计事件(状态机的"落事件"口径)
  static String eventForTutorTaskStatus(String status) =>
      switch (status.trim()) {
        'active' => 'start',
        'done' => 'submit',
        'skipped' => 'skip',
        'expired' => 'expire',
        _ => 'reopen', // pending:撤销完成 / 重新打开
      };

  // ── 能力快照 ──────────────────────────────────────────────────────

  /// 写一条能力项快照(**upsert**:同 `dimension + snapshot_at` 只留一条)。
  ///
  /// 为什么是 upsert 而不是纯插入:同一天可能被多个触发点写(词汇量测试、
  /// 写作批改、周报、任务结算),纯插入会让"今天的能力值"出现多行、趋势图锯齿;
  /// 但**不同 snapshot_at** 仍逐条保留 —— 趋势看的是时间序列,不能覆盖历史。
  ///
  /// [snapshot] 支持的键:`snapshot_at`(默认现在)、`dimension`(必填)、
  /// `value`、`unit`、`source`、`confidence`、`evidence_json`(Map/List/已是
  /// JSON 串均可)、`created_at`。返回快照 id,失败 -1。
  static Future<int> insertAbilitySnapshot(Map<String, Object?> snapshot) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      final dimension = '${snapshot['dimension'] ?? ''}'.trim();
      if (dimension.isEmpty) return -1;
      final snapshotAt =
          '${snapshot['snapshot_at'] ?? now}'.trim().isEmpty
              ? now
              : '${snapshot['snapshot_at'] ?? now}'.trim();
      final row = <String, Object?>{
        'snapshot_at': snapshotAt,
        'dimension': dimension,
        'value': _toDoubleOrNull(snapshot['value']) ?? 0,
        'unit': snapshot['unit']?.toString(),
        'source': snapshot['source']?.toString(),
        'confidence': _toDoubleOrNull(snapshot['confidence']),
        'evidence_json': _jsonFieldOrNull(snapshot['evidence_json']),
        'created_at': '${snapshot['created_at'] ?? now}',
      };
      final existing = await db.query(
        'ability_snapshots',
        columns: ['id'],
        where: 'dimension = ? AND snapshot_at = ?',
        whereArgs: [dimension, snapshotAt],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final id = (existing.first['id'] as num).toInt();
        await db.update(
          'ability_snapshots',
          row,
          where: 'id = ?',
          whereArgs: [id],
        );
        return id;
      }
      return await db.insert('ability_snapshots', row);
    } catch (e) {
      debugPrint('ReadFlow insertAbilitySnapshot failed: $e');
      return -1;
    }
  }

  /// 某维度的**最新**能力快照(没有 → null;**不编默认值**)
  static Future<Map<String, Object?>?> latestAbility(String dimension) async {
    try {
      final db = await database;
      final rows = await db.query(
        'ability_snapshots',
        where: 'dimension = ?',
        whereArgs: [dimension.trim()],
        orderBy: 'snapshot_at DESC, id DESC',
        limit: 1,
      );
      return rows.isEmpty ? null : _decorateAbilitySnapshot(rows.first);
    } catch (e) {
      debugPrint('ReadFlow latestAbility failed: $e');
      return null;
    }
  }

  /// 某维度**上一次**快照(用于"变化量":latest - previous;没有 → null)。
  ///
  /// 取最近两条的**第二条**;只有一条时返回 null —— 不能拿最新条跟自己比
  /// 算出"变化 0",那会让界面显示"这周没变化"(其实是没有历史可比较)。
  static Future<Map<String, Object?>?> previousAbility(
    String dimension,
  ) async {
    try {
      final db = await database;
      final rows = await db.query(
        'ability_snapshots',
        where: 'dimension = ?',
        whereArgs: [dimension.trim()],
        orderBy: 'snapshot_at DESC, id DESC',
        limit: 2,
      );
      if (rows.length < 2) return null;
      return _decorateAbilitySnapshot(rows[1]);
    } catch (e) {
      debugPrint('ReadFlow previousAbility failed: $e');
      return null;
    }
  }

  /// 某维度最近 [limit] 条快照,按时间**升序**返回(画趋势图可直接用)。
  ///
  /// SQL 先 DESC 取最新 N 条再反转:直接 ASC + LIMIT 会取到**最早**的 N 条
  /// (和能力项越用越久的历史相反),这是"列表 limit"最常见的坑。
  static Future<List<Map<String, Object?>>> abilityHistory(
    String dimension, {
    int limit = 30,
  }) async {
    try {
      final db = await database;
      final rows = await db.query(
        'ability_snapshots',
        where: 'dimension = ?',
        whereArgs: [dimension.trim()],
        orderBy: 'snapshot_at DESC, id DESC',
        limit: limit <= 0 ? 30 : limit,
      );
      return rows.reversed.map(_decorateAbilitySnapshot).toList();
    } catch (e) {
      debugPrint('ReadFlow abilityHistory failed: $e');
      return [];
    }
  }

  // ── 任务事件 ──────────────────────────────────────────────────────

  /// 追加一条任务事件(只追加,不改不删)。
  ///
  /// [event] 支持的键:`task_id`(必填)、`event`(必填,建议取自
  /// [tutorTaskEvents])、`at`(默认现在)、`payload_json`/`payload`
  /// (Map/List/JSON 串)、`created_at`。参数非法/写库失败静默跳过 ——
  /// 审计是"加分项",不能因为记事件失败让任务操作本身失败。
  static Future<void> insertTaskEvent(Map<String, Object?> event) async {
    try {
      final taskId = _toIntOrNull(event['task_id']);
      final name = '${event['event'] ?? ''}'.trim();
      if (taskId == null || taskId <= 0 || name.isEmpty) return;
      final db = await database;
      final now = DateTime.now().toIso8601String();
      await db.insert('task_events', {
        'task_id': taskId,
        'event': name,
        'at': '${event['at'] ?? now}',
        'payload_json':
            _jsonFieldOrNull(event['payload_json'] ?? event['payload']),
        'created_at': '${event['created_at'] ?? now}',
      });
    } catch (e) {
      debugPrint('ReadFlow insertTaskEvent failed: $e');
    }
  }

  /// 某任务的全部事件,按时间**正序**(复盘时间线:create → start → submit…)。
  /// 每条附解析后的 `payload` 键(坏 JSON → null,原串保留)。
  static Future<List<Map<String, Object?>>> listTaskEvents(int taskId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'task_events',
        where: 'task_id = ?',
        whereArgs: [taskId],
        orderBy: 'at ASC, id ASC',
      );
      return rows
          .map((row) => <String, Object?>{
                ...row,
                'payload': _tryDecodeJson(row['payload_json']?.toString()),
              })
          .toList();
    } catch (e) {
      debugPrint('ReadFlow listTaskEvents failed: $e');
      return [];
    }
  }

  // ── 任务状态机 ────────────────────────────────────────────────────

  /// 改任务状态,**同时写一条 task_events**(复盘要审计,不能只改当前行)。
  ///
  /// 状态机(research §2.4.2):
  /// ```
  /// pending ──开始──> active ──提交/手动勾──> done
  /// pending/active ──跳过──> skipped
  /// pending/active ──次日结算未做──> expired
  /// done/skipped ──重新打开──> pending
  /// ```
  /// 行为约定:
  /// - `active` 且没给 [startedAt]:自动写开始时间(第一次开始);
  /// - `done` 且 done_at 为空:自动补 done_at(手动勾也算完成时间);
  /// - `pending`(撤销/重开):清掉 done_at/result_json —— 避免出现
  ///   "状态是 pending 但仍有完成时间"的自相矛盾行;
  /// - [resultJson] 是**已编码的 JSON 串**(UI 传 jsonEncode(map)),不传则保留原值;
  /// - 非法 status/不存在的 id 一律静默忽略(记 debugPrint),不抛给 UI。
  /// 编辑任务本身(标题 / 预计分钟 / 归属维度 / 说明)。
  ///
  /// v3 批 4(用户 2026-11-01):"学习任务也是死的,不支持用户编辑自定义
  /// —— 支持后,还要支持软件内部的数据追踪复盘与指导"。
  /// 所以任务必须可改:改标题、改时长、改归属;每次修改都写一条 `edit` 事件,
  /// 复盘时才能回答"这条任务是被用户改过才完成的,还是原样完成的"。
  ///
  /// 与 [updateTutorTaskStatus] 分开的原因:状态迁移会联动 `started_at` /
  /// `done_at` / 清 `result_json` 等规则,编辑只改"内容字段",不碰状态。
  static Future<bool> updateTutorTaskFields(
    int taskId, {
    String? title,
    int? targetMinutes,
    String? kind,
    String? goalTag,
    String? note,
  }) async {
    if (taskId <= 0) return false;
    final fields = <String, Object?>{};
    if (title != null && title.trim().isNotEmpty) {
      fields['title'] = title.trim();
    }
    if (targetMinutes != null && targetMinutes >= 0) {
      fields['target_minutes'] = targetMinutes;
    }
    if (kind != null && kind.trim().isNotEmpty) fields['kind'] = kind.trim();
    if (goalTag != null) fields['goal_tag'] = goalTag.trim();
    if (note != null) fields['note'] = note;
    if (fields.isEmpty) return false;
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      await db.transaction((txn) async {
        await txn.update(
          'tutor_tasks',
          fields,
          where: 'id = ?',
          whereArgs: [taskId],
        );
        await txn.insert('task_events', {
          'task_id': taskId,
          'event': 'edit',
          'at': now,
          'payload_json': jsonEncode(fields),
          'created_at': now,
        });
      });
      return true;
    } catch (e) {
      debugPrint('ReadFlow updateTutorTaskFields failed: $e');
      return false;
    }
  }

  /// 更新任务状态(状态机 + 审计事件,v2.18.0 / 批 4)。
  ///
  /// 规则:
  /// - `active` 且没给 [startedAt]:自动写开始时间(第一次开始);
  /// - `done` 且 done_at 为空:自动补 done_at(手动勾也算完成时间);
  /// - `pending`(撤销/重开):清掉 done_at/result_json —— 避免出现
  ///   "状态是 pending 但仍有完成时间"的自相矛盾行;
  /// - [resultJson] 是**已编码的 JSON 串**(UI 传 jsonEncode(map)),不传则保留原值;
  /// - 非法 status/不存在的 id 一律静默忽略(记 debugPrint),不抛给 UI。
  static Future<void> updateTutorTaskStatus(
    int taskId,
    String status, {
    String? startedAt,
    int? actualMinutes,
    String? note,
    String? resultJson,
  }) async {
    final target = status.trim();
    if (taskId <= 0 || !isValidTutorTaskStatus(target)) {
      debugPrint('ReadFlow updateTutorTaskStatus 参数非法: id=$taskId status=$status');
      return;
    }
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      await db.transaction((txn) async {
        final before = await txn.query(
          'tutor_tasks',
          where: 'id = ?',
          whereArgs: [taskId],
          limit: 1,
        );
        if (before.isEmpty) return;
        final row = before.first;
        final from = '${row['status'] ?? 'pending'}';
        final fields = <String, Object?>{'status': target};
        if (startedAt != null && startedAt.trim().isNotEmpty) {
          fields['started_at'] = startedAt.trim();
        } else if (target == 'active' &&
            (row['started_at'] == null ||
                '${row['started_at']}'.trim().isEmpty)) {
          fields['started_at'] = now;
        }
        if (actualMinutes != null) fields['actual_minutes'] = actualMinutes;
        if (note != null) fields['note'] = note;
        if (resultJson != null) fields['result_json'] = resultJson;
        if (target == 'done') {
          if (row['done_at'] == null ||
              '${row['done_at']}'.trim().isEmpty) {
            fields['done_at'] = now;
          }
        } else if (target == 'pending') {
          fields['done_at'] = null;
          fields['result_json'] = null;
        }
        await txn.update(
          'tutor_tasks',
          fields,
          where: 'id = ?',
          whereArgs: [taskId],
        );
        await txn.insert('task_events', {
          'task_id': taskId,
          'event': eventForTutorTaskStatus(target),
          'at': now,
          'payload_json': jsonEncode(<String, Object?>{
            'from': from,
            'to': target,
            'started_at': ?startedAt,
            'actual_minutes': ?actualMinutes,
            'note': ?note,
          }),
          'created_at': now,
        });
      });
    } catch (e) {
      debugPrint('ReadFlow updateTutorTaskStatus failed: $e');
    }
  }

  /// 任务列表(跨天/按状态/按日期筛选),`plan_date DESC, created_at ASC`。
  ///
  /// [planDate] 传 `'2026-11-02'` 或 ISO 时间都行(内部只取日期,半开区间
  /// `[当天 00:00, 次日 00:00)`;解析失败则忽略该筛选,不返回空列表骗用户)。
  /// [status] 非法则忽略筛选。返回行带解析后的 `payload`/`result`。
  static Future<List<Map<String, Object?>>> listTutorTasks({
    String? planDate,
    String? status,
    int limit = 50,
  }) async {
    try {
      final db = await database;
      final where = <String>[];
      final args = <Object?>[];
      final statusText = status?.trim() ?? '';
      if (statusText.isNotEmpty && isValidTutorTaskStatus(statusText)) {
        where.add('status = ?');
        args.add(statusText);
      }
      final dateText = planDate?.trim() ?? '';
      if (dateText.isNotEmpty) {
        final day = DateTime.tryParse(dateText);
        if (day != null) {
          final start = DateTime(day.year, day.month, day.day);
          final end = DateTime(day.year, day.month, day.day + 1);
          where.add('plan_date >= ? AND plan_date < ?');
          args
            ..add(start.toIso8601String())
            ..add(end.toIso8601String());
        }
      }
      final rows = await db.query(
        'tutor_tasks',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'plan_date DESC, created_at ASC, id ASC',
        limit: limit <= 0 ? 50 : limit,
      );
      return rows.map(_decorateTutorTask).toList();
    } catch (e) {
      debugPrint('ReadFlow listTutorTasks failed: $e');
      return [];
    }
  }

  /// 完成率/按时统计(复盘页与周报的"任务"块)。
  ///
  /// ## 口径(按 docs/research/output-and-tutor.md §2.4.4 锁死)
  /// - `completionRate = done / (done + skipped + expired)`;
  /// - **expired 进分母**:过期=没按时完成,是"计划不合身"的证据,不能从
  ///   分母里抹掉(否则跳过/过期越多完成率越高,复盘就失真);
  /// - `pending`/`active` **不进分母**(还没结算,不能算失败);
  /// - `planned` = 区间内任务总数(含 pending/active),与完成率分母**不是一回事**,
  ///   两个数都要给 UI(pending 多说明"今天还没开始",不是完成率差);
  /// - `avgActualMinutes` 只统计 `status='done'` 且 actual_minutes>0 的任务,
  ///   没有样本返回 null(不伪造 0 分钟)。
  ///
  /// [since] 传了就按"那天的 00:00 起"过滤(含当天);null = 不限时间。
  static Future<Map<String, Object?>> taskCompletionStats({
    DateTime? since,
  }) async {
    try {
      final db = await database;
      final sinceStart = since == null
          ? null
          : DateTime(since.year, since.month, since.day);
      final rows = await db.rawQuery(
        'SELECT status, COUNT(*) AS c FROM tutor_tasks '
        '${sinceStart == null ? '' : 'WHERE plan_date >= ? '}'
        'GROUP BY status',
        sinceStart == null ? null : [sinceStart.toIso8601String()],
      );
      final counts = <String, int>{};
      for (final row in rows) {
        final key = '${row['status'] ?? 'pending'}';
        counts[key] =
            (counts[key] ?? 0) + ((row['c'] as num?)?.toInt() ?? 0);
      }
      final planned = counts.values.fold<int>(0, (sum, c) => sum + c);
      final done = counts['done'] ?? 0;
      final skipped = counts['skipped'] ?? 0;
      final expired = counts['expired'] ?? 0;
      final denominator = done + skipped + expired;
      final completionRate = denominator == 0 ? 0.0 : done / denominator;
      final avgRows = await db.rawQuery(
        "SELECT AVG(actual_minutes) AS m FROM tutor_tasks "
        "WHERE status = 'done' AND actual_minutes IS NOT NULL "
        "AND actual_minutes > 0 "
        "${sinceStart == null ? '' : 'AND plan_date >= ? '}",
        sinceStart == null ? null : [sinceStart.toIso8601String()],
      );
      final avg = avgRows.isEmpty
          ? null
          : _toDoubleOrNull(avgRows.first['m']);
      return <String, Object?>{
        'planned': planned,
        'done': done,
        'skipped': skipped,
        'expired': expired,
        'completionRate': completionRate,
        'avgActualMinutes': avg,
      };
    } catch (e) {
      debugPrint('ReadFlow taskCompletionStats failed: $e');
      return <String, Object?>{
        'planned': 0,
        'done': 0,
        'skipped': 0,
        'expired': 0,
        'completionRate': 0.0,
        'avgActualMinutes': null,
      };
    }
  }

  // ── 内部小工具 ────────────────────────────────────────────────────

  static Map<String, Object?> _decorateAbilitySnapshot(
    Map<String, Object?> row,
  ) {
    return {
      ...row,
      'evidence': _tryDecodeJson(row['evidence_json']?.toString()),
    };
  }

  static double? _toDoubleOrNull(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static int? _toIntOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// JSON 字段归一:null → null;String 视为**已编码的 JSON 串**原样保留;
  /// 其余(Map/List)jsonEncode。编码失败(循环引用等)→ null,不抛。
  static String? _jsonFieldOrNull(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (e) {
      debugPrint('ReadFlow 任务/能力 JSON 编码失败(置空): $e');
      return null;
    }
  }

  /// 追加一条导师对话。[at] 用于补齐历史(导入/测试),不传就是"现在"。
  ///
  /// [conversationId] 为 null 时归入"默认对话"(老数据与未指定时的兜底)。
  static Future<int> insertTutorMessage({
    required String role,
    required String content,
    String? toolCalls,
    int? conversationId,
    DateTime? at,
  }) async {
    try {
      final db = await database;
      final now = (at ?? DateTime.now()).toIso8601String();
      final id = await db.insert('tutor_messages', {
        'role': role,
        'content': content,
        'tool_calls': toolCalls,
        'conversation_id': conversationId,
        'created_at': now,
      });
      // 会话列表要按"最近聊过"排序,所以每条消息都推一下 updated_at
      if (conversationId != null) {
        await db.update(
          'tutor_conversations',
          {'updated_at': now},
          where: 'id = ?',
          whereArgs: [conversationId],
        );
      }
      return id;
    } catch (e) {
      debugPrint('ReadFlow insertTutorMessage failed: $e');
      return -1;
    }
  }

  /// 最近 [limit] 条导师对话,按**时间正序**返回(老的在前,新的在后)。
  /// 为什么要"查 DESC 再反转":limit 必须作用在最新的 N 条上,直接 ASC + LIMIT
  /// 会取到最早的 N 条(聊得越久上下文越跑偏);反转是为了喂模型时顺序正确。
  ///
  /// [conversationId] 传具体 id 只取该会话;传 null 取**全部**(兼容老调用方)。
  static Future<List<Map<String, Object?>>> getTutorMessages({
    int limit = 50,
    int? conversationId,
  }) async {
    try {
      final db = await database;
      final rows = await db.query(
        'tutor_messages',
        where: conversationId == null ? null : 'conversation_id = ?',
        whereArgs: conversationId == null ? null : [conversationId],
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
  ///
  /// [conversationId] 非空只清那一个会话(用户第 5(2) 条"清除聊天")。
  static Future<void> clearTutorMessages({int? conversationId}) async {
    try {
      final db = await database;
      await db.delete(
        'tutor_messages',
        where: conversationId == null ? null : 'conversation_id = ?',
        whereArgs: conversationId == null ? null : [conversationId],
      );
    } catch (e) {
      debugPrint('ReadFlow clearTutorMessages failed: $e');
    }
  }

  // ── 助理会话(v2.8,用户第 5(2) 条:新建 / 多开 / 改名 / 删除)──

  /// 新建一个会话,返回 id。标题默认「新对话」,首条提问后由界面改名。
  static Future<int> createTutorConversation({
    String title = '新对话',
    String? kind,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      return await db.insert('tutor_conversations', {
        'title': title,
        'kind': kind,
        'created_at': now,
        'updated_at': now,
      });
    } catch (e) {
      debugPrint('ReadFlow createTutorConversation failed: $e');
      return -1;
    }
  }

  /// 会话列表(最近聊过的在前)
  static Future<List<Map<String, Object?>>> getTutorConversations({
    int limit = 50,
  }) async {
    try {
      final db = await database;
      return await db.query(
        'tutor_conversations',
        orderBy: 'updated_at DESC, id DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('ReadFlow getTutorConversations failed: $e');
      return [];
    }
  }

  static Future<int> renameTutorConversation(int id, String title) async {
    final t = title.trim();
    if (t.isEmpty) return 0;
    try {
      final db = await database;
      return await db.update(
        'tutor_conversations',
        {'title': t, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('ReadFlow renameTutorConversation failed: $e');
      return 0;
    }
  }

  /// 删除会话**连同它的消息**(不删 tutor_memory)
  static Future<void> deleteTutorConversation(int id) async {
    try {
      final db = await database;
      await db.transaction((txn) async {
        await txn.delete('tutor_messages',
            where: 'conversation_id = ?', whereArgs: [id]);
        await txn.delete('tutor_conversations',
            where: 'id = ?', whereArgs: [id]);
      });
    } catch (e) {
      debugPrint('ReadFlow deleteTutorConversation failed: $e');
    }
  }

  /// 为会话自动取个标题(用首条提问的前 16 个字)
  static Future<void> autoTitleTutorConversation(
    int id,
    String firstQuestion,
  ) async {
    final q = firstQuestion.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (q.isEmpty) return;
    final title = q.length <= 16 ? q : '${q.substring(0, 16)}…';
    await renameTutorConversation(id, title);
  }

  /// 记一条导师长期记忆(kind: preference/commitment/obstacle/insight)。
  ///
  /// ─────────────── 练习计划与记录(v2.9,用户第 2 条)───────────────
  ///
  /// 用户原话:"词汇练习、翻译练习这些,都要有系统规划、进度追踪,要让用户看得出
  /// 有完整的练习方向 —— 而不是现在这种随便给几个词、给几个句子翻译。"
  ///
  /// 三种模式(用户答"都需要,给用户提供选择"):plan(4 周计划)/daily(今日包)/auto(自适应)
  static Future<int> createDrillPlan({
    required String mode,
    required List<String> goals,
    String levelNote = '',
    int weeks = 4,
    int perDay = 10,
    DateTime? startDate,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      // 同模式只留一个进行中的计划:旧的直接关掉(避免"两个计划同时算进度")
      await db.update(
        'drill_plans',
        {'status': 'archived', 'updated_at': now},
        where: 'mode = ? AND status = ?',
        whereArgs: [mode, 'active'],
      );
      return await db.insert('drill_plans', {
        'mode': mode,
        'goals': jsonEncode(goals),
        'level_note': levelNote,
        'weeks': weeks,
        'per_day': perDay,
        'start_date': (startDate ?? DateTime.now()).toIso8601String(),
        'status': 'active',
        'created_at': now,
        'updated_at': now,
      });
    } catch (e) {
      debugPrint('ReadFlow createDrillPlan failed: $e');
      return -1;
    }
  }

  /// 当前进行中的计划(没有就返回 null)
  static Future<Map<String, Object?>?> activeDrillPlan(String mode) async {
    try {
      final db = await database;
      final rows = await db.query(
        'drill_plans',
        where: 'mode = ? AND status = ?',
        whereArgs: [mode, 'active'],
        orderBy: 'id DESC',
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    } catch (e) {
      debugPrint('ReadFlow activeDrillPlan failed: $e');
      return null;
    }
  }

  static Future<void> closeDrillPlan(int id, {String status = 'done'}) async {
    try {
      final db = await database;
      await db.update(
        'drill_plans',
        {'status': status, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('ReadFlow closeDrillPlan failed: $e');
    }
  }

  /// 记一次练习(进度追踪的原子记录)
  static Future<int> logDrill({
    required String mode,
    required int total,
    required int correct,
    int seconds = 0,
    int? planId,
    List<String> goals = const [],
    List<String> wrong = const [],
  }) async {
    try {
      final db = await database;
      final id = await db.insert('drill_logs', {
        'mode': mode,
        'plan_id': planId,
        'goals': jsonEncode(goals),
        'total': total,
        'correct': correct,
        'seconds': seconds,
        'wrong_words': jsonEncode(wrong.take(30).toList()),
        'created_at': DateTime.now().toIso8601String(),
      });
      if (planId != null) {
        await db.update(
          'drill_plans',
          {'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [planId],
        );
      }
      return id;
    } catch (e) {
      debugPrint('ReadFlow logDrill failed: $e');
      return -1;
    }
  }

  /// 练习记录(按时间倒序)
  static Future<List<Map<String, Object?>>> getDrillLogs({
    String? mode,
    int limit = 100,
  }) async {
    try {
      final db = await database;
      return await db.query(
        'drill_logs',
        where: mode == null ? null : 'mode = ?',
        whereArgs: mode == null ? null : [mode],
        orderBy: 'created_at DESC, id DESC',
        limit: limit,
      );
    } catch (e) {
      debugPrint('ReadFlow getDrillLogs failed: $e');
      return [];
    }
  }

  /// 某模式的累计进度(界面上的"进度追踪"直接读它)
  ///
  /// 返回:times 练习次数 / total 总题数 / correct 总对题 / accuracy 正确率 /
  /// todayTotal 今日题数 / todayDone 今日是否练过 / streak 连续练习天数
  static Future<Map<String, Object?>> drillProgress({String? mode}) async {
    try {
      final logs = await getDrillLogs(mode: mode, limit: 2000);
      var total = 0, correct = 0, seconds = 0;
      final days = <String>{};
      final today = DateTime.now();
      var todayTotal = 0;
      for (final r in logs) {
        total += (r['total'] as int?) ?? 0;
        correct += (r['correct'] as int?) ?? 0;
        seconds += (r['seconds'] as int?) ?? 0;
        final t = DateTime.tryParse('${r['created_at'] ?? ''}');
        if (t == null) continue;
        days.add('${t.year}-${t.month}-${t.day}');
        if (t.year == today.year && t.month == today.month && t.day == today.day) {
          todayTotal += (r['total'] as int?) ?? 0;
        }
      }
      // 连续天数:从今天(或昨天)往前数
      var streak = 0;
      var cursor = DateTime(today.year, today.month, today.day);
      if (!days.contains('${cursor.year}-${cursor.month}-${cursor.day}')) {
        cursor = cursor.subtract(const Duration(days: 1));
      }
      while (days.contains('${cursor.year}-${cursor.month}-${cursor.day}')) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      }
      return {
        'times': logs.length,
        'total': total,
        'correct': correct,
        'accuracy': total == 0 ? 0.0 : correct / total,
        'seconds': seconds,
        'todayTotal': todayTotal,
        'streak': streak,
      };
    } catch (e) {
      debugPrint('ReadFlow drillProgress failed: $e');
      return {
        'times': 0,
        'total': 0,
        'correct': 0,
        'accuracy': 0.0,
        'seconds': 0,
        'todayTotal': 0,
        'streak': 0,
      };
    }
  }

  // ── 材料里的 AI 内容块(v2.9,用户第 3(5) 条)──

  static Future<int> upsertMaterialBlock({
    required int materialId,
    required String kind,
    int chunkIndex = -1,
    String title = '',
    required String payloadJson,
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      final existing = await db.query(
        'material_blocks',
        where: 'material_id = ? AND chunk_index = ? AND kind = ?',
        whereArgs: [materialId, chunkIndex, kind],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        await db.update(
          'material_blocks',
          {
            'title': title,
            'payload': payloadJson,
            'created_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        return id;
      }
      return await db.insert('material_blocks', {
        'material_id': materialId,
        'chunk_index': chunkIndex,
        'kind': kind,
        'title': title,
        'payload': payloadJson,
        'created_at': now,
      });
    } catch (e) {
      debugPrint('ReadFlow upsertMaterialBlock failed: $e');
      return -1;
    }
  }

  static Future<List<Map<String, Object?>>> getMaterialBlocks(
    int materialId, {
    int? chunkIndex,
  }) async {
    try {
      final db = await database;
      return await db.query(
        'material_blocks',
        where: chunkIndex == null
            ? 'material_id = ?'
            : 'material_id = ? AND chunk_index = ?',
        whereArgs:
            chunkIndex == null ? [materialId] : [materialId, chunkIndex],
        orderBy: 'chunk_index ASC, id ASC',
      );
    } catch (e) {
      debugPrint('ReadFlow getMaterialBlocks failed: $e');
      return [];
    }
  }

  static Future<void> deleteMaterialBlocks(
    int materialId, {
    String? kind,
    int? chunkIndex,
  }) async {
    try {
      final db = await database;
      var where = 'material_id = ?';
      final args = <Object?>[materialId];
      if (chunkIndex != null) {
        where += ' AND chunk_index = ?';
        args.add(chunkIndex);
      }
      if (kind != null) {
        where += ' AND kind = ?';
        args.add(kind);
      }
      await db.delete('material_blocks', where: where, whereArgs: args);
    } catch (e) {
      debugPrint('ReadFlow deleteMaterialBlocks failed: $e');
    }
  }

  // ── 书架(v2.10,用户 10/4 第 4/5 条)──

  /// 放进书架(已在架上则只更新备注,不重复加)
  static Future<int> addToBookshelf(
    int materialId, {
    String? note,
    String fromWhere = 'reader',
  }) async {
    try {
      final db = await database;
      final now = DateTime.now().toIso8601String();
      final existing = await db.query(
        'bookshelf',
        where: 'material_id = ?',
        whereArgs: [materialId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        await db.update(
          'bookshelf',
          {'note': note ?? existing.first['note'], 'added_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        return id;
      }
      // slot = 当前最大 + 1:摆上去的顺序就是用户放书的顺序(书架要"一本本排")
      final maxRow = await db.rawQuery('SELECT MAX(slot) AS m FROM bookshelf');
      final nextSlot = ((maxRow.first['m'] as int?) ?? 0) + 1;
      return await db.insert('bookshelf', {
        'material_id': materialId,
        'slot': nextSlot,
        'note': note,
        'added_at': now,
        'from_where': fromWhere,
      });
    } catch (e) {
      debugPrint('ReadFlow addToBookshelf failed: $e');
      return -1;
    }
  }

  static Future<void> removeFromBookshelf(int materialId) async {
    try {
      final db = await database;
      await db.delete('bookshelf', where: 'material_id = ?', whereArgs: [materialId]);
    } catch (e) {
      debugPrint('ReadFlow removeFromBookshelf failed: $e');
    }
  }

  static Future<bool> isOnBookshelf(int materialId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'bookshelf',
        where: 'material_id = ?',
        whereArgs: [materialId],
        limit: 1,
      );
      return rows.isNotEmpty;
    } catch (e) {
      debugPrint('ReadFlow isOnBookshelf failed: $e');
      return false;
    }
  }

  /// 书架上的书(**按摆放顺序**),带标题/进度/难度/封面所需字段 —— 界面一次查完
  static Future<List<Map<String, Object?>>> bookshelfItems() async {
    try {
      final db = await database;
      return await db.rawQuery('''
        SELECT b.id AS shelf_id,
               b.slot AS slot,
               b.note AS note,
               b.added_at AS added_at,
               b.from_where AS from_where,
               m.id AS material_id,
               COALESCE(NULLIF(m.title_cn, ''), m.title) AS title,
               m.title AS title_en,
               m.title_cn AS title_cn,
               m.kind AS kind,
               m.source AS source,
               m.origin AS origin,
               m.cefr AS cefr,
               m.word_count AS word_count,
               m.est_minutes AS est_minutes,
               m.coverage AS coverage,
               m.url AS url,
               m.cover_url AS cover_url,
               p.percent AS percent,
               p.position AS position,
               p.minutes AS minutes,
               p.picked_words AS picked_words,
               p.finished_at AS finished_at,
               COALESCE(p.updated_at, b.added_at) AS updated_at
        FROM bookshelf b
        JOIN materials m ON m.id = b.material_id
        LEFT JOIN material_progress p ON p.material_id = m.id
        ORDER BY b.slot ASC, b.id ASC
      ''');
    } catch (e) {
      debugPrint('ReadFlow bookshelfItems failed: $e');
      return [];
    }
  }

  static Future<int> bookshelfCount() async {
    try {
      final db = await database;
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM bookshelf');
      return (rows.first['c'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// 拖拽/手动调整摆放顺序:把 [materialId] 挪到 [slot] 位置(其余顺延由界面重排后整体提交)
  static Future<void> setBookshelfOrder(List<int> materialIds) async {
    try {
      final db = await database;
      await db.transaction((txn) async {
        for (var i = 0; i < materialIds.length; i++) {
          await txn.update(
            'bookshelf',
            {'slot': i + 1},
            where: 'material_id = ?',
            whereArgs: [materialIds[i]],
          );
        }
      });
    } catch (e) {
      debugPrint('ReadFlow setBookshelfOrder failed: $e');
    }
  }

  // ── 材料中文标题(v2.10,用户 10/4 第 2(2) 条)──

  /// 写一份中文标题缓存。
  ///
  /// 用户原话:"推荐的所有材料,**我都说了标题要有中文翻译呀** —— 我都说了几次了,
  /// 一次都没实现过"。以前只在"当下那一次列表加载"里翻,翻完就丢:
  /// 材料库、书架、阅读器、历史记录里到处都是没翻译的英文标题。
  /// 现在译名**落库**(materials.title_cn),任何界面读同一份,且只翻一次。
  static Future<void> setMaterialTitleCn(int materialId, String titleCn) async {
    final t = titleCn.trim();
    if (t.isEmpty) return;
    try {
      final db = await database;
      await db.update(
        'materials',
        {'title_cn': t},
        where: 'id = ?',
        whereArgs: [materialId],
      );
    } catch (e) {
      debugPrint('ReadFlow setMaterialTitleCn failed: $e');
    }
  }

  /// 还没中文名的材料(界面在后台补齐译名用;limit 控制一次翻几条,别一次翻一百篇)
  static Future<List<Map<String, Object?>>> materialsMissingTitleCn({
    int limit = 8,
  }) async {
    try {
      final db = await database;
      return await db.rawQuery('''
        SELECT id, title FROM materials
        WHERE (title_cn IS NULL OR title_cn = '')
          AND title IS NOT NULL AND title != ''
        ORDER BY COALESCE(cached_at, created_at) DESC
        LIMIT ?
      ''', [limit]);
    } catch (e) {
      debugPrint('ReadFlow materialsMissingTitleCn failed: $e');
      return [];
    }
  }

  // ── 材料来源与分组(v2.9,用户第 5 条:材料导入要能分类)──
  /// 设置材料的分组名(用户自定义,如「新视野教材」);传空 = 取消分组
  static Future<void> setMaterialGroup(int materialId, String? group) async {
    try {
      final db = await database;
      final g = (group ?? '').trim();
      await db.update(
        'materials',
        {'group_name': g.isEmpty ? null : g},
        where: 'id = ?',
        whereArgs: [materialId],
      );
    } catch (e) {
      debugPrint('ReadFlow setMaterialGroup failed: $e');
    }
  }

  /// 已有的分组名(去重、按材料数倒序)
  static Future<List<String>> materialGroups() async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        'SELECT group_name, COUNT(*) AS c FROM materials '
        "WHERE group_name IS NOT NULL AND group_name != '' "
        'GROUP BY group_name ORDER BY c DESC, group_name ASC',
      );
      return [for (final r in rows) '${r['group_name']}'];
    } catch (e) {
      debugPrint('ReadFlow materialGroups failed: $e');
      return [];
    }
  }

  /// 按来源统计材料数(import/local/ai/feed)——「材料导入」与「词汇本」分家的依据
  static Future<Map<String, int>> materialCountByOrigin() async {
    try {
      final db = await database;
      final rows = await db.rawQuery(
        'SELECT COALESCE(origin, source) AS o, COUNT(*) AS c FROM materials '
        'GROUP BY o',
      );
      return {
        for (final r in rows) '${r['o']}': (r['c'] as int?) ?? 0,
      };
    } catch (e) {
      debugPrint('ReadFlow materialCountByOrigin failed: $e');
      return {};
    }
  }  /// 与 tutor_messages 分表:对话可以清,偏好/承诺/障碍/结论必须留着。
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
