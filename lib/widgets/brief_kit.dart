import 'package:flutter/material.dart';

import '../config/design_tokens.dart';

/// 灰字瘦身(v2.30.0,用户:"大量灰字冗余注释看着累")。
///
/// 所有"说明性灰字"统一走这里:**只留第一句、最多 30 字**。
/// 为什么在排版层截而不是改数据层:这些句子有的来自 service(简报/周报),
/// 数据本身是完整的;界面上只需要一行,多出来的信息在点进去的详情页里。
String briefOneLine(String text, {int maxChars = 30}) {
  final String s = text.trim();
  if (s.isEmpty) return s;
  // 先取第一句(。;! ? 换行都算断句),再裁剪
  final int cut = s.indexOf(RegExp(r'[。;;!!??\n]'));
  String first = cut < 0 ? s : s.substring(0, cut);
  first = first.trim();
  if (first.isEmpty) first = s;
  if (first.length <= maxChars) {
    return first.endsWith('。') ? first : '$first。';
  }
  return '${first.substring(0, maxChars)}…';
}

/// B ·「每日简报」语言 —— **只服务「助理」「我的」两个板块**。
///
/// 为什么单开一个 kit 而不是改 `v4_kit`/`v4_theme`:
/// 用户选型是「助理/我的 = B 主语言 + A 数据内页」,输入/输出/阅读器仍是果冻语言;
/// 全局皮肤这一轮由 Lead 管,这里只放**本板块私有**的暖纸白令牌与排版件,
/// 不注册 ThemeExtension、不影响其他屏幕(读取 [Theme.brightness] 派生深色版)。
///
/// 语言要点(见 `docs/ASSISTANT-MINE-REDESIGN-2026-11-06.md` §2.2):
/// 暖纸白底 + 砖红唯一强调 + 墨绿判断句 + 40px 日期刊头 + 时间线 + 引文 + 大圆角(26)。
class BriefTheme {
  const BriefTheme({
    required this.pageBg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.line,
    required this.accent,
    required this.accent2,
    required this.warn,
    required this.onAccent,
    required this.shadow,
  });

  final Color pageBg;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;
  final Color line;

  /// 砖红:主行动 / 日期 / 编号(一屏最多 3 处)
  final Color accent;

  /// 墨绿:判断句 / 引文 / 「已完成」
  final Color accent2;
  final Color warn;
  final Color onAccent;
  final List<BoxShadow> shadow;

  static const BriefTheme light = BriefTheme(
    pageBg: Color(0xFFFBF7F0),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF4EDE2),
    ink: Color(0xFF211C16),
    inkSoft: Color(0xFF6C6259),
    inkFaint: Color(0xFFA0968A),
    line: Color(0xFFEDE3D5),
    accent: Color(0xFFC4562E),
    accent2: Color(0xFF2F5D50),
    warn: Color(0xFFB87A12),
    onAccent: Color(0xFFFFFFFF),
    shadow: <BoxShadow>[
      BoxShadow(color: Color(0x14231C12), blurRadius: 24, offset: Offset(0, 10)),
      BoxShadow(color: Color(0x08231C12), blurRadius: 4, offset: Offset(0, 1)),
    ],
  );

  /// 深色版:同一套关系(暖黑纸 + 砖红提亮),保证深色下不刺眼也不失效
  static const BriefTheme dark = BriefTheme(
    pageBg: Color(0xFF14110E),
    surface: Color(0xFF1D1915),
    surfaceAlt: Color(0xFF262019),
    ink: Color(0xFFF4EEE5),
    inkSoft: Color(0xFFB6AA9B),
    inkFaint: Color(0xFF7C7166),
    line: Color(0xFF2C2620),
    accent: Color(0xFFE0805A),
    accent2: Color(0xFF7FB49F),
    warn: Color(0xFFE0A23C),
    onAccent: Color(0xFF20140E),
    shadow: <BoxShadow>[
      BoxShadow(color: Color(0x66000000), blurRadius: 22, offset: Offset(0, 8)),
    ],
  );

  static BriefTheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  Color tint(Color color, {double alpha = 0.08}) =>
      Color.alphaBlend(color.withValues(alpha: alpha), surface);
}

