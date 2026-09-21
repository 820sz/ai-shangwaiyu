import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/writing_log.dart';
import '../../services/base_api.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../widgets/error_state.dart';
import '../../widgets/writing_labels.dart';
import '../input/widgets/follow_up_drawer.dart';
import 'writing_logs_screen.dart';

/// 写译批改(v1.5.0 初版 / v1.6.0 重构)。
///
/// 流程:选材料类型(手写档 / 电子档)→ 手写档先识别成电子档 →
/// 文本可编辑确认 → AI 批改 → 分数 + 分类错误汇总 + 逐条点评 + 修正全文。
/// 批改后可保存为练习日志(按日期归档),可开追问抽屉继续问(与识图页同款体验)。
class WriteReviewScreen extends StatefulWidget {
  const WriteReviewScreen({super.key});

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

enum _Phase { compose, transcribing, reviewing, result, error }

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  final ImagePicker _picker = ImagePicker();
  final _api = DoubaoApiService();
  final _textCtrl = TextEditingController();
  final List<File> _images = [];

  /// 手写档 / 电子档(取值与标签统一在 lib/widgets/writing_labels.dart,
  /// 与「写译记录」页共用同一份,避免两页文案漂移 —— P2-29)
  String _materialType = kMaterialTypeHandwritten;

  _Phase _phase = _Phase.compose;
  String? _error;

  Map<String, dynamic> _result = {};
  List<Map<String, String>> _issues = [];
  Map<String, String> _errorSummary = {};
  bool _promptedSave = false;
  bool _saved = false;

  /// 退出确认弹窗是否已经打开(P2-27):连按两次返回键只弹一个窗
  bool _exitDialogOpen = false;

  late final FollowUpController _followUp;

  static const _maxImages = 9;

  @override
  void initState() {
    super.initState();
    _followUp = FollowUpController(
      buildContext: _buildFollowUpContext,
      imageFilesProvider: () =>
          _materialType == kMaterialTypeHandwritten ? _images : null,
      historyKey: 'saved_writing_follow_up_chats',
      emptyHint: '就这次批改提问',
    );
  }

  @override
  void dispose() {
    _followUp.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  /// 追问抽屉的材料上下文:原文 + 批改结果 + 错误汇总
  String _buildFollowUpContext() {
    final buf = StringBuffer('材料类型:写译批改(用户提交的英文写作)\n');
    buf.writeln('【我的原文】\n${_textCtrl.text.trim()}');
    final corrected = (_result['correction'] ?? '').toString().trim();
    if (corrected.isNotEmpty) {
      buf.writeln('\n【批改后全文】\n$corrected');
    }
    final score = (_result['score'] ?? '').toString().trim();
    if (score.isNotEmpty) buf.writeln('\n【得分】$score');
    if (_issues.isNotEmpty) {
      buf.writeln('\n【逐条点评】');
      for (final it in _issues) {
        buf.writeln(
          '- 原文「${it['original']}」→ 改为「${it['correction']}」'
          '(${it['type']}):${it['reason']}',
        );
      }
    }
    final summaryText = _errorSummary.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}:${e.value}')
        .join(';');
    if (summaryText.isNotEmpty) {
      buf.writeln('\n【错误分类汇总】$summaryText');
    }
    return buf.toString();
  }

  // ── 图片 ──

