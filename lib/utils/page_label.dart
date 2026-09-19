/// 页码/章节输入的智能归一(v1.8.0)。
///
/// 用户实测问题:填「p9页」被录成「pp9页」,只有填「9」才对;同一本书里
/// 页码格式也乱七八糟(有带 p、有不带 p)。这里把各种写法统一成 `p9` 样式。
///
/// 规则:
/// - 去掉「第/页/頁」与多余空格
/// - 前缀 p/P 归一为单个小写 p
/// - `p9页` / `第9页` / `9` / `P 9` → `p9`
/// - `p9-12` / `p9~12` / `第9至12页` → `p9-12`
/// - `p16 p17` / `p16,p17` → 连续数字压缩成 `p16-17`,否则 `p16,p20`
/// - 非数字内容(如「序章」「前言」)原样保留(仅去首尾空白)
String normalizePageLabel(String raw) {
  final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return '';

  // 统一范围分隔符
  final unified = trimmed
      .replaceAll(RegExp(r'[~～–—−]'), '-')
      .replaceAll('至', '-')
      .replaceAll('到', '-');

  final tokens = unified
      .split(RegExp(r'[,\uFF0C;；、/|]+'))
      .expand((t) => t.split(' '))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty);

  final labels = <String>[];
  for (final token in tokens) {
    // 去掉所有 p/P/第/页/頁 等装饰字符,只留数字与连字符
    var s = token.replaceAll(RegExp(r'[pP第页頁]'), '');
    s = s.replaceAll(RegExp(r'[^0-9\-]'), '');
    s = s.replaceAll(RegExp(r'-+'), '-');
    s = s.replaceAll(RegExp(r'^-+|-+$'), '');
    if (s.isEmpty) continue;
    labels.add('p$s');
  }

  if (labels.isEmpty) {
    // 没有数字:非页码内容(序章/前言/Chapter One…)原样保留
    return trimmed;
  }
  return _compressConsecutive(labels);
}

/// `['p16','p17','p18']` → `'p16-18'`;不连续则逗号连接
String _compressConsecutive(List<String> labels) {
  final nums = <int>[];
  for (final l in labels) {
    final m = RegExp(r'^p(\d+)$').firstMatch(l);
    if (m == null) return labels.join(','); // 含范围/非数字 → 不压缩
    nums.add(int.parse(m.group(1)!));
  }
  nums.sort();
  final unique = <int>[];
  for (final n in nums) {
    if (unique.isEmpty || unique.last != n) unique.add(n);
  }
  if (unique.length == 1) return 'p${unique.first}';
  var consecutive = true;
  for (int i = 1; i < unique.length; i++) {
    if (unique[i] != unique[i - 1] + 1) {
      consecutive = false;
      break;
    }
  }
  if (consecutive) return 'p${unique.first}-${unique.last}';
  return unique.map((n) => 'p$n').join(',');
}
