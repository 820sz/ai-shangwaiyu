import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';


import '../../models/bookmark.dart';
import '../../models/vocabulary.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../services/audio_service.dart';
import '../../services/backup_service.dart';
import '../../services/base_api.dart';
import '../../services/database.dart';
import '../../services/deepseek_api.dart';
import '../../services/external_link.dart';
import '../../services/material_library.dart';
import '../../services/material_blocks.dart' as blocks;
import '../../services/reader_settings.dart';
import '../../services/reader_units.dart';
import '../../services/reading_quiz.dart';
import '../../services/translation_diagnostics.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/material_blocks.dart';
import '../../widgets/reader_action_bar.dart';
import '../../widgets/reader_console.dart';
import '../../widgets/reader_paper.dart';
import '../../widgets/reader_progress.dart';
import '../../widgets/reader_sheets.dart';
import '../../widgets/reader_text.dart';
import '../../widgets/waiting.dart';
import '../../widgets/word_action_sheet.dart';
import 'dictation_screen.dart';
import 'reading_quiz_screen.dart';
import 'widgets/category_picker.dart';
import 'widgets/follow_up_drawer.dart';
import 'widgets/quick_replies.dart';
import 'widgets/reader_follow_up_context.dart';
import 'widgets/sub_category_input.dart';

/// 材料阅读器(v2.0)。
///
/// 与"把材料丢进文章阅读器"的区别:
/// 1. **按块懒加载**:材料可能是一本书(几十万字),分块从 material_content 读,
///    只为可见的块建 widget;
/// 2. **点词即查 + 一键入库**:点任何词 → 底部弹层(释义/音标/例句 + 朗读 +
///    收进生词本),入库时同步建立复习状态(due=现在),直接进复习队列;
/// 3. **进度落库**:读到第几块、花了多少分钟、查了多少词、收了多少词,
///    退出与"读完"都写进 material_progress,并记一次 reading_session
///    (导师与统计都读这份数据)。
class MaterialReaderScreen extends StatefulWidget {
  final int materialId;

  /// 翻译服务(默认真实实现)。
  ///
  /// 为什么做成可注入:翻译这条链路历史上"修了好几轮都没修好",根因之一是
  /// 它**完全不可测**(`DeepseekApiService()` 直接 new 在 State 里,测试无法替换)。
  /// 默认值保持原行为,现有调用方一行都不用改;widget 测试可传 fake 子类。
  final DeepseekApiService? translateApi;

  const MaterialReaderScreen({
    super.key,
    required this.materialId,
    this.translateApi,
  });

  @override
  State<MaterialReaderScreen> createState() => _MaterialReaderScreenState();
}

class _MaterialReaderScreenState extends State<MaterialReaderScreen> {
  final _scrollCtrl = ScrollController();
  final _stopwatch = Stopwatch();

  Map<String, Object?>? _material;
  List<Map<String, Object?>> _chunks = const [];

  /// 翻译单元(真段落):在 [_load] 里由 [_chunks] 拆出。
  ///
  /// 为什么必须单独一层:正文按 **2500 词一块**入库,"块"不是"段"。旧实现把
  /// 块当段 → 典型文章只有 1 段 → 进度分母恒 1(进度条永远是死的)、一次请求
  /// 发整篇 → 模型回 N 段与 1 段对不上 → 只翻出第一段。翻译、进度、逐段对照
  /// 全部改按**真段落**走(拆分规则见 services/reader_units.dart)。
  List<ReaderUnit> _units = const [];

  /// 块下标 → 该块第一个单元下标(空块指向下一个有段落的块;见
  /// [chunkFirstUnitIndices])。续读跳转、"可见块展开成单元"都用它。
  List<int> _firstUnitOfChunk = const [];

  /// 翻译 API(可注入,见 [MaterialReaderScreen.translateApi] 的注释)
  late final DeepseekApiService _api =
      widget.translateApi ?? DeepseekApiService();

  MaterialAnalysis? _analysis;

  bool _loading = true;
  String? _error;
  int _lastChunkIndex = 0;
  int _lookups = 0;
  int _picked = 0;

  /// 本轮拾取的词(出读后测验要用它们;只存在内存,不入库)
  final List<String> _pickedWords = [];
  bool _finished = false;

  /// 阅读设置(v2.5):字号乘数与行距,落 Hive,两个阅读器共用
  double _fontScale = ReaderSettings.defaultFontScale;
  double _lineHeight = ReaderSettings.defaultLineHeight;

  // ═══════════ v2.27 · 阅读器 C 方案(2026-11-06 用户拍板)═══════════
  //
  // 用户三条抱怨:底部拥挤 / 字体色调差 / 滑动没有进度百分比。C 的解法是
  // "零常驻按钮 + 一张纸 + 常驻进度",全部落在本文件与 `widgets/reader_*`。

  /// 纸张三色:纸白(冷灰纸,默认)/ 米黄(暖纸)/ 墨夜(深色纸)。
  /// 持久化在 `ReaderSettings`(settings Hive box),切换立即生效、重启保留。
  ReaderPaper _paper = ReaderPaper.white;

  /// 当前纸张的调色板(色值见 `lib/widgets/reader_paper.dart`)
  ReaderPalette _palette = paletteOf(ReaderPaper.white);

  /// 阅读进度 0~1,**只**通知进度组件(右侧胶囊/竖轨、贴底 2px 线、控制台数字)。
  ///
  /// 为什么用 ValueNotifier 而不是 setState:滚动每帧都变,整屏重建会让
  /// [#_buildUnit] 里上千个 TapGestureRecognizer 与译文卡片跟着重建,低端机
  /// 必然掉帧;而进度只需要重建 3 个像素级小组件。
  final ValueNotifier<double> _readingPercent = ValueNotifier<double>(0);

  /// 最近一次滚动比例(0~1)。落库 percent 用它,不再按"2500 词一块"粗估
  /// (典型文章只有 1 块 → 旧逻辑永远写 0 或 100)。
  double _lastScrollRatio = 0;

  /// C 方案 6 档字阶(标题/栏目标签/署名/首段/正文/译文),由阅读设置算出
  ReaderType get _type => ReaderType.fromSettings();

  // ═══════════ 逐段翻译(v2.12.2 重做:用户 2026-10-20 原话「完全是一坨屎,稀烂,没法用」)═══════════
  //
  // 旧实现为什么没法用(逐条对应重做后的设计):
  // 1. 打开翻译先弹「范围选择」—— 用户还没看到一句译文就得先做选择题;
  //    现在默认只翻**当前可见的几段**,先把结果给到眼前,范围改成翻完后
  //    才出现的「继续翻后文 / 整章」增量按钮;
  // 2. 旧实现一批 3~4 段一起翻,一段失败/截断就整批标红;现在**一段一个请求**
  //    (并发 2 路),某段失败只影响那一段,单独重试,不牵连别人;
  // 3. 旧实现进度条的分母/分子对不上、取消后还显示「正在翻译」;现在进度 =
  //    本轮真正完成的段数,取消会中断在途请求并立刻把状态清干净;
  // 4. 旧译文只是「跟在下面」,不能点、也看不出能做什么;现在译文可点 →
  //    带着「原段 + 译文」去追问,右侧菜单还能单独重翻这一段。
  //
  /// 是否显示译文(关闭只隐藏,不清已翻好的内容 —— 再打开立刻回来)
  bool _showTranslation = false;

  /// 单元(真段落)下标 → 中文译文。译文只存内存:材料正文才是事实源,
  /// 译文是"读的辅助",下次打开重翻即可(写库要改表结构,不在本次范围)。
  final Map<int, String> _translations = {};

  /// 单元下标 → 附加提示(如"只翻好了前 1/1 段(可能被截断)")。
  /// 与 [_chunkErrors] 分开:错误是"这段没翻出来"(可重试),note 是
  /// "翻出来了但可能不完整" —— 两者 UI 完全不同,旧实现把 note 静默丢弃了。
  final Map<int, String> _translationNotes = {};

  /// 单元下标 → 失败原因(该段可单独重试;没有失败 = 空)
  final Map<int, String> _chunkErrors = {};

  /// 用户主动取消了这一段的翻译(不是失败 —— 不重试、也不自动重翻;
  /// 段落下面给一行「已取消 · 重试」,想翻再点)
  final Set<int> _canceledChunks = {};

  /// 正在排队/在途的段(**单元下标**)。用集合而不是布尔:判断"这一段是否在等
  /// 译文"是逐段 UI(骨架屏 / 取消按钮)的唯一依据。
  final Set<int> _pendingChunks = {};

  /// 待翻队列(严格按用户看到的顺序;单元下标)
  final List<int> _queue = [];

  /// 在途请求(并发上限 [_translateConcurrency];键 = 单元下标)
  final Map<int, CancelToken> _chunkTokens = {};

  /// 每一个单元的作业代号:取消/重排后旧请求回来时,靠它丢弃过期结果
  final Map<int, int> _chunkJobEpoch = {};
  int _epochSeq = 0;

  /// 在途请求(键 = 单元下标,值 = 本次作业号)。
  /// 用 Map 而不是单纯计数:取消某段/停止整轮后旧请求晚回来时,
  /// 靠作业号判断"这个并发位还是不是它的",不会把新任务的槽位一起吞掉。
  final Map<int, int> _activeJobs = {};
  int _jobSeq = 0;

  /// 本轮翻译的进度状态机(分母 = 本轮入队的**真段落数**,典型文章 6~10)。
  /// 抽成纯类是为了可单测:旧实现"最后一段完成时先清零再渲染"导致 100% 那
  /// 一帧从未被渲染(进度条永远是 0%)—— 顺序 bug 必须由单测锁住。
  final TranslationRunState _run = TranslationRunState();

  /// 100% 的进度条保留 2 秒再收:让用户确认"这一轮真的结束了"。
  Timer? _runResetTimer;

  /// 用户点了「取消」之后暂停"随读随翻";点「继续翻后文/整章」会重新打开
  bool _autoTranslate = true;

  /// 滚动停下来 450ms 再算"哪几段在屏幕里" —— 滚动中每帧算 RenderBox
  /// 会在低端机上掉帧,而且一停就翻会让用户看到一串骨架同时出现。
  Timer? _visibleTimer;

  /// 列表的 key(用它的视口矩形判断段落是否真的可见,而不是按滚动比例猜)
  final GlobalKey _listKey = GlobalKey();

  /// 每个**段落单元**的 key(同上;列表项已经是单元而不是块)
  final Map<int, GlobalKey> _unitKeys = {};

  /// 点译文追问时,把追问范围钉在这一段(单元下标);null = 整篇
  int? _followUpChunk;

  /// 一次「继续翻后文」翻多少段
  static const int _translateBatch = 3;

  /// 打开翻译 / 随读随翻时,一次最多补当前屏的几段
  /// (手机一屏通常 3~5 段;给 5 段能覆盖全屏,又不会一次排太多请求)
  static const int _visibleBatch = 5;

  /// 并发路数:2 路是"快"与"不触发限流"的平衡点(逐段请求后仍然保留)
  static const int _translateConcurrency = 2;

  /// 是否已经问过"继续上次阅读"(避免每次重建都弹)
  bool _resumeAsked = false;

  // ── v2.9(用户第 3(5) 条):材料里的 AI 内容块 ──
  /// 已落库/刚生成的块(按 chunk_index 插在对应段落后面)
  List<blocks.MaterialBlockDraft> _blockList = const [];

  /// 正在生成的那一个块('chunkIndex:kind' 作为键;空 = 没有在生成)
  String? _blockWaiting;

  /// 生成失败(键同上,值 = 可读错误)
  final Map<String, String> _blockErrors = {};

  // ── v2.9(用户第 4 条):阅读进度自动留存 ──
  /// 上次落盘时间(节流:最多每 3 秒一次)
  DateTime? _lastPersistAt;

  /// 上次落盘时的段索引(翻段立刻存一次)
  int? _lastPersistIndex;

  /// 上次写 reading_sessions 之后累计的阅读秒数(跨多次落盘累计)
  int _sessionSeconds = 0;

  /// 收词保存位置(v2.7,用户第 3 条"选择保存位置"):默认跟着这份材料走 ——
  /// 分类由材料种类映射,材料名 = 标题。不改也不会掉进「未归类」。
  WordSaveTarget _saveTarget = const WordSaveTarget();

