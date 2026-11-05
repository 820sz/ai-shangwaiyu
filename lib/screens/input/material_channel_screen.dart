import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../providers/vocab_provider.dart';
import '../../services/database.dart';
import '../../services/deepseek_search.dart';
import '../../services/external_link.dart';
import '../../services/input_prefs.dart';
import '../../services/learner_model_store.dart';
import '../../services/material_channel.dart';
import '../../services/material_discovery.dart';
import '../../services/material_library.dart';
import '../../services/material_need.dart';
import '../../services/material_source.dart';
import '../../services/material_taxonomy.dart';
import '../../services/original_search.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/confirm_destructive.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/search_timeline.dart';
import '../../widgets/v4/v4_kit.dart';
import 'material_browse_screen.dart';
import 'material_reader_screen.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// **材料中心 · 频道页**(v5 · 方案 2「频道化」,2026-11-05 用户拍板)
/// ═══════════════════════════════════════════════════════════════════════
///
/// 一个入口 = 一个频道(按需求 / 按题材 / 按形式 / 按场景)。频道页解决三件旧问题:
/// 1. **二级板块点进去只有"历史材料的无限竖列"** → 改成分「发现 / 我的」两个 Tab:
///    「发现」是真实检索结果(可分组、可分页、可保存),「我的」才是历史材料
///    (可编辑中文名 / 从频道移除 / 删除);
/// 2. **AI 补长尾的结果留不下来** → 发现结果按频道 id 落 Hive 快照
///    ([MaterialChannelStore]);下次进频道先显示上次结果 + 更新时间/花费;
/// 3. **只有"重新找",没有"继续找更多"/分页** → 结果每页最多 10 条本地分页,
///    底部「继续找更多」先让模型基于**真实已见候选**换检索词,再带着
///    `excludeUrls` 去搜,不会把上一页的卡片重复塞回来。
///
/// 视觉纪律:沿用 v4「明亮果冻」语言 —— [V4Skin] 取色、白卡 + 细边 + 柔影
/// ([AppCard])、胶囊 chip、大标题 20~24px、间距一律 [Gap]。不写裸色值。
///
/// 依赖边界(契约由 Lead 固定,本页只调用):
/// - `MaterialChannel` / `ChannelRunSnapshot` / `MaterialChannelStore` 来自
///   `services/material_channel.dart`;
/// - `MaterialDiscovery.discover(excludeUrls:/extraQueries:)`、
///   `planNextQueries()`、`looksLikePdfUrl()` 来自 `services/material_discovery.dart`。
class MaterialChannelScreen extends StatefulWidget {
  /// 频道属于哪个大方向(按需求 / 按题材 / 按形式 / 按场景)
  final MaterialDirection direction;

  /// 从材料中心点进来时预选的子分类 id(为空 = 整个方向)
  final String? initialSubtopic;

  const MaterialChannelScreen({
    super.key,
    required this.direction,
    this.initialSubtopic,
  });

  @override
  State<MaterialChannelScreen> createState() => _MaterialChannelScreenState();
}

/// 发现 Tab 的一条结果(**UI 侧模型**)。
///
/// 为什么 UI 再建一层模型、而不是直接拿 [DiscoveredCandidate] 渲染:
/// - 快照**不存正文**(契约),从快照还原的条目没有 content/analysis,
///   但卡片仍要能显示来源/类型/日期、仍要能点开原文;
/// - 用户从快照点「开始读 / 保存」时要**按需补抓正文**,并把"确定抓不到"
///   记在条目上(之后禁用入口并提示打开原文),这些状态不属于发现流水线。
/// 结果类型推断:官方搜索返回的 kind 恒为 article,但「教材 / 应试真题」必须靠
/// 标题/URL 才能真的分出来(质检 P1-3:否则两个分组永远空、教材与书籍内容一样)。
/// 只做保守推断:已有明确 kind(book/paper/news…)不覆盖。
String inferChannelKind(
  String title,
  String url, {
  String fallback = 'article',
}) {
  if (fallback != 'article' && fallback.isNotEmpty) return fallback;
  final hay = '${title.toLowerCase()} ${url.toLowerCase()}';
  bool has(List<String> keys) => keys.any(hay.contains);
  if (has(<String>[
    '真题', '试题', '模拟题', '试卷', '四六级', '四级', '六级', 'cet-4', 'cet4',
    'cet-6', 'cet6', 'ielts', '雅思', '托福', 'toefl', '考研', 'exam paper',
    'past paper', 'answer key',
  ])) {
    return 'exam';
  }
  if (has(<String>[
    '教材', '课本', '新概念', '必修', '选修', '同步练习', '教师用书', 'textbook',
    'workbook', 'coursebook', 'new concept', 'student book', 'reading and writing',
  ])) {
    return 'textbook';
  }
  return fallback;
}

class _ChannelItem {
  final String title;
  final String url;
  final String sourceLabel;
  final String kind;
  final String snippet;
  final String? imageUrl;
  final int authority;
  final DateTime? date;
  final bool fromSearchApi;

  /// 原始顺序(组内排序的同分兜底,保证稳定)
  final int seq;

  /// 正文(快照还原时为 null;用户点开始读/保存时补抓)
  String? content;

  /// 本地难度分析(只有本次**新抓**的候选才有 —— 快照不存 analysis)
  MaterialAnalysis? analysis;

  /// 已经确认抓不到正文(本轮流水线里被抓取失败,或补抓失败)
  bool contentUnavailable;

  /// 已入库的材料 id(本次会话内点过开始读/保存)
  int? materialId;

  /// 已保存到本频道「我的」
  bool saved = false;

  _ChannelItem({
    required this.title,
    required this.url,
    required this.sourceLabel,
    required this.kind,
    required this.snippet,
    required this.seq,
    this.imageUrl,
    this.authority = -1,
    this.date,
    this.fromSearchApi = false,
    this.content,
    this.analysis,
    this.contentUnavailable = false,
  });

  /// 从发现流水线的候选转换(内容/难度只在本次运行里有效)。
  factory _ChannelItem.fromCandidate(
    DiscoveredCandidate c, {
    required int seq,
  }) {
    final title = c.title.trim();
    final content = c.content;
    return _ChannelItem(
      title: title.isEmpty ? c.url : title,
      url: c.url.trim(),
      sourceLabel: c.sourceLabel.trim(),
      kind: inferChannelKind(title, c.url, fallback: c.kind.trim().isEmpty ? 'article' : c.kind.trim()),
      snippet: c.snippet.trim(),
      imageUrl: (c.imageUrl ?? '').trim().isEmpty ? null : c.imageUrl!.trim(),
      authority: c.authority,
      date: c.date,
      fromSearchApi: c.fromSearchApi,
      seq: seq,
      content: content,
      analysis: c.analysis,
      // 发现流水线的 items 都抓到了正文;这里仍做防御,避免将来契约变化时
      // 把"无正文"当成可读条目
      contentUnavailable: content == null || content.trim().isEmpty,
    );
  }

  /// 从频道快照还原(9 个契约字段;脏条目返回 null 由调用方跳过)。
  static _ChannelItem? fromSnapshot(
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
    return _ChannelItem(
      title: title.isEmpty ? url : title,
      url: url,
      sourceLabel: '${map['sourceLabel'] ?? ''}'.trim(),
      kind: inferChannelKind(title, url, fallback: kind.isEmpty ? 'article' : kind),
      snippet: '${map['snippet'] ?? ''}'.trim(),
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
      authority: authority,
      date: date,
      fromSearchApi: map['fromSearchApi'] == true,
      seq: seq,
    );
  }
}

