/// 「找材料」与频道页**共用的结果列表件**(2026-11-06 · 用户选型后实施)。
///
/// 这个文件的唯一动机:**结果页只允许有一套实现**。
/// 频道页(按题材/按形式/按场景/按需求)与新的「自由搜 / 按需找」两个结果页
/// 必须是同一套分组/分页/封面/保存/打开原文语义,否则用户会在两个入口看到
/// 两种行为,将来改一处必漏一处(设计文档 §3.4 的硬要求)。
///
/// 分三层,层层可复用:
/// 1. **纯函数**(无 BuildContext,可直接单测):
///    [materialResultPageSize] 分页数学、[materialResultGroupOrder] 分组口径、
///    `inferMaterialKind` 类型推断、[groupMaterialResultItems] 分组+排序、
///    [materialResultPageSlices] 「全局页码 + 页内分组小标题」切片;
/// 2. **展示件**:[MaterialResultCoverThumb](真封面缩略图,无图不画假封面)、
///    [MaterialResultCard](结果卡:标题/来源/类型/难度胶囊/摘要/三个动作)、
///    [MaterialResultGroupHeader]、[MaterialResultPageBar](上一页/第X/Y页/下一页)、
///    [MaterialResultList](给新结果页直接用的整段列表);
/// 3. **[MaterialResultController]**:两份新结果页共用的数据+动作(快照读写、
///    去重合并、分页、补抓正文/入库/保存/打开原文)。频道页有自己的一套
///    (行为保持不变,本轮只把「展示」抽出来),新页统一走这个 controller。
///
/// 纪律:
/// - **封面只在真的有图时出现**(`shelfCoverHasImage`),没有图就走纯文字版式,
///   不画渐变假封面(用户 2026-11-06 真机反馈);
/// - 难度只显示**真实算出来的覆盖率**;没抓正文时只允许显示来源级「预计区间」
///   (由 [MaterialLibrary.estimateDifficulty] 给,文案自带"非精确覆盖率");
/// - 文案/颜色/间距一律走 [V4Skin]/[AppFont]/[Gap],不写裸值。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/design_tokens.dart';
import '../config/v4_theme.dart';
import '../providers/vocab_provider.dart';
import '../services/content_quality.dart';
import '../services/deepseek_search.dart';
import '../services/external_link.dart';
import '../services/learner_model_store.dart';
import '../services/material_channel.dart';
import '../services/material_discovery.dart';
import '../services/material_library.dart';
import '../services/material_source.dart';
import 'app_ui.dart';
import 'design_kit.dart';
import 'material_cover.dart';
import 'shelf_cover_grid.dart';

/// 每页条数(与频道页同一口径:10 条 ≈ 手机一屏半)。
const int materialResultPageSize = 10;

/// 总页数(纯函数,可单测)。0 条也算 1 页 —— 页码控件永远显示"第 1 / 1 页"。
int materialResultPageCount(int total, {int pageSize = materialResultPageSize}) {
  if (pageSize <= 0) return 1;
  if (total <= 0) return 1;
  return (total + pageSize - 1) ~/ pageSize;
}

/// 把页码夹进合法范围(纯函数,可单测)。
int materialResultPageClamp(
  int page,
  int total, {
  int pageSize = materialResultPageSize,
}) {
  final maxPage = materialResultPageCount(total, pageSize: pageSize) - 1;
  if (page < 0) return 0;
  return page > maxPage ? maxPage : page;
}

/// 某页对应的条目区间 `[start, end)`(纯函数,可单测)。
({int start, int end}) materialResultPageRange(
  int page,
  int total, {
  int pageSize = materialResultPageSize,
}) {
  if (total <= 0 || pageSize <= 0) return (start: 0, end: 0);
  final safePage = materialResultPageClamp(page, total, pageSize: pageSize);
  final start = safePage * pageSize;
  final end = math.min(start + pageSize, total);
  return (start: start, end: end < start ? start : end);
}

/// 分组顺序:教材 / 应试真题 / 书籍 / 论文 / 外刊新闻 / 文章 / 其他
const List<String> materialResultGroupOrder = <String>[
  'textbook',
  'exam',
  'book',
  'paper',
  'news',
  'article',
  'other',
];

/// 材料 kind → 分组 key / 组名(与设计文档的分组口径一致)。
const Map<String, String> materialResultGroupLabels = <String, String>{
  'textbook': '教材',
  'exam': '应试真题',
  'book': '书籍',
  'paper': '论文',
  'news': '外刊/新闻',
  'article': '文章',
  'other': '其他',
};

String materialResultGroupKeyOf(String kind) {
  final key = kind.trim().toLowerCase();
  return materialResultGroupLabels.containsKey(key) ? key : 'other';
}

