/// 书架页(v2.10,用户 10/4 第 4、5 条)。
///
/// 用户原话:
/// - "材料中心的文章,应增加一个'书架'功能 …… 在文章内部增加一个 ui 即加入书架 ——
///   在退出材料中心里的文章时,发出提问'放进书架?'";
/// - "书架的 ui 展示要丰富,最好真的像一个书架,一架的书,等待用户放满"。
///
/// ## 本页负责什么(以及不负责什么)
/// - **负责**:读 `DatabaseService.bookshelfItems()` → 交给 [BookshelfView] 画成
///   真书架;点书进阅读器;长按弹层(打开 / 查看封面 / 标记读完 / 移出书架);
///   右上角"排列";中文标题补齐。
/// - **不负责**:**在阅读器里加"加入书架"按钮、退出时问"放进书架?"** —— 那是
///   阅读器(由 Lead 接)的事;本页只管"书架本身长什么样、怎么用"。
///
/// ## 为什么点书 = 直接打开阅读器(而不是"先高亮再点开")
/// 用户拿起一本书的动作只有一种意图:**继续读它**。做成"第一次点只选中、第二次点
/// 才打开"会白吃一次点击(手机上尤其烦),而且书架页本身没有"批量操作"的需求,
/// 选中态无处可去。所以:点 = 打开(同时书脊会亮一下、顶部提示条显示这本书的
/// 进度,作为"就是这本"的即时反馈);要看详情/移出书架走**长按**。
library;

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../services/bookshelf.dart';
import '../../services/database.dart';
import '../../services/deepseek_api.dart';
import '../../services/material_library.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/bookshelf_view.dart';
import '../../widgets/material_cover.dart';
import '../../widgets/waiting.dart';
import 'material_center_screen.dart';
import 'material_reader_screen.dart';

/// 排列方式(书架右上角"排列")
enum BookshelfSort {
  /// 最近读过的排前面(默认):找回"上次读到哪本"最快
  recent('最近阅读'),

  /// 新放上来的排前面:刚加完书就能看到它
  added('加入时间'),

  /// 进度高的排前面
  progress('阅读进度');

