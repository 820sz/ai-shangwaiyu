import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/stats_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../providers/article_provider.dart';
import '../../providers/bookmark_provider.dart';
import '../../config/constants.dart';
import '../../models/learner_model.dart';
import '../../services/api_endpoint.dart';
import '../../services/doubao_api.dart';
import '../../services/learner_context.dart';
import '../../services/learner_model_store.dart';
import '../../utils/crash_logger.dart';
import '../../widgets/stats_chart.dart';
import '../../widgets/update_dialog.dart';
import '../../services/update_service.dart';
import 'vocab_list.dart';
import 'stats_page.dart';
import 'api_settings.dart';
import 'bookmarks_screen.dart';
import '../review/review_screen.dart';
import '../input/learner_preferences_screen.dart';
import '../tutor/placement_test_screen.dart';

class ProfileHomeScreen extends StatefulWidget {
  const ProfileHomeScreen({super.key});

  @override
  State<ProfileHomeScreen> createState() => _ProfileHomeScreenState();
}

class _ProfileHomeScreenState extends State<ProfileHomeScreen> {
  String _advice = '';
  bool _loadingAdvice = false;
  /// 建议接口失败(审查 P2-33):原实现 catch 静默 → 界面与"数据太少"无法区分,
  /// 用户只能反复下拉刷新。留一个标志位给「重新生成」入口。
  bool _adviceFailed = false;