  /// 追问抽屉控制器(v2.7,第 3 条):与识图页共用同一套实现
  late final FollowUpController _followUp = FollowUpController(
    buildContext: _buildFollowUpContext,
    historyKey: 'saved_follow_up_reading',
    emptyHint: '就这份材料提问,AI 会基于正文回答',
  );

  /// 追问时的材料上下文（委托纯函数 [buildReaderFollowUpContext]，可单测）。
  ///
  /// 根因记录（2026-11-08 用户反馈 / 真机截图实测）：
  /// 旧实现在这里按块累加正文、`if (body.length + t.length > 6000) break;` ——
  /// 而正文按 **2500 词一块**入库：一篇 2011 词的材料只有 1 块、约 1.2 万字符，
  /// 第一次循环就 break，body 为空 → AI 只收到「正文节选:」这一行标题，于是
  /// 回复"正文节选是空的，只有标题和元信息（2011 词、B2、覆盖率 84.9%）"。
  ///
  /// 现在：保证非空（按字符截断）、整篇时**优先当前在读小节**、单段追问保持
  /// "本段原文 + 页面译文 + 前后邻段"。
  String _buildFollowUpContext() {
    final a = _analysis;
    final difficultyLine = a == null
        ? ''
        : '篇幅 ${a.wordCount} 词 · ${a.cefr} · '
            '我的已知词覆盖率 ${(a.knownTokenRatio * 100).toStringAsFixed(1)}%';
    final at = _followUpChunk;
    return buildReaderFollowUpContext(
      title: '${_material?['title'] ?? ''}',
      sourceUrl: '${_material?['url'] ?? ''}',
      difficultyLine: difficultyLine,
      chunkTitles: <String>[for (final c in _chunks) '${c['title'] ?? ''}'],
      chunkTexts: <String>[for (final c in _chunks) '${c['text'] ?? ''}'],
      unitTexts: <String>[for (final u in _units) u.text],
      translations: _translations,
      pinnedUnit: at,
      pinnedChunk: (at != null && at >= 0 && at < _units.length)
          ? _units[at].chunkIndex
          : null,
      currentChunk: _chunks.isEmpty
          ? null
          : _lastChunkIndex.clamp(0, _chunks.length - 1),
    );
  }

  @override
  void initState() {
    super.initState();
    _fontScale = ReaderSettings.fontScale();
    _lineHeight = ReaderSettings.lineHeight();
    _paper = ReaderSettings.paper();
    _palette = paletteOf(_paper);
    _stopwatch.start();
    _load();
    _scrollCtrl.addListener(_onScroll);
  }