  final String label;
  const BookshelfSort(this.label);
}

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  List<BookshelfBook> _books = const [];
  bool _loading = true;
  String? _error;
  BookshelfSort _sort = BookshelfSort.recent;

  /// 已经试过补译名的材料 id:避免"翻不出来 → 每次进来都再翻一次"
  final Set<int> _titleTried = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 读书架数据。
  ///
  /// [showSkeleton] 只在**首屏**为 true:补译名、从阅读器返回、下拉刷新都在
  /// "用户已经看得见书架"的时候发生 —— 那会儿如果整屏换成骨架屏,书会凭空消失
  /// 一下再出现(比不刷新还烦),所以那几种情况只静默换数据。
  Future<void> _load({bool showSkeleton = true}) async {
    if (showSkeleton) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await DatabaseService.bookshelfItems();
      final books = rows.map(BookshelfBook.fromRow).toList();
      if (!mounted) return;
      setState(() {
        _books = books;
        _loading = false;
        _error = null;
      });
      _fillChineseTitles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 首次加载失败要整屏报错 + 重试;后续刷新失败保留旧数据(书架还在)
        _error = showSkeleton ? '$e' : null;
      });
      if (!showSkeleton) _toast('书架刷新失败,显示的还是刚才的数据');
    }
  }

  /// 补齐中文标题(用户为"标题必须是中文"发过两次火)。
  ///
  /// 为什么在书架页也要补:早期的材料行 `title_cn` 是空的,用户看到的会是英文标题;
  /// 这里在**后台**补几条(一次最多 4 条,合并成一次请求,不阻塞界面),
  /// 补到就写回 `materials.title_cn`(数据层的既定口径,全 App 读同一份)。
  /// 翻不出来(没配 API / 网络不通)**静默跳过**:界面已经有原文标题兜底,
  /// 这里再弹一次错误提示反而更烦。
  Future<void> _fillChineseTitles() async {
    try {
      final rows = await DatabaseService.materialsMissingTitleCn(limit: 4);
      if (rows.isEmpty) return;
      final targets = <int, String>{};
      for (final row in rows) {
        final id = row['id'];
        final title = row['title']?.toString().trim() ?? '';
        if (id is! int || title.isEmpty) continue;
        if (_titleTried.contains(id)) continue;
        targets[id] = title;
      }
      if (targets.isEmpty) return;
      if (!mounted) return;
      // DeepseekApiService 是**每次用新的**:它内部持有 Dio,没有需要保持的状态
      final translated = await DeepseekApiService()
          .translateTitles(targets.values.toList());
      if (translated.isEmpty) return;
      var changed = false;
      for (final entry in targets.entries) {
        _titleTried.add(entry.key); // 试过就记上,别每次进书架都重试同一批
        final cn = translated[entry.value]?.trim() ?? '';
        if (cn.isEmpty) continue;
        await DatabaseService.setMaterialTitleCn(entry.key, cn);
        changed = true;
      }
      if (changed && mounted) await _load(showSkeleton: false);
    } catch (_) {
      // 补译名是"锦上添花":失败不该影响书架本身,也不该打断用户
    }
  }

  /// 按 [BookshelfSort] 重排并落库(摆放顺序是用户资产的一部分,重排要持久)
  Future<void> _applySort(BookshelfSort sort) async {
    final list = [..._books];
    int byDate(DateTime? a, DateTime? b) {
      // 没有时间的排最后(而不是当成 1970 顶到最前面)
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    switch (sort) {
      case BookshelfSort.recent:
        list.sort((a, b) {
          final c = byDate(a.updatedAt, b.updatedAt);
          return c != 0 ? c : a.slot.compareTo(b.slot);
        });
      case BookshelfSort.added:
        list.sort((a, b) {
          final c = byDate(a.addedAt, b.addedAt);
          return c != 0 ? c : a.slot.compareTo(b.slot);
        });
      case BookshelfSort.progress:
        list.sort((a, b) {
          final c = b.percent.compareTo(a.percent);
          return c != 0 ? c : a.slot.compareTo(b.slot);
        });
    }

    setState(() {
      _sort = sort;
      _books = list;
    });
    await DatabaseService.setBookshelfOrder(
      [for (final b in list) b.materialId],
    );
  }

  Future<void> _openBook(BookshelfBook book) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialReaderScreen(materialId: book.materialId),
      ),
    );
    // 回到书架要刷新:用户在阅读器里可能"加入书架""移出书架",进度也变了。
    // 这里**不闪骨架屏** —— 他刚看完那本书,书架应该还在原地,只是进度变了。
    if (mounted) await _load(showSkeleton: false);
  }

  Future<void> _removeBook(BookshelfBook book) async {
    await DatabaseService.removeFromBookshelf(book.materialId);
    if (!mounted) return;
    setState(() {
      _books = [for (final b in _books) if (b.materialId != book.materialId) b];
    });
    _toast('已把《${book.title}》移出书架');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          if (!_loading && _error == null && _books.isNotEmpty)
            PopupMenuButton<BookshelfSort>(
              tooltip: '排列',
              icon: const Icon(Icons.swap_vert),
              initialValue: _sort,
              onSelected: _applySort,
              itemBuilder: (_) => [
                for (final s in BookshelfSort.values)
                  PopupMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Icon(
                          s == _sort
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: s == _sort
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: Gap.xs),
                        Text(s.label),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      // 用骨架屏而不是转圈(本项目已全面换掉转圈,见 widgets/waiting.dart)
      return ListView(
        padding: Insets.page,
        children: const [
          AppCard(child: SkeletonLines(lines: 3, seed: 0)),
          SizedBox(height: Gap.md),
          AppCard(child: SkeletonLines(lines: 5, seed: 1)),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        padding: Insets.page,
        children: [
          AppErrorCard(message: '书架没打开:$_error', onRetry: _load),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: Insets.page,
        children: [
          BookshelfView(
            books: _books,
            onTapBook: _openBook,
            onLongPressBook: _showBookSheet,
            emptyHint: '书架还是空的 —— 读到想留着的材料,在阅读器里点「加入书架」,它就摆上来了',
            emptyAction: FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MaterialCenterScreen()),
              ).then((_) {
                if (mounted) _load();
              }),
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: const Text('去材料中心挑一本'),
            ),
          ),
          const SizedBox(height: Gap.lg),
          if (_books.isNotEmpty)
            Text(
              '点一本书继续读,长按可以移出书架或看封面',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          const SizedBox(height: Gap.xl),
        ],
      ),
    );
  }

  /// 长按弹层:打开 / 查看封面 / 标记已读完 / 移出书架
  Future<void> _showBookSheet(BookshelfBook book) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _BookSheet(book: book),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        await _openBook(book);
      case 'cover':
        await _showCover(book);
      case 'finish':
        // 标记读完:进度直接写 100(数据层的语义就是"读完了")。
        //
        // 为什么用 upsertMaterialProgress 而不是新写一条 SQL:`material_progress`
        // 是阅读器/统计/导师共读的表,口径必须只有一处。这里的取舍写在明处 ——
        // `position` 会被写成 0(它只有必填参数,没办法"只改完成态")。
        // 代价:以后从这本的"继续阅读"进去会从头开始 —— 对一本**已经读完**的书,
        // 这个行为反而是可接受的;换来的是"读完"这个状态与全 App 一致。
        await DatabaseService.upsertMaterialProgress(
          book.materialId,
          position: 0,
          percent: 100,
          finished: true,
        );
        if (!mounted) return;
        await _load(showSkeleton: false);
        _toast('《${book.title}》标记为已读完');
      case 'remove':
        await _removeBook(book);
    }
  }

  /// 查看封面:书脊上看不到的东西(真封面、难度、词数、进度、笔记)都在这里
  Future<void> _showCover(BookshelfBook book) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _CoverSheet(book: book),
    );
  }
}

