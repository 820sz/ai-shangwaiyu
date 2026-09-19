import 'dart:convert';

import '../models/material_recommendation.dart';
import '../models/vocabulary.dart';

/// 「其他输入材料」的 AI 推荐逻辑(v1.8.0)。
///
/// 设计要点(对应用户反馈):
/// - 推荐依据 = **用户学习画像**(可编辑、已保存) + **软件内真实词汇数据**
/// - 推荐清单与"学习内容"全部走**流式输出**,并落库缓存,下次进入直接读
/// - 纯函数集中在这里,便于单测
class MaterialRecommendService {
  /// 从词库推断用户水平线索(纯函数):词汇量 + 来源书籍 + 掌握度分布
  static String vocabFingerprint(List<Vocabulary> vocab) {
    if (vocab.isEmpty) return '(词库为空,暂无词汇数据可参考)';
    final byBook = <String, int>{};
    final byCategory = <String, int>{};
    var mastered = 0;
    var learning = 0;
    var fresh = 0;
    var phraseCount = 0;
    for (final v in vocab) {
      final book = (v.sourceBook ?? '').trim();
      if (book.isNotEmpty) byBook[book] = (byBook[book] ?? 0) + 1;
      final cat = (v.category ?? '').trim();
      if (cat.isNotEmpty) byCategory[cat] = (byCategory[cat] ?? 0) + 1;
      switch (v.masteryLevel) {
        case 2:
          mastered++;
        case 1:
          learning++;
        default:
          fresh++;
      }
      if (v.wordType == 'phrase') phraseCount++;
    }
    final topBooks = (byBook.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) => '${e.key}(${e.value})')
        .join('、');
    final topCats = (byCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(4)
        .map((e) => '${e.key}(${e.value})')
        .join('、');
    final recent = (vocab.take(20).map((v) => v.word).toList()).join(', ');
    return [
      '收藏词汇总数:${vocab.length}(已掌握 $mastered / 学习中 $learning / 新词 $fresh,短语 $phraseCount)',
      if (topBooks.isNotEmpty) '来源书籍: $topBooks',
      if (topCats.isNotEmpty) '材料分类分布: $topCats',
      if (recent.isNotEmpty) '最近收录的词: $recent',
    ].join('\n');
  }

  /// 推荐清单 system 提示词
  static const String recommendationSystemPrompt = '''
你是资深英语学习规划师。根据用户的学习画像与真实词汇数据,推荐 4-6 份**当下最值得学**的英语材料。
必须返回 JSON(不要任何多余文字):
{"items":[{"title":"材料名","summary":"一句话说明这份材料讲什么(40字内)","level":"难度标签(如 B1 / 四级 / 雅思6.5)","reason":"为什么推荐给这位用户(结合他的水平/目的/生词数据,60字内)","keywords":"3-5个关键词,逗号分隔"}]}
要求:
1. 材料要真实存在且容易获取(经典教材、知名原版书、主流外刊栏目、公开演讲等),不要编造不存在的书名。
2. 难度必须匹配用户水平画像——宁可比当前水平略高一点点,不要越级到读不懂。
3. 每份材料的 reason 必须引用用户的具体数据或画像(例如"你在《XXX》里的生词偏学术")。
4. 覆盖不同题材,优先用户偏好;若用户未填偏好,则按词汇数据推断。
只输出 JSON。''';

  /// 推荐清单 user 提示词
  static String recommendationUserPrompt({
    required LearnerProfile profile,
    required List<Vocabulary> vocab,
    required String category,
  }) {
    return '''
【用户学习画像】
${profile.summaryText}

【用户真实词汇数据】
${vocabFingerprint(vocab)}

【本次想找的材料类型】$category

请给出该类型下最匹配的 4-6 份材料,只返回 JSON。''';
  }

  /// 学习内容 system 提示词(点开某份推荐后生成可学习的内容)
  static const String contentSystemPrompt = '''
你是英语精读老师。用户选中了一份材料,请为他生成一份**可以直接拿来学**的精读内容(中文讲解 + 英文原文片段)。
输出 Markdown(不要用代码块包裹整篇),结构:
## 📖 选段
(3-5 段英文原文或典型例句,难度匹配用户水平;若非真实出版物原文,请写"根据该材料风格改写的精读选段")
## 🇨🇳 中文导读
(每段选段对应的中文翻译或大意,逐段对应)
## 🔑 重点词与表达
(6-10 条:英文 — 中文释义 — 一句话用法说明;优先覆盖用户生词本里的词)
## 🧭 怎么用这份材料
(3-4 条具体的学习动作建议,例如"先盲听/先泛读一遍,再回来看重点词")
要求:内容务实用得上,不要空话;英文难度贴近用户水平。''';

  /// 学习内容 user 提示词
  static String contentUserPrompt({
    required MaterialRecommendation rec,
    required LearnerProfile profile,
    required List<Vocabulary> vocab,
  }) {
    final words = vocab.take(80).map((v) => v.word).join(', ');
    return '''
【材料】${rec.title}
【简介】${rec.summary}
【难度】${rec.level}
【推荐理由】${rec.reason}

【用户画像】${profile.summaryText}
【用户生词本(请尽量覆盖)】${words.isEmpty ? '(暂无)' : words}

请按 system 里的结构生成精读内容。''';
  }

  /// 解析推荐清单 JSON(纯函数,可单测)。
  /// 兼容 ```json 包裹、多余说明文字;字段缺失补空串;坏数据不抛异常。
  static List<MaterialRecommendation> parseRecommendations(
    String content, {
    required String category,
    String profileSnapshot = '',
    DateTime? now,
  }) {
    final jsonStr = _extractJson(content);
    if (jsonStr.isEmpty) return const [];
    try {
      final parsed = jsonDecode(jsonStr);
      if (parsed is! Map) return const [];
      final raw = parsed['items'];
      if (raw is! List) return const [];
      final created = now ?? DateTime.now();
      final list = <MaterialRecommendation>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final title = e['title']?.toString().trim() ?? '';
        if (title.isEmpty) continue;
        list.add(
          MaterialRecommendation(
            category: category,
            title: title,
            summary: e['summary']?.toString().trim() ?? '',
            level: e['level']?.toString().trim() ?? '',
            reason: e['reason']?.toString().trim() ?? '',
            keywords: e['keywords']?.toString().trim() ?? '',
            profileSnapshot: profileSnapshot,
            createdAt: created,
          ),
        );
      }
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// 取 JSON 主体(与 DoubaoApiService.extractJsonBlock 同规则,
  /// 这里独立实现以便服务层单测不依赖 API 类)
  static String _extractJson(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
    if (fence != null) {
      final inner = (fence.group(1) ?? '').trim();
      if (inner.startsWith('{') || inner.startsWith('[')) return inner;
    }
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start >= 0 && end > start) return t.substring(start, end + 1);
    return '';
  }
}
