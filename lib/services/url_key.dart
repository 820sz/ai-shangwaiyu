/// URL 归一去重键 —— **全库唯一实现**（P2-9，2026-11-06）。
///
/// 历史上有两套：
/// - `material_channel.dart` 的 `normalizedUrlKey`（去协议/锚点/utm_*，不处理尾斜杠）；
/// - `material_discovery.dart` 的 `dedupeKeyOf`（只去 http(s)/锚点/utm_/ref/source，去尾斜杠）。
/// 两套规则不同 → 同一条 URL 在"发现去重"和"快照/保存关系"里可能得到不同 key，
/// 表现为"继续找更多"把同一篇又堆出来、或保存关系对不上材料。现统一到这里，
/// 两个旧名字都改为引用本函数（保留名字只为兼容现有调用方与测试）。
///
/// 归一规则（都可解释，错一点就会误合并/漏合并）：
/// 1. 小写（域名本身大小写不敏感，路径大小写差异在真实站点里几乎不表示不同文章）；
/// 2. 去协议（http/https 混用的同一篇算同一篇）；
/// 3. 去锚点（`#section` 不改变内容）；
/// 4. 去纯跟踪参数（`utm_*` / `ref` / `source` / `fbclid` / `gclid` / `spm`）；
///    **其余参数一律保留**（`?id=1&page=2` 是内容身份的一部分）；
/// 5. 去尾部斜杠（`/a/` 与 `/a` 是同一篇）；
/// 6. 空串/纯空白 → `''`（调用方据此判"没有 url"）。
String normalizedUrlKey(String raw) {
  var key = raw.trim().toLowerCase();
  if (key.isEmpty) return '';

  // 协议不参与身份比较
  key = key.replaceFirst(RegExp(r'^[a-z][a-z0-9+.\-]*://'), '');

  // 锚点不改变内容
  final hash = key.indexOf('#');
  if (hash >= 0) key = key.substring(0, hash);

  // 拆 path / query：尾斜杠只对 path 处理，query 里的 `/` 不能动
  final q = key.indexOf('?');
  var path = q < 0 ? key : key.substring(0, q);
  final query = q < 0 ? '' : key.substring(q + 1);
  path = path.replaceFirst(RegExp(r'/+$'), '');
  if (query.isEmpty) return path;

  const noiseNames = <String>{'ref', 'source', 'fbclid', 'gclid', 'spm'};
  final kept = <String>[];
  for (final piece in query.split('&')) {
    if (piece.isEmpty) continue;
    final cut = piece.indexOf('=');
    final name = cut < 0 ? piece : piece.substring(0, cut);
    if (name.startsWith('utm_') || noiseNames.contains(name)) continue;
    kept.add(piece);
  }
  return kept.isEmpty ? path : '$path?${kept.join('&')}';
}

/// 两条 URL 是否是"同一篇"（按 [normalizedUrlKey] 口径；空 URL 不相等）。
bool isSameUrl(String a, String b) {
  final ka = normalizedUrlKey(a);
  if (ka.isEmpty) return false;
  return ka == normalizedUrlKey(b);
}