/// 长按弹层的**内容**(选项本身只是一列表)
///
/// 为什么不用系统 AlertDialog:这一屏是"实体书架"的隐喻,弹层却做成两块
/// 系统按钮会瞬间出戏;底部弹层 + 书脊色的小书图标更贴。
class _BookSheet extends StatelessWidget {
  final BookshelfBook book;

  const _BookSheet({required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final colors = spinePalette(book.title);
    final pct = book.percent.round();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
            child: Row(
              children: [
                // 一个小书脊色块:弹层与刚才长按的那本书对得上
                Container(
                  width: 14,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: colors,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (book.subtitle.isNotEmpty)
                        Text(
                          book.subtitle,
                          maxLines: 2,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 11, color: muted),
                        ),
                    ],
                  ),
                ),
                Text(
                  book.finished ? '已读完' : (pct <= 0 ? '未开始' : '$pct%'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: book.finished
                        ? AppTheme.successColor(context)
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _tile(context, 'open', Icons.menu_book_outlined, '打开阅读'),
          _tile(context, 'cover', Icons.image_outlined, '查看封面'),
          if (!book.finished)
            _tile(context, 'finish', Icons.check_circle_outline, '标记为已读完'),
          _tile(
            context,
            'remove',
            Icons.delete_outline,
            '移出书架',
            color: AppTheme.dangerColor(context),
          ),
          const SizedBox(height: Gap.xs),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, size: 20, color: color ?? theme.colorScheme.primary),
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(color: color),
      ),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

/// 查看封面:封面 + 元信息(词数 / 难度 / 时长 / 进度 / 笔记)
class _CoverSheet extends StatelessWidget {
  final BookshelfBook book;

  const _CoverSheet({required this.book});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final level = MaterialLevel.of(book.cefr, kind: book.kind);
    final pct = book.percent.round();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '封面',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Gap.sm),
            // 真封面(deeper 尺寸这里给足了:168 → 240,才看得出画面)
            MaterialCover(
              seed: book.title,
              kind: book.kind,
              width: double.infinity,
              height: 240,
              levelLabel: 'Lv$level',
            ),
            const SizedBox(height: Gap.sm),
            Text(
              book.title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
            ),
            if (book.subtitle.isNotEmpty) ...[
              const SizedBox(height: Gap.xxs),
              Text(
                book.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.xs,
              runSpacing: Gap.xxs,
              children: [
                _chip(context, MaterialLibrary.kindLabel(book.kind)),
                _chip(context, 'Lv$level'),
                if (book.wordCount > 0) _chip(context, '${book.wordCount} 词'),
                if (book.minutes > 0) _chip(context, '读了 ${book.minutes} 分钟'),
                _chip(
                  context,
                  book.finished ? '已读完' : (pct <= 0 ? '还没翻开' : '读到 $pct%'),
                  color: book.finished
                      ? AppTheme.successColor(context)
                      : theme.colorScheme.primary,
                ),
                if (book.pickedWords > 0)
                  _chip(context, '收了 ${book.pickedWords} 个词'),
              ],
            ),
            if (book.note.trim().isNotEmpty) ...[
              const SizedBox(height: Gap.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(140),
                  borderRadius: Radii.controlRadius,
                ),
                child: Text(
                  book.note.trim(),
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
            ],
            if (book.addedAt != null) ...[
              const SizedBox(height: Gap.xs),
              Text(
                '加入书架:${_dateLabel(book.addedAt!)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontSize: 11, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String text, {Color? color}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xs, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? theme.colorScheme.onSurface).withAlpha(18),
        borderRadius: BorderRadius.circular(Radii.control - 4),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 日期只显示"年月日":书架上不需要精确到秒
  static String _dateLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
