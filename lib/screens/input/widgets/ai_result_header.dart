import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// AI 结果摘要头部 — 紧凑版
class AiResultHeader extends StatelessWidget {
  final int totalCount;
  final int wordCount;
  final int phraseCount;
  final int sentenceCount;
  final String modelName;
  final String thinkingLabel;

  /// 本地校验说明(v2.4):忽略了哪些条目、纠正了什么。
  /// 为空则不显示这一行 —— 识别一切正常时不该多占地方。
  final String? guardNote;

  /// 点"校验"时的明细(被丢弃条目的原因),为空则不可点
  final List<String>? guardDetails;

  /// 模型自报的扫描对账(v2.6):"扫描 42 行 · 找到 18 处标记"。
  /// 为什么要显示:用户判断"它到底有没有认真看"就靠这两个数 ——
  /// 标记数远小于肉眼可见时,用户会知道该点"重新识别"。
  final String? scanNote;

  /// 第二遍高清分块复查的状态/战果(v2.6)
  final String? missedNote;

  /// "待确认"条数(模型拿不准算不算标记,但仍收进来的)
  final int uncertainCount;

  const AiResultHeader({
    super.key,
    required this.totalCount,
    required this.wordCount,
    required this.phraseCount,
    required this.sentenceCount,
    required this.modelName,
    required this.thinkingLabel,
    this.guardNote,
    this.guardDetails,
    this.scanNote,
    this.missedNote,
    this.uncertainCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '识别完成 · 共 $totalCount 个标记',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _countBadge(
                '📝',
                '$wordCount 单词',
                AppTheme.wordTypeColor(context, 'word'),
              ),
              _countBadge(
                '📐',
                '$phraseCount 短语',
                AppTheme.wordTypeColor(context, 'phrase'),
              ),
              _countBadge(
                '💬',
                '$sentenceCount 句子',
                AppTheme.wordTypeColor(context, 'sentence'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$modelName · $thinkingLabel',
            // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
            style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
          ),
          // v2.6:扫描对账 + 复查状态(一行,不占地方但很关键 —— 用户据此判断漏没漏)
          if (scanNote != null || missedNote != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.manage_search,
                    size: 13, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    [?scanNote, ?missedNote].join(' · '),
                    style: TextStyle(
                        fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          // v2.6:待确认提示(模型拿不准 → 收进来了,用户可取消)
          if (uncertainCount > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.help_outline, size: 13, color: AppTheme.warningColor(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$uncertainCount 条「待确认」:模型拿不准算不算标记,仍收进来了 —— 不要的取消勾选即可',
                    style: TextStyle(
                        fontSize: 10, color: AppTheme.warningColor(context)),
                  ),
                ),
              ],
            ),
          ],
          if (guardNote != null) ...[
            const SizedBox(height: 4),
            // 把"盲盒"打开:告诉用户本地校验动过什么,并允许看明细
            InkWell(
              onTap: (guardDetails == null || guardDetails!.isEmpty)
                  ? null
                  : () => showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('本地校验明细'),
                          content: SingleChildScrollView(
                            child: Text(
                              guardDetails!.join('\n'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('知道了'),
                            ),
                          ],
                        ),
                      ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fact_check_outlined,
                      size: 13, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    guardNote!,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                      decoration: (guardDetails == null || guardDetails!.isEmpty)
                          ? null
                          : TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _countBadge(String emoji, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$emoji $label',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }
}
