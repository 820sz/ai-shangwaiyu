// 阅读器「追问材料」上下文构建 · 纯函数单测（2026-11-08 / task-21 A1）
//
// 用户真机截图：AI 回复"你给的识别材料里，正文节选是空的——只有标题和元信息
// （2011 词、B2、覆盖率 84.9%），没有实际段落文本"。
//
// 根因：旧实现按块累加、`if (body.length + t.length > 6000) break;`；正文按
// 2500 词一块入库，2011 词的材料只有 1 块（约 1.2 万字符），第一次循环就 break
// → 正文为空。下面几条测试就是把这个真机 bug 钉住。
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/screens/input/widgets/quick_replies.dart';
import 'package:readflow/screens/input/widgets/reader_follow_up_context.dart';

String _longText(String marker, int chars) {
  final sb = StringBuffer(marker);
  while (sb.length < chars) {
    sb.write(' the quiet hour rewards attention and punishes the busy mind.');
  }
  return sb.toString();
}

void main() {
  group('整篇追问：正文必须真的传进去（旧实现单块 >6000 字符就为空）', () {
    test('单块 1.2 万字符（真机 2011 词那种单块材料）→ 上下文含正文', () {
      final ctx = buildReaderFollowUpContext(
        title: 'The Quiet Hour',
        sourceUrl: 'https://example.com/quiet',
        difficultyLine: '篇幅 2011 词 · B2 · 我的已知词覆盖率 84.9%',
        chunkTitles: const ['The quiet hour'],
        // 真机那篇：单块 ≈ 1.2 万字符
        chunkTexts: [_longText('MARKER_QUIET_HOUR', 12000)],
        unitTexts: const [],
        translations: const {},
        currentChunk: 0,
      );
      expect(ctx, contains('材料:The Quiet Hour'));
      expect(ctx, contains('2011 词'));
      // 关键断言：正文非空（正是旧实现丢掉的）
      expect(ctx, contains('MARKER_QUIET_HOUR'));
      expect(ctx, contains('正文节选:'));
      expect(ctx.length, greaterThan(1500));
    });

    test('优先喂当前在读小节（长文第 3 节，不是只喂全文开头）', () {
      final chunks = <String>[
        _longText('CHUNK_ONE', 5000),
        _longText('CHUNK_TWO', 5000),
        _longText('SECTION_THREE_MARKER', 3000),
        _longText('CHUNK_FOUR', 3000),
      ];
      final ctx = buildReaderFollowUpContext(
        title: 'Quiet',
        sourceUrl: '',
        difficultyLine: '',
        chunkTitles: const ['One', 'Two', 'Three', 'Four'],
        chunkTexts: chunks,
        unitTexts: const [],
        translations: const {},
        currentChunk: 2,
      );
      expect(ctx, contains('当前在读小节:Three'));
      expect(ctx, contains('SECTION_THREE_MARKER'));
    });

    test('块正文为空（异常老数据）→ 用段落单元兜底，仍非空', () {
      final ctx = buildReaderFollowUpContext(
        title: 'T',
        sourceUrl: '',
        difficultyLine: '',
        chunkTitles: const ['s1'],
        chunkTexts: const [''],
        unitTexts: const ['UNIT_FALLBACK_TEXT'],
        translations: const {},
        currentChunk: 0,
      );
      expect(ctx, contains('UNIT_FALLBACK_TEXT'));
      expect(ctx, isNot(contains('正文暂未读取到')));
    });

    test('真的没有正文 → 明确写出来，不让模型以为被吞了', () {
      final ctx = buildReaderFollowUpContext(
        title: 'Empty',
        sourceUrl: '',
        difficultyLine: '篇幅 0 词',
        chunkTitles: const [],
        chunkTexts: const [],
        unitTexts: const [],
        translations: const {},
      );
      expect(ctx, contains('正文暂未读取到'));
    });
  });

  group('单段追问（点译文）：仍然只喂本段 + 邻段', () {
    test('本段原文 / 页面译文 / 小节标题 / 邻段都在', () {
      final ctx = buildReaderFollowUpContext(
        title: 'T',
        sourceUrl: '',
        difficultyLine: '',
        chunkTitles: const ['Section A', 'Section B'],
        chunkTexts: const ['aaa', 'bbb'],
        unitTexts: const ['PREV_SENTENCE', 'TARGET_SENTENCE', 'NEXT_SENTENCE'],
        translations: const {1: '目标句子的中文译文'},
        pinnedUnit: 1,
        pinnedChunk: 1,
      );
      expect(ctx, contains('这次追问只针对第 2/3 段'));
      expect(ctx, contains('小标题:Section B'));
      expect(ctx, contains('本段原文:'));
      expect(ctx, contains('TARGET_SENTENCE'));
      expect(ctx, contains('目标句子的中文译文'));
      expect(ctx, contains('PREV_SENTENCE'));
      expect(ctx, contains('NEXT_SENTENCE'));
    });
  });

  group('阅读器快捷提问：只留「梳理内容」「评价材料」', () {
    test('阅读器列表恰好两个，且不含英英词典/逐句翻译', () {
      expect(QuickReplies.reader.map((r) => r.label).toList(),
          ['梳理内容', '评价材料']);
      final labels = QuickReplies.reader.map((r) => r.label).toList();
      expect(labels, isNot(contains('英英词典')));
      expect(labels, isNot(contains('逐句翻译')));
      // 每个都有真正要发出去的 prompt
      for (final r in QuickReplies.reader) {
        expect(r.prompt.trim().isNotEmpty, isTrue);
      }
    });

    test('其它页面默认那排不受影响（识图/写译仍是 5 个）', () {
      expect(QuickReplies.defaults.length, 5);
      expect(QuickReplies.defaults.map((r) => r.label),
          contains('英英词典'));
    });
  });
}
