import 'package:flutter/material.dart';

import '../../../config/design_tokens.dart';
import '../../../config/v4_theme.dart';
import '../../../services/material_need.dart';
import '../../../services/material_taxonomy.dart';
import '../../../widgets/art_cover.dart';

/// 材料中心 v5 首页的**纯展示层**(不碰 Provider/数据库/网络)。
///
/// 为什么单独拆:这样"真实屏幕渲染"测试可以直接给这个 widget 喂假数据出图
/// (v4 时期用手搭示意图当验收,和真机对不上 —— 这次不再这么干)。
/// 数据加载、导航都在 `MaterialCenterScreen`(material_center_screen.dart)。
///
/// 2026-11-04 用户补充:
/// - 今日精读**保留现在这种大卡 UI**(封面 + 今日精读/外刊/Lv 标签 + 标题/中文标题 +
///   认知率/时长/词数 + 摘要句数/发音 + 难度建议 + 开始阅读/换一篇/原文链接);
/// - 只需加**小小的左右切换箭头**换材料;
/// - **长按卡片**预览完整信息:完整标题 + 标题翻译 + 来源 + 为什么推这篇。
class MaterialHubHomeView extends StatefulWidget {
  final List<MaterialHubDaily> daily;
  final MaterialNeed need;
  final int libraryCount;
  final bool loadingDaily;

  final ValueChanged<MaterialHubDaily> onOpenDaily;
  final ValueChanged<MaterialHubDaily>? onOpenOriginal;
  final VoidCallback onShuffleDaily;
  final VoidCallback onOpenNeed;
  final void Function(MaterialDirectionDef) onOpenDirection;
  final VoidCallback onOpenLibrary;

  const MaterialHubHomeView({
    super.key,
    required this.daily,
    required this.need,
    required this.libraryCount,
    required this.onOpenDaily,
    required this.onShuffleDaily,
    required this.onOpenNeed,
    required this.onOpenDirection,
    required this.onOpenLibrary,
    this.onOpenOriginal,
    this.loadingDaily = false,
  });

  @override
  State<MaterialHubHomeView> createState() => _MaterialHubHomeViewState();
}

class _MaterialHubHomeViewState extends State<MaterialHubHomeView> {
  final PageController _dailyCtrl = PageController(viewportFraction: 0.96);
  int _page = 0;
  int _lastCount = 0;

  @override
  void dispose() {
    _dailyCtrl.dispose();
    super.dispose();
  }

