import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../models/learner_model.dart';
import '../../services/drill_catalog.dart';
import '../../services/drill_planner.dart';
import '../../services/database.dart';
import '../../services/learner_model_store.dart';
import '../../services/output_composer.dart';
import '../../services/output_draft.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/v4/v4_kit.dart';
import '../../widgets/waiting.dart';
import '../review/review_screen.dart';
import '../writing/write_review_screen.dart';
import '../writing/writing_logs_screen.dart';
import 'drill_plan_screen.dart';
// DrillMode 枚举定义在 drill_screen.dart;四阶卡片的进度摘要按模式取
import 'drill_screen.dart' show DrillMode;
import 'practice_history_screen.dart';
import 'practice_flow_screen.dart';
import 'practice_setup_screen.dart';
import 'widgets/output_tier_card.dart';
import 'widgets/paper_kit.dart';

/// 输出页(v3 · 批 3 重做)。
///
/// 用户 2026-11-01 的批注(两条,决定了这一页的结构):
/// 1. > "输出练习,主要是在语音、词汇、语法三要素的基础上,去开发听说读写中
///      '写'的练习,因为'说'当前模型不支持"
/// 2. > "四阶写作阶梯这个不错,不过不要搞成'只有写词过了才写句'这种死人逻辑,
///      而是并行逻辑,因为每个人的需求基础想法不一样。"
///
/// 所以这一页是**四阶并行的工作台**,不是"线性闯关":
/// - 写词(词汇+语音):认词/拼写/听写 —— 入口接现有复习内核(FSRS);
/// - 写句(词汇+语法):中译英回译 —— 入口接现有翻译练习;
/// - 写段(语法+篇章):摘要/续写/观点段 —— 题源(从读过的材料出题)正在做,
///   卡片明确标"开发中",不装作能用;
/// - 写篇(篇章+语用):写译批改 + 写译记录(按目标考试要求批改)。
///
/// 四张卡**平级并列**,没有先后锁;从哪一阶开始由用户自己决定。
class OutputHomeScreen extends StatefulWidget {
  const OutputHomeScreen({super.key});

  @override
  State<OutputHomeScreen> createState() => _OutputHomeScreenState();
}

class _OutputHomeScreenState extends State<OutputHomeScreen> {
  LearnerModel _model = LearnerModel();

  /// 与「输入」页同款的日期眉标
  String _dateLine() {
    final now = DateTime.now();
    const week = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${now.month} 月 ${now.day} 日 · ${week[now.weekday - 1]}';
  }

  /// 两个练习模式各自的进度摘要(卡片上要显示真实进度)
  final Map<DrillMode, DrillSummary> _summaries = {};
  bool _loading = true;

  /// 今日建议用的真实数据:到期复习词数 + 最近 7 天写译篇数。
  /// 只读现有表(不新增查询口径),拿不到就当 0 —— 建议卡随之隐藏该行,不编数字。
  int _dueWords = 0;
  int _writes7d = 0;

