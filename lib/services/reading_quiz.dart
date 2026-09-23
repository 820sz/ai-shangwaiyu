import 'dart:math';

/// 读后测验生成器(v2.0)—— **纯函数、无 IO、不调 AI**。
///
/// 设计原则(对应 PLAN-2.0 §6 的"读后动作"):
/// - 题目**从材料原文里出**:完形填空的句子就是用户刚读过的句子,
///   干扰项也从同一份材料的生词里取 → 测的是"这篇你读懂了吗",
///   而不是另出一套无关的题;
/// - **本地生成**:出题不需要花钱、离线可用、同一份材料每次出的题可复现
///   (由 seed 决定),便于复盘("上次错的还是这几个词");
/// - 输出与评分都落在 `quiz_results`(v2.0 已建表),错题进错误档案与复习队列。
///
/// 已知取舍:不生成"理解类"主观题(那需要 AI);这一版只做两件能客观评分的事:
/// **完形填空**(语境中的词义/搭配)与**中译英回想**(主动回忆)。
class QuizQuestion {
  /// cloze = 句子挖空选词;recall = 看中文写英文
  final String kind;
  final String prompt;
  final List<String> options;
  final int answerIndex;
  final String answer;
  final String sourceWord;

  /// 出题所依据的原句(结果页用来"回看语境")
  final String? contextSentence;

  const QuizQuestion({
    required this.kind,
    required this.prompt,
    required this.answer,
    required this.sourceWord,
    this.options = const [],
    this.answerIndex = -1,
    this.contextSentence,
  });

  bool get isCloze => kind == 'cloze';

  /// 判断一个作答是否正确(recall 允许大小写/首尾空白差异)
  bool isCorrect(String? given) {
    if (given == null) return false;
    final g = given.trim().toLowerCase();
    if (g.isEmpty) return false;
    if (isCloze) return options.isNotEmpty && answerIndex >= 0 && options[answerIndex].toLowerCase() == g;
    return answer.trim().toLowerCase() == g;
  }
}

class ReadingQuiz {
  ReadingQuiz._();

  /// 完形填空的词长下限:太短的词(3 字母以下)挖空后句子几乎无法推断,
  /// 而且常见功能词(and/the)会让干扰项区分度太低
  static const int minClozeWordLength = 4;

  /// 句子长度区间:太短没有语境,太长读起来像考试
  static const int minSentenceChars = 40;
  static const int maxSentenceChars = 220;

  /// 生成读后测验。
  /// - [text] 材料全文(或前若干块的拼接)
  /// - [targetWords] 优先出题的词(用户拾取的生词 + 本材料的高频生词)
  /// - [translations] 词 → 中文释义(有则额外生成"中译英"回想题)
  static List<QuizQuestion> build({
    required String text,
    required List<String> targetWords,
    Map<String, String> translations = const {},
    int maxQuestions = 5,
    int seed = 1,
  }) {
    final rng = Random(seed);
    final targets = <String>[];
    for (final w in targetWords) {
      final t = w.trim().toLowerCase();
      if (t.isEmpty || targets.contains(t)) continue;
      if (!RegExp(r'^[a-z]+$').hasMatch(t)) continue;
      targets.add(t);
    }
    if (targets.isEmpty || text.trim().isEmpty) return const [];

    final sentences = splitSentences(text);
    final out = <QuizQuestion>[];

    // ── ① 完形填空:优先用"含目标词"的原句 ──
    final usedWords = <String>{};
    final usedSentences = <String>{};
    for (final w in targets) {
      if (out.length >= maxQuestions) break;
      if (w.length < minClozeWordLength) continue;
      final pattern = RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false);
      String? sentence;
      for (final s in sentences) {
        if (usedSentences.contains(s)) continue;
        if (pattern.hasMatch(s)) {
          sentence = s;
          break;
        }
      }
      if (sentence == null) continue;
      final blanked = sentence.replaceAll(pattern, '______');
      final distractors = _pickDistractors(
        answer: w,
        pool: targets,
        rng: rng,
        count: 3,
      );
      if (distractors.length < 3) continue; // 干扰项不够就不出这题(宁缺毋滥)
      final options = [w, ...distractors]..shuffle(rng);
      out.add(QuizQuestion(
        kind: 'cloze',
        prompt: blanked,
        options: options,
        answerIndex: options.indexOf(w),
        answer: w,
        sourceWord: w,
        contextSentence: sentence,
      ));
      usedWords.add(w);
      usedSentences.add(sentence);
    }

