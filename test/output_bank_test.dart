import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/output_bank.dart';
import 'package:readflow/services/output_composer.dart';

/// 批 3 增强 · 内置素材库(按目标自选练习来源)的纯函数测试。
///
/// 守的是用户新要求的核心逻辑:
/// - 考四六级的人 → 优先看到四六级词/范文句/作文题;读外刊的人 → 外刊高频词;
/// - 没有目标的人也能练(通用来源不丢);
/// - 抽词可复现(同一 seed 同结果)、不越界;
/// - 内置题组结构正确(阶/题型/rubric/参考答案/来源标记),能直接进练习器。
void main() {
  group('素材解析', () {
    test('考纲词表解析:词/释义/词性都不为空,数量符合预期', () {
      expect(OutputBank.cet4Words.length, greaterThan(150));
      for (final e in OutputBank.cet4Words) {
        expect(e.word.trim(), isNotEmpty);
        expect(e.meaning.trim(), isNotEmpty);
        expect(e.pos.trim(), isNotEmpty);
      }
    });

    test('外刊词表与范文句/段落/作文题不为空', () {
      expect(OutputBank.newsWords.length, greaterThan(50));
      expect(OutputBank.essaySentences.length, greaterThanOrEqualTo(10));
      expect(OutputBank.paragraphModels.length, greaterThanOrEqualTo(5));
      expect(OutputBank.essayPrompts.length, greaterThanOrEqualTo(8));
      for (final s in OutputBank.essaySentences) {
        expect(s.en.trim(), isNotEmpty);
        expect(s.zh.trim(), isNotEmpty);
      }
    });
  });

  group('按目标推荐来源', () {
    test('四六级目标 → 四六级词/范文句/作文题排在通用来源前面', () {
      final sources = OutputBank.recommendedSources(const ['四六级']);
      final ids = sources.map((s) => s.id).toList();
      expect(ids, contains('cet4_words'));
      expect(ids, contains('essay_prompts'));
      // 四六级命中的来源必须整体排在未命中的前面
      final firstNonMatch = sources.indexWhere(
        (s) => !s.matches(const ['四六级']),
      );
      if (firstNonMatch >= 0) {
        for (var i = 0; i < firstNonMatch; i++) {
          expect(sources[i].matches(const ['四六级']), isTrue);
        }
      }
    });

    test('外刊/雅思目标 → 外刊高频词命中', () {
      final sources = OutputBank.recommendedSources(const ['读外刊', '雅思']);
      final news = sources.firstWhere((s) => s.id == 'news_words');
      expect(news.matches(const ['读外刊']), isTrue);
      expect(news.matches(const ['雅思']), isTrue);
    });

    test('没有目标也返回全部来源(可选择),不能是空列表', () {
      final sources = OutputBank.recommendedSources(const []);
      expect(sources.length, OutputBank.sources().length);
    });

    test('每个阶都有可用来源(写词/写句/写段/写篇都不缺)', () {
      final sources = OutputBank.recommendedSources(const []);
      for (final tier in OutputTier.values) {
        expect(
          sources.where((s) => s.tier == tier).isNotEmpty,
          isTrue,
          reason: '$tier 阶没有练习来源',
        );
      }
    });
  });

  group('抽词', () {
    test('同一 seed 结果可复现,数量正确且不重复', () {
      final a = OutputBank.pickWords(OutputBank.cet4Words, 10, seed: 42);
      final b = OutputBank.pickWords(OutputBank.cet4Words, 10, seed: 42);
      expect(a.map((e) => e.word).toList(), b.map((e) => e.word).toList());
      expect(a.length, 10);
      expect(a.map((e) => e.word).toSet().length, 10);
    });

    test('请求超过词库时只返回词库大小,空库返回空', () {
      expect(
        OutputBank.pickWords(OutputBank.newsWords, 9999).length,
        OutputBank.newsWords.length,
      );
      expect(OutputBank.pickWords(const [], 10), isEmpty);
      expect(OutputBank.pickWords(OutputBank.cet4Words, 0), isEmpty);
    });
  });

  group('内置题组结构', () {
    test('写句:中文题面 + 英文参考答案 + 回译 rubric + verified', () {
      final set = OutputBank.buildSentenceSet(
        pairs: OutputBank.essaySentences.take(3).toList(),
      );
      expect(set.tasks.length, 3);
      for (final t in set.tasks) {
        expect(t.tier, OutputTier.sentence);
        expect(t.type, 'back_translation');
        expect(t.promptZh.trim(), isNotEmpty);
        expect(t.reference.trim(), isNotEmpty);
        expect(t.rubricId, 'back_translation');
        expect(t.source, 'builtin');
        expect(t.verifyStatus, 'verified');
      }
      expect(set.rubricId, 'back_translation');
    });

    test('写段:题面中文 + 英文参考 + summary rubric', () {
      final set = OutputBank.buildParagraphSet(
        models: OutputBank.paragraphModels.take(2).toList(),
      );
      expect(set.tasks.length, 2);
      for (final t in set.tasks) {
        expect(t.type, 'paragraph');
        expect(t.rubricId, 'summary');
        expect(t.reference.trim(), isNotEmpty);
      }
    });

    test('写篇:题目含要点 + 写作 rubric + 字数要求', () {
      final set = OutputBank.buildEssaySet(
        prompts: [OutputBank.essayPrompts.first],
      );
      final task = set.tasks.single;
      expect(task.type, 'exam_writing');
      expect(task.rubricId, 'cet4_writing');
      expect(task.promptZh, contains('参考要点'));
      expect(task.promptEn.trim(), isNotEmpty);
      expect(task.wordCount, greaterThan(0));
    });

    test('题组可以直接被练习器消费(字段完整,不依赖网络)', () {
      final sets = [
        OutputBank.buildSentenceSet(
          pairs: OutputBank.essaySentences.take(2).toList(),
        ),
        OutputBank.buildParagraphSet(
          models: OutputBank.paragraphModels.take(2).toList(),
        ),
        OutputBank.buildEssaySet(prompts: [OutputBank.essayPrompts.first]),
      ];
      for (final set in sets) {
        expect(set.tasks, isNotEmpty);
        expect(set.isEmpty, isFalse);
        for (final t in set.tasks) {
          expect(t.promptZh.isNotEmpty || t.promptEn.isNotEmpty, isTrue);
          // 写句/写段必须带参考答案;写篇用"要点提示"代替范文(不给模板)
          if (t.tier != OutputTier.essay) {
            expect(t.hasReference, isTrue);
          }
        }
      }
    });
  });
}
