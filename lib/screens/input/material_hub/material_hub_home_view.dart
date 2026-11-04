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
class MaterialHubHomeView extends StatelessWidget {
  /// 今日精读候选(3~5 篇,可左右切)
  final List<MaterialHubDaily> daily;

  /// 当前需求摘要(只读展示;点它去"按需求找材料")
  final MaterialNeed need;

  /// 材料库篇数
  final int libraryCount;

  /// 今日精读正在加载
  final bool loadingDaily;

  final ValueChanged<MaterialHubDaily> onOpenDaily;
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
    this.loadingDaily = false,
  });

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xl),
      children: <Widget>[
        // ① 今日精读:唯一的内容推荐位(可左右切)
        _sectionLabel(skin, '今日精读', trailing: '左右滑切换'),
        const SizedBox(height: Gap.xs),
        _dailyCarousel(skin),
        const SizedBox(height: Gap.md),

        // ② 按需求:全局推送的开关(只读摘要 + 进入编辑)
        _needCard(skin),
        const SizedBox(height: Gap.md),

        // ③ 三个并行方向:题材 / 形式 / 场景
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

        // ④ 材料库(浏览 + 外部导入分开管理)
        _libraryCard(skin),
      ],
    );
  }

  Widget _sectionLabel(V4Skin skin, String title, {String? trailing}) {
    return Row(
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
            color: skin.ink,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing,
            style: TextStyle(fontSize: 10.5, color: skin.inkFaint),
          ),
      ],
    );
  }

  Widget _dailyCarousel(V4Skin skin) {
    if (loadingDaily && daily.isEmpty) {
      return Container(
        height: 176,
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
    if (daily.isEmpty) {
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
                _pill(skin, '按需求找材料', onTap: onOpenNeed),
                const SizedBox(width: Gap.xs),
                _pill(skin, '换一批', onTap: onShuffleDaily, tonal: true),
              ],
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 196,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.92),
        itemCount: daily.length,
        onPageChanged: (_) {},
        itemBuilder: (context, i) {
          final d = daily[i];
          return Padding(
            padding: EdgeInsets.only(right: i == daily.length - 1 ? 0 : Gap.xs),
            child: _dailyCard(skin, d),
          );
        },
      ),
    );
  }

  Widget _dailyCard(V4Skin skin, MaterialHubDaily d) {
    return GestureDetector(
      onTap: () => onOpenDaily(d),
      child: Container(
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: skin.shadow,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            ArtCover(
              title: d.title,
              kind: d.kind,
              imageUrl: d.coverUrl,
              width: 96,
              height: 140,
              radius: 14,
              levelLabel: d.cefr.isEmpty ? null : d.cefr,
            ),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: skin.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          d.sourceLabel,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: skin.accent,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '去读 ›',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: skin.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
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
                      style: TextStyle(fontSize: 11, color: skin.inkSoft),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    d.metaLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: skin.inkFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _needCard(V4Skin skin) {
    final empty = need.isEmpty;
    return InkWell(
      onTap: onOpenNeed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: empty
                ? skin.hairline
                : skin.accent.withValues(alpha: 0.30),
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
                  Text(
                    '按需求找材料',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: skin.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    empty ? '先花 10 秒设一下:难度 · 目标 · 形式' : need.summary,
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
      onTap: () => onOpenDirection(def),
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
                color: skin.pastelAt(def.id.index).first
                    .withValues(alpha: 0.55),
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
                      color: skin.ink,
                    ),
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
      onTap: onOpenLibrary,
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
              child: Text(
                '我的材料库',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: skin.ink,
                ),
              ),
            ),
            Text(
              '$libraryCount 篇 · 管理',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: skin.accent,
              ),
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
          color: tonal
              ? skin.surfaceAlt
              : skin.accent.withValues(alpha: 0.12),
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
  final String kind;
  final String cefr;
  final String? coverUrl;
  final String url;
  final int wordCount;
  final int estMinutes;

  const MaterialHubDaily({
    this.materialId,
    required this.title,
    this.titleCn = '',
    this.sourceLabel = '',
    this.kind = 'article',
    this.cefr = '',
    this.coverUrl,
    this.url = '',
    this.wordCount = 0,
    this.estMinutes = 0,
  });

  String get metaLine {
    final parts = <String>[
      if (wordCount > 0) '$wordCount 词',
      if (estMinutes > 0) '约 $estMinutes 分钟',
      if (cefr.isNotEmpty) cefr,
    ];
    return parts.join(' · ');
  }
}
