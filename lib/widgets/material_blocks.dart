import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../config/theme.dart';
import '../services/material_blocks.dart';
import 'waiting.dart';

/// 材料阅读器里的「AI 内容块」渲染(v2.9,用户第 3(5) 条)。
///
/// 用户原话:"增加更丰富的形式…让 ai 在材料中绘出表格啊等等,思维导图呀等等…
/// 核心诉求是让软件内的阅读体验更丰富,更舒服。"
///
/// 设计取向(**不要"全是字"**):
/// - 每个块都是一张**卡片**(圆角 + 留白),块与块之间靠外边距拉开;
/// - 五种形式各有**自己的图标与强调色**:表格蓝、导图紫、时间线琥珀、
///   要点绿、自测红 —— 用户扫一眼就知道这一块是什么;
/// - 结构靠**图形**(斑马纹行、连线、圆点、编号圆)而不是靠句子;
/// - 全部自绘/原生布局,**不引第三方库**。
///
/// 数据约定见 [MaterialBlockDraft.data]。

/// 一个内容块 = 卡片(头部 + 内容)
class MaterialBlockView extends StatelessWidget {
  final MaterialBlockDraft block;

  /// 删除这一块
  final VoidCallback? onDelete;

  /// 重新生成这一块
  final VoidCallback? onRegenerate;

  /// 紧凑模式(弹层里预览用:不显示操作按钮)
  final bool compact;

  const MaterialBlockView({
    super.key,
    required this.block,
    this.onDelete,
    this.onRegenerate,
    this.compact = false,
  });

  /// 每种形式的强调色(块与块之间的第一层区分)
  static Color accentOf(BuildContext context, MaterialBlockKind kind) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (kind) {
      case MaterialBlockKind.table:
        return AppTheme.chartSeries(context);
      case MaterialBlockKind.mindmap:
        return dark ? const Color(0xFFB49BE8) : const Color(0xFF6B4CE6);
      case MaterialBlockKind.timeline:
        return AppTheme.amber(context);
      case MaterialBlockKind.points:
        return AppTheme.successColor(context);
      case MaterialBlockKind.quiz:
        return AppTheme.warningColor(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentOf(context, block.kind);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.fromLTRB(Gap.xs, Gap.xs, Gap.xs, Gap.md),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: Radii.cardRadius,
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 头部:图标 + 标题 + 来源标注 + 两个小按钮 ──
          Container(
            padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.xs, Gap.xs),
            decoration: BoxDecoration(
              color: accent.withAlpha(theme.brightness == Brightness.dark ? 26 : 14),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Radii.card),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(38),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(block.kind.icon, size: 15, color: accent),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        block.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        block.sourceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ],
                  ),
                ),
                if (!compact && onRegenerate != null)
                  IconButton(
                    tooltip: '重新生成',
                    onPressed: onRegenerate,
                    iconSize: 17,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    icon: Icon(Icons.refresh, color: muted),
                  ),
                if (!compact && onDelete != null)
                  IconButton(
                    tooltip: '删除这一块',
                    onPressed: onDelete,
                    iconSize: 17,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    icon: Icon(Icons.delete_outline, color: muted),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.sm, Gap.sm),
            child: MaterialBlockBody(block: block),
          ),
        ],
      ),
    );
  }
}

/// 只渲染"内容"(不含卡片头),弹层里预览与阅读器里共用
class MaterialBlockBody extends StatelessWidget {
  final MaterialBlockDraft block;

  const MaterialBlockBody({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    switch (block.kind) {
      case MaterialBlockKind.table:
        return _TableBody(data: block.data);
      case MaterialBlockKind.mindmap:
        return _MindmapBody(data: block.data);
      case MaterialBlockKind.timeline:
        return _TimelineBody(data: block.data);
      case MaterialBlockKind.points:
        return _PointsBody(data: block.data);
      case MaterialBlockKind.quiz:
        return _QuizBody(data: block.data);
    }
  }
}

/// 生成中的等待态(骨架 + 真实步骤时间线)——
/// 有明确步骤的 AI 任务用 [AiWaitingTimeline],**不用转圈**。
class MaterialBlockWaiting extends StatelessWidget {
  final MaterialBlockKind kind;

  /// 已完成到第几步(0 基):0 读取正文 / 1 AI 整理 / 2 解析保存
  final int step;

  /// 失败步(>=0 时该步标红,后面步骤不显示)
  final int failedStep;

  final String? detail;

