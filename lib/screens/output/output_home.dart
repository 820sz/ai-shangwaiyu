import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/article_provider.dart';
import '../../providers/vocab_provider.dart';
import '../../models/article.dart';
import '../writing/write_review_screen.dart';
import '../writing/writing_logs_screen.dart';
import 'article_reader.dart';

class OutputHomeScreen extends StatefulWidget {
  const OutputHomeScreen({super.key});

  @override
  State<OutputHomeScreen> createState() => _OutputHomeScreenState();
}

class _OutputHomeScreenState extends State<OutputHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ArticleProvider>().loadArticles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final articleProv = context.watch<ArticleProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('输出'),
      ),
      body: articleProv.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── 写译批改 / 写译记录(v1.6.0:从输入页迁到输出页) ──
                _buildWritingEntries(theme),

                // 生成按钮
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          articleProv.generating ? null : () => _generateArticle(),
                      icon: articleProv.generating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(articleProv.generating ? 'AI 正在生成文章…' : '基于生词生成文章'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),

                if (articleProv.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      articleProv.error!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                    ),
                  ),

                const Divider(),

                // 文章列表
                Expanded(
                  child: articleProv.articles.isEmpty
                      ? _buildEmptyState(theme)
                      : _buildArticleList(articleProv, theme),
                ),
              ],
            ),
    );
  }

  /// 写译批改 / 写译记录入口(v1.6.0:从输入页迁来,输出页才是"写"的地方)
  Widget _buildWritingEntries(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.primary.withAlpha(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WriteReviewScreen(),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_note,
                        color: theme.colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '写译批改',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '手写/电子稿 → AI 批改',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WritingLogsScreen(),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_edu_outlined,
                        color: Colors.amber[800],
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '写译记录',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '按日期查阅复盘',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.article_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            '还没有 AI 生成的文章',
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            '添加生词后，点击上方按钮生成',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleList(ArticleProvider provider, ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () => provider.loadArticles(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: provider.articles.length + 1,
        itemBuilder: (context, index) {
          if (index == provider.articles.length) {
            return const SizedBox(height: 80);
          }
          final article = provider.articles[index];
          final exercises = article.id != null
              ? provider.exercisesByArticle[article.id] ?? []
              : <dynamic>[];

          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: Text(
                article.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    article.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _metaChip(Icons.bookmark, '${article.vocabCount} 生词', theme),
                      const SizedBox(width: 8),
                      _metaChip(Icons.fitness_center, '${exercises.length} 练习', theme),
                      const SizedBox(width: 8),
                      _metaChip(
                        Icons.calendar_today,
                        '${article.createdAt.month}/${article.createdAt.day}',
                        theme,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => _confirmDelete(article),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ArticleReaderScreen(article: article),
                  ),
                ).then((_) => provider.loadArticles());
              },
            ),
          );
        },
      ),
    );
  }

  Widget _metaChip(IconData icon, String label, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Future<void> _generateArticle() async {
    final vocab = context.read<VocabProvider>();
    final articleProv = context.read<ArticleProvider>();

    // 取最近未掌握的词汇
    await vocab.loadVocabularies();
    final candidates = vocab.vocabularies
        .where((v) => v.masteryLevel != 2)
        .take(20)
        .toList();

    if (candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有足够的生词，请先拍照添加一些。')),
        );
      }
      return;
    }

    final vocabList = candidates
        .map((v) => {
              'id': v.id?.toString() ?? '',
              'word': v.word,
              'translation': v.translation ?? '',
            })
        .toList();

    final article = await articleProv.generateArticle(vocabList);

    if (article != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文章「${article.title}」已生成')),
      );
    } else if (mounted && articleProv.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(articleProv.error!)),
      );
    }
  }

  void _confirmDelete(Article article) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文章'),
        content: Text('确定删除「${article.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<ArticleProvider>().deleteArticle(article.id!);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
