import 'dart:async';

import 'package:flutter/gestures.dart';
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
import '../../services/doubao_api.dart';
import '../../services/material_library.dart';
import '../../services/reader_settings.dart';
import '../../services/reading_quiz.dart';
import '../../services/text_difficulty.dart';
import '../../services/tts_service.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/audio_player_bar.dart';
import 'dictation_screen.dart';
import 'reading_quiz_screen.dart';

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

  // ── 点词:释义 / 朗读 / 收进生词本 ──
  Future<void> _onWordTap(String rawWord) async {
    final word = rawWord.trim();
    if (word.isEmpty) return;
    _lookups++;
    final sentence = _sentenceAround(word);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _WordSheet(
        word: word,
        sentence: sentence,
        onSpeak: (t) => TtsService.instance.speak(t),
        onSave: (v) => _saveWord(v),
      ),
    );
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
      return '已收进生词本(会出现在复习里)';
    } catch (e) {
      return '保存失败:$e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final title = '${_material?['title'] ?? '阅读'}';
    final a = _analysis;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          // 逐段翻译(v2.6):点一下 = 英文原文 + 中文对照(按段)
          IconButton(
            tooltip: _showTranslation ? '关闭翻译' : '翻译(逐段英中对照)',
            onPressed: _chunks.isEmpty ? null : _toggleTranslation,
            icon: Icon(_showTranslation ? Icons.translate : Icons.translate_outlined),
          ),
          // 阅读设置(v2.5):字号 / 行距 —— 长时间读英文最需要的两个旋钮
          IconButton(
            tooltip: '阅读设置(字号 / 行距)',
            onPressed: _showReaderSettings,
            icon: const Icon(Icons.format_size),
          ),
          // 听写练习(v2.2):用 TTS 按句出题 —— 文字与音频天然对齐,可客观判分
          IconButton(
            tooltip: '听写练习',
            onPressed: _chunks.isEmpty
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DictationScreen(
                          title: '${_material?['title'] ?? '材料'}',
                          text: _chunks
                              .map((c) => '${c['text'] ?? ''}')
                              .join('\n\n'),
                        ),
                      ),
                    ),
            icon: const Icon(Icons.headphones_outlined),
          ),
          // 导出这篇为 Markdown 阅读包(带来源/许可/生词表)
          IconButton(
            tooltip: '导出这篇(Markdown)',
            onPressed: _chunks.isEmpty ? null : _exportPack,
            icon: const Icon(Icons.download_outlined),
          ),
          if (!_finished)
            TextButton(
              onPressed: _finishReading,
              child: const Text('读完了'),
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
          _TappableText(
            text: text,
            onWordTap: _onWordTap,
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

/// 可点词的正文。
///
/// 实现取舍:把段落按词切成 TextSpan + TapGestureRecognizer。
/// 超长段落(>1200 词)不切词 —— 上万个 span 会让低端机掉帧,
/// 这时退化成普通可选文本(长按仍可复制,只是没有点词查词)。
class _TappableText extends StatefulWidget {
  final String text;
  final void Function(String word) onWordTap;
  final TextStyle style;

  const _TappableText({
    required this.text,
    required this.onWordTap,
    required this.style,
  });

  @override
  State<_TappableText> createState() => _TappableTextState();
}

class _TappableTextState extends State<_TappableText> {
  static const int maxSpans = 1200;
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = TextDifficulty.tokenize(widget.text);
    if (tokens.length > maxSpans) {
      return SelectableText(widget.text, style: widget.style);
    }

    // 用正则切分保留原标点与空格(只在词上挂手势)
    final spans = <InlineSpan>[];
    final pattern = RegExp(r"[A-Za-z]+(?:'[A-Za-z]+)*(?:-[A-Za-z]+)*");
    var cursor = 0;
    for (final m in pattern.allMatches(widget.text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, m.start)));
      }
      final word = m.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onWordTap(word);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: word,
        recognizer: recognizer,
        style: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: theme.colorScheme.primary.withAlpha(60),
        ),
      ));
      cursor = m.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }

    return SelectableText.rich(
      TextSpan(style: widget.style, children: spans),
    );
  }
}

/// 点词后的底部弹层:AI 释义(按需拉取)+ 朗读 + 收进生词本
class _WordSheet extends StatefulWidget {
  final String word;
  final String sentence;
  final Future<bool> Function(String text) onSpeak;
  final Future<String> Function(Vocabulary v) onSave;

  const _WordSheet({
    required this.word,
    required this.sentence,
    required this.onSpeak,
    required this.onSave,
  });

