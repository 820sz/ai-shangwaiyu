import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/base_api.dart';
import '../../services/doubao_api.dart';

/// 写译批改(v1.5.0):手写英文 → 识别 → 确认/修改 → AI 批改。
/// 流程:1) 拍照/相册选手写图 → 「识别文本」;2) 文本框可编辑;
/// 3) 「AI 批改」→ 分数 + 修正后全文 + 逐条问题点评。
class WriteReviewScreen extends StatefulWidget {
  const WriteReviewScreen({super.key});

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

enum _Phase { input, transcribing, reviewing, result, error }

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  final ImagePicker _picker = ImagePicker();
  final _api = DoubaoApiService();
  final _textCtrl = TextEditingController();

  File? _image;
  _Phase _phase = _Phase.input;
  String? _error;
  Map<String, dynamic> _reviewResult = {};
  List<Map<String, String>> _issues = [];

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (photo != null && mounted) {
        setState(() {
          _image = File(photo.path);
          _phase = _Phase.input;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('相机错误：$e')));
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (photo != null && mounted) {
        setState(() {
          _image = File(photo.path);
          _phase = _Phase.input;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('选择图片错误：$e')));
      }
    }
  }

  /// 步骤1:识别手写文本
  Future<void> _transcribe() async {
    final image = _image;
    if (image == null) return;
    setState(() {
      _phase = _Phase.transcribing;
      _error = null;
    });
    try {
      final text = await _api.transcribeWriting(image);
      if (!mounted) return;
      setState(() {
        _textCtrl.text = text;
        _phase = _Phase.input;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '识别失败：${BaseApiService.friendlyError(e)}';
      });
    }
  }

  /// 步骤2:AI 批改
  Future<void> _review() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先输入或识别出英文内容'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _phase = _Phase.reviewing;
      _error = null;
    });
    try {
      final review = await _api.reviewWriting(text);
      if (!mounted) return;
      setState(() {
        _reviewResult = review;
        _issues = (review['issues'] as List<Map<String, String>>?) ?? [];
        _phase = _Phase.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '批改失败：${BaseApiService.friendlyError(e)}';
      });
    }
  }

  void _backToInput() {
    setState(() {
      _phase = _Phase.input;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('写译批改')),
      body: switch (_phase) {
        _Phase.error => _buildError(context),
        _Phase.transcribing || _Phase.reviewing => _buildLoading(context),
        _Phase.result => _buildResult(context),
        _Phase.input => _buildInput(context),
      },
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _backToInput,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('返回重试'),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('返回'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 手写图片区 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.gesture, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        '手写英文',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _pickFromGallery,
                        icon: const Icon(Icons.photo_library_outlined, size: 16),
                        label: const Text('相册'),
                      ),
                      TextButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.camera_alt_outlined, size: 16),
                        label: const Text('拍照'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_image == null)
                    Container(
                      width: double.infinity,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Center(
                        child: Text(
                          '拍一张手写英文练习的照片，或从相册选择',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Hero(
                          tag: 'writing_image',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              _image!,
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => setState(() => _image = null),
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('移除图片'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _transcribe,
                              icon: const Icon(Icons.document_scanner_outlined, size: 16),
                              label: const Text('识别文本'),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── 文本区 ──
          TextField(
            controller: _textCtrl,
            maxLines: 8,
            minLines: 5,
            decoration: InputDecoration(
              labelText: '英文内容（可修改）',
              hintText: '识别结果会填入这里，可手动修改或直接粘贴输入',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 8),
          Center(
            child: Text(
              '批改返回：分数 + 修正后全文 + 逐条错误点评（语法/拼写/用词/自然度）',
              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context) {
    final theme = Theme.of(context);
    final scoreTxt = (_reviewResult['score'] ?? '').toString();
    final score = int.tryParse(scoreTxt);
    final scoreColor = score == null
        ? Colors.grey
        : score >= 80
            ? Colors.green
            : score >= 60
                ? Colors.orange
                : Colors.red;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 分数卡 ──
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
                    (_reviewResult['summary'] ?? '').toString().isEmpty
                        ? '批改完成'
                        : _reviewResult['summary'].toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── 问题清单 ──
        if (_issues.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('逐条点评',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._issues.asMap().entries.map((e) => _issueCard(theme, e.key, e.value)),
        ],
        // ── 修正后全文 ──
        if ((_reviewResult['correction'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('修正后全文',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                _reviewResult['correction'].toString(),
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ),
          ),
        ],
        // ── 我的原文对比 ──
        const SizedBox(height: 12),
        Text('我的原文',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
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
        const SizedBox(height: 4),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _backToInput,
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
        const SizedBox(height: 24),
      ],
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                const Spacer(),
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