    // ── ② 中译英回想:有中文释义的目标词 ──
    for (final w in targets) {
      if (out.length >= maxQuestions) break;
      if (usedWords.contains(w)) continue;
      final zh = (translations[w] ?? '').trim();
      if (zh.isEmpty) continue;
      out.add(QuizQuestion(
        kind: 'recall',
        prompt: '用英文表达:$zh',
        answer: w,
        sourceWord: w,
      ));
    }

    return out.take(maxQuestions).toList();
  }

  /// 挑干扰项:优先与答案**同长度区间**的词(越长越像),不足则放宽
  static List<String> _pickDistractors({
    required String answer,
    required List<String> pool,
    required Random rng,
    required int count,
  }) {
    final others = pool
        .where((w) => w != answer && w.length >= minClozeWordLength)
        .toList()
      ..shuffle(rng);
    final near = others.where((w) => (w.length - answer.length).abs() <= 2).toList();
    final far = others.where((w) => (w.length - answer.length).abs() > 2).toList();
    final picked = <String>[];
    for (final w in [...near, ...far]) {
      if (picked.length >= count) break;
      if (picked.contains(w)) continue;
      picked.add(w);
    }
    return picked;
  }

  /// 句子切分(纯函数):按 . ! ? 加空白切,丢掉过短/过长的句子。
  /// 不做缩写消歧(Dr. / U.S.)—— 读后测验不需要那么精确,
  /// 但要把结果过滤到"适合挖空的长度"。
  static List<String> splitSentences(String text) {
    final out = <String>[];
    final normalized = text.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\s+'), ' ');
    final matches = RegExp(r'[^.!?]+[.!?]+').allMatches(normalized);
    for (final m in matches) {
      final s = m.group(0)!.trim();
      if (s.length < minSentenceChars || s.length > maxSentenceChars) continue;
      // 至少要有 6 个词才值得挖空
      if (s.split(' ').length < 6) continue;
      out.add(s);
    }
    return out;
  }

  /// 评分:返回正确题数(未作答按错处理)
  static int grade(List<QuizQuestion> questions, List<String?> answers) {
    var ok = 0;
    for (var i = 0; i < questions.length; i++) {
      if (questions[i].isCorrect(i < answers.length ? answers[i] : null)) ok++;
    }
    return ok;
  }

  /// 错题涉及的词(用于更新复习状态与错误档案)
  static List<String> wrongWords(
    List<QuizQuestion> questions,
    List<String?> answers,
  ) {
    final out = <String>[];
    for (var i = 0; i < questions.length; i++) {
      final given = i < answers.length ? answers[i] : null;
      if (!questions[i].isCorrect(given)) out.add(questions[i].sourceWord);
    }
    return out;
  }

  /// 结果一句话(给界面直接显示)
  static String summary(int correct, int total) {
    if (total <= 0) return '这次没有生成题目';
    final rate = correct / total;
    if (rate >= 0.99) return '$correct/$total —— 这篇材料你是真读懂了';
    if (rate >= 0.7) return '$correct/$total —— 大意抓住了,错的那几个词回看一下';
    if (rate >= 0.4) return '$correct/$total —— 读懂了一半,建议降低材料难度再读一遍';
    return '$correct/$total —— 这篇对你偏难,换一份覆盖率更高的材料更划算';
  }
}
