import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/vocabulary.dart';
import '../../providers/vocab_provider.dart';
import '../../services/tts_service.dart';

/// 复习模式(v1.5.0):抽认卡 — 看词想义 → 翻面核对 → 标记掌握度。
/// 数据源:生词本;按掌握度筛选(全部/新词/学习中/已掌握);
/// 标记结果实时写回数据库(VocabProvider.updateMastery)。
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  /// 筛选掌握度:-1=全部
  int _filterLevel = -1;
  List<Vocabulary> _deck = [];
  int _index = 0;
  bool _flipped = false;
  bool _loading = true;
  String? _error;

  // 本轮标记统计
  int _countMastered = 0; // →2
  int _countLearning = 0; // →1
  int _countNew = 0; // →0
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<VocabProvider>().loadVocabularies();
      _buildDeck();
    } catch (e) {
      _error = '加载生词失败：$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _buildDeck() {
    final all = context.read<VocabProvider>().vocabularies;
    // 只复习至少带释义的条目(没释义的卡片没法"想义",复习无意义)
    var items = all
        .where((v) => (v.translation ?? '').isNotEmpty)
        .toList();
    if (_filterLevel >= 0) {
      items = items.where((v) => v.masteryLevel == _filterLevel).toList();
    }
    items.shuffle(Random());
    setState(() {
      _deck = items;
      _index = 0;
      _flipped = false;
      _countMastered = 0;
      _countLearning = 0;
      _countNew = 0;
      _finished = false;
    });
  }

  Future<void> _mark(int level) async {
    final v = _deck[_index];
    // 先写库(异步,失败也要翻下一张,不卡复习)
    try {
      await context.read<VocabProvider>().updateMastery(v.id!, level);
    } catch (_) {
      // 记录失败不阻断复习流
    }
    if (!mounted) return;
    setState(() {
      switch (level) {
        case 2:
          _countMastered++;
        case 1:
          _countLearning++;
        default:
          _countNew++;
      }
      if (_index + 1 >= _deck.length) {
        _finished = true;
      } else {
        _index++;
        _flipped = false;
      }
    });
  }

  Future<void> _speak(Vocabulary v) async {
    final ok = await TtsService.instance.speak(v.displayLabel);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('复习模式')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _deck.isEmpty
                  ? _buildEmpty(theme)
                  : _buildBody(theme),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.style_outlined, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            _filterLevel >= 0
                ? '该掌握度下暂无带释义的词汇'
                : '生词本里还没有带释义的词汇',
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              setState(() => _filterLevel = -1);
              _buildDeck();
            },
            child: const Text('查看全部'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final v = _deck[_index];
    return Column(
      children: [
        // ── 筛选条 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...['全部', '新词', '学习中', '已掌握'].asMap().entries.map((e) {
                  final level = e.key - 1; // -1,0,1,2
                  final label = e.value;
                  final isSel = _filterLevel == level;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(label),
                      selected: isSel,
                      onSelected: (_) {
                        setState(() => _filterLevel = level);
                        _buildDeck();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _buildDeck,
                  tooltip: '打乱重来',
                  icon: const Icon(Icons.shuffle, size: 18),
                ),
              ],
            ),
          ),
        ),
        // ── 进度 ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    _finished
                        ? '本轮完成'
                        : '第 ${_index + 1} / ${_deck.length} 张',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '✓已掌握 $_countMastered · 学习中 $_countLearning · 新词 $_countNew',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: _finished
                    ? 1
                    : (_deck.isEmpty ? 0 : (_index + 1) / _deck.length),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ),
        ),
        // ── 卡片区 ──
        Expanded(
          child: _finished ? _buildSummary(theme) : _buildCard(theme, v),
        ),
      ],
    );
  }

  Widget _buildCard(ThemeData theme, Vocabulary v) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _flipped = !_flipped),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Card(
                  key: ValueKey(_flipped),
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _flipped ? _cardBack(theme, v) : _cardFront(theme, v),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── 标记掌握度 ──
          Row(
            children: [
              Expanded(
                child: _markButton(
                  theme,
                  label: '不认识',
                  icon: Icons.sentiment_very_dissatisfied,
                  color: Colors.red,
                  level: 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _markButton(
                  theme,
                  label: '模糊',
                  icon: Icons.sentiment_neutral,
                  color: Colors.blue,
                  level: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _markButton(
                  theme,
                  label: '认识',
                  icon: Icons.sentiment_very_satisfied,
                  color: Colors.green,
                  level: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardFront(ThemeData theme, Vocabulary v) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '看词想义',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey[400],
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          v.displayLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
        ),
        if (v.phonetic != null && v.phonetic!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            v.phonetic!,
            style: TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: Colors.grey[600],
            ),
          ),
        ],
        const SizedBox(height: 16),
        IconButton(
          onPressed: () => _speak(v),
          tooltip: '朗读',
          icon: Icon(
            Icons.volume_up_outlined,
            size: 28,
            color: theme.colorScheme.primary,
          ),
        ),
        const Spacer(),
        Text(
          '轻点卡片查看释义',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
        ),
      ],
    );
  }

  Widget _cardBack(ThemeData theme, Vocabulary v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          v.displayLabel,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (v.phonetic != null && v.phonetic!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            v.phonetic!,
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Colors.grey[600],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.translation ?? '',
                  style: theme.textTheme.titleMedium,
                ),
                if (v.originalSentence != null &&
                    v.originalSentence!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    v.originalSentence!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ],
                if (v.grammarNote != null && v.grammarNote!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    v.grammarNote!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Center(
          child: Text(
            '选择下方掌握度继续',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration, size: 56, color: Colors.amber),
            const SizedBox(height: 16),
            Text('本轮复习完成！',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              '共 $_countMastered 张认识 · $_countLearning 张模糊 · $_countNew 张不认识',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _buildDeck,
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('再来一轮'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _markButton(
    ThemeData theme, {
    required String label,
    required IconData icon,
    required Color color,
    required int level,
  }) {
    return GestureDetector(
      onTap: () => _mark(level),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withAlpha(12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(120), width: 1.4),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
