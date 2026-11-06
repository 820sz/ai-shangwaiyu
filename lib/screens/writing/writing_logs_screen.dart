import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/writing_log.dart';
import '../../widgets/v4/v4_kit.dart';
import '../../services/database.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/confirm_destructive.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/error_state.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/waiting.dart';
import '../../widgets/writing_labels.dart';
import 'write_review_screen.dart';

/// 写译记录(v1.6.0):按日期文件夹归档的写译练习轨迹,可查阅复盘。
class WritingLogsScreen extends StatefulWidget {
  const WritingLogsScreen({super.key});

  @override
  State<WritingLogsScreen> createState() => _WritingLogsScreenState();
}

class _WritingLogsScreenState extends State<WritingLogsScreen> {
  List<WritingLog>? _logs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final logs = await DatabaseService.getWritingLogs();
      if (mounted) {
        setState(() {
          _logs = logs;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败：$e');
    }
  }

  /// 重试(P2-30):先回到加载态再拉数据——
  /// 否则重试期间页面还挂着上一次的错误,看不出"点了有没有反应"
  Future<void> _retry() async {
    setState(() {
      _error = null;
      _logs = null;
    });
    await _load();
  }

  /// 按日期分组(日期文件夹)
  Map<String, List<WritingLog>> _groupByDate() {
    final groups = <String, List<WritingLog>>{};
    for (final log in _logs ?? <WritingLog>[]) {
      groups.putIfAbsent(log.dateKey, () => []).add(log);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logs = _logs;
    final all = logs ?? const <WritingLog>[];
    final summary = _summary(all);
    return Scaffold(
      appBar: V4JellyAppBar(
        title: '写译记录',
        actions: <Widget>[
          if (all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: Center(
                // 顶部只放两个真数字(篇数 / 均分):用户一眼看到产出与水平
                child: Text(
                  summary,
                  style: AppFont.metaStyle
                      .copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        // A1:加载/失败/空/列表之间 180ms easeOut 切换,不再硬切
        // (只有低频的状态切换才给动效,列表滚动等高频操作不加)
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        child: _buildBody(theme),
      ),
    );
  }

  /// 三态(P2-30 / B4):加载中 / 加载失败可重试 / 空态与列表。
  /// 失败态此前只是一个裸 Text(连重试按钮都没有),用户只能退出去重进。
  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return ErrorState(
        key: const ValueKey('logs-error'),
        message: _error!,
        onRetry: _retry,
      );
    }
    final logs = _logs;
    if (logs == null) {
      // 整页记录在读取:骨架屏先铺出"日期分组 + 条目"的形状,
      // 读到后原地替换;key 必须保留,AnimatedSwitcher 靠它做切场。
      return const Padding(
        key: ValueKey('logs-loading'),
        padding: Insets.page,
        child: SkeletonLines(lines: 6, seed: 1),
      );
    }
    if (logs.isEmpty) {
      // 空态必须给"下一步":只写"暂无记录"用户仍然不知道从哪里开始
      return Center(
        key: const ValueKey('logs-empty'),
        child: SingleChildScrollView(
          padding: Insets.page,
          child: AppEmptyState(
            icon: Icons.edit_note,
            art: EmptyArtKind.scatteredLetters,
            title: '还没有写译记录',
            hint: '批改完点「保存记录」就会按日期归档到这里;'
                '攒几篇回看,能看出自己反复踩的坑',
            action: FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WriteReviewScreen()),
              ).then((_) {
                if (mounted) _load();
              }),
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('去写译批改'),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      key: const ValueKey('logs-list'),
      onRefresh: _load,
      child: _buildList(theme),
    );
  }

  /// 按日期分组的标题 + 组内均分:日期头只显示"几篇"太单薄,
  /// 有了分数才能一眼看出"那天写得好不好"(没有分数的记录不参与均分)。
  Widget _dateHeader(ThemeData theme, String date, List<WritingLog> logs) {
    final avg = _avgScore(logs);
    return AppSectionTitle(
      title: logs.first.dateLabel,
      subtitle: avg == null ? '${logs.length} 篇' : '${logs.length} 篇 · 均分 $avg',
      padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.xxs),
    );
  }

  /// 顶部摘要:共几篇 + 均分(有评分才显示)—— 两个都是本机真实数据
  String _summary(List<WritingLog> logs) {
    final avg = _avgScore(logs);
    return avg == null ? '共 ${logs.length} 篇' : '共 ${logs.length} 篇 · 均分 $avg';
  }

  /// 记录里的分数(坏值返回 null:不把"解析失败"当 0 分)
  static int? _scoreOf(WritingLog log) {
    final raw = int.tryParse((log.score ?? '').trim());
    if (raw == null) return null;
    return raw.clamp(0, 100);
  }

  /// 一组记录的均分;一条评分都没有时返回 null(不显示 0 分)
  static int? _avgScore(List<WritingLog> logs) {
    final scores = logs.map(_scoreOf).whereType<int>().toList();
    if (scores.isEmpty) return null;
    final sum = scores.fold<int>(0, (a, b) => a + b);
    return (sum / scores.length).round();
  }

  /// 分数语义色:>=80 成功 / >=60 注意 / 其余危险 —— 与写译批改结果页同一套阈值
  Color _scoreColor(BuildContext context, int? score) {
    if (score == null) return Theme.of(context).colorScheme.onSurfaceVariant;
    if (score >= 80) return AppTheme.successColor(context);
    if (score >= 60) return AppTheme.warningColor(context);
    return AppTheme.dangerColor(context);
  }

  Widget _buildList(ThemeData theme) {
    final groups = _groupByDate();
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView(
      padding: Insets.page,
      children: [
        _summaryCard(theme, _logs ?? const []),
        for (final date in dates) ...[
          _dateHeader(theme, date, groups[date]!),
          ...groups[date]!.map((log) => _logCard(theme, log)),
          const SizedBox(height: Gap.xs),
        ],
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  /// 顶部摘要卡:产出量 + 均分(均分没有评分时显示"待评分",不写 0 分)
  Widget _summaryCard(ThemeData theme, List<WritingLog> logs) {
    final avg = _avgScore(logs);
    final muted = theme.colorScheme.onSurfaceVariant;
    return AppCard(
      variant: AppCardVariant.accent,
      child: Row(
        children: [
          Icon(Icons.edit_note, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('保存下来的写译练习', style: AppFont.subheadStyle),
                const SizedBox(height: 2),
                Text(
                  '共 ${logs.length} 篇 · 点开可看逐条点评与修正全文',
                  style: AppFont.metaStyle.copyWith(color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.xs),
          AppTag(
            avg == null ? '待评分' : '均分 $avg',
            tone: avg == null
                ? AppTagTone.neutral
                : (avg >= 80
                    ? AppTagTone.success
                    : (avg >= 60 ? AppTagTone.warning : AppTagTone.danger)),
            icon: Icons.insights_outlined,
          ),
        ],
      ),
    );
  }

  Widget _logCard(ThemeData theme, WritingLog log) {
    final score = _scoreOf(log);
    final scoreColor = _scoreColor(context, score);
    return AppCard(
      onTap: () => _showDetail(log),
      margin: const EdgeInsets.only(bottom: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _scoreBadge(scoreColor, log),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFont.subheadStyle,
                ),
                const SizedBox(height: Gap.xxs),
                Wrap(
                  spacing: Gap.xs,
                  runSpacing: Gap.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      log.timeLabel,
                      style: AppFont.metaStyle.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    AppTag(
                      materialTypeLabel(log.sourceType),
                      tone: log.sourceType == kMaterialTypeHandwritten
                          ? AppTagTone.primary
                          : AppTagTone.neutral,
                      icon: log.sourceType == kMaterialTypeHandwritten
                          ? Icons.gesture
                          : Icons.keyboard_alt_outlined,
                    ),
                    if (log.issueCount > 0)
                      AppTag(
                        '${log.issueCount} 处问题',
                        tone: AppTagTone.warning,
                        icon: Icons.edit_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            tooltip: '删除这条记录',
            onPressed: () => _confirmDelete(log),
          ),
        ],
      ),
    );
  }

  /// 分数徽标:圆形底色 + 大数字(结果页/记录页同一套语义色阈值)
  Widget _scoreBadge(Color color, WritingLog log) {
    final text = (log.score ?? '').trim();
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(24),
        border: Border.all(color: color.withAlpha(110), width: 1.5),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text.isEmpty ? '--' : text,
          style: AppFont.tagStyle.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 删除记录(P2-28):确认弹窗改用公共 [confirmDestructive](红底 + 不可恢复提示),
  /// 并且删除成功后给 SnackBar——此前删完页面只是少一张卡,没有任何反馈。
  Future<void> _confirmDelete(WritingLog log) async {
    final ok = await confirmDestructive(
      context,
      title: '删除练习记录',
      message: '只删除本机这条写译记录,不影响原文与材料。'
          '删除后不可恢复(可用下方「撤销」找回)。',
    );
    if (!ok || !mounted) return;
    try {
      if (log.id != null) {
        await DatabaseService.deleteWritingLog(log.id!);
      }
    } catch (e) {
      if (mounted) showFeedbackSnack(context, '删除失败：$e');
      return;
    }
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    showFeedbackSnack(
      context,
      '已删除练习记录',
      actionLabel: '撤销',
      // 撤销要留够反应时间(默认 3 秒给普通提示用)
      duration: const Duration(seconds: 6),
      // 撤销 = 用同一条记录(含原 id、原 createdAt)重新插回,
      // 日期分组与"共 N 篇"都会跟着恢复
      onAction: () async {
        try {
          await DatabaseService.insertWritingLog(log);
        } catch (e) {
          debugPrint('ReadFlow writingLog undo: $e');
        }
        if (mounted) await _load();
      },
    );
  }

  void _showDetail(WritingLog log) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                // B3:日期是变长文本,给 Flexible 让它换行——
                // 否则字号放大到 2× 时这一行必然横向溢出
                Flexible(
                  child: Text(
                    '${log.dateLabel} ${log.timeLabel}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _chip(
                  materialTypeLabel(log.sourceType),
                  log.sourceType == kMaterialTypeHandwritten
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const Spacer(),
                if ((log.score ?? '').isNotEmpty)
                  Text(
                    '${log.score} 分',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
              ],
            ),
            if ((log.summary ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(log.summary!, style: theme.textTheme.bodyMedium),
            ],
            // 手写原稿
            if (log.imagePaths.any((p) => File(p).existsSync())) ...[
              const SizedBox(height: 16),
              _sectionTitle(theme, '手写原稿'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: log.imagePaths
                    .where((p) => File(p).existsSync())
                    .map(
                      (p) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(p),
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            // 错误分类汇总
            if (log.errorSummary.values.any((v) => v.trim().isNotEmpty)) ...[
              const SizedBox(height: 16),
              _sectionTitle(theme, '错误分类汇总'),
              const SizedBox(height: 8),
              ...WritingLog.categories
                  .where((c) => (log.errorSummary[c] ?? '').trim().isNotEmpty)
                  .map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.5,
                            color: theme.colorScheme.onSurface,
                          ),
                          children: [
                            TextSpan(
                              text: '$c：',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: log.errorSummary[c]),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
            // 逐条点评
            if (log.issues.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionTitle(theme, '逐条点评（${log.issues.length}）'),
              const SizedBox(height: 8),
              ...log.issues.asMap().entries.map((e) {
                final it = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${e.key + 1}. ${it['type'] ?? ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if ((it['original'] ?? '').isNotEmpty)
                        Text(
                          it['original']!,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.dangerColor(context),
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      if ((it['correction'] ?? '').isNotEmpty)
                        Text(
                          it['correction']!,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.successColor(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if ((it['reason'] ?? '').isNotEmpty)
                        Text(
                          it['reason']!,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
            if ((log.correctedText ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionTitle(theme, '修正后全文'),
              const SizedBox(height: 6),
              SelectableText(
                log.correctedText!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ],
            const SizedBox(height: 16),
            _sectionTitle(theme, '我的原文'),
            const SizedBox(height: 6),
            SelectableText(
              log.originalText,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if ((log.model ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '批改模型:${log.model}',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
