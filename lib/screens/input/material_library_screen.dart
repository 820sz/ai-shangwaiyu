import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../services/database.dart';
import '../../services/material_library.dart';
import '../../services/material_source.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/v4/v4_kit.dart';
import 'material_reader_screen.dart';

/// 一个分组(浏览记录按来源 / 外部导入按用户分组名)
class ShelfGroup {
  final String id;
  final String label;
  final List<ShelfItem> items;
  const ShelfGroup({required this.id, required this.label, required this.items});
}

/// 浏览记录分组(纯函数,可单测):按材料来源分组,组内按 id 倒序。
List<ShelfGroup> groupBrowsedBySource(List<ShelfItem> items) {
  final map = <String, List<ShelfItem>>{};
  for (final it in items) {
    final src = it.source.isEmpty ? 'unknown' : it.source;
    map.putIfAbsent(src, () => <ShelfItem>[]).add(it);
  }
  final groups = <ShelfGroup>[];
  for (final e in map.entries) {
    final label = MaterialSourceService.sourceOf(e.key)?.label ??
        (e.key == 'unknown' ? '未知来源' : e.key);
    final list = <ShelfItem>[...e.value]..sort((a, b) => b.id.compareTo(a.id));
    groups.add(ShelfGroup(id: 'src:${e.key}', label: label, items: list));
  }
  groups.sort((a, b) => b.items.length.compareTo(a.items.length));
  return groups;
}

/// 外部导入分组(纯函数,可单测):按材料分组名(可为空)分组,组内按 id 倒序。
List<ShelfGroup> groupImportedByGroupName(List<ShelfItem> items) {
  final map = <String, List<ShelfItem>>{};
  for (final it in items) {
    final g = (it.group ?? '').trim();
    map.putIfAbsent(g, () => <ShelfItem>[]).add(it);
  }
  final groups = <ShelfGroup>[];
  for (final e in map.entries) {
    final list = <ShelfItem>[...e.value]..sort((a, b) => b.id.compareTo(a.id));
    groups.add(ShelfGroup(
      id: 'grp:${e.key}',
      label: e.key.isEmpty ? '未分组' : e.key,
      items: list,
    ));
  }
  groups.sort((a, b) {
    // "未分组"排最后
    if (a.label == '未分组') return 1;
    if (b.label == '未分组') return -1;
    return a.label.compareTo(b.label);
  });
  return groups;
}

/// 我的材料库(v5 · P3 收尾版)。
///
/// 用户 11/04 明确:**浏览记录和外部导入必须分开管理**。本页三个 tab:
/// - 浏览记录:按来源分组、可折叠;支持重命名/隐藏/删除;
/// - 外部导入:按用户分组名分组、可折叠;支持重命名/隐藏/删除;
/// - 已隐藏:隐藏过的材料在这里恢复或彻底删除。
///
/// 全部操作复用现有 DB 能力(setMaterialTitleCn / deleteMaterial)+ Hive 隐藏黑名单,
/// 不新增数据库结构。
class MaterialLibraryScreen extends StatefulWidget {
  const MaterialLibraryScreen({super.key});

  @override
  State<MaterialLibraryScreen> createState() => _MaterialLibraryScreenState();
}

