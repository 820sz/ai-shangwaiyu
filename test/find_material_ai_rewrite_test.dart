import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/material_ai_rewrite.dart';
import 'package:readflow/services/material_library.dart';

/// AI 改写学习版(非原文)· 纯逻辑单测(2026-11-07 第三轮 · 用户真机反馈第 4 条)。
///
/// 这里钉住的全是"出错会引起用户信任问题"的规则:
/// - 标题/许可必须一直带"非原文"标注(不许冒充原文);
/// - 来源只能来自真实搜到的候选(模型编的链接一律丢);
/// - 没线索就不生成(不凭空编);
/// - 字数是本地实数,难度只用真实算出来的覆盖率;
/// - 失败给人话原因,不抛异常到界面。
void main() {
  const sourceA = AiRewriteSource(
    title: 'Atomic Habits — James Clear',
    url: 'https://example.com/atomic-habits',
    site: 'example.com',
    snippet: '习惯养成与微小改变:每天进步 1% 的复利效应。',
    kind: 'book',
  );
  const sourceB = AiRewriteSource(
    title: 'How Tiny Habits Work',
    url: 'https://example.org/tiny-habits',
    site: 'example.org',
    snippet: '行为设计:提示、惯常行为、奖励。',
    kind: 'article',
  );
  const sourceC = AiRewriteSource(
    title: 'The Power of Habit (review)',
    url: 'https://example.net/habit-review',
    site: 'example.net',
    snippet: '习惯回路的科普介绍。',
  );

  String bodyOf(int words) => List<String>.generate(
        words,
        (i) => i.isEven ? 'habit' : 'change',
      ).join(' ');

  AiRewriteRequest request({List<AiRewriteSource> sources = const <AiRewriteSource>[]}) =>
      AiRewriteRequest(
        query: '原子习惯 atomic habits',
        sources: sources.isEmpty
            ? const <AiRewriteSource>[sourceA, sourceB, sourceC]
            : sources,
        bandLabel: 'i+10 · 挑战',
        bandHint: '目标难度 i+10:未知词率 2%~10%',
        goals: const <String>['四六级', '兴趣阅读'],
        interests: const <String>['science'],
      );

  String validJson({
    String topic = 'Small Habits, Big Changes',
    String body = '',
    Object? usedSources = const <int>[1, 2],
    String titleCn = '微小习惯,巨大改变',
    String summaryCn = '一篇基于搜索线索改写的学习版,不是原文。',
  }) {
    final b = body.isEmpty ? bodyOf(220) : body;
    return '```json\n'
        '{"topic": "$topic", "title_cn": "$titleCn", '
        '"summary_cn": "$summaryCn", "body": "$b", '
        '"used_sources": $usedSources}\n```';
  }

  group('目标篇幅(纯函数)', () {
    test('按档位给不同篇幅;不限给 320', () {
      expect(aiRewriteTargetWords('i+1 · 舒适'), 260);
      expect(aiRewriteTargetWords('i+10 · 挑战'), 340);
      expect(aiRewriteTargetWords('i+100 · 快反馈'), 420);
      expect(aiRewriteTargetWords(''), 320);
      expect(aiRewriteTargetWords('不限'), 320);
    });

    test('请求默认篇幅跟档位走,显式传值优先', () {
      expect(request().targetWords, 340);
      expect(
        AiRewriteRequest(
          query: 'q',
          sources: const <AiRewriteSource>[sourceA],
          bandLabel: 'i+1 · 舒适',
        ).targetWords,
        260,
      );
      expect(
        AiRewriteRequest(
          query: 'q',
          sources: const <AiRewriteSource>[sourceA],
          bandLabel: 'i+10 · 挑战',
          targetWords: 200,
        ).targetWords,
        200,
      );
    });
  });

  group('标题与身份(纯函数)', () {
    test('标题永远带「AI 改写学习版（非原文）」,且不含 Markdown 星号', () {
      final title = aiRewriteTitleOf('Atomic Habits');
      expect(title, 'Atomic Habits · $aiRewriteMarker');
      expect(title, contains('非原文'));
      expect(title, isNot(contains('*')));
    });

    test('模型自己带的标注/引号/星号会被洗掉,不重复', () {
      expect(
        aiRewriteTitleOf('**Atomic Habits** · AI 改写学习版（非原文）'),
        'Atomic Habits · $aiRewriteMarker',
      );
      expect(
        aiRewriteTitleOf('“Small Habits, Big Changes”'),
        'Small Habits, Big Changes · $aiRewriteMarker',
      );
      expect(aiRewriteTitleOf('   '), '未命名主题 · $aiRewriteMarker');
    });

    test('身份按主题归一:同主题同 id,不同主题不同 id', () {
      final a = aiRewriteSourceIdOf('Atomic Habits');
      final b = aiRewriteSourceIdOf('  atomic   habits ');
      final c = aiRewriteSourceIdOf('Tiny Habits');
      expect(a, b);
      expect(a, isNot(c));
      expect(a, startsWith(aiRewriteSourceIdPrefix));
      expect(aiRewriteSourceIdOf(''), '${aiRewriteSourceIdPrefix}untitled');
    });
  });

  group('提示词(纯函数)', () {
    test('带上关键词/档位/目标/真实线索编号,并写死"只输出 JSON"', () {
      final prompt = buildAiRewritePrompt(request());
      expect(prompt.system, contains('不是原文'));
      expect(prompt.system, contains('不许编造具体引文'));
      expect(prompt.system, contains('只输出 JSON'));
      // 2026-11-08：覆盖优先 + 先出 outline、字数不设固定上限
      expect(prompt.system, contains('先确定作品/主题'));
      expect(prompt.system, contains('outline'));
      expect(prompt.system, contains('不设固定字数'));
      expect(prompt.user, contains('原子习惯 atomic habits'));
      expect(prompt.user, contains('i+10 · 挑战'));
      expect(prompt.user, contains('四六级'));
      expect(prompt.user, contains('1. title=Atomic Habits'));
      expect(prompt.user, contains('3. title=The Power of Habit'));
      expect(prompt.user, contains('覆盖全部要点'));
    });

    test('没有任何线索时提示词不会让模型凭空编(输入侧仍由 generate 挡住)', () {
      final prompt = buildAiRewritePrompt(
        AiRewriteRequest(query: 'q', sources: const <AiRewriteSource>[]),
      );
      expect(prompt.user, contains('这次没有可用线索'));
      expect(prompt.user, isNot(contains('1. title=')));
    });
  });

  group('解析模型返回(纯函数,不合格返回 null)', () {
    test('标准 JSON(带围栏)解析成功:正文/中文标题/导读/来源/字数', () {
      final material = parseAiRewrite(validJson(), request: request());
      expect(material, isNotNull);
      expect(material!.topic, 'Small Habits, Big Changes');
      expect(material.titleCn, '微小习惯,巨大改变');
      expect(material.summaryCn, contains('不是原文'));
      expect(material.body, contains('habit'));
      expect(material.wordCount, aiRewriteCountWords(material.body));
      expect(material.usedSources, <AiRewriteSource>[sourceA, sourceB]);
      expect(material.bandLabel, 'i+10 · 挑战');
      expect(material.title, contains(aiRewriteMarker));
    });

    test('来源编号越界/模型自带 URL/编造来源 → 只映射真实候选', () {
      final material = parseAiRewrite(
        validJson(
          // used_sources 必须是合法 JSON:模型给数字编号 + 一条编造 URL
          usedSources: '[2, 9, "https://fake.example.com/invented"]',
        ),
        request: request(),
      );
      expect(material, isNotNull);
      expect(material!.usedSources, <AiRewriteSource>[sourceB]);
      expect(
        material.usedSources.any((s) => s.url.contains('fake.example.com')),
        isFalse,
      );
    });

    test('模型没给 used_sources → 退化为真实前 3 条(不造来源)', () {
      final material = parseAiRewrite(
        validJson(usedSources: null),
        request: request(),
      );
      expect(material, isNotNull);
      expect(material!.usedSources.length, 3);
      expect(material.usedSources.first.url, sourceA.url);
      expect(material.basisLimited, isFalse);
    });

    test('只有 1 条线索时 basisLimited=true(界面要明说依据有限)', () {
      final material = parseAiRewrite(
        validJson(usedSources: const <int>[1]),
        request: request(sources: const <AiRewriteSource>[sourceA]),
      );
      expect(material, isNotNull);
      expect(material!.basisLimited, isTrue);
    });

    test('正文太短 / 中文正文 / 没主题 → null(不把半成品塞给用户)', () {
      expect(
        parseAiRewrite(
          validJson(body: 'Habit change.'),
          request: request(),
        ),
        isNull,
      );
      expect(
        parseAiRewrite(
          validJson(body: List<String>.filled(40, '习惯改变是好事').join(' ')),
          request: request(),
        ),
        isNull,
      );
      expect(
        parseAiRewrite(
          '{"body": "${bodyOf(200)}"}',
          request: request(),
        ),
        isNull,
      );
      expect(parseAiRewrite('', request: request()), isNull);
      expect(parseAiRewrite('这不是 JSON', request: request()), isNull);
    });

    test('正文清洗:去围栏/井号/行内星号,压缩空行', () {
      final material = parseAiRewrite(
        validJson(
          body: '# Title\\n\\n**${bodyOf(200)}**\\n\\n\\n\\nTail.',
        ),
        request: request(),
      );
      expect(material, isNotNull);
      expect(material!.body, isNot(contains('#')));
      expect(material.body, isNot(contains('*')));
      expect(material.body, isNot(contains('\n\n\n')));
    });
  });

  group('来源与说明文本(入库/阅读共用)', () {
    test('正文末尾带来源链接 + 非原文 + 许可,三者缺一不可', () {
      final material = parseAiRewrite(validJson(), request: request())!;
      final text = buildAiRewriteProvenanceText(material);
      expect(text, contains(material.body));
      expect(text, contains('非原文'));
      expect(text, contains(sourceA.url));
      expect(text, contains(sourceB.url));
      expect(text, contains(aiRewriteLicense));
      expect(text, contains('不是原文'));
    });
  });

  group('入库行(纯函数)', () {
    test('source=ai / title 带标注 / license 标注 / url 保留来源链接', () {
      final material = parseAiRewrite(validJson(), request: request())!;
      final row = buildAiRewriteMaterialRow(material);
      expect(row['kind'], 'article');
      expect(row['source'], 'ai');
      expect('${row['source_id']}', startsWith(aiRewriteSourceIdPrefix));
      expect('${row['title']}', contains(aiRewriteMarker));
      expect('${row['title']}', isNot(contains('*')));
      expect('${row['license']}', contains('AI 改写'));
      expect('${row['license']}', contains('仅供个人学习'));
      expect(row['url'], sourceA.url);
      expect(row['word_count'], material.wordCount);
      expect(row['difficulty_json'], isNull, reason: '没算难度就不写难度 JSON');
    });

    test('有真实分析时填覆盖率/CEFR/时长与 difficulty_json', () {
      final material = parseAiRewrite(validJson(), request: request())!;
      const analysis = MaterialAnalysis(
        wordCount: 210,
        uniqueWords: 90,
        newTypes: 12,
        estMinutes: 3,
        coverage: 0.97,
        knownTokenRatio: 0.97,
        newWordDensity: 3,
        cefr: 'B1',
        topNewWords: <String>['habit'],
      );
      final row = buildAiRewriteMaterialRow(material, analysis: analysis);
      expect(row['word_count'], 210);
      expect(row['cefr'], 'B1');
      expect(row['coverage'], 0.97);
      expect(row['est_minutes'], 3);
      expect('${row['difficulty_json']}', contains('known_token_ratio'));
    });
  });

  group('MaterialAiRewriter(注入 handler + measurer,不碰网络)', () {
    test('没有线索但给了作品/主题 → 用模型知识改写(2026-11-08 新逻辑)', () async {
      var called = false;
      final rewriter = MaterialAiRewriter(
        handler: (_, _) async {
          called = true;
          return validJson();
        },
        measurer: (_) async => const AiRewriteMeasurement(wordCount: 200),
      );
      final outcome = await rewriter.generate(
        AiRewriteRequest(
          query: '原子习惯',
          topicHint: '原子习惯 / Atomic Habits',
          sources: const <AiRewriteSource>[],
        ),
      );
      expect(outcome.ok, isTrue);
      expect(called, isTrue);
    });

    test('没有线索也没有作品/主题 → 失败且不调用模型', () async {
      var called = false;
      final rewriter = MaterialAiRewriter(
        handler: (_, _) async {
          called = true;
          return validJson();
        },
        measurer: (_) async => const AiRewriteMeasurement(wordCount: 200),
      );
      final outcome = await rewriter.generate(
        AiRewriteRequest(query: '', sources: const <AiRewriteSource>[]),
      );
      expect(outcome.ok, isFalse);
      expect(called, isFalse);
    });

    test('成功:解析 + 本地实数替换模型自报字数,覆盖率来自 measurer', () async {
      String? system;
      String? user;
      final rewriter = MaterialAiRewriter(
        handler: (s, u) async {
          system = s;
          user = u;
          return validJson();
        },
        measurer: (body) async => AiRewriteMeasurement(
          wordCount: 207,
          estMinutes: 3,
          coverage: 0.962,
          cefr: 'B1',
        ),
      );
      final outcome = await rewriter.generate(request());
      expect(outcome.ok, isTrue);
      final material = outcome.material!;
      expect(material.wordCount, 207, reason: '字数必须是本地实数');
      expect(material.coverage, closeTo(0.962, 1e-9));
      expect(material.cefr, 'B1');
      expect(material.estMinutes, 3);
      expect(system, contains('只输出 JSON'));
      expect(user, contains('原子习惯'));
      expect(material.metricLine, contains('覆盖率 96%'));
      expect(material.metricLine, contains('按 i+10 · 挑战 档改写'));
    });

    test('模型没返回/抛异常 → 人话失败原因(不抛到界面)', () async {
      final noAnswer = MaterialAiRewriter(
        handler: (_, _) async => null,
        measurer: (_) async => const AiRewriteMeasurement(wordCount: 200),
      );
      final first = await noAnswer.generate(request());
      expect(first.ok, isFalse);
      expect(first.error, contains('API'));

      final throwing = MaterialAiRewriter(
        handler: (_, _) async => throw Exception('network down'),
        measurer: (_) async => const AiRewriteMeasurement(wordCount: 200),
      );
      final second = await throwing.generate(request());
      expect(second.ok, isFalse);
      expect(second.error, contains('API'));
    });

    test('模型返回不合格内容 → 失败原因说清"不硬塞给你"', () async {
      final rewriter = MaterialAiRewriter(
        handler: (_, _) async => '抱歉,我不能写这个。',
        measurer: (_) async => const AiRewriteMeasurement(wordCount: 200),
      );
      final outcome = await rewriter.generate(request());
      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('可读的英文材料'));
    });

    test('measure 失败(返回 null)时仍给字数(本地数),不大幅编覆盖率', () async {
      final rewriter = MaterialAiRewriter(
        handler: (_, _) async => validJson(),
        measurer: (_) async => null,
      );
      final outcome = await rewriter.generate(request());
      expect(outcome.ok, isTrue);
      expect(outcome.material!.wordCount, aiRewriteCountWords(outcome.material!.body));
      expect(outcome.material!.coverage, isNull);
    });
  });
}
