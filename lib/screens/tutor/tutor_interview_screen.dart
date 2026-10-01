import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../models/learner_model.dart';
import '../../services/database.dart';
import '../../services/learner_model_store.dart';

/// 助理的**先访谈**(v2.8,用户第 5(3) 条)。
///
/// 用户原话:"'今天还有几件事'这种建议毫无参考价值 —— 学习助理的定位必须由 AI 来对话:
/// 询问、分析用户的水平、偏好、目标需求、其他情况,从而定制真正具有指导性的建议 ——
/// 就像 agent 做任务时给 user 提问选项一样 —— 这才是接入 ai 的初心。"
///
/// 所以这里不是"让用户填一张表单",而是**一步一步问 + 每步给可点的选项**:
/// - 每屏一个问题,选项是**大按钮**(不用打字,想补话也有输入框);
/// - 一共 6 步,一分钟能答完;
/// - 答完立刻落进学习者模型(goal / dailyMinutes / interests)+ 助理长期记忆
///   (tutor_memory),于是「学习现状分析」与「学习任务」两个方向**用得上**这些答案
///   —— 这正是用户说的"第一个功能和第四个功能会影响二三个功能"。
class TutorInterviewScreen extends StatefulWidget {
  const TutorInterviewScreen({super.key});

  @override
  State<TutorInterviewScreen> createState() => _TutorInterviewScreenState();
}

/// 一步访谈:一个问题 + 一组可点选项
class _Step {
  final String question;
  final String why;
  final List<String> options;
  final bool multi;

  const _Step({
    required this.question,
    required this.why,
    required this.options,
    this.multi = false,
  });
}

class _TutorInterviewScreenState extends State<TutorInterviewScreen> {
  static const List<_Step> _steps = [
    _Step(
      question: '你学英语,最主要想用它做什么?',
      why: '这决定我给你排什么材料、练什么题型',
      options: ['四六级', '考研', '雅思/托福', '出国生活', '工作/学术', '兴趣阅读', '看剧看视频'],
    ),
    _Step(
      question: '大概什么时候要用上?',
      why: '有截止日期才排得出节奏',
      options: ['3 个月内', '半年内', '一年内', '没有期限,慢慢来'],
    ),
    _Step(
      question: '每天大概能拿出多少时间?',
      why: '少而稳比多而断更有效',
      options: ['10 分钟以内', '15 分钟左右', '30 分钟左右', '1 小时以上'],
    ),
    _Step(
      question: '现在读英文材料,你的感觉是?',
      why: '我先按你的自评起步,后面用词汇量测试校准',
      options: ['基本读不懂', '能读简单的,生词很多', '大意能懂,细节吃力', '读得比较顺,想再快点'],
    ),
    _Step(
      question: '你想读什么题材?(可多选)',
      why: '题材决定了材料库给你推什么',
      options: ['科学与技术', '商业与政治', '健康与生活', '文化与艺术', '旅行与体验', '小说故事'],
      multi: true,
    ),
    _Step(
      question: '有没有你不想看的内容?',
      why: '我会让 AI 避开这些题材',
      options: ['太学术的', '政治新闻', '恐怖/暴力', '恋爱八卦', '体育'],
      multi: true,
    ),
  ];

  int _index = 0;
  final List<Set<String>> _picked = List.generate(_steps.length, (_) => <String>{});
  final TextEditingController _freeCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _freeCtrl.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _steps.length - 1;

  void _toggle(String option) {
    final step = _steps[_index];
    setState(() {
      final set = _picked[_index];
      if (step.multi) {
        set.contains(option) ? set.remove(option) : set.add(option);
      } else {
        set
          ..clear()
          ..add(option);
      }
    });
  }

  Future<void> _next() async {
    // 非必答:但至少让人看到"可以跳过"
    if (!_isLast) {
      setState(() {
        _index++;
        _freeCtrl.clear();
      });
      return;
    }
    await _finish();
  }

