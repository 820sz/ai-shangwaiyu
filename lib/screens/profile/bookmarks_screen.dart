import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/bookmark.dart';
import '../../providers/bookmark_provider.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/confirm_destructive.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';
// 复用追问气泡那套"克制的 Markdown 样式":正文一律 onSurface,
// 只有链接用主色,层级靠字重 —— 详见 calmMarkdownSheet 的注释。
import '../input/widgets/follow_up_bubble.dart' show calmMarkdownSheet;

/// 收藏夹页(v1.4.0 问题 9;v2.8 按功能区分类;v2.10 精美阅读页)。
///
/// 用户第 10 条原话:"收藏夹需要体现不同功能区收藏进来的东西 —— 比如:词汇收藏夹、
/// 对话收藏夹(追问抽屉里收藏的东西)、文章收藏夹、写译收藏夹(收藏的错误呀这些)…
/// 需要智能的把各个功能区的收藏功能,进行归类处理以及对应的展示。"
///
/// 用户第 7 条(v2.10,2026-10-04)原话:"'收藏夹'功能里收藏的内容,需**增加精美的
/// 阅读界面**,现在的太简陋了,而且**有一堆 ai 符号残留**。"
/// 两件事都落在这里:
/// 1. 详情从 `AlertDialog + SelectableText` 换成全屏阅读页 [BookmarkReaderScreen]
///    (选全屏页而不是 90% 高的底部弹层,理由见该类的注释);
/// 2. 正文**先清洗再渲染**(`cleanMarkdownForDisplay`),把裸奔的 `**` / `##` / `- `
///    变成真正的粗体 / 标题 / 列表 —— 见该函数的规则注释。
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  /// 当前分区(null = 全部)
  String? _section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏夹')),
      body: Consumer<BookmarkProvider>(
        builder: (context, bp, _) => AnimatedSwitcher(
          // A1:加载/失败/空/列表之间的切换给 180ms easeOut,
          // 不再硬切(高频操作不加动画,这里是低频的状态切换)
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          child: _buildBody(context, bp),
        ),
      ),
    );
  }

  /// 某分区有多少条(用于 chip 上的计数)
  int _countOf(BookmarkProvider bp, String id) =>
      bp.items.where((b) => b.source == id).length;

  /// 三态(P2-30):加载中 / 加载失败可重试 / 空态与列表。
  /// 空态与失败态此前长得一样(都是"没有内容"),用户分不清是没收藏还是坏了。
  Widget _buildBody(BuildContext context, BookmarkProvider bp) {
    if (bp.error != null && !bp.loaded) {
      // 只有"失败且手里没数据"才整页报错;有数据时的刷新失败不该清屏
      return ErrorState(
        key: const ValueKey('bookmarks-error'),
        message: bp.error!,
        onRetry: () => context.read<BookmarkProvider>().load(),
      );
    }
    if (!bp.loaded) {
      // v2.10:这里原来是 `CircularProgressIndicator` —— 全项目已经统一
      // 改成骨架屏/时间线/进度条(用户明确要求过"不要再转圈"),这处是漏网的。
      return const Padding(
        key: ValueKey('bookmarks-loading'),
        padding: Insets.page,
        child: AppLoading(label: '正在读取收藏…'),
      );
    }
    if (bp.items.isEmpty) {
      return const EmptyState(
        key: ValueKey('bookmarks-empty'),
        icon: Icons.star_border,
        title: '还没有收藏',
        hint: '在追问回答顶部、词条卡片、阅读器里点 ☆ 即可收藏,会自动归到对应分区',
      );
    }

    final items = _section == null
        ? bp.items
        : bp.items.where((b) => b.source == _section).toList();

    return Column(
      key: const ValueKey('bookmarks-list'),
      children: [
        // ① 分区 chips(用户第 10 条的核心)
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              _sectionChip(
                context,
                label: '全部',
                count: bp.items.length,
                selected: _section == null,
                onTap: () => setState(() => _section = null),
              ),
              for (final s in AppConstants.bookmarkSections)
                _sectionChip(
                  context,
                  label: s['label']!,
                  count: _countOf(bp, s['id']!),
                  selected: _section == s['id'],
                  onTap: () => setState(() => _section = s['id']),
                ),
            ],
          ),
        ),
        // ② 当前分区的说明(告诉用户"这类是从哪儿收藏来的")
        if (_section != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppConstants.bookmarkSections
                        .firstWhere((s) => s['id'] == _section)['hint'] ??
                    '',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: '这个分区还没有收藏',
                  hint: '换个分区看看,或去对应功能区点 ☆',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _BookmarkCard(bookmark: items[i]),
                ),
        ),
      ],
    );
  }

  Widget _sectionChip(
    BuildContext context, {
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(count > 0 ? '$label $count' : label),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        labelStyle: TextStyle(
          fontSize: 12,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 来源徽标(列表与阅读页共用一份,避免两处颜色/图标不一致)
// ─────────────────────────────────────────────────────────────

/// 某个收藏来源的徽标样式:标签 / 图标 / 颜色。
///
/// 四个来源的口径沿用 [AppConstants.bookmarkSections](词汇/对话/文章/写译),
/// 颜色全部取自主题与语义色 —— 写死的颜色在深色下会偏暗或刺眼(见 AppTheme 注释)。
({String label, IconData icon, Color color}) bookmarkSourceStyle(
  BuildContext context,
  String source,
) {
  final theme = Theme.of(context);
  return switch (source) {
    AppConstants.bookmarkSourceVocab => (
        label: '词汇',
        icon: Icons.bookmark,
        color: theme.colorScheme.tertiary,
      ),
    AppConstants.bookmarkSourceArticle => (
        label: '文章',
        icon: Icons.article_outlined,
        color: AppTheme.successColor(context),
      ),
    AppConstants.bookmarkSourceWriting => (
        label: '写译',
        icon: Icons.edit_note,
        color: AppTheme.amber(context),
      ),
    _ => (
        label: '对话',
        icon: Icons.chat_bubble_outline,
        color: theme.colorScheme.primary,
      ),
  };
}

// ─────────────────────────────────────────────────────────────
// 正文清洗(纯函数:可单测,也是"AI 符号残留"的正经修法)
// ─────────────────────────────────────────────────────────────

/// 把收藏正文里的"AI 残留符号"清洗成可渲染的 Markdown。
///
/// 为什么需要它:收藏内容来自 AI 回答,里面全是 Markdown 标记;而 v2.10 之前详情页用
/// `SelectableText` 直接显示原文 —— **Text 不渲染 Markdown**,于是用户看到的是
/// 字面的 `**重点**`、`## 标题`、`- 列表`,也就是他说的"一堆 ai 符号残留"。
/// 现在的做法是"先清洗、再交给 flutter_markdown 渲染",清洗只做**有把握**的事。
///
/// 规则(逐条都有测试钉住,见 `test/bookmark_view_test.dart`):
/// 1. 统一换行:`\r\n` / `\r` → `\n`;
/// 2. 全角符号转半角:`＊`→`*`、`＃`→`#`(手机输入法/AI 输出都可能给出全角);
/// 3. 去掉行尾空白(含全角空格)—— 行尾空格在 Markdown 里是"硬换行",会凭空多出断行;
/// 4. 行首裸项目符号 `• ● ▪ · ‧` → `- `(CommonMark 不认这些字符,
///    不清的话用户看到的就是一个个孤零零的圆点);
/// 5. 补结构:列表项/标题/引用紧跟在正文行后面时,中间补一个空行,
///    让 Markdown 正确进入块级(否则有序列表会被当成上一段的一部分);
/// 6. 未闭合的 `**`:一行里 `**` 出现奇数次,说明有一半没配对,删掉最后一个
///    (就是那个"半截加粗",渲染出来是一串字面星号);
/// 7. 去掉 AI 开场客套("好的,以下是…"/"当然可以!"),最多两行;
/// 8. 去掉结尾客套("希望对你有所帮助"/"如果还有疑问,随时问我"),最多两行;
/// 9. 连续空行最多留一个(否则正文里全是空档);
/// 10. 兜底:清洗后为空而原文非空 → 返回原文(宁可显示原文,也不能给用户一片空白)。
///
/// **不碰的东西**:代码围栏(``` / ~~~)内部的行一个字符都不改 ——
/// 那是代码,补空行/删星号都会毁掉它;以及所有成对闭合的 Markdown 结构。
String cleanMarkdownForDisplay(String raw) {
  final source = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (source.trim().isEmpty) return '';

  final srcLines = source.split('\n');

  // 先标出代码围栏内的行(含围栏行本身):这些行原样保留
  final verbatim = List<bool>.filled(srcLines.length, false);
  var inFence = false;
  for (var i = 0; i < srcLines.length; i++) {
    final t = srcLines[i].trimLeft();
    if (t.startsWith('```') || t.startsWith('~~~')) {
      verbatim[i] = true;
      inFence = !inFence;
    } else {
      verbatim[i] = inFence;
    }
  }

  final out = <String>[];
  for (var i = 0; i < srcLines.length; i++) {
    if (verbatim[i]) {
      out.add(srcLines[i]);
      continue;
    }
    var line = srcLines[i]
        .replaceAll('\uFF0A', '*') // ＊
        .replaceAll('\uFF03', '#') // ＃
        .replaceAll(RegExp(r'[ \t\u3000]+$'), '');
    // 行首项目符号统一。
    // 注意:必须用 replaceFirstMapped —— `replaceFirst` 的替换串**不解释 $1**,
    // 写成 `replaceFirst(re, r'$1- ')` 会把缩进替换成字面的 "$1- "
    line = line.replaceFirstMapped(
      RegExp(r'^(\s*)[•●▪·‧]\s*'),
      (m) => '${m[1]}- ',
    );
    // 半截加粗
    line = _dropUnclosedBold(line);
    // 结构修复:块级元素紧跟在正文行后面时补空行
    if (_startsBlock(line) &&
        out.isNotEmpty &&
        out.last.trim().isNotEmpty &&
        !_startsBlock(out.last)) {
      out.add('');
    }
    out.add(line);
  }

  // 去掉开头客套(最多两行;删完不能什么都不剩)
  var start = 0;
  while (start < out.length && out[start].trim().isEmpty) {
    start++;
  }
  var dropped = 0;
  while (start < out.length && dropped < 2 && _isAiPreamble(out[start].trim())) {
    start++;
    dropped++;
    while (start < out.length && out[start].trim().isEmpty) {
      start++;
    }
  }
  if (start >= out.length) start = 0;

  // 去掉结尾客套(最多两行)
  var end = out.length;
  while (end > start && out[end - 1].trim().isEmpty) {
    end--;
  }
  dropped = 0;
  while (end > start && dropped < 2 && _isAiCloser(out[end - 1].trim())) {
    end--;
    dropped++;
    while (end > start && out[end - 1].trim().isEmpty) {
      end--;
    }
  }
  if (end <= start) end = out.length;

  var text = out.sublist(start, end).join('\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (text.isEmpty) {
    // 清洗把内容吃光了 —— 回到原文(只去首尾空白),总比给用户一片空白好
    return source.trim();
  }
  return text;
}

/// 一行里 `**` 出现奇数次 = 有一半没配对,删掉最后一个
String _dropUnclosedBold(String line) {
  final hits = RegExp(r'\*\*').allMatches(line).toList();
  if (hits.isEmpty || hits.length.isEven) return line;
  final last = hits.last;
  return line.replaceRange(last.start, last.end, '');
}

/// 这一行是不是"块级元素"的开头(列表 / 标题 / 引用 / 围栏 / 分隔线)
bool _startsBlock(String line) {
  final t = line.trimLeft();
  if (t.isEmpty) return false;
  if (t.startsWith('```') || t.startsWith('~~~')) return true;
  if (RegExp(r'^#{1,6}\s').hasMatch(t)) return true;
  if (RegExp(r'^>\s?').hasMatch(t)) return true;
  if (RegExp(r'^[-*+]\s').hasMatch(t)) return true;
  if (RegExp(r'^\d{1,3}[.)]\s').hasMatch(t)) return true;
  if (RegExp(r'^([-*_])\s*\1\s*\1').hasMatch(t)) return true;
  return false;
}

/// AI 开场客套:只有**明确模式**才算,拿不准就留着 ——
/// 删错一句正文,比留下一句客套严重得多。
///
/// 两类模式:
/// 1. 整行就是一句应答("好的!"/"当然可以"/"OK~")—— 要求**整行**只有客套词,
///    于是"当然,语言学习需要时间。"这种正常句子不会被误删;
/// 2. 含明确引导语的行("以下是…"/"我来帮你分析…")。
final RegExp _preambleSolo = RegExp(
  r'^(好的|好嘞|好的呀|当然|当然可以|没问题|收到|明白了|了解了|了解|OK|Ok|ok)'
  r'[,，。.!！~、:：\s]*$',
);
final RegExp _preambleCue = RegExp(
  r'(以下是|下面是|如下是|以下为|如下所示|以下内容|下面为你|为你整理|我来帮你|我来为你|帮你分析)',
);

bool _isAiPreamble(String line) {
  if (line.isEmpty || line.length > 30) return false;
  if (_preambleSolo.hasMatch(line)) return true;
  return _preambleCue.hasMatch(line);
}

/// AI 结尾客套。
///
/// 每条都**锚定整行**(`^…$`):正文里出现"希望对你有帮助"这几个字
/// (比如"希望对你有所帮助这句话是 AI 的口头禅。")不该被当成客套删掉。
final List<RegExp> _closerPatterns = [
  // "希望对你有所帮助 / 希望这些对你有用 / 希望本文能帮到你" ——
  // 注意 "有所帮助" 是最常见的一种:旧的 "有帮助" 匹配不到它(中间多了个"所"),
  // 所以这里把 有所/能/可以 这些中间词一起写进备选。
  RegExp(r'^希望[^。!！\n]{0,16}(有帮助|有所帮助|帮到你|能帮到|对你有用|有用|有收获)[。.!！~]?$'),
  RegExp(r'^如果(还)?有(任何|其他|别的)?(疑问|问题|需要)[^。!！\n]{0,10}[。.!！~]?$'),
  RegExp(r'^还有(什么|其他|别的)?(疑问|问题|需要)[^。!！\n]{0,10}[。.!！~]?$'),
  RegExp(r'^祝(你|您)?(学习|阅读|复习)?(愉快|顺利|进步|加油)[。.!！~]?$'),
  RegExp(r'^随时(可以)?(问我|提问|找我|交流)[。.!！~]?$'),
  RegExp(r'^(能)?(对你)?(有帮助|有所帮助|帮到你)[。.!！~]?$'),
];

bool _isAiCloser(String line) {
  if (line.isEmpty || line.length > 40) return false;
  return _closerPatterns.any((p) => p.hasMatch(line));
}

/// 阅读页信息条上的"字数":中文按字、英文按词。
/// (英语材料按"字"报数会虚高 —— 一句 10 个词的英文报成 60 字,用户会觉得莫名其妙)
String bookmarkLengthLabel(String text) {
  final t = text.trim();
  if (t.isEmpty) return '没有正文';
  final cjk = RegExp(r'[\u4e00-\u9fff\u3040-\u30ff]').allMatches(t).length;
  final words = RegExp(r"[A-Za-z][A-Za-z'’\-]*").allMatches(t).length;
  if (cjk == 0 && words == 0) {
    return '${t.replaceAll(RegExp(r'\s'), '').length} 字';
  }
  return cjk >= words ? '$cjk 字' : '$words 词';
}

// ─────────────────────────────────────────────────────────────
// 阅读页
// ─────────────────────────────────────────────────────────────

/// 收藏的**阅读页**(v2.10,用户第 7 条)。
///
/// 为什么选全屏页、而不是 90% 高的 `showModalBottomSheet`:
/// 1. 阅读是**长时间停留**的场景,底部弹层随时可能被误下滑关掉,阅读位置就丢了
///    (全屏页有系统返回手势 + 状态保留,更接近"在读书");
/// 2. 长文 + `SelectionArea` 长按选择时,弹层的拖拽手势会和选择手势打架;
/// 3. 全屏页能挂 AppBar(标题=来源)与固定的底部动作条,信息层次比弹层清楚。
class BookmarkReaderScreen extends StatelessWidget {
  final Bookmark bookmark;

  const BookmarkReaderScreen({super.key, required this.bookmark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bookmarkSourceStyle(context, bookmark.source);
    final body = cleanMarkdownForDisplay(bookmark.content);

    return Scaffold(
      appBar: AppBar(title: Text('${style.label}收藏')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _header(context, style),
            Expanded(
              child: body.isEmpty
                  // 兜底:空内容/全是空白不能给用户一块白板
                  ? const Center(
                      child: AppEmpty(
                        icon: Icons.notes,
                        title: '这条收藏没有正文',
                        hint: '内容可能在收藏时就没抓到,可以删掉这条重新收藏一次',
                      ),
                    )
                  : SelectionArea(
                      // 长按选中 = 系统默认菜单(复制/全选);README 规则见
                      // follow_up_bubble 的同类注释:不覆盖默认项,于是
                      // "选中哪段复制哪段"仍然是系统行为
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.lg),
                        child: MarkdownBody(
                          data: body,
                          selectable: true,
                          styleSheet: readerMarkdownSheet(theme),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _actions(context),
    );
  }

  /// 顶部信息卡:来源徽标 + 标题 + 收藏时间 + 字数(+ 模型 / 原词)
  Widget _header(
    BuildContext context,
    ({String label, IconData icon, Color color}) style,
  ) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final meta = <String>[
      bookmarkLengthLabel(bookmark.content),
      if ((bookmark.sourceWord ?? '').trim().isNotEmpty)
        '原词 ${bookmark.sourceWord!.trim()}',
      if ((bookmark.model ?? '').trim().isNotEmpty) bookmark.model!.trim(),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.xs),
      child: AppCard(
        margin: EdgeInsets.zero,
        color: style.color.withAlpha(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 来源徽标:四个功能区各有图标与颜色(与列表口径一致)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: style.color.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(style.icon, size: 13, color: style.color),
                      const SizedBox(width: 4),
                      Text(
                        style.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: style.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTime(bookmark.createdAt),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
            const SizedBox(height: Gap.xs),
            Text(
              bookmark.title.trim().isEmpty ? '(无标题)' : bookmark.title.trim(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              meta.join(' · '),
              style: TextStyle(fontSize: 11, color: muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部动作:复制全文 / 删除(带确认)/ 关闭
  Widget _actions(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.sm),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy_all_outlined, size: 16),
                  label: const Text('复制全文'),
                ),
              ),
              const SizedBox(width: Gap.xs),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  side: BorderSide(color: theme.colorScheme.error.withAlpha(120)),
                ),
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除'),
              ),
              const SizedBox(width: Gap.xxs),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 复制**清洗后**的正文(用户看到的就是清洗后的,复制的也该是它)
  void _copy(BuildContext context) {
    final clean = cleanMarkdownForDisplay(bookmark.content);
    Clipboard.setData(
      ClipboardData(text: clean.isEmpty ? bookmark.content : clean),
    );
    showFeedbackSnack(context, '已复制全文');
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final id = bookmark.id;
    if (id == null) {
      showFeedbackSnack(context, '这条收藏缺少记录,无法删除');
      return;
    }
    // 先抓住 messenger:阅读页 pop 掉之后 context 就失效了,
    // 但"已删除 + 撤销"这条反馈必须留在**列表页**上面(与列表页删除体验一致)
    final messenger = ScaffoldMessenger.of(context);
    final bp = context.read<BookmarkProvider>();
    // 删之前先记一下"这条在不在缓存里":BookmarkProvider.remove 内部吞异常,
    // 不回头核对就会变成"提示删了、其实还在、页面还退了"的假成功。
    // (只在缓存里真有它的时候才核对得出来 —— 列表没加载过就只能按成功处理,
    //  与列表页的删除行为保持一致。)
    final wasListed = bp.items.any((b) => b.id == id);
    final ok = await confirmDestructive(
      context,
      title: '删除收藏',
      message: '确定删除「${bookmark.title}」吗?删除后不可恢复。',
    );
    if (!ok || !context.mounted) return;
    await bp.remove(id);
    if (!context.mounted) return;
    if (wasListed && bp.items.any((b) => b.id == id)) {
      showFeedbackSnack(context, '删除失败,请稍后重试');
      return;
    }
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('已删除收藏'),
          behavior: SnackBarBehavior.floating,
          // 撤销要留够反应时间(默认 3 秒太快)
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '撤销',
            // 撤销 = 重新插入同一条(内容已删,toggle 这次一定是"收藏")
            onPressed: () => bp.toggle(bookmark),
          ),
        ),
      );
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// 阅读页的 Markdown 样式 = [calmMarkdownSheet] 的**少量扩展**。
///
/// 配色规则一条不改(正文一律 onSurface、只有链接用主色、层级靠字重)——
/// v2.8 用户抱怨过"一段话 4 种颜色",不能为了"精美"把老毛病请回来。
/// 扩展的只有"读长文"需要的三件事:字号提到 15、**行高 1.72**、段落间距 12。
MarkdownStyleSheet readerMarkdownSheet(ThemeData theme) {
  final base = calmMarkdownSheet(theme);
  final cs = theme.colorScheme;
  final body = (base.p ?? theme.textTheme.bodyMedium ?? const TextStyle())
      .copyWith(fontSize: 15, height: 1.72, color: cs.onSurface);
  TextStyle head(TextStyle? src, double size) => (src ?? body).copyWith(
        fontSize: size,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      );
  return base.copyWith(
    p: body,
    blockSpacing: Gap.sm,
    listBullet: body,
    h1: head(base.h1, 21),
    h2: head(base.h2, 18),
    h3: head(base.h3, 16),
    h4: head(base.h4, 15.5),
    h5: head(base.h5, 15),
    h6: head(base.h6, 15),
    blockquote: (base.blockquote ?? body).copyWith(fontSize: 14.5, height: 1.7),
    blockquotePadding: const EdgeInsets.fromLTRB(Gap.sm, Gap.xs, Gap.sm, Gap.xs),
    code: (base.code ?? const TextStyle()).copyWith(fontSize: 13),
    tableHead: (base.tableHead ?? body).copyWith(fontSize: 13),
    tableBody: (base.tableBody ?? body).copyWith(fontSize: 13, height: 1.6),
  );
}

// ─────────────────────────────────────────────────────────────
// 列表卡片
// ─────────────────────────────────────────────────────────────

class _BookmarkCard extends StatelessWidget {
  final Bookmark bookmark;

  const _BookmarkCard({required this.bookmark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bookmarkSourceStyle(context, bookmark.source);
    // 列表预览也过一遍清洗:上一版预览里 `**` `##` 一样裸奔。
    // 只取前 400 字再清洗,长文列表不会因为预览做全量清洗而卡顿。
    final head = bookmark.content.characters.take(400).toString();
    final preview = cleanMarkdownForDisplay(head)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return Card(
      color: theme.colorScheme.surface,
      child: InkWell(
        borderRadius: Radii.cardRadius,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BookmarkReaderScreen(bookmark: bookmark),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(style.icon, size: 18, color: style.color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookmark.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${style.label} · '
                      '${bookmark.createdAt.year}-'
                      '${bookmark.createdAt.month.toString().padLeft(2, '0')}-'
                      '${bookmark.createdAt.day.toString().padLeft(2, '0')}',
                      // P2-31:次要文字对比度不足 → 用主题的次要文字色(深浅色都达 AA)
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview.length > 80
                          ? '${preview.substring(0, 80)}…'
                          : preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                tooltip: '删除收藏',
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 删除收藏(P2-28):此前这个图标一点就直接从库里删掉,
  /// 无确认、无提示、不可撤销 —— 与"生词批量删除有确认"完全是两套预期。
  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await confirmDestructive(
      context,
      title: '删除收藏',
      message: '确定删除「${bookmark.title}」吗？删除后不可恢复。',
    );
    if (!ok || !context.mounted) return;
    final id = bookmark.id;
    if (id == null) return;
    final bp = context.read<BookmarkProvider>();
    await bp.remove(id);
    if (!context.mounted) return;
    showFeedbackSnack(
      context,
      '已删除收藏',
      actionLabel: '撤销',
      // 撤销要留够反应时间,3 秒太快(默认值给普通提示用)
      duration: const Duration(seconds: 6),
      // 撤销 = 重新插入同一条(内容已被删掉,toggle 这次一定是"收藏")
      onAction: () => bp.toggle(bookmark),
    );
  }
}
