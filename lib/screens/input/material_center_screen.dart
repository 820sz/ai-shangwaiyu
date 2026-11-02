import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/learner_model.dart';
import '../../providers/vocab_provider.dart';
import '../../services/bookshelf.dart';
import '../../services/database.dart';
import '../../services/deepseek_api.dart';
import '../../services/external_link.dart';
import '../../services/feed_parser.dart' show FeedItem;
import '../../services/input_prefs.dart';
import '../../services/learner_model_store.dart';
import '../../services/material_library.dart';
import '../../services/material_prefs.dart';
import '../../services/material_source.dart';
import '../../services/material_source_status.dart';
import '../../services/material_topics.dart';
import '../../services/original_search.dart';
import '../../services/word_frequency.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/bookshelf_view.dart';
import '../../widgets/collapsible_section.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/material_cover.dart';
import '../../widgets/waiting.dart';
import 'category_material_screen.dart';
import 'material_category_screen.dart';
import 'material_discover_screen.dart';
import 'bookshelf_screen.dart';
import 'material_import_flow.dart';
import 'material_reader_screen.dart';
import 'widgets/material_preview_dialog.dart';
import 'widgets/material_topic_card.dart';

/// 材料中心(v2.0;v2.7 大改;v2.8 按参考软件做视觉与信息架构升级)。
///
/// ## v2.8 为什么重排(用户第 6(2) 条)
/// 用户原话:**"你做的所有功能的展示逻辑都非常单一枯燥,没有任何想用的欲望。
/// 整个软件全是字唉。"** 并附了参考软件(扇贝阅读)的两张截屏。
/// 调研(见 `docs/SPEC-material-discovery-2026-10-01.md`)结论 + 本机实测:
/// - 参考软件的结构是「大图卡片 + 分类 tab + 图文列表 + Lv 徽标 + 开始阅读」;
/// - 公开图源里 Wikipedia/Openverse/Gutendex/Open Library **全部不可达**,
///   只有 Gutenberg 封面 / RSS 的 media:content 可用 →
///   所以**程序化封面**(零网络零版权,按标题 hash 稳定取色)是首版最稳的底,
///   有真图时用真图([MaterialCover] 自动二选一)。
///
/// ## 本页结构
/// 1. **个性化找资源**(v2.7):难度 + 类型 + 题材 + 补充需求;
/// 2. **今日精读**(v2.8):一张大卡 —— 配图 / 题材 / Lv / 中英标题 / 句数时长口音 / 开始阅读;
/// 3. **发现更多**(v2.8):题材 tab + 图文列表,检索过程**流式**展示(「查阅了 xxx」);
/// 4. **按你的水平找材料**(分类入口);
/// 5. **今日推荐**(源最新条目,标题中文化);
/// 6. **材料库**:图文卡片 + 难度适配标注 + 原文链接。
class MaterialCenterScreen extends StatefulWidget {
  const MaterialCenterScreen({super.key});

  @override
  State<MaterialCenterScreen> createState() => _MaterialCenterScreenState();
}

class _MaterialCenterScreenState extends State<MaterialCenterScreen> {
  final _service = MaterialSourceService.instance;
  final _ai = DeepseekApiService();

  String _sourceId = MaterialSourceService.defaultSourceId;
  List<FeedItem> _items = const [];
  List<ShelfItem> _shelf = const [];
  bool _loadingShelf = true;
  bool _loadingItems = false;
  String? _error;
  LearnerModel _model = LearnerModel();
  MaterialPrefs _prefs = MaterialPrefs.empty;

  /// 输入偏好统一层(v3 批 2):目标(多选)/兴趣/难度档/时间都从这里读,
  /// 与「输入」首页的「我的需求」是同一份数据 —— 两处显示不能不一致。
  InputPreferences _inputPrefs = InputPreferences.load();

  /// 难度档辅助调整建议(v3 批 7 · P1-2):`suggestBand` 的展示结果。
  ///
  /// 为什么放在页面 state 而不是每次 build 现算:算它要读 SQLite(材料进度 +
  /// 测验准确率),不能在 build 里做;null = 还没算完 / 没有建议,两种都**不占位**。
  BandAdvice? _bandAdvice;
  bool _onlyFit = false;

  /// v3 批 8(拍板 #1):材料库是否"按目标优先"排序(有目标才生效,用户可关)。
  bool _goalFirst = true;
  Map<String, SourceHealth> _health = const {};
  bool _probing = false;

  /// 标题中文化缓存(英文原标题 → 中文译名)
  final Map<String, String> _titleCn = {};

  // ── 今日精读(v2.8)──
  FeedItem? _daily;
  MaterialAnalysis? _dailyAnalysis;
  bool _dailyLoading = false;

  // ── 发现更多(v2.8;v2.9 多选 + 自定义分区 + 卡片排版修)──
  List<MaterialTopic> _availableTopics = [...MaterialTopic.all];
  List<MaterialTopic> _topics = const [];
  Set<String> _selectedTopics = {};
  List<OriginalHit> _topicHits = const [];
  List<SearchEvent> _topicEvents = const [];
  bool _topicLoading = false;
  bool _topicLoaded = false;
  String _topicNote = '';

  /// 区块的展开/收起/隐藏(v2.9,用户 3(1) 条)
  final _sectionPrefs = SectionPrefsNotifier(UiSectionPrefs.load());

  /// (v2.12 移除)`_group` 三组分段切换。
  ///
  /// 上一版把页面分成「找材料 / 在读 / 我的东西」三组,用户 10/23 的原话是
  /// "分类逻辑还是一坨屎,难用死了,压根看不出功能分类之间的意义" ——
  /// 因为**维度不是用户的任务**:三组名字都是系统视角。现在改为
  /// 顶部**内容领域页签** + 纵向杂志式信息流(见 build 注释)。

