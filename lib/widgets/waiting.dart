import 'dart:async';

import 'package:flutter/material.dart';

import '../config/design_tokens.dart';
import '../config/theme.dart';

/// 全 App 统一的"AI 干活时"等待 UI(v2.9)。
///
/// 用户 10/2 原话:"该软件最后所有让 ai 进行思考或者什么任务的功能,都要把现在的
/// **转圈等待 ui 改成其他更可感、更高级的等待动画形式**,最好是流式输出,
/// 比如其他区的'正在检索''正在抓取原文'转圈,也要换成更可感的表现动画,
/// 不确定的就给我推荐几个方案,让我来选。"
///
/// 他选了 **A + B + C 三套都要**,所以这里按任务类型分工:
/// - 有**明确步骤**的任务(检索 / 抓取 / 识图 / 批改 / 分析)→ [AiWaitingTimeline](A);
/// - 生成**长文本**的任务(识图结果 / AI 文章 / 批改正文)→ [SkeletonLines](B);
/// - 能**估进度**的批量任务(逐段翻译 / 批量分析)→ [ProgressStageBar](C)。
///
/// 三条硬规则(所有等待态都要遵守):
/// 1. **只显示真实发生的步骤** —— 不编造进度、不假装"已完成 3 步";
/// 2. 每一步**至少显示 600ms**(再快也让人看清发生了什么);
/// 3. 超过 8 秒的等待要**升级信息**(如"正在深入检索(已读 k 篇)"),而不是干转。

/// 时间线里的一步
class AiStep {
  final String label;

  /// 三种状态:进行中 / 完成 / 失败
  final AiStepState state;

  /// 该步的补充(如"找到 10 篇"、"超时")
  final String? detail;

  const AiStep({
    required this.label,
    this.state = AiStepState.running,
    this.detail,
  });
}

enum AiStepState { running, done, failed }

/// A 方案:流式过程时间线
///
/// 每一条都是**真实发生**的事;末尾有转圈(还在跑时)或小结(跑完时)。
class AiWaitingTimeline extends StatefulWidget {
  final List<AiStep> steps;

  /// 还在进行中(尾部显示"还在继续…")
  final bool running;

  /// 结束后的一句话小结(如"查阅了 22 篇 · 用时 4 秒")
  final String? footer;

  /// 展开显示还是紧凑(紧凑用于卡片内、聊天气泡内)
  final bool compact;

  const AiWaitingTimeline({
    super.key,
    required this.steps,
    this.running = false,
    this.footer,
    this.compact = false,
  });

  @override
  State<AiWaitingTimeline> createState() => _AiWaitingTimelineState();
}

