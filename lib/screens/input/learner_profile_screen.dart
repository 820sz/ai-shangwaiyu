import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/material_recommendation.dart';
import '../../providers/vocab_provider.dart';
import '../../services/learner_profile_store.dart';

/// 学习画像编辑页(v1.8.0):AI 推荐的个性化依据,填完即保存,可随时修改。
class LearnerProfileScreen extends StatefulWidget {
  const LearnerProfileScreen({super.key});

  @override
  State<LearnerProfileScreen> createState() => _LearnerProfileScreenState();
}

class _LearnerProfileScreenState extends State<LearnerProfileScreen> {
  late LearnerProfile _profile;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _profile = LearnerProfileStore.load();
    _noteCtrl.text = _profile.note;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 用词库数据一键推断(词汇量→水平,来源→兴趣题材)
  void _suggest() {
    final vocab = context.read<VocabProvider>().vocabularies;
    final suggested = LearnerProfileStore.suggestFromVocab(
      vocab,
      base: _profile,
    );
    setState(() => _profile = suggested);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已根据你的词汇数据填入建议，可再修改'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    final profile = _profile.copyWith(
      note: _noteCtrl.text.trim(),
      confirmed: true,
    );
    await LearnerProfileStore.save(profile);
    if (mounted) {
      Navigator.pop(context, profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习画像'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '填得越准，推荐越贴合',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _suggest,
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('按词汇推断'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _sectionTitle(theme, '英语水平'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LearnerProfile.levelOptions
                .map(
                  (l) => _chip(
                    theme,
                    label: l,
                    selected: _profile.level == l,
                    onTap: () => setState(
                      () => _profile = _profile.copyWith(level: l),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          _sectionTitle(theme, '学习目的'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LearnerProfile.goalOptions
                .map(
                  (g) => _chip(
                    theme,
                    label: g,
                    selected: _profile.goal == g,
                    onTap: () => setState(
                      () => _profile = _profile.copyWith(goal: g),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          _sectionTitle(theme, '偏好题材（可多选）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LearnerProfile.interestOptions.map((i) {
              final selected = _profile.interests.contains(i);
              return _chip(
                theme,
                label: i,
                selected: selected,
                onTap: () {
                  final list = [..._profile.interests];
                  selected ? list.remove(i) : list.add(i);
                  setState(
                    () => _profile = _profile.copyWith(interests: list),
                  );
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _sectionTitle(theme, '补充说明（可选）'),
          const SizedBox(height: 6),
          TextField(
            controller: _noteCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '如：下个月考雅思，写作最弱',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('保存画像'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
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
    );
  }
}
