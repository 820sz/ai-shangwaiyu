import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/material_recommendation.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/screens/input/learner_preferences_screen.dart';
import 'package:readflow/services/doubao_api.dart';
import 'package:readflow/services/material_recommend_service.dart';
import 'package:readflow/services/tts_accent.dart';

/// v2.0 回归测试:
/// ① 词汇双音标(phonetic_uk / phonetic_us)—— 模型往返、老数据回填、坏类型容错、显示规则
/// ② AI 补全解析的音标字段(单/双)
/// ③ 朗读音色档位 → TTS 语言码(纯函数)
/// ④ 题材/关键词黑名单 isBlocked / filterBlocked / 屏蔽词切分
void main() {
  group('Vocabulary 双音标 — 模型往返(v2.0)', () {
    test('toMap/fromMap 往返:两套音标各自保留,phonetic 兼容列取英式', () {
      final v = Vocabulary(
        word: 'schedule',
        phoneticUk: '/ˈʃedjuːl/',
        phoneticUs: '/ˈskedʒuːl/',
      );
      final map = v.toMap();
      // 兼容列给一个值(老代码/老版本降级读 DB 时不至于丢音标)
      expect(map['phonetic_uk'], '/ˈʃedjuːl/');
      expect(map['phonetic_us'], '/ˈskedʒuːl/');
      expect(map['phonetic'], '/ˈʃedjuːl/');

      final back = Vocabulary.fromMap(map);
      expect(back.phoneticUk, '/ˈʃedjuːl/');
      expect(back.phoneticUs, '/ˈskedʒuːl/');
      expect(back.phoneticsUk, '/ˈʃedjuːl/');
      expect(back.phoneticsUs, '/ˈskedʒuːl/');
    });

    test('老数据(只有 phonetic 列)读的时候回填到英/美两边', () {
      final back = Vocabulary.fromMap({
        'id': 7,
        'word': 'unfettered',
        'translation': '无拘束的',
        'phonetic': '/ˈʌnfetəd/',
        'word_type': 'word',
        'created_at': '2026-01-01T00:00:00.000',
      });
      expect(back.phonetic, '/ˈʌnfetəd/');
      expect(back.phoneticUk, '/ˈʌnfetəd/');
      expect(back.phoneticUs, '/ˈʌnfetəd/');
      // 两边实际是同一套 → 按单音标显示(不写成"英 x · 美 x")
      expect(back.displayPhonetic, '/ˈʌnfetəd/');
    });

    test('fromMap 容错:列缺失 / 坏类型 → null,不抛异常', () {
      // 模拟"老库还没加列" + 类型全乱(数字/Map/List 都不是 String)
      final back = Vocabulary.fromMap({
        'word': 'hello',
        'phonetic': 123,
        'phonetic_uk': ['/x/'],
        'phonetic_us': {'v': '/y/'},
        'word_type': 'word',
        'created_at': '2026-01-01T00:00:00.000',
      });
      expect(back.phonetic, isNull);
      expect(back.phoneticUk, isNull);
      expect(back.phoneticUs, isNull);
      expect(back.displayPhonetic, isNull);

      // 完全没有这三列(最老的库形态)
      final bare = Vocabulary.fromMap({
        'word': 'hi',
        'word_type': 'word',
        'created_at': '2026-01-01T00:00:00.000',
      });
      expect(bare.phoneticUk, isNull);
      expect(bare.phoneticUs, isNull);
      expect(bare.hasPhonetic, isFalse);
    });

    test('copyWith:可分别设置/覆盖/清空两边音标', () {
      final v = Vocabulary(word: 'a', phonetic: '/old/');
      final both = v.copyWith(phoneticUk: '/uk/', phoneticUs: '/us/');
      expect(both.phoneticUk, '/uk/');
      expect(both.phoneticUs, '/us/');
      // 未传的字段保留原值(哨兵语义)
      expect(both.phonetic, '/old/');

      final cleared = both.copyWith(phoneticUs: null);
      expect(cleared.phoneticUs, isNull);
      expect(cleared.phoneticUk, '/uk/');
    });

    test('displayPhonetic 显示规则:两边 / 一边 / 都空', () {
      expect(
        Vocabulary(word: 'a', phoneticUk: '/uk/', phoneticUs: '/us/')
            .displayPhonetic,
        '英 /uk/ · 美 /us/',
      );
      // 只有一边 → 只显示那一边且不加标签(与 v1.5 老样式一致)
      expect(
        Vocabulary(word: 'a', phoneticUk: '/uk/').displayPhonetic,
        '/uk/',
      );
      expect(
        Vocabulary(word: 'a', phoneticUs: '/us/').displayPhonetic,
        '/us/',
      );
      // 纯空白等同没有
      expect(
        Vocabulary(word: 'a', phoneticUk: '   ', phoneticUs: '')
            .displayPhonetic,
        isNull,
      );
      expect(Vocabulary(word: 'a').displayPhonetic, isNull);
    });
  });

  group('parseWordInfo — 单/双音标与容错(v2.0)', () {
    test('同时返回英/美两套 → 分别解析', () {
      final info = DoubaoApiService.parseWordInfo(
        '{"translation":"日程","part_of_speech":"n.",'
        '"phonetic_uk":"/ˈʃedjuːl/","phonetic_us":"/ˈskedʒuːl/",'
        '"original_sentence":"What is your schedule?"}',
      );
      expect(info['phonetic_uk'], '/ˈʃedjuːl/');
      expect(info['phonetic_us'], '/ˈskedʒuːl/');
      // 老字段不再由模型提供 → 空串(不编造)
      expect(info['phonetic'], '');
    });

    test('老返回只有 phonetic → 回填到两边,phonetic 原样保留', () {
      final info = DoubaoApiService.parseWordInfo(
        '{"translation":"无拘束的","phonetic":"/ˈʌnfetəd/"}',
      );
      expect(info['phonetic'], '/ˈʌnfetəd/');
      expect(info['phonetic_uk'], '/ˈʌnfetəd/');
      expect(info['phonetic_us'], '/ˈʌnfetəd/');
    });

    test('只给一边 + 空白/非字符串 → 另一边落空,不抛', () {
      final onlyUk = DoubaoApiService.parseWordInfo(
        '{"translation":"a","phonetic_uk":"/uk/"}',
      );
      expect(onlyUk['phonetic_uk'], '/uk/');
      expect(onlyUk['phonetic_us'], '');

      final blank = DoubaoApiService.parseWordInfo(
        '{"translation":"a","phonetic_uk":"   ","phonetic_us":123}',
      );
      expect(blank['phonetic_uk'], '');
      // 非字符串按 toString 处理(123 → "123"),但空白必须归空
      expect(blank['phonetic_us'], '123');
    });

    test('坏 JSON / 数组 / 空串 → 空 map,不抛异常', () {
      expect(DoubaoApiService.parseWordInfo('抱歉,我无法回答'), isEmpty);
      expect(DoubaoApiService.parseWordInfo('[1,2,3]'), isEmpty);
      expect(DoubaoApiService.parseWordInfo(''), isEmpty);
    });

    test('合法 JSON 但字段全缺 → 七个键都在,值统一空串', () {
      // 老调用方(表单回填)拿的就是这套键,不能让某个键消失变成 null
      final info = DoubaoApiService.parseWordInfo('{"unrelated":"x"}');
      expect(info.length, 7);
      expect(info['phonetic'], '');
      expect(info['phonetic_uk'], '');
      expect(info['phonetic_us'], '');
      expect(info['translation'], '');
    });
  });

  group('朗读音色档位 → TTS 语言码(纯函数)', () {
    test('三档映射', () {
      expect(ttsLanguageForAccent('uk'), 'en-GB');
      expect(ttsLanguageForAccent('us'), 'en-US');
      // 跟随系统 → null,由 TtsService 退回引擎默认语言
      expect(ttsLanguageForAccent('system'), isNull);
    });

    test('未知/空值当"跟随系统",不让坏配置把朗读弄哑', () {
      expect(ttsLanguageForAccent(null), isNull);
      expect(ttsLanguageForAccent(''), isNull);
      expect(ttsLanguageForAccent('en-GB'), isNull);
      expect(ttsLanguageForAccent('UK'), isNull); // 大小写敏感:只认小写档位
    });

    test('档位文案', () {
      expect(ttsAccentLabel('system'), '跟随系统');
      expect(ttsAccentLabel('uk'), '英式发音');
      expect(ttsAccentLabel('us'), '美式发音');
      expect(ttsAccentLabel('乱填的'), '跟随系统');
    });
  });

  group('题材黑名单 isBlocked(v2.0)', () {
    test('命中题材 → 屏蔽', () {
      expect(
        MaterialRecommendService.isBlocked(
          title: '国际政治新闻选读',
          blockedTopics: const ['政治'],
          blockedKeywords: const [],
        ),
        isTrue,
      );
      expect(
        MaterialRecommendService.isBlocked(
          title: 'The Economist 商业财经专栏',
          summary: '全球市场与公司报道',
          keywords: '商业, 财经, 市场',
          blockedTopics: const ['商业财经'],
          blockedKeywords: const [],
        ),
        isTrue,
      );
    });

    test('命中关键词(标题/简介/关键词任一处)→ 屏蔽', () {
      expect(
        MaterialRecommendService.isBlocked(
          title: 'BBC 娱乐八卦周刊',
          blockedTopics: const [],
          blockedKeywords: const ['八卦'],
        ),
        isTrue,
      );
      expect(
        MaterialRecommendService.isBlocked(
          title: 'A Short History of Tea',
          summary: '讲茶叶贸易与减肥风潮',
          blockedTopics: const [],
          blockedKeywords: const ['减肥'],
        ),
        isTrue,
      );
      expect(
        MaterialRecommendService.isBlocked(
          title: 'Science Weekly',
          keywords: '减肥, 营养, 代谢',
          blockedTopics: const [],
          blockedKeywords: const ['减肥'],
        ),
        isTrue,
      );
    });

    test('大小写与首尾空白不影响命中', () {
      expect(
        MaterialRecommendService.isBlocked(
          title: 'POLITICS TODAY',
          blockedTopics: const ['  politics  '],
          blockedKeywords: const [],
        ),
        isTrue,
      );
      expect(
        MaterialRecommendService.isBlocked(
          title: 'Politics Today',
          summary: 'Daily POLITICS briefing',
          blockedTopics: const [],
          blockedKeywords: const ['Politics'],
        ),
        isTrue,
      );
    });

    test('空黑名单 / 空白项 → 一律放行', () {
      expect(
        MaterialRecommendService.isBlocked(
          title: '任何材料',
          summary: '任何简介',
          keywords: '任何关键词',
          blockedTopics: const [],
          blockedKeywords: const [],
        ),
        isFalse,
      );
      // 黑名单里只有空白项 ≈ 没配(否则用户误敲一个空格就把推荐清空了)
      expect(
        MaterialRecommendService.isBlocked(
          title: '任何材料',
          blockedTopics: const ['   ', ''],
          blockedKeywords: const ['  '],
        ),
        isFalse,
      );
    });

    test('包含匹配:短屏蔽词会连更长的标题一起挡掉(口径写死在注释里)', () {
      expect(
        MaterialRecommendService.isBlocked(
          title: 'International Politics and Trade',
          blockedTopics: const ['politic'],
          blockedKeywords: const [],
        ),
        isTrue,
      );
      // 反向:屏蔽"政治"不会误伤不含该词的材料
      expect(
        MaterialRecommendService.isBlocked(
          title: 'Introduction to Microeconomics',
          blockedTopics: const ['政治'],
          blockedKeywords: const [],
        ),
        isFalse,
      );
    });

    test('正则元字符当普通字符处理,不炸也不误伤', () {
      expect(
        MaterialRecommendService.isBlocked(
          title: 'C++ 入门与算法竞赛',
          blockedTopics: const ['C++'],
          blockedKeywords: const [],
        ),
        isTrue,
      );
      // "(a" 是坏正则的典型输入:包含匹配口径下它只匹配字面量
      expect(
        MaterialRecommendService.isBlocked(
          title: 'Grammar Drills',
          blockedTopics: const ['(a'],
          blockedKeywords: const [],
        ),
        isFalse,
      );
      expect(
        MaterialRecommendService.isBlocked(
          title: 'Unit (a) review',
          blockedTopics: const ['(a'],
          blockedKeywords: const [],
        ),
        isTrue,
      );
    });
  });

  group('filterBlocked / blockedCount(v2.0)', () {
    List<MaterialRecommendation> deck() => [
          _rec('政治学导论', summary: '西方政治制度', keywords: '政治, 制度'),
          _rec('Pride and Prejudice', summary: '经典文学小说', keywords: '小说, 爱情'),
          _rec('减肥的科学', summary: '代谢与饮食', keywords: '健康'),
          _rec('Microeconomics', summary: '供需与市场,经济学入门', keywords: '经济'),
        ];

    test('按题材过滤,剩下的条数正确', () {
      final out = MaterialRecommendService.filterBlocked(
        deck(),
        blockedTopics: const ['政治'],
        blockedKeywords: const [],
      );
      expect(out.map((r) => r.title).toList(),
          ['Pride and Prejudice', '减肥的科学', 'Microeconomics']);
      expect(out.length, 3);
    });

    test('题材 + 关键词同时命中 → 计数不重复算', () {
      final items = deck();
      final out = MaterialRecommendService.filterBlocked(
        items,
        blockedTopics: const ['政治'],
        blockedKeywords: const ['减肥'],
      );
      expect(out.length, 2);
      expect(
        MaterialRecommendService.blockedCount(
          items,
          blockedTopics: const ['政治'],
          blockedKeywords: const ['减肥'],
        ),
        2,
      );
    });

    test('两个列表都空 → 原样全放行,计数为 0', () {
      final items = deck();
      final out = MaterialRecommendService.filterBlocked(
        items,
        blockedTopics: const [],
        blockedKeywords: const [],
      );
      expect(out.length, 4);
      expect(
        MaterialRecommendService.blockedCount(
          items,
          blockedTopics: const [],
          blockedKeywords: const [],
        ),
        0,
      );
    });

    test('全被挡住 → 空列表 + 计数等于总数', () {
      final items = deck();
      // 四个词条每条的标题/简介/关键词里都有一个含 "学" 的字段,
      // 于是全部命中 —— 这就是"包含匹配会误伤"的现场
      final out = MaterialRecommendService.filterBlocked(
        items,
        blockedTopics: const [],
        blockedKeywords: const ['学'],
      );
      expect(out, isEmpty);
      expect(
        MaterialRecommendService.blockedCount(
          items,
          blockedTopics: const [],
          blockedKeywords: const ['学'],
        ),
        4,
      );
    });

    test('中文标题也能被英文/中文屏蔽词命中(包含匹配不看语言)', () {
      final items = deck();
      final out = MaterialRecommendService.filterBlocked(
        items,
        blockedTopics: const [],
        blockedKeywords: const ['政治'],
      );
      expect(out.map((r) => r.title).toList(),
          ['Pride and Prejudice', '减肥的科学', 'Microeconomics']);
    });
  });

  group('黑名单进推荐提示词(v2.0)', () {
    test('有黑名单 → 提示词明确列出题材与关键词', () {
      final prompt = MaterialRecommendService.recommendationUserPrompt(
        profile: const LearnerProfile(level: '中级（B1-B2）'),
        vocab: const [],
        category: '外刊',
        blockedTopics: const ['政治', '影视娱乐'],
        blockedKeywords: const ['八卦'],
      );
      expect(prompt, contains('不要推荐这些题材:政治、影视娱乐'));
      expect(prompt, contains('不要出现这些词:八卦'));
    });

    test('无黑名单 → 不出现屏蔽段落(老行为不变)', () {
      final prompt = MaterialRecommendService.recommendationUserPrompt(
        profile: const LearnerProfile(level: '中级（B1-B2）'),
        vocab: const [],
        category: '外刊',
      );
      expect(prompt, isNot(contains('不想看')));
      expect(prompt, contains('【本次想找的材料类型】外刊'));
    });
  });

  group('屏蔽关键词切分(纯函数)', () {
    test('逗号/空格/顿号/分号/换行都认,并去重', () {
      expect(
        splitBlockedKeywords('政治, 八卦 减肥、战争;广告\n娱乐'),
        ['政治', '八卦', '减肥', '战争', '广告', '娱乐'],
      );
      expect(splitBlockedKeywords('政治，政治, 政治'), ['政治']);
    });

    test('空输入/纯分隔符 → 空列表', () {
      expect(splitBlockedKeywords(''), isEmpty);
      expect(splitBlockedKeywords('  , ， 、 '), isEmpty);
    });
  });
}

MaterialRecommendation _rec(
  String title, {
  String summary = '',
  String keywords = '',
}) =>
    MaterialRecommendation(
      category: '外刊',
      title: title,
      summary: summary,
      keywords: keywords,
      createdAt: DateTime(2026, 1, 1),
    );
