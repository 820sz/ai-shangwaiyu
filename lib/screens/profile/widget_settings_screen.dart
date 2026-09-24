import 'package:flutter/material.dart';

import '../../services/widget_payload.dart';
import '../../services/widget_service.dart';

/// 桌面小组件设置页(v2.2)。
///
/// 为什么要有这一页 —— 小组件的一切问题都发生在"App 之外",用户没法在 App 里
/// 排查:不知道有没有添加上、不知道桌面上的数字是什么时候的。所以这页给三件事:
/// 1. **状态**:系统里已添加几个(问启动器要);
/// 2. **一键添加**:支持的话直接请求钉到桌面,不支持就给长按桌面的图文步骤;
/// 3. **手动同步 + 预览**:点一下立刻按当前数据推送,并把"桌面上会显示什么"
///    原样贴出来 —— 不用切回桌面就能核对数字对不对。
class WidgetSettingsScreen extends StatefulWidget {
  const WidgetSettingsScreen({super.key});

  @override
  State<WidgetSettingsScreen> createState() => _WidgetSettingsScreenState();
}

class _WidgetSettingsScreenState extends State<WidgetSettingsScreen> {
  int _installed = 0;
  bool _loading = true;
  bool _busy = false;
  String? _message;
  WidgetPayload? _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final count = await WidgetService.installedCount();
    if (!mounted) return;
    setState(() {
      _installed = count;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    final ok = await WidgetService.sync();
    final payload = await WidgetService.buildPayload();
    final count = await WidgetService.installedCount();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _installed = count;
      _preview = payload;
      _message = ok
          ? null
          : (count == 0
              // 桌面上还没有这个小组件时,推送本来就没对象 —— 这不是失败,
              // 要引导用户先添加,而不是吓唬他说"设备不支持"
              ? '你还没把小组件放到桌面 —— 先点上面的「一键添加到桌面」'
              : '数据已保存,但通知桌面刷新失败 —— 桌面上的数字可能还是旧的');
    });
  }

  Future<void> _pin() async {
    setState(() => _busy = true);
    final ok = await WidgetService.requestPin();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      setState(() => _message = '已把小组件交给系统 —— 在弹窗里确认「添加」即可');
      await _load();
    } else {
      setState(() => _message = '这个启动器不支持一键添加,请按下面的步骤手动加');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('桌面小组件')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('状态',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    _loading
                        ? '正在查询…'
                        : (_installed > 0
                            ? '你已经在桌面上放了 $_installed 个小组件'
                            : '桌面上还没有小组件'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _pin,
                        icon: const Icon(Icons.add_to_home_screen, size: 18),
                        label: const Text('一键添加到桌面'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _sync,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('同步并预览'),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    Text(_message!,
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                ],
              ),
            ),
          ),

          if (_preview != null) ...[
            const SizedBox(height: 8),
            _WidgetPreviewCard(payload: _preview!),
          ],

          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('手动添加(所有启动器都行)',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    '1. 长按桌面空白处;\n'
                    '2. 选「小组件 / 挂件」;\n'
                    '3. 在列表里找「AI上外语 · 今天」,拖到桌面上。',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('它显示什么 / 不显示什么',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    '· 显示:今天第一件该做的事、待复习词数、今天的新词额度、连续学习天数;'
                    '点整块打开 App。\n'
                    '· 数据是**打开 App 时推送**的(桌面挂件读不到 App 的数据库),'
                    '所以超过一天没打开 App,小组件会自己改说「打开 App 刷新今日任务」,'
                    '不会拿旧数字冒充今天。\n'
                    '· 不显示:生词内容、AI 回复 —— 桌面是公开场合,学习内容不该默认摊在外面。',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 预览卡:把小组件在桌面上的样子(文字部分)按同一配色画出来
class _WidgetPreviewCard extends StatelessWidget {
  final WidgetPayload payload;

  const _WidgetPreviewCard({required this.payload});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = payload.previewLines();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('桌面上的样子(文字预览)',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('AI上外语 · 今天',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF8FC0F0))),
                      ),
                      if (payload.badge.isNotEmpty)
                        Text(payload.badge,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF8FC0F0))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(lines.isNotEmpty ? lines[0] : '',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  if (lines.length > 1)
                    Text(lines[1],
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFC9D1E0))),
                  const SizedBox(height: 2),
                  if (lines.length > 2)
                    Text(lines[2],
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF8B93A5))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