  Future<void> _pickImages({required bool fromCamera}) async {
    if (_images.length >= _maxImages) {
      _toast('最多 $_maxImages 张图片');
      return;
    }
    try {
      if (fromCamera) {
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
          maxWidth: 1600,
        );
        if (photo != null && mounted) {
          setState(() => _images.add(File(photo.path)));
        }
      } else {
        final picked = await _picker.pickMultiImage(
          imageQuality: 70,
          maxWidth: 1600,
          limit: _maxImages - _images.length,
        );
        if (picked.isNotEmpty && mounted) {
          setState(() {
            _images.addAll(
              picked
                  .take(_maxImages - _images.length)
                  .map((x) => File(x.path)),
            );
          });
        }
      }
    } catch (e) {
      if (mounted) _toast('选择图片失败：$e');
    }
  }

  // ── 识别(手写档 → 电子档) ──

  Future<void> _transcribe() async {
    if (_images.isEmpty) {
      _toast('请先拍照或从相册选择手写稿');
      return;
    }
    setState(() {
      _phase = _Phase.transcribing;
      _error = null;
    });
    try {
      final text = await _api.transcribeWriting(_images);
      if (!mounted) return;
      setState(() {
        final old = _textCtrl.text.trim();
        _textCtrl.text = old.isEmpty ? text : '$old\n$text';
        _phase = _Phase.compose;
      });
      _toast('已识别为电子档，可修改后批改');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '识别失败：${BaseApiService.friendlyError(e)}';
      });
    }
  }

  // ── 批改 ──

  Future<void> _review() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _toast('请先输入英文内容（手写档可先点「识别为电子档」）');
      return;
    }
    setState(() {
      _phase = _Phase.reviewing;
      _error = null;
      _promptedSave = false;
      _saved = false;
    });
    try {
      final result = await _api.reviewWriting(text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _issues = (result['issues'] as List<Map<String, String>>?) ?? [];
        _errorSummary =
            (result['error_summary'] as Map<String, String>?) ?? {};
        _phase = _Phase.result;
      });
      if (!_promptedSave) {
        _promptedSave = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _askSaveLog());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '批改失败：${BaseApiService.friendlyError(e)}';
      });
    }
  }

  // ── 保存练习日志 ──

  Future<void> _askSaveLog() async {
    if (!mounted || _saved) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('是否保存此次写译练习？'),
        content: const Text('保存后可在「写译记录」按日期查阅。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('暂不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) await _saveLog();
  }

  /// 保存为写译记录。返回是否真的写库成功 ——
  /// 退出确认要用它决定"保存后能不能 pop":失败还退出去等于数据照样丢。
  Future<bool> _saveLog() async {
    try {
      await DatabaseService.insertWritingLog(
        WritingLog(
          sourceType: _materialType,
          originalText: _textCtrl.text.trim(),
          correctedText: (_result['correction'] ?? '').toString(),
          score: (_result['score'] ?? '').toString(),
          summary: (_result['summary'] ?? '').toString(),
          issues: _issues,
          errorSummary: _errorSummary,
          model: _followUp.endpoint.model,
          imagePaths: _images.map((f) => f.path).toList(),
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) {
        setState(() => _saved = true);
        _toast('已保存到写译记录');
      }
      return true;
    } catch (e) {
      if (mounted) _toast('保存失败：$e');
      return false;
    }
  }

  // ── 退出保护(P2-27) ──

  /// 页面上是否有"值得挽留"的产物:敲过的原文 / 拍过的手写稿 / 已出的批改结果。
  bool _hasUnsavedWork() {
    if (_textCtrl.text.trim().isNotEmpty) return true;
    if (_images.isNotEmpty) return true;
    if (_phase == _Phase.result || _result.isNotEmpty) return true;
    return false;
  }

  /// 原文词数(编辑态与退出提示共用一份算法,避免两处数出不同结果)
  int get _wordCount => _textCtrl.text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;

  /// 返回键/左上角箭头被按下时的三选一问(与识图页 process_chat.dart 的
  /// `_onWillPop` 同一套交互风格:取消 / 直接离开 / 保存并退出)。
  ///
  /// 为什么必须问:手写档最多要拍 9 张、原文可能敲几百字、批改还花过一次
  /// AI 调用 —— 按一下返回就全丢,而且不进 writing_logs(练习统计少记)。
  /// 返回 true = 允许离开;false = 留在本页。
  Future<bool> _onWillPop() async {
    if (!_hasUnsavedWork()) return true; // 空白页:不打扰用户
    if (_exitDialogOpen) return false; // 连点两次返回不叠弹窗
    _exitDialogOpen = true;
    var choice = 'cancel';
    try {
      final parts = <String>[];
      if (_textCtrl.text.trim().isNotEmpty) parts.add('$_wordCount 词原文');
      if (_images.isNotEmpty) parts.add('${_images.length} 张手写稿');
      if (_phase == _Phase.result) parts.add('本次批改结果');
      final what = parts.isEmpty ? '当前内容' : parts.join('、');
      final hint = _phase == _Phase.result
          ? '保存为写译记录后可在「写译记录」按日期查阅。'
          : '保存为写译记录后可在「写译记录」按日期查阅。\n'
                '（本次还没批改，记录里暂时没有分数与点评）';
      choice =
          await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('离开写译批改？'),
              content: Text('你还有 $what 没有保存。\n$hint'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'discard'),
                  child: const Text('直接离开'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  child: const Text('保存为写译记录'),
                ),
              ],
            ),
          ) ??
          'cancel';
    } finally {
      _exitDialogOpen = false;
    }
    if (choice == 'save') {
      final saved = await _saveLog();
      // 保存失败就留在页面上(草稿还在),不要"报个错然后照退不误"
      if (!saved) return false;
      // 顺手把本轮追问对话存进历史,避免"存了批改却丢了追问"
      if (_followUp.dirty && _followUp.messages.value.isNotEmpty) {
        await _followUp.saveConversation();
      }
      return true;
    }
    return choice == 'discard';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _backToCompose() {
    setState(() {
      _phase = _Phase.compose;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 我们手动控制:先问保存/离开,再决定退不退(P2-27)
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        try {
          final ok = await _onWillPop();
          if (ok && mounted) Navigator.of(context).pop(result);
        } catch (e) {
          // 兜底:确认流程本身出错也不能把用户困在这一页
          debugPrint('ReadFlow writeReview onPopInvokedWithResult: $e');
          if (mounted) Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('写译批改'),
          actions: [
            // 常驻保存入口(P2-27):结果页很长,底部的保存按钮得滚到底才看得见;
            // 而原来只有"批改完成弹一次"的对话框,点过"暂不保存"就再也回不来。
            // 这里刻意用紧凑的图标按钮:AppBar 是 centerTitle,放带文字的长按钮
            // 会挤压居中的标题(窄屏上标题会被截断)。
            if (_phase == _Phase.result)
              IconButton(
                tooltip: _saved ? '已保存到写译记录' : '保存记录',
                icon: Icon(
                  _saved ? Icons.check_circle_outline : Icons.save_outlined,
                ),
                onPressed: _saved ? null : () => _saveLog(),
              ),
            IconButton(
              tooltip: '写译记录',
              icon: const Icon(Icons.history_edu_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WritingLogsScreen()),
              ),
            ),
          ],
        ),
        floatingActionButton: _phase == _Phase.result
            ? FloatingActionButton.extended(
                onPressed: () => showFollowUpDrawer(
                  context: context,
                  controller: _followUp,
                  title: '追问批改',
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('追问'),
              )
            : null,
        body: AnimatedSwitcher(
          // A1:阶段切换(编辑 → 生成中 → 结果/错误)给 200ms easeOut 淡入,
          // 不再硬切;分数圆环另有 520ms 的数值入场(见 _scoreBadge)。
          // 输入、滚动这类高频操作不加动画。
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          child: KeyedSubtree(
            key: ValueKey(_phase),
            child: switch (_phase) {
              _Phase.error => _buildError(context),
              _Phase.transcribing || _Phase.reviewing => _buildLoading(context),
              _Phase.result => _buildResult(context),
              _Phase.compose => _buildCompose(context),
            },
          ),
        ),
      ),
    ); // PopScope
  }

  // ── 编辑态 ──

  Widget _buildCompose(BuildContext context) {
    final isHandwritten = _materialType == kMaterialTypeHandwritten;
    final wordCount = _wordCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // 材料类型(取值与文案见 lib/widgets/writing_labels.dart,
        // 与「写译记录」页共用一份 —— P2-29 的局部收口)
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: kMaterialTypeHandwritten,
              icon: Icon(Icons.gesture, size: 16),
              label: Text(kMaterialTypeHandwrittenLabel),
            ),
            ButtonSegment(
              value: kMaterialTypeElectronic,
              icon: Icon(Icons.keyboard_alt_outlined, size: 16),
              label: Text(kMaterialTypeElectronicLabel),
            ),
          ],
          selected: {_materialType},
          onSelectionChanged: (s) => setState(() => _materialType = s.first),
        ),
        const SizedBox(height: 12),

        // 手写稿:固定高度横向条,永不撑破页面
        if (isHandwritten) ...[
          Row(
            children: [
              Text(
                '手写稿 ${_images.length}/$_maxImages',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '从相册选择（可多选）',
                onPressed: () => _pickImages(fromCamera: false),
                icon: const Icon(Icons.photo_library_outlined),
              ),
              IconButton(
                tooltip: '拍照',
                onPressed: () => _pickImages(fromCamera: true),
                icon: const Icon(Icons.camera_alt_outlined),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 92,
            child: _images.isEmpty
                ? GestureDetector(
                    onTap: () => _pickImages(fromCamera: false),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 28,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        GestureDetector(
                          onTap: () => _openImageViewer(i),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _images[i],
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _images.removeAt(i)),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black54,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _images.isEmpty ? null : _transcribe,
              icon: const Icon(Icons.document_scanner_outlined, size: 16),
              label: const Text('识别为电子档'),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 文本区:固定高度,内部滚动(长文不会把页面顶爆)
        Row(
          children: [
            Text(
              isHandwritten ? '电子档' : '英文内容',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Text(
              '$wordCount 词',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 240,
          child: TextField(
            controller: _textCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: isHandwritten ? null : '粘贴或输入要批改的英文',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _review,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('AI 批改'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  /// 全屏看图(v1.7.0):可缩放拖动,点空白处关闭
  void _openImageViewer(int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, _, _) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text('${index + 1} / ${_images.length}'),
          ),
          body: GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Image.file(_images[index], fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _phase == _Phase.transcribing ? 'AI 正在识别手写内容…' : 'AI 正在批改写作…',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    // 用公共 ErrorState(P2-30 / B4):错误 + 一个明确出口,
    // 与统计页/写译记录页的错误态长得一样,用户不必重新学
    return ErrorState(
      message: _error ?? '批改失败',
      onRetry: _backToCompose,
      retryLabel: '返回重试',
    );
  }

  // ── 结果态 ──

  Widget _buildResult(BuildContext context) {
    final theme = Theme.of(context);
    final scoreTxt = (_result['score'] ?? '').toString();
    final score = int.tryParse(scoreTxt);
    final scoreColor = score == null
        ? Colors.grey
        : score >= 80
        ? Colors.green
        : score >= 60
        ? Colors.orange
        : Colors.red;
    final hasSummary =
        _errorSummary.values.any((v) => v.trim().isNotEmpty);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // 分数 + 总评
        Card(
          color: scoreColor.withAlpha(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _scoreBadge(
                  score: score,
                  scoreTxt: scoreTxt,
                  color: scoreColor,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    (_result['summary'] ?? '').toString().isEmpty
                        ? '批改完成'
                        : _result['summary'].toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 错误分类汇总
        if (hasSummary) ...[
          const SizedBox(height: 16),
          Text(
            '错误分类汇总',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...WritingLog.categories
              .where((c) => (_errorSummary[c] ?? '').trim().isNotEmpty)
              .map((c) => _summaryCard(theme, c, _errorSummary[c]!)),
        ],

        // 逐条点评
        if (_issues.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '逐条点评（${_issues.length}）',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ..._issues.asMap().entries.map(
            (e) => _issueCard(theme, e.key, e.value),
          ),
        ],

        // 修正后全文
        if ((_result['correction'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '修正后全文',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                _result['correction'].toString(),
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ),
          ),
        ],

        // 我的原文
        const SizedBox(height: 16),
        Text(
          '我的原文',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              _textCtrl.text.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.6,
                color: Colors.grey[700],
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _backToCompose,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('修改后再批'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _review,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重新批改'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: _saved ? null : () => _saveLog(),
            icon: Icon(
              _saved ? Icons.check : Icons.save_outlined,
              size: 18,
            ),
            // 文案与 AppBar 的「保存记录」/退出弹窗的「保存为写译记录」对齐(P2-29)
            label: Text(_saved ? '已保存到写译记录' : '保存为写译记录'),
          ),
        ),
      ],
    );
  }

  /// 分数圆环 + 分数文本。
  ///
  /// A1(动效):从生成中到出结果是全 App 唯一的"成就时刻",值得一次
  /// 520ms 的 TweenAnimationBuilder 入场 —— 数字从 0 涨到目标分,
  /// 圆环按同一进度填充(两者读同一个动画值,数字和环不会脱节)。
  /// 用 TweenAnimationBuilder 而不是 AnimationController:一次性的值入场,
  /// 不需要显式管理生命周期,也不怕页面重建后重播(目标值不变就不重播)。
  ///
  /// B3(字号放大):不再是 64×64 硬盒 + fontSize 22 —— 系统字号 1.5×~2× 时
  /// 会被裁掉。下限保持 64,上限 84 兜底,里面套 FittedBox:正常字号仍是 64,
  /// 字号放大时圆环跟着长一点,极端字号则缩小填进去。
  Widget _scoreBadge({
    required int? score,
    required String scoreTxt,
    required Color color,
  }) {
    final target = (score ?? 0).clamp(0, 100).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final shown = score == null
            ? (scoreTxt.isEmpty ? '--' : scoreTxt)
            : '${value.round()}';
        return Stack(
          alignment: Alignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 64,
                minHeight: 64,
                maxWidth: 84,
                maxHeight: 84,
              ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withAlpha(25),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    shown,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
            // 圆环:与数字共用动画值(0 → score/100)
            if (score != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CircularProgressIndicator(
                    value: value / 100,
                    strokeWidth: 3.5,
                    backgroundColor: color.withAlpha(30),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(ThemeData theme, String category, String text) {
    final color = switch (category) {
      '词汇' => Colors.purple,
      '语法' => Colors.blue,
      '表达优化' => Colors.teal,
      _ => Colors.grey,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                category,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _issueCard(ThemeData theme, int index, Map<String, String> issue) {
    final original = issue['original'] ?? '';
    final correction = issue['correction'] ?? '';
    final type = issue['type'] ?? '';
    final reason = issue['reason'] ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
                if (type.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (original.isNotEmpty)
              Text(
                original,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.red[400],
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            if (correction.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                correction,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.green[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                reason,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
