import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'deepseek_api.dart';
import 'html_text.dart';
import 'material_source.dart';

/// 材料导入的三条通道(v2.7,用户第 2(4) 条)。
///
/// 用户原话:"材料中心的外部资源导入问题 —— 要支持各种格式啊,不管是文件、
/// 图片(图片就走一次 ai 提取)、链接都要支持呀,而不是现在的'标题、内容'"。
///
/// 本层只做**"外部东西 → MaterialDoc"** 这一段(纯逻辑,可单测):
/// - 文件:纯文本类(`.txt/.md/.markdown/.srt/.vtt/.csv/.tsv/.json/.log`)直接读,
///   `.html/.htm` 走 [HtmlText.readableText] 抽正文;PDF/EPUB/DOCX 明确拒绝
///   (用户 2026-09-29 选定:本批只做纯文本类,不引解析库);
/// - 图片:文字由 AI 提取(在 `doubao_api.extractFullTextStream`),这里只负责
///   把提取结果包成文档、并**如实标注这是 AI 提取的文字**;
/// - 链接:交给 [MaterialSourceService.fetchAnyUrl] 抓正文,这里只做包装。
///
/// 三条通道最后都汇到同一个 [MaterialDoc],于是入库、难度分析、阅读器、
/// 「我的学习材料」全都复用同一条管线 —— 不为"导入"再写一套阅读逻辑。
class MaterialImport {
  MaterialImport._();

  /// 纯文本类扩展名(能直接当正文读)
  static const Set<String> textExtensions = {
    'txt', 'text', 'md', 'markdown', 'srt', 'vtt', 'csv', 'tsv',
    'json', 'log', 'rtf',
  };

  /// 抽正文的扩展名(HTML 系)
  static const Set<String> htmlExtensions = {'html', 'htm', 'xhtml'};

  /// 明确暂不支持、且要**说清原因**的扩展名
  static const Set<String> unsupportedExtensions = {
    'pdf', 'epub', 'mobi', 'azw3', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx',
  };

  /// 文件是否可导入(纯文本类或 HTML 系)
  static bool isSupportedFile(String fileName) {
    final ext = extensionOf(fileName);
    return textExtensions.contains(ext) || htmlExtensions.contains(ext);
  }

  /// 小写扩展名(无扩展名 → 空串)
  static String extensionOf(String fileName) {
    final name = fileName.trim();
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// 用文件名当标题(去掉扩展名;全空时给"未命名材料")
  static String titleFromFileName(String fileName) {
    var base = fileName.trim();
    final slash = base.lastIndexOf(RegExp(r'[/\\]'));
    if (slash >= 0) base = base.substring(slash + 1);
    final ext = extensionOf(base);
    if (ext.isNotEmpty) base = base.substring(0, base.length - ext.length - 1);
    base = base.replaceAll(RegExp(r'[_\s]+'), ' ').trim();
    return base.isEmpty ? '未命名材料' : base;
  }

  /// 解码文本文件字节。
  ///
  /// 顺序:去 BOM → 严格 UTF-8 → 宽松 UTF-8。宽松模式下如果替换字符占比很高
  /// (说明这多半是 GBK/GB18030 编码的中文文件,而 Dart 标准库没有 GBK 解码器),
  /// 返回 [DecodedText.warning] 让界面如实提示,而不是把一屏乱码当材料入库。
  static DecodedText decodeTextBytes(Uint8List bytes) {
    if (bytes.isEmpty) return const DecodedText('', '');
    var data = bytes;
    // UTF-8 BOM
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      data = Uint8List.sublistView(data, 3);
    }
    try {
      return DecodedText(utf8.decode(data), '');
    } catch (e) {
      debugPrint('ReadFlow 文件不是严格 UTF-8,改用宽松解码: $e');
    }
    final loose = utf8.decode(data, allowMalformed: true);
    final bad = '�'.allMatches(loose).length;
    final warning = (loose.isNotEmpty && bad / loose.length > 0.02)
        ? '这个文件不是 UTF-8 编码(可能是 GBK),读出来会是乱码 —— '
            '建议另存为 UTF-8 再导入,或直接复制文本用「粘贴材料」'
        : '';
    return DecodedText(loose, warning);
  }

  /// ① 文件 → 材料文档
  static MaterialDoc fromFileText({
    required String fileName,
    required String text,
    String? title,
  }) {
    final isHtml = htmlExtensions.contains(extensionOf(fileName));
    final body = isHtml ? HtmlText.readableText(text) : text;
    final cleaned = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (cleaned.isEmpty) {
      throw const MaterialSourceException(
        sourceLabel: '文件导入',
        message: '这个文件里没有可读的文字(空文件,或正文没被解析出来)',
      );
    }
    final finalTitle = (title ?? '').trim().isNotEmpty
        ? title!.trim()
        : titleFromFileName(fileName);
    final chunks = MaterialSourceService.chunkByWords(cleaned, wordsPerChunk: 2500);
    return MaterialDoc(
      sourceId: 'file',
      sourceId2: fileName.trim(),
      kind: 'article',
      title: finalTitle,
      url: '',
      license: '你导入的自备文件,仅限个人学习使用',
      language: _guessLanguage(cleaned),
      chunks: chunks,
      plainText: chunks.map((c) => c.text).join('\n\n'),
    );
  }