/// 卡片上的类型胶囊:先按分组口径,其他类型再回落材料库的 kind 文案。
String materialResultKindChipLabel(String kind) {
  final key = kind.trim().toLowerCase();
  final label = materialResultGroupLabels[key];
  if (label != null && key != 'other') return label;
  return MaterialLibrary.kindLabel(kind);
}

/// 结果类型推断:官方搜索返回的 kind 恒为 article,但「教材 / 应试真题」必须靠
/// 标题/URL 才能真的分出来(质检 P1-3:否则两个分组永远空、教材与书籍内容一样)。
/// 只做保守推断:已有明确 kind(book/paper/news…)不覆盖。
String inferMaterialKind(
  String title,
  String url, {
  String fallback = 'article',
}) {
  if (fallback != 'article' && fallback.isNotEmpty) return fallback;
  final hay = '${title.toLowerCase()} ${url.toLowerCase()}';
  bool has(List<String> keys) => keys.any(hay.contains);
  if (has(<String>[
    '真题',
    '试题',
    '模拟题',
    '试卷',
    '四六级',
    '四级',
    '六级',
    'cet-4',
    'cet4',
    'cet-6',
    'cet6',
    'ielts',
    '雅思',
    '托福',
    'toefl',
    '考研',
    'exam paper',
    'past paper',
    'answer key',
  ])) {
    return 'exam';
  }
  if (has(<String>[
    '教材',
    '课本',
    '新概念',
    '必修',
    '选修',
    '同步练习',
    '教师用书',
    'textbook',
    'workbook',
    'coursebook',
    'new concept',
    'student book',
    'reading and writing',
  ])) {
    return 'textbook';
  }
  return fallback;
}

/// 卡片上的日期(短格式:YYYY-MM-DD)
String materialResultFormatDay(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)}';
}

/// 一个分组(组名 + 组内条目);泛型是为了让频道页的私有模型与新页的
/// [MaterialResultItem] 共用同一套分组/排序实现。
class MaterialResultGroup<T> {
  final String label;
  final List<T> items;

  const MaterialResultGroup({required this.label, required this.items});
}

/// 一页里的分组切片(组名 + 本页该组几条 + 全组共几条 + 本页条目)。
class MaterialResultPageSlice<T> {
  final String label;
  final int groupTotal;
  final List<T> items;

  const MaterialResultPageSlice({
    required this.label,
    required this.groupTotal,
    required this.items,
  });
}

/// 分组 + 组内排序(纯函数)。
///
/// 排序口径与频道页完全一致:
/// 1. **有真实难度分析的在前**(覆盖率降序);
/// 2. 同分(或都没有分析)按**权威度**降序;
/// 3. 再同分按**原始顺序** `seq` 升序(保证稳定,翻页不跳)。
List<MaterialResultGroup<T>> groupMaterialResultItems<T>(
  Iterable<T> items, {
  required String Function(T item) kindOf,
  double? Function(T item)? coverageOf,
  int Function(T item)? authorityOf,
  int Function(T item)? seqOf,
}) {
  final buckets = <String, List<T>>{};
  for (final item in items) {
    final key = materialResultGroupKeyOf(kindOf(item));
    final bucket = buckets[key];
    if (bucket == null) {
      buckets[key] = <T>[item];
    } else {
      bucket.add(item);
    }
  }

  int compare(T a, T b) {
    final aCoverage = coverageOf?.call(a);
    final bCoverage = coverageOf?.call(b);
    if ((aCoverage == null) != (bCoverage == null)) {
      return aCoverage == null ? 1 : -1;
    }
    if (aCoverage != null && bCoverage != null) {
      final byCoverage = bCoverage.compareTo(aCoverage);
      if (byCoverage != 0) return byCoverage;
    }
    final byAuthority =
        (authorityOf?.call(b) ?? -1).compareTo(authorityOf?.call(a) ?? -1);
    if (byAuthority != 0) return byAuthority;
    return (seqOf?.call(a) ?? 0).compareTo(seqOf?.call(b) ?? 0);
  }

  final out = <MaterialResultGroup<T>>[];
  for (final key in materialResultGroupOrder) {
    final list = buckets.remove(key);
    if (list == null || list.isEmpty) continue;
    list.sort(compare);
    out.add(
      MaterialResultGroup<T>(
        label: materialResultGroupLabels[key] ?? '其他',
        items: list,
      ),
    );
  }
  // 防御:未知类型已在 materialResultGroupKeyOf 归入 other,这里理论不命中
  if (buckets.isNotEmpty) {
    final rest = <T>[];
    for (final list in buckets.values) {
      rest.addAll(list);
    }
    rest.sort(compare);
    out.add(MaterialResultGroup<T>(label: '其他', items: rest));
  }
  return out;
}

