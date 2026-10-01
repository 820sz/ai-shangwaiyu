import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/vocabulary.dart';
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

  /// 逐段翻译(v2.6 用户第 8(4) 条;v2.8 改为**按需**:滚到哪翻到哪)
  bool _showTranslation = false;

  /// 正在翻(底部动作栏显示进度)
  bool _translateRunning = false;
  String? _translateError;

  /// 翻不出来 / 段数对不上的段(可就地重试)
  final Set<int> _chunkErrors = {};

  /// 块索引 → 中文译文(与 _chunks 一一对应)
  final Map<int, String> _translations = {};

  // ── v2.9(用户第 3(2) 条):翻译进度条 + 自选范围 ──
  /// 本次要翻的段(升序),空 = 没有正在进行的批量任务
  List<int> _translateTargets = const [];

  /// 本次允许翻的段区间(算进度用;「整篇」时就是全文)
  int _rangeStart = 0;
  int _rangeEnd = 0;

  /// 已处理完的段数(含失败段 —— 失败也是"处理过了",进度不能卡住)
  int _translateDone = 0;

  /// 开始时间(进度条显示"已用 12 秒")
  DateTime? _translateStartedAt;

  /// 用户点了取消(已翻好的保留)
  bool _translateCanceled = false;

  /// 上次选的范围(默认"当前段前后各 3 段" —— 打开翻译时最常用的一档)
  blocks.TranslateScope _scope = blocks.TranslateScope.around;

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

  /// 追问时的材料上下文:标题 + 难度 + 正文节选(太长会挤爆提示词)
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
  /// 历史:旧实现打开时按每批 8 段把**整篇**翻完才显示(一本书 200+ 块 =
  /// 几十次请求,用户看到的就是永远在转圈);v2.8 改成"滚到哪翻到哪"。
  ///
  /// **v2.9(用户第 3(2) 条)**:用户原话"翻译功能进度缓慢,需要增加翻译的
  /// 进度条…以及让用户自选翻译范围"。所以现在:
  /// 1. 打开翻译先弹**范围选择**(当前段 / 前后各 3 段 / 当前章 / 整篇),
  ///    每档都写清"共 N 段、约 X 分钟",用户自己决定翻多少;
  /// 2. 开翻后底部动作栏出现 **ProgressStageBar**:真实进度 =
  ///    已完成段数 / 本次要翻的段数,带「取消」(取消后已翻好的保留);
  /// 3. 关掉再打开 = 沿用上次范围继续翻没翻过的段。
  Future<void> _toggleTranslation() async {
    if (_showTranslation) {
      setState(() {
        _showTranslation = false;
        // 关掉翻译 = 停止后台翻(已翻好的保留,再打开继续)
        _translateCanceled = true;
      });
      return;
    }
    setState(() {
      _showTranslation = true;
      _translateError = null;
    });
    if (_chunks.isEmpty) return;
    final api = DeepseekApiService();
    if (!api.isConfigured) {
      setState(() => _translateError = '还没有配置 API Key —— 到「我的 → API 设置」填一个就能翻译');
      return;
    }
    // 关掉再打开:继承上次范围,但这次要点一次范围确认(用户能改)
    await _pickTranslateScope();
  }

  /// 范围选择弹层(用户第 3(2) 条"让用户自选翻译范围")
  Future<void> _pickTranslateScope() async {
    if (_chunks.isEmpty) return;
    final picked = await showModalBottomSheet<blocks.TranslateScope>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final muted = theme.colorScheme.onSurfaceVariant;
        // 各档的实时提示:还剩几段、约多久 —— 用户选之前就知道要花多少时间
        String hintFor(blocks.TranslateScope s) {
          final plan = blocks.planTranslation(
            scope: s,
            current: _lastChunkIndex,
            chunkCount: _chunks.length,
            alreadyDone: _doneIndices(),
            failed: _chunkErrors,
          );
          return blocks.translatePlanHint(
            s,
            chunkCount: _chunks.length,
            pending: plan.total,
            translated: _translations.length,
          );
        }

        final planAll = blocks.planTranslation(
          scope: blocks.TranslateScope.all,
          current: _lastChunkIndex,
          chunkCount: _chunks.length,
          alreadyDone: _doneIndices(),
          failed: _chunkErrors,
        );
        final warning = blocks.bulkTranslateWarning(planAll.total);
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
                      Icon(Icons.translate, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: Gap.xs),
                      Text(
                        '翻译范围',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.xxs),
                  Text(
                    '现在读到第 ${_lastChunkIndex + 1}/${_chunks.length} 段。'
                    '翻好的段落会留在原位,下次打开不用重翻。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: muted, height: 1.5),
                  ),
                  const SizedBox(height: Gap.sm),
                  for (final s in blocks.TranslateScope.values) ...[
                    _scopeTile(theme, s, hintFor(s), picked: s == _scope),
                    const SizedBox(height: Gap.xs),
                  ],
                  if (warning.isNotEmpty) ...[
                    const SizedBox(height: Gap.xxs),
                    Container(
                      padding: const EdgeInsets.all(Gap.sm),
                      decoration: BoxDecoration(
                        color: AppTheme.warningColor(ctx).withAlpha(18),
                        borderRadius: Radii.controlRadius,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: AppTheme.warningColor(ctx)),
                          const SizedBox(width: Gap.xs),
                          Expanded(
                            child: Text(
                              warning,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() => _scope = picked);
    await _startTranslation(picked);
  }

  /// 范围选择里的一行(图标 + 名称 + 段数/耗时 + 选中态)
  Widget _scopeTile(
    ThemeData theme,
    blocks.TranslateScope s,
    String hint, {
    required bool picked,
  }) {
    final cs = theme.colorScheme;
    return Material(
      color: picked ? cs.primary.withAlpha(16) : cs.surfaceContainerHighest.withAlpha(110),
      borderRadius: Radii.controlRadius,
      child: InkWell(
        borderRadius: Radii.controlRadius,
        onTap: () => Navigator.pop(context, s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 10),
          child: Row(
            children: [
              Icon(s.icon, size: 18, color: picked ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: picked ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    Text(
                      hint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (picked)
                Icon(Icons.check_circle, size: 17, color: cs.primary)
              else
                Icon(Icons.chevron_right, size: 18, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }

  /// 已有译文的段集合(传给 planTranslation,避免重复翻)
  Set<int> _doneIndices() => _translations.keys.toSet();

  /// 开始翻译当前范围(第 3(2) 条的核心)
  Future<void> _startTranslation(blocks.TranslateScope scope) async {
    if (!_showTranslation || _chunks.isEmpty) return;
    if (_translateRunning) {
      setState(() => _translateError = '正在翻译,先点「取消」再换范围');
      return;
    }
    final api = DeepseekApiService();
    if (!api.isConfigured) {
      setState(() => _translateError = '还没有配置 API Key —— 到「我的 → API 设置」填一个就能翻译');
      return;
    }
    final plan = blocks.planTranslation(
      scope: scope,
      current: _lastChunkIndex,
      chunkCount: _chunks.length,
      alreadyDone: _doneIndices(),
      failed: _chunkErrors,
    );
    setState(() {
      _translateError = null;
      _translateCanceled = false;
      _scope = scope;
      _rangeStart = plan.rangeStart;
      _rangeEnd = plan.rangeEnd;
      _translateTargets = plan.indices;
      _translateDone = 0;
      _translateRunning = true;
      _translateStartedAt = DateTime.now();
    });
    if (plan.isEmpty) {
      setState(() {
        _translateRunning = false;
        _translateError = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${scope.label}」里的段落都已经翻好了')),
        );
      }
      return;
    }
    try {
      await _translateBatches(plan.indices);
    } finally {
      if (mounted) {
        setState(() {
          _translateRunning = false;
          _translateTargets = const [];
        });
      } else {
        _translateRunning = false;
      }
    }
  }

  /// 分批翻译(每批最多 3 段合一次请求)并**实时更新进度**。
  ///
  /// 进度口径(硬规则:只显示真实进度):
  /// - 分子 [_translateDone] = 已处理完的段(失败也算处理过,否则进度会停在
  ///   原地让人以为卡死);
  /// - 分母在"本次要翻的段数"与 60 之间取小 —— 一次翻 200 段时按 200 算
  ///   进度条几乎不动,同样会让人以为卡死;真正的段数写在 detail 里。
  Future<void> _translateBatches(List<int> indices) async {
    final api = DeepseekApiService();
    const batch = 3;
    for (var s = 0; s < indices.length; s += batch) {
      if (!mounted || !_showTranslation || _translateCanceled) return;
      final slice = indices.sublist(s, (s + batch).clamp(0, indices.length));
      final texts = [for (final i in slice) '${_chunks[i]['text'] ?? ''}'];
      try {
        final translated = await api.translateParagraphs(texts);
        if (!mounted) return;
        setState(() {
          if (translated.length == slice.length) {
            for (var k = 0; k < slice.length; k++) {
              _translations[slice[k]] = translated[k];
              _chunkErrors.remove(slice[k]);
            }
          } else {
            // 段数对不上:整批丢弃并标记,让用户点单段重试(错误可见 > 静默错位)
            _chunkErrors.addAll(slice);
            _translateError = '译文段数与原文对不上,已丢弃这一批(可点该段的「重试」)';
          }
          _translateDone += slice.length;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _chunkErrors.addAll(slice);
          _translateError = '翻译失败:$e';
          _translateDone += slice.length;
        });
      }
    }
  }

  /// 取消本次批量翻译(已翻好的保留)
  void _cancelTranslation() {
    setState(() => _translateCanceled = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已取消 —— 翻好的 ${_translations.length} 段都保留着'),
        ),
      );
    }
  }

  /// 进度条(v2.9):真实进度;不在翻译时返回 null(不显示假进度条)
  ProgressStageBar? _buildTranslateProgress() {
    if (!_translateRunning) return null;
    final targetCount = _translateTargets.length;
    if (targetCount <= 0) return null;
    // 分母:本次段数与 60 取小(见 _translateBatches 的注释)
    final denom = targetCount <= 60 ? targetCount : 60;
    final value = (_translateDone / denom).clamp(0.0, 1.0);
    final processedUpto = _rangeStart + _translateDone;
    final detail = StringBuffer(
      '已完成 $_translateDone/$targetCount 段 · 读到第 '
      '${processedUpto.clamp(1, _chunks.length)} 段',
    );
    // 剩余估算:样本不足(<2 段)不给 —— 宁可不说,也不给一个乱跳的数字
    final started = _translateStartedAt;
    if (started != null && _translateDone >= 2) {
      final secs = DateTime.now().difference(started).inSeconds;
      final per = secs / _translateDone;
      final left = (targetCount - _translateDone) * per;
      if (left >= 20) {
        detail.write(' · 约剩 ${blocks.formatEstimate(left.round())}');
      }
    }
    return ProgressStageBar(
      stage: '正在翻译第 ${processedUpto.clamp(1, _chunks.length)}/${_chunks.length} 段',
      value: value,
      detail: detail.toString(),
      startedAt: started,
      onCancel: _cancelTranslation,
    );
  }

  /// 单段重试(点该段上的「重试」)。已翻好的段不重复翻,进度照常更新。
  Future<void> _retryChunk(int index) async {
    setState(() {
      _chunkErrors.remove(index);
      _translateError = null;
      _showTranslation = true;
    });
    if (_translateRunning) return;
    setState(() {
      _translateCanceled = false;
      _rangeStart = index;
      _rangeEnd = index;
      _translateTargets = [index];
      _translateDone = 0;
      _translateRunning = true;
      _translateStartedAt = DateTime.now();
    });
    try {
      await _translateBatches([index]);
    } finally {
      if (mounted) {
        setState(() {
          _translateRunning = false;
          _translateTargets = const [];
        });
      } else {
        _translateRunning = false;
      }
    }
  }

  /// 滚动到哪、就顺手把附近还没翻的段翻掉(v2.9:交给**用户选的范围**决定)
  void _maybeAutoTranslate(int index) {
    if (!_showTranslation || _translateRunning || _translateCanceled) return;
    if (!DeepseekApiService().isConfigured) return;
    final plan = blocks.planTranslation(
      scope: _scope,
      current: index,
      chunkCount: _chunks.length,
      alreadyDone: _doneIndices(),
      failed: _chunkErrors,
    );
    if (plan.isEmpty) return;
    // 不在滚动回调里直接 await:交给下一帧,避免滚动期间做 IO 与 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showTranslation && !_translateRunning) {
        _startTranslation(_scope);
      }
    });
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
    final moved = idx != _lastChunkIndex;
    _lastChunkIndex = idx;
    // v2.9(第 4 条):滚动即自动留存进度(节流在 _persist 里)
    _persist(finished: _finished);
    // v2.9(第 3(2) 条):开了翻译就按**用户选的范围**补翻当前位置附近的段
    if (moved) _maybeAutoTranslate(idx);
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

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
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
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(
                            Gap.md, Gap.sm, Gap.md, 80),
                        itemCount: _chunks.length,
                        itemBuilder: (_, index) => _buildChunk(theme, index),
                      ),
                    ),
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
                      // v2.9(第 3(2) 条):翻译进度条(真实进度 + 取消)
                      translationProgress: _buildTranslateProgress(),
                      onRetranslate:
                          _showTranslation && !_translateRunning
                              ? _pickTranslateScope
                              : null,
                      // v2.8:翻译状态摊在动作栏上 —— 用户要知道"翻到哪了"
                      translationNote: !_showTranslation
                          ? ''
                          : (_translateRunning
                              ? '翻译中 ${_translations.length}/${_chunks.length}'
                              : (_translateError != null
                                  ? '翻译出错,往下滚或点该段重试'
                                  : '已翻 ${_translations.length}/${_chunks.length}'
                                      ' · 可换范围继续翻')),
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
    final muted = theme.colorScheme.onSurfaceVariant;
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
          // 逐段译文(v2.6;v2.9 带范围选择与进度):紧跟在本段英文下面,浅色区分 + 稍小字号
          if (_showTranslation) ...[
            const SizedBox(height: Gap.xs),
            if (_chunkErrors.contains(index))
              AppErrorCard(
                message: '这一段的翻译没成功'
                    '${_translateError == null ? '' : ':$_translateError'}',
                onRetry: () => _retryChunk(index),
                retryLabel: '重试这一段',
              )
            else if (!_translations.containsKey(index))
              // 还在等着翻的段:用骨架屏占住"译文将要出现的位置"——
              // 只有真的在翻、且这一段在本次范围内才显示(不骗人)
              if (_translateRunning &&
                  index >= _rangeStart &&
                  index <= _rangeEnd)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.xxs),
                  child: SkeletonLines(
                    lines: 2,
                    withTitle: false,
                    lineHeight: 10,
                    seed: index,
                  ),
                )
              else
                Row(
                  children: [
                    Icon(Icons.translate, size: 13, color: muted),
                    const SizedBox(width: Gap.xxs),
                    Expanded(
                      child: Text(
                        _translateCanceled
                            ? '这段还没翻(点「换范围」继续)'
                            : '这段还没翻(点下方「翻译」选范围)',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted, fontSize: 11.5),
                      ),
                    ),
                  ],
                )
            else ...[
              // 英中对照:译文用小一号字 + 左侧主题色竖线,一眼分得清原文与译文
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xs),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(150),
                  borderRadius: Radii.controlRadius,
                  border: Border(
                    left: BorderSide(color: theme.colorScheme.primary, width: 3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: Gap.xs),
                      child: Icon(Icons.translate,
                          size: 13, color: theme.colorScheme.primary),
                    ),
                    Expanded(
                      child: Text(
                        _translations[index]!,
                        style: TextStyle(
                          fontSize:
                              ReaderSettings.baseFontSize * _fontScale * 0.86,
                          height: _lineHeight * 0.95,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.xxs),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                    minimumSize: const Size(0, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _translateRunning ? null : () => _retryChunk(index),
                  icon: const Icon(Icons.refresh, size: 13),
                  label: const Text('重翻这段', style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ],
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