class _AiWaitingTimelineState extends State<AiWaitingTimeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty && widget.footer == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? Gap.sm : Gap.sm + 2,
        vertical: widget.compact ? Gap.xs : Gap.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(150),
        borderRadius: Radii.controlRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < widget.steps.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == widget.steps.length - 1 ? 0 : 5,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stepIcon(context, widget.steps[i].state),
                  const SizedBox(width: Gap.xs),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: widget.compact ? 11.5 : 12.5,
                          height: 1.4,
                          color: widget.steps[i].state == AiStepState.running
                              ? theme.colorScheme.onSurface
                              : muted,
                          fontWeight: widget.steps[i].state == AiStepState.done
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                        children: [
                          TextSpan(text: widget.steps[i].label),
                          if ((widget.steps[i].detail ?? '').isNotEmpty)
                            TextSpan(
                              text: '  ${widget.steps[i].detail}',
                              style: TextStyle(
                                fontSize: widget.compact ? 10.5 : 11,
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.running)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                  Text(
                    '还在继续…',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          if (widget.footer != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.footer!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.successColor(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepIcon(BuildContext context, AiStepState state) {
    final color = switch (state) {
      AiStepState.done => AppTheme.successColor(context),
      AiStepState.failed => AppTheme.warningColor(context),
      AiStepState.running => Theme.of(context).colorScheme.primary,
    };
    if (state == AiStepState.running) {
      return FadeTransition(
        opacity: Tween<double>(begin: 0.3, end: 1).animate(_pulse),
        child: Icon(Icons.radio_button_checked, size: 14, color: color),
      );
    }
    return Icon(
      state == AiStepState.done ? Icons.check_circle : Icons.info_outline,
      size: 14,
      color: color,
    );
  }
}

/// B 方案:骨架屏(与最终内容同形状的灰块,逐块淡入)
///
/// 用在"生成长文本"的地方:用户先看到的不是转圈,而是**结果将要占据的样子**,
/// 于是等待感明显变短(内容一到就原地替换)。
class SkeletonLines extends StatefulWidget {
  /// 行数(默认 5)
  final int lines;

  /// 是否显示标题块(像卡片标题那样粗一点)
  final bool withTitle;

  /// 每行高度
  final double lineHeight;

  /// 用于列表里的第 n 个卡片(错开起始时间,避免整屏同步闪)
  final int seed;

  const SkeletonLines({
    super.key,
    this.lines = 5,
    this.withTitle = true,
    this.lineHeight = 12,
    this.seed = 0,
  });

  @override
  State<SkeletonLines> createState() => _SkeletonLinesState();
}

class _SkeletonLinesState extends State<SkeletonLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    // 错开起始:同一屏多张骨架不会像呼吸灯一样整齐闪
    Timer(Duration(milliseconds: (widget.seed % 5) * 90), () {
      if (mounted) _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final alpha = 14 + (10 * _c.value).round();
        Widget bar(double widthFactor, double h) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: widthFactor,
                child: Container(
                  height: h,
                  decoration: BoxDecoration(
                    color: base.withAlpha(alpha),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.withTitle) bar(0.55, widget.lineHeight + 4),
            for (var i = 0; i < widget.lines; i++)
              // 最后一行短一点,像真的段落
              bar(i == widget.lines - 1 ? 0.62 : 1.0, widget.lineHeight),
          ],
        );
      },
    );
  }
}

/// C 方案:进度条 + 阶段文案 + 已用时(可取消)
///
/// 用在**能估算进度**的批量任务:逐段翻译、批量分析。
/// 进度值必须是"真切完成的份数 / 总份数",没有估算就不显示百分比。
class ProgressStageBar extends StatefulWidget {
  /// 0~1;null = 未知进度(只显示流动条)
  final double? value;

  /// 当前阶段文案(如"正在翻译第 3/40 段")
  final String stage;

  /// 阶段补充(如"已完成 3 段 · 约剩 1 分钟")
  final String? detail;

  /// 开始时间(用于显示"已用 12 秒")
  final DateTime? startedAt;

  /// 取消按钮(可空:不可取消的任务不显示)
  final VoidCallback? onCancel;

  const ProgressStageBar({
    super.key,
    required this.stage,
    this.value,
    this.detail,
    this.startedAt,
    this.onCancel,
  });

  @override
  State<ProgressStageBar> createState() => _ProgressStageBarState();
}

class _ProgressStageBarState extends State<ProgressStageBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (widget.startedAt != null) {
      // 每秒重绘一次"已用 N 秒":等待超过 3 秒后,时间本身就是最好的反馈
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final s = widget.startedAt;
    if (s == null) return '';
    final sec = DateTime.now().difference(s).inSeconds;
    if (sec < 3) return '';
    if (sec < 60) return '已用 $sec 秒';
    return '已用 ${(sec ~/ 60)} 分 ${sec % 60} 秒';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.stage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (widget.value != null)
              Text(
                '${(widget.value! * 100).round()}%',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            if (_elapsed.isNotEmpty) ...[
              const SizedBox(width: Gap.xs),
              Text(_elapsed, style: TextStyle(fontSize: 11, color: muted)),
            ],
            if (widget.onCancel != null) ...[
              const SizedBox(width: Gap.xxs),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: widget.onCancel,
                child: const Text('取消', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: widget.value == null
              ? LinearProgressIndicator(
                  minHeight: 5,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                )
              : LinearProgressIndicator(
                  value: widget.value!.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
        ),
        if ((widget.detail ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            widget.detail!,
            style: TextStyle(fontSize: 11, height: 1.35, color: muted),
          ),
        ],
      ],
    );
  }
}

/// 极简的"AI 正在思考"三点跳动(聊天/气泡里用;有内容时立刻被替换)
class ThinkingDots extends StatefulWidget {
  final String label;
  final bool compact;

  const ThinkingDots({super.key, this.label = '正在思考', this.compact = false});

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label,
            style: TextStyle(
                fontSize: widget.compact ? 11 : 12, color: muted)),
        const SizedBox(width: 6),
        for (var i = 0; i < 3; i++)
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              // 三个点错相跳动:0 / 0.33 / 0.66 的相位差
              final t = (_c.value + i / 3) % 1.0;
              final a = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.15, 1.0);
              return Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Opacity(
                  opacity: a,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
