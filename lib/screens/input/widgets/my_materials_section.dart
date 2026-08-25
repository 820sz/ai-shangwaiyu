import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/constants.dart';
import '../../../providers/vocab_provider.dart';
import '../../../services/database.dart';
import '../../../models/vocabulary.dart';
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
          Icon(Icons.inbox_outlined, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text(
            '拍照识文后保存的生词会出现在这里',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
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
              color: count > 0 ? theme.colorScheme.primary : Colors.grey,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
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
    final items = await DatabaseService.getVocabulariesByCategory(
        widget.category);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  /// 按 materialPath 分组 → 未指定路径的归入"未分类"
  Map<String, List<Vocabulary>> _groupByMaterialPath() {
    final groups = <String, List<Vocabulary>>{};
    for (final v in _items!) {
      final path = (v.materialPath != null && v.materialPath!.isNotEmpty)
          ? v.materialPath!
          : '未分类';
      groups.putIfAbsent(path, () => []);
      groups[path]!.add(v);
    }
    return groups;
  }

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
              color: Colors.grey[300],
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
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
                          style: TextStyle(color: Colors.grey[400])))
                  : _buildGroupedList(),
        ),
      ],
      ),
    );
  }

  Widget _buildGroupedList() {
    final groups = _groupByMaterialPath();
    final keys = groups.keys.toList();

    // 只有一个分组 → 扁平列表
    if (keys.length == 1) {
      return ListView(
        controller: widget.scrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: _buildVocabList(groups[keys.first]!),
      );
    }

    // 多个子文件夹 → 分组展示
    return ListView.builder(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final key = keys[i];
        final items = groups[key]!;
        final isUncategorized = key == '未分类';
        // 从 materialPath 提取显示名（去掉主分类前缀）
        final displayName = isUncategorized
            ? '未归类'
            : key.replaceFirst('${widget.category}/', '');
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.grey[200]!),
          ),
          child: ExpansionTile(
            initiallyExpanded: !isUncategorized,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding:
                const EdgeInsets.fromLTRB(8, 0, 8, 8),
            leading: Icon(
              isUncategorized ? Icons.folder_outlined : Icons.folder,
              size: 20,
              color: isUncategorized ? Colors.grey : Colors.amber[700],
            ),
            title: Text(
              displayName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${items.length} 个生词',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            children: _buildVocabList(items),
          ),
        );
      },
    );
  }

  List<Widget> _buildVocabList(List<Vocabulary> items) {
    return items.map((v) {
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
                  color: v.wordType == 'phrase'
                      ? Colors.orange[50]
                      : Colors.purple[50],
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
    }).toList();
  }
}
