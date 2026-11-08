/// 阅读器「追问材料」的材料上下文构建（纯函数，可单测）。
///
/// 为什么单独抽出来（2026-11-08 用户反馈 / task-21 A1）：
/// 旧实现直接写在阅读器 State 里，按"整块拼接、超过 6000 字符就 break"：
/// ```dart
/// for (final c in _chunks) {
///   final t = c.text;
///   if (body.length + t.length > 6000) break;   // ← 第一块就超大时直接 break
///   body.writeln(t);
/// }
/// ```
/// 而正文按 **2500 词一块**入库：一篇 2011 词的材料只有 1 块、约 1.2 万字符，
/// 第一次循环就 break → body 为空 → AI 收到的 system 里只有「正文节选:」这行
/// 标题，于是真机回复"正文节选是空的，只有标题和元信息"。用户截图原话。
///
/// 现在的口径：
/// 1. **保证非空**：任何一块有文字，输出里就一定有正文（按字符截断，不按块 break）；
/// 2. **优先当前小节**：整篇追问时先给用户正在读的那一节（最多 4000 字），
///    再补全文开头 2000 字 —— 问"这里/这节"时模型拿到的就是眼前内容；
/// 3. 单段追问（点译文）分支保持原口径：本段原文 + 页面译文 + 前后各一段。
library;

/// 单块正文截断上限（当前小节）
const int _kCurrentSectionChars = 4000;

/// 全文开头补充分上限
const int _kArticleHeadChars = 2000;

/// 单段追问里本段/译文的截断上限
const int _kPinnedUnitChars = 2000;

/// 单段追问里相邻段的截断上限
const int _kNeighborChars = 800;

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

/// 构建「追问材料」的上下文。
///
/// - [title]/[sourceUrl]/[difficultyLine]：材料元信息（difficultyLine 可为空）；
/// - [chunkTitles]/[chunkTexts]：按块（章节）的标题与正文；
/// - [unitTexts]：按真段落拆出的单元正文（`chunkTexts` 为空时的兜底）；
/// - [translations]：单元下标 → 页面上的中文译文；
/// - [pinnedUnit]：非空 = 「点译文追问这一段」，只喂这一段及其邻段；
/// - [pinnedChunk]：单段追问时该段所属小节（用于带小标题）；
/// - [currentChunk]：整篇追问时优先喂用户正在读的那一节。
String buildReaderFollowUpContext({
  required String title,
  required String sourceUrl,
  required String difficultyLine,
  required List<String> chunkTitles,
  required List<String> chunkTexts,
  required List<String> unitTexts,
  required Map<int, String> translations,
  int? pinnedUnit,
  int? pinnedChunk,
  int? currentChunk,
}) {
  final head = StringBuffer()
    ..writeln('材料:$title')
    ..writeln('来源:${sourceUrl.trim().isEmpty ? '（无链接）' : sourceUrl.trim()}');
  if (difficultyLine.trim().isNotEmpty) head.writeln(difficultyLine.trim());

  // ── 单段追问（点译文）──
  final at = pinnedUnit;
  if (at != null && at >= 0 && at < unitTexts.length) {
    final unit = unitTexts[at].trim();
    final previous = at > 0 ? unitTexts[at - 1].trim() : '';
    final next = at + 1 < unitTexts.length ? unitTexts[at + 1].trim() : '';
    final subtitle = (pinnedChunk != null &&
            pinnedChunk >= 0 &&
            pinnedChunk < chunkTitles.length)
        ? chunkTitles[pinnedChunk].trim()
        : '';
    final translation = translations[at];
    final body = StringBuffer()
      ..writeln('这次追问只针对第 ${at + 1}/${unitTexts.length} 段。');
    if (subtitle.isNotEmpty) body.writeln('小标题:$subtitle');
    if (previous.isNotEmpty) {
      body
        ..writeln('\n上一段原文(只用于理解指代/术语,不要翻译):')
        ..writeln(_clip(previous, _kNeighborChars));
    }
    body
      ..writeln('\n本段原文:')
      ..writeln(_clip(unit, _kPinnedUnitChars));
    if (translation != null && translation.trim().isNotEmpty) {
      body
        ..writeln('\n页面上的中文译文:')
        ..writeln(_clip(translation, _kPinnedUnitChars));
    } else {
      body.writeln('\n页面上的这一段还没有中文译文。');
    }
    if (next.isNotEmpty) {
      body
        ..writeln('\n下一段原文(只用于理解指代/术语,不要翻译):')
        ..writeln(_clip(next, _kNeighborChars));
    }
    return '${head.toString()}\n$body';
  }

  // ── 整篇追问 ──
  final body = StringBuffer();
  final current = currentChunk;
  if (current != null &&
      current >= 0 &&
      current < chunkTexts.length &&
      chunkTexts[current].trim().isNotEmpty) {
    final sectionTitle =
        current < chunkTitles.length ? chunkTitles[current].trim() : '';
    body.writeln('\n【当前在读小节${sectionTitle.isEmpty ? '' : ':$sectionTitle'}】');
    body.writeln(_clip(chunkTexts[current].trim(), _kCurrentSectionChars));
  }

  // 全文开头：给模型"这篇文章在讲什么"的锚点（当前节就是第一节时不重复喂）
  final articleHead = chunkTexts
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .join('\n\n');
  if (articleHead.isNotEmpty && current != 0) {
    body.writeln('\n【全文开头节选】');
    body.writeln(_clip(articleHead, _kArticleHeadChars));
  }

  // 兜底 1：块正文为空（老数据/异常）→ 用段落单元拼
  if (body.isEmpty || body.toString().trim().isEmpty) {
    final joined =
        unitTexts.map((t) => t.trim()).where((t) => t.isNotEmpty).join('\n\n');
    if (joined.isNotEmpty) {
      body
        ..writeln('\n【全文开头节选】')
        ..writeln(_clip(joined, _kArticleHeadChars));
    }
  }

  // 兜底 2：真的没有正文 —— 明确写出来，别让模型以为"正文被吞了"
  if (body.isEmpty || body.toString().trim().isEmpty) {
    body.writeln('\n【正文暂未读取到】这份材料目前没有可用的正文文本，'
        '请只基于上面的元信息回答，并提醒用户正文可能未加载完成。');
  }

  return '${head.toString()}\n正文节选:\n$body';
}
