import '../config/placement_bank.dart';

/// 词汇量测试「完整版」语法分项诊断(E1-10,v2.23)。
///
/// ## 为什么单独抽一层
/// 完整版只把语法结果存成一个 `grammar_score`(见 placement_test_screen 的
/// `last_placement`)。一个总分既进不了错误档案(没有分项标签),也进不了助理
/// 的"语法薄弱点"诊断 —— 用户只知道"语法 60 分",不知道是时态还是冠词。
/// 这里把"哪些错题要记成哪一类薄弱点"做成**纯函数**:
/// - 屏幕只负责调用 + 写库(`DatabaseService.bumpErrorTag`),不自己算;
/// - 单测可以直接用假作答断言分项的选取与去重规则。
///
/// ## 口径(与 OutputFeedback 的错误回流一致)
/// - 只记**答错**的题;未作答(null)不算错 —— 没作答不等于掌握,但也不能凭空
///   给人扣一顶"薄弱"的帽子(正常流程里答完才允许下一题,所以也到不了这步);
/// - 按题目标签去重:同一类考点错两题只记一次(`+1`),错误档案回答的是
///   "这个坑反复踩了几次",不是"这张卷子错了几个空";
/// - 证据取该类**第一道错题的题干**,错误档案里能回想起是哪题。
///
/// 返回 `tag → evidence`;顺序按题目顺序(同分项取第一次出现)。
Map<String, String> grammarErrorTags({
  required List<ChoiceQuestion> questions,
  required List<int?> answers,
}) {
  final out = <String, String>{};
  for (var i = 0; i < questions.length; i++) {
    final q = questions[i];
    final picked = i < answers.length ? answers[i] : null;
    if (picked == null) continue; // 未作答:不记薄弱点
    if (picked == q.answerIndex) continue; // 答对:不是薄弱点
    out.putIfAbsent(q.tag, () => q.prompt);
  }
  return out;
}
