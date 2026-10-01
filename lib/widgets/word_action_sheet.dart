import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/design_tokens.dart';
import '../config/theme.dart';
import '../models/vocabulary.dart';
import '../providers/vocab_provider.dart';
import '../services/doubao_api.dart';
import '../services/tts_service.dart';
import '../screens/input/widgets/category_picker.dart';
import '../screens/input/widgets/sub_category_input.dart';
import 'app_ui.dart';
import 'waiting.dart';

/// 词条要存到哪儿(v2.7,用户第 3 条:"选择保存位置")。
///
/// 为什么必须有它:阅读器以前收藏生词时 `sourceBook: null`、分类也不写 ——
/// 结果是"从材料里收的词全掉进「未归类」"(用户第 6(2) 条抱怨的正是这个现象)。
/// 现在:默认位置由材料带出来(分类 + 材料名 + 页码),用户随时可以改。
class WordSaveTarget {
  /// 学习分类(教材/书籍/外刊/碎片文章/其他)
  final String category;

  /// 材料名 / 书名
  final String materialName;

  /// 页码 / 章节(可空)
  final String page;

  const WordSaveTarget({
    this.category = '其他',
    this.materialName = '',
    this.page = '',
  });

  String get label {
    final parts = <String>[
      if (materialName.trim().isNotEmpty) materialName.trim(),
      if (page.trim().isNotEmpty) page.trim(),
    ];
    final tail = parts.isEmpty ? '未指定材料' : parts.join(' · ');
    return '$category / $tail';
  }

  /// 生成要入库的词条(出处字段一次写全,不再各调用点各拼一份)
  Vocabulary toVocabulary({
    required String word,
    String? translation,
    String? partOfSpeech,
    String? phonetic,
    String? sentence,
    String? grammarNote,
    String wordType = 'word',
  }) {
    final name = materialName.trim();
    return Vocabulary(
      word: word,
      translation: translation,
      partOfSpeech: partOfSpeech,
      phonetic: phonetic,
      originalSentence: sentence,
      grammarNote: grammarNote,
      wordType: wordType,
      category: category,
      sourceBook: name.isEmpty ? null : name,
      materialPath:
          name.isEmpty ? null : '$category/$name',
    );
  }
}

/// 点词 / 长按选词后的底部弹层(v2.7 抽成公共件,三个阅读器共用)。
///
/// 两个动作与用户第 2(2) 条的要求一一对应:
/// 1. **询问 AI** —— 就这一处流式讲清楚(不跳页);
/// 2. **收藏进单词本** —— 入库并建立复习状态,同时显示/可改「保存位置」。
///
/// [autoAsk] = 由「询问 AI」入口进来时直接开始讲解(用户不用再点一次)。
Future<void> showWordActionSheet(
  BuildContext context, {
  required String word,
  String sentence = '',
  WordSaveTarget? target,
  bool autoAsk = false,
  String sourceTitle = '',
  Future<String> Function(Vocabulary v)? onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // v2.8(用户第 3 条):弹层换更"跟手"的曲线与时长 —— 默认 250ms 线性上滑
    // 在真机上像"啪一下弹出来";这里先快后慢,与全 App 的 Motion.curve 一致
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      reverseDuration: Duration(milliseconds: 220),
    ),
    builder: (ctx) => _WordActionSheet(
      word: word,
      sentence: sentence,
      target: target ?? const WordSaveTarget(),
      autoAsk: autoAsk,
      sourceTitle: sourceTitle,
      onSave: onSave,
    ),
  );
}

class _WordActionSheet extends StatefulWidget {
  final String word;
  final String sentence;
  final WordSaveTarget target;
  final bool autoAsk;
  final String sourceTitle;
  final Future<String> Function(Vocabulary v)? onSave;

  const _WordActionSheet({
    required this.word,
    required this.sentence,
    required this.target,
    required this.autoAsk,
    required this.sourceTitle,
    this.onSave,
  });

  @override
  State<_WordActionSheet> createState() => _WordActionSheetState();
}

class _WordActionSheetState extends State<_WordActionSheet> {
  final _api = DoubaoApiService();
  Map<String, String>? _info;
  bool _loading = true;
  String? _error;
  String _saveMsg = '';
  late WordSaveTarget _target = widget.target;

  /// 「询问 AI」的流式讲解
  bool _asking = false;
  String _aiAnswer = '';
  String? _aiError;
  StreamSubscription<SseChunk>? _aiSub;

