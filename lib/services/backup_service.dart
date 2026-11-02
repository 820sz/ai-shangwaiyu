import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, DatabaseExecutor;

import '../config/constants.dart';
import '../models/vocabulary.dart';
import 'database.dart';
import 'export_service.dart';
import 'fsrs.dart';
import 'learner_model_store.dart';
import 'material_library.dart';
import 'material_source.dart';
import 'review_queue.dart';

/// 组装好的阅读包(标题 + Markdown 正文)
class _MaterialPack {
  final String title;
  final String content;

  const _MaterialPack({required this.title, required this.content});
}

/// 导出文件(路径 + 内容,便于 UI 同时给"打开位置"与"复制")
class ExportedFile {
  final String path;
  final String content;
  final String label;

  /// 导出时想告诉用户的额外说明(例如"作答记录已截断到最近 5000 条")。
  /// 单独一个字段而不是拼进 label:label 是文件名(给分享/复制用),
  /// 说明是给人读的,混在一起会让 UI 两侧都变形。
  final List<String> notes;

  const ExportedFile({
    required this.path,
    required this.content,
    required this.label,
    this.notes = const [],
  });

  int get bytes => content.length;
  String get fileName => path.split(Platform.pathSeparator).last;
}

/// 一次完整备份的组装结果(**还没落盘**)。
///
/// 为什么把"组装 JSON"与"写文件"拆开:
/// 1. 测试可以在不依赖 path_provider 的情况下跑真正的导出全链路;
/// 2. 以后"复制备份到剪贴板/分享"两个入口可直接复用同一份 JSON,
///    不必各自再写一遍读库逻辑(两套实现必然漂移)。
class BackupExport {
  final String json;
  final int formatVersion;

  /// 表名 → 导出条数(含 v1 的 vocab/review_cards)
  final Map<String, int> counts;

  /// 表名 → {limit, total, exported}(只含被截断的表)
  final Map<String, Object?> truncation;

  /// 给用户的截断说明(没有截断时为空)
  final List<String> notes;

  const BackupExport({
    required this.json,
    required this.formatVersion,
    this.counts = const {},
    this.truncation = const {},
    this.notes = const [],
  });

  bool get truncated => truncation.isNotEmpty;
}

/// 恢复报告里**单张表**的统计。
///
/// 为什么恢复要逐表报告:用户在"换机"时最怕的是"看起来导入成功,其实只进来
/// 一半"。把每张表"备份里有多少 / 实际写进多少 / 跳过多少(为什么)"摊开,
/// 比一句"导入成功"可信得多。
class RestoreTableStat {
  /// 备份里该表的条数
  final int exported;

  /// 实际写进本机的条数(插入或合并更新)
  final int restored;

  /// 跳过的条数(已存在/缺关联/字段不可用)
  final int skipped;

  /// 跳过的主要原因(给人看的一句话;没跳过则为 null)
  final String? skipReason;

  const RestoreTableStat({
    this.exported = 0,
    this.restored = 0,
    this.skipped = 0,
    this.skipReason,
  });

  static const RestoreTableStat empty = RestoreTableStat();

  bool get isEmpty => exported == 0 && restored == 0 && skipped == 0;
}

/// 导入结果(给用户看的报告)
class RestoreReport {
  final int added;
  final int skipped;
  final int cardsRestored;
  final bool replacedModel;

  /// v2:备份格式版本(1 = 老备份)
  final int backupVersion;

  /// v2:逐表恢复统计(表名 → 统计)。老备份为空表,summary 行为与以前一致。
  final Map<String, RestoreTableStat> tables;
  final List<String> warnings;

  const RestoreReport({
    this.added = 0,
    this.skipped = 0,
    this.cardsRestored = 0,
    this.replacedModel = false,
    this.backupVersion = 1,
    this.tables = const {},
    this.warnings = const [],
  });

  String get summary {
    final parts = <String>['导入 $added 个新词'];
    if (skipped > 0) parts.add('跳过 $skipped 个已存在');
    if (cardsRestored > 0) parts.add('恢复 $cardsRestored 条复习状态');
    if (replacedModel) parts.add('恢复学习画像');
    // v2 表:只把"真的有数据进来"的表列出来 —— 全 0 的表列出来只会让报告变长
    final withData = [
      for (final entry in tables.entries)
        if (entry.value.restored > 0) entry,
    ];
    if (withData.isNotEmpty) {
      final detail = withData
          .map((e) => '${_tableLabel(e.key)} ${e.value.restored}')
          .join(' · ');
      parts.add('恢复 $detail');
    }
    final tableSkipped = tables.values.fold<int>(0, (sum, s) => sum + s.skipped);
    if (tableSkipped > 0) parts.add('跳过 $tableSkipped 条已存在/无关联数据');
    return parts.join(' · ');
  }

  /// 表名 → 人话标签(报告与警告共用,避免 UI 里出现 `output_attempts` 这种裸表名)
  static String _tableLabel(String table) => switch (table) {
        'material_translations' => '阅读译文',
        'exercise_sets' => '题组',
        'exercise_items' => '题目',
        'rubrics' => '评分标准',
        'output_attempts' => '输出作答',
        'ability_snapshots' => '能力快照',
        'task_events' => '任务事件',
        'tutor_tasks' => '助理任务',
        'error_tags' => '错误标签',
        'word_review' => '复习状态',
        _ => table,
      };

  static String tableLabel(String table) => _tableLabel(table);
}

/// 阅读包导出结果(单篇时 dirPath 为 null)
class MaterialPackReport {
  final List<String> files;
  final String? dirPath;
  final int failed;

  const MaterialPackReport({
    this.files = const [],
    this.dirPath,
    this.failed = 0,
  });

  int get count => files.length;

  String get summary {
    final where = dirPath == null ? '导出目录' : dirPath!.split('/').last;
    final base = '已导出 $count 篇到 $where';
    return failed > 0 ? '$base($failed 篇无正文,已跳过)' : base;
  }
}

/// 备份与导出的落地层(v2.2)。
///
/// 存放位置的选择:App 的**外部私有目录**(Android:`/Android/data/<包名>/files`)。
/// 理由:无需任何存储权限即可写(Android 10+ 的作用域存储),而且文件管理器能看到、
/// 用户能把文件拷走 —— 这正是"换机迁移"要的。内部 docs 目录用户看不见,不合适。
class BackupService {
  BackupService._();

