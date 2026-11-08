#!/usr/bin/env bash
cd /d/readflow || exit 1
python - <<'PY'
p='test/find_material_ai_rewrite_test.dart'
s=open(p,encoding='utf-8').read()
old = """    test('没有线索 → 直接失败,且不调用模型(不凭空编)', () async {
      var called = false;
      final rewriter = MaterialAiRewriter(
        handler: (_, _) async {
          called = true;
          return validJson();
        },
        measurer: (_) async => const AiRewriteMeasurement(wordCount: 200),
      );
      final outcome = await rewriter.generate(
        AiRewriteRequest(query: 'q', sources: const <AiRewriteSource>[]),
      );
      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('没有'));
      expect(called, isFalse);
    });"""
new = """    test('没有线索但给了作品/主题 → 用模型知识改写(2026-11-08 新逻辑)', () async {
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
    });"""
assert old in s, 'anchor missing'
s=s.replace(old,new,1)
open(p,'w',encoding='utf-8',newline='\n').write(s)
print('test updated')
PY
bash tool/lockrun.sh test test/find_material_ai_rewrite_test.dart test/find_material_free_search_test.dart --no-pub --timeout 120s 2>&1 | tail -6
