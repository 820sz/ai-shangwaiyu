import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../config/v4_theme.dart';

/// AI 改写前的两个可选项（用户 2026-11-08 要求）：
/// - 字数：不限（推荐，优先保证覆盖内容）/ 约 400 / 约 700 / 约 1000；
/// - 难度：贴近原材料难度（默认）/ 更简单 / 更难。
class AiRewriteOptions {
  /// null = 不限字数
  final int? wordLimit;

  /// 'same' | 'easier' | 'harder'
  final String difficultyMode;

  const AiRewriteOptions({
    this.wordLimit,
    this.difficultyMode = 'same',
  });
}

/// 弹出「改写选项」底部弹层；用户取消返回 null。
Future<AiRewriteOptions?> showAiRewriteOptions(BuildContext context) {
  return showModalBottomSheet<AiRewriteOptions>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _AiRewriteOptionsSheet(),
  );
}

class _AiRewriteOptionsSheet extends StatefulWidget {
  const _AiRewriteOptionsSheet();

  @override
  State<_AiRewriteOptionsSheet> createState() => _AiRewriteOptionsSheetState();
}

class _AiRewriteOptionsSheetState extends State<_AiRewriteOptionsSheet> {
  int? _wordLimit; // null = 不限
  String _difficulty = 'same';

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    // 选项较多 + 系统大字号时，内容会超过一屏：限制最大高度并允许滚动，
    // 保证底部「开始生成」按钮能滚到、点得到（2026-11-08 真机反馈）。
    final double maxH = MediaQuery.sizeOf(context).height * 0.86;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: skin.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'AI 改写前，确认两个选项',
            style: AppFont.subheadStyle.copyWith(
              color: skin.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '默认不限字数、贴近原材料难度，并优先保证覆盖材料主要内容。',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: skin.inkSoft),
          ),
          const SizedBox(height: Gap.md),
          Text('字数要求',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: skin.ink)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _choice(
                label: '不限（推荐，优先覆盖内容）',
                selected: _wordLimit == null,
                onTap: () => setState(() => _wordLimit = null),
              ),
              for (final n in const <int>[400, 700, 1000])
                _choice(
                  label: '约 $n 词',
                  selected: _wordLimit == n,
                  onTap: () => setState(() => _wordLimit = n),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Text('难度要求',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: skin.ink)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _choice(
                label: '贴近原材料难度',
                selected: _difficulty == 'same',
                onTap: () => setState(() => _difficulty = 'same'),
              ),
              _choice(
                label: '更简单（高频词/短句）',
                selected: _difficulty == 'easier',
                onTap: () => setState(() => _difficulty = 'easier'),
              ),
              _choice(
                label: '更难（丰富词汇/复杂句）',
                selected: _difficulty == 'harder',
                onTap: () => setState(() => _difficulty = 'harder'),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(
                AiRewriteOptions(
                  wordLimit: _wordLimit,
                  difficultyMode: _difficulty,
                ),
              ),
              child: const Text('开始生成 AI 改写学习版（非原文）'),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final skin = V4Skin.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? skin.accent.withValues(alpha: 0.12)
              : skin.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? skin.accent : skin.hairline,
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? skin.accent : skin.inkSoft,
          ),
        ),
      ),
    );
  }
}
