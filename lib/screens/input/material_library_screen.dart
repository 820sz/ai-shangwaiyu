import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../services/database.dart';
import '../../services/material_library.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/v4/v4_kit.dart';
import 'material_reader_screen.dart';

/// 我的材料库(v5 · P3 第一版):
/// 浏览记录 / 外部导入 **分开管理**(用户 11/04 明确要求),
/// 支持重命名中文标题、删除、隐藏(隐藏存 Hive 黑名单,不动数据库结构)。
class MaterialLibraryScreen extends StatefulWidget {
  const MaterialLibraryScreen({super.key});

  @override
  State<MaterialLibraryScreen> createState() => _MaterialLibraryScreenState();
}

class _MaterialLibraryScreenState extends State<MaterialLibraryScreen> {
  static const String _hiddenKey = 'material_library_hidden';
  List<ShelfItem> _items = const <ShelfItem>[];
  Set<int> _hidden = <int>{};
  bool _loading = true;
  bool _showHidden = false;

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

  List<ShelfItem> get _imported =>
      _items.where((s) => s.origin == 'import').toList();
  List<ShelfItem> get _browsed =>
      _items.where((s) => s.origin != 'import').toList();

  Future<void> _persistHidden() async {
    final box = Hive.box(AppConstants.hiveBoxSettings);
    await box.put(_hiddenKey, _hidden.toList());
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

  Future<void> _delete(ShelfItem s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这篇材料?'),
        content: Text(
          '「${s.titleCn.isNotEmpty ? s.titleCn : s.title}」的正文、阅读进度和译文会一起删除,'
          '不能恢复。',
          style: const TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseService.deleteMaterial(s.id);
    await _load();
  }

  Future<void> _toggleHidden(ShelfItem s) async {
    setState(() {
      if (!_hidden.remove(s.id)) _hidden.add(s.id);
    });
    await _persistHidden();
  }

  void _open(ShelfItem s) {
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: skin.pageBg,
        appBar: V4JellyAppBar(
          title: '我的材料库',
          actions: <Widget>[
            V4IconAction(
              icon: _showHidden ? Icons.visibility : Icons.visibility_off,
              tooltip: _showHidden ? '隐藏已隐藏材料' : '显示已隐藏材料',
              onTap: () => setState(() => _showHidden = !_showHidden),
            ),
            const SizedBox(width: Gap.xs),
          ],
          bottom: TabBar(
            labelColor: skin.ink,
            unselectedLabelColor: skin.inkSoft,
            indicatorColor: skin.accent,
            tabs: const <Widget>[
              Tab(text: '浏览记录'),
              Tab(text: '外部导入'),
            ],
          ),
        ),
        body: _loading
            ? const Center(
                child: Text('正在读取材料库…', style: TextStyle(fontSize: 12)))
            : TabBarView(
                children: <Widget>[
                  _list(_browsed, emptyHint: '还没有浏览过材料。去材料中心挑一篇,读完就会出现在这里。'),
                  _list(_imported, emptyHint: '还没有外部导入的材料。点右上角「导入」把文章/书/链接导进来。'),
                ],
              ),
      ),
    );
  }

  Widget _list(List<ShelfItem> items, {required String emptyHint}) {
    final skin = V4Skin.of(context);
    final visible = items
        .where((s) => _showHidden || !_hidden.contains(s.id))
        .toList()
      ..sort((a, b) => b.id.compareTo(a.id));
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.xl),
          child: Text(
            emptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.6, color: skin.inkSoft),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xl),
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final s = visible[i];
        final hidden = _hidden.contains(s.id);
        return Opacity(
          opacity: hidden ? 0.55 : 1,
          child: AppCard(
            onTap: () => _open(s),
            child: Row(
              children: <Widget>[
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
                        style:
                            TextStyle(fontSize: 10.5, color: skin.inkSoft),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '管理',
                  icon: Icon(Icons.more_horiz, size: 18, color: skin.inkFaint),
                  onSelected: (v) {
                    if (v == 'rename') _rename(s);
                    if (v == 'delete') _delete(s);
                    if (v == 'hide') _toggleHidden(s);
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                        value: 'rename', child: Text('编辑中文标题')),
                    PopupMenuItem<String>(
                      value: 'hide',
                      child: Text(hidden ? '取消隐藏' : '隐藏(不参与推荐)'),
                    ),
                    const PopupMenuItem<String>(
                        value: 'delete', child: Text('删除材料')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
