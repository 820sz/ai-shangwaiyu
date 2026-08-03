import 'package:flutter/material.dart';

/// 分类子信息（由 showSubCategoryInput 返回）
class CategorySubInfo {
  /// 用户输入的材料名称（如：书名、教材名、刊物名等）
  final String materialName;
  /// 自动构建的分层路径，如 '书籍/三体'
  final String materialPath;

  const CategorySubInfo({
    required this.materialName,
    required this.materialPath,
  });
}

/// 选择主分类后弹出此 BottomSheet，收集子分类信息。
///
/// [category] — 主分类名（教材/书籍/外刊/碎片文章/其他）
/// [prefill]  — 从识别上下文预填的值（如 sourceBook）
///
/// 各分类提示：
/// - 教材 → 教材名称 + 单元/课
/// - 书籍 → 书名
/// - 外刊 → 刊物名 + 期号
/// - 碎片文章 → 来源App/网址
/// - 其他 → 自由备注
Future<CategorySubInfo?> showSubCategoryInput(
  BuildContext context, {
  required String category,
  String prefill = '',
}) {
  final bottomSafe = MediaQuery.of(context).padding.bottom;
  return showModalBottomSheet<CategorySubInfo>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _SubCategoryInputSheet(
      category: category,
      prefill: prefill,
      bottomSafe: bottomSafe,
    ),
  );
}

class _SubCategoryInputSheet extends StatefulWidget {
  final String category;
  final String prefill;
  final double bottomSafe;

  const _SubCategoryInputSheet({
    required this.category,
    required this.prefill,
    required this.bottomSafe,
  });

  @override
  State<_SubCategoryInputSheet> createState() => _SubCategoryInputSheetState();
}

class _SubCategoryInputSheetState extends State<_SubCategoryInputSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _extraCtrl;

  static const _hints = <String, List<String>>{
    '教材': ['教材名称（如：新概念英语）', '单元/册（如：第2册）'],
    '书籍': ['书名（如：哈利波特与魔法石）', '章节/页码（可选）'],
    '外刊': ['刊物名称（如：The Economist）', '期号/日期（可选）'],
    '碎片文章': ['来源（如：微信公众号/知乎）', '标题/链接（可选）'],
    '其他': ['材料名称或备注', '更多信息（可选）'],
  };

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.prefill);
    _extraCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  String get _placeholder1 => _hints[widget.category]?[0] ?? '材料名称';
  String get _placeholder2 => _hints[widget.category]?[1] ?? '更多信息';
  String get _iconLabel {
    switch (widget.category) {
      case '教材':
        return '📚';
      case '书籍':
        return '📖';
      case '外刊':
        return '📰';
      case '碎片文章':
        return '📄';
      default:
        return '📁';
    }
  }

  CategorySubInfo _buildResult() {
    final name = _nameCtrl.text.trim();
    final extra = _extraCtrl.text.trim();
    final materialName = name.isNotEmpty ? name : widget.category;
    final segments = <String>[widget.category];
    if (name.isNotEmpty) segments.add(name);
    if (extra.isNotEmpty) segments.add(extra);
    return CategorySubInfo(
      materialName: materialName,
      materialPath: segments.join('/'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + widget.bottomSafe,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽条
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 标题
            Row(
              children: [
                Text(_iconLabel, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(
                  '${widget.category} · 补充信息',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '添加后可在材料管理中按层级浏览（可选，留空则只归入大类）',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            // 输入框1 — 材料名称
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _placeholder1,
                hintText: _placeholder1,
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(Icons.label_outline, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            // 输入框2 — 额外信息
            TextField(
              controller: _extraCtrl,
              decoration: InputDecoration(
                labelText: _placeholder2,
                hintText: _placeholder2,
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(Icons.info_outline, size: 20),
              ),
            ),
            const SizedBox(height: 16),
            // 按钮行
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('跳过'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, _buildResult()),
                    child: const Text('确认'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
