import 'package:flutter/material.dart';
import '../../../services/database.dart';
import '../../../utils/page_label.dart';

/// 分类子信息（由 showSubCategoryInput 返回）
class CategorySubInfo {
  /// 用户输入的材料名称（如：书名、教材名、刊物名等）
  final String materialName;
  /// 自动构建的分层路径，如 '书籍/三体'
  final String materialPath;
  /// 页码/附注(仅"书籍"类:独立于路径,v1.4.4——避免"同一本书按页码
  /// 每页一类"的混乱;其余类别此字段为 null)
  final String? sourcePage;

  const CategorySubInfo({
    required this.materialName,
    required this.materialPath,
    this.sourcePage,
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

  /// 该分类下已用过的素材路径(子分类记忆)
  List<String> _historyPaths = [];
  bool _historyLoaded = false;

  static const _hints = <String, List<String>>{
    '教材': ['教材名称（如：新概念英语）', '单元/册（如：第2册）'],
    '书籍': ['书名（如：哈利波特与魔法石）', '页码（如：3-5页，同一本书自动合并）'],
    '外刊': ['刊物名称（如：The Economist）', '期号/日期（可选）'],
    '碎片文章': ['来源（如：微信公众号/知乎）', '标题/链接（可选）'],
    '其他': ['材料名称或备注', '更多信息（可选）'],
  };

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.prefill);
    _extraCtrl = TextEditingController();
    _loadHistory();
  }

  /// 加载本分类历史子分类(失败静默 → 空列表,不影响输入)
  Future<void> _loadHistory() async {
    try {
      final paths = await DatabaseService.getMaterialPathsByCategory(
          widget.category);
      if (mounted) {
        setState(() {
          _historyPaths = paths;
          _historyLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _historyLoaded = true);
    }
  }

  /// 点选历史路径 → 填充输入框(用户可继续微调)
  /// 路径形如 '书籍/三体/第1章',截掉主分类前缀后放回 name 框,
  /// 确认时按 segments 拼回原路径,不会丢失层级。
  void _applyHistory(String path) {
    final display = path.startsWith('${widget.category}/')
        ? path.substring(widget.category.length + 1)
        : path;
    setState(() {
      _nameCtrl.text = display;
      _extraCtrl.clear();
    });
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
    // v1.4.4:书籍类的第二输入框是"页码/章节",存 sourcePage(独立字段),
    // 不拼进 material_path——同一本书无论存哪页都归入同一个路径,
    // 杜绝"同一本书按页码每页一类"的混乱;教材/外刊的层级信息(单元/
    // 期号)仍拼进路径,层级浏览有意义。
    // v1.8.0:页码做智能归一——「p9页」「第9页」「9」统一成「p9」,
    // 「p16 p17」压缩成「p16-17」,不再出现「pp9页」这种脏数据。
    final isBook = widget.category == '书籍';
    final segments = <String>[widget.category];
    if (name.isNotEmpty) segments.add(name);
    if (!isBook && extra.isNotEmpty) segments.add(extra);
    final page = isBook ? normalizePageLabel(extra) : '';
    return CategorySubInfo(
      materialName: materialName,
      materialPath: segments.join('/'),
      sourcePage: page.isEmpty ? null : page,
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
                  color: theme.colorScheme.outlineVariant,
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
            const SizedBox(height: 16),
            // 历史子分类 — 点选即填,不必重新输入
            if (_historyLoaded && _historyPaths.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '历史分类',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _historyPaths.map((p) {
                  final display = p.startsWith('${widget.category}/')
                      ? p.substring(widget.category.length + 1)
                      : p;
                  return ChoiceChip(
                    label: Text(display,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    selected: false,
                    onSelected: (_) => _applyHistory(p),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
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
