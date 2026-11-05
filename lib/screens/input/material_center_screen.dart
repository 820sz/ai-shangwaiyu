import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../services/database.dart';
import '../../services/external_link.dart';
import '../../services/learner_model_store.dart';
import '../../services/material_library.dart';
import '../../services/material_need.dart';
import '../../services/material_prefs.dart';
import '../../services/material_source.dart';
import '../../services/material_taxonomy.dart';
import '../../services/original_search.dart';

import '../../widgets/material_cover.dart';

import 'material_channel_screen.dart';
import 'material_hub/material_hub_home_view.dart';
import 'material_import_flow.dart';
import 'bookshelf_screen.dart';
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
  int _bookshelfCount = 0;

  /// 0 = 大头部完全展开;1 = 已滚到顶、只留紧凑条
  double _collapseT = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    MaterialNeed need = const MaterialNeed();
    var shelf = <ShelfItem>[];
    var books = 0;
    try {
      need = MaterialNeed.load();
      shelf = await MaterialLibrary.shelf(limit: 300);
      shelf = need.rank(shelf);
      books = (await DatabaseService.bookshelfItems()).length;
    } catch (_) {
      // 读库失败不阻塞页面:空态里给"去导入/去找"的出口
    }
    if (!mounted) return;
    setState(() {
      _need = need;
      _shelf = shelf;
      _bookshelfCount = books;
      _loading = false;
    });
    await _loadDaily();
  }

  /// 今日精读候选:优先公开源最新条目(可用时),否则从材料库按需求排前几篇。
  Future<void> _loadDaily() async {
    setState(() => _loadingDaily = true);
    final need = _need;
    // 推荐理由(长按预览里显示):只用真实依据,不编
    String reasonFor({double? coverage}) {
      final parts = <String>[];
      if (coverage != null && !need.band.isAny) {
        final inBand = need.band.contains(coverage);
        parts.add(
            '认知率 ${(coverage * 100).toStringAsFixed(0)}%,${inBand ? '正好落在你选的 ${need.band.label} 档' : '不在你选的 ${need.band.label} 档,今天候选有限先给你看'}');
      }
      if (need.goals.isNotEmpty) {
        parts.add('符合你的目标:${need.goals.join("、")}');
      }
      if (need.kinds.isNotEmpty) {
        parts.add(
            '你偏好的形式:${need.kinds.map((k) => MaterialPrefs.kindLabels[k] ?? k).join("、")}');
      }
      if (parts.isEmpty) {
        parts.add('按当前可用内容源挑的最新一篇,先保持每天的输入节奏');
      }
      return parts.join(';');
    }

    final out = <MaterialHubDaily>[];
    // ① 材料库里未读完的(按需求排序)先兜底 —— 保证离线也有东西可读
    for (final s in _shelf.where((s) => !s.finished).take(5)) {
      final level = MaterialLevel.of(s.cefr, kind: s.kind);
      final coverage = s.coverage;
      out.add(MaterialHubDaily(
        materialId: s.id,
        title: s.titleCn.isNotEmpty ? s.titleCn : s.title,
        titleCn: s.titleCn.isNotEmpty ? s.title : '',
        sourceLabel: s.origin == 'import' ? '导入' : s.source,
        kind: s.kind,
        levelLabel: 'Lv$level',
        knownPercent: coverage != null ? coverage * 100 : null,
        wordCount: s.wordCount,
        estMinutes: s.estMinutes,
        accentLabel: MaterialLevel.accentOf(s.source),
        adviceLine: coverage == null
            ? ''
            : '${s.cefr.isNotEmpty ? s.cefr : "CEFR"} · ${MaterialLevel.matchHint(coverage)}',
        adviceWarning: coverage != null && coverage < 0.90,
        reason: reasonFor(coverage: coverage),
        coverUrl: MaterialSourceService.coverFor(
          storedCoverUrl: s.coverUrl,
          sourceUrl: s.url,
        ),
        url: s.url,
      ));
    }
    // ② 公开源最新条目(网络不可用就跳过,不报错)
    for (final sourceId in const <String>['npr', 'gutenberg']) {
      try {
        final items = await MaterialSourceService.instance
            .listItems(sourceId, limit: 4)
            .timeout(const Duration(seconds: 6));
        final src = MaterialSourceService.sourceOf(sourceId);
        final kind = src?.kind ?? 'article';
        final estimate = MaterialLibrary.estimateDifficulty(
          sourceId: sourceId,
          kind: kind,
        );
        final level = MaterialLevel.fallbackForKind(kind);
        for (final it in items) {
          out.add(MaterialHubDaily(
            title: it.title,
            sourceLabel: src?.label ?? sourceId,
            kind: kind,
            levelLabel: 'Lv$level',
            coverUrl: it.imageUrl,
            url: it.link,
            accentLabel: MaterialLevel.accentOf(sourceId),
            adviceLine: estimate.label,
            estimateNote:
                '${estimate.basis} · 开始阅读后按你的词频算真实认知率',
            reason: reasonFor(),
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
    // 方案 2「频道化」(用户 11/05 拍板):四个大分类统一进频道页,
    // 每个频道 = 「发现(真实检索结果) / 我的(可管理材料)」两个 Tab。
    // 旧的 MaterialBrowseScreen 保留,仅作为频道页「去设置需求」的入口。
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialChannelScreen(direction: def.id),
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

  void _openBookshelf() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BookshelfScreen()),
    ).then((_) {
      if (mounted) unawaited(_load());
    });
  }

  void _onScrollOffset(double px) {
    final t = (px / 120).clamp(0.0, 1.0);
    if ((t - _collapseT).abs() > 0.02 && mounted) {
      setState(() => _collapseT = t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            // 大头部放进滚动内容里:下滑会跟着滚走,不再永久悬在顶部
            if (_loading)
              ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  _hubHeader(skin),
                  const Padding(
                    padding: EdgeInsets.all(Gap.xl),
                    child: Center(
                      child: Text('正在打开材料中心…',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              )
            else
              RefreshIndicator(
                onRefresh: _load,
                child: MaterialHubHomeView(
                  header: _hubHeader(skin),
                  daily: _daily,
                  need: _need,
                  libraryCount: _shelf.length,
                  bookshelfCount: _bookshelfCount,
                  loadingDaily: _loadingDaily,
                  onScrollOffset: _onScrollOffset,
                  onOpenDaily: _openDaily,
                  onOpenOriginal: (d) async {
                    if (d.url.isEmpty) return;
                    final ok = await launchExternalUrl(d.url);
                    if (!ok) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(
                          content: Text('打不开这篇的原文链接,可以点卡片进软件内阅读'),
                          behavior: SnackBarBehavior.floating,
                        ));
                    }
                  },
                  onShuffleDaily: _shuffleDaily,
                  onOpenNeed: () => _openDirection(MaterialTaxonomy.need),
                  onOpenDirection: _openDirection,
                  onOpenLibrary: _openLibrary,
                  onOpenBookshelf: _openBookshelf,
                ),
              ),
            // 下滑后的紧凑顶栏
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: _collapseT < 0.6,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: _collapseT >= 0.6 ? 1 : 0,
                  child: _compactBar(context, skin),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 材料中心的果冻大头部:标题、需求摘要、编辑需求/导入两个动作
  Widget _hubHeader(V4Skin skin) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Gap.xs, Gap.xs, Gap.xs, Gap.xs),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.alphaBlend(
                skin.pastelAt(1).first.withValues(alpha: 0.75), skin.pageBg),
            Color.alphaBlend(
                skin.pastelAt(0).first.withValues(alpha: 0.55), skin.pageBg),
            Color.alphaBlend(
                skin.pastelAt(2).first.withValues(alpha: 0.45), skin.pageBg),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -28,
            top: -34,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    _hubCircle(
                      skin,
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.maybePop(context),
                    ),
                    const Spacer(),
                    _hubCircle(
                      skin,
                      icon: Icons.tune_rounded,
                      onTap: () => _openDirection(MaterialTaxonomy.need),
                    ),
                    const SizedBox(width: Gap.xs),
                    _hubCircle(
                      skin,
                      icon: Icons.add_rounded,
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
                const SizedBox(height: Gap.md),
                Text(
                  '材料中心',
                  style: TextStyle(
                    fontSize: 34,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                    color: skin.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _need.isEmpty
                      ? '选一篇,今天就读它 · 设一下需求,全 App 按它推'
                      : '按你的需求推:${_need.summary}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: skin.inkSoft,
                  ),
                ),
                const SizedBox(height: Gap.sm),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubCircle(V4Skin skin,
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: skin.surface.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: skin.shadow,
        ),
        child: Icon(icon, size: 19, color: skin.ink),
      ),
    );
  }

  /// 下滑后出现的紧凑顶栏:返回 + 标题 + 两个动作
  Widget _compactBar(BuildContext context, V4Skin skin) {
    return Container(
      decoration: BoxDecoration(
        color: skin.pageBg.withValues(alpha: 0.94),
        border: Border(bottom: BorderSide(color: skin.hairline)),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: Gap.sm,
        right: Gap.sm,
        bottom: 6,
      ),
      child: Row(
        children: <Widget>[
          _hubCircle(
            skin,
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Text(
              '材料中心',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                color: skin.ink,
              ),
            ),
          ),
          _hubCircle(
            skin,
            icon: Icons.tune_rounded,
            onTap: () => _openDirection(MaterialTaxonomy.need),
          ),
          const SizedBox(width: Gap.xs),
          _hubCircle(
            skin,
            icon: Icons.add_rounded,
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
    );
  }
}
