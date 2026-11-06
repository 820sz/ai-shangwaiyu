import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../providers/vocab_provider.dart';
import '../../services/backup_service.dart';
import '../../services/export_service.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/waiting.dart';
import '../../widgets/v4/v4_kit.dart';

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

  /// 表名 → 用户能看懂的中文(恢复报告逐行显示用;内部表名不直接给用户看)。
  String _tableLabel(String table) => switch (table) {
        'material_translations' => '阅读译文',
        'exercise_sets' => '题组',
        'exercise_items' => '题目',
        'output_attempts' => '输出作答',
        'ability_snapshots' => '能力快照',
        'task_events' => '任务事件',
        'tutor_tasks' => '学习任务',
        'error_tags' => '错误档案',
        'word_review' => '复习记录',
        'rubrics' => '评分标准',
        'vocabulary' => '生词',
        'materials' => '材料',
        'material_content' => '正文',
        'material_progress' => '阅读进度',
        'daily_log' => '学习日志',
        _ => table,
      };

  Future<void> _run(Future<ExportedFile> Function() job, String label) async {
    setState(() => _busy = true);
    try {
      final file = await job();
      if (!mounted) return;
      setState(() {
        _lastExport = file;
        _busy = false;
      });
      // v3 批 8:备份可能被截断(最近 5000 条),截断事实必须让用户看见 ——
      // 否则用户以为"全备份了",换机后少数据会以为软件丢数据。
      final notes = file.notes.where((n) => n.trim().isNotEmpty).toList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notes.isEmpty
                ? '$label 已导出(${file.bytes} 字符)'
                : '$label 已导出(${file.bytes} 字符)${'\n'}${notes.join('\n')}',
          ),
          duration: notes.isEmpty
              ? const Duration(seconds: 4)
              : const Duration(seconds: 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label 失败:$e')));
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
              const SizedBox(height: Gap.xs),
              SelectableText('位置:${report.dirPath}'),
              if (report.failed > 0) ...[
                const SizedBox(height: Gap.xs),
                Text('另有 ${report.failed} 篇没有正文,已跳过。'),
              ],
              const SizedBox(height: Gap.xs),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('阅读包导出失败:$e')));
    }
  }

  Future<void> _copy(ExportedFile file) async {
    await Clipboard.setData(ClipboardData(text: file.content));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('内容已复制 —— 可粘到备忘录/微信/云盘')));
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
            '会先清空:当前 ${context.read<VocabProvider>().vocabularies.length} 个生词'
            ' + 全部复习状态(不可撤销)。\n\n'
            '然后导入:备份里的 ${data.vocab.length} 个词'
            ' + 复习进度/学习画像。\n\n'
            '不会动:材料库、阅读记录、学习统计与 API 设置。\n'
            '如果当前数据还有用,请先导出一份完整备份。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.dangerColor(context),
                foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
              ),
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
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(report.summary),
            // v3 批 8:恢复报告逐表条数(用户换机后要能核对"哪些数据回来了")
            if (report.tables.isNotEmpty) ...[
              const SizedBox(height: Gap.xs),
              for (final entry in report.tables.entries)
                if (entry.value.restored > 0 || entry.value.skipped > 0)
                  Text(
                    '· ${_tableLabel(entry.key)}:'
                    '恢复 ${entry.value.restored}'
                    '${entry.value.skipped > 0 ? ',跳过 ${entry.value.skipped}' : ''}',
                    style: AppFont.tagStyle.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
            ],
            const SizedBox(height: 2),
            Text(
              '备份格式版本:${report.backupVersion}',
              style: AppFont.tagStyle
                  .copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),            if (report.warnings.isNotEmpty) ...[
              const SizedBox(height: Gap.xs),
              for (final w in report.warnings)
                Text(
                  '⚠️ $w',
                  style: TextStyle(color: AppTheme.warningColor(context)),
                ),
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
      appBar: const V4JellyAppBar(title: '备份与导出'),
      body: ListView(
        padding: Insets.page,
        children: [
          Text(
            '你的数据只在这台手机上(系统云备份已关闭)。'
            '换机、丢机或误清数据前,请先导出一份完整备份。',
            style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
          ),
          const SizedBox(height: Gap.xs),

          // ── 01 导出 ──
          const AppSectionHeader(indexLabel: '01', title: '导出'),
          _exportCard(
            icon: Icons.backup_outlined,
            title: '完整备份(JSON)',
            subtitle: '生词 + 复习进度 + 学习画像 + 偏好。「只有它能回导」,换机迁移用这个',
            onTap: _busy
                ? null
                : () => _run(BackupService.exportBackupJson, '完整备份'),
          ),
          _exportCard(
            icon: Icons.table_chart_outlined,
            title: '生词本 CSV',
            subtitle: 'Excel / 表格可直接打开(含释义、双音标、掌握度、复习状态)',
            onTap: _busy
                ? null
                : () => _run(BackupService.exportVocabCsv, 'CSV'),
          ),
          _exportCard(
            icon: Icons.style_outlined,
            title: 'Anki 导入包(TSV)',
            subtitle: '正面=单词,背面=释义+音标+例句,标签带掌握度 —— 可导入 Anki 等工具',
            onTap: _busy
                ? null
                : () => _run(BackupService.exportVocabAnkiTsv, 'Anki 包'),
          ),

          _exportCard(
            icon: Icons.auto_stories_outlined,
            title: '阅读包(全部材料 · Markdown)',
            subtitle:
                '材料库里每篇材料导成一个 .md(元信息 + 正文 + 生词表),'
                '可丢进网盘或笔记软件按篇管理',
            onTap: _busy ? null : _runPack,
          ),

          if (_lastExport != null) ...[
            const SizedBox(height: Gap.sm),
            AppCard(
              color: theme.colorScheme.primary.withAlpha(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '最近导出:${_lastExport!.fileName}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Gap.xxs),
                  SelectableText(
                    '文件位置:${_lastExport!.path}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: Gap.xs),
                  // 一排按钮统一用 Wrap:窄屏/大字号自动换行,不把右边裁掉
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: Gap.xs,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _copy(_lastExport!),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('复制内容'),
                      ),
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
          ],

          const Divider(height: 32),

          // ── 02 从备份恢复 ──
          const AppSectionHeader(indexLabel: '02', title: '从备份恢复'),
          Text(
            '把备份 JSON 的内容粘进下面(全选复制文件内容即可)。'
            '「合并」只补本地没有的词;「覆盖」会先清空本地生词再导入。',
            style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
          ),
          const SizedBox(height: Gap.xs),
          TextField(
            controller: _pasteCtrl,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '在此粘贴备份 JSON…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Gap.xs),
          Row(
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _parse,
                child: const Text('解析'),
              ),
              const SizedBox(width: Gap.xs),
              if (_parsed != null)
                Expanded(
                  child: Text(
                    _parsed!.ok
                        ? '识别到:${_parsed!.summaryLine}'
                        : '❌ ${_parsed!.error}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _parsed!.ok
                          ? muted
                          : AppTheme.dangerColor(context),
                    ),
                  ),
                ),
            ],
          ),
          if (_parsed?.ok == true) ...[
            const SizedBox(height: Gap.sm),
            // 一排按钮用 Wrap:窄屏/大字号自动换行(原来两个 Expanded 硬挤一行)
            Wrap(
              spacing: Gap.sm,
              runSpacing: Gap.sm,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _restore(replace: false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                  ),
                  child: const Text('合并导入'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _restore(replace: true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                  ),
                  child: const Text('覆盖导入'),
                ),
              ],
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: Gap.md),
            // v2.10:整块加载态不再转圈。备份/恢复是"批量读写、但算不出百分比"
            // 的动作,用 ProgressStageBar 的未知进度流动条(value: null)说明
            // "确实还在动";这里并没有内容要出现,所以不用骨架屏(那会假装
            // 马上有卡片加载出来)。
            const ProgressStageBar(stage: '正在处理备份…', detail: '数据正在读写,请勿退出 App'),
          ],
          const SizedBox(height: Gap.lg),
          // ── 03 注意 ──
          const AppSectionHeader(indexLabel: '03', title: '注意'),
          AppCard(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Text(
              '· 备份文件里不包含 API Key(那是你的密钥,不该出现在导出文件里),'
              '换机后需要在「API 设置」里重新填一次。',
              style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exportCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return AppActionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      // 忙碌中要**看得出来**是不可用的(原来 ListTile 会自动置灰,
      // 换成统一组件后由 enabled 承担同一件事)
      enabled: onTap != null,
      trailing: const Icon(Icons.download_outlined),
    );
  }
}