  /// 导出文件名前缀(带时间戳,避免互相覆盖)
  static String stamp([DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
  }

  /// 写文件;失败时抛出可读中文错误(UI 直接显示)
  static Future<ExportedFile> write(String fileName, String content) async {
    Directory dir;
    try {
      dir = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = await getApplicationDocumentsDirectory();
    }
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final file = File('${exportDir.path}/$fileName');
    await file.writeAsString(content, flush: true);
    return ExportedFile(path: file.path, content: content, label: fileName);
  }

  /// 生词本 → CSV(Excel 可直接打开)
  static Future<ExportedFile> exportVocabCsv() async {
    final vocab = await DatabaseService.getVocabularies(limit: 100000);
    final cards = await _cardsByVocabId();
    return write(
      'readflow-生词本-${stamp()}.csv',
      ExportService.vocabCsv(vocab, cards: cards),
    );
  }

  /// 生词本 → Anki 导入用 TSV
  static Future<ExportedFile> exportVocabAnkiTsv() async {
    final vocab = await DatabaseService.getVocabularies(limit: 100000);
    return write(
      'readflow-ankii导入-${stamp()}.txt',
      ExportService.vocabAnkiTsv(vocab),
    );
  }

  /// 完整备份 JSON(可回导)。
  ///
  /// v2(2026-11-02):除生词/复习状态/画像/设置外,补上 v3 新增的学习历史
  /// (阅读译文、输出题组与作答、能力快照、任务与事件、错误标签、复习状态原表、
  /// rubrics)。**不含 API Key**(那是用户自己的密钥,不该出现在导出文件里)。
  static Future<ExportedFile> exportBackupJson() async {
    final built = await buildBackupJson();
    final file = await write(
      'readflow-备份-${stamp()}.json',
      built.json,
    );
    return ExportedFile(
      path: file.path,
      content: file.content,
      label: file.label,
      // 截断不是"细节":用户换机后发现自己 3 个月的作答记录只剩最近 5000 条,
      // 必须当场知道,而不是以为全都在
      notes: built.notes,
    );
  }

  /// 组装完整备份 JSON(**不落盘**)。
  ///
  /// 拆出这一层的理由见 [BackupExport];测试用它跑"导出 → 清库 → 恢复"全链路,
  /// 不依赖手机文件系统。
  static Future<BackupExport> buildBackupJson({DateTime? now}) async {
    final vocab = await DatabaseService.getVocabularies(limit: 100000);
    final cards = await _cardsByVocabId();
    final model = LearnerModelStore.load();
    // 只备份"跨设备有意义"的设置:API Key 绝不进备份文件
    final box = Hive.box(AppConstants.hiveBoxSettings);
    final accent = box.get(AppConstants.keyTtsAccent);
    final collected = await _collectV2Tables();
    final json = ExportService.backupJson(
      vocab: vocab,
      cards: cards,
      model: model,
      settings: {
        if (accent is String) 'tts_accent': accent,
      },
      tables: collected.tables,
      truncation: collected.truncation,
      now: now,
    );
    final counts = <String, int>{
      'vocab': vocab.length,
      'review_cards': cards.length,
      for (final entry in collected.tables.entries)
        entry.key: entry.value.length,
    };
    return BackupExport(
      json: json,
      formatVersion: ExportService.currentBackupVersion,
      counts: counts,
      truncation: collected.truncation,
      notes: collected.notes,
    );
  }

  /// 单表导出的安全上限(体积控制)。
  ///
  /// 为什么只截这两张表:output_attempts / task_events 是"只追加"的流水,
  /// 一年能到几万条,而备份是整份 JSON 进剪贴板/微信的(太大直接发不出去);
  /// 其余表(译文/题组/能力快照/任务)是按天/按材料聚合的,量级可控,全导。
  static const int outputAttemptsLimit = 5000;
  static const int taskEventsLimit = 5000;

  /// 收集 v3 新表的行数据 + 截断说明。
  ///
  /// 失败策略:**宁可整份导出失败,也不静默少导一张表** —— 备份是用户唯一的
  /// 数据出口,悄悄漏掉一张表 = 用户以为数据安全了,其实已经丢了。所以这里
  /// 查库失败会带表名抛中文异常(与 [_buildMaterialPack] 的"宁可报错不出空包"同源)。
  static Future<_CollectedTables> _collectV2Tables() async {
    final db = await DatabaseService.database;
    Future<List<Map<String, Object?>>> query(String label, String sql) async {
      try {
        return await db.rawQuery(sql);
      } catch (e) {
        throw StateError('读取$label失败:$e');
      }
    }

    Future<int> count(String label, String table) async {
      try {
        final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
        return (rows.first['c'] as num?)?.toInt() ?? 0;
      } catch (e) {
        throw StateError('统计$label条数失败:$e');
      }
    }

    final tables = <String, List<Map<String, Object?>>>{};
    final truncation = <String, Object?>{};
    final notes = <String>[];

    // ① 阅读译文:按 (material_id, unit_index) 排,恢复时才能快速判重
    tables['material_translations'] = await query(
      '阅读译文',
      'SELECT * FROM material_translations '
      'ORDER BY material_id ASC, unit_index ASC',
    );

    // ② 题组 + 题目:两张表分别导,id 保留在 JSON 里供恢复时重建父子关系
    tables['exercise_sets'] = await query(
      '输出题组',
      'SELECT * FROM exercise_sets ORDER BY id ASC',
    );
    tables['exercise_items'] = await query(
      '输出题目',
      'SELECT * FROM exercise_items ORDER BY set_id ASC, idx ASC, id ASC',
    );

    // ③ rubrics:全导(含内置 seed 与用户自定义)。恢复侧只插缺失、不动已有行 ——
    //    内置 seed 是事实源,备份里旧的 seed 不应覆盖本地更新过的新 seed。
    tables['rubrics'] = await query(
      '评分标准',
      'SELECT * FROM rubrics ORDER BY created_at ASC, id ASC',
    );

    // ④ 输出作答:只保留最近 5000 条(截断口径写在 truncation/notes 里)
    final attemptsTotal = await count('输出作答', 'output_attempts');
    final attempts = await query(
      '输出作答',
      'SELECT * FROM output_attempts '
      'ORDER BY created_at DESC, id DESC LIMIT $outputAttemptsLimit',
    );
    tables['output_attempts'] = attempts;
    if (attemptsTotal > attempts.length) {
      truncation['output_attempts'] = <String, Object?>{
        'limit': outputAttemptsLimit,
        'total': attemptsTotal,
        'exported': attempts.length,
      };
      notes.add(
        '输出作答共 $attemptsTotal 条,备份只保留最近 ${attempts.length} 条'
        '(上限 $outputAttemptsLimit 条)',
      );
    }

    // ⑤ 能力快照:全导(它是趋势图的事实源,截断会让趋势断掉)
    tables['ability_snapshots'] = await query(
      '能力快照',
      'SELECT * FROM ability_snapshots ORDER BY snapshot_at ASC, id ASC',
    );

    // ⑥ 任务事件:最近 5000 条(同上,流水表)
    final eventsTotal = await count('任务事件', 'task_events');
    final events = await query(
      '任务事件',
      'SELECT * FROM task_events '
      'ORDER BY at DESC, id DESC LIMIT $taskEventsLimit',
    );
    tables['task_events'] = events;
    if (eventsTotal > events.length) {
      truncation['task_events'] = <String, Object?>{
        'limit': taskEventsLimit,
        'total': eventsTotal,
        'exported': events.length,
      };
      notes.add(
        '任务事件共 $eventsTotal 条,备份只保留最近 ${events.length} 条'
        '(上限 $taskEventsLimit 条)',
      );
    }

    // ⑦ 助理任务:全导(任务本身数量少,且复盘要靠完整历史)
    tables['tutor_tasks'] = await query(
      '助理任务',
      'SELECT * FROM tutor_tasks ORDER BY plan_date ASC, id ASC',
    );

    // ⑧ 错误标签画像:全导(越早的记录越值钱,截断会让"复发次数"失真)
    tables['error_tags'] = await query(
      '错误标签',
      'SELECT * FROM error_tags ORDER BY id ASC',
    );

    // ⑨ word_review 原表:带上小写词面 —— 恢复时词条 id 会重新分配,
    //    只有"词"能跨设备对齐(v1 的 vocab[].review 已覆盖大部分场景,
    //    这张表是原样兜底,例如某条复习行对应的词条已不在 vocab 列表里)。
    tables['word_review'] = await query(
      '复习状态原表',
      '''
      SELECT wr.id AS id,
             wr.vocab_id AS vocab_id,
             wr.stability AS stability,
             wr.difficulty AS difficulty,
             wr.due_at AS due_at,
             wr.last_review_at AS last_review_at,
             wr.reps AS reps,
             wr.lapses AS lapses,
             wr.last_rating AS last_rating,
             wr.created_at AS created_at,
             wr.updated_at AS updated_at,
             LOWER(COALESCE(v.word, '')) AS vocabulary_word
      FROM word_review wr
      LEFT JOIN vocabulary v ON v.id = wr.vocab_id
      ORDER BY wr.id ASC
      ''',
    );

    return _CollectedTables(
      tables: tables,
      truncation: truncation,
      notes: notes,
    );
  }

  // ── 阅读包:把材料导出成可带走的 Markdown ──

  /// 单篇材料 → 一个 Markdown 文件(元信息 + 正文 + 生词表)。
  ///
  /// 失败时抛异常(材料不存在/没有正文),由 UI 显示中文原因 ——
  /// 导出一个空文件比报错更糟:用户以为备份成功了。
  static Future<ExportedFile> exportMaterialPack(int materialId) async {
    final pack = await _buildMaterialPack(materialId);
    if (pack == null) {
      throw StateError('这篇材料没有正文,无法导出');
    }
    return write(
      'readflow-阅读包-${_slug(pack.title)}-${stamp()}.md',
      pack.content,
    );
  }

  /// 全部材料 → 一个文件夹,一篇一个 .md。
  ///
  /// 为什么分文件而不是合成一个大 Markdown:材料可能上千篇,合成一份既打不开
  /// 也没法挑着看;一篇一个文件可以直接丢进笔记软件/网盘按篇管理。
  static Future<MaterialPackReport> exportAllMaterialsPack({
    int limit = 500,
  }) async {
    final rows = await DatabaseService.getMaterials(limit: limit);
    if (rows.isEmpty) {
      throw StateError('材料库还是空的,先抓一篇再导出');
    }
    Directory dir;
    try {
      dir = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = await getApplicationDocumentsDirectory();
    }
    final outDir = Directory('${dir.path}/exports/阅读包-${stamp()}');
    if (!outDir.existsSync()) await outDir.create(recursive: true);

    final files = <String>[];
    var failed = 0;
    for (var i = 0; i < rows.length; i++) {
      final id = rows[i]['id'];
      if (id is! int) {
        failed++;
        continue;
      }
      final pack = await _buildMaterialPack(id);
      if (pack == null) {
        failed++;
        continue;
      }
      // 序号前缀:文件管理器按名字排序时保持材料库的顺序(新的在前由 id 决定)
      final name = '${(i + 1).toString().padLeft(3, '0')}-'
          '${_slug(pack.title)}.md';
      final file = File('${outDir.path}/$name');
      await file.writeAsString(pack.content, flush: true);
      files.add(name);
    }
    if (files.isEmpty) {
      throw StateError('$limit 篇材料里没有一篇带正文,已取消导出');
    }
    return MaterialPackReport(
      files: files,
      dirPath: outDir.path,
      failed: failed,
    );
  }

  /// 组装单篇阅读包(材料不存在或没有正文时返回 null)
  static Future<_MaterialPack?> _buildMaterialPack(int materialId) async {
    final row = await DatabaseService.getMaterialById(materialId);
    if (row == null) return null;
    final chunkRows = await DatabaseService.getMaterialChunks(materialId);
    final paragraphs = <ExportParagraph>[
      for (final c in chunkRows)
        if (('${c['text'] ?? ''}').trim().isNotEmpty)
          ExportParagraph(
            title: (c['title'] as String?)?.trim().isEmpty ?? true
                ? null
                : '${c['title']}'.trim(),
            text: '${c['text']}'.trim(),
          ),
    ];
    if (paragraphs.isEmpty) return null;

    final title = '${row['title'] ?? '未命名材料'}'.trim();
    final source = '${row['source'] ?? ''}'.trim();
    final meta = _sourceMeta(source);
    final analysis =
        row['difficulty'] is MaterialAnalysis ? row['difficulty'] as MaterialAnalysis : null;
    return _MaterialPack(
      title: title,
      content: ExportService.materialPackMarkdown(
        title: title,
        chunks: paragraphs,
        author: '${row['author'] ?? ''}'.trim(),
        source: meta?.label ?? source,
        license: ('${row['license'] ?? ''}'.trim().isEmpty
                ? (meta?.license ?? '')
                : '${row['license']}'.trim()),
        url: '${row['url'] ?? ''}'.trim(),
        cefr: '${row['cefr'] ?? ''}'.trim(),
        coverage: row['coverage'] is num
            ? (row['coverage'] as num).toDouble()
            : analysis?.coverage,
        wordCount: row['word_count'] is num
            ? (row['word_count'] as num).toInt()
            : analysis?.wordCount,
        estMinutes: row['est_minutes'] is num
            ? (row['est_minutes'] as num).toInt()
            : analysis?.estMinutes,
        newWords: analysis?.topNewWords ?? const [],
      ),
    );
  }

  static MaterialSource? _sourceMeta(String id) {
    if (id.isEmpty) return null;
    for (final s in MaterialSourceService.sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 文件名安全化:去掉路径分隔符与 Windows 保留字符,限长 —— 标题来自网络,
  /// 里面出现 `/`、`:`、换行都会让写文件失败或造出奇怪的路径。
  static String _slug(String title) {
    var s = title.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), ' ').trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^\.+'), '');
    if (s.isEmpty) s = '材料';
    final runes = s.runes.toList();
    if (runes.length > 40) s = String.fromCharCodes(runes.take(40));
    return s;
  }

  static Future<Map<int, FsrsCard>> _cardsByVocabId() async {
    final rows = await DatabaseService.getWordReviews();
    return ReviewQueue.cardsFromRows(rows, now: DateTime.now());
  }

  /// 导入备份。
  /// [replace] = true:先清空生词本与复习状态再导入(真正的"换机恢复");
  /// false:按词去重合并(重复词跳过,不覆盖现有释义与掌握度)。
  ///
  /// v2 新增:备份里带 `tables` 时,把 v3 新表**在一个事务里**合并恢复
  /// (见 [_restoreV2Tables]);`replace` 的既有语义只覆盖生词本与复习状态,
  /// v3 表一律"只补不改"(不能因为用户点了覆盖导入就删掉本机已有的能力历史/
  /// 任务审计 —— 那些是不可逆的记账数据,而且备份里可能本来就是空的)。
  static Future<RestoreReport> restore(
    BackupData data, {
    required bool replace,
  }) async {
    final warnings = <String>[];
    if (!data.ok) {
      return RestoreReport(warnings: [data.error ?? '备份内容不可用']);
    }
    // 格式版本比本机新:拒绝。宁可明确报错,也不要用旧代码去猜新格式 ——
    // 猜错的代价是写坏用户手里的唯一一份数据。
    if (data.backupVersion > ExportService.currentBackupVersion) {
      return RestoreReport(
        backupVersion: data.backupVersion,
        warnings: [
          '备份来自更新版本的 App(备份格式 v${data.backupVersion}),'
              '请先升级再导入(本机支持到 v${ExportService.currentBackupVersion})',
        ],
      );
    }
    var added = 0;
    var skipped = 0;
    var cardsRestored = 0;
    // 提到 try 外面:异常路径也要如实报告"画像到底恢复没有"
    var restoredModel = false;
    var tableStats = const <String, RestoreTableStat>{};

    try {
      if (replace) {
        final existing = await DatabaseService.getVocabularies(limit: 100000);
        final ids = [
          for (final v in existing)
            if (v.id != null) v.id!,
        ];
        if (ids.isNotEmpty) await DatabaseService.deleteVocabularies(ids);
        await DatabaseService.clearWordReviews();
      }

      final existingWords = <String>{};
      final current = await DatabaseService.getVocabularies(limit: 100000);
      for (final v in current) {
        existingWords.add(v.word.toLowerCase());
      }

      for (final v in data.vocab) {
        final key = v.word.toLowerCase();
        if (existingWords.contains(key)) {
          skipped++;
          continue;
        }
        // id 不沿用(避免与本地冲突),其余字段照写
        final inserted = await DatabaseService.insertVocabulary(
          Vocabulary(
            word: v.word,
            translation: v.translation,
            sourceBook: v.sourceBook,
            sourcePage: v.sourcePage,
            originalSentence: v.originalSentence,
            photoPath: v.photoPath,
            wordType: v.wordType,
            masteryLevel: v.masteryLevel,
            partOfSpeech: v.partOfSpeech,
            grammarNote: v.grammarNote,
            phonetic: v.phonetic,
            phoneticUk: v.phoneticUk,
            phoneticUs: v.phoneticUs,
            category: v.category,
            materialPath: v.materialPath,
            createdAt: v.createdAt,
          ),
        );
        added++;
        existingWords.add(key);
        final card = data.cardsByWord[key];
        if (card != null && inserted > 0) {
          await DatabaseService.upsertWordReview(
            inserted,
            stability: card.stability,
            difficulty: card.difficulty,
            dueAt: card.due,
            lastReviewAt: card.lastReview ?? DateTime.now(),
            lastRating: card.lastRating?.value,
            // P2 修复:复习次数与遗忘次数也要还原(以前恢复后被重置成 1 / 0)
            reps: card.reps,
            lapses: card.lapses,
          );
          cardsRestored++;
        }
      }

      // 画像:合并语义 = 备份里有的字段覆盖本地(用户明确在恢复)
      final model = data.model;
      if (model != null) {
        await LearnerModelStore.save(
          LearnerModelStore.load().copyWith(
            vocabEstimate: model.vocabEstimate,
            vocabLow: model.vocabLow,
            vocabHigh: model.vocabHigh,
            cefr: model.cefr,
            lastPlacementAt: model.lastPlacementAt,
            falseAlarmRate: model.falseAlarmRate,
            goal: model.goal,
            dailyMinutes: model.dailyMinutes,
            maxNewWords: model.maxNewWords,
            interests: model.interests,
            blockedTopics: model.blockedTopics,
            blockedKeywords: model.blockedKeywords,
          ),
        );
        restoredModel = true;
      }

      // 设置白名单(音色)
      final accent = data.settings['tts_accent'];
      if (accent != null && AppConstants.ttsAccentOptions.containsKey(accent)) {
        await Hive.box(AppConstants.hiveBoxSettings)
            .put(AppConstants.keyTtsAccent, accent);
      }

      // v2:v3 新表的恢复(单事务)。放在生词/画像之后:它依赖 vocabulary
      // 已经就位(word_review 按词面对齐),且失败时不能把上面已恢复的
      // 生词回滚掉 —— 生词恢复本身是按词去重的幂等操作,重跑安全。
      if (data.tables.isNotEmpty) {
        try {
          tableStats = await _restoreV2Tables(data);
        } catch (e) {
          // 整块回滚(事务),给出可读原因;生词/画像/设置继续保持已恢复状态。
          warnings.add(
            '阅读译文/输出/能力/任务等新表数据恢复失败,已整体回滚'
            '(生词本、复习状态与学习画像不受影响):$e',
          );
          debugPrint('ReadFlow v2 表恢复失败(已回滚): $e');
        }
      }
      // 截断说明:导出时被截掉的历史要明说,否则用户以为换机后一条没少
      warnings.addAll(_truncationWarnings(data.truncation));
    } catch (e) {
      warnings.add('导入过程中出错:$e(已导入的部分已保存)');
      debugPrint('ReadFlow 备份导入失败: $e');
    }

    return RestoreReport(
      added: added,
      skipped: skipped,
      cardsRestored: cardsRestored,
      replacedModel: restoredModel,
      backupVersion: data.backupVersion,
      tables: tableStats,
      warnings: warnings,
    );
  }

  // ═══════════════ v2:v3 新表的恢复(单事务 + 逐表冲突策略) ═══════════════
  //
  // 冲突/跳过策略(逐表写清楚 —— 换机恢复一旦"猜"就是在赌用户的数据):
  // - material_translations:UNIQUE(material_id, unit_index),已存在 → 跳过。
  //   理由:译文是派生资产,本机已有的是用户可能重翻过的版本,不能覆盖。
  // - rubrics:按 id 只插缺失,不动已有行。理由:内置 rubric 是 seed 事实源,
  //   本地可能已被新版本升级过,旧备份里的 seed 不该覆盖新的。
  // - exercise_sets/items:无自然键,按 (source, title, created_at) 判重;
  //   重导的题组跳过其整套题目;父子关系用"旧 id → 新 id"映射重建。
  // - output_attempts:无自然键,按 (created_at, mode, answer) 判重(哈希键);
  //   set_id/item_id 映射不到(题组被截断或已不存在)就置空 —— 宁可少一条关联,
  //   也不要把作答挂到本机不相干的题组上(那会让统计与错误热点算错)。
  // - ability_snapshots:按 (dimension, snapshot_at) 判重;已存在跳过,
  //   避免趋势图出现重复点(DB 层的 upsert 用的也是同一键)。
  // - task_events:按 (映射后的 task_id, event, at) 判重;父任务映射不到的事件
  //   无法归属 → 跳过(掉到别的任务名下比丢一条审计更糟)。
  // - tutor_tasks:按 (plan_date, title, kind) 判重;已存在则复用其 id 供事件映射,
  //   不修改本地任务状态(状态机归本机管)。
  // - error_tags:按 (source, tag) 合并:count 取 max、first_at 取更早、
  //   last_at 取更晚、status/evidence 保留本地。理由:同一错误在本机与备份里
  //   各记了一部分次数,取 max 不会让"复发次数"虚高(相加会)。
  // - word_review:按词面对齐本机 vocabulary;已随 vocab[].review 恢复的直接
  //   跳过(不重复写),只兜底"备份里有复习行但 vocab 卡片缺失"的场景。
  //
  // 为什么整块一个事务:这些表互相有引用(题组↔题目、任务↔事件),写一半的库
  // 比"一条都没恢复"更糟 —— 统计会显示出根本不存在的关联。事务失败 → 整块
  // 回滚,由调用方转成一句可读警告(不静默)。
  static Future<Map<String, RestoreTableStat>> _restoreV2Tables(
    BackupData data,
  ) async {
    final db = await DatabaseService.database;
    final stats = <String, RestoreTableStat>{};
    final nowIso = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await _restoreRubrics(txn, data.tables['rubrics'] ?? const [], nowIso, stats);
      await _restoreTranslations(
        txn,
        data.tables['material_translations'] ?? const [],
        nowIso,
        stats,
      );
      final setMap = await _restoreExerciseSets(
        txn,
        data.tables['exercise_sets'] ?? const [],
        nowIso,
        stats,
      );
      final itemMap = await _restoreExerciseItems(
        txn,
        data.tables['exercise_items'] ?? const [],
        setMap,
        stats,
      );
      final taskMap = await _restoreTutorTasks(
        txn,
        data.tables['tutor_tasks'] ?? const [],
        nowIso,
        stats,
      );
      await _restoreTaskEvents(
        txn,
        data.tables['task_events'] ?? const [],
        taskMap,
        nowIso,
        stats,
      );
      await _restoreOutputAttempts(
        txn,
        data.tables['output_attempts'] ?? const [],
        setMap,
        itemMap,
        nowIso,
        stats,
      );
      await _restoreAbilitySnapshots(
        txn,
        data.tables['ability_snapshots'] ?? const [],
        nowIso,
        stats,
      );
      await _restoreErrorTags(
        txn,
        data.tables['error_tags'] ?? const [],
        stats,
      );
      await _restoreWordReviews(
        txn,
        data.tables['word_review'] ?? const [],
        data.cardsByWord.keys.toSet(),
        stats,
      );
    });
    return stats;
  }

  // ── 单表恢复(每个方法都只接收行数据 + 写库器,便于单独读) ──

  static Future<void> _restoreRubrics(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    String nowIso,
    Map<String, RestoreTableStat> stats,
  ) async {
    final existing = <String>{};
    for (final r in await txn.query('rubrics', columns: ['id'])) {
      final id = _asString(r['id']);
      if (id.isNotEmpty) existing.add(id);
    }
    var restored = 0;
    var skipped = 0;
    for (final row in rows) {
      final id = _asString(row['id']);
      if (id.isEmpty || !existing.add(id)) {
        skipped++;
        continue;
      }
      final inserted = await txn.insert(
        'rubrics',
        <String, Object?>{
          'id': id,
          // type/scoring_mode 都是 NOT NULL,缺失时给安全默认(不是编内容,
          // 只是让 NOT NULL 列有值;真正内容仍来自备份的 JSON 列)
          'type': row['type'] ?? 'writing',
          'scoring_mode': row['scoring_mode'] ?? 'ai_rubric',
          'dimensions_json': _jsonCell(row['dimensions_json']),
          'bands_json': _jsonCell(row['bands_json']),
          'prompt_template': row['prompt_template'],
          'created_at': _asString(row['created_at']).isEmpty
              ? nowIso
              : row['created_at'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (inserted > 0) {
        restored++;
      } else {
        skipped++;
      }
    }
    stats['rubrics'] = RestoreTableStat(
      exported: rows.length,
      restored: restored,
      skipped: skipped,
      skipReason: skipped > 0 ? '本机已有同 id 的评分标准,不覆盖' : null,
    );
  }

  static Future<void> _restoreTranslations(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    String nowIso,
    Map<String, RestoreTableStat> stats,
  ) async {
    final existing = <String>{};
    for (final r in await txn.query(
      'material_translations',
      columns: ['material_id', 'unit_index'],
    )) {
      final mid = _asInt(r['material_id']);
      final unit = _asInt(r['unit_index']);
      if (mid != null && unit != null) existing.add('$mid|$unit');
    }
    var restored = 0;
    var skipped = 0;
    for (final row in rows) {
      final mid = _asInt(row['material_id']);
      final unit = _asInt(row['unit_index']);
      if (mid == null || unit == null || !existing.add('$mid|$unit')) {
        skipped++;
        continue;
      }
      // 注意:source_text/translated_text 是 NOT NULL。这里不做"空值兜底":
      // 结构坏的行**不会被写成半残译文** —— 约束违规被 INSERT OR IGNORE 跳过
      // 并如实计入 skipped;而 sqflite 层不支持的类型(Map 等)会直接让事务
      // 失败、整块回滚(见 _restoreV2Tables 的说明)。
      final inserted = await txn.insert(
        'material_translations',
        <String, Object?>{
          'material_id': mid,
          'unit_index': unit,
          'chunk_index': _asInt(row['chunk_index']) ?? unit,
          'source_text': row['source_text'],
          'translated_text': row['translated_text'],
          'model': row['model'],
          'created_at': _asString(row['created_at']).isEmpty
              ? nowIso
              : row['created_at'],
          'updated_at': row['updated_at'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      // INSERT OR IGNORE 会连 NOT NULL 违规一起吞掉(返回 0),所以计数必须
      // 看真实 rowid:被忽略的行算"跳过",不能谎报成已恢复。
      if (inserted > 0) {
        restored++;
      } else {
        skipped++;
      }
    }
    stats['material_translations'] = RestoreTableStat(
      exported: rows.length,
      restored: restored,
      skipped: skipped,
      skipReason: skipped > 0 ? '本机同材料同段落已有译文,不覆盖' : null,
    );
  }

  /// 恢复题组,返回"旧题组 id → 新题组 id"(题目与作答靠它重建关联)。
  static Future<Map<int, int>> _restoreExerciseSets(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    String nowIso,
    Map<String, RestoreTableStat> stats,
  ) async {
    final existing = <String>{};
    for (final r in await txn.query(
      'exercise_sets',
      columns: ['source', 'title', 'created_at'],
    )) {
      existing.add(
        '${_asString(r['source'])}|${_asString(r['title'])}|'
        '${_asString(r['created_at'])}',
      );
    }
    final idMap = <int, int>{};
    var restored = 0;
    var skipped = 0;
    for (final row in rows) {
      final oldId = _asInt(row['id']);
      final title = _asString(row['title']);
      final naturalKey = '${_asString(row['source'])}|$title|'
          '${_asString(row['created_at'])}';
      if (title.isEmpty || existing.contains(naturalKey)) {
        skipped++;
        continue;
      }
      final newId = await txn.insert('exercise_sets', <String, Object?>{
        'source': _asString(row['source']).isEmpty ? 'ai' : row['source'],
        'exam_type': row['exam_type'] ?? 'none',
        'paper_year': row['paper_year'],
        'paper_label': row['paper_label'],
        'section': row['section'],
        'title': title,
        'difficulty_cefr': row['difficulty_cefr'],
        'goals_json': _jsonCell(row['goals_json']),
        'rubric_id': row['rubric_id'],
        'material_id': row['material_id'],
        'license_note': row['license_note'],
        'verify_status': row['verify_status'] ?? 'pending',
        'created_at': _asString(row['created_at']).isEmpty
            ? nowIso
            : row['created_at'],
      });
      existing.add(naturalKey);
      if (oldId != null) idMap[oldId] = newId;
      restored++;
    }
    stats['exercise_sets'] = RestoreTableStat(
      exported: rows.length,
      restored: restored,
      skipped: skipped,
      skipReason: skipped > 0 ? '同来源同标题同创建时间的题组已存在,跳过(及其题目)' : null,
    );
    return idMap;
  }

  /// 恢复题目,返回"旧题目 id → 新题目 id"(作答靠它重建关联)。
  static Future<Map<int, int>> _restoreExerciseItems(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    Map<int, int> setMap,
    Map<String, RestoreTableStat> stats,
  ) async {
    final idMap = <int, int>{};
    var restored = 0;
    var skipped = 0;
    for (final row in rows) {
      final oldSetId = _asInt(row['set_id']);
      final newSetId = oldSetId == null ? null : setMap[oldSetId];
      if (newSetId == null) {
        // 题组被跳过(已存在)或被截断 → 题目无处安放,宁可跳过也不挂错父题组
        skipped++;
        continue;
      }
      final oldId = _asInt(row['id']);
      final newId = await txn.insert('exercise_items', <String, Object?>{
        'set_id': newSetId,
        'idx': _asInt(row['idx']) ?? 0,
        'type': _asString(row['type']).isEmpty ? 'summary' : row['type'],
        'prompt_zh': row['prompt_zh'],
        'prompt_en': row['prompt_en'],
        'reference_answer': row['reference_answer'],
        'accepted_answers_json': _jsonCell(row['accepted_answers_json']),
        'rubric_id': row['rubric_id'],
        'ability_tags_json': _jsonCell(row['ability_tags_json']),
        'grammar_points_json': _jsonCell(row['grammar_points_json']),
        'word_count': _asInt(row['word_count']) ?? 0,
        'source_span': row['source_span'],
        'audio_ref': row['audio_ref'],
      });
      if (oldId != null) idMap[oldId] = newId;
      restored++;
    }
    stats['exercise_items'] = RestoreTableStat(
      exported: rows.length,
      restored: restored,
      skipped: skipped,
      skipReason: skipped > 0 ? '所属题组已存在或被截断,题目不再挂接' : null,
    );
    return idMap;
  }

  /// 恢复助理任务,返回"旧任务 id → 新任务 id"(事件靠它重建关联)。
  static Future<Map<int, int>> _restoreTutorTasks(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    String nowIso,
    Map<String, RestoreTableStat> stats,
  ) async {
    final existing = <String, int>{};
    for (final r in await txn.query(
      'tutor_tasks',
      columns: ['id', 'plan_date', 'title', 'kind'],
    )) {
      final id = _asInt(r['id']);
      if (id == null) continue;
      existing[
          '${_asString(r['plan_date'])}|${_asString(r['title'])}|${_asString(r['kind'])}'] =
          id;
    }
    final idMap = <int, int>{};
    final inserted = <(int, int, Object?)>[]; // (旧 id, 新 id, 旧 parent_id)
    var restored = 0;
    var skipped = 0;
    for (final row in rows) {
      final oldId = _asInt(row['id']);
      final planDate = _asString(row['plan_date']);
      final kind = _asString(row['kind']);
      final title = _asString(row['title']);
      // 三列都是 NOT NULL,缺任何一个这张任务卡都没有意义
      if (planDate.isEmpty || kind.isEmpty || title.isEmpty) {
        skipped++;
        continue;
      }
      final naturalKey = '$planDate|$title|$kind';
      final existId = existing[naturalKey];
      if (existId != null) {
        if (oldId != null) idMap[oldId] = existId;
        skipped++;
        continue;
      }
      final newId = await txn.insert('tutor_tasks', <String, Object?>{
        'plan_date': planDate,
        'kind': kind,
        'title': title,
        'payload_json': _jsonCell(row['payload_json']),
        'target_minutes': _asInt(row['target_minutes']) ?? 0,
        'done_at': row['done_at'],
        'result_json': _jsonCell(row['result_json']),
        'created_at': _asString(row['created_at']).isEmpty
            ? nowIso
            : row['created_at'],
        'origin': _asString(row['origin']).isEmpty ? 'auto' : row['origin'],
        'status': _asString(row['status']).isEmpty ? 'pending' : row['status'],
        'started_at': row['started_at'],
        'actual_minutes': row['actual_minutes'],
        'note': row['note'],
        'goal_tag': row['goal_tag'],
      });
      existing[naturalKey] = newId;
      if (oldId != null) {
        idMap[oldId] = newId;
        inserted.add((oldId, newId, row['parent_id']));
      }
      restored++;
    }
    // parent_id 二次回填:导出顺序按 plan_date,父任务可能排在子任务后面,
    // 先全部插入再按映射修 parent,避免"父还没插就引用"。
    for (final (_, newId, parentOld) in inserted) {
      final oldParent = _asInt(parentOld);
      final newParent = oldParent == null ? null : idMap[oldParent];
      if (newParent == null) continue;
      await txn.update(
        'tutor_tasks',
        {'parent_id': newParent},
        where: 'id = ?',
        whereArgs: [newId],
      );
    }
    stats['tutor_tasks'] = RestoreTableStat(
      exported: rows.length,
      restored: restored,
      skipped: skipped,
      skipReason: skipped > 0 ? '同计划日期同类型同标题的任务已存在,不覆盖状态' : null,
    );
    return idMap;
  }

  static Future<void> _restoreTaskEvents(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    Map<int, int> taskMap,
    String nowIso,
    Map<String, RestoreTableStat> stats,
  ) async {
    final existing = <String>{};
    for (final r in await txn.query(
      'task_events',
      columns: ['task_id', 'event', 'at'],
    )) {
      existing.add(
        '${_asString(r['task_id'])}|${_asString(r['event'])}|'
        '${_asString(r['at'])}',
      );
    }
    var restored = 0;
    var skipped = 0;
    for (final row in rows) {
      final oldTaskId = _asInt(row['task_id']);
      final newTaskId = oldTaskId == null ? null : taskMap[oldTaskId];
      final event = _asString(row['event']);
      if (newTaskId == null || event.isEmpty) {
        skipped++;
        continue;
      }
      final at = _asString(row['at']).isEmpty ? nowIso : _asString(row['at']);
      if (!existing.add('$newTaskId|$event|$at')) {
        skipped++;
        continue;
      }
      await txn.insert('task_events', <String, Object?>{
        'task_id': newTaskId,
        'event': event,
        'at': at,
        'payload_json': _jsonCell(row['payload_json']),
        'created_at': _asString(row['created_at']).isEmpty
            ? nowIso
            : row['created_at'],
      });
      restored++;
    }
    stats['task_events'] = RestoreTableStat(
      exported: rows.length,
      restored: restored,
      skipped: skipped,
      skipReason: skipped > 0 ? '父任务不存在(或已存在),事件无法归属' : null,
    );
  }

  static Future<void> _restoreOutputAttempts(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    Map<int, int> setMap,
    Map<int, int> itemMap,
    String nowIso,
    Map<String, RestoreTableStat> stats,
  ) async {
    // 判重键预载:只查备份最早时间之后的作答,避免全表扫描(流水表可能上万条)
    DateTime? earliest;
    for (final row in rows) {
      final t = DateTime.tryParse(_asString(row['created_at']));
      if (t != null && (earliest == null || t.isBefore(earliest))) earliest = t;
    }
    final existing = <String>{};
    if (earliest != null) {
      final local = await txn.query(
        'output_attempts',
        columns: ['created_at', 'mode', 'answer'],
        where: 'created_at >= ?',
        whereArgs: [earliest.toIso8601String()],
      );
      for (final r in local) {
        existing.add(
          _attemptKey(
            _asString(r['created_at']),
            _asString(r['mode']),
            _asString(r['answer']),
          ),
        );
      }
    }
    var restored = 0;
    var skipped = 0;
    for (final row in rows) {
      final createdAt = _asString(row['created_at']);
      if (createdAt.isEmpty) {
        skipped++;
        continue;
      }
      if (!existing.add(
        _attemptKey(createdAt, _asString(row['mode']), _asString(row['answer'])),
      )) {
        skipped++;
        continue;
      }
      final oldSetId = _asInt(row['set_id']);
      final oldItemId = _asInt(row['item_id']);
      await txn.insert('output_attempts', <String, Object?>{
        // 映射不到关联时置空:作答本身仍然恢复(历史不丢),只是不再挂到
        // 本机可能不相干的题组/题目上
        'set_id': oldSetId == null ? null : setMap[oldSetId],
        'item_id': oldItemId == null ? null : itemMap[oldItemId],
        'mode': row['mode'],
        'answer': row['answer'],
        'correct': _asInt(row['correct']),
        'score_json': _jsonCell(row['score_json']),
        'seconds': _asInt(row['seconds']) ?? 0,
        // plan_id 指向 drill_plans(不在备份里);保留原值会挂到本机不相干的
        // 计划上,所以置空 —— 少一个关联比错关联安全
        'plan_id': null,
        'error_tags_json': _jsonCell(row['error_tags_json']),
        'created_at': createdAt,
      });
      restored++;
    }
    stats['output_attempts'] = RestoreTableStat(
      exported: rows.length,
      restored: restored,
      skipped: skipped,
      skipReason: skipped > 0 ? '本机已有相同时间/模式/答案的作答,跳过' : null,
    );
  }

  static Future<void> _restoreAbilitySnapshots(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    String nowIso,
    Map<String, RestoreTableStat> stats,
  ) async {
    final existing = <String>{};
    for (final r in await txn.query(
      'ability_snapshots',
      columns: ['dimension', 'snapshot_at'],
    )) {
      existing.add('${_asString(r['dimension'])}|${_asString(r['snapshot_at'])}');
    }
    var restored = 0;
    var skipped = 0;
    for (final row in rows) {
      final dimension = _asString(row['dimension']);
      final snapshotAt = _asString(row['snapshot_at']);
      final value = _asDouble(row['value']);
      // 没有数值的快照没有意义:写成 0 会在趋势图上画出"能力归零"的假信号
      if (dimension.isEmpty ||
          snapshotAt.isEmpty ||
          value == null ||
          !existing.add('$dimension|$snapshotAt')) {
        skipped++;
        continue;
      }
      await txn.insert('ability_snapshots', <String, Object?>{
        'snapshot_at': snapshotAt,
        'dimension': dimension,
        'value': value,
        'unit': row['unit'],
        'source': row['source'],
        'confidence': _asDouble(row['confidence']),
        'evidence_json': _jsonCell(row['evidence_json']),
        'created_at': _asString(row['created_at']).isEmpty
            ? nowIso
            : row['created_at'],
      });
      restored++;
    }
    stats['ability_snapshots'] = RestoreTableStat(
      exported: rows.length,
      restored: restored,
      skipped: skipped,
      skipReason: skipped > 0 ? '本机已有同维度同时间的快照,不覆盖' : null,
    );
  }

  static Future<void> _restoreErrorTags(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    Map<String, RestoreTableStat> stats,
  ) async {
    final existing = <String, Map<String, Object?>>{};
    for (final r in await txn.query('error_tags')) {
      final key = '${_asString(r['source'])}|${_asString(r['tag'])}';
      existing.putIfAbsent(key, () => r);
    }
    var restored = 0;
    var skipped = 0;
    for (final row in rows) {
      final source = _asString(row['source']);
      final tag = _asString(row['tag']);
      if (source.isEmpty || tag.isEmpty) {
        skipped++;
        continue;
      }
      final key = '$source|$tag';
      final local = existing[key];
      final count = _asInt(row['count']) ?? 1;
      if (local == null) {
        await txn.insert('error_tags', <String, Object?>{
          'source': source,
          'tag': tag,
          'count': count < 1 ? 1 : count,
          'first_at': row['first_at'],
          'last_at': row['last_at'],
          'status': _asString(row['status']).isEmpty ? 'active' : row['status'],
          'evidence': row['evidence'],
        });
        restored++;
        continue;
      }
      // 合并(不相加):同一错误在本机与备份里各记了一部分次数,
      // 取 max 反映"至少复发过几次",相加会让复发次数虚高。
      final localCount = _asInt(local['count']) ?? 0;
      final localEvidence = _asString(local['evidence']);
      await txn.update(
        'error_tags',
        <String, Object?>{
          'count': count > localCount ? count : localCount,
          'first_at': _earlierIso(local['first_at'], row['first_at']),
          'last_at': _laterIso(local['last_at'], row['last_at']),
          // 状态归本机管(fixed 是用户在本机确认过的),证据优先用本机的,
          // 本机没有才用备份的
          'evidence': localEvidence.isNotEmpty
              ? local['evidence']
              : row['evidence'],
        },
        where: 'id = ?',
        whereArgs: [local['id']],
      );
      restored++;
    }
    stats['error_tags'] = RestoreTableStat(
      exported: rows.length,
      restored: restored,
      skipped: skipped,
      skipReason: skipped > 0 ? '缺少来源或标签,无法归并' : null,
    );
  }

  static Future<void> _restoreWordReviews(
    DatabaseExecutor txn,
    List<Map<String, Object?>> rows,
    Set<String> cardsByWord,
    Map<String, RestoreTableStat> stats,
  ) async {
    final wordToId = <String, int>{};
    for (final r in await txn.query(
      'vocabulary',
      columns: ['id', 'word'],
    )) {
      final id = _asInt(r['id']);
      final word = _asString(r['word']).toLowerCase();
      if (id != null && word.isNotEmpty) wordToId[word] = id;
    }
    var restored = 0;
    var skipped = 0;
    for (final row in rows) {
      final word = _asString(row['vocabulary_word']).toLowerCase();
      // 已经随 vocab[].review 恢复过的词跳过(同一个复习状态写两遍没有意义,
      // 还会把 upsert 的 reps 语义弄乱)
      if (word.isEmpty || cardsByWord.contains(word)) {
        skipped++;
        continue;
      }
      final vocabId = wordToId[word];
      if (vocabId == null) {
        // 本机没有这个词条(例如只恢复了部分生词):复习状态没有宿主
        skipped++;
        continue;
      }
      await txn.insert(
        'word_review',
        <String, Object?>{
          'vocab_id': vocabId,
          'stability': _asDouble(row['stability']) ?? 0,
          'difficulty': _asDouble(row['difficulty']) ?? 0,
          'due_at': row['due_at'],
          'last_review_at': row['last_review_at'],
          'reps': _asInt(row['reps']) ?? 0,
          'lapses': _asInt(row['lapses']) ?? 0,
          'last_rating': _asInt(row['last_rating']),
          'created_at': row['created_at'],
          'updated_at': row['updated_at'],
        },
        // vocab_id 是 UNIQUE:REPLACE = upsert 覆盖,不会一行变两行
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      restored++;
    }
    stats['word_review'] = RestoreTableStat(
      exported: rows.length,
      restored: restored,
      skipped: skipped,
      skipReason: skipped > 0 ? '已随生词卡片恢复或本机无该词条' : null,
    );
  }

  // ── 备份行的安全取值(坏备份不能抛类型错误) ──

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.trim());
  }

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}'.trim());
  }

  static String _asString(Object? v) => '${v ?? ''}'.trim();

  /// JSON 列:Map/List 直接编码成字符串(老备份/手改备份里可能是嵌套对象),
  /// 其余原样返回 —— null 仍是 null(缺值语义不能被编码成 "null")。
  static Object? _jsonCell(Object? v) {
    if (v == null || v is String || v is num || v is bool) return v;
    try {
      return jsonEncode(v);
    } catch (_) {
      return '$v';
    }
  }

  /// 作答判重键:创建时间 + 模式 + 答案长度/哈希。
  /// 为什么不直接比较答案原文:作答可能有几千字,5000 条全放内存里做集合
  /// 会占用几十 MB;长度+哈希的碰撞概率对"判重"这个用途足够低。
  static String _attemptKey(String createdAt, String mode, String answer) =>
      '$createdAt|$mode|${answer.length}|${answer.hashCode}';

  /// 两个 ISO 时间串取较早的一个(空串视为"没有")
  static Object? _earlierIso(Object? a, Object? b) {
    final sa = _asString(a);
    final sb = _asString(b);
    if (sa.isEmpty) return b;
    if (sb.isEmpty) return a;
    return sa.compareTo(sb) <= 0 ? a : b;
  }

  /// 两个 ISO 时间串取较晚的一个(空串视为"没有")
  static Object? _laterIso(Object? a, Object? b) {
    final sa = _asString(a);
    final sb = _asString(b);
    if (sa.isEmpty) return b;
    if (sb.isEmpty) return a;
    return sa.compareTo(sb) >= 0 ? a : b;
  }

  /// 把导出时的截断事实变成给用户看的警告句。
  static List<String> _truncationWarnings(Map<String, Object?> truncation) {
    final out = <String>[];
    for (final entry in truncation.entries) {
      final meta = entry.value is Map ? entry.value as Map : const {};
      final exported = meta['exported'];
      final total = meta['total'];
      if (exported is! num || total is! num) continue;
      out.add(
        '备份里的${RestoreReport.tableLabel(entry.key)}只包含最近 '
        '${exported.toInt()} 条(导出时共 ${total.toInt()} 条,'
        '更早的历史不在备份里)',
      );
    }
    return out;
  }
}

/// 导出侧收集到的 v3 新表数据(表名 → 行 / 截断说明 / 给用户的说明)
class _CollectedTables {
  final Map<String, List<Map<String, Object?>>> tables;
  final Map<String, Object?> truncation;
  final List<String> notes;

  const _CollectedTables({
    required this.tables,
    required this.truncation,
    required this.notes,
  });
}