  @override
  void initState() {
    super.initState();
    _prefs = MaterialPrefs.load();
    _inputPrefs = InputPreferences.load();
    // v2.23 修:自定义分区存 Hive,原来只在"新加分区"时才读 —— 重启 App 后
    // 分类墙上看不到自己建的分区,用户会以为分区丢了。首次进入就读全。
    _availableTopics = [...MaterialTopic.all, ...CustomTopics.load()];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _model = LearnerModelStore.load();
      _health = MaterialSourceStatus.loadAll();
      _sourceId = _initialSourceId();
      _loadShelf();
      _loadItems();
      // v2.23 修:书架预览原来只在"进过书架页又返回"后才加载,首屏永远是一排
      // 空书位 —— 用户以为书架坏了。跟其它区块一起首屏加载。
      unawaited(_loadBookshelf());
      _loadTopics([_availableTopics.first]);
      // 已有的材料里还没中文名的,后台补齐(用户为此提过两次)
      unawaited(_backfillShelfTitles());
      // 难度档辅助调整:用最近真实行为算一条建议(数据不足时静默不显示)
      unawaited(_loadBandAdvice());
    });
  }

  /// 初始内容源:用户选了「来源类型」偏好就用那一类里可用的源,否则按健康度选。
  ///
  /// v2.23 修(分类筛选失效):「我的需求 → 来源类型」以前**对今日推荐完全不
  /// 生效**(只作用于弹层里的题材检索),用户勾了"外刊/新闻"回到首页看到的还是
  /// 公版书 —— 看起来就是筛选坏了。现在首屏与保存偏好后都按它重选源。
  String _initialSourceId() {
    if (_prefs.kinds.isNotEmpty) {
      for (final s in _prefs.preferredSources) {
        final health = _health[s.id];
        // 偏好里没测过 / 实测可用 → 就用它;已知连不上的继续找下一个
        if (health == null || health.ok) return s.id;
      }
    }
    return MaterialSourceStatus.preferredSourceId(
      knownIds: [for (final s in MaterialSourceService.sources) s.id],
      fallback: MaterialSourceService.defaultSourceId,
      all: _health,
    );
  }

  /// 读真实信号并算"要不要调档"的建议(失败静默:建议只是锦上添花,
  /// 不能因为它读不到就让材料中心打不开)。
  Future<void> _loadBandAdvice() async {
    try {
      final advice = await loadBandAdvice();
      if (!mounted) return;
      setState(() => _bandAdvice = advice);
    } catch (e) {
      debugPrint('材料中心难度建议读取失败(已忽略): $e');
    }
  }

  Future<void> _loadShelf() async {
    try {
      final items = await MaterialLibrary.shelf(limit: 50);
      if (!mounted) return;
      setState(() {
        _shelf = MaterialLibrary.rankForBand(items, _prefs.band);
        _loadingShelf = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingShelf = false);
      debugPrint('材料库读取失败: $e');
    }
  }

  Future<void> _loadItems() async {
    setState(() {
      _loadingItems = true;
      _error = null;
    });
    try {
      final raw = await _service.listItems(_sourceId, limit: 12);
      await MaterialSourceStatus.recordOk(_sourceId);
      if (!mounted) return;
      // v2.23 修:同一个源偶尔把同一篇发两次(RSS 重发/多栏目同时收录),
      // 横滑列表会出现两张一模一样的卡 —— 按链接/标题先去重再展示。
      final items = MaterialLibrary.dedupeBy(
        raw,
        urlOf: (e) => e.link,
        titleOf: (e) => e.title,
      );
      setState(() {
        _items = items;
        _loadingItems = false;
        _health = MaterialSourceStatus.loadAll();
      });
      // 今日精读同样遵守屏蔽设置:只从过滤后的条目里挑,不能一边说"已过滤
      // N 条"、一边又把被屏蔽的第一条做成全页最大的卡。
      final allowed = _allowedFeed(items).kept;
      // 今日精读:取第一条做"预分析"(抓正文 + 本地难度),失败就退回不带难度的卡
      unawaited(_loadDaily(allowed.isEmpty ? null : allowed.first));
      // 标题中文化(用户第 2(2)/6(1) 条:标题一律「中文(英文)」)
      unawaited(_translateTitles(items.take(10).map((e) => e.title).toList()));
    } catch (e) {
      await MaterialSourceStatus.recordFail(_sourceId, e);
      if (!mounted) return;
      setState(() {
        _loadingItems = false;
        _error = '$e';
        _health = MaterialSourceStatus.loadAll();
      });
    }
  }

  /// 当前内容源的中文名(黑名单匹配与界面展示共用;拿不到就用 id,不编名字)
  String get _sourceLabel =>
      MaterialSourceService.sourceOf(_sourceId)?.label ?? _sourceId;

  /// 「今日推荐 / 今日精读」的过滤口径(C1-14)。
  ///
  /// 过滤判断本身在 [InputPreferences.allowsMaterial](标题/来源/题材任一命中
  /// 屏蔽词即过滤),这里只负责把 FeedItem 映射成那三个输入。
  BlocklistFilterResult<FeedItem> _allowedFeed(
    Iterable<FeedItem> items,
  ) {
    final kind = MaterialLevel.kindOfSource(_sourceId);
    return MaterialLibrary.filterBlocked(
      items,
      _inputPrefs,
      titleOf: (e) => e.title,
      sourceOf: (_) => _sourceLabel,
      genresOf: (_) => [MaterialLibrary.kindLabel(kind)],
    );
  }

  /// 「发现更多」结果的过滤口径(C1-14):标题 / 来源 / 检索题材三处命中即过滤。
  BlocklistFilterResult<OriginalHit> _allowedHits(
    Iterable<OriginalHit> hits,
  ) {
    final topics = _topics;
    return MaterialLibrary.filterBlocked(
      hits,
      _inputPrefs,
      titleOf: (h) => h.title,
      sourceOf: (h) =>
          MaterialSourceService.sourceOf(h.sourceId)?.label ?? h.sourceId,
      genresOf: (h) => [
        MaterialLibrary.kindLabel(MaterialLevel.kindOfSource(h.sourceId)),
        for (final t in topics) t.label,
      ],
    );
  }

  /// 今日精读:抓第一条的正文并做本地难度分析(不入库)。
  /// 大字卡要显示真实 Lv / 认知率,所以这一步值得花一次网络往返。
  Future<void> _loadDaily(FeedItem? item) async {
    if (item == null) {
      if (!mounted) return;
      setState(() {
        _daily = null;
        _dailyAnalysis = null;
        _dailyLoading = false;
      });
      return;
    }
    setState(() {
      _daily = item;
      _dailyAnalysis = null;
      _dailyLoading = true;
    });
    try {
      final doc = await _service.fetchDocument(_sourceId, url: item.link);
      if (!mounted) return;
      final vocab = context.read<VocabProvider>().vocabularies;
      final a = await MaterialLibrary.analyze(
        doc.plainText.isEmpty
            ? doc.chunks.map((c) => c.text).join('\n\n')
            : doc.plainText,
        model: _model,
        vocab: vocab,
      );
      if (!mounted) return;
      setState(() {
        _dailyAnalysis = a;
        _dailyLoading = false;
      });
    } catch (e) {
      debugPrint('今日精读预分析失败(不影响打开): $e');
      if (!mounted) return;
      setState(() => _dailyLoading = false);
    }
  }

  /// 「发现更多」:按题材检索(公版书 + 论文 + 外媒三路并行),过程流式上报
  ///
  /// v2.9(用户 3(3) 条):题材**可多选**(多选就一起搜、结果合并去重),
  /// 也可以**自己加分区**(自定义题材存 Hive,与内置的一起出现在这里)。
  Future<void> _loadTopics(List<MaterialTopic> topics) async {
    if (topics.isEmpty) return;
    setState(() {
      _topics = topics;
      _selectedTopics = {for (final t in topics) t.id};
      _topicLoading = true;
      _topicLoaded = true;
      _topicHits = const [];
      _topicEvents = const [];
      _topicNote = '';
    });
    final started = DateTime.now();
    final events = <SearchEvent>[];
    void push(SearchEvent e) {
      events.add(e);
      if (mounted) setState(() => _topicEvents = List.of(events));
    }

    push(SearchEvent(
      stage: SearchStage.preparing,
      label: topics.length == 1
          ? '按「${topics.first.label}」找材料:${topics.first.description}'
          : '一起找 ${topics.length} 个题材:${topics.map((t) => t.label).join('、')}',
    ));
    try {
      // 用户若在偏好里写了题材,优先用它的说法(他比我们更清楚要什么);
      // v2.10:选了"内容类型"就把它的英文检索词拼进来(中文标签对公开源没用)
      final genres = _prefs.genres.trim();
      final contentQueries = _prefs.contentQueries;
      final all = <OriginalHit>[];
      final seen = <String>{};
      final notes = <String>[];
      for (final topic in topics) {
        final base = genres.isEmpty ? topic.queries.first : genres;
        final query = contentQueries.isEmpty
            ? base
            : '$base ${contentQueries.first}';
        final result = await OriginalSearch.search(
          query,
          category: '其他',
          sourceIds: _prefs.kinds.isEmpty
              ? null
              : [for (final s in _prefs.preferredSources) s.id],
          onProgress: push,
        );
        for (final h in result.hits) {
          // 多题材合并时按 URL 去重(同一篇可能被两个题材的检索词命中)
          final key = h.url.trim().isEmpty ? h.title : h.url;
          if (seen.add(key)) all.add(h);
        }
        notes.addAll(result.notes);
        if (!mounted) return;
      }
      final seconds = DateTime.now().difference(started).inSeconds;
      push(SearchEvent(
        stage: SearchStage.done,
        label: '查阅了 ${all.length} 篇 · 用时 ${seconds == 0 ? '不到 1' : seconds} 秒',
        done: 1,
        total: 1,
        hits: all.length,
      ));
      setState(() {
        _topicHits = all;
        _topicLoading = false;
        _topicNote = notes.toSet().join(' · ');
      });
      unawaited(_translateTitles(all.take(12).map((h) => h.title).toList()));
    } catch (e) {
      if (!mounted) return;
      push(SearchEvent(stage: SearchStage.sourceFailed, label: '这次没找成:$e'));
      setState(() {
        _topicLoading = false;
        _topicNote = '$e';
      });
    }
  }

  /// 加一个自定义分区(用户 3(3) 条:发现更多的子分类要能自己加)
  Future<void> _addCustomTopic() async {
    final nameCtrl = TextEditingController();
    final queryCtrl = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            Gap.md,
            0,
            Gap.md,
            Gap.md + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('加一个自己的分区',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: Gap.xxs),
              Text(
                '公开内容源只认英文,所以检索词写英文(逗号分隔多个,越多搜得越广)。',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: Gap.md),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '分区名(中文)',
                  hintText: '如:帮我找金融英语',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: queryCtrl,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '英文检索词',
                  hintText: 'finance news, financial times, investment',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: Gap.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('加上去'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final topic = await CustomTopics.add(
      label: nameCtrl.text,
      queriesText: queryCtrl.text,
      description: '自定义分区',
    );
    nameCtrl.dispose();
    queryCtrl.dispose();
    if (topic == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分区名和英文检索词都要填')),
        );
      }
      return;
    }
    _reloadTopics();
    if (!mounted) return;
    await _loadTopics([..._topics, topic]);
  }

  void _reloadTopics() {
    setState(() {
      _availableTopics = [...MaterialTopic.all, ...CustomTopics.load()];
    });
  }

  /// 批量把英文标题翻成中文(**并且落库**)。
  ///
  /// v2.10 修(用户 10/4 原话:"推荐的所有材料,我都说了标题要有中文翻译呀 ——
  /// 我都说了几次了,一次都没实现过"):
  /// 旧实现只把译名塞进**这一次列表加载**的内存缓存 —— 材料库、书架、阅读器标题、
  /// 历史记录全都没中文,用户当然觉得"从来没实现"。
  /// 现在:①译名写进 `materials.title_cn`(任何界面读同一份、只翻一次);
  /// ②材料库/书架加载后**后台补齐**还没译名的材料;③界面上凡是英文标题都带中文。
  Future<void> _translateTitles(List<String> titles) async {
    final todo = [
      for (final t in titles)
        if (t.trim().isNotEmpty && !_titleCn.containsKey(t)) t,
    ];
    if (todo.isEmpty || !_ai.isConfigured) return;
    try {
      final map = await _ai.translateTitles(todo);
      if (!mounted) return;
      setState(() => _titleCn.addAll(map));
      await _persistTitleCn(map);
    } catch (e) {
      debugPrint('ReadFlow 标题中文化失败(保持英文): $e');
    }
  }

  /// 把译名写回材料表(标题 → 材料 id)
  Future<void> _persistTitleCn(Map<String, String> map) async {
    try {
      final shelf = await MaterialLibrary.shelf(limit: 300);
      for (final s in shelf) {
        final cn = map[s.title]?.trim();
        if (cn != null && cn.isNotEmpty) {
          await DatabaseService.setMaterialTitleCn(s.id, cn);
        }
      }
    } catch (e) {
      debugPrint('ReadFlow 写回中文标题失败: $e');
    }
  }

  /// 材料库里还没有中文名的,在后台慢慢补齐(app 打开时补几条,不阻塞界面)
  Future<void> _backfillShelfTitles() async {
    if (!_ai.isConfigured) return;
    try {
      for (var round = 0; round < 3; round++) {
        final rows = await DatabaseService.materialsMissingTitleCn(limit: 6);
        if (rows.isEmpty || !mounted) return;
        final titles = [for (final r in rows) '${r['title'] ?? ''}']
            .where((t) => t.trim().isNotEmpty)
            .toList();
        if (titles.isEmpty) return;
        final map = await _ai.translateTitles(titles);
        if (!mounted) return;
        var saved = 0;
        for (final r in rows) {
          final cn = map['${r['title']}']?.trim();
          final id = r['id'] as int?;
          if (id != null && cn != null && cn.isNotEmpty) {
            await DatabaseService.setMaterialTitleCn(id, cn);
            saved++;
          }
        }
        setState(() => _titleCn.addAll(map));
        // 一条都没写成功(比如 AI 一直返回空)就别再循环了,免得刷接口
        if (saved == 0) return;
      }
      if (mounted) {
        _model = LearnerModelStore.load();
        await _loadShelf();
      }
    } catch (e) {
      debugPrint('ReadFlow 后台补标题失败: $e');
    }
  }

  /// 「中文(英文)」标题(与分类页同一规则)
  String _titleCnOf(String en) => _titleCn[en]?.trim() ?? '';

  Future<void> _probeAll() async {
    setState(() => _probing = true);
    for (final s in MaterialSourceService.sources) {
      try {
        await _service.listItems(s.id, limit: 1);
        await MaterialSourceStatus.recordOk(s.id);
      } catch (e) {
        await MaterialSourceStatus.recordFail(s.id, e);
      }
      if (!mounted) return;
      setState(() => _health = MaterialSourceStatus.loadAll());
    }
    if (!mounted) return;
    setState(() => _probing = false);
    final usable = MaterialSourceService.sources
        .where((s) => _health[s.id]?.ok == true)
        .map((s) => s.label)
        .toList();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(usable.isEmpty
            ? '所有源都连不上 —— 检查网络后重试'
            : '可用源:${usable.join('、')}'),
      ),
    );
  }

  /// 打开一条"今日推荐"条目(v2.10)**真的打开它**,不是只换上面那张卡
  Future<void> _openFeedItem(FeedItem item) async {
    try {
      await MaterialImportFlow.openHitWithProgress(
        context,
        hit: OriginalHit(
          sourceId: _sourceId,
          sourceId2: item.link,
          title: item.title,
          url: item.link,
          note: item.summary,
          imageUrl: item.imageUrl,
        ),
        model: _model,
      );
    } catch (e) {
      // 流程内部已提示可读原因,这里只兜住"没被接住的异常",让页面不僵死
      _showOpenFailure(item.title, e);
    }
    if (!mounted) return;
    _model = LearnerModelStore.load();
    await _loadShelf();
    unawaited(_backfillShelfTitles());
  }

  /// 打开今日精读(大卡按钮)
  Future<void> _openDaily() async {
    final item = _daily;
    if (item == null) return;
    try {
      await MaterialImportFlow.openHitWithProgress(
        context,
        hit: OriginalHit(
          sourceId: _sourceId,
          sourceId2: item.link,
          title: item.title,
          url: item.link,
          note: item.summary,
          imageUrl: item.imageUrl,
        ),
        model: _model,
        label: '正在抓取并分析这篇…',
      );
    } catch (e) {
      _showOpenFailure(item.title, e);
    }
    if (!mounted) return;
    _model = LearnerModelStore.load();
    await _loadShelf();
  }

  /// 打开一条发现结果(软件内阅读)
  Future<void> _openHit(OriginalHit hit) async {
    try {
      await MaterialImportFlow.openHitWithProgress(
        context,
        hit: hit,
        model: _model,
      );
    } catch (e) {
      _showOpenFailure(hit.title, e);
    }
    if (!mounted) return;
    await _loadShelf();
  }

  Future<void> _openReader(int materialId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialReaderScreen(materialId: materialId),
      ),
    );
    if (!mounted) return;
    _model = LearnerModelStore.load();
    await _loadShelf();
    // 读完/读了一半会改变"读完率"与查词密度 —— 回来重算建议,
    // 否则用户刚读完一本,卡上还挂着按旧数据算的建议
    unawaited(_loadBandAdvice());
  }

  Future<void> _import() async {
    final ingested = await MaterialImportFlow.run(
      context,
      model: _model,
      dialogTitle: '导入材料',
    );
    if (ingested == null || !mounted) return;
    await _showPreview(ingested);
    await _loadShelf();
  }

  Future<void> _showPreview(IngestedMaterial ingested) async {
    final go = await showMaterialPreview(context, ingested);
    if (go && mounted) await _openReader(ingested.materialId);
  }

  Future<void> _openExternal(String url) async {
    var opened = false;
    try {
      opened = await launchExternalUrl(url);
    } catch (e) {
      // 打不开外链不是致命错误:统一走同一句提示,不吞异常但也不崩
      _showOpenFailure(url, e);
      return;
    }
    if (!opened) _showOpenFailure(url);
  }

  /// 打开失败的**统一**提示(C1-17)。
  ///
  /// 为什么收成一个入口:一页里"点开卡片/点原文链接/今日精读"有 4 条路径,
  /// 旧实现文案各写各的("打不开这个链接:$url" / "打开链接失败:$e"),同一件
  /// 事两种说法 —— 用户困惑,排障时也不知道该信哪条。现在全部是
  /// 「打不开这条内容[:原因] · 名称」,并浮动显示不挡内容。
  void _showOpenFailure(String what, [Object? error]) {
    if (!mounted) return;
    final name = what.trim();
    final reason = error == null ? '' : ':${_humanOpenError(error)}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '打不开这条内容$reason${name.isEmpty ? '' : ' · $name'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 异常 → 一句人能读的话(太长的堆栈式信息截断,SnackBar 一行放得下)
  String _humanOpenError(Object error) {
    final raw = '$error'.trim();
    if (raw.isEmpty) return '网络或链接异常';
    // 异常文本里常常带 "Exception: " 前缀,去掉后用户更好读
    final text = raw.replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '');
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }

  // (v2.13 移除)`_setBand`:难度选择收进了「我的需求」的调整弹层
  // (`_showPrefsSheet`),首页不再单独排一行难度 chip。

  Future<void> _showPrefsSheet() async {
    var draft = _prefs;
    final genresCtrl = TextEditingController(text: _prefs.genres);
    final extraCtrl = TextEditingController(text: _prefs.extra);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final muted = theme.colorScheme.onSurfaceVariant;
          void apply(MaterialPrefs p) => setSheet(() => draft = p);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Gap.md,
                0,
                Gap.md,
                Gap.md + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('个性化找资源',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: Gap.xxs),
                    Text(
                      '这些只影响"让 AI 去找什么样的材料",不会改动你已有的生词与材料。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, height: 1.4),
                    ),
                    const SizedBox(height: Gap.md),
                    Text('难度(i+1 / i+10 / i+100)',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final b in MaterialBand.values)
                          ChoiceChip(
                            label: Text(b.label),
                            selected: draft.band == b,
                            onSelected: (_) => apply(draft.copyWith(band: b)),
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.xxs),
                    Text(draft.band.description,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted, fontSize: 11)),
                    const SizedBox(height: Gap.md),
                    // v2.10(用户 10/4 第 2(4) 条):**内容层面**的类型 —— 与上面
                    // "来源类型"是两个维度:那个管"从哪来",这个管"里面是什么"。
                    Text('内容类型(可多选)',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    const SizedBox(height: Gap.xxs),
                    Text(
                      '来源管"从哪来",这里管"里面是什么" —— 选中的会被翻成英文检索词,直接影响找什么。',
                      style: TextStyle(fontSize: 11, height: 1.4, color: muted),
                    ),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final t in MaterialPrefs.contentCatalog)
                          FilterChip(
                            label: Text(t.label),
                            selected: draft.contentTypes.contains(t.id),
                            onSelected: (on) {
                              final next = {...draft.contentTypes};
                              if (on) {
                                next.add(t.id);
                              } else {
                                next.remove(t.id);
                              }
                              apply(draft.copyWith(contentTypes: next));
                            },
                            tooltip: t.hint,
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.md),
                    Text('来源类型',
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final e in MaterialPrefs.kindLabels.entries)
                          FilterChip(
                            label: Text(e.value),
                            selected: draft.kinds.contains(e.key),
                            onSelected: (on) {
                              final next = {...draft.kinds};
                              if (on) {
                                next.add(e.key);
                              } else {
                                next.remove(e.key);
                              }
                              apply(draft.copyWith(kinds: next));
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.md),
                    TextField(
                      controller: genresCtrl,
                      decoration: const InputDecoration(
                        labelText: '题材倾向(可留空)',
                        hintText: '如:哲学散文、英式幽默、科技新闻',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => apply(draft.copyWith(genres: v)),
                    ),
                    const SizedBox(height: Gap.sm),
                    TextField(
                      controller: extraCtrl,
                      maxLines: 3,
                      minLines: 2,
                      decoration: const InputDecoration(
                        labelText: '补充 / 调整需求(可留空)',
                        hintText: '如:不要学术腔,每篇 10 分钟以内读完',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => apply(draft.copyWith(extra: v)),
                    ),
                    const SizedBox(height: Gap.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => apply(MaterialPrefs.empty),
                            child: const Text('清空偏好'),
                          ),
                        ),
                        const SizedBox(width: Gap.xs),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('保存'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    genresCtrl.dispose();
    extraCtrl.dispose();
    if (saved != true || !mounted) return;
    setState(() => _prefs = draft);
    await _prefs.save();
    if (!mounted) return;
    // v2.23 修:「我的需求」里的兴趣/题材与输入偏好层是同一份数据(Hive 同一个
    // key),保存后必须重读 —— 否则本页标签与黑名单过滤还按旧值渲染,看起来
    // 就是"筛选没生效"。
    setState(() => _inputPrefs = InputPreferences.load());
    // v2.23 修:来源类型偏好保存后**立即**生效 —— 以前只影响弹层里的题材检索,
    // 今日推荐还是旧源,用户会以为来源筛选坏了。偏好变了就换源重拉。
    if (_prefs.kinds.isNotEmpty) {
      final preferred = _prefs.preferredSources;
      if (preferred.isNotEmpty && preferred.first.id != _sourceId) {
        setState(() => _sourceId = preferred.first.id);
        unawaited(_loadItems());
      }
    }
    await _loadShelf();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('偏好已保存 —— 推荐与找材料都会按它来'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // 题材/类型变了就重搜一次发现区,让偏好立刻生效
    unawaited(_loadTopics(_topics.isEmpty ? [_availableTopics.first] : _topics));
  }

  // (v2.13 移除)`_fitCount`:它只服务于折叠标题的副标题;现在区块直接展开,
  // 筛选提示在材料库自己的筛选行里,不再需要这个计数。

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // v3 批 8 去重 + 按目标优先排序(拍板 #1 后半);v2.23 补 url/title 级去重。
    var shelf = (_onlyFit && !_prefs.band.isAny)
        ? _shelf.where((s) {
            final c = s.coverage;
            return c == null || _prefs.band.contains(c);
          }).toList()
        : _shelf;
    // 两层去重:id 层(同一行被读两次/接口重复返回)是数据层兜底;url/title 层
    // 解决"同一篇从不同链接入库"—— 只做 id 层时材料库里会出现同一篇两张卡。
    shelf = MaterialLibrary.dedupeShelf(shelf);
    shelf = MaterialLibrary.dedupeBy(
      shelf,
      urlOf: (s) => s.url,
      titleOf: (s) => '${s.titleCn} ${s.title}',
    );
    if (_goalFirst && _inputPrefs.examGoals.isNotEmpty) {
      shelf = MaterialLibrary.rankForGoals(shelf, _inputPrefs.examGoals);
    }
    // 今日推荐:去重 + 黑名单过滤(C1-14)。
    //
    // 为什么过滤放在 build 而不是加载时:`_inputPrefs` 可能在本页内变(保存
    // 「我的需求」、以后从别处改完回来),每次重建都用最新屏蔽词,列表才不会
    // 出现"改了屏蔽词但推荐没变"的假筛选。
    final feed = _allowedFeed(
      MaterialLibrary.dedupeBy(
        _items,
        urlOf: (e) => e.link,
        titleOf: (e) => e.title,
      ),
    );
    final feedRail = feed.kept.take(8).toList();
    return SectionPrefsScope(
      notifier: _sectionPrefs,
      child: Scaffold(
        // v2.12(前端全面升级):去掉 AppBar —— 标题变成内容的一部分(大标题 + 一句话),
        // 右上的两个操作(区块管理 / 导入)跟着标题走。样图的发现页也是这种结构。
        body: SafeArea(
          bottom: false,
          child: ListView(
            // 记住滚动位置:收起/展开后不会跳回顶部
            key: const PageStorageKey<String>('material_center'),
            padding: Insets.page,
            children: [
            // ── v2.12 信息架构(用户 10/5 骂"分类逻辑是一坨屎")──
            //
            // 上一版我按自己的功能名把页面分成「找材料 / 在读 / 我的东西」三组
            // 分段切换 —— 用户看不出意义,因为**分类维度不是用户的任务**。
            // 这一版改成:
            //   ① 顶部**内容领域页签**(科学与技术/商业与政治/…,来自 MaterialTopic)——
            //      这就是样图里"分类逻辑清晰"的那种 tab,点一下直接按题材找;
            //   ② 去掉三组分段切换,所有区块**纵向杂志式排列**(每段形态不同:
            //      大图卡 → 横滑卡流 → 题材结果 → 网格 → 书架 → 横卡列表),
            //      靠形态差异和编号标题产生节奏,而不是靠"折叠横杠";
            //   ③ 每个区块自身的折叠/隐藏机制(v2.9)原样保留。
            // ① 页面标题 + 操作(替代 AppBar)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '材料中心',
                        style: AppFont.displayStyle.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '选一篇,今天就读它',
                        style: AppFont.metaStyle.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '区块管理(恢复被隐藏的功能区)',
                  onPressed: _showSectionManager,
                  icon: const Icon(Icons.view_agenda_outlined),
                ),
                IconButton(
                  tooltip: '导入材料(文件 / 图片 / 链接 / 粘贴)',
                  onPressed: _import,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),

            // ── v2.13(用户 2026-10-20 的结构要求)──
            // 「用户偏好需求 —— 提供材料(而不是现在的先给材料,"个性化找资源"在最下面),
            //   所有的材料都要基于用户的"个性化"提供」
            // 「只提供材料分类这种大功能分区,点进去后再提供单独的子分区」
            // 所以这一版:**需求卡置顶** → 今日精读 → **大分类网格**(点进二级页)
            // → 今日推荐 → 书架 → 材料库 → 更多找法(低频,收进弹层)。
            // 内容领域 tab、发现更多、按水平找都不再占首页 —— 它们在分类页/弹层里。

            // ② 我的需求(偏好前置:所有材料都按它来)
            AppStagger(index: 0, child: _buildNeedsHero(theme, muted)),

            // 01 今日精读:大图卡
            AppStagger(
              index: 1,
              child: _sectionBlock(
                title: '今日精读',
                indexLabel: '01',
                child: _buildDailyCard(theme, muted),
              ),
            ),

            // 02 按分类找材料:大分区网格(点进去才是子分区与列表)
            AppStagger(
              index: 2,
              child: _sectionBlock(
                title: '按分类找材料',
                indexLabel: '02',
                child: _buildCategoryGrid(theme),
              ),
            ),

            // 03 今日推荐:横滑封面卡
            AppStagger(
              index: 3,
              child: _sectionBlock(
                title: '今日推荐',
                indexLabel: '03',
                actionLabel: _probing ? '检测中…' : '检测可用源',
                onAction: _probing ? null : _probeAll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sourceStrip(theme),
                    const SizedBox(height: Gap.xs),
                    _sourceNote(theme, muted),
                    const SizedBox(height: Gap.sm),
                    // C1-14:黑名单过滤计数 —— 列表变短必须让用户知道是"自己
                    // 的屏蔽设置"造成的,否则会被当成"这个源没内容"。
                    if (feed.hasHidden) ...[
                      Text(
                        '已按你的屏蔽设置过滤 ${feed.hidden} 条',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: Gap.xs),
                    ],
                    if (_loadingItems)
                      const SkeletonLines(lines: 4, seed: 1)
                    else if (_error != null)
                      _errorCard(theme, muted)
                    else if (_items.isEmpty)
                      const AppEmpty(
                        icon: Icons.article_outlined,
                        title: '这个源暂时没有条目',
                        hint: '换一个源试试,或点「检测可用源」',
                      )
                    else if (feedRail.isEmpty)
                      // 有内容但全被屏蔽:给明确空态 + 可执行出口(不静默缩成空)
                      const AppEmpty(
                        icon: Icons.block_outlined,
                        title: '这个源的条目都被你的屏蔽设置过滤了',
                        hint: '到「我的 → 学习偏好」调整屏蔽词,或换一个内容源',
                      )
                    else ...[
                      SizedBox(
                        // v2.23:高度按"封面 + 三行文字 + 动作行"重算(原 186
                        // 放不下两行标题 + 难度行,长标题会把动作行挤出卡片);
                        // 文字缩放上限由卡片自己夹到 1.15,再大字号也不会溢出。
                        height: 240,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: feedRail.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: Gap.sm),
                          itemBuilder: (_, i) => SizedBox(
                            width: 236,
                            child: _buildFeedCard(theme, feedRail[i]),
                          ),
                        ),
                      ),
                      const SizedBox(height: Gap.xs),
                      // 口径必须写在卡外:卡上只放一句「预计」,否则容易被当成
                      // "实测覆盖率"(真正实测的只有今日精读那张大卡)。
                      Text(
                        '「预计」难度按来源/类型估算,不是实测认知率;点开卡片让软件'
                        '按你的词频分析一次,才有真实覆盖率。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 04 书架:真书架直接摆出来
            AppStagger(
              index: 4,
              child: _sectionBlock(
                title: '书架',
                indexLabel: '04',
                actionLabel: '去看看',
                onAction: _openBookshelf,
                child: _buildBookshelfPreview(theme, muted),
              ),
            ),

            // 05 材料库:横卡列表直接展示
            AppStagger(
              index: 5,
              child: _sectionBlock(
                title: '材料库',
                indexLabel: '05',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // v3 批 8:目标优先排序开关(有目标且库里有材料才出现)
                    if (_inputPrefs.examGoals.isNotEmpty && _shelf.isNotEmpty) ...[
                      Wrap(
                        spacing: Gap.xs,
                        runSpacing: Gap.xs,
                        alignment: WrapAlignment.end,
                        children: [
                          FilterChip(
                            label: Text(
                              '按目标优先·${_inputPrefs.examGoals.take(2).join('/')}',
                            ),
                            selected: _goalFirst,
                            onSelected: (v) => setState(() => _goalFirst = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: Gap.xs),
                    ],
                    if (!_prefs.band.isAny && _shelf.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilterChip(
                          label: const Text('只看符合'),
                          selected: _onlyFit,
                          onSelected: (v) => setState(() => _onlyFit = v),
                        ),
                      ),
                      const SizedBox(height: Gap.xs),
                    ],
                    if (_loadingShelf)
                      const SkeletonLines(lines: 3, seed: 2)
                    else if (shelf.isEmpty)
                      AppEmpty(
                        icon: Icons.library_books_outlined,
                        title: _onlyFit
                            ? '没有符合 ${_prefs.band.label} 的材料'
                            : '还没有材料',
                        hint: _onlyFit
                            ? '把「只看符合」取消,或换一个难度档'
                            : '从上面挑一份,或点右上角「+」导入',
                      )
                    else
                      for (final s in shelf) _buildShelfCard(theme, s),
                  ],
                ),
              ),
            ),

            // 06 更多找法(低频入口:发现更多 + 按水平找,收进一个弹层)
            AppStagger(index: 6, child: _buildMoreWaysCard(theme, muted)),

            const SizedBox(height: Gap.lg),
          ],
          ),
        ),
      ),
    );
  }

  /// **我的需求**(置顶卡,v2.13)。
  ///
  /// 用户 2026-10-20 的两条要求一起落在这里:
  /// ① 「用户偏好需求 —— 提供材料(而不是现在的先给材料,"个性化找资源"在最下面),
  ///    所有的材料都要基于用户的"个性化"提供」→ 这张卡必须在**所有材料之前**;
  /// ② 没设过偏好的人要给一句"先告诉我你要什么",而不是让他自己去找那个入口。
  Widget _buildNeedsHero(ThemeData theme, Color muted) {
    final cs = theme.colorScheme;
    final configured = !_prefs.band.isAny ||
        _prefs.kinds.isNotEmpty ||
        _prefs.genres.trim().isNotEmpty ||
        _prefs.extra.trim().isNotEmpty ||
        _inputPrefs.examGoals.isNotEmpty ||
        _inputPrefs.interests.isNotEmpty;
    return AppCard(
      variant: AppCardVariant.hero,
      onTap: _showPrefsSheet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(18),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: Icon(Icons.tune, size: 20, color: cs.primary),
              ),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text(
                  '我的需求',
                  style: AppFont.subheadStyle.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: _showPrefsSheet,
                child: Text(configured ? '调整' : '现在设置'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            configured
                ? _prefs.summary
                : '先花 10 秒告诉我想读什么(难度 / 来源 / 题材),'
                    '下面的材料都按它来 —— 不设也行,那就按通用推荐',
            style: AppFont.metaStyle.copyWith(color: muted, height: 1.5),
          ),
          const SizedBox(height: Gap.xs),
          // v3 批 2:目标/兴趣/每天时长与「输入」首页共用同一份偏好,
          // 这一页也要显示出来(用户会问"为什么这里和首页说的不一样")
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              if (_inputPrefs.examGoals.isNotEmpty)
                AppTag('目标 ${_inputPrefs.examGoals.join(' / ')}'),
              if (_inputPrefs.interests.isNotEmpty)
                AppTag('兴趣 ${_inputPrefs.interests.take(2).join(' / ')}'),
              if ((_inputPrefs.dailyMinutes ?? 0) > 0)
                AppTag('每天 ${_inputPrefs.dailyMinutes} 分钟'),
            ],
          ),
          const SizedBox(height: Gap.xs),
          // 难度档**在卡上直接可切**(v3 批 2:用户要求"难度要能自选、
          // 全 App 同步")—— 材料中心是主入口,不该藏在弹层里两层。
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              for (final band in MaterialBand.values)
                ChoiceChip(
                  label: Text(
                    band.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: _prefs.band == band,
                  onSelected: (v) => _quickSwitchBand(band),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _prefs.band.description,
            style: AppFont.tagStyle.copyWith(color: muted, height: 1.35),
          ),
          // 难度档辅助调整(v3 批 7 · P1-2):有真实数据支撑且建议档≠当前档时,
          // 在卡内多一行"建议 + 一键应用";数据不足时 `shouldShow=false` → 零占位。
          if (_bandAdvice != null)
            BandAdviceBanner(
              advice: _bandAdvice!,
              onApply: () => _applyBandAdvice(_bandAdvice!),
            ),
        ],
      ),
    );
  }

  /// 一键应用建议:写偏好(材料中心/输入首页/输出共用同一份)+ 重排材料库,
  /// 然后收起建议并给一句可逆提示 —— 用户随时能在「调整」里改回。
  Future<void> _applyBandAdvice(BandAdvice advice) async {
    final suggestion = advice.suggestion;
    if (suggestion == null) return;
    // 先收起建议:档位已经改到建议档,旧提示继续挂在卡上会显得"没生效"
    setState(() => _bandAdvice = null);
    await _quickSwitchBand(suggestion.band.materialBand);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已调到 ${suggestion.band.label},可随时在「调整」里改回'),
      ),
    );
  }

  /// 卡片上直接切难度档:存偏好 + 重新按档排序材料库(不重抓网络)。
  Future<void> _quickSwitchBand(MaterialBand band) async {
    final next = _prefs.copyWith(band: band);
    setState(() {
      _prefs = next;
      _inputPrefs = _inputPrefs.withBand(
        DifficultyBand.bandOf(band.name),
      );
      // 用户手动改过档后,旧建议就过期了 —— 立刻收起,避免"建议还在但档已变"
      _bandAdvice = null;
    });
    await next.save();
    // 全 App 同步:难度档也写进输入偏好层(材料中心/输入首页/输出共用)
    await _inputPrefs.saveBand(DifficultyBand.bandOf(band.name));
    if (mounted) await _loadShelf();
  }

  /// **按分类找材料**:大分区网格(点进去才是子分区与列表,v2.13)
  ///
  /// v3(批 1,2026-11-01):每个题材从"色块 + Material 图标"换成**自绘几何身份
  /// 图形**(`DomainGraphic`)。用户截图里那排小图标块是他反复说"简陋/前端没变"
  /// 的直接来源 —— 现在 13 个领域各有自己的几何语言(轨道/柱线/脉搏/拱门/航线/
  /// 字母/考卷/公式/报头/书脊/声波/便签),分类墙才像"图形墙"。
  Widget _buildCategoryGrid(ThemeData theme) {
    final topics = _availableTopics;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Gap.xs,
        crossAxisSpacing: Gap.xs,
        // 比 v2.13 高 20:给身份图形留出主位(图形占卡片上半,文字在下方)
        mainAxisExtent: 152,
      ),
      itemCount: topics.length,
      itemBuilder: (_, i) {
        final t = topics[i];
        return MaterialTopicCard(
          topic: t,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MaterialCategoryScreen(topic: t),
            ),
          ),
        );
      },
    );
  }

  /// 低频入口:AI 按需求找 + 按难度发现更多(收进弹层,首页不再堆内容)
  Widget _buildMoreWaysCard(ThemeData theme, Color muted) {
    final cs = theme.colorScheme;
    return AppCard(
      onTap: _showMoreWays,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(14),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Icon(Icons.travel_explore, size: 20, color: cs.primary),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '还有更多找法',
                  style: AppFont.subheadStyle.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '用中文说需求让 AI 去找 · 按难度发现更多',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.metaStyle.copyWith(color: muted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: cs.outline),
        ],
      ),
    );
  }

  /// 更多找法弹层:发现更多 + 按水平找(内容不删,只是不再占首页)
  Future<void> _showMoreWays() async {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: Insets.page,
          children: [
            // v3 批 2:"AI 按需求找材料"—— 需求→检索计划→多源抓取→本地算难度。
            // 放在弹层最上面:它是"按需求提供材料"的主路径,题材检索是补充。
            AppCard(
              variant: AppCardVariant.accent,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MaterialDiscoverScreen(),
                  ),
                );
              },
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 按需求找材料',
                          style: AppFont.subheadStyle.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '用中文说想要什么：公开源 + DeepSeek 官方搜索，抓回正文算真实难度',
                          style: AppFont.tagStyle.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.md),
            Text(
              '按你的水平找材料',
              style: AppFont.headingStyle.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: Gap.xs),
            _buildAiDiscoverGrid(theme),
            const SizedBox(height: Gap.md),
            Text(
              '发现更多(按题材检索)',
              style: AppFont.headingStyle.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: Gap.xs),
            _buildDiscover(theme, muted),
            const SizedBox(height: Gap.lg),
          ],
        ),
      ),
    );
  }

  /// 一个"区块" = 编号标题 + **内容直接展开**(没有折叠)。
  ///
  /// v2.13:用户 10/23 的原话是"到底为什么还是'清一色的竖列展开收起'这种烂到没边的
  /// 交互" —— 上一版每个区块都是 `CollapsibleSection`(一排"标题 + 箭头",内容要点开),
  /// 他只是看到换了个颜色。现在区块默认全展开,标题只负责分段;
  /// 「隐藏区块」仍可在顶部菜单里做(低频操作,不该占主流程)。
  Widget _sectionBlock({
    required String title,
    required String indexLabel,
    required Widget child,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: title,
          indexLabel: indexLabel,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
        child,
      ],
    );
  }

  /// 区块管理(v2.9):被隐藏的功能区在这里恢复 —— 隐藏不是"删掉找不回来"。
  Future<void> _showSectionManager() async {
    const all = [
      ('prefs', '个性化找资源', '难度 / 类型 / 题材 / 补充需求'),
      ('daily', '今日精读', '每天一篇大卡'),
      ('discover', '发现更多', '题材检索与结果'),
      ('byLevel', '按你的水平找材料', '分类入口'),
      ('feed', '今日推荐', '内容源最新条目'),
      ('shelf', '材料库', '你收藏与导入的材料'),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
                child: Text('区块管理',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
                child: Text(
                  '关掉不想天天看到的区块,页面就短了 —— 这里是开关,随时能开回来。',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
              ),
              for (final s in all)
                SwitchListTile(
                  dense: true,
                  value: !_sectionPrefs.isHidden(s.$1),
                  title: Text(s.$2, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(s.$3, style: const TextStyle(fontSize: 11)),
                  onChanged: (on) {
                    on ? _sectionPrefs.show(s.$1) : _sectionPrefs.hide(s.$1);
                    setSheet(() {});
                  },
                ),
              const SizedBox(height: Gap.xs),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────── ⓪ 个性化找资源 ─────────────────

  // (v2.13 移除)`_buildPrefsCard`:偏好内容改为**置顶的需求卡**
  // (`_buildNeedsHero`)+ 独立的「调整」弹层,不再作为第 7 个区块出现 ——
  // 用户明确说"个性化找资源不该在最下面,材料要基于偏好提供"。

  // ───────────────── ① 今日精读大卡(v2.8) ─────────────────

  Widget _buildDailyCard(ThemeData theme, Color muted) {
    final item = _daily;
    final a = _dailyAnalysis;
    final kind = MaterialLevel.kindOfSource(_sourceId);
    final lv = a == null
        ? MaterialLevel.fallbackForKind(kind)
        : MaterialLevel.of(a.cefr, kind: kind);
    final accent = MaterialLevel.accentOf(_sourceId);
    // v2.23(C1-17):没有正文分析时不再"什么难度都不显示",用源元数据给预计
    // 区间;有分析(`_dailyAnalysis`)的卡继续显示真实认知率 —— 两者绝不混用。
    final estimate = MaterialLibrary.estimateDifficulty(
      sourceId: _sourceId,
      kind: kind,
    );

    if (item == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Gap.xs),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('今日精读',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: Gap.sm),
              if (_loadingItems || _dailyLoading)
                // 加载态与其它区块统一成骨架屏(此前这里是 AppLoading:
                // 同一页出现两种骨架形状,数据到达时布局会跳)。
                const SkeletonLines(lines: 5, seed: 0)
              else
                Text('这个源暂时没有可精读的条目 —— 换一个源,或看上面的「发现更多」',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ),
        ),
      );
    }

    final cn = _titleCnOf(item.title);
    final sentences = a == null
        ? 0
        : MaterialLevel.sentenceCount(item.summary.isEmpty ? item.title : item.summary);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: _openDaily,
        // v2.11:整页唯一一张**主角卡**(变体 hero:大圆角 + 浮起 + 轻微染底)。
        // 为什么只给这一张:体检查出全页只有一处大图,其余封面都在 76~88px ——
        // 没有大小对比,眼睛就没有落点。主角卡只允许一屏一个,多了就变"图墙"。
        variant: AppCardVariant.hero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MaterialCover(
              seed: item.title,
              kind: kind,
              imageUrl: item.imageUrl,
              height: 186,
              radius: 0,
              levelLabel: 'Lv$lv',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _chip(theme, '今日精读', accent: true),
                      const SizedBox(width: Gap.xxs + 2),
                      _chip(theme, _kindLabel(kind)),
                      const SizedBox(width: Gap.xxs + 2),
                      _chip(theme, 'Lv$lv'),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (cn.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      cn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: muted, height: 1.3),
                    ),
                  ],
                  const SizedBox(height: Gap.xs),
                  // 元信息:认知率 + 时长 + 词数 + 句数 + 口音
                  // (参考软件只有"难度 + 词数"两项 —— 这几项是我们多给的)
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: 4,
                    children: [
                      if (a != null)
                        _meta(
                          theme,
                          Icons.speed,
                          '已知 ${(a.knownTokenRatio * 100).toStringAsFixed(0)}%',
                        ),
                      // 没有本地分析 → 显示"预计"区间,并明确它不是实测覆盖率
                      if (a == null)
                        _meta(theme, Icons.speed, estimate.label),
                      if (a != null)
                        _meta(theme, Icons.timer_outlined, '约 ${a.estMinutes} 分钟'),
                      if (a != null && a.wordCount > 0)
                        _meta(theme, Icons.notes, '${a.wordCount} 词'),
                      if (sentences > 0)
                        _meta(theme, Icons.format_quote, '摘要约 $sentences 句'),
                      if (accent.isNotEmpty)
                        _meta(theme, Icons.volume_up_outlined, accent),
                    ],
                  ),
                  if (a != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${a.cefr} · ${MaterialLevel.matchHint(a.knownTokenRatio)}'
                      '${a.tooHard ? ' · 建议只精读前几段' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: a.tooHard
                            ? AppTheme.warningColor(context)
                            : theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  // 估算口径必须原样写给用户看:这是"预计",不是算出来的认知率
                  if (a == null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${estimate.basis} · 开始阅读后按你的词频算真实认知率',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: Gap.sm),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: FilledButton.icon(
                            onPressed: _dailyLoading ? null : _openDaily,
                            icon: const Icon(Icons.play_arrow_rounded, size: 20),
                            label: Text(_dailyLoading ? '正在分析…' : '开始阅读'),
                          ),
                        ),
                      ),
                      const SizedBox(width: Gap.xs),
                      IconButton.outlined(
                        tooltip: '换一篇',
                        onPressed: _loadingItems
                            ? null
                            : () {
                                // 「换一篇」也要绕开屏蔽词:从过滤后的条目里取
                                // 下一篇,不能换成一篇用户明确屏蔽掉的
                                FeedItem? next;
                                for (final f in _allowedFeed(_items).kept) {
                                  if (f.link != item.link) {
                                    next = f;
                                    break;
                                  }
                                }
                                if (next != null) _loadDaily(next);
                              },
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton.outlined(
                        tooltip: '原文链接',
                        onPressed: () => _openExternal(item.link),
                        icon: const Icon(Icons.link),
                      ),
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

  String _kindLabel(String kind) => switch (kind) {
        'book' => '公版书',
        'paper' => '论文',
        'news' => '外刊',
        'podcast' => '播客',
        'wiki' => '百科',
        _ => '文章',
      };

  Widget _chip(ThemeData theme, String text, {bool accent = false}) {
    final color =
        accent ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(accent ? 22 : 16),
        borderRadius: BorderRadius.circular(Radii.control - 4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String text) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: muted),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: muted)),
      ],
    );
  }

  // ───────────────── ② 发现更多 ─────────────────

  Widget _buildDiscover(ThemeData theme, Color muted) {
    final selected = _selectedTopics;
    // C1-14:发现列表也遵守黑名单;先按 url/title 去重(不同题材的检索词
    // 经常命中同一篇,旧实现只在"同一次多题材合并"里按 URL 去重)。
    final hits = _allowedHits(
      MaterialLibrary.dedupeBy(
        _topicHits,
        urlOf: (h) => h.url,
        titleOf: (h) => h.title,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 题材 chip:**可多选**(用户 3(3) 条);选中的一起搜、结果合并去重
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in _availableTopics)
                Padding(
                  padding: const EdgeInsets.only(right: Gap.xs),
                  child: FilterChip(
                    avatar: Icon(t.icon, size: 15),
                    label: Text(t.label),
                    selected: selected.contains(t.id),
                    onSelected: (on) {
                      final next = {...selected};
                      on ? next.add(t.id) : next.remove(t.id);
                      setState(() => _selectedTopics = next);
                    },
                    // 自定义分区:长按可删(内置的不给删)
                    onDeleted: t.id.startsWith('custom_')
                        ? () async {
                            await CustomTopics.remove(t.id);
                            _reloadTopics();
                            if (!mounted) return;
                            final next = {...selected}..remove(t.id);
                            setState(() => _selectedTopics = next);
                          }
                        : null,
                    deleteIcon: const Icon(Icons.close, size: 14),
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              // 加一个自己的分区
              ActionChip(
                avatar: const Icon(Icons.add, size: 15),
                label: const Text('自定义分区', style: TextStyle(fontSize: 12)),
                onPressed: _addCustomTopic,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.xs),
        // 操作行:搜选中的 / 清空选择
        Row(
          children: [
            Expanded(
              child: Text(
                selected.isEmpty
                    ? '选一个或多个题材(可多选,也可以自己加分区)'
                    : '已选 ${selected.length} 个题材'
                        '${_topicHits.isEmpty ? '' : ' · ${_topicHits.length} 篇'}',
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
            if (selected.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                ),
                onPressed: () => setState(() => _selectedTopics = {}),
                child: const Text('清空', style: TextStyle(fontSize: 12)),
              ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(fontSize: 12.5),
              ),
              onPressed: _topicLoading || selected.isEmpty
                  ? null
                  : () {
                      final chosen = [
                        for (final t in _availableTopics)
                          if (selected.contains(t.id)) t,
                      ];
                      if (chosen.isNotEmpty) _loadTopics(chosen);
                    },
              child: Text(_topicLoading ? '检索中…' : '开始找'),
            ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        // 检索过程:流式时间线(用户第 6(4) 条;v2.9 换成全 App 共用组件)
        if (_topicEvents.isNotEmpty)
          AiWaitingTimeline(
            steps: [
              for (final e in _topicEvents)
                AiStep(
                  label: e.label,
                  detail: e.total > 0 && e.done > 0
                      ? '${e.done}/${e.total}'
                      : null,
                  state: switch (e.stage) {
                    SearchStage.done => AiStepState.done,
                    SearchStage.sourceFailed => AiStepState.failed,
                    _ => AiStepState.running,
                  },
                ),
            ],
            running: _topicLoading,
          ),
        if (_topicNote.isNotEmpty) ...[
          const SizedBox(height: Gap.xs),
          Text(_topicNote,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: muted, fontSize: 11, height: 1.4)),
        ],
        // 黑名单过滤计数:与今日推荐同一句文案(用户不需要记两套说法)
        if (hits.hasHidden) ...[
          const SizedBox(height: Gap.xs),
          Text(
            '已按你的屏蔽设置过滤 ${hits.hidden} 条',
            style: theme.textTheme.bodySmall?.copyWith(
              color: muted,
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: Gap.xs),
        if (_topicLoading && _topicHits.isEmpty)
          // 方案 B:骨架屏(与结果卡片同形状),不再是转圈
          const SkeletonLines(lines: 6, seed: 3)
        else if (_topicHits.isEmpty && _topicLoaded)
          AppEmpty(
            icon: Icons.search_off,
            title: '这个题材这次没找到',
            hint: '换个题材,或加一个自己的分区;也可以在「个性化找资源」里写清你想要什么',
          )
        else if (hits.kept.isEmpty)
          // 找到了但全被屏蔽:明确说是"你的设置"而不是"没内容"
          AppEmpty(
            icon: Icons.block_outlined,
            title: '找到的 ${hits.hidden} 篇都被你的屏蔽设置过滤了',
            hint: '到「我的 → 学习偏好」调整屏蔽词,或换个题材再找',
          )
        else
          for (var i = 0; i < hits.kept.length; i++)
            AppStagger(
              index: i,
              child: _buildDiscoverCard(theme, hits.kept[i]),
            ),
      ],
    );
  }

  /// 书架(v2.10,用户 10/4 第 4/5 条):材料中心里的一块,点开是独立书架页
  ///
  /// v2.13:去掉 `_shelfCount` —— 区块不再折叠,标题副标题里的"架上 N 本"没了,
  /// 书架上是否为空直接看得到(真书架 + 空位)。
  List<Map<String, Object?>> _bookshelf = const [];

  Future<void> _loadBookshelf() async {
    try {
      final rows = await DatabaseService.bookshelfItems();
      if (!mounted) return;
      setState(() {
        _bookshelf = rows;
      });
    } catch (e) {
      debugPrint('读书架失败: $e');
    }
  }

  Future<void> _openBookshelf() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BookshelfScreen()),
    );
    if (!mounted) return;
    await _loadBookshelf();
    await _loadShelf();
  }

  /// 材料中心里的书架预览(v2.11 换成**真书架**)。
  ///
  /// 旧实现是自己另写的一条 44px 宽色块书脊 —— 没有搁板、没有厚度、没有空书位,
  /// 而隔壁 `bookshelf_view.dart` 里已经有一套用 6 个 CustomPainter 画出来的真书架
  /// (深胡桃木搁板 + 立着的书脊 + 虚线空位),**全 App 只被用过 1 次**。
  /// 用户 10/4 的原话是"书架的 ui 展示要丰富,最好真的像一个书架…等待用户放满",
  /// 所以这里直接复用那套:材料中心也能看到"架子还有几个空位"。
  ///
  /// 参数取舍(为什么这样传):
  /// - `booksPerShelf: 4`:材料中心这一块是**预览**,不让它撑得过高;
  /// - `showStats: false`:统计条已经在独立书架页给了,这里只留"架子"本身;
  /// - `onTapEmptySlot` / `emptyAction` → 都指向书架页(空书架时它就是引导按钮)。
  Widget _buildBookshelfPreview(ThemeData theme, Color muted) {
    final books = [
      for (final r in _bookshelf) BookshelfBook.fromRow(r),
    ];
    return AppCard(
      onTap: _openBookshelf,
      variant: AppCardVariant.compact,
      child: BookshelfView(
        books: books,
        booksPerShelf: 4,
        showStats: false,
        onTapBook: (_) => _openBookshelf(),
        onTapEmptySlot: _openBookshelf,
        emptyHint: '读到想留着的材料,在阅读器里点「加入书架」;\n退出时会问你一句「放进书架?」',
        emptyAction: FilledButton.tonalIcon(
          onPressed: _openBookshelf,
          icon: const Icon(Icons.auto_stories_outlined, size: 16),
          label: const Text('去挑一本'),
        ),
      ),
    );
  }

  /// v2.9 修(用户截图指出的问题):上一版把「软件内阅读」做成默认尺寸的大按钮
  /// 塞进一行,结果**两个按钮超出卡片宽度**、右边那个被裁成「原」字,
  /// 标题与元信息也被挤到截断。现在:
  /// - 卡片整体可点(读到阅读器),不再靠一个占半行的大按钮;
  /// - 两个动作都是**紧凑小按钮** + `Wrap`,窄屏会自动换行,**永远不会溢出**;
  /// - 元信息独立一行,不吃按钮的宽度。
  Widget _buildDiscoverCard(ThemeData theme, OriginalHit hit) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final kind = MaterialLevel.kindOfSource(hit.sourceId);
    final lv = MaterialLevel.fallbackForKind(kind);
    final cn = _titleCnOf(hit.title);
    final accent = MaterialLevel.accentOf(hit.sourceId);
    final source = MaterialSourceService.sourceOf(hit.sourceId);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: AppCard(
        padding: const EdgeInsets.all(Gap.sm),
        onTap: () => _openHit(hit),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MaterialCover(
                  seed: hit.title,
                  kind: kind,
                  imageUrl: hit.imageUrl,
                  width: 78,
                  height: 78,
                  radius: Radii.control,
                  levelLabel: 'Lv$lv',
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 14.5,
                          height: 1.28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (cn.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          cn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted, height: 1.25),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        [
                          source?.label ?? '',
                          if (hit.note.trim().isNotEmpty) hit.note.trim(),
                          if (accent.isNotEmpty) accent,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xs),
            // 动作:紧凑 + Wrap —— 窄屏换行而不是溢出(上一版就是在这溢出)
            Wrap(
              spacing: Gap.xs,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontSize: 12.5),
                  ),
                  onPressed: () => _openHit(hit),
                  child: const Text('软件内阅读'),
                ),
                if (hit.url.trim().isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                    onPressed: () => _openExternal(hit.url),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('原文'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────── ③ 今日推荐(源最新条目) ─────────────────

  Widget _sourceStrip(ThemeData theme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final s in MaterialSourceService.sources)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _sourceChip(context, theme, s),
            ),
        ],
      ),
    );
  }

  Widget _sourceChip(BuildContext context, ThemeData theme, MaterialSource s) {
    final health = _health[s.id];
    final measured = MaterialSourceService.measuredReachable.contains(s.id);
    final IconData? mark = health == null
        ? (measured ? Icons.check_circle_outline : null)
        : (health.ok ? Icons.check_circle : Icons.error_outline);
    final markColor = health == null
        ? theme.colorScheme.onSurfaceVariant
        : (health.ok
              ? AppTheme.successColor(context)
              : AppTheme.warningColor(context));
    final preferred = _prefs.kinds.isEmpty || _prefs.kinds.contains(s.kind);
    return ChoiceChip(
      avatar: mark == null ? null : Icon(mark, size: 15, color: markColor),
      label: Text(preferred ? s.label : '${s.label}(非偏好)'),
      labelStyle: health != null && !health.ok
          ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
          : null,
      selected: _sourceId == s.id,
      onSelected: (_) {
        setState(() => _sourceId = s.id);
        _loadItems();
      },
    );
  }

  Widget _sourceNote(ThemeData theme, Color muted) {
    final s = MaterialSourceService.sourceOf(_sourceId);
    if (s == null) return const SizedBox.shrink();
    final health = _health[s.id];
    final ok = health?.ok == true;
    final dot = health == null
        ? theme.colorScheme.outlineVariant
        : (ok
              ? AppTheme.successColor(context)
              : AppTheme.warningColor(context));
    final now = DateTime.now();
    final status = health == null
        ? (MaterialSourceService.measuredReachable.contains(s.id)
            ? '实测可用(2026-09 中国大陆):这个源一直比较稳'
            : '还没试过这个源 —— 拉不到就换一个')
        : '${health.label(now)}'
            '${ok ? '' : ' —— ${health.message ?? '未知原因'}'}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: Gap.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.description,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              const SizedBox(height: 2),
              Text(
                status,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: health != null && !ok
                      ? AppTheme.warningColor(context)
                      : muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorCard(ThemeData theme, Color muted) {
    final s = MaterialSourceService.sourceOf(_sourceId);
    final label = s?.label ?? _sourceId;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_off, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text('「$label」这次没拉到',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              FilledButton.tonalIcon(
                onPressed: _loadItems,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(_error!,
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: Gap.xxs),
          Text(
            '内容源都在境外,部分网络会连不上 —— 这不是 App 坏了。'
            '换个源试试,或看上面的「发现更多」(题材检索会多路并行)。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: muted, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 「今日推荐」的一张卡(v2.11 改成**横滑卡**的竖版式)。
  ///
  /// 旧版式:76×76 封面 + 右边三行文字(标题/中文标题/一行小按钮)——
  /// 和材料库卡、发现卡几乎一模一样,一屏六张全同宽同高,这就是用户说的
  /// "清一色的竖列功能块"。
  /// 新版式:卡片宽 236,上半是**通栏 120 高的封面**(有真图时一眼看到原图),
  /// 下半是标题 + 中文标题 + 预计难度 + 一行动作。横向滑动看更多。
  ///
  /// 动作保持不变(点卡 = 直接打开阅读,「设为今日精读」仍是卡上小按钮)——
  /// 用户 10/4 明确要求过"点卡片要真的打开",这条不能因为改版式而丢。
  Widget _buildFeedCard(ThemeData theme, FeedItem item) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final kind = MaterialLevel.kindOfSource(_sourceId);
    final cn = _titleCnOf(item.title);
    // C1-17:feed 卡没有本地分析,给"预计难度区间"(口径见 estimateDifficulty);
    // 卡片高度是定死的,这一行直接占掉原来"中文标题占位行"下方的空隙。
    final estimate = MaterialLibrary.estimateDifficulty(
      sourceId: _sourceId,
      kind: kind,
    );
    // 卡片高度定死(横向列表需要确定高度),系统字号放大到 2× 时三行文字 +
    // 动作行必然溢出。这里把**这张卡**的文字缩放夹到 1.15:不影响全局无障碍
    // 设置,也保住卡片不出现黄黑条/被裁掉动作按钮。
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: AppCard(
      variant: AppCardVariant.compact,
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      // v2.10 修(用户 10/4:"'今日推荐'的文章点了后没反应"):
      // 旧实现把点击做成了"设为今日精读"(只换上面那张大卡),用户当然觉得没反应。
      // 现在**点卡片 = 直接打开这篇文章阅读**(这才是点下去该发生的事),
      // 「设为今日精读」降级成卡片下方的小按钮。
      onTap: () => _openFeedItem(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MaterialCover(
            seed: item.title,
            kind: kind,
            imageUrl: item.imageUrl,
            width: double.infinity,
            height: 120,
            radius: 0,
          ),
          // 文字区:**必须用 Expanded 包住**,不能直接塞进 Column。
          //
          // 为什么(这是个真坑,不是防御性多余代码):这张卡的高度是由外层
          // `SizedBox(height: 240)` 定死的,而下面结构里需要"把动作行压到卡底"。
          // 如果文字区用 `Column` + `Spacer`,一旦某行行高比估算的高
          //(系统字号放大、字体回退、中文行高差异),整列就会超出 240 →
          // **BOTTOM OVERFLOWED** 黄黑条(v2.9 就栽过同类问题)。
          // `Expanded` 会把它拿到的高度**夹紧**给子列,`Spacer` 再吸收余量:
          // 有余量时贴底,不够时由子列自己裁剪/省略,永不溢出。
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title.isEmpty ? '(无标题)' : item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 13.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  // 中文标题(没有就占位一行小字,免得卡片高度在两张卡之间跳动)
                  Text(cn.isEmpty ? ' ' : cn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, fontSize: 11, height: 1.3)),
                  const SizedBox(height: 2),
                  // 预计难度区间(不是实测覆盖率):完整口径在区块脚注与
                  // tooltip 里,卡片内只放一句"预计",避免被误读成精确值。
                  Tooltip(
                    message: estimate.basis,
                    child: Row(
                      children: [
                        Icon(Icons.speed, size: 12, color: muted),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            estimate.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // 动作行:窄卡里两个按钮必须能换行(Wrap),否则又会出现
                  // v2.9 那次"按钮被裁成『原』字"的事故
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: 0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (item.published != null)
                        _meta(theme, Icons.schedule, item.published!),
                      // 设成今日精读(次要动作,小按钮)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 22),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          setState(() => _daily = item);
                          _loadDaily(item);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已设为今日精读(在上面的「今日精读」卡里)'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.local_fire_department_outlined,
                            size: 13),
                        label: const Text('设为精读',
                            style: TextStyle(fontSize: 11)),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 22),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _openExternal(item.link),
                        child: const Text('原文链接',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ───────────────── ④ 分类入口 ─────────────────

  /// 「按你的水平找材料」的分类入口(v2.11 改成**真网格**)。
  ///
  /// 体检结论:这里以前是"手写 Row + Expanded 拼出的两列",而全库 `GridView`
  /// **0 处**、真正能称得上网格的只有这一块 —— 于是整页看起来就是"竖列 + 一行行方块"。
  /// 现在改成 `GridView.count`(shrinkWrap + NeverScrollable,嵌在外层 ListView 里),
  /// 单元复用 `AppActionTile(style: grid)` —— 全 App 只有一份"网格方块"的实现。
  ///
  /// ⚠️ 窄屏安全:`childAspectRatio` 特意给得偏矮(1.35),中文两个字的标签
  /// (如「碎片文章」)在 320dp 宽屏上不会把文字挤出格子。
  Widget _buildAiDiscoverGrid(ThemeData theme) {
    final cats = AppConstants.learningCategories;
    const icons = <String, IconData>{
      '教材': Icons.school,
      '书籍': Icons.menu_book,
      '外刊': Icons.article,
      '碎片文章': Icons.auto_stories,
      '其他': Icons.folder,
    };
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Gap.xs,
      crossAxisSpacing: Gap.xs,
      childAspectRatio: 1.35,
      children: [
        for (final c in cats)
          AppActionTile(
            style: AppActionTileStyle.grid,
            icon: icons[c] ?? Icons.folder,
            title: c,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CategoryMaterialScreen(category: c),
              ),
            ),
          ),
      ],
    );
  }

  // ───────────────── ⑤ 材料库卡片 ─────────────────

  /// 材料库的一张卡(v2.12:改成**横卡**形态 —— 左文右图 + 竖排 Lv 徽标)。
  ///
  /// 为什么换形态:旧版是"76 小图 + 标题 + 三行小字 + 两个按钮"的竖排卡,
  /// 和今日推荐/发现卡几乎一样(用户说的"清一色")。用户给的样图里,
  /// 发现页是**左文右图**的横卡:标题占左侧、日期/标签在左下、右侧方形缩略图 +
  /// 竖排 Lv —— 这种排布扫读效率最高(文字左边对齐成一条线)。
  /// 同时**去掉卡上的两个按钮**:整卡可点就够了,按钮只会让卡片变高、变吵。
  Widget _buildShelfCard(ThemeData theme, ShelfItem s) {
    final cov = s.coverage;
    final fit = cov == null ? '' : _prefs.band.fitLabel(cov);
    final lv = MaterialLevel.of(s.cefr, kind: s.kind);
    final metaText = [
      '${s.wordCount} 词',
      '约 ${s.estMinutes} 分钟',
    ].join(' · ');
    return AppWideCard(
      title: s.title,
      subtitle: metaText,
      dateText: s.progressLabel,
      tags: [
        if (cov != null) AppTag('已知 ${(cov * 100).toStringAsFixed(0)}%'),
        if (fit.isNotEmpty)
          AppTag(
            fit,
            tone: fit.startsWith('符合')
                ? AppTagTone.primary
                : AppTagTone.neutral,
          ),
        if (s.pickedWords > 0) AppTag('已收 ${s.pickedWords} 词'),
      ],
      imageUrl: MaterialSourceService.coverFor(
        storedCoverUrl: s.coverUrl,
        sourceUrl: s.url,
      ),
      seed: s.title,
      kind: s.kind,
      level: '$lv',
      onTap: () => _openReader(s.id),
      trailing: s.url.trim().isEmpty
          ? null
          : IconButton(
              tooltip: '打开原文链接',
              onPressed: () => _openExternal(s.url),
              icon: const Icon(Icons.open_in_new, size: 16),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
    );
  }
}

/// 词频表在使用前必须先加载(分析依赖它);这里给一个统一的预热入口,
/// 让调用方(材料中心/阅读器)在打开前调用一次即可。
Future<void> warmUpWordFrequency() => WordFrequency.ensureLoaded();

/// 难度档「软件辅助调整」建议条(v3 批 7 · P1-2)。
///
/// 用户 11/01 批注第 7 条要求「难度档用户自选 + 全 App 同步 + **软件辅助调整**」;
/// 前两项已在 v2.14 做完,这条把纯函数 `suggestBand` 的结论真的接到界面上:
/// - **不弹窗、不强制**:只在「我的需求」区多一行;点按钮才真的改档,
///   不点就什么都不变(与"用户自选"不冲突 —— 软件只给依据,决定权仍在人);
/// - **不占位**:数据不足/信号冲突/档位=不限时返回零尺寸,不留空行;
/// - **依据真实**:文案里的读完率/查词密度/正确率全部来自最近真实使用数据。
///
/// 为什么做成公开 widget 而不是两屏各写一个私有方法:
/// 1. 输入首页与材料中心的这条建议必须**一字不差**(口径分叉 = 用户困惑);
/// 2. widget test 可以直接注入假 [BandAdvice] 渲染"显示/不显示"两种情况,
///    不必启动 Hive/SQLite(数据读取在 `loadBandAdvice` 里,与渲染解耦)。
class BandAdviceBanner extends StatelessWidget {
  /// 展示用建议(含当前档/建议档/文案);`shouldShow=false` 时零尺寸
  final BandAdvice advice;

  /// 用户点「调到 i+X」时调用(应用动作由所在页面负责:写偏好 + 刷新)
  final VoidCallback onApply;

  const BandAdviceBanner({
    super.key,
    required this.advice,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    // 没有建议就是零尺寸:SizedBox.shrink 不参与布局,不会在卡内留空行
    if (!advice.shouldShow) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final line = advice.line;
    final action = advice.actionLabel;
    if (line == null || action == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xxs),
        decoration: BoxDecoration(
          // 用主色低透明度做"系统提示"底色:明暗两套主题都成立,不硬编码颜色
          color: cs.primary.withAlpha(12),
          borderRadius: Radii.controlRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, size: 15, color: cs.primary),
                const SizedBox(width: Gap.xxs),
                Expanded(
                  child: Text(
                    line,
                    style: AppFont.tagStyle.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onApply,
                child: Text(
                  action,
                  style: AppFont.tagStyle.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