  /// 学习者模型(v2.0):词汇量基线卡片的数据来源。
  /// Hive 同步读,不阻塞首帧;测试页返回后再刷一次。
  LearnerModel _learnerModel = LearnerModel();

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
    await Future.wait([
      context.read<StatsProvider>().loadStats(),
      context.read<VocabProvider>().loadVocabularies(),
      context.read<BookmarkProvider>().load(),
    ]);
    // P2-10:三个 load 都 await 完之后用户可能已经退出本页,
    // 此时下面的 _loadAdvice 开头就要读 context,必须先挡一道
    if (!mounted) return;
    _loadAdvice();
  }

  Future<void> _loadAdvice() async {
    final stats = context.read<StatsProvider>();
    final vocab = context.read<VocabProvider>();
    final articleProv = context.read<ArticleProvider>();

    if (stats.totalVocab < 5) return; // 数据太少不推荐(界面会显示说明行,不是消失)

    setState(() {
      _loadingAdvice = true;
      _adviceFailed = false;
    });
    try {
      final result = await articleProv.getPersonalizedAdvice(
        totalVocab: stats.totalVocab,
        // 审查 P2-33:原先恒为 0 → AI 画像永远是"一个词都没掌握",
        // 建议内容与实际学习进度脱节(且是付费调用)。按 0=新词/1=学习中/2=掌握 取 2。
        masteredVocab:
            vocab.vocabularies.where((v) => v.masteryLevel == 2).length,
        streakDays: stats.streakDays,
        vocabByBook: vocab.vocabByBook,
      );
      if (mounted) setState(() => _advice = result);
    } catch (_) {
      // 失败要能看见(审查 P2-33):只记标志位,由界面给「重新生成」
      if (mounted) setState(() => _adviceFailed = true);
    }
    if (mounted) setState(() => _loadingAdvice = false);
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
          padding: const EdgeInsets.all(16),
          children: [
            // ── 统计卡片 ──
            Row(
              children: [
                _StatCard(
                    icon: Icons.menu_book,
                    value: '${stats.totalVocab}',
                    label: '总词汇量',
                    color: Colors.blue),
                const SizedBox(width: 10),
                _StatCard(
                    icon: Icons.local_fire_department,
                    value: '${stats.streakDays}',
                    label: '连续天数',
                    color: Colors.orange),
                const SizedBox(width: 10),
                _StatCard(
                    icon: Icons.fitness_center,
                    value: '${stats.totalExercises}',
                    label: '已完成练习',
                    color: Colors.green),
              ],
            ),
            const SizedBox(height: 20),

            // ── 快速入口 ──
            _MenuTile(
              icon: Icons.book,
              title: '我的生词本',
              subtitle: '按书籍分组',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VocabListScreen()),
              ),
            ),
            _MenuTile(
              icon: Icons.style,
              title: '复习模式',
              subtitle: '抽认卡记忆',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReviewScreen()),
              ),
            ),
            _MenuTile(
              icon: Icons.bar_chart,
              title: '学习统计',
              subtitle: '趋势与热力图',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StatsPageScreen()),
              ),
            ),
            _MenuTile(
              icon: Icons.star_outline,
              title: '收藏夹',
              subtitle: '收藏的洞见与好句',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BookmarksScreen()),
              ),
            ),
            _MenuTile(
              icon: Icons.settings,
              title: 'API 设置',
              subtitle: '配置 API Key',
              onTap: () => _showSettings(),
            ),
            // 学习偏好(v2.0):朗读音色 + 不想看的题材/关键词。
            // 与 API 设置分开放:一个是技术配置,一个是个人偏好,
            // 混在一起用户找不到"屏蔽题材"这件事。
            _MenuTile(
              icon: Icons.tune,
              title: '学习偏好',
              // 副标题直接暴露"当前屏蔽了几个/哪些":用户一眼能看出
              // 黑名单是不是生效了(静默生效等于没生效)
              subtitle: _preferencesSubtitle(),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LearnerPreferencesScreen(),
                  ),
                );
                // 黑名单可能刚改过:回来自刷新,让副标题与磁盘保持一致
                if (!mounted) return;
                setState(() => _learnerModel = LearnerModelStore.load());
              },
            ),
            _MenuTile(
              icon: Icons.medical_information,
              title: '诊断信息',
              subtitle: '崩溃日志与配置',
              onTap: () => _showDiagnostics(),
            ),
            _MenuTile(
              icon: Icons.system_update_alt,
              title: '检查更新',
              subtitle: 'GitHub 最新版',
              onTap: () async {
                try {
                  final info = await UpdateService.checkLatestRelease();
                  if (!context.mounted) return;
                  if (info == null || !info.hasUpdate) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('当前已是最新版本')),
                    );
                  } else {
                    showUpdateDialog(context, info);
                  }
                } catch (e) {
                  // F3:检查失败(网络全断)必须明说,不能伪装成"已是最新"
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('检查更新失败:$e')),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 16),

            // ── 词汇量基线(v2.0) ──
            // 这一块把"水平"从"生词本收藏数瞎估"变成**测量值 + 区间 + 依据**。
            // 导师与材料推荐都以它为地基,所以入口放在「我的」页显眼处。
            _buildBaselineCard(theme),

            // ── 学习曲线预览 ──
            if (stats.dailyLogs.isNotEmpty) ...[
              Text('学习趋势',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              LearningCurveChart(dailyLogs: stats.dailyLogs),
            ],

            const SizedBox(height: 20),

            // ── AI 建议 ──
            // 四态而不是两态(审查 P2-33):加载中 / 数据不足(说明行,不整块消失)/
            // 失败(给「重新生成」)/ 有内容。用户要能区分"暂时没有"和"坏了"。
            if (_loadingAdvice)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (stats.totalVocab < 5)
              Row(
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '收藏 5 个生词后自动生成学习建议',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              )
            else if (_advice.isNotEmpty) ...[
              Text('AI 学习建议',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Card(
                color: theme.colorScheme.primary.withAlpha(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          color: Colors.amber, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _advice,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(height: 1.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (_adviceFailed)
              Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '学习建议生成失败(网络或 API Key 问题)',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadingAdvice ? null : _loadAdvice,
                    child: const Text('重新生成'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ApiSettingsScreen()),
    );
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

  /// 词汇量基线卡片(v2.0):显示测量值/区间/来源,并提供两个测试入口
  Widget _buildBaselineCard(ThemeData theme) {
    final model = _learnerModel;
    final muted = theme.colorScheme.onSurfaceVariant;
    final f = model.vocabEstimate;
    final hasBaseline = (f?.value ?? 0) > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.straighten, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('词汇量基线',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasBaseline
                  ? '约 ${f!.value} 词'
                      '${model.vocabLow != null && model.vocabHigh != null ? '(${model.vocabLow}-${model.vocabHigh})' : ''}'
                      '${model.cefr != null && model.cefr!.value.isNotEmpty ? ' · ${model.cefr!.value}' : ''}'
                  : '尚未测量',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              // 依据必须摆出来:这行的存在就是为了让用户知道数字是怎么来的
              LearnerContext.describeBaseline(model),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _startPlacement(full: false),
                    child: const Text('速测(5 分钟)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _startPlacement(full: true),
                    child: const Text('完整版(10 分钟)'),
                  ),
                ),
              ],
            ),
            if (hasBaseline) ...[
              const SizedBox(height: 6),
              Text(
                '测试会给出区间而不是单一数字;隔一段时间可以重测,基线会更新。',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

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
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                // P2-31:正文灰阶对比度 <4.5:1,提到 grey[600] 达 WCAG AA
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
