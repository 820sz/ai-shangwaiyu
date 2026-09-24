import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/vision_guard.dart';

/// 识图校验层的测试。
///
/// 这些断言全部来自**用户实测遇到的真实错误**(2026-09-24 反馈 + 5 张翻拍样本):
/// 手写中文批注被当成词条、同一个词出现两次、一整页批注单词被标成短语、
/// 长句被截断成"开头…省略号"、编出图上没有的词。每一条都必须被本地规则挡住,
/// 不能继续指望模型"自觉"。
void main() {
  Map<String, dynamic> item(
    String word, {
    String type = 'word',
    String sentence = '',
    String line = '',
  }) =>
      {
        'word': word,
        'word_type': type,
        'original_sentence': sentence,
        if (line.isNotEmpty) 'line': line,
      };

  group('类型本地判定(不再全信模型)', () {
    test('单个 token 一律是单词 —— 修"一整页单词被标成短语"', () {
      expect(VisionGuard.classify('blur'), 'word');
      expect(VisionGuard.classify('  Nevertheless  '), 'word');
      expect(VisionGuard.classify('nature-versus-nurture'), 'word');
      expect(VisionGuard.classify('"vault"'), 'word');
    });

    test('2-3 个词且无句末标点 → 短语', () {
      expect(VisionGuard.classify('began to blur'), 'phrase');
      expect(VisionGuard.classify('cerebral power'), 'phrase');
      expect(VisionGuard.classify('in a sweat'), 'phrase');
    });

    test('有句末标点 → 句子(不论长短)', () {
      expect(VisionGuard.classify('It never is.'), 'sentence');
      expect(VisionGuard.classify('What matters things they do?'), 'sentence');
    });

    test('4 词以上:有小句标志词才算句子', () {
      expect(
        VisionGuard.classify(
            'Inventorying memory is the first and most fundamental form of research'),
        'sentence',
      );
      expect(
        VisionGuard.classify('the cerebral power to punch home the truth'),
        'phrase',
        reason: '长名词短语不该被当成句子',
      );
    });

    test('模型说 phrase 但实际是单词 → 被本地纠正并计数', () {
      final r = VisionGuard.apply([
        item('blur', type: 'phrase'),
        item('vault', type: 'phrase'),
      ]);
      expect(r.kept.map((e) => e['word_type']), everyElement('word'));
      expect(r.typeFixed, 2);
      expect(r.note, contains('纠正类型 2 条'));
    });
  });

  group('丢弃规则(都要给得出原因)', () {
    test('手写中文批注**保留**(用户要拿它补录,2026-09-24 纠正)', () {
      final r = VisionGuard.apply([
        item('自恋 n.'),
        item('普遍/寻常'),
        item('blur'),
      ]);
      expect(r.kept, hasLength(3), reason: '中文批注不能被丢掉');
      expect(r.kept.map((e) => e['word']), containsAll(['自恋 n.', '普遍/寻常', 'blur']));
      expect(r.dropped, isEmpty);
    });

    test('词面与证据行都相同 → 判为模型复读,丢弃', () {
      final r = VisionGuard.apply([
        item('vault', line: 'the same mental vault'),
        item('vault', line: 'the same mental vault'),
        item(' vault '),
      ]);
      expect(r.kept, hasLength(1));
      expect(r.dropped, hasLength(2));
      expect(r.dropped.map((d) => d.reason), everyElement('重复条目'));
    });

    test('同一个词在不同位置各标一次 → 合并成一条并记出现次数', () {
      final r = VisionGuard.apply([
        item('apple', line: 'An apple a day keeps the doctor away.'),
        item('apple', line: 'She ate an apple on the way home.'),
      ]);
      expect(r.kept, hasLength(1), reason: '同一个词只留一条词条');
      final kept = r.kept.single;
      expect(kept['occurrence_count'], 2);
      expect((kept['occurrences'] as List), hasLength(2));
      expect(r.mergedOccurrences, 1);
      expect(r.note, contains('合并重复出现 1 处'));
    });

    test('被更长条目按词边界包含 → 丢短的("art" 不在 "artist" 里被判重复)', () {
      final r = VisionGuard.apply([
        item('began to blur'),
        item('blur'),
        item('artist'),
        item('art'),
      ]);
      final kept = r.kept.map((e) => e['word']).toList();
      expect(kept, contains('began to blur'));
      expect(kept, contains('artist'));
      expect(kept, contains('art'), reason: 'art 是独立单词,不是 artist 的一部分');
      expect(r.dropped.map((d) => d.text), contains('blur'));
    });

    test('截断词条:有完整句就替换,没有就丢掉(不留半句进生词本)', () {
      final r = VisionGuard.apply([
        item('Inventorying memory is the first…',
            sentence:
                'Inventorying memory is the first and most fundamental form of research.'),
        item('The dynamic of punishment…'),
      ]);
      expect(r.kept, hasLength(1));
      expect(r.kept.first['word'],
          'Inventorying memory is the first and most fundamental form of research.');
      expect(r.truncationFixed, 1);
      expect(r.dropped.single.reason, '截断/省略号');
      expect(r.note, contains('补全截断 1 条'));
    });

    test('空条目/太短/带数字的伪词都丢掉,且原因分得清', () {
      final r = VisionGuard.apply([
        item(''),
        item('   '),
        item('— — —'),
        item('a'),
        item('word12'),
      ]);
      expect(r.kept, isEmpty);
      final reasons = r.dropped.map((d) => d.reason).toList();
      expect(reasons.where((x) => x == '空条目').length, 2);
      expect(reasons.where((x) => x == '太短').length, 2,
          reason: '— — — 与 a 都是"没有足够的字母"');
      expect(reasons, contains('不是英文'), reason: 'word12 混了数字');
    });
  });

  group('证据行核对(把"盲盒"变成"可解释")', () {
    test('行里找不到该词条 → 标记存疑但保留(不误删真条目)', () {
      final r = VisionGuard.apply([
        item('vault', line: 'These sources begin to blur because memory stores them'),
        item('reservoir',
            line: 'Without a reservoir of unique knowledge, you can only imitate others'),
      ]);
      expect(r.kept, hasLength(2));
      expect(r.unverified, 1);
      expect(r.kept.first['needs_review'], isTrue);
      expect(r.kept.last.containsKey('needs_review'), isFalse);
      expect(r.note, contains('存疑 1 条'));
    });

    test('行内确有该词(忽略大小写/标点) → 不算存疑', () {
      final r = VisionGuard.apply([
        item('Vault', line: 'sources begin to blur because memory stores them in the same mental VAULT.'),
      ]);
      expect(r.unverified, 0);
    });

    test('没给行信息的条目不算存疑(模型没义务给)', () {
      final r = VisionGuard.apply([item('blur')]);
      expect(r.unverified, 0);
      expect(r.note, isNull, reason: '没有任何问题时不显示校验行');
    });
  });

  group('上限与说明', () {
    test('超过上限就截断(防止模型刷屏)', () {
      final r = VisionGuard.apply([
        for (var i = 0; i < 250; i++) item('word$i'),
      ], maxItems: 200);
      // word0..word249:全部是"单词"但含数字 → 不是纯英文,会被丢掉
      expect(r.kept.length, lessThanOrEqualTo(200));
    });

    test('全部正常时不显示校验行(note == null)', () {
      final r = VisionGuard.apply([
        item('blur', line: 'began to blur'),
        item('vault', line: 'mental vault'),
      ]);
      expect(r.dropped, isEmpty);
      expect(r.typeFixed, 0);
      expect(r.note, isNull);
    });
  });
}
