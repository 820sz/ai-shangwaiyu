import 'package:flutter/material.dart';

import '../../../config/design_tokens.dart';
import '../../../config/theme.dart';
import '../../../services/material_library.dart';

/// 「读前卡」:入库/导入后先告诉用户"这份材料对你是什么难度",再决定读不读(v2.7 抽出)。
///
/// 为什么抽成公共件:材料中心、文件导入、图片提取、链接导入**四条路径**都会入库,
/// 每一处都该有同一张读前卡(v2.6 之前只有材料中心里有,导入的材料直接就进阅读器了)。
/// 返回 true = 用户点「开始读」。
Future<bool> showMaterialPreview(
  BuildContext context,
  IngestedMaterial ingested,
) async {
  final a = ingested.analysis;
  final theme = Theme.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ingested.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _kv(ctx, '篇幅', '${a.wordCount} 词 · 约 ${a.estMinutes} 分钟'),
            _kv(ctx, '难度估计', '${a.cefr} · ${a.hint}'),
            _kv(
              ctx,
              '已知词覆盖率',
              '${(a.knownTokenRatio * 100).toStringAsFixed(1)}%'
                  '(词形 ${(a.coverage * 100).toStringAsFixed(0)}%)',
            ),
            _kv(ctx, '生词密度', '每 100 词约 ${a.newWordDensity.toStringAsFixed(1)} 个'),
            if (a.topNewWords.isNotEmpty)
              _kv(ctx, '先认这几个词', a.topNewWords.take(8).join('、')),
            if (a.tooHard) ...[
              const SizedBox(height: Gap.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppTheme.warningColor(ctx),
                  ),
                  const SizedBox(width: Gap.xxs),
                  Expanded(
                    child: Text(
                      '这份材料对你偏难(覆盖率低于 90%)。可以先读,但建议只精读前几段,别硬啃。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.warningColor(ctx),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('先不读'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('开始读'),
        ),
      ],
    ),
  );
  return go == true;
}

Widget _kv(BuildContext context, String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          children: [
            TextSpan(
              text: '$k：',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: v,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
