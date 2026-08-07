import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// 发现新版本弹窗 → 确认后进入下载进度 → 下载完自动调起安装
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  final action = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前 v${info.currentVersion} → v${info.version}',
            style: Theme.of(ctx).textTheme.titleSmall,
          ),
          if (info.releaseNotes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('更新内容', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              info.releaseNotes.trim(),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('立即更新'),
        ),
      ],
    ),
  );

  if (action == true && context.mounted) {
    await _showDownloadDialog(context, info);
  }
}

/// 下载进度对话框:下载完成自动调起安装,失败可重试
Future<void> _showDownloadDialog(BuildContext context, UpdateInfo info) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DownloadDialog(info: info),
  );
}

class _DownloadDialog extends StatefulWidget {
  final UpdateInfo info;
  const _DownloadDialog({required this.info});

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog>
    with WidgetsBindingObserver {
  double _progress = 0;
  bool _downloading = true;
  String? _error;
  bool _installing = false;
  /// 安装意图发出后 App 是否进入过后台。
  /// 正常情况系统安装器会压到前台 → App 变 paused;
  /// 若始终 resumed,说明安装器根本没弹出(静默拒绝),需引导用户开权限
  bool _sawBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDownload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // PackageInstaller 前台时 App 进入 inactive/paused
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _sawBackground = true;
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
      _sawBackground = false;
    });
    try {
      final path = await UpdateService.downloadApk(
        widget.info.downloadUrl,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installing = true;
      });
      // 调起系统安装器,对话框随即关闭
      await UpdateService.installApk(path);
      if (!mounted) return;
      if (!_sawBackground) {
        // 安装意图发出但 App 从未进入后台 → 安装界面没弹出,
        // 大概率是系统"安装未知应用"权限被禁,给出明确引导
        setState(() {
          _installing = false;
          _error = '未检测到安装界面弹出。\n'
              '请前往 系统设置 → 应用 → AI上外语 → '
              '「安装未知应用」→ 允许,然后点重试。';
        });
        return;
      }
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _installing = false;
          _error = '下载失败:$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_installing ? '正在打开安装器…' : '下载更新 v${widget.info.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_downloading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text('${(_progress * 100).toStringAsFixed(0)}%'),
          ] else if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _startDownload,
              child: const Text('重试'),
            ),
          ],
        ],
      ),
      actions: [
        if (_downloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
      ],
    );
  }
}
