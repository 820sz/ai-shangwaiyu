import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../models/vocabulary.dart';
import '../../providers/vocab_provider.dart';
import '../../services/audio_service.dart';
import '../../services/backup_service.dart';
import '../../services/database.dart';
import '../../services/deepseek_api.dart';
import '../../services/external_link.dart';
import '../../services/material_library.dart';
import '../../services/reader_settings.dart';
import '../../services/reading_quiz.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/audio_player_bar.dart';
import '../../widgets/reader_action_bar.dart';
import '../../widgets/reader_text.dart';
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

  /// 逐段翻译(v2.6,用户第 8(4) 条):"侧边栏提供翻译,点击后按段逐段翻译,
  /// 按每段英文 + 中文的方式呈现材料"。
  bool _showTranslation = false;
  bool _translating = false;
  String? _translateError;

  /// 块索引 → 中文译文(与 _chunks 一一对应)
  final Map<int, String> _translations = {};

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

  /// 开/关逐段翻译。首次打开时按批调用文本 API(每批 8 段),
  /// 段落数对不上就整批丢弃并说明原因 —— 绝不把译文错位到别的段落上。
  Future<void> _toggleTranslation() async {
    if (_showTranslation) {
      setState(() => _showTranslation = false);
      return;
    }
    setState(() {
      _showTranslation = true;
      _translateError = null;
    });
    if (_translations.isNotEmpty || _chunks.isEmpty) return;

    setState(() => _translating = true);
    try {
      final api = DeepseekApiService();
      if (!api.isConfigured) {
        throw Exception('还没有配置 API Key —— 到「我的 → API 设置」填一个就能翻译');
      }
      const batchSize = 8;
      for (var start = 0; start < _chunks.length; start += batchSize) {
        final end = (start + batchSize).clamp(0, _chunks.length);
        final slice = <String>[
          for (var i = start; i < end; i++) '${_chunks[i]['text'] ?? ''}',
        ];
        final translated = await api.translateParagraphs(slice);
        if (!mounted) return;
        setState(() {
          for (var i = 0; i < translated.length; i++) {
            _translations[start + i] = translated[i];
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _translateError = '$e');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
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
    _persist(finished: _finished);
    super.dispose();
  }

  void _onScroll() {
    // 用滚动位置粗估"读到第几块"(每块高度不一,按比例足够用)
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0 || _chunks.isEmpty) return;
    final ratio = (_scrollCtrl.offset / max).clamp(0, 1);
    _lastChunkIndex = (ratio * (_chunks.length - 1)).round();
  }

  Future<void> _load() async {
    try {
      final material = await DatabaseService.getMaterialById(widget.materialId);
      final chunks = await DatabaseService.getMaterialChunks(widget.materialId);
      final progress =
          await DatabaseService.getMaterialProgress(widget.materialId);
      if (!mounted) return;
      MaterialAnalysis? analysis;
      final raw = material?['difficulty'];
      if (raw is Map) {
        analysis = MaterialAnalysis.fromJson(Map<String, Object?>.from(raw));
      }
      setState(() {
        _material = material;
        _chunks = chunks;
        _analysis = analysis;
        _lookups = _intOf(progress?['lookups']);
        _picked = _intOf(progress?['picked_words']);
        _lastChunkIndex = _intOf(progress?['position']);
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

  Future<void> _persist({required bool finished}) async {
    if (_chunks.isEmpty) return;
    final percent = finished
        ? 100.0
        : ((_lastChunkIndex + 1) / _chunks.length * 100).clamp(0, 100).toDouble();
    try {
      await DatabaseService.upsertMaterialProgress(
        widget.materialId,
        position: _lastChunkIndex,
        percent: percent,
        addMinutes: _stopwatch.elapsed.inMinutes,
        addLookups: _lookups,
        addPickedWords: _picked,
        finished: finished,
      );
      // 记一次阅读会话:导师要读"读了多久/多快/查了多少词"
      if (_stopwatch.elapsed.inSeconds >= 20) {
        await DatabaseService.insertReadingSession(
          materialId: widget.materialId,
          words: _wordCountSoFar(),
          lookups: _lookups,
          duration: _stopwatch.elapsed,
        );
      }
      _stopwatch.reset();
      _stopwatch.start();
      _lookups = 0;
      _picked = 0;
    } catch (e) {
      debugPrint('阅读进度写入失败: $e');
    }
  }

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
      body: _loading
          ? const AppLoading(label: '正在打开材料…')
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
                        itemCount: _chunks.length + (_translateError == null ? 0 : 1),
                        itemBuilder: (_, i) {
                          // 第一行留给翻译失败的说明(不挡住正文)
                          if (_translateError != null && i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: Gap.sm),
                              child: AppErrorCard(
                                message: '翻译失败:$_translateError',
                                onRetry: _toggleTranslation,
                                retryLabel: '重试翻译',
                              ),
                            );
                          }
                          final index =
                              _translateError == null ? i : i - 1;
                          return _buildChunk(theme, index);
                        },
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
                      moreActions: [
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
          // 逐段译文(v2.6):紧跟在本段英文下面,浅色区分 + 稍小字号
          if (_showTranslation) ...[
            const SizedBox(height: Gap.xs),
            if (_translating && !_translations.containsKey(index))
              Text('翻译中…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: Radii.controlRadius,
                ),
                child: Text(
                  _translations[index] ?? '(这一段还没翻出来)',
                  style: TextStyle(
                    fontSize: ReaderSettings.baseFontSize * _fontScale * 0.86,
                    height: _lineHeight * 0.95,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