  void _jump(int delta) {
    if (widget.daily.length < 2) return;
    final next = (_page + delta).clamp(0, widget.daily.length - 1);
    if (next == _page) return;
    _dailyCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
    setState(() => _page = next);
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    // 候选换了一批(换一篇/重新加载)时把页回到 0,避免停在越界页
    if (widget.daily.length != _lastCount) {
      _lastCount = widget.daily.length;
      _page = 0;
      if (_dailyCtrl.hasClients) _dailyCtrl.jumpToPage(0);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xl),
      children: <Widget>[
        _dailyHeader(skin),
        const SizedBox(height: Gap.xs),
        _dailyCarousel(skin),
        const SizedBox(height: Gap.md),
        _needCard(skin),
        const SizedBox(height: Gap.md),
        Row(
          children: <Widget>[
            Expanded(
              child: _directionCard(
                skin,
                MaterialTaxonomy.topic,
                subtitle: '科技 / 商业 / 文化…',
              ),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: _directionCard(
                skin,
                MaterialTaxonomy.form,
                subtitle: '教材 / 书 / 外刊 / 论文…',
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        _directionCard(
          skin,
          MaterialTaxonomy.scene,
          subtitle: '应试 / 出国旅游 / 生活聊天 / 生产力英语',
          wide: true,
        ),
        const SizedBox(height: Gap.md),
        _libraryCard(skin),
      ],
    );
  }

  Widget _dailyHeader(V4Skin skin) {
    return Row(
      children: <Widget>[
        Text(
          '今日精读',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
            color: skin.ink,
          ),
        ),
        const Spacer(),
        if (widget.daily.length > 1) ...<Widget>[
          // 用户 11/04:保留现有大卡 UI,只加"小小的左右切换箭头"
          _arrow(skin, Icons.chevron_left_rounded,
              _page > 0 ? () => _jump(-1) : null),
          const SizedBox(width: 6),
          _arrow(skin, Icons.chevron_right_rounded,
              _page < widget.daily.length - 1 ? () => _jump(1) : null),
          const SizedBox(width: 8),
          Text(
            '${_page + 1}/${widget.daily.length}',
            style: TextStyle(fontSize: 10.5, color: skin.inkFaint),
          ),
        ] else
          Text('左右滑切换',
              style: TextStyle(fontSize: 10.5, color: skin.inkFaint)),
      ],
    );
  }

  Widget _dailyCarousel(V4Skin skin) {
    if (widget.loadingDaily && widget.daily.isEmpty) {
      return Container(
        height: 320,
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: skin.shadow,
        ),
        alignment: Alignment.center,
        child: Text('正在挑今天读的…',
            style: TextStyle(fontSize: 11.5, color: skin.inkFaint)),
      );
    }
    if (widget.daily.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: skin.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('今天还没挑到精读',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: skin.ink)),
            const SizedBox(height: 4),
            Text('去「按题材 / 按形式 / 按场景」里挑一篇,或让 AI 按需求找',
                style: TextStyle(fontSize: 11.5, color: skin.inkSoft)),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                _pill(skin, '按需求找材料', onTap: widget.onOpenNeed),
                const SizedBox(width: Gap.xs),
                _pill(skin, '换一批', onTap: widget.onShuffleDaily, tonal: true),
              ],
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 430,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 卡片用 clamped 字号上限,长标题/大字号也不会撑破固定高度
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: PageView.builder(
              controller: _dailyCtrl,
              itemCount: widget.daily.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.symmetric(horizontal: Gap.xxs),
                child: _dailyCard(skin, widget.daily[i]),
              ),
            ),
          ),
          // 左右切换箭头统一放在标题行(见 _dailyHeader),卡面上不再叠箭头
        ],
      ),
    );
  }

  Widget _arrow(V4Skin skin, IconData icon, VoidCallback? onTap) {
    return Material(
      color: skin.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: skin.hairline),
            boxShadow: skin.shadow,
          ),
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? skin.inkFaint : skin.ink,
          ),
        ),
      ),
    );
  }

  /// 今日精读大卡:保留用户认可的现有 UI(封面 + 标签 + 标题 + 元信息 + 建议 + 主行动)
  Widget _dailyCard(V4Skin skin, MaterialHubDaily d) {
    return GestureDetector(
      onTap: () => widget.onOpenDaily(d),
      onLongPress: () => _showDailyPreview(skin, d),
      child: Container(
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: skin.shadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ArtCover(
              title: d.title,
              kind: d.kind,
              imageUrl: d.coverUrl,
              height: 176,
              radius: 0,
              levelLabel: d.levelLabel.isEmpty ? null : d.levelLabel,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        _badge(skin, '今日精读', accent: true),
                        const SizedBox(width: 6),
                        _badge(skin, d.kindLabel),
                        if (d.levelLabel.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _badge(skin, d.levelLabel),
                        ],
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _showDailyPreview(skin, d),
                          child: Icon(Icons.info_outline,
                              size: 15, color: skin.inkFaint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      d.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16.5,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        color: skin.ink,
                      ),
                    ),
                    if (d.titleCn.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        d.titleCn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, height: 1.3, color: skin.inkSoft),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 3,
                      children: <Widget>[
                        if (d.knownPercent != null)
                          _meta(skin, Icons.speed,
                              '已知 ${d.knownPercent!.toStringAsFixed(0)}%'),
                        if (d.estMinutes > 0)
                          _meta(skin, Icons.timer_outlined,
                              '约 ${d.estMinutes} 分钟'),
                        if (d.wordCount > 0)
                          _meta(skin, Icons.notes, '${d.wordCount} 词'),
                        if (d.summarySentences > 0)
                          _meta(skin, Icons.format_quote,
                              '摘要约 ${d.summarySentences} 句'),
                        if (d.accentLabel.isNotEmpty)
                          _meta(skin, Icons.volume_up_outlined, d.accentLabel),
                      ],
                    ),
                    if (d.adviceLine.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        d.adviceLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: d.adviceWarning
                              ? const Color(0xFFC46A2E)
                              : skin.accent,
                        ),
                      ),
                    ],
                    if (d.estimateNote.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        d.estimateNote,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 9.5, color: skin.inkFaint),
                      ),
                    ],
                    const Spacer(),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: SizedBox(
                            height: 42,
                            child: FilledButton.icon(
                              onPressed: () => widget.onOpenDaily(d),
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 19),
                              label: const Text('开始阅读'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _circleAction(
                          skin,
                          Icons.refresh,
                          '换一篇',
                          widget.onShuffleDaily,
                        ),
                        const SizedBox(width: 6),
                        if (d.url.isNotEmpty)
                          _circleAction(
                            skin,
                            Icons.link,
                            '原文链接',
                            () => widget.onOpenOriginal?.call(d),
                          ),
                      ],
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

  Widget _badge(V4Skin skin, String text, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: accent
            ? skin.accent.withValues(alpha: 0.13)
            : skin.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: accent ? skin.accent : skin.inkSoft,
        ),
      ),
    );
  }

  Widget _meta(V4Skin skin, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 12, color: skin.inkFaint),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 10.5, color: skin.inkSoft)),
      ],
    );
  }

  Widget _circleAction(
    V4Skin skin,
    IconData icon,
    String tooltip,
    VoidCallback? onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: skin.surfaceAlt,
            shape: BoxShape.circle,
            border: Border.all(color: skin.hairline),
          ),
          child: Icon(icon, size: 17, color: skin.inkSoft),
        ),
      ),
    );
  }

  /// 长按预览(用户 11/04 要求):完整标题 + 标题翻译 + 来源 + 为什么推这篇
  void _showDailyPreview(V4Skin skin, MaterialHubDaily d) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final s = V4Skin.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  d.title,
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.3,
                    fontWeight: FontWeight.w900,
                    color: s.ink,
                  ),
                ),
                if (d.titleCn.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    d.titleCn,
                    style: TextStyle(fontSize: 13, color: s.inkSoft),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    _badge(s, '今日精读', accent: true),
                    _badge(s, d.kindLabel),
                    if (d.levelLabel.isNotEmpty) _badge(s, d.levelLabel),
                    if (d.sourceLabel.isNotEmpty) _badge(s, '来源 · ${d.sourceLabel}'),
                  ],
                ),
                const SizedBox(height: 12),
                if (d.reason.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: s.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(Icons.auto_awesome,
                                size: 14, color: s.accent),
                            const SizedBox(width: 4),
                            Text(
                              '为什么推这篇',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: s.accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.reason,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.5,
                            color: s.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (d.metaLine.isNotEmpty) ...[
                  Text(d.metaLine,
                      style: TextStyle(fontSize: 11, color: s.inkSoft)),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          widget.onOpenDaily(d);
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('开始阅读'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('再看'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _needCard(V4Skin skin) {
    final empty = widget.need.isEmpty;
    return InkWell(
      onTap: widget.onOpenNeed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: empty ? skin.hairline : skin.accent.withValues(alpha: 0.30),
          ),
          boxShadow: skin.shadow,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: skin.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.tune_rounded, size: 19, color: skin.accent),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('按需求找材料',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: skin.ink)),
                  const SizedBox(height: 2),
                  Text(
                    empty ? '先花 10 秒设一下:难度 · 目标 · 形式' : widget.need.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: empty ? skin.accent : skin.inkSoft,
                      fontWeight: empty ? FontWeight.w700 : FontWeight.w400,
                    ),
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

  String _shortLabel(MaterialDirectionDef def) =>
      def.label.replaceAll('找材料', '');

  Widget _directionCard(
    V4Skin skin,
    MaterialDirectionDef def, {
    String? subtitle,
    bool wide = false,
  }) {
    return InkWell(
      onTap: () => widget.onOpenDirection(def),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: skin.shadow,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color:
                    skin.pastelAt(def.id.index).first.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(def.icon, size: 22, color: skin.ink),
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _shortLabel(def),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: skin.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle ?? def.subtitle,
                    maxLines: wide ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5, height: 1.35, color: skin.inkSoft),
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

  Widget _libraryCard(V4Skin skin) {
    return InkWell(
      onTap: widget.onOpenLibrary,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: skin.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.folder_copy_outlined, size: 20, color: skin.accent),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text('我的材料库',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: skin.ink)),
            ),
            Text(
              '${widget.libraryCount} 篇 · 管理',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: skin.accent),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: skin.inkFaint),
          ],
        ),
      ),
    );
  }

  Widget _pill(
    V4Skin skin,
    String label, {
    required VoidCallback onTap,
    bool tonal = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              tonal ? skin.surfaceAlt : skin.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: tonal ? skin.inkSoft : skin.accent,
          ),
        ),
      ),
    );
  }
}

