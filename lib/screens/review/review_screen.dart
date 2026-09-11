import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../models/vocabulary.dart';
import '../../providers/vocab_provider.dart';
import '../../services/tts_service.dart';
import '../../utils/review_deck.dart';

/// 复习模式(v1.5.0 初版 / v1.7.0 重做)。
///
/// v1.7.0 修复用户实测 5 个问题:
/// 1. 标记后不再直接跳过——自动翻面显示释义,看完点「下一张」
/// 2. 支持左右滑动 + ⬅➡ 按钮前后翻卡(可回看上一张)
/// 3. 顶部筛选/进度对比度提高(深色文字 + 主题色进度条)
/// 4. 分类增加日期筛选(今天/近3天/近一周/近一月),卡片显示保存时间
/// 5. 复习进度持久化(Hive):退出再进可「继续上次」
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  static const _progressKey = 'review_progress';

  /// 掌握度筛选:-1=全部
  int _filterLevel = -1;

  /// 日期筛选天数:0=全部
  int _filterDays = 0;

  List<Vocabulary> _deck = [];
  int _index = 0;
  bool _flipped = false;
  bool _loading = true;
  String? _error;

  int _countMastered = 0;
  int _countLearning = 0;
  int _countNew = 0;
  bool _finished = false;

  /// 本轮每张卡的标记结果(word id → mastery),回看上一张时高亮
  final Map<int, int> _marks = {};

  /// 可续的进度(用于顶部提示条)
  ReviewProgress? _resumable;

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
      final all = context.read<VocabProvider>().vocabularies;
      // 读上次进度:卡组与当前词库一致 + 已翻过页,才提示续看
      final saved = _readProgress();
      if (saved != null && !saved.isEmpty) {
        final candidate = filterReviewItems(
          all,
          level: saved.filterLevel,
          days: saved.filterDays,
        );
        final sameFilter =
            saved.filterLevel == _filterLevel && saved.filterDays == _filterDays;
        if (sameFilter && saved.matchesDeck(candidate) && saved.index > 0) {
          _resumable = saved;
        }
      }
      _buildDeck(keepResumable: true, save: _resumable == null);
    } catch (e) {
      _error = '加载生词失败：$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  ReviewProgress? _readProgress() {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings).get(_progressKey);
      if (raw is Map) {
        return ReviewProgress.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
    return null;
  }

  void _saveProgress() {
    if (_deck.isEmpty) return;
    try {
      final progress = ReviewProgress(
        deckIds: _deck.map((v) => v.id ?? -1).where((i) => i >= 0).toList(),
        index: _index,
        countMastered: _countMastered,
        countLearning: _countLearning,
        countNew: _countNew,
        filterLevel: _filterLevel,
        filterDays: _filterDays,
        flipped: _flipped,
        updatedAt: DateTime.now(),
      );
      Hive.box(
        AppConstants.hiveBoxSettings,
      ).put(_progressKey, progress.toJson());
    } catch (_) {
      // 进度保存失败不影响复习
    }
  }

  void _clearProgress() {
    try {
      Hive.box(AppConstants.hiveBoxSettings).delete(_progressKey);
    } catch (_) {}
  }

  /// 构建卡组;[resume] true 时尝试续上次进度(否则重新打乱)。
  /// [save] false 时不写进度——首次进页若已有可续进度,必须先让用户
  /// 选择「继续/重新开始」,不能先用新打的乱序覆盖掉旧进度。
  void _buildDeck({
    bool resume = false,
    bool keepResumable = false,
    bool save = true,
  }) {
    final all = context.read<VocabProvider>().vocabularies;
    final items = filterReviewItems(
      all,
      level: _filterLevel,
      days: _filterDays,
    );
    List<Vocabulary> deck;
    int index = 0;
    int mastered = 0, learning = 0, fresh = 0;
    bool flipped = false;

    final saved = resume ? _readProgress() : null;
    if (saved != null && !saved.isEmpty && saved.matchesDeck(items)) {
      final restored = restoreDeck(items, saved);
      deck = restored.deck;
      index = restored.index;
      mastered = saved.countMastered;
      learning = saved.countLearning;
      fresh = saved.countNew;
      flipped = saved.flipped;
    } else {
      items.shuffle(Random());
      deck = items;
    }

    if (!mounted) return;
    setState(() {
      _deck = deck;
      _index = index;
      _countMastered = mastered;
      _countLearning = learning;
      _countNew = fresh;
      _flipped = flipped;
      _finished = false;
      if (!keepResumable) _resumable = null;
    });
    if (save) _saveProgress();
  }

  /// 标记掌握度:写库 + **自动翻面显示释义**(不再直接跳过),看完点「下一张」
  Future<void> _mark(int level) async {
    if (_deck.isEmpty || _index >= _deck.length) return;
    final v = _deck[_index];
    if (v.id != null) _marks[v.id!] = level;
    try {
      await context.read<VocabProvider>().updateMastery(v.id!, level);
    } catch (_) {
      // 记录失败不阻断复习
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
      _flipped = true; // 自动翻面:先看释义再走
    });
    _saveProgress();
  }

  void _next() {
    if (_index + 1 >= _deck.length) {
      setState(() => _finished = true);
      _clearProgress();
      return;
    }
    setState(() {
      _index++;
      _flipped = false;
    });
    _saveProgress();
  }

  void _prev() {
    if (_index == 0) return;
    setState(() {
      _index--;
      _flipped = false;
    });
    _saveProgress();
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
      appBar: AppBar(
        title: const Text('复习模式'),
        actions: [
          if (_deck.isNotEmpty && !_finished)
            IconButton(
              tooltip: '打乱重来',
              icon: const Icon(Icons.shuffle, size: 20),
              onPressed: () {
                _clearProgress();
                _buildDeck();
              },
            ),
        ],
      ),
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
            _filterLevel >= 0 || _filterDays > 0
                ? '该筛选条件下暂无带释义的词汇'
                : '生词本里还没有带释义的词汇',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              setState(() {
                _filterLevel = -1;
                _filterDays = 0;
              });
              _buildDeck();
            },
            child: const Text('查看全部'),
          ),
        ],
      ),
    );
  }

  // ── 主体 ──

  Widget _buildBody(ThemeData theme) {
    return Column(
      children: [
        _buildFilterBar(theme),
        _buildProgressBar(theme),
        if (_resumable != null && !_finished) _buildResumeBanner(theme),
        Expanded(
          child: _finished ? _buildSummary(theme) : _buildCardArea(theme),
        ),
      ],
    );
  }

  /// 筛选栏(v1.7.0:对比度提高 + 日期筛选)
  Widget _buildFilterBar(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(
                  theme,
                  label: '全部',
                  selected: _filterLevel == -1,
                  onTap: () {
                    setState(() => _filterLevel = -1);
                    _buildDeck();
                  },
                ),
                for (final e in const {'新词': 0, '学习中': 1, '已掌握': 2}.entries)
                  _filterChip(
                    theme,
                    label: e.key,
                    selected: _filterLevel == e.value,
                    onTap: () {
                      setState(() => _filterLevel = e.value);
                      _buildDeck();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.event_outlined,
                    size: 16,
                    color: Colors.grey[800],
                  ),
                ),
                for (final f in ReviewDateFilter.options)
                  _filterChip(
                    theme,
                    label: f.label,
                    selected: _filterDays == f.days,
                    onTap: () {
                      setState(() => _filterDays = f.days);
                      _buildDeck();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    ThemeData theme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withAlpha(28)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : Colors.grey[400]!,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? theme.colorScheme.primary : Colors.grey[850],
            ),
          ),
        ),
      ),
    );
  }

  /// 进度条(v1.7.0:深色文字 + 主题色进度)
  Widget _buildProgressBar(ThemeData theme) {
    final total = _deck.length;
    final current = _finished ? total : _index + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                _finished ? '本轮完成' : '第 $current / $total 张',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Text(
                '已掌握 $_countMastered · 学习中 $_countLearning · 新词 $_countNew',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[850],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : current / total,
              minHeight: 7,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 续看提示条
  Widget _buildResumeBanner(ThemeData theme) {
    final p = _resumable!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.primary.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '上次复习到第 ${p.index + 1} 张',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _resumable = null);
              _clearProgress();
              _buildDeck();
            },
            child: const Text('重新开始', style: TextStyle(fontSize: 12)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
            onPressed: () {
              setState(() => _resumable = null);
              _buildDeck(resume: true);
            },
            child: const Text('继续', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ── 卡片区(支持左右滑动翻卡) ──

  Widget _buildCardArea(ThemeData theme) {
    final v = _deck[_index];
    final markedLevel = v.id != null ? _marks[v.id!] : null;
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            // 右滑 = 上一张;左滑 = 翻面/下一张
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > 200) {
                _prev();
              } else if (velocity < -200) {
                _flipped ? _next() : setState(() => _flipped = true);
              }
            },
            onTap: () => setState(() => _flipped = !_flipped),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Card(
                key: ValueKey('${_index}_$_flipped'),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _flipped
                        ? _cardBack(theme, v, markedLevel)
                        : _cardFront(theme, v),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // 前后翻卡
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(
              onPressed: _index == 0 ? null : _prev,
              tooltip: '上一张',
              icon: const Icon(Icons.chevron_left),
            ),
            const SizedBox(width: 10),
            Text(
              '${_index + 1} / ${_deck.length}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 10),
            IconButton.outlined(
              onPressed: _flipped
                  ? _next
                  : () => setState(() => _flipped = true),
              tooltip: '下一张',
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 标记按钮(点完自动翻面显示释义,看完点「下一张」)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: _markButton(
                  label: '不认识',
                  icon: Icons.sentiment_very_dissatisfied,
                  color: Colors.red,
                  level: 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _markButton(
                  label: '模糊',
                  icon: Icons.sentiment_neutral,
                  color: Colors.blue,
                  level: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _markButton(
                  label: '认识',
                  icon: Icons.sentiment_very_satisfied,
                  color: Colors.green,
                  level: 2,
                ),
              ),
            ],
          ),
        ),
        if (_flipped)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: _next,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(_index + 1 >= _deck.length ? '完成本轮' : '下一张'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
              ),
            ),
          ),
      ],
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
            fontWeight: FontWeight.w700,
            color: Colors.grey[600],
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 20),
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
              color: Colors.grey[700],
            ),
          ),
        ],
        const SizedBox(height: 12),
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
          '保存于 ${v.createdLabel}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _cardBack(ThemeData theme, Vocabulary v, int? markedLevel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                v.displayLabel,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (markedLevel != null) _markBadge(markedLevel),
          ],
        ),
        if (v.phonetic != null && v.phonetic!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            v.phonetic!,
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Colors.grey[700],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.translation ?? '', style: theme.textTheme.titleMedium),
                if (v.originalSentence != null &&
                    v.originalSentence!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    v.originalSentence!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[800],
                      height: 1.5,
                    ),
                  ),
                ],
                if (v.grammarNote != null && v.grammarNote!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    v.grammarNote!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '保存于 ${v.createdLabel}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _markBadge(int level) {
    final (String label, Color color) = switch (level) {
      2 => ('已标记：认识', Colors.green),
      1 => ('已标记：模糊', Colors.blue),
      _ => ('已标记：不认识', Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
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
            Text(
              '本轮复习完成！',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '共 $_countMastered 张认识 · $_countLearning 张模糊 · $_countNew 张不认识',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                _clearProgress();
                _buildDeck();
              },
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

  Widget _markButton({
    required String label,
    required IconData icon,
    required Color color,
    required int level,
  }) {
    return GestureDetector(
      onTap: () => _mark(level),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withAlpha(14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(130), width: 1.4),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
