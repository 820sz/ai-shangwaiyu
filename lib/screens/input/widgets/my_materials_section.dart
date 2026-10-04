import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/constants.dart';
import '../../../config/design_tokens.dart';
import '../../../config/theme.dart';
import '../../../providers/vocab_provider.dart';
import '../../../services/database.dart';
import '../../../models/vocabulary.dart';
import '../../../utils/material_group.dart';
import '../../../utils/page_label.dart';
import '../../../widgets/app_ui.dart';
import '../../profile/vocab_list.dart';

/// 板块:**我的词汇本**(v1.6.0 起叫「我的学习材料」;v2.9 改名)。
///
/// 用户 10/2 第 5 条:"'我的学习材料'现在**本质是个词汇本**,需改为'材料导入'
/// (…)+'我的词汇本'(然后子功能就是现有的教程、等等这些逻辑)"。
///
/// 所以这一块只做**词汇**:按分类(教材/书籍/外刊/碎片文章/其他)浏览已收藏的生词,
/// 材料本体与导入在隔壁 [ImportedMaterialsSection]。
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

    return AppCard(
      // v2.7(第 1 条):与同页其他卡片统一几何(旧写法 Card(margin: h16)+ 圆角 12 +
      // tilePadding 16 → 左边缘比别的卡片多缩进 16px)
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding:
            const EdgeInsets.fromLTRB(14, 0, 14, 12),
        leading: Icon(Icons.folder_open, color: theme.colorScheme.primary),
        title: Text(
          '我的词汇本',
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

  /// 改出处(v2.7,用户第 6(2) 条)。
  ///
  /// 「未归类」里的词 `material_path` 是空的,而这里以前**只能改页码**
  /// (`updateSourcePageByIds` 只写 `source_page`)—— 于是用户给未归类的内容
  /// 编辑了"出处"(页码),它依然待在「未归类」,看起来就是"归类没生效"。
  /// 现在:未归类走 [needMaterial] 分支,弹「材料名 + 页码」两个字段,填了材料名
  /// 就真的离开未归类;其余分组的页码编辑保持原样(整组一起改,输入自动归一)。
  Future<void> _editSource(
    String label,
    List<Vocabulary> items, {
    bool needMaterial = false,
  }) async {
    if (needMaterial) {
      await _assignMaterial(
        label: label.isEmpty ? '未标页码' : label,
        items: items,
        page: label,
      );
      return;
    }
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

  /// 「移动材料」(v2.10,用户 10/4 第 8 条)。
  ///
  /// 用户要的是"**从已有分类里选**",而不是每次都要手打一遍材料名。所以:
  /// 1. 列出**当前分类下已有的材料**(按生词数倒序)—— 一个词一个词点过来的人,
  ///    通常就是要把零散的词并到同一本书下面;
  /// 2. 再列出**其它分类下的材料**(跨分类移动也常见:拍下来的词原本归到"教材",
  ///    其实属于某本"书籍");
  /// 3. 都没有合适的 → 底部给「新建一个材料…」走原来的手填流程(兜底,不是主路径)。
  Future<void> _moveToExisting({
    required String label,
    required List<Vocabulary> items,
  }) async {
    // 已经在"未归类"里的词:材料名是空的,列表里不会出现它们,直接给新建入口
    final paths = await DatabaseService.getMaterialPathsByCategory(
      widget.category,
    );
    if (!mounted) return;
    final choices = <String>[
      for (final p in paths)
        if (p.trim().isNotEmpty && p != label) p,
    ]..sort();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('移动到哪?',
                      style: Theme.of(ctx)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    '${items.length} 个生词 · 从「${widget.category}」里已有的材料中选一个',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: choices.isEmpty
                  ? const Center(child: Text('这个分类下还没有别的材料'))
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: choices.length,
                      itemBuilder: (_, i) {
                        final p = choices[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.menu_book_outlined, size: 18),
                          title: Text(p,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14)),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => Navigator.pop(ctx, p),
                        );
                      },
                    ),
            ),
            const SizedBox(height: Gap.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, '__new__'),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 17),
                  label: const Text('新建一个材料…(手动输入)'),
                ),
              ),
            ),
            const SizedBox(height: Gap.sm),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == '__new__') {
      await _assignMaterial(label: label, items: items);
      return;
    }
    await _moveInto(picked, items);
  }

  /// 真正把这批词移到目标材料下(不弹任何对话框,选完即生效)
  Future<void> _moveInto(String materialName, List<Vocabulary> items) async {
    final ids = items.map((v) => v.id).whereType<int>().toList();
    if (ids.isEmpty) return;
    await context.read<VocabProvider>().moveVocabularies(
          ids,
          category: widget.category,
          materialPath: buildMaterialPath(
            category: widget.category,
            name: materialName,
          ),
          sourceBook: materialName,
        );
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已把 ${ids.length} 个生词移到「$materialName」'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 归入材料 / 改出处(v2.7,用户第 6(2) 条):写 `material_path` + `source_book`
  /// (+ 可选页码)。这是"未归类"唯一的出口 —— 填了材料名,这一组就移到
  /// 「分类 / 材料名」下面。
  Future<void> _assignMaterial({
    required String label,
    required List<Vocabulary> items,
    String? book,
    String? page,
  }) async {
    final ids = items.map((v) => v.id).whereType<int>().toList();
    if (ids.isEmpty) return;
    final nameCtrl = TextEditingController(text: book ?? '');
    final pageCtrl = TextEditingController(
      text: (page ?? '') == '未标页码' ? '' : (page ?? ''),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑出处'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共 ${ids.length} 个生词。材料名决定它们挂在哪个材料下面 —— '
                '「未归类」里的词只有填了材料名才会移出去。',
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '材料名 / 书名',
                  hintText: '如:哈利波特与魔法石',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pageCtrl,
                decoration: const InputDecoration(
                  labelText: '页码 / 章节(可选)',
                  hintText: '如 p33-35 或 第2章',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    final pageText = pageCtrl.text.trim();
    nameCtrl.dispose();
    pageCtrl.dispose();
    if (saved != true || !mounted) return;
    if (name.isEmpty) {
      // 空材料名 = 依旧未归类。与其"保存成功但什么都没变",不如当场说清。
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('材料名没填 —— 没有材料名它就还是「未归类」'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final normalized = normalizePageLabel(pageText);
    await context.read<VocabProvider>().moveVocabularies(
          ids,
          category: widget.category,
          materialPath: buildMaterialPath(
            category: widget.category,
            name: name,
          ),
          sourceBook: name,
          sourcePage: normalized.isEmpty ? null : normalized,
        );
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已把 ${ids.length} 个生词归入「$name」'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 解散分组(v2.7,用户第 6(1) 条):词**保留**,只把材料出处清空 → 回到「未归类」。
  Future<void> _detachGroup(String label, List<Vocabulary> items) async {
    final ids = items.map((v) => v.id).whereType<int>().toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('解散「$label」?'),
        content: Text(
          '${ids.length} 个生词都会保留,只是不再挂在任何材料下面'
          '(移到「未归类」)。生词与复习记录不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解散'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<VocabProvider>().detachMaterial(ids);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已解散分组,${ids.length} 个生词移到「未归类」'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 删除整组(v2.7,用户第 6(1) 条:"没法直接选中子分类进行删除,
  /// 只能进生词本一个一个删")。走批量删除:单事务 + 单次刷新,不是 N 次单删。
  Future<void> _deleteGroup(String label, List<Vocabulary> items) async {
    final ids = items.map((v) => v.id).whereType<int>().toList();
    if (ids.isEmpty) return;
    final danger = AppTheme.dangerColor(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「$label」?'),
        content: Text(
          '这一组共 ${ids.length} 个生词,删除后不可恢复'
          '(连同它们的复习记录一起移除)。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除 ${ids.length} 个'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = await context.read<VocabProvider>().deleteVocabularies(ids);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 $n 个生词'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: danger,
      ),
    );
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
              color: isUncategorized
                  ? theme.colorScheme.onSurfaceVariant
                  : AppTheme.amber(context),
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
            // v2.7(第 6(1) 条):右上角改回**默认展开箭头** —— ExpansionTile 的
            // trailing 一旦被占用,箭头就没了,用户看不出这一行能展开;
            // 重命名/改出处/解散/删除整组统一放到展开区底部一行(带文字标签,更好找)。
            children: [
              if (hasSubgroups)
                ...subs.entries.map(
                  (e) => _buildSubgroupTile(
                    e.key,
                    e.value,
                    needMaterial: isUncategorized,
                  ),
                )
              else
                ..._buildVocabList(
                    subs.isEmpty ? <Vocabulary>[] : subs.values.first),
              _groupActions(g, [
                for (final list in subs.values) ...list,
              ], isUncategorized),
            ],
          ),
        );
      },
    );
  }

  Widget _groupActions(
    MaterialGroup g,
    List<Vocabulary> items,
    bool isUncategorized,
  ) {
    final danger = AppTheme.dangerColor(context);
    final ids = items.map((v) => v.id).whereType<int>().toList();
    if (ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Wrap(
        spacing: Gap.xs,
        runSpacing: Gap.xs,
        children: [
          if (!isUncategorized)
            ActionChip(
              avatar: const Icon(Icons.drive_file_rename_outline, size: 15),
              label: const Text('重命名'),
              onPressed: () => _renameGroup(g),
            ),
          ActionChip(
            avatar: const Icon(Icons.drive_file_move_outline, size: 15),
            // v2.10(用户 10/4 第 8 条):"应该是用户能**选移动进已有的分类里**,
            // 而不是现在的'归入材料出处'这种点进去还得用户手动填"
            // → 先弹"选已有的分类/材料",手填只作为兜底入口。
            label: const Text('移动材料…'),
            onPressed: () => _moveToExisting(label: g.label, items: items),
          ),
          if (!isUncategorized)
            ActionChip(
              avatar: const Icon(Icons.folder_off_outlined, size: 15),
              label: const Text('解散分组'),
              onPressed: () => _detachGroup(g.label, items),
            ),
          ActionChip(
            avatar: Icon(Icons.delete_outline, size: 15, color: danger),
            label: Text('删除整组(${ids.length})',
                style: TextStyle(color: danger)),
            onPressed: () => _deleteGroup(g.label, items),
          ),
        ],
      ),
    );
  }

  /// 二级:页码/章节(书籍)或子分类
  ///
  /// [needMaterial] = 这个二级挂在「未归类」下面(第 6(2) 条):这时铅笔不能只改页码,
  /// 必须同时能填材料名,否则改完还在未归类。
  Widget _buildSubgroupTile(
    String label,
    List<Vocabulary> items, {
    bool needMaterial = false,
  }) {
    final theme = Theme.of(context);
    final danger = AppTheme.dangerColor(context);
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
        // 改页码/章节(v1.8.0)+ 删除这一组(v2.7,第 6(1) 条):
        // 二级也能直接删,不必进生词本一个个删
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: needMaterial ? '编辑出处(材料名 / 页码)' : '修改页码/章节',
              icon: const Icon(Icons.edit_outlined, size: 15),
              onPressed: () => _editSource(
                label,
                items,
                needMaterial: needMaterial,
              ),
            ),
            IconButton(
              tooltip: '删除这一组(${items.length} 个生词)',
              icon: Icon(Icons.delete_outline, size: 15, color: danger),
              onPressed: () =>
                  _deleteGroup(label.isEmpty ? '未标页码' : label, items),
            ),
          ],
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
                color: AppTheme.wordTypeColor(
                  context,
                  v.wordType,
                ).withAlpha(34),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                v.wordType == 'phrase' ? '短语' : '句子',
                style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.wordTypeColor(context, v.wordType)),
              ),
            ),
    );
  }

  /// ExpansionTile 的 children 仍需 Widget 列表(那里本来就一次性展开)
  List<Widget> _buildVocabList(List<Vocabulary> items) {
    return items.map(_buildVocabRow).toList();
  }
}
