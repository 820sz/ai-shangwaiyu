import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../providers/vocab_provider.dart';
import '../../services/word_frequency.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/v4/v4_kit.dart';
import '../../widgets/vocab_card.dart';
import '../input/widgets/category_picker.dart';
import '../input/widgets/sub_category_input.dart';
import 'vocab_detail.dart';

class VocabListScreen extends StatefulWidget {
  final String? sourceBook;

  const VocabListScreen({super.key, this.sourceBook});

  @override
  State<VocabListScreen> createState() => _VocabListScreenState();
}

class _VocabListScreenState extends State<VocabListScreen> {
  String _selectedBook = '全部';
  String _selectedType = '全部';
  String _searchQuery = '';
  bool _showSearch = false;
  final _searchCtrl = TextEditingController();

  // ── 多选模式 ──
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

  // ── 防竞态：每次换筛选条件 generation+1，结果只认最新一代 ──
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.sourceBook != null) {
      _selectedBook = widget.sourceBook!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // P2-10:进页立刻返回时 element 已 deactivate,
      // 不加这道判断会抛错并被 CrashLogger 记成"崩溃",污染诊断日志
      if (!mounted) return;
      context.read<VocabProvider>().loadVocabularies(
            sourceBook:
                _selectedBook == '全部' ? null : _selectedBook,
          );
      // v2.4(B2):原型备注要用内嵌词频表校验候选词是否真词 ——
      // 先把它加载好再重绘一次,否则列表里"有时有括号有时没有"
      if (!WordFrequency.isLoaded) {
        await WordFrequency.ensureLoaded();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    // P2-13:此前没有 dispose → 反复进出"生词本"会累积泄漏控制器
    _searchCtrl.dispose();
    super.dispose();
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
        if (!_selectionMode) _selectionMode = true;
      }
    });
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final deleteColor = Theme.of(context).colorScheme.error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个生词吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: deleteColor),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final provider = context.read<VocabProvider>();
    await Future.wait(_selectedIds.toList().map((id) => provider.deleteVocabulary(id)));
    if (mounted) _exitSelectionMode();
  }

  Future<void> _batchMove() async {
    if (_selectedIds.isEmpty) return;
    // 1. 选目标分类
    final category = await showCategoryPicker(context);
    if (category == null || !mounted) return;
    // 2. 选子分类信息。
    //    v2.4(A6)修复:原来**取消这一步也会照常移动**,结果是"分类改了、
    //    material_path 没改" —— 词在「我的学习材料」里仍然挂在「未归类」,
    //    用户以为归类没生效。现在取消 = 整件事取消。
    final provider = context.read<VocabProvider>();
    final prefillSource = _commonSourceBook(provider);
    final subInfo = await showSubCategoryInput(
      context,
      category: category,
      prefill: prefillSource,
    );
    if (!mounted) return;
    if (subInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已取消:没有填材料名/页码,生词不会被移动'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await Future.wait(_selectedIds.toList().map((id) =>
        provider.updateVocabulary(id,
            category: category,
            materialPath: subInfo.materialPath,
            sourceBook: subInfo.materialName,
            sourcePage: subInfo.sourcePage)));
    if (mounted) {
      final count = _selectedIds.length; // 先存计数，再清选择
      final hasSourceBookOverwrite = subInfo.materialName.isNotEmpty;
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hasSourceBookOverwrite
              ? '已将 $count 个生词移至「$category / ${subInfo.materialName}」'
              : '已将 $count 个生词移至「$category」'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 选中词条的共同出处(用于预填子分类对话框,省得重新手打书名)
  String _commonSourceBook(VocabProvider provider) {
    final books = <String>{};
    for (final v in provider.vocabularies) {
      if (v.id == null || !_selectedIds.contains(v.id)) continue;
      final b = (v.sourceBook ?? '').trim();
      if (b.isNotEmpty) books.add(b);
    }
    return books.length == 1 ? books.first : '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vocab = context.watch<VocabProvider>();

    // 筛选
    var items =
        _searchQuery.isEmpty ? vocab.vocabularies : vocab.search(_searchQuery);
    if (_selectedType != '全部') {
      final typeMap = {'单词': 'word', '短语': 'phrase', '句子': 'sentence'};
      items = items
          .where((v) => v.wordType == typeMap[_selectedType])
          .toList();
    }

    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // v4(2026-11-03):生词本换成内页果冻头;搜索框从 AppBar 里挪出来
            // 变成头图下的一行标准输入框(主题自带果冻样式),多选动作收进玻璃圆键。
            V4DetailHeader(
              domain: GraphicDomain.language,
              title: _selectionMode ? '已选 ${_selectedIds.length} 项' : '生词本',
              subtitle: _selectionMode
                  ? '选中的词可以批量移动或删除'
                  : '共 ${vocab.vocabularies.length} 个生词 · 点词看详情,长按可多选',
              leading: _selectionMode
                  ? V4IconAction(
                      icon: Icons.close_rounded,
                      tooltip: '退出多选',
                      onTap: _exitSelectionMode,
                    )
                  : null,
              leadingBack: !_selectionMode,
              actions: <Widget>[
                if (_selectionMode) ...<Widget>[
                  V4IconAction(
                    icon: Icons.drive_file_move_outlined,
                    tooltip: '移动到其他分类',
                    onTap: _batchMove,
                  ),
                  V4IconAction(
                    icon: Icons.delete_outline,
                    tooltip: '批量删除',
                    onTap: _batchDelete,
                  ),
                  V4IconAction(
                    icon: Icons.select_all,
                    tooltip: '全选',
                    onTap: () {
                      setState(() {
                        if (_selectedIds.length == items.length) {
                          _selectedIds.clear();
                          _selectionMode = false;
                        } else {
                          _selectedIds
                              .addAll(items.map((v) => v.id!).toList());
                        }
                      });
                    },
                  ),
                ] else
                  V4IconAction(
                    icon: _showSearch ? Icons.close : Icons.search,
                    tooltip: '搜索生词',
                    onTap: () {
                      setState(() {
                        _showSearch = !_showSearch;
                        if (!_showSearch) {
                          _searchQuery = '';
                          _searchCtrl.clear();
                        }
                      });
                    },
                  ),
              ],
            ),
            Expanded(
              child: Column(
                children: <Widget>[
                  if (_showSearch && !_selectionMode)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Gap.page, Gap.xs, Gap.page, Gap.xs),
                      child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          hintText: '搜索生词…',
                          prefixIcon: Icon(Icons.search, size: 18),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                        onSubmitted: (_) => setState(() {}),
                      ),
                    ),
          if (!_selectionMode) ...[
            // 筛选栏（选择模式下隐藏）
            _buildFilterBar(vocab, theme),
            const Divider(height: 1),
          ],

          // 统计
          if (_searchQuery.isEmpty && _selectedType == '全部' && !_selectionMode)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '共 ${items.length} 个生词',
                    // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13),
                  ),
                  const Spacer(),
                  if (_selectedBook != '全部')
                    Text(
                      '《$_selectedBook》',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                ],
              ),
            ),

          // 词汇列表
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty ? '还没有生词' : '没有匹配结果',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final v = items[index];
                      final isSelected = _selectedIds.contains(v.id);
                      return VocabCard(
                        vocab: v,
                        selected: _selectionMode ? isSelected : null,
                        onTap: () {
                          if (_selectionMode) {
                            _toggleSelect(v.id!);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    VocabDetailScreen(vocab: v),
                              ),
                            );
                          }
                        },
                        onLongPress: () => _toggleSelect(v.id!),
                        onDelete: () {
                          context
                              .read<VocabProvider>()
                              .deleteVocabulary(v.id!);
                        },
                      );
                    },
                  ),
          ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(VocabProvider vocab, ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // 书籍筛选
            ...['全部', ...vocab.bookList].map((book) {
              final isSelected = _selectedBook == book;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(book == '全部' ? '📚 全部' : book,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      )),
                  selected: isSelected,
                  selectedColor: theme.colorScheme.primary.withAlpha(30),
                  checkmarkColor: theme.colorScheme.primary,
                  side: BorderSide(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                  onSelected: (v) {
                    setState(() => _selectedBook = book);
                    final gen = ++_loadGeneration;
                    context.read<VocabProvider>().loadVocabularies(
                          sourceBook:
                              book == '全部' ? null : book,
                        ).then((_) {
                      if (!mounted || gen != _loadGeneration) return;
                      setState(() {});
                    });
                  },
                  visualDensity: VisualDensity.compact,
                ),
              );
            }),
            const SizedBox(width: 8),
            Container(
                width: 1,
                height: 24,
                color: theme.colorScheme.outlineVariant),
            const SizedBox(width: 8),
            // 类型筛选
            ...['全部', '单词', '短语', '句子'].map((type) {
              final isSelected = _selectedType == type;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(type,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      )),
                  selected: isSelected,
                  selectedColor: theme.colorScheme.primary.withAlpha(30),
                  checkmarkColor: theme.colorScheme.primary,
                  side: BorderSide(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                  onSelected: (v) {
                    setState(() => _selectedType = type);
                  },
                  visualDensity: VisualDensity.compact,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
