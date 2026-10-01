import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/design_tokens.dart';
import '../models/learner_model.dart';
import '../services/learner_context.dart';
import '../services/learner_model_store.dart';
import '../services/profile_card.dart';

/// 「我的」顶部个性化名片(v2.8,用户第 9 条)。
///
/// 用户原话:"'我的'界面,在顶部增加个性化名片 —— 头像自定义、名片背景自定义、
/// 签名自定义、词汇量展示"。
///
/// 四样东西都在这张卡上:
/// - **头像**:相册选图(复制进 App 目录)或自带文字/emoji 头像;
/// - **背景**:6 套挑过的渐变(任意取色容易做出看不清字的组合);
/// - **签名**:一句话,空的时候给一句引导;
/// - **词汇量**:直接读学习者模型(与「学习」组里的基线是同一份数据,不重复算)。
class ProfileNameCard extends StatefulWidget {
  /// 大数字(生词数)等统计由外部传入,避免这里再查一次库
  final int? vocabCount;
  final int? masteredCount;

  const ProfileNameCard({super.key, this.vocabCount, this.masteredCount});

  @override
  State<ProfileNameCard> createState() => _ProfileNameCardState();
}

class _ProfileNameCardState extends State<ProfileNameCard> {
  ProfileCardSettings _card = ProfileCardSettings.defaults;
  LearnerModel _model = LearnerModel();

  @override
  void initState() {
    super.initState();
    _card = ProfileCardSettings.load();
    _model = LearnerModelStore.load();
  }

  Future<void> _edit() async {
    var draft = _card;
    final signCtrl = TextEditingController(text: _card.signature);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Gap.md,
                0,
                Gap.md,
                Gap.md + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('个性化名片',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: Gap.md),
                    // ① 头像
                    Text('头像',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: Gap.xs),
                    Row(
                      children: [
                        _avatarPreview(draft, 56),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    final picked = await ImagePicker().pickImage(
                                      source: ImageSource.gallery,
                                      maxWidth: 600,
                                      imageQuality: 90,
                                    );
                                    if (picked == null) return;
                                    final path = await ProfileCardSettings
                                        .persistAvatar(File(picked.path));
                                    if (path == null) return;
                                    setSheet(() =>
                                        draft = draft.copyWith(avatarPath: path));
                                  } catch (e) {
                                    debugPrint('选头像失败: $e');
                                  }
                                },
                                icon: const Icon(Icons.photo_library_outlined,
                                    size: 16),
                                label: const Text('从相册选一张'),
                              ),
                              if ((draft.avatarPath ?? '').isNotEmpty)
                                TextButton(
                                  onPressed: () => setSheet(
                                      () => draft = draft.copyWith(avatarPath: null)),
                                  child: const Text('用文字头像'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final t in ProfileCardSettings.avatarTexts)
                          ChoiceChip(
                            label: Text(t),
                            selected: (draft.avatarPath ?? '').isEmpty &&
                                draft.avatarText == t,
                            onSelected: (_) => setSheet(() => draft = draft.copyWith(
                                  avatarPath: null,
                                  avatarText: t,
                                )),
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.md),
                    // ② 背景
                    Text('名片背景',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final b in ProfileCardSettings.backgrounds)
                          InkWell(
                            borderRadius: Radii.controlRadius,
                            onTap: () => setSheet(() => draft = draft.copyWith(
                                backgroundId: '${b['id']}')),
                            child: Container(
                              width: 64,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color((b['colors'] as List)[0] as int),
                                    Color((b['colors'] as List)[1] as int),
                                  ],
                                ),
                                borderRadius: Radii.controlRadius,
                                border: Border.all(
                                  color: draft.backgroundId == b['id']
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${b['label']}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.md),
                    // ③ 签名
                    TextField(
                      controller: signCtrl,
                      maxLines: 2,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: '个性签名',
                        hintText: '如:每天 20 分钟,读原著',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          setSheet(() => draft = draft.copyWith(signature: v)),
                    ),
                    const SizedBox(height: Gap.md),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    signCtrl.dispose();
    if (saved != true || !mounted) return;
    setState(() => _card = draft);
    await _card.save();
  }

  Widget _avatarPreview(ProfileCardSettings s, double size) {
    final hasImg = (s.avatarPath ?? '').isNotEmpty &&
        File(s.avatarPath!).existsSync();
    final text = s.avatarText.isNotEmpty
        ? s.avatarText
        : (s.signature.isNotEmpty ? s.signature.characters.first : '我');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(46),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withAlpha(120), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: hasImg
          ? Image.file(File(s.avatarPath!),
              width: size, height: size, fit: BoxFit.cover)
          : Text(
              text,
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = ProfileCardSettings.backgroundOf(_card.backgroundId);
    final colors = [
      Color((bg['colors'] as List)[0] as int),
      Color((bg['colors'] as List)[1] as int),
    ];
    final baseline = LearnerContext.describeBaseline(_model);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: ClipRRect(
        borderRadius: Radii.cardRadius,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
              ),
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatarPreview(_card, 62),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _card.signature.trim().isEmpty
                                    ? '点右上角，给自己配一张名片'
                                    : _card.signature.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.3,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '编辑名片',
                              onPressed: _edit,
                              icon: const Icon(Icons.edit_outlined,
                                  size: 18, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          baseline,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            color: Colors.white.withAlpha(220),
                          ),
                        ),
                        const SizedBox(height: Gap.xs),
                        // 词汇量展示(用户点名要有)
                        Row(
                          children: [
                            _stat('生词', '${widget.vocabCount ?? 0}'),
                            const SizedBox(width: Gap.sm),
                            _stat('已掌握', '${widget.masteredCount ?? 0}'),
                            const SizedBox(width: Gap.sm),
                            _stat(
                              '每天',
                              (_model.dailyMinutes?.value ?? 0) > 0
                                  ? '${_model.dailyMinutes!.value} 分钟'
                                  : '—',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(210)),
        ),
      ],
    );
  }
}