/// 把"分组顺序 + 当前页区间"合成一页要渲染的分组片段(纯函数,可单测)。
///
/// 为什么不做"每组各自分页":结果总量本来就不大(快照上限 120 条),
/// 每组再分页会出现"3 个组各 1 页"的页码,翻页反而更累;
/// 这里保持**全局页码**(每页 10 条),分组只作为页内小标题。
List<MaterialResultPageSlice<T>> materialResultPageSlices<T>(
  List<MaterialResultGroup<T>> groups,
  int page,
  int total, {
  int pageSize = materialResultPageSize,
}) {
  final range = materialResultPageRange(page, total, pageSize: pageSize);
  final slices = <MaterialResultPageSlice<T>>[];
  var cursor = 0;
  for (final group in groups) {
    final groupStart = cursor;
    final groupEnd = cursor + group.items.length;
    cursor = groupEnd;
    final start = math.max(groupStart, range.start);
    final end = math.min(groupEnd, range.end);
    if (start >= end) continue;
    slices.add(
      MaterialResultPageSlice<T>(
        label: group.label,
        groupTotal: group.items.length,
        items: group.items.sublist(start - groupStart, end - groupStart),
      ),
    );
  }
  return slices;
}

/// 结果条目(新结果页的 UI 侧模型;**与频道页 `_ChannelItem` 同构**)。
///
/// 可变字段都是"这次会话里才产生的状态":
/// - [imageUrl] 补抓正文时拿到真封面才写回(原本没有才写);
/// - [content]/[analysis] 只有本次补抓/发现流水线才有(快照不存);
/// - [materialId]/[saved] 入库/保存后的关系。
class MaterialResultItem {
  final String title;
  final String url;
  final String sourceLabel;
  final String kind;
  final String snippet;

  /// 真实封面(og:image / markdown 首图)。没有就是 null → 文字版式。
  String? imageUrl;

  /// 内容源 id(`gutenberg` / `arxiv` / `npr`…);用于「预计难度」估算。
  /// 快照不存这个字段(契约 9 键),恢复后会变 null → 不显示预计难度。
  final String? sourceId;

  /// 预计难度文案(如「预计 B1~B2 · 中等」;来源级估算,非精确覆盖率)。
  final String? estimateLabel;

  /// 预计难度的口径说明(界面用 tooltip 原样展示,不隐藏"估算")。
  final String? estimateBasis;

  final int authority;
  final DateTime? date;
  final bool fromSearchApi;
  final int seq;

  String? content;
  MaterialAnalysis? analysis;
  bool contentUnavailable;
  String? contentUnavailableReason;
  int? materialId;
  bool saved;

  MaterialResultItem({
    required this.title,
    required this.url,
    required this.sourceLabel,
    required this.kind,
    required this.seq,
    this.snippet = '',
    this.imageUrl,
    this.sourceId,
    this.estimateLabel,
    this.estimateBasis,
    this.authority = -1,
    this.date,
    this.fromSearchApi = false,
    this.content,
    this.analysis,
    this.contentUnavailable = false,
    this.contentUnavailableReason,
    this.materialId,
    this.saved = false,
  });

  /// 从发现流水线的候选转换(内容/难度只在本次运行里有效)。
  factory MaterialResultItem.fromCandidate(
    DiscoveredCandidate c, {
    required int seq,
  }) {
    final title = c.title.trim();
    final content = c.content;
    return MaterialResultItem(
      title: title.isEmpty ? c.url : title,
      url: c.url.trim(),
      sourceLabel: c.sourceLabel.trim(),
      kind: inferMaterialKind(
        title,
        c.url,
        fallback: c.kind.trim().isEmpty ? 'article' : c.kind.trim(),
      ),
      snippet: c.snippet.trim(),
      imageUrl: (c.imageUrl ?? '').trim().isEmpty ? null : c.imageUrl!.trim(),
      authority: c.authority,
      date: c.date,
      fromSearchApi: c.fromSearchApi,
      seq: seq,
      content: content,
      analysis: c.analysis,
      // 发现流水线的 items 都抓到了正文;防御性再确认一次
      contentUnavailable: content == null || content.trim().isEmpty,
    );
  }

  /// 从快照还原(9 个契约字段;脏条目返回 null 由调用方跳过)。
  static MaterialResultItem? fromSnapshot(
    Map<String, Object?> map, {
    required int seq,
  }) {
    final url = '${map['url'] ?? ''}'.trim();
    if (url.isEmpty) return null;
    final title = '${map['title'] ?? ''}'.trim();
    final kind = '${map['kind'] ?? ''}'.trim();
    final imageUrl = '${map['imageUrl'] ?? ''}'.trim();
    final rawDate = map['date'];
    DateTime? date;
    if (rawDate is DateTime) {
      date = rawDate;
    } else if (rawDate != null) {
      date = DateTime.tryParse('$rawDate');
    }
    final rawAuthority = map['authority'];
    final authority = rawAuthority is int
        ? rawAuthority
        : (rawAuthority is num
              ? rawAuthority.toInt()
              : int.tryParse('${rawAuthority ?? ''}') ?? -1);
    return MaterialResultItem(
      title: title.isEmpty ? url : title,
      url: url,
      sourceLabel: '${map['sourceLabel'] ?? ''}'.trim(),
      kind: inferMaterialKind(
        title,
        url,
        fallback: kind.isEmpty ? 'article' : kind,
      ),
      snippet: '${map['snippet'] ?? ''}'.trim(),
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
      authority: authority,
      date: date,
      fromSearchApi: map['fromSearchApi'] == true,
      seq: seq,
    );
  }

