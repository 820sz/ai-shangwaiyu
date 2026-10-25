import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/bookmark.dart';
import '../../models/vocabulary.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../services/audio_service.dart';
import '../../services/backup_service.dart';
import '../../services/database.dart';
import '../../services/deepseek_api.dart';
import '../../services/external_link.dart';
import '../../services/material_library.dart';
import '../../services/material_blocks.dart' as blocks;
import '../../services/reader_settings.dart';
import '../../services/reading_quiz.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/material_blocks.dart';
import '../../widgets/reader_action_bar.dart';
import '../../widgets/reader_text.dart';
import '../../widgets/waiting.dart';
import '../../widgets/word_action_sheet.dart';
import 'dictation_screen.dart';
import 'reading_quiz_screen.dart';
import 'widgets/category_picker.dart';
import 'widgets/follow_up_drawer.dart';
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
  const MaterialReaderScreen({super.key, required this.materialId});

  @override
  State<MaterialReaderScreen> createState() => _MaterialReaderScreenState();
}

class _MaterialReaderScreenState extends State<MaterialReaderScreen> {
  final _scrollCtrl = ScrollController();
  final _stopwatch = Stopwatch();

  Map<String, Object?>? _material;
  List<Map<String, Object?>> _chunks = const [];
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

  /// 段索引 → 中文译文。译文只存内存:材料正文才是事实源,译文是"读的辅助",
  /// 下次打开重翻即可(写库要改表结构,不在本次范围)。
  final Map<int, String> _translations = {};

  /// 段索引 → 失败原因(该段可单独重试;没有失败 = 空)
  final Map<int, String> _chunkErrors = {};

  /// 用户主动取消了这一段的翻译(不是失败 —— 不重试、也不自动重翻;
  /// 段落下面给一行「已取消 · 重试」,想翻再点)
  final Set<int> _canceledChunks = {};

  /// 正在排队/在途的段。**用集合而不是布尔**:判断"这一段是否在等译文"是
  /// 逐段 UI(骨架屏 / 取消按钮)的唯一依据。
  final Set<int> _pendingChunks = {};

  /// 待翻队列(严格按用户看到的顺序)
  final List<int> _queue = [];

  /// 在途请求(并发上限 [_translateConcurrency]);键 = 段索引
  final Map<int, CancelToken> _chunkTokens = {};

  /// 每一段的作业代号:取消/重排后旧请求回来时,靠它丢弃过期结果
  final Map<int, int> _chunkJobEpoch = {};
  int _epochSeq = 0;

  /// 在途请求(键 = 段索引,值 = 本次作业号)。
  /// 用 Map 而不是单纯计数:取消某段/停止整轮后旧请求晚回来时,
  /// 靠作业号判断"这个并发位还是不是它的",不会把新任务的槽位一起吞掉。
  final Map<int, int> _activeJobs = {};
  int _jobSeq = 0;

  /// 本轮「一轮翻译」的段数与已完成数(进度条 = 已完成 / 本轮总数)
  int _runTotal = 0;
  int _runDone = 0;
  DateTime? _runStartedAt;

  /// 用户点了「取消」之后暂停"随读随翻";点「继续翻后文/整章」会重新打开
  bool _autoTranslate = true;

  /// 滚动停下来 450ms 再算"哪几段在屏幕里" —— 滚动中每帧算 RenderBox
  /// 会在低端机上掉帧,而且一停就翻会让用户看到一串骨架同时出现。
  Timer? _visibleTimer;

  /// 列表的 key(用它的视口矩形判断段落是否真的可见,而不是按滚动比例猜)
  final GlobalKey _listKey = GlobalKey();

  /// 每个段落的 key(同上)
  final Map<int, GlobalKey> _chunkKeys = {};

  /// 点译文追问时,把追问范围钉在这一段;null = 整篇
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

