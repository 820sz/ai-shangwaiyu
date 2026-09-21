import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../config/constants.dart';
import '../../services/api_endpoint.dart';
import '../../services/doubao_api.dart';

/// 全屏 API 设置页 — 主/副双槽位:
/// 主 = 多模态(识图/全文翻译/素材推荐/追问默认)
/// 副 = 专项文本(文章生成/回译/建议),未配置则全部走主
class ApiSettingsScreen extends StatefulWidget {
  const ApiSettingsScreen({super.key});

  @override
  State<ApiSettingsScreen> createState() => _ApiSettingsScreenState();
}

class _ApiSettingsScreenState extends State<ApiSettingsScreen> {
  late final Box _box;

  // ── 主槽位(多模态) ──
  late final TextEditingController _primaryKeyCtrl;
  late final TextEditingController _primaryUrlCtrl;
  late final TextEditingController _primaryModelCtrl;
  String _primaryThinking = 'disabled';

  // ── 副槽位(专项文本) ──
  late final TextEditingController _secondaryKeyCtrl;
  late final TextEditingController _secondaryUrlCtrl;
  late final TextEditingController _secondaryModelCtrl;
  String _secondaryThinking = 'disabled';

  /// 模型列表(异步填充)。
  /// 主槽位 = 主槽位兜底清单(豆包系 + DeepSeek 视觉模型,2026-08-21);
  /// 副槽位 = DeepSeek 文本清单。
  List<String> _primaryModels = AppConstants.primaryFallbackModels;
  List<String> _secondaryModels = AppConstants.deepseekFallbackModels;

  /// 加载中
  bool _primaryLoading = false;
  bool _secondaryLoading = false;

