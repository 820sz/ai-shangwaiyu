import 'dart:convert';

import 'package:flutter/material.dart' show IconData, Icons;

import 'api_endpoint.dart';
import 'base_api.dart';
import 'database.dart';

/// 材料里的「AI 内容块」(v2.9,用户第 3(5) 条)。
///
/// 用户原话:"软件内抓取的材料原文这些 —— 现在是只有文本模式,而且前端也很单一,
/// 需要增加更丰富的形式,以及支持选择让 ai 根据内容自动输出内容形式 ——
/// 比如读到一篇带有数据的材料,支持让 ai 在材料中绘出表格啊等等,思维导图呀等等,
/// 只是举个例 —— 核心诉求是让软件内的阅读体验更丰富,更舒服。"
///
/// 所以这一层做三件事,**全部与界面无关**(纯逻辑,可单测):
/// 1. [analyzeBestKinds] —— **纯函数**读文本特征,推荐"这篇适合做成什么形式",
///    并且必须给出**为什么**(如"这篇有 12 处数字/年份,适合做成表格");
/// 2. [generateBlocks] —— 让 AI 按严格 JSON schema 把某一段整理成某种形式,
///    解析失败给**可读中文错误**(绝不抛到界面、绝不崩);
/// 3. [parsePayload] / [MaterialBlockDraft.fromRow] —— 落库与回读的解析,
///    库里的坏数据只让那一个块不显示,不影响整篇阅读。
///
/// 落库走 [DatabaseService.upsertMaterialBlock](同 material+chunk+kind 是 upsert),
/// 于是"重新生成"= 覆盖同一条,"删掉"= [DatabaseService.deleteMaterialBlocks]。
///
/// ⚠️ 为什么请求代码写在这里而不是 deepseek_api.dart:本次改动的文件范围被
/// 严格限定,`deepseek_api.dart` 不在其中。这里复用同一套
/// [BaseApiService.buildChatBody] / [postWithReasoningFallback] /
/// [BaseApiService.extractContentWithReasoning](行为完全一致),
/// 不复制粘贴私有实现。

/// 内容块形式。五种覆盖"数据 / 关系 / 时间 / 要点 / 自测"五类阅读需求。
enum MaterialBlockKind {
  table(
    'table',
    '表格',
    Icons.table_chart_outlined,
    '数据、年份、对比项 —— 排成表一眼看清',
  ),
  mindmap(
    'mindmap',
    '思维导图',
    Icons.account_tree_outlined,
    '中心主题 + 分支 —— 看结构、看层级关系',
  ),
  timeline(
    'timeline',
    '时间线',
    Icons.timeline_outlined,
    '按时间发生的先后排成一条轴',
  ),
  points(
    'points',
    '要点卡',
    Icons.checklist_rtl_outlined,
    '论点、步骤、结论 —— 编号成卡片',
  ),
  quiz(
    'quiz',
    '自测卡',
    Icons.quiz_outlined,
    '就这段内容出几道题,点开看答案',
  );

  const MaterialBlockKind(this.id, this.label, this.icon, this.hint);

  /// 落库用的字符串(与 material_blocks.kind 一致)
  final String id;

  /// 界面上的中文名
  final String label;

  /// 界面图标(五种形式各有各的图标,一眼区分)
  final IconData icon;

  /// 一句话说明"这个形式什么时候用"
  final String hint;

