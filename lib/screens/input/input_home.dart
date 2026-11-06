import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../providers/vocab_provider.dart';
import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/saved_session.dart';
import '../../services/doubao_api.dart';
import '../../services/api_endpoint.dart';
import '../../services/learner_model_store.dart';
import '../../services/input_prefs.dart';
import '../../services/material_library.dart';
import '../../services/material_prefs.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/art_cover.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/v4/v4_kit.dart';
import '../../widgets/waiting.dart';
import 'material_import_flow.dart';
import 'find_material_screen.dart';
import 'material_reader_screen.dart';
import 'process_chat.dart';
import 'widgets/ai_article_section.dart';
import 'material_category_screen.dart';
import 'material_center_screen.dart';
import '../../services/material_topics.dart';
import 'widgets/analysis_mode_picker.dart';
import 'widgets/imported_materials_section.dart';
import 'widgets/material_preview_dialog.dart';
import 'widgets/my_materials_section.dart';

class InputHomeScreen extends StatefulWidget {
  const InputHomeScreen({super.key});

  @override
  State<InputHomeScreen> createState() => _InputHomeScreenState();
}

class _InputHomeScreenState extends State<InputHomeScreen> {
  final ImagePicker _picker = ImagePicker();
  String _sourceBook = '';
  String _sourcePage = '';
  bool _showBookInput = false;

  /// 材料架上"正在读"的材料(v3 批 2)。
  ///
  /// 为什么输入首页要加载这个:用户 11/01 的批注是"输入 = 读 + 听",而这一页
  /// 以前第一屏是"上传图片" —— 一个"工具入口"占了输入的主位。现在第一屏回答
  /// "今天输入什么":有在读的继续读,没有的去材料中心按难度找。
  List<ShelfItem> _shelf = const [];
  bool _shelfLoading = true;

  /// 输入偏好(难度档等)。用户 11/01:难度要能自选,并且全 App 同步 ——
  /// 这里就是"同步"的入口之一(材料中心、推荐、题目都读同一个 prefs)。
  MaterialPrefs _prefs = MaterialPrefs.load();

  /// 当前选中的题材 tab(v4):只影响 tab 高亮,点击即进分类页。
  String _selectedTopicId = 'sci_tech';

  /// 难度档辅助调整建议(v3 批 7 · P1-2):suggestBand 的展示结果。
  /// null = 还没算完 / 没有建议 —— 两种情况都不占位(不留空行)。
  BandAdvice? _bandAdvice;

  /// 多图累积
  final List<File> _pendingImages = [];
  static const _maxImages = 10;

  // ── 当前模型 & 思考模式（从 Hive 实时读） ──
  String get _currentModel {
    final v = Hive.box(
      AppConstants.hiveBoxSettings,
    ).get(AppConstants.keyDoubaoModel);
    return (v is String && v.isNotEmpty) ? v : AppConstants.doubaoVisionModel;
  }

