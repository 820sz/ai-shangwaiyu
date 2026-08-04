import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/article.dart';
import '../../providers/article_provider.dart';
import 'exercise_screen.dart';

class ArticleReaderScreen extends StatefulWidget {
  final Article article;

  const ArticleReaderScreen({super.key, required this.article});

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  bool _showTranslation = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final article = widget.article;
    final provider = context.watch<ArticleProvider>();

    final exercises = article.id != null
        ? provider.exercisesByArticle[article.id] ?? []
        : <dynamic>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(article.title),
        actions: [
          TextButton(
            onPressed: () {
              if (article.translation == null ||
                  article.translation!.isEmpty) {
                // 旧文章无翻译数据(DB v5 之前的文章)——提示而不是无反应
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('该文章暂无中文翻译，可删除后重新生成'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              setState(() => _showTranslation = !_showTranslation);
            },
            child: Text(_showTranslation ? '隐藏翻译' : '显示翻译'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 元信息
          Row(
            children: [
              Icon(Icons.bookmark_outline, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text('包含 ${article.vocabCount} 个生词',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              const SizedBox(width: 16),
              Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                  '${article.createdAt.month}月${article.createdAt.day}日',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            ],
          ),
          const SizedBox(height: 20),

          // 文章内容(显示翻译时英文段下方对照渲染对应中文段,段落索引对齐)
          ...article.paragraphs.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.8,
                        fontSize: 16,
                      ),
                    ),
                    if (_showTranslation &&
                        e.key < article.translationParagraphs.length)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          article.translationParagraphs[e.key],
                          style: TextStyle(
                            height: 1.8,
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                  ],
                ),
              )),

          const SizedBox(height: 24),

          // 练习区
          if (exercises.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 12),
            Text('回译练习',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...exercises.map((ex) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: ex.score != null
                          ? (ex.score! >= 60
                              ? Colors.green[100]
                              : Colors.orange[100])
                          : Colors.grey[100],
                      child: Text(
                        ex.score != null ? '${ex.score!.toInt()}%' : '—',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ex.score != null
                              ? (ex.score! >= 60 ? Colors.green : Colors.orange)
                              : Colors.grey,
                        ),
                      ),
                    ),
                    title: Text('练习 ${exercises.indexOf(ex) + 1}',
                        style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      '${ex.createdAt.month}月${ex.createdAt.day}日 · ${ex.sourceSentences.length} 个句子',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExerciseScreen(exercise: ex),
                        ),
                      );
                    },
                  ),
                )),
          ],

          const SizedBox(height: 16),

          // 生成失败/提示信息(此前失败完全无反馈,用户以为一直在生成)
          if (provider.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                provider.error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ),

          // 生成新练习
          if (provider.generating)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final ex = await provider.generateExercise(article);
                  if (ex != null && mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExerciseScreen(exercise: ex),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.fitness_center),
                label: const Text('生成回译练习'),
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