  /// 按 id 反查(库里读到坏 kind 时返回 null,调用方跳过该块)
  static MaterialBlockKind? byId(String? id) {
    if (id == null) return null;
    for (final k in MaterialBlockKind.values) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// 一次推荐:[kind] 适合做成什么,而 [why] 说清**为什么**(用户能看到依据,
/// 而不是一个黑盒按钮)。
class KindSuggestion {
  final MaterialBlockKind kind;

  /// 推荐说明(中文,带具体数字,如"有 12 处数字/年份,适合做成表格")
  final String why;

  /// 打分(仅用于排序;越大越贴合)
  final double score;

  const KindSuggestion({
    required this.kind,
    required this.why,
    required this.score,
  });

  @override
  String toString() => '${kind.id}(${score.toStringAsFixed(1)}): $why';
}

/// 解析好的一个内容块(界面直接吃这个,不再碰 JSON)
class MaterialBlockDraft {
  final MaterialBlockKind kind;

  /// 块标题(默认给形式名,如「表格」;AI 可以给更具体的)
  final String title;

  /// 结构化数据,键随 kind 不同:
  /// - table:   `{columns:[..], rows:[[..],..]}`
  /// - mindmap: `{center:'中心主题', branches:[{label:'分支', children:['子项']}]}`
  /// - timeline:`{events:[{time:'1945', text:'事件'}]}`
  /// - points:  `{items:[{title:'要点', text:'说明'}]}`
  /// - quiz:    `{items:[{question:'问题', answer:'答案'}]}`
  final Map<String, Object?> data;

  /// 来自第几段(-1 = 整篇级)
  final int chunkIndex;

  /// 库里那一条的 id(尚未落库时为 null)
  final int? id;

  const MaterialBlockDraft({
    required this.kind,
    required this.title,
    required this.data,
    this.chunkIndex = -1,
    this.id,
  });

  MaterialBlockDraft copyWith({int? id}) => MaterialBlockDraft(
        kind: kind,
        title: title,
        data: data,
        chunkIndex: chunkIndex,
        id: id ?? this.id,
      );

  /// 落库用的 payload JSON
  String toPayloadJson() => jsonEncode(data);

  /// 从数据库行还原。**坏数据返回 null**(那一块不显示,不影响整篇阅读)。
  static MaterialBlockDraft? fromRow(Map<String, Object?> row) {
    final kind = MaterialBlockKind.byId('${row['kind'] ?? ''}');
    if (kind == null) return null;
    final raw = '${row['payload'] ?? ''}';
    final data = parsePayload(kind, raw);
    if (data == null) return null;
    final title = '${row['title'] ?? ''}'.trim();
    return MaterialBlockDraft(
      kind: kind,
      title: title.isEmpty ? kind.label : title,
      data: data,
      chunkIndex: _asInt(row['chunk_index'], fallback: -1),
      id: row['id'] is int ? row['id'] as int : null,
    );
  }

  /// 「AI 整理 · 基于第 N 段」的来源标注
  String get sourceLabel =>
      chunkIndex < 0 ? 'AI 整理 · 基于整篇' : 'AI 整理 · 基于第 ${chunkIndex + 1} 段';
}

/// 生成结果(成功给 [draft],失败给 [error] —— 调用方只需看这两个字段)
class MaterialBlocksResult {
  final MaterialBlockKind kind;
  final MaterialBlockDraft? draft;

  /// 失败原因(中文,可直接显示给用户)
  final String? error;

  /// AI 附的一句话说明(可选,如"按时间顺序整理")
  final String note;

  /// 落库后的 id(<=0 表示没落库)
  final int savedId;

  const MaterialBlocksResult({
    required this.kind,
    this.draft,
    this.error,
    this.note = '',
    this.savedId = -1,
  });

  bool get ok => draft != null && error == null;
}

// ═══════════════ 1. 纯函数:按内容自动推荐形式 ═══════════════

/// 分析文本特征 → 按**推荐顺序**给出适合的形式,每条都带"为什么"。
///
/// 纯函数(不碰网络、不碰数据库),所以可以直接单测;界面上「让 AI 推荐」按钮
/// 先用它给出**依据**,再去生成 —— 用户看到的是"这篇有 12 处数字,适合表格",
/// 而不是"AI 觉得你该看表格"。
///
/// 判据(全部可在文本上数出来,不猜):
/// - 数字/年份多(≥5 处)→ table;若同时有一组年份 → timeline 更靠前;
/// - 年份跨度 ≥3 个不同年份、或出现"first/then/later/世纪"这类时间词 → timeline;
/// - 出现"首先/其次/步骤/第一步"这类顺序词 → points(教程、流程);
/// - 专有名词/大写词多(≥8 个不同)→ mindmap(人物关系、概念体系);
/// - 对比词多(而/相比/然而 vs/than/compared)→ table;
/// - 任何文本 → 兜底给 points 与 quiz(总能出要点与自测)。
///
/// 返回值**非空**(至少 2 条),调用方不用判空。
List<KindSuggestion> analyzeBestKinds(String text) {
  final f = _TextFeatures.of(text);
  final out = <KindSuggestion>[];

  // ── 表格:数字/对比 ──
  if (f.numbers >= 5) {
    out.add(KindSuggestion(
      kind: MaterialBlockKind.table,
      why: '这篇有 ${f.numbers} 处数字/年份,适合做成表格对照',
      score: 6.0 + (f.numbers - 5) * 0.15 + f.compares * 0.3,
    ));
  } else if (f.compares >= 2) {
    out.add(KindSuggestion(
      kind: MaterialBlockKind.table,
      why: '文中有 ${f.compares} 处对比表达,适合做成两栏表格',
      score: 5.0 + f.compares * 0.3,
    ));
  }

  // ── 时间线:年份序列 / 时间词 ──
  if (f.years.length >= 3) {
    out.add(KindSuggestion(
      kind: MaterialBlockKind.timeline,
      why: '出现了 ${f.years.length} 个年份'
          '(${f.years.take(3).join('、')}${f.years.length > 3 ? '…' : ''}),'
          '适合排成时间线',
      score: 7.0 + f.years.length * 0.2,
    ));
  } else if (f.timeWords >= 3) {
    out.add(KindSuggestion(
      kind: MaterialBlockKind.timeline,
      why: '有 ${f.timeWords} 处先后/时间表达,适合排成时间线',
      score: 4.5 + f.timeWords * 0.2,
    ));
  }

  // ── 要点卡:步骤 / 顺序 ──
  if (f.stepWords >= 2) {
    out.add(KindSuggestion(
      kind: MaterialBlockKind.points,
      why: '有 ${f.stepWords} 处步骤/顺序词(首先、其次、步骤…),适合拆成要点卡',
      score: 6.5 + f.stepWords * 0.2,
    ));
  }

  // ── 思维导图:专有名词 / 层级 ──
  if (f.entities >= 8) {
    out.add(KindSuggestion(
      kind: MaterialBlockKind.mindmap,
      why: '文中出现 ${f.entities} 个不同的专有名词,适合画成思维导图看关系',
      score: 6.0 + f.entities * 0.1,
    ));
  } else if (f.sentences >= 12 && f.entities >= 4) {
    out.add(KindSuggestion(
      kind: MaterialBlockKind.mindmap,
      why: '篇幅较长(${f.sentences} 句)且概念较多,适合用思维导图梳理结构',
      score: 4.0,
    ));
  }

  // ── 自测卡:任何有长度的材料都能自测 ──
  if (f.words >= 80) {
    out.add(KindSuggestion(
      kind: MaterialBlockKind.quiz,
      why: '段落有 ${f.words} 词,够出 ${_quizCount(f.words)} 道自测题检验理解',
      score: 3.0 + f.words / 400,
    ));
  }

  // ── 兜底:至少给要点卡(短段落也总能提炼要点)──
  final hasPoints = out.any((s) => s.kind == MaterialBlockKind.points);
  if (!hasPoints) {
    out.add(KindSuggestion(
      kind: MaterialBlockKind.points,
      why: f.words >= 30
          ? '这段 ${f.words} 词,可以提炼成几个要点'
          : '内容较短,先提炼成要点最稳妥',
      score: 2.0,
    ));
  }
  if (!out.any((s) => s.kind == MaterialBlockKind.table) && f.numbers > 0) {
    out.add(KindSuggestion(
      kind: MaterialBlockKind.table,
      why: '有 ${f.numbers} 处数字,也可以整理成小表格',
      score: 1.5,
    ));
  }
  // 最终兜底:无论如何至少两条(界面上"让 AI 推荐"点开不能是空的)
  if (out.length < 2) {
    out.add(const KindSuggestion(
      kind: MaterialBlockKind.table,
      why: '也可以把这段的关键信息整理成一张对照表',
      score: 1.0,
    ));
  }

  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

/// 最符合这一篇的那**一种**形式(分数太低就返回 null,让界面别硬推)。
MaterialBlockKind? detectFromText(String text) {
  final list = analyzeBestKinds(text);
  if (list.isEmpty) return null;
  if (list.first.score < 3.0) return null;
  return list.first.kind;
}

/// 给界面用的一句话推荐(带"为什么")
String describeSuggestion(KindSuggestion s) => '${s.kind.label}:${s.why}';

int _quizCount(int words) {
  if (words >= 400) return 5;
  if (words >= 250) return 4;
  if (words >= 150) return 3;
  return 2;
}

/// 文本特征(纯计算,不依赖任何外部状态)
class _TextFeatures {
  final int words;
  final int sentences;
  final int numbers;
  final int compares;
  final int stepWords;
  final int timeWords;
  final int entities;
  final List<String> years;

  const _TextFeatures({
    required this.words,
    required this.sentences,
    required this.numbers,
    required this.compares,
    required this.stepWords,
    required this.timeWords,
    required this.entities,
    required this.years,
  });

  static const _compareWords = [
    'however', 'whereas', 'compared', 'while', 'than', 'versus',
    'on the other hand', 'in contrast',
  ];
  static const _stepWords = [
    'first', 'second', 'third', 'then', 'next', 'finally', 'step',
    'firstly', 'secondly', 'lastly',
  ];
  static const _timeWords = [
    'century', 'decade', 'annual', 'in 18', 'in 19', 'in 20', 'later',
    'earlier', 'meanwhile', 'afterward', 'before', 'after',
  ];

  /// 句首大写不算专有名词(否则每句第一个词都会把 entities 灌满)
  static const _stopEntities = {
    'the', 'a', 'an', 'this', 'that', 'these', 'those', 'it', 'he', 'she',
    'they', 'we', 'i', 'you', 'in', 'on', 'at', 'for', 'but', 'and', 'or',
    'if', 'when', 'while', 'as', 'by', 'to', 'of', 'with', 'from', 'there',
    'here', 'what', 'who', 'how', 'why', 'his', 'her', 'their', 'its', 'our',
    'my', 'not', 'no', 'so', 'then', 'now', 'one', 'two', 'many', 'most',
    'some', 'all', 'such', 'after', 'before', 'because', 'although', 'though',
  };

  static _TextFeatures of(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      return const _TextFeatures(
        words: 0, sentences: 0, numbers: 0, compares: 0,
        stepWords: 0, timeWords: 0, entities: 0, years: [],
      );
    }
    final lower = t.toLowerCase();
    final wordList = RegExp(r"[A-Za-z][A-Za-z'\-]*").allMatches(t).toList();

    // 年份单独数(它决定"要不要时间线");数字统计里**排除 4 位年份**,
    // 否则一篇纯大事年表会被数成"数字很多 → 表格",把时间线挤下去。
    // 数字形态:12 / 3.5 / 12% / 1,000(小数点后必须有数字 —— 否则句末的
    // "123." 也会被算成一个小数,把数字数量灌水)。
    final years = <String>{};
    for (final m in RegExp(r'\b(1[5-9]\d{2}|20\d{2})\b').allMatches(t)) {
      years.add(m.group(1)!);
    }
    final numeric =
        RegExp(r'(\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?%?').allMatches(t).where((m) {
      final s = m.group(0)!;
      return !(s.length == 4 && years.contains(s));
    }).length;
    int countWords(List<String> needles) {
      var n = 0;
      for (final w in needles) {
        if (w.contains(' ')) {
          if (lower.contains(w)) n++;
        } else {
          n += RegExp('\\b${RegExp.escape(w)}\\b').allMatches(lower).length;
        }
      }
      return n;
    }

    final entitySet = <String>{};
    for (final m in RegExp(r'\b[A-Z][a-z]{2,}\b').allMatches(t)) {
      final w = m.group(0)!;
      if (_stopEntities.contains(w.toLowerCase())) continue;
      entitySet.add(w);
    }

    return _TextFeatures(
      words: wordList.length,
      sentences: RegExp(r'[.!?]+').allMatches(t).length,
      numbers: numeric,
      compares: countWords(_compareWords),
      stepWords: countWords(_stepWords),
      timeWords: countWords(_timeWords),
      entities: entitySet.length,
      years: years.toList()..sort(),
    );
  }
}

/// 逐段翻译的耗时估算(与 [MaterialBlockKind] 无关,但同属"让用户有预期"的一环)。
///
/// 依据:每批最多 3 段合一次请求,单次请求含网络往返约 5~8 秒 → 每段约 2 秒。
/// 给的是**量级**(用户要的是"要不要现在翻"),不是精确承诺,所以文案写「约」。
int estimateTranslationSeconds(int chunkCount) {
  if (chunkCount <= 0) return 0;
  return chunkCount * 2 + 3;
}

/// 把秒数写成中文(「不到 1 分钟」/「约 3 分钟」)
String formatEstimate(int seconds) {
  if (seconds <= 0) return '';
  if (seconds < 60) return '不到 1 分钟';
  final m = (seconds / 60).round();
  return '约 $m 分钟';
}

// ═══════════════ 2. 解析:AI 返回的 JSON → 结构化数据 ═══════════════

/// 从模型输出里抠出 JSON 对象(**纯函数,不抛异常**)。
///
/// 兼容三种常见脏输出:```json 围栏、前后有说明文字、整体是数组。
/// 抠不出来返回空 Map —— 调用方给"读不懂 AI 的返回"这类可读错误。
Map<String, Object?> extractJsonObject(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return const {};
  var body = s;
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
  if (fence != null) {
    body = (fence.group(1) ?? '').trim();
  } else {
    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    if (start >= 0 && end > start) {
      body = body.substring(start, end + 1);
    }
  }
  if (body.isEmpty) return const {};
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    return const {};
  } catch (_) {
    return const {};
  }
}

/// 按 kind 解析 JSON 文本 → 结构化数据;**结构不对返回 null**(绝不抛)。
///
/// 每种 kind 的 schema(同时也是提示词里给模型的示例):
/// - table:    `{"title":"..","columns":[".."],"rows":[["..",".."]]}`
/// - mindmap:  `{"title":"..","center":"..","branches":[{"label":"..","children":[".."]}]}`
/// - timeline: `{"title":"..","events":[{"time":"..","text":".."}]}`
/// - points:   `{"title":"..","items":[{"title":"..","text":".."}]}`
/// - quiz:     `{"title":"..","items":[{"question":"..","answer":".."}]}`
Map<String, Object?>? parsePayload(MaterialBlockKind kind, String raw) {
  final json = extractJsonObject(raw);
  if (json.isEmpty) return null;
  switch (kind) {
    case MaterialBlockKind.table:
      final columns = _stringList(json['columns']);
      // ⚠️ 行是**二维数组**(`[["a","b"]]`),不能用 _mapList —— 那个只认 Map,
      // 会把每一行都当空丢掉(表格只剩表头)。这里逐行展开,并兼容"行是对象"
      // 与"单元格是数组"两种歪输出。
      final rawRows = <List<String>>[];
      for (final r in (json['rows'] is List ? json['rows'] as List : const [])) {
        if (r is List) {
          final cells = <String>[];
          for (final cell in r) {
            cells.addAll(_stringList(cell));
          }
          rawRows.add(cells);
        } else if (r is Map) {
          final cells = <String>[];
          for (final v in r.values) {
            cells.addAll(_stringList(v));
          }
          rawRows.add(cells);
        }
      }
      final rows = <List<String>>[...rawRows]
        ..removeWhere((r) => r.every((c) => c.trim().isEmpty));
      final flat = _stringList(json['rows']);
      final width = _maxWidth(columns, rawRows, rows, flat);
      // 一列都凑不出来的既不是表格也不该显示 —— 一律当解析失败(界面给可读提示)
      if (columns.isEmpty && rows.isEmpty) return null;
      if (width < 2) return null;
      final body = rows.isNotEmpty ? rows : [flat];
      return {
        'title': _title(json['title'], kind.label),
        'columns': columns,
        'rows': [
          for (final r in body) _pad(r, width),
        ],
        'width': width,
      };

    case MaterialBlockKind.mindmap:
      final center = _str(json['center']);
      final branches = <Map<String, Object?>>[];
      for (final b in _mapList(json['branches'])) {
        final label = _str(b['label'] ?? b['name'] ?? b['topic']);
        if (label.isEmpty) continue;
        branches.add({
          'label': label,
          // 层级 >3 收敛:每个分支最多 4 个子项(再多的在数据层就砍掉,
          // 界面不用再关心"会不会撑爆")
          'children': _stringList(b['children'] ?? b['items']).take(4).toList(),
        });
      }
      if (center.isEmpty || branches.isEmpty) return null;
      // 层级 >3 收敛:只保留 中心 → 分支 → 子项(再深的由 AI 压平)
      return {
        'title': _title(json['title'], kind.label),
        'center': center,
        'branches': branches.take(8).toList(),
      };

    case MaterialBlockKind.timeline:
      final events = <Map<String, String>>[];
      for (final e in _mapList(json['events'] ?? json['items'])) {
        final time = _str(e['time'] ?? e['date'] ?? e['when']);
        final text = _str(e['text'] ?? e['event'] ?? e['desc'] ?? e['title']);
        if (text.isEmpty) continue;
        events.add({'time': time, 'text': text});
      }
      if (events.isEmpty) return null;
      final sorted = _sortTimeline(events);
      return {
        'title': _title(json['title'], kind.label),
        'events': sorted.take(20).toList(),
      };

    case MaterialBlockKind.points:
      final items = <Map<String, String>>[];
      for (final e in _mapList(json['items'] ?? json['points'])) {
        final title = _str(e['title'] ?? e['point'] ?? e['label']);
        final text = _str(e['text'] ?? e['desc'] ?? e['detail'] ?? e['content']);
        if (title.isEmpty && text.isEmpty) continue;
        items.add({'title': title, 'text': text});
      }
      if (items.isEmpty) return null;
      return {
        'title': _title(json['title'], kind.label),
        'items': items.take(12).toList(),
      };

    case MaterialBlockKind.quiz:
      final items = <Map<String, String>>[];
      for (final e in _mapList(json['items'] ?? json['questions'])) {
        final q = _str(e['question'] ?? e['q'] ?? e['title']);
        final a = _str(e['answer'] ?? e['a'] ?? e['text']);
        if (q.isEmpty || a.isEmpty) continue;
        items.add({'question': q, 'answer': a});
      }
      if (items.isEmpty) return null;
      return {
        'title': _title(json['title'], kind.label),
        'items': items.take(8).toList(),
      };
  }
}

String _title(Object? v, String fallback) {
  final s = _str(v);
  return s.isEmpty ? fallback : s;
}

String _str(Object? v) => v == null ? '' : '$v'.trim();

List<String> _stringList(Object? v) {
  if (v is List) {
    return [for (final e in v) _str(e)].where((s) => s.isNotEmpty).toList();
  }
  final s = _str(v);
  return s.isEmpty ? const [] : [s];
}

List<Map<String, Object?>> _mapList(Object? v) {
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (e is Map) Map<String, Object?>.from(e),
  ];
}