  /// 快照 map(与频道页同一契约:9 个字段,正文/难度/相关性一律不存)。
  Map<String, Object?> toSnapshotMap() => <String, Object?>{
        'title': title,
        'url': url,
        'sourceLabel': sourceLabel,
        'kind': kind,
        'snippet': snippet,
        'imageUrl': imageUrl,
        'authority': authority,
        'date': date?.toIso8601String(),
        'fromSearchApi': fromSearchApi,
      };
}

// ═══════════════════════════════════════════════════════════════════════
// 展示件
// ═══════════════════════════════════════════════════════════════════════

/// 发现卡 / 「我的」卡的真实封面缩略图。
///
/// **只在数据里真的有 http(s) 封面地址时才被创建**(调用方先判
/// [shelfCoverHasImage]);加载中 / 加载失败都显示**中性的"无图"占位**
/// (种类图标 + 细边,不带渐变、不冒充书封)。
class MaterialResultCoverThumb extends StatelessWidget {
  final String url;
  final String title;
  final String kind;
  final double width;
  final double height;
  final double radius;

  const MaterialResultCoverThumb({
    super.key,
    required this.url,
    required this.title,
    required this.kind,
    this.width = 58,
    this.height = 76,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: skin.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: skin.hairline),
      ),
      child: Icon(
        coverKindIcon(kind),
        size: width * 0.34,
        color: skin.inkFaint,
      ),
    );
    return Semantics(
      image: true,
      label: title,
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.network(
            url,
            width: width,
            height: height,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                (wasSynchronouslyLoaded || frame != null) ? child : placeholder,
            errorBuilder: (context, error, stackTrace) => placeholder,
          ),
        ),
      ),
    );
  }
}

/// 结果卡:标题 + 来源/类型/难度胶囊 + 摘要 + 按钮行。
///
/// **封面只在真的有图时出现**;没有图不留封面位、不画渐变假封面,
/// 直接把"标题 + 来源/类型/难度"做成文字版式(用户 2026-11-06 真机反馈)。
class MaterialResultCard extends StatelessWidget {
  final String title;
  final String url;
  final String sourceLabel;
  final String kind;
  final String snippet;
  final String? imageUrl;
  final DateTime? date;
  final bool fromSearchApi;
  final int authority;

  /// 真实覆盖率(0~1)。null = 这篇还没抓正文算过 —— **不许拿估算值冒充**。
  final double? coverage;

  /// 真实 CEFR(分析结果里才有)
  final String cefr;

  /// 来源级「预计难度」文案(可选;口径写明"非精确覆盖率")
  final String? estimateLabel;

  final bool saved;
  final bool busy;
  final bool contentUnavailable;
  final bool pdf;

  /// 「为什么推这篇」一行(按需找专用;必须由调用方保证是有真实依据才传)
  final String? reason;

  /// "抓不到正文"的说明文案(有值才显示;频道页与两个新页共用同一套解释)
  final String? unavailableHint;

  final VoidCallback? onRead;
  final VoidCallback? onSave;
  final VoidCallback? onOpenOriginal;

