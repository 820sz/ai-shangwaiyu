import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../../config/constants.dart';
import '../../models/vocabulary.dart';
import '../../providers/vocab_provider.dart';
import '../../services/database.dart';
import '../../services/fsrs.dart';
import '../../services/learner_model_store.dart';
import '../../services/review_queue.dart';
import '../../services/tts_service.dart';
import '../../services/tutor_engine.dart' show TutorEngine;
import '../../utils/review_deck.dart';

/// 复习题型(v2.1 扩展):
/// - [recognize] 认词:看词回想释义(原来的卡片方式)
/// - [spell] 拼写:看中文释义拼出英文 —— 检验"能产出"而不只是"能认得"
/// - [dictate] 听写:听发音写单词 —— 音频输入先落到单词层(v2.2 再扩展到句子)
enum ReviewCardMode {
  recognize('认词'),
  spell('拼写'),
  dictate('听写');

  final String label;
  const ReviewCardMode(this.label);
}

/// 复习模式(v1.5.0 初版 / v1.7.0 重做 / **v2.1 接入 FSRS**)。
///
/// v2.1 的变化(这是间隔重复真正开始工作的版本):
/// - **默认进入「今日复习」**:队列由 [ReviewQueue] 从 `word_review` 的 FSRS 状态
///   算出 —— 到期的词按"过期最久 + 记忆最脆弱"排前,再按"复习优先"的配额补新词;
/// - **四档评分**(不认识 / 模糊 / 认识 / 太简单)替代原来的三档标记:
///   每次评分都会更新稳定度、难度与下次到期时间(FSRS-4.5);
/// - 顶部显示预计用时与**未来 7 天负荷**(防止某天突然堆几百个);
/// - 原来的「自由复习」(按掌握度/日期筛选整库浏览)保留,作为补充入口。
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

  // ─── v2.1:FSRS 今日队列 ───

  /// true = 今日复习(FSRS 四档评分);false = 自由复习(原筛选浏览模式)
  bool _fsrsMode = true;
  bool _queueLoading = false;
  ReviewQueuePlan? _plan;

  /// 本次会话的卡片序列(到期 + 配额内新词)
  List<ReviewQueueItem> _queue = [];
  int _qIndex = 0;
  bool _qFlipped = false;

  /// 本次会话的评分统计(评分值 → 次数)
  final Map<int, int> _ratingCounts = {};

  /// 复习题型(v2.1 扩展):认词 / 拼写 / 听写
  ReviewCardMode _cardMode = ReviewCardMode.recognize;

  /// 拼写/听写模式的输入框与提交结果(null = 未提交)
  final _spellCtrl = TextEditingController();
  String? _spellAnswer;

  @override
  void initState() {
    super.initState();
    _load();
    _loadQueue();
  }

  @override
  void dispose() {
    _spellCtrl.dispose();
    super.dispose();
  }

  // ─── v2.1:队列加载与评分 ───

  /// 组装今日队列:生词本 + word_review 卡片 + 每日时间预算
  Future<void> _loadQueue() async {
    setState(() {
      _queueLoading = true;
      _error = null;
    });
    try {
      final vocab = context.read<VocabProvider>().vocabularies;
      final rows = await DatabaseService.getWordReviews();
      final now = DateTime.now();
      final cards = ReviewQueue.cardsFromRows(rows, now: now);
      final model = LearnerModelStore.load();
      final plan = ReviewQueue.build(
        vocab: vocab,
        cards: cards,
        now: now,
        dailyMinutes:
            model.dailyMinutes?.value ?? TutorEngine.defaultDailyMinutes,
        // 配额来自「学习偏好」页(v2.1):默认 20,复习吃满预算时自动降到 0
        maxNewWords: model.maxNewWords?.value ?? 20,
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _queue = [...plan.dueWords, ...plan.newWords];
        _qIndex = 0;
        _qFlipped = false;
        _queueLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _queueLoading = false;
        _error = '读取复习队列失败:$e';
      });
    }
  }

  /// 拼写/听写模式:提交后对比答案(忽略大小写与首尾空白)
  void _checkSpelling() {
    final typed = _spellCtrl.text.trim();
    setState(() {
      _spellAnswer = typed;
      _qFlipped = true; // 提交即翻面:显示正确拼写与释义
    });
  }

  /// 拼写是否正确(提交前为 null)
  bool? get _spellCorrect {
    if (_spellAnswer == null) return null;
    final item = _queue[_qIndex];
    // 判分逻辑在 ReviewGrading(纯函数,可单测):忽略大小写/空白/连字符
    return ReviewGrading.isCorrect(_spellAnswer!, item.vocab.word);
  }

  /// 评分:更新 FSRS 卡片(稳定度/难度/到期)+ 同步旧 mastery 档位
  Future<void> _rate(FsrsRating rating) async {
    if (_qIndex >= _queue.length) return;
    final item = _queue[_qIndex];
    final id = item.vocab.id;
    final now = DateTime.now();
    final next = ReviewQueue.applyRating(item.card, rating, now: now);

    setState(() {
      _ratingCounts[rating.value] = (_ratingCounts[rating.value] ?? 0) + 1;
      // 本地也更新卡片,便于同一会话里回看/重复评分
      _queue[_qIndex] = ReviewQueueItem(
        vocab: item.vocab,
        card: next,
        isNew: false,
      );
      _qFlipped = false;
      // 清掉拼写/听写的作答状态,否则下一张卡会带着上一张的答案
      _spellAnswer = null;
      _spellCtrl.clear();
      _qIndex++;
    });

    if (id == null) return;
    // 提前取好 Provider 与 Messenger:await 之后再用 context 会被 analyzer 判为
    // "跨异步间隙使用 BuildContext"(而且页面被 pop 时确实会炸)
    final vocabProvider = context.read<VocabProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DatabaseService.upsertWordReview(
        id,
        stability: next.stability,
        difficulty: next.difficulty,
        dueAt: next.due,
        lastReviewAt: now,
        lastRating: rating.value,
        lapse: rating == FsrsRating.again,
      );
      // 旧的三档 mastery 仍被统计页/词库页使用,保持一致(避免两套数据打架)
      final mastery = ReviewQueue.isLongTermKnown(next)
          ? 2
          : (rating == FsrsRating.again ? 0 : 1);
      await vocabProvider.updateMastery(id, mastery);
      // "不认识"记进错误档案:复习漏掉的词就是最真实的薄弱点
      if (rating == FsrsRating.again) {
        await DatabaseService.bumpErrorTag(
          source: 'review',
          tag: '词汇',
          evidence: item.vocab.word,
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('复习结果保存失败:$e')),
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 提前取 Provider:await 之后再用 context 会被判为跨异步间隙使用
      final provider = context.read<VocabProvider>();
      await provider.loadVocabularies();
      final all = provider.vocabularies;
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
        // v1.9.0(P1-5):已标记表与断点词 id 一起存 —— 续看后
        // 卡片标记不丢、也不会重复计数
        marks: Map<int, int>.from(_marks),
        lastId: _deck.isEmpty
            ? null
            : (_index < _deck.length ? _deck[_index].id : _deck.last.id),
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
    Map<int, int> restoredMarks = {};

    final saved = resume ? _readProgress() : null;
    if (saved != null && !saved.isEmpty && saved.matchesDeck(items)) {
      final restored = restoreDeck(items, saved);
      deck = restored.deck;
      index = restored.index;
      mastered = saved.countMastered;
      learning = saved.countLearning;
      fresh = saved.countNew;
      flipped = saved.flipped;
      restoredMarks = Map<int, int>.from(saved.marks); // v1.9.0(P1-5)
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
      _marks
        ..clear()
        ..addAll(restoredMarks);
      if (!keepResumable) _resumable = null;
    });
    if (save) _saveProgress();
  }

  /// 标记掌握度(v1.8.0 按用户反馈重做):
  /// - 「认识」:记完**直接进下一张**(不需要再翻面看释义)
  /// - 「不认识 / 模糊」:翻面显示释义,看完点「下一张」
  /// - 同一张卡重复点同一档位不再计次(修复"一个词反复点认识刷进度"的 bug);
  ///   回看时改标记会先撤销旧档位计数再计新档位 —— 统计始终等于已标记卡片数
  Future<void> _mark(int level) async {
    if (_deck.isEmpty || _index >= _deck.length) return;
    final v = _deck[_index];
    final id = v.id;
    if (id == null) return;
    final previous = _marks[id];
    if (previous == level) return; // 重复点同一档位:忽略
    try {
      await context.read<VocabProvider>().updateMastery(id, level);
    } catch (_) {
      // 记录失败不阻断复习
    }
    if (!mounted) return;
    _marks[id] = level;
    setState(() {
      if (previous != null) _applyCount(previous, -1);
      _applyCount(level, 1);
      _flipped = level != 2; // 认识不翻面;不认识/模糊先看释义
    });
    _saveProgress();
    if (level == 2) _next();
  }

  /// 统计加减(带回夹:计数不会变成负数)
  void _applyCount(int level, int delta) {
    switch (level) {
      case 2:
        _countMastered = (_countMastered + delta).clamp(0, 1 << 30);
      case 1:
        _countLearning = (_countLearning + delta).clamp(0, 1 << 30);
      default:
        _countNew = (_countNew + delta).clamp(0, 1 << 30);
    }
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
    // v2.0:按设置的音色朗读(英/美/跟随系统)
    final ok = await TtsService.instance.speakPreferred(v.displayWordText);
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
        title: Text(_fsrsMode ? '今日复习' : '自由复习'),
        actions: [
          if (!_fsrsMode && _deck.isNotEmpty && !_finished)
            IconButton(
              tooltip: '打乱重来',
              icon: const Icon(Icons.shuffle, size: 20),
              onPressed: () {
                _clearProgress();
                _buildDeck();
              },
            ),
          if (_fsrsMode)
            IconButton(
              tooltip: '重新计算队列',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _loadQueue,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildModeBar(theme),
          Expanded(
            child: _fsrsMode ? _buildQueueBody(theme) : _buildFreeBody(theme),
          ),
        ],
      ),
    );
  }

  /// 模式切换(v2.1):今日复习(FSRS)/ 自由复习(原筛选浏览)
  Widget _buildModeBar(ThemeData theme) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('今日复习')),
              ButtonSegment(value: false, label: Text('自由复习')),
            ],
            selected: {_fsrsMode},
            onSelectionChanged: (s) {
              setState(() => _fsrsMode = s.first);
              if (s.first) _loadQueue();
            },
            showSelectedIcon: false,
          ),
          const Spacer(),
          if (_fsrsMode && _plan != null)
            Text(
              '预计 ${_plan!.estimatedMinutes} 分钟',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }

  // ── 今日复习(FSRS) ──

  Widget _buildQueueBody(ThemeData theme) {
    if (_queueLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final plan = _plan;
    if (plan == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('队列还没算出来'),
            const SizedBox(height: 8),
            FilledButton(onPressed: _loadQueue, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_queue.isEmpty) return _buildQueueEmpty(theme, plan);
    if (_qIndex >= _queue.length) return _buildQueueSummary(theme, plan);
    return _buildQueueCard(theme, plan);
  }

  Widget _buildQueueEmpty(ThemeData theme, ReviewQueuePlan plan) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final forecast = plan.forecast.map((e) => '$e').join(' / ');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('今天没有到期的词', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              plan.buckets.total > 0
                  ? '后面还有 ${plan.buckets.total} 个在排队(未来 7 天:$forecast)'
                  : '复习队列是空的 —— 去材料里收几个新词,或做一次自由复习',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => setState(() => _fsrsMode = false),
              child: const Text('去自由复习'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueCard(ThemeData theme, ReviewQueuePlan plan) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final item = _queue[_qIndex];
    final v = item.vocab;
    final total = _queue.length;
    final progress = _qIndex / total;
    final isTyping =
        _cardMode == ReviewCardMode.spell || _cardMode == ReviewCardMode.dictate;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              LinearProgressIndicator(value: progress, minHeight: 6),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${_qIndex + 1} / $total',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: muted, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  // 题型切换:同一批词换一种问法(拼写/听写检验"能产出")
                  for (final m in ReviewCardMode.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: ChoiceChip(
                        label: Text(m.label, style: const TextStyle(fontSize: 11)),
                        selected: _cardMode == m,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() {
                          _cardMode = m;
                          _spellCtrl.clear();
                          _spellAnswer = null;
                          _qFlipped = false;
                        }),
                      ),
                    ),
                  const Spacer(),
                  if (item.isNew)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('新词',
                          style: TextStyle(
                              fontSize: 10, color: theme.colorScheme.primary)),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: isTyping
                      ? _buildTypingCard(theme, v)
                      : GestureDetector(
                          onTap: () => setState(() => _qFlipped = !_qFlipped),
                          child: _qFlipped
                              ? _cardBack(theme, v, null)
                              : _cardFront(theme, v),
                        ),
                ),
              ),
            ),
          ),
        ),
        // ── 底部操作区:按题型给不同动作 ──
        if (isTyping && _spellAnswer == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _spellCtrl.text.trim().isEmpty ? null : _checkSpelling,
                child: const Text('检查'),
              ),
            ),
          )
        else if (!isTyping && !_qFlipped)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Text('先自己回忆,再看答案',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => setState(() => _qFlipped = true),
                    child: const Text('显示答案'),
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Text(
                  _spellAnswer == null
                      ? '刚才想起来的难度?'
                      : (_spellCorrect == true ? '拼对了 —— 给自己定个档' : '拼错了 —— 建议选「不认识」'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _spellAnswer == null
                        ? muted
                        : (_spellCorrect == true ? Colors.green : Colors.red),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _ratingButton(
                        label: '不认识',
                        color: Colors.red,
                        rating: FsrsRating.again,
                        emphasized: _spellCorrect == false,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ratingButton(
                        label: '模糊',
                        color: Colors.orange,
                        rating: FsrsRating.hard,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ratingButton(
                        label: '认识',
                        color: Colors.blue,
                        rating: FsrsRating.good,
                        emphasized: _spellCorrect == true,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ratingButton(
                        label: '太简单',
                        color: Colors.green,
                        rating: FsrsRating.easy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 拼写/听写模式的卡面:给提示 + 输入框(听写自动朗读一次)
  Widget _buildTypingCard(ThemeData theme, Vocabulary v) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final isDictate = _cardMode == ReviewCardMode.dictate;
    if (isDictate) {
      // 听写进入时念一遍(用户可点喇叭重听)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) TtsService.instance.speakPreferred(v.displayWordText);
      });
    }
    if (_spellAnswer != null) {
      // 已提交 → 直接展示答案卡(正确/错误对比)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_spellCorrect == true ? Icons.check_circle : Icons.cancel,
                  color: _spellCorrect == true ? Colors.green : Colors.red),
              const SizedBox(width: 6),
              Text(
                _spellCorrect == true ? '拼写正确' : '拼写错误',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('你的答案:${_spellAnswer!.isEmpty ? '(空)' : _spellAnswer}',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(v.word,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _cardBack(theme, v, null),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isDictate) ...[
          Text('听发音,写出这个单词', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 12),
          Center(
            child: IconButton.filledTonal(
              tooltip: '再听一遍',
              onPressed: () => TtsService.instance.speakPreferred(v.displayWordText),
              icon: const Icon(Icons.volume_up),
              iconSize: 32,
            ),
          ),
        ] else ...[
          Text('看中文,拼出英文单词',
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 12),
          Text(
            (v.translation ?? '').trim().isEmpty
                ? '(这个词没有中文释义,可以直接跳过)'
                : v.translation!,
            style: theme.textTheme.titleLarge,
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _spellCtrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: '输入英文',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_spellCtrl.text.trim().isNotEmpty) _checkSpelling();
          },
        ),
      ],
    );
  }

  Widget _ratingButton({
    required String label,
    required Color color,
    required FsrsRating rating,
    bool emphasized = false,
  }) {
    return OutlinedButton(
      onPressed: () => _rate(rating),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(emphasized ? 255 : 120)),
        backgroundColor: emphasized ? color.withAlpha(20) : null,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  /// 今日队列完成:小结 + 未来负荷 + 下一步
  Widget _buildQueueSummary(ThemeData theme, ReviewQueuePlan plan) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final again = _ratingCounts[FsrsRating.again.value] ?? 0;
    final hard = _ratingCounts[FsrsRating.hard.value] ?? 0;
    final good = _ratingCounts[FsrsRating.good.value] ?? 0;
    final easy = _ratingCounts[FsrsRating.easy.value] ?? 0;
    final learned = _queue.length;
    final forecast = plan.forecast.map((e) => '$e').join(' / ');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.task_alt, size: 44, color: theme.colorScheme.primary),
                const SizedBox(height: 10),
                Text('今天的复习做完了', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('本轮 $learned 个词:认识 $good · 太简单 $easy · '
                    '模糊 $hard · 不认识 $again',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 10),
                if (again > 0)
                  Text('$again 个"不认识"已经回到队列(更早再见),并记进错误档案。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('未来 7 天负荷(每天要复习的词数)',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(forecast,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(
                  _loadAdvice(plan),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loadQueue,
                child: const Text('清下一批'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 负荷建议:某天明显堆积就提醒"别加新词"
  String _loadAdvice(ReviewQueuePlan plan) {
    final peak = plan.forecast.isEmpty
        ? 0
        : plan.forecast.reduce((a, b) => a > b ? a : b);
    if (peak == 0) return '后面几天都很轻松 —— 可以多收点新词。';
    if (peak > 60) {
      return '某天会到 $peak 个 —— 这两天别再堆新词了,先还账。';
    }
    if (peak > 30) return '峰值 $peak 个/天 —— 节奏正常,新词按配额加就行。';
    return '峰值 $peak 个/天 —— 很轻松。';
  }

  /// 自由复习(原有逻辑):筛选 + 整库浏览
  Widget _buildFreeBody(ThemeData theme) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text(_error!))
        : _deck.isEmpty
        ? _buildEmpty(theme)
        : _buildBody(theme);
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.style_outlined,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            _filterLevel >= 0 || _filterDays > 0
                ? '该筛选条件下暂无带释义的词汇'
                : '生词本里还没有带释义的词汇',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
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
                    color: theme.colorScheme.onSurface,
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
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface,
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '认识/已掌握 $_countMastered · 模糊/学习中 $_countLearning · 不认识/新词 $_countNew',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface,
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
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
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
              // A1(v1.9.0):翻面与换卡给不同方向语意 —— 纯淡入淡出时用户
              // 分不清"我翻面了"还是"换词了";系统开"移除动画"时直接瞬时切换
              duration: Duration(
                milliseconds: MediaQuery.of(context).disableAnimations
                    ? 0
                    : (_flipped ? 180 : 240),
              ),
              transitionBuilder: (child, anim) {
                final incoming = child.key == ValueKey('${_index}_$_flipped');
                final slide = _flipped
                    ? const Offset(0, 0.04)
                    : Offset(incoming ? 0.12 : -0.12, 0);
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: slide,
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                );
              },
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
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
                  statusLabel: '新词',
                  icon: Icons.sentiment_very_dissatisfied,
                  color: Colors.red,
                  level: 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _markButton(
                  label: '模糊',
                  statusLabel: '学习中',
                  icon: Icons.sentiment_neutral,
                  color: Colors.blue,
                  level: 1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _markButton(
                  label: '认识',
                  statusLabel: '已掌握',
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
            color: theme.colorScheme.onSurfaceVariant,
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
        if (v.displayPhonetic != null) ...[
          const SizedBox(height: 10),
          Text(
            v.displayPhonetic!,
            style: TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
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
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
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
        if (v.displayPhonetic != null) ...[
          const SizedBox(height: 4),
          Text(
            v.displayPhonetic!,
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
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
                      color: theme.colorScheme.onSurface,
                      height: 1.5,
                    ),
                  ),
                ],
                if (v.grammarNote != null && v.grammarNote!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    v.grammarNote!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '保存于 ${v.createdLabel}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
      2 => ('已标记：认识 · 已掌握', Colors.green),
      1 => ('已标记：模糊 · 学习中', Colors.blue),
      _ => ('已标记：不认识 · 新词', Colors.red),
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
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
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
    required String statusLabel,
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
            // P2-29:动作词 + 结果状态词一起显示 —— 用户标完「不认识」回词库
            // 看到的是「新词」,这里先把对应关系讲清楚
            Text(
              statusLabel,
              style: TextStyle(fontSize: 10, color: color.withAlpha(200)),
            ),
          ],
        ),
      ),
    );
  }
}
