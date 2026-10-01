import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/material_blocks.dart';

/// 内容块层的测试(v2.9,用户第 3(2)/3(5)/4 条)。
///
/// 这一层的两个纯函数直接决定用户在界面上看到什么,所以断言都压在**具体数字**
/// 与**具体结构**上,而不是"不抛异常就算过":
/// - [analyzeBestKinds] 给不出"为什么推荐",界面上的推荐按钮就是个黑盒;
/// - [parsePayload] 判错一点,用户看到的就是空表格 / 错位的时间线;
/// - [planTranslation] 算错范围,用户选"当前段"会被翻掉一整篇。
void main() {
  group('按内容推荐形式(analyzeBestKinds)', () {
    test('数字/对比多 → 首推表格,并且说清有几处数字', () {
      const text = 'Revenue rose 12% in 2023, while costs fell 7% to 3.5 million. '
          'The team grew 24% and output was 18 units per 40 hours. '
          'However margins dropped 5 points compared with last year.';
      final list = analyzeBestKinds(text);
      expect(list, isNotEmpty);
      expect(list.first.kind, MaterialBlockKind.table);
      // 推荐理由必须带**具体数字**(用户要看到依据):12% / 7% / 3.5 / 24% / 18 / 40 / 5 = 7 处
      expect(list.first.why, contains('数字'));
      expect(list.first.why, contains('7 处'));
      expect(describeSuggestion(list.first), contains('表格'));
    });

    test('一串年份 → 首推时间线,且年份不被当成"数字多"而误推表格', () {
      const text = '1945 ended the war. In 1961 the wall was built. '
          'By 1972 the treaty was signed. The year 1991 changed everything.';
      final list = analyzeBestKinds(text);
      expect(list.first.kind, MaterialBlockKind.timeline);
      // 4 个年份不该触发"数字很多 → 表格"
      final table = list.where((s) => s.kind == MaterialBlockKind.table);
      expect(table, isEmpty);
      expect(list.first.why, contains('1945'));
    });

    test('出现步骤词 → 推荐要点卡,理由里带步骤词数量', () {
      const text = 'First you download the file. Second you unzip it. '
          'Next you open the folder. Finally you run the script. '
          'This is how the installer works.';
      final list = analyzeBestKinds(text);
      final points = list.where((s) => s.kind == MaterialBlockKind.points);
      expect(points, isNotEmpty);
      expect(points.first.why, contains('步骤'));
      // 没有数字也没有年份 → 表格/时间线都不该进榜
      expect(list.any((s) => s.kind == MaterialBlockKind.timeline), isFalse);
    });

    test('专有名词多 → 推荐思维导图', () {
      const text = 'Einstein admired Newton, while Bohr argued with Heisenberg. '
          'Planck, Curie, Rutherford, Faraday and Maxwell built the field. '
          'Feynman later explained Dirac to students.';
      final list = analyzeBestKinds(text);
      expect(list.any((s) => s.kind == MaterialBlockKind.mindmap), isTrue);
      expect(
        list.firstWhere((s) => s.kind == MaterialBlockKind.mindmap).why,
        contains('专有名词'),
      );
    });

    test('任何时候都至少给两条推荐(界面不会出现空列表)', () {
      expect(analyzeBestKinds('').length, greaterThanOrEqualTo(1));
      expect(analyzeBestKinds('Hello world.').length, greaterThanOrEqualTo(2));
    });

    test('推荐按分数从高到低排(界面直接取第一条当默认)', () {
      const text = '1945 ended the war. In 1961 the wall was built. '
          'By 1972 the treaty was signed.';
      final list = analyzeBestKinds(text);
      for (var i = 1; i < list.length; i++) {
        expect(list[i - 1].score, greaterThanOrEqualTo(list[i].score));
      }
    });

    test('detectFromText:够长的文本给形式,过短的不硬推', () {
      expect(detectFromText('Hello.'), isNull);
      expect(
        detectFromText(
          'Revenue rose 12% while costs fell 7% and output grew 24% '
          'compared with 2023, 2024 and 2025 plans.',
        ),
        isNotNull,
      );
    });

    test('五种形式都有中文名 / 图标 / 一句话说明(界面靠它们区分)', () {
      for (final k in MaterialBlockKind.values) {
        expect(k.label.isNotEmpty, isTrue);
        expect(k.hint.isNotEmpty, isTrue);
        expect(k.id, isNot(contains(' ')));
        expect(MaterialBlockKind.byId(k.id), k);
      }
      expect(MaterialBlockKind.byId('nope'), isNull);
      expect(MaterialBlockKind.byId(null), isNull);
    });
  });

  group('AI 返回解析(extractJsonObject / parsePayload)', () {
    test('抠 JSON:裸 JSON / ```json 围栏 / 前后有说明文字', () {
      expect(extractJsonObject('{"a":1}'), {'a': 1});
      expect(extractJsonObject('```json\n{"a":2}\n```'), {'a': 2});
      expect(
        extractJsonObject('好的,这是结果:{"a":3} 希望有用'),
        {'a': 3},
      );
    });

    test('抠 JSON:空串 / 彻底不是 JSON / 数组 → 空 Map(绝不抛)', () {
      expect(extractJsonObject(''), isEmpty);
      expect(extractJsonObject('完全不是 JSON'), isEmpty);
      expect(extractJsonObject('{"a":'), isEmpty);
      expect(extractJsonObject('[1,2,3]'), isEmpty);
    });

    test('表格:列 + 行,短行自动补齐到最宽,单列不算表格', () {
      final data = parsePayload(
        MaterialBlockKind.table,
        '{"title":"产量对比","columns":["年份","产量"],"rows":[["1945","12"],["1961"]]}',
      );
      expect(data, isNotNull);
      expect(data!['title'], '产量对比');
      expect(data['columns'], ['年份', '产量']);
      expect(data['width'], 2);
      final rows = data['rows'] as List;
      expect(rows.length, 2);
      expect(rows[1], ['1961', ''], reason: '缺的单元格补空串,表格才不会塌');

      expect(
        parsePayload(MaterialBlockKind.table, '{"columns":["只有一列"],"rows":[["a"]]}'),
        isNull,
        reason: '单列不叫表格 —— 宁可报错也不显示一个只有一列的"表格"',
      );
    });

    test('思维导图:分支多于 8 个会收敛;子项最多留 4 个', () {
      final branches = [
        for (var i = 0; i < 12; i++)
          '{"label":"分支$i","children":["a","b","c","d","e","f"]}',
      ].join(',');
      final data = parsePayload(
        MaterialBlockKind.mindmap,
        '{"center":"中心","branches":[$branches]}',
      );
      expect(data, isNotNull);
      expect((data!['branches'] as List).length, 8);
      final first = (data['branches'] as List).first as Map;
      expect((first['children'] as List).length, 4, reason: '层级 >3 层要收敛显示');
    });

    test('思维导图:只有中心没有分支 → null(不显示半张图)', () {
      expect(
        parsePayload(MaterialBlockKind.mindmap, '{"center":"只有中心"}'),
        isNull,
      );
    });

    test('时间线:按年份升序排,没有年份的按原顺序兜底', () {
      final data = parsePayload(
        MaterialBlockKind.timeline,
        '{"events":[{"time":"1972","text":"签约"},'
            '{"time":"1945","text":"战争结束"},'
            '{"time":"1961","text":"建墙"}]}',
      );
      expect(data, isNotNull);
      final events = data!['events'] as List;
      expect(
        [for (final e in events) (e as Map)['time']],
        ['1945', '1961', '1972'],
      );
    });

    test('时间线:事件缺正文的条目被丢掉', () {
      final data = parsePayload(
        MaterialBlockKind.timeline,
        '{"events":[{"time":"1945","text":"战争结束"},{"time":"1961","text":""}]}',
      );
      expect(data, isNotNull);
      expect((data!['events'] as List).length, 1);
    });

    test('要点卡:只要有一条能用的就成,全空则 null', () {
      final ok = parsePayload(
        MaterialBlockKind.points,
        '{"title":"三个要点","items":[{"title":"成本","text":"下降了 7%"},{"title":"","text":""}]}',
      );
      expect(ok, isNotNull);
      expect((ok!['items'] as List).length, 1);
      expect(
        parsePayload(MaterialBlockKind.points, '{"items":[{"title":"","text":""}]}'),
        isNull,
      );
    });

    test('自测卡:问题或答案缺一个就丢掉,最多留 8 道', () {
      final items = [
        for (var i = 0; i < 12; i++)
          '{"question":"Q$i","answer":"A$i"}',
        '{"question":"没答案"}',
        '{"answer":"没问题"}',
      ].join(',');
      final data = parsePayload(MaterialBlockKind.quiz, '{"items":[$items]}');
      expect(data, isNotNull);
      expect((data!['items'] as List).length, 8);
    });

    test('每种形式的 schema 示例都写进了提示词(严格 JSON 的前提)', () {
      for (final k in MaterialBlockKind.values) {
        final prompt = buildSystemPrompt(k);
        expect(prompt, contains('JSON'));
        expect(prompt, contains('只输出'));
      }
      expect(buildSystemPrompt(MaterialBlockKind.table), contains('columns'));
      expect(buildSystemPrompt(MaterialBlockKind.mindmap), contains('branches'));
      expect(buildSystemPrompt(MaterialBlockKind.timeline), contains('events'));
      expect(buildSystemPrompt(MaterialBlockKind.points), contains('items'));
      expect(buildSystemPrompt(MaterialBlockKind.quiz), contains('question'));
    });

    test('落库 payload 能原样读回来(fromRow 往返)', () {
      final data = parsePayload(
        MaterialBlockKind.points,
        '{"title":"要点","items":[{"title":"成本","text":"下降 7%"}]}',
      )!;
      final draft = MaterialBlockDraft(
        kind: MaterialBlockKind.points,
        title: '要点',
        data: data,
        chunkIndex: 3,
      );
      final row = <String, Object?>{
        'id': 7,
        'kind': 'points',
        'title': '要点',
        'payload': draft.toPayloadJson(),
        'chunk_index': 3,
      };
      final back = MaterialBlockDraft.fromRow(row);
      expect(back, isNotNull);
      expect(back!.kind, MaterialBlockKind.points);
      expect(back.chunkIndex, 3);
      expect(back.id, 7);
      expect(back.sourceLabel, 'AI 整理 · 基于第 4 段');
      expect(jsonEncode(back.data), jsonEncode(data));
      expect(
        MaterialBlockDraft(
          kind: MaterialBlockKind.points,
          title: 't',
          data: const {},
        ).sourceLabel,
        'AI 整理 · 基于整篇',
      );
    });

    test('库里的坏数据只让那一块消失,不抛异常', () {
      expect(
        MaterialBlockDraft.fromRow({
          'id': 1,
          'kind': 'unknown_kind',
          'title': 'x',
          'payload': '{}',
          'chunk_index': 0,
        }),
        isNull,
      );
      expect(
        MaterialBlockDraft.fromRow({
          'id': 2,
          'kind': 'table',
          'title': 'x',
          'payload': '这不是 JSON',
          'chunk_index': 0,
        }),
        isNull,
      );
    });

    test('标题为空时回落到形式名(卡片头不会空着)', () {
      final draft = MaterialBlockDraft.fromRow({
        'id': 3,
        'kind': 'quiz',
        'title': '   ',
        'payload': '{"items":[{"question":"q","answer":"a"}]}',
        'chunk_index': -1,
      });
      expect(draft!.title, '自测卡');
    });
  });

  group('逐段翻译的范围(planTranslation)', () {
    test('当前段:只翻一段', () {
      final p = planTranslation(
        scope: TranslateScope.current,
        current: 5,
        chunkCount: 40,
      );
      expect(p.indices, [5]);
      expect(p.total, 1);
    });

    test('前后各 3 段:边界处自动收窄', () {
      final mid = planTranslation(
        scope: TranslateScope.around,
        current: 10,
        chunkCount: 40,
      );
      expect(mid.indices, [7, 8, 9, 10, 11, 12, 13]);
      final head = planTranslation(
        scope: TranslateScope.around,
        current: 0,
        chunkCount: 40,
      );
      expect(head.indices, [0, 1, 2, 3]);
      final tail = planTranslation(
        scope: TranslateScope.around,
        current: 39,
        chunkCount: 40,
      );
      expect(tail.indices, [36, 37, 38, 39]);
    });

    test('当前章 / 前 20 段:到尾部自动截断', () {
      final p = planTranslation(
        scope: TranslateScope.chapter,
        current: 35,
        chunkCount: 40,
      );
      expect(p.total, 5);
      expect(p.indices, [35, 36, 37, 38, 39]);
    });

    test('整篇:0..N-1', () {
      final p = planTranslation(
        scope: TranslateScope.all,
        current: 3,
        chunkCount: 4,
      );
      expect(p.indices, [0, 1, 2, 3]);
      expect(p.rangeStart, 0);
      expect(p.rangeEnd, 3);
    });

    test('已经翻好的段不重复翻;失败的段会重试', () {
      final p = planTranslation(
        scope: TranslateScope.around,
        current: 3,
        chunkCount: 20,
        alreadyDone: {0, 1, 2, 3, 4},
        failed: {2},
      );
      expect(p.indices, [2, 5, 6], reason: '2 是失败的 → 重试;0/1/3/4 已有译文 → 跳过');
    });

    test('全都翻好了 → 空计划(界面提示"已经翻好了")', () {
      final p = planTranslation(
        scope: TranslateScope.all,
        current: 0,
        chunkCount: 3,
        alreadyDone: {0, 1, 2},
      );
      expect(p.isEmpty, isTrue);
      expect(p.total, 0);
    });

    test('越界的 current 会被夹到合法范围(不会算出一个空段)', () {
      final p = planTranslation(
        scope: TranslateScope.current,
        current: 99,
        chunkCount: 5,
      );
      expect(p.indices, [4]);
      final neg = planTranslation(
        scope: TranslateScope.current,
        current: -3,
        chunkCount: 5,
      );
      expect(neg.indices, [0]);
    });

    test('没有正文时不崩,给空计划', () {
      final p = planTranslation(
        scope: TranslateScope.all,
        current: 0,
        chunkCount: 0,
      );
      expect(p.isEmpty, isTrue);
      expect(p.rangeEnd, -1);
    });
  });

  group('范围提示与耗时估算(用户要"提前知道要花多久")', () {
    test('耗时估算随段数增长,1 段也在 1 分钟内', () {
      expect(estimateTranslationSeconds(0), 0);
      expect(formatEstimate(estimateTranslationSeconds(1)), '不到 1 分钟');
      expect(estimateTranslationSeconds(40), greaterThan(estimateTranslationSeconds(10)));
      expect(formatEstimate(estimateTranslationSeconds(40)), contains('分钟'));
    });

    test('整篇提示带总段数与待翻段数', () {
      final hint = translatePlanHint(
        TranslateScope.all,
        chunkCount: 40,
        pending: 37,
        translated: 3,
      );
      expect(hint, contains('共 40 段'));
      expect(hint, contains('待翻 37 段'));
      expect(hint, contains('已翻 3 段'));
    });

    test('待翻为 0 时说"都翻好了",而不是显示 0 段 0 分钟', () {
      expect(
        translatePlanHint(TranslateScope.all,
            chunkCount: 10, pending: 0, translated: 10),
        contains('都翻好了'),
      );
      expect(
        translatePlanHint(TranslateScope.current,
            chunkCount: 10, pending: 0, translated: 10),
        contains('已经翻好'),
      );
    });

    test('没有正文时给一句人话', () {
      expect(
        translatePlanHint(TranslateScope.all,
            chunkCount: 0, pending: 0, translated: 0),
        contains('还没有正文'),
      );
    });

    test('小批量不提醒,大批量提醒可取消', () {
      expect(bulkTranslateWarning(20), isEmpty);
      expect(bulkTranslateWarning(200), contains('取消'));
    });
  });
}
