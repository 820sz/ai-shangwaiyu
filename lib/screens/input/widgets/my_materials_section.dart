import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/constants.dart';
import '../../../providers/vocab_provider.dart';
import '../../../services/database.dart';
import '../../../models/vocabulary.dart';
import '../../../utils/material_group.dart';
import '../../profile/vocab_list.dart';

/// 板块2：我的学习材料 — 按分类浏览用户已保存的材料
class MyMaterialsSection extends StatelessWidget {
  const MyMaterialsSection({super.key});

  static const _icons = <String, IconData>{
    '教材': Icons.school,
    '书籍': Icons.menu_book,
    '外刊': Icons.article,
    '碎片文章': Icons.auto_stories,
    '其他': Icons.folder,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vocab = context.watch<VocabProvider>();
    final byCategory = vocab.vocabByCategory;

    // 统计总数
    final totalVocab = vocab.vocabularies.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding:
            const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: Icon(Icons.folder_open, color: theme.colorScheme.primary),
        title: Text(
          '我的学习材料',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: totalVocab == 0
            ? const Text('暂无材料', style: TextStyle(fontSize: 12))
            : Text('共 $totalVocab 个生词',
                style: const TextStyle(fontSize: 12)),
        children: [
          if (totalVocab == 0)
            _buildEmptyState(theme)
          else ...[
            // 分类统计列表
            for (final cat in AppConstants.learningCategories)
              _CategoryRow(
                name: cat,
                icon: _icons[cat] ?? Icons.folder,
                count: byCategory[cat] ?? 0,
                onTap: () => _showCategoryVocabList(context, cat),
              ),
            const SizedBox(height: 8),
            // 查看全部按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VocabListScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.list_alt, size: 16),
                label: const Text('查看全部生词'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            '暂无材料',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showCategoryVocabList(BuildContext context, String category) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollCtrl) =>
            _CategoryVocabSheet(category: category, scrollCtrl: scrollCtrl, bottomSafe: bottomSafe),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String name;
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  const _CategoryRow({
    required this.name,
    required this.icon,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 22, color: theme.colorScheme.primary),
      title: Text(name, style: const TextStyle(fontSize: 14)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: count > 0 ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
      onTap: count > 0 ? onTap : null,
    );
  }
}

/// 分类下的生词列表（底部弹窗）— 按 materialPath 子文件夹分组
class _CategoryVocabSheet extends StatefulWidget {
  final String category;
  final ScrollController scrollCtrl;
  final double bottomSafe;

  const _CategoryVocabSheet({
    required this.category,
    required this.scrollCtrl,
    required this.bottomSafe,
  });

  @override
  State<_CategoryVocabSheet> createState() => _CategoryVocabSheetState();
}

class _CategoryVocabSheetState extends State<_CategoryVocabSheet> {
  List<Vocabulary>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // v1.8.0 修「数量对不上」:原实现用默认 limit=100,分类 251 个词只读到
    // 100 个 → 标题写 100 与实际不符。这里一次读全(上限给足)。
    final items = await DatabaseService.getVocabulariesByCategory(
      widget.category,
      limit: 5000,
    );
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  /// 重命名书/材料文件夹(v1.8.0:用户要求书名可改)
  Future<void> _renameGroup(MaterialGroup group) async {
    final ctrl = TextEditingController(text: group.label);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '名称',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName == null || newName.isEmpty || !mounted) return;
    if (group.path == '未归类') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未归类分组的词请先在生词本里指定分类')),
      );
      return;
    }
    final newPath = '${widget.category}/$newName';
    await DatabaseService.renameBookPath(
      oldPath: group.path,
      newPath: newPath,
      newBookName: newName,
    );
    if (!mounted) return;
    await context.read<VocabProvider>().loadVocabularies();
    await _load();
  }

  /// 改页码/章节标签(v1.8.0):整组一起改,输入会被智能归一
  Future<void> _editPageLabel(String label, List<Vocabulary> items) async {
    final ctrl = TextEditingController(
      text: label == '未标页码' ? '' : label,
    );
    final newLabel = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改页码/章节'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '如 p9 或 p9-12',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newLabel == null || !mounted) return;
    final ids = items.map((v) => v.id).whereType<int>().toList();
    await DatabaseService.updateSourcePageByIds(ids, newLabel);
    if (!mounted) return;
    await _load();
  }

  /// 分组(v1.6.0):书籍 = 一本书一个文件夹,页/章为子分类;
  /// 其他分类沿用整条 material_path 作一级分组。
  List<MaterialGroup> _grouped() => groupMaterials(_items!, category: widget.category);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomSafe),
      child: Column(
      children: [
        // 拖拽条
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                widget.category,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_items != null)
                Text('${_items!.length} 个生词',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items == null || _items!.isEmpty
                  ? Center(
                      child: Text('该分类暂无生词',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
                  : _buildGroupedList(),
        ),
      ],
      ),
    );
  }

  Widget _buildGroupedList() {
    final theme = Theme.of(context);
    final groups = _grouped();
    // 只有一个分组且无有效二级 → 扁平列表
    if (groups.length == 1) {
      final subs = groups.first.subgroups;
      if (subs.length <= 1) {
        final only = subs.isEmpty ? <Vocabulary>[] : subs.values.first;
        // P2-4:改为惰性构建 —— 原 `ListView(children: ...)` 会把该分组下
        // 全部词条一次性建成 ListTile(词表上限 5000,最坏一次建几千个)
        return ListView.builder(
          controller: widget.scrollCtrl,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: only.length,
          itemBuilder: (_, i) => _buildVocabRow(only[i]),
        );
      }
    }

    return ListView.builder(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: groups.length,
      itemBuilder: (_, i) {
        final g = groups[i];
        final isUncategorized = g.path == '未归类';
        final subs = g.subgroups;
        // 无有效二级(单个空 key)→ 直接铺词;有二级 → 嵌套页/章
        final hasSubgroups = !(subs.length == 1 && subs.keys.first.isEmpty);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: ExpansionTile(
            initiallyExpanded: !isUncategorized,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            leading: Icon(
              isUncategorized ? Icons.folder_outlined : Icons.folder,
              size: 20,
              color: isUncategorized ? theme.colorScheme.onSurfaceVariant : Colors.amber[700],
            ),
            title: Text(
              g.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${g.totalCount} 个生词'
              '${hasSubgroups ? ' · ${subs.length} 个${widget.category == '书籍' ? '页码/章节' : '子分类'}' : ''}',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
            ),
            // 重命名(v1.8.0):书名/材料名可手动改
            trailing: isUncategorized
                ? null
                : IconButton(
                    tooltip: '重命名',
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    onPressed: () => _renameGroup(g),
                  ),
            children: hasSubgroups
                ? subs.entries
                    .map((e) => _buildSubgroupTile(e.key, e.value))
                    .toList()
                : _buildVocabList(
                    subs.isEmpty ? <Vocabulary>[] : subs.values.first),
          ),
        );
      },
    );
  }

  /// 二级:页码/章节(书籍)或子分类
  Widget _buildSubgroupTile(String label, List<Vocabulary> items) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        leading: Icon(
          Icons.bookmark_border,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          label.isEmpty ? '未标页码' : label,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          '${items.length} 个生词',
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
        ),
        // 改页码/章节(v1.8.0):整组一起改,输入自动归一
        trailing: IconButton(
          tooltip: '修改页码/章节',
          icon: const Icon(Icons.edit_outlined, size: 15),
          onPressed: () => _editPageLabel(label, items),
        ),
        children: _buildVocabList(items),
      ),
    );
  }

  /// 单个词条行(从原 _buildVocabList 抽出,P2-4:支持 ListView.builder 惰性构建)
  Widget _buildVocabRow(Vocabulary v) {
    return ListTile(
      dense: true,
      title: Text(v.word,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: v.translation != null
          ? Text(v.translation!,
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: v.wordType == 'word'
          ? null
          : Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                // 词型角标:半透明色相(浅色下≈orange[50]/purple[50],深色下成立)
                color: v.wordType == 'phrase'
                    ? Colors.orange.withAlpha(34)
                    : Colors.purple.withAlpha(34),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                v.wordType == 'phrase' ? '短语' : '句子',
                style: TextStyle(
                    fontSize: 10,
                    color: v.wordType == 'phrase'
                        ? Colors.orange[700]
                        : Colors.purple[700]),
              ),
            ),
    );
  }

  /// ExpansionTile 的 children 仍需 Widget 列表(那里本来就一次性展开)
  List<Widget> _buildVocabList(List<Vocabulary> items) {
    return items.map(_buildVocabRow).toList();
  }
}