List<String> _pad(List<String> row, int width) {
  if (row.length >= width) return row;
  return [...row, ...List.filled(width - row.length, '')];
}

/// 表格实际有多少列 = 表头、每一行、以及"整块给成一维数组"三种形态里的最大值。
/// 必须先算宽度再判"够不够两列" —— 旧写法先判 `rows.isEmpty` 就 return null,
/// 导致 `{"columns":[],"rows":["a","b"]}`(AI 只给了一维行)被误判成解析失败。
int _maxWidth(
  List<String> columns,
  List<List<String>> rawRows,
  List<List<String>> rows,
  List<String> flat,
) {
  var w = columns.length;
  for (final r in rawRows) {
    if (r.length > w) w = r.length;
  }
  for (final r in rows) {
    if (r.length > w) w = r.length;
  }
  if (flat.length > w) w = flat.length;
  return w;
}

/// 时间线排序:年份/数字开头按数字排,其余保持原顺序(稳定)。
List<Map<String, String>> _sortTimeline(List<Map<String, String>> events) {
  final keyed = <MapEntry<int, Map<String, String>>>[];
  for (var i = 0; i < events.length; i++) {
    final m = RegExp(r'\d{1,4}').firstMatch(events[i]['time'] ?? '');
    keyed.add(MapEntry(m == null ? 100000 + i : int.parse(m.group(0)!), events[i]));
  }
  keyed.sort((a, b) => a.key.compareTo(b.key));
  return [for (final e in keyed) e.value];
}

