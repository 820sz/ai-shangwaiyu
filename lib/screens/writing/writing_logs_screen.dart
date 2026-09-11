import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/writing_log.dart';
import '../../services/database.dart';

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
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : logs == null
          ? const Center(child: CircularProgressIndicator())
          : logs.isEmpty
          ? _buildEmpty(theme)
          : RefreshIndicator(
              onRefresh: _load,
              child: _buildList(theme),
            ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_edu_outlined, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            '还没有保存的写译练习',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
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
                Text(
                  groups[date]!.first.dateLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${groups[date]!.length} 篇',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scoreColor.withAlpha(25),
            border: Border.all(color: scoreColor.withAlpha(120), width: 1.5),
          ),
          child: Center(
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
        title: Text(
          log.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(
                log.timeLabel,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(width: 8),
              _chip(
                log.sourceType == 'handwritten' ? '手写档' : '电子档',
                log.sourceType == 'handwritten'
                    ? Colors.deepPurple
                    : Colors.blueGrey,
              ),
              if (log.issueCount > 0) ...[
                const SizedBox(width: 6),
                _chip('${log.issueCount} 处问题', Colors.orange),
              ],
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

  void _confirmDelete(WritingLog log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除练习记录'),
        content: Text('确定删除「${log.title}」吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              if (log.id != null) {
                await DatabaseService.deleteWritingLog(log.id!);
              }
              await _load();
            },
            child: const Text('删除'),
          ),
        ],
      ),
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
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  '${log.dateLabel} ${log.timeLabel}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                _chip(
                  log.sourceType == 'handwritten' ? '手写档' : '电子档',
                  log.sourceType == 'handwritten'
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
                            color: Colors.black87,
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
                            color: Colors.grey[600],
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
                color: Colors.grey[700],
              ),
            ),
            if ((log.model ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '批改模型:${log.model}',
                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
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