  const MaterialBlockWaiting({
    super.key,
    required this.kind,
    this.step = 0,
    this.failedStep = -1,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final labels = [
      '读取该段正文',
      '让 AI 整理成${kind.label}',
      '解析并保存到这篇材料',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AiWaitingTimeline(
          running: failedStep < 0 && step < labels.length - 1,
          steps: [
            for (var i = 0; i < labels.length; i++)
              if (failedStep < 0 || i <= failedStep)
                AiStep(
                  label: labels[i],
                  detail: i == step && detail != null ? detail : null,
                  state: failedStep == i
                      ? AiStepState.failed
                      : (i < step ? AiStepState.done : AiStepState.running),
                ),
          ],
        ),
        if (failedStep < 0) ...[
          const SizedBox(height: Gap.sm),
          // 结果将占据的位置先摆出来(等待感明显更短)
          SkeletonLines(lines: kind == MaterialBlockKind.table ? 3 : 4, seed: 2),
        ],
      ],
    );
  }
}

/// 生成失败:说明 + 重试(**不用红字一坨**,用统一的错误卡)
class MaterialBlockErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const MaterialBlockErrorCard({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.all(Gap.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withAlpha(12),
        borderRadius: Radii.controlRadius,
        border: Border.all(color: theme.colorScheme.error.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 17, color: theme.colorScheme.error),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                height: 1.45,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onRetry,
              child: const Text('重试', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

// ═══════════════ table:真表格(表头 + 斑马纹 + 横向可滚)═══════════════

class _TableBody extends StatelessWidget {
  final Map<String, Object?> data;

  const _TableBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = MaterialBlockView.accentOf(context, MaterialBlockKind.table);
    final columns = (data['columns'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    final rows = (data['rows'] as List?) ?? const [];
    if (rows.isEmpty && columns.isEmpty) {
      return const _EmptyBlockBody(message: '这一块没有内容');
    }
    final width = _widthOf(data, columns, rows);
    final table = Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder.symmetric(
        inside: BorderSide(color: theme.dividerColor.withAlpha(60)),
      ),
      columnWidths: {
        for (var i = 0; i < width; i++) i: const IntrinsicColumnWidth(),
      },
      children: [
        if (columns.isNotEmpty)
          TableRow(
            decoration: BoxDecoration(color: accent.withAlpha(28)),
            children: [
              for (final c in columns)
                _cell(
                  context,
                  c,
                  bold: true,
                  color: accent,
                ),
            ],
          ),
        for (var r = 0; r < rows.length; r++)
          TableRow(
            // 斑马纹:窄屏上眼睛不容易串行
            decoration: BoxDecoration(
              color: r.isOdd
                  ? theme.colorScheme.surfaceContainerHighest.withAlpha(90)
                  : Colors.transparent,
            ),
            children: [
              for (var c = 0; c < width; c++)
                _cell(
                  context,
                  c < (rows[r] as List).length ? '${(rows[r] as List)[c]}' : '',
                  bold: false,
                ),
            ],
          ),
      ],
    );
    // 窄屏不挤爆:包一层横向滚动,最小宽度按列数给(不够就滚)
    return LayoutBuilder(
      builder: (context, c) {
        final minWidth = (width * 86.0).clamp(200.0, 900.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth > c.maxWidth ? minWidth : c.maxWidth),
            child: table,
          ),
        );
      },
    );
  }

  static int _widthOf(Map<String, Object?> data, List<String> columns, List<Object?> rows) {
    final declared = data['width'];
    if (declared is int && declared > 0) return declared;
    var w = columns.length;
    for (final r in rows) {
      if (r is List && r.length > w) w = r.length;
    }
    return w <= 0 ? 2 : w;
  }

  Widget _cell(BuildContext context, String text, {required bool bold, Color? color}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Gap.xs),
      child: Text(
        text.isEmpty ? '—' : text,
        style: theme.textTheme.bodySmall?.copyWith(
          height: 1.4,
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
          color: color ?? theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

// ═══════════════ mindmap:自绘连线 + 层级收敛 ═══════════════

class _MindmapBody extends StatelessWidget {
  final Map<String, Object?> data;

  const _MindmapBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = MaterialBlockView.accentOf(context, MaterialBlockKind.mindmap);
    final center = '${data['center'] ?? ''}'.trim();
    final rawBranches = (data['branches'] as List?) ?? const [];
    final branches = <_Branch>[];
    for (final b in rawBranches) {
      if (b is! Map) continue;
      final label = '${b['label'] ?? ''}'.trim();
      if (label.isEmpty) continue;
      final children = (b['children'] as List?)
              ?.map((e) => '$e'.trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      // 层级 >3 收敛:分支下只显示前 4 个子项(更深的由服务层压平成两层)
      branches.add(_Branch(label, children.take(4).toList()));
    }
    if (center.isEmpty || branches.isEmpty) {
      return const _EmptyBlockBody(message: '这一块没有内容');
    }
    return LayoutBuilder(
      builder: (context, c) {
        // 窄屏(每支不足 130)叠成单列,避免挤成一坨
        final rows = c.maxWidth < 320 || branches.length <= 1;
        return rows
            ? _ColumnMindmap(
                center: center,
                branches: branches,
                accent: accent,
                theme: theme,
              )
            : _RadialMindmap(
                center: center,
                branches: branches,
                accent: accent,
                theme: theme,
              );
      },
    );
  }
}

class _Branch {
  final String label;
  final List<String> children;
  const _Branch(this.label, this.children);
}

/// 窄屏:中心在左、分支在右,用自绘连线连接
class _RadialMindmap extends StatelessWidget {
  final String center;
  final List<_Branch> branches;
  final Color accent;
  final ThemeData theme;

  const _RadialMindmap({
    required this.center,
    required this.branches,
    required this.accent,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final centers = <double>[];
    var y = 0.0;
    for (final b in branches) {
      final h = _branchHeight(b, theme);
      centers.add(y + h / 2);
      y += h + Gap.xs;
    }
    // 中心块的高度决定连线起点(它按内容撑开,所以取"一行文字的量级")
    final fs = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final rootCenterY = 10 + fs * 1.3 / 2;
    return IntrinsicHeight(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _BranchPainter(
                branchCenters: centers,
                color: accent,
                rootCenterY: rootCenterY,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: _RootChip(text: center, accent: accent, theme: theme),
                  ),
                ],
              ),
              const SizedBox(width: Gap.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < branches.length; i++) ...[
                      _BranchBlock(
                        branch: branches[i],
                        accent: accent,
                        theme: theme,
                      ),
                      if (i != branches.length - 1) const SizedBox(height: Gap.xs),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单列:中心在上、分支依次在下方(用左侧竖线与圆点表示层级)
class _ColumnMindmap extends StatelessWidget {
  final String center;
  final List<_Branch> branches;
  final Color accent;
  final ThemeData theme;

  const _ColumnMindmap({
    required this.center,
    required this.branches,
    required this.accent,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RootChip(text: center, accent: accent, theme: theme),
        const SizedBox(height: Gap.xs),
        for (final b in branches)
          Padding(
            padding: const EdgeInsets.only(left: Gap.md, bottom: Gap.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(child: _BranchBlock(branch: b, accent: accent, theme: theme)),
              ],
            ),
          ),
      ],
    );
  }
}

class _RootChip extends StatelessWidget {
  final String text;
  final Color accent;
  final ThemeData theme;

  const _RootChip({required this.text, required this.accent, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withAlpha(30),
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: accent),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: accent,
          height: 1.3,
        ),
      ),
    );
  }
}

class _BranchBlock extends StatelessWidget {
  final _Branch branch;
  final Color accent;
  final ThemeData theme;

  const _BranchBlock({
    required this.branch,
    required this.accent,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            branch.label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
        for (final child in branch.children)
          Padding(
            padding: const EdgeInsets.only(left: Gap.xs, top: Gap.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 12,
                  height: 1,
                  margin: const EdgeInsets.only(top: 8),
                  color: accent.withAlpha(140),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    child,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 分支相对整块的高度(连线端点要靠它算)
double _branchHeight(_Branch b, ThemeData theme) {
  final fs = theme.textTheme.bodySmall?.fontSize ?? 12;
  // 分支标签:Chip(5+5 padding)+ 一行
  var h = 10 + fs * 1.25;
  // 子项:每行 4(top gap)+ 一行
  h += b.children.length * (Gap.xxs + fs * 1.35);
  return h;
}

/// 中心 → 各分支的连线(自绘,不引第三方库)。
///
/// 用**从中心发出的曲线**画,而不是"一根主干 + 直角分叉":文字块宽度不一,
/// 直角分叉在真机上很容易穿字;曲线只要端点对得上就一定好看。
class _BranchPainter extends CustomPainter {
  final List<double> branchCenters;
  final Color color;

  /// 中心块的中线位置;null = 画在整块高度的正中
  final double? rootCenterY;

  const _BranchPainter({
    required this.branchCenters,
    required this.color,
    this.rootCenterY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (branchCenters.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = color.withAlpha(150);
    final rootY = rootCenterY ?? size.height / 2;
    const rootX = 6.0;
    final endX = size.width - 2;
    for (final cy in branchCenters) {
      final p = Path()
        ..moveTo(rootX, rootY)
        ..cubicTo(
          rootX + (endX - rootX) * 0.45,
          rootY,
          rootX + (endX - rootX) * 0.55,
          cy,
          endX,
          cy,
        );
      canvas.drawPath(p, paint);
    }
    canvas.drawCircle(Offset(rootX, rootY), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BranchPainter old) =>
      old.branchCenters.length != branchCenters.length ||
      old.color != color ||
      old.rootCenterY != rootCenterY;
}

// ═══════════════ timeline:左侧时间轴 + 圆点 + 右侧事件卡 ═══════════════

class _TimelineBody extends StatelessWidget {
  final Map<String, Object?> data;

  const _TimelineBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = MaterialBlockView.accentOf(context, MaterialBlockKind.timeline);
    final events = <_Event>[];
    for (final e in (data['events'] as List?) ?? const []) {
      if (e is! Map) continue;
      final text = '${e['text'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      events.add(_Event('${e['time'] ?? ''}'.trim(), text));
    }
    if (events.isEmpty) return const _EmptyBlockBody(message: '这一块没有内容');
    return Stack(
      children: [
        // 竖线:从第一个圆点到最后一个圆点(两端各留 8,不画到卡片外面)
        Positioned(
          left: 5.6,
          top: 8,
          bottom: 8,
          child: Container(width: 1.4, color: accent.withAlpha(90)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < events.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == events.length - 1 ? 0 : Gap.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 圆点(最后一个实心,读起来知道"到头了")
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: accent.withAlpha(i == events.length - 1 ? 255 : 60),
                          shape: BoxShape.circle,
                          border: Border.all(color: accent, width: 1.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xs),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withAlpha(140),
                          borderRadius: Radii.controlRadius,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (events[i].time.isNotEmpty)
                              Text(
                                events[i].time,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            Text(
                              events[i].text,
                              style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Event {
  final String time;
  final String text;
  const _Event(this.time, this.text);
}

// ═══════════════ points:编号要点卡 ═══════════════

class _PointsBody extends StatelessWidget {
  final Map<String, Object?> data;

  const _PointsBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = MaterialBlockView.accentOf(context, MaterialBlockKind.points);
    final items = <_Point>[];
    for (final e in (data['items'] as List?) ?? const []) {
      if (e is! Map) continue;
      final title = '${e['title'] ?? ''}'.trim();
      final text = '${e['text'] ?? ''}'.trim();
      if (title.isEmpty && text.isEmpty) continue;
      items.add(_Point(title, text));
    }
    if (items.isEmpty) return const _EmptyBlockBody(message: '这一块没有内容');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Container(
            margin: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : Gap.xs),
            padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xs, Gap.sm, Gap.xs),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
              borderRadius: Radii.controlRadius,
              border: Border(
                left: BorderSide(color: accent, width: 3),
                top: BorderSide(color: accent.withAlpha(40)),
                right: BorderSide(color: accent.withAlpha(40)),
                bottom: BorderSide(color: accent.withAlpha(40)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(38),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (items[i].title.isNotEmpty)
                        Text(
                          items[i].title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      if (items[i].text.isNotEmpty) ...[
                        if (items[i].title.isNotEmpty) const SizedBox(height: 2),
                        Text(
                          items[i].text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Point {
  final String title;
  final String text;
  const _Point(this.title, this.text);
}

// ═══════════════ quiz:点开看答案的自测小卡 ═══════════════

class _QuizBody extends StatelessWidget {
  final Map<String, Object?> data;

  const _QuizBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final items = <_Quiz>[];
    for (final e in (data['items'] as List?) ?? const []) {
      if (e is! Map) continue;
      final q = '${e['question'] ?? ''}'.trim();
      final a = '${e['answer'] ?? ''}'.trim();
      if (q.isEmpty || a.isEmpty) continue;
      items.add(_Quiz(q, a));
    }
    if (items.isEmpty) return const _EmptyBlockBody(message: '这一块没有内容');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          _QuizTile(index: i, quiz: items[i]),
      ],
    );
  }
}

class _QuizTile extends StatefulWidget {
  final int index;
  final _Quiz quiz;

  const _QuizTile({required this.index, required this.quiz});

  @override
  State<_QuizTile> createState() => _QuizTileState();
}

class _QuizTileState extends State<_QuizTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = MaterialBlockView.accentOf(context, MaterialBlockKind.quiz);
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
        borderRadius: Radii.controlRadius,
        border: Border.all(color: accent.withAlpha(_open ? 90 : 40)),
      ),
      child: InkWell(
        borderRadius: Radii.controlRadius,
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.xs, Gap.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Q${widget.index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: Text(
                      widget.quiz.question,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (_open) ...[
                const SizedBox(height: Gap.xs),
                Container(
                  padding: const EdgeInsets.all(Gap.xs),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor(context).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 15, color: AppTheme.successColor(context)),
                      const SizedBox(width: Gap.xs),
                      Expanded(
                        child: Text(
                          widget.quiz.answer,
                          style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '点一下看答案',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Quiz {
  final String question;
  final String answer;
  const _Quiz(this.question, this.answer);
}

class _EmptyBlockBody extends StatelessWidget {
  final String message;

  const _EmptyBlockBody({required this.message});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.inbox_outlined, size: 16, color: muted),
        const SizedBox(width: Gap.xs),
        Text(message, style: TextStyle(fontSize: 12, color: muted)),
      ],
    );
  }
}
