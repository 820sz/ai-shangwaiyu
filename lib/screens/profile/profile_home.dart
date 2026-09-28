import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/stats_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../providers/bookmark_provider.dart';
import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/learner_model.dart';
import '../../services/api_endpoint.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../services/learner_context.dart';
import '../../services/learner_model_store.dart';
import '../../services/material_source.dart';
import '../../services/material_source_status.dart';
import '../../services/widget_service.dart';
import '../../utils/crash_logger.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/stats_chart.dart';
import '../../widgets/update_dialog.dart';
import '../../services/update_service.dart';
import 'vocab_list.dart';
import 'stats_page.dart';
import 'api_settings.dart';
import 'appearance_screen.dart';
import 'bookmarks_screen.dart';
import 'backup_screen.dart';
import 'error_archive_screen.dart';
import 'widget_settings_screen.dart';
import 'weekly_report_screen.dart';
import '../review/review_screen.dart';
import '../input/learner_preferences_screen.dart';
import '../tutor/placement_test_screen.dart';

class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({super.key});

  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  /// 学习者模型(v2.0):词汇量基线卡片的数据来源。
  /// Hive 同步读,不阻塞首帧;测试页返回后再刷一次。
  LearnerModel _learnerModel = LearnerModel();

  /// 待处理的错误类数(v2.1 错误档案入口的副标题)。
  /// 为什么要显示:错误档案是一个"平时没人点"的页面,副标题报出积压量
  /// 才有被点开的理由 —— 只写"写译与测验的错题"等于没有入口。
  int _activeErrorKinds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // P2-10:进页立刻返回时 element 已 deactivate,
      // 不加这道判断会抛错并被 CrashLogger 记成"崩溃",污染诊断日志
      if (!mounted) return;
      _loadAll();
    });
  }

  Future<void> _loadAll() async {
    // 学习者模型先读(Hive 同步,页面一渲染就能显示基线)
    _learnerModel = LearnerModelStore.load();
    // 错误类数:失败不影响主流程(读不到就退回中性副标题)
    final errors = await DatabaseService.getErrorTags(status: 'active');
    if (!mounted) return;
    setState(() => _activeErrorKinds = errors.length);
    await Future.wait([
      context.read<StatsProvider>().loadStats(),
      context.read<VocabProvider>().loadVocabularies(),
      context.read<BookmarkProvider>().load(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = context.watch<StatsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: Insets.page,
          children: [
            // ── 数据就在手边:三个关键数字 ──
            _buildStatsRow(theme, stats),
            const SizedBox(height: Gap.md),

            // ── 词汇量基线(v2.0;v2.6 收成一行入口)──
            // 用户实测:"词汇量测试占据这么大个 UI,把它合并进「学习」里的一项就行"。
            // 于是从"占半屏的大卡片 + 两个按钮"改成**学习组里的一行**:
            // 副标题直接报当前基线(不点也能看到),点开才让你选速测/完整版。
            const AppSectionTitle(title: '学习'),
            AppStagger(
              index: 1,
              child: Column(
                children: [
                  _buildBaselineTile(),
                  AppActionTile(
                    icon: Icons.book,
                    title: '我的生词本',
                    subtitle: '按书籍分组',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const VocabListScreen()),
                    ),
                  ),
                  AppActionTile(
                    icon: Icons.style,
                    title: '复习模式',
                    subtitle: '抽认卡记忆',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReviewScreen()),
                    ),
                  ),
                  AppActionTile(
                    icon: Icons.star_outline,
                    title: '收藏夹',
                    subtitle: '收藏的洞见与好句',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BookmarksScreen()),
                    ),
                  ),
                ],
              ),
            ),

            // ── 数据与回顾 ──
            const AppSectionTitle(title: '数据与回顾'),
            AppStagger(
              index: 2,
              child: Column(
                children: [
                  AppActionTile(
                    icon: Icons.bar_chart,
                    title: '学习统计',
                    subtitle: '趋势与热力图',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const StatsPageScreen()),
                    ),
                  ),
                  AppActionTile(
                    icon: Icons.insights,
                    title: '本周报告',
                    subtitle: '这周做了什么、下周改什么(本地算,不调 AI)',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const WeeklyReportScreen()),
                    ),
                  ),
                  // 错误档案(v2.1):把"我英语不好"变成"我时态错了 7 次"。
                  // 副标题报出积压量,这个"平时没人点"的页面才有被点开的理由。
                  AppActionTile(
                    icon: Icons.fact_check_outlined,
                    title: '错误档案',
                    subtitle: _activeErrorKinds > 0
                        ? '待处理 $_activeErrorKinds 类'
                        : '写译批改、读后测验与复习里的错题',
                    onTap: _openErrorArchive,
                  ),
                  // 备份与导出(v2.2):数据只在这台手机上,这是唯一的迁移/保险出口
                  AppActionTile(
                    icon: Icons.backup_outlined,
                    title: '备份与导出',
                    subtitle: '完整备份(可回导)/ 生词本 CSV / Anki 导入包',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BackupScreen()),
                    ),
                  ),
                  // 学习曲线预览:数据与回顾组里最"一眼看懂"的那张图
                  if (stats.dailyLogs.isNotEmpty) ...[
                    const SizedBox(height: Gap.xs),
                    LearningCurveChart(dailyLogs: stats.dailyLogs),
                  ],
                ],
              ),
            ),

            // ── 设置与数据管理 ──
            const AppSectionTitle(title: '设置与数据管理'),
            AppStagger(
              index: 3,
              child: Column(
                children: [
                  AppActionTile(
                    icon: Icons.settings,
                    title: 'API 设置',
                    subtitle: '配置 API Key',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ApiSettingsScreen()),
                    ),
                  ),
                  // 学习偏好(v2.0):朗读音色 + 不想看的题材/关键词。
                  // 与 API 设置分开放:一个是技术配置,一个是个人偏好,
                  // 混在一起用户找不到"屏蔽题材"这件事。
                  AppActionTile(
                    icon: Icons.tune,
                    title: '学习偏好',
                    // 副标题直接暴露"当前屏蔽了几个/哪些":用户一眼能看出
                    // 黑名单是不是生效了(静默生效等于没生效)
                    subtitle: _preferencesSubtitle(),
                    onTap: _openPreferences,
                  ),
                  // 外观(v2.2):深浅色 + 开屏文案(v2.5)
                  AppActionTile(
                    icon: Icons.brightness_6_outlined,
                    title: '外观',
                    subtitle: '浅色 / 深色 / 跟随系统 · 开屏文案',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AppearanceScreen()),
                    ),
                  ),
                  // 桌面小组件(v2.2):状态 / 一键添加 / 手动同步并预览
                  AppActionTile(
                    icon: Icons.widgets_outlined,
                    title: '桌面小组件',
                    subtitle: '在桌面看今天的任务与待复习数',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WidgetSettingsScreen(),
                      ),
                    ),
                  ),
                  AppActionTile(
                    icon: Icons.medical_information,
                    title: '诊断信息',
                    subtitle: '崩溃日志与配置',
                    onTap: _showDiagnostics,
                  ),
                  AppActionTile(
                    icon: Icons.system_update_alt,
                    title: '检查更新',
                    subtitle: 'GitHub 最新版',
                    onTap: _checkUpdate,
                  ),
                ],
              ),
            ),

            const SizedBox(height: Gap.md),

            // ── 这里原本是「AI 学习建议」卡片 ──
            // 已删除(用户 2026-09-24 实测:"完全没用"):它的输入只有"生词本收藏数 +
            // 连续天数 + 按书分布",算不出任何真东西 —— 说"先定小目标、每天 10 分钟"
            // 这种谁都能说的话,还要花一次付费 API 调用。
            // 现在"今天该做什么"由学习助理页按本地诊断给出:结论带数字依据、
            // 可点、可打勾、会随数据变化。两者定位重叠,留一个真的。
          ],
        ),
      ),
    );
  }

  /// 顶部三个关键数字(总词汇量 / 连续天数 / 已完成练习)
  Widget _buildStatsRow(ThemeData theme, StatsProvider stats) {
    return Row(
      children: [
        _StatCard(
          icon: Icons.menu_book,
          value: '${stats.totalVocab}',
          label: '总词汇量',
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: Gap.xs),
        _StatCard(
          icon: Icons.local_fire_department,
          value: '${stats.streakDays}',
          label: '连续天数',
          color: AppTheme.warningColor(context),
        ),
        const SizedBox(width: Gap.xs),
        _StatCard(
          icon: Icons.fitness_center,
          value: '${stats.totalExercises}',
          label: '已完成练习',
          color: AppTheme.successColor(context),
        ),
      ],
    );
  }

  /// 错误档案:回来后刷新副标题(用户刚在里面标了「已改正」)
  Future<void> _openErrorArchive() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ErrorArchiveScreen()),
    );
    if (!mounted) return;
    final errors = await DatabaseService.getErrorTags(status: 'active');
    if (!mounted) return;
    setState(() => _activeErrorKinds = errors.length);
  }

  /// 学习偏好:黑名单可能刚改过,回来自刷新,让副标题与磁盘保持一致
  Future<void> _openPreferences() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LearnerPreferencesScreen()),
    );
    if (!mounted) return;
    setState(() => _learnerModel = LearnerModelStore.load());
  }

  /// 检查更新:F3 —— 检查失败(网络全断)必须明说,不能伪装成"已是最新"
  Future<void> _checkUpdate() async {
    try {
      final info = await UpdateService.checkLatestRelease();
      if (!mounted) return;
      if (info == null || !info.hasUpdate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前已是最新版本')),
        );
      } else {
        showUpdateDialog(context, info);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败:$e')),
      );
    }
  }

  /// 词汇量基线行(v2.6):原先是占半屏的大卡片,现收成学习组里的一行。
  /// 副标题直接报"约 X 词 · CEFR(区间)"——不点也能看到当前基线。
  Widget _buildBaselineTile() {
    final model = _learnerModel;
    final f = model.vocabEstimate;
    final hasBaseline = (f?.value ?? 0) > 0;
    final String subtitle;
    if (!hasBaseline) {
      subtitle = '尚未测量 · 约 5 分钟,给出词汇量与 CEFR 区间';
    } else {
      final range = (model.vocabLow != null && model.vocabHigh != null)
          ? '(${model.vocabLow}-${model.vocabHigh})'
          : '';
      final cefr = (model.cefr != null && model.cefr!.value.isNotEmpty)
          ? ' · ${model.cefr!.value}'
          : '';
      subtitle = '约 ${f!.value} 词$range$cefr · 点击可重测';
    }
    return AppActionTile(
      icon: Icons.straighten,
      title: '词汇量测试',
      subtitle: subtitle,
      onTap: () => _pickPlacement(hasBaseline: hasBaseline),
    );
  }

  /// 选速测(5 分钟)/ 完整版(10 分钟)—— 原来这两个按钮常驻在「我的」页,
  /// 现在收进弹层:需要时才出现,不占首页空间。
  Future<void> _pickPlacement({required bool hasBaseline}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('词汇量测试',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: Gap.xxs),
                Text(
                  '测试给出的是区间而不是单一数字;隔一段时间可以重测,基线会更新。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                if (hasBaseline) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    '当前基线:${_baselineDetail()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: Gap.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, 'quick'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    child: const Text('速测(约 5 分钟)'),
                  ),
                ),
                const SizedBox(height: Gap.xs),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, 'full'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    child: const Text('完整版(约 10 分钟)'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    await _startPlacement(full: choice == 'full');
  }

  /// 「学习偏好」副标题:没屏蔽就说清这一页有什么,屏蔽了就报数量和内容
  String _preferencesSubtitle() {
    final topics = _learnerModel.blockedTopics;
    final keywords = _learnerModel.blockedKeywords;
    final total = topics.length + keywords.length;
    if (total == 0) return '朗读音色 · 屏蔽题材与关键词';
    final shown = [...topics, ...keywords].take(3).join('、');
    final more = total > 3 ? ' 等 $total 项' : '';
    return '已屏蔽:$shown$more';
  }

  /// 词汇量基线的**依据**一句话(收成入口行后,详情放进弹层/测试完成后看)
  String _baselineDetail() => LearnerContext.describeBaseline(_learnerModel);

  Future<void> _startPlacement({required bool full}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlacementTestScreen(full: full)),
    );
    if (!mounted) return;
    // 回来时刷新基线展示(测试结果已写进学习者模型)
    setState(() => _learnerModel = LearnerModelStore.load());
  }

  /// 诊断信息:崩溃日志 + 当前 API 配置摘要(key 打码)。
  /// 真机闪退/识别失败时,打开这里截图即可定位,无需 adb(v1.3.2)。
  Future<void> _showDiagnostics() async {
    final log = await CrashLogger.readCrashLog();
    final box = Hive.box(AppConstants.hiveBoxSettings);
    // 审查 P2-6:原来给前 6 位 + 后 2 位 + 精确长度,截图外发即泄露可用片段
    // (sk-/ark- 前缀之外的字符都是秘密)。现在只报"哪家 + 多少字符":
    // 足以判断"是不是填了/填错家/少复制",又拼不出任何片段。
    String maskKey(String? k) {
      if (k == null || k.isEmpty) return '(未配置)';
      final String kind;
      final lower = k.toLowerCase();
      if (lower.startsWith('sk-')) {
        kind = 'DeepSeek Key';
      } else if (lower.startsWith('ark-')) {
        kind = '火山方舟 Key';
      } else {
        kind = '未知厂商 Key';
      }
      return '$kind(${k.length} 字符)';
    }

    String briefUrl(String? u) {
      if (u == null || u.isEmpty) return '(默认)';
      return u;
    }

    final summary = [
      // 审查 P2-6:这一页会整屏截图外发,提醒必须写在最顶部(而不是藏在按钮说明里)
      '⚠️ 此页含本机日志与配置,公开前请自行检查(Key 只显示厂商与长度)',
      '',
      '── 主 API(多模态) ──',
      'Key: ${maskKey(ApiEndpointConfig.primary.apiKey)}',
      'Base URL: ${briefUrl(box.get(AppConstants.keyDoubaoBaseUrl) as String?)}',
      '模型: ${ApiEndpointConfig.primary.model}',
      '思考: ${ApiEndpointConfig.primary.thinking}',
      '',
      '── 副 API(文本) ──',
      'Key: ${maskKey(ApiEndpointConfig.secondary.apiKey)}',
      'Base URL: ${briefUrl(box.get(AppConstants.keyDeepseekBaseUrl) as String?)}',
      '模型: ${ApiEndpointConfig.secondary.model}',
      '',
      '── 模型列表加载 ──',
      DoubaoApiService.lastFetchNote,
      // v2.3:内容源可达性取决于**用户网络**,平时看不见 —— 放这里让"材料中心
      // 打不开"这类问题一次截图就能定性(哪些源试过、结果、失败原因)
      ...MaterialSourceStatus.summaryLines(
        sources: MaterialSourceService.sources,
        state: MaterialSourceStatus.loadAll(),
        now: DateTime.now(),
      ),
      '',
      '── 桌面小组件 ──',
      await WidgetService.statusLine(),
      '',
      '── 崩溃日志 ──',
      log.isEmpty ? '(无崩溃记录)' : log,
    ].join('\n');

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('诊断信息'),
        content: SingleChildScrollView(
          child: SelectableText(
            summary,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await CrashLogger.clearCrashLog();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('清空日志'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(
            vertical: Gap.md, horizontal: Gap.xs),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: Gap.xxs + 2),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