  /// v1.7.0:取配置层已校验的档位(档位表外的值会被迁移),
  /// 不再读裸 Hive 值——否则「极致」这类合法档位在页头显示成"不思考"。
  String get _currentThinking => ApiEndpointConfig.primary.thinking;
  @override
  void initState() {
    super.initState();
    // 初始加载词库
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<VocabProvider>().loadVocabularies();
      _loadShelf();
      // 难度档辅助调整:首帧后用真实行为算一条建议(数据不足时静默不显示)
      _loadBandAdvice();
    });
  }

  /// 读真实信号并算"要不要调档"的建议(失败静默:建议只是辅助,不能因此白屏)。
  Future<void> _loadBandAdvice() async {
    try {
      final advice = await loadBandAdvice();
      if (!mounted) return;
      setState(() => _bandAdvice = advice);
    } catch (e) {
      debugPrint('输入首页难度建议读取失败(已忽略): $e');
    }
  }

  /// 加载"在读材料"(失败静默:首页不能因为一次书架查询失败就白屏)。
  Future<void> _loadShelf() async {
    try {
      final items = await MaterialLibrary.shelf(limit: 30);
      if (!mounted) return;
      setState(() {
        _shelf = items;
        _shelfLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _shelfLoading = false);
    }
  }

  /// 正在读的那一份:读过一点、还没读完;没有就返回 null(空态)。
  ShelfItem? get _continueItem {
    for (final item in _shelf) {
      if (!item.finished && item.percent > 0) return item;
    }
    return null;
  }

  /// 打开阅读器,回来刷新进度(继续读卡的百分比要立刻变)。
  Future<void> _openShelfItem(ShelfItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialReaderScreen(materialId: item.id),
      ),
    );
    if (!mounted) return;
    _loadShelf();
    // 阅读会改变"读完率/查词密度" → 难度建议要按新数据重算
    _loadBandAdvice();
  }

  void _openMaterialCenter() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MaterialCenterScreen()),
    ).then((_) {
      if (!mounted) return;
      _loadShelf();
      // 材料中心里可能改了难度档 → 回来重算建议(首页不能拿着旧档的结论)
      _loadBandAdvice();
    });
  }

  /// 「找材料」统一入口(v2.27.0)：旧的 AI 找材料页已下线，这里进新的
  /// 「找材料」(自由搜 / 按我的情况找)，与材料中心/hub 的入口是同一页。
  void _openAiDiscover() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FindMaterialScreen()),
    ).then((_) {
      if (mounted) _loadShelf();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topics = MaterialTopic.all.take(6).toList();
    final v4Topics = v4TopicsFrom([
      for (final t in topics) (id: t.id, label: t.label),
    ]);

    // v4(2026-11-02 用户定案"前端重做";11-03 选定「明亮果冻」基调):
    // 整页换成新的视觉语言 —— 果冻头图 + 题材 tabs + 糖果色动作砖 + 白卡列表。
    final goalText = (LearnerModelStore.load().goal?.value ?? '').trim();
    return V4PageScaffold(
      domain: GraphicDomain.news,
      eyebrow: _dateLine(),
      title: '输入',
      subtitle: '读和听，才是输入。找不到想读的，去材料中心挑一篇。',
      showAppBarBack: false,
      chips: [
        V4GlassChip(icon: Icons.speed, label: '难度 ${_prefs.band.label}'),
        if (goalText.isNotEmpty)
          V4GlassChip(
            icon: Icons.flag_outlined,
            label: goalText.length > 10 ? '${goalText.substring(0, 10)}…' : goalText,
          ),
      ],
      actions: [
        V4PillButton(
          label: '材料中心',
          light: true,
          icon: Icons.explore_outlined,
          onTap: _openMaterialCenter,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 题材 tabs:点一个直接进对应分类页
          V4TopicTabs(
            topics: v4Topics,
            selectedId: _selectedTopicId,
            onSelected: (t) {
              setState(() => _selectedTopicId = t.id);
              final topic = topics.firstWhere((m) => m.id == t.id);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MaterialCategoryScreen(topic: topic),
                ),
              ).then((_) {
                if (!mounted) return;
                _loadShelf();
                _loadBandAdvice();
              });
            },
          ),
          const SizedBox(height: Gap.sm),
          // 我的需求(目标 + 难度档)
          AppStagger(index: 0, child: _buildNeedBar(theme)),
          const SizedBox(height: Gap.sm),
          // 今天读什么:继续读 / 去材料中心
          AppStagger(index: 1, child: _buildTodayReading(theme)),
          const SizedBox(height: Gap.sm),
          // 快速入口:四块动作砖(材料中心/AI 找/拍照/链接)
          AppStagger(
            index: 2,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: V4ActionTile(
                        icon: Icons.explore_outlined,
                        title: '材料中心',
                        subtitle: '按题材/难度找材料',
                        primary: true,
                        domain: GraphicDomain.news,
                        onTap: _openMaterialCenter,
                      ),
                    ),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: V4ActionTile(
                        icon: Icons.auto_awesome,
                        title: '找材料',
                        subtitle: '自由搜 · 或按你的情况找',
                        domain: GraphicDomain.academic,
                        onTap: _openAiDiscover,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                Row(
                  children: [
                    Expanded(
                      child: V4ActionTile(
                        icon: Icons.add_photo_alternate_outlined,
                        title: '拍照/相册',
                        subtitle: '纸面、屏幕变材料',
                        domain: GraphicDomain.language,
                        onTap: _pickImageSource,
                      ),
                    ),
                    const SizedBox(width: Gap.xs),
                    Expanded(
                      child: V4ActionTile(
                        icon: Icons.link,
                        title: '链接导入',
                        subtitle: '网页 / 论文 / 期刊',
                        domain: GraphicDomain.culture,
                        onTap: _importFromLink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 模型/识图参数 + 待提交图片:保留原交互,但收进"导入材料"区块
          AppStagger(index: 3, child: _buildCaptureSectionCard(theme)),
          const SizedBox(height: Gap.xs),
          const V4SectionTitle(
            indexLabel: '01',
            title: 'AI 生词定制文章',
            subtitle: '把当天的生词编成一篇可读文章',
          ),
          const AppStagger(index: 4, child: AiArticleSection()),
          const V4SectionTitle(
            indexLabel: '02',
            title: '材料导入',
            subtitle: '拍照、链接、文件都汇总在这里',
          ),
          const AppStagger(index: 5, child: ImportedMaterialsSection()),
          const V4SectionTitle(
            indexLabel: '03',
            title: '我的词汇本',
            subtitle: '按分类看生词与复习进度',
          ),
          const AppStagger(index: 6, child: MyMaterialsSection()),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }

  /// 日期眉标(只留日期与星期,给大标题做"眉";引导语在大标题下方)。
  String _dateLine() {
    final now = DateTime.now();
    const week = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${now.month} 月 ${now.day} 日 · ${week[now.weekday - 1]}';
  }

  /// 我的需求条(v3 批 2)。
  ///
  /// 用户 11/01 的流程要求是「**需求在前、材料在后**」:先知道自己为什么学、
  /// 想读多难,材料才有意义。这一条永远在"今天读什么"上面,给出当前摘要;
  /// 点开可改难度档(i+1 舒适 / i+10 挑战 / i+100 快速正反馈)。
  Widget _buildNeedBar(ThemeData theme) {
    final cs = theme.colorScheme;
    final goal = LearnerModelStore.load().goal?.value;
    final goalText =
        (goal != null && goal.trim().isNotEmpty) ? goal.trim() : '未设目标';
    return AppCard(
      variant: AppCardVariant.compact,
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.md,
        vertical: Gap.sm,
      ),
      onTap: _showNeedSheet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(14),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: Icon(Icons.tune, size: 19, color: cs.primary),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '我的需求',
                      style: AppFont.subheadStyle.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$goalText · 难度 ${_prefs.band.label}（${_prefs.band.description}）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.metaStyle.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: cs.outline),
            ],
          ),
          // 难度档辅助调整(v3 批 7 · P1-2):有真实数据支撑且建议档≠当前档时
          // 才显示;没建议时 BandAdviceBanner 返回零尺寸 → 卡内不留空行。
          if (_bandAdvice != null)
            BandAdviceBanner(
              advice: _bandAdvice!,
              onApply: () => _applyBandAdvice(_bandAdvice!),
            ),
        ],
      ),
    );
  }

  /// 一键应用难度建议:写偏好(与材料中心/输出共用同一份)+ 收起建议 + 可逆提示。
  ///
  /// 为什么不重新计算一遍建议:用户刚采纳了"升一档",立刻再算大概率又给出
  /// "升一档"(读完率还是高),会变成连环弹建议 —— 收起,等下次进页面再说。
  Future<void> _applyBandAdvice(BandAdvice advice) async {
    final suggestion = advice.suggestion;
    if (suggestion == null) return;
    final next = _prefs.copyWith(band: suggestion.band.materialBand);
    setState(() {
      _prefs = next;
      _bandAdvice = null;
    });
    final ok = await applyBandSuggestion(suggestion);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '已调到 ${suggestion.band.label},可随时在「我的需求」里改回'
              : '保存失败,请重试',
        ),
      ),
    );
  }

  /// 难度档选择弹层(v3 批 2,用户 11/01:"需要让用户自选难度并软件同步调整")。
  ///
  /// 为什么给每档写"体验描述"而不是只给 i+1/i+10/i+100:这几个符号对老用户
  /// 是黑话。用户自己说"我喜欢 i+100,因为短期能获得效果形成正反馈" ——
  /// 所以 i+100 的文案要写成"费劲但爽",而不是"硬啃/不推荐"。
  Future<void> _showNeedSheet() async {
    final cs = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<MaterialBand>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
              child: Text(
                '我想读多难？',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Text(
                '难度档会同步给材料推荐、阅读器难度标签和练习题目；随时可以改。',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(height: Gap.xs),
            for (final band in MaterialBand.values)
              ListTile(
                leading: Icon(
                  _prefs.band == band
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _prefs.band == band ? cs.primary : null,
                ),
                title: Text(band.label),
                subtitle: Text(band.description),
                onTap: () => Navigator.pop(ctx, band),
              ),
            const SizedBox(height: Gap.xs),
          ],
        ),
      ),
    );
    if (picked == null || !mounted || picked == _prefs.band) return;
    setState(() {
      _prefs = _prefs.copyWith(band: picked);
      // 用户手动选过档后,按旧档算出的建议立刻过期 —— 收起,避免看到矛盾信息
      _bandAdvice = null;
    });
    await _prefs.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('难度档已切到 ${picked.label}：${picked.description}')),
    );
  }

  /// 今天输入什么:有在读材料就"继续读",没有就引导去材料中心按难度找。
  ///
  /// 用户 11/01:"输入 = 读 + 听";所以这一栏的主行动必须先是"接着读"。
  Widget _buildTodayReading(ThemeData theme) {
    final cs = theme.colorScheme;
    if (_shelfLoading) {
      return const AppCard(child: SkeletonLines(lines: 3));
    }
    final item = _continueItem;
    if (item == null) {
      return AppCard(
        variant: AppCardVariant.hero,
        onTap: _openMaterialCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今天读什么？',
              style: AppFont.titleStyle.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '按你的目标和难度档，从外刊 / 公版书 / 论文里找真实材料来读',
              style: AppFont.metaStyle.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: Gap.md),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _openMaterialCenter,
                      icon: const Icon(Icons.explore_outlined, size: 18),
                      label: const Text('去材料中心找材料'),
                    ),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _openAiDiscover,
                      child: const Text('找材料'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final title = item.titleCn.isNotEmpty ? item.titleCn : item.title;
    // v3 终版重做:继续读卡从"小图 + 两行字 + 两个按钮"升级为**今日阅读海报**:
    // 大封面（带投影）、字号层级、真实进度条、明确的「材料中心」入口。
    final progress = (item.percent.clamp(0, 100)) / 100.0;
    return AppCard(
      variant: AppCardVariant.hero,
      onTap: () => _openShelfItem(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '继续读',
                style: AppFont.tagStyle.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              if (item.cefr.isNotEmpty)
                AppTag(item.cefr, tone: AppTagTone.primary),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 带投影的大封面:让"在读的那一本"有实体感(不再是扁方块)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.card),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withAlpha(46),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ArtCover(
                  title: title,
                  kind: item.kind,
                  imageUrl: item.coverUrl,
                  width: 96,
                  height: 128,
                  levelLabel: item.cefr.isEmpty ? null : item.cefr,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.subheadStyle.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.percent > 0)
                          AppTag('已读 ${item.percent.round()}%'),
                        if (item.coverage != null && item.coverage! > 0)
                          AppTag('覆盖率 ${(item.coverage! * 100).round()}%'),
                        if (item.estMinutes > 0)
                          AppTag('约 ${item.estMinutes} 分钟'),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),
                    // 真实进度条:让"读到哪"成为视觉主体,而不是一行小字
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: cs.outlineVariant.withAlpha(70),
                      ),
                    ),
                    const SizedBox(height: Gap.sm),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        FilledButton(
                          onPressed: () => _openShelfItem(item),
                          child: const Text('接着读'),
                        ),
                        OutlinedButton(
                          onPressed: _openMaterialCenter,
                          child: const Text('材料中心'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 输入方式动作砖(v3 终版):等宽两张,主行动实心、次行动描边。
  Widget _captureActionTile(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool primary,
    required VoidCallback onTap,
  }) {
    final cs = theme.colorScheme;
    final fg = primary ? cs.onPrimary : cs.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        padding: const EdgeInsets.all(Gap.sm),
        decoration: BoxDecoration(
          color: primary ? cs.primary : cs.surfaceContainerHighest.withAlpha(80),
          borderRadius: BorderRadius.circular(Radii.card),
          border: primary
              ? null
              : Border.all(color: cs.outlineVariant, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: primary ? cs.onPrimary : cs.primary),
            const SizedBox(height: Gap.xs),
            Text(
              title,
              style: AppFont.subheadStyle.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFont.tagStyle.copyWith(
                color: primary ? cs.onPrimary.withAlpha(210) : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 拍照识文卡片(v2.6 重做;v2.7 升级为「上传分析材料」,用户第 3 条)。
  ///
  /// 用户原话:'"拍照识文"功能也要优化,现在的使用场景只能用于手写或者照片 ——
  /// 因此,该功能升级为"上传分析材料",然后子功能 ——"拍照识别"和"外部链接导入"
  /// (也就是兼容各种网站链接,包括但不限于论文、期刊等等这些)'。
  ///
  /// 所以这一张卡现在有**两个子功能**:
  /// 1. **拍照识别** = 原来的拍照/相册取词(识图结果页的模型/保存/追问原样保留);
  /// 2. **外部链接导入** = 贴一个公开链接 → 抓正文 → 在软件内的阅读器里读
  ///    (逐段翻译 / 点词 / 收藏 / 追问 / 底部动作栏,与材料中心同一套)。
  ///
  /// v3(批 2):从"本页唯一主行动(hero)"降为**第二层级的工具卡** ——
  /// 输入这一栏的主行动现在是"今天读什么"(见 [_buildTodayReading])。
  /// 用户 11/01 的原话是"输入 = 读 + 听",识图只是把纸面/屏幕变成材料的**手段**,
  /// 不该占住首屏最重的位置。
  Widget _buildCaptureSectionCard(ThemeData theme) {
    final cs = theme.colorScheme;
    return AppCard(
      variant: AppCardVariant.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行:图标块 + 标题 + 说明 —— 层级清楚,不挤成一行
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(14),
                  borderRadius: BorderRadius.circular(Radii.control),
                ),
                child: Icon(
                  Icons.document_scanner_outlined,
                  size: 21,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '拍照 / 导入材料',
                      style: AppFont.subheadStyle.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '把纸面/屏幕上的内容变成可读、可练的材料',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFont.metaStyle.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),

          // ① v2.10:拍照与相册合并成一个入口。
          // v3 终版:整宽大蓝按钮改成**两张等宽动作砖**（图标+标题+一句说明）:
          // 视觉更轻、信息更清楚，也避免"整屏一个巨大的蓝块"的廉价感。
          Row(
            children: [
              Expanded(
                child: _captureActionTile(
                  theme,
                  icon: Icons.add_photo_alternate_outlined,
                  title: '拍照识文',
                  subtitle: '纸面 / 屏幕 → 可读材料',
                  primary: true,
                  onTap: _pickImageSource,
                ),
              ),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: _captureActionTile(
                  theme,
                  icon: Icons.link,
                  title: '链接导入',
                  subtitle: '网页 / 论文 / 期刊',
                  primary: false,
                  onTap: _importFromLink,
                ),
              ),
            ],
          ),

          const SizedBox(height: Gap.sm),
          // ③ 参数行:模型 / 思考档(识图前即可切换)
          _buildModelThinkingRow(theme),

          // ④ 待提交图片缩略图 + 开始识别
          if (_pendingImages.isNotEmpty) ...[
            const SizedBox(height: Gap.sm),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: _pendingImages.length,
                separatorBuilder: (_, _) => const SizedBox(width: Gap.xs),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _showImagePreview(i),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.control - 2),
                        child: Image.file(
                          _pendingImages[i],
                          width: 64,
                          height: 72,
                          // P3:64×72 的缩略图按 128px 解码即可,
                          // 原图直解是低端机 OOM 的主因
                          cacheWidth: 128,
                          fit: BoxFit.cover,
                        ),
                      ),
                      // 删除按钮（右上角）
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _removePendingImage(i),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      // 裁剪按钮（右下角）
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () async {
                            final cropped = await _cropImage(
                              _pendingImages[i],
                            );
                            if (cropped != null && mounted) {
                              setState(() => _pendingImages[i] = cropped);
                            }
                          },
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            child: const Icon(
                              Icons.crop,
                              size: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Gap.xs),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitImages,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text('开始识别(${_pendingImages.length} 张)'),
              ),
            ),
          ],

          // ⑤ 继续上次暂存的会话
          if (_savedSessions.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showSavedSessions,
                icon: const Icon(Icons.history, size: 16),
                label: Text(
                  '继续上次会话(${_savedSessions.length} 条)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],

          // ⑥ 出处(可折叠,收起来时不占视觉)
          const SizedBox(height: Gap.xxs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _showBookInput = !_showBookInput),
              icon: Icon(
                _showBookInput ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                _sourceBook.isEmpty
                    ? '标注出处(可选)'
                    : '《$_sourceBook》p$_sourcePage',
              ),
            ),
          ),
          if (_showBookInput) _buildBookInput(theme),
        ],
      ),
    );
  }

  Widget _buildBookInput(ThemeData theme) {
    // v2.12:同 _buildModelThinkingRow —— 双重缩进改由卡片统一管
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              decoration: const InputDecoration(
                labelText: '书名',
                hintText: '如：哈利波特与魔法石',
                isDense: true,
              ),
              onChanged: (v) => _sourceBook = v,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: TextField(
              decoration: const InputDecoration(
                labelText: '页码',
                hintText: 'p23',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => _sourcePage = v,
            ),
          ),
        ],
      ),
    );
  }

  /// AI 模型 & 思考强度选择行 — 识图前即可切换，避免进入识别后再打断
  /// 上传图片入口(v2.10,用户 10/4 第 1 条):一个按钮 → 弹层里再选拍照 / 相册。
  ///
  /// 为什么要合并:以前"拍照识别"和"从相册选择"是**两个并排的按钮**,用户得先想
  /// "我这算拍照还是相册"——其实他心里只有"我要传张图"。收成一个入口后再分叉,
  /// 主界面少一个按钮,选择也更清楚。
  Future<void> _pickImageSource() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
              child: Text('图片来源',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍一张'),
              subtitle: const Text('用手写稿 / 书页 / 屏幕直接拍'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选(可多选)'),
              subtitle: const Text('最多 9 张,一次识别完'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            const SizedBox(height: Gap.xs),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'camera') {
      await _takePhoto();
    } else {
      await _pickFromGallery();
    }
  }

  Widget _buildModelThinkingRow(ThemeData theme) {
    // v2.12:原来是 horizontal: 20 —— 卡片自己的内边距已经是 20,
    // 再加一层就变成 40 的缩进,参数行被挤到中间。现在交给卡片统一管。
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.model_training,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: PopupMenuButton<String>(
              offset: const Offset(0, 200),
              constraints: const BoxConstraints(maxWidth: 280),
              itemBuilder: (_) => [
                // 按端点族/最近拉取结果展示(配了 DS 就显示 DS 模型,v1.4.3)
                ...primaryModelChoices().map((m) {
                  final isSel = m == _currentModel;
                  return PopupMenuItem(
                    value: 'model:$m',
                    height: 30,
                    child: Text(
                      m,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                        color: isSel ? const Color(0xFF3D7A5C) : null,
                      ),
                    ),
                  );
                }),
                const PopupMenuDivider(),
                ...AppConstants.thinkingOptionsFor(_currentModel).entries
                    .map((e) {
                  final isSel = e.key == _currentThinking;
                  return PopupMenuItem(
                    value: 'think:${e.key}',
                    height: 30,
                    child: Row(
                      children: [
                        Icon(
                          isSel ? Icons.lightbulb : Icons.lightbulb_outline,
                          size: 12,
                          color: isSel
                              ? AppTheme.warningColor(context)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSel
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSel
                                ? AppTheme.warningColor(context)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              onSelected: (v) async {
                if (v.startsWith('model:')) {
                  await Hive.box(
                    AppConstants.hiveBoxSettings,
                  ).put(AppConstants.keyDoubaoModel, v.substring(6));
                } else if (v.startsWith('think:')) {
                  await Hive.box(
                    AppConstants.hiveBoxSettings,
                  ).put(AppConstants.keyDoubaoThinking, v.substring(6));
                }
                if (mounted) setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _currentModel.length > 22
                      ? '${_currentModel.substring(0, 22)}…'
                      : _currentModel,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 思考强度快捷标签(橙色描边:半透明色相,深色下同样成立)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppTheme.warningColor(context).withAlpha(110),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              AppConstants.thinkingOptionsFor(_currentModel)[_currentThinking] ??
                  '不思考',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.warningColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 外部链接导入(v2.7,用户第 3 条):贴公开链接 → 抓正文 → 入库 → 阅读器。
  ///
  /// 与材料中心的导入走**同一个** [MaterialImportFlow]:抓取方式(Gutenberg/arXiv
  /// 用专用抓取、其它走通用网页正文)、失败原因、标题中文化、入库全都共用一份实现。
  Future<void> _importFromLink() async {
    final ingested = await MaterialImportFlow.run(
      context,
      model: LearnerModelStore.load(),
      only: ImportChannel.link,
      dialogTitle: '外部链接导入',
    );
    if (ingested == null || !mounted) return;
    final go = await showMaterialPreview(context, ingested);
    if (!mounted) return;
    if (go) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialReaderScreen(materialId: ingested.materialId),
        ),
      );
      if (mounted) await context.read<VocabProvider>().loadVocabularies();
    }
  }

  Future<void> _takePhoto() async {
    if (_pendingImages.length >= _maxImages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('最多$_maxImages张图片')));
      return;
    }
    try {
      // B0-3(2026-11-01):从 1024/q50 提到 **1600/q85**,与结果页「追加图片」
      // 入口统一(那边原来 2600/q92,像素≈6.4 倍,是追加闪退的根因之一)。
      // 为什么是 1600 而不是 2600:v2.13 的「自动方向检测」每张图要整图解码,
      // 1600 的解码内存约为 2600 的 38%,而 1024 对淡色划线/手写确实偏低 ——
      // 1600 是"识别率"与"内存峰值"的中点。预处理已移到后台 isolate 并串行。
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (photo != null && mounted) {
        setState(() => _pendingImages.add(File(photo.path)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('相机错误：$e')));
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_pendingImages.length >= _maxImages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('最多$_maxImages张图片')));
      return;
    }
    try {
      // B0-3:与拍照、结果页「追加图片」三方统一为 1600/q85(理由见 _takePhoto)。
      // 上限 _maxImages(代码实为 10 张)保持不变 —— 张数由产品决定,
      // 内存由"预处理移 isolate + 严格串行"兜底(见 vision_image.dart)。
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1600,
        limit: _maxImages - _pendingImages.length,
      );
      if (images.isNotEmpty && mounted) {
        final files = images
            .take(_maxImages - _pendingImages.length)
            .map((x) => File(x.path))
            .toList();
        setState(() => _pendingImages.addAll(files));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择图片错误：$e')));
      }
    }
  }

  /// 调用系统裁剪界面。返回裁剪后的文件，用户取消则返回 null。
  Future<File?> _cropImage(File imageFile, {String? label}) async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        maxWidth: 1024,
        maxHeight: 2048,
        compressQuality: 70,
        compressFormat: ImageCompressFormat.jpg,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: label != null ? '裁剪 $label' : '裁剪图片',
            toolbarColor: const Color(0xFF1A1A2E),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
        ],
      );
      if (cropped != null) return File(cropped.path);
      return null;
    } catch (e) {
      debugPrint('ReadFlow crop failed: $e');
      return imageFile;
    }
  }

  void _removePendingImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  // ═══════════════ 暂存会话 ═══════════════

  /// 已暂存的会话列表(最新在前)
  List<SavedSession> get _savedSessions {
    try {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      final raw = box.get(AppConstants.keySavedSessions);
      if (raw is List) {
        // Hive 读回的嵌套 Map 是 _Map<dynamic, dynamic>,不能直接
        // as Map<String, dynamic> 强转(会抛)——必须 .from 重建
        return raw
            .map((e) => SavedSession.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// 会话列表弹窗:点选恢复,可删除
  void _showSavedSessions() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    '暂存的会话',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Hive.box(
                        AppConstants.hiveBoxSettings,
                      ).delete(AppConstants.keySavedSessions);
                      Navigator.pop(ctx);
                      if (mounted) setState(() {});
                    },
                    child: Text(
                      '清空全部',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.dangerColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_savedSessions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text('暂无暂存的会话',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              )
            else
              ...List.generate(_savedSessions.length, (i) {
                final s = _savedSessions[i];
                return ListTile(
                  leading: const Icon(Icons.chat_bubble_outline, size: 20),
                  title: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    s.dateLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () {
                      final box = Hive.box(AppConstants.hiveBoxSettings);
                      final rest = _savedSessions
                          .where((x) => x.id != s.id)
                          .toList();
                      box.put(
                        AppConstants.keySavedSessions,
                        rest.map((x) => x.toJson()).toList(),
                      );
                      Navigator.pop(ctx);
                      if (mounted) setState(() {});
                    },
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _resumeSession(s);
                  },
                );
              }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 恢复会话:从结果 photoPath 重建图片文件列表(只保留仍存在的副本),
  /// 以恢复模式打开结果页 — 识别结果与追问消息一并还原。
  void _resumeSession(SavedSession s) {
    final files = <File>[];
    for (final m in s.results) {
      // Vocabulary.toMap() 序列化为 snake_case('photo_path');
      // 兼容老数据的 camelCase('photoPath')
      final p = (m['photo_path'] ?? m['photoPath']) as String?;
      if (p == null || p.isEmpty) continue;
      final f = File(p);
      if (f.existsSync() && !files.any((x) => x.path == p)) {
        files.add(f);
      }
    }
    // v2.6 修复(用户实测:"选不保存对话后,拍照识文下还是保留残留对话"):
    // 暂存会话是**一次性的草稿** —— 恢复后必须从暂存列表里删掉,否则它会一直
    // 挂在那里:用户明明在退出时选了「不保存」,回到输入页却还是看到同一条旧会话,
    // 点进去又把它整个恢复出来。想再留一份的话,重新「暂时离开」即可。
    try {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      final rest = _savedSessions.where((x) => x.id != s.id).toList();
      box.put(
        AppConstants.keySavedSessions,
        rest.map((x) => x.toJson()).toList(),
      );
      setState(() {});
    } catch (e) {
      debugPrint('ReadFlow 消费暂存会话失败(不影响恢复): $e');
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessChatScreen(
          imageFiles: files,
          sourceBook: s.sourceBook,
          sourcePage: s.sourcePage,
          analysisMode: s.analysisMode,
          restoreSession: s,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  /// 点击缩略图 → 大图预览弹窗，可放大查看、裁剪
  void _showImagePreview(int index) {
    final file = _pendingImages[index];
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, anim, secAnim) => _ImagePreviewPage(
          file: file,
          index: index,
          onCrop: _onCropFromPreview,
        ),
        transitionsBuilder: (ctx, anim, secAnim, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  /// 预览页中触发的裁剪 → 等待裁剪完成 → pop 回主页 → 替换图片
  Future<void> _onCropFromPreview(int index) async {
    final cropped = await _cropImage(_pendingImages[index]);
    if (cropped != null && mounted) {
      setState(() => _pendingImages[index] = cropped);
    }
  }

  void _submitImages() async {
    if (_pendingImages.isEmpty) return;

    // 弹出分析模式选择
    final mode = await showAnalysisModePicker(context);
    if (mode == null || !mounted) return; // 用户取消

    final files = List<File>.from(_pendingImages);
    _processImages(files, analysisMode: mode);
  }

  Future<void> _processImages(
    List<File> imageFiles, {
    String analysisMode = AppConstants.analysisModeMarked,
  }) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessChatScreen(
          imageFiles: imageFiles,
          sourceBook: _sourceBook.isNotEmpty ? _sourceBook : null,
          sourcePage: _sourcePage.isNotEmpty ? _sourcePage : null,
          analysisMode: analysisMode,
        ),
      ),
    );

    if (mounted) {
      // 从识图页返回后始终清空待提交图片（用户可在识图页内重试，无需保留）
      setState(() => _pendingImages.clear());
      // 重新加载学习材料列表
      await context.read<VocabProvider>().loadVocabularies();
      // await 之后 context 可能已失效(用户返回时页面被销毁),用前再确认一次
      if (!mounted) return;
      if (saved == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('生词已保存'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// 图片大图预览页 — 点击缩略图弹出，支持放大查看和裁剪入口
class _ImagePreviewPage extends StatelessWidget {
  final File file;
  final int index;
  final Future<void> Function(int index) onCrop;

  const _ImagePreviewPage({
    required this.file,
    required this.index,
    required this.onCrop,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 全屏图片（可交互）
          Center(
            child: InteractiveViewer(
              maxScale: 5.0,
              child: Image.file(
                file,
                width: size.width,
                // P3:按屏幕宽度解码,别把 12MP 原图整张解进内存(约 48MB/张)
                cacheWidth:
                    (size.width * MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(320, 2048),
                fit: BoxFit.contain,
              ),
            ),
          ),
          // 顶部关闭按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black54,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
          // 底部裁剪按钮
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context); // 先关预览
                  await onCrop(index);
                },
                icon: const Icon(Icons.crop, size: 18),
                label: const Text('裁剪图片'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
