import 'package:flutter/material.dart';
import '../models/article.dart';
import '../models/exercise.dart';
import '../models/learning_record.dart';
import '../services/database.dart';
import '../services/deepseek_api.dart';
import '../utils/scoring.dart';

class ArticleProvider extends ChangeNotifier {
  final DeepseekApiService _deepseek = DeepseekApiService();
  List<Article> _articles = [];
  Map<int, List<Exercise>> _exercisesByArticle = {};
  bool _loading = false;
  bool _generating = false;
  String? _error;

  List<Article> get articles => _articles;
  Map<int, List<Exercise>> get exercisesByArticle => _exercisesByArticle;
  bool get loading => _loading;
  bool get generating => _generating;
  String? get error => _error;

  /// 加载文章列表
  Future<void> loadArticles() async {
    _loading = true;
    notifyListeners();

    _articles = await DatabaseService.getArticles();
    // 也加载每篇文章的练习
    _exercisesByArticle = {};
    for (final a in _articles) {
      if (a.id != null) {
        _exercisesByArticle[a.id!] =
            await DatabaseService.getExercisesByArticle(a.id!);
      }
    }

    _loading = false;
    notifyListeners();
  }

  /// 根据生词列表生成文章
  Future<Article?> generateArticle(
    List<Map<String, String>> vocabList,
  ) async {
    _generating = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _deepseek.generateArticle(vocabList);
      final title = result['title'] as String? ?? '未命名文章';
      final content = result['content'] as String? ?? '';

      if (content.isEmpty) {
        _error = 'AI 未能生成文章，请重试。';
        _generating = false;
        notifyListeners();
        return null;
      }

      final vocabIds = vocabList
          .map((v) => int.tryParse(v['id'] ?? '') ?? 0)
          .where((n) => n > 0)
          .toList();

      final article = Article(
        title: title,
        content: content,
        vocabIds: vocabIds,
      );

      final id = await DatabaseService.insertArticle(article);
      final saved = article.copyWith(id: id);

      await loadArticles();
      _generating = false;
      notifyListeners();
      return saved;
    } catch (e) {
      _error = '生成失败：${e.toString()}';
      _generating = false;
      notifyListeners();
      return null;
    }
  }

  /// 为文章生成回译练习
  Future<Exercise?> generateExercise(Article article) async {
    _generating = true;
    notifyListeners();

    try {
      final sentences =
          await _deepseek.generateBackTranslationExercise(article.content);

      if (sentences.isEmpty) {
        _generating = false;
        notifyListeners();
        return null;
      }

      final exercise = Exercise(
        articleId: article.id!,
        // 题面=中文,参考答案=英文原句(供真实评分)
        sourceSentences: sentences.map((s) => s['chinese']!).toList(),
        referenceAnswers: sentences.map((s) => s['english']!).toList(),
        userAnswers: List.filled(sentences.length, null),
      );

      final id = await DatabaseService.insertExercise(exercise);

      // 更新学习记录（递增）
      final todayRecord = (await DatabaseService.getDailyLogsInRange(
              DateTime.now(), DateTime.now()))
          .firstOrNull;
      await DatabaseService.upsertDailyLog(
        todayRecord != null
            ? todayRecord.copyWith(
                exerciseCompleted: todayRecord.exerciseCompleted + 1)
            : LearningRecord(
                date: DateTime.now(),
                exerciseCompleted: 1,
                studyMinutes: 0, // TODO: 从实际练习计时获取
              ),
      );

      await loadArticles();
      _generating = false;
      notifyListeners();
      return Exercise(
        id: id,
        articleId: article.id!,
        sourceSentences: sentences.map((s) => s['chinese']!).toList(),
        referenceAnswers: sentences.map((s) => s['english']!).toList(),
        userAnswers: null,
      );
    } catch (e) {
      _error = '生成练习失败：${e.toString()}';
      _generating = false;
      notifyListeners();
      return null;
    }
  }

  /// 保存练习答案并评分(评分逻辑见 utils/scoring.dart)
  Future<double?> submitExerciseAnswers(
    int exerciseId,
    List<String?> answers,
    List<String>? referenceAnswers,
  ) async {
    double score = 0;
    if (referenceAnswers != null && referenceAnswers.isNotEmpty) {
      score = scoreBackTranslation(answers, referenceAnswers);
    }

    await DatabaseService.saveExerciseAnswer(exerciseId, answers, score);
    await loadArticles();
    return score;
  }

  /// 获取个性化建议
  Future<String> getPersonalizedAdvice({
    required int totalVocab,
    required int masteredVocab,
    required int streakDays,
    required Map<String, int> vocabByBook,
  }) async {
    final memory = await DatabaseService.getAllMemory();
    return _deepseek.getPersonalizedAdvice(
      totalVocab: totalVocab,
      masteredVocab: masteredVocab,
      streakDays: streakDays,
      vocabByBook: vocabByBook,
      memory: memory,
    );
  }

  /// 删除文章
  Future<void> deleteArticle(int id) async {
    await DatabaseService.deleteArticle(id);
    _exercisesByArticle.remove(id);
    await loadArticles();
  }
}

extension ArticleCopy on Article {
  Article copyWith({int? id}) {
    return Article(
      id: id ?? this.id,
      title: title,
      content: content,
      vocabIds: vocabIds,
      createdAt: createdAt,
    );
  }
}
