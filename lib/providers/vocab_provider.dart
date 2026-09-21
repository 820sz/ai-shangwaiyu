import 'package:flutter/material.dart';
import '../models/vocabulary.dart';
import '../services/database.dart';

/// 生词库状态。
///
/// v1.9.0 加固(审查 P1-7/P1-8):
/// - 加**世代守卫**(`_loadGen`):带筛选与不带筛选的加载会并发发生
///   (生词本按书筛选 vs 复习/推荐页全量),旧实现"后返回的覆盖先返回的",
///   会把筛选结果冲成全量、甚至把刚删的词显示回来。
/// - 加**批量接口**:批量删除/移动走单事务一次调用 + 一次刷新,
///   不再 N 路并发写 + N 次全表刷新(既是性能问题也是竞态来源)。
/// - `_loading` 用 `finally` 复位:任何异常都不会让界面永久转圈。
class VocabProvider extends ChangeNotifier {
  List<Vocabulary> _vocabularies = [];
  List<String> _bookList = [];
  Map<String, int> _vocabByBook = {};
  Map<String, int> _vocabByCategory = {};
  bool _loading = false;
  String? _error;

  /// 每次加载/刷新自增;异步返回后只有"最新一代"才允许写入状态
  int _loadGen = 0;

  List<Vocabulary> get vocabularies => _vocabularies;
  List<String> get bookList => _bookList;
  Map<String, int> get vocabByBook => _vocabByBook;
  Map<String, int> get vocabByCategory => _vocabByCategory;
  bool get loading => _loading;
  String? get error => _error;

  /// 确认保存生词到数据库
  Future<int> saveVocabularies(List<Vocabulary> list) async {
    final count = await DatabaseService.insertVocabularies(list);

    // 更新当天的学习记录（非关键路径，失败不阻断保存，但必须留痕）
    try {
      await DatabaseService.incrementDailyWords(DateTime.now(), count);
    } catch (e) {
      debugPrint('ReadFlow incrementDailyWords failed: $e');
    }

    await _refresh();
    return count;
  }

  /// 从数据库加载生词
  Future<void> loadVocabularies({
    String? sourceBook,
    int? masteryLevel,
  }) async {
    final gen = ++_loadGen;
    _loading = true;
    notifyListeners();

    try {
      final items = await DatabaseService.getVocabularies(
        sourceBook: sourceBook,
        masteryLevel: masteryLevel,
      );
      final results = await Future.wait([
        DatabaseService.getBookList(),
        DatabaseService.getVocabCountByBook(),
        DatabaseService.getVocabCountByCategory(),
      ]);
      if (gen != _loadGen) return; // 已被更新的加载取代,丢弃本次结果
      _vocabularies = items;
      _bookList = results[0] as List<String>;
      _vocabByBook = results[1] as Map<String, int>;
      _vocabByCategory = results[2] as Map<String, int>;
      _error = null;
    } catch (e, stack) {
      debugPrint('ReadFlow loadVocabularies error: $e\n$stack');
      if (gen == _loadGen) _error = '加载失败：$e';
    } finally {
      if (gen == _loadGen) {
        _loading = false;
        notifyListeners();
      }
    }
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

  /// 批量删除(v1.9.0):单事务 + 单次刷新。返回成功删除的条数。
  Future<int> deleteVocabularies(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final n = await DatabaseService.deleteVocabularies(ids);
    await _refresh();
    return n;
  }

  /// 批量移动分类(v1.9.0):单事务 + 单次刷新。
  Future<int> moveVocabularies(
    List<int> ids, {
    String? category,
    String? materialPath,
    String? sourceBook,
    String? sourcePage,
  }) async {
    if (ids.isEmpty) return 0;
    final n = await DatabaseService.updateVocabulariesCategory(
      ids,
      category: category,
      materialPath: materialPath,
      sourceBook: sourceBook,
      sourcePage: sourcePage,
    );
    await _refresh();
    return n;
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
    final gen = ++_loadGen;
    try {
      final results = await Future.wait([
        DatabaseService.getVocabularies(),
        DatabaseService.getBookList(),
        DatabaseService.getVocabCountByBook(),
        DatabaseService.getVocabCountByCategory(),
      ]);
      if (gen != _loadGen) return;
      _vocabularies = results[0] as List<Vocabulary>;
      _bookList = results[1] as List<String>;
      _vocabByBook = results[2] as Map<String, int>;
      _vocabByCategory = results[3] as Map<String, int>;
      _error = null;
    } catch (e, stack) {
      debugPrint('ReadFlow _refresh error: $e\n$stack');
      if (gen == _loadGen) _error = '刷新失败：$e';
    } finally {
      if (gen == _loadGen) notifyListeners();
    }
  }
}
