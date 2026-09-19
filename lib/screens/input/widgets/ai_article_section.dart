import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/article.dart';
import '../../../providers/article_provider.dart';
import '../../../providers/vocab_provider.dart';
import '../../output/article_reader.dart';

/// 特色功能 · AI 生词定制文章(v1.8.0:从「输出」页迁到「输入」页)。
///
/// 用生词本里的词现写一篇文章,读它 = 在语境里复习自己的生词。
class AiArticleSection extends StatefulWidget {
  const AiArticleSection({super.key});

  @override
  State<AiArticleSection> createState() => _AiArticleSectionState();
}

class _AiArticleSectionState extends State<AiArticleSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ArticleProvider>().loadArticles();
    });
  }

  Future<void> _generate() async {
    final vocab = context.read<VocabProvider>();
    final articleProv = context.read<ArticleProvider>();

    await vocab.loadVocabularies();
    final candidates = vocab.vocabularies
        .where((v) => v.masteryLevel != 2)
        .take(20)
        .toList();

    if (candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('还没有足够的生词，先去拍几张照片取词吧')),
        );
      }
      return;
    }

    final article = await articleProv.generateArticle(
      candidates
          .map(
            (v) => {
              'id': v.id?.toString() ?? '',
              'word': v.word,
              'translation': v.translation ?? '',
            },
          )
          .toList(),
    );

    if (!mounted) return;
    if (article != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成《${article.title}》')),
      );
    } else if (articleProv.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(articleProv.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final articleProv = context.watch<ArticleProvider>();
    final articles = articleProv.articles;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: Icon(Icons.auto_stories, color: theme.colorScheme.primary),
        title: Text(
          '特色功能 · AI 生词定制文章',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          articles.isEmpty ? '用你的生词现写一篇' : '已有 ${articles.length} 篇',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: articleProv.generating ? null : _generate,
              icon: articleProv.generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(articleProv.generating ? 'AI 正在写…' : '生成文章'),
            ),
          ),
          if (articles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '生成的文章会出现在这里，点开可精读',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            )
          else
            ...articles.take(10).map((a) => _articleTile(theme, a)),
        ],
      ),
    );
  }

  Widget _articleTile(ThemeData theme, Article a) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.article_outlined,
        size: 20,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        a.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${a.vocabCount} 生词 · ${a.createdAt.month}/${a.createdAt.day}',
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      ),
      trailing: IconButton(
        tooltip: '删除',
        icon: const Icon(Icons.delete_outline, size: 16),
        onPressed: () => _confirmDelete(a),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ArticleReaderScreen(article: a)),
        ).then((_) => context.read<ArticleProvider>().loadArticles());
      },
    );
  }

  void _confirmDelete(Article a) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文章'),
        content: Text('确定删除《${a.title}》吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<ArticleProvider>().deleteArticle(a.id!);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