/// 今日精读的一张候选卡(纯数据,便于渲染测试注入)
class MaterialHubDaily {
  final int? materialId;
  final String title;
  final String titleCn;
  final String sourceLabel;

  /// 材料类型(book/news/paper/article…)
  final String kind;

  /// 展示用的等级(如 Lv8)
  final String levelLabel;

  /// 认知率(0~100;来自本地分析,没有就 null → 显示预计难度)
  final double? knownPercent;

  final int wordCount;
  final int estMinutes;
  final int summarySentences;

  /// 口音标签(美音/英音),没有就空
  final String accentLabel;

  /// 适配建议行(如 "B2 · 挑战区,读起来略吃力")
  final String adviceLine;
  final bool adviceWarning;

  /// 预计难度的口径说明(没有本地分析时显示)
  final String estimateNote;

  /// 推荐理由(长按预览里显示)
  final String reason;

  final String? coverUrl;
  final String url;

  const MaterialHubDaily({
    this.materialId,
    required this.title,
    this.titleCn = '',
    this.sourceLabel = '',
    this.kind = 'article',
    this.levelLabel = '',
    this.knownPercent,
    this.wordCount = 0,
    this.estMinutes = 0,
    this.summarySentences = 0,
    this.accentLabel = '',
    this.adviceLine = '',
    this.adviceWarning = false,
    this.estimateNote = '',
    this.reason = '',
    this.coverUrl,
    this.url = '',
  });

  String get kindLabel => switch (kind) {
        'book' => '公版书',
        'paper' => '论文',
        'news' => '外刊',
        'podcast' => '播客',
        'wiki' => '百科',
        'exam' => '真题',
        _ => '文章',
      };

  String get metaLine {
    final parts = <String>[
      if (knownPercent != null)
        '已知 ${knownPercent!.toStringAsFixed(0)}%',
      if (wordCount > 0) '$wordCount 词',
      if (estMinutes > 0) '约 $estMinutes 分钟',
      if (levelLabel.isNotEmpty) levelLabel,
      if (accentLabel.isNotEmpty) accentLabel,
    ];
    return parts.join(' · ');
  }
}
