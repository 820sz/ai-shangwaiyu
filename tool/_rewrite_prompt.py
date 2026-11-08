# -*- coding: utf-8 -*-
p = r"lib/services/material_ai_rewrite.dart"
s = open(p, encoding="utf-8").read()
start = s.index("({String system, String user}) buildAiRewritePrompt(AiRewriteRequest request) {")
end = s.index("/// 解析模型返回(纯函数,可单测;容错优先,不合格返回 null)。")
new = '''({String system, String user}) buildAiRewritePrompt(AiRewriteRequest request) {
  final limit = request.wordLimit;
  final lengthRule = (limit == null || limit <= 0)
      ? '篇幅由原材料内容量决定：原作内容多就写长、少就写短；覆盖完整优先，'
          '通常 1000~2500 词，不要为凑字数重复，也不要为了短而省略核心内容。'
      : '用户要求约 $limit 词（±15%）；如内容覆盖需要可略超。';
  final difficulty = switch (request.difficultyMode) {
    'easier' => '用更简单的英文：高频词、短句、清楚的结构。',
    'harder' => '用更丰富的词汇与更复杂的句式，但保持可读。',
    _ => '用词与句长贴近原材料/目标难度，不要额外拔高或刻意简化。',
  };
  final system = \'\'\'你是英语学习材料编辑。你要做的是：把用户要找的这部作品/这个主题，以原作者的叙述口吻重写成一篇英文学习材料（相当于"用英文把原作内容重写一遍"），而不是写书评、读后感、概述或介绍文章。

硬规则（违反任何一条都算失败）：
1. 口吻：沿用原作的叙述视角与人称（原作是第一人称就用第一人称；是论述/教学口吻就用相应口吻）。正文里不许出现"这本书讲了…/作者认为…/本文介绍…/这是围绕《X》的改写…"这类第三人称元叙述。
2. 内容覆盖优先：先用你知道的（以及线索里能确认的）内容，梳理原作的主要结构/章节/核心观点/方法/例子/结论，正文要按原作的结构完整展开这些内容；核心内容不许一笔带过。
3. 篇幅：$lengthRule
4. 语言：英文正文，分段清楚（像原作章节/段落那样自然展开）；不要练习题、生词表、书评式评价。
5. 非原文标注：正文里不要写"AI改写/非原文"字样；标注只由 App 在标题与文末统一加。
6. 禁止编造：不许编造具体引文、页码、统计数据、链接；可以写一般性内容，但不要假装是原文原句。
7. 难度：$difficulty
8. 只输出 JSON：
{
  "topic": "英文书名/主题（<=80 字符，不带书名号/引号/星号）",
  "title_cn": "中文书名/主题（<=30 字）",
  "outline": ["原作核心内容点1", "点2", "…"],
  "body": "英文正文（段落之间用 \\\\n\\\\n 分隔；按原作结构完整展开）",
  "used_sources": [1, 2]
}
outline 只用于自查覆盖，不得原样出现在正文里；used_sources 填线索编号（1 起，可空数组）。\'\'\';
  final buf = StringBuffer();
  if (request.topicHint.trim().isNotEmpty) {
    buf.writeln('用户要找的作品/主题:${request.topicHint.trim()}');
  }
  buf.writeln('用户搜索关键词:${request.query.trim()}');
  if (request.bandLabel.trim().isNotEmpty) {
    buf.writeln('目标难度档:${request.bandLabel.trim()}');
  }
  if (request.goals.isNotEmpty) {
    buf.writeln('学习目标:${request.goals.take(3).join("、")}');
  }
  if (request.interests.isNotEmpty) {
    buf.writeln('兴趣:${request.interests.take(4).join("、")}');
  }
  if (request.extraNote.trim().isNotEmpty) {
    buf.writeln('用户补充要求:${request.extraNote.trim()}');
  }
  buf.writeln('这次搜到的线索（只用来补充/确认内容，不要复制链接）：');
  if (request.sources.isEmpty) {
    buf.writeln('（没有外部线索——请用你对这部作品/主题的知识来写，不要声称有来源。）');
  } else {
    for (var i = 0; i < request.sources.length; i++) {
      final src = request.sources[i];
      buf.writeln(
        '${i + 1}. title=${src.title} | site=${src.site} | kind=${src.kind} '
        '| snippet=${src.snippet} | url=${src.url}',
      );
    }
  }
  buf.writeln('请按原文/作品本身的口吻与结构，写一篇覆盖完整内容的英文学习版，按 JSON 输出。');
  return (system: system, user: buf.toString());
}

'''
s = s[:start] + new + s[end:]
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("prompt rewritten")