  @override
  void initState() {
    super.initState();
    _box = Hive.box(AppConstants.hiveBoxSettings);
    _primaryKeyCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDoubaoApiKey, defaultValue: '') as String? ?? '',
    );
    _primaryUrlCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDoubaoBaseUrl, defaultValue: '') as String? ?? '',
    );
    _primaryModelCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDoubaoModel, defaultValue: '') as String? ?? '',
    );
    _primaryThinking =
        _migrateThinking(AppConstants.keyDoubaoThinking, _primaryModelCtrl.text);

    _secondaryKeyCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDeepseekApiKey, defaultValue: '') as String? ?? '',
    );
    _secondaryUrlCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDeepseekBaseUrl, defaultValue: '') as String? ?? '',
    );
    _secondaryModelCtrl = TextEditingController(
      text: _box.get(AppConstants.keyDeepseekModel, defaultValue: '') as String? ?? '',
    );
    _secondaryThinking =
        _migrateThinking(AppConstants.keyDeepseekThinking, _secondaryModelCtrl.text);
  }

  /// 读思考模式并迁移旧值(v1.7.0 改为按模型族档位表判定):
  /// - 档位表里有的值一律保留(DS 现在正确保留 high/max)
  /// - minimal → disabled(并入不思考);豆包的 medium 等表外值 → low
  String _migrateThinking(String hiveKey, String model) {
    final saved = _box.get(hiveKey) as String?;
    final allowed = AppConstants.thinkingOptionsFor(model).keys.toSet();
    if (saved != null && allowed.contains(saved)) return saved;
    if (saved == 'minimal') return 'disabled';
    if (saved == 'medium' || saved == 'high') return 'low';
    return 'disabled';
  }

  @override
  void dispose() {
    _primaryKeyCtrl.dispose();
    _primaryUrlCtrl.dispose();
    _primaryModelCtrl.dispose();
    _secondaryKeyCtrl.dispose();
    _secondaryUrlCtrl.dispose();
    _secondaryModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // URL 清洗+校验(v1.3.2):粘贴带全角冒号/空格/换行 → 清洗;
    // 清洗后非空但不以 http(s):// 开头 → 警告并重置为默认,绝不存坏值
    final primaryKey = _primaryKeyCtrl.text.replaceAll(RegExp(r'\s+'), '');
    final secondaryKey = _secondaryKeyCtrl.text.replaceAll(RegExp(r'\s+'), '');
    // 未填 URL 按 Key 前缀补默认端点(v1.4.0):sk- → DeepSeek 官方,零配置错配
    final primaryUrlRaw = ApiEndpointConfig.cleanBaseUrl(_primaryUrlCtrl.text);
    final primaryUrlValid = ApiEndpointConfig.normalizedBaseUrl(primaryUrlRaw);
    final primaryUrlSaved = primaryUrlValid ??
        (primaryKey.toLowerCase().startsWith('sk-')
            ? AppConstants.deepseekBaseUrl
            : '');
    final secondaryUrlRaw = ApiEndpointConfig.cleanBaseUrl(_secondaryUrlCtrl.text);
    final secondaryUrlValid = ApiEndpointConfig.normalizedBaseUrl(secondaryUrlRaw);
    final secondaryUrlSaved = secondaryUrlValid ??
        (secondaryKey.toLowerCase().startsWith('sk-')
            ? AppConstants.deepseekBaseUrl
            : '');
    final badUrl =
        (primaryUrlRaw.isNotEmpty && primaryUrlValid == null) ||
        (secondaryUrlRaw.isNotEmpty && secondaryUrlValid == null);
    final autoUrl =
        (primaryUrlRaw.isEmpty && (primaryKey.toLowerCase().startsWith('sk-'))) ||
        (secondaryUrlRaw.isEmpty && (secondaryKey.toLowerCase().startsWith('sk-')));

    // 主槽位(复用原豆包 key,老配置无需迁移)
    await _box.put(AppConstants.keyDoubaoApiKey, primaryKey);
    await _box.put(AppConstants.keyDoubaoBaseUrl, primaryUrlSaved);
    await _box.put(AppConstants.keyDoubaoModel, _primaryModelCtrl.text.trim());
    await _box.put(AppConstants.keyDoubaoThinking, _primaryThinking);
    // 副槽位(复用原 DeepSeek key)
    await _box.put(AppConstants.keyDeepseekApiKey, secondaryKey);
    await _box.put(AppConstants.keyDeepseekBaseUrl, secondaryUrlSaved);
    await _box.put(AppConstants.keyDeepseekModel, _secondaryModelCtrl.text.trim());
    await _box.put(AppConstants.keyDeepseekThinking, _secondaryThinking);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            badUrl
                ? 'Base URL 格式不正确(需 http/https 开头),已重置为默认端点;请检查后重新填写'
                : autoUrl
                    ? 'API 设置已保存 · 检测到 DeepSeek Key,已自动使用 https://api.deepseek.com'
                    : 'API 设置已保存 · 模型变更后重新拍照生效',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  // ── 模型选择器 ──

  Future<void> _fetchAndShowPicker({required bool isPrimary}) async {
    final keyCtrl = isPrimary ? _primaryKeyCtrl : _secondaryKeyCtrl;
    final urlCtrl = isPrimary ? _primaryUrlCtrl : _secondaryUrlCtrl;
    final defaultUrl = isPrimary
        ? ApiEndpointConfig.primary.defaultBaseUrl
        : ApiEndpointConfig.secondary.defaultBaseUrl;

    final apiKey = keyCtrl.text.trim();
    final urlRaw = ApiEndpointConfig.cleanBaseUrl(urlCtrl.text);
    // 未填 URL 时按 Key 前缀自动配端点:sk- → DeepSeek 官方(否则拉方舟 /models
    // 会失败回退豆包清单,用户看不到自己的 DS 模型——v1.3.1 实测痛点)
    final baseUrl = urlRaw.isNotEmpty
        ? (ApiEndpointConfig.normalizedBaseUrl(urlRaw) ?? defaultUrl)
        : (apiKey.toLowerCase().startsWith('sk-')
            ? AppConstants.deepseekBaseUrl
            : defaultUrl);

    setState(() {
      if (isPrimary) {
        _primaryLoading = true;
      } else {
        _secondaryLoading = true;
      }
    });

    // 两槽位拉取 /models 后按能力/模型族过滤:
    // 主=只留视觉候选(isVisionCandidate:vision/doubao-seed 系),砍掉未开通的
    //   老文本/角色/纯文本 DS 模型(v1.3.0-2 用户实测"一堆乱模型"问题);
    // 副=DeepSeek 系列 —— 方舟聚合端点会混入他族模型,过滤避免误导
    if (apiKey.isNotEmpty) {
      final models = await DoubaoApiService.fetchModels(
        baseUrl,
        apiKey,
        allowPrefixes: isPrimary ? const [] : const ['deepseek'],
        keepFilter: isPrimary ? isVisionCandidate : null,
        fallback: isPrimary
            ? AppConstants.primaryFallbackModels
            : AppConstants.deepseekFallbackModels,
      );
      if (mounted) {
        setState(() {
          if (isPrimary) {
            _primaryModels = models;
          } else {
            _secondaryModels = models;
          }
        });
      }
    }

    if (mounted) {
      setState(() {
        if (isPrimary) {
          _primaryLoading = false;
        } else {
          _secondaryLoading = false;
        }
      });
      _showModelPicker(isPrimary: isPrimary);
    }
  }

  void _showModelPicker({required bool isPrimary}) {
    final modelCtrl = isPrimary ? _primaryModelCtrl : _secondaryModelCtrl;
    final urlCtrl = isPrimary ? _primaryUrlCtrl : _secondaryUrlCtrl;
    final models = isPrimary ? _primaryModels : _secondaryModels;
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
          // 防呆:选中 DeepSeek 模型但端点还是方舟(默认/volces)时提示配对
          // (v1.3.0-2 用户实测:ark key + DS 模型名 → 识别失败"API Key 无效")
          final url = urlCtrl.text.trim();
          final isArkUrl =
              url.isEmpty || url.contains('volces.com') || url.contains('ark.cn-');
          if (id.toLowerCase().contains('deepseek') && isArkUrl) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(
                content: Text(
                  'DeepSeek 模型需搭配：Base URL https://api.deepseek.com '
                  '+ DeepSeek 官方 Key（sk- 开头）。否则会提示 API 无效。',
                ),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 6),
              ),
            );
          }
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
          // ── 主 API(多模态) ──
          _SectionHeader(title: '主 API(多模态)'),
          const SizedBox(height: 4),
          Text(
            '拍照识文 / 全文翻译 / 素材推荐 / 追问默认。需支持图片识别的模型。\n'
            '模型列表按视觉能力过滤。Key 填 sk- 开头(DeepSeek 官方)时,'
            'Base URL 留空自动使用 https://api.deepseek.com;ark- 开头(火山方舟)'
            '自动使用方舟端点。DeepSeek 视觉模型为 deepseek-v4-flash-vision-exp。',
            // P2-31:正文灰阶对比度 <4.5:1,提到 grey[600] 达 WCAG AA
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          _ApiField(
            controller: _primaryKeyCtrl,
            label: 'API Key',
            hint: 'sk- 开头 = DeepSeek 官方 · ark- 开头 = 火山方舟',
          ),
          _ApiField(
            controller: _primaryUrlCtrl,
            label: 'Base URL',
            hint: '留空按 Key 类型自动使用',
          ),
          _ModelRow(
            controller: _primaryModelCtrl,
            label: '模型名称',
            hint: '默认：${ApiEndpointConfig.primary.defaultModel}',
            loading: _primaryLoading,
            onFetch: () => _fetchAndShowPicker(isPrimary: true),
          ),
          _ThinkingDropdown(
            value: _primaryThinking,
            options: AppConstants.thinkingOptionsFor(_primaryModelCtrl.text),
            onChanged: (v) => setState(() => _primaryThinking = v),
          ),
          const SizedBox(height: 24),

          // ── 副 API(专项文本) ──
          _SectionHeader(title: '副 API(专项文本 · 可选)'),
          const SizedBox(height: 4),
          Text(
            '文章生成 / 回译练习 / 个性化建议。未配置时自动使用主 API。',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          _ApiField(
            controller: _secondaryKeyCtrl,
            label: 'API Key',
            hint: 'sk- 开头 = DeepSeek 官方',
          ),
          _ApiField(
            controller: _secondaryUrlCtrl,
            label: 'Base URL',
            hint: '留空用默认',
          ),
          _ModelRow(
            controller: _secondaryModelCtrl,
            label: '模型名称',
            hint: '默认：${ApiEndpointConfig.secondary.defaultModel}',
            loading: _secondaryLoading,
            onFetch: () => _fetchAndShowPicker(isPrimary: false),
          ),
          _ThinkingDropdown(
            value: _secondaryThinking,
            options: AppConstants.thinkingOptionsFor(_secondaryModelCtrl.text),
            onChanged: (v) => setState(() => _secondaryThinking = v),
          ),
          const SizedBox(height: 16),

          // ── 提示 ──
          Text(
            '可填任意 OpenAI 兼容端点。模型列表可直接选择，也可手动输入。'
            'Key 保存在手机本地，不上传任何服务器。',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
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

/// 思考模式下拉(两槽位共用,v1.4.3 按模型族展示档位:
/// DS 系 4 档(不思考/低/中/高),豆包系 2 档)
class _ThinkingDropdown extends StatelessWidget {
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const _ThinkingDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 当前值必须存在于档位表(模型族切换后旧值可能非法,如 DS→豆包时的高档)
    final validValue = options.containsKey(value) ? value : options.keys.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: '思考模式',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: validValue,
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            items: options.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
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
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
