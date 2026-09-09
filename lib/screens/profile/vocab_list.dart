import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/vocab_provider.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VocabProvider>().loadVocabularies(
            sourceBook:
                _selectedBook == '全部' ? null : _selectedBook,
          );
    });
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final provider = context.read<VocabProvider>();
    await Future.wait(_selectedIds.toList().map((id) => provider.deleteVocabulary(id)));
    if (mounted) _exitSelectionMode();
  }

  Future<void> _batchMove() async {
    if (_selectedIds.isEmpty) return;
    // 1. 选目标分类
    final category = await showCategoryPicker(context);
    if (category == null || !mounted) return;
    // 2. 选子分类信息
    final subInfo = await showSubCategoryInput(context, category: category);
    if (!mounted) return;

    final provider = context.read<VocabProvider>();
    await Future.wait(_selectedIds.toList().map((id) =>
        provider.updateVocabulary(id,
            category: category,
            materialPath: subInfo?.materialPath,
            sourceBook: subInfo?.materialName,
            sourcePage: subInfo?.sourcePage)));
    if (mounted) {
      final count = _selectedIds.length; // 先存计数，再清选择
      final hasSourceBookOverwrite = subInfo?.materialName != null;
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hasSourceBookOverwrite
              ? '已将 $count 个生词移至「$category」，出处已更新'
              : '已将 $count 个生词移至「$category」'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 1,
        title: _selectionMode
            ? Text('已选 ${_selectedIds.length} 项')
            : _showSearch
                ? TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: const TextStyle(
                      color: Color(0xFF1A1A2E),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    cursorColor: const Color(0xFF1A1A2E),
                    cursorWidth: 2,
                    decoration: const InputDecoration(
                      hintText: '搜索生词…',
                      hintStyle: TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      filled: false,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                    onSubmitted: (_) => setState(() {}),
                  )
                : const Text('生词本',
                    style: TextStyle(
                      color: Color(0xFF1A1A2E),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    )),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        actions: [
          if (_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              tooltip: '移动到其他分类',
              onPressed: _batchMove,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '批量删除',
              onPressed: _batchDelete,
            ),
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
              onPressed: () {
                setState(() {
                  if (_selectedIds.length == items.length) {
                    _selectedIds.clear();
                    _selectionMode = false;
                  } else {
                    _selectedIds.addAll(items.map((v) => v.id!).toList());
                  }
                });
              },
            ),
          ] else ...[
            IconButton(
              icon: Icon(_showSearch ? Icons.close : Icons.search),
              onPressed: () {
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
        ],
      ),
      body: Column(
        children: [
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
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
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
                      style: TextStyle(color: Colors.grey[400]),
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
                        color: isSelected ? const Color(0xFF1A1A2E) : const Color(0xFF555555),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      )),
                  selected: isSelected,
                  selectedColor: const Color(0xFF1A1A2E).withAlpha(18),
                  checkmarkColor: const Color(0xFF1A1A2E),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF1A1A2E) : Colors.grey[300]!,
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
            Container(width: 1, height: 24, color: Colors.grey[300]),
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
                        color: isSelected ? const Color(0xFF1A1A2E) : const Color(0xFF555555),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      )),
                  selected: isSelected,
                  selectedColor: const Color(0xFF1A1A2E).withAlpha(18),
                  checkmarkColor: const Color(0xFF1A1A2E),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF1A1A2E) : Colors.grey[300]!,
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
