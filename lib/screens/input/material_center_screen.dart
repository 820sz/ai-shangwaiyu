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
import '../../widgets/material_cover.dart';
import '../../widgets/waiting.dart';
import 'category_material_screen.dart';
import 'bookshelf_screen.dart';
import 'material_import_flow.dart';
import 'material_reader_screen.dart';
import 'widgets/material_preview_dialog.dart';

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
  bool _onlyFit = false;
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

  /// 当前显示的功能分组(v2.11 材料中心的信息架构)。
  ///
  /// 0 = 找材料(个性化偏好 + 题材发现 + 按水平找)、
  /// 1 = 在读(书架 + 今日推荐)、2 = 我的东西(材料库)。
  /// 为什么用"分组切换"而不是继续 7 段竖排:用户 10/5 的原话是
  /// "材料中心更是没有欲望的竖列呈现" —— 7 个同形标题行首尾相连,
  /// 首屏全是横杠。分组后首屏只见"主角卡 + 一组内容",每块的空间也变大了。
  /// 注意:分组**不是把功能藏起来** —— 切一下就全在,而且每个区块自身的
  /// 折叠/隐藏机制(v2.9)原样保留。
  int _group = 0;

  /// 分组切换器:一枚 `SegmentedButton`(Material 3,自带选中态与动效)
  Widget _buildGroupSwitcher(ThemeData theme) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(
          value: 0,
          icon: Icon(Icons.travel_explore_outlined, size: 16),
          label: Text('找材料'),
        ),
        ButtonSegment(
          value: 1,
          icon: Icon(Icons.auto_stories_outlined, size: 16),
          label: Text('在读'),
        ),
        ButtonSegment(
          value: 2,
          icon: Icon(Icons.library_books_outlined, size: 16),
          label: Text('我的东西'),
        ),
      ],
      selected: {_group},
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: AppFont.caption, fontWeight: FontWeight.w600),
        ),
      ),
      onSelectionChanged: (s) => setState(() => _group = s.first),
    );
  }

  @override
  void initState() {
    super.initState();
    _prefs = MaterialPrefs.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _model = LearnerModelStore.load();
      _health = MaterialSourceStatus.loadAll();
      _sourceId = MaterialSourceStatus.preferredSourceId(
        knownIds: [for (final s in MaterialSourceService.sources) s.id],
        fallback: MaterialSourceService.defaultSourceId,
        all: _health,
      );
      _loadShelf();
      _loadItems();
      _loadTopics([_availableTopics.first]);
      // 已有的材料里还没中文名的,后台补齐(用户为此提过两次)
      unawaited(_backfillShelfTitles());
    });
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
      final items = await _service.listItems(_sourceId, limit: 12);
      await MaterialSourceStatus.recordOk(_sourceId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loadingItems = false;
        _health = MaterialSourceStatus.loadAll();
      });
      // 今日精读:取第一条做"预分析"(抓正文 + 本地难度),失败就退回不带难度的卡
      unawaited(_loadDaily(items.isEmpty ? null : items.first));
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
    if (!mounted) return;
    _model = LearnerModelStore.load();
    await _loadShelf();
    unawaited(_backfillShelfTitles());
  }

  /// 打开今日精读(大卡按钮)
  Future<void> _openDaily() async {
    final item = _daily;
    if (item == null) return;
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
    if (!mounted) return;
    _model = LearnerModelStore.load();
    await _loadShelf();
  }

  /// 打开一条发现结果(软件内阅读)
  Future<void> _openHit(OriginalHit hit) async {
    await MaterialImportFlow.openHitWithProgress(
      context,
      hit: hit,
      model: _model,
    );
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
    try {
      final ok = await launchExternalUrl(url);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打不开这个链接:$url')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开链接失败:$e')),
      );
    }
  }

  Future<void> _setBand(MaterialBand band) async {
    setState(() => _prefs = _prefs.copyWith(band: band));
    await _prefs.save();
    if (!mounted) return;
    await _loadShelf();
  }

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
    await _loadShelf();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('偏好已保存 —— 下次找材料会按它来'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // 题材/类型变了就重搜一次发现区,让偏好立刻生效
    unawaited(_loadTopics(_topics.isEmpty ? [_availableTopics.first] : _topics));
  }

  int get _fitCount {
    if (_prefs.band.isAny) return _shelf.length;
    return _shelf.where((s) {
      final c = s.coverage;
      return c != null && _prefs.band.contains(c);
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final shelf = (_onlyFit && !_prefs.band.isAny)
        ? _shelf.where((s) {
            final c = s.coverage;
            return c == null || _prefs.band.contains(c);
          }).toList()
        : _shelf;
    return SectionPrefsScope(
      notifier: _sectionPrefs,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('材料中心'),
          actions: [
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
        body: ListView(
          // 记住滚动位置:收起/展开后不会跳回顶部
          key: const PageStorageKey<String>('material_center'),
          padding: Insets.page,
          children: [
            // ── v2.11 信息架构(用户 10/5:"材料中心更是没有欲望的竖列呈现")──
            //
            // 改动:以前是 **7 个折叠区块首尾相连**(标题行由同一份代码渲染 →
            // 一眼扫过去是 7 条一模一样的横杠)。现在:
            //   ① 「今日精读」提到最上面当**主角**(hero 卡,不再藏进折叠区);
            //   ② 其余 6 个区块收进 **3 组分段切换**,一次只显示一组 ——
            //      首屏看得见的东西变少,每个区块的纵向空间变大;
            //   ③ 每个区块**本身仍然可折叠/可隐藏**(v2.9 的机制原样保留),
            //      分段只是"分层",不是"把功能藏起来":切一下就全在。
            //
            // 分组依据是"用户此刻想干什么",不是按功能名硬分:
            //   找材料(个性化偏好 + 题材发现 + 按水平找)、
            //   在读的(书架 + 今日推荐)、
            //   我的东西(材料库)。
            _buildGroupSwitcher(theme),
            const SizedBox(height: Gap.xs),
            AppStagger(
              index: 1,
              child: CollapsibleSection(
                id: 'daily',
                title: '今日精读',
                icon: Icons.local_fire_department_outlined,
                subtitle: '每天一篇,打开前先告诉你它有多难',
                collapsedHint: _daily == null ? '还没有可精读的条目' : _daily!.title,
                child: _buildDailyCard(theme, muted),
              ),
            ),
            if (_group == 0) ...[
              AppStagger(
                index: 0,
                child: CollapsibleSection(
                  id: 'prefs',
                  title: '个性化找资源',
                  icon: Icons.tune,
                  subtitle: _prefs.summary,
                  collapsedHint: _prefs.summary,
                  trailing: TextButton(
                    onPressed: _showPrefsSheet,
                    child: const Text('调整'),
                  ),
                  child: _buildPrefsCard(theme, muted),
                ),
              ),
              AppStagger(
                index: 2,
                child: CollapsibleSection(
                  id: 'discover',
                  title: '发现更多',
                  icon: Icons.explore_outlined,
                  subtitle: '按题材找:公版书 + 论文 + 外媒三路并行',
                  collapsedHint: _selectedTopics.isEmpty
                      ? '选题材后在这里出结果'
                      : '已选 ${_selectedTopics.length} 个题材 · ${_topicHits.length} 篇材料',
                  child: _buildDiscover(theme, muted),
                ),
              ),
            ],
            if (_group == 1) ...[
              AppStagger(
                index: 3,
                child: CollapsibleSection(
                  id: 'bookshelf',
                  title: '书架',
                  icon: Icons.collections_bookmark_outlined,
                  subtitle: _shelfCount == 0
                      ? '还没放书 —— 读过的材料可以摆上来'
                      : '架上 $_shelfCount 本 · 点开继续读',
                  collapsedHint: _shelfCount == 0 ? '空书架' : '$_shelfCount 本',
                trailing: TextButton(
                  onPressed: () => _openBookshelf(),
                  child: const Text('去看看'),
                ),
                // 书架本体在独立页面(那里要画真的架子),这里给一个"当前架上"的真架子预览
                child: _buildBookshelfPreview(theme, muted),
              ),
            ),
            AppStagger(
              index: 4,
              child: CollapsibleSection(
                id: 'byLevel',
                title: '按你的水平找材料',
                icon: Icons.school_outlined,
                subtitle: '中文说需求,AI 去公开源找原文',
                child: _buildAiDiscoverGrid(theme),
              ),
            ),
            ],
            if (_group == 1)
              AppStagger(
                index: 5,
                child: CollapsibleSection(
                  id: 'feed',
                  title: '今日推荐',
                  icon: Icons.rss_feed,
                  subtitle:
                    '${MaterialSourceService.sourceOf(_sourceId)?.label ?? _sourceId} · 最新条目',
                  collapsedHint:
                      _items.isEmpty ? '还没有条目' : '${_items.length} 条最新条目',
                  trailing: TextButton(
                    onPressed: _probing ? null : _probeAll,
                    child: Text(_probing ? '检测中…' : '检测可用源'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sourceStrip(theme),
                      const SizedBox(height: Gap.xs),
                      _sourceNote(theme, muted),
                      const SizedBox(height: Gap.sm),
                      if (_loadingItems)
                        // 方案 B:骨架屏(与最终卡片同形状),不再是转圈
                        const SkeletonLines(lines: 4, seed: 1)
                      else if (_error != null)
                        _errorCard(theme, muted)
                      else if (_items.isEmpty)
                        const AppEmpty(
                          icon: Icons.article_outlined,
                          title: '这个源暂时没有条目',
                          hint: '换一个源试试,或点「检测可用源」',
                        )
                      else
                        // v2.11:**横滑卡片流**(体检:全页只有一处横滑,其余清一色竖列)。
                        // 为什么改成横滑而不是继续竖排六张:
                        // 材料中心一屏里已经有 6 个竖列区块,"今日推荐"再竖排六张,
                        // 一屏全是同宽同高的卡 —— 这是用户说的"没有欲望的竖列呈现"。
                        // 横滑让"还能往右看"这件事本身变成吸引力,同时把纵向高度
                        // 从 6 张卡(约 600px)压到 1 行(约 176px)。
                        SizedBox(
                          height: 176,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _items.take(8).length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: Gap.xs),
                            itemBuilder: (_, i) => SizedBox(
                              width: 232,
                              child: _buildFeedCard(theme, _items[i]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_group == 2)
              AppStagger(
              index: 6,
              child: CollapsibleSection(
                id: 'shelf',
                title: '材料库',
                icon: Icons.library_books_outlined,
                subtitle: _prefs.band.isAny
                    ? '按「今天最适合读」排序'
                    : '按 ${_prefs.band.label} 排序 · 符合 $_fitCount 篇',
                collapsedHint: '${shelf.length} 篇 · 点开继续读',
                trailing: _prefs.band.isAny || _shelf.isEmpty
                    ? null
                    : FilterChip(
                        label: const Text('只看符合'),
                        selected: _onlyFit,
                        onSelected: (v) => setState(() => _onlyFit = v),
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loadingShelf)
                      const SkeletonLines(lines: 3, seed: 2)
                    else if (shelf.isEmpty)
                      AppEmpty(
                        icon: Icons.library_books_outlined,
                        title: _onlyFit ? '没有符合 ${_prefs.band.label} 的材料' : '还没有材料',
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
            const SizedBox(height: Gap.lg),
          ],
        ),
      ),
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

  Widget _buildPrefsCard(ThemeData theme, Color muted) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text('个性化找资源',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (_prefs.activeCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_prefs.activeCount} 项偏好',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              TextButton(
                onPressed: _showPrefsSheet,
                child: const Text('调整'),
              ),
            ],
          ),
          const SizedBox(height: Gap.xxs),
          Text(
            _prefs.summary,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: muted, height: 1.4),
          ),
          const SizedBox(height: Gap.sm),
          Text('难度', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: Gap.xxs),
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              for (final b in MaterialBand.values)
                ChoiceChip(
                  label: Text(b.label),
                  selected: _prefs.band == b,
                  onSelected: (_) => _setBand(b),
                ),
            ],
          ),
          if (!_prefs.band.isAny) ...[
            const SizedBox(height: Gap.xxs),
            Text(
              _prefs.band.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: muted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  // ───────────────── ① 今日精读大卡(v2.8) ─────────────────

  Widget _buildDailyCard(ThemeData theme, Color muted) {
    final item = _daily;
    final a = _dailyAnalysis;
    final kind = MaterialLevel.kindOfSource(_sourceId);
    final lv = a == null
        ? MaterialLevel.fallbackForKind(kind)
        : MaterialLevel.of(a.cefr, kind: kind);
    final accent = MaterialLevel.accentOf(_sourceId);

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
                const AppLoading(label: '正在准备今天的精读…')
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
                                final next = _items.length > 1 ? _items[1] : null;
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
        else
          for (var i = 0; i < _topicHits.length; i++)
            AppStagger(
              index: i,
              child: _buildDiscoverCard(theme, _topicHits[i]),
            ),
      ],
    );
  }

  /// 书架(v2.10,用户 10/4 第 4/5 条):材料中心里的一块,点开是独立书架页
  int _shelfCount = 0;
  List<Map<String, Object?>> _bookshelf = const [];

  Future<void> _loadBookshelf() async {
    try {
      final rows = await DatabaseService.bookshelfItems();
      if (!mounted) return;
      setState(() {
        _bookshelf = rows;
        _shelfCount = rows.length;
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
  /// 新版式:卡片宽 232,上半是**通栏 120 高的封面**(有真图时一眼看到原图),
  /// 下半是标题 + 中文标题 + 一行动作。整块只占约 176 高,横向滑动看更多。
  ///
  /// 动作保持不变(点卡 = 直接打开阅读,「设为今日精读」仍是卡上小按钮)——
  /// 用户 10/4 明确要求过"点卡片要真的打开",这条不能因为改版式而丢。
  Widget _buildFeedCard(ThemeData theme, FeedItem item) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final kind = MaterialLevel.kindOfSource(_sourceId);
    final cn = _titleCnOf(item.title);
    return AppCard(
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
          // `SizedBox(height: 176)` 定死的,而下面结构里需要"把动作行压到卡底"。
          // 如果文字区用 `Column` + `Spacer`,一旦某行行高比估算的高
          //(系统字号放大、字体回退、中文行高差异),整列就会超出 176 →
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

  Widget _buildShelfCard(ThemeData theme, ShelfItem s) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final cov = s.coverage;
    final fit = cov == null ? '' : _prefs.band.fitLabel(cov);
    final lv = MaterialLevel.of(s.cefr, kind: s.kind);
    final meta = [
      '${s.wordCount} 词',
      '约 ${s.estMinutes} 分钟',
      s.progressLabel,
      if (s.pickedWords > 0) '已收 ${s.pickedWords} 词',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: AppCard(
        onTap: () => _openReader(s.id),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MaterialCover(
              seed: s.title,
              kind: s.kind,
              // v2.11:材料库卡的封面 —— 库里存的 cover_url 优先,老数据按
              // `url` 里的公版书书号现算(见 MaterialSourceService.coverFor)
              imageUrl: MaterialSourceService.coverFor(
                storedCoverUrl: s.coverUrl,
                sourceUrl: s.url,
              ),
              width: 76,
              height: 76,
              radius: Radii.control,
              levelLabel: 'Lv$lv',
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(meta,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, fontSize: 11.5)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: 2,
                    children: [
                      if (cov != null)
                        _meta(theme, Icons.speed,
                            '已知 ${(cov * 100).toStringAsFixed(0)}%'),
                      if (fit.isNotEmpty)
                        _chip(theme, fit, accent: fit.startsWith('符合')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: () => _openReader(s.id),
                        child: const Text('继续读'),
                      ),
                      const SizedBox(width: Gap.xxs),
                      if (s.url.trim().isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _openExternal(s.url),
                          icon: const Icon(Icons.link, size: 15),
                          label: const Text('原文链接'),
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
}

/// 词频表在使用前必须先加载(分析依赖它);这里给一个统一的预热入口,
/// 让调用方(材料中心/阅读器)在打开前调用一次即可。
Future<void> warmUpWordFrequency() => WordFrequency.ensureLoaded();
