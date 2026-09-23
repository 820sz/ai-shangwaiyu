import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/vocab_provider.dart';
import '../../services/backup_service.dart';
import '../../services/export_service.dart';

/// 备份与导出(v2.2「生产力」)。
///
/// 为什么这个页面很重要:本 App 的设计是"数据只在这台手机上"
/// (系统云备份已关闭,防明文 Key 上云),所以**导出是用户唯一的数据主权出口**:
/// 换机、丢机、误清数据都靠它。三条出口各有用途:
/// - **完整备份(JSON)**:唯一的"可回导"格式,换机就靠它;
/// - **生词本 CSV**:给 Excel/表格用,人可读;
/// - **Anki 导入包(TSV)**:把词汇资产搬到别的记忆工具里(不被本项目锁死)。
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  /// 分享通道:与 MainActivity.kt 的 app/share_text 对应(零依赖)
  static const MethodChannel _shareChannel = MethodChannel('app/share_text');

  final _pasteCtrl = TextEditingController();
  BackupData? _parsed;
  bool _busy = false;
  ExportedFile? _lastExport;

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ExportedFile> Function() job, String label) async {
    setState(() => _busy = true);
    try {
      final file = await job();
      if (!mounted) return;
      setState(() {
        _lastExport = file;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label 已导出(${file.bytes} 字符)')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label 失败:$e')),
      );
    }
  }

  /// 阅读包导出:返回的是"文件夹 + 若干文件",与单个文件导出不是同一形态,
  /// 所以单独一条路径(复用同一个 _busy 锁,避免并发写盘)
  Future<void> _runPack() async {
    setState(() => _busy = true);
    try {
      final report = await BackupService.exportAllMaterialsPack();
      if (!mounted) return;
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('阅读包已导出'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('导出 ${report.count} 篇材料(每篇一个 Markdown 文件)。'),
              const SizedBox(height: 8),
              SelectableText('位置:${report.dirPath}'),
              if (report.failed > 0) ...[
                const SizedBox(height: 8),
                Text('另有 ${report.failed} 篇没有正文,已跳过。'),
              ],
              const SizedBox(height: 8),
              const Text('每个文件都带来源、原文链接与版权许可 —— 请勿再分发。'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('阅读包导出失败:$e')),
      );
    }
  }

  Future<void> _copy(ExportedFile file) async {
    await Clipboard.setData(ClipboardData(text: file.content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('内容已复制 —— 可粘到备忘录/微信/云盘')),
    );
  }

  Future<void> _share(ExportedFile file) async {
    try {
      await _shareChannel.invokeMethod('shareText', {
        'text': file.content,
        'title': file.fileName,
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开分享面板失败:${e.message ?? e.code}')),
      );
    }
  }

  void _parse() {
    final data = ExportService.parseBackup(_pasteCtrl.text);
    setState(() => _parsed = data);
  }

  Future<void> _restore({required bool replace}) async {
    final data = _parsed;
    if (data == null || !data.ok) return;
    if (replace) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('覆盖导入?'),
          content: Text(
            '会先**清空当前的 ${context.read<VocabProvider>().vocabularies.length} 个生词**'
            '与全部复习状态,再导入备份里的 ${data.vocab.length} 个词。\n\n'
            '这个操作不可撤销 —— 如果当前数据还有用,请先导出一份完整备份。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空并导入'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _busy = true);
    final report = await BackupService.restore(data, replace: replace);
    if (!mounted) return;
    // 词库变了 → 让 Provider 重新读一遍,别让界面显示旧数据
    await context.read<VocabProvider>().loadVocabularies();
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(report.summary),
            if (report.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final w in report.warnings)
                Text('⚠️ $w', style: const TextStyle(color: Colors.orange)),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('备份与导出')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '你的数据只在这台手机上(系统云备份已关闭)。'
            '换机、丢机或误清数据前,请先导出一份完整备份。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 16),

          // ── 导出 ──
          Text('导出',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _exportCard(
            theme,
            icon: Icons.backup_outlined,
            title: '完整备份(JSON)',
            subtitle: '生词 + 复习进度 + 学习画像 + 偏好。**只有它能回导**,换机迁移用这个',
            onTap: _busy ? null : () => _run(BackupService.exportBackupJson, '完整备份'),
          ),
          _exportCard(
            theme,
            icon: Icons.table_chart_outlined,
            title: '生词本 CSV',
            subtitle: 'Excel / 表格可直接打开(含释义、双音标、掌握度、复习状态)',
            onTap: _busy ? null : () => _run(BackupService.exportVocabCsv, 'CSV'),
          ),
          _exportCard(
            theme,
            icon: Icons.style_outlined,
            title: 'Anki 导入包(TSV)',
            subtitle: '正面=单词,背面=释义+音标+例句,标签带掌握度 —— 可导入 Anki 等工具',
            onTap: _busy ? null : () => _run(BackupService.exportVocabAnkiTsv, 'Anki 包'),
          ),

          _exportCard(
            theme,
            icon: Icons.auto_stories_outlined,
            title: '阅读包(全部材料 · Markdown)',
            subtitle: '材料库里每篇材料导成一个 .md(元信息 + 正文 + 生词表),'
                '可丢进网盘或笔记软件按篇管理',
            onTap: _busy ? null : _runPack,
          ),

          if (_lastExport != null) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.primary.withAlpha(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最近导出:${_lastExport!.fileName}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    SelectableText(
                      '文件位置:${_lastExport!.path}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _copy(_lastExport!),
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('复制内容'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _share(_lastExport!),
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text('分享/发送'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          const Divider(height: 32),

          // ── 导入 ──
          Text('从备份恢复',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '把备份 JSON 的内容粘进下面(全选复制文件内容即可)。'
            '「合并」只补本地没有的词;「覆盖」会先清空本地生词再导入。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pasteCtrl,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '在此粘贴备份 JSON…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(onPressed: _busy ? null : _parse, child: const Text('解析')),
              const SizedBox(width: 8),
              if (_parsed != null)
                Expanded(
                  child: Text(
                    _parsed!.ok ? '识别到:${_parsed!.summaryLine}' : '❌ ${_parsed!.error}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _parsed!.ok ? muted : Colors.red,
                    ),
                  ),
                ),
            ],
          ),
          if (_parsed?.ok == true) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _restore(replace: false),
                    child: const Text('合并导入'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _restore(replace: true),
                    child: const Text('覆盖导入'),
                  ),
                ),
              ],
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 20),
          Text(
            '⚠️ 备份文件里**不包含 API Key**(那是你的密钥,不该出现在导出文件里),'
            '换机后需要在「API 设置」里重新填一次。',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }

  Widget _exportCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        trailing: const Icon(Icons.download_outlined),
        onTap: onTap,
      ),
    );
  }
}
