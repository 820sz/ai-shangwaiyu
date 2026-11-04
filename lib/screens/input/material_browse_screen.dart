import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../services/material_library.dart';
import '../../services/material_need.dart';
import '../../services/material_prefs.dart';
import '../../services/material_taxonomy.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/v4/v4_kit.dart';
import 'material_discover_screen.dart';
import 'material_reader_screen.dart';

/// 材料中心二级浏览页(v5 · P2 骨架):
/// 同一个页面承载 **按需求 / 按题材 / 按形式 / 按场景** 四个维度 ——
/// 顶部子分类多选,下面材料列表,排序统一走 [MaterialNeed.rank](全局推送口径)。
///
/// 说明(诚实标注):
/// - 按需求:难度档 + 形式 + 目标 → 保存后影响全 App 推送(写 MaterialPrefs);
/// - 按形式:严格按材料 kind 过滤;
/// - 按题材/按场景:当前按标题关键词做**初步筛选**,AI 补长尾在下一阶段接入
///   (先把入口与结构立住,不假装完整)。
class MaterialBrowseScreen extends StatefulWidget {
  final MaterialDirection direction;
  final String? initialSubtopic;

  const MaterialBrowseScreen({
    super.key,
    required this.direction,
    this.initialSubtopic,
  });

  @override
  State<MaterialBrowseScreen> createState() => _MaterialBrowseScreenState();
}

