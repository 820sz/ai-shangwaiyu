import '../models/vocabulary.dart';

/// 补充识别结果合并(纯函数,可单测)— v1.3.0 问题 3。
///
/// 把 [fresh](AI 对全图再次识别的结果)并入 [existing](当前展示的词汇),
/// 按 (word 忽略大小写, wordType) 去重——同一词条补充识别重复返回时只保留
/// 原有条目,只有真正遗漏的新词才追加。原顺序保持:旧结果在前,新词在后。
List<Vocabulary> mergeSupplementResults(
  List<Vocabulary> existing,
  List<Vocabulary> fresh,
) {
  final existingKeys = {
    for (final v in existing) '${v.word.toLowerCase()}|${v.wordType}',
  };
  final merged = [...existing];
  for (final r in fresh) {
    final key = '${r.word.toLowerCase()}|${r.wordType}';
    if (!existingKeys.contains(key)) {
      existingKeys.add(key);
      merged.add(r);
    }
  }
  return merged;
}
