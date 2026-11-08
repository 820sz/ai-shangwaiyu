import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../providers/vocab_provider.dart';
import '../../services/content_quality.dart';
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
import '../../widgets/material_result_list.dart';
import '../../widgets/search_timeline.dart';
import '../../widgets/shelf_cover_grid.dart';
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
/// 2026-11-06 用户真机反馈后的三处修订(仍在本文件,不动 services/):
/// - **结果真分页**:底部页码控件(上一页 / 第 X / Y 页 / 下一页),切页滚回列表顶;
///   类型分组保留(同一页里按组出小标题),「继续找更多」追加后页数增加、
///   并自动跳到"第一条新结果"所在页;
/// - **顶部分类条随滚动滚走**:chips 从固定条挪进滚动内容,下滑时整条滚出去;
///   滚走后在顶部出现一条紧凑的范围条(显示当前频道 + 已选子分类,点「改范围」
///   滚回顶部),而不是永远占着一块高度遮内容;
/// - **封面不再假装是图**:结果卡/「我的」卡只在数据真的有 `imageUrl`/`coverUrl`
///   时画真图,没有就走"标题 + 中文标题 + 来源/难度"的文字版式([TextCover])。
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

  /// **仅渲染 / 质检测试用**:注入"实跑一轮后"的发现结果(快照 9 字段 map)。
  ///
  /// 生产永不传。为什么要这个口子:频道页的质量过滤汇总(`_notes`,如
  /// 「已过滤 N 条质量不合格的候选(公告/报名页 x、非英文 y、弱相关 z)」)
  /// 来自**真实运行结果**,质检验收需要一张"过滤后可见"的截图,不能靠联网碰运气。
  final List<Map<String, Object?>> debugItems;

  /// **仅渲染 / 质检测试用**:配合 [debugItems] 显示的说明行(同上,生产不传)。
  final List<String> debugNotes;

  const MaterialChannelScreen({
    super.key,
    required this.direction,
    this.initialSubtopic,
    this.debugItems = const <Map<String, Object?>>[],
    this.debugNotes = const <String>[],
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
}) =>
    inferMaterialKind(title, url, fallback: fallback);

/// 真题的展示标签:把「四级真题 / 六级真题」并进来源胶囊(判不出就不加假标签)。
///
/// 为什么放来源位而不是新加组件:结果卡由公共件 `MaterialResultCard` 渲染
/// (卡片本体归结果列表,不在本页改),来源胶囊是第一枚可见标签,能直接承载
/// 「CET-4 / CET-6」的分级信息(用户真机:真题分不出四级六级)。
String _examTaggedSourceLabel(String sourceLabel, String title, String url) {
  final tag = MaterialTaxonomy.examLevelTag(title, url: url);
  if (tag.isEmpty) return sourceLabel;
  return sourceLabel.trim().isEmpty ? tag : '$tag · ${sourceLabel.trim()}';
}

/// 每页条数(用户 2026-11-06 拍板:结果按页翻,不再"显示更多"无限追加)。
///
/// 10 条 ≈ 手机一屏半:一页能扫完,又不至于翻页翻到烦。
const int materialChannelPageSize = materialResultPageSize;

/// 总页数(纯函数,可单测)。0 条也算 1 页 —— 页码控件永远显示"第 1 / 1 页",
/// 不会出现 "第 1 / 0 页" 这种自相矛盾的文案。
int materialChannelPageCount(int total, {int pageSize = materialChannelPageSize}) =>
    materialResultPageCount(total, pageSize: pageSize);

/// 把页码夹进合法范围(纯函数,可单测)。
///
/// 为什么必须有:"继续找更多"/刷新/删除材料都会让总条数变化,页码可能越界;
/// 渲染时统一夹紧,就不会渲染出一页空白还点不动。
int materialChannelPageClamp(
  int page,
  int total, {
  int pageSize = materialChannelPageSize,
}) =>
    materialResultPageClamp(page, total, pageSize: pageSize);

/// 某页对应的条目区间 `[start, end)`(纯函数,可单测)。
({int start, int end}) materialChannelPageRange(
  int page,
  int total, {
  int pageSize = materialChannelPageSize,
}) =>
    materialResultPageRange(page, total, pageSize: pageSize);

/// 「我的」一次从材料库读多少条(排序 = 最近更新)。
///
/// `MaterialLibrary.shelf()` 没有分页接口(本轮不改 DB 层),所以 300 是上限;
/// 达到上限时界面必须**明说"只显示最近更新的 300 篇"**,不能让第 301 篇
/// 之后保存的材料静默消失(QA N2)。
const int materialChannelMineShelfLimit = 300;

class _ChannelItem {
  final String title;
  final String url;
  final String sourceLabel;
  final String kind;
  final String snippet;

  /// 真实封面图(发现流水线给的 og:image / markdown 首图)。
  ///
  /// 可变:用户点「开始读/保存到我的」会按需补抓正文,抓取结果里的
  /// `doc.coverUrl` / markdown 首图会写回这里(见 [_fetchContentFor]),
  /// 这样回到发现 Tab 时卡片就有真封面,不再是文字版式。
  String? imageUrl;

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