  @override
  State<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<_WordSheet> {
  final _api = DoubaoApiService();
  Map<String, String>? _info;
  bool _loading = true;
  String? _error;
  String _saveMsg = '';

  /// 「询问 AI」的流式讲解(v2.6)
  bool _asking = false;
  String _aiAnswer = '';
  String? _aiError;
  StreamSubscription<SseChunk>? _aiSub;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void dispose() {
    _aiSub?.cancel();
    super.dispose();
  }

  /// 就这一个词问 AI(流式),答案就地显示在面板里 —— 不再跳去别的页面
  Future<void> _askAi() async {
    setState(() {
      _asking = true;
      _aiError = null;
      _aiAnswer = '';
    });
    try {
      final stream = _api.explainWord(
        word: widget.word,
        sentence: widget.sentence,
      );
      _aiSub = stream.listen(
        (chunk) {
          if (!mounted || chunk.isReasoning) return;
          setState(() => _aiAnswer += chunk.text);
        },
        onDone: () {
          if (mounted) setState(() => _asking = false);
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _asking = false;
              _aiError = '$e';
            });
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _asking = false;
          _aiError = '$e';
        });
      }
    }
  }

  Future<void> _lookup() async {
    try {
      final info = await _api.completeWordInfo(widget.word);
      if (!mounted) return;
      setState(() {
        _info = info;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final info = _info ?? const <String, String>{};
    final phonetic = info['phonetic'] ?? '';
    final pos = info['part_of_speech'] ?? '';
    final translation = info['translation'] ?? '';
    final example = info['original_sentence'] ?? '';
    final grammar = info['grammar_note'] ?? '';
    return SafeArea(
      // 大字号(2× 系统字号)下弹层会变高 —— 可滚动,永不溢出
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ① 词头:词 + 音标 + 朗读(层级最高,一眼定位到"我点的是哪个词")
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.word,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (phonetic.isNotEmpty) ...[
                        const SizedBox(height: Gap.xxs),
                        Text(phonetic,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: muted)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Gap.xs),
                IconButton.filledTonal(
                  tooltip: '朗读',
                  onPressed: () => widget.onSpeak(widget.word),
                  icon: const Icon(Icons.volume_up_outlined),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            // ② 释义区(按需从 AI 拉,加载时不挡住词头)
            if (_loading)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: Gap.xs),
                  Text('正在查释义…',
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: muted)),
                ],
              )
            else if (_error != null)
              AppErrorCard(
                message: '查询失败:$_error',
                retryLabel: '重新查',
                onRetry: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _lookup();
                },
              )
            else ...[
              if (pos.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Gap.xs, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(Radii.control - 4),
                  ),
                  child: Text(pos,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ),
                const SizedBox(height: Gap.xs),
              ],
              if (translation.isNotEmpty)
                Text(translation, style: theme.textTheme.bodyLarge),
              if (example.isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Gap.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: Radii.controlRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('例句',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: Gap.xxs),
                      Text(example,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.5)),
                    ],
                  ),
                ),
              ],
              if (grammar.isNotEmpty) ...[
                const SizedBox(height: Gap.xs),
                Text('语法:$grammar',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: muted, height: 1.5)),
              ],
            ],
            const SizedBox(height: Gap.md),
            // ③ 两个动作(用户第 8(4) 条:点词/选词后底部给两个小选项)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _asking ? null : _askAi,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                    ),
                    icon: const Icon(Icons.help_outline, size: 18),
                    label: Text(_asking ? 'AI 正在讲…' : '询问 AI'),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final v = Vocabulary(
                        word: widget.word,
                        translation: info['translation'],
                        partOfSpeech: info['part_of_speech'],
                        phonetic: info['phonetic'],
                        originalSentence:
                            info['original_sentence']?.isNotEmpty == true
                                ? info['original_sentence']
                                : (widget.sentence.isEmpty
                                    ? null
                                    : widget.sentence),
                        grammarNote: info['grammar_note'],
                        sourceBook: null,
                        wordType: 'word',
                      );
                      final msg = await widget.onSave(v);
                      if (!mounted) return;
                      setState(() => _saveMsg = msg);
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 46),
                    ),
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('收藏进单词本'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xs),
            Text(
              _saveMsg.isNotEmpty
                  ? _saveMsg
                  : '收藏后会立刻进入复习队列(下次复习按记忆强度安排)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _saveMsg.isNotEmpty
                    ? theme.colorScheme.primary
                    : muted,
              ),
            ),
            // AI 讲解区(流式)
            if (_aiAnswer.isNotEmpty || _aiError != null || _asking) ...[
              const SizedBox(height: Gap.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(12),
                  borderRadius: Radii.controlRadius,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: Gap.xxs + 2),
                        Text('AI 讲解',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ),
                    const SizedBox(height: Gap.xxs + 2),
                    if (_aiError != null)
                      Text('讲解失败:$_aiError',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppTheme.dangerColor(context)))
                    else
                      Text(
                        _aiAnswer.isEmpty ? '正在想…' : _aiAnswer,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(height: 1.5),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
