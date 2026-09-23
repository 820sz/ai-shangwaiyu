import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

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

  const ExportedFile({
    required this.path,
    required this.content,
    required this.label,
  });

  int get bytes => content.length;
  String get fileName => path.split(Platform.pathSeparator).last;
}

/// 导入结果(给用户看的报告)
class RestoreReport {
  final int added;
  final int skipped;
  final int cardsRestored;
  final bool replacedModel;
  final List<String> warnings;

  const RestoreReport({
    this.added = 0,
    this.skipped = 0,
    this.cardsRestored = 0,
    this.replacedModel = false,
    this.warnings = const [],
  });

  String get summary {
    final parts = <String>['导入 $added 个新词'];
    if (skipped > 0) parts.add('跳过 $skipped 个已存在');
    if (cardsRestored > 0) parts.add('恢复 $cardsRestored 条复习状态');
    if (replacedModel) parts.add('恢复学习画像');
    return parts.join(' · ');
  }
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

  /// 完整备份 JSON(可回导)
  static Future<ExportedFile> exportBackupJson() async {
    final vocab = await DatabaseService.getVocabularies(limit: 100000);
    final cards = await _cardsByVocabId();
    final model = LearnerModelStore.load();
    // 只备份"跨设备有意义"的设置:API Key 绝不进备份文件
    final box = Hive.box(AppConstants.hiveBoxSettings);
    final accent = box.get(AppConstants.keyTtsAccent);
    return write(
      'readflow-备份-${stamp()}.json',
      ExportService.backupJson(
        vocab: vocab,
        cards: cards,
        model: model,
        settings: {
          if (accent is String) 'tts_accent': accent,
        },
      ),
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
  static Future<RestoreReport> restore(
    BackupData data, {
    required bool replace,
  }) async {
    final warnings = <String>[];
    if (!data.ok) {
      return RestoreReport(warnings: [data.error ?? '备份内容不可用']);
    }
    var added = 0;
    var skipped = 0;
    var cardsRestored = 0;
    // 提到 try 外面:异常路径也要如实报告"画像到底恢复没有"
    var restoredModel = false;

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
    } catch (e) {
      warnings.add('导入过程中出错:$e(已导入的部分已保存)');
      debugPrint('ReadFlow 备份导入失败: $e');
    }

    return RestoreReport(
      added: added,
      skipped: skipped,
      cardsRestored: cardsRestored,
      replacedModel: restoredModel,
      warnings: warnings,
    );
  }
}
