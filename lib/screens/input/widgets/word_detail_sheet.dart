import 'package:flutter/material.dart';
import '../../../models/vocabulary.dart';
import 'example_sentence.dart';

/// 单词详情 BottomSheet
/// [onSave] 单独保存此词（async，等保存完成才关 sheet）
/// [onEdit] 打开编辑对话框
/// [onRemove] 从选集中移除此词
void showWordDetailSheet({
  required BuildContext context,
  required Vocabulary item,
  required Future<void> Function() onSave,
  required VoidCallback onEdit,
  required VoidCallback onRemove,
}) {
  final theme = Theme.of(context);
  final bottomSafe = MediaQuery.of(context).padding.bottom;

  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.7,
      expand: false,
      builder: (ctx, scrollCtrl) => Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomSafe),
        child: ListView(
          controller: scrollCtrl,
          children: [
            // 拖拽条
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 单词大标题
            Text(
              item.word,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            // 类型 + 词性
            Row(
              children: [
                _tag(item.wordType == 'phrase' ? '短语' : item.wordType == 'sentence' ? '句子' : '单词',
                    _typeColor(item.wordType)),
                if (item.partOfSpeech != null && item.partOfSpeech!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _tag(item.partOfSpeech!, Colors.grey[600]!),
                ],
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // 释义
            if (item.translation != null && item.translation!.isNotEmpty) ...[
              Text('释义', style: _sectionTitle(theme)),
              const SizedBox(height: 4),
              Text(item.translation!, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
            ],
            // 原文例句
            if (item.originalSentence != null && item.originalSentence!.isNotEmpty) ...[
              Text('原文例句', style: _sectionTitle(theme)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ExampleSentence(
                  sentence: item.originalSentence!,
                  highlightWord: item.word,
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[700]),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 语法分析
            if (item.grammarNote != null && item.grammarNote!.isNotEmpty) ...[
              Text('语法分析', style: _sectionTitle(theme)),
              const SizedBox(height: 4),
              Text(item.grammarNote!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 8),
            // 操作栏
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionButton(ctx, Icons.edit_outlined, '编辑', onEdit),
                // 保存按钮：等 async 保存完成再关 sheet
                TextButton.icon(
                  onPressed: () async {
                    await onSave();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('保存'),
                ),
                _actionButton(ctx, Icons.close, '移除', onRemove, destructive: true),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

TextStyle _sectionTitle(ThemeData theme) {
  return TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600]);
}

Color _typeColor(String type) {
  if (type == 'phrase') return Colors.orange;
  if (type == 'sentence') return Colors.purple;
  return const Color(0xFF4A90D9);
}

Widget _tag(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
  );
}

Widget _actionButton(
  BuildContext ctx,
  IconData icon,
  String label,
  VoidCallback onPressed, {
  bool destructive = false,
}) {
  return TextButton.icon(
    onPressed: () {
      Navigator.pop(ctx);
      onPressed();
    },
    icon: Icon(icon, size: 18, color: destructive ? Colors.red[400] : null),
    label: Text(label, style: TextStyle(color: destructive ? Colors.red[400] : null)),
  );
}
