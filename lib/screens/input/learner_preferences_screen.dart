import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../config/constants.dart';
import '../../models/learner_model.dart';
import '../../models/material_recommendation.dart';
import '../../services/learner_model_store.dart';
import '../../services/tts_accent.dart';

/// 学习偏好(v2.0,「我的 → 学习偏好」进入)
///
/// 一页管两件事(都属于"用户主动表达偏好",不该分散到 API 设置里):
/// 1. **朗读音色** —— 跟随系统 / 英式 / 美式(存 Hive,词条朗读即生效)
/// 2. **不想看的题材与关键词** —— 材料推荐与导师选材一律遵守
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
  final _keywordCtrl = TextEditingController();

  /// 朗读音色档位:'system' | 'uk' | 'us'
  String _accent = 'system';

  /// 每日配额(来自学习者模型;缺省与 ReviewQueue 的默认值一致)
  int _dailyMinutes = 30;
  int _maxNewWords = 20;

  @override
  void initState() {
    super.initState();
    _box = Hive.box(AppConstants.hiveBoxSettings);
    _model = LearnerModelStore.load();
    // 未知/损坏的值回退默认档,避免下拉框拿到表外的值
    final saved = _box.get(AppConstants.keyTtsAccent);
    _accent = AppConstants.ttsAccentOptions.containsKey(saved)
        ? saved as String
        : 'system';
    _dailyMinutes = _model.dailyMinutes?.value ?? 30;
    _maxNewWords = _model.maxNewWords?.value ?? 20;
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

  Future<void> _save() async {
    // 音色直接落 Hive(与 API 设置一致:不需要"保存"按钮也能生效)
    await _box.put(AppConstants.keyTtsAccent, _accent);
    // ⚠️ 题材/关键词黑名单必须真的写进学习者模型 ——
    // 之前这里只写了音色,页面上的 _model 是本地副本,退出即丢(用户以为存了)
    _model = await LearnerModelStore.saveSelfReported(
      base: _model,
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
      appBar: AppBar(
        title: const Text('学习偏好'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── 朗读音色 ──
          _sectionTitle(theme, '朗读音色'),
          Text(
            '当前:${ttsAccentLabel(_accent)}。词条与小喇叭按钮按这个音色朗读;'
            '词条会同时显示英式/美式音标,想听另一种口音随时切换。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 8),
          // Flutter 3.32 起 RadioListTile 的 groupValue/onChanged 已废弃,
          // 用 RadioGroup 祖先统一管选中值(否则 analyze 会报 deprecated)
          RadioGroup<String>(
            groupValue: _accent,
            onChanged: (v) => setState(() => _accent = v ?? 'system'),
            child: Column(
              children: [
                for (final e in AppConstants.ttsAccentOptions.entries)
                  RadioListTile<String>(
                    value: e.key,
                    title: Text(e.value, style: const TextStyle(fontSize: 14)),
                    subtitle: e.key == 'system'
                        ? Text('按手机当前语区选择,英语词条一般念美音',
                            style: TextStyle(fontSize: 11, color: muted))
                        : null,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),

          const Divider(height: 32),

          // ── 每日配额(v2.1:复习优先的时间预算) ──
          _sectionTitle(theme, '每日学习配额'),
          Text(
            '复习优先:到期的词先占用时间预算,剩下的容量才用来加新词。'
            '这两个数字决定导师每天给你派多少任务、复习队列放多少个新词。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 10),
          Text('每天可投入时间', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const [15, 30, 45, 60, 90])
                _chip(
                  theme,
                  label: '$m 分钟',
                  selected: _dailyMinutes == m,
                  onTap: () => setState(() => _dailyMinutes = m),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('每天最多加几个新词', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in const [0, 10, 20, 30, 50])
                _chip(
                  theme,
                  label: n == 0 ? '只复习不加新词' : '$n 个',
                  selected: _maxNewWords == n,
                  onTap: () => setState(() => _maxNewWords = n),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '当日到期词太多时,新词配额会自动降到 0 —— 先把欠的账还上。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),

          const Divider(height: 32),

          // ── 不想看的题材 ──
          _sectionTitle(theme, '不想看的题材(可多选)'),
          Text(
            '选中的题材不会出现在材料推荐里,导师选材也会避开。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _topicOptions.map((t) {
              final selected = _model.blockedTopics.contains(t);
              return _chip(
                theme,
                label: t,
                selected: selected,
                onTap: () => _toggleTopic(t),
              );
            }).toList(),
          ),
          if (_model.blockedTopics.isNotEmpty) ...[
            const SizedBox(height: 12),
            _blockedSummary(theme, '已屏蔽题材', _model.blockedTopics,
                onRemove: _toggleTopic),
          ],

          const SizedBox(height: 20),

          // ── 屏蔽关键词 ──
          _sectionTitle(theme, '屏蔽关键词'),
          Text(
            '逗号或空格分隔,可一次加多个。命中标题/简介/关键词的材料都会被挡掉。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 8),
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
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _addKeywords(_keywordCtrl.text),
                child: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_model.blockedKeywords.isEmpty)
            Text('还没有屏蔽任何关键词',
                style: theme.textTheme.bodySmall?.copyWith(color: muted))
          else
            _blockedSummary(
              theme,
              '已屏蔽关键词',
              _model.blockedKeywords,
              onRemove: (k) {
                final list = [..._model.blockedKeywords]..remove(k);
                setState(() => _model = _model.copyWith(blockedKeywords: list));
              },
            ),

          const SizedBox(height: 20),
          Text(
            '匹配口径是"包含匹配"(忽略大小写与首尾空白):屏蔽「政治」'
            '会连「国际政治」一起挡掉。所以别填太短的常用词(如「AI」'
            '会误伤含这三个字母的标题)。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('保存偏好'),
            ),
          ),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label(${items.length})',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              Chip(
                label: Text(item, style: const TextStyle(fontSize: 12)),
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

  Widget _sectionTitle(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      );

  Widget _chip(
    ThemeData theme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withAlpha(28)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          // 屏蔽项用错误色描边,和"偏好题材"的选中态在视觉上区分开:
          // 这两个列表语义相反(一个是要看的,一个是不看的)
          border: Border.all(
            color: selected ? Colors.red[400]! : Colors.grey[400]!,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Text(
          selected ? '$label ✕' : label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.red[700] : Colors.grey[850],
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
