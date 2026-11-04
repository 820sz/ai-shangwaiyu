import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../services/learner_model_store.dart';
import '../../services/material_library.dart';
import '../../services/material_need.dart';
import '../../services/material_source.dart';
import '../../services/material_taxonomy.dart';
import '../../services/original_search.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/v4/v4_kit.dart';
import 'material_browse_screen.dart';
import 'material_hub/material_hub_home_view.dart';
import 'material_import_flow.dart';
import 'material_library_screen.dart';
import 'material_reader_screen.dart';

// 旧版材料中心里仍被「输入首页」与测试共用的公共组件(BandAdviceBanner /
// warmUpWordFrequency)做**选择性再导出** —— 它们与材料中心入口无关,只是历史位置
// 在旧文件里。新首页不重写它们,避免动输入首页与既有测试。
export 'legacy_material_center_screen.dart'
    show BandAdviceBanner, warmUpWordFrequency;

/// 材料中心 v5(2026-11-04 用户拍板架构后重写)。
///
/// 首页只保留:**今日精读(左右切)** + **按需求** + **按题材/按形式/按场景** +
/// **我的材料库** 五个入口;原来塞在首页的 我的需求/分类网格/今日推荐/书架/材料库/
/// 更多找法 全部拆走(需求合并进"按需求",分类进二级页,书架回书架页,库进管理页)。
///
/// 数据与排序:所有列表统一走 [MaterialNeed.rank] —— "按需求"是**全局推送机制**,
/// 不只是某个页面(用户 11/04 明确要求)。
class MaterialCenterScreen extends StatefulWidget {
  const MaterialCenterScreen({super.key});

  @override
  State<MaterialCenterScreen> createState() => _MaterialCenterScreenState();
}

class _MaterialCenterScreenState extends State<MaterialCenterScreen> {
  MaterialNeed _need = const MaterialNeed();
  List<ShelfItem> _shelf = const <ShelfItem>[];
  List<MaterialHubDaily> _daily = const <MaterialHubDaily>[];
  bool _loading = true;
  bool _loadingDaily = false;
  int _shuffle = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    MaterialNeed need = const MaterialNeed();
    var shelf = <ShelfItem>[];
    try {
      need = MaterialNeed.load();
      shelf = await MaterialLibrary.shelf(limit: 300);
      shelf = need.rank(shelf);
    } catch (_) {
      // 读库失败不阻塞页面:空态里给"去导入/去找"的出口
    }
    if (!mounted) return;
    setState(() {
      _need = need;
      _shelf = shelf;
      _loading = false;
    });
    await _loadDaily();
  }

  /// 今日精读候选:优先公开源最新条目(可用时),否则从材料库按需求排前几篇。
  Future<void> _loadDaily() async {
    setState(() => _loadingDaily = true);
    final out = <MaterialHubDaily>[];
    // ① 材料库里未读完的(按需求排序)先兜底 —— 保证离线也有东西可读
    for (final s in _shelf.where((s) => !s.finished).take(5)) {
      out.add(MaterialHubDaily(
        materialId: s.id,
        title: s.titleCn.isNotEmpty ? s.titleCn : s.title,
        titleCn: s.titleCn.isNotEmpty ? s.title : '',
        sourceLabel: s.origin == 'import' ? '导入' : s.source,
        kind: s.kind,
        cefr: s.cefr,
        coverUrl: MaterialSourceService.coverFor(
          storedCoverUrl: s.coverUrl,
          sourceUrl: s.url,
        ),
        url: s.url,
        wordCount: s.wordCount,
        estMinutes: s.estMinutes,
      ));
    }
    // ② 公开源最新条目(网络不可用就跳过,不报错)
    for (final sourceId in const <String>['npr', 'gutenberg']) {
      try {
        final items = await MaterialSourceService.instance
            .listItems(sourceId, limit: 4)
            .timeout(const Duration(seconds: 6));
        final src = MaterialSourceService.sourceOf(sourceId);
        for (final it in items) {
          out.add(MaterialHubDaily(
            title: it.title,
            sourceLabel: src?.label ?? sourceId,
            kind: src?.kind ?? 'article',
            coverUrl: it.imageUrl,
            url: it.link,
          ));
        }
      } catch (_) {
        // 单源不可用:跳过(国内网络下 BBC/VOA 常不可达)
      }
    }
    if (!mounted) return;
    setState(() {
      _daily = out;
      _loadingDaily = false;
    });
  }

  void _shuffleDaily() {
    if (_daily.length <= 1) {
      unawaited(_loadDaily());
      return;
    }
    setState(() {
      _shuffle = (_shuffle + 1) % _daily.length;
      _daily = <MaterialHubDaily>[
        ..._daily.sublist(_shuffle),
        ..._daily.sublist(0, _shuffle),
      ];
    });
  }

  Future<void> _openDaily(MaterialHubDaily d) async {
    if (d.materialId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialReaderScreen(materialId: d.materialId!),
        ),
      );
    } else if (d.url.isNotEmpty) {
      try {
        await MaterialImportFlow.openHitWithProgress(
          context,
          hit: OriginalHit(
            sourceId: 'npr',
            sourceId2: d.url,
            title: d.title,
            url: d.url,
          ),
          model: LearnerModelStore.load(),
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              content: Text('这篇暂时打不开,换一篇或稍后再试'),
              behavior: SnackBarBehavior.floating,
            ));
        }
      }
    }
    if (mounted) await _load();
  }

  void _openDirection(MaterialDirectionDef def) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialBrowseScreen(direction: def.id),
      ),
    ).then((_) {
      if (mounted) unawaited(_load());
    });
  }

  void _openLibrary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MaterialLibraryScreen()),
    ).then((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            V4DetailHeader(
              domain: GraphicDomain.book,
              title: '材料中心',
              subtitle: _need.isEmpty
                  ? '选一篇,今天就读它 · 设一下需求,全 App 按它推'
                  : '按你的需求推:${_need.summary}',
              actions: <Widget>[
                V4IconAction(
                  icon: Icons.tune_rounded,
                  tooltip: '编辑我的需求',
                  onTap: () => _openDirection(MaterialTaxonomy.need),
                ),
                const SizedBox(width: Gap.xs),
                V4IconAction(
                  icon: Icons.add_rounded,
                  tooltip: '导入材料',
                  onTap: () async {
                    await MaterialImportFlow.run(
                      context,
                      model: LearnerModelStore.load(),
                    );
                    if (mounted) await _load();
                  },
                ),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: Text('正在打开材料中心…',
                          style: TextStyle(fontSize: 12)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: MaterialHubHomeView(
                        daily: _daily,
                        need: _need,
                        libraryCount: _shelf.length,
                        loadingDaily: _loadingDaily,
                        onOpenDaily: _openDaily,
                        onShuffleDaily: _shuffleDaily,
                        onOpenNeed: () => _openDirection(MaterialTaxonomy.need),
                        onOpenDirection: _openDirection,
                        onOpenLibrary: _openLibrary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
