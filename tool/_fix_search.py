# -*- coding: utf-8 -*-
p = r"lib/screens/input/free_search_screen.dart"
s = open(p, encoding="utf-8").read()
start = s.index("    await runPass(searchQuery);")
end = s.index("    _event(\n      fresh.isEmpty\n          ? '没有匹配的结果")
new = """    await runPass(searchQuery);
    // 2026-11-08 修正：原版没找到时不要再在同一个书源里空转（上一版补搜 3 次都查 Gutenberg）。
    // 书/作品类 → 直接用官方搜索找「内容解读/摘要」作为真实参考；
    // 其他类型 → 用 AI 规划的检索词补搜一轮公开源。
    if (fresh.length < 2) {
      if (plan.changed) {
        _event('公开源没有原文，改用官方搜索找内容参考…');
        try {
          final secondary = await MaterialDiscovery().discover(
            queries: <String>[
              '$searchQuery summary chapter by chapter',
              '$searchQuery key ideas explained',
              '$searchQuery book notes',
            ],
            excludeUrls: seenUrls,
            prefs: _prefs,
            model: LearnerModelStore.load(),
            vocab: const <Vocabulary>[],
            maxFetch: 5,
            userQuery: '《${plan.original}》的内容要点（用于 AI 改写参考）',
            onEvent: (String _) {},
          );
          notes.addAll(secondary.notes.take(2));
          for (final candidate in secondary.items) {
            final text = '${candidate.title} ${candidate.snippet}'.toLowerCase();
            if (!_strictMatches(text, searchQuery)) continue;
            fresh.add(MaterialResultItem.fromCandidate(candidate, seq: seq++));
            sources.add(
              AiRewriteSource(
                title: candidate.title,
                url: candidate.url,
                site: candidate.sourceLabel,
                snippet: candidate.snippet,
                kind: candidate.kind,
              ),
            );
          }
          if (fresh.isNotEmpty) {
            notes.add('原版没有可读原文，已用官方搜索找到 ${fresh.length} 篇内容参考。');
          }
        } catch (e) {
          notes.add('内容参考搜索失败：$e');
        }
      } else {
        List<String> extra = const <String>[];
        try {
          extra = await planner.planQueries(
            '围绕《${plan.original}》（"$searchQuery"）找可读的英文相关内容。'
            '给出 2 条英文检索词。',
            max: 2,
          );
        } catch (_) {}
        for (final extraQuery in extra) {
          _event('补搜:$extraQuery');
          await runPass(extraQuery);
          if (fresh.length >= 4) break;
        }
        if (fresh.isNotEmpty) notes.add('已补搜 ${fresh.length} 条相关内容。');
      }
    }

"""
s = s[:start] + new + s[end:]
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("secondary search rewritten")