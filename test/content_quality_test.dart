import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/content_quality.dart';

/// 2026-11-06 用户真机反馈：找「四六级真题」时点进去只有图书介绍/购买页。
/// 这里锚定四道闸的口径，防止以后又退回"只看 200 字"。
void main() {
  const englishArticle = '''
The story of modern computing is a story of specialization. General purpose
processors are good at many things, but they are not always good at the same
thing at the same time. Engineers therefore build special hardware for the work
that matters most. A chip designed for one job can be smaller, faster and
cheaper than a general purpose part. It can also use less power. These
advantages explain why so many companies now design their own silicon instead
of buying everything off the shelf.
''';

  group('rejectReason — 可读正文判定', () {
    test('正常英文文章通过', () {
      expect(ContentQuality.rejectReason(englishArticle), isNull);
    });

    test('太短不算正文（保留原 200 字门槛）', () {
      expect(
        ContentQuality.rejectReason('A short paragraph that is clearly not enough.'),
        isNotNull,
      );
    });

    test('中文书店商品详情页被拒（含价格/ISBN/购买按钮）', () {
      const page = '''
新概念英语 第三册 教材（附光盘） 
定价：￥58.00  售价：￥39.90  折扣：6.9折  满减：满100减20  包邮
出版社：外语教学与研究出版社  出版时间：2020年1月  ISBN：9787513594000
开本：16开  页数：320  装帧：平装  版次：1  印次：12
商品详情
内容简介：本书是经典英语教材，适合中级学习者，配套练习与录音……
库存：有货  配送：次日达  销量：12000+  好评：98%
加入购物车  立即购买
''';
      final reason = ContentQuality.rejectReason(page);
      expect(reason, isNotNull);
      expect(ContentQuality.looksLikeBookOrProductPage(page), isTrue);
    });

    test('英文商品页被拒（Add to Cart / In Stock / Price）', () {
      const page = '''
CET-4 Practice Tests (2023 Edition)
Price: \$19.99  In Stock  Free Shipping
Add to Cart   Buy Now
Customer Reviews: 4.8 out of 5. This book collects twelve full practice
tests for college English learners who want to prepare carefully and
systematically over the course of several months before the exam.
''';
      expect(
        ContentQuality.rejectReason(page),
        isNotNull,
        reason: '购买意图出现即判售卖页',
      );
    });

    test('中文站点导航/介绍页被拒（英文比例过低）', () {
      const page = '''
当前位置：首页 > 图书 > 外语学习 > 四六级
您可能还喜欢：大学英语四级真题 六级真题 考研英语 雅思真题 托福真题
关于我们 | 联系我们 | 网站地图 | 版权声明 | 帮助中心 | 用户协议
购物指南  支付方式  配送服务  售后服务  商家合作  人才招聘
''';
      expect(ContentQuality.rejectReason(page), isNotNull);
    });

    test('书评类文章提到出版社/定价不误杀', () {
      const review = '''
A Calm Look at How Textbooks Are Made

出版社 and 定价 are part of a book's metadata, but a good review explains why
a title matters. This essay walks through the making of a modern textbook: the
authors, the reviewers, the classroom pilots, and the long revision cycles.
It argues that the best materials are not the ones with the highest price or
the flashiest cover, but the ones whose exercises teach you to notice language.
''';
      expect(ContentQuality.looksLikeBookOrProductPage(review), isFalse);
    });

    test('短行导航列表页被拒', () {
      final nav = List<String>.generate(20, (i) => '栏目${i + 1}').join('\n');
      expect(ContentQuality.looksLikeNavListing(nav), isTrue);
    });
  });

  group('firstImageFromMarkdown — 真实封面提取', () {
    test('取 markdown 第一张正文图，跳过 logo/data:', () {
      const md = '''
![site logo](https://x.com/static/logo.png)
Some paragraph.
![cover](https://cdn.x.com/images/cover.jpg)
''';
      expect(
        ContentQuality.firstImageFromMarkdown(md),
        'https://cdn.x.com/images/cover.jpg',
      );
    });

    test('相对路径按页面 URL 解析成绝对地址', () {
      const md = '<p><img src="/img/hero.webp" /></p>';
      expect(
        ContentQuality.firstImageFromMarkdown(
          md,
          baseUrl: 'https://example.com/news/story',
        ),
        'https://example.com/img/hero.webp',
      );
    });

    test('没有图片 / data: 图 / 转不出绝对地址 → null（UI 走无封面版式）', () {
      expect(ContentQuality.firstImageFromMarkdown('plain text'), isNull);
      expect(
        ContentQuality.firstImageFromMarkdown('![a](data:image/png;base64,xx)'),
        isNull,
      );
      expect(
        ContentQuality.firstImageFromMarkdown('![a](/relative.png)'),
        isNull,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 第三轮（2026-11-07 用户真机反馈）：候选级三层过滤
  // ══════════════════════════════════════════════════════════════════
  group('非英文内容（越南语/印尼语）', () {
    const vietnameseTitle =
        'Cách học tiếng Anh hiệu quả cho người mới bắt đầu';
    const vietnameseBody = '''
Bài viết này hướng dẫn cách học tiếng Anh hiệu quả cho người mới. Bạn nên
bắt đầu từ những mẫu câu đơn giản, sau đó mở rộng vốn từ vựng mỗi ngày.
Đừng cố gắng học quá nhiều từ trong một buổi, hãy chia nhỏ mục tiêu.
''';
    const indonesianTitle =
        'Cara belajar bahasa Inggris dengan cepat untuk pemula';

    test('越南语标题被判为非英文', () {
      expect(ContentQuality.looksLatinNonEnglish(vietnameseTitle), isTrue);
    });

    test('越南语正文被判为非英文（正文级闸门直接拒）', () {
      expect(ContentQuality.looksLatinNonEnglish(vietnameseBody), isTrue);
      expect(ContentQuality.rejectReason(vietnameseBody), isNotNull);
      expect(
        ContentQuality.rejectReason('$vietnameseBody' * 2),
        contains('不是英文'),
      );
    });

    test('印尼语标题被判为非英文', () {
      expect(ContentQuality.looksLatinNonEnglish(indonesianTitle), isTrue);
    });

    test('正常英文标题/正文不误杀', () {
      expect(
        ContentQuality.looksLatinNonEnglish('Climate Change and Coastal Cities'),
        isFalse,
      );
      expect(ContentQuality.looksLatinNonEnglish(englishArticle), isFalse);
      // 英文短文/短语不做语言判定（信息不足）
      expect(ContentQuality.looksLatinNonEnglish('New Concept English 3'),
          isFalse);
    });

    test('中文页面不算"外语乱入"（中文教材/真题合法）', () {
      expect(
        ContentQuality.looksLatinNonEnglish('大学英语四级真题 2024 年 6 月阅读部分'),
        isFalse,
      );
    });
  });

  group('公告/报名/考试信息页', () {
    test('中文报名/考试简介页被拒', () {
      expect(
        ContentQuality.looksLikeAnnouncementPage(
          title: '2024 年 12 月大学英语四级考试报名通知',
          url: 'https://exam.example.com/baoming/2024',
        ),
        isTrue,
      );
      expect(
        ContentQuality.looksLikeAnnouncementPage(
          title: '大学英语四级考试简介',
          snippet: '考试时间、报名条件与准考证打印说明',
        ),
        isTrue,
      );
    });

    test('英文报名页/官网页被拒', () {
      expect(
        ContentQuality.looksLikeAnnouncementPage(
          title: 'Registration for CET-4 now open',
          url: 'https://example.edu/registration',
        ),
        isTrue,
      );
    });

    test('正常材料页不误杀', () {
      expect(
        ContentQuality.looksLikeAnnouncementPage(
          title: 'CET-4 真题 2024 年 6 月阅读部分（附答案解析）',
          url: 'https://example.com/cet4/2024-reading',
        ),
        isFalse,
      );
    });
  });

  group('弱相关过滤', () {
    test('与分类检索词完全无命中的候选被拒', () {
      expect(
        ContentQuality.isWeaklyRelated(
          title: 'Best pizza restaurants in town',
          snippet: 'A food blog about dough and cheese.',
          seeds: const <String>['business politics news', '商业与政治'],
        ),
        isTrue,
      );
    });

    test('有真实命中不误杀（英文前缀 / 中文子串）', () {
      expect(
        ContentQuality.isWeaklyRelated(
          title: 'How to Read Better: evidence from reading research',
          snippet: 'reading comprehension strategies',
          seeds: const <String>['reading', 'english reading'],
        ),
        isFalse,
      );
      expect(
        ContentQuality.isWeaklyRelated(
          title: '商业与政治：本周市场观察',
          snippet: 'market and policy',
          seeds: const <String>['商业与政治'],
        ),
        isFalse,
      );
    });

    test('官方搜索已排序/高权威的候选直接信任', () {
      expect(
        ContentQuality.isWeaklyRelated(
          title: 'A totally unrelated title',
          seeds: const <String>['climate change'],
          rerankScore: 2,
        ),
        isFalse,
      );
      expect(
        ContentQuality.isWeaklyRelated(
          title: 'A totally unrelated title',
          seeds: const <String>['climate change'],
          authority: 3,
        ),
        isFalse,
      );
    });
  });

  group('候选级综合判定 rejectCandidate', () {
    test('公告页 → announcement', () {
      expect(
        ContentQuality.rejectCandidate(
          title: '四级考试报名入口',
          url: 'https://example.com/baoming',
          seeds: const <String>['CET-4 真题'],
        ),
        ContentReject.announcement,
      );
    });

    test('越南语 → nonEnglish', () {
      expect(
        ContentQuality.rejectCandidate(
          title: 'Cách học tiếng Anh hiệu quả',
          url: 'https://example.com/vi/article',
          snippet: 'bài viết về cách học tiếng anh cho người mới',
          seeds: const <String>['english reading'],
        ),
        ContentReject.nonEnglish,
      );
    });

    test('弱相关 → weakRelated', () {
      expect(
        ContentQuality.rejectCandidate(
          title: 'Best pizza in town',
          url: 'https://example.com/food/pizza',
          seeds: const <String>['business politics news'],
        ),
        ContentReject.weakRelated,
      );
    });

    test('正常英文候选 → null', () {
      expect(
        ContentQuality.rejectCandidate(
          title: 'CET-4 真题 2024 阅读（附答案）',
          url: 'https://example.com/cet4/2024',
          snippet: '大学英语四级真题阅读部分',
          seeds: const <String>['CET-4 真题阅读'],
        ),
        isNull,
      );
    });
  });
}