  /// 收尾:写进学习者模型 + 助理长期记忆,然后给一句"我记住了什么"
  Future<void> _finish() async {
    setState(() => _saving = true);
    final model = LearnerModelStore.load();
    final now = DateTime.now();

    String answerAt(int i) => _picked[i].join('、');

    // ① 目标:直接写 goal(带来源=自评)
    final goal = answerAt(0);
    final deadline = answerAt(1);
    final minutes = _minutesOf(answerAt(2));
    final levelSelf = answerAt(3);
    final interests = _picked[4].toList();
    final blocked = _picked[5].toList();

    var next = model.copyWith(
      goal: goal.isEmpty
          ? null
          : ProfileField<String>(
              value: deadline.isEmpty ? goal : '$goal($deadline)',
              source: ProfileSource.self,
              confidence: 0.9,
              updatedAt: now,
            ),
      dailyMinutes: minutes == null
          ? null
          : ProfileField<int>(
              value: minutes,
              source: ProfileSource.self,
              confidence: 0.9,
              updatedAt: now,
            ),
      interests: interests.isEmpty
          ? null
          : ProfileField<List<String>>(
              value: interests,
              source: ProfileSource.self,
              confidence: 0.9,
              updatedAt: now,
            ),
      blockedTopics: blocked,
      extras: {
        ...model.extras,
        'interview_level_self': levelSelf,
        'interview_at': now.toIso8601String(),
      },
    );
    if (goal.isEmpty) next = next.copyWith(clearGoal: true);
    if (minutes == null) next = next.copyWith(clearDailyMinutes: true);
    if (interests.isEmpty) next = next.copyWith(clearInterests: true);
    await LearnerModelStore.save(next);

    // ② 助理长期记忆:二、三两个方向(分析与任务)要读它
    final lines = <String>[
      if (goal.isNotEmpty) '学习目的:$goal${deadline.isEmpty ? '' : ' · $deadline'}',
      if (minutes != null) '每天可投入约 $minutes 分钟',
      if (levelSelf.isNotEmpty) '自评水平:$levelSelf',
      if (interests.isNotEmpty) '偏好题材:${interests.join('、')}',
      if (blocked.isNotEmpty) '不想看:${blocked.join('、')}',
    ];
    for (final l in lines) {
      await DatabaseService.addTutorMemory(kind: 'preference', text: l);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('记住了'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('这些会用在「学习现状分析」和「学习任务」里:',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: Gap.xs),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('· $l', style: const TextStyle(fontSize: 13)),
              ),
            if (lines.isEmpty)
              const Text('这次没选任何选项 —— 随时可以再点「先聊聊」重来',
                  style: TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  int? _minutesOf(String label) {
    if (label.contains('10')) return 10;
    if (label.contains('15')) return 15;
    if (label.contains('30')) return 30;
    if (label.contains('1 小时')) return 60;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final step = _steps[_index];
    return Scaffold(
      appBar: AppBar(
        title: const Text('先聊聊你的情况'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('跳过'),
          ),
        ],
      ),
      body: ListView(
        padding: Insets.page,
        children: [
          // 进度:第几问 / 共几问(让用户知道"还剩几屏")
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / _steps.length,
                    minHeight: 5,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: Gap.xs),
              Text('${_index + 1}/${_steps.length}',
                  style: TextStyle(fontSize: 11, color: muted)),
            ],
          ),
          const SizedBox(height: Gap.lg),
          Text(
            step.question,
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 20,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Gap.xs),
          Text('为什么问:${step.why}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: muted, height: 1.4)),
          const SizedBox(height: Gap.md),
          // 选项按钮(用户点选即可,不用打字 —— 这就是"给 user 提问选项")
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              for (final o in step.options)
                _optionChip(o, selected: _picked[_index].contains(o)),
            ],
          ),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _freeCtrl,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '想补充点什么?(可留空)',
              hintText: '如:主要想练听力,读也想练',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: Gap.lg),
          Row(
            children: [
              if (_index > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _index--),
                    child: const Text('上一题'),
                  ),
                ),
              if (_index > 0) const SizedBox(width: Gap.xs),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _next,
                  icon: Icon(_isLast ? Icons.check : Icons.arrow_forward, size: 18),
                  label: Text(_saving ? '保存中…' : (_isLast ? '完成' : '下一题')),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () {
                          // "这题先跳过":不选也能往下走
                          if (_isLast) {
                            _finish();
                          } else {
                            setState(() => _index++);
                          }
                        },
                  child: const Text('这题先跳过'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _optionChip(String label, {required bool selected}) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: Radii.controlRadius,
      onTap: () => _toggle(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withAlpha(26)
              : theme.colorScheme.surface,
          borderRadius: Radii.controlRadius,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_circle,
                  size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