  const MaterialResultCard({
    super.key,
    required this.title,
    required this.url,
    required this.sourceLabel,
    required this.kind,
    required this.snippet,
    this.imageUrl,
    this.date,
    this.fromSearchApi = false,
    this.authority = -1,
    this.coverage,
    this.cefr = '',
    this.estimateLabel,
    this.saved = false,
    this.busy = false,
    this.contentUnavailable = false,
    this.pdf = false,
    this.reason,
    this.unavailableHint,
    this.onRead,
    this.onSave,
    this.onOpenOriginal,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final coverUrl = (imageUrl ?? '').trim();
    final hasCover = shelfCoverHasImage(coverUrl);
    final tags = <Widget>[
      AppTag(sourceLabel.trim().isEmpty ? '未知来源' : sourceLabel),
      AppTag(materialResultKindChipLabel(kind)),
      if (coverage != null)
        AppTag(
          '覆盖率 ${(coverage! * 100).round()}%',
          tone: AppTagTone.primary,
        ),
      if (cefr.isNotEmpty) AppTag(cefr),
      // 没抓正文时只能给"来源级预计区间",且必须写明不是精确覆盖率
      if (coverage == null && (estimateLabel ?? '').isNotEmpty)
        AppTag(estimateLabel!),
      if (fromSearchApi && authority >= 0) AppTag('权威度 $authority/4'),
      if (date != null) AppTag(materialResultFormatDay(date!)),
      if (saved) const AppTag('已在我的', tone: AppTagTone.success),
    ];
    return AppCard(
      variant: AppCardVariant.compact,
      padding: const EdgeInsets.all(Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (hasCover) ...<Widget>[
                MaterialResultCoverThumb(
                  url: coverUrl,
                  title: title,
                  kind: kind,
                ),
                const SizedBox(width: Gap.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.subheadStyle.copyWith(
                        color: skin.ink,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (snippet.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.tagStyle.copyWith(
                          color: skin.inkSoft,
                          height: 1.4,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: tags),
          if ((reason ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: skin.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                reason!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppFont.tagStyle.copyWith(
                  color: skin.inkSoft,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: Gap.xs,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton(
                onPressed: onRead,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('开始读'),
              ),
              OutlinedButton(
                onPressed: onSave,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(saved ? '已在我的' : '保存到我的'),
              ),
              if (url.trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: onOpenOriginal,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    pdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.open_in_new_rounded,
                    size: 14,
                  ),
                  label: Text(pdf ? '打开 PDF' : '打开原文'),
                ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if ((unavailableHint ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                unavailableHint!.trim(),
                style: AppFont.tagStyle.copyWith(
                  color: skin.inkFaint,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 组标题:本页取了几条 + 全组共几条(翻页时用户能看出"这组还没完")
class MaterialResultGroupHeader extends StatelessWidget {
  final String label;
  final int visible;
  final int total;

  const MaterialResultGroupHeader({
    super.key,
    required this.label,
    required this.visible,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.sm, bottom: 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: skin.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppFont.metaStyle.copyWith(
              color: skin.ink,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            visible < total ? '本页 $visible 条 · 共 $total 条' : '$total 篇',
            style: AppFont.tagStyle.copyWith(color: skin.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// 底部页码控件(真分页的核心):上一页 / 第 X / Y 页 / 下一页。
///
/// 视觉沿用果冻语言:白卡 + 细边 + 胶囊按钮;禁用态用 0.45 透明 + 不响应点击
/// (而不是整块变灰 —— 整块灰掉会像"功能坏了",半透明才像"到头了")。
class MaterialResultPageBar extends StatelessWidget {
  final int page;
  final int pageCount;
  final int total;
  final ValueChanged<int> onGo;

  const MaterialResultPageBar({
    super.key,
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final hasPrev = page > 0;
    final hasNext = page < pageCount - 1;
    return AppCard(
      variant: AppCardVariant.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: <Widget>[
          _pageButton(
            skin,
            icon: Icons.chevron_left_rounded,
            label: '上一页',
            enabled: hasPrev,
            onTap: () => onGo(page - 1),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '第 ${page + 1} / $pageCount 页',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.metaStyle.copyWith(
                    color: skin.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '共 $total 篇 · 每页 $materialResultPageSize 条',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.tagStyle.copyWith(color: skin.inkFaint),
                ),
              ],
            ),
          ),
          _pageButton(
            skin,
            icon: Icons.chevron_right_rounded,
            label: '下一页',
            enabled: hasNext,
            onTap: () => onGo(page + 1),
          ),
        ],
      ),
    );
  }

  Widget _pageButton(
    V4Skin skin, {
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final color = enabled ? skin.accent : skin.inkFaint;
    final isPrev = icon == Icons.chevron_left_rounded;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: Radii.pillRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: skin.surfaceAlt,
            borderRadius: Radii.pillRadius,
            border: Border.all(color: skin.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (isPrev) Icon(icon, size: 16, color: color),
              if (isPrev) const SizedBox(width: 1),
              Text(
                label,
                style: AppFont.metaStyle.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!isPrev) const SizedBox(width: 1),
              if (!isPrev) Icon(icon, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// 给"自由搜 / 按需找"结果页直接用的整段列表(不可滚动,由父级 ListView 承载)。
///
/// 结构与频道页一致:页内分组小标题 → 本页卡片 → 页码控件 → 「继续找更多」。
/// 父级负责滚动与「切页回顶」(把 page 状态和 ScrollController 放父级,
/// 这样两个新页、以后的频道页都能复用同一套行为)。
class MaterialResultList extends StatelessWidget {
  final List<MaterialResultItem> items;
  final int page;
  final String? busyUrl;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<MaterialResultItem> onRead;
  final ValueChanged<MaterialResultItem> onSave;
  final ValueChanged<MaterialResultItem> onOpenOriginal;

  /// 每张卡的「为什么推这篇」文案(按需找用;返回 null 就不显示)
  final String? Function(MaterialResultItem item)? reasonFor;

  /// 「继续找更多」:不传 = 不显示按钮
  final VoidCallback? onContinue;
  final bool continueEnabled;
  final String continueLabel;
  final String? continueHint;

  const MaterialResultList({
    super.key,
    required this.items,
    required this.page,
    required this.busyUrl,
    required this.onPageChanged,
    required this.onRead,
    required this.onSave,
    required this.onOpenOriginal,
    this.reasonFor,
    this.onContinue,
    this.continueEnabled = true,
    this.continueLabel = '继续找更多',
    this.continueHint,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final pageCount = materialResultPageCount(items.length);
    final safePage = materialResultPageClamp(page, items.length);
    final groups = groupMaterialResultItems<MaterialResultItem>(
      items,
      kindOf: (item) => item.kind,
      coverageOf: (item) => item.analysis?.knownTokenRatio,
      authorityOf: (item) => item.authority,
      seqOf: (item) => item.seq,
    );
    final slices = materialResultPageSlices<MaterialResultItem>(
      groups,
      safePage,
      items.length,
    );
    final children = <Widget>[];
    for (final slice in slices) {
      children.add(
        MaterialResultGroupHeader(
          label: slice.label,
          visible: slice.items.length,
          total: slice.groupTotal,
        ),
      );
      for (final item in slice.items) {
        children.add(
          MaterialResultCard(
            title: item.title,
            url: item.url,
            sourceLabel: item.sourceLabel,
            kind: item.kind,
            snippet: item.snippet,
            imageUrl: item.imageUrl,
            date: item.date,
            fromSearchApi: item.fromSearchApi,
            authority: item.authority,
            coverage: item.analysis?.knownTokenRatio,
            cefr: item.analysis?.cefr ?? '',
            estimateLabel: item.estimateLabel,
            saved: item.saved,
            busy: busyUrl != null && busyUrl == item.url,
            contentUnavailable: item.contentUnavailable,
            pdf: MaterialDiscovery.looksLikePdfUrl(item.url),
            reason: reasonFor?.call(item),
            onRead: item.contentUnavailable || busyUrl != null
                ? null
                : () => onRead(item),
            onSave: item.contentUnavailable ||
                    item.saved ||
                    busyUrl != null
                ? null
                : () => onSave(item),
            onOpenOriginal: busyUrl != null ? null : () => onOpenOriginal(item),
          ),
        );
      }
    }
    children.add(const SizedBox(height: Gap.sm));
    children.add(
      MaterialResultPageBar(
        page: safePage,
        pageCount: pageCount,
        total: items.length,
        onGo: onPageChanged,
      ),
    );
    if (onContinue != null) {
      children.add(const SizedBox(height: Gap.sm));
      children.add(
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: continueEnabled ? onContinue : null,
            icon: const Icon(Icons.travel_explore_rounded, size: 18),
            label: Text(continueLabel),
          ),
        ),
      );
    }
    if ((continueHint ?? '').trim().isNotEmpty) {
      children.add(const SizedBox(height: Gap.xs));
      children.add(
        Center(
          child: Text(
            continueHint!,
            style: AppFont.tagStyle.copyWith(color: skin.inkFaint),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 数据 + 动作共用控制器(新结果页用;频道页保持自己的一套,行为不变)
// ═══════════════════════════════════════════════════════════════════════

/// 结果页的共用控制器:快照读写、去重合并、分页、补抓正文/入库/保存/打开原文。
///
/// 为什么抽出这一层:自由搜与按需找两个页面的"结果 → 开始读 / 保存到我的 /
/// 打开原文"必须与频道页**同一套行为**(补抓正文 → 质量闸门 → 入库 → 记保存关系),
/// 复制两份必然漂移;抽成一处后两份页面只负责"怎么搜"。
///
/// 页面用法:`controller.addListener(() => setState(() {}))` + 调 [read]/[save]
/// 拿 snack 文案。**不持有 BuildContext**(只在动作里临时接收)。
class MaterialResultController extends ChangeNotifier {
  MaterialResultController({
    required this.storeId,
    this.readerBuilder,
  });

  /// 快照/保存关系的频道 id(`need:all` 或 `free:<归一关键词>`)
  final String storeId;

  /// 「开始读」时构建阅读器页面的回调(**注入而不是 import**,这样这一层不依赖
  /// 具体屏幕,可在纯 widget 测试里跑;调用方通常传
  /// `(id) => MaterialReaderScreen(materialId: id)`)。
  final Widget Function(int materialId)? readerBuilder;

  final List<MaterialResultItem> items = <MaterialResultItem>[];
  final Set<String> savedIds = <String>{};
  int page = 0;
  String? busyUrl;
  DateTime? updatedAt;
  int apiRequests = 0;
  double costCny = 0;
  List<String> notes = <String>[];
  bool loadingSnapshot = false;

  int get pageCount => materialResultPageCount(items.length);

  int get safePage => materialResultPageClamp(page, items.length);

  /// 读上次结果快照 + 保存关系(失败静默:页面照常可用)
  Future<void> loadSnapshot() async {
    loadingSnapshot = true;
    _notify();
    try {
      final snapshot = await MaterialChannelStore.loadSnapshot(storeId);
      savedIds
        ..clear()
        ..addAll(await MaterialChannelStore.savedMaterialIds(storeId));
      items.clear();
      if (snapshot != null) {
        var seq = 0;
        for (final map in snapshot.items) {
          final item = MaterialResultItem.fromSnapshot(map, seq: seq);
          if (item == null) continue;
          items.add(item);
          seq++;
        }
        updatedAt = snapshot.updatedAt;
        apiRequests = snapshot.apiRequests;
        costCny = snapshot.costCny;
      }
      for (final item in items) {
        final id = item.materialId;
        if (id != null && savedIds.contains('$id')) item.saved = true;
      }
      page = materialResultPageClamp(page, items.length);
    } catch (_) {
      // 快照读失败不影响页面:按空列表继续
    } finally {
      loadingSnapshot = false;
      _notify();
    }
  }

  /// 合并一轮新结果 + 落快照。
  ///
  /// [append] = true 用于「继续找更多」:旧条目保持原顺序,新条目按 URL 归一去重后
  /// 追加;快照侧由 [MaterialChannelStore.saveRun] 再按同一归一规则去重并累加成本。
  Future<bool> applyRun({
    required List<MaterialResultItem> fresh,
    required List<String> queriesUsed,
    required int runApiRequests,
    required double runCostCny,
    required List<String> runNotes,
    bool append = false,
  }) async {
    final before = items.length;
    if (!append) {
      items.clear();
      page = 0;
    }
    final seen = <String>{for (final item in items) normalizedUrlKey(item.url)};
    var added = 0;
    for (final item in fresh) {
      final key = normalizedUrlKey(item.url);
      if (key.isEmpty || !seen.add(key)) continue;
      items.add(item);
      added++;
    }
    updatedAt = DateTime.now();
    apiRequests += runApiRequests;
    costCny += runCostCny;
    notes = List<String>.of(runNotes);
    if (append && added > 0) {
      // 追加后跳到"第一条新结果"所在页:用户点完「继续找更多」要立刻看到新东西
      page = materialResultPageClamp(
        before ~/ materialResultPageSize,
        items.length,
      );
    }
    _notify();
    try {
      return await MaterialChannelStore.saveRun(
        storeId,
        items: <Map<String, Object?>>[
          for (final item in fresh) item.toSnapshotMap(),
        ],
        apiRequests: runApiRequests,
        costCny: runCostCny,
        queriesUsed: queriesUsed,
        append: append,
      );
    } catch (_) {
      return false;
    }
  }

  void goPage(int next) {
    final clamped = materialResultPageClamp(next, items.length);
    if (clamped == page) return;
    page = clamped;
    _notify();
  }

  void clearResults() {
    items.clear();
    page = 0;
    _notify();
  }

  /// 「开始读」:本地已有这篇 → 直接打开;否则补抓正文 → 入库 → 进阅读器。
  /// 返回非空 = 需要页面弹的提示文案。
  Future<String?> read(BuildContext context, MaterialResultItem item) async {
    if (busyUrl != null) return null;
    busyUrl = item.url;
    _notify();
    try {
      var materialId = item.materialId;
      if (materialId == null) {
        final ok = await _ensureContent(item);
        if (!ok) {
          item.contentUnavailable = true;
          return _unavailableHint(item);
        }
        // await 之后再碰 context 前必须确认还挂着(控制器不持有 BuildContext)
        if (!context.mounted) return null;
        materialId = await _ingest(context, item);
        item.materialId = materialId;
      }
      if (!context.mounted) return null;
      final builder = readerBuilder;
      if (builder == null) return '阅读器没有接入,暂时不能打开(请从材料中心进入)';
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => builder(materialId!)),
      );
      return null;
    } catch (e) {
      return '打开失败:$e';
    } finally {
      busyUrl = null;
      _notify();
    }
  }

  /// 「保存到我的」:本地已有这篇 → 只记保存关系;否则补抓正文 → 入库 → 记录。
  /// 返回非空 = 需要页面弹的提示文案(成功也是)。
  Future<String?> save(BuildContext context, MaterialResultItem item) async {
    if (busyUrl != null || item.saved) return null;
    busyUrl = item.url;
    _notify();
    try {
      var materialId = item.materialId;
      if (materialId == null) {
        final ok = await _ensureContent(item);
        if (!ok) {
          item.contentUnavailable = true;
          return _unavailableHint(item, saving: true);
        }
        if (!context.mounted) return null;
        materialId = await _ingest(context, item);
        item.materialId = materialId;
      }
      final saved = await MaterialChannelStore.addSavedMaterial(
        storeId,
        materialId,
      );
      if (!saved) return '保存失败:本地存储写入出错,请重试';
      await MaterialChannelStore.removeHiddenMaterial(storeId, materialId);
      savedIds.add('$materialId');
      item.saved = true;
      _notify();
      return '已保存到「我的」,可以在那里离线读、改中文名、删除。';
    } catch (e) {
      return '保存失败:$e';
    } finally {
      busyUrl = null;
      _notify();
    }
  }

  /// 打开原文 / PDF(系统浏览器兜底:抓不到正文的结果也必须能点动)
  Future<String?> openOriginal(MaterialResultItem item) async {
    if (item.url.trim().isEmpty) return null;
    final ok = await launchExternalUrl(item.url);
    return ok ? null : '这个链接打不开,可以换一篇或稍后再试。';
  }

  /// 页面卸载后别再 notify(controller 由 State 持有并 dispose)
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  // ── 内部:补抓正文 / 入库(与频道页同一套质量闸门)──────────────────

  Future<bool> _ensureContent(MaterialResultItem item) async {
    final cached = item.content;
    if (cached != null && cached.trim().isNotEmpty) return true;
    if (item.contentUnavailable) return false;
    final fetched = await _fetchContentFor(item);
    if (fetched == null || fetched.trim().isEmpty) {
      item.contentUnavailable = true;
      return false;
    }
    item.content = fetched;
    return true;
  }

  /// 按需补抓正文:① 普通 HTTP 抓取;② 官方 Fetch(教材/真题多在中文站)。
  ///
  /// 每段都要过 [ContentQuality.rejectReason] 四道闸;**两段都不合格返回 null**,
  /// 由调用方提示"抓不到正文,可打开原文/PDF",而不是把宣传页塞进阅读器。
  /// 抓取顺带把**真实封面**写回 [MaterialResultItem.imageUrl](原本没图才写)。
  Future<String?> _fetchContentFor(MaterialResultItem item) async {
    String? lastReason;
    try {
      final doc = await MaterialSourceService.instance.fetchAnyUrl(
        item.url,
        titleHint: item.title,
      );
      _rememberCover(item, doc.coverUrl, baseUrl: item.url);
      final text = doc.chunks.map((chunk) => chunk.text).join('\n\n').trim();
      final reason = ContentQuality.rejectReason(text);
      if (reason == null) return text;
      lastReason = reason;
    } catch (_) {
      // 普通抓取失败 → 尝试官方 Fetch
    }
    try {
      final client = DeepSeekSearchClient();
      if (!client.available) {
        item.contentUnavailableReason = lastReason;
        return null;
      }
      final fetched = await client.fetch(item.url);
      if (fetched == null) {
        item.contentUnavailableReason = lastReason;
        return null;
      }
      final markdown = fetched.content;
      _rememberCover(
        item,
        ContentQuality.firstImageFromMarkdown(markdown, baseUrl: item.url),
      );
      final text = plainTextFromMarkdown(markdown).trim();
      final reason = ContentQuality.rejectReason(text);
      if (reason == null) return text;
      item.contentUnavailableReason = reason;
      return null;
    } catch (_) {
      item.contentUnavailableReason = lastReason;
      return null;
    }
  }

  /// 把抓到的真实封面写回条目(只在原本**没有**封面时写,不覆盖已有图)。
  void _rememberCover(MaterialResultItem item, String? raw, {String? baseUrl}) {
    if ((item.imageUrl ?? '').trim().isNotEmpty) return;
    final cover = ContentQuality.absoluteHttpUrl(raw ?? '', baseUrl: baseUrl);
    if (cover == null || cover.trim().isEmpty) return;
    item.imageUrl = cover;
  }

  /// 入库(正文 → 材料库),返回 materialId。**调用前必须确认 context.mounted**。
  Future<int> _ingest(BuildContext context, MaterialResultItem item) async {
    final vocab = context.read<VocabProvider>().vocabularies;
    final content = item.content;
    if (content == null || content.trim().isEmpty) {
      throw StateError('这篇还没抓到正文,不能入库');
    }
    final ingested = await MaterialLibrary.ingestText(
      title: item.title.trim().isEmpty ? item.url : item.title.trim(),
      text: content,
      model: LearnerModelStore.load(),
      vocab: vocab,
      kind: item.kind,
      url: item.url,
      coverUrl: item.imageUrl,
    );
    return ingested.materialId;
  }

  String _unavailableHint(MaterialResultItem item, {bool saving = false}) {
    final reason = (item.contentUnavailableReason ?? '').trim();
    final tail = saving ? '可以先「打开原文」读一遍,再回来保存。' : '可以先「打开原文」读,或换一篇。';
    if (reason.isEmpty) return '这篇抓不到可读正文,$tail';
    return '这篇抓到的不是正文($reason),$tail';
  }
}