// ═══════════════ 3. 生成:让 AI 按形式整理(严格 JSON)═══════════════

/// 每种形式给模型的 system prompt(含 schema 示例 —— 用户要求"严格 JSON")。
String buildSystemPrompt(MaterialBlockKind kind) {
  const common = '''
规则:
1. 只输出 **JSON 对象**,不要 Markdown 代码块以外的任何解释文字;
2. 中文表达,专业名词保留英文原文(用「中文(English)」的写法);
3. 内容必须**只依据用户给的这段原文**,不要编造原文里没有的事实、数字、年份;
4. 原文信息不足以填满某个字段时,**少给几条**,不要凑数、不要写"暂无"。''';

  switch (kind) {
    case MaterialBlockKind.table:
      return '''你把英语学习材料里的一段原文整理成**中文表格**。
返回 JSON:{"title":"表格标题","note":"一句话说明(可选)",
 "columns":["列1","列2","列3"],
 "rows":[["单元格","单元格","单元格"],["单元格","单元格","单元格"]]}
要求:2~4 列;每行单元格数量必须与 columns 完全一致;数字/年份原样保留。
$common''';

    case MaterialBlockKind.mindmap:
      return '''你把英语学习材料里的一段原文整理成**思维导图**。
返回 JSON:{"title":"导图标题","note":"一句话说明(可选)",
 "center":"中心主题(不超过 12 字)",
 "branches":[{"label":"分支(不超过 10 字)","children":["要点","要点"]}]}
要求:3~6 个分支;每个分支 1~4 个要点;每条不超过 24 字;**最多两层**(分支 → 要点)。
$common''';

    case MaterialBlockKind.timeline:
      return '''你把英语学习材料里的一段原文整理成**时间线**。
返回 JSON:{"title":"时间线标题","note":"一句话说明(可选)",
 "events":[{"time":"1945 年","text":"发生了什么(不超过 40 字)"}]}
要求:按时间先后排列;time 用原文里的年份/日期/阶段词(如"第一步""后来"),
原文**没有时间信息就不要编**,多余的事件宁可不给;最多 8 条。
$common''';

    case MaterialBlockKind.points:
      return '''你把英语学习材料里的一段原文提炼成**要点卡**。
返回 JSON:{"title":"要点标题","note":"一句话说明(可选)",
 "items":[{"title":"要点(不超过 12 字)","text":"一句中文解释(不超过 40 字)"}]}
要求:3~6 条;按原文的逻辑顺序;每条都必须能在原文里找到依据。
$common''';

    case MaterialBlockKind.quiz:
      return '''你就英语学习材料里的一段原文出**理解自测题**(不是语法题)。
返回 JSON:{"title":"自测标题","note":"一句话说明(可选)",
 "items":[{"question":"英文问题(不超过 20 词)","answer":"中文参考答案(不超过 60 字)"}]}
要求:2~5 道;考**内容理解**(主旨、细节、因果、作者态度);
答案必须是原文能支撑的,不要问"你觉得";题目之间不要重复。
$common''';
  }
}