  /// 追问时的材料上下文。
  ///
  /// 两种范围:
  /// - 整篇(底部「追问」):标题 + 难度 + 正文节选(太长会挤爆提示词);
  /// - 单段(点译文):**只带这一段**的原文 + 页面上显示的中文译文,外加
  ///   前后各一段原文(仅用于判断代词与术语,明确告诉模型不要翻)。
  ///
  /// 为什么单段要单独喂:用户点译文想问的是"这里为什么这么译/有没有译错",
  /// 把整篇 6000 字节选塞进去,模型会去总结全文,反而答不到这一句上。
  String _buildFollowUpContext() {
    final title = '${_material?['title'] ?? ''}';
    final a = _analysis;
    final head = StringBuffer()
      ..writeln('材料:$title')
      ..writeln('来源:${_material?['url'] ?? '（无链接）'}');
    if (a != null) {
      head.writeln('篇幅 ${a.wordCount} 词 · ${a.cefr} · '
          '我的已知词覆盖率 ${(a.knownTokenRatio * 100).toStringAsFixed(1)}%');
    }
    final at = _followUpChunk;
    if (at != null && at >= 0 && at < _chunks.length) {
      String clip(String s, int max) =>
          s.length <= max ? s : '${s.substring(0, max)}…';
      final row = _chunks[at];
      final original = '${row['text'] ?? ''}'.trim();
      final subtitle = '${row['title'] ?? ''}'.trim();
      final previous = at > 0 ? '${_chunks[at - 1]['text'] ?? ''}'.trim() : '';
      final next = at + 1 < _chunks.length
          ? '${_chunks[at + 1]['text'] ?? ''}'.trim()
          : '';
      final translation = _translations[at];
      final body = StringBuffer()
        ..writeln('这次追问只针对第 ${at + 1}/${_chunks.length} 段。');
      if (subtitle.isNotEmpty) body.writeln('小标题:$subtitle');
      if (previous.isNotEmpty) {
        body
          ..writeln('\n上一段原文(只用于理解指代/术语,不要翻译):')
          ..writeln(clip(previous, 800));
      }
      body
        ..writeln('\n本段原文:')
        ..writeln(clip(original, 2000));
      if (translation != null && translation.trim().isNotEmpty) {
        body
          ..writeln('\n页面上的中文译文:')
          ..writeln(clip(translation, 2000));
      } else {
        body.writeln('\n页面上的这一段还没有中文译文。');
      }
      if (next.isNotEmpty) {
        body
          ..writeln('\n下一段原文(只用于理解指代/术语,不要翻译):')
          ..writeln(clip(next, 800));
      }
      return '${head.toString()}\n$body';
    }
    final body = StringBuffer();
    for (final c in _chunks) {
      final t = '${c['text'] ?? ''}';
      if (body.length + t.length > 6000) break;
      body.writeln(t);
    }
    return '${head.toString()}\n正文节选:\n$body';
  }

  @override
  void initState() {
    super.initState();
    _fontScale = ReaderSettings.fontScale();
    _lineHeight = ReaderSettings.lineHeight();
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
    if (_chunks.isEmpty) return;
    if (!DeepseekApiService().isConfigured) {
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

  /// 哪些段落**真的在屏幕里**:用列表视口与每个段落的 RenderBox 求交,
  /// 而不是按滚动比例猜 —— 一本书的段落高度差别很大,比例法会把没读到的段
  /// 当成"当前段"(旧实现"选取的范围也是乱的"就有这个原因)。
  ///
  /// [limit] 限制这次最多翻几段:打开翻译先给眼前最多 5 段,
  /// 避免一开就排队几十个请求。
  List<int> _visibleChunkIndices({int limit = _visibleBatch}) {
    final viewport = _listKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      return _fallbackVisible(limit);
    }
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    final hits = <int>[];
    for (final entry in _chunkKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height <= top || y >= bottom) continue;
      hits.add(entry.key);
    }
    hits.sort();
    if (hits.isEmpty) return _fallbackVisible(limit);
    return hits.take(limit).toList();
  }

  /// 首帧 / 视口还没挂上时的兜底:从"读到第几段"往后取几段
  List<int> _fallbackVisible(int limit) {
    if (_chunks.isEmpty) return const [];
    final start = _lastChunkIndex.clamp(0, _chunks.length - 1);
    final end = (start + limit).clamp(0, _chunks.length);
    return [for (var i = start; i < end; i++) i];
  }

  GlobalKey _chunkKey(int index) => _chunkKeys.putIfAbsent(
        index,
        () => GlobalKey(debugLabel: 'reader-chunk-$index'),
      );

  /// 这一段还能不能翻:已有译文 / 已排队 / 已失败 / 空段都不重复发请求。
  ///
  /// 失败段必须由用户点「重试」才重翻 —— 否则随读随翻会在同一个坏段上死循环,
  /// 把额度烧光(旧实现就有"越滚越错、一直失败"的观感)。
  bool _canTranslate(int index) {
    if (index < 0 || index >= _chunks.length) return false;
    if (_translations.containsKey(index)) return false;
    if (_pendingChunks.contains(index)) return false;
    if (_chunkErrors.containsKey(index)) return false;
    if (_canceledChunks.contains(index)) return false;
    return '${_chunks[index]['text'] ?? ''}'.trim().isNotEmpty;
  }

