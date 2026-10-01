import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../providers/vocab_provider.dart';
import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/saved_session.dart';
import '../../services/doubao_api.dart';
import '../../services/api_endpoint.dart';
import '../../services/learner_model_store.dart';
import '../../widgets/app_ui.dart';
import 'material_import_flow.dart';
import 'material_reader_screen.dart';
import 'process_chat.dart';
import 'widgets/ai_article_section.dart';
import 'material_center_screen.dart';
import 'widgets/analysis_mode_picker.dart';
import 'widgets/imported_materials_section.dart';
import 'widgets/material_preview_dialog.dart';
import 'widgets/my_materials_section.dart';

class InputHomeScreen extends StatefulWidget {
  const InputHomeScreen({super.key});

  @override
  State<InputHomeScreen> createState() => _InputHomeScreenState();
}

class _InputHomeScreenState extends State<InputHomeScreen> {
  final ImagePicker _picker = ImagePicker();
  String _sourceBook = '';
  String _sourcePage = '';
  bool _showBookInput = false;

  /// 多图累积
  final List<File> _pendingImages = [];
  static const _maxImages = 10;

  // ── 当前模型 & 思考模式（从 Hive 实时读） ──
  String get _currentModel {
    final v = Hive.box(
      AppConstants.hiveBoxSettings,
    ).get(AppConstants.keyDoubaoModel);
    return (v is String && v.isNotEmpty) ? v : AppConstants.doubaoVisionModel;
  }