/// 交给模型的 user prompt(带段落位置,便于它写"基于第 N 段")。
String buildUserPrompt(MaterialBlockKind kind, String text, {int chunkIndex = -1}) {
  final at = chunkIndex >= 0 ? '这段是材料的第 ${chunkIndex + 1} 段。' : '';
  return '$at请把下面这段原文整理成「${kind.label}」:\n\n"""\n${text.trim()}\n"""';
}

/// 让 AI 把 [text] 整理成 [kind],**解析成功后落库**,返回结果。
///
/// 全链路不抛异常:未配置 Key / 网络失败 / JSON 读不懂 / 结构不对,
/// 都以 [MaterialBlocksResult.error] 里的一句中文返回,界面按错误卡 + 重试处理。
Future<MaterialBlocksResult> generateBlocks({
  required int materialId,
  required String text,
  required MaterialBlockKind kind,
  String? title,
  int chunkIndex = -1,
}) async {
  final api = DeepseekBlocksApi();
  if (!api.isConfigured) {
    return MaterialBlocksResult(
      kind: kind,
      error: '还没有配置 API Key —— 到「我的 → API 设置」填一个就能生成',
    );
  }
  final body = text.trim();
  if (body.isEmpty) {
    return MaterialBlocksResult(kind: kind, error: '这一段没有正文,没法整理');
  }
  final String raw;
  try {
    raw = await api.completeJson(
      system: buildSystemPrompt(kind),
      user: buildUserPrompt(kind, body, chunkIndex: chunkIndex),
      maxTokens: 3072,
    );
  } catch (e) {
    return MaterialBlocksResult(
      kind: kind,
      error: BaseApiService.friendlyError(e),
    );
  }
  return saveGenerated(
    materialId: materialId,
    kind: kind,
    raw: raw,
    title: title,
    chunkIndex: chunkIndex,
  );
}

