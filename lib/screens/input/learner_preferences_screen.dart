import 'package:flutter/material.dart';
import '../../widgets/v4/v4_kit.dart';
import 'package:hive/hive.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/learner_model.dart';
import '../../models/material_recommendation.dart';
import '../../services/drill_catalog.dart';
import '../../services/learner_model_store.dart';
import '../../services/material_prefs.dart';
import '../../services/tts_accent.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';

/// 学习偏好(v2.0 起;v3 批 5 统一视觉 + 目标多选)
///
/// 一页管五件事(都是"用户主动表达偏好",不该分散到 API 设置里):
/// 1. **学习目标(多选)** —— 写入 `LearnerModel.goals`(多值),
///    同时兼容写第一个到单值 `goal`(旧读者/AI 提示词还在用它);
/// 2. **材料难度** —— i+1 / i+10 / i+100,与 `material_prefs.dart` 的
///    [MaterialBand] 同一口径(按已知词覆盖率分档),不再另立一套数字;
/// 3. **每日学习配额** —— 复习优先的时间预算 + 新词上限;
/// 4. **朗读音色** —— 跟随系统 / 英式 / 美式(存 Hive,词条朗读即生效);
/// 5. **不想看的题材与关键词** —— 材料推荐、找材料、助理选材一律遵守。
///
/// 为什么把"目标"和"难度"也放进这页:它们和"每天多少分钟"是同一类东西
/// (决定软件给用户什么),以前目标只在访谈/画像页能改、难度只在材料中心
/// 底部弹层能改 —— 用户根本找不到"在哪里调整我的人设"。
///
/// 黑名单的关键设计:界面上必须**看得到当前屏蔽了什么、能一条条删**。
/// 只给一个"添加"输入框的实现是单向门,用户设错了也不知道怎么退回。
class LearnerPreferencesScreen extends StatefulWidget {
  const LearnerPreferencesScreen({super.key});

  @override
  State<LearnerPreferencesScreen> createState() =>
      _LearnerPreferencesScreenState();
}

class _LearnerPreferencesScreenState extends State<LearnerPreferencesScreen> {
  late final Box _box;
  late LearnerModel _model;
  late MaterialPrefs _prefs;
  final _keywordCtrl = TextEditingController();

  /// 朗读音色档位:'system' | 'uk' | 'us'
  String _accent = 'system';

  /// 每日配额(来自学习者模型;缺省与 ReviewQueue 的默认值一致)
  int _dailyMinutes = 30;
  int _maxNewWords = 20;

  /// 学习目标多选(存的是 [DrillCatalog] 的中文 label —— 输出模块就按它组题)
  List<String> _selectedGoals = <String>[];

  /// 材料难度档(与材料中心"我的需求"同一个字段,不另存一份)
  MaterialBand _band = MaterialBand.any;

  @override
  void initState() {
    super.initState();
    _box = Hive.box(AppConstants.hiveBoxSettings);
    _model = LearnerModelStore.load();
    _prefs = MaterialPrefs.load();
    // 未知/损坏的值回退默认档,避免下拉框拿到表外的值
    final saved = _box.get(AppConstants.keyTtsAccent);
    _accent = AppConstants.ttsAccentOptions.containsKey(saved)
        ? saved as String
        : 'system';
    _dailyMinutes = _model.dailyMinutes?.value ?? 30;
    _maxNewWords = _model.maxNewWords?.value ?? 20;
    _band = _prefs.band;
    _selectedGoals = _initialGoals();
  }

