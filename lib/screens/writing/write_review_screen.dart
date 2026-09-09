import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/writing_log.dart';
import '../../services/base_api.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
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

  /// 手写档 / 电子档
  String _materialType = 'handwritten';

  _Phase _phase = _Phase.compose;
  String? _error;

  Map<String, dynamic> _result = {};
  List<Map<String, String>> _issues = [];
  Map<String, String> _errorSummary = {};
  bool _promptedSave = false;
  bool _saved = false;

  late final FollowUpController _followUp;

  static const _maxImages = 9;

  @override
  void initState() {
    super.initState();
    _followUp = FollowUpController(
      buildContext: _buildFollowUpContext,
      imageFilesProvider: () => _materialType == 'handwritten' ? _images : null,
      historyKey: 'saved_writing_follow_up_chats',
      emptyHint: '就这次批改继续提问，例如「为什么这里用完成时？」',
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
        content: const Text('保存后可在「写译记录」里按日期查阅，方便复盘错误。'),
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

  Future<void> _saveLog() async {
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
    } catch (e) {
      if (mounted) _toast('保存失败：$e');
    }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('写译批改'),
        actions: [
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
      body: switch (_phase) {
        _Phase.error => _buildError(context),
        _Phase.transcribing || _Phase.reviewing => _buildLoading(context),
        _Phase.result => _buildResult(context),
        _Phase.compose => _buildCompose(context),
      },
    );
  }

  // ── 编辑态 ──

  Widget _buildCompose(BuildContext context) {
    final theme = Theme.of(context);
    final isHandwritten = _materialType == 'handwritten';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // 材料类型
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'handwritten',
              icon: Icon(Icons.gesture, size: 16),
              label: Text('手写档'),
            ),
            ButtonSegment(
              value: 'electronic',
              icon: Icon(Icons.keyboard_alt_outlined, size: 16),
              label: Text('电子档'),
            ),
          ],
          selected: {_materialType},
          onSelectionChanged: (s) => setState(() => _materialType = s.first),
        ),
        const SizedBox(height: 8),
        Text(
          isHandwritten
              ? '① 拍照/相册上传手写稿（可多张）→ ② 识别为电子档 → ③ 修改确认后批改'
              : '直接粘贴或输入英文，点「AI 批改」即可',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        const SizedBox(height: 12),

        // 手写档:图片区
        if (isHandwritten) ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.gesture,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '手写稿（${_images.length}/$_maxImages）',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _pickImages(fromCamera: false),
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 16,
                        ),
                        label: const Text('相册'),
                      ),
                      TextButton.icon(
                        onPressed: () => _pickImages(fromCamera: true),
                        icon: const Icon(Icons.camera_alt_outlined, size: 16),
                        label: const Text('拍照'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_images.isEmpty)
                    Container(
                      width: double.infinity,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Center(
                        child: Text(
                          '可一次选多张手写稿，按顺序合并成一份文稿',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _images.asMap().entries.map((e) {
                        final i = e.key;
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                e.value,
                                width: 84,
                                height: 84,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _images.removeAt(i)),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black54,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  if (_images.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _transcribe,
                        icon: const Icon(
                          Icons.document_scanner_outlined,
                          size: 16,
                        ),
                        label: Text('识别为电子档（${_images.length} 张）'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 电子档文本
        TextField(
          controller: _textCtrl,
          maxLines: 10,
          minLines: 6,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: isHandwritten ? '电子档（识别结果，可修改）' : '英文内容',
            hintText: isHandwritten
                ? '识别结果会填入这里，可手动修改'
                : '粘贴或输入要批改的英文',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_textCtrl.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} 词',
          style: TextStyle(fontSize: 11, color: Colors.grey[400]),
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
        const SizedBox(height: 10),
        Center(
          child: Text(
            '批改返回:分数 + 修正后全文 + 逐条点评 + 按词汇/语法/表达优化/其他分类的错误汇总',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ),
      ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            SelectableText(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _backToCompose,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('返回重试'),
            ),
          ],
        ),
      ),
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
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scoreColor.withAlpha(30),
                    border: Border.all(color: scoreColor, width: 3),
                  ),
                  child: Center(
                    child: Text(
                      scoreTxt.isEmpty ? '--' : scoreTxt,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                  ),
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
            onPressed: _saved ? null : _saveLog,
            icon: Icon(
              _saved ? Icons.check : Icons.save_outlined,
              size: 18,
            ),
            label: Text(_saved ? '已保存到写译记录' : '保存此次练习'),
          ),
        ),
      ],
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