  /// 抓不到正文的**具体原因**([ContentQuality.rejectReason] 给用户看的文案)。
  ///
  /// 有值时卡片/提示解释"为什么不能读";没有时仍给固定的兜底文案。
  /// 这样用户看到的是"抓到的是图书/课程介绍页"而不是笼统的"抓不到正文"。
  String? contentUnavailableReason;

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
    final displayTitle = title.isEmpty ? c.url : title;
    final content = c.content;
    return _ChannelItem(
      title: displayTitle,
      url: c.url.trim(),
      sourceLabel: _examTaggedSourceLabel(
        c.sourceLabel.trim(),
        displayTitle,
        c.url,
      ),
      kind: inferChannelKind(displayTitle, c.url,
          fallback: c.kind.trim().isEmpty ? 'article' : c.kind.trim()),
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
      sourceLabel: _examTaggedSourceLabel(
        '${map['sourceLabel'] ?? ''}'.trim(),
        title.isEmpty ? url : title,
        url,
      ),
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

  /// 「我的」读失败的信息(P2-2):读失败要显示错误态与重试,不能伪装成"没有材料"。
  String? _mineError;

  /// 本次会话跑过发现(用于区分"还没找过"的介绍卡与"找过但空的"空态卡)
  bool _ranThisSession = false;
  String? _error;

  /// 正在补抓/入库的条目 url(单条互斥,避免连点重复入库)
  String? _busyUrl;

  /// 发现 Tab 当前页(0 基;渲染时统一用 [materialChannelPageClamp] 夹紧)
  int _page = 0;

  /// 「我的」Tab 当前页(与发现同一套页码口径,历史材料再多也不变成无限竖列)
  int _minePage = 0;

  /// 顶部大块(chips / 需求摘要)的收起进度:0 = 完整显示,1 = 已滚走。
  /// 与材料中心首页同一套口径(滚 120px 收完),滚完后才露出紧凑范围条。
  double _collapseT = 0;

  /// 两个 Tab 各自一条滚动控制器:切页要滚回列表顶、点紧凑条要滚回 chips,
  /// 都得直接命令对应的列表,不能靠"重建后自然回到顶部"(重建并不会回顶)。
  final ScrollController _discoverScroll = ScrollController();
  final ScrollController _mineScroll = ScrollController();

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
    _discoverScroll.dispose();
    _mineScroll.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // indexIsChanging 期间会多次回调;只在切到「我的」后刷一次材料列表
    if (_tab.indexIsChanging) return;
    // 两个 Tab 的滚动位置互相独立:切 Tab 后按当前 Tab 的偏移重算收起进度,
    // 否则"发现页滚到底 → 切到我的页(在顶部)"时紧凑条会白白挂着
    _syncCollapseWithTab();
    if (_tab.index == 1) unawaited(_loadMine(showLoading: false));
  }

  // ═══════════════════════════════════════════════════════════════════
  // 滚动:顶部分类条随滚动收起 + 切页滚回列表顶
  // ═══════════════════════════════════════════════════════════════════

  /// 当前 Tab 的滚动控制器(发现 / 我的)
  ScrollController get _currentScroll =>
      _tab.index == 0 ? _discoverScroll : _mineScroll;

