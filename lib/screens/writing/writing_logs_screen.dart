import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/writing_log.dart';
import '../../services/database.dart';
import '../../widgets/confirm_destructive.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
import '../../widgets/writing_labels.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('写译记录'),
        actions: [
          if ((logs ?? []).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '共 ${logs!.length} 篇',
                  // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
      return const Center(
        key: ValueKey('logs-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (logs.isEmpty) {
      return const EmptyState(
        key: ValueKey('logs-empty'),
        icon: Icons.history_edu_outlined,
        title: '还没有保存的写译练习',
        hint: '在「写译批改」批改后点「保存记录」即可归档到这里',
      );
    }
    return RefreshIndicator(
      key: const ValueKey('logs-list'),
      onRefresh: _load,
      child: _buildList(theme),
    );
  }

  Widget _buildList(ThemeData theme) {
    final groups = _groupByDate();
    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        for (final date in dates) ...[
          // 日期文件夹标题
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  size: 18,
                  color: Colors.amber[700],
                ),
                const SizedBox(width: 6),
                // B3:日期是变长文本,给 Flexible 让它换行而不是把这一行挤爆
                Flexible(
                  child: Text(
                    groups[date]!.first.dateLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${groups[date]!.length} 篇',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ...groups[date]!.map((log) => _logCard(theme, log)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _logCard(ThemeData theme, WritingLog log) {
    final score = int.tryParse(log.score ?? '');
    final scoreColor = score == null
        ? Colors.grey
        : score >= 80
        ? Colors.green
        : score >= 60
        ? Colors.orange
        : Colors.red;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: ConstrainedBox(
          // B3:原来是 44×44 的硬盒子装 fontSize 14 的分数,系统字号放大到
          // 1.5×~2× 时文字会被裁掉。改成"下限 44(保持原视觉)+ 上限 60",
          // 配 FittedBox:正常字号仍占 44,字号放大时盒子长一点,
          // 极端字号下缩小填进去,永不裁切。
          constraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
            maxWidth: 60,
            maxHeight: 60,
          ),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scoreColor.withAlpha(25),
              border: Border.all(
                color: scoreColor.withAlpha(120),
                width: 1.5,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                (log.score ?? '').isEmpty ? '--' : log.score!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          log.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          // B3:原来是一个 Row,系统字号放大到 2× 时"时间 + 两个标签"必然
          // 横向溢出(黄黑条纹)。改 Wrap:正常字号仍是一行,字号大时自动换行。
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                log.timeLabel,
                // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              _chip(
                materialTypeLabel(log.sourceType),
                log.sourceType == kMaterialTypeHandwritten
                    ? Colors.deepPurple
                    : Colors.blueGrey,
              ),
              if (log.issueCount > 0)
                _chip('${log.issueCount} 处问题', Colors.orange),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () => _confirmDelete(log),
        ),
        onTap: () => _showDetail(log),
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
      message: '确定删除「${log.title}」吗？删除后不可恢复。',
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
                      ? Colors.deepPurple
                      : Colors.blueGrey,
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
                            color: Colors.red[400],
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      if ((it['correction'] ?? '').isNotEmpty)
                        Text(
                          it['correction']!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green[700],
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
