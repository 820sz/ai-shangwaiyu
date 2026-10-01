import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/design_tokens.dart';
import '../models/learner_model.dart';
import '../services/learner_context.dart';
import '../services/learner_model_store.dart';
import '../services/profile_card.dart';

/// 「我的」顶部个性化名片(v2.8 初版,v2.9 按用户反馈重做)。
///
/// v2.9 用户反馈原话:"**'我的'的用户名片没法编辑调整背景图,头像也是。
/// 没法自定义用户名字。个性卡片整体的 ui 风要再精美优化一些。**"
///
/// 三处根因 + 修法:
/// 1. **没法自定义名字** —— v2.8 压根没有"昵称"这个字段 → 现在有,而且名字是卡上最大的字;
/// 2. **没法调整背景图/头像** —— 上一版编辑入口只是卡片右上角一个灰色小铅笔,
///    而且背景只有 6 套固定渐变、不能放图 → 现在**整张卡可点**、
///    卡片右下角有醒目的「编辑名片」按钮,背景**既可选渐变也可从相册选图**;
/// 3. **不够精美** —— 重排层级:头像带双环描边 → 昵称(大字)→ 签名(次级)→
///    数据行(三格,带细分隔线);背景图自动叠一层暗色渐变保证白字可读。
class ProfileNameCard extends StatefulWidget {
  final int? vocabCount;