/// 解析 + 落库(与网络解耦,便于单测:喂一段 JSON 就能验证落库结果)。
Future<MaterialBlocksResult> saveGenerated({
  required int materialId,
  required MaterialBlockKind kind,
  required String raw,
  String? title,
  int chunkIndex = -1,
}) async {
  final data = parsePayload(kind, raw);
  if (data == null) {
    return MaterialBlocksResult(
      kind: kind,
      error: 'AI 这次没按${kind.label}的格式返回(可能被截断),点「重试」再来一次',
    );
  }
  final aiTitle = '${data['title'] ?? ''}'.trim();
  final finalTitle = (title ?? '').trim().isNotEmpty
      ? title!.trim()
      : (aiTitle.isEmpty ? kind.label : aiTitle);
  final draft = MaterialBlockDraft(
    kind: kind,
    title: finalTitle,
    data: data,
    chunkIndex: chunkIndex,
  );
  final note = '${extractJsonObject(raw)['note'] ?? ''}'.trim();
  final id = await DatabaseService.upsertMaterialBlock(
    materialId: materialId,
    kind: kind.id,
    chunkIndex: chunkIndex,
    title: finalTitle,
    payloadJson: draft.toPayloadJson(),
  );
  if (id <= 0) {
    return MaterialBlocksResult(
      kind: kind,
      error: '整理好了但保存失败(本地数据库写入出错),点「重试」再来一次',
      note: note,
    );
  }
  return MaterialBlocksResult(
    kind: kind,
    draft: draft.copyWith(id: id),
    note: note,
    savedId: id,
  );
}