  @override
  void initState() {
    super.initState();
    _lookup();
    if (widget.autoAsk) {
      // 用户是从「询问 AI」进来的:直接开始讲
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _askAi();
      });
    }
  }

  @override
  void dispose() {
    _aiSub?.cancel();
    super.dispose();
  }

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
        sourceBook: widget.sourceTitle.isEmpty ? null : widget.sourceTitle,
      );
      _aiSub = stream.listen(
        (chunk) {
          if (!mounted || chunk.isReasoning) return;
          setState(() => _aiAnswer += chunk.text);
        },
        onDone: () {
          if (mounted) setState(() => _asking = false);
        },
        onError: (Object e) {
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

  /// 改「保存位置」(第 3 条):分类 → 材料名/页码,复用生词本里那两个选择器,
  /// 不另造一套交互。
  Future<void> _changeTarget() async {
    final category = await showCategoryPicker(context);
    if (category == null || !mounted) return;
    final sub = await showSubCategoryInput(
      context,
      category: category,
      prefill: _target.materialName,
    );
    if (sub == null || !mounted) return;
    setState(() {
      _target = WordSaveTarget(
        category: category,
        materialName: sub.materialName,
        page: sub.sourcePage ?? '',
      );
    });
  }

  Future<void> _save() async {
    final info = _info ?? const <String, String>{};
    final v = _target.toVocabulary(
      word: widget.word,
      translation: info['translation'],
      partOfSpeech: info['part_of_speech'],
      phonetic: info['phonetic'],
      sentence: (info['original_sentence']?.isNotEmpty == true)
          ? info['original_sentence']
          : (widget.sentence.isEmpty ? null : widget.sentence),
      grammarNote: info['grammar_note'],
      wordType: widget.word.contains(' ') ? 'phrase' : 'word',
    );
    String msg;
    if (widget.onSave != null) {
      msg = await widget.onSave!(v);
    } else {
      try {
        await context.read<VocabProvider>().saveVocabularies([v]);
        msg = '已收进生词本(会出现在复习里)';
      } catch (e) {
        msg = '保存失败:$e';
      }
    }
    if (!mounted) return;
    setState(() => _saveMsg = msg);
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
            // ① 词头:词 + 音标 + 朗读
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
                  onPressed: () => TtsService.instance.speak(widget.word),
                  icon: const Icon(Icons.volume_up_outlined),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),

            // ② 释义区(按需从 AI 拉)
            //
            // v2.8(用户第 3 条"唤起要有过渡动画"):加载态与结果之间用
            // AnimatedSwitcher 过渡 —— 旧实现是"转圈突然被一段文字顶掉",
            // 视觉上很生硬;现在淡入 + 轻微上移,弹层内容的出现不再"跳"。
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: _loading
                  ? Column(
                      key: const ValueKey('loading'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // v2.9:释义是"生成长文本",用骨架屏而不是转圈 ——
                        // 用户先看到结果将要占据的形状,等待感明显变短
                        const ThinkingDots(label: '正在查释义', compact: true),
                        const SizedBox(height: Gap.xs),
                        const SkeletonLines(lines: 3, withTitle: false),
                      ],
                    )
                  : (_error != null
                      ? AppErrorCard(
                          key: const ValueKey('error'),
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
                      : Column(
                          key: const ValueKey('loaded'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (pos.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: Gap.xs, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme.surfaceContainerHighest,
                                  borderRadius:
                                      BorderRadius.circular(Radii.control - 4),
                                ),
                                child: Text(pos,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: muted)),
                              ),
                              const SizedBox(height: Gap.xs),
                            ],
                            if (translation.isNotEmpty)
                              Text(translation,
                                  style: theme.textTheme.bodyLarge),
                            if (example.isNotEmpty) ...[
                              const SizedBox(height: Gap.sm),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(Gap.sm),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme.surfaceContainerHighest,
                                  borderRadius: Radii.controlRadius,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('例句',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
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
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: muted, height: 1.5)),
                            ],
                          ],
                        )),
            ),

            // ③ 保存位置(第 3 条):默认跟着材料走,可改 —— 不改也不会掉进「未归类」
            const SizedBox(height: Gap.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Gap.sm, vertical: Gap.xxs + 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(10),
                borderRadius: Radii.controlRadius,
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 15, color: theme.colorScheme.primary),
                  const SizedBox(width: Gap.xxs + 2),
                  Expanded(
                    child: Text(
                      '保存到:${_target.label}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        height: 1.3,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _changeTarget,
                    child: const Text('改'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.xs),

            // ④ 两个动作(用户第 2(2) 条)
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
                    onPressed: _save,
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
                color: _saveMsg.isNotEmpty ? theme.colorScheme.primary : muted,
              ),
            ),

            // ⑤ AI 讲解区(流式;v2.8 加出现动画与"打字中"指示)
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !(_aiAnswer.isNotEmpty || _aiError != null || _asking)
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: Gap.sm),
                      child: Container(
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
                                const Spacer(),
                                if (_asking) const _TypingDots(),
                              ],
                            ),
                            const SizedBox(height: Gap.xxs + 2),
                            if (_aiError != null)
                              Text('讲解失败:$_aiError',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppTheme.dangerColor(context)))
                            else if (_aiAnswer.isEmpty)
                              // 还没吐第一个字:给骨架条,而不是一句静止的"正在想…"
                              const _SkeletonLines()
                            else
                              // v2.8(用户第 8 条"配色太多显得花"):讲解正文**只用正文色**,
                              // 强调靠字重 —— 旧实现里标题/列表/引用各一套色,
                              // 一段话里同时出现主色+琥珀+绿+红,看着很乱
                              Text(
                                _aiAnswer,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.6,
                                  color: theme.colorScheme.onSurface,
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
    );
  }
}

/// AI 正在生成时的三点动画(v2.8,用户第 3 条"要过渡动画")。
///
/// 比一句静止的「正在想…」好得多:用户一眼就知道"它还在打字",不会以为卡住。
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 第 i 个点的亮度:0.25~1.0 之间按周期依次亮起
  double _dotOpacity(int i) {
    final phase = (_ctrl.value - i / 3.0) % 1.0;
    final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return 0.25 + 0.75 * wave;
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Opacity(
                opacity: _dotOpacity(i).clamp(0.25, 1.0),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 讲解还没开始出字时的骨架条(比一句静止的"正在想…"更像"正在生产")
class _SkeletonLines extends StatefulWidget {
  const _SkeletonLines();

  @override
  State<_SkeletonLines> createState() => _SkeletonLinesState();
}

class _SkeletonLinesState extends State<_SkeletonLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in const [1.0, 0.86, 0.55])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: FractionallySizedBox(
                widthFactor: w,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: base.withAlpha((14 + 16 * _ctrl.value).round()),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