  /// 多选目标的初始值 = `goals` 多值;老用户只有单值 `goal` 时按 label 反推
  /// (例如 "四六级(半年内)" → 勾上「四六级」),不让人升级后"目标突然消失"。
  List<String> _initialGoals() {
    final goals = List<String>.of(_model.goals);
    if (goals.isNotEmpty) return goals;
    final legacy = _model.goal?.value.trim() ?? '';
    if (legacy.isEmpty) return goals;
    for (final goal in DrillCatalog.goals) {
      if (legacy.contains(goal.label)) goals.add(goal.label);
    }
    return goals;
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  /// 可选题材 = 预设题材 ∪ 已屏蔽的题材
  /// (用户可能手填过预设表外的题材,编辑时不能让它消失)
  List<String> get _topicOptions {
    final out = <String>[...LearnerProfile.interestOptions];
    for (final t in _model.blockedTopics) {
      if (!out.contains(t)) out.add(t);
    }
    return out;
  }

  /// 可选目标 = 出题目录里的 8 个目标 ∪ 已选中的值
  List<String> get _goalOptions {
    final out = <String>[for (final g in DrillCatalog.goals) g.label];
    for (final g in _selectedGoals) {
      if (!out.contains(g)) out.add(g);
    }
    return out;
  }

  Future<void> _save() async {
    // 音色直接落 Hive(与 API 设置一致:不需要"保存"按钮也能生效)
    await _box.put(AppConstants.keyTtsAccent, _accent);
    // 难度档写回材料偏好 —— 材料中心/推荐与 AI 找材料读的是同一份字段
    await _prefs.copyWith(band: _band).save();
    // ⚠️ 目标/黑名单/配额必须真的写进学习者模型 ——
    // 之前这里只写了音色,页面上的 _model 是本地副本,退出即丢(用户以为存了)。
    // v3:`goals` 多值是唯一口径;同时把第一个写进单值 `goal` 只为兼容旧读者。
    _model = await LearnerModelStore.saveSelfReported(
      base: _model,
      goals: _selectedGoals,
      goal: _selectedGoals.isEmpty ? '' : _selectedGoals.first,
      blockedTopics: _model.blockedTopics,
      blockedKeywords: _model.blockedKeywords,
      dailyMinutes: _dailyMinutes,
      maxNewWords: _maxNewWords,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('学习偏好已保存'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context, true);
  }

  /// 危险操作:重置偏好(统一二次确认,文案写清"会丢什么/不会动什么")。
  ///
  /// 只清这三样而不是"清空所有设置":配额与音色是习惯配置,清掉会让用户的
  /// 日常节奏突然变化;生词/材料/学习记录更不该被"重置偏好"牵连。
  Future<void> _resetPreferences() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置学习偏好?'),
        content: const Text(
          '会清空:学习目标、材料难度(回到「不限」)、屏蔽题材与屏蔽关键词。\n\n'
          '不会动:每日配额、朗读音色、生词本、材料库与学习记录。\n\n'
          '重置后点「保存偏好」才会写入。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerColor(ctx),
              // 危险按钮上的文字用主色前景(白),红底白字对比足够
              foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _selectedGoals = <String>[];
      _band = MaterialBand.any;
      _model = _model.copyWith(
        blockedTopics: const <String>[],
        blockedKeywords: const <String>[],
      );
      _keywordCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已重置当前页面上的偏好,点「保存偏好」后生效'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleGoal(String goal) {
    setState(() {
      final next = List<String>.of(_selectedGoals);
      next.contains(goal) ? next.remove(goal) : next.add(goal);
      _selectedGoals = next;
    });
  }

  void _toggleTopic(String topic) {
    final list = [..._model.blockedTopics];
    list.contains(topic) ? list.remove(topic) : list.add(topic);
    setState(() => _model = _model.copyWith(blockedTopics: list));
  }

  void _addKeywords(String raw) {
    final added = splitBlockedKeywords(raw);
    if (added.isEmpty) return;
    final list = [..._model.blockedKeywords];
    for (final k in added) {
      if (!list.contains(k)) list.add(k);
    }
    _keywordCtrl.clear();
    setState(() => _model = _model.copyWith(blockedKeywords: list));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: V4JellyAppBar(
        title: '学习偏好',
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: Insets.page,
        children: [
          // ── 顶部说明:一页说清"这些偏好在哪生效" ──
          AppCard(
            variant: AppCardVariant.hero,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tune, color: theme.colorScheme.primary),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '这些偏好会影响什么',
                        style: AppFont.subheadStyle.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: Gap.xxs),
                      Text(
                        '学习助理派什么任务、材料中心找什么材料、出题难度与题材。'
                        '不改变你已经收藏的生词、材料与学习记录。',
                        style: AppFont.tagStyle.copyWith(
                          color: muted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── 01 学习目标(多选) ──
          const AppSectionHeader(indexLabel: '01', title: '学习目标(可多选)'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '目标决定"练什么、先补哪一项":备考类会多一些真题句与长难句,'
                  '兴趣类会多一些原版读物与地道表达。可以同时选多个。',
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
                ),
                const SizedBox(height: Gap.sm),
                Wrap(
                  spacing: Gap.xs,
                  runSpacing: Gap.xs,
                  children: [
                    for (final goal in _goalOptions)
                      _choiceChip(
                        label: goal,
                        selected: _selectedGoals.contains(goal),
                        onTap: () => _toggleGoal(goal),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  _selectedGoals.isEmpty
                      ? '尚未选择 —— 不选也能用,只是推荐会更泛。'
                      : '已选 ${_selectedGoals.length} 个:${_selectedGoals.join(' · ')}',
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.4),
                ),
              ],
            ),
          ),

          // ── 02 材料难度 ──
          const AppSectionHeader(indexLabel: '02', title: '材料难度'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _bandOptions.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  _optionRow(
                    title: _bandOptions[i].$1,
                    subtitle: _bandOptions[i].$2,
                    selected: _band == _bandOptions[i].$3,
                    onTap: () => setState(() => _band = _bandOptions[i].$3),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Text(
              '难度按"已知词覆盖率"分档,与材料中心的「我的需求」是同一份设置;'
              'i+1 是轻松读、i+10 是精读区、i+100 是挑战区。',
              style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
            ),
          ),

          // ── 03 每日配额 ──
          const AppSectionHeader(indexLabel: '03', title: '每日学习配额'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '复习优先:到期的词先占用时间预算,剩下的容量才用来加新词。'
                  '这两个数字决定学习助理每天给你派多少任务、复习队列放多少个新词。',
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  '每天可投入时间',
                  style: AppFont.bodyStyle.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Wrap(
                  spacing: Gap.xs,
                  runSpacing: Gap.xs,
                  children: [
                    for (final m in const [15, 30, 45, 60, 90])
                      _choiceChip(
                        label: '$m 分钟',
                        selected: _dailyMinutes == m,
                        onTap: () => setState(() => _dailyMinutes = m),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Text(
                  '每天最多加几个新词',
                  style: AppFont.bodyStyle.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Wrap(
                  spacing: Gap.xs,
                  runSpacing: Gap.xs,
                  children: [
                    for (final n in const [0, 10, 20, 30, 50])
                      _choiceChip(
                        label: n == 0 ? '只复习不加新词' : '$n 个',
                        selected: _maxNewWords == n,
                        onTap: () => setState(() => _maxNewWords = n),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  '当日到期词太多时,新词配额会自动降到 0 —— 先把欠的账还上。',
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.4),
                ),
              ],
            ),
          ),

          // ── 04 朗读音色 ──
          const AppSectionHeader(indexLabel: '04', title: '朗读音色'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (
                  var i = 0;
                  i < AppConstants.ttsAccentOptions.length;
                  i++
                ) ...[
                  if (i > 0)
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  _optionRow(
                    title: AppConstants.ttsAccentOptions.entries
                        .elementAt(i)
                        .value,
                    subtitle:
                        AppConstants.ttsAccentOptions.entries
                                .elementAt(i)
                                .key ==
                            'system'
                        ? '按手机当前语区选择,英语词条一般念美音'
                        : null,
                    selected:
                        _accent ==
                        AppConstants.ttsAccentOptions.keys.elementAt(i),
                    onTap: () => setState(
                      () => _accent = AppConstants.ttsAccentOptions.keys
                          .elementAt(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Text(
              '当前:${ttsAccentLabel(_accent)}。词条会同时显示英式/美式音标,'
              '想听另一种口音随时切换。',
              style: AppFont.tagStyle.copyWith(color: muted, height: 1.4),
            ),
          ),

          // ── 05 屏蔽题材与关键词 ──
          const AppSectionHeader(indexLabel: '05', title: '不想看的题材与关键词'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选中的题材不会出现在材料推荐/找材料里,学习助理选材也会避开。',
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
                ),
                const SizedBox(height: Gap.sm),
                Wrap(
                  spacing: Gap.xs,
                  runSpacing: Gap.xs,
                  children: _topicOptions
                      .map(
                        (t) => _dangerChip(
                          label: t,
                          selected: _model.blockedTopics.contains(t),
                          onTap: () => _toggleTopic(t),
                        ),
                      )
                      .toList(),
                ),
                if (_model.blockedTopics.isNotEmpty) ...[
                  const SizedBox(height: Gap.sm),
                  _blockedSummary(
                    theme,
                    '已屏蔽题材',
                    _model.blockedTopics,
                    onRemove: _toggleTopic,
                  ),
                ],
                const SizedBox(height: Gap.md),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: Gap.md),
                Text(
                  '屏蔽关键词',
                  style: AppFont.bodyStyle.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Gap.xxs),
                Text(
                  '逗号或空格分隔,可一次加多个。命中标题/简介/关键词的材料都会被挡掉。',
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.4),
                ),
                const SizedBox(height: Gap.xs),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keywordCtrl,
                        decoration: const InputDecoration(
                          hintText: '如:政治, 八卦, 减肥',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: _addKeywords,
                      ),
                    ),
                    const SizedBox(width: Gap.xs),
                    FilledButton.tonal(
                      onPressed: () => _addKeywords(_keywordCtrl.text),
                      child: const Text('添加'),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                if (_model.blockedKeywords.isEmpty)
                  Text(
                    '还没有屏蔽任何关键词',
                    style: AppFont.tagStyle.copyWith(color: muted, height: 1.4),
                  )
                else
                  _blockedSummary(
                    theme,
                    '已屏蔽关键词',
                    _model.blockedKeywords,
                    onRemove: (k) {
                      final list = [..._model.blockedKeywords]..remove(k);
                      setState(
                        () => _model = _model.copyWith(blockedKeywords: list),
                      );
                    },
                  ),
                const SizedBox(height: Gap.sm),
                Text(
                  '匹配口径是"包含匹配"(忽略大小写与首尾空白):屏蔽「政治」'
                  '会连「国际政治」一起挡掉。所以别填太短的常用词(如「AI」'
                  '会误伤含这三个字母的标题)。',
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.4),
                ),
              ],
            ),
          ),

          // ── 06 重置(危险操作) ──
          const AppSectionHeader(indexLabel: '06', title: '重置'),
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '重置学习偏好',
                        style: AppFont.bodyStyle.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: Gap.xxs),
                      Text(
                        '清空目标/难度/黑名单;不会动配额、音色与学习数据。',
                        style: AppFont.tagStyle.copyWith(
                          color: muted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Gap.sm),
                OutlinedButton(
                  onPressed: _resetPreferences,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.dangerColor(context),
                    side: BorderSide(color: AppTheme.dangerColor(context)),
                  ),
                  child: const Text('重置'),
                ),
              ],
            ),
          ),

          const SizedBox(height: Gap.lg),
          // 一排按钮用 Wrap:窄屏/大字号下自动换行,不溢出
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.xl,
                    vertical: 14,
                  ),
                  minimumSize: const Size(0, 48),
                ),
                child: const Text('保存偏好'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.lg,
                    vertical: 14,
                  ),
                  minimumSize: const Size(0, 48),
                ),
                child: const Text('取消'),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }

  /// 难度四档的正面文案(顺序即展示顺序)。
  ///
  /// 文案与 [MaterialBand] 的阈值同一口径(i+1:未知词 ≤2%、i+10:2%~10%、
  /// i+100:>10%),但不照抄 `material_prefs.dart` 里"硬啃区/过载"这类
  /// 负向说法 —— 难度是用户主动选的**目标**,不是"你不行"的判定。
  List<(String, String, MaterialBand)> get _bandOptions =>
      <(String, String, MaterialBand)>[
        ('i+1 · 轻松读', '每 100 词 ≤2 个生词 —— 建立信心、读得顺', MaterialBand.i1),
        ('i+10 · 精读区', '每 100 词 2~10 个生词 —— 舒适区,能够一够', MaterialBand.i10),
        ('i+100 · 挑战区', '每 100 词 10 个以上生词 —— 冲刺用,建议先预热生词', MaterialBand.i100),
        ('不限', '不按难度筛,什么都可以看看', MaterialBand.any),
      ];

  /// 一行"标题 + 说明 + 右侧选择控件"(设置项统一形态)
  Widget _optionRow({
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppFont.bodyStyle.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppFont.tagStyle.copyWith(
                        color: muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Gap.sm),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  /// 当前屏蔽项一览 + 逐条删除(不能只有"加"的入口)
  Widget _blockedSummary(
    ThemeData theme,
    String label,
    List<String> items, {
    required void Function(String) onRemove,
  }) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label(${items.length})',
          style: AppFont.tagStyle.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Gap.xs),
        Wrap(
          spacing: Gap.xs,
          runSpacing: Gap.xs,
          children: [
            for (final item in items)
              Chip(
                label: Text(
                  item,
                  style: AppFont.tagStyle.copyWith(color: muted),
                ),
                deleteIcon: const Icon(Icons.close, size: 15),
                deleteButtonTooltipMessage: '不再屏蔽',
                onDeleted: () => onRemove(item),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ],
    );
  }

  /// 普通选择胶囊(目标/配额等):选中 = 主色底 + 主色字
  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? primary.withAlpha(28)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: Radii.pillRadius,
          border: Border.all(
            color: selected
                ? primary.withAlpha(120)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          selected ? '$label ✓' : label,
          style: AppFont.tagStyle.copyWith(
            color: selected ? primary : theme.colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// 黑名单胶囊:选中 = 危险色(与"想看的目标"在视觉上区分开 —— 两者语义相反)
  Widget _dangerChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final danger = AppTheme.dangerColor(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? danger.withAlpha(28)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: Radii.pillRadius,
          border: Border.all(
            color: selected
                ? danger.withAlpha(120)
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          selected ? '$label ✕' : label,
          style: AppFont.tagStyle.copyWith(
            color: selected ? danger : muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 把用户输入的一行文本切成屏蔽词(纯函数,可单测)。
///
/// 分隔符:中英文逗号、分号、顿号、换行、制表符、空格 —— 用户怎么写都得认,
/// 否则"政治 八卦"会被当成一个词,屏蔽失效。
/// 归一化:去首尾空白 + 去重(保留首次出现顺序,便于界面稳定)。
List<String> splitBlockedKeywords(String raw) {
  final out = <String>[];
  for (final part in raw.split(RegExp(r'[,，;；、\s]+'))) {
    final t = part.trim();
    if (t.isEmpty) continue;
    if (!out.contains(t)) out.add(t);
  }
  return out;
}
