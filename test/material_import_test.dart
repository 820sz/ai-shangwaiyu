import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/material_import.dart';
import 'package:readflow/services/material_source.dart';

/// v2.7 材料导入三条通道的单测(用户第 2(4) 条:文件 / 图片 / 链接)。
///
/// 重点测**纯逻辑**:扩展名判定、文本解码、URL 规整、文档组装。
/// 网络抓取与图片 OCR 不在这里测(它们要么依赖外网、要么依赖模型),
/// 但那两条路的"包装与兜底"逻辑(标题、许可标注、空内容报错)都在这里钉死。
void main() {
  group('文件类型判定', () {
    test('纯文本类与 HTML 系可导入', () {
      for (final n in [
        'a.txt', 'a.md', 'a.MARKDOWN', 'sub/b.srt', 'c.csv', 'd.json',
        'e.html', 'f.htm', 'g.xhtml',
      ]) {
        expect(MaterialImport.isSupportedFile(n), isTrue, reason: n);
      }
    });

    test('PDF/EPUB/DOCX 明确不支持(要能说清原因,而不是静默失败)', () {
      for (final ext in ['pdf', 'epub', 'mobi', 'doc', 'docx', 'ppt', 'xlsx']) {
        expect(MaterialImport.unsupportedExtensions.contains(ext), isTrue);
        expect(MaterialImport.isSupportedFile('x.$ext'), isFalse);
      }
    });

    test('无扩展名 / 奇怪文件名不崩', () {
      expect(MaterialImport.extensionOf('README'), '');
      expect(MaterialImport.extensionOf('a.'), '');
      expect(MaterialImport.extensionOf(''), '');
      expect(MaterialImport.isSupportedFile('README'), isFalse);
    });
  });

  group('标题推断', () {
    test('去扩展名 + 下划线转空格 + 去路径', () {
      expect(MaterialImport.titleFromFileName('pride_and_prejudice.txt'),
          'pride and prejudice');
      expect(MaterialImport.titleFromFileName(r'C:\x\y\My Book.md'), 'My Book');
      expect(MaterialImport.titleFromFileName('/storage/a/b.srt'), 'b');
    });

    test('空标题回落"未命名材料"(材料库不能出现空白条目)', () {
      expect(MaterialImport.titleFromFileName('.txt'), '未命名材料');
      expect(MaterialImport.titleFromFileName('   '), '未命名材料');
    });
  });

  group('文本解码', () {
    test('UTF-8(带 BOM)正常解码且不留 BOM', () {
      final bytes = Uint8List.fromList([
        0xEF, 0xBB, 0xBF,
        ...utf8.encode('Hello 世界'),
      ]);
      final d = MaterialImport.decodeTextBytes(bytes);
      expect(d.text, 'Hello 世界');
      expect(d.hasWarning, isFalse);
    });

    test('空文件返回空文本', () {
      expect(MaterialImport.decodeTextBytes(Uint8List(0)).text, '');
    });

    test('非 UTF-8(GBK 中文)给出乱码警告,而不是把乱码当材料', () {
      // "中文" 的 GBK 编码是 D6 D0 CE C4 —— 不是合法 UTF-8 序列
      final gbk = Uint8List.fromList([0xD6, 0xD0, 0xCE, 0xC4]);
      final d = MaterialImport.decodeTextBytes(gbk);
      expect(d.hasWarning, isTrue);
      expect(d.warning, contains('UTF-8'));
    });
  });

  group('文件 → 材料文档', () {
    test('纯文本:标题取文件名、块切好、语言判为 en', () {
      final doc = MaterialImport.fromFileText(
        fileName: 'my_article.txt',
        text: 'The quick brown fox jumps over the lazy dog.\n\nSecond paragraph here.',
      );
      expect(doc.title, 'my article');
      expect(doc.sourceId, 'file');
      expect(doc.sourceId2, 'my_article.txt');
      expect(doc.chunks, isNotEmpty);
      expect(doc.language, 'en');
      expect(doc.wordCount, greaterThan(5));
    });

    test('HTML 文件走正文抽取(标签不会混进材料)', () {
      final doc = MaterialImport.fromFileText(
        fileName: 'page.html',
        text: '<html><head><title>T</title></head><body>'
            '<script>var x=1;</script><p>Real content here.</p>'
            '<nav><a href="/x">menu</a></nav></body></html>',
      );
      expect(doc.plainText, contains('Real content here.'));
      expect(doc.plainText, isNot(contains('var x=1')));
      expect(doc.plainText, isNot(contains('<p>')));
    });

    test('空文件抛可读异常(中文原因,不是空文档)', () {
      expect(
        () => MaterialImport.fromFileText(fileName: 'empty.txt', text: '   \n  '),
        throwsA(isA<MaterialSourceException>()),
      );
    });

    test('中文正文判为 zh(阅读器据此决定批注处理)', () {
      final doc = MaterialImport.fromFileText(
        fileName: 'cn.txt',
        text: '这是一段中文材料,用来验证语言判定逻辑是否按中文比例走。',
      );
      expect(doc.language, 'zh');
    });
  });

  group('图片提取文本 → 材料文档', () {
    test('标题缺省时按日期命名,许可里写明"AI 提取"', () {
      final doc = MaterialImport.fromImageText(
        text: 'Some extracted text from a photo.',
      );
      expect(doc.title, startsWith('图片材料'));
      expect(doc.sourceId, 'image');
      expect(doc.license, contains('AI 提取'));
    });

    test('空文本抛异常(不能让用户拿到一份空材料)', () {
      expect(
        () => MaterialImport.fromImageText(text: '  '),
        throwsA(isA<MaterialSourceException>()),
      );
    });
  });

  group('链接规整(normalizeExternalUrl)', () {
    test('缺协议补 https;http/https 原样保留', () {
      expect(MaterialSourceService.normalizeExternalUrl('example.com/a'),
          'https://example.com/a');
      expect(MaterialSourceService.normalizeExternalUrl('http://a.cn/x'),
          'http://a.cn/x');
      expect(MaterialSourceService.normalizeExternalUrl('https://a.cn/x'),
          'https://a.cn/x');
    });

    test('剥掉 Markdown/引号包裹与中文标点尾巴(从聊天里粘来很常见)', () {
      expect(
        MaterialSourceService.normalizeExternalUrl('<https://a.cn/x>'),
        'https://a.cn/x',
      );
      expect(
        MaterialSourceService.normalizeExternalUrl('“https://a.cn/x”。'),
        'https://a.cn/x',
      );
    });

    test('非 http(s) 协议一律拒绝(不做任意文件读取的入口)', () {
      expect(MaterialSourceService.normalizeExternalUrl('file:///etc/passwd'), '');
      expect(MaterialSourceService.normalizeExternalUrl('content://media/1'), '');
      expect(MaterialSourceService.normalizeExternalUrl('javascript:alert(1)'), '');
    });

    test('不像网址的输入返回空串(由界面给中文提示)', () {
      expect(MaterialSourceService.normalizeExternalUrl(''), '');
      expect(MaterialSourceService.normalizeExternalUrl('随便一句话'), '');
      expect(MaterialSourceService.normalizeExternalUrl('https://随便一句话'), '');
    });

    test('识别 Gutenberg / arXiv 链接 → 走专用抓取(不再抽书目页导航)', () {
      expect(
        MaterialSourceService.gutenbergIdOf(
            'https://www.gutenberg.org/ebooks/1342'),
        1342,
      );
      expect(
        MaterialSourceService.arxivIdOf('https://arxiv.org/abs/1706.03762'),
        '1706.03762',
      );
    });
  });

  group('标题中文化', () {
    test('未配置 API Key 时原样返回(翻译失败不能挡住导入)', () async {
      final t = await MaterialImport.localizedTitle('Pride and Prejudice');
      expect(t, 'Pride and Prejudice');
    });

    test('已是「中文(英文)」或纯中文 → 不重复翻译', () async {
      expect(await MaterialImport.localizedTitle('傲慢与偏见(Pride and Prejudice)'),
          '傲慢与偏见(Pride and Prejudice)');
      expect(await MaterialImport.localizedTitle('傲慢与偏见'), '傲慢与偏见');
      expect(await MaterialImport.localizedTitle('  '), '');
    });
  });
}
