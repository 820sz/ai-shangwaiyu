import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/vocabulary.dart';
import '../../providers/vocab_provider.dart';
import '../../services/tts_service.dart';
import '../input/widgets/example_sentence.dart';

class VocabDetailScreen extends StatefulWidget {
  final Vocabulary vocab;

  const VocabDetailScreen({super.key, required this.vocab});

  @override
  State<VocabDetailScreen> createState() => _VocabDetailScreenState();
}

class _VocabDetailScreenState extends State<VocabDetailScreen> {
  late Vocabulary _vocab;

  @override
  void initState() {
    super.initState();
    _vocab = widget.vocab;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('生词详情'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 单词大字:截断词条回退显示完整句子(F8,与列表/横幅一致)
          // v1.5.0:点单词本体即朗读(系统 TTS);右侧另有喇叭按钮
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _speak,
                  child: Text(
                    _vocab.displayWordText,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              IconButton(
                onPressed: _speak,
                tooltip: '朗读',
                icon: Icon(
                  Icons.volume_up_outlined,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 音标(v1.5.0,AI 补全生成)
          if (_vocab.phonetic != null && _vocab.phonetic!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _vocab.phonetic!,
                style: TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[600],
                ),
              ),
            ),
          const SizedBox(height: 4),
          if (_vocab.translation != null && _vocab.translation!.isNotEmpty)
            Text(
              _vocab.translation!,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: Colors.grey[600]),
            ),
          const Divider(height: 32),

          // 基本信息
          _SectionTitle(title: '基本信息'),
          _InfoTile(
              label: '类型',
              value: _vocab.wordType == 'word'
                  ? '单词'
                  : _vocab.wordType == 'phrase'
                      ? '短语'
                      : '句子'),
          _InfoTile(label: '出处', value: _vocab.sourceSummary),
          _InfoTile(
              label: '添加时间',
              value:
                  '${_vocab.createdAt.month}月${_vocab.createdAt.day}日 '
                  '${_vocab.createdAt.hour.toString().padLeft(2, '0')}:${_vocab.createdAt.minute.toString().padLeft(2, '0')}'),

          // 例句
          if (_vocab.originalSentence != null &&
              _vocab.originalSentence!.isNotEmpty) ...[
            const Divider(height: 24),
            _SectionTitle(title: '原文例句'),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: ExampleSentence(
                  sentence: _vocab.originalSentence!,
                  highlightWord: _vocab.word,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(height: 1.6, fontStyle: FontStyle.italic),
                ),
              ),
            ),
          ],

          // 掌握度
          const Divider(height: 24),
          _SectionTitle(title: '掌握程度'),
          const SizedBox(height: 8),
          Row(
            children: [
              _MasteryButton(
                label: '新词',
                level: 0,
                current: _vocab.masteryLevel,
                color: Colors.orange,
                onTap: () => _updateMastery(0),
              ),
              const SizedBox(width: 8),
              _MasteryButton(
                label: '学习中',
                level: 1,
                current: _vocab.masteryLevel,
                color: Colors.blue,
                onTap: () => _updateMastery(1),
              ),
              const SizedBox(width: 8),
              _MasteryButton(
                label: '已掌握',
                level: 2,
                current: _vocab.masteryLevel,
                color: Colors.green,
                onTap: () => _updateMastery(2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _speak() async {
    final ok = await TtsService.instance.speak(_vocab.displayWordText);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设备未找到可用语音引擎，暂时无法朗读'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _updateMastery(int level) async {
    await context.read<VocabProvider>().updateMastery(_vocab.id!, level);
    setState(() {
      _vocab = _vocab.copyWith(masteryLevel: level);
    });
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _MasteryButton extends StatelessWidget {
  final String label;
  final int level;
  final int current;
  final Color color;
  final VoidCallback onTap;

  const _MasteryButton({
    required this.label,
    required this.level,
    required this.current,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = current == level;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withAlpha(30) : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? color : Colors.grey,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
