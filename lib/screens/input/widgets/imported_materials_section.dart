import 'package:flutter/material.dart';

import '../../../config/design_tokens.dart';
import '../../../config/theme.dart';
import '../../../services/database.dart';
import '../../../services/learner_model_store.dart';
import '../../../services/material_library.dart';
import '../../../widgets/app_ui.dart';
import '../../../widgets/material_cover.dart';
import '../../../widgets/waiting.dart';
import '../material_import_flow.dart';
import '../material_reader_screen.dart';

/// 「材料导入」(v2.9,用户 10/2 第 5 条)。
///
/// 用户原话:"'我的学习材料'现在本质是个**词汇本**,需改为
/// **'材料导入'**(支持用户外部导入材料,并保存,软件内阅读,比如我导入一本新视野的
/// 电子版教材——所以你要做好**分类、前端、数据库**等问题)
/// **'我的词汇本'**(然后子功能就是现有的教程、等等这些逻辑)"
///
/// 于是原来的「我的学习材料」一分为二:
/// - **本组件 = 材料导入**:外部导入的材料本体(教材 / 论文 / 文章),
///   可以分组(如「新视野教材」)、重命名分组、删除分组,点开就是阅读器;
/// - `MyMaterialsSection` = 我的词汇本:原有按分类/教材的**生词**逻辑,原样保留。
///
/// 数据:`materials` 表(v2.9 新增 `origin` 与 `group_name` 两列)。
/// 分类是**用户自己定的分组名**,不是我们硬编的枚举 —— 他导一本《新视野》就叫
/// 「新视野教材」,导论文就叫「论文」,软件不去猜。
class ImportedMaterialsSection extends StatefulWidget {
  const ImportedMaterialsSection({super.key});

  @override
  State<ImportedMaterialsSection> createState() =>
      _ImportedMaterialsSectionState();
}

class _ImportedMaterialsSectionState extends State<ImportedMaterialsSection> {
  List<ShelfItem> _items = const [];
  bool _loading = true;
  bool _open = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await MaterialLibrary.shelf(limit: 200);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      debugPrint('读取已导入材料失败: $e');
    }
  }

  /// 分组:先按用户自定义分组名,其余按来源归一类
  Map<String, List<ShelfItem>> get _groups {
    final out = <String, List<ShelfItem>>{};
    for (final m in _items) {
      final key = (m.group ?? '').trim().isEmpty ? _originLabel(m) : m.group!.trim();
      out.putIfAbsent(key, () => []).add(m);
    }
    // 组名按材料数倒序,"其它"垫底
    final keys = out.keys.toList()
      ..sort((a, b) {
        if (a == '其它材料') return 1;
        if (b == '其它材料') return -1;
        return out[b]!.length.compareTo(out[a]!.length);
      });
    return {for (final k in keys) k: out[k]!};
  }

  String _originLabel(ShelfItem m) {
    if (m.kind == 'book') return '公版书';
    if (m.kind == 'paper') return '论文';
    if (m.kind == 'news' || m.kind == 'podcast') return '外刊';
    return '其它材料';
  }

  Future<void> _import() async {
    final ingested = await MaterialImportFlow.run(
      context,
      model: LearnerModelStore.load(),
      dialogTitle: '导入材料',
    );
    if (ingested == null || !mounted) return;
    await _load();
    if (!mounted) return;
    // 导完立刻打开阅读器:用户导材料的目的就是读,不该再点一次
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialReaderScreen(materialId: ingested.materialId),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _openReader(int id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MaterialReaderScreen(materialId: id)),
    );
    if (!mounted) return;
    await _load();
  }

  /// 给材料分组/改名(用户 5 条说的"分类")
  Future<void> _setGroup(ShelfItem m) async {
    final ctrl = TextEditingController(text: m.group ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归到哪个分类?'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分类名',
            hintText: '如:新视野教材 / 考研阅读 / 论文',
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
    if (name == null || !mounted) return;
    await DatabaseService.setMaterialGroup(m.id, name);
    if (!mounted) return;
    await _load();
  }

  /// 整组操作:重命名(改名所有同组材料)/ 删除分组(只解组,不删材料)
  Future<void> _groupActions(String group, List<ShelfItem> items) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text('重命名「$group」'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('解散这个分组(材料都留着)'),
              subtitle: const Text('材料会回到按来源自动分的组里'),
              onTap: () => Navigator.pop(ctx, 'detach'),
            ),
            const SizedBox(height: Gap.xs),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'rename') {
      final ctrl = TextEditingController(text: group);
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重命名分组'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
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
      if (name == null || !mounted) return;
      for (final m in items) {
        await DatabaseService.setMaterialGroup(m.id, name);
      }
    } else {
      for (final m in items) {
        await DatabaseService.setMaterialGroup(m.id, null);
      }
    }
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final groups = _groups;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行:点标题收放(与其他长区块一致)
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _open ? 0 : -0.25,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(Icons.expand_more,
                        size: 20, color: _open ? null : muted),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.upload_file_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('材料导入',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          _loading
                              ? '正在读取…'
                              : (_items.isEmpty
                                  ? '还没有导入的材料 — 教材、论文、文章都能导进来读'
                                  : '已导入 ${_items.length} 份 · ${groups.length} 个分类'),
                          style: TextStyle(fontSize: 11.5, color: muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('导入'),
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            if (_loading)
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: SkeletonLines(lines: 2, seed: 4),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '可以导入:TXT / MD 文件、粘贴文本、图片(识别成文本)、网页链接。'
                      '导入时填个分类名(如「新视野教材」),以后就按分类找。',
                      style: TextStyle(fontSize: 11.5, height: 1.5, color: muted),
                    ),
                    const SizedBox(height: Gap.xs),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _import,
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text('导入第一份材料'),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final entry in groups.entries)
                _buildGroup(theme, muted, entry.key, entry.value),
          ],
        ],
      ),
    );
  }

  Widget _buildGroup(
    ThemeData theme,
    Color muted,
    String group,
    List<ShelfItem> items,
  ) {
    final custom = items.any((m) => (m.group ?? '').trim().isNotEmpty);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: custom,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        leading: Icon(
          custom ? Icons.folder : Icons.folder_outlined,
          size: 20,
          color: custom ? AppTheme.amber(context) : muted,
        ),
        title: Text(group, style: const TextStyle(fontSize: 14)),
        subtitle: Text('${items.length} 份材料',
            style: TextStyle(fontSize: 11.5, color: muted)),
        children: [
          for (final m in items) _buildRow(theme, muted, m),
          if (custom)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: Gap.xs,
                runSpacing: Gap.xs,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.drive_file_rename_outline, size: 15),
                    label: const Text('重命名分组'),
                    onPressed: () => _groupActions(group, items),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.folder_off_outlined, size: 15),
                    label: const Text('解散分组'),
                    onPressed: () => _groupActions(group, items),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(ThemeData theme, Color muted, ShelfItem m) {
    final lv = MaterialLevel.of(m.cefr, kind: m.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: InkWell(
        borderRadius: Radii.controlRadius,
        onTap: () => _openReader(m.id),
        child: Row(
          children: [
            MaterialCover(
              seed: m.title,
              kind: m.kind,
              width: 52,
              height: 52,
              radius: Radii.control,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Lv$lv · ${m.wordCount} 词 · 约 ${m.estMinutes} 分钟 · ${m.progressLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '改分类',
              icon: const Icon(Icons.folder_outlined, size: 16),
              onPressed: () => _setGroup(m),
            ),
            Icon(Icons.chevron_right, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}