/// 结果分组(按材料类型;组名带数量)。
class _ResultGroup {
  final String label;
  final List<_ChannelItem> items;

  const _ResultGroup({required this.label, required this.items});
}

class _MaterialChannelScreenState extends State<MaterialChannelScreen>
    with SingleTickerProviderStateMixin {
  late final MaterialDirectionDef _def;
  late final TabController _tab;

  /// 需求/偏好缓存(频道查询词与 needText 都从这两份推导;改完设置回来会重读)
  InputPreferences _prefs = InputPreferences(band: DifficultyBand.any);
  MaterialNeed _need = const MaterialNeed();

  /// 已选子分类(空 = 整个方向;「按需求」方向没有子分类)
  final Set<String> _selected = <String>{};

  /// 发现 Tab 结果(快照 + 本次运行的并集)
  List<_ChannelItem> _items = <_ChannelItem>[];

  /// 我的 Tab:该频道保存过 / 符合子分类的历史材料
  List<ShelfItem> _mine = <ShelfItem>[];
  Set<String> _savedIds = <String>{};

  /// 本次会话里已从频道移除的材料 id(仅隐藏,不删材料)
  final Set<int> _removed = <int>{};

  /// 频道级持久移除表(跨会话;从「我的」移过的不会再出现)
  Set<String> _hiddenIds = <String>{};

  DateTime? _updatedAt;
  int _apiRequests = 0;
  double _costCny = 0;

  /// 最近一次运行的说明(源失败/过滤条数 —— 原样展示,不隐瞒)
  List<String> _notes = <String>[];

  final List<SearchEvent> _events = <SearchEvent>[];
  bool _showProcess = false;
  bool _running = false;
  bool _loading = true;
  bool _mineLoading = false;

  /// 本次会话跑过发现(用于区分"还没找过"的介绍卡与"找过但空的"空态卡)
  bool _ranThisSession = false;
  String? _error;

  /// 正在补抓/入库的条目 url(单条互斥,避免连点重复入库)
  String? _busyUrl;

  int _visibleCount = 10;
  int _mineVisible = 20;

  @override
  void initState() {
    super.initState();
    _def = MaterialTaxonomy.of(widget.direction);
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(_onTabChanged);
    // 预选子分类:只有确实属于本方向的 id 才收,防止路由参数写错导致空频道
    final initial = widget.initialSubtopic;
    if (initial != null &&
        MaterialTaxonomy.subtopicOf(widget.direction, initial) != null) {
      _selected.add(initial);
    }
    _refreshPrefsAndNeed();
    unawaited(_reloadAll());
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // indexIsChanging 期间会多次回调;只在切到「我的」后刷一次材料列表
    if (_tab.indexIsChanging) return;
    if (_tab.index == 1) unawaited(_loadMine(showLoading: false));
  }

  // ═══════════════════════════════════════════════════════════════════
  // 频道身份:方向 + 排序后的已选子分类 → 稳定 id(快照按 id 存,不能漂)
  // ═══════════════════════════════════════════════════════════════════

  /// 频道短标题(协议里的展示名):「按题材」「按形式」「按场景」「按需求」。
  String get _shortTitle {
    final label = _def.label.replaceAll('找材料', '').trim();
    return label.isEmpty ? _def.label : label;
  }

  /// 频道值对象:UI 侧把 id / 标题 / 检索词一次算清,交给同一套快照存储。
  ///
  /// id 形如 `topic:tech,business`;不选任何子分类 = 整个方向 → `topic:all`。
  /// **不把需求摘要拼进 id**:按需求频道的 id 固定为 `need:all`,需求本身在
  /// needText/queries 里,这样用户改需求后仍能读到上一次的发现结果。
  MaterialChannel get _channel {
    final ids = _selected.toList()..sort();
    final labels = <String>[];
    for (final id in ids) {
      final sub = MaterialTaxonomy.subtopicOf(widget.direction, id);
      if (sub != null) labels.add(sub.label);
    }
    final needSummary = _need.summary;
    final needText = widget.direction == MaterialDirection.need
        ? (needSummary.trim().isEmpty ? '按我的需求找真实材料' : needSummary)
        : <String>[
            _shortTitle,
            if (labels.isNotEmpty) labels.join('、'),
            if (!_need.isEmpty) '我的需求:$needSummary',
          ].join(' · ');
    return MaterialChannel(
      id: '${widget.direction.name}:${ids.isEmpty ? 'all' : ids.join(',')}',
      title: labels.isEmpty
          ? _shortTitle
          : '$_shortTitle · ${labels.join('、')}',
      direction: widget.direction,
      subtopicIds: ids,
      queries: _buildQueries(ids),
      needText: needText,
    );
  }

  /// 频道检索词:子分类自带的 queries + 展示名(中文给官方搜索)。
  ///
  /// 按题材/按形式的子分类在 taxonomy 里**没有** queries(那是给「按场景」配的),
  /// 若不补英文词,公开源(RSS/Gutenberg/arXiv 只认拉丁字母)一条都搜不到。
  /// 所以这里按 id 补一组**通用英文检索词**(不是假数据,是真实检索词),
  /// 保证没配官方 Key 时频道也有发现能力。
  List<String> _buildQueries(List<String> selectedIds) {
    if (widget.direction == MaterialDirection.need) return _needQueries();
    final subs = <MaterialSubtopic>[];
    if (selectedIds.isEmpty) {
      subs.addAll(_def.subtopics);
    } else {
      for (final id in selectedIds) {
        final sub = MaterialTaxonomy.subtopicOf(widget.direction, id);
        if (sub != null) subs.add(sub);
      }
    }
    final out = <String>[];
    for (final sub in subs) {
      out.addAll(sub.queries);
      out.add(sub.label);
      if (sub.queries.isEmpty) {
        out.addAll(
          _subQueryFallback['${widget.direction.name}:${sub.id}'] ??
              const <String>[],
        );
      }
    }
    return _dedupeTake(out, 6);
  }

  /// 按需求方向:需求里的自由文本/目标/英文兴趣直接当检索词(官方搜索认中文)。
  List<String> _needQueries() {
    final out = <String>[];
    final extra = _need.extra.trim();
    if (extra.isNotEmpty) out.add(extra);
    out.addAll(_prefs.examGoals);
    for (final interest in _prefs.interests) {
      if (_hasLatin(interest)) out.add(interest);
    }
    if (out.isEmpty) out.add('english reading');
    return _dedupeTake(out, 6);
  }

  /// 子分类补全检索词(仅当 taxonomy 没给 queries 时使用)。
  ///
  /// 键是 `方向:子分类 id`,避免不同方向里同 id(如 form/exam 与 scene/exam)
  /// 互相串词。新增子分类时在这里补一行即可,不需要动 taxonomy(那是纯常量层)。
  static const Map<String, List<String>> _subQueryFallback =
      <String, List<String>>{
        // 按题材
        'topic:sci_tech': <String>['science technology news'],
        'topic:business': <String>['business politics news'],
        'topic:health': <String>['health lifestyle news'],
        'topic:culture': <String>['culture arts news'],
        'topic:travel': <String>['travel experience article'],
        'topic:language': <String>['language learning english'],
        // 按形式
        'form:textbook': <String>['english textbook'],
        'form:book': <String>['english book'],
        'form:news': <String>['english news magazine'],
        'form:paper': <String>['academic paper'],
        'form:exam': <String>['exam paper'],
        'form:fragment': <String>['english article'],
        'form:other': <String>[],
      };

  static bool _hasLatin(String text) => RegExp(r'[A-Za-z]').hasMatch(text);

  /// 去空白/去重/截断(检索词和展示都靠它,避免同一词重复出现在来源里)
  static List<String> _dedupeTake(Iterable<String> raw, int max) {
    final out = <String>[];
    for (final item in raw) {
      final text = item.trim();
      if (text.isEmpty || out.contains(text)) continue;
      out.add(text);
      if (out.length >= max) break;
    }
    return out;
  }

  // ═══════════════════════════════════════════════════════════════════
  // 数据加载
  // ═══════════════════════════════════════════════════════════════════

  /// 读需求偏好。Hive 未打开/脏数据时退回空偏好,不能让页面打不开
  /// (单测里没有 Hive 时尤其重要 —— 频道页要能在纯 widget test 里渲染)。
  void _refreshPrefsAndNeed() {
    try {
      _prefs = InputPreferences.load();
    } catch (e) {
      debugPrint('ReadFlow 频道页读取输入偏好失败(用空偏好继续): $e');
    }
    try {
      _need = MaterialNeed.load();
    } catch (e) {
      debugPrint('ReadFlow 频道页读取需求失败(用空需求继续): $e');
    }
  }

  /// 换频道(改子分类)或首次进入:读快照 + 保存关系 + 材料库,重置分页。
  ///
  /// [showPageLoading] = false 用于下拉刷新:保留当前内容只转刷新圈,
  /// 否则整页会闪成"正在打开频道…"(切频道时才需要整页 loading)。
  Future<void> _reloadAll({bool showPageLoading = true}) async {
    _refreshPrefsAndNeed();
    final channel = _channel;
    setState(() {
      _loading = showPageLoading;
      _error = null;
      _events.clear();
      _showProcess = false;
      _ranThisSession = false;
    });
    ChannelRunSnapshot? snapshot;
    Set<String> savedIds = <String>{};
    Set<String> hiddenIds = <String>{};
    List<ShelfItem> shelf = const <ShelfItem>[];
    try {
      snapshot = await MaterialChannelStore.loadSnapshot(channel.id);
      savedIds = await MaterialChannelStore.savedMaterialIds(channel.id);
      hiddenIds = await MaterialChannelStore.hiddenMaterialIds(channel.id);
      shelf = await MaterialLibrary.shelf(limit: 300);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取频道数据失败:$e';
      });
      return;
    }
    if (!mounted || channel.id != _channel.id) return;

    final items = <_ChannelItem>[];
    if (snapshot != null) {
      for (final map in snapshot.items) {
        final item = _ChannelItem.fromSnapshot(map, seq: items.length);
        if (item != null) items.add(item);
      }
    }
    _markSavedFromShelf(items, shelf, savedIds);
    setState(() {
      _loading = false;
      _items = items;
      _updatedAt = snapshot?.updatedAt;
      _apiRequests = snapshot?.apiRequests ?? 0;
      _costCny = snapshot?.costCny ?? 0;
      _notes = <String>[];
      _savedIds = savedIds;
      _hiddenIds = hiddenIds;
      _removed.clear();
      _mine = _mineFrom(shelf, savedIds);
      _mineLoading = false;
      _visibleCount = 10;
      _mineVisible = 20;
    });
  }

  /// 重读「我的」:保存关系 + 材料库(阅读进度会变,读完回来要刷)。
  Future<void> _loadMine({bool showLoading = true}) async {
    final channelId = _channel.id;
    if (showLoading) setState(() => _mineLoading = true);
    Set<String> savedIds = <String>{};
    Set<String> hiddenIds = <String>{};
    List<ShelfItem> shelf = const <ShelfItem>[];
    try {
      savedIds = await MaterialChannelStore.savedMaterialIds(channelId);
      hiddenIds = await MaterialChannelStore.hiddenMaterialIds(channelId);
      shelf = await MaterialLibrary.shelf(limit: 300);
    } catch (e) {
      debugPrint('ReadFlow 频道页读取我的材料失败: $e');
    }
    if (!mounted || channelId != _channel.id) return;
    setState(() {
      _savedIds = savedIds;
      _hiddenIds = hiddenIds;
      _mine = _mineFrom(shelf, savedIds);
      _mineLoading = false;
    });
  }

  /// 我的 Tab 数据 = 「保存到本频道」的材料 ∪ 「旧逻辑匹配到本频道」的材料。
  ///
  /// 旧逻辑:
  /// - 按形式:**严格按 kind 过滤**(taxonomy 子分类的 kinds),这是"按形式"的语义;
  /// - 按题材/按场景:标题/中文标题/分组名里含子分类关键词(轻量初筛,与旧
  ///   [MaterialBrowseScreen] 的口径一致)。
  ///
  /// 边界(刻意):**没选任何子分类时不做旧逻辑匹配** —— 否则"整个方向"频道
  /// 会把材料库 300 条历史全倒进「我的」,正是方案 2 要消灭的"无限竖列"。
  /// 这时只显示用户明确"保存到我的"的材料。
  List<ShelfItem> _mineFrom(List<ShelfItem> shelf, Set<String> savedIds) {
    if (shelf.isEmpty) return const <ShelfItem>[];
    final out = <ShelfItem>[];
    for (final item in shelf) {
      if (_removed.contains(item.id)) continue;
      if (_hiddenIds.contains('${item.id}')) continue;
      if (savedIds.contains('${item.id}') || _matchesLegacy(item)) {
        out.add(item);
      }
    }
    // shelf() 本身按最近更新倒序;这里保持原顺序 = 「按最近更新排序」。
    return out;
  }

  bool _matchesLegacy(ShelfItem item) {
    if (_selected.isEmpty) return false;
    final ids = _selected.toList()..sort();
    if (widget.direction == MaterialDirection.form) {
      final kinds = <String>{};
      for (final id in ids) {
        final sub = MaterialTaxonomy.subtopicOf(MaterialDirection.form, id);
        if (sub != null) kinds.addAll(sub.kinds);
      }
      if (kinds.isEmpty) return false;
      return kinds.contains(item.kind);
    }
    final keys = <String>[];
    for (final id in ids) {
      final sub = MaterialTaxonomy.subtopicOf(widget.direction, id);
      if (sub == null) continue;
      keys.add(sub.label);
      keys.addAll(sub.queries);
    }
    if (keys.isEmpty) return false;
    final haystack = '${item.title} ${item.titleCn} ${item.group ?? ''}'
        .toLowerCase();
    return keys.any((key) {
      final needle = key.trim().toLowerCase();
      return needle.isNotEmpty && haystack.contains(needle);
    });
  }

  /// 把快照条目和材料库里的材料对上号:
  /// - 按 url/标题都能对上(同一篇材料读过后可能 rename 中文标题);
  /// - **不只匹配"已保存"的**:只要材料库里有这篇(哪怕只是读过),就把 materialId
  ///   关联上,避免再点「开始读」时重复抓正文/重复计费(质检 P1-4)。
  void _markSavedFromShelf(
    List<_ChannelItem> items,
    List<ShelfItem> shelf,
    Set<String> savedIds,
  ) {
    if (items.isEmpty || shelf.isEmpty) return;
    final byUrl = <String, ShelfItem>{};
    final byTitle = <String, ShelfItem>{};
    for (final item in shelf) {
      final urlKey = normalizedUrlKey(item.url);
      if (urlKey.isNotEmpty) byUrl[urlKey] = item;
      final titleKey = item.title.trim().toLowerCase();
      if (titleKey.isNotEmpty) byTitle[titleKey] = item;
    }
    for (final item in items) {
      final found = byUrl[normalizedUrlKey(item.url)] ??
          byTitle[item.title.trim().toLowerCase()];
      if (found == null) continue;
      item.materialId = found.id;
      item.saved = savedIds.contains('${found.id}');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 发现:运行检索 / 继续找更多
  // ═══════════════════════════════════════════════════════════════════

  void _event(String label, {SearchStage stage = SearchStage.searching}) {
    if (!mounted) return;
    setState(() => _events.add(SearchEvent(stage: stage, label: label)));
  }

  /// 跑一轮发现。
  ///
  /// [more] = true 是「继续找更多」:先让模型看**真实已见候选**给出新检索词;
  /// false 是「开始/刷新」:沿用频道检索词。两种情况都带 `excludeUrls`
  /// (已见 url),所以不会把上一页的卡片重复塞回来。
  Future<void> _startDiscovery({bool more = false}) async {
    if (_running) return;
    if (more && _items.isEmpty) return;
    final vocab = context.read<VocabProvider>().vocabularies;
    _refreshPrefsAndNeed();
    final channel = _channel;
    final hadItems = _items.isNotEmpty;
    setState(() {
      _running = true;
      _showProcess = true;
      _error = null;
      _events.clear();
      if (!hadItems) {
        // 首轮:清掉旧状态,过程卡片从头开始
        _updatedAt = null;
        _apiRequests = 0;
        _costCny = 0;
        _notes = <String>[];
        _visibleCount = 10;
      }
    });
    try {
      var extraQueries = const <String>[];
      if (more) {
        _event('让 AI 根据已找到的结果想新的检索词…');
        try {
          extraQueries = await MaterialDiscovery().planNextQueries(
            userQuery: channel.needText,
            seenCandidates: <Map<String, Object?>>[
              for (final item in _items) _snapshotMapOf(item),
            ],
            prefsHint: _prefs.promptHint,
          );
        } catch (e) {
          debugPrint('ReadFlow 频道页换检索词失败: $e');
          extraQueries = const <String>[];
        }
        if (!mounted) return;
        if (extraQueries.isEmpty) {
          setState(() {
            _running = false;
            _showProcess = false;
          });
          _snack('没想出新的检索词。可以换个子分类,或点「刷新」重试。');
          return;
        }
        _event('新检索词:${extraQueries.join(' / ')}');
      }

      final run = await MaterialDiscovery().discover(
        queries: channel.queries,
        extraQueries: extraQueries,
        excludeUrls: <String>{for (final item in _items) item.url},
        prefs: _prefs,
        model: LearnerModelStore.load(),
        vocab: vocab,
        maxFetch: 8,
        userQuery: channel.needText,
        onEvent: _event,
      );
      if (!mounted) return;
      if (channel.id != _channel.id) {
        // 检索期间用户改了子分类:这批结果属于旧频道,丢弃,避免串频道
        setState(() {
          _running = false;
          _showProcess = false;
        });
        return;
      }

      final fresh = <_ChannelItem>[];
      for (final candidate in run.items) {
        fresh.add(
          _ChannelItem.fromCandidate(
            candidate,
            seq: _items.length + fresh.length,
          ),
        );
      }
      final merged = _mergeItems(_items, fresh);
      final added = merged.length - _items.length;
      final runQueries = <String>[...channel.queries, ...extraQueries];
      _event(
        run.items.isEmpty
            ? '这次没有抓到可读正文'
            : '找到 ${run.items.length} 篇可读材料'
                  '${run.estimatedCostCny > 0 ? ' · 官方搜索约 ${run.estimatedCostCny.toStringAsFixed(3)} 元' : ''}',
        stage: run.items.isEmpty ? SearchStage.sourceEmpty : SearchStage.done,
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        // 跑完自动收起过程卡(用户 11/05 反馈:过程一直铺着,结果被顶远)
        _showProcess = false;
        _items = merged;
        _updatedAt = DateTime.now();
        // 成本口径:本轮 run 的花费 + 之前累计(与 store 的 append 累加一致)
        _apiRequests = _apiRequests + run.searchApiRequests;
        _costCny = _costCny + run.estimatedCostCny;
        _notes = List<String>.of(run.notes);
        _ranThisSession = true;
        if (hadItems) {
          // 追加后把新批次顶进可见范围,否则用户还要再点一次「显示更多」
          _visibleCount += 10;
        }
      });
      if (hadItems && added <= 0) {
        _snack('这次没有新增结果,可以换个子分类或稍后再试。');
      }

      // 落快照:正文/analysis 不进快照(契约);成本/检索词按**本轮**传,
      // append 时由 store 侧累加,不能把累计值再传进去(会重复计费)。
      try {
        await MaterialChannelStore.saveRun(
          channel.id,
          items: <Map<String, Object?>>[
            for (final item in fresh) _snapshotMapOf(item),
          ],
          apiRequests: run.searchApiRequests,
          costCny: run.estimatedCostCny,
          queriesUsed: runQueries,
          append: hadItems,
        );
      } catch (e) {
        debugPrint('ReadFlow 频道页保存快照失败: $e');
        if (mounted) {
          _snack('结果已显示,但保存频道快照失败(下次进入可能看不到这批结果)。');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _showProcess = false;
        _error = '$e';
      });
    }
  }

  /// 合并新旧结果:按 URL 归一去重(旧条目优先保留,新条目只追加没见过的)。
  List<_ChannelItem> _mergeItems(
    List<_ChannelItem> oldItems,
    List<_ChannelItem> freshItems,
  ) {
    final out = <_ChannelItem>[...oldItems];
    final seen = <String>{
      for (final item in oldItems) normalizedUrlKey(item.url),
    };
    for (final item in freshItems) {
      final key = normalizedUrlKey(item.url);
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(item);
    }
    return out;
  }

  /// 快照 map(契约 9 键;正文/难度/相关性一律不存)。
  Map<String, Object?> _snapshotMapOf(_ChannelItem item) => <String, Object?>{
    'title': item.title,
    'url': item.url,
    'sourceLabel': item.sourceLabel,
    'kind': item.kind,
    'snippet': item.snippet,
    'imageUrl': item.imageUrl,
    'authority': item.authority,
    'date': item.date?.toIso8601String(),
    'fromSearchApi': item.fromSearchApi,
  };

  // ═══════════════════════════════════════════════════════════════════
  // 发现:补抓正文 / 入库 / 保存
  // ═══════════════════════════════════════════════════════════════════

  /// 快照不存正文:用户点「开始读 / 保存到我的」时按需补抓一次。
  ///
  /// 顺序与发现流水线一致:① 普通 HTTP 抓取(公开源、静态页);② 官方 Fetch
  /// (教材/真题多在中文站,普通抓取常被反爬挡住)。② 只有配置了官方 Key 才
  /// 可用、且按成功请求计费,所以只在 ① 失败/正文太短时才走。
  Future<String?> _fetchContentFor(_ChannelItem item) async {
    try {
      final doc = await MaterialSourceService.instance.fetchAnyUrl(
        item.url,
        titleHint: item.title,
      );
      final text = doc.chunks.map((chunk) => chunk.text).join('\n\n').trim();
      if (text.length >= 200) return text;
    } catch (e) {
      debugPrint('ReadFlow 频道页普通抓取失败(${item.url}): $e');
    }
    try {
      final client = DeepSeekSearchClient();
      if (!client.available) return null;
      final page = await client.fetch(item.url);
      if (page == null) return null;
      final text = plainTextFromMarkdown(page.content).trim();
      return text.length >= 200 ? text : null;
    } catch (e) {
      debugPrint('ReadFlow 频道页官方抓取失败(${item.url}): $e');
      return null;
    }
  }

  Future<bool> _ensureContent(_ChannelItem item) async {
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

  /// 入库(正文 → 材料库),返回 materialId。**调用前必须确认 mounted**。
  Future<int> _ingestToLibrary(_ChannelItem item) async {
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
    );
    return ingested.materialId;
  }

  /// 「开始读」:若本地已有这篇(读过/保存过)→ 直接打开,不重复抓正文;
  /// 否则补抓正文 → 入库 → 进阅读器。
  Future<void> _startRead(_ChannelItem item) async {
    if (_busyUrl != null) return;
    setState(() => _busyUrl = item.url);
    try {
      var materialId = item.materialId;
      if (materialId == null) {
        final ok = await _ensureContent(item);
        if (!ok) {
          item.contentUnavailable = true;
          if (!mounted) return;
          setState(() {});
          _snack('这篇抓不到正文(常见于 PDF/反爬站点),可以点「打开原文/打开 PDF」直接看。');
          return;
        }
        if (!mounted) return;
        materialId = await _ingestToLibrary(item);
        item.materialId = materialId;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialReaderScreen(materialId: materialId!),
        ),
      );
      if (!mounted) return;
      // 读完回来刷新「我的」(进度变了,旧逻辑匹配也会把这篇算进来)
      await _loadMine(showLoading: false);
    } catch (e) {
      if (mounted) _snack('打开失败:$e');
    } finally {
      if (mounted) setState(() => _busyUrl = null);
    }
  }

  /// 「保存到我的」:本地已有这篇 → 只记频道保存关系;否则补抓正文 → 入库 → 记录。
  Future<void> _saveToMine(_ChannelItem item) async {
    if (_busyUrl != null || item.saved) return;
    final channelId = _channel.id;
    setState(() => _busyUrl = item.url);
    try {
      var materialId = item.materialId;
      if (materialId == null) {
        final ok = await _ensureContent(item);
        if (!ok) {
          item.contentUnavailable = true;
          if (!mounted) return;
          setState(() {});
          _snack('这篇抓不到正文,暂时不能保存;可以点「打开原文」直接看。');
          return;
        }
        if (!mounted) return;
        materialId = await _ingestToLibrary(item);
        item.materialId = materialId;
      }
      await MaterialChannelStore.addSavedMaterial(channelId, materialId);
      // 之前从本频道移除过 → 重新保存时把持久移除记录也撤掉
      await MaterialChannelStore.removeHiddenMaterial(channelId, materialId);
      await _loadMine(showLoading: false);
      if (!mounted) return;
      setState(() {
        item.saved = true;
        _savedIds.add('$materialId');
        _hiddenIds.remove('$materialId');
        // 之前从频道移除过同一篇时,重新保存要把它从"本次会话已移除"里放出来
        _removed.remove(materialId);
      });
      _snack('已保存到「我的」,可以在那里离线读、改中文名、删除。');
    } catch (e) {
      if (mounted) _snack('保存失败:$e');
    } finally {
      if (mounted) setState(() => _busyUrl = null);
    }
  }

  /// 打开原文 / PDF(系统浏览器兜底:抓不到正文的结果也必须能点动)
  Future<void> _openOriginal(_ChannelItem item) async {
    if (item.url.trim().isEmpty) return;
    final ok = await launchExternalUrl(item.url);
    if (!ok && mounted) {
      _snack('这个链接打不开,可以换一篇或稍后再试。');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 我的:打开 / 编辑 / 移除 / 删除
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _openMine(ShelfItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialReaderScreen(materialId: item.id),
      ),
    );
    if (mounted) await _loadMine(showLoading: false);
  }

  /// 长按 / 点「⋯」都走同一个管理面板(移动端比弹菜单更好点)。
  Future<void> _showMineActions(ShelfItem item) async {
    final skin = V4Skin.of(context);
    final title = item.titleCn.isNotEmpty ? item.titleCn : item.title;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: skin.surface,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        Widget entry({
          required String value,
          required IconData icon,
          required String label,
          Color? color,
        }) {
          return ListTile(
            leading: Icon(icon, size: 20, color: color ?? cs.onSurfaceVariant),
            title: Text(
              label,
              style: AppFont.bodyStyle.copyWith(color: color ?? cs.onSurface),
            ),
            onTap: () => Navigator.pop(ctx, value),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: Gap.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.subheadStyle.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                entry(
                  value: 'open',
                  icon: Icons.menu_book_rounded,
                  label: '打开阅读',
                ),
                entry(
                  value: 'rename',
                  icon: Icons.drive_file_rename_outline_rounded,
                  label: '编辑中文标题',
                ),
                // 「从频道移除」对所有「我的」条目都可用:只影响本频道显示,
                // 不删材料本体;且会持久记录(重进频道也不会再冒出来)。
                entry(
                  value: 'remove',
                  icon: Icons.bookmark_remove_outlined,
                  label: '从本频道移除(材料保留在材料库)',
                ),
                entry(
                  value: 'delete',
                  icon: Icons.delete_outline_rounded,
                  label: '删除材料(不可恢复)',
                  color: cs.error,
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    if (action == 'open') {
      await _openMine(item);
    } else if (action == 'rename') {
      await _renameMine(item);
    } else if (action == 'remove') {
      await _removeFromChannel(item);
    } else if (action == 'delete') {
      await _deleteMine(item);
    }
  }

  Future<void> _renameMine(ShelfItem item) async {
    final controller = TextEditingController(
      text: item.titleCn.isNotEmpty ? item.titleCn : item.title,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑中文标题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '给这篇材料起个中文名(方便在列表里认出来)',
            isDense: true,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final text = controller.text.trim();
    controller.dispose();
    if (ok != true || text.isEmpty) return;
    try {
      await DatabaseService.setMaterialTitleCn(item.id, text);
    } catch (e) {
      if (mounted) _snack('改标题失败:$e');
      return;
    }
    if (!mounted) return;
    await _loadMine(showLoading: false);
    _snack('标题已更新');
  }

  /// 从频道移除:**只删"保存关系"+ 记频道级移除表**,材料本体/阅读进度都不动。
  ///
  /// 记录持久移除表后,即使这条材料命中了旧逻辑(按形式 kind / 题材关键词),
  /// 重进频道也不会再出现(质检 P1-5 修)。
  Future<void> _removeFromChannel(ShelfItem item) async {
    final channelId = _channel.id;
    try {
      await MaterialChannelStore.removeSavedMaterial(channelId, item.id);
      await MaterialChannelStore.addHiddenMaterial(channelId, item.id);
    } catch (e) {
      if (mounted) _snack('移除失败:$e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _savedIds.remove('${item.id}');
      _hiddenIds.add('${item.id}');
      _removed.add(item.id);
      _mine = _mine.where((entry) => entry.id != item.id).toList();
      // 发现 Tab 里同一篇的「已在我的」状态也要跟着回退,否则两个 Tab 说法不一致
      _markUnsavedInDiscovery(item.id);
    });
    showFeedbackSnack(context, '已从本频道移除(材料仍在材料库,重进也不会再出现)');
  }

  Future<void> _deleteMine(ShelfItem item) async {
    final title = item.titleCn.isNotEmpty ? item.titleCn : item.title;
    final ok = await confirmDestructive(
      context,
      title: '删除这份材料?',
      message: '「$title」的正文、阅读进度和译文会一起删除,不能恢复。',
    );
    if (!ok || !mounted) return;
    try {
      await DatabaseService.deleteMaterial(item.id);
      // 删材料后顺手清掉保存关系,避免「我的」里留下指向已删材料的脏 id
      await MaterialChannelStore.removeSavedMaterial(_channel.id, item.id);
    } catch (e) {
      if (mounted) _snack('删除失败:$e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _savedIds.remove('${item.id}');
      _removed.add(item.id);
      _mine = _mine.where((entry) => entry.id != item.id).toList();
      _markUnsavedInDiscovery(item.id);
    });
    showFeedbackSnack(context, '已删除');
  }

  /// 材料被移出频道/删除后,把发现 Tab 里对应卡片的"已在我的"状态回退。
  void _markUnsavedInDiscovery(int materialId) {
    for (final discoveryItem in _items) {
      if (discoveryItem.materialId == materialId) discoveryItem.saved = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 子分类 / 需求设置
  // ═══════════════════════════════════════════════════════════════════

  void _toggleSubtopic(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
    unawaited(_reloadAll());
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(() => _selected.clear());
    unawaited(_reloadAll());
  }

  /// 按需求方向:去「按需求」页改需求(难度/形式/目标),回来重读。
  Future<void> _openNeedSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const MaterialBrowseScreen(direction: MaterialDirection.need),
      ),
    );
    if (!mounted) return;
    _refreshPrefsAndNeed();
    await _reloadAll();
  }

  // ═══════════════════════════════════════════════════════════════════
  // 头部刷新
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onHeaderRefresh() async {
    if (_running) return;
    if (_tab.index == 1) {
      await _loadMine();
    } else {
      await _startDiscovery();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // 构建
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: _shortTitle,
        actions: <Widget>[
          V4IconAction(
            icon: Icons.refresh_rounded,
            tooltip: _tab.index == 0 ? '再找一批(排除已见结果)' : '刷新频道材料',
            onTap: _onHeaderRefresh,
          ),
          const SizedBox(width: Gap.xs),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: skin.ink,
          unselectedLabelColor: skin.inkSoft,
          indicatorColor: skin.accent,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          labelStyle: AppFont.subheadStyle.copyWith(
            fontWeight: FontWeight.w800,
          ),
          unselectedLabelStyle: AppFont.subheadStyle,
          tabs: const <Widget>[
            Tab(text: '发现'),
            Tab(text: '我的'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: Text('正在打开频道…', style: TextStyle(fontSize: 12)))
          : Column(
              children: <Widget>[
                _channelHeaderBar(skin),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: <Widget>[_discoverTab(skin), _mineTab(skin)],
                  ),
                ),
              ],
            ),
    );
  }

  // ── 头部:子分类 chips / 需求摘要 ─────────────────────────────────

  Widget _channelHeaderBar(V4Skin skin) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, Gap.xs),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: skin.hairline)),
      ),
      child: widget.direction == MaterialDirection.need
          ? _needSummaryBar(skin)
          : _subtopicBar(skin),
    );
  }

  Widget _subtopicBar(V4Skin skin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          _running ? '正在检索中,先不要改子分类…' : '${_def.subtitle} · 可多选(不选 = 整个方向)',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppFont.tagStyle.copyWith(color: skin.inkFaint),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: Gap.xs,
          runSpacing: 6,
          children: <Widget>[
            _scopeChip(
              skin,
              label: '全部',
              selected: _selected.isEmpty,
              onTap: _running ? null : _clearSelection,
            ),
            for (final sub in _def.subtopics)
              _scopeChip(
                skin,
                label: sub.label,
                selected: _selected.contains(sub.id),
                onTap: _running ? null : () => _toggleSubtopic(sub.id),
              ),
          ],
        ),
      ],
    );
  }

  /// 按需求方向:只读摘要 + 去设置入口(需求是全局事实源,不在这里现场编辑,
  /// 避免"两处都能改、说法不一致")。
  Widget _needSummaryBar(V4Skin skin) {
    final summary = _need.isEmpty
        ? '还没设置需求:默认按「普遍适合中级学习者」去找'
        : '我的需求:${_need.summary}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.tune_rounded, size: 16, color: skin.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppFont.tagStyle.copyWith(
                  color: skin.inkSoft,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _running ? null : _openNeedSettings,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const Icon(Icons.settings_outlined, size: 15),
            label: const Text('去设置需求'),
          ),
        ),
      ],
    );
  }

  Widget _scopeChip(
    V4Skin skin, {
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.pillRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? skin.accent.withValues(alpha: 0.12)
                : skin.surface,
            borderRadius: Radii.pillRadius,
            border: Border.all(
              color: selected
                  ? skin.accent.withValues(alpha: 0.5)
                  : skin.hairline,
            ),
          ),
          child: Text(
            label,
            style: AppFont.metaStyle.copyWith(
              color: selected ? skin.accent : skin.inkSoft,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  // ── 发现 Tab ────────────────────────────────────────────────────

  Widget _discoverTab(V4Skin skin) {
    return RefreshIndicator(
      // 下拉刷新只重读本地快照,不花检索/搜索钱;要找新内容用「刷新/继续找更多」。
      // 检索进行中不重读:否则会把过程事件/新结果冲掉(用户会觉得"点了一下啥也没了")。
      onRefresh: () async {
        if (_running) return;
        await _reloadAll(showPageLoading: false);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xl),
        children: _discoverChildren(skin),
      ),
    );
  }

  List<Widget> _discoverChildren(V4Skin skin) {
    final children = <Widget>[];
    if (_running || _events.isNotEmpty) {
      children.add(_processCard(skin));
      children.add(const SizedBox(height: Gap.sm));
    }
    if (_items.isNotEmpty || _updatedAt != null) {
      children.add(_resultMetaRow(skin));
      children.add(const SizedBox(height: Gap.sm));
    }
    if (_error != null) {
      children.add(
        AppErrorCard(
          message: _error!,
          onRetry: _running ? null : () => _startDiscovery(),
        ),
      );
      children.add(const SizedBox(height: Gap.sm));
    }
    if (_items.isNotEmpty) {
      final result = _buildResultWidgets(skin);
      children.addAll(result.widgets);
      if (result.hidden > 0) {
        children.add(const SizedBox(height: Gap.xs));
        children.add(
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _visibleCount += 10),
              icon: const Icon(Icons.expand_more_rounded, size: 18),
              label: Text('显示更多(还有 ${result.hidden} 条)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
              ),
            ),
          ),
        );
      }
      children.add(const SizedBox(height: Gap.sm));
      children.add(
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: _running ? null : () => _startDiscovery(more: true),
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore_rounded, size: 18),
            label: Text(_running ? '正在找更多…' : '继续找更多'),
          ),
        ),
      );
    } else if (!_running && _error == null) {
      // 上次跑过但 0 条:也要让用户看到"上次结果 + 花费"(质检 P1-2),
      // 不能又显示"从没找过"的介绍卡。
      if (_items.isEmpty && _updatedAt != null) {
        children.add(_emptyAfterRun());
      } else {
        children.add(_ranThisSession ? _emptyAfterRun() : _introCard(skin));
      }
    }
    children.add(const SizedBox(height: Gap.xl));
    return children;
  }

  /// 搜索过程(默认折叠):跑完只留一行「搜索过程 · N 步」,点开才展开时间线。
  Widget _processCard(V4Skin skin) {
    return AppCard(
      variant: AppCardVariant.compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _showProcess = !_showProcess),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Icon(
                    _running ? Icons.autorenew_rounded : Icons.timeline_rounded,
                    size: 17,
                    color: skin.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _running ? '正在找材料(点开看过程)' : '搜索过程 · ${_events.length} 步',
                      style: AppFont.subheadStyle.copyWith(
                        color: skin.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _showProcess ? '收起' : '展开',
                    style: AppFont.tagStyle.copyWith(color: skin.accent),
                  ),
                  Icon(
                    _showProcess
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: skin.inkFaint,
                  ),
                ],
              ),
            ),
          ),
          if (_showProcess) ...<Widget>[
            const SizedBox(height: 6),
            SearchTimeline(events: _events, loading: _running),
          ],
        ],
      ),
    );
  }

  /// 上次/本次结果摘要:更新时间 + 花费 + 源说明(原样展示,不隐藏失败原因)。
  Widget _resultMetaRow(V4Skin skin) {
    final buffer = <String>[_ranThisSession ? '本次结果' : '上次结果'];
    final updatedAt = _updatedAt;
    if (updatedAt != null) buffer.add(_fmtDateTime(updatedAt));
    buffer.add('${_items.length} 篇');
    if (_apiRequests > 0) {
      buffer.add('花费 ${_costCny.toStringAsFixed(3)} 元');
    }
    return AppCard(
      variant: AppCardVariant.compact,
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.history_rounded, size: 15, color: skin.inkFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  buffer.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.metaStyle.copyWith(color: skin.inkSoft),
                ),
              ),
              // 刷新统一放 AppBar 右侧,这一行只承载"上次结果/时间/花费",
              // 不再塞按钮 —— 小屏上会被挤成一行省略号(真机 11/05 反馈过紧)
            ],
          ),
          if (_notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 21, right: 8, bottom: 4),
              child: Text(
                _notes.take(2).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppFont.tagStyle.copyWith(
                  color: skin.inkFaint,
                  height: 1.4,
                ),
              ),
            ),
          // 快照只存链接,正文要按需补抓:这句话只在顶部说一次,
          // 不再每张卡重复(真机上满屏重复提示很吵)
          if (_items.isNotEmpty &&
              _items.any((e) => e.content == null && !e.contentUnavailable))
            Padding(
              padding: const EdgeInsets.only(left: 21, right: 8, bottom: 4),
              child: Text(
                '这些是上次的结果(只存链接):点「开始读/保存到我的」会补抓正文。',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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

  /// 还没有任何结果时的介绍卡(主按钮是"开始找真实材料")。
  Widget _introCard(V4Skin skin) {
    final channel = _channel;
    // 标题里已经写了"在这个频道",kicker 只补充当前频道范围,避免和 AppBar 标题重复
    final scopeLabel = channel.subtopicIds.isEmpty
        ? '整个方向'
        : '已选 ${channel.subtopicIds.length} 个子分类';
    final intro = widget.direction == MaterialDirection.need
        ? '按你设置的需求去公开源 + DeepSeek 官方搜索里找真实材料;'
              '每条结果都有真实链接,抓到正文的可以直接读、保存到「我的」。'
        : '先在你选的子分类里检索真实材料(公开源 + DeepSeek 官方搜索),'
              '抓到正文后本地算难度;结果按材料类型分组,每页最多 10 条。';
    return AppCard(
      variant: AppCardVariant.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: skin.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.travel_explore_rounded,
                  size: 20,
                  color: skin.accent,
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      scopeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.tagStyle.copyWith(color: skin.accent),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '在这个频道里找真实材料',
                      style: AppFont.headingStyle.copyWith(
                        color: skin.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            intro,
            style: AppFont.tagStyle.copyWith(
              color: skin.inkSoft,
              height: 1.5,
              fontSize: 12,
            ),
          ),
          if (channel.queries.isNotEmpty) ...<Widget>[
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.xs,
              runSpacing: 4,
              children: <Widget>[
                for (final query in channel.queries.take(3)) AppTag(query),
              ],
            ),
          ],
          const SizedBox(height: Gap.md),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _running ? null : () => _startDiscovery(),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('开始找真实材料'),
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text(
            '每次最多抓 8 篇正文并本地算难度;官方搜索按成功请求计费(这次大约几厘到几分钱)。',
            style: AppFont.tagStyle.copyWith(color: skin.inkFaint, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// 找过但没找到可读正文:明确告诉用户下一步(换检索词 / 换子分类)。
  Widget _emptyAfterRun() {
    final hint = _notes.isEmpty
        ? '换个检索方向,或换一个子分类再找。'
        : '${_notes.take(3).join('\n')}\n\n换个检索方向,或换一个子分类再找。';
    return AppEmptyState(
      icon: Icons.travel_explore_outlined,
      title: '这次没找到能读的正文',
      hint: hint,
      action: FilledButton(
        onPressed: _running ? null : () => _startDiscovery(),
        child: const Text('再找一次'),
      ),
    );
  }

  /// 分组 + 本地分页:每页最多 [_visibleCount] 条;组名带"可见/总数"。
  ({List<Widget> widgets, int hidden}) _buildResultWidgets(V4Skin skin) {
    final groups = _groupedResults();
    final widgets = <Widget>[];
    var budget = _visibleCount;
    var shown = 0;
    for (final group in groups) {
      if (budget <= 0) break;
      final take = group.items.length <= budget ? group.items.length : budget;
      if (take <= 0) continue;
      budget -= take;
      widgets.add(_groupHeader(skin, group.label, take, group.items.length));
      for (var i = 0; i < take; i++) {
        widgets.add(
          AppStagger(index: shown++, child: _resultCard(group.items[i])),
        );
      }
    }
    return (widgets: widgets, hidden: _items.length - shown);
  }

  Widget _groupHeader(V4Skin skin, String label, int visible, int total) {
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
            visible < total ? '$visible / $total 篇' : '$total 篇',
            style: AppFont.tagStyle.copyWith(color: skin.inkFaint),
          ),
        ],
      ),
    );
  }

  /// 结果分组:按材料类型(教材/应试真题/书籍/论文/外刊新闻/文章/其他),
  /// 组内先按**真实难度**(覆盖率高的在前)再按权威度排(快照无难度,按权威度)。
  List<_ResultGroup> _groupedResults() {
    final buckets = <String, List<_ChannelItem>>{};
    for (final item in _items) {
      final key = _groupKeyOf(item.kind);
      final bucket = buckets[key];
      if (bucket == null) {
        buckets[key] = <_ChannelItem>[item];
      } else {
        bucket.add(item);
      }
    }
    final out = <_ResultGroup>[];
    for (final key in _groupOrder) {
      final items = buckets.remove(key);
      if (items == null || items.isEmpty) continue;
      items.sort(_compareInGroup);
      out.add(_ResultGroup(label: _groupLabels[key] ?? '其他', items: items));
    }
    // 防御:未知类型已在 _groupKeyOf 归入 other,这里理论上不会命中
    if (buckets.isNotEmpty) {
      final rest = <_ChannelItem>[];
      for (final items in buckets.values) {
        rest.addAll(items);
      }
      rest.sort(_compareInGroup);
      out.add(_ResultGroup(label: '其他', items: rest));
    }
    return out;
  }

  int _compareInGroup(_ChannelItem a, _ChannelItem b) {
    final aCoverage = a.analysis?.knownTokenRatio;
    final bCoverage = b.analysis?.knownTokenRatio;
    if ((aCoverage == null) != (bCoverage == null)) {
      return aCoverage == null ? 1 : -1;
    }
    if (aCoverage != null && bCoverage != null) {
      final byCoverage = bCoverage.compareTo(aCoverage);
      if (byCoverage != 0) return byCoverage;
    }
    final byAuthority = b.authority.compareTo(a.authority);
    if (byAuthority != 0) return byAuthority;
    return a.seq.compareTo(b.seq);
  }

  /// 结果卡:标题(2 行) + 来源/类型/难度胶囊 + 摘要(2 行) + 按钮行。
  Widget _resultCard(_ChannelItem item) {
    final skin = V4Skin.of(context);
    final isPdf = MaterialDiscovery.looksLikePdfUrl(item.url);
    final busy = _busyUrl == item.url;
    final unavailable = item.contentUnavailable;
    final canRead = !unavailable && !busy;
    final analysis = item.analysis;

    final tags = <Widget>[
      AppTag(item.sourceLabel.trim().isEmpty ? '未知来源' : item.sourceLabel),
      AppTag(_kindChipLabel(item.kind)),
      if (analysis != null)
        AppTag(
          '覆盖率 ${(analysis.knownTokenRatio * 100).round()}%',
          tone: AppTagTone.primary,
        ),
      if (analysis != null && analysis.cefr.isNotEmpty) AppTag(analysis.cefr),
      if (item.fromSearchApi && item.authority >= 0)
        AppTag('权威度 ${item.authority}/4'),
      if (item.date != null) AppTag(_fmtDay(item.date!)),
      if (item.saved) const AppTag('已在我的', tone: AppTagTone.success),
    ];

    return AppCard(
      variant: AppCardVariant.compact,
      padding: const EdgeInsets.all(Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppFont.subheadStyle.copyWith(
              color: skin.ink,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: tags),
          if (item.snippet.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              item.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppFont.tagStyle.copyWith(
                color: skin.inkSoft,
                height: 1.4,
                fontSize: 11.5,
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
                onPressed: canRead ? () => _startRead(item) : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('开始读'),
              ),
              OutlinedButton(
                onPressed: canRead && !item.saved
                    ? () => _saveToMine(item)
                    : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(item.saved ? '已在我的' : '保存到我的'),
              ),
              if (item.url.trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _openOriginal(item),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    isPdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.open_in_new_rounded,
                    size: 14,
                  ),
                  label: Text(isPdf ? '打开 PDF' : '打开原文'),
                ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (unavailable)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '这篇抓不到正文(常见于 PDF/反爬站点),可以点「打开原文/打开 PDF」直接看。',
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

  // ── 我的 Tab ────────────────────────────────────────────────────

  Widget _mineTab(V4Skin skin) {
    return RefreshIndicator(
      onRefresh: () => _loadMine(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xl),
        children: _mineChildren(skin),
      ),
    );
  }

  List<Widget> _mineChildren(V4Skin skin) {
    if (_mineLoading) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(vertical: Gap.xl),
          child: Center(
            child: Text('正在读取频道材料…', style: TextStyle(fontSize: 12)),
          ),
        ),
      ];
    }
    if (_mine.isEmpty) {
      return <Widget>[
        AppEmptyState(
          icon: Icons.bookmark_border_rounded,
          title: '这个频道里还没有材料',
          hint:
              '在「发现」里找到合适的,点「保存到我的」;'
              '读过的、并且属于这个频道子分类的材料也会自动出现在这里。',
          action: FilledButton.icon(
            onPressed: () => _tab.animateTo(0),
            icon: const Icon(Icons.travel_explore_rounded, size: 16),
            label: const Text('去发现里找'),
          ),
        ),
      ];
    }
    final visible = _mine.take(_mineVisible).toList();
    return <Widget>[
      Row(
        children: <Widget>[
          Icon(Icons.bookmarks_outlined, size: 16, color: skin.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '频道材料 ${_mine.length} 篇',
              style: AppFont.subheadStyle.copyWith(
                color: skin.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _tab.animateTo(0),
            child: const Text('去发现里找'),
          ),
        ],
      ),
      Text(
        '按最近更新排序 · 长按卡片或点「⋯」可改中文名 / 从频道移除 / 删除',
        style: AppFont.tagStyle.copyWith(color: skin.inkFaint, height: 1.4),
      ),
      const SizedBox(height: Gap.sm),
      for (var i = 0; i < visible.length; i++) _mineCard(visible[i]),
      if (_mine.length > visible.length) ...<Widget>[
        const SizedBox(height: Gap.xs),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _mineVisible += 20),
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            label: Text('显示更多(还有 ${_mine.length - visible.length} 篇)'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
            ),
          ),
        ),
      ],
    ];
  }

  Widget _mineCard(ShelfItem item) {
    final skin = V4Skin.of(context);
    final saved = _savedIds.contains('${item.id}');
    final subtitleParts = <String>[
      if (item.wordCount > 0) '${item.wordCount} 词',
      if (item.estMinutes > 0) '约 ${item.estMinutes} 分钟',
      if (item.cefr.isNotEmpty) item.cefr,
      item.progressLabel,
    ];
    return GestureDetector(
      onLongPress: () => _showMineActions(item),
      child: AppWideCard(
        title: item.titleCn.isNotEmpty ? item.titleCn : item.title,
        subtitle: subtitleParts.join(' · '),
        seed: item.title,
        kind: item.kind,
        imageUrl: item.coverUrl,
        tags: <Widget>[
          if (saved) const AppTag('已保存', tone: AppTagTone.primary),
          AppTag(MaterialLibrary.kindLabel(item.kind)),
          if (item.origin == 'import') const AppTag('导入'),
        ],
        trailing: IconButton(
          tooltip: '管理',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.more_horiz_rounded, size: 18, color: skin.inkFaint),
          onPressed: () => _showMineActions(item),
        ),
        onTap: () => _openMine(item),
      ),
    );
  }

  // ── 小工具 ──────────────────────────────────────────────────────

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _fmtDateTime(DateTime time) =>
      '${_two(time.month)}-${_two(time.day)} ${_two(time.hour)}:${_two(time.minute)}';

  static String _fmtDay(DateTime time) =>
      '${time.year}-${_two(time.month)}-${_two(time.day)}';

  /// 分组顺序:教材 / 应试真题 / 书籍 / 论文 / 外刊新闻 / 文章 / 其他
  static const List<String> _groupOrder = <String>[
    'textbook',
    'exam',
    'book',
    'paper',
    'news',
    'article',
    'other',
  ];

  /// 材料 kind → 分组 key / 组名(与 plan 文档的分组口径一致)。
  static const Map<String, String> _groupLabels = <String, String>{
    'textbook': '教材',
    'exam': '应试真题',
    'book': '书籍',
    'paper': '论文',
    'news': '外刊/新闻',
    'article': '文章',
    'other': '其他',
  };

  static String _groupKeyOf(String kind) {
    final key = kind.trim().toLowerCase();
    return _groupLabels.containsKey(key) ? key : 'other';
  }

  /// 卡片上的类型胶囊:先按分组口径,其他类型再回落材料库的 kind 文案。
  static String _kindChipLabel(String kind) {
    final key = kind.trim().toLowerCase();
    final label = _groupLabels[key];
    if (label != null && key != 'other') return label;
    return MaterialLibrary.kindLabel(kind);
  }
}