/// 读这篇材料已落库的所有块(坏数据自动跳过)
Future<List<MaterialBlockDraft>> loadBlocks(int materialId) async {
  final rows = await DatabaseService.getMaterialBlocks(materialId);
  final out = <MaterialBlockDraft>[];
  for (final r in rows) {
    final d = MaterialBlockDraft.fromRow(r);
    if (d != null) out.add(d);
  }
  return out;
}

/// 删掉某一块(界面上的小垃圾桶)
Future<void> removeBlock(int materialId, MaterialBlockKind kind, int chunkIndex) =>
    DatabaseService.deleteMaterialBlocks(
      materialId,
      kind: kind.id,
      chunkIndex: chunkIndex,
    );

int _asInt(Object? v, {int fallback = 0}) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? fallback);

// ═══════════════ 4. 逐段翻译的范围(用户第 3(2) 条:"让用户自选翻译范围")═══════════════

/// 翻译范围。用户原话:"翻译功能进度缓慢,需要增加翻译的进度条…以及让用户自选
/// 翻译范围。" —— 全篇翻一本书 = 几十次请求,现在由**用户自己决定翻多少**:
/// 当前段 / 前后各 3 段 / 当前章或前 20 段 / 整篇。
enum TranslateScope {
  current('当前这一段', Icons.article_outlined),
  around('当前段前后各 3 段', Icons.view_agenda_outlined),
  chapter('当前章 / 前 20 段', Icons.menu_book_outlined),
  all('整篇', Icons.all_inclusive);

