import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/screens/input/widgets/follow_up_models.dart';
import 'package:readflow/utils/follow_up_context.dart';

/// 追问上下文构建回归测试(v1.3.0 问题 5):
/// 原实现只拼"已识别词汇",全文翻译模式下为空 → AI 回复"没收到内容"。
/// 现在必须包含:词汇列表 + 全文翻译段落,两者都要时都在。
/// v1.4.2 追加:buildFollowUpHistory——role 映射(ai→assistant)是
/// "追问第二问必 400" 的回归测试。
void main() {
  FollowUpMessage user(String t) => FollowUpMessage(role: 'user', content: t);
  FollowUpMessage ai(String t, {bool streaming = false}) =>
      FollowUpMessage(role: 'ai', content: t, streaming: streaming);

  group('buildFollowUpHistory — 追问历史(role 映射+截断)', () {
    test('ai → assistant 映射(直接发 ai 会 400,第二问必崩的根因)', () {
      final msgs = [
        user('第一问'),
        ai('第一答'),
        user('第二问'),
        ai('', streaming: true), // 第二答占位(流式生成中)
      ];
      final h = buildFollowUpHistory(msgs, 3);
      expect(h.length, 2);
      expect(h[0], {'role': 'user', 'content': '第一问'});
      expect(h[1], {'role': 'assistant', 'content': '第一答'});
      expect(h.any((m) => m['role'] == 'ai'), isFalse); // 不存在裸 role=ai
    });

    test('首次提问(无历史)→ 空列表', () {
      final msgs = [user('问题'), ai('', streaming: true)];
      expect(buildFollowUpHistory(msgs, 1), isEmpty);
    });

    test('编辑重发:排除被替换的问题自身', () {
      final msgs = [
        user('旧问1'),
        ai('答1'),
        user('修改后的当前问'), // aiMsgIndex-1 = 当前问题,不入历史
        ai('', streaming: true),
      ];
      final h = buildFollowUpHistory(msgs, 3);
      expect(h.map((m) => m['content']).toList(), ['旧问1', '答1']);
    });

    test('最多 20 条,超出截断保留最近', () {
      final msgs = <FollowUpMessage>[
        for (int i = 0; i < 30; i++) user('u$i'),
        ai('', streaming: true),
      ];
      // aiMsgIndex=30:最后一条 user(u29)是当前问题被排除
      // 历史 = u9..u28(20 条)
      final h = buildFollowUpHistory(msgs, 30);
      expect(h.length, 20);
      expect(h.first['content'], 'u9');
      expect(h.last['content'], 'u28');
    });
  });

  Vocabulary word(String w, {String? t, String? sentence}) => Vocabulary(
        word: w,
        translation: t,
        originalSentence: sentence,
      );

  test('全文翻译模式:无词汇但有翻译段落 → 上下文含翻译内容', () {
    final ctx = buildFollowUpContext(
      results: [],
      paragraphs: [
        {'original': 'Sharp-eyed fictions express the gap between the two.',
         'translation': '敏锐的小说表达了二者之间的差距。'},
      ],
    );
    expect(ctx, contains('页面全文翻译'));
    expect(ctx, contains('Sharp-eyed fictions express the gap'));
    expect(ctx, contains('敏锐的小说表达了二者之间的差距'));
    // 不应出现"已识别的词汇"(空列表不输出空标题)
    expect(ctx, isNot(contains('已识别的词汇')));
  });

  test('圈画模式:有词汇无翻译 → 词汇列表+出处例句', () {
    final ctx = buildFollowUpContext(
      results: [
        word('unfettered', t: '无拘束的',
            sentence: 'The mind wants unfettered freedom.'),
        word('compound with', t: '由…构成', sentence: 'Copper compounds with sulfur.'),
        Vocabulary(word: 'This is a full sentence.', wordType: 'sentence',
            translation: '这是一个完整句子。'),
      ],
      paragraphs: [],
    );
    expect(ctx, contains('已识别的词汇'));
    expect(ctx, contains('- unfettered: 无拘束的 (word)'));
    expect(ctx, contains('例句：The mind wants unfettered freedom.'));
    expect(ctx, contains('(sentence)'));
    expect(ctx, isNot(contains('页面全文翻译')));
  });

  test('词汇+翻译都有 → 两部分都在,顺序词汇在前', () {
    final ctx = buildFollowUpContext(
      results: [word('elegy', t: '挽歌')],
      paragraphs: [
        {'original': 'An elegy is a poem.', 'translation': '挽歌是一种诗。'},
      ],
    );
    final vocabIdx = ctx.indexOf('已识别的词汇');
    final paraIdx = ctx.indexOf('页面全文翻译');
    expect(vocabIdx, greaterThan(-1));
    expect(paraIdx, greaterThan(vocabIdx));
  });

  test('全部为空 → 空字符串(调用方会以图片兜底或提示用户)', () {
    expect(buildFollowUpContext(results: [], paragraphs: []), isEmpty);
  });
}