class _MaterialBrowseScreenState extends State<MaterialBrowseScreen> {
  late MaterialDirectionDef _def;
  MaterialNeed _need = const MaterialNeed();
  List<ShelfItem> _items = const <ShelfItem>[];
  final Set<String> _selected = <String>{};
  MaterialBand _band = MaterialBand.any;
  final Set<String> _kinds = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _def = MaterialTaxonomy.of(widget.direction);
    if (widget.initialSubtopic != null) {
      _selected.add(widget.initialSubtopic!);
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    var items = <ShelfItem>[];
    final need = MaterialNeed.load();
    try {
      items = await MaterialLibrary.shelf(limit: 300);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _need = need;
      _band = need.band;
      _kinds
        ..clear()
        ..addAll(need.kinds);
      _items = need.rank(items);
      _loading = false;
    });
  }

  /// 当前可见材料:需求页不过滤(全按需求排序);题材/场景按标题关键词初步过滤。
  List<ShelfItem> get _visible {
    if (widget.direction == MaterialDirection.need) return _items;
    if (widget.direction == MaterialDirection.form) {
      final allowed = <String>{};
      for (final id in _selected) {
        final sub = MaterialTaxonomy.subtopicOf(MaterialDirection.form, id);
        allowed.addAll(sub?.kinds ?? const <String>{});
      }
      if (allowed.isEmpty) return _items;
      return _items.where((it) => allowed.contains(it.kind)).toList();
    }
    // 题材 / 场景:标题关键词匹配(轻量初筛)
    final keys = <String>[];
    for (final id in _selected) {
      final sub = MaterialTaxonomy.subtopicOf(widget.direction, id);
      keys.addAll(sub?.queries ?? const <String>[]);
      if (sub != null) keys.add(sub.label);
    }
    if (keys.isEmpty) return _items;
    final lowered = keys.map((k) => k.toLowerCase()).toList();
    final out = _items.where((it) {
      final hay = '${it.title} ${it.titleCn}'.toLowerCase();
      return lowered.any((k) => k.isNotEmpty && hay.contains(k));
    }).toList();
    return out;
  }

  Future<void> _saveNeed() async {
    await MaterialPrefs.load().copyWith(band: _band, kinds: _kinds).save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('需求已保存:全 App 的材料会按它排序/推荐'),
        behavior: SnackBarBehavior.floating,
      ));
    await _load();
  }

  void _openReader(ShelfItem s) {
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
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: _def.label,
        actions: <Widget>[
          V4IconAction(
            icon: Icons.refresh,
            tooltip: '重新加载',
            onTap: () => _load(),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Text('正在读取材料…', style: TextStyle(fontSize: 12)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Gap.page, Gap.sm, Gap.page, Gap.xl),
              children: <Widget>[
                Text(
                  _def.subtitle,
                  style: TextStyle(
                      fontSize: 11.5, height: 1.5, color: skin.inkSoft),
                ),
                const SizedBox(height: Gap.sm),
                if (widget.direction == MaterialDirection.need)
                  _needEditor(skin)
                else
                  _subtopicChips(skin),
                const SizedBox(height: Gap.sm),
                if (widget.direction == MaterialDirection.need)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saveNeed,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('保存需求并查看结果'),
                    ),
                  ),
                const SizedBox(height: Gap.md),
                Row(
                  children: <Widget>[
                    Text(
                      '材料 ${_visible.length} 篇',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: skin.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    if (widget.direction != MaterialDirection.need)
                      Text(
                        '按需求排序',
                        style: TextStyle(
                            fontSize: 10.5, color: skin.inkFaint),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                if (_visible.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: skin.surface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      '这个方向还没有材料。可以用「导入」把外部文章/书导进来,'
                      '或等下一版接入的「AI 补长尾」按这个方向去找。',
                      style: TextStyle(
                          fontSize: 11.5, height: 1.6, color: skin.inkSoft),
                    ),
                  )
                else
                  for (final s in _visible)
                    AppWideCard(
                      title: s.titleCn.isNotEmpty ? s.titleCn : s.title,
                      subtitle: [
                        if (s.wordCount > 0) '${s.wordCount} 词',
                        if (s.estMinutes > 0) '约 ${s.estMinutes} 分钟',
                        if (s.cefr.isNotEmpty) s.cefr,
                      ].join(' · '),
                      autoArt: true,
                      seed: s.title,
                      kind: s.kind,
                      imageUrl: s.coverUrl,
                      level: s.cefr.isEmpty ? null : s.cefr,
                      tags: <Widget>[
                        if (s.percent > 1)
                          AppTag('${s.percent.toStringAsFixed(0)}%'),
                        if (s.origin == 'import') const AppTag('导入'),
                      ],
                      onTap: () => _openReader(s),
                    ),
                const SizedBox(height: Gap.md),
                _aiLongTailCard(skin),
              ],
            ),
    );
  }

  /// 按方向补长尾(用户 11/04):分类找到后还能"按这个方向再找"。
  /// 走 v3 的真实爬取流程(AI 出检索计划 → DeepSeek 官方搜索/公开源 → 抓回正文),
  /// 不再用旧的"AI 凭空编写推荐"。
  String _aiCategoryLabel() {
    final picked = _def.subtopics
        .where((s) => _selected.contains(s.id))
        .map((s) => s.label)
        .join('、');
    if (picked.isNotEmpty) return picked;
    return _def.label.replaceAll('找材料', '');
  }

  void _openAiSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialDiscoverScreen(
          initialNeed: '按「${_aiCategoryLabel()}」方向找真实材料:'
              '要能抓到原文,难度适配我的水平',
        ),
      ),
    );
  }

  Widget _aiLongTailCard(V4Skin skin) {
    return InkWell(
      onTap: _openAiSearch,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: skin.surfaceAlt,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.auto_awesome, size: 18, color: skin.accent),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '没找到想要的?让 AI 补长尾',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: skin.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '按「${_aiCategoryLabel()}」这个方向,用公开源 + AI 再找一批',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: skin.inkSoft),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: skin.inkFaint),
          ],
        ),
      ),
    );
  }

  Widget _subtopicChips(V4Skin skin) {
    return Wrap(
      spacing: Gap.xs,
      runSpacing: Gap.xs,
      children: <Widget>[
        for (final sub in _def.subtopics)
          _chip(
            skin,
            label: sub.label,
            selected: _selected.contains(sub.id),
            onTap: () => setState(() {
              if (!_selected.remove(sub.id)) _selected.add(sub.id);
            }),
          ),
      ],
    );
  }

  Widget _needEditor(V4Skin skin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('难度档(会同步给全 App 的材料推荐/难度标签)',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: skin.inkSoft)),
        const SizedBox(height: Gap.xs),
        Wrap(
          spacing: Gap.xs,
          runSpacing: Gap.xs,
          children: <Widget>[
            for (final band in MaterialBand.values)
              _chip(
                skin,
                label: band.label,
                selected: _band == band,
                onTap: () => setState(() => _band = band),
              ),
          ],
        ),
        if (_need.goals.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          Text('学习目标(来自助理访谈,只读)',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: skin.inkSoft)),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: <Widget>[
              for (final g in _need.goals) AppTag(g),
            ],
          ),
        ],
        const SizedBox(height: Gap.sm),
        Text('按形式(可多选;不选=不限)',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: skin.inkSoft)),
        const SizedBox(height: Gap.xs),
        Wrap(
          spacing: Gap.xs,
          runSpacing: Gap.xs,
          children: <Widget>[
            for (final entry in MaterialPrefs.kindLabels.entries)
              _chip(
                skin,
                label: entry.value,
                selected: _kinds.contains(entry.key),
                onTap: () => setState(() {
                  if (!_kinds.remove(entry.key)) _kinds.add(entry.key);
                }),
              ),
          ],
        ),
      ],
    );
  }

  Widget _chip(
    V4Skin skin, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? skin.accent.withValues(alpha: 0.13)
              : skin.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? skin.accent.withValues(alpha: 0.5)
                : skin.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? skin.accent : skin.inkSoft,
          ),
        ),
      ),
    );
  }
}