/// 简报页统一外壳(两个首页 Tab 用):状态栏不归我们管,这里只负责
/// 「暖纸底 + 顶部留白 + 可滚动内容 + 可选底部动作」。
class BriefScaffold extends StatelessWidget {
  const BriefScaffold({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 8, 22, 28),
    this.bottom,
    this.refresh,
  });

  final Widget child;
  final EdgeInsets padding;
  final Widget? bottom;
  final Future<void> Function()? refresh;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    Widget list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      children: <Widget>[child],
    );
    if (refresh != null) {
      list = RefreshIndicator(
        onRefresh: refresh!,
        color: t.accent,
        backgroundColor: t.surface,
        child: list,
      );
    }
    return Scaffold(
      backgroundColor: t.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(child: list),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

/// 简报卡:白面 + 26 大圆角 + 无描边(层级只靠柔阴影与留白)。
class BriefCard extends StatelessWidget {
  const BriefCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 18),
    this.highlight = false,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;

  /// 主卡(今天要做什么)用 1.5px 砖红淡描边,与普通卡区分
  final bool highlight;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(26),
        border: highlight
            ? Border.all(color: t.accent.withValues(alpha: 0.35), width: 1.4)
            : null,
        boxShadow: t.shadow,
      ),
      child: child,
    );
  }
}

/// 眉标:9.5 / w800 / 字距 1.6(编辑感来自字距,不靠字体)
class BriefLabel extends StatelessWidget {
  const BriefLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return Text(
      text,
      style: AppFont.tagStyle.copyWith(
        fontSize: 9.5,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w800,
        color: color ?? t.accent,
      ),
    );
  }
}

/// 页面刊头:眉标 + 40px 日期 + 右侧两行小字。
class BriefDateHead extends StatelessWidget {
  const BriefDateHead({
    super.key,
    required this.eyebrow,
    required this.bigDate,
    this.rightTop,
    this.rightBottom,
  });

  final String eyebrow;
  final String bigDate;
  final String? rightTop;
  final String? rightBottom;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              BriefLabel(eyebrow),
              const SizedBox(height: Gap.xs),
              Text(
                bigDate,
                style: AppFont.displayStyle.copyWith(
                  fontSize: 40,
                  height: 1.0,
                  letterSpacing: -1.4,
                  fontWeight: FontWeight.w900,
                  color: t.ink,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (rightTop != null)
              Text(
                rightTop!,
                style: AppFont.metaStyle.copyWith(
                  fontSize: 11,
                  color: t.inkSoft,
                ),
              ),
            if (rightBottom != null) ...[
              const SizedBox(height: 3),
              Text(
                rightBottom!,
                style: AppFont.metaStyle.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: t.ink,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 简报口吻的开场:一句话标题 + 一段正文(行高 1.75 的「人写的」段落)
class BriefLead extends StatelessWidget {
  const BriefLead({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppFont.titleStyle.copyWith(
            fontSize: 22,
            height: 1.32,
            letterSpacing: -0.4,
            fontWeight: FontWeight.w800,
            color: t.ink,
          ),
        ),
        const SizedBox(height: Gap.xs),
        Text(
          body,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppFont.bodyStyle.copyWith(
            fontSize: 13,
            height: 1.55,
            color: t.inkSoft,
          ),
        ),
      ],
    );
  }
}

/// 今天的时间线一行(点 + 竖线 + 两条字)。
class BriefTimelineRow extends StatelessWidget {
  const BriefTimelineRow({
    super.key,
    required this.when,
    required this.title,
    this.detail,
    this.last = false,
    this.onTap,
  });

  final String when;
  final String title;
  final String? detail;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    final Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 14,
          child: Column(
            children: <Widget>[
              const SizedBox(height: 5),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: t.accent,
                  shape: BoxShape.circle,
                ),
              ),
              if (!last) Container(width: 1, height: 30, color: t.line),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                when,
                style: AppFont.metaStyle.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t.inkFaint,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFont.bodyStyle.copyWith(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.metaStyle.copyWith(
                    fontSize: 11,
                    height: 1.45,
                    color: t.inkSoft,
                  ),
                ),
              ],
              if (!last) const SizedBox(height: 10),
            ],
          ),
        ),
        if (onTap != null)
          Icon(Icons.chevron_right, size: 18, color: t.inkFaint),
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: row,
      ),
    );
  }
}

/// 数字行:大号数字 + 小字单位,编辑排版式(不是 KPI 卡)。
class BriefStatRow extends StatelessWidget {
  const BriefStatRow({super.key, required this.stats});

  final List<BriefStat> stats;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    for (var i = 0; i < stats.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 16));
      children.add(Expanded(child: stats[i]));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: children,
    );
  }
}

