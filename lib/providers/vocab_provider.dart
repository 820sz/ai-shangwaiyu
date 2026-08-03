import 'dart:io';
import 'package:flutter/material.dart';
import '../models/vocabulary.dart';
import '../services/database.dart';
import '../services/doubao_api.dart';

class VocabProvider extends ChangeNotifier {
  final DoubaoApiService _doubao = DoubaoApiService();
  List<Vocabulary> _vocabularies = [];
  List<String> _bookList = [];
  Map<String, int> _vocabByBook = {};
  Map<String, int> _vocabByCategory = {};
  bool _loading = false;
  String? _error;

  List<Vocabulary> get vocabularies => _vocabularies;
  List<String> get bookList => _bookList;
  Map<String, int> get vocabByBook => _vocabByBook;
  Map<String, int> get vocabByCategory => _vocabByCategory;
  bool get loading => _loading;
  String? get error => _error;

  /// 从相机拍照取词
  Future<List<Vocabulary>> extractFromPhoto(
    List<File> imageFiles, {
    String? sourceBook,
    String? sourcePage,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await _doubao.extractVocabulary(
        imageFiles,
        sourceBook: sourceBook,
        sourcePage: sourcePage,
      );

      if (results.isEmpty) {
        _error = 'AI 未识别到标记的单词，请确认图片中有标记痕迹。';
        _loading = false;
        notifyListeners();
        return [];
      }

      // 转为 Vocabulary 对象（暂未入库）
      final list = results.map((r) {
        return Vocabulary(
          word: r['word'] as String,
          translation: r['translation'] as String?,
          sourceBook: sourceBook,
          sourcePage: sourcePage,
          originalSentence: r['original_sentence'] as String?,
          photoPath: imageFiles.first.path,
          wordType: (r['word_type'] as String?) ?? 'word',
          partOfSpeech: r['part_of_speech'] as String?,
          grammarNote: r['grammar_note'] as String?,
        );
      }).toList();

      _loading = false;
      notifyListeners();
      return list;
    } catch (e, stack) {
      debugPrint('ReadFlow extractFromPhoto error: $e\n$stack');
      _error = '识别失败：${e.toString()}';
      _loading = false;
      notifyListeners();
      return [];
    }
  }

  /// 确认保存生词到数据库
  Future<int> saveVocabularies(List<Vocabulary> list) async {
    final count = await DatabaseService.insertVocabularies(list);

    // 更新当天的学习记录（非关键路径，失败不阻断保存）
    try {
      await DatabaseService.incrementDailyWords(DateTime.now(), count);
    } catch (_) {
      // 日志表可能不存在（旧版升级），静默忽略
    }

    await _refresh();
    return count;
  }

  /// 从数据库加载生词
  Future<void> loadVocabularies({
    String? sourceBook,
    int? masteryLevel,
  }) async {
    _loading = true;
    notifyListeners();

    try {
      _vocabularies = await DatabaseService.getVocabularies(
        sourceBook: sourceBook,
        masteryLevel: masteryLevel,
      );
      final results = await Future.wait([
        DatabaseService.getBookList(),
        DatabaseService.getVocabCountByBook(),
        DatabaseService.getVocabCountByCategory(),
      ]);
      _bookList = results[0] as List<String>;
      _vocabByBook = results[1] as Map<String, int>;
      _vocabByCategory = results[2] as Map<String, int>;
    } catch (e, stack) {
      debugPrint('ReadFlow loadVocabularies error: $e\n$stack');
      _error = '加载失败：$e';
    }
    _loading = false;
    notifyListeners();
  }

  /// 更新掌握度
  Future<void> updateMastery(int id, int level) async {
    await DatabaseService.updateMastery(id, level);
    await _refresh();
  }

  /// 更新生词分类/来源（用于批量移动）
  Future<void> updateVocabulary(int id,
      {String? category,
      String? materialPath,
      String? sourceBook,
      String? sourcePage}) async {
    await DatabaseService.updateVocabulary(id,
        category: category,
        materialPath: materialPath,
        sourceBook: sourceBook,
        sourcePage: sourcePage);
    await _refresh();
  }

  /// 删除生词
  Future<void> deleteVocabulary(int id) async {
    try {
      await DatabaseService.deleteVocabulary(id);
    } catch (e) {
      debugPrint('ReadFlow deleteVocabulary error: $e');
      _error = '删除失败：$e';
      notifyListeners();
      return; // 失败不刷新
    }
    await _refresh();
  }

  /// 搜索生词
  List<Vocabulary> search(String query) {
    if (query.isEmpty) return _vocabularies;
    final q = query.toLowerCase();
    return _vocabularies.where((v) {
      return v.word.toLowerCase().contains(q) ||
          (v.translation?.toLowerCase().contains(q) ?? false) ||
          (v.originalSentence?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        DatabaseService.getVocabularies(),
        DatabaseService.getBookList(),
        DatabaseService.getVocabCountByBook(),
        DatabaseService.getVocabCountByCategory(),
      ]);
      _vocabularies = results[0] as List<Vocabulary>;
      _bookList = results[1] as List<String>;
      _vocabByBook = results[2] as Map<String, int>;
      _vocabByCategory = results[3] as Map<String, int>;
    } catch (e, stack) {
      debugPrint('ReadFlow _refresh error: $e\n$stack');
      _error = '刷新失败：$e';
    }
    notifyListeners();
  }
}