  /// v1.7.0:取配置层已校验的档位(档位表外的值会被迁移),
  /// 不再读裸 Hive 值——否则「极致」这类合法档位在页头显示成"不思考"。
  String get _currentThinking => ApiEndpointConfig.primary.thinking;
  @override
  void initState() {
    super.initState();
    // 初始加载词库
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<VocabProvider>().loadVocabularies();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('输入')),
      body: SingleChildScrollView(
        // v2.7(第 1 条):这里以前是 `EdgeInsets.only(bottom: Gap.lg)` —— **没有左右边距**,
        // 于是上面的 AppCard 是通栏的,而下面 AI 文章 / 我的学习材料各自硬写
        // `Card(margin: horizontal 16)`,同一页出现两套卡片几何(外边距 0/16、
        // 圆角 16/12、左内容边距 14/32)。用户说的"ui 大小不统一"就是这个。
        // 现在统一走页面标准边距,四张卡同一套几何。
        padding: Insets.page,
        child: Column(
          children: [
            // ── 主行动:拍照识文(v2.5,U1)──
            // 训记的本质是"一进来就能开始":这一页的第一屏先给**一个动作**,
            // 其余(材料中心 / AI 文章 / 我的材料)按重要性往下排。
            AppStagger(index: 0, child: _buildCaptureSectionCard(theme)),

            // ── 材料中心(v2.0;唯一的"找材料"入口)──
            AppStagger(index: 1, child: _buildMaterialCenterCard(theme)),

            // ── AI 生词定制文章 ──
            const AppStagger(index: 2, child: AiArticleSection()),

            // ── 材料导入（v2.9,用户第 5 条:外部导入的材料本体，可分类、可阅读）──
            const AppStagger(index: 3, child: ImportedMaterialsSection()),

            // ── 我的词汇本（v2.9,用户第 5 条:原来这块本质就是词汇本）──
            const AppStagger(index: 4, child: MyMaterialsSection()),
          ],
        ),
      ),
    );
  }

  /// 材料中心入口(v2.0):软件提供的真实材料渠道
  ///
  /// v2.5(U1):改用统一的 `AppActionTile`(图标/标题/副标题/箭头全 App 一套),
  /// 与学习助理页的入口卡长得一致 —— 以前每页各画一种,看起来"不是同一个 App"。
  Widget _buildMaterialCenterCard(ThemeData theme) {
    return AppActionTile(
      icon: Icons.local_library_outlined,
      title: '材料中心',
      subtitle: '资料原文(公版书/论文/外刊)+ AI 整理 + 自备文本',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MaterialCenterScreen()),
      ),
    );
  }

  /// 拍照识文卡片(v2.6 重做;v2.7 升级为「上传分析材料」,用户第 3 条)。
  ///
  /// 用户原话:'"拍照识文"功能也要优化,现在的使用场景只能用于手写或者照片 ——
  /// 因此,该功能升级为"上传分析材料",然后子功能 ——"拍照识别"和"外部链接导入"
  /// (也就是兼容各种网站链接,包括但不限于论文、期刊等等这些)'。
  ///
  /// 所以这一张卡现在有**两个子功能**:
  /// 1. **拍照识别** = 原来的拍照/相册取词(识图结果页的模型/保存/追问原样保留);
  /// 2. **外部链接导入** = 贴一个公开链接 → 抓正文 → 在软件内的阅读器里读
  ///    (逐段翻译 / 点词 / 收藏 / 追问 / 底部动作栏,与材料中心同一套)。
  /// 两个入口都放在卡片顶部一行,平级、一眼能看出这是"两条路"。
  Widget _buildCaptureSectionCard(ThemeData theme) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行(带模型/思考档位的快捷入口,不占额外一行)
          Row(
            children: [
              Icon(Icons.upload_file, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: Gap.xs),
              Text(
                '上传分析材料',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: Text(
                  '拍照识词,或导入链接让 AI 帮你分析',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),

          // ① 两个子功能平级并排:拍照识别 / 外部链接导入(第 3 条)
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _takePhoto,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('拍照识别', style: TextStyle(fontSize: 14)),
                ),
              ),
              const SizedBox(width: Gap.xs),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importFromLink,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('外部链接导入',
                      style: TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),

          // ② 次要行动:从相册选择(属于"拍照识别"这条路)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickFromGallery,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
              ),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('从相册选择(可多选)'),
            ),
          ),

          const SizedBox(height: Gap.xs),
          // ③ 参数行:模型 / 思考档(识图前即可切换)
          _buildModelThinkingRow(theme),

          // ④ 待提交图片缩略图 + 开始识别
          if (_pendingImages.isNotEmpty) ...[
            const SizedBox(height: Gap.sm),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: _pendingImages.length,
                separatorBuilder: (_, _) => const SizedBox(width: Gap.xs),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _showImagePreview(i),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.control - 2),
                        child: Image.file(
                          _pendingImages[i],
                          width: 64,
                          height: 72,
                          // P3:64×72 的缩略图按 128px 解码即可,
                          // 原图直解是低端机 OOM 的主因
                          cacheWidth: 128,
                          fit: BoxFit.cover,
                        ),
                      ),
                      // 删除按钮（右上角）
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _removePendingImage(i),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      // 裁剪按钮（右下角）
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () async {
                            final cropped = await _cropImage(
                              _pendingImages[i],
                            );
                            if (cropped != null && mounted) {
                              setState(() => _pendingImages[i] = cropped);
                            }
                          },
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black54,
                            ),
                            child: const Icon(
                              Icons.crop,
                              size: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Gap.xs),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitImages,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text('开始识别(${_pendingImages.length} 张)'),
              ),
            ),
          ],

          // ⑤ 继续上次暂存的会话
          if (_savedSessions.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showSavedSessions,
                icon: const Icon(Icons.history, size: 16),
                label: Text(
                  '继续上次会话(${_savedSessions.length} 条)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],

          // ⑥ 出处(可折叠,收起来时不占视觉)
          const SizedBox(height: Gap.xxs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _showBookInput = !_showBookInput),
              icon: Icon(
                _showBookInput ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                _sourceBook.isEmpty
                    ? '标注出处(可选)'
                    : '《$_sourceBook》p$_sourcePage',
              ),
            ),
          ),
          if (_showBookInput) _buildBookInput(theme),
        ],
      ),
    );
  }

  Widget _buildBookInput(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              decoration: const InputDecoration(
                labelText: '书名',
                hintText: '如：哈利波特与魔法石',
                isDense: true,
              ),
              onChanged: (v) => _sourceBook = v,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: TextField(
              decoration: const InputDecoration(
                labelText: '页码',
                hintText: 'p23',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => _sourcePage = v,
            ),
          ),
        ],
      ),
    );
  }

  /// AI 模型 & 思考强度选择行 — 识图前即可切换，避免进入识别后再打断
  Widget _buildModelThinkingRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.model_training,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: PopupMenuButton<String>(
              offset: const Offset(0, 200),
              constraints: const BoxConstraints(maxWidth: 280),
              itemBuilder: (_) => [
                // 按端点族/最近拉取结果展示(配了 DS 就显示 DS 模型,v1.4.3)
                ...primaryModelChoices().map((m) {
                  final isSel = m == _currentModel;
                  return PopupMenuItem(
                    value: 'model:$m',
                    height: 30,
                    child: Text(
                      m,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                        color: isSel ? const Color(0xFF3D7A5C) : null,
                      ),
                    ),
                  );
                }),
                const PopupMenuDivider(),
                ...AppConstants.thinkingOptionsFor(_currentModel).entries
                    .map((e) {
                  final isSel = e.key == _currentThinking;
                  return PopupMenuItem(
                    value: 'think:${e.key}',
                    height: 30,
                    child: Row(
                      children: [
                        Icon(
                          isSel ? Icons.lightbulb : Icons.lightbulb_outline,
                          size: 12,
                          color: isSel
                              ? AppTheme.warningColor(context)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSel
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSel
                                ? AppTheme.warningColor(context)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              onSelected: (v) async {
                if (v.startsWith('model:')) {
                  await Hive.box(
                    AppConstants.hiveBoxSettings,
                  ).put(AppConstants.keyDoubaoModel, v.substring(6));
                } else if (v.startsWith('think:')) {
                  await Hive.box(
                    AppConstants.hiveBoxSettings,
                  ).put(AppConstants.keyDoubaoThinking, v.substring(6));
                }
                if (mounted) setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _currentModel.length > 22
                      ? '${_currentModel.substring(0, 22)}…'
                      : _currentModel,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 思考强度快捷标签(橙色描边:半透明色相,深色下同样成立)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppTheme.warningColor(context).withAlpha(110),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              AppConstants.thinkingOptionsFor(_currentModel)[_currentThinking] ??
                  '不思考',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.warningColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 外部链接导入(v2.7,用户第 3 条):贴公开链接 → 抓正文 → 入库 → 阅读器。
  ///
  /// 与材料中心的导入走**同一个** [MaterialImportFlow]:抓取方式(Gutenberg/arXiv
  /// 用专用抓取、其它走通用网页正文)、失败原因、标题中文化、入库全都共用一份实现。
  Future<void> _importFromLink() async {
    final ingested = await MaterialImportFlow.run(
      context,
      model: LearnerModelStore.load(),
      only: ImportChannel.link,
      dialogTitle: '外部链接导入',
    );
    if (ingested == null || !mounted) return;
    final go = await showMaterialPreview(context, ingested);
    if (!mounted) return;
    if (go) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MaterialReaderScreen(materialId: ingested.materialId),
        ),
      );
      if (mounted) await context.read<VocabProvider>().loadVocabularies();
    }
  }

  Future<void> _takePhoto() async {
    if (_pendingImages.length >= _maxImages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('最多$_maxImages张图片')));
      return;
    }
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50,
        maxWidth: 1024,
      );
      if (photo != null && mounted) {
        setState(() => _pendingImages.add(File(photo.path)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('相机错误：$e')));
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_pendingImages.length >= _maxImages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('最多$_maxImages张图片')));
      return;
    }
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 50,
        maxWidth: 1024,
        limit: _maxImages - _pendingImages.length,
      );
      if (images.isNotEmpty && mounted) {
        final files = images
            .take(_maxImages - _pendingImages.length)
            .map((x) => File(x.path))
            .toList();
        setState(() => _pendingImages.addAll(files));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('选择图片错误：$e')));
      }
    }
  }

  /// 调用系统裁剪界面。返回裁剪后的文件，用户取消则返回 null。
  Future<File?> _cropImage(File imageFile, {String? label}) async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        maxWidth: 1024,
        maxHeight: 2048,
        compressQuality: 70,
        compressFormat: ImageCompressFormat.jpg,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: label != null ? '裁剪 $label' : '裁剪图片',
            toolbarColor: const Color(0xFF1A1A2E),
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
        ],
      );
      if (cropped != null) return File(cropped.path);
      return null;
    } catch (e) {
      debugPrint('ReadFlow crop failed: $e');
      return imageFile;
    }
  }

  void _removePendingImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  // ═══════════════ 暂存会话 ═══════════════

  /// 已暂存的会话列表(最新在前)
  List<SavedSession> get _savedSessions {
    try {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      final raw = box.get(AppConstants.keySavedSessions);
      if (raw is List) {
        // Hive 读回的嵌套 Map 是 _Map<dynamic, dynamic>,不能直接
        // as Map<String, dynamic> 强转(会抛)——必须 .from 重建
        return raw
            .map((e) => SavedSession.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// 会话列表弹窗:点选恢复,可删除
  void _showSavedSessions() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    '暂存的会话',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Hive.box(
                        AppConstants.hiveBoxSettings,
                      ).delete(AppConstants.keySavedSessions);
                      Navigator.pop(ctx);
                      if (mounted) setState(() {});
                    },
                    child: Text(
                      '清空全部',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.dangerColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_savedSessions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text('暂无暂存的会话',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              )
            else
              ...List.generate(_savedSessions.length, (i) {
                final s = _savedSessions[i];
                return ListTile(
                  leading: const Icon(Icons.chat_bubble_outline, size: 20),
                  title: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    s.dateLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () {
                      final box = Hive.box(AppConstants.hiveBoxSettings);
                      final rest = _savedSessions
                          .where((x) => x.id != s.id)
                          .toList();
                      box.put(
                        AppConstants.keySavedSessions,
                        rest.map((x) => x.toJson()).toList(),
                      );
                      Navigator.pop(ctx);
                      if (mounted) setState(() {});
                    },
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _resumeSession(s);
                  },
                );
              }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 恢复会话:从结果 photoPath 重建图片文件列表(只保留仍存在的副本),
  /// 以恢复模式打开结果页 — 识别结果与追问消息一并还原。
  void _resumeSession(SavedSession s) {
    final files = <File>[];
    for (final m in s.results) {
      // Vocabulary.toMap() 序列化为 snake_case('photo_path');
      // 兼容老数据的 camelCase('photoPath')
      final p = (m['photo_path'] ?? m['photoPath']) as String?;
      if (p == null || p.isEmpty) continue;
      final f = File(p);
      if (f.existsSync() && !files.any((x) => x.path == p)) {
        files.add(f);
      }
    }
    // v2.6 修复(用户实测:"选不保存对话后,拍照识文下还是保留残留对话"):
    // 暂存会话是**一次性的草稿** —— 恢复后必须从暂存列表里删掉,否则它会一直
    // 挂在那里:用户明明在退出时选了「不保存」,回到输入页却还是看到同一条旧会话,
    // 点进去又把它整个恢复出来。想再留一份的话,重新「暂时离开」即可。
    try {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      final rest = _savedSessions.where((x) => x.id != s.id).toList();
      box.put(
        AppConstants.keySavedSessions,
        rest.map((x) => x.toJson()).toList(),
      );
      setState(() {});
    } catch (e) {
      debugPrint('ReadFlow 消费暂存会话失败(不影响恢复): $e');
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessChatScreen(
          imageFiles: files,
          sourceBook: s.sourceBook,
          sourcePage: s.sourcePage,
          analysisMode: s.analysisMode,
          restoreSession: s,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  /// 点击缩略图 → 大图预览弹窗，可放大查看、裁剪
  void _showImagePreview(int index) {
    final file = _pendingImages[index];
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, anim, secAnim) => _ImagePreviewPage(
          file: file,
          index: index,
          onCrop: _onCropFromPreview,
        ),
        transitionsBuilder: (ctx, anim, secAnim, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  /// 预览页中触发的裁剪 → 等待裁剪完成 → pop 回主页 → 替换图片
  Future<void> _onCropFromPreview(int index) async {
    final cropped = await _cropImage(_pendingImages[index]);
    if (cropped != null && mounted) {
      setState(() => _pendingImages[index] = cropped);
    }
  }

  void _submitImages() async {
    if (_pendingImages.isEmpty) return;

    // 弹出分析模式选择
    final mode = await showAnalysisModePicker(context);
    if (mode == null || !mounted) return; // 用户取消

    final files = List<File>.from(_pendingImages);
    _processImages(files, analysisMode: mode);
  }

  Future<void> _processImages(
    List<File> imageFiles, {
    String analysisMode = AppConstants.analysisModeMarked,
  }) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessChatScreen(
          imageFiles: imageFiles,
          sourceBook: _sourceBook.isNotEmpty ? _sourceBook : null,
          sourcePage: _sourcePage.isNotEmpty ? _sourcePage : null,
          analysisMode: analysisMode,
        ),
      ),
    );

    if (mounted) {
      // 从识图页返回后始终清空待提交图片（用户可在识图页内重试，无需保留）
      setState(() => _pendingImages.clear());
      // 重新加载学习材料列表
      await context.read<VocabProvider>().loadVocabularies();
      if (saved == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('生词已保存'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// 图片大图预览页 — 点击缩略图弹出，支持放大查看和裁剪入口
class _ImagePreviewPage extends StatelessWidget {
  final File file;
  final int index;
  final Future<void> Function(int index) onCrop;

  const _ImagePreviewPage({
    required this.file,
    required this.index,
    required this.onCrop,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 全屏图片（可交互）
          Center(
            child: InteractiveViewer(
              maxScale: 5.0,
              child: Image.file(
                file,
                width: size.width,
                // P3:按屏幕宽度解码,别把 12MP 原图整张解进内存(约 48MB/张)
                cacheWidth:
                    (size.width * MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(320, 2048),
                fit: BoxFit.contain,
              ),
            ),
          ),
          // 顶部关闭按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black54,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
          // 底部裁剪按钮
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context); // 先关预览
                  await onCrop(index);
                },
                icon: const Icon(Icons.crop, size: 18),
                label: const Text('裁剪图片'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
