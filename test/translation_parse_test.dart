import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/deepseek_api.dart';

/// v2.13.1 回归:翻译返回的解析 + **段数对账**(纯函数,不联网)。
///
/// 这条链路以前 0 覆盖,而"段数对不上"正是用户看到"只翻了第一段却没有提示"
/// 的直接原因(旧实现 note 非空却被界面静默丢弃)。这里锁住 7 种返回形态。
void main() {
  group('parseTranslationOutcome', () {
    test('正常 JSON:段数一致 → 全部译文、无 note', () {
      final out = DeepseekApiService.parseTranslationOutcome(
        '{"translations":["第一段","第二段","第三段"]}',
        3,
      );
      expect(out.translations, ['第一段', '第二段', '第三段']);
      expect(out.note, isNull);
    });

    test('```json 围栏包裹 → 仍能解析', () {
      final out = DeepseekApiService.parseTranslationOutcome(
        '```json\n{"translations":["甲","乙"]}\n```',
        2,
      );
      expect(out.translations, ['甲', '乙']);
      expect(out.note, isNull);
    });

    test('前后夹带说明文字("好的,结果如下:") → 抠出 JSON', () {
      final out = DeepseekApiService.parseTranslationOutcome(
        '好的,翻译结果如下:\n{"translations":["一","二"]}\n请查收。',
        2,
      );
      expect(out.translations, ['一', '二']);
      expect(out.note, isNull);
    });

    test('段数少于期望 → 保留能对上的前 k 段 + note(界面必须显示)', () {
      final out = DeepseekApiService.parseTranslationOutcome(
        '{"translations":["第一段","第二段"]}',
        3,
      );
      expect(out.translations, ['第一段', '第二段']);
      expect(out.note, contains('2/3'));
      expect(out.note, contains('截断'));
    });

    test('段数多于期望 → 多出来的丢掉(绝不错位到下一段)+ note', () {
      final out = DeepseekApiService.parseTranslationOutcome(
        '{"translations":["甲","乙","丙"]}',
        2,
      );
      expect(out.translations, ['甲', '乙']);
      expect(out.note, contains('2/2'));
    });

    test('JSON 被截断/不闭合 → 视为没有译文 + note(不能静默显示空白)', () {
      final out = DeepseekApiService.parseTranslationOutcome(
        '{"translations":["第一段","第二段"',
        2,
      );
      expect(out.translations, isEmpty);
      expect(out.note, isNotNull);
      expect(out.note, contains('没返回译文'));
    });

    test('空内容 / 空 translations → note 提示可能被截断', () {
      for (final content in ['', '{"translations":[]}', 'not json at all']) {
        final out = DeepseekApiService.parseTranslationOutcome(content, 1);
        expect(out.translations, isEmpty, reason: '输入:$content');
        expect(out.note, contains('没返回译文'), reason: '输入:$content');
      }
    });

    test('空字符串项被过滤;期望数为 0 时不做段数对账', () {
      final out = DeepseekApiService.parseTranslationOutcome(
        '{"translations":["甲","  ","乙"]}',
        0,
      );
      expect(out.translations, ['甲', '乙']);
      expect(out.note, isNull);
    });

    // v2.16.0:finish_reason 可见 —— 'length' = 被模型输出上限截断。
    // 旧实现完全不看它,用户只看到"少了一段"却不知道原因(以为功能坏了)。
    group('finish_reason == length(输出被截断)', () {
      test('段数不足 + 截断 → note 明确写「输出被截断」', () {
        final out = DeepseekApiService.parseTranslationOutcome(
          '{"translations":["只翻出第一段"]}',
          3,
          finishReason: 'length',
        );
        expect(out.translations, ['只翻出第一段']);
        expect(out.note, contains('输出被截断'));
        expect(out.note, contains('1/3'));
      });

      test('一个译文都没有 + 截断 → note 也必须说清是截断', () {
        final out = DeepseekApiService.parseTranslationOutcome(
          '{"translations":',
          1,
          finishReason: 'length',
        );
        expect(out.translations, isEmpty);
        expect(out.note, contains('输出被截断'));
      });

      test('finish_reason 正常(stop)时保持原文案,不误报截断', () {
        final out = DeepseekApiService.parseTranslationOutcome(
          '{"translations":["甲"]}',
          2,
          finishReason: 'stop',
        );
        expect(out.note, contains('可能被截断'));
        expect(out.note, isNot(contains('达到模型输出上限')));
      });

      test('段数刚好对得上时忽略 finish_reason(内容已完整)', () {
        final out = DeepseekApiService.parseTranslationOutcome(
          '{"translations":["甲","乙"]}',
          2,
          finishReason: 'length',
        );
        expect(out.translations, ['甲', '乙']);
        expect(out.note, isNull);
      });
    });

    test('finishReasonOf:从响应里取 finish_reason,畸形响应退 null', () {
      expect(
        DeepseekApiService.finishReasonOf({
          'choices': [
            {
              'message': {'content': '{}'},
              'finish_reason': 'length',
            }
          ]
        }),
        'length',
      );
      expect(
        DeepseekApiService.finishReasonOf({
          'choices': [
            {'message': {'content': '{}'}, 'finish_reason': 'stop'}
          ]
        }),
        'stop',
      );
      expect(DeepseekApiService.finishReasonOf(const {}), isNull);
      expect(DeepseekApiService.finishReasonOf(const {'choices': []}), isNull);
      expect(
        DeepseekApiService.finishReasonOf(const {
          'choices': ['not-a-map']
        }),
        isNull,
      );
    });
  });
}