  const TranslateScope(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// 一次翻译计划:要翻哪些段、共几段、给用户看的预期文案。
class TranslatePlan {
  final TranslateScope scope;

  /// 待翻段的索引(已按顺序去重)
  final List<int> indices;

  /// 允许这次翻的段索引闭区间(用于算进度,见阅读器里的分母)
  final int rangeStart;
  final int rangeEnd;

  const TranslatePlan({
    required this.scope,
    required this.indices,
    required this.rangeStart,
    required this.rangeEnd,
  });

  int get total => indices.length;

  bool get isEmpty => indices.isEmpty;
}

/// 按范围算出待翻的段(**纯函数,可单测**)。
///
/// [alreadyDone] 是"已经有译文"的段(不重复翻);[failed] 是上次失败的段
/// (用户再点翻译时应当重试它们,所以不排除)。
/// 返回的 indices 一定落在 `[0, chunkCount)` 内且**升序去重**。
TranslatePlan planTranslation({
  required TranslateScope scope,
  required int current,
  required int chunkCount,
  Set<int> alreadyDone = const {},
  Set<int> failed = const {},
}) {
  if (chunkCount <= 0) {
    return TranslatePlan(
      scope: scope,
      indices: const [],
      rangeStart: 0,
      rangeEnd: -1,
    );
  }
  final cur = current.clamp(0, chunkCount - 1);
  final (int start, int end) = switch (scope) {
    // 只翻当前段
    TranslateScope.current => (cur, cur),
    // 前后各 3 段(共 7 段)
    TranslateScope.around => (
        (cur - 3).clamp(0, chunkCount - 1),
        (cur + 3).clamp(0, chunkCount - 1),
      ),
    // 当前章:没有章节信息就用"当前位置起的 20 段"(够读一屏半)
    TranslateScope.chapter => (cur, (cur + 19).clamp(0, chunkCount - 1)),
    TranslateScope.all => (0, chunkCount - 1),
  };
  final out = <int>[];
  for (var i = start; i <= end; i++) {
    if (alreadyDone.contains(i) && !failed.contains(i)) continue;
    out.add(i);
  }
  return TranslatePlan(
    scope: scope,
    indices: out,
    rangeStart: start,
    rangeEnd: end,
  );
}

/// 选择范围时给用户看的提示(段数 + 预计耗时 + "还剩多少没翻")。
///
/// [translated] = **全篇**已经有译文的段数(只用来显示"已翻 N 段"),
/// 与 [pending](本次待翻)含义不同 —— 别把两个数搞混,否则会出现
/// "待翻 37 段(已翻 37 段)"这种自相矛盾的文案。
String translatePlanHint(
  TranslateScope scope, {
  required int chunkCount,
  required int pending,
  required int translated,
}) {
  if (chunkCount <= 0) return '这份材料还没有正文';
  switch (scope) {
    case TranslateScope.current:
      return pending > 0 ? '只翻你正在读的这一段 · 约 5 秒' : '当前段已经翻好了';
    case TranslateScope.around:
      return pending > 0
          ? '共 $pending 段 · ${formatEstimate(estimateTranslationSeconds(pending))}'
          : '这一带的段落都已经翻好了';
    case TranslateScope.chapter:
      return pending > 0
          ? '共 $pending 段 · ${formatEstimate(estimateTranslationSeconds(pending))}'
          : '这一段之后都已经翻好了';
    case TranslateScope.all:
      final base = '共 $chunkCount 段';
      if (pending <= 0) return '$base · 整篇都翻好了';
      return '$base · 待翻 $pending 段 · '
          '${formatEstimate(estimateTranslationSeconds(pending))}'
          '${translated > 0 ? '(已翻 $translated 段)' : ''}';
  }
}

/// 整篇规模很大时的提醒(一本书整篇翻译要很久,得先告诉用户)
String bulkTranslateWarning(int pending) {
  if (pending <= 40) return '';
  return '整篇有 $pending 段要翻,可能要 '
      '${formatEstimate(estimateTranslationSeconds(pending))} 以上;'
      '翻的过程中可以随时「取消」,已经翻好的会保留。';
}

/// 内容块专用的 API 通道。
///
/// 与 [DeepseekApiService] **同一套槽位策略与请求构造**(副槽位已配置走副,
/// 否则走主),只是把"发一次请求并拿回 content"收敛成一个方法 ——
/// 因为本次改动不允许修改 `deepseek_api.dart`,所以这里不复制它的私有实现,
/// 只复用 [BaseApiService] 的公共件。
class DeepseekBlocksApi extends BaseApiService {
  @override
  ApiEndpointConfig get config =>
      ApiEndpointConfig.secondary.isConfigured
          ? ApiEndpointConfig.secondary
          : ApiEndpointConfig.primary;

  bool get isConfigured => config.isConfigured;

  /// 发一次 chat/completions,返回正文(reasoning 通道有内容时也接受)
  Future<String> completeJson({
    required String system,
    required String user,
    int maxTokens = 3072,
    double temperature = 0.3,
  }) async {
    final response = await postWithReasoningFallback(
      '/v1/chat/completions',
      BaseApiService.buildChatBody(
        cfg: config,
        temperature: temperature,
        maxTokens: maxTokens,
        messages: [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': user},
        ],
      ),
      cfg: config,
    );
    return BaseApiService.extractContentWithReasoning(response.data);
  }
}