  /// 开/关逐段翻译。
  ///
  /// 重做后的交互(用户 2026-10-20 原话「完全是一坨屎,稀烂,没法用」):
  /// - **打开 = 立刻翻当前可见的几段**,不再先弹范围选择(旧实现让用户
  ///   还没看到一句译文就做选择题,这是"没法用"的第一层);
  /// - **关闭 = 只隐藏译文**,已翻好的保留;在途请求真的 cancel 掉
  ///   (旧实现关掉后请求还在跑,这就是"取消不掉");
  /// - 再次打开沿用已翻好的段,不重复花钱。
  Future<void> _toggleTranslation() async {
    if (_showTranslation) {
      setState(() => _showTranslation = false);
      _stopTranslation(notify: false);
      return;
    }
    if (_units.isEmpty) return;
    if (!_api.isConfigured) {
      _toast('还没有配置 API Key —— 到「我的 → API 设置」填一个就能翻译');
      return;
    }
    setState(() {
      _showTranslation = true;
      _autoTranslate = true;
    });
    // 先给即时结果:当前屏幕里看得见的段落(最多 5 段)。
    // 为什么不是"当前段":用户打开翻译时往往已经看了半屏,只翻一段会显得没反应。
    _enqueueVisible(limit: _visibleBatch);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// 哪些**段落单元**真的在屏幕里:用列表视口与每个单元的 RenderBox 求交,
  /// 而不是按滚动比例猜 —— 段落高度差别很大,比例法会把没读到的段
  /// 当成"当前段"(旧实现"选取的范围也是乱的"就有这个原因)。
  ///
  /// [limit] 限制这次最多翻几段:打开翻译先给眼前最多 5 段,
  /// 避免一开就排队几十个请求。
  List<int> _visibleUnitIndices({int limit = _visibleBatch}) {
    final viewport = _listKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      return _fallbackVisibleUnits(limit);
    }
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    final hits = <int>[];
    for (final entry in _unitKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height <= top || y >= bottom) continue;
      hits.add(entry.key);
    }
    hits.sort();
    if (hits.isEmpty) return _fallbackVisibleUnits(limit);
    return hits.take(limit).toList();
  }

  /// 首帧 / 视口还没挂上时的兜底:从"读到第几块"映射到单元,再往后取几段
  List<int> _fallbackVisibleUnits(int limit) {
    if (_units.isEmpty) return const [];
    final chunkCount = _chunks.length;
    final chunk = chunkCount <= 0 ? 0 : _lastChunkIndex.clamp(0, chunkCount - 1);
    final start =
        (_firstUnitOfChunk.length > chunk ? _firstUnitOfChunk[chunk] : 0)
            .clamp(0, _units.length);
    final end = (start + limit).clamp(0, _units.length);
    return [for (var i = start; i < end; i++) i];
  }

  GlobalKey _unitKey(int index) => _unitKeys.putIfAbsent(
        index,
        () => GlobalKey(debugLabel: 'reader-unit-$index'),
      );

  /// 这一段还能不能翻:已有译文 / 已排队 / 已失败 / 空段都不重复发请求。
  ///
  /// 失败段必须由用户点「重试」才重翻 —— 否则随读随翻会在同一个坏段上死循环,
  /// 把额度烧光(旧实现就有"越滚越错、一直失败"的观感)。
  bool _canTranslate(int index) {
    if (index < 0 || index >= _units.length) return false;
    if (_translations.containsKey(index)) return false;
    if (_pendingChunks.contains(index)) return false;
    if (_chunkErrors.containsKey(index)) return false;
    if (_canceledChunks.contains(index)) return false;
    return _units[index].text.trim().isNotEmpty;
  }

  /// 把若干**段落单元**放进翻译队列。
  ///
  /// 为什么改成**逐段请求**而不是旧实现的一批 3~4 段:
  /// - 旧实现一段失败/截断,整批都标红(用户看到的是"全错了");
  /// - 逐段请求后,每段有自己的成功/失败/取消状态,重试只重试这一条;
  /// - 代价是请求数变多,所以并发 2 路 + 只翻眼前几段,整体等待反而更短。
  void _enqueueTranslation(List<int> indices) {
    if (!_showTranslation || _units.isEmpty) return;
    // 上一轮已经收尾(可能还停在"100% 保留 2 秒"的展示期)→ 这是新一轮:
    // 必须先重置分母,否则新一批会被加进上一轮的总数里,进度永远到不了 100%。
    final idle = _activeJobs.isEmpty && _queue.isEmpty;
    if (idle) {
      _runResetTimer?.cancel();
      _runResetTimer = null;
    }
    final fresh = <int>[];
    for (final i in indices) {
      if (!_canTranslate(i)) continue;
      _pendingChunks.add(i);
      _queue.add(i);
      _chunkJobEpoch[i] = ++_epochSeq;
      fresh.add(i);
    }
    if (fresh.isEmpty) return;
    if (idle) {
      _run.begin(fresh.length);
    } else {
      _run.add(fresh.length);
    }
    setState(() {});
    _pumpTranslationQueue();
  }

  /// 队列泵:最多 [_translateConcurrency] 路在途,完成一个立刻补一个。
  /// 进度 = 本轮已完成 / 本轮总数,每完成一段就 +1(不再是"整批回来才动")。
  void _pumpTranslationQueue() {
    if (!mounted || !_showTranslation) return;
    while (_activeJobs.length < _translateConcurrency && _queue.isNotEmpty) {
      final index = _queue.removeAt(0);
      final epoch = _chunkJobEpoch[index];
      if (epoch == null) continue;
      final jobId = ++_jobSeq;
      _activeJobs[index] = jobId;
      _translateOne(index, epoch).whenComplete(() {
        // 只有"当前占着这个段位"的作业才允许收尾:
        // 取消后重试会占同一个 index,旧请求回来时不能动新任务的状态。
        final wasActive = _activeJobs[index] == jobId;
        if (wasActive) {
          _activeJobs.remove(index);
          if (_chunkJobEpoch[index] == epoch) {
            _chunkJobEpoch.remove(index);
            _run.completeOne();
          }
        }
        _pumpTranslationQueue();
      });
    }
    // 本轮真的结束了:**先把 100% 渲染出来,再收条**。
    //
    // 旧实现这里直接把 _runTotal/_runDone 清零再 setState → `done/total`
    // 从未被 build 过,用户看到的进度条从出现到消失只有 0%(「进度永远是死的」
    // 的直接原因)。现在交给 TranslationRunState:markFinished 让这一帧是
    // 100%,2 秒后再由定时器清空。
    if (_activeJobs.isEmpty && _queue.isEmpty && _run.visible) {
      _run.markFinished();
      _scheduleRunReset();
    }
    setState(() {});
  }

  /// 一轮完成后,把 100% 的进度条保留 2 秒。
  ///
  /// 只在"本轮仍是最新"时清空:若 2 秒内用户又点了「继续翻后文」,新任务会
  /// 取消这个定时器(见 [_enqueueTranslation]),不会把新一轮的进度清掉。
  void _scheduleRunReset() {
    if (_runResetTimer != null) return;
    _runResetTimer = Timer(const Duration(seconds: 2), () {
      _runResetTimer = null;
      if (!mounted) return;
      if (_activeJobs.isNotEmpty || _queue.isNotEmpty) return;
      setState(() {
        _run.clear();
      });
    });
  }

  /// 翻一段(这里的 index = **段落单元**下标,不是正文块)。
  /// 一个请求只负责一段 —— 失败、取消、重试都只影响这一段。
  ///
  /// [epoch] 是这段的作业代号:用户取消/重翻后,旧请求晚回来的结果会被丢弃,
  /// 不会覆盖新译文(旧实现"取消后仍在翻译、结果又跳出来"的根因之一)。
  Future<void> _translateOne(int index, int epoch) async {
    if (!mounted || !_showTranslation) return;
    if (_chunkJobEpoch[index] != epoch) return;
    final token = CancelToken();
    _chunkTokens[index] = token;
    try {
      // v2.13.1:一次只发**一个真段落**(≤600 字符)。旧实现发整块(最多
      // 6000 词)并只声明 1 段 → 模型按空行回 N 段 → 段数对不上 → 只抢救
      // 第一段,note 被静默丢弃。段落级请求让"段数对账"变成 1:1,且失败只
      // 影响这一段、45s 超时可控。
      final outcome = await _api.translateParagraphsRich(
        [_units[index].text],
        cancelToken: token,
      );
      if (!mounted) return;
      if (_chunkJobEpoch[index] != epoch || _chunkTokens[index] != token) return;
      final text = outcome.translations.isEmpty
          ? ''
          : outcome.translations.first.trim();
      if (text.isEmpty) {
        _markChunkError(index, outcome.note ?? 'AI 没返回译文');
        return;
      }
      setState(() {
        _translations[index] = text;
        _chunkErrors.remove(index);
        _pendingChunks.remove(index);
        // note 非空 = 模型给的段数与输入对不上(可能被截断)。旧实现静默丢掉
        // 它,用户以为"整段都翻好了";现在段落下面会显示一行提示。
        final note = outcome.note?.trim() ?? '';
        if (note.isEmpty) {
          _translationNotes.remove(index);
        } else {
          _translationNotes[index] = note;
        }
      });
      // v2.16.0:译文落库(失败静默 —— 译文已经在界面上了,写库失败只影响
      // "下次进来还在不在",不能反过来把这一段标成失败)。
      await _persistTranslation(index);
    } on DioException catch (e) {
      // 取消不是"翻译失败":直接丢掉,不弹错误、不标红
      if (CancelToken.isCancel(e) || token.isCancelled) return;
      // 已经被取消/重排了(epoch 不在了)→ 旧请求的错误也不能写回界面
      if (_chunkJobEpoch[index] != epoch) return;
      _markChunkError(index, _humanError(e));
    } catch (e) {
      if (token.isCancelled) return;
      if (_chunkJobEpoch[index] != epoch) return;
      _markChunkError(index, _humanError(e));
    } finally {
      if (identical(_chunkTokens[index], token)) {
        _chunkTokens.remove(index);
      }
    }
  }

  void _markChunkError(int index, String message) {
    if (!mounted) return;
    // v2.16.0:失败原因进**进程内**诊断缓存(最多 3 条),“我的 → 诊断信息”
    // 可查 —— 用户说"翻译失败"时不用再靠猜;消息已脱敏,不含 key。
    TranslationDiagnostics.recordFailure(message);
    setState(() {
      _chunkErrors[index] = message;
      _translationNotes.remove(index);
      _pendingChunks.remove(index);
    });
  }

  /// 把一段译文落库(v2.16.0)。失败只记调试日志,不影响界面。
  ///
  /// 写 [sourceText] 快照:下次进阅读器加载时用它比对"这条译文还对得上当前
  /// 这一段吗";材料重新导入/切段变化后对不上 → 不显示(见
  /// `DatabaseService.alignTranslationsToUnits`)。
  Future<void> _persistTranslation(int index) async {
    if (index < 0 || index >= _units.length) return;
    final text = _translations[index]?.trim() ?? '';
    if (text.isEmpty) return;
    final unit = _units[index];
    try {
      await DatabaseService.saveMaterialTranslation(
        widget.materialId,
        unitIndex: index,
        chunkIndex: unit.chunkIndex,
        sourceText: unit.text,
        translatedText: text,
        model: DeepseekApiService.activeConfig.model,
      );
    } catch (e) {
      debugPrint('ReadFlow 译文落库失败(不影响阅读): $e');
    }
  }

  /// 把异常翻成人话:网络超时/鉴权失败/429/端点不匹配都有中文指引
  /// (旧实现只截断英文 DioException,用户看不懂"最近一次:..."是什么)。
  String _humanError(Object e) => BaseApiService.friendlyError(e);

  /// 停止翻译:清空队列 + cancel 在途请求 + 清掉本轮进度。
  ///
  /// [notify] true = 用户主动点了取消,给一条"翻好的都保留"的反馈;
  /// false = 关闭翻译/离开页面时静默停止。
  void _stopTranslation({bool notify = true}) {
    final had = _activeJobs.isNotEmpty || _queue.isNotEmpty;
    _queue.clear();
    for (final token in _chunkTokens.values.toList()) {
      try {
        token.cancel('停止翻译');
      } catch (_) {
        // 取消失败不影响界面:结果回来时会被 epoch 判断丢掉
      }
    }
    _chunkTokens.clear();
    // 清掉 epoch 与在途作业 = 之后回来的旧结果一律不认,并发槽位也立刻还给
    // 新一轮(否则取消后立刻重开,要等旧请求超时才动,看着像卡死)。
    _chunkJobEpoch.clear();
    _activeJobs.clear();
    _pendingChunks.clear();
    _runResetTimer?.cancel();
    _runResetTimer = null;
    _run.clear();
    if (mounted) setState(() {});
    if (notify && had) {
      _toast('已停止 —— 翻好的 ${_translations.length} 段都保留着');
    }
  }

  /// 用户点「取消」:停掉本轮,并**暂停随读随翻** —— 否则下一滚又自动开翻,
  /// 用户会觉得"取消不掉"(与旧实现同一个投诉)。
  void _cancelAllTranslation() {
    _autoTranslate = false;
    _stopTranslation();
  }

  /// 取消**某一段**:排队中的直接移出;在途的 cancel 掉那个请求。
  /// 只影响这一段 —— 其它段照常翻完(旧实现只能整批取消/整批失败)。
  void _cancelChunkTranslation(int index) {
    if (_queue.remove(index)) {
      _canceledChunks.add(index);
      _chunkJobEpoch.remove(index);
      _pendingChunks.remove(index);
      // 取消也是一种"已处理":进度分子 +1,否则本轮永远差一格到 100%。
      _run.completeOne();
      setState(() {});
      _pumpTranslationQueue();
      return;
    }
    final token = _chunkTokens.remove(index);
    if (token == null) {
      // 请求刚好已经完成(骨架屏还没消失时点到了):不要把刚到的译文标成
      // "已取消" —— 只把 pending 清掉,让译文正常显示。
      setState(() => _pendingChunks.remove(index));
      return;
    }
    _canceledChunks.add(index);
    _chunkJobEpoch.remove(index);
    _pendingChunks.remove(index);
    // 立刻把并发槽位还给队列:不必等被 cancel 的请求真的收尾
    _activeJobs.remove(index);
    _run.completeOne();
    try {
      token.cancel('取消这一段');
    } catch (_) {}
    setState(() {});
    _pumpTranslationQueue();
  }

  /// 本轮翻译进度条(真实完成数 / 本轮入队数),只给翻译弹层用。
  ///
  /// 分母 = 本轮入队的**真段落数**(典型文章 6~10,不再恒 1);分子 = 已完成
  /// (成功 / 失败 / 取消都算"已处理")。分母/进度值都来自 [TranslationRunState]
  /// —— 完成时它先把分子补到分母,保证 100% 那一帧真的被渲染出来。
  Widget? _translationProgressWidget() {
    if (!_run.visible) return null;
    final total = _run.total;
    final done = _run.done;
    final detail = StringBuffer('已翻 ${_translations.length}/${_units.length} 段');
    if (_chunkErrors.isNotEmpty) {
      detail.write(' · ${_chunkErrors.length} 段待重试');
    }
    return ProgressStageBar(
      stage: '正在翻译 · 已完成 $done/$total 段',
      value: _run.progress,
      detail: detail.toString(),
      startedAt: _run.startedAt,
      onCancel: _cancelAllTranslation,
    );
  }

  /// 翻译弹层(C 方案):翻译进度与增量操作从"压在正文下的灰带"收进这里。
  ///
  /// 旧实现是一条 93px 的实底灰带(_buildTranslationTray),紧贴正文、视觉上
  /// 就是横在文字下面的一条灰条,而且和底栏翻译 chip 状态双写。C 方案下正文里
  /// 只留译文本身,进度与动作全部进弹层;顶部只留一条 2px 细提示线。
  void _showTranslationSheet() {
    final failed = _chunkErrors.length;
    final busy = _activeJobs.isNotEmpty || _queue.isNotEmpty || _run.visible;
    final done = _translations.length;
    final unitCount = _units.length;
    final String status;
    if (failed > 0) {
      status = '已翻 $done/$unitCount 段 · $failed 段没翻出来';
    } else if (!_autoTranslate) {
      status = '已翻 $done/$unitCount 段 · 随读随翻已暂停';
    } else if (done == 0) {
      status = '随读随翻 · 先翻当前屏';
    } else {
      status = '已翻 $done/$unitCount 段 · 点译文可问 AI';
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReaderTranslationSheet(
        palette: _palette,
        editing: _showTranslation,
        done: done,
        total: unitCount,
        failed: failed,
        status: status,
        autoTranslate: _autoTranslate,
        translateTarget: DeepseekApiService.targetSummary,
        progressBar: busy ? _translationProgressWidget() : null,
        lastError: failed > 0 ? _humanError(_chunkErrors.values.last) : null,
        onContinueNext: _translateNext,
        onWholeChapter: _translateChapter,
        onRetryFailed: _retryFailedChunks,
        onToggleOff: _toggleTranslation,
      ),
    );
  }

  /// 模型与思考档(C 版弹层):原来挤在底栏最左、属于"低频却常驻"的典型,
  /// 现在归到控制台「材料」组。
  Future<void> _showModelSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReaderModelSheet(
        palette: _palette,
        model: ReaderModelSheet.currentModel(),
        thinking: ReaderModelSheet.currentThinking(),
        onPick: (model, thinking) async {
          final box = Hive.box(AppConstants.hiveBoxSettings);
          await box.put(AppConstants.keyDoubaoModel, model);
          await box.put(AppConstants.keyDoubaoThinking, thinking);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  /// 材料动作(导出 / 听写 / 读完 / 原文链接)
  void _showMaterialActions() {
    final url = '${_material?['url'] ?? ''}'.trim();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ReaderActionSheet(
        palette: _palette,
        title: '材料',
        note: '导出/听写/读完都会记进学习数据;原文链接用系统浏览器打开。',
        actions: <ReaderActionItem>[
          if (_chunks.isNotEmpty)
            ReaderActionItem(
              icon: Icons.download_outlined,
              label: '导出这篇(Markdown)',
              hint: '阅读包',
              onTap: _exportPack,
            ),
          if (_chunks.isNotEmpty)
            ReaderActionItem(
              icon: Icons.headphones_outlined,
              label: '听写练习',
              onTap: () => _onMoreAction('dictation'),
            ),
          if (!_finished)
            ReaderActionItem(
              icon: Icons.check_circle_outline,
              label: '读完了(进度记 100%)',
              onTap: _finishReading,
            ),
          if (url.isNotEmpty)
            ReaderActionItem(
              icon: Icons.open_in_new,
              label: '原文链接',
              hint: '浏览器',
              onTap: () => _openSourceLink(url),
            ),
        ],
      ),
    );
  }

  /// 上滑「阅读控制台」:底部零常驻按钮的唯一动作入口。
  Future<void> _openConsole() async {
    if (_chunks.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (_) => ReaderConsoleSheet(data: _consoleData()),
    );
  }

  /// 控制台的数据快照(控制台是纯展示组件,不碰业务状态)
  ReaderConsoleData _consoleData() {
    final t = _type;
    final model = ReaderModelSheet.currentModel();
    final thinking = ReaderModelSheet.currentThinking();
    return ReaderConsoleData(
      palette: _palette,
      progress: _readingPercent,
      currentUnit: _currentUnitIndex(),
      totalUnits: _units.length,
      currentChunk: _currentChunkIndex(),
      chunkTitles: <String>[
        for (var i = 0; i < _chunks.length; i++)
          '${_chunks[i]['title'] ?? ''}'.trim().isEmpty
              ? '第 ${i + 1} 节'
              : '${_chunks[i]['title']}'.trim(),
      ],
      chunkPercents: _chunkPercents(),
      translationDone: _translations.length,
      translationTotal: _units.length,
      showTranslation: _showTranslation,
      pickedCount: _pickedWords.length,
      finished: _finished,
      onShelf: _onShelf,
      fontLabel:
          '${ReaderSettings.cFontLabel(t.body)} · ${ReaderSettings.lineHeightLabel(_lineHeight)}',
      modelLabel:
          '$model · ${AppConstants.thinkingOptionsFor(model)[thinking] ?? thinking}',
      saveTargetLabel: _saveTarget.label,
      hasRichForms: _chunks.isNotEmpty,
      onContinue: _continueReading,
      onToggleTranslation: _showTranslationSheet,
      onFollowUp: _openFollowUp,
      onSavePicked: _showPickedSummary,
      onChangeSaveTarget: _changeSaveTarget,
      onToggleShelf: _toggleShelf,
      onJumpChunk: _scrollToChunk,
      onOpenFullToc: _showToc,
      onOpenSettings: _showReaderSettings,
      onOpenModel: _showModelSheet,
      onOpenRichForms: _openRichForms,
      onOpenMaterialActions: _showMaterialActions,
    );
  }

  /// 当前读到第几节(0 起)。
  ///
  /// 用**连续单元坐标**（floor）而不是 `_lastChunkIndex`（round）：控制台目录
  /// 高亮/本节 % 必须和总进度同一套坐标，否则出现在"高亮下一节 + 本节 0%"
  /// 的错位观感。
  int _currentChunkIndex() {
    if (_chunks.isEmpty) return 0;
    if (_units.isEmpty) return _lastChunkIndex.clamp(0, _chunks.length - 1);
    final cursor = _lastScrollRatio * (_units.length - 1);
    var current = 0;
    for (var i = 0; i < _firstUnitOfChunk.length && i < _chunks.length; i++) {
      if (_firstUnitOfChunk[i] <= cursor) current = i;
    }
    return current.clamp(0, _chunks.length - 1);
  }

  /// 当前读到第几段(0 起;按滚动比例估算,和进度同一份真值)
  int _currentUnitIndex() {
    if (_units.isEmpty) return 0;
    return (_lastScrollRatio * (_units.length - 1))
        .round()
        .clamp(0, _units.length - 1);
  }

  /// 每节(块)的阅读 %:按单元覆盖算,和总进度同一套比例。
  List<double> _chunkPercents() {
    if (_chunks.isEmpty) return const <double>[];
    if (_units.isEmpty) {
      return <double>[
        for (var i = 0; i < _chunks.length; i++)
          i < _lastChunkIndex
              ? 100
              : i == _lastChunkIndex
                  ? (_lastScrollRatio * 100).clamp(0.0, 100.0)
                  : 0,
      ];
    }
    final cursor =
        (_lastScrollRatio * (_units.length - 1)).clamp(0.0, _units.length - 1.0);
    final out = <double>[];
    for (var c = 0; c < _chunks.length; c++) {
      final start =
          c < _firstUnitOfChunk.length ? _firstUnitOfChunk[c] : 0;
      var end = c + 1 < _firstUnitOfChunk.length
          ? _firstUnitOfChunk[c + 1] - 1
          : _units.length - 1;
      if (end < start) end = start;
      final span = end - start + 1;
      out.add((((cursor - start) / span).clamp(0.0, 1.0)) * 100);
    }
    return out;
  }

  /// 「继续阅读」= 收起控制台继续读(进度已经在那儿,不跳)
  void _continueReading() {
    if (mounted) Navigator.of(context).maybePop();
  }

  /// 点右上角 % 胶囊弹「回到顶部 / 跳到底部」小菜单（2026-11-08 用户反馈 C）。
  ///
  /// 保持 C 的**零常驻按钮**:不新增任何常驻控件,只复用已有的 % 胶囊做
  /// 轻量入口(控制台/底部把手区都不变);平滑滚动后 `_onScroll` 照常更新
  /// 进度并落库,不破坏续读位置。
  void _showProgressJumpMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ReaderActionSheet(
        palette: _palette,
        title: '跳到',
        note: '进度照常记录;回顶/回底只是移动视图,不会改动已读比例。',
        actions: <ReaderActionItem>[
          ReaderActionItem(
            icon: Icons.vertical_align_top,
            label: '回到顶部',
            hint: '0%',
            onTap: () => _animateScrollTo(0),
          ),
          ReaderActionItem(
            icon: Icons.vertical_align_bottom,
            label: '跳到底部',
            hint: '100%',
            onTap: () => _animateScrollTo(double.infinity),
          ),
        ],
      ),
    );
  }

  /// 平滑滚动到指定位置(`double.infinity` = 到底);未挂载/无内容时静默忽略。
  void _animateScrollTo(double target) {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return;
    final to = target.isFinite ? target.clamp(0.0, max) : max;
    if ((_scrollCtrl.offset - to).abs() < 1) return;
    _scrollCtrl.animateTo(
      to,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// 顶部 2px 翻译细提示(不压正文):翻译进行中 / 已翻比例的一条细线。
  Widget _translationHintLine(ReaderPalette p) {
    final total = _units.isEmpty ? 1 : _units.length;
    final ratio = _run.visible
        ? _run.progress.clamp(0.0, 1.0)
        : (_translations.length / total).clamp(0.0, 1.0);
    return SizedBox(
      height: 2,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(color: p.hairline),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: ratio,
            child: ColoredBox(color: p.accent.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }

  /// 单段重试(失败卡上的「重试」)。只重发这一段,不碰其它段。
  void _retryChunk(int index) {
    if (index < 0 || index >= _units.length) return;
    setState(() {
      _chunkErrors.remove(index);
      _translationNotes.remove(index);
      _canceledChunks.remove(index);
      _showTranslation = true;
    });
    _enqueueTranslation([index]);
  }

  /// 重翻这一段的译文(译文菜单里的「重翻这段」):
  /// 先拿掉旧译文再入队,用户能立刻看到骨架屏,知道"这次真的在重翻"。
  void _retranslateChunk(int index) {
    setState(() {
      _translations.remove(index);
      _translationNotes.remove(index);
      _chunkErrors.remove(index);
      _canceledChunks.remove(index);
      _showTranslation = true;
    });
    _enqueueTranslation([index]);
  }

  /// 「继续翻后文」:先翻当前屏幕里还没翻的段;都翻好了就往后取 3 段。
  ///
  /// 为什么先看当前屏:用户在读哪一段,结果就应该出现在哪一段下面,
  /// 而不是从"上次翻到的地方"继续、把结果翻在屏幕外。
  void _translateNext() {
    if (_units.isEmpty) return;
    if (!_api.isConfigured) {
      _toast('还没有配置 API Key —— 到「我的 → API 设置」填一个就能翻译');
      return;
    }
    var resume = false;
    if (!_showTranslation) {
      _showTranslation = true;
      resume = true;
    }
    if (!_autoTranslate) {
      _autoTranslate = true;
      resume = true;
    }
    if (resume) {
      setState(() {});
    }
    final visible = _visibleUnitIndices(limit: _visibleBatch);
    final targets = <int>[
      for (final i in visible)
        if (_canTranslate(i)) i,
    ];
    if (targets.isEmpty) {
      // 当前屏都翻好了 → 从当前屏最后一段的下一段往后翻。
      // 不能从"全局最远一段"往后:那样会跳过用户正在读的中间段;
      // 也不能只看紧邻 3 段:中间可能已经翻过,后面还有没翻的。
      var start = visible.isEmpty ? _unitIndexOfCurrentChunk() : visible.last + 1;
      if (start < 0) start = 0;
      for (var i = start;
          i < _units.length && targets.length < _translateBatch;
          i++) {
        if (_canTranslate(i)) targets.add(i);
      }
    }
    if (targets.isEmpty) {
      _toast('后面的段落都翻好了');
      return;
    }
    _enqueueTranslation(targets);
  }

  /// 当前读到的块 → 该块第一个单元下标(续读/整章的起点)
  int _unitIndexOfCurrentChunk() {
    if (_firstUnitOfChunk.isEmpty) return 0;
    final chunk = _chunks.isEmpty
        ? 0
        : _lastChunkIndex.clamp(0, _chunks.length - 1);
    return _firstUnitOfChunk[chunk].clamp(0, _units.length);
  }

  /// 「整章」:从当前读到的位置往后 20 **段**(没有章节信息时,这是"一章"的近似)。
  ///
  /// 这是用户明确点的批量操作,所以一次性入队;进度条显示真实完成数,
  /// 随时可取消,取消后已翻好的保留。
  void _translateChapter() {
    if (_units.isEmpty) return;
    if (!_api.isConfigured) {
      _toast('还没有配置 API Key —— 到「我的 → API 设置」填一个就能翻译');
      return;
    }
    var resume = false;
    if (!_showTranslation) {
      _showTranslation = true;
      resume = true;
    }
    if (!_autoTranslate) {
      _autoTranslate = true;
      resume = true;
    }
    if (resume) {
      setState(() {});
    }
    final start = _unitIndexOfCurrentChunk().clamp(0, _units.length - 1);
    final end = (start + 19).clamp(0, _units.length - 1);
    final targets = <int>[
      for (var i = start; i <= end; i++)
        if (_canTranslate(i)) i,
    ];
    if (targets.isEmpty) {
      _toast('这一段之后都翻好了');
      return;
    }
    _enqueueTranslation(targets);
  }

  /// 「重试失败段」:一次最多补 6 段,避免网络坏时一按就把几十个请求全发出去。
  void _retryFailedChunks() {
    if (_chunkErrors.isEmpty) return;
    final targets = _chunkErrors.keys.toList()..sort();
    final take = targets.take(6).toList();
    setState(() {
      for (final i in take) {
        _chunkErrors.remove(i);
      }
    });
    _enqueueTranslation(take);
    if (targets.length > take.length) {
      _toast('先重试 ${take.length} 段,还有 ${targets.length - take.length} 段可再点一次');
    }
  }

  /// 滚动停下后,把当前屏幕里还没翻的段补上。
  ///
  /// 为什么保留"随读随翻"而不是只在按下翻译时翻一次:
  /// 阅读是连续往下走的,用户不该每翻一屏就再点一次按钮;
  /// 但只在翻译开着、且没被用户取消时才发生(取消后自动暂停,见
  /// [_cancelAllTranslation])。
  void _scheduleVisibleTranslation() {
    if (!_showTranslation || !_autoTranslate) return;
    if (!_api.isConfigured) return;
    _visibleTimer?.cancel();
    _visibleTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || !_showTranslation || !_autoTranslate) return;
      _enqueueVisible(limit: _visibleBatch);
    });
  }

  void _enqueueVisible({required int limit}) {
    final targets = <int>[
      for (final i in _visibleUnitIndices(limit: limit))
        if (_canTranslate(i)) i,
    ];
    if (targets.isEmpty) return;
    _enqueueTranslation(targets);
  }

  /// 点译文 → 就这一段追问(带原段 + 页面上的译文 + 相邻两段)。
  ///
  /// 复用页面已有的 `FollowUpController`:把 [_followUpChunk] 钉在这一段(单元
  /// 下标),`_buildFollowUpContext` 就会只喂这一段的上下文;问完再点底部「追问」
  /// 会自动清掉这个钉选,回到整篇范围。
  void _askAboutChunk(int index) {
    if (index < 0 || index >= _units.length) return;
    setState(() => _followUpChunk = index);
    showFollowUpDrawer(
      context: context,
      controller: _followUp,
      title: '追问这一段',
      prefillQuestion: _followUpQuestionFor(index),
      // 阅读场景只留两个快捷键(梳理内容 / 评价材料),不再常置
      // 英英词典/逐句翻译等识图场景按钮(2026-11-08 用户反馈)。
      quickReplies: QuickReplies.reader,
    );
  }

  /// 预填的问题:与其让用户从空白输入框开始,不如直接问"这版译文准不准"。
  /// 用户可以改,改完再发 —— 这里**不自动发送**,避免意外消耗额度。
  String _followUpQuestionFor(int index) {
    final hasTranslation = _translations.containsKey(index);
    if (hasTranslation) {
      return '请对照第 ${index + 1} 段的原文检查这段译文:术语、限定、否定、时态和语气'
          '有没有被削弱或改写?逐处说明,并给出更严谨的译法。';
    }
    return '请讲第 ${index + 1} 段:先用准确的中文说清关键术语与句法,再给一版严谨的译文。';
  }

  /// 阅读设置面板:字号 / 行距 —— 边调边生效(不用"确定"按钮),退出时已落盘
  /// 正文前的刊头(C 方案):栏目标签 + 标题 28/1.1/w900/-0.8 + 署名 +
  /// 「2px 粗线 + 1px 细线」的刊头双线,然后才进正文。
  ///
  /// 标题 / 来源 / 难度全部在滚动内容里,下滑会滚走 —— 阅读器顶部不常驻任何信息条
  /// (旧实现是一条永远悬在顶上的信息行 + 30 号标题卡)。
  Widget _readingLead(
    BuildContext context,
    ThemeData theme,
    dynamic a,
    String title,
  ) {
    final p = _palette;
    final t = _type;
    final kind = '${_material?['kind'] ?? 'article'}';
    final wordCount = _intOf(_material?['word_count']);
    final kicker = 'READING · ${MaterialLibrary.kindLabel(kind)}'.toUpperCase();
    final author = '${_material?['author'] ?? ''}'.trim();
    final byline = <String>[
      if (author.isNotEmpty) author,
      if (a != null) a.cefr,
      if (a != null) '约 ${a.estMinutes} 分钟',
      if (a != null) '已知 ${(a.knownTokenRatio * 100).toStringAsFixed(0)}%',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                kicker,
                style: TextStyle(
                  fontSize: t.kicker,
                  height: ReaderType.kickerHeight,
                  letterSpacing: ReaderType.kickerSpacing,
                  fontWeight: FontWeight.w800,
                  color: p.accent,
                ),
              ),
              const Spacer(),
              if (wordCount > 0)
                Text(
                  '$wordCount 词',
                  style: TextStyle(
                    fontSize: t.kicker,
                    height: ReaderType.kickerHeight,
                    letterSpacing: ReaderType.kickerSpacing,
                    fontWeight: FontWeight.w800,
                    color: p.inkFaint,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: t.title,
              height: ReaderType.titleHeight,
              letterSpacing: ReaderType.titleSpacing,
              fontWeight: FontWeight.w900,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            byline.isEmpty ? '正在分析难度…' : byline,
            style: TextStyle(
              fontSize: t.signature,
              height: ReaderType.signatureHeight,
              letterSpacing: ReaderType.signatureSpacing,
              color: p.inkSoft,
            ),
          ),
          const SizedBox(height: 10),
          // 刊头双线:2px 墨线 + 2px 空 + 1px 细线
          Container(height: 2, color: p.ink),
          const SizedBox(height: 2),
          Container(height: 1, color: p.hairline),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  /// 阅读设置(C 版):字号 / 行距 / 纸张三色 + 实时预览卡。
  ///
  /// 三件事:① 改完立刻生效(不用"确定"按钮);② 落 Hive(重启保留);
  /// ③ 纸张是整个阅读器换肤,所以连弹层自己也会跟着换纸(见 readerTheme)。
  Future<void> _showReaderSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReaderSettingsSheet(
        initialPaper: _paper,
        initialFontScale: _fontScale,
        initialLineHeight: _lineHeight,
        onChanged: (paper, scale, height) {
          ReaderSettings.setPaper(paper);
          ReaderSettings.setFontScale(scale);
          ReaderSettings.setLineHeight(height);
          if (!mounted) return;
          setState(() {
            _paper = paper;
            _palette = paletteOf(paper);
            _fontScale = scale;
            _lineHeight = height;
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    // 常驻进度的通知源:页面销毁必须释放,否则定时器/异步回调晚到会报
    // "used after dispose"
    _readingPercent.dispose();
    _stopwatch.stop();
    // 离开页面 = 真的停掉翻译:取消定时器与在途请求。这里不用
    // _stopTranslation(),因为 dispose 期间 setState 会报错。
    _visibleTimer?.cancel();
    _queue.clear();
    for (final token in _chunkTokens.values.toList()) {
      try {
        token.cancel('离开阅读器');
      } catch (_) {}
    }
    _chunkTokens.clear();
    _chunkJobEpoch.clear();
    _activeJobs.clear();
    _pendingChunks.clear();
    // "100% 保留 2 秒"的收条定时器:离开页面必须取消,否则它会在已 dispose
    // 的 State 上 setState(虽然有 mounted 守卫,取消掉更干净)
    _runResetTimer?.cancel();
    _runResetTimer = null;
    // 退出即落盘:用户不需要记着"点保存",进度丢失是最劝退的体验之一
    // (force: 退出这一次不管节流窗口,该存就存)
    _persist(finished: _finished, force: true);
    super.dispose();
  }

  void _onScroll() {
    // 用滚动位置粗估"读到第几块"(每块高度不一,按比例足够用)。
    // v2.13.1:列表项已从"块"变成"段落单元",所以比例要按**单元**算,
    // 再映射回块 —— 否则块索引会整体跑偏(进度/续读位置跟着错)。
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0 || _chunks.isEmpty) return;
    final ratio = (_scrollCtrl.offset / max).clamp(0.0, 1.0);
    // v2.27(C 方案):真实滚动比例 → 常驻进度(右侧胶囊/竖轨 + 贴底 2px 线)。
    // **只**更新 ValueNotifier,不 setState 整屏;未读完最多显示 99%(100% 留给
    // 「读完了」这个动作,否则进度条会假到 100)。
    _lastScrollRatio = ratio;
    _readingPercent.value = _finished ? 1.0 : ratio.clamp(0.0, 0.99);
    if (_units.isEmpty) {
      _lastChunkIndex = (ratio * (_chunks.length - 1)).round();
    } else {
      final unitIdx = (ratio * (_units.length - 1)).round();
      _lastChunkIndex = _units[unitIdx.clamp(0, _units.length - 1)].chunkIndex;
    }
    // v2.9(第 4 条):滚动即自动留存进度(节流在 _persist 里)
    _persist(finished: _finished);
    // v2.12.2:开了翻译就"随读随翻"当前屏(滚动停 450ms 才触发,见
    // _scheduleVisibleTranslation);不再按旧范围一次性翻一大片。
    // 不判断 moved:同一"段"内继续滚动也可能露出新段落,而去抖会合并连续滚动。
    _scheduleVisibleTranslation();
  }

  /// 阅读进度自动留存(v2.9,用户第 4 条"材料中心阅读的那些材料阅读的进度,
  /// 要自动同步留存")。
  ///
  /// 两条去抖规则(改动的初衷是"别把磁盘写爆,也别丢进度"):
  /// 1. **每翻一段必存**:段索引变了就落一次(读数位置是最不能丢的);
  /// 2. 否则**最多每 3 秒一次**:同一段里反复滚动不会每次都写库。
  ///
  /// reading_sessions 单独按"累计读满 5 分钟"落一条 —— 用真实累计时长,
  /// 不用"距上次落盘"的增量(那样读取会很碎)。[force] 用于退出页面时兜底。
  Future<void> _persist({required bool finished, bool force = false}) async {
    if (_chunks.isEmpty) return;
    final now = DateTime.now();
    final movedChunk = _lastPersistIndex != _lastChunkIndex;
    final due = _lastPersistAt == null ||
        now.difference(_lastPersistAt!) >= const Duration(seconds: 3);
    if (!force && !movedChunk && !due) return;
    _lastPersistAt = now;
    _lastPersistIndex = _lastChunkIndex;

    // 会话:读满 5 分钟写一条(统计/周报要读它);退出/读完后把剩下的零头
    // (≥30 秒)也补一条,不然"读了 4 分钟就退出"完全不留痕。
    //
    // ⚠️ 累计值单独记 [_sessionSeconds],不能用 stopwatch.elapsed ——
    // 进度落盘每 3 秒就把秒表清零了,拿它判断"读满 5 分钟"永远不成立。
    final elapsed = _stopwatch.elapsed;
    final seconds = elapsed.inSeconds;
    _sessionSeconds += seconds;
    final worthSession = _sessionSeconds >= 300;
    final finishNow = finished && _sessionSeconds >= 30;
    final tailSession = (finished || force) && _sessionSeconds >= 30;

    final percent = finished
        ? 100.0
        // v2.27(C 方案):落库 percent 改成**真实滚动比例**(见 _lastScrollRatio
        // 在 _onScroll 里的更新),不再按 2500 词一块粗估 —— 典型文章只有 1 块,
        // 旧逻辑写出来永远是 0 或 100,书架/材料中心的进度条因此是死的。
        // 未读完最多 99:100 只留给「读完了」。
        : (_lastScrollRatio * 100).clamp(0.0, 99.0);
    final addMinutes = seconds ~/ 60;
    final addLookups = _lookups;
    final addPicked = _picked;
    final words = _wordCountSoFar();

    // 先落进度(绝对值:position/percent 覆盖,minutes/lookups 累加)
    await DatabaseService.upsertMaterialProgress(
      widget.materialId,
      position: _lastChunkIndex,
      percent: percent,
      addMinutes: addMinutes,
      addLookups: addLookups,
      addPickedWords: addPicked,
      finished: finished,
    );

    // 会话按累计用量落;落完就清零,避免同一次阅读被重复计
    try {
      if (worthSession || tailSession) {
        await DatabaseService.insertReadingSession(
          materialId: widget.materialId,
          words: finishNow ? _intOf(_material?['word_count']) : words,
          lookups: addLookups,
          duration: Duration(seconds: _sessionSeconds),
        );
        _sessionSeconds = 0;
      }
    } catch (e) {
      debugPrint('阅读会话写入失败: $e');
    }

    _stopwatch.reset();
    _stopwatch.start();
    _lookups = 0;
    _picked = 0;
  }

  /// 目录(C 版):按块(章节)列出,每行带**本节阅读 %**,正在读的一行砖红。
  ///
  /// 旧实现是"大字裸列表"(20 号标题 + ListTile + 分割线,只有节名和词数);
  /// C 统一成纸面紧凑行,和阅读控制台里的 3 行目录是同一套视觉。
  Future<void> _showToc() async {
    final titles = <String>[];
    final words = <int>[];
    for (var i = 0; i < _chunks.length; i++) {
      final raw = '${_chunks[i]['title'] ?? ''}'.trim();
      titles.add(raw.isEmpty ? '第 ${i + 1} 节' : raw);
      final text = '${_chunks[i]['text'] ?? ''}';
      words.add(RegExp(r"[A-Za-z']+").allMatches(text).length);
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ReaderTocSheet(
        palette: _palette,
        titles: titles,
        wordCounts: words,
        percents: _chunkPercents(),
        current: _currentChunkIndex(),
        onPick: _scrollToChunk,
      ),
    );
  }

  /// 接着上次读:滚到上次的段(不静默跳转 —— 用户点了「继续」才跳)
  void _scrollToChunk(int index) {
    if (_chunks.length <= 1) return;
    final chunk = index.clamp(0, _chunks.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastChunkIndex = chunk;
      _lastPersistIndex = chunk;
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      if (max <= 0) return;
      // 列表项 = 段落单元:把块映射成"该块第一个单元",再按单元比例跳
      if (_units.isEmpty || _units.length <= 1) {
        _scrollCtrl.jumpTo(0);
        return;
      }
      final unit = _firstUnitOfChunk.length > chunk
          ? _firstUnitOfChunk[chunk].clamp(0, _units.length - 1)
          : 0;
      _scrollCtrl.jumpTo(max * (unit / (_units.length - 1)).clamp(0.0, 1.0));
    });
  }

  /// 有历史进度时的询问(用户第 4 条):「继续 / 从头开始」,不静默跳转。
  ///
  /// C 版:主按钮是 ink 实心胶囊;续读按**真实 percent** 跳(§7.2 Step 5),
  /// 不再按"块比例"跳 —— 典型文章只有 1 块,按块跳等于永远回顶部。
  Future<void> _askResume({
    required Map<String, Object?> progress,
    required int position,
    required int percent,
    required int minutes,
  }) async {
    final finished = progress['finished_at'] != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => ReaderResumeSheet(
        palette: _palette,
        finished: finished,
        percent: percent,
        position: position,
        minutes: minutes,
        onResume: () => Navigator.pop(ctx, 'resume'),
        onRestart: () => Navigator.pop(ctx, 'restart'),
      ),
    );
    if (!mounted) return;
    if (choice == 'resume') {
      _scrollToPercent(percent.toDouble());
    } else if (choice == 'restart' && _scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0);
    }
  }

  /// 按 percent(0~100)跳转 —— 续读的准确入口。
  ///
  /// 列表项高度不一时 `maxScrollExtent` 与内容比例不是严格线性,但比"按块跳"
  /// 准得多;percent 来自落库的真实滚动比例,同一份真值闭环保住了。
  void _scrollToPercent(double percent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      if (max <= 0) return;
      final target = (max * (percent.clamp(0.0, 100.0) / 100)).clamp(0.0, max);
      _scrollCtrl.jumpTo(target);
      _lastScrollRatio = max <= 0 ? 0 : (target / max).clamp(0.0, 1.0);
      _readingPercent.value =
          _finished ? 1.0 : _lastScrollRatio.clamp(0.0, 0.99);
    });
  }

  /// 打开材料:元信息 + 正文分块 + **已存的阅读进度** + **已存的 AI 内容块**。
  ///
  /// v2.9(第 4 条):有进度就**问一句**"继续还是从头"(不静默跳转);
  /// 首开时把 started_at 写进去(统计要算"这本书读了多久")。
  Future<void> _load({bool askResume = true}) async {
    try {
      final material = await DatabaseService.getMaterialById(widget.materialId);
      final chunks = await DatabaseService.getMaterialChunks(widget.materialId);
      final progress =
          await DatabaseService.getMaterialProgress(widget.materialId);
      final savedBlocks = await blocks.loadBlocks(widget.materialId);
      if (!mounted) return;
      // 书架状态(用户 10/4 第 4 条):决定 AppBar 上的 ☆ 是实心还是空心
      unawaited(_loadShelfState());
      MaterialAnalysis? analysis;
      final raw = material?['difficulty'];
      if (raw is Map) {
        analysis = MaterialAnalysis.fromJson(Map<String, Object?>.from(raw));
      }
      final position = _intOf(progress?['position']);
      final percent = _intOf(progress?['percent']);
      final minutes = _intOf(progress?['minutes']);
      final hasProgress = progress != null &&
          (position > 0 || percent > 0 || minutes > 0);
      // v2.13.1:把正文块拆成**真段落单元**(翻译/进度/逐段对照的最小单元)。
      // 拆分是纯函数、一次 O(文本长度),在加载时做一次即可。
      var units = splitUnits(chunks);
      if (units.isEmpty && chunks.isNotEmpty) {
        // 极端兜底:整篇连一个非空段都没有 —— 仍按块建空单元,
        // 保证列表/标题/AI 内容块还能渲染(不能因为"没文字"白屏)
        units = [
          for (var i = 0; i < chunks.length; i++)
            ReaderUnit(chunkIndex: i, paraIndex: 0, text: ''),
        ];
      }
      final firstUnitOfChunk = chunkFirstUnitIndices(units, chunks.length);
      // v2.16.0(阅读器翻译根治第一段):读回**已落库译文** —— "翻过一次就永久在"。
      // 必须用记录里的 source_text 快照做防错位:材料重新导入/切段变化后 unit
      // 下标会漂移,内容对不上的条目不显示(宁可重翻,也不能把 A 段译文挂到 B 段)。
      final savedTranslations =
          await DatabaseService.loadMaterialTranslationRecords(widget.materialId);
      final restored = DatabaseService.alignTranslationsToUnits(
        savedTranslations,
        [for (final u in units) u.text],
      );
      if (!mounted) return;
      setState(() {
        _material = material;
        _chunks = chunks;
        _units = units;
        _firstUnitOfChunk = firstUnitOfChunk;
        _analysis = analysis;
        _blockList = savedBlocks;
        // 已落库译文直接填进 _translations:这些段 _canTranslate=false →
        // **不重复翻**,也不会计入本轮进度分母(分母=本轮真正入队的段数)。
        _translations
          ..clear()
          ..addAll(restored);
        // 重新加载时段数/内容可能变了,上一轮的内存态(错误/取消/提示)全部失效
        _chunkErrors.clear();
        _canceledChunks.clear();
        _translationNotes.clear();
        _lookups = _intOf(progress?['lookups']);
        _picked = _intOf(progress?['picked_words']);
        _lastChunkIndex = position;
        _lastPersistIndex = position;
        _finished = progress?['finished_at'] != null;
        // 保存位置默认值:分类由材料种类映射(书→书籍、新闻→外刊…),
        // 材料名 = 标题 —— 用户不用选,收藏的词也不会掉进「未归类」
        final title = '${material?['title'] ?? ''}'.trim();
        final kind = '${material?['kind'] ?? 'article'}';
        _saveTarget = WordSaveTarget(
          category: MaterialLibrary.categoryOfKind(kind),
          materialName: title,
        );
        _loading = false;
      });
      // v2.27(C 方案):打开时先把**已存真实 percent** 摆到常驻进度上;
      // 用户选「继续」后 _scrollToPercent 会再校准一次。
      // ⚠️ 必须在 setState 之后**立刻**做:如果放在后面的 await(首开写库)之后,
      // 它会晚于滚动监听执行,把用户刚滚出来的进度覆盖回 0 —— 历史 bug。
      _lastScrollRatio = (percent / 100).clamp(0.0, 1.0);
      _readingPercent.value =
          _finished ? 1.0 : _lastScrollRatio.clamp(0.0, 0.99);
      // 首开就写 started_at(upsertMaterialProgress 只在首行写它);
      // 顺带把"这份材料被打开过"变成事实,统计页才看得到。
      if (progress == null) {
        await DatabaseService.upsertMaterialProgress(
          widget.materialId,
          position: position,
          percent: percent.toDouble(),
        );
      }
      _lastPersistAt = DateTime.now();
      // 有进度就问一句(在正文渲染之后弹,用户能看到自己读到哪)
      if (askResume && !_resumeAsked && hasProgress && chunks.isNotEmpty) {
        _resumeAsked = true;
        await _askResume(
          progress: progress,
          position: position,
          percent: percent,
          minutes: minutes,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  int _intOf(Object? v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

  int _wordCountSoFar() {
    final total = _intOf(_material?['word_count']);
    if (total <= 0 || _chunks.isEmpty) return total;
    return (total * ((_lastChunkIndex + 1) / _chunks.length)).round();
  }

  /// 导出这篇材料为 Markdown 阅读包(v2.2):正文 + 元信息 + 生词表,
  /// 带出去在电脑/笔记软件里继续读 —— 材料库不能只进不出。
  Future<void> _exportPack() async {
    try {
      final file = await BackupService.exportMaterialPack(widget.materialId);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('阅读包已导出'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('已写成 Markdown(${file.bytes} 字符),含正文、来源与生词表。'),
              const SizedBox(height: 8),
              SelectableText('文件:${file.path}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: file.content));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                // 用弹窗前取好的 messenger:此时外层 context 可能已随弹窗关闭失效
                messenger.showSnackBar(
                  const SnackBar(content: Text('Markdown 全文已复制')),
                );
              },
              child: const Text('复制全文'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败:$e')),
      );
    }
  }

  Future<void> _finishReading() async {
    _stopwatch.stop();
    await _persist(finished: true);
    if (!mounted) return;
    setState(() => _finished = true);
    // 「读完了」是唯一允许 100% 的动作:常驻进度立刻满格,不再等滚动
    _readingPercent.value = 1.0;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已标记读完 —— 进度与用时已记入学习数据')),
    );
    await _startQuiz();
  }

  /// 读后测验:从材料原文 + 本轮拾取的词本地出题(不花 API、离线可用)
  Future<void> _startQuiz() async {
    final text = _chunks.map((c) => '${c['text'] ?? ''}').join('\n\n');
    final targets = <String>[
      ..._pickedWords,
      ...?_analysis?.topNewWords,
    ];
    if (targets.isEmpty || text.trim().length < 200) {
      // 材料太短或没拾词就不硬出题(卷子没意义比没有卷子更糟)
      return;
    }
    // 有中文释义的拾取词可以用来出"中译英"回想题
    final translations = <String, String>{};
    try {
      for (final w in _pickedWords) {
        final rows = await DatabaseService.getVocabularies(limit: 500);
        final hit = rows.where((v) => v.word.toLowerCase() == w.toLowerCase());
        if (hit.isNotEmpty && (hit.first.translation ?? '').isNotEmpty) {
          translations[w.toLowerCase()] = hit.first.translation!;
        }
      }
    } catch (e) {
      debugPrint('取释义失败(不影响出题): $e');
    }

    final questions = ReadingQuiz.build(
      text: text,
      targetWords: targets,
      translations: translations,
      maxQuestions: 5,
      // seed 用 materialId:同一份材料每次出同一批题,便于复盘
      seed: widget.materialId,
    );
    if (questions.isEmpty || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReadingQuizScreen(
          materialId: widget.materialId,
          title: '${_material?['title'] ?? '材料'}',
          questions: questions,
        ),
      ),
    );
  }

  // ── 点词 / 长按选词:询问 AI 与收藏(v2.7 走公共件,与另外两个阅读器一致)──
  Future<void> _onWordTap(String rawWord, {bool askAi = false}) async {
    final word = rawWord.trim();
    if (word.isEmpty) return;
    _lookups++;
    await showWordActionSheet(
      context,
      word: word,
      sentence: _sentenceAround(word),
      target: _saveTarget,
      autoAsk: askAi,
      sourceTitle: '${_material?['title'] ?? ''}',
      onSave: _saveWord,
    );
  }

  /// 长按选中多个词后的两个选项(用户第 2(2) 条):询问 AI / 收藏进单词本
  void _onSelectionAction(String selection, ReaderTextAction action) {
    _onWordTap(selection, askAi: action == ReaderTextAction.askAi);
  }

  /// 取包含该词的句子(例句给 AI 更准的释义;找不到就给空)
  String _sentenceAround(String word) {
    // 当前块文本里找第一处出现,向前后各扩到句号
    for (final c in _chunks) {
      final text = '${c['text'] ?? ''}';
      final idx = text.toLowerCase().indexOf(word.toLowerCase());
      if (idx < 0) continue;
      final start = text.lastIndexOf(RegExp(r'[.!?\n]'), idx);
      final end = text.indexOf(RegExp(r'[.!?\n]'), idx + word.length);
      final from = start < 0 ? 0 : start + 1;
      final to = end < 0 ? text.length : end + 1;
      final s = text.substring(from, to).trim();
      return s.length > 240 ? s.substring(0, 240) : s;
    }
    return '';
  }

  /// 改「保存位置」(第 3 条):分类 → 材料名 / 页码,复用生词本里的两个选择器
  Future<void> _changeSaveTarget() async {
    final category = await showCategoryPicker(context);
    if (category == null || !mounted) return;
    final sub = await showSubCategoryInput(
      context,
      category: category,
      prefill: _saveTarget.materialName,
    );
    if (sub == null || !mounted) return;
    setState(() {
      _saveTarget = WordSaveTarget(
        category: category,
        materialName: sub.materialName,
        page: sub.sourcePage ?? '',
      );
    });
  }

  /// 打开追问抽屉(第 3 条:追问 AI 是基本逻辑之一)
  void _openFollowUp() {
    // 底部「追问」= 整篇范围:清掉点译文时钉选的段落,否则上下文还停在上一段
    if (_followUpChunk != null) {
      setState(() => _followUpChunk = null);
    }
    showFollowUpDrawer(
      context: context,
      controller: _followUp,
      title: '追问材料',
      quickReplies: QuickReplies.reader,
    );
  }

  // ═══════════ 丰富形式:v2.9(用户第 3(5) 条)═══════════
  //
  // 用户原话:"现在是只有文本模式,而且前端也很单一,需要增加更丰富的形式,
  // 以及支持选择让 ai 根据内容自动输出内容形式 —— 比如读到一篇带有数据的材料,
  // 支持让 ai 在材料中绘出表格啊等等,思维导图呀等等。"
  //
  // 所以入口给两个:**用户自己选**(5 种形式各一句话说明),
  // 或**让 AI 推荐**(先用纯函数 analyzeBestKinds 给出"为什么推荐它",
  // 用户看到依据再决定,而不是一个黑盒按钮)。

  /// 这一段(或整篇)的正文:AiWaitingTimeline 的第一步就是"读取该段正文"
  String _textOfChunk(int index) {
    if (index >= 0 && index < _chunks.length) {
      return '${_chunks[index]['text'] ?? ''}';
    }
    return _chunks.map((c) => '${c['text'] ?? ''}').join('\n\n');
  }

  String _blockKey(int chunkIndex, blocks.MaterialBlockKind kind) =>
      '$chunkIndex:${kind.id}';

  /// 给 AI 的正文:整篇时按段拼接并截断(一本书不能整本塞进提示词)
  String _sourceFor(int chunkIndex) {
    final text = _textOfChunk(chunkIndex).trim();
    if (text.length <= 6000) return text;
    return '${text.substring(0, 6000)}\n…(原文过长,以上为前 6000 字)';
  }

  Future<void> _openRichForms() async {
    if (_chunks.isEmpty) return;
    // 2026-11-08 用户反馈:点「丰富形式」后页面跳到全材料最下方。这里除了
    // 保持"弹 sheet 选形式"(不再有其它滚动逻辑),还兜底:sheet 关闭后如果
    // 阅读位置被动过(比如列表因插入生成骨架而 relayout),恢复原位置 ——
    // 用户只是选格式,不该被挪走。
    final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _RichFormsSheet(
        current: _lastChunkIndex,
        source: _sourceFor(_lastChunkIndex),
        existing: _blockList,
        onPick: (kind, chunkIndex) {
          Navigator.pop(ctx);
          _generateBlock(kind, chunkIndex);
        },
      ),
    );
    if (!mounted || !_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return;
    final target = offset.clamp(0.0, max);
    if ((_scrollCtrl.offset - target).abs() > 1) {
      _scrollCtrl.jumpTo(target);
    }
  }

  /// 生成一个内容块:进度用 AiWaitingTimeline(三步都是**真实发生**的),
  /// 失败给可重试的错误卡 —— 全程不转圈。
  Future<void> _generateBlock(
    blocks.MaterialBlockKind kind, [
    int? chunkIndex,
  ]) async {
    final at = chunkIndex ?? _lastChunkIndex;
    final key = _blockKey(at, kind);
    setState(() {
      _blockWaiting = key;
      _blockErrors.remove(key);
    });
    try {
      final result = await blocks.generateBlocks(
        materialId: widget.materialId,
        text: _sourceFor(at),
        kind: kind,
        chunkIndex: at,
      );
      if (!mounted) return;
      if (!result.ok || result.draft == null) {
        setState(() {
          _blockWaiting = null;
          _blockErrors[key] = result.error ?? '生成失败';
        });
        return;
      }
      final draft = result.draft!;
      setState(() {
        _blockWaiting = null;
        // 同段同类型只留一条(upsert 落库也是这个口径)
        _blockList = [
          for (final b in _blockList)
            if (!(b.chunkIndex == draft.chunkIndex && b.kind == draft.kind)) b,
          draft,
        ]..sort((a, b) {
            final c = a.chunkIndex.compareTo(b.chunkIndex);
            return c != 0 ? c : (a.id ?? 0).compareTo(b.id ?? 0);
          });
      });
      if (result.note.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${kind.label}已生成 —— ${result.note}')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${kind.label}已生成,就在第 ${at + 1} 段下面')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _blockWaiting = null;
        _blockErrors[key] = '$e';
      });
    }
  }

  /// 删掉一个块(库里的那条也删)
  Future<void> _deleteBlock(blocks.MaterialBlockDraft block) async {
    final key = _blockKey(block.chunkIndex, block.kind);
    setState(() {
      _blockList = [
        for (final b in _blockList)
          if (!(b.chunkIndex == block.chunkIndex && b.kind == block.kind)) b,
      ];
      _blockErrors.remove(key);
    });
    await blocks.removeBlock(widget.materialId, block.kind, block.chunkIndex);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除这个${block.kind.label}')),
    );
  }

  /// 重新生成同一个块(头部的小刷新按钮)
  void _regenerateBlock(blocks.MaterialBlockDraft block) {
    _generateBlock(block.kind, block.chunkIndex);
  }

  /// 「收词」= 把本次收的词再确认一遍(给用户一个明确的收口)
  void _showPickedSummary() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ReaderPickedSheet(
        palette: _palette,
        words: _pickedWords,
        saveTargetLabel: _saveTarget.label,
        onChangeTarget: _changeSaveTarget,
      ),
    );
  }

  Future<String> _saveWord(Vocabulary v) async {
    try {
      await context.read<VocabProvider>().saveVocabularies([v]);
      // 入库同时建立复习状态 → 立刻进复习队列(v2.0 起 word_review 是单一事实源)
      final saved = await DatabaseService.getVocabularies(limit: 200);
      final hit = saved.where((e) => e.word == v.word).toList();
      if (hit.isNotEmpty && hit.first.id != null) {
        await DatabaseService.upsertWordReview(
          hit.first.id!,
          stability: 0,
          difficulty: 5,
          dueAt: DateTime.now(),
          lastReviewAt: DateTime.now(),
        );
      }
      _picked++;
      if (!_pickedWords.any((w) => w.toLowerCase() == v.word.toLowerCase())) {
        _pickedWords.add(v.word);
      }
      if (mounted) setState(() {});
      return '已收进生词本(存到 ${_saveTarget.label})';
    } catch (e) {
      return '保存失败:$e';
    }
  }

  /// 是否已在书架(用户 10/4 第 4 条)
  bool _onShelf = false;

  /// 这次进来是否已经问过"放进书架?"(退出时只问一次,不烦人)
  bool _askedShelf = false;

  /// 材料 id(书架/收藏都要用)
  int? get _materialId {
    final v = _material?['id'];
    return v is int ? v : int.tryParse('$v');
  }

  Future<void> _loadShelfState() async {
    final id = _materialId;
    if (id == null) return;
    final on = await DatabaseService.isOnBookshelf(id);
    if (!mounted) return;
    setState(() => _onShelf = on);
  }

  Future<void> _toggleShelf() async {
    final id = _materialId;
    if (id == null) return;
    if (_onShelf) {
      await DatabaseService.removeFromBookshelf(id);
      if (!mounted) return;
      setState(() => _onShelf = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('已从书架移出'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    await DatabaseService.addToBookshelf(id);
    if (!mounted) return;
    setState(() => _onShelf = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已放上书架 —— 在「材料中心 → 书架」里能看到它'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 收藏这篇材料(进「文章」收藏夹)
  Future<void> _bookmarkCurrent() async {
    final title = '${_material?['title'] ?? ''}';
    if (title.isEmpty) return;
    final bp = context.read<BookmarkProvider>();
    final firstChunks = _chunks
        .take(3)
        .map((c) => '${c['text'] ?? ''}')
        .where((t) => t.trim().isNotEmpty)
        .join('\n\n');
    final saved = await bp.toggle(
      Bookmark(
        source: AppConstants.bookmarkSourceArticle,
        title: title,
        content: '${_material?['url'] ?? ''}\n\n$firstChunks'.trim(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? '已收藏到「文章」收藏夹' : '已取消收藏'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 退出阅读器时的三选一(用户 10/4 第 4 条原话:
  /// "在退出材料中心里的文章时,发出提问'放进书架?'or'不了,就看看'or'放进收藏夹'")。
  ///
  /// 只在"真读过一点"且**还没在书架上**时问 —— 刚点开就退出不问,已经在架子上的也不问。
  Future<void> _askShelfOnExit() async {
    final id = _materialId;
    if (id == null || _askedShelf || _onShelf) return;
    if (_chunks.isEmpty) return;
    _askedShelf = true;
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('这篇要留下吗?',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '放进书架 = 以后在「材料中心 → 书架」里一眼看见、接着读',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: const Text('放进书架'),
              subtitle: const Text('摆到架子上,带进度'),
              onTap: () => Navigator.pop(ctx, 'shelf'),
            ),
            ListTile(
              leading: const Icon(Icons.star_border),
              title: const Text('放进收藏夹'),
              subtitle: const Text('收藏到「文章」分区'),
              onTap: () => Navigator.pop(ctx, 'bookmark'),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('不了,就看看'),
              onTap: () => Navigator.pop(ctx, 'none'),
            ),
            const SizedBox(height: Gap.xs),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'shelf') {
      await _toggleShelf();
    } else if (choice == 'bookmark') {
      await _bookmarkCurrent();
    }
  }

  /// 「更多」菜单的动作分发(v2.7)
  void _onMoreAction(String v) {
    switch (v) {
      case 'link':
        final url = '${_material?['url'] ?? ''}';
        if (url.trim().isNotEmpty) _openSourceLink(url);
      case 'settings':
        _showReaderSettings();
      case 'toc':
        _showToc();
      case 'dictation':
        if (_chunks.isEmpty) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DictationScreen(
              title: '${_material?['title'] ?? '材料'}',
              text: _chunks.map((c) => '${c['text'] ?? ''}').join('\n\n'),
            ),
          ),
        );
      case 'export':
        if (_chunks.isNotEmpty) _exportPack();
      case 'finish':
        _finishReading();
    }
  }

  /// 打开原文链接(第 2(1) 条:软件内读 + 原文链接两条路)
  Future<void> _openSourceLink(String url) async {
    final ok = await launchExternalUrl(url);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打不开这个链接:$url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    // C 方案:阅读器**局部**换肤(不改全局 v4_theme)。所有从这个页面弹出的
    // 共享弹层(查词 word_action_sheet / 追问抽屉 / 分类选择器)包进这层 Theme
    // 后也会跟着纸色走,不需要去改别人的文件。
    final theme = readerTheme(context, p);
    final title = '${_material?['title'] ?? '阅读'}';
    final a = _analysis;
    return Theme(
      data: theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // 墨夜纸上要浅色状态栏图标
        value: p.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final nav = Navigator.of(context);
            await _askShelfOnExit();
            if (!mounted) return;
            // 让最后一笔进度先落盘,再退出
            await _persist(finished: _finished, force: true);
            nav.pop();
          },
          child: Scaffold(
            backgroundColor: p.page,
            // C 方案:没有 AppBar、没有 FAB、没有底部动作栏 ——
            // 只有正文 + 左上返回圆钮 + 右侧进度胶囊/竖轨 + 贴底 2px 线与 42px 把手区。
            body: _loading
                ? _buildLoadingBody(p)
                : _error != null
                    ? _buildErrorBody(p)
                    : _buildReaderBody(theme, p, title, a),
          ),
        ),
      ),
    );
  }

  /// 打开中的骨架(C 版:纸面上直接摆出正文将占的位置,不用转圈)
  Widget _buildLoadingBody(ReaderPalette p) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 20, 20),
        children: <Widget>[
          Text(
            '正在打开材料…',
            style: TextStyle(fontSize: 10.5, color: p.inkFaint),
          ),
          const SizedBox(height: 14),
          const SkeletonLines(lines: 6, seed: 0),
          const SizedBox(height: 20),
          const SkeletonLines(lines: 4, withTitle: false, seed: 1),
        ],
      ),
    );
  }

  Widget _buildErrorBody(ReaderPalette p) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 20, 20),
        child: AppErrorCard(
          message: '打不开这份材料:$_error',
          onRetry: () {
            setState(() {
              _loading = true;
              _error = null;
            });
            _load();
          },
        ),
      ),
    );
  }

  /// C 方案正文区
  Widget _buildReaderBody(
    ThemeData theme,
    ReaderPalette p,
    String title,
    MaterialAnalysis? a,
  ) {
    final playable =
        AudioService.looksPlayable(_material?['audio_url'] as String?);
    return SafeArea(
      bottom: false,
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              // 顶部安全条:返回圆钮独占一条纸色顶条,正文从它下面开始滚
              // —— 悬浮圆钮在任何滚动位置都会压住第一行字(用户截图里
              // "What multitasking..." 被圆钮盖住),这里用让位彻底解决。
              _readerTopBar(p),
              if (playable)
                AudioPlayerBar(
                  url: '${_material!['audio_url']}',
                  title: '${_material!['title'] ?? ''}',
                ),
              // 翻译进度:一条 2px 细线,不占正文、不压正文
              // (旧实现是 93px 的实底灰带,见 _buildTranslationTray 的历史)
              if (_showTranslation) _translationHintLine(p),
              Expanded(
                child: ListView.builder(
                  // 用列表视口的真实矩形判断"哪几段可见"(见 _visibleUnitIndices)
                  key: _listKey,
                  controller: _scrollCtrl,
                  // 第三轮整改(用户真机第 2 条):竖轨改成**悬浮 overlay**,
                  // 不再用 46px 挤压正文。左右 16/20、上下 4/18 —— 390 宽下
                  // 正文宽度 318 → 354px;右侧 20 里有 10px 是竖轨安全区。
                  padding: const EdgeInsets.fromLTRB(16, 4, 20, 18),
                  itemCount: _units.length + 1,
                  itemBuilder: (_, index) => index == 0
                      ? _readingLead(context, theme, a, title)
                      : _buildUnit(theme, index - 1),
                ),
              ),
              // 贴底 2px 进度线 + 42px 把手区:零常驻按钮
              ReaderBottomDock(
                progress: _readingPercent,
                palette: p,
                onOpenConsole: _openConsole,
                bottomInset: MediaQuery.viewPaddingOf(context).bottom,
              ),
            ],
          ),
          // 96px 竖轨悬浮在正文右侧安全区之上(3px,不挤压正文、不遮字);
          // 右 4 + 12px 透明热区,点轨道也能打开控制台。
          Positioned(
            top: 0,
            bottom: 0,
            right: 4,
            child: Align(
              alignment: const Alignment(0, -0.18),
              child: ReaderProgressRail(
                progress: _readingPercent,
                palette: p,
                onTap: _openConsole,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部安全条(C 方案):返回圆钮 + 右侧 % 胶囊,纸色底给正文让位。
  ///
  /// 「零常驻按钮」说的是**底部**(动作全部收进控制台);返回是导航必需,
  /// 但它不能浮在正文上面 —— 这里固定一条 40px 纸色顶条,正文从顶条下沿
  /// 开始滚,任何滚动位置都不会有按钮压字。
  ///
  /// 第三轮整改(用户真机第 2 条):原来的右侧「% 胶囊 + 竖轨」为让位把正文
  /// 挤窄了 46px。现在**胶囊进顶条右侧**(悬浮在纸上、不压任何字),竖轨只剩
  /// 3px 悬浮在正文右侧安全区(见 reader_progress.dart)。
  Widget _readerTopBar(ReaderPalette p) {
    return Container(
      height: 40,
      width: double.infinity,
      color: p.page,
      padding: const EdgeInsets.only(left: 12, right: 10),
      child: Row(
        children: <Widget>[
          ReaderCircleButton(
            icon: Icons.arrow_back_ios_new,
            size: 14,
            palette: p,
            onTap: () async {
              final nav = Navigator.of(context);
              await _askShelfOnExit();
              if (!mounted) return;
              await _persist(finished: _finished, force: true);
              nav.pop();
            },
          ),
          const Spacer(),
          ReaderProgressBadge(
            progress: _readingPercent,
            palette: p,
            onTap: _showProgressJumpMenu,
          ),
        ],
      ),
    );
  }

  /// 就地译文区(C 方案):紧贴这一段原文下方 —— 左侧 2px 砖红竖线 +
  /// 「中译」小标 + 13.5/1.8 的次要文字色译文。
  ///
  /// 三件事**不做**,否则阅读会被打断:
  /// - 不加整块底色(会和正文抢注意力,深色下还会变成一块亮色);
  /// - 不把"重翻"做成大按钮(只有失败时才出现一行可点的「重试」);
  /// - 不弹任何浮层(译文就在原位置出现/消失,不推走上面的正文)。
  ///
  /// 点译文本身 = 追问这一段(带原文 + 译文上下文);右侧「…」里是
  /// 追问 / 重翻这段 —— 重翻只重发这一段,不影响其它段。
  Widget _buildTranslationArea(ThemeData theme, int index) {
    final p = _palette;
    final t = _type;
    final translation = _translations[index];
    final error = _chunkErrors[index];
    final note = _translationNotes[index];
    final pending = _pendingChunks.contains(index);

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, size: 14, color: p.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Tooltip(
                message: error,
                child: Text(
                  '这段没翻出来',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: p.inkFaint),
                ),
              ),
            ),
            _MiniAction(
              label: '重试',
              palette: p,
              onTap: () => _retryChunk(index),
            ),
          ],
        ),
      );
    }

    if (_canceledChunks.contains(index)) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.translate, size: 14, color: p.inkFaint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '这段的翻译已取消',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: p.inkFaint),
              ),
            ),
            _MiniAction(
              label: '重试',
              palette: p,
              onTap: () => _retryChunk(index),
            ),
          ],
        ),
      );
    }

    if (pending && translation == null) {
      // 便签骨架:先摆出译文的形状,不转圈
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          decoration: BoxDecoration(
            color: p.transBg,
            border: Border(left: BorderSide(color: p.accent, width: 2)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SkeletonLines(
                lines: 2,
                withTitle: false,
                lineHeight: 10,
                seed: index,
              ),
              const SizedBox(height: 2),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '正在翻译这段…',
                      style: TextStyle(fontSize: 9.5, color: p.inkFaint),
                    ),
                  ),
                  _MiniAction(
                    label: '取消这段',
                    palette: p,
                    onTap: () => _cancelChunkTranslation(index),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (translation == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        decoration: BoxDecoration(
          color: p.transBg,
          border: Border(left: BorderSide(color: p.accent, width: 2)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Text(
                '中译',
                style: TextStyle(
                  fontSize: ReaderType.transLabel,
                  height: 1.2,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                  color: p.accent,
                ),
              ),
            ),
            Expanded(
              child: Tooltip(
                message: '点译文可追问 AI;右侧「…」可重翻这一段',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _askAboutChunk(index),
                  child: Padding(
                    padding:
                        const EdgeInsets.only(top: 1, bottom: 2, right: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          translation,
                          style: TextStyle(
                            fontSize: t.translation,
                            height: ReaderType.translationHeight,
                            color: p.inkSoft,
                          ),
                        ),
                        // v2.13.1:模型段数对不上时的提示(**不能再静默丢弃**)
                        if (note != null && note.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '可能不完整:$note',
                            style: TextStyle(
                              fontSize: 9.5,
                              height: 1.3,
                              color: p.accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 操作只留一个「…」,不占版面;点译文本身已经是"追问这段"
            PopupMenuButton<String>(
              tooltip: '译文操作',
              padding: EdgeInsets.zero,
              iconSize: 16,
              color: p.sheet,
              icon: Icon(Icons.more_horiz, size: 16, color: p.inkFaint),
              onSelected: (v) {
                if (v == 'ask') {
                  _askAboutChunk(index);
                } else if (v == 'retry') {
                  _retranslateChunk(index);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'ask',
                  height: 38,
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 16, color: p.inkSoft),
                      const SizedBox(width: 8),
                      Text('追问这段', style: TextStyle(fontSize: 13, color: p.ink)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'retry',
                  height: 38,
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 16, color: p.inkSoft),
                      const SizedBox(width: 8),
                      Text('重翻这段', style: TextStyle(fontSize: 13, color: p.ink)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 生词高亮集合(小写):来自材料的 `top_new_words` 分析结果。
  ///
  /// C 方案口径:只有**真生词**画砖红实线 + w600;其余词保持墨色(仍可点)。
  /// 旧实现给每个英文词都画下划线,一屏几十条红线 = 没有重点、字面脏,
  /// 这也是"字体非常差"的一部分。
  Set<String> get _highlightWords => <String>{
        for (final w in _analysis?.topNewWords ?? const <String>[])
          w.toLowerCase(),
      };

  /// 渲染一个**段落单元**(列表项 = 真段落,不再是 2500 词的正文块)。
  ///
  /// 块独有的东西只出现在块的边界上:
  /// - 块标题(`chunk.title`)挂在该块第一个单元上方(C 的"栏目标签"式小标);
  /// - AI 内容块(表格/导图…)挂在该块最后一个单元之后。
  ///
  /// C 排印:**首段 20/1.82(导语),其余 18 号 × 用户字号档 / 用户行距档**;
  /// 生词 = 墨色词 + 砖红实线下划线(不再是全词主色 + 虚线,那种"满屏蓝链接"
  /// 正是用户说的"字体非常差"的原因之一)。
  Widget _buildUnit(ThemeData theme, int index) {
    final p = _palette;
    final t = _type;
    final unit = _units[index];
    final chunkIndex = unit.chunkIndex;
    final chunkTitle = _chunks[chunkIndex]['title'];
    final isFirstOfChunk = _firstUnitOfChunk.length > chunkIndex &&
        _firstUnitOfChunk[chunkIndex] == index;
    final isLastOfChunk =
        index + 1 >= _units.length || _units[index + 1].chunkIndex != chunkIndex;
    final isLead = index == 0;
    final bodyStyle = TextStyle(
      fontSize: isLead ? t.lead : t.body,
      height: isLead ? ReaderType.leadHeight : _lineHeight,
      letterSpacing: isLead ? 0.1 : 0.05,
      color: p.ink,
    );
    // v2.9(第 3(5) 条):这个块挂着的 AI 内容块(表格/导图/时间线/要点/自测)
    final chunkBlocks = [
      for (final b in _blockList)
        if (b.chunkIndex == chunkIndex) b,
    ];
    // 正在生成的那一个(只在块末尾显示一次等待时间线,不重复)
    final waitingKey = _blockWaiting;
    final waitingHere = waitingKey != null &&
        waitingKey.startsWith('$chunkIndex:') &&
        chunkBlocks.every((b) => _blockKey(chunkIndex, b.kind) != waitingKey);
    final waitingKind = waitingHere
        ? blocks.MaterialBlockKind.byId(waitingKey.split(':').last)
        : null;
    return Padding(
      // 每个单元挂一个稳定 key:滚动停下的"可见段"判断要拿它的 RenderBox
      key: _unitKey(index),
      padding: EdgeInsets.only(bottom: isLastOfChunk ? 18 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (isFirstOfChunk &&
              chunkTitle is String &&
              chunkTitle.trim().isNotEmpty) ...[
            Text(
              chunkTitle.trim(),
              style: TextStyle(
                fontSize: 10.5,
                height: 1.2,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: p.inkFaint,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (unit.text.isNotEmpty)
            TappablePassage(
              text: unit.text,
              onWordTap: _onWordTap,
              onSelectionAction: _onSelectionAction,
              style: bodyStyle,
              wordColor: p.ink,
              underlineColor: p.accent,
              underlineThickness: isLead ? 1.6 : 1.5,
              highlightWords: _highlightWords,
            ),
          // 逐段译文:紧贴**这一段**原文下方,不挪版面、不弹浮层。
          if (_showTranslation) _buildTranslationArea(theme, index),
          // ── AI 内容块:插在块末尾,与正文用留白 + 卡片分开 ──
          if (isLastOfChunk && waitingHere && waitingKind != null) ...[
            const SizedBox(height: 10),
            MaterialBlockWaiting(kind: waitingKind),
          ],
          if (isLastOfChunk)
            for (final b in chunkBlocks) ...[
              const SizedBox(height: 8),
              if (_blockErrors[_blockKey(chunkIndex, b.kind)] != null)
                MaterialBlockErrorCard(
                  message: _blockErrors[_blockKey(chunkIndex, b.kind)]!,
                  onRetry: () => _regenerateBlock(b),
                )
              else
                MaterialBlockView(
                  block: b,
                  onDelete: () => _deleteBlock(b),
                  onRegenerate: () => _regenerateBlock(b),
                ),
            ],
        ],
      ),
    );
  }
}


/// 译文卡里的小动作(重试 / 取消这段):9.5 号、无按钮壳、只占一行
class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.label,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 26),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: palette.accent,
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 9.5)),
    );
  }
}

/// 「丰富形式」选择弹层(v2.9,用户第 3(5) 条)。
///
/// 两件事同时给用户:
/// 1. **自己选** —— 五种形式各一行(图标 + 名称 + 一句话说明);
/// 2. **让 AI 推荐** —— 点一下先展开 [blocks.analyzeBestKinds] 算出的
///    "为什么推荐它"(如"这篇有 12 处数字,适合做成表格"),用户看到依据
///    再点生成,而不是盲点一个黑盒按钮。
class _RichFormsSheet extends StatefulWidget {
  /// 当前读到第几段(默认就整理这一段)
  final int current;

  /// 当前段的正文(用来算推荐依据)
  final String source;
  final List<blocks.MaterialBlockDraft> existing;
  final void Function(blocks.MaterialBlockKind kind, int chunkIndex) onPick;

  const _RichFormsSheet({
    required this.current,
    required this.source,
    required this.existing,
    required this.onPick,
  });

  @override
  State<_RichFormsSheet> createState() => _RichFormsSheetState();
}

class _RichFormsSheetState extends State<_RichFormsSheet> {
  bool _showReasons = false;
  late final List<blocks.KindSuggestion> _suggestions =
      blocks.analyzeBestKinds(widget.source);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final here = [
      for (final b in widget.existing)
        if (b.chunkIndex == widget.current) b,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: Gap.xs),
                  Text(
                    '丰富阅读形式',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xxs),
              Text(
                '把第 ${widget.current + 1} 段的正文交给 AI 重新组织,'
                '生成的内容会排在这一段下面(原文不动)。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: muted, height: 1.5),
              ),
              const SizedBox(height: Gap.sm),

              // ── 让 AI 推荐 ──
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _showReasons = !_showReasons),
                  icon: Icon(
                    _showReasons ? Icons.expand_less : Icons.auto_fix_high,
                    size: 18,
                  ),
                  label: Text(_showReasons ? '收起推荐依据' : '让 AI 推荐(先说为什么)'),
                ),
              ),
              if (_showReasons) ...[
                const SizedBox(height: Gap.xs),
                Container(
                  padding: const EdgeInsets.all(Gap.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(12),
                    borderRadius: Radii.controlRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '按这一段的文字特征算出来的推荐(点一行就能生成):',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted, height: 1.4),
                      ),
                      const SizedBox(height: Gap.xs),
                      for (final s in _suggestions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Gap.xxs),
                          child: InkWell(
                            borderRadius: Radii.controlRadius,
                            onTap: () => widget.onPick(s.kind, widget.current),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: Gap.xs, vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(s.kind.icon,
                                      size: 15,
                                      color: MaterialBlockView.accentOf(
                                          context, s.kind)),
                                  const SizedBox(width: Gap.xs),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(height: 1.45),
                                        children: [
                                          TextSpan(
                                            text: '${s.kind.label}  ',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700),
                                          ),
                                          TextSpan(
                                            text: s.why,
                                            style: TextStyle(color: muted),
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
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Gap.sm),

              // ── 自己选 ──
              for (final kind in blocks.MaterialBlockKind.values) ...[
                _kindTile(context, kind, here.any((b) => b.kind == kind)),
                const SizedBox(height: Gap.xs),
              ],

              // ── 这一段已有哪些块 ──
              if (here.isNotEmpty) ...[
                const SizedBox(height: Gap.xxs),
                Text(
                  '这一段已有:${here.map((b) => b.kind.label).join('、')}'
                  '(再生成同一种会覆盖它)',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: muted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindTile(BuildContext context, blocks.MaterialBlockKind kind, bool exists) {
    final theme = Theme.of(context);
    final accent = MaterialBlockView.accentOf(context, kind);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
      borderRadius: Radii.controlRadius,
      child: InkWell(
        borderRadius: Radii.controlRadius,
        onTap: () => widget.onPick(kind, widget.current),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(kind.icon, size: 16, color: accent),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          kind.label,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (exists) ...[
                          const SizedBox(width: Gap.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: accent.withAlpha(28),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '已有',
                              style: TextStyle(fontSize: 10, color: accent),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      kind.hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
