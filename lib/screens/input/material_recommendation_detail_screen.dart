import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../models/article.dart';
import '../../models/bookmark.dart';
import '../../models/material_recommendation.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../services/base_api.dart';
import '../../services/database.dart';
import '../../services/doubao_api.dart';
import '../../services/material_recommend_service.dart';
import 'widgets/follow_up_drawer.dart';

/// 推荐材料详情(v1.8.0):真正能"用起来"的一页。
///
/// - 打开时若没生成过学习内容 → **流式生成**(精读选段+中文导读+重点词+用法建议)并落库
/// - 生成过 → 直接读缓存,秒开
/// - 支持:收藏、复制、**保存为文章**(进阅读器精读)、追问继续问
class MaterialRecommendationDetailScreen extends StatefulWidget {
  final MaterialRecommendation recommendation;
  final LearnerProfile profile;

  const MaterialRecommendationDetailScreen({
    super.key,
    required this.recommendation,
    required this.profile,
  });

  @override
  State<MaterialRecommendationDetailScreen> createState() =>
      _MaterialRecommendationDetailScreenState();
}

class _MaterialRecommendationDetailScreenState
    extends State<MaterialRecommendationDetailScreen> {
  final _api = DoubaoApiService();

  late MaterialRecommendation _rec;
  String _content = '';
  bool _generating = false;
  String? _error;
  bool _savedAsArticle = false;
  StreamSubscription<SseChunk>? _sub;
  late final FollowUpController _followUp;

  @override
  void initState() {
    super.initState();
    _rec = widget.recommendation;
    _content = _rec.content;
    _followUp = FollowUpController(
      buildContext: () => _buildFollowUpContext(),
      historyKey: 'saved_material_follow_up_chats',
      emptyHint: '就这份材料提问',
    );
    if (_content.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _followUp.dispose();
    super.dispose();
  }

  String _buildFollowUpContext() {
    final buf = StringBuffer('学习材料:${_rec.title}\n');
    if (_rec.summary.isNotEmpty) buf.writeln('简介:${_rec.summary}');
    if (_rec.level.isNotEmpty) buf.writeln('难度:${_rec.level}');
    buf.writeln('用户学习画像:${widget.profile.summaryText}');
    if (_content.trim().isNotEmpty) {
      buf.writeln('\n【已生成的学习内容】\n$_content');
    }
    return buf.toString();
  }

  /// 流式生成学习内容(生成完写库缓存)
  Future<void> _generate({bool force = false}) async {
    if (_generating || (!force && _content.trim().isNotEmpty)) return;
    setState(() {
      _generating = true;
      _error = null;
      if (force) _content = '';
    });
    try {
      final vocab = context.read<VocabProvider>().vocabularies;
      final stream = _api.streamPrompt(
        system: MaterialRecommendService.contentSystemPrompt,
        user: MaterialRecommendService.contentUserPrompt(
          rec: _rec,
          profile: widget.profile,
          vocab: vocab,
        ),
      );
      final buffer = StringBuffer();
      final done = Completer<void>();
      _sub = stream.listen(
        (chunk) {
          if (chunk.isReasoning) return;
          buffer.write(chunk.text);
          if (mounted) setState(() => _content = buffer.toString());
        },
        onDone: () => done.complete(),
        onError: (e) {
          if (!done.isCompleted) done.completeError(e);
        },
        cancelOnError: false,
      );
      await done.future;

      var text = buffer.toString().trim();
      if (text.isEmpty) {
        throw Exception('AI 未返回内容，请重试');
      }
      text = DoubaoApiService.extractMarkdown(text);
      if (_rec.id != null) {
        await DatabaseService.updateRecommendationContent(_rec.id!, text);
      }
      if (mounted) setState(() => _content = text);
    } catch (e) {
      if (mounted) setState(() => _error = BaseApiService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 保存为文章 → 可在阅读器里精读(含翻译/练习)
  Future<void> _saveAsArticle() async {
    if (_content.trim().isEmpty) return;
    try {
      await DatabaseService.insertArticle(
        Article(
          title: _rec.title,
          content: _content,
          vocabIds: context
              .read<VocabProvider>()
              .vocabularies
              .map((v) => v.id)
              .whereType<int>()
              .take(30)
              .toList(),
        ),
      );
      if (!mounted) return;
      setState(() => _savedAsArticle = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已保存为文章，可在「特色功能 · AI 生词定制文章」里阅读'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  Future<void> _toggleBookmark() async {
    final provider = context.read<BookmarkProvider>();
    final saved = await provider.toggle(
      Bookmark(
        source: AppConstants.bookmarkSourceFollowUp,
        title: _rec.title,
        content: _content.trim().isEmpty ? _rec.summary : _content,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? '已收藏' : '已取消收藏'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_rec.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '收藏',
            icon: const Icon(Icons.star_border),
            onPressed: _toggleBookmark,
          ),
          IconButton(
            tooltip: '重新生成',
            icon: const Icon(Icons.refresh),
            onPressed: _generating ? null : () => _generate(force: true),
          ),
        ],
      ),
      floatingActionButton: _content.trim().isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showFollowUpDrawer(
                context: context,
                controller: _followUp,
                title: '追问材料',
              ),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('追问'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          // 材料信息
          Card(
            color: theme.colorScheme.primary.withAlpha(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _rec.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_rec.level.isNotEmpty)
                        Text(
                          _rec.level,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  if (_rec.summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _rec.summary,
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                  if (_rec.reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '为什么推荐：${_rec.reason}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          if (_generating && _content.trim().isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('AI 正在生成学习内容…', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),

          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _generate(force: true),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],

          // 学习内容(流式写入)
          if (_content.trim().isNotEmpty)
            SelectableText(
              _content,
              style: const TextStyle(fontSize: 14, height: 1.7),
            ),

          if (_content.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _savedAsArticle ? null : _saveAsArticle,
                    icon: Icon(
                      _savedAsArticle ? Icons.check : Icons.article_outlined,
                      size: 16,
                    ),
                    label: Text(_savedAsArticle ? '已存为文章' : '保存为文章'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showFollowUpDrawer(
                        context: context,
                        controller: _followUp,
                        title: '追问材料',
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('追问'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
