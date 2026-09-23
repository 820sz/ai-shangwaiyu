import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/vocabulary.dart';
import '../../providers/vocab_provider.dart';
import '../../services/database.dart';
import '../../services/dictation.dart';
import '../../services/tts_service.dart';

/// 听写练习(v2.2 听说)。
///
/// 设计取舍(为什么用系统 TTS 而不是材料自带音频):
/// RSS 音频没有时间轴,无法把"第 37 秒"对到"文中第几句";硬做只会变成
/// 假功能。而 TTS 按句子生成语音,**文字与音频天然对齐** ——
/// 于是听写可以**客观判分**(逐词 LCS 比对),这是真练习而不是感觉。
///
/// 诚实边界:只比对**文字**,不评分发音(没有语音识别就不编造发音分);
/// 想练发音请用「跟读」—— 听一遍、自己说一遍,不做假评分。
class DictationScreen extends StatefulWidget {
  /// 材料标题(结果页展示)
  final String title;

  /// 材料正文(出题来源)
  final String text;

  const DictationScreen({
    super.key,
    required this.title,
    required this.text,
  });

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  final _ctrl = TextEditingController();
  late final List<String> _sentences;
  int _index = 0;
  DictationResult? _current;
  final List<DictationResult> _results = [];
  bool _saving = false;
  String _saveMsg = '';

  @override
  void initState() {
    super.initState();
    // seed 用标题长度:同一份材料每次出同样的句子,便于复盘
    _sentences = Dictation.pickSentences(
      widget.text,
      count: 5,
      seed: widget.title.length + 7,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _play();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    TtsService.instance.stop();
    super.dispose();
  }

  Future<void> _play({bool slow = false}) async {
    if (_sentences.isEmpty) return;
    final s = _sentences[_index];
    if (slow) {
      await TtsService.instance.speakSlowPreferred(s);
    } else {
      await TtsService.instance.speakPreferred(s);
    }
  }

  void _submit() {
    final r = Dictation.grade(_sentences[_index], _ctrl.text);
    setState(() {
      _current = r;
      _results.add(r);
    });
  }

  void _next() {
    if (_index + 1 >= _sentences.length) {
      setState(() => _index = _sentences.length); // 进入总结
      return;
    }
    setState(() {
      _index++;
      _current = null;
      _ctrl.clear();
    });
    _play();
  }

  /// 把这一轮漏掉的词收进生词本(听不出来 = 最该背的词)
  Future<void> _saveMissedWords() async {
    final words = Dictation.missWords(_results);
    if (words.isEmpty) return;
    setState(() {
      _saving = true;
      _saveMsg = '';
    });
    try {
      final provider = context.read<VocabProvider>();
      await provider.saveVocabularies([
        for (final w in words)
          Vocabulary(
            word: w,
            sourceBook: widget.title,
            category: '其他',
            wordType: 'word',
          ),
      ]);
      // 与阅读器一致:入库即建立复习状态 → 直接进复习队列
      final saved = await DatabaseService.getVocabularies(limit: 500);
      var linked = 0;
      for (final w in words) {
        final hit = saved.where((v) => v.word.toLowerCase() == w);
        if (hit.isEmpty || hit.first.id == null) continue;
        await DatabaseService.upsertWordReview(
          hit.first.id!,
          stability: 0,
          difficulty: 6,
          dueAt: DateTime.now(),
          lastReviewAt: DateTime.now(),
        );
        linked++;
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveMsg = '已收进生词本 $linked 个(会出现在复习里)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveMsg = '保存失败:$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (_sentences.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('听写练习')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('这份材料里没有适合听写的句子(太短或太长)'),
          ),
        ),
      );
    }
    final done = _index >= _sentences.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(done ? '听写结果' : '听写 ${_index + 1}/${_sentences.length}'),
        bottom: done
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: _index / _sentences.length,
                  minHeight: 4,
                ),
              ),
      ),
      body: done ? _buildSummary(theme, muted) : _buildQuestion(theme, muted),
    );
  }

  Widget _buildQuestion(ThemeData theme, Color muted) {
    final r = _current;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '听发音,把整句写下来。听不清就点「慢速」—— 慢速重放比同速重放有用。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              tooltip: '播放',
              onPressed: () => _play(),
              icon: const Icon(Icons.play_arrow),
              iconSize: 28,
            ),
            const SizedBox(width: 12),
            ActionChip(
              avatar: const Icon(Icons.slow_motion_video, size: 16),
              label: const Text('慢速', style: TextStyle(fontSize: 12)),
              onPressed: () => _play(slow: true),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _ctrl,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          enabled: r == null,
          decoration: const InputDecoration(
            hintText: '在这里写下你听到的句子…',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            if (r == null) _submit();
          },
        ),
        const SizedBox(height: 12),
        if (r == null)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _ctrl.text.trim().isEmpty ? null : _submit,
              child: const Text('提交'),
            ),
          )
        else ...[
          _buildResultCard(theme, muted, r),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _next, child: const Text('下一句')),
          ),
        ],
      ],
    );
  }

  Widget _buildResultCard(ThemeData theme, Color muted, DictationResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.perfect ? Icons.check_circle : Icons.rule,
                  color: r.perfect ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 6),
                Text('正确率 ${r.scoreLine}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Text('原文:${r.reference}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text('你写的:${r.typed.trim().isEmpty ? '(空)' : r.typed}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            const SizedBox(height: 8),
            Text(r.comment, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(ThemeData theme, Color muted) {
    final missed = Dictation.missWords(_results);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Text(Dictation.summaryLine(_results),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge),
                const SizedBox(height: 10),
                if (missed.isNotEmpty) ...[
                  Text('这一轮没听出来的词:',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  const SizedBox(height: 4),
                  Text(missed.take(12).join('、'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _results.length; i++)
          Card(
            child: ListTile(
              dense: true,
              leading: Text('${i + 1}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              title: Text(_results[i].reference, style: theme.textTheme.bodySmall),
              trailing: Text(_results[i].scoreLine,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _results[i].perfect ? Colors.green : Colors.orange,
                  )),
            ),
          ),
        const SizedBox(height: 12),
        if (missed.isNotEmpty)
          FilledButton.icon(
            onPressed: _saving ? null : _saveMissedWords,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(_saving ? '保存中…' : '把没听出的词收进生词本(${missed.length})'),
          ),
        if (_saveMsg.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_saveMsg, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
        const SizedBox(height: 8),
        Text(
          '提示:这一页只对**文字**判分,不评发音。想练发音请用材料音频(如果有)'
          '跟着念 —— 我们不做没有依据的发音打分。',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}