class BriefStat extends StatelessWidget {
  const BriefStat({
    super.key,
    required this.value,
    required this.label,
    this.color,
    this.valueSize = 26,
  });

  final String value;
  final String label;
  final Color? color;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: AppFont.displayStyle.copyWith(
            fontSize: valueSize,
            height: 1.0,
            letterSpacing: -0.8,
            fontWeight: FontWeight.w900,
            color: color ?? t.ink,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: AppFont.metaStyle.copyWith(fontSize: 10.5, color: t.inkSoft),
        ),
      ],
    );
  }
}

/// 引文(判断句 / 提醒):左侧墨绿 3px 竖线,底色极淡。
class BriefQuote extends StatelessWidget {
  const BriefQuote({super.key, required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    final Color c = color ?? t.accent2;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 16, 13),
      decoration: BoxDecoration(
        color: t.tint(c, alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: c, width: 3)),
      ),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: AppFont.bodyStyle.copyWith(
          fontSize: 13.5,
          height: 1.65,
          color: t.ink,
        ),
      ),
    );
  }
}

/// 主按钮(砖红胶囊)
class BriefPrimaryButton extends StatelessWidget {
  const BriefPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.height = 44,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    final bool enabled = onTap != null;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: enabled ? t.accent : t.line,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...[
                Icon(icon, size: 17, color: enabled ? t.onAccent : t.inkFaint),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppFont.bodyStyle.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: enabled ? t.onAccent : t.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 次按钮(线框胶囊)
class BriefOutlineButton extends StatelessWidget {
  const BriefOutlineButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 42,
  });

  final String label;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: t.line),
            ),
            child: Text(
              label,
              style: AppFont.bodyStyle.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: t.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 简报里的入口行(标题 + 一行说明 + 右箭头),首页「去看看」用。
class BriefEntryRow extends StatelessWidget {
  const BriefEntryRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.leading,
    this.trailingText,
    this.dense = false,
    this.showDivider = true,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? leading;
  final String? trailingText;
  final bool dense;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return Column(
      children: <Widget>[
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? 11 : 14),
            child: Row(
              children: <Widget>[
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.bodyStyle.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFont.metaStyle.copyWith(
                          fontSize: 11,
                          height: 1.5,
                          color: t.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailingText != null)
                  Padding(
                    padding: const EdgeInsets.only(left: Gap.xs),
                    child: Text(
                      trailingText!,
                      style: AppFont.metaStyle.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.accent2,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: t.inkFaint),
              ],
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, thickness: 0.8, color: t.line),
      ],
    );
  }
}

/// 简报区块标题(左:眉标;右:可选动作)
class BriefSectionTitle extends StatelessWidget {
  const BriefSectionTitle({
    super.key,
    required this.eyebrow,
    this.trailing,
    this.onTrailingTap,
  });

  final String eyebrow;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: Row(
        children: <Widget>[
          BriefLabel(eyebrow, color: t.inkFaint),
          const Spacer(),
          if (trailing != null)
            InkWell(
              onTap: onTrailingTap,
              child: Text(
                trailing!,
                style: AppFont.metaStyle.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.accent2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 7 根柱(简报里的「本周」):暖色细柱 + 固定高度,不依赖外部约束。
class BriefBars extends StatelessWidget {
  const BriefBars({
    super.key,
    required this.values,
    this.height = 34,
    this.color,
    this.gap = 4,
  });

  final List<double> values;
  final double height;
  final Color? color;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    double maxV = 0;
    for (final double v in values) {
      if (v > maxV) maxV = v;
    }
    if (maxV <= 0) maxV = 1;
    final List<Widget> children = <Widget>[];
    for (var i = 0; i < values.length; i++) {
      if (i > 0) children.add(SizedBox(width: gap));
      final double h = (height * (values[i] / maxV)).clamp(3.0, height);
      children.add(
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: h,
              decoration: BoxDecoration(
                color: (color ?? t.accent).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: children),
    );
  }
}

/// 空态(简报语言):一句话 + 一个可执行动作,不用灰色大图标糊弄。
class BriefEmpty extends StatelessWidget {
  const BriefEmpty({
    super.key,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: AppFont.bodyStyle.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppFont.bodyStyle.copyWith(
            fontSize: 11,
            height: 1.55,
            color: t.inkSoft,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: Gap.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: t.accent2,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: AppFont.bodyStyle.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: t.accent2,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
