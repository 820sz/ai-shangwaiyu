import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../models/learner_model.dart';
import '../../services/learner_model_store.dart';
import '../../services/material_source.dart';
import '../../services/material_topics.dart';
import '../../services/original_search.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/waiting.dart';
import 'ai_material_search.dart';
import 'material_import_flow.dart';

/// **一个材料大分类的二级页**(v2.13,用户 2026-10-20 的要求)。
///
/// 用户原话:
/// 「材料中心不要把功能区和子功能区全部塞在一个界面 —— 比如现在的每类材料
///   都是下方展示具体子类 —— 应该是只提供材料分类这种大功能分区,点进去后
///   再提供单独的子分区,这样材料中心就简洁多了,而且只大功能区的情况下,
///   你可以也有发挥前端升级的空间了,软件其他地方同理。」
///
/// 所以:**子分区(内容源筛选 / 换说法找)全在这一页**,首页只留大分类卡。
///
/// 页面结构:
///   ① 题材头图(图标 + 名称 + 一句人话说明)
///   ② 子分区筛选:内容源(公版书/外媒/论文…按源列)
///   ③ 材料列表(左文右图横卡;整卡点进阅读器)
///   ④ 换个说法找(复用 AI 中文检索)
class MaterialCategoryScreen extends StatefulWidget {
  /// 题材(来自 [MaterialTopic.all],也支持用户自定义分区)
  final MaterialTopic topic;

  const MaterialCategoryScreen({super.key, required this.topic});

  @override
  State<MaterialCategoryScreen> createState() => _MaterialCategoryScreenState();
}

class _MaterialCategoryScreenState extends State<MaterialCategoryScreen> {
  /// 当前选中的内容源(空 = 全部源)
  final Set<String> _sources = {};

  LearnerModel _model = LearnerModel();
  List<OriginalHit> _hits = const [];
  bool _loading = true;
  String? _error;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _model = LearnerModelStore.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _hits = const [];
    });
    try {
      // 每个题材自带 2~3 组英文检索词(公版书/arXiv/RSS 三路并行在 OriginalSearch 内)
      final queries = widget.topic.queries.take(2).toList();
      final all = <OriginalHit>[];
      final seen = <String>{};
      final notes = <String>[];
      for (final q in queries) {
        final result = await OriginalSearch.search(
          q,
          category: '其他',
          sourceIds: _sources.isEmpty ? null : _sources.toList(),
        );
        for (final h in result.hits) {
          final key = h.url.trim().isEmpty ? h.title : h.url;
          if (seen.add(key)) all.add(h);
        }
        notes.addAll(result.notes);
      }
      if (!mounted) return;
      setState(() {
        _hits = all;
        _note = notes.toSet().take(2).join(' · ');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 打开一条结果:抓原文 → 入库 → 进阅读器(与材料中心的打开流程是同一个)
  Future<void> _openHit(OriginalHit hit) async {
    await MaterialImportFlow.openHitWithProgress(
      context,
      hit: hit,
      model: _model,
    );
    if (!mounted) return;
    // 打开过就算"在读":回刷一次列表里的进度/封面
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.topic.label)),
      body: ListView(
        padding: Insets.page,
        children: [
          // ① 题材头图:一眼知道"这个分类里是什么"
          AppCard(
            variant: AppCardVariant.hero,
            padding: const EdgeInsets.all(Gap.md),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(18),
                    borderRadius: BorderRadius.circular(Radii.control + 2),
                  ),
                  child: Icon(widget.topic.icon, size: 28, color: cs.primary),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.topic.label,
                        style: AppFont.headingStyle.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.topic.description,
                        style: AppFont.metaStyle.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // ② 子分区:内容源(点一下只在这个源里找)
          const AppSectionHeader(title: '在这些来源里找', indexLabel: '01'),
          Wrap(
            spacing: Gap.xs,
            runSpacing: Gap.xs,
            children: [
              for (final s in _sourceChoices)
                FilterChip(
                  label: Text(s.label, style: const TextStyle(fontSize: 12)),
                  selected: _sources.contains(s.id),
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _sources.add(s.id);
                      } else {
                        _sources.remove(s.id);
                      }
                    });
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  _loading
                      ? '正在按「${widget.topic.label}」找材料…'
                      : '找到 ${_hits.length} 篇${_note.isEmpty ? '' : ' · $_note'}',
                  style: AppFont.metaStyle.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重新找'),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),

          // ③ 材料列表
          if (_loading)
            const SkeletonLines(lines: 5, seed: 3)
          else if (_error != null)
            AppErrorCard(message: _error!, onRetry: _load)
          else if (_hits.isEmpty)
            const AppEmptyState(
              icon: Icons.travel_explore_outlined,
              title: '这个范围里暂时没找到',
              hint: '取消几个来源筛选,或者换个说法让 AI 去找',
            )
          else
            for (var i = 0; i < _hits.length; i++)
              AppStagger(index: i, child: _hitCard(cs, _hits[i])),

          const SizedBox(height: Gap.md),
          // ④ 换个说法找:AI 中文检索(本页不重造轮子)
          AppCard(
            variant: AppCardVariant.compact,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AiMaterialSearchScreen(
                  category: widget.topic.label,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 20, color: cs.primary),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Text(
                    '用中文说需求,让 AI 去公开源找${widget.topic.label}的材料',
                    style: AppFont.metaStyle.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: cs.outline),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }

  /// 一条材料:左文右图横卡(与材料库/发现页同一形态)
  Widget _hitCard(ColorScheme cs, OriginalHit hit) {
    final source = MaterialSourceService.sourceOf(hit.sourceId);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: AppWideCard(
        title: hit.title,
        subtitle: hit.note.isEmpty ? null : hit.note,
        dateText: source?.label ?? hit.sourceId,
        tags: [
          AppTag('原文', tone: AppTagTone.primary),
          if (hit.author.isNotEmpty) AppTag(hit.author),
        ],
        imageUrl: hit.imageUrl,
        seed: hit.title,
        onTap: () => _openHit(hit),
      ),
    );
  }

  /// 内容源筛选项(只列真实可用的几类,不铺满)
  List<({String id, String label})> get _sourceChoices {
    final out = <({String id, String label})>[];
    for (final s in MaterialSourceService.sources) {
      if (s.kind == 'book') {
        out.add((id: s.id, label: '公版书'));
      } else if (s.kind == 'news') {
        out.add((id: s.id, label: '外媒'));
      } else if (s.kind == 'paper') {
        out.add((id: s.id, label: '论文'));
      }
    }
    return out.take(6).toList();
  }
}
