import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/screens/input/widgets/quick_replies.dart';
import 'package:readflow/services/material_recommend_service.dart';
import 'package:readflow/services/translation_policy.dart';

/// 翻译纪律(v2.12.2,用户 2026-10-20)。
///
/// 这条纪律是**优先级约束**,不是文风建议。测试锁三件事:
/// 1. "准确/专业 > 流畅"必须写死在文本里,不能被后来的文案润色冲掉;
/// 2. 术语、限定、否定、时态、逻辑关系这些最容易为了"顺口"牺牲的点都有明文;
/// 3. 它真的被挂进了几条会产出译文的提示词(至少抽查快捷回复与精读导读),
///    而不是只建了一个没人用的常量。
void main() {
  group('翻译纪律', () {
    test('优先级写清:准确/专业优先,流畅只服务于原意', () {
      expect(TranslationPolicy.discipline, contains('准确、专业 > 流畅'));
      expect(TranslationPolicy.discipline, contains('不允许为了顺口'));
      expect(TranslationPolicy.discipline, contains('以这六条为准'));
    });

    test('术语、限定、否定、时态、逻辑关系都有可执行约束', () {
      for (final keyword in [
        '术语用学界/行业通用译法',
        '限定',
        '否定',
        '时态',
        '情态',
        '逻辑关系',
      ]) {
        expect(
          TranslationPolicy.discipline,
          contains(keyword),
          reason: '翻译纪律缺少「$keyword」这一条',
        );
      }
    });

    test('输出格式仍按各提示词原位要求(不改 JSON 结构)', () {
      expect(TranslationPolicy.discipline, contains('JSON 字段名'));
      expect(TranslationPolicy.discipline, contains('段数'));
    });

    test('同一份纪律确实进了会产出译文的提示词', () {
      // 追问快捷回复(逐句翻译)
      final reply =
          QuickReplies.defaults.firstWhere((r) => r.label == '逐句翻译');
      expect(reply.prompt, contains(TranslationPolicy.discipline));
      // 仍然保留"不要逐词硬译" —— 严谨不等于逐词硬译
      expect(reply.prompt, contains('不要逐词硬译'));

      // 材料精读导读(每段译文/大意 + 重点词的中文释义)
      expect(
        MaterialRecommendService.contentSystemPrompt,
        contains(TranslationPolicy.discipline),
      );
    });
  });
}
