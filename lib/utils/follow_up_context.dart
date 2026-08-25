import '../models/vocabulary.dart';

/// 构建追问默认上下文(纯函数,可单测)。
///
/// 背景(v1.3.0 问题 5 修复):原实现只拼接"已识别词汇"列表——
/// 全文翻译模式下词汇为空,AI 收到空上下文,回答"没有收到上传的
/// 具体页面图片或文字内容"(用户真机截图实锤)。
///
/// 现在补全三类信息:
/// 1. 已识别词汇(word/释义/类型/出处例句)
/// 2. 页面全文翻译(原文+译文段落)
/// 3. 图片由调用方以多模态消息附带([DoubaoApiService.followUpStream])
String buildFollowUpContext({
  required List<Vocabulary> results,
  required List<Map<String, String>> paragraphs,
}) {
  final ctx = StringBuffer();

  if (results.isNotEmpty) {
    ctx.writeln('已识别的词汇：');
    for (final v in results) {
      final sb = StringBuffer('- ${v.word}: ${v.translation ?? ""} (${v.wordType})');
      if (v.originalSentence != null && v.originalSentence!.isNotEmpty) {
        sb.write(' 例句：${v.originalSentence}');
      }
      ctx.writeln(sb.toString());
    }
  }

  if (paragraphs.isNotEmpty) {
    if (results.isNotEmpty) ctx.writeln();
    ctx.writeln('页面全文翻译：');
    for (final p in paragraphs) {
      ctx.writeln('原文：${p['original'] ?? ''}');
      ctx.writeln('译文：${p['translation'] ?? ''}');
    }
  }

  return ctx.toString();
}
