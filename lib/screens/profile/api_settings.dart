import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../config/constants.dart';
import '../../services/doubao_api.dart';

/// 全屏 API 设置页 — 豆包 & DeepSeek 双端点的 Key / URL / 模型名
class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  late final Box _box;

  late final TextEditingController _doubaoKeyCtrl;
  late final TextEditingController _doubaoUrlCtrl;
  late final TextEditingController _doubaoModelCtrl;
  late final TextEditingController _deepseekKeyCtrl;
  late final TextEditingController _deepseekUrlCtrl;
  late final TextEditingController _deepseekModelCtrl;

  /// 模型列表（异步填充）
  List<String> _doubaoModels = DoubaoApiService.fallbackDoubaoModels;
  final List<String> _deepseekModels = ['deepseek-chat', 'deepseek-reasoner'];

  /// 思考模式
  String _doubaoThinking = 'disabled';

  /// 加载中
  bool _doubaoLoading = false;
  bool _deepseekLoading = false;

  @override
  void initState() {
    super.initState();
    _box = Hive.box(AppConstants.hiveBoxSettings);
    _doubaoKeyCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDoubaoApiKey, defaultValue: '') as String? ?? '',
    );
    _doubaoUrlCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDoubaoBaseUrl, defaultValue: '') as String? ?? '',
    );
    _doubaoModelCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDoubaoModel, defaultValue: '') as String? ?? '',
    );
    final saved = _box.get(AppConstants.keyDoubaoThinking) as String?;
    // 迁移旧值：minimal → disabled，其余合法则保留
    if (saved == 'minimal') {
      _doubaoThinking = 'disabled';
    } else if (saved == 'disabled' || saved == 'low' || saved == 'medium' || saved == 'high') {
      _doubaoThinking = saved!;
    } else {
      _doubaoThinking = 'disabled';
    }
    _deepseekKeyCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDeepseekApiKey, defaultValue: '') as String? ?? '',
    );
    _deepseekUrlCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDeepseekBaseUrl, defaultValue: '') as String? ?? '',
    );
    _deepseekModelCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDeepseekModel, defaultValue: '') as String? ?? '',
    );
  }

  @override
  void dispose() {
    _doubaoKeyCtrl.dispose();
    _doubaoUrlCtrl.dispose();
    _doubaoModelCtrl.dispose();
    _deepseekKeyCtrl.dispose();
    _deepseekUrlCtrl.dispose();
    _deepseekModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _box.put(AppConstants.keyDoubaoApiKey, _doubaoKeyCtrl.text.trim());
    await _box.put(AppConstants.keyDoubaoBaseUrl, _doubaoUrlCtrl.text.trim());
    await _box.put(AppConstants.keyDoubaoModel, _doubaoModelCtrl.text.trim());
    await _box.put(AppConstants.keyDoubaoThinking, _doubaoThinking);
    await _box.put(AppConstants.keyDeepseekApiKey, _deepseekKeyCtrl.text.trim());
    await _box.put(AppConstants.keyDeepseekBaseUrl, _deepseekUrlCtrl.text.trim());
    await _box.put(AppConstants.keyDeepseekModel, _deepseekModelCtrl.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('API 设置已保存 · 模型变更后重新拍照生效'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  // ── 模型选择器 ──

  Future<void> _fetchAndShowPicker({required bool isDoubao}) async {
    final keyCtrl = isDoubao ? _doubaoKeyCtrl : _deepseekKeyCtrl;
    final urlCtrl = isDoubao ? _doubaoUrlCtrl : _deepseekUrlCtrl;
    final defaultUrl = isDoubao ? AppConstants.doubaoBaseUrl : AppConstants.deepseekBaseUrl;

    final apiKey = keyCtrl.text.trim();
    final baseUrl = urlCtrl.text.trim().isNotEmpty ? urlCtrl.text.trim() : defaultUrl;

    setState(() {
      if (isDoubao) {
        _doubaoLoading = true;
      } else {
        _deepseekLoading = true;
      }
    });

    // Doubao: 调 API 获取动态列表；DeepSeek: 仅用内置清单
    if (apiKey.isNotEmpty && isDoubao) {
      final models = await DoubaoApiService.fetchModels(baseUrl, apiKey);
      if (mounted) {
        setState(() {
          _doubaoModels = models;
        });
      }
    }

    if (mounted) {
      setState(() {
        if (isDoubao) {
          _doubaoLoading = false;
        } else {
          _deepseekLoading = false;
        }
      });
      _showModelPicker(isDoubao: isDoubao);
    }
  }

  void _showModelPicker({required bool isDoubao}) {
    final modelCtrl = isDoubao ? _doubaoModelCtrl : _deepseekModelCtrl;
    final models = isDoubao ? _doubaoModels : _deepseekModels;
    final currentModel = modelCtrl.text.trim();
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ModelPickerSheet(
        models: models,
        currentModel: currentModel,
        bottomSafe: bottomSafe,
        onSelected: (id) {
          modelCtrl.text = id;
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API 设置'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 豆包（火山方舟） ──
          _SectionHeader(title: '豆包（火山方舟）'),
          const SizedBox(height: 8),
          _ApiField(
            controller: _doubaoKeyCtrl,
            label: 'API Key',
            hint: '火山方舟 → API Key 管理',
          ),
          _ApiField(
            controller: _doubaoUrlCtrl,
            label: 'Base URL',
            hint: '默认：${AppConstants.doubaoBaseUrl}',
          ),
          _ModelRow(
            controller: _doubaoModelCtrl,
            label: '模型名称',
            hint: '默认：${AppConstants.doubaoVisionModel}',
            loading: _doubaoLoading,
            onFetch: () => _fetchAndShowPicker(isDoubao: true),
          ),
          // 思考强度
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '思考模式',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _doubaoThinking,
                  isExpanded: true,
                  isDense: true,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  items: AppConstants.thinkingOptions.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _doubaoThinking = v);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── DeepSeek ──
          _SectionHeader(title: 'DeepSeek'),
          const SizedBox(height: 8),
          _ApiField(
            controller: _deepseekKeyCtrl,
            label: 'API Key',
            hint: 'platform.deepseek.com → API keys',
          ),
          _ApiField(
            controller: _deepseekUrlCtrl,
            label: 'Base URL',
            hint: '默认：${AppConstants.deepseekBaseUrl}',
          ),
          _ModelRow(
            controller: _deepseekModelCtrl,
            label: '模型名称',
            hint: '默认：${AppConstants.deepseekChatModel}',
            loading: _deepseekLoading,
            onFetch: () => _fetchAndShowPicker(isDoubao: false),
          ),
          const SizedBox(height: 16),

          // ── 提示 ──
          Text(
            '留空的字段将使用默认值。模型列表可直接选择，也可手动输入其他模型。'
            'Key 保存在手机本地，不上传任何服务器。',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

// ═══════════════ 组件 ═══════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
    );
  }
}

class _ApiField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;

  const _ApiField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}

/// 模型行：输入框 + 选择按钮
class _ModelRow extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool loading;
  final VoidCallback onFetch;

  const _ModelRow({
    required this.controller,
    required this.label,
    required this.hint,
    required this.loading,
    required this.onFetch,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: loading ? null : onFetch,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('选择', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

/// BottomSheet — 模型列表 + 搜索
class _ModelPickerSheet extends StatefulWidget {
  final List<String> models;
  final String currentModel;
  final double bottomSafe;
  final ValueChanged<String> onSelected;

  const _ModelPickerSheet({
    required this.models,
    required this.currentModel,
    required this.bottomSafe,
    required this.onSelected,
  });

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  String _filter = '';

  List<String> get _filtered {
    if (_filter.isEmpty) return widget.models;
    final q = _filter.toLowerCase();
    return widget.models.where((m) => m.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.25,
      maxChildSize: 0.75,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Padding(
          padding: EdgeInsets.only(bottom: widget.bottomSafe),
          child: Column(
        children: [
          // 拖拽条
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 搜索栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索模型…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _filter = ''),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          // 底部提示
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '未找到需要的模型？手动输入到上方文本框即可',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ),
          // 列表
          Expanded(
            child: ListView.separated(
              controller: scrollCtrl,
              itemCount: _filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final model = _filtered[i];
                final isSelected = model == widget.currentModel;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20,
                    color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                  title: Text(
                    model,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? Theme.of(context).colorScheme.primary : null,
                    ),
                  ),
                  onTap: () => widget.onSelected(model),
                );
              },
            ),
          ),
        ],
      ),
    );
  },
  );
  }
}
