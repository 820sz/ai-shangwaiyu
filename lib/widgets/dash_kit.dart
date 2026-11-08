import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../config/v4_theme.dart';

/// A ·「诊断台」语言 —— **只服务助理/我的两个板块的数据内页**。
///
/// 用户选型:首页 = B 每日简报,数据内页(统计/周报/错误档案/复盘)= A 诊断台。
/// A 不引入新皮肤:颜色直接取当前 [V4Skin](与主屏同源),只补两档**语义色**
/// (正向/警示)和一套「密度更高」的排版件 —— 因为果冻皮肤只有"强调",而仪表盘
/// 必须有"好坏"两档(见设计文档 §2.1)。
class DashTheme {
  DashTheme._({
    required this.skin,
    required this.good,
    required this.warn,
    required this.danger,
  });

  final V4Skin skin;
  final Color good;
  final Color warn;
  final Color danger;

  static DashTheme of(BuildContext context) {
    final V4Skin skin = V4Skin.of(context);
    final bool dark = skin.dark;
    return DashTheme._(
      skin: skin,
      good: dark ? const Color(0xFF4FD1A1) : const Color(0xFF12A06E),
      warn: dark ? const Color(0xFFF0B24A) : const Color(0xFFD98600),
      danger: dark ? const Color(0xFFFF8A7A) : const Color(0xFFD24B42),
    );
  }

  Color get ink => skin.ink;
  Color get inkSoft => skin.inkSoft;
  Color get inkFaint => skin.inkFaint;
  Color get line => skin.hairline;
  Color get accent => skin.accent;
  Color get surface => skin.surface;

  /// 渐变细线:与主屏头图同一套色(诊断台保留 2px 渐变作为连续性锚点)
  LinearGradient get ruleGradient => skin.heroFill;
}

/// 诊断台卡片:白面 + 18 圆角 + 0.9px 细边 + 比果冻更淡的阴影(7 张卡叠着不脏)。
class DashCard extends StatelessWidget {
  const DashCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: d.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: d.line.withValues(alpha: d.skin.dark ? 1 : 0.9),
          width: 0.9,
        ),
        boxShadow: d.skin.dark
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFF1B2140).withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: child,
    );
  }
}

/// KPI 带:一张白卡里 3 列指标(值 + 单位 + 标签),列间 1px 竖线。
class DashKpiBand extends StatelessWidget {
  const DashKpiBand({super.key, required this.items});

  final List<DashKpi> items;

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    final List<Widget> children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) {
        children.add(
          Container(
            width: 1,
            height: 30,
            color: d.line,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
        );
      }
      children.add(Expanded(child: items[i]));
    }
    return DashCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(children: children),
    );
  }
}

class DashKpi extends StatelessWidget {
  const DashKpi({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.color,
    this.size = 22,
  });

  final String label;
  final String value;
  final String unit;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              value,
              style: AppFont.displayStyle.copyWith(
                fontSize: size,
                height: 1.1,
                letterSpacing: -0.4,
                fontWeight: FontWeight.w800,
                color: color ?? d.ink,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(
                unit,
                style: AppFont.tagStyle.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: d.inkFaint,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: AppFont.tagStyle.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: d.inkSoft,
          ),
        ),
      ],
    );
  }
}

/// 区块标题:`01 现状分析 —————— 右侧动作`(编号 + 标题 + 一条细线)。
class DashSectionTitle extends StatelessWidget {
  const DashSectionTitle({
    super.key,
    required this.index,
    required this.title,
    this.trailing,
    this.top = 18,
  });

  final String index;
  final String title;
  final String? trailing;

  /// 与上一块的间距(默认 18;首块传 0)
  final double top;

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 10),
      child: Row(
        children: <Widget>[
          Text(
            index,
            style: AppFont.tagStyle.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: d.accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: AppFont.headingStyle.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: d.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: d.line.withValues(alpha: 0.8),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: AppFont.metaStyle.copyWith(
                fontSize: 11,
                color: d.inkFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 诊断台指标行:标签 / 值 + 3px 细条 + 一行依据。
///
/// 「待测」维度传 [measured] = false:值显示「待测」、不画条、依据换成怎么测,
/// 绝不编数字(设计文档 §2.1 的数据纪律)。
class DashMetricRow extends StatelessWidget {
  const DashMetricRow({
    super.key,
    required this.label,
    required this.value,
    this.evidence = '',
    this.ratio,
    this.color,
    this.measured = true,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 9),
  });

  final String label;
  final String value;
  final String evidence;

  /// 0..1 的条长;null = 不画条
  final double? ratio;
  final Color? color;
  final bool measured;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    final Color c = color ?? d.accent;
    final Widget body = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                label,
                style: AppFont.bodyStyle.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: d.ink,
                ),
              ),
              const Spacer(),
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.chevron_right, size: 17, color: d.inkFaint),
                ),
              Text(
                value,
                style: AppFont.headingStyle.copyWith(
                  fontSize: 16,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: measured ? d.ink : d.inkFaint,
                ),
              ),
            ],
          ),
          if (measured && ratio != null) ...[
            const SizedBox(height: 5),
            DashThinBar(value: ratio!, color: c),
          ],
          if (evidence.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              evidence,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFont.metaStyle.copyWith(
                fontSize: 11,
                height: 1.4,
                color: d.inkSoft,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: body,
    );
  }
}

/// 3px 细条(诊断台的唯一"条形图"原子)。
class DashThinBar extends StatelessWidget {
  const DashThinBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 3,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    final double f = value.isNaN ? 0 : value.clamp(0.0, 1.0);
    return Container(
      height: height,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: d.line.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(height),
      ),
      child: FractionallySizedBox(
        widthFactor: f <= 0 ? 0.001 : f,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(height),
          ),
        ),
      ),
    );
  }
}

/// 通用列表行(错误档案 / 排名行):左 lead + 标题/副标题 + 右侧值 + 箭头。
class DashListRow extends StatelessWidget {
  const DashListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.trailingText,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final String? trailingText;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    final Widget row = Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: AppFont.bodyStyle.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: d.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppFont.metaStyle.copyWith(
                      fontSize: 11,
                      height: 1.4,
                      color: d.inkSoft,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailingText != null)
            Text(
              trailingText!,
              style: AppFont.metaStyle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: d.inkSoft,
              ),
            ),
          ?trailing,
          if (onTap != null)
            Icon(Icons.chevron_right, size: 17, color: d.inkFaint),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

/// 诊断台的语义着色:0 = 正常(绿) / 1 = 注意(黄) / 2 = 需要处理(红)。
Color dashSeverityColor(BuildContext context, int severity) {
  final DashTheme d = DashTheme.of(context);
  switch (severity) {
    case 2:
      return d.danger;
    case 1:
      return d.warn;
    default:
      return d.good;
  }
}

/// 诊断台头部:2px 渐变细线 + 标题行(与主屏果冻头同一套色的连续性锚点)。
class DashPageHead extends StatelessWidget {
  const DashPageHead({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final DashTheme d = DashTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: d.ruleGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: AppFont.displayStyle.copyWith(
                      fontSize: 20,
                      height: 1.2,
                      letterSpacing: -0.3,
                      fontWeight: FontWeight.w800,
                      color: d.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: AppFont.metaStyle.copyWith(
                        fontSize: 11,
                        color: d.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            for (final Widget a in actions) ...[a, const SizedBox(width: 8)],
          ],
        ),
      ],
    );
  }
}