  /// 把若干段放进翻译队列。
  ///
  /// 为什么改成**逐段请求**而不是旧实现的一批 3~4 段:
  /// - 旧实现一段失败/截断,整批都标红(用户看到的是"全错了");
  /// - 逐段请求后,每段有自己的成功/失败/取消状态,重试只重试这一条;
  /// - 代价是请求数变多,所以并发 2 路 + 只翻眼前几段,整体等待反而更短。
  void _enqueueTranslation(List<int> indices) {
    if (!_showTranslation || _chunks.isEmpty) return;
    final fresh = <int>[];
    for (final i in indices) {
      if (!_canTranslate(i)) continue;
      _pendingChunks.add(i);
      _queue.add(i);
      _chunkJobEpoch[i] = ++_epochSeq;
      fresh.add(i);
    }
    if (fresh.isEmpty) return;
    if (_runTotal == 0) {
      _runStartedAt = DateTime.now();
      _runDone = 0;
    }
    _runTotal += fresh.length;
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
            _runDone++;
          }
        }
        _pumpTranslationQueue();
      });
    }
    // 本轮真的结束了:把进度状态清干净(而不是留一个 100% 的条骗人)
    if (_activeJobs.isEmpty && _queue.isEmpty && _runTotal > 0) {
      _runTotal = 0;
      _runDone = 0;
      _runStartedAt = null;
    }
    setState(() {});
  }

  /// 翻一段。一个请求只负责一段 —— 失败、取消、重试都只影响这一段。
  ///
  /// [epoch] 是这段的作业代号:用户取消/重翻后,旧请求晚回来的结果会被丢弃,
  /// 不会覆盖新译文(旧实现"取消后仍在翻译、结果又跳出来"的根因之一)。
  Future<void> _translateOne(int index, int epoch) async {
    if (!mounted || !_showTranslation) return;
    if (_chunkJobEpoch[index] != epoch) return;
    final token = CancelToken();
    _chunkTokens[index] = token;
    try {
      final outcome = await DeepseekApiService().translateParagraphsRich(
        ['${_chunks[index]['text'] ?? ''}'],
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
      });
    } on DioException catch (e) {
      // 取消不是"翻译失败":直接丢掉,不弹错误、不标红
      if (CancelToken.isCancel(e) || token.isCancelled) return;
      // 已经被取消/重排了(epoch 不在了)→ 旧请求的错误也不能写回界面
      if (_chunkJobEpoch[index] != epoch) return;
      _markChunkError(index, _humanError(e));
    } catch (e) {
      if (token.isCancelled) return;
      if (_chunkJobEpoch[index] != epoch) return;
      _markChunkError(index, '$e');
    } finally {
      if (identical(_chunkTokens[index], token)) {
        _chunkTokens.remove(index);
      }
    }
  }

  void _markChunkError(int index, String message) {
    if (!mounted) return;
    setState(() {
      _chunkErrors[index] = message;
      _pendingChunks.remove(index);
    });
  }

  String _humanError(Object e) {
    final s = '$e';
    if (s.length > 120) return '${s.substring(0, 120)}…';
    return s;
  }

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
    _runTotal = 0;
    _runDone = 0;
    _runStartedAt = null;
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
    _canceledChunks.add(index);
    if (_queue.remove(index)) {
      _chunkJobEpoch.remove(index);
      _pendingChunks.remove(index);
      _runDone++;
      setState(() {});
      _pumpTranslationQueue();
      return;
    }
    final token = _chunkTokens.remove(index);
    if (token == null) {
      setState(() => _pendingChunks.remove(index));
      return;
    }
    _chunkJobEpoch.remove(index);
    _pendingChunks.remove(index);
    // 立刻把并发槽位还给队列:不必等被 cancel 的请求真的收尾
    _activeJobs.remove(index);
    _runDone++;
    try {
      token.cancel('取消这一段');
    } catch (_) {}
    setState(() {});
    _pumpTranslationQueue();
  }

  /// 本轮进度(只在真的在翻时显示)。
  ///
  /// 分母 = 本轮入队的真实段数;分子 = 已完成(成功/失败/取消都算完成)——
  /// 旧实现分母被人为压成 `min(段数, 60)`,界面上同时出现两套数字
  /// (用户原话"选取的范围也是乱的");现在只有这一套口径。
  Widget? _buildTranslationProgress() {
    if (_runTotal <= 0) return null;
    final done = _runDone.clamp(0, _runTotal);
    final detail = StringBuffer('已翻 ${_translations.length}/${_chunks.length} 段');
    if (_chunkErrors.isNotEmpty) {
      detail.write(' · ${_chunkErrors.length} 段待重试');
    }
    return ProgressStageBar(
      stage: '正在翻译 · 已完成 $done/$_runTotal 段',
      value: done / _runTotal,
      detail: detail.toString(),
      startedAt: _runStartedAt,
      onCancel: _cancelAllTranslation,
    );
  }

  /// 翻译控制条:贴在底部动作栏上方,只在翻译开着时出现。
  ///
  /// 为什么另起一条而不是复用旧动作栏的「换范围」:
  /// - `ReaderActionBar` 在 `lib/widgets/`(本次冻结),只有「换范围」一个入口;
  /// - 重做后要的是**不打断阅读的增量操作**:继续翻后文 / 整章 / 重试失败段,
  ///   而且这些按钮只在翻完后出现,不逼用户先做选择题。
  Widget _buildTranslationTray(ThemeData theme) {
    final cs = theme.colorScheme;
    final busy = _activeJobs.isNotEmpty || _queue.isNotEmpty || _runTotal > 0;
    final failed = _chunkErrors.length;
    final done = _translations.length;
    // 兜底:理论上 busy 就一定有 runTotal;万一状态错位,也显示"正在翻译"
    // 而不是在任务还在跑的时候露出「继续翻后文」让人重复点。
    final progress = busy
        ? (_buildTranslationProgress() ??
            ProgressStageBar(
              stage: '正在翻译…',
              detail: '已翻 $done/${_chunks.length} 段',
              startedAt: _runStartedAt,
              onCancel: _cancelAllTranslation,
            ))
        : null;

    final String status;
    if (failed > 0) {
      status = '已翻 $done/${_chunks.length} 段 · $failed 段没翻出来';
    } else if (!_autoTranslate) {
      status = '已翻 $done/${_chunks.length} 段 · 随读随翻已暂停';
    } else if (done == 0) {
      status = '随读随翻 · 先翻当前屏';
    } else {
      status = '已翻 $done/${_chunks.length} 段 · 点译文可问 AI';
    }

    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xxs, Gap.xs, Gap.xxs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(right: Gap.xs),
              child: progress,
            )
          else
            Row(
              children: [
                Icon(Icons.translate, size: 14, color: cs.primary),
                const SizedBox(width: Gap.xxs),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: AppFont.meta,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (failed > 0)
                  Tooltip(
                    message: '重试 $failed 段没翻出来的段落',
                    child: IconButton(
                      onPressed: _retryFailedChunks,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: Icon(Icons.refresh, size: 17, color: cs.primary),
                    ),
                  ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xxs),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _translateNext,
                  child: const Text(
                    '继续翻后文',
                    style: TextStyle(fontSize: AppFont.tag),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xxs),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _translateChapter,
                  child: const Text(
                    '整章',
                    style: TextStyle(fontSize: AppFont.tag),
                  ),
                ),
              ],
            ),
          if (!busy && failed > 0)
            // 只显示最近一条失败原因(单行、省略):用户至少知道是网络还是额度,
            // 又不至于让 20 条错误铺满屏幕。
            Padding(
              padding: const EdgeInsets.only(left: Gap.lg, bottom: 2),
              child: Text(
                '最近一次:${_humanError(_chunkErrors.values.last)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: AppFont.tag,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 单段重试(失败卡上的「重试」)。只重发这一段,不碰其它段。
  void _retryChunk(int index) {
    if (index < 0 || index >= _chunks.length) return;
    setState(() {
      _chunkErrors.remove(index);
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
    if (_chunks.isEmpty) return;
    if (!DeepseekApiService().isConfigured) {
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
    final visible = _visibleChunkIndices(limit: _visibleBatch);
    final targets = <int>[
      for (final i in visible)
        if (_canTranslate(i)) i,
    ];
    if (targets.isEmpty) {
      // 当前屏都翻好了 → 从当前屏最后一段的下一段往后翻。
      // 不能从"全局最远一段"往后:那样会跳过用户正在读的中间段;
      // 也不能只看紧邻 3 段:中间可能已经翻过,后面还有没翻的。
      var start = visible.isEmpty ? _lastChunkIndex + 1 : visible.last + 1;
      if (start < 0) start = 0;
      for (var i = start;
          i < _chunks.length && targets.length < _translateBatch;
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

  /// 「整章」:从当前读到的位置往后 20 段(没有章节信息时,这是"一章"的近似)。
  ///
  /// 这是用户明确点的批量操作,所以一次性入队;进度条显示真实完成数,
  /// 随时可取消,取消后已翻好的保留。
  void _translateChapter() {
    if (_chunks.isEmpty) return;
    if (!DeepseekApiService().isConfigured) {
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
    final start = _lastChunkIndex.clamp(0, _chunks.length - 1);
    final end = (start + 19).clamp(0, _chunks.length - 1);
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
    if (!DeepseekApiService().isConfigured) return;
    _visibleTimer?.cancel();
    _visibleTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || !_showTranslation || !_autoTranslate) return;
      _enqueueVisible(limit: _visibleBatch);
    });
  }

  void _enqueueVisible({required int limit}) {
    final targets = <int>[
      for (final i in _visibleChunkIndices(limit: limit))
        if (_canTranslate(i)) i,
    ];
    if (targets.isEmpty) return;
    _enqueueTranslation(targets);
  }

  /// 点译文 → 就这一段追问(带原段 + 页面上的译文 + 相邻两段)。
  ///
  /// 复用页面已有的 `FollowUpController`:把 [_followUpChunk] 钉在这一段,
  /// `_buildFollowUpContext` 就会只喂这一段的上下文;问完再点底部「追问」
  /// 会自动清掉这个钉选,回到整篇范围。
  void _askAboutChunk(int index) {
    if (index < 0 || index >= _chunks.length) return;
    setState(() => _followUpChunk = index);
    showFollowUpDrawer(
      context: context,
      controller: _followUp,
      title: '追问这一段',
      prefillQuestion: _followUpQuestionFor(index),
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
  Future<void> _showReaderSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final muted = theme.colorScheme.onSurfaceVariant;
          void apply(double scale, double height) {
            setSheet(() {});
            setState(() {
              _fontScale = scale;
              _lineHeight = height;
            });
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Gap.md, 0, Gap.md, Gap.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('阅读设置',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: Gap.md),
                  Text('字号', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  const SizedBox(height: Gap.xs),
                  Wrap(
                    spacing: Gap.xs,
                    children: [
                      for (final s in ReaderSettings.fontScales)
                        ChoiceChip(
                          label: Text(ReaderSettings.scaleLabel(s)),
                          selected: _fontScale == s,
                          onSelected: (_) {
                            ReaderSettings.setFontScale(s);
                            apply(s, _lineHeight);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  Text('行距', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  const SizedBox(height: Gap.xs),
                  Wrap(
                    spacing: Gap.xs,
                    children: [
                      for (var i = 0; i < ReaderSettings.lineHeights.length; i++)
                        ChoiceChip(
                          label: Text(ReaderSettings.lineHeightLabels[i]),
                          selected: _lineHeight == ReaderSettings.lineHeights[i],
                          onSelected: (_) {
                            final h = ReaderSettings.lineHeights[i];
                            ReaderSettings.setLineHeight(h);
                            apply(_fontScale, h);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  // 预览:调完立刻能看到正文长什么样(不然要退出去才知道)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(Gap.sm),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: Radii.controlRadius,
                    ),
                    child: Text(
                      'The quick brown fox jumps over the lazy dog. '
                      '阅读的样子大致就是这样。',
                      style: TextStyle(
                        fontSize: ReaderSettings.baseFontSize * _fontScale,
                        height: _lineHeight,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
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
    // 退出即落盘:用户不需要记着"点保存",进度丢失是最劝退的体验之一
    // (force: 退出这一次不管节流窗口,该存就存)
    _persist(finished: _finished, force: true);
    super.dispose();
  }

  void _onScroll() {
    // 用滚动位置粗估"读到第几块"(每块高度不一,按比例足够用)
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0 || _chunks.isEmpty) return;
    final ratio = (_scrollCtrl.offset / max).clamp(0, 1);
    final idx = (ratio * (_chunks.length - 1)).round();
    _lastChunkIndex = idx;
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
        : ((_lastChunkIndex + 1) / _chunks.length * 100).clamp(0, 100).toDouble();
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

  /// 接着上次读:滚到上次的段(不静默跳转 —— 用户点了「继续」才跳)
  void _scrollToChunk(int index) {
    if (_chunks.length <= 1) return;
    final idx = index.clamp(0, _chunks.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastChunkIndex = idx;
      _lastPersistIndex = idx;
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      if (max <= 0) return;
      _scrollCtrl.jumpTo(max * (idx / (_chunks.length - 1)).clamp(0.0, 1.0));
    });
  }

  /// 有历史进度时的询问(用户第 4 条):「继续 / 从头开始」,不静默跳转
  Future<void> _askResume({
    required Map<String, Object?> progress,
    required int position,
    required int percent,
    required int minutes,
  }) async {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final finished = progress['finished_at'] != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: Gap.xs),
                  Text(
                    finished ? '这篇你读完了' : '上次读到 $percent%(第 ${position + 1} 段)',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xxs),
              Text(
                finished
                    ? '已经标记读完,已读 $minutes 分钟。要从上次的位置再看一遍吗?'
                    : '已读 $minutes 分钟。继续,还是从头开始?',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: muted, height: 1.5),
              ),
              const SizedBox(height: Gap.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'resume'),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(finished
                      ? '回到第 ${position + 1} 段'
                      : '继续(第 ${position + 1} 段)'),
                ),
              ),
              const SizedBox(height: Gap.xs),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'restart'),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('从头开始'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'resume') {
      _scrollToChunk(position);
    } else if (_scrollCtrl.hasClients) {
      // 从头开始:回顶部(控制器还没挂上时什么都不做,别在这里抛)
      _scrollCtrl.jumpTo(0);
    }
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
      setState(() {
        _material = material;
        _chunks = chunks;
        _analysis = analysis;
        _blockList = savedBlocks;
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

  void _openRichForms() {
    if (_chunks.isEmpty) return;
    showModalBottomSheet<void>(
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

  /// 「保存」= 把本次收的词再确认一遍(给用户一个明确的收口)
  void _showPickedSummary() {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
          child: _pickedWords.isEmpty
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('还没有收词',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: Gap.xs),
                    Text(
                      '点正文里的任意英文单词(或长按选中一段),底部会弹出'
                      '「询问 AI / 收藏进单词本」。收藏时按下方显示的保存位置入库,'
                      '并立刻进入复习队列。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('本次收了 ${_pickedWords.length} 个词',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: Gap.xxs),
                    Text(
                      '存到:${_saveTarget.label}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final w in _pickedWords)
                          Chip(
                            label: Text(w),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _changeSaveTarget();
                        },
                        icon: const Icon(Icons.drive_file_move_outline, size: 16),
                        label: const Text('改保存位置'),
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(
                      '注:收词时已即时入库,这里只是让你确认收到了哪些、存到哪儿。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
        ),
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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final title = '${_material?['title'] ?? '阅读'}';
    final url = '${_material?['url'] ?? ''}'.trim();
    final a = _analysis;

    // v2.10(用户 10/4 第 4 条):退出这篇材料时问一句
    // "放进书架? / 放进收藏夹 / 不了,就看看" —— 用 PopScope 拦住返回,
    // 问完再真的退出(已经在架上或没读过就不问)
    return PopScope(
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
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          // v2.10(用户 10/4 第 4 条):**加入书架** —— 明明白白一个按钮,
          // 不用翻"更多"菜单(用户说的是"在文章内部增加一个 ui 即加入书架")
          IconButton(
            tooltip: _onShelf ? '已在书架上(点一下移出)' : '加入书架',
            onPressed: _toggleShelf,
            icon: Icon(
              _onShelf ? Icons.collections_bookmark : Icons.collections_bookmark_outlined,
            ),
          ),
          // v2.7(第 3 条):原来这里是 5 个图标挤在一起 —— 现在只留「更多」,
          // 其余(翻译 / 模型 / 保存 / 追问)按用户要求挪到界面下方的动作栏
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: _onMoreAction,
            itemBuilder: (_) => [
              if (url.isNotEmpty)
                const PopupMenuItem(
                  value: 'link',
                  height: 38,
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new, size: 17),
                      SizedBox(width: Gap.xs),
                      Text('原文链接', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'settings',
                height: 38,
                child: Row(
                  children: [
                    Icon(Icons.format_size, size: 17),
                    SizedBox(width: Gap.xs),
                    Text('阅读设置(字号 / 行距)', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'dictation',
                height: 38,
                child: Row(
                  children: [
                    Icon(Icons.headphones_outlined, size: 17),
                    SizedBox(width: Gap.xs),
                    Text('听写练习', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                height: 38,
                child: Row(
                  children: [
                    Icon(Icons.download_outlined, size: 17),
                    SizedBox(width: Gap.xs),
                    Text('导出这篇(Markdown)', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              if (!_finished)
                const PopupMenuItem(
                  value: 'finish',
                  height: 38,
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, size: 17),
                      SizedBox(width: Gap.xs),
                      Text('读完了', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      // 阅读器里**不留转圈**(用户要求等待态换成更可感的形式):
      // 打开材料用骨架屏 —— 它先摆出"正文将要占的位置",读起来比转圈快
      body: _loading
          ? ListView(
              padding: Insets.page,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_outlined,
                        size: 15, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: Gap.xs),
                    Text(
                      '正在打开材料…',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                const SkeletonLines(lines: 6, seed: 0),
                const SizedBox(height: Gap.lg),
                const SkeletonLines(lines: 4, withTitle: false, seed: 1),
              ],
            )
          : _error != null
              ? Padding(
                  padding: Insets.page,
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
                )
              : Column(
                  children: [
                    // 听力材料(播客/TED)在顶部给播放条:边听边看稿
                    if (AudioService.looksPlayable(_material?['audio_url'] as String?))
                      AudioPlayerBar(
                        url: '${_material!['audio_url']}',
                        title: '${_material!['title'] ?? ''}',
                      ),
                    if (a != null)
                      Container(
                        width: double.infinity,
                        color: theme.colorScheme.surfaceContainerHighest,
                        padding: const EdgeInsets.symmetric(
                            horizontal: Gap.md, vertical: Gap.xs),
                        child: Text(
                          '${a.wordCount} 词 · 约 ${a.estMinutes} 分钟 · ${a.cefr} · '
                          '覆盖率 ${(a.knownTokenRatio * 100).toStringAsFixed(1)}% · ${a.hint}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        // v2.12.2:用列表视口的真实矩形判断"哪几段可见"
                        // (设备/字号/行距不同,按滚动比例猜会把范围翻错)
                        key: _listKey,
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(
                            Gap.md, Gap.sm, Gap.md, 80),
                        itemCount: _chunks.length,
                        itemBuilder: (_, index) => _buildChunk(theme, index),
                      ),
                    ),
                    // ── 翻译控制条(v2.12.2 重做)──
                    // 只放增量动作(继续翻后文 / 整章 / 重试失败段)与真实进度;
                    // 打开翻译不再先弹范围选择。
                    if (_showTranslation) _buildTranslationTray(theme),
                    // ── 底部动作栏(v2.7,用户第 3 条):模型 / 翻译 / 保存 / 追问,
                    //    位置与拍照识图页下方的动作栏一致 ──
                    ReaderActionBar(
                      translating: _showTranslation,
                      onToggleTranslation: _toggleTranslation,
                      pickedCount: _pickedWords.length,
                      onSave: _showPickedSummary,
                      onFollowUp: _openFollowUp,
                      saveTargetLabel: _saveTarget.label,
                      onChangeTarget: _changeSaveTarget,
                      onModelChanged: () {
                        if (mounted) setState(() {});
                      },
                      // v2.9(第 3(5) 条):丰富形式的入口
                      onRichForms: _openRichForms,
                      // 翻译状态/进度全部移到上面的控制条:
                      // 动作栏只保留开关,避免两套文案/两条进度条互相打架。
                      moreActions: [
                        ReaderMoreAction(
                          id: 'rich',
                          label: '丰富形式(表格 / 导图 …)',
                          icon: Icons.auto_awesome_outlined,
                          onSelected: _openRichForms,
                        ),
                        if (url.isNotEmpty)
                          ReaderMoreAction(
                            id: 'link',
                            label: '原文链接',
                            icon: Icons.open_in_new,
                            onSelected: () => _openSourceLink(url),
                          ),
                        ReaderMoreAction(
                          id: 'settings',
                          label: '阅读设置(字号 / 行距)',
                          icon: Icons.format_size,
                          onSelected: _showReaderSettings,
                        ),
                        ReaderMoreAction(
                          id: 'dictation',
                          label: '听写练习',
                          icon: Icons.headphones_outlined,
                          onSelected: () => _onMoreAction('dictation'),
                        ),
                        ReaderMoreAction(
                          id: 'export',
                          label: '导出这篇(Markdown)',
                          icon: Icons.download_outlined,
                          onSelected: () => _onMoreAction('export'),
                        ),
                        if (!_finished)
                          ReaderMoreAction(
                            id: 'finish',
                            label: '读完了',
                            icon: Icons.check_circle_outline,
                            onSelected: _finishReading,
                          ),
                      ],
                    ),
                  ],
                ),
      floatingActionButton: _loading || _chunks.isEmpty
          ? null
          : FloatingActionButton.small(
              tooltip: '回到顶部',
              onPressed: () => _scrollCtrl.animateTo(
                0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
              ),
              child: const Icon(Icons.arrow_upward),
            ),
      ),
    );
  }

  /// 就地译文区:紧贴原段下方,左侧主题色细线 + 比正文小一号 + 次要文字色。
  ///
  /// 三件事**不做**,否则阅读会被打断:
  /// - 不加整块底色(会和正文抢注意力,深色下还会变成一块亮色);
  /// - 不把"重翻"做成大按钮(只有失败时才出现一行可点的「重试」);
  /// - 不弹任何浮层(译文就在原位置出现/消失,不推走上面的正文)。
  ///
  /// 点译文本身 = 追问这一段(带原文 + 译文上下文);右侧「…」里是
  /// 追问 / 重翻这段 —— 重翻只重发这一段,不影响其它段。
  Widget _buildTranslationArea(ThemeData theme, int index) {
    final cs = theme.colorScheme;
    final translation = _translations[index];
    final error = _chunkErrors[index];
    final pending = _pendingChunks.contains(index);

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: Gap.xs),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 14,
              color: AppTheme.warningColor(context),
            ),
            const SizedBox(width: Gap.xxs),
            Expanded(
              child: Tooltip(
                message: error,
                child: Text(
                  '这段没翻出来',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: AppFont.meta,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                minimumSize: const Size(0, 26),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _retryChunk(index),
              child: const Text(
                '重试',
                style: TextStyle(fontSize: AppFont.tag),
              ),
            ),
          ],
        ),
      );
    }

    if (_canceledChunks.contains(index)) {
      return Padding(
        padding: const EdgeInsets.only(top: Gap.xs),
        child: Row(
          children: [
            Icon(Icons.translate, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: Gap.xxs),
            Expanded(
              child: Text(
                '这段的翻译已取消',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: AppFont.meta,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                minimumSize: const Size(0, 26),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _retryChunk(index),
              child: const Text(
                '重试',
                style: TextStyle(fontSize: AppFont.tag),
              ),
            ),
          ],
        ),
      );
    }

    if (pending && translation == null) {
      return Padding(
        padding: const EdgeInsets.only(top: Gap.xs),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: cs.outlineVariant, width: 2),
            ),
          ),
          padding: const EdgeInsets.only(left: Gap.sm, top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 骨架屏占住"译文将要出现的位置":用户先看到形状,不是转圈
              SkeletonLines(
                lines: 2,
                withTitle: false,
                lineHeight: 10,
                seed: index,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _cancelChunkTranslation(index),
                  child: const Text(
                    '取消这段',
                    style: TextStyle(fontSize: AppFont.tag),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (translation == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: cs.primary, width: 2.5),
          ),
        ),
        padding: const EdgeInsets.only(left: Gap.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Tooltip(
                message: '点译文可追问 AI;右侧「…」可重翻这一段',
                child: InkWell(
                  borderRadius: Radii.controlRadius,
                  onTap: () => _askAboutChunk(index),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: 1,
                      bottom: 2,
                      right: Gap.xxs,
                    ),
                    child: Text(
                      translation,
                      style: TextStyle(
                        fontSize:
                            ReaderSettings.baseFontSize * _fontScale * 0.86,
                        height: _lineHeight * 0.95,
                        color: cs.onSurfaceVariant,
                      ),
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
              icon: Icon(
                Icons.more_horiz,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              onSelected: (v) {
                if (v == 'ask') {
                  _askAboutChunk(index);
                } else if (v == 'retry') {
                  _retranslateChunk(index);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'ask',
                  height: 38,
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 16),
                      SizedBox(width: Gap.xs),
                      Text('追问这段', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'retry',
                  height: 38,
                  child: Row(
                    children: [
                      Icon(Icons.refresh, size: 16),
                      SizedBox(width: Gap.xs),
                      Text('重翻这段', style: TextStyle(fontSize: 13)),
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

  Widget _buildChunk(ThemeData theme, int index) {
    final row = _chunks[index];
    final chunkTitle = row['title'];
    final text = '${row['text'] ?? ''}';
    // 正文样式由**阅读设置**决定(字号乘数 × 基准号 + 行距档位),
    // 系统无障碍字号仍由 MediaQuery 叠加,不在这里覆盖
    final bodyStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: ReaderSettings.baseFontSize * _fontScale,
      height: _lineHeight,
    );
    // v2.9(第 3(5) 条):这一段挂着的 AI 内容块(表格/导图/时间线/要点/自测)
    final chunkBlocks = [
      for (final b in _blockList)
        if (b.chunkIndex == index) b,
    ];
    // 正在生成的那一个(只在本段头部显示一次等待时间线,不重复)
    final waitingKey = _blockWaiting;
    final waitingHere = waitingKey != null &&
        waitingKey.startsWith('$index:') &&
        chunkBlocks.every((b) => _blockKey(index, b.kind) != waitingKey);
    final waitingKind = waitingHere
        ? blocks.MaterialBlockKind.byId(waitingKey.split(':').last)
        : null;
    return Padding(
      // 每个段落挂一个稳定 key:滚动停下的"可见段"判断要拿它的 RenderBox
      key: _chunkKey(index),
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chunkTitle is String && chunkTitle.trim().isNotEmpty) ...[
            Text(chunkTitle.trim(),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: Gap.sm),
          ],
          TappablePassage(
            text: text,
            onWordTap: _onWordTap,
            onSelectionAction: _onSelectionAction,
            style: bodyStyle,
          ),
          // 逐段译文(v2.12.2 重做):紧贴原段下方,不挪版面、不弹浮层。
          // 成功 / 失败 / 在途三种状态各占一个很轻的槽位,详见 _buildTranslationArea。
          if (_showTranslation) _buildTranslationArea(theme, index),
          // ── AI 内容块(第 3(5) 条):插在本段之后,与正文用留白 + 卡片分开 ──
          if (waitingHere && waitingKind != null) ...[
            const SizedBox(height: Gap.sm),
            MaterialBlockWaiting(kind: waitingKind),
          ],
          for (final b in chunkBlocks) ...[
            const SizedBox(height: Gap.xxs),
            if (_blockErrors[_blockKey(index, b.kind)] != null)
              MaterialBlockErrorCard(
                message: _blockErrors[_blockKey(index, b.kind)]!,
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
