import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../services/api_endpoint.dart';
import '../../services/doubao_api.dart';
import '../../services/material_art.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/v4/v4_kit.dart';
import '../../widgets/waiting.dart';

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

  /// 测试连通中(按钮文案切换;这里刻意不用裸转圈 —— 40 高按钮里塞不下,
  /// 用户也只需要知道"在测"而不是看动画)
  bool _primaryTesting = false;
  bool _secondaryTesting = false;

  /// 材料自动配图策略(设置项;默认只抓取、不花钱)
  CoverArtMode _artMode = CoverArtMode.crawl;

  @override
  void initState() {
    super.initState();
    _box = Hive.box(AppConstants.hiveBoxSettings);
    _artMode = MaterialArt.mode;
    _primaryKeyCtrl = TextEditingController(
      text:
          _box.get(AppConstants.keyDoubaoApiKey, defaultValue: '') as String? ??
          '',
    );
    _primaryUrlCtrl = TextEditingController(
      text:
          _box.get(AppConstants.keyDoubaoBaseUrl, defaultValue: '')
              as String? ??
          '',
    );
    _primaryModelCtrl = TextEditingController(
      text:
          _box.get(AppConstants.keyDoubaoModel, defaultValue: '') as String? ??
          '',
    );
    _primaryThinking = _migrateThinking(
      AppConstants.keyDoubaoThinking,
      _primaryModelCtrl.text,
    );

    _secondaryKeyCtrl = TextEditingController(
      text:
          _box.get(AppConstants.keyDeepseekApiKey, defaultValue: '')
              as String? ??
          '',
    );
    _secondaryUrlCtrl = TextEditingController(
      text:
          _box.get(AppConstants.keyDeepseekBaseUrl, defaultValue: '')
              as String? ??
          '',
    );
    _secondaryModelCtrl = TextEditingController(
      text:
          _box.get(AppConstants.keyDeepseekModel, defaultValue: '')
              as String? ??
          '',
    );
    _secondaryThinking = _migrateThinking(
      AppConstants.keyDeepseekThinking,
      _secondaryModelCtrl.text,
    );
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
    final primaryUrlSaved =
        primaryUrlValid ??
        (primaryKey.toLowerCase().startsWith('sk-')
            ? AppConstants.deepseekBaseUrl
            : '');
    final secondaryUrlRaw = ApiEndpointConfig.cleanBaseUrl(
      _secondaryUrlCtrl.text,
    );
    final secondaryUrlValid = ApiEndpointConfig.normalizedBaseUrl(
      secondaryUrlRaw,
    );
    final secondaryUrlSaved =
        secondaryUrlValid ??
        (secondaryKey.toLowerCase().startsWith('sk-')
            ? AppConstants.deepseekBaseUrl
            : '');
    final badUrl =
        (primaryUrlRaw.isNotEmpty && primaryUrlValid == null) ||
        (secondaryUrlRaw.isNotEmpty && secondaryUrlValid == null);
    final autoUrl =
        (primaryUrlRaw.isEmpty &&
            (primaryKey.toLowerCase().startsWith('sk-'))) ||
        (secondaryUrlRaw.isEmpty &&
            (secondaryKey.toLowerCase().startsWith('sk-')));

    // 主槽位(复用原豆包 key,老配置无需迁移)
    await _box.put(AppConstants.keyDoubaoApiKey, primaryKey);
    await _box.put(AppConstants.keyDoubaoBaseUrl, primaryUrlSaved);
    await _box.put(AppConstants.keyDoubaoModel, _primaryModelCtrl.text.trim());
    await _box.put(AppConstants.keyDoubaoThinking, _primaryThinking);
    // 副槽位(复用原 DeepSeek key)
    await _box.put(AppConstants.keyDeepseekApiKey, secondaryKey);
    await _box.put(AppConstants.keyDeepseekBaseUrl, secondaryUrlSaved);
    await _box.put(
      AppConstants.keyDeepseekModel,
      _secondaryModelCtrl.text.trim(),
    );
    await _box.put(AppConstants.keyDeepseekThinking, _secondaryThinking);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            badUrl
                ? 'Base URL 格式不正确(需 http/https 开头),已重置为默认端点;请检查后重新填写'
                : autoUrl
                ? 'API 设置已保存 · 检测到 DeepSeek Key,已自动使用 https://api.deepseek.com'
                : primaryKey.isEmpty
                ? 'API 设置已保存 · 注意:主 API 未配置,拍照识文/翻译/批改不可用'
                : 'API 设置已保存 · 模型变更后重新拍照生效',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  /// 槽位中文名(测试结果/不可用提示共用一份口径)
  String _slotLabel(bool isPrimary) => isPrimary ? '主 API' : '副 API';

  /// **测试连通**:拿当前 Key/Base URL 调一次 `GET /models`,
  /// 把"Key 与端点是否配对"当场验证掉 —— 用户最常踩的坑就是
  /// "DeepSeek Key 配了方舟端点/方舟 Key 配了 DeepSeek 模型",保存完才发现不可用。
  ///
  /// 没 Key 时**不发请求**:直接告诉用户缺什么(请求也没用,还浪费一次往返)。
  Future<void> _testConnection({required bool isPrimary}) async {
    final keyCtrl = isPrimary ? _primaryKeyCtrl : _secondaryKeyCtrl;
    final urlCtrl = isPrimary ? _primaryUrlCtrl : _secondaryUrlCtrl;
    final defaultUrl = isPrimary
        ? ApiEndpointConfig.primary.defaultBaseUrl
        : ApiEndpointConfig.secondary.defaultBaseUrl;
    final apiKey = keyCtrl.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '先填 ${_slotLabel(isPrimary)} 的 API Key 再测试 —— '
              '没有 Key 时这个槽位的功能都不可用',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    final urlRaw = ApiEndpointConfig.cleanBaseUrl(urlCtrl.text);
    final baseUrl = urlRaw.isNotEmpty
        ? (ApiEndpointConfig.normalizedBaseUrl(urlRaw) ?? defaultUrl)
        : (apiKey.toLowerCase().startsWith('sk-')
              ? AppConstants.deepseekBaseUrl
              : defaultUrl);
    setState(() {
      if (isPrimary) {
        _primaryTesting = true;
      } else {
        _secondaryTesting = true;
      }
    });
    final startedAt = DateTime.now();
    var models = const <String>[];
    try {
      models = await DoubaoApiService.fetchModels(
        baseUrl,
        apiKey,
        // 过滤口径与"选择模型"一致,避免把别族模型当成可用证据
        allowPrefixes: isPrimary ? const [] : const ['deepseek'],
        keepFilter: isPrimary ? isVisionCandidate : null,
        fallback: const <String>[],
      );
    } catch (e) {
      debugPrint('ReadFlow API 测试连通失败: $e');
    }
    if (!mounted) return;
    setState(() {
      if (isPrimary) {
        _primaryTesting = false;
      } else {
        _secondaryTesting = false;
      }
    });
    final costMs = DateTime.now().difference(startedAt).inMilliseconds;
    final ok = models.isNotEmpty;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '${_slotLabel(isPrimary)} 连通正常 · 拉到 ${models.length} 个模型 · ${costMs}ms'
                : '${_slotLabel(isPrimary)} 连不上 /models —— ${DoubaoApiService.lastFetchNote}。'
                      '请检查 Key 与 Base URL 是否配对:DeepSeek Key 用 api.deepseek.com,'
                      '方舟 Key 用方舟端点。',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: ok ? 4 : 6),
        ),
      );
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
              url.isEmpty ||
              url.contains('volces.com') ||
              url.contains('ark.cn-');
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

  // ── 能力可用性卡片(动态) ──

  /// "没有 Key 时哪些功能不可用"必须**逐项说清**,而不是一句"未配置"。
  ///
  /// 用户 2026-11-01 的诉求:别只说"未配置" —— 他要知道后果。
  /// 这张卡按输入框里的 Key 实时判定(外层用 AnimatedBuilder 监听两个 Key 输入框),
  /// 让用户"边填边看到"哪些能力被点亮;也解释了为什么有些功能只要文本 Key、
  /// 有些必须主 API、真题抓取还必须是 DeepSeek 官方 Key。
  Widget _capabilitiesCard(ThemeData theme) {
    final muted = theme.colorScheme.onSurfaceVariant;
    final primaryKey = _primaryKeyCtrl.text.trim();
    final secondaryKey = _secondaryKeyCtrl.text.trim();
    final hasPrimary = primaryKey.isNotEmpty;
    final hasSecondary = secondaryKey.isNotEmpty;
    final hasText = hasPrimary || hasSecondary;
    // 真题抓取走 DeepSeek 官方 Search/Fetch:只认 sk- 官方 Key(方舟 Key 不行)
    final hasDeepseekOfficial =
        primaryKey.toLowerCase().startsWith('sk-') ||
        secondaryKey.toLowerCase().startsWith('sk-');
    const okTag = AppTag('可用', tone: AppTagTone.success, icon: Icons.check);
    const needTextTag = AppTag('需要任一 Key', tone: AppTagTone.warning);
    const needPrimaryTag = AppTag('需要主 API', tone: AppTagTone.warning);
    const needOfficialTag = AppTag('需要 sk- 官方 Key', tone: AppTagTone.warning);

    final headline = (!hasPrimary && !hasSecondary)
        ? '还没配置 API Key:下列 AI 功能全部不可用(离线功能不受影响)。'
        : !hasPrimary
        ? '主 API 未配置:拍照识文 / 手写批改不可用,其余文本功能自动走副 API。'
        : !hasSecondary
        ? '副 API 未配置:文本功能自动使用主 API(可用)。'
        : '主 / 副 API 均已配置。';

    return AppCard(
      variant: AppCardVariant.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.key_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text(
                  '需要 Key 的 AI 功能',
                  style: AppFont.subheadStyle.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xxs),
          Text(
            headline,
            style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
          ),
          const SizedBox(height: Gap.sm),
          _capabilityRow(
            icon: Icons.photo_camera_outlined,
            title: '拍照识文 / 手写转写',
            note: '主 API(视觉模型)',
            tag: hasPrimary ? okTag : needPrimaryTag,
          ),
          _capabilityRow(
            icon: Icons.translate,
            title: '翻译(全文 / 逐段)',
            note: '主 / 副任一(副未配置时走主)',
            tag: hasText ? okTag : needTextTag,
          ),
          _capabilityRow(
            icon: Icons.travel_explore,
            title: 'AI 找材料 / 标题中文化',
            note: '主 / 副任一',
            tag: hasText ? okTag : needTextTag,
          ),
          _capabilityRow(
            icon: Icons.edit_note,
            title: 'AI 出题 / 评分',
            note: '主 / 副任一',
            tag: hasText ? okTag : needTextTag,
          ),
          _capabilityRow(
            icon: Icons.spellcheck,
            title: '写译批改',
            note: '文本用主/副;手写照片需要主 API',
            tag: hasText ? okTag : needTextTag,
          ),
          _capabilityRow(
            icon: Icons.manage_search,
            title: '真题抓取(DeepSeek 搜索)',
            note: 'DeepSeek 官方 Key(sk- 开头)',
            tag: hasDeepseekOfficial ? okTag : needOfficialTag,
          ),
          const SizedBox(height: Gap.xs),
          Text(
            '没配 Key 也能用:阅读已导入材料、复习生词、本地判分的练习。',
            style: AppFont.tagStyle.copyWith(color: muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// 能力行:图标 + 名称/条件 + 右侧状态标签(整页统一形态)
  Widget _capabilityRow({
    required IconData icon,
    required String title,
    required String note,
    required AppTag tag,
  }) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: muted),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppFont.metaStyle.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  note,
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.xs),
          tag,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final primaryReady = _primaryKeyCtrl.text.trim().isNotEmpty;
    final secondaryReady = _secondaryKeyCtrl.text.trim().isNotEmpty;

    return Scaffold(
      appBar: V4JellyAppBar(
        title: 'API 设置',
        actions: <Widget>[
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: Insets.page,
        children: [
          // ── 00 需要 Key 的 AI 功能(边填 Key 边点亮)──
          AnimatedBuilder(
            animation: Listenable.merge([_primaryKeyCtrl, _secondaryKeyCtrl]),
            builder: (context, _) => _capabilitiesCard(theme),
          ),

          // ── 01 主 API(多模态) ──
          AppSectionHeader(
            indexLabel: '01',
            title: '主 API(多模态)',
            trailing: AppTag(
              primaryReady ? '已配置' : '未配置',
              tone: primaryReady ? AppTagTone.success : AppTagTone.warning,
            ),
          ),
          Text(
            '拍照识文 / 手写转写 / 全文翻译 / 素材推荐 / 追问。需要支持图片识别的模型。',
            style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
          ),
          const SizedBox(height: Gap.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  hint: '默认:${ApiEndpointConfig.primary.defaultModel}',
                  loading: _primaryLoading,
                  onFetch: () => _fetchAndShowPicker(isPrimary: true),
                ),
                _ThinkingDropdown(
                  value: _primaryThinking,
                  options: AppConstants.thinkingOptionsFor(
                    _primaryModelCtrl.text,
                  ),
                  onChanged: (v) => setState(() => _primaryThinking = v),
                ),
                // 测试连通:保存前先验一次 Key/端点是否配对,别等用的时候才发现
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _primaryTesting
                        ? null
                        : () => _testConnection(isPrimary: true),
                    icon: Icon(
                      _primaryTesting
                          ? Icons.hourglass_top_outlined
                          : Icons.wifi_tethering,
                      size: 16,
                    ),
                    label: Text(_primaryTesting ? '测试中…' : '测试连通'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // ── 02 副 API(专项文本 · 可选) ──
          AppSectionHeader(
            indexLabel: '02',
            title: '副 API(专项文本 · 可选)',
            trailing: AppTag(
              secondaryReady ? '已配置' : '未配置',
              tone: secondaryReady ? AppTagTone.success : AppTagTone.warning,
            ),
          ),
          Text(
            'AI 找材料 / 逐段翻译 / 出题 / 评分 / 文章生成。未配置时自动使用主 API。',
            style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
          ),
          const SizedBox(height: Gap.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  hint: '默认:${ApiEndpointConfig.secondary.defaultModel}',
                  loading: _secondaryLoading,
                  onFetch: () => _fetchAndShowPicker(isPrimary: false),
                ),
                _ThinkingDropdown(
                  value: _secondaryThinking,
                  options: AppConstants.thinkingOptionsFor(
                    _secondaryModelCtrl.text,
                  ),
                  onChanged: (v) => setState(() => _secondaryThinking = v),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _secondaryTesting
                        ? null
                        : () => _testConnection(isPrimary: false),
                    icon: Icon(
                      _secondaryTesting
                          ? Icons.hourglass_top_outlined
                          : Icons.wifi_tethering,
                      size: 16,
                    ),
                    label: Text(_secondaryTesting ? '测试中…' : '测试连通'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // ── 03 Key 与隐私 ──
          const AppSectionHeader(indexLabel: '03', title: 'Key 与隐私'),
          AppCard(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '· Key 只保存在本机,不上传任何服务器;导出的备份文件里也不含 Key。',
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
                ),
                const SizedBox(height: Gap.xxs),
                Text(
                  '· 可填任意 OpenAI 兼容端点;DeepSeek 官方 Key(sk-)可留空 Base URL 自动配对。',
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
                ),
                const SizedBox(height: Gap.xxs),
                Text(
                  '· 方舟 Key(ark-)必须配方舟端点;混用会提示"API Key 无效"。',
                  style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),

          // ── 04 材料自动配图 ──
          //
          // 用户 2026-11-03:"材料那些封面尽量能让 AI 抓取并配上材料自身的插图
          // 或者封面,不然整个软件太素了"。默认只抓取(**免费**):书从豆瓣拿书封、
          // 其他材料从 360 图片拿相关插图,抓到落盘缓存;AI 生图按张计费,默认关。
          AppSectionHeader(
            indexLabel: '04',
            title: '材料自动配图',
            trailing: AppTag(
              _artMode == CoverArtMode.off ? '已关闭' : '已开启',
              tone: _artMode == CoverArtMode.off
                  ? AppTagTone.neutral
                  : AppTagTone.success,
            ),
          ),
          Text(
            '给没有配图的材料自动找一张自己的图:书优先取书封,其它取相关插图,'
            '抓到后缓存在本机(不重复联网)。',
            style: AppFont.tagStyle.copyWith(color: muted, height: 1.5),
          ),
          const SizedBox(height: Gap.sm),
          AppCard(
            child: Column(
              children: <Widget>[
                _artModeTile(
                  CoverArtMode.crawl,
                  '抓取书封 / 插图(免费)',
                  '书用豆瓣封面,其他用图片搜索;抓不到就用程序化封面',
                ),
                _artModeTile(
                  CoverArtMode.crawlThenAi,
                  '抓不到时让 AI 生成插图',
                  MaterialArt.aiAvailable
                      ? '走方舟 Seedream,按张计费(约几毛/张);生成一次后永久缓存'
                      : '当前端点不是火山方舟,生图不可用(需要 ark- Key + 方舟端点)',
                ),
                _artModeTile(
                  CoverArtMode.off,
                  '关闭自动配图',
                  '只用材料源自带的图;没有就用程序化封面',
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }

  Future<void> _setArtMode(CoverArtMode? mode) async {
    if (mode == null) return;
    setState(() => _artMode = mode);
    await MaterialArt.setMode(mode);
  }

  /// 配图策略的单选项(不用 RadioListTile:Flutter 3.44 起它的
  /// groupValue/onChanged 已废弃,换成"图标 + ListTile"零迁移成本)
  Widget _artModeTile(CoverArtMode mode, String title, String subtitle) {
    final selected = _artMode == mode;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => _setArtMode(mode),
    );
  }
}

// ═══════════════ 组件 ═══════════════

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
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          // 字阶/字体族从主题派生:不要写裸 TextStyle —— 它会盖掉主题字体族
          hintStyle: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
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
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
            ),
          ),
          const SizedBox(width: Gap.xs),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: loading ? null : onFetch,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              // v2.10:按钮内联 loading 不再转圈。这个按钮只有 40 高、还和左侧
              // 输入框挤在同一个 Row 里,骨架屏/时间线都放不下;三点跳动(空标签
              // 只占约 21×4)最接近原来 16×16 的占位,不会把输入框挤窄。
              child: loading
                  ? const ThinkingDots(label: '', compact: true)
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
      padding: const EdgeInsets.only(bottom: Gap.sm),
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
            // 思考模式下拉:文字样式从主题派生(裸 TextStyle 会盖掉字体族)
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
            items: options.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
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
    final theme = Theme.of(context);

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
              // 拖拽条由全局主题提供,这里不再画第二条(双横杠修复)。
              const SizedBox(height: Gap.xs),
              // 搜索栏
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.md,
                  vertical: Gap.xs,
                ),
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
                padding: const EdgeInsets.only(bottom: Gap.xxs),
                child: Text(
                  '未找到需要的模型？手动输入到上方文本框即可',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        model,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
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