  const ProfileNameCard({super.key, this.vocabCount});

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
    final nameCtrl = TextEditingController(text: _card.nickname);
    final signCtrl = TextEditingController(text: _card.signature);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final theme = Theme.of(ctx);
          final muted = theme.colorScheme.onSurfaceVariant;
          Future<void> pickBackground() async {
            try {
              final picked = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 1600,
                imageQuality: 88,
              );
              if (picked == null) return;
              final path =
                  await ProfileCardSettings.persistImage(File(picked.path),
                      prefix: 'card_bg');
              if (path == null) return;
              setSheet(() => draft = draft.copyWith(backgroundPath: path));
            } catch (e) {
              debugPrint('选背景图失败: $e');
            }
          }

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
                    // 顶部**实时预览**:改什么立刻看到,不用"保存了才知道啥样"
                    Center(
                      child: ClipRRect(
                        borderRadius: Radii.cardRadius,
                        child: SizedBox(
                          width: double.infinity,
                          height: 104,
                          child: _CardBackdrop(
                            settings: draft,
                            child: Padding(
                              padding: const EdgeInsets.all(Gap.sm),
                              child: Row(
                                children: [
                                  _avatar(draft, 46, border: Colors.white),
                                  const SizedBox(width: Gap.sm),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          draft.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (draft.signature.trim().isNotEmpty)
                                          Text(
                                            draft.signature.trim(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white.withAlpha(215),
                                              fontSize: 11.5,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    Text('名片预览',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: muted)),
                    const SizedBox(height: Gap.sm),
                    // ① 昵称
                    TextField(
                      controller: nameCtrl,
                      maxLength: 12,
                      decoration: const InputDecoration(
                        labelText: '你的名字 / 昵称',
                        hintText: '如:小樱、Aki、每天读一篇',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          setSheet(() => draft = draft.copyWith(nickname: v)),
                    ),
                    const SizedBox(height: Gap.xs),
                    // ② 签名
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
                    const SizedBox(height: Gap.sm),
                    // ③ 头像
                    Text('头像',
                        style: TextStyle(fontSize: 12.5, color: muted)),
                    const SizedBox(height: Gap.xs),
                    Row(
                      children: [
                        _avatar(draft, 52, border: theme.colorScheme.outlineVariant),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Wrap(
                            spacing: Gap.xs,
                            runSpacing: Gap.xs,
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
                                        .persistImage(File(picked.path),
                                            prefix: 'avatar');
                                    if (path == null) return;
                                    setSheet(() =>
                                        draft = draft.copyWith(avatarPath: path));
                                  } catch (e) {
                                    debugPrint('选头像失败: $e');
                                  }
                                },
                                icon: const Icon(Icons.photo_library_outlined,
                                    size: 16),
                                label: const Text('从相册选'),
                              ),
                              if ((draft.avatarPath ?? '').isNotEmpty)
                                TextButton(
                                  onPressed: () => setSheet(() =>
                                      draft = draft.copyWith(avatarPath: null)),
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
                            onSelected: (_) => setSheet(() => draft =
                                draft.copyWith(
                                    avatarPath: null, avatarText: t)),
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.md),
                    // ④ 背景:渐变 or 自选图
                    Text('名片背景',
                        style: TextStyle(fontSize: 12.5, color: muted)),
                    const SizedBox(height: Gap.xs),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final b in ProfileCardSettings.backgrounds)
                          InkWell(
                            borderRadius: Radii.controlRadius,
                            onTap: () => setSheet(() => draft =
                                draft.copyWith(
                                    backgroundId: '${b['id']}',
                                    backgroundPath: null)),
                            child: Container(
                              width: 62,
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
                                  color: (draft.backgroundPath ?? '').isEmpty &&
                                          draft.backgroundId == b['id']
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text('${b['label']}',
                                  style: const TextStyle(
                                      fontSize: 10.5, color: Colors.white)),
                            ),
                          ),
                        // 自选背景图
                        InkWell(
                          borderRadius: Radii.controlRadius,
                          onTap: pickBackground,
                          child: Container(
                            width: 62,
                            height: 40,
                            decoration: BoxDecoration(
                              color:
                                  theme.colorScheme.surfaceContainerHighest,
                              borderRadius: Radii.controlRadius,
                              border: Border.all(
                                color: (draft.backgroundPath ?? '').isNotEmpty
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                                width: (draft.backgroundPath ?? '').isNotEmpty
                                    ? 2
                                    : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 15, color: muted),
                                Text('选图',
                                    style: TextStyle(
                                        fontSize: 9.5, color: muted)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if ((draft.backgroundPath ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '已用自选背景图(会自动压暗,保证字看得清)',
                                style: TextStyle(fontSize: 11, color: muted),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setSheet(() =>
                                  draft = draft.copyWith(backgroundPath: null)),
                              child: const Text('换回渐变'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: Gap.md),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('保存名片'),
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
    nameCtrl.dispose();
    signCtrl.dispose();
    if (saved != true || !mounted) return;
    setState(() => _card = draft);
    await _card.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('名片已更新'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 头像(有图用图;没图用文字/emoji)
  Widget _avatar(ProfileCardSettings s, double size, {required Color border}) {
    final hasImg = (s.avatarPath ?? '').isNotEmpty &&
        File(s.avatarPath!).existsSync();
    final text = s.avatarText.isNotEmpty
        ? s.avatarText
        : (s.nickname.isNotEmpty ? s.nickname.characters.first : '我');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(52),
        shape: BoxShape.circle,
        border: Border.all(color: border.withAlpha(160), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(28),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
    final baseline = LearnerContext.describeBaseline(_model);
    final daily = _model.dailyMinutes?.value ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: ClipRRect(
        borderRadius: Radii.cardRadius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            // 整卡可点 = 编辑名片(用户反馈"没法编辑")
            onTap: _edit,
            child: _CardBackdrop(
              settings: _card,
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _avatar(_card, 64, border: Colors.white),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _card.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _card.signature.trim().isEmpty
                                    ? '点这张卡,给自己配名字、头像和背景'
                                    : _card.signature.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withAlpha(228),
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),
                    // 数据行:三格 + 细分隔线(比"一串小字"清楚)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(26),
                        borderRadius: Radii.controlRadius,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _stat('生词', '${widget.vocabCount ?? 0}'),
                          ),
                          _statDivider(),
                          Expanded(child: _stat('水平', baseline)),
                          _statDivider(),
                          Expanded(
                            child: _stat('每天', daily > 0 ? '$daily 分' : '—'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Gap.sm),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (baseline.isEmpty)
                                ? '把名字、头像、背景换成你的'
                                : '点这里改名字 / 头像 / 背景 / 签名',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.white.withAlpha(190),
                            ),
                          ),
                        ),
                        // 醒目的编辑按钮:上一版只有一个灰色小铅笔,用户根本没找到
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(46),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withAlpha(120)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_outlined,
                                  size: 13, color: Colors.white),
                              SizedBox(width: 4),
                              Text('编辑名片',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 22,
        color: Colors.white.withAlpha(56),
      );

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(
          value.isEmpty ? '—' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(fontSize: 10.5, color: Colors.white.withAlpha(200)),
        ),
      ],
    );
  }
}

/// 名片背景:自选图(压暗)→ 渐变的回落顺序
class _CardBackdrop extends StatelessWidget {
  final ProfileCardSettings settings;
  final Widget child;

  const _CardBackdrop({required this.settings, required this.child});

  @override
  Widget build(BuildContext context) {
    final bgPath = settings.backgroundPath ?? '';
    final hasImg = bgPath.isNotEmpty && File(bgPath).existsSync();
    final bg = ProfileCardSettings.backgroundOf(settings.backgroundId);
    final colors = [
      Color((bg['colors'] as List)[0] as int),
      Color((bg['colors'] as List)[1] as int),
    ];
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: hasImg
              ? Image.file(File(bgPath), fit: BoxFit.cover)
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                  ),
                ),
        ),
        // 图上的压暗层:满屏图直接铺白字会看不清(这是上一版只给渐变的原因,
        // 现在给自选图,就用这层保证对比度)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: hasImg
                    ? [Colors.black.withAlpha(130), Colors.black.withAlpha(90)]
                    : colors.map((c) => c.withAlpha(0)).toList(),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
