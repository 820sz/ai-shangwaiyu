import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/reader_units.dart';

/// v2.13.1 回归:阅读器翻译单元 = **真段落**,不是 2500 词的正文块。
///
/// 用户原话(2026-11-01):「文章阅读器的翻译功能永远没法用,翻译进度永远是死的」。
/// 根因就是「块 = 段」:典型文章 1 块 → 进度分母恒 1;整块发一次请求 → 模型回
/// N 段与 1 段对不上 → 只翻出第一段。这个文件锁住拆分规则(段数/顺序/无损/
/// 超长段/空段/chunk 映射),避免以后又退回去按块翻译。
void main() {
  List<Map<String, Object?>> chunksOf(List<String> texts) => [
        for (final t in texts) {'text': t},
      ];

  group('splitUnits:按空行拆真段落', () {
    test('真段数:一个 2 段的正文块 → 2 个翻译单元(旧实现是 1 个)', () {
      final units = splitUnits(chunksOf([
        'First paragraph.\n\nSecond paragraph.',
      ]));
      expect(units.length, 2);
      expect(units[0].text, 'First paragraph.');
      expect(units[1].text, 'Second paragraph.');
      expect(units[0].chunkIndex, 0);
      expect(units[1].chunkIndex, 0);
      expect(units[0].paraIndex, 0);
      expect(units[1].paraIndex, 1);
    });

    test('顺序保持 + 跨块映射:单元顺序 = 阅读顺序', () {
      final units = splitUnits(chunksOf([
        'A one.\n\nA two.',
        'B one.\n\nB two.\n\nB three.',
      ]));
      expect(units.map((u) => u.text).toList(),
          ['A one.', 'A two.', 'B one.', 'B two.', 'B three.']);
      expect(units.map((u) => u.chunkIndex).toList(), [0, 0, 1, 1, 1]);
      expect(units.map((u) => u.paraIndex).toList(), [0, 1, 0, 1, 2]);
    });

    test('空行/空段丢弃,不产生空单元', () {
      final units = splitUnits(chunksOf([
        '\n\n  \nFirst.\n\n\n\nSecond.\n \n\n',
      ]));
      expect(units.length, 2);
      expect(units.map((u) => u.text).toList(), ['First.', 'Second.']);
    });

    test('无损:拆出来的片段拼回去,除空白外与原文一致', () {
      final original =
          'Alpha beta gamma. Delta epsilon zeta!\n\n'
          'Eta theta iota? Kappa lambda mu. Nu xi omicron.';
      final units = splitUnits(chunksOf([original]), maxChars: 30);
      expect(units.length, greaterThan(2)); // 确实被切开了
      String noSpace(String s) => s.replaceAll(RegExp(r'\s+'), '');
      expect(noSpace(units.map((u) => u.text).join(' ')), noSpace(original));
    });

    test('超长段按句子/空格二次切:每片不超上限、同属一个 paraIndex、不丢字', () {
      // 6 句 × ~120 字符 ≈ 720 字符 > 600 上限
      final sentence = 'This is a fairly long English sentence used for testing. ';
      final long = List.filled(12, sentence).join().trim();
      expect(long.length, greaterThan(600));
      final units = splitUnits(chunksOf([long]), maxChars: 600);
      expect(units.length, greaterThan(1));
      for (final u in units) {
        expect(u.text.length, lessThanOrEqualTo(600));
        expect(u.chunkIndex, 0);
        expect(u.paraIndex, 0, reason: '二次切分的片段仍属于同一个自然段');
      }
      String noSpace(String s) => s.replaceAll(RegExp(r'\s+'), '');
      expect(noSpace(units.map((u) => u.text).join()), noSpace(long));
    });

    test('无空格超长串也能切(URL/长词不撑爆单请求),不丢字符', () {
      final long = 'x' * 1500;
      final units = splitUnits(chunksOf([long]), maxChars: 600);
      expect(units.length, 3);
      for (final u in units) {
        expect(u.text.length, lessThanOrEqualTo(600));
      }
      expect(units.map((u) => u.text).join(), long);
    });

    test('自定义 maxChars 生效;整篇没有空文本块时返回空列表', () {
      final units = splitUnits(chunksOf(['abc def', 'ghi jkl']), maxChars: 40);
      expect(units.length, 2);
      expect(splitUnits(chunksOf(['', '   ', '\n\n'])), isEmpty);
    });
  });

  group('chunkFirstUnitIndices:块 → 单元映射', () {
    test('每块第一个单元下标', () {
      final units = splitUnits(chunksOf([
        'A1.\n\nA2.',
        'B1.',
      ]));
      expect(chunkFirstUnitIndices(units, 2), [0, 2]);
    });

    test('中间有空块时指向下一个有内容的块,末尾不越界', () {
      final units = splitUnits(chunksOf([
        'Only one.',
        '   ',
        'Last two.\n\nLast three.',
      ]));
      final first = chunkFirstUnitIndices(units, 3);
      expect(first.length, 3);
      expect(first[0], 0);
      // 空块(第 2 块)指向第 3 块的首个单元
      expect(first[1], 1);
      expect(first[2], 1);
      // 末尾:全空块时指向 units.length(调用方 clamp 后不会越界)
      expect(chunkFirstUnitIndices(splitUnits(chunksOf(['', ' '])), 2), [0, 0]);
    });
  });
}