  /// 上次没做完的练习(首页「继续上次练习」;没有就 null,不占位)
  ResumablePractice? _resumable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    final model = LearnerModelStore.load();
    if (mounted) setState(() => _model = model);
    for (final mode in DrillMode.values) {
      final summary = await loadDrillSummary(mode);
      if (!mounted) return;
      setState(() => _summaries[mode] = summary);
    }
    var due = 0;
    try {
      due = await DatabaseService.getDueReviewCount();
    } catch (_) {
      // 复习队列读失败不影响输出页打开
    }
    var writes = 0;
    try {
      final logs = await DatabaseService.getWritingLogs(limit: 50);
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      writes = logs.where((l) => l.createdAt.isAfter(cutoff)).length;
    } catch (_) {
      // 写译记录读失败同理:建议卡少一行,页面照常
    }
    if (!mounted) return;
    setState(() {
      _dueWords = due;
      _writes7d = writes;
      _loading = false;
    });
    // 「继续上次练习」:草稿存在且题组还能从库里还原才显示(失败静默隐藏)
    try {
      final resumable = await loadResumablePractice();
      if (mounted) setState(() => _resumable = resumable);
    } catch (_) {
      // 草稿读取失败不影响输出首页其它内容
    }
  }

  /// 继续上次没做完的练习:题组已落库,直接带 set 进练习器(不重新搜索/生成)
  Future<void> _continuePractice(ResumablePractice resumable) async {
    await appPush(
      context,
      (_) => PracticeFlowScreen(
        set: resumable.set,
        savedSetId: resumable.draft.setId,
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openPlan({DrillMode? mode}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrillPlanScreen(initialMode: mode ?? DrillMode.spelling),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  /// 练习中心入口(v3 批 8, D1-14):旧版 drill 链路降为"旧版计划",
  /// 四阶练习是默认推荐 —— 老链路数据不删,但主入口不再把它当唯一选择。
  Future<void> _openPracticeCenter() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
                child: Text(
                  '练习中心',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              // P3:入口弹层也走纸面件(旧 ListTile 在纸面里像"另一个 App")
              PaperRow(
                leading: Icon(
                  Icons.grid_view_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: '四阶练习（推荐）',
                meta: '写词 / 写句 / 写段 / 写篇，可从材料和目标出题，按 rubric 批改',
                onTap: () => Navigator.pop(ctx, 'tier'),
              ),
              const SizedBox(height: Gap.xs),
              PaperRow(
                leading: Icon(
                  Icons.event_note_outlined,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                title: '旧版练习计划',
                meta: '按水平排练习计划（保留历史进度，不再新增题型）',
                onTap: () => Navigator.pop(ctx, 'legacy'),
              ),
              const SizedBox(height: Gap.xs),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice == 'tier') {
      await _openPractice(OutputTier.word);
    } else {
      await _openPlan();
    }
  }

  /// 进四阶练习器(写词/写句/写段/写篇):先选"从哪出题",再逐题写 + 按 rubric 批改。
  ///
  /// 用 [AppPageRoute] 的淡入+上滑转场(批 6):输出是"选来源 → 做题 → 看结果"
  /// 的钻取流,统一转场比默认右滑更像"展开一层"。
  Future<void> _openPractice(OutputTier tier) async {
    await appPush(context, (_) => PracticeSetupScreen(tier: tier));
    if (mounted) _load();
  }

  Future<void> _openReview() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReviewScreen()),
    );
    if (mounted) _load();
  }

  /// 口语交流:说明白"在做什么、为什么还不能用"
  void _explainSpeaking() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final muted = theme.colorScheme.onSurfaceVariant;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mic_none,
                        size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: Gap.xs),
                    Text(
                      '口语交流还没开放',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  '这件事做不好不如不做 —— 它至少要接三样东西:',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: Gap.xs),
                for (final line in const [
                  '实时语音(你说一句、它接一句,延迟要低到不打断思路)',
                  '发音评分(音素级:哪个音不准、重音在哪,不能只给个总分)',
                  '按目标出话题(四六级口试 / 雅思 Part 2 / 日常寒暄,题库不同)',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: Gap.xs),
                        Expanded(
                          child: Text(
                            line,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: Gap.xs),
                Text(
                  '在那之前:写出来的东西,才是说出来的地基 —— '
                  '说不出来,多半是先写不出来。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 练习进度摘要(真实数据;没有计划就报已练题数/正确率)。
  String? _progressOf(DrillMode mode) {
    final summary = _summaries[mode] ?? DrillSummary.empty;
    if (!summary.stats.hasData) return null;
    final stats = summary.stats;
    final parts = <String>['已练 ${stats.total} 题'];
    if (stats.total > 0) {
      parts.add('正确率 ${(stats.accuracy * 100).round()}%');
    }
    if (summary.hasPlan) parts.add(summary.progress.summary);
    return parts.join(' · ');
  }

  /// 头图光斑(低透明度径向渐变;只让底子透气,不压文字)
  Widget _heroBlob(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0.0)],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // 入口屏:头图用果冻皮肤(B),正文用纸面主题(A)——两套皮肤各管一段
    final theme = paperThemeOf(context);
    final skin = V4Skin.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final goals = DrillCatalog.normalizeAll([
      ..._model.goals,
      if ((_model.goal?.value ?? '').isNotEmpty) _model.goal!.value,
    ]);
    final level = DrillPlanner.levelOf(_model);

    return Scaffold(
      body: PaperSkin(
        child: SafeArea(
        bottom: false,
        child: ListView(
          padding: Insets.page,
          children: [
            // ① 头图(入口借 B「果冻头图」):渐变 + 两团光斑 + 白胶囊 CTA。
            // 内页(设置/答题/批改/题库)走纸面 A,只有入口保留色彩与光。
            ClipRRect(
              borderRadius: BorderRadius.circular(skin.heroRadius),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: -70,
                    top: -90,
                    child: _heroBlob(skin.accent.withValues(alpha: 0.26), 210),
                  ),
                  Positioned(
                    right: -50,
                    top: -60,
                    child:
                        _heroBlob(skin.accentAlt.withValues(alpha: 0.24), 190),
                  ),
                  Container(
              decoration: BoxDecoration(gradient: skin.heroFill),
              padding:
                  const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dateLine(),
                          style: AppFont.tagStyle.copyWith(
                            color: skin.inkSoft,
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: Gap.xs),
                        Text(
                          '输出',
                          style: AppFont.displayStyle.copyWith(
                            color: skin.ink,
                            fontSize: 34,
                            height: 1.1,
                            letterSpacing: -1.2,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '写词 → 写句 → 写段 → 写篇 · 四阶并行',
                          style: AppFont.bodyStyle.copyWith(
                            color: skin.inkSoft,
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                  V4PillButton(
                    label: '练习中心',
                    light: true,
                    icon: Icons.tune,
                    onTap: _openPracticeCenter,
                  ),
                ],
              ),
                  ),
                ],
              ),
            ),

            // ② 方向卡:目标 + 水平(点开进练习中心改;四阶共用同一个方向)
            AppStagger(
              index: 0,
              child: AppCard(
                onTap: () => _openPlan(),
                color: theme.colorScheme.primary.withAlpha(12),
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.flag_outlined,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: Gap.xs),
                        Expanded(
                          child: Text(
                            goals.isEmpty ? '还没选目标' : '目标:${goals.join(' + ')}',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${level.label}档',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right,
                            size: 18, color: theme.colorScheme.outline),
                      ],
                    ),
                    const SizedBox(height: Gap.xs),
                    Text(
                      goals.isEmpty
                          ? '选目标(可多选)后,四阶题目都会按它挑词长、句长与评分标准'
                          : DrillCatalog.resolve(goals)
                              .map((g) => g.what)
                              .take(2)
                              .join(';'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: muted,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: Gap.sm),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        _infoPill(theme, Icons.speed, '水平:${level.label}'),
                        if (_model.hasVocabBaseline)
                          _infoPill(
                            theme,
                            Icons.bar_chart,
                            '词汇量 ${_model.vocabEstimate!.value}',
                          )
                        else
                          _infoPill(theme, Icons.help_outline, '还没测词汇量'),
                        if ((_model.dailyMinutes?.value ?? 0) > 0)
                          _infoPill(
                            theme,
                            Icons.schedule,
                            '每天 ${_model.dailyMinutes!.value} 分钟',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),

            // ②.2 继续上次练习(2026-11-07 真机反馈第 6 条第 4 点):
            // 题组在出题时**已经落库**,这里只把"停在第几题 + 未提交草稿"接回来,
            // 点进去不重新搜索/不重新生成。
            if (_resumable != null) ...<Widget>[
              PaperRow(
                leading: Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                title: '继续上次练习',
                meta:
                    '${_resumable!.set.title} · ${_resumable!.progressLabel} · ${_resumable!.answeredLabel}',
                onTap: () => _continuePractice(_resumable!),
              ),
              const SizedBox(height: Gap.sm),
            ],

            // ②.5 今日建议:只用真实数据(到期复习词数 / 近 7 天写译篇数)
            //
            // 不再套 AppStagger:它的入场延迟在首帧/截图里会留下"看不见但占位"
            // 的空带(QA P3);这张卡是信息卡,直接常显更稳。
            if (!_loading) _buildTodayAdvice(theme),
            const SizedBox(height: Gap.md),

            // ③ 四阶台阶(并行,不锁顺序)
            const PaperSectionHead(index: '01', title: '四阶'),
            if (_loading)
              const AppCard(
                child: SkeletonLines(lines: 3, withTitle: true, seed: 3),
              )
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Gap.xs,
                crossAxisSpacing: Gap.xs,
                childAspectRatio: 1.02,
                children: [
                  OutputTierCard(
                    tier: outputTierCatalog[0].tier,
                    indexLabel: '01',
                    title: outputTierCatalog[0].title,
                    subtitle: outputTierCatalog[0].subtitle,
                    progress: _progressOf(DrillMode.spelling),
                    // v3 增强:写词不再只有"复习生词本"一条路 —— 进设置页还能
                    // 按目标练内置考纲/外刊高频词(不依赖输入闭环)。
                    onTap: () => _openPractice(OutputTier.word),
                  ),
                  OutputTierCard(
                    tier: outputTierCatalog[1].tier,
                    indexLabel: '02',
                    title: outputTierCatalog[1].title,
                    subtitle: outputTierCatalog[1].subtitle,
                    progress: _progressOf(DrillMode.translation),
                    onTap: () => _openPractice(OutputTier.sentence),
                  ),
                  OutputTierCard(
                    tier: outputTierCatalog[2].tier,
                    indexLabel: '03',
                    title: outputTierCatalog[2].title,
                    subtitle: outputTierCatalog[2].subtitle,
                    onTap: () => _openPractice(OutputTier.paragraph),
                  ),
                  OutputTierCard(
                    tier: outputTierCatalog[3].tier,
                    indexLabel: '04',
                    title: outputTierCatalog[3].title,
                    subtitle: outputTierCatalog[3].subtitle,
                    onTap: () => _openPractice(OutputTier.essay),
                  ),
                ],
              ),
            const SizedBox(height: Gap.xs),
            // 写词/写句的补充入口:拼写与回译的"练习计划"仍在练习中心
            Wrap(
              spacing: Gap.xs,
              children: [
                TextButton(
                  onPressed: () => _openPlan(mode: DrillMode.spelling),
                  child: const Text('写词 · 拼写练习计划'),
                ),
                TextButton(
                  onPressed: () => _openPlan(mode: DrillMode.translation),
                  child: const Text('写句 · 回译练习计划'),
                ),
                // v3 批 8(D1-8):题库浏览 —— 历史题组可原样重练,不再"做完就走"
                TextButton(
                  onPressed: () => appPush(
                    context,
                    (_) => const PracticeHistoryScreen(),
                  ),
                  child: const Text('题库'),
                ),
              ],
            ),

            // ④ 写篇:批改与复盘(现有能力,真实入口)
            const PaperSectionHead(index: '02', title: '写篇 · 批改与复盘'),
            AppStagger(
              index: 4,
              child: AppActionTile(
                icon: Icons.edit_note,
                title: '写译批改',
                subtitle: '手写 / 电子稿 → 按你的目标考试评分（rubric 维度分）',
                highlight: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WriteReviewScreen()),
                ),
              ),
            ),
            AppStagger(
              index: 5,
              child: AppActionTile(
                icon: Icons.workspace_premium_outlined,
                title: '按目标考试真题练',
                subtitle: '抓公开真题页面出题（写作 / 翻译），每题标注来源',
                onTap: () => _openPractice(OutputTier.essay),
              ),
            ),
            AppStagger(
              index: 6,
              child: AppActionTile(
                icon: Icons.history_edu_outlined,
                title: '写译记录',
                subtitle: '按日期查阅与复盘',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WritingLogsScreen()),
                ),
              ),
            ),

            // ⑤ 口语:先挂着,但说清规划(不装能用)
            const SizedBox(height: Gap.xs),
            AppStagger(
              index: 6,
              child: Opacity(
                opacity: 0.75,
                child: AppActionTile(
                  icon: Icons.mic_none,
                  title: '口语交流(敬请期待)',
                  subtitle: '要接实时语音 + 音素级发音评分 + 按目标出话题,做不好不上',
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(Radii.control - 4),
                    ),
                    child: Text('开发中',
                        style: TextStyle(fontSize: 10, color: muted)),
                  ),
                  onTap: _explainSpeaking,
                ),
              ),
            ),
            const SizedBox(height: Gap.lg),
          ],
        ),
        ),
      ),
    );
  }

  /// 今日建议(v3 批 3):两条真实数据 → 两条建议。
  ///
  /// 为什么不做 AI 生成的"鸡汤式建议":项目纪律是**每条结论必须带数据**;
  /// 到期词数、近 7 天写译篇数都是软件里已有的真实数字,直接拿来用。
  Widget _buildTodayAdvice(ThemeData theme) {
    final cs = theme.colorScheme;
    final rows = <Widget>[];
    if (_dueWords > 0) {
      rows.add(_adviceRow(
        theme,
        Icons.sync,
        '有 $_dueWords 个词到期，先用「写词」把它们写一遍',
        '去写词',
        _openReview,
      ));
    } else {
      rows.add(_adviceRow(
        theme,
        Icons.check_circle_outline,
        '今天没有到期的复习词',
        null,
        null,
      ));
    }
    if (_writes7d == 0) {
      rows.add(_adviceRow(
        theme,
        Icons.edit_note,
        '最近 7 天没有写译练习，写一篇 120 词的短文最有效',
        '去写篇',
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WriteReviewScreen()),
        ),
      ));
    } else {
      rows.add(_adviceRow(
        theme,
        Icons.trending_up,
        '近 7 天写了 $_writes7d 篇，保持输出节奏',
        null,
        null,
      ));
    }
    return AppCard(
      variant: AppCardVariant.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                '今日建议',
                style: AppFont.subheadStyle.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _adviceRow(
    ThemeData theme,
    IconData icon,
    String text,
    String? actionLabel,
    VoidCallback? onTap,
  ) {
    final cs = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppFont.tagStyle.copyWith(
              color: cs.onSurface,
              height: 1.35,
            ),
          ),
        ),
        if (actionLabel != null && onTap != null)
          TextButton(
            onPressed: onTap,
            child: Text(actionLabel, style: const TextStyle(fontSize: 11)),
          ),
      ],
    );
  }

  Widget _infoPill(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(160),
        borderRadius: BorderRadius.circular(Radii.control - 3),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
