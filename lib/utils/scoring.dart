/// 回译练习评分(纯函数,可单测)。
///
/// 新练习:参考为英文原句 → 词集合重叠率 ≥0.5 算对。
/// 旧练习:DB 无英文参考,参考是中文题面 → 长度启发式(估算)。
double scoreBackTranslation(
    List<String?> answers, List<String> references) {
  if (references.isEmpty) return 0;
  int matched = 0;
  for (int i = 0; i < answers.length && i < references.length; i++) {
    final user = answers[i]?.trim() ?? '';
    final ref = references[i].trim();
    if (user.isEmpty || ref.isEmpty) continue;

    final ratio = _looksEnglish(ref)
        ? _overlapRatio(user, ref)
        : (user.length >= ref.length * 0.3 ? 1 : 0);
    if (ratio >= 0.5) matched++;
  }
  return matched / references.length * 100;
}

/// 小写 + 去标点 → 词集合(评分用)
Set<String> _wordSet(String text) {
  final cleaned = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  return cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
}

double _overlapRatio(String user, String ref) {
  final u = _wordSet(user);
  final r = _wordSet(ref);
  if (r.isEmpty || u.isEmpty) return 0;
  return u.intersection(r).length / r.length;
}

/// 参考句含英文字母 → 视为英文参考答案
bool _looksEnglish(String text) => RegExp(r'[a-zA-Z]').hasMatch(text);