class _MaterialLibraryScreenState extends State<MaterialLibraryScreen> {
  static const String _hiddenKey = 'material_library_hidden';
  List<ShelfItem> _items = const <ShelfItem>[];
  Set<int> _hidden = <int>{};
  final Set<String> _collapsed = <String>{};
  final Set<int> _selected = <int>{};
  bool _selecting = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    var items = <ShelfItem>[];
    try {
      items = await MaterialLibrary.shelf(limit: 500);
    } catch (_) {}
    final box = Hive.box(AppConstants.hiveBoxSettings);
    final raw = box.get(_hiddenKey);
    final hidden = <int>{
      if (raw is List) for (final v in raw) if (v is int) v,
    };
    if (!mounted) return;
    setState(() {
      _items = items;
      _hidden = hidden;
      _loading = false;
    });
  }

  List<ShelfItem> get _browsed =>
      _items.where((s) => s.origin != 'import').toList();
  List<ShelfItem> get _imported =>
      _items.where((s) => s.origin == 'import').toList();
  List<ShelfItem> get _hiddenItems =>
      _items.where((s) => _hidden.contains(s.id)).toList();

  Future<void> _persistHidden() async {
    await Hive.box(AppConstants.hiveBoxSettings)
        .put(_hiddenKey, _hidden.toList());
  }

  void _toggleCollapse(String id) {
    setState(() {
      if (!_collapsed.remove(id)) _collapsed.add(id);
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _rename(ShelfItem s) async {
    final ctrl = TextEditingController(
      text: s.titleCn.isNotEmpty ? s.titleCn : s.title,
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑中文标题'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '给这篇材料起个中文名',
            isDense: true,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || text.isEmpty) return;
    await DatabaseService.setMaterialTitleCn(s.id, text);
    await _load();
  }

  /// 删除/隐藏二选一:用户 11/04 要求"浏览记录要能管理",先给可逆的隐藏。
  Future<void> _disposeOne(ShelfItem s) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('处理「${s.titleCn.isNotEmpty ? s.titleCn : s.title}」'),
        content: const Text(
          '隐藏:从列表和推荐里移走,可在「已隐藏」里恢复;\n'
          '彻底删除:正文、阅读进度和译文一起删掉,不能恢复。',
          style: TextStyle(fontSize: 12.5, height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'hide'),
            child: const Text('隐藏'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (action == 'hide') {
      setState(() => _hidden.add(s.id));
      await _persistHidden();
    } else if (action == 'delete') {
      await DatabaseService.deleteMaterial(s.id);
      await _load();
    }
  }

  Future<void> _batchDispose({required bool hide}) async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(hide ? '隐藏 $count 篇材料?' : '彻底删除 $count 篇材料?'),
        content: Text(
          hide
              ? '隐藏后不在列表与推荐中出现,可在「已隐藏」里恢复。'
              : '正文、阅读进度和译文会一起删除,不能恢复。',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hide ? '隐藏' : '删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (hide) {
      setState(() => _hidden.addAll(_selected));
      await _persistHidden();
    } else {
      for (final id in _selected) {
        await DatabaseService.deleteMaterial(id);
      }
      await _load();
    }
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  void _open(ShelfItem s) {
    if (_selecting) {
      _toggleSelect(s.id);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialReaderScreen(materialId: s.id),
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final browsing = _browsed;
    final imported = _imported;
    final hidden = _hiddenItems;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: skin.pageBg,
        appBar: V4JellyAppBar(
          title: _selecting ? '已选 ${_selected.length} 篇' : '我的材料库',
          actions: <Widget>[
            if (_selecting) ...<Widget>[
              V4IconAction(
                icon: Icons.close_rounded,
                tooltip: '退出多选',
                onTap: () => setState(() {
                  _selecting = false;
                  _selected.clear();
                }),
              ),
              const SizedBox(width: Gap.xs),
            ] else if (browsing.isNotEmpty || imported.isNotEmpty)
              V4IconAction(
                icon: Icons.checklist,
                tooltip: '多选管理',
                onTap: () => setState(() => _selecting = true),
              ),
            const SizedBox(width: Gap.xs),
          ],
          bottom: TabBar(
            labelColor: skin.ink,
            unselectedLabelColor: skin.inkSoft,
            indicatorColor: skin.accent,
            tabs: <Widget>[
              Tab(text: '浏览记录 ${browsing.length}'),
              Tab(text: '外部导入 ${imported.length}'),
              Tab(text: '已隐藏 ${hidden.length}'),
            ],
          ),
        ),
        body: _loading
            ? const Center(
                child: Text('正在读取材料库…', style: TextStyle(fontSize: 12)))
            : Column(
                children: <Widget>[
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        _groupedList(
                          groups: groupBrowsedBySource(browsing),
                          emptyHint: '还没有浏览过材料。去材料中心挑一篇,读完就会出现在这里。',
                        ),
                        _groupedList(
                          groups: groupImportedByGroupName(imported),
                          emptyHint: '还没有外部导入的材料。去材料中心右上角「导入」把文章/书/链接导进来。',
                        ),
                        _hiddenList(hidden),
                      ],
                    ),
                  ),
                  if (_selecting)
                    SafeArea(
                      top: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(
                            Gap.page, Gap.xs, Gap.page, Gap.sm),
                        decoration: BoxDecoration(
                          color: skin.surface,
                          border: Border(
                              top: BorderSide(color: skin.hairline)),
                        ),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _selected.isEmpty
                                    ? null
                                    : () => _batchDispose(hide: true),
                                icon: const Icon(
                                    Icons.visibility_off_outlined,
                                    size: 16),
                                label: const Text('隐藏'),
                              ),
                            ),
                            const SizedBox(width: Gap.xs),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _selected.isEmpty
                                    ? null
                                    : () => _batchDispose(hide: false),
                                icon: const Icon(Icons.delete_outline, size: 16),
                                label: const Text('删除'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _groupedList({
    required List<ShelfGroup> groups,
    required String emptyHint,
  }) {
    final skin = V4Skin.of(context);
    final visibleGroups = groups
        .map((g) => ShelfGroup(
              id: g.id,
              label: g.label,
              items: g.items
                  .where((s) => !_hidden.contains(s.id))
                  .toList(growable: false),
            ))
        .where((g) => g.items.isNotEmpty)
        .toList();
    if (visibleGroups.isEmpty) {
      return _empty(emptyHint);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xl),
      children: <Widget>[
        for (final g in visibleGroups) ...<Widget>[
          InkWell(
            onTap: () => _toggleCollapse(g.id),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: skin.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.folder_outlined, size: 16, color: skin.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${g.label} · ${g.items.length}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: skin.inkSoft,
                      ),
                    ),
                  ),
                  Icon(
                    _collapsed.contains(g.id)
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    size: 18,
                    color: skin.inkFaint,
                  ),
                ],
              ),
            ),
          ),
          if (!_collapsed.contains(g.id)) ...<Widget>[
            const SizedBox(height: Gap.xs),
            for (final s in g.items) _card(s, hideAction: _disposeOne),
          ],
          const SizedBox(height: Gap.md),
        ],
      ],
    );
  }

  Widget _hiddenList(List<ShelfItem> items) {
    final skin = V4Skin.of(context);
    if (items.isEmpty) {
      return _empty('没有隐藏的材料。\n隐藏的材料会留在这里,随时能恢复。');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xl),
      children: <Widget>[
        Text(
          '隐藏的材料不参与列表与推荐;恢复后会回到原来的分组。',
          style: TextStyle(fontSize: 11, height: 1.5, color: skin.inkSoft),
        ),
        const SizedBox(height: Gap.sm),
        for (final s in items)
          _card(
            s,
            trailing: <Widget>[
              TextButton(
                onPressed: () async {
                  setState(() => _hidden.remove(s.id));
                  await _persistHidden();
                },
                child: const Text('恢复'),
              ),
              TextButton(
                onPressed: () async {
                  await DatabaseService.deleteMaterial(s.id);
                  setState(() => _hidden.remove(s.id));
                  await _load();
                },
                child: const Text('删除'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _card(
    ShelfItem s, {
    void Function(ShelfItem)? hideAction,
    List<Widget>? trailing,
  }) {
    final skin = V4Skin.of(context);
    final hidden = _hidden.contains(s.id);
    final selected = _selected.contains(s.id);
    return Opacity(
      opacity: hidden ? 0.55 : 1,
      child: GestureDetector(
        onLongPress: () {
          setState(() {
            _selecting = true;
            _toggleSelect(s.id);
          });
        },
        child: AppCard(
          onTap: () => _open(s),
          child: Row(
          children: <Widget>[
            if (_selecting)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? skin.accent : skin.inkFaint,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    s.titleCn.isNotEmpty ? s.titleCn : s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: skin.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      if (s.origin == 'import') '导入',
                      if (s.wordCount > 0) '${s.wordCount} 词',
                      if (s.cefr.isNotEmpty) s.cefr,
                      if (s.percent > 1)
                        '已读 ${s.percent.toStringAsFixed(0)}%',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: skin.inkSoft),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              ...trailing
            else if (!_selecting)
              PopupMenuButton<String>(
                tooltip: '管理',
                icon: Icon(Icons.more_horiz, size: 18, color: skin.inkFaint),
                onSelected: (v) {
                  if (v == 'rename') _rename(s);
                  if (v == 'dispose') hideAction?.call(s);
                },
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                      value: 'rename', child: Text('编辑中文标题')),
                  const PopupMenuItem<String>(
                      value: 'dispose', child: Text('隐藏 / 删除')),
                ],
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _empty(String hint) {
    final skin = V4Skin.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Text(
          hint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.6, color: skin.inkSoft),
        ),
      ),
    );
  }
}