  /// ③ 图片经 AI 提取出的文字 → 材料文档
  ///
  /// 许可说明里**如实写清"AI 提取,可能有识别误差"**:这份正文不是原书原文,
  /// 用户有权知道 (与 v2.4 起"AI 整理内容必须标注"的立场一致)。
  static MaterialDoc fromImageText({
    required String text,
    String? title,
    String? sourceHint,
  }) {
    final cleaned = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (cleaned.isEmpty) {
      throw const MaterialSourceException(
        sourceLabel: '图片提取',
        message: 'AI 没有从这张图里提取到文字 —— 换一张更清晰的图,或改用「粘贴材料」',
      );
    }
    final finalTitle = (title ?? '').trim().isNotEmpty
        ? title!.trim()
        : '图片材料 ${_stamp(DateTime.now())}';
    final chunks = MaterialSourceService.chunkByWords(cleaned, wordsPerChunk: 2500);
    return MaterialDoc(
      sourceId: 'image',
      sourceId2: '${finalTitle}_${DateTime.now().millisecondsSinceEpoch}',
      kind: 'article',
      title: finalTitle,
      url: '',
      license: '由你的图片经 AI 提取的文字(${sourceHint ?? '可能有个别识别误差'}),'
          '仅限个人学习使用',
      language: _guessLanguage(cleaned),
      chunks: chunks,
      plainText: chunks.map((c) => c.text).join('\n\n'),
    );
  }

  /// ④ 链接 → 材料文档(抓取交给 [MaterialSourceService.fetchAnyUrl])
  static Future<MaterialDoc> fromUrl(String url, {String? title}) =>
      MaterialSourceService.instance.fetchAnyUrl(url, titleHint: title);

  /// 按链接**自动选抓取方式**(v2.7)。
  ///
  /// 为什么需要:同一个链接可能是"一本公版书的书目页"或"一篇论文的摘要页",
  /// 通用网页抽取只能拿到导航文字;识别出是 Gutenberg / arXiv 就走专用抓取
  /// (公版书能拿到全文、论文能拿到摘要),用户贴同一个链接得到的东西完全不同。
  /// 识别不出来才回落通用网页正文。
  static Future<MaterialDoc> fromAnyUrl(String url, {String? title}) async {
    final svc = MaterialSourceService.instance;
    final bookId = MaterialSourceService.gutenbergIdOf(url);
    if (bookId != null) return svc.fetchGutenberg(bookId);
    final arxivId = MaterialSourceService.arxivIdOf(url);
    if (arxivId != null) return svc.fetchArxiv(arxivId);
    return svc.fetchAnyUrl(url, titleHint: title);
  }

  /// 把英文标题补成「中文(英文)」(v2.7,用户第 2(2) 条:
  /// "提供的材料标题都要按照「中文(英文)」的格式,这样才能方便用户学习")。
  ///
  /// AI 没配 / 翻不出来 → **保持原标题**:绝不允许"翻译失败"挡住材料导入。
  /// 已经是「中文(英文)」或纯中文标题就直接返回,不重复翻译。
  static Future<String> localizedTitle(String rawTitle) async {
    final t = rawTitle.trim();
    if (t.isEmpty) return t;
    if (RegExp(r'[（(].+[）)]$').hasMatch(t) ||
        !RegExp(r'[A-Za-z]').hasMatch(t)) {
      return t;
    }
    try {
      final api = DeepseekApiService();
      if (!api.isConfigured) return t;
      final map = await api.translateTitles([t]);
      final cn = map[t]?.trim() ?? '';
      if (cn.isEmpty || cn == t) return t;
      return '$cn（$t）';
    } catch (e) {
      debugPrint('ReadFlow 标题中文化失败(保持原样): $e');
      return t;
    }
  }

  /// 粗判语言(只分中英):中文占比高就当 zh —— 阅读器的取词/音标逻辑按它决定
  /// 要不要给"中文批注"留位置
  static String _guessLanguage(String text) {
    if (text.isEmpty) return 'en';
    var cjk = 0;
    for (final r in text.runes) {
      if (r >= 0x4E00 && r <= 0x9FFF) cjk++;
    }
    return cjk / text.runes.length > 0.3 ? 'zh' : 'en';
  }

  static String _stamp(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// 解码结果:文本 + 要不要给用户一句提示(空串 = 没问题)
class DecodedText {
  final String text;
  final String warning;
  const DecodedText(this.text, this.warning);

  bool get hasWarning => warning.isNotEmpty;
}