  /// 分类条收起进度:滚动 120px 收完(与材料中心首页同一口径)。
  ///
  /// 用 NotificationListener 统一接两个列表的滚动通知,而不是给每个列表
  /// 各挂一个 listener —— 页面只有一块顶栏,收起状态必须全局一致。
  ///
  /// 只按**方向**过滤、不按 `depth` 过滤:通知从 TabBarView 里的竖向列表
  /// 往上冒时会先穿过 TabBarView 自己的 PageView(横向 Viewport),
  /// depth 会被加成 1;按 depth==0 过滤会导致一条都收不到。
  /// 本页内容里没有别的竖向可滚动区域,方向过滤已经足够精确。
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    _onScrollOffset(notification.metrics.pixels);
    return false;
  }

  void _onScrollOffset(double px) {
    final t = (px / 120).clamp(0.0, 1.0);
    if ((t - _collapseT).abs() > 0.02 && mounted) {
      setState(() => _collapseT = t);
    }
  }

  /// 切 Tab 后按该 Tab 当前偏移同步收起进度(避免两个 Tab 的状态互相串)
  void _syncCollapseWithTab() {
    final ctrl = _currentScroll;
    final px = ctrl.hasClients ? ctrl.offset : 0.0;
    final t = (px / 120).clamp(0.0, 1.0);
    if ((t - _collapseT).abs() > 0.02 && mounted) {
      setState(() => _collapseT = t);
    }
  }

  /// 滚回列表顶:切页 / 点紧凑条「改范围」都用它。
  ///
  /// 用 animateTo 而不是 jumpTo:用户能看见"滚动"这个动作,才知道自己翻页了;
  /// 没有 client(列表还没建出来)时直接跳过,不抛。
  void _scrollToTop({bool animate = true}) {
    final ctrl = _currentScroll;
    if (!ctrl.hasClients) return;
    if (animate) {
      unawaited(
        ctrl.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      ctrl.jumpTo(0);
    }
  }

  /// 翻到发现 Tab 的第 [page] 页并滚回顶部
  void _goPage(int page) {
    final next = materialChannelPageClamp(page, _items.length);
    if (next == _page) return;
    setState(() => _page = next);
    _scrollToTop();
  }

  /// 翻到「我的」Tab 的第 [page] 页并滚回顶部
  void _goMinePage(int page) {
    final next = materialChannelPageClamp(page, _mine.length);
    if (next == _minePage) return;
    setState(() => _minePage = next);
    _scrollToTop();
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
    // 2026-11-07 用户真机反馈(第 1 条):材料中心(按题材/形式/场景)不再把
    // 用户需求/目标写进检索提示 —— 否则「四六级 + 商业政治」这种组合会一起
    // 为难 AI,结果又少又怪。需求画像只留给「按需求」频道 /「找材料·按我的情况找」。
    final needText = widget.direction == MaterialDirection.need
        ? (needSummary.trim().isEmpty ? '按我的需求找真实材料' : needSummary)
        : <String>[
            _shortTitle,
            if (labels.isNotEmpty) labels.join('、'),
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

  // ═══════════════════════════════════════════════════════════════════
  // 「我的」的键:方向级,不是子分类组合级(QA N1)
  // ═══════════════════════════════════════════════════════════════════
  //
  // 快照和保存关系是**两套 key**,不能混:
  // - 快照(`material_channel_` + [_channel.id]):一个子分类组合一份发现结果,
  //   换组合就该看到"这个组合上次找的结果" → 必须用组合级 id;
  // - 保存关系(「我的」):用户点"保存到我的"是**对这份材料**的收藏,
  //   不是"对这个子分类组合"的收藏。以前两者共用 `_channel.id`,用户切一下
  //   子分类 id 就变了,保存过的材料在「我的」里凭空消失(QA N1)。
  //
  // 现在:保存关系一律写**方向级** `topic:all` / `form:all` / `scene:all` / `need:all`;
  // 读的时候同时兼容旧的组合级 key,升级不会丢已保存的材料(只读不迁)。

  /// 保存关系(「我的」)用的方向级 key
  String get _mineStoreId => '${widget.direction.name}:all';

  /// 读保存关系时要合并的 key:方向级(新)+ 当前子分类组合(旧数据)
  List<String> get _mineStoreKeys {
    final keys = <String>{_mineStoreId, _channel.id};
    return keys.toList(growable: false);
  }

  /// 读「保存到我的」材料 id 集合(方向级 + 旧组合级合并)
  Future<Set<String>> _loadSavedIds() async {
    final out = <String>{};
    for (final key in _mineStoreKeys) {
      out.addAll(await MaterialChannelStore.savedMaterialIds(key));
    }
    return out;
  }

  /// 读频道级移除表(同样合并旧 key,保证"移过的不再冒出来")
  Future<Set<String>> _loadHiddenIds() async {
    final out = <String>{};
    for (final key in _mineStoreKeys) {
      out.addAll(await MaterialChannelStore.hiddenMaterialIds(key));
    }
    return out;
  }

  /// 频道检索词:子分类自带的 queries + 展示名(中文给官方搜索)。
  ///
  /// 2026-11-07 用户真机反馈后收口成**纯函数** [MaterialTaxonomy.buildChannelQueries]:
  /// - 按题材/形式/场景:只用「分类检索词」,**不注入用户目标/需求**;
  /// - 按需求:沿用需求自由文本 + 目标 + 拉丁兴趣(独立入口的个性化)。
  /// 子分类没配 queries 时用 [_subQueryFallback] 补真实英文检索词。
  List<String> _buildQueries(List<String> selectedIds) =>
      MaterialTaxonomy.buildChannelQueries(
        direction: widget.direction,
        def: _def,
        selectedIds: selectedIds,
        goals: _prefs.examGoals,
        interests: _prefs.interests,
        extraNeed: _need.extra,
        fallbackQueries: _subQueryFallback,
      );

  /// 频道页给 AI 的**中性提示词**(只含分类 + 难度;「按需求」方向返回空串,
  /// 由 [MaterialDiscovery.discover] 回落到 `InputPreferences.promptHint`)。
  String get _channelPromptHint => MaterialTaxonomy.buildChannelPromptHint(
        direction: widget.direction,
        def: _def,
        selectedIds: _selected.toList(),
        bandHint: _need.band.isAny ? '' : _need.band.hintForAi,
      );

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
      // 保存关系/移除表用方向级 key(见 _mineStoreId):切子分类不会丢已保存
      savedIds = await _loadSavedIds();
      hiddenIds = await _loadHiddenIds();
      shelf = await MaterialLibrary.shelf(limit: materialChannelMineShelfLimit);
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
      // 换频道 / 刷新后回到第 1 页和列表顶:否则用户改完子分类还停在第 3 页,
      // 看到的是半截结果,会以为"这个子分类没有材料"
      _page = 0;
      _minePage = 0;
      _collapseT = 0;
    });
    // 重建列表不会把滚动位置归零,要显式滚一次(两个 Tab 都可能在旧偏移上)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_discoverScroll.hasClients) _discoverScroll.jumpTo(0);
      if (_mineScroll.hasClients) _mineScroll.jumpTo(0);
    });

    if (widget.debugItems.isNotEmpty) {
      // 仅渲染/质检测试:预置"实跑一轮后"的结果与质量过滤汇总(生产不传)。
      final injected = <_ChannelItem>[];
      for (final map in widget.debugItems) {
        final item = _ChannelItem.fromSnapshot(map, seq: injected.length);
        if (item != null) injected.add(item);
      }
      _markSavedFromShelf(injected, shelf, savedIds);
      if (!mounted) return;
      setState(() {
        _items = injected;
        _notes = widget.debugNotes;
        _updatedAt = DateTime.now();
        _ranThisSession = true;
        _page = 0;
      });
    }
  }

  /// 重读「我的」:保存关系 + 材料库(阅读进度会变,读完回来要刷)。
  Future<void> _loadMine({bool showLoading = true}) async {
    final channelId = _channel.id;
    if (showLoading) setState(() => _mineLoading = true);
    Set<String> savedIds = <String>{};
    Set<String> hiddenIds = <String>{};
    List<ShelfItem> shelf = const <ShelfItem>[];
    String? error;
    try {
      savedIds = await _loadSavedIds();
      hiddenIds = await _loadHiddenIds();
      shelf = await MaterialLibrary.shelf(limit: materialChannelMineShelfLimit);
    } catch (e) {
      // P2-2:读失败 ≠ 没有材料。以前只 debugPrint,shelf 保持空,
      // 用户看到「这个频道里还没有材料」的空态,以为自己没保存过。
      debugPrint('ReadFlow 频道页读取我的材料失败: $e');
      error = '本地材料读取失败';
    }
    if (!mounted || channelId != _channel.id) return;
    setState(() {
      _savedIds = savedIds;
      _hiddenIds = hiddenIds;
      _mine = error == null ? _mineFrom(shelf, savedIds) : <ShelfItem>[];
      // 读完/删了材料后总数会变少:页码越界就夹回最后一页(否则渲染空白页)
      _minePage = materialChannelPageClamp(_minePage, _mine.length);
      _mineError = error;
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
    // P2-3:快照条数有上限;到上限后先读/保存已有结果,别让"付了钱结果被截断"。
    if (more && _items.length >= MaterialChannelStore.maxSnapshotItems) {
      _snack(
        '这个频道的结果已到上限(${MaterialChannelStore.maxSnapshotItems} 篇)。'
        '先读或保存已有结果,或点右上角刷新重新找一批。',
      );
      return;
    }
    final vocab = context.read<VocabProvider>().vocabularies;
    _refreshPrefsAndNeed();
    final channel = _channel;
    // 中性提示词(分类 + 难度):非「按需求」频道不再注入用户目标/需求白名单;
    // 「按需求」方向返回空串 → discover 内部回落到 InputPreferences.promptHint。
    final neutralHint = _channelPromptHint;
    final modelHint = neutralHint.isEmpty ? _prefs.promptHint : neutralHint;
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
        _page = 0;
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
            prefsHint: modelHint,
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
        // 频道页只按「分类 + 难度」找(材料中心不再被用户需求框死)
        promptHintOverride: neutralHint,
        categoryHint: channel.title,
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
      final beforeCount = _items.length;
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
        if (hadItems && added > 0) {
          // 追加后跳到"第一条新结果"所在页:用户点完「继续找更多」要立刻看到
          // 新东西;还停在原页会以为没反应。总页数由总条数重算(页数随之增加)。
          _page = materialChannelPageClamp(
            beforeCount ~/ materialChannelPageSize,
            merged.length,
          );
        }
      });
      if (hadItems && added > 0) {
        // 新的一页从顶部开始看(与点页码翻页同一套行为)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _tab.index == 0) _scrollToTop();
        });
      }
      if (hadItems && added <= 0) {
        _snack('这次没有新增结果,可以换个子分类或稍后再试。');
      }

      // 落快照:正文/analysis 不进快照(契约);成本/检索词按**本轮**传,
      // append 时由 store 侧累加,不能把累计值再传进去(会重复计费)。
      // P2-1:store 返回成败;失败要告诉用户"下次进来可能看不到这批"。
      final snapshotSaved = await MaterialChannelStore.saveRun(
        channel.id,
        items: <Map<String, Object?>>[
          for (final item in fresh) _snapshotMapOf(item),
        ],
        apiRequests: run.searchApiRequests,
        costCny: run.estimatedCostCny,
        queriesUsed: runQueries,
        append: hadItems,
      );
      if (!snapshotSaved && mounted) {
        _snack('结果已显示,但保存频道快照失败(下次进入可能看不到这批结果)。');
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

  /// 按需补抓正文:① 普通 HTTP 抓取(公开源/静态页);② 官方 Fetch
  /// (教材/真题多在中文站,普通抓取常被反爬挡住,且官方 Fetch 按成功请求计费)。
  ///
  /// 2026-11-06 内容质量闸门(用户真机反馈「点进去只有图书介绍/购买页」):
  /// 以前只判 `length >= 200`,而书店商品页、课程售卖页、站点导航页都能轻松
  /// 超过 200 字 → 被当成正文入库。现在每段抓取都要过 [ContentQuality.rejectReason]
  /// 四道闸(长度/购买意图/商品介绍版块/正文形态);**两段都不合格返回 null**,
  /// 由调用方提示"抓不到正文,可打开原文/PDF",而不是把宣传页塞进阅读器。
  ///
  /// 两段抓取都顺手把**真实封面**写回 [item.imageUrl](有图且原本没图才写):
  /// 用户点「开始读/保存到我的」后再回到发现 Tab,卡片就有真封面了。
  Future<String?> _fetchContentFor(_ChannelItem item) async {
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
      debugPrint('ReadFlow 频道页普通抓取不合格(${item.url}): $reason');
    } catch (e) {
      debugPrint('ReadFlow 频道页普通抓取失败(${item.url}): $e');
    }
    try {
      final client = DeepSeekSearchClient();
      if (!client.available) {
        // 没配官方 Key:只有第一段失败/不合格,如实记原因(不假装配图)
        item.contentUnavailableReason = lastReason;
        return null;
      }
      final page = await client.fetch(item.url);
      if (page == null) {
        item.contentUnavailableReason = lastReason;
        return null;
      }
      final markdown = page.content;
      _rememberCover(
        item,
        ContentQuality.firstImageFromMarkdown(markdown, baseUrl: item.url),
      );
      final text = plainTextFromMarkdown(markdown).trim();
      final reason = ContentQuality.rejectReason(text);
      if (reason == null) return text;
      item.contentUnavailableReason = reason;
      return null;
    } catch (e) {
      debugPrint('ReadFlow 频道页官方抓取失败(${item.url}): $e');
      item.contentUnavailableReason = lastReason;
      return null;
    }
  }

  /// 把抓到的真实封面写回条目(只在原本**没有**封面时写,不覆盖已有图)。
  ///
  /// [raw] 可能是相对路径:用 [baseUrl] 转成绝对 http(s);转不出来就丢弃,
  /// 由卡片回落文字版式 —— 绝不编一个假封面地址。
  void _rememberCover(_ChannelItem item, String? raw, {String? baseUrl}) {
    if ((item.imageUrl ?? '').trim().isNotEmpty) return;
    final cover = ContentQuality.absoluteHttpUrl(raw ?? '', baseUrl: baseUrl);
    if (cover == null || cover.trim().isEmpty) return;
    item.imageUrl = cover;
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
      // 把发现卡上已经拿到的真实封面一起入库(落到 materials.cover_url):
      // 否则「我的」/书架 3D/网格/阅读器只能回落到程序化封面 ——
      // 用户问题 1(假封面)的另一半就在这里(QA 核对过)。
      coverUrl: item.imageUrl,
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
          _snack(_unavailableHint(item));
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

  /// 「保存到我的」:本地已有这篇 → 只记方向级保存关系;否则补抓正文 → 入库 → 记录。
  Future<void> _saveToMine(_ChannelItem item) async {
    if (_busyUrl != null || item.saved) return;
    setState(() => _busyUrl = item.url);
    try {
      var materialId = item.materialId;
      if (materialId == null) {
        final ok = await _ensureContent(item);
        if (!ok) {
          item.contentUnavailable = true;
          if (!mounted) return;
          setState(() {});
          _snack(_unavailableHint(item, saving: true));
          return;
        }
        if (!mounted) return;
        materialId = await _ingestToLibrary(item);
        item.materialId = materialId;
      }
      // P2-1:保存关系写失败要如实说,否则"已保存"但下次进来没有。
      // QA N1:写**方向级** key(_mineStoreId),换子分类后「我的」里不会消失。
      final saved = await MaterialChannelStore.addSavedMaterial(
        _mineStoreId,
        materialId,
      );
      if (!saved) {
        if (mounted) _snack('保存失败:本地存储写入出错,请重试');
        return;
      }
      // 之前从本频道移除过 → 重新保存时把持久移除记录也撤掉(含旧组合级 key)
      for (final key in _mineStoreKeys) {
        final cleared =
            await MaterialChannelStore.removeHiddenMaterial(key, materialId);
        if (!cleared) {
          // QA B7-③:撤隐藏失败不阻塞"已保存",但极端情况下重进本频道
          // 这篇仍会被过滤掉 —— 至少留日志便于排查,不扩大改动。
          debugPrint(
            'ReadFlow 撤销频道隐藏失败(key=$key, materialId=$materialId):'
            '已保存,但重进频道可能仍被过滤',
          );
        }
      }
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
    // P2-1:DB 写方法现在返回成败;失败必须如实提示,不能"没写进去还弹已更新"。
    final updated = await DatabaseService.setMaterialTitleCn(item.id, text);
    if (!updated) {
      if (mounted) _snack('改标题失败:数据库没写进去,请重试');
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
    // P2-1:存储写方法返回成败;任一失败都如实提示,不假装移除成功。
    // QA N1:保存关系横跨方向级(新)与旧组合级 key,两边都要清干净,
    // 否则用户切换子分类后这条又被旧 key 带回来。
    var unlinked = true;
    for (final key in _mineStoreKeys) {
      final ok = await MaterialChannelStore.removeSavedMaterial(key, item.id);
      unlinked = ok && unlinked;
    }
    // 移除表写方向级:换子分类后也不该再冒出来
    final hidden =
        await MaterialChannelStore.addHiddenMaterial(_mineStoreId, item.id);
    if (!unlinked || !hidden) {
      if (mounted) _snack('移除失败:本地存储写入出错,请重试');
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
    // P2-1:deleteMaterial 用 -1 表示删除过程出错(0 = 本来就没有)。
    final deleted = await DatabaseService.deleteMaterial(item.id);
    if (deleted < 0) {
      if (mounted) _snack('删除失败:数据库操作出错,材料还在,请重试');
      return;
    }
    // 删材料后顺手清掉保存关系,避免「我的」里留下指向已删材料的脏 id。
    // 关系清理失败不影响"材料已删"的事实(读的时候会跳过脏 id)。
    // QA N1:保存关系横跨方向级(新)与旧组合级 key,两边都清。
    for (final key in _mineStoreKeys) {
      await MaterialChannelStore.removeSavedMaterial(key, item.id);
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

  /// 按需求方向:去「设置需求」页改需求(难度/形式/目标),回来重读。
  ///
  /// P2-8:频道页只要**需求编辑器**,不要旧页的"结果列表/AI 补长尾"整页 ——
  /// `settingsOnly: true` 时旧页只显示编辑器 + 保存,保存后 `pop(true)`。
  Future<void> _openNeedSettings() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const MaterialBrowseScreen(
          direction: MaterialDirection.need,
          settingsOnly: true,
        ),
      ),
    );
    if (!mounted) return;
    _refreshPrefsAndNeed();
    await _reloadAll();
    if (saved == true) _snack('需求已保存:全 App 的材料会按它排序/推荐');
  }

  // ═══════════════════════════════════════════════════════════════════
  // 头部刷新
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onHeaderRefresh() async {
    if (_running) return;
    if (_tab.index == 1) {
      await _loadMine();
      return;
    }
    // QA N3:结果已到快照上限(120 篇)时,不能再走"追加"路径 ——
    // store 的 append 会用 sublist(0, 120) 把**新结果直接丢掉**,但搜索费照付。
    // 这时刷新必须走"重新找一批(替换)":先清空当前结果再搜。
    if (_items.length >= MaterialChannelStore.maxSnapshotItems) {
      await _refreshAtCap();
      return;
    }
    // P2-7:发现 Tab 顶部刷新 = 重新调官方搜索(要计费),和下拉刷新
    // (只重读本地快照、免费)不是一回事。已有结果时先确认,避免误触重复付费。
    if (_items.isNotEmpty) {
      final confirmed = await _confirmPaidResearch();
      if (!confirmed || !mounted) return;
    }
    await _startDiscovery();
  }

  /// 结果已到上限时的"重新找一批"(QA N3)。
  ///
  /// 为什么要先清空再搜:发现结果存快照时 `append=true` 会封顶 120 条并**丢弃**
  /// 超出部分 —— 用户付了费却看不到新结果。清空后 [_startDiscovery] 按
  /// `hadItems == false` 走"替换",新一批完整保留、页数也回到第 1 页。
  /// 已经「保存到我的」的材料是独立关系表,清空发现结果不会删它们。
  Future<void> _refreshAtCap() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新找一批?'),
        content: Text(
          '当前已有 ${_items.length} 条结果,已经到频道上限'
          '(${MaterialChannelStore.maxSnapshotItems} 篇)。\n\n'
          '再找一批会整体替换当前结果(不是追加),这样新结果不会因为超上限被丢掉;'
          '已保存到「我的」的材料不受影响。\n\n'
          '这会重新调用公开源 + DeepSeek 官方搜索(按成功请求计费,模型调用另计)。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重新找一批'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      // 先清空:让 _startDiscovery 走"替换"分支(append=false),页数回第 1 页
      _items = <_ChannelItem>[];
      _updatedAt = null;
      _apiRequests = 0;
      _costCny = 0;
      _notes = <String>[];
      _page = 0;
      _events.clear();
      _showProcess = false;
    });
    await _startDiscovery();
  }

  /// 发现 Tab 顶部刷新前的付费确认(P2-7)。返回 true = 用户确认再找一批。
  Future<bool> _confirmPaidResearch() async {
    final lastRound = _apiRequests > 0
        ? '上一批累计官方搜索 $_apiRequests 次、约 ${_costCny.toStringAsFixed(3)} 元。'
        : '每次会重新调用公开源 + DeepSeek 官方搜索(按成功请求计费,模型调用另计)。';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('再找一批?'),
        content: Text(
          '$lastRound\n\n这会重新检索并可能产生新的费用;'
          '只是想重读上次结果不用刷新(下拉即可)。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('再找一批'),
          ),
        ],
      ),
    );
    return confirmed == true;
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
            tooltip: _tab.index == 1
                ? '刷新频道材料'
                : (_items.length >= MaterialChannelStore.maxSnapshotItems
                      // QA N3:到上限后刷新走"替换",文案要说清楚,别让用户以为只是排除已见
                      ? '重新找一批(已到上限,会替换当前结果)'
                      : '再找一批(排除已见结果)'),
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
          : Stack(
              children: <Widget>[
                // 顶部分类条不再是"钉死的固定条":它被放进两个 Tab 各自的
                // 滚动内容里(见 _discoverTab/_mineTab),下滑时整条滚出去,
                // 不再永久占一块高度压住结果。
                // 这里统一接两个列表的滚动通知,驱动"滚走后顶部紧凑范围条出现"。
                Positioned.fill(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: TabBarView(
                      controller: _tab,
                      children: <Widget>[_discoverTab(skin), _mineTab(skin)],
                    ),
                  ),
                ),
                // 收起后仍能一眼看到当前频道范围(见 _compactScopeBar)
                _compactScopeBar(skin),
              ],
            ),
    );
  }

  // ── 头部:子分类 chips / 需求摘要 ─────────────────────────────────

  /// 频道顶部的范围条(子分类 chips / 需求摘要)。
  ///
  /// **它现在在滚动内容里**(两个 Tab 各自的第一块),不再是固定条:
  /// 用户往下看结果时它会随内容滚走,把整块高度让给结果;
  /// 滚走后在顶部出现 [_compactScopeBar],仍能一眼看到当前频道范围。
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

  /// 滚走后的紧凑范围条:一行显示"频道 + 已选范围",点「改范围」滚回顶部。
  ///
  /// 为什么要留着它(而不是完全隐藏):用户滚到第 3 页时,如果顶部什么都
  /// 没有,就分不清"我现在看的是哪个子分类的结果";为什么不做成固定条:
  /// 固定条会像之前那样一直遮着内容。这里只在收起过半时淡入,而且只有一行。
  Widget _compactScopeBar(V4Skin skin) {
    final visible = _collapseT >= 0.6;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: visible ? 1 : 0,
          child: Container(
            decoration: BoxDecoration(
              // 必须**不透明**:下面的结果会从条底下滚过,半透明会让卡片标题
              // 透出来和"按题材 · 整个方向"叠在一起(渲染图里肉眼可见的脏)
              color: skin.pageBg,
              border: Border(bottom: BorderSide(color: skin.hairline)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: skin.ink.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(Gap.md, 5, Gap.sm, 5),
            child: Row(
              children: <Widget>[
                Icon(Icons.filter_alt_outlined, size: 14, color: skin.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _scopeSummary(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.tagStyle.copyWith(
                      color: skin.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _scrollToTop(),
                  borderRadius: Radii.pillRadius,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '改范围',
                          style: AppFont.tagStyle.copyWith(
                            color: skin.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 14,
                          color: skin.accent,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 当前频道范围的一行摘要(紧凑条用):「按题材 · 科技、商业」/「整个方向」。
  String _scopeSummary() {
    if (widget.direction == MaterialDirection.need) {
      final summary = _need.summary.trim();
      return summary.isEmpty ? '整个需求 · 还没设置' : '需求:$summary';
    }
    if (_selected.isEmpty) return '$_shortTitle · 整个方向';
    final ids = _selected.toList()..sort();
    final labels = <String>[];
    for (final id in ids) {
      final sub = MaterialTaxonomy.subtopicOf(widget.direction, id);
      if (sub != null) labels.add(sub.label);
    }
    return '$_shortTitle · ${labels.isEmpty ? '整个方向' : labels.join('、')}';
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
      child: CustomScrollView(
        controller: _discoverScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          // 顶部分类条是滚动内容的第一块:下滑时整条滚走,不再固定遮挡结果
          SliverToBoxAdapter(child: _channelHeaderBar(skin)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate(_discoverChildren(skin)),
            ),
          ),
        ],
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
      final atCap = _items.length >= MaterialChannelStore.maxSnapshotItems;
      final pageCount = materialChannelPageCount(_items.length);
      final page = materialChannelPageClamp(_page, _items.length);
      // 分组保留:同一页里仍按"教材 / 应试真题 / 书籍…"出小标题,
      // 只是每组只取落进本页的那几条(见 _pageGroupSlices)
      final slices = _pageGroupSlices(page);
      var stagger = 0;
      for (final slice in slices) {
        children.add(
          _groupHeader(skin, slice.label, slice.items.length, slice.groupTotal),
        );
        for (final item in slice.items) {
          children.add(
            AppStagger(index: stagger++, child: _resultCard(item)),
          );
        }
      }
      children.add(const SizedBox(height: Gap.sm));
      // 真分页:底部页码控件(上一页 / 第 X / Y 页 / 下一页),切页滚回列表顶
      children.add(
        _pageBar(
          skin,
          page: page,
          pageCount: pageCount,
          total: _items.length,
          onGo: _goPage,
        ),
      );
      children.add(const SizedBox(height: Gap.sm));
      children.add(
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed:
                _running || atCap ? null : () => _startDiscovery(more: true),
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore_rounded, size: 18),
            label: Text(
              _running
                  ? '正在找更多…'
                  : atCap
                  ? '结果已到上限(${MaterialChannelStore.maxSnapshotItems} 篇)'
                  : '继续找更多',
            ),
          ),
        ),
      );
      if (page < pageCount - 1) {
        children.add(const SizedBox(height: Gap.xs));
        children.add(
          Center(
            child: Text(
              '还有 ${pageCount - 1 - page} 页',
              style: AppFont.tagStyle.copyWith(color: skin.inkFaint),
            ),
          ),
        );
      }
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

  /// 把"分组顺序 + 当前页区间"合成一页要渲染的分组片段(纯逻辑,可单测)。
  ///
  /// 全局页码(每页 10 条)+ 页内分组小标题,实现见
  /// [materialResultPageSlices](频道页与新「找材料」结果页共用)。
  List<MaterialResultPageSlice<_ChannelItem>> _pageGroupSlices(int page) =>
      materialResultPageSlices<_ChannelItem>(
        _groupedResults(),
        page,
        _items.length,
      );

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
    // 有分页时把"当前第几页"也放进摘要行:用户不用滚到底也能知道进度
    if (_items.isNotEmpty) {
      final pageCount = materialChannelPageCount(_items.length);
      if (pageCount > 1) {
        final page = materialChannelPageClamp(_page, _items.length);
        buffer.add('第 ${page + 1}/$pageCount 页');
      }
    }
    if (_apiRequests > 0) {
      // P2-5:这个数只含官方 Search/Fetch(5 元/千次成功请求),不含模型调用;
      // 如实标注口径,不装作"全部花费"。
      buffer.add('官方搜索约 ${_costCny.toStringAsFixed(3)} 元(模型未计)');
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
                '上次结果只存链接;点「开始读」会补抓正文。',
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
            '每次最多抓 8 篇正文;官方搜索按成功请求计费(几厘到几分钱)。',
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

  /// 底部页码控件(真分页的核心):上一页 / 第 X / Y 页 / 下一页。
  ///
  /// 视觉沿用果冻语言:白卡 + 细边 + 胶囊按钮;禁用态用 0.45 透明 + 不响应点击
  /// (而不是整块变灰 —— 整块灰掉会像"功能坏了",半透明才像"到头了")。
  Widget _pageBar(
    V4Skin skin, {
    required int page,
    required int pageCount,
    required int total,
    required ValueChanged<int> onGo,
  }) =>
      MaterialResultPageBar(
        page: page,
        pageCount: pageCount,
        total: total,
        onGo: onGo,
      );

  Widget _groupHeader(V4Skin skin, String label, int visible, int total) =>
      MaterialResultGroupHeader(
        label: label,
        visible: visible,
        total: total,
      );

  /// 结果分组:按材料类型(教材/应试真题/书籍/论文/外刊新闻/文章/其他),
  /// 组内先按**真实难度**(覆盖率高的在前)再按权威度排(快照无难度,按权威度)。
  List<MaterialResultGroup<_ChannelItem>> _groupedResults() =>
      groupMaterialResultItems<_ChannelItem>(
        _items,
        kindOf: (item) => item.kind,
        coverageOf: (item) => item.analysis?.knownTokenRatio,
        authorityOf: (item) => item.authority,
        seqOf: (item) => item.seq,
      );

  /// 结果卡:标题 + 来源/类型/难度胶囊 + 摘要 + 按钮行。
  ///
  /// **封面只在真的有图时出现**:`imageUrl` 是发现流水线填的 og:image /
  /// markdown 首图。没有图就不留封面位、也不画渐变假封面,直接把"标题 +
  /// 来源/类型/难度"做成文字版式(用户 2026-11-06 真机反馈)。
  Widget _resultCard(_ChannelItem item) {
    final isPdf = MaterialDiscovery.looksLikePdfUrl(item.url);
    final busy = _busyUrl == item.url;
    final canRead = !item.contentUnavailable && !busy;
    return MaterialResultCard(
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
      saved: item.saved,
      busy: busy,
      contentUnavailable: item.contentUnavailable,
      pdf: isPdf,
      unavailableHint:
          item.contentUnavailable ? _unavailableHint(item) : null,
      onRead: canRead ? () => _startRead(item) : null,
      onSave: canRead && !item.saved ? () => _saveToMine(item) : null,
      onOpenOriginal: busy ? null : () => _openOriginal(item),
    );
  }

  // ── 我的 Tab ────────────────────────────────────────────────────

  Widget _mineTab(V4Skin skin) {
    return RefreshIndicator(
      onRefresh: () => _loadMine(),
      child: CustomScrollView(
        controller: _mineScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          // 与发现 Tab 同一口径:顶部范围条随内容滚走
          SliverToBoxAdapter(child: _channelHeaderBar(skin)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate(_mineChildren(skin)),
            ),
          ),
        ],
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
    if (_mineError != null) {
      // P2-2:读失败给错误态 + 重试,不要显示"还没有材料"。
      return <Widget>[
        AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: '频道材料读取失败',
          hint: '$_mineError。你的材料没有丢,重新读一次就好。',
          action: FilledButton.icon(
            onPressed: () => _loadMine(),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重试'),
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
    // 「我的」同样按页展示:历史材料再多也不会变成一条无限竖列
    final pageCount = materialChannelPageCount(_mine.length);
    final page = materialChannelPageClamp(_minePage, _mine.length);
    final range = materialChannelPageRange(page, _mine.length);
    final visible = _mine.sublist(range.start, range.end);
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
        '按最近更新排序 · 长按卡片可管理',
        style: AppFont.tagStyle.copyWith(color: skin.inkFaint, height: 1.4),
      ),
      // QA N2:材料库读取有 300 条上限(DB 层本轮不改)。到上限时**明说**,
      // 不能让第 301 篇之后保存的材料看起来"凭空消失"。
      if (_mine.length >= materialChannelMineShelfLimit)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '只显示前 $materialChannelMineShelfLimit 篇;更早的到「材料库」看。',
            style: AppFont.tagStyle.copyWith(
              color: skin.inkFaint,
              height: 1.4,
            ),
          ),
        ),
      const SizedBox(height: Gap.sm),
      for (var i = 0; i < visible.length; i++)
        AppStagger(index: i, child: _mineCard(visible[i])),
      const SizedBox(height: Gap.sm),
      // 页码控件:与发现 Tab 同一套(上一页 / 第 X / Y 页 / 下一页)
      _pageBar(
        skin,
        page: page,
        pageCount: pageCount,
        total: _mine.length,
        onGo: _goMinePage,
      ),
    ];
  }

  /// 「我的」卡片:有 `coverUrl` 才显示真封面;**没有就纯文字版式**
  /// (标题 + 中文标题 + 来源/难度),不再走 AppWideCard 的程序化渐变封面。
  ///
  /// 为什么不用 AppWideCard:它内部固定渲染 `MaterialCover` —— 没图时会画一张
  /// 渐变"假封面"并盖一个「原版书」角标,正是用户真机反馈的那个东西。
  Widget _mineCard(ShelfItem item) {
    final skin = V4Skin.of(context);
    final saved = _savedIds.contains('${item.id}');
    final hasCover = shelfCoverHasImage(item.coverUrl);
    final titleCn = item.titleCn.trim();
    final title = titleCn.isNotEmpty ? titleCn : item.title;
    // 中文名在上、原文名在下(同名字不重复显示)
    final titleEn = item.title.trim() == title ? '' : item.title.trim();
    final metaParts = <String>[
      if (item.wordCount > 0) '${item.wordCount} 词',
      if (item.estMinutes > 0) '约 ${item.estMinutes} 分钟',
      if (item.cefr.isNotEmpty) item.cefr,
      item.progressLabel,
    ];
    return GestureDetector(
      onLongPress: () => _showMineActions(item),
      child: AppCard(
        variant: AppCardVariant.compact,
        padding: const EdgeInsets.all(Gap.sm),
        onTap: () => _openMine(item),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (hasCover) ...<Widget>[
              MaterialResultCoverThumb(
                url: item.coverUrl!,
                title: item.title,
                kind: item.kind,
                width: 62,
                height: 84,
                radius: 12,
              ),              const SizedBox(width: Gap.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppFont.subheadStyle.copyWith(
                            color: skin.ink,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '管理',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: skin.inkFaint,
                        ),
                        onPressed: () => _showMineActions(item),
                      ),
                    ],
                  ),
                  if (titleEn.isNotEmpty) ...<Widget>[
                    Text(
                      titleEn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.tagStyle.copyWith(color: skin.inkSoft),
                    ),
                    const SizedBox(height: 2),
                  ],
                  if (metaParts.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      metaParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.metaStyle.copyWith(color: skin.inkSoft),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: 4,
                    children: <Widget>[
                      if (saved) const AppTag('已保存', tone: AppTagTone.primary),
                      AppTag(MaterialLibrary.kindLabel(item.kind)),
                      if (item.origin == 'import') const AppTag('导入'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 抓不到正文时给用户的解释:有 [ContentQuality.rejectReason] 的具体原因
  /// 就说原因(如"抓到的是图书/课程介绍页"),没有就退回兜底文案。
  String _unavailableHint(_ChannelItem item, {bool saving = false}) {
    final reason = (item.contentUnavailableReason ?? '').trim();
    if (reason.isEmpty) {
      return saving
          ? '这篇抓不到正文,暂时不能保存;可以点「打开原文」直接看。'
          : '这篇抓不到正文(常见于 PDF/反爬站点),可以点「打开原文/PDF」直接看。';
    }
    return saving
        ? '这篇不能当正文保存:$reason。可以点「打开原文」直接看。'
        : '这篇不能当正文读:$reason。可以点「打开原文/PDF」直接看。';
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
}

