import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// 分享通道:与 MainActivity.kt 的 app/share_text 对应
  static const MethodChannel _shareChannel = MethodChannel('app/share_text');

  /// 复制全文翻译到剪贴板(内置 API,零依赖)
  Future<void> _copyTranslation(Article article) async {
    final text = article.translation ?? '';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('全文翻译已复制(${text.length} 字),可到微信/备忘录粘贴'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 保存出口:调系统分享面板,可存到微信/备忘录/文件管理器
  Future<void> _shareTranslation(Article article) async {
    try {
      await _shareChannel.invokeMethod('shareText', {
        'text': article.translation ?? '',
        'title': article.title,
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打开分享面板失败:${e.message}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final article = widget.article;
    final provider = context.watch<ArticleProvider>();

    final exercises = article.id != null
        ? provider.exercisesByArticle[article.id] ?? []
        : <dynamic>[];

    // 全文翻译存在时才显示"复制/保存"菜单(旧文章无翻译数据)
    final hasTranslation =
        article.translation != null && article.translation!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(article.title),
        actions: [
          TextButton(
            onPressed: () {
              if (!hasTranslation) {
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
          if (hasTranslation)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: '翻译操作',
              onSelected: (value) {
                switch (value) {
                  case 'copy':
                    _copyTranslation(article);
                  case 'share':
                    _shareTranslation(article);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'copy',
                  child: Row(
                    children: [
                      Icon(Icons.copy_all,
                          size: 18, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      const Text('复制全文翻译'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.save_alt,
                          size: 18, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      const Text('保存/分享翻译'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 元信息
          Row(
            children: [
              Icon(Icons.bookmark_outline,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('包含 ${article.vocabCount} 个生词',
                  // P2-31:正文灰阶对比度不够,这里用主题的次要文字色(深浅色都达 AA)
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13)),
              const SizedBox(width: 16),
              Icon(Icons.calendar_today,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                  '${article.createdAt.month}月${article.createdAt.day}日',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13)),
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
                            color: theme.colorScheme.onSurfaceVariant,
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
                      // 成绩徽章的底色也用半透明色相:浅色下≈green[100]/orange[100],
                      // 深色下不会变成一圈亮白
                      backgroundColor: ex.score != null
                          ? (ex.score! >= 60
                              ? Colors.green.withAlpha(60)
                              : Colors.orange.withAlpha(60))
                          : theme.colorScheme.surfaceContainerHighest,
                      child: Text(
                        ex.score != null ? '${ex.score!.toInt()}%' : '—',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ex.score != null
                              ? (ex.score! >= 60 ? Colors.green : Colors.orange)
                              : theme.colorScheme.onSurfaceVariant,
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
