import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/learner_model.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/stats_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../services/about_content.dart';
import '../../services/api_endpoint.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../services/learner_context.dart';
import '../../services/learner_model_store.dart';
import '../../services/material_source.dart';
import '../../services/material_source_status.dart';
import '../../services/tutor_briefing.dart';
import '../../services/translation_diagnostics.dart';
import '../../services/update_service.dart';
import '../../services/widget_service.dart';
import '../../utils/crash_logger.dart';
import '../../widgets/brief_kit.dart';
import '../../widgets/profile_name_card.dart';
import '../../widgets/update_dialog.dart';
import '../../widgets/waiting.dart';
import '../input/learner_preferences_screen.dart';
import '../review/review_screen.dart';
import '../tutor/placement_test_screen.dart';
import '../writing/writing_logs_screen.dart';
import 'about_doc_screen.dart';
import 'about_screen.dart';
import 'api_settings.dart';
import 'appearance_screen.dart';
import 'backup_screen.dart';
import 'bookmarks_screen.dart';
import 'error_archive_screen.dart';
import 'stats_page.dart';
import 'vocab_list.dart';
import 'weekly_report_screen.dart';
import 'widget_settings_screen.dart';

/// 「我的」首页 · B「每日简报」语言。
///
/// 用户选型(2026-11-06):助理/我的 = B 每日简报 + A 数据内页。
/// 这一页从「9 个入口行平铺」改成**本周简报**:
/// 刊头 → 一句本周结论 + 一段事实 → 名片 → 本周事实卡(真实数字 + 7 天柱)
/// → 分组入口(学习 / 数据 / 设置)。数据全部来自现有 Provider 与 Hive:
/// `StatsProvider` / `LearnerModelStore` / 错误档案条数 / 写译记录条数。
class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({super.key});

  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  /// 学习者模型:词汇量基线/屏蔽偏好(同步读 Hive,不阻塞首帧)
  LearnerModel _learnerModel = LearnerModel();

  /// 待处理的错误类数(错误档案入口副标题)
  int _activeErrorKinds = 0;

  /// 写译记录篇数(这个入口以前在「我的」里根本没有)
  int _writingLogCount = 0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadAll();
    });
  }

  Future<void> _loadAll() async {
    _learnerModel = LearnerModelStore.load();
    try {
      final List<Map<String, Object?>> errors =
          await DatabaseService.getErrorTags(status: 'active');
      if (!mounted) return;
      setState(() => _activeErrorKinds = errors.length);
    } catch (_) {
      // 读不到就退回中性副标题,不影响首页
    }
    try {
      final List<dynamic> logs = await DatabaseService.getWritingLogs(limit: 200);
      if (!mounted) return;
      setState(() => _writingLogCount = logs.length);
    } catch (_) {
      // 同上:写译记录读失败只是少一个数字
    }
    await Future.wait(<Future<void>>[
      context.read<StatsProvider>().loadStats(),
      context.read<VocabProvider>().loadVocabularies(),
      context.read<BookmarkProvider>().load(),
    ]);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final StatsProvider stats = context.watch<StatsProvider>();
    final BriefTheme t = BriefTheme.of(context);
    if (_loading) {
      return BriefScaffold(
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: SkeletonLines(lines: 6, seed: 2),
        ),
      );
    }
    final MineBriefing b = MineBriefing.build(
      totalVocab: stats.totalVocab,
      streakDays: stats.streakDays,
      totalExercises: stats.totalExercises,
      dailyLogs: stats.dailyLogs,
      activeErrorKinds: _activeErrorKinds,
      writingLogCount: _writingLogCount,
      cefr: _learnerModel.cefr?.value,
      vocabEstimate: _learnerModel.vocabEstimate?.value,
      vocabLow: _learnerModel.vocabLow,
      vocabHigh: _learnerModel.vocabHigh,
    );

    return BriefScaffold(
      refresh: _loadAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          BriefDateHead(
            eyebrow: '我的 · PROFILE',
            bigDate: b.dateBig,
            rightTop: b.weekday,
            rightBottom:
                b.streakDays > 0 ? '连续 ${b.streakDays} 天' : '还没形成连续记录',
          ),
          const SizedBox(height: Gap.md),
          Text(
            b.greeting,
            style: AppFont.headingStyle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          const SizedBox(height: Gap.xs),
          BriefLead(title: b.headline, body: b.lead),
          const SizedBox(height: Gap.md),

          // ── 个性化名片(保留原有头像/背景/签名能力)──
          ProfileNameCard(vocabCount: stats.totalVocab),
          const SizedBox(height: Gap.md),

          // ── 本周事实 ──
          BriefCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                BriefSectionTitle(
                  eyebrow: '本周',
                  trailing: '看本周报告',
                  onTrailingTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const WeeklyReportScreen(),
                      ),
                    );
                    if (mounted) await _loadAll();
                  },
                ),
                if (b.facts.isEmpty)
                  BriefEmpty(
                    title: '这周还没有学习记录',
                    hint: '收一个词、做一次练习,这里就会出现真实数字与 7 天柱。',
                    actionLabel: '去输入页',
                    onAction: () => Navigator.maybePop(context),
                  )
                else
                  BriefStatRow(
                    stats: <BriefStat>[
                      for (final BriefFact f in b.facts.take(3))
                        BriefStat(
                          value: f.value,
                          label: f.label,
                          valueSize: 24,
                          color: switch (f.tone) {
                            BriefTone.good => t.accent2,
                            BriefTone.accent => t.accent,
                            BriefTone.warn => t.warn,
                            BriefTone.neutral => t.ink,
                          },
                        ),
                    ],
                  ),
                if (b.weekBars.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  BriefBars(values: b.weekBars, height: 30),
                  const SizedBox(height: 6),
                  Text(
                    '近 7 天活动量 ${b.weekBarsTotal > 0 ? '合计 ${b.weekBarsTotal}' : '暂无记录'}',
                    style: AppFont.metaStyle.copyWith(
                      fontSize: 10.5,
                      color: t.inkFaint,
                    ),
                  ),
                ],
                if (b.gaps.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '还缺:${b.gaps.join('、')} —— 补上之后,统计与建议才会具体。',
                    style: AppFont.metaStyle.copyWith(
                      fontSize: 10.5,
                      height: 1.55,
                      color: t.warn,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),

          // ── 学习 ──
          BriefCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              children: <Widget>[
                BriefEntryRow(
                  title: '词汇量测试',
                  subtitle: b.vocabText,
                  dense: true,
                  onTap: _pickPlacement,
                ),
                BriefEntryRow(
                  title: '我的生词本',
                  subtitle: '${stats.totalVocab} 个词 · 按书籍分组',
                  dense: true,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const VocabListScreen(),
                      ),
                    );
                    if (mounted) await _loadAll();
                  },
                ),
                BriefEntryRow(
                  title: '复习模式',
                  subtitle: '抽认卡记忆 · 到期词优先',
                  dense: true,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const ReviewScreen()),
                    );
                    if (mounted) await _loadAll();
                  },
                ),
                BriefEntryRow(
                  title: '收藏夹',
                  subtitle: '收藏的洞见与好句',
                  dense: true,
                  showDivider: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const BookmarksScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),

          // ── 数据与回顾 ──
          BriefCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              children: <Widget>[
                BriefEntryRow(
                  title: '学习统计',
                  subtitle: '趋势 / 热力图 / 月度(诊断台排版)',
                  dense: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const StatsPageScreen()),
                  ),
                ),
                BriefEntryRow(
                  title: '本周报告',
                  subtitle: '这周做了什么、下周改什么(本地算,不调 AI)',
                  dense: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const WeeklyReportScreen(),
                    ),
                  ),
                ),
                BriefEntryRow(
                  title: '错误档案',
                  subtitle: _activeErrorKinds > 0
                      ? '待处理 $_activeErrorKinds 类 · 写译/测验/复习的错题'
                      : '写译批改、读后测验与复习里的错题',
                  trailingText: _activeErrorKinds > 0 ? '$_activeErrorKinds 类' : null,
                  dense: true,
                  onTap: _openErrorArchive,
                ),
                BriefEntryRow(
                  title: '写译记录',
                  subtitle: _writingLogCount > 0
                      ? '$_writingLogCount 篇 · 按日期归档的写译轨迹'
                      : '按日期归档的写译练习轨迹',
                  trailingText: _writingLogCount > 0 ? '$_writingLogCount 篇' : null,
                  dense: true,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const WritingLogsScreen(),
                      ),
                    );
                    if (mounted) await _loadAll();
                  },
                ),
                BriefEntryRow(
                  title: '备份与导出',
                  subtitle: '完整备份(可回导)/ 生词本 CSV / Anki 导入包',
                  dense: true,
                  showDivider: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),

          // ── 设置 ──
          BriefCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              children: <Widget>[
                BriefEntryRow(
                  title: 'API 设置',
                  subtitle: '配置 API Key(只显示厂商与长度)',
                  dense: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const ApiSettingsScreen()),
                  ),
                ),
                BriefEntryRow(
                  title: '学习偏好',
                  subtitle: _preferencesSubtitle(),
                  dense: true,
                  onTap: _openPreferences,
                ),
                BriefEntryRow(
                  title: '外观',
                  subtitle: '浅色 / 深色 / 跟随系统 · 开屏文案',
                  dense: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AppearanceScreen(),
                    ),
                  ),
                ),
                BriefEntryRow(
                  title: '桌面小组件',
                  subtitle: '在桌面看今天的任务与待复习数',
                  dense: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const WidgetSettingsScreen(),
                    ),
                  ),
                ),
                BriefEntryRow(
                  title: '关于与更新',
                  subtitle: '版本 / 检查更新 / 诊断信息 / 开源许可 / 公告重看',
                  dense: true,
                  showDivider: false,
                  onTap: _openAbout,
                ),
              ],
            ),
          ),

          // ── 关于(用户第 8 条:底部新增关于栏,三个入口)──
          BriefCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              children: <Widget>[
                for (final AboutDoc doc in AboutDoc.values) ...<Widget>[
                  BriefEntryRow(
                    title: doc.title,
                    subtitle: doc.subtitle,
                    dense: true,
                    showDivider: doc != AboutDoc.values.last,
                    onTap: () => _openDoc(doc),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openErrorArchive() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ErrorArchiveScreen()),
    );
    if (!mounted) return;
    await _loadAll();
  }

  Future<void> _openPreferences() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const LearnerPreferencesScreen()),
    );
    if (!mounted) return;
    setState(() => _learnerModel = LearnerModelStore.load());
  }

  void _openAbout() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AboutScreen(
          onCheckUpdate: _checkUpdate,
          onShowDiagnostics: _showDiagnostics,
        ),
      ),
    );
  }

  /// 关于三入口(软件声明 / 软件特色 / 软件思想)
  Future<void> _openDoc(AboutDoc doc) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => AboutDocScreen(doc: doc)),
    );
  }

  /// 词汇量测试:基线有/没有都给同一入口,弹层选速测或完整版
  Future<void> _pickPlacement() async {
    final bool hasBaseline = (_learnerModel.vocabEstimate?.value ?? 0) > 0;
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        final ThemeData theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '词汇量测试',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
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

  Future<void> _startPlacement({required bool full}) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PlacementTestScreen(full: full),
      ),
    );
    if (!mounted) return;
    setState(() => _learnerModel = LearnerModelStore.load());
    await _loadAll();
  }

  String _baselineDetail() => LearnerContext.describeBaseline(_learnerModel);

  String _preferencesSubtitle() {
    final List<String> topics = _learnerModel.blockedTopics;
    final List<String> keywords = _learnerModel.blockedKeywords;
    final int total = topics.length + keywords.length;
    if (total == 0) return '朗读音色 · 屏蔽题材与关键词';
    final String shown = <String>[...topics, ...keywords].take(3).join('、');
    return '已屏蔽:$shown${total > 3 ? ' 等 $total 项' : ''}';
  }

  /// 检查更新:F3 —— 检查失败(网络全断)必须明说,不能伪装成"已是最新"
  Future<void> _checkUpdate() async {
    try {
      final dynamic info = await UpdateService.checkLatestRelease();
      if (!mounted) return;
      if (info == null || info.hasUpdate != true) {
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

  /// 诊断信息:崩溃日志 + 当前 API 配置摘要(key 打码)。
  /// 真机闪退/识别失败时,打开这里截图即可定位,无需 adb(v1.3.2)。
  Future<void> _showDiagnostics() async {
    final String log = await CrashLogger.readCrashLog();
    final box = Hive.box(AppConstants.hiveBoxSettings);
    String maskKey(String? k) {
      if (k == null || k.isEmpty) return '(未配置)';
      final String kind;
      final String lower = k.toLowerCase();
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

    final String summary = <String>[
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
      '── 翻译(阅读器) ──',
      '槽位/模型: ${TranslationDiagnostics.targetSummary}',
      'Base URL: ${TranslationDiagnostics.baseHost}',
      '最近失败:',
      ...TranslationDiagnostics.failureLines(),
      '',
      '── 模型列表加载 ──',
      DoubaoApiService.lastFetchNote,
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
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('诊断信息'),
        content: SingleChildScrollView(
          child: SelectableText(
            summary,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.dangerColor(ctx),
            ),
            onPressed: () async {
              final bool? confirmed = await showDialog<bool>(
                context: ctx,
                builder: (BuildContext c) => AlertDialog(
                  title: const Text('清空崩溃日志?'),
                  content: const Text(
                    '只会删除本机保存的崩溃诊断记录,不影响生词、材料、'
                    '学习统计与 API Key。清空后无法恢复。',
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('清空'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
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
