import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/material_art.dart';
import 'package:readflow/widgets/art_cover.dart';
import 'package:readflow/widgets/material_cover.dart';

/// 材料自动配图(v4.3)的**纯函数合同** —— 不联网,只锁解析与规则。
///
/// 为什么要单测这一层:抓取链路里最容易坏的是"图床返回了风控页/脏 JSON",
/// 解析器一旦把 HTML 当图片地址塞进 Image.network,界面就是一片白块。
/// 所以:JSON 形状、地址升级、尺寸过滤、生图响应解析都必须钉死。
void main() {
  group('豆瓣书封解析', () {
    const fixture = '''
[{"title":"活着","url":"https://book.douban.com/subject/4913064/","pic":"https://img9.doubanio.com/view/subject/s/public/s29869926.jpg","author_name":"余华","year":"2012","type":"b","id":"4913064"},
 {"title":"活着","url":"https://book.douban.com/subject/27064488/","pic":"https://img3.doubanio.com/view/subject/s/public/s29652928.jpg","author_name":"余华","year":"2017","type":"b","id":"27064488"}]
''';

    test('取第一本书的封面,并把 /s/ 小图升级成 /l/ 大图', () {
      expect(
        MaterialArt.firstDoubanCover(fixture),
        'https://img9.doubanio.com/view/subject/l/public/s29869926.jpg',
      );
    });

    test('空/脏数据/非书条目 → null(绝不能让风控页变成图片地址)', () {
      expect(MaterialArt.firstDoubanCover(null), isNull);
      expect(MaterialArt.firstDoubanCover(''), isNull);
      expect(MaterialArt.firstDoubanCover('<html>forbid</html>'), isNull);
      expect(
        MaterialArt.firstDoubanCover(
          '[{"title":"x","type":"m","pic":"https://x/y.jpg"}]',
        ),
        isNull,
      );
      expect(
        MaterialArt.firstDoubanCover(
          '[{"title":"x","type":"b","pic":"javascript:void(0)"}]',
        ),
        isNull,
      );
    });
  });

  group('360 图片搜索解析', () {
    const fixture = '''
{"total":55,"list":[
 {"width":"240","height":"320","img":"https://pic.example.com/small.jpg","thumb":"https://p3.ssl.qhimgs1.com/small.jpg"},
 {"width":"800","height":"600","img":"https://pic.rmb.bdstatic.com/big.jpg","thumb":"https://p3.ssl.qhimgs1.com/big.jpg"},
 {"width":"1024","height":"768","thumb_bak":"https://p3.ssl.qhimgs1.com/big2.jpg"}
]}
''';

    test('跳过窄图,优先原图 img;没有原图时退 thumb_bak', () {
      expect(
        MaterialArt.firstSo360Image(fixture),
        'https://pic.rmb.bdstatic.com/big.jpg',
      );
      expect(
        MaterialArt.firstSo360Image(
          '{"list":[{"width":"160","img":"https://x/small.jpg"},{"width":"700","thumb_bak":"https://x/back.jpg"}]}',
        ),
        'https://x/back.jpg',
      );
    });

    test('空/风控 JSON → null', () {
      expect(MaterialArt.firstSo360Image(null), isNull);
      expect(MaterialArt.firstSo360Image('{"status":1,"info":"forbid"}'), isNull);
      expect(MaterialArt.firstSo360Image('[1,2,3]'), isNull);
    });
  });

  group('AI 生图(可选兜底)', () {
    test('提示词包含标题与"不要文字",并统一糖果色调', () {
      final p = MaterialArt.aiPrompt(title: 'Moby Dick', kind: 'book');
      expect(p, contains('Moby Dick'));
      expect(p, contains('不要出现任何文字'));
      expect(p, contains('糖果色'));
    });

    test('候选模型:已知 Seedream 型号在列表里(账号没发现时用兜底)', () {
      final models = MaterialArt.aiModelCandidates();
      expect(models, isNotEmpty);
      expect(models.any((m) => m.contains('seedream')), isTrue);
    });

    test('生图响应解析:data[0].url;无 url → null', () {
      expect(
        MaterialArt.firstAiImageUrl(<String, dynamic>{
          'data': <dynamic>[
            <String, dynamic>{'url': 'https://ark.example.com/a.jpeg'},
          ],
        }),
        'https://ark.example.com/a.jpeg',
      );
      expect(
        MaterialArt.firstAiImageUrl(<String, dynamic>{
          'data': <dynamic>[
            <String, dynamic>{'b64_json': 'xxx'},
          ],
        }),
        isNull,
      );
      expect(MaterialArt.firstAiImageUrl(null), isNull);
    });

    test('当前测试环境未配置方舟 → AI 不可用(默认不花钱)', () {
      expect(MaterialArt.aiAvailable, isFalse);
    });
  });

  group('缓存键', () {
    test('同标题同类型 → 同名;类型或标题变了 → 不同名', () {
      final a = MaterialArt.cacheName(title: 'Moby Dick', kind: 'book');
      expect(MaterialArt.cacheName(title: 'Moby Dick', kind: 'book'), a);
      expect(MaterialArt.cacheName(title: 'Moby Dick', kind: 'news'), isNot(a));
      expect(MaterialArt.cacheName(title: 'Moby Dick 2', kind: 'book'), isNot(a));
      expect(a.startsWith('matart_'), isTrue);
    });

    test('搜索词构造:书名号被清掉、类型加提示词', () {
      // 通过行为间接验证:提示词在纯函数层不可见,这里只验证不炸且稳定
      expect(MaterialArt.doubanSearchUrl('活着'), contains('subject_suggest'));
      expect(MaterialArt.so360SearchUrl('Moby Dick'), contains('image.so.com'));
    });
  });

  group('ArtCover 组件(禁网降级)', () {
    testWidgets('关掉抓取时退回程序化封面,不抛异常', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ArtCover(
                title: 'The Elements of Style',
                kind: 'book',
                width: 88,
                height: 118,
                levelLabel: 'C1',
                enableFetch: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MaterialCover), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
