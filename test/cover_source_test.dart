import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/bookshelf.dart';
import 'package:readflow/services/material_source.dart';
import 'package:readflow/services/original_search.dart';

/// v2.11「封面用原材料自己的原插图」回归测试(用户 2026-10-05 第 2 条)。
///
/// 用户原话:"**不需要 ai 生图啊,很多材料明明链接点开里面自己就有配图啊!**
/// 把原材料的原插图作为材料的封面不就行了吗?"
///
/// 这条链路以前有三处断点,本文件逐处钉住:
/// 1. RSS 头图抽不出来(`imageOf` 只认 media RSS 三件套,NPR 实测 0 命中);
/// 2. 文章页 `og:image` 根本不解析(全库无实现);
/// 3. 拿到了图也不落库(`materials` 没有 cover_url 列)→ 重启就退化成色块。
///
/// 下面的取样全部来自**实测原文**(2026-10-05 真机网络请求),
/// 不是编的:见 `docs/` 里那一轮的取证记录。
void main() {
  group('articleCoverUrl — 文章页 og:image(实测 NPR 原文形状)', () {
    // property= 而不是 name=:老代码里的 _metaOf 只认 name,直接复用会 0 命中
    const nprPage = '''
      <html><head>
      <meta property="og:image" content="https://npr.brightspotcdn.com/dims3/default/strip/false/crop/2000x1125+0+0/resize/1400/quality/85/format/jpeg/?url=http%3A%2F%2Fnpr-brightspot.s3.amazonaws.com%2F83%2F73%2F3a307a1b4a229daf6ff87a9f126f%2Fcopy-of-6-book-covers-5.jpg" />
      <meta name="twitter:image" content="https://npr.brightspotcdn.com/other.jpg" />
      </head><body><p>正文</p></body></html>
    ''';

    test('og:image 用 property= 也要取到,并且把 CDN 拆成 S3 原址(CDN 直连 403)', () {
      final got = MaterialSourceService.articleCoverUrl(
        nprPage,
        'https://www.npr.org/2026/10/06/nx-s1-5991463/story',
      );
      expect(got, isNotNull);
      // 实测:带 ?url= 的 CDN 地址直连 403,拆出来的 S3 原址才是 200 image/jpeg
      expect(got, startsWith('https://npr-brightspot.s3.amazonaws.com/'));
      expect(got, isNot(contains('brightspotcdn.com')));
      expect(got, endsWith('copy-of-6-book-covers-5.jpg'));
    });

    test('没有 og:image 时退到 twitter:image', () {
      final got = MaterialSourceService.articleCoverUrl(
        '<html><head><meta name="twitter:image" content="https://x.example/t.jpg"/></head></html>',
        'https://x.example/a',
      );
      expect(got, equals('https://x.example/t.jpg'));
    });

    test('两级 meta 都没有 → 正文第一张真图(相对路径要拼成绝对地址)', () {
      final got = MaterialSourceService.articleCoverUrl(
        '<html><body><img src="images/i_003.jpg" alt="x"><p>t</p></body></html>',
        'https://www.gutenberg.org/files/1342/1342-h/1342-h.htm',
      );
      expect(
        got,
        equals('https://www.gutenberg.org/files/1342/1342-h/images/i_003.jpg'),
      );
    });

    test('啥都没有 → null(界面回落程序化封面,不留白块)', () {
      expect(MaterialSourceService.articleCoverUrl('<html></html>', 'https://x.example'), isNull);
      expect(MaterialSourceService.articleCoverUrl('', 'https://x.example'), isNull);
    });
  });

  group('coverFor — 一条材料最终该显示哪张封面', () {
    test('库里存的图优先(这是"原材料自己的原插图")', () {
      expect(
        MaterialSourceService.coverFor(
          storedCoverUrl: 'https://npr-brightspot.s3.amazonaws.com/a.jpg',
          sourceUrl: 'https://www.npr.org/x',
        ),
        equals('https://npr-brightspot.s3.amazonaws.com/a.jpg'),
      );
    });

    test('库里没存(老数据)→ 按公版书书号现算,一次网络往返都不用', () {
      expect(
        MaterialSourceService.coverFor(
          sourceUrl: 'https://www.gutenberg.org/ebooks/79727',
        ),
        equals('https://www.gutenberg.org/cache/epub/79727/pg79727.cover.medium.jpg'),
      );
    });

    test('列表态临时拿到的图也能用(顺序:库里的 → 列表给的)', () {
      expect(
        MaterialSourceService.coverFor(
          itemImageUrl: 'https://feeds.example/hero.jpg',
        ),
        equals('https://feeds.example/hero.jpg'),
      );
    });

    test('都不是图 → null;脏值(false:// / 本地路径)一律不认', () {
      expect(MaterialSourceService.coverFor(sourceUrl: 'https://example.com/x'), isNull);
      expect(
        MaterialSourceService.coverFor(storedCoverUrl: 'file:///C:/a.jpg'),
        isNull,
      );
    });
  });

  group('gutenbergCoverUrlOf — 公版书官方封面地址(实测 12/12 可达)', () {
    test('6 个书号拼出来的地址与实测一致', () {
      for (final id in [79727, 11231, 555, 79732, 100, 1342]) {
        expect(
          MaterialSourceService.gutenbergCoverUrlOf('$id'),
          equals('https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg'),
        );
      }
    });

    test('非法书号返回 null(不拼出一个 404 地址)', () {
      expect(MaterialSourceService.gutenbergCoverUrlOf('0'), isNull);
      expect(MaterialSourceService.gutenbergCoverUrlOf('-3'), isNull);
      expect(MaterialSourceService.gutenbergCoverUrlOf('abc'), isNull);
    });

    test('旧的 OriginalHit.gutenbergCoverUrl 入口行为不变(调用点不动)', () {
      expect(
        OriginalHit.gutenbergCoverUrl('1342'),
        equals(MaterialSourceService.gutenbergCoverUrlOf('1342')),
      );
      expect(OriginalHit.gutenbergCoverUrl('oops'), isNull);
    });
  });

  group('BookshelfBook.fromRow — 书架要能带出封面', () {
    test('有 cover_url 就带出来', () {
      final b = BookshelfBook.fromRow({
        'material_id': 7,
        'title': '傲慢与偏见',
        'cover_url': 'https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg',
      });
      expect(b.coverUrl, contains('pg1342.cover'));
    });

    test('老数据(无列/空串/"null"/脏值)一律当"没有图",不塞给 Image.network', () {
      for (final bad in [null, '', '   ', 'null', 'file:///C:/x.jpg']) {
        final b = BookshelfBook.fromRow({
          'material_id': 1,
          'title': 'x',
          'cover_url': bad,
        });
        expect(b.coverUrl, isNull, reason: 'cover_url=$bad 不该被当成可用图');
      }
    });
  });
}
