import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../config/constants.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../services/database.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/dash_kit.dart';
import '../../widgets/design_kit.dart';
import '../../widgets/error_state.dart';
import '../../widgets/graphics/graphics.dart';
import '../../widgets/v4/v4_kit.dart';
import '../../widgets/waiting.dart';
import '../writing/write_review_screen.dart';

/// 错误档案里 source 的中文名(用户不认识 'reading_quiz' 这类内部名)
const Map<String, String> _errorSourceLabels = {
  'writing': '写译批改',
  'exercise': '回译练习',
  'placement': '水平测试',
  'reading_quiz': '读后测验',
  'review': '复习',
  'output': '输出练习',
};

String _errorSourceLabel(String source) {
  final raw = source.trim();
  if (raw.isEmpty) return '其他';
  return _errorSourceLabels[raw] ?? raw;
}

/// 错误档案页(v2.1)。
///
/// 为什么要有这一页:`error_tags` 表从 v2.1 起就在累加(写译批改 / 读后测验 /
/// 回译练习 / 复习答"不认识"都会往里写),但用户此前看不到 —— 数据在涨,
/// 认知却停在"我英语不太好"。这一页要回答两个具体问题:
/// **我最常错什么**(tag + 次数)和**我修好了没**(active/fixed 两个页签)。
///
/// 这一页只做读取 + 一个状态位的写入(`setErrorTagStatus`),不新增 SQL。
class ErrorArchiveScreen extends StatefulWidget {
  const ErrorArchiveScreen({super.key});

  @override
  State<ErrorArchiveScreen> createState() => _ErrorArchiveScreenState();
}

class _ErrorArchiveScreenState extends State<ErrorArchiveScreen> {
  /// 本地记录"这条在什么时候被标过已改正"。
  ///
  /// 为什么需要:表里有 `status` 但没有 `fixed_at` ——
  /// `bumpErrorTag` 复发时会把 status 拉回 'active',于是"标过 fixed、
  /// 之后又错"这件事在库里查不出来(只剩 active,看不出是第一次错还是复发)。
  /// 加字段要动 database.dart(其它任务在写,本任务不动),所以这里用
  /// 应用自己发起的"标记已改正"时刻做对照:之后 last_at 又变晚 = 复发。
  /// 代价说清楚:只统计**本机标记过**的复发;从没标过 fixed 的条目无从判断。
  static const String _fixedAtKey = 'error_tag_fixed_at';

  bool _loading = true;
  String? _error;

  /// 页签:0 = 待处理(active),1 = 已改正(fixed)
  int _tab = 0;

  /// 来源筛选(null = 全部);v3 回流后同一 tag 会从多个来源写入,
  /// 按来源能看出"这类错是写译扣出来的还是测验收出来的"。
  String? _source;

  List<_ErrorTag> _active = const [];
  List<_ErrorTag> _fixed = const [];

  /// tag id → 上次标"已改正"的时刻(仅本机标记记录)
  Map<String, DateTime> _fixedAt = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        DatabaseService.getErrorTags(status: 'active'),
        DatabaseService.getErrorTags(status: 'fixed'),
      ]);
      if (!mounted) return;
      setState(() {
        _active = results[0].map(_ErrorTag.fromRow).toList();
        _fixed = results[1].map(_ErrorTag.fromRow).toList();
        _fixedAt = _readFixedAt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '读取错误档案失败:$e';
        _loading = false;
      });
    }
  }

  /// 读本机的"标记时刻"表(坏数据/未初始化一律当空,不影响主流程)
  Map<String, DateTime> _readFixedAt() {
    try {
      final raw = Hive.box(AppConstants.hiveBoxSettings).get(_fixedAtKey);
      if (raw is! Map) return const {};
      final out = <String, DateTime>{};
      raw.forEach((k, v) {
        final at = DateTime.tryParse('$v');
        if (at != null) out['$k'] = at;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _rememberFixed(int id) async {
    try {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      final raw = box.get(_fixedAtKey);
      final next = Map<String, String>.from(
        raw is Map
            ? Map<String, dynamic>.from(raw).map((k, v) => MapEntry(k, '$v'))
            : const <String, String>{},
      );
      next['$id'] = DateTime.now().toIso8601String();
      await box.put(_fixedAtKey, next);
    } catch (_) {
      // 记不上只是"下次不显示复发角标",不该拦住状态修改本身
    }
  }

  /// 改状态(唯一写操作)。[toFixed] true = 标记已改正,false = 恢复为待处理。
  Future<void> _setStatus(_ErrorTag t, {required bool toFixed}) async {
    final id = t.id;
    if (id == null) return;
    final rows = await DatabaseService.setErrorTagStatus(
      id,
      toFixed ? 'fixed' : 'active',
    );
    if (!mounted) return;
    if (rows <= 0) {
      // 0 行 = id 不存在或状态非法:必须明说,不能假装成功
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('修改失败:这条记录已不存在')),
      );
      await _load();
      return;
    }
    if (toFixed) {
      await _rememberFixed(id);
    } else {
      await _forgetFixedEntry(id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(toFixed ? '已标记「${t.tag}」为已改正' : '已恢复「${t.tag}」为待处理'),
        duration: const Duration(seconds: 2),
      ),
    );
    await _load();
  }

  /// 从本机记录里删掉一条(恢复为待处理时:下次再标才算新的起点)
  Future<void> _forgetFixedEntry(int id) async {
    try {
      final box = Hive.box(AppConstants.hiveBoxSettings);
      final raw = box.get(_fixedAtKey);
      if (raw is! Map) return;
      final next = Map<String, dynamic>.from(raw)..remove('$id');
      await box.put(_fixedAtKey, next);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const V4JellyAppBar(title: '错误档案', domain: GraphicDomain.custom),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 三态:加载中 / 失败可重试 / 内容(内容里再分空态)
    if (_loading) {
      // v2.10:整页加载态不再转圈 —— 骨架屏先铺出"错误记录列表将要占据的
      // 形状",数据一到原地替换(全项目统一等待 UI 的约定见 waiting.dart)。
      return const Padding(
        padding: Insets.page,
        child: SkeletonLines(lines: 6, seed: 1),
      );
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    final base = _tab == 0 ? _active : _fixed;
    final list = _filtered(base);
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          _buildTabs(base, list),
          _buildDashSummary(base, list),
          Expanded(
            // 空态也套一层可滚动容器:否则空列表时 RefreshIndicator 拉不动,
            // 用户以为"下拉刷新坏了"
            child: list.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: Insets.page,
                    children: [_buildEmpty(base)],
                  )
                : _buildList(list),
          ),
        ],
      ),
    );
  }

  /// 按来源筛选(全部 = 不过滤)
  List<_ErrorTag> _filtered(List<_ErrorTag> list) {
    final source = _source;
    if (source == null) return list;
    return list.where((t) => t.source == source).toList(growable: false);
  }

  Widget _buildTabs(List<_ErrorTag> base, List<_ErrorTag> list) {
    // 各页签带条数:用户不进页签也知道另一边有没有积压
    Widget tabChip(String label, int index, int count) {
      final selected = _tab == index;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xxs),
          child: ChoiceChip(
            label: SizedBox(
              width: double.infinity,
              child: Text('$label $count', textAlign: TextAlign.center),
            ),
            selected: selected,
            onSelected: (_) => setState(() {
              _tab = index;
              // 切页签时清掉来源筛选:上个页签有的来源,这个页签未必有
              _source = null;
            }),
            labelStyle: AppFont.metaStyle.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    final sources = <String>{for (final t in base) t.source};
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.sm, Gap.sm, Gap.sm, Gap.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              tabChip('待处理', 0, _active.length),
              tabChip('已改正', 1, _fixed.length),
            ],
          ),
          if (base.isNotEmpty) ...[
            const SizedBox(height: Gap.xs),
            // 来源筛选:同一 tag 可能从写译/测验/复习多处写入,
            // 分组后能看清"这类错主要是哪条链路扣出来的"
            Wrap(
              spacing: Gap.xs,
              runSpacing: Gap.xxs,
              children: [
                _sourceChip('全部', count: base.length, source: null),
                for (final source in sources)
                  _sourceChip(
                    _errorSourceLabel(source),
                    count: base.where((t) => t.source == source).length,
                    source: source,
                  ),
              ],
            ),
            if (list.isNotEmpty) ...[
              const SizedBox(height: Gap.xs),
              _buildSummary(list),
            ],
          ],
        ],
      ),
    );
  }

  /// 来源筛选 chip(AppTag 风格;选中 = 主色 + 勾)
  Widget _sourceChip(
    String label, {
    required int count,
    required String? source,
  }) {
    final selected = _source == source;
    return InkWell(
      borderRadius: Radii.pillRadius,
      onTap: () => setState(() => _source = source),
      child: AppTag(
        '$label $count',
        tone: selected ? AppTagTone.primary : AppTagTone.neutral,
        icon: selected ? Icons.check : null,
      ),
    );
  }

  Widget _buildSummary(List<_ErrorTag> list) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final total = list.fold<int>(0, (sum, t) => sum + t.count);
    if (list.isEmpty) {
      return Text(
        '这个来源下没有记录(共 0 次)',
        style: AppFont.metaStyle.copyWith(color: muted),
      );
    }
    final top = list.first; // 库里已按 count DESC 排好(错得最多的在前)
    final headline = _tab == 0
        ? '共 ${list.length} 类、$total 次;最需要处理的是「${top.tag}」(${top.count} 次)'
        : '已改正 ${list.length} 类(累计错过 $total 次)';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _tab == 0 ? Icons.priority_high : Icons.check_circle_outline,
          size: 16,
          color: _tab == 0
              ? theme.colorScheme.error
              : AppTheme.successColor(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            headline,
            style: AppFont.metaStyle.copyWith(color: muted),
          ),
        ),
      ],
    );
  }

  /// 空态分三种,文案与动作都必须不同:
  /// - 来源筛选筛没了 = 不是没数据,清掉筛选即可(给"查看全部来源");
  /// - 一条记录都没有 = 还没产出数据(引导去做一次会产生数据的动作);
  /// - 这一类清干净了 = 用户的工作成果(正反馈,给"看看已改正的"入口)。
  Widget _buildEmpty(List<_ErrorTag> base) {
    if (_source != null && base.isNotEmpty) {
      return AppCard(
        child: AppEmptyState(
          icon: Icons.filter_alt_outlined,
          art: EmptyArtKind.magnifier,
          title: '这个来源没有记录',
          hint: '当前只看「${_errorSourceLabel(_source!)}」,清掉筛选能看到全部',
          action: TextButton.icon(
            onPressed: () => setState(() => _source = null),
            icon: const Icon(Icons.clear_all, size: 16),
            label: const Text('查看全部来源'),
          ),
        ),
      );
    }
    if (_tab == 0) {
      final everHad = _fixed.isNotEmpty;
      return AppCard(
        child: AppEmptyState(
          icon: everHad
              ? Icons.verified_outlined
              : Icons.psychology_alt_outlined,
          art: EmptyArtKind.magnifier,
          title: everHad ? '待处理的错误都清干净了' : '还没有错误记录',
          hint: everHad
              ? '共 ${_fixed.length} 类已改正 —— 再错一次会自动回到这里'
              : '错误标签来自写译批改/读后测验/复习答错;做一次写译批改就会自动建档',
          action: everHad
              ? TextButton.icon(
                  onPressed: () => setState(() => _tab = 1),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('看看已改正的'),
                )
              : FilledButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WriteReviewScreen(),
                      ),
                    );
                    if (mounted) await _load();
                  },
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('去写译批改'),
                ),
        ),
      );
    }
    return AppCard(
      child: AppEmptyState(
        icon: Icons.check_circle_outline,
        art: EmptyArtKind.magnifier,
        title: '还没有标记已改正的记录',
        hint: '在「待处理」里点「标记已改正」,修好的错误会出现在这里',
        action: TextButton.icon(
          onPressed: () => setState(() => _tab = 0),
          icon: const Icon(Icons.inbox_outlined, size: 16),
          label: const Text('回到待处理'),
        ),
      ),
    );
  }

  /// 数据内页 · A 诊断台头部:KPI 带 + 「错在哪」分布细条。
  ///
  /// 为什么加这一段:原来一进页就是两级筛选 + 卡片列表,用户看不出
  /// "一共多少、最该先动哪一类";KPI + 分布条把这两个问题在首屏回答掉。
  Widget _buildDashSummary(List<_ErrorTag> base, List<_ErrorTag> list) {
    final DashTheme d = DashTheme.of(context);
    final int total = list.fold<int>(0, (int s, _ErrorTag t) => s + t.count);
    final List<_ErrorTag> top = list.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xxs, Gap.page, Gap.xs),
      child: Column(
        children: <Widget>[
          DashKpiBand(
            items: <DashKpi>[
              DashKpi(
                label: _tab == 0 ? '待处理' : '已改正',
                value: '${list.length}',
                unit: '类',
              ),
              DashKpi(
                label: '累计次数',
                value: '$total',
                unit: '次',
                color: total > 0 ? d.warn : null,
              ),
              DashKpi(
                label: '最需要处理',
                value: top.isEmpty ? '—' : top.first.tag,
                size: 15,
                color: top.isEmpty ? null : d.danger,
              ),
            ],
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 10),
            DashCard(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < top.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: 62,
                            child: Text(
                              top[i].tag,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFont.bodyStyle.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: d.ink,
                              ),
                            ),
                          ),
                          Expanded(
                            child: DashThinBar(
                              value: total <= 0 ? 0 : top[i].count / total,
                              color: i == 0 ? d.danger : d.accent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 42,
                            child: Text(
                              '${top[i].count} 次',
                              textAlign: TextAlign.right,
                              style: AppFont.metaStyle.copyWith(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: d.inkSoft,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList(List<_ErrorTag> list) {
    return ListView.separated(
      padding: Insets.page.copyWith(top: Gap.xxs, bottom: Gap.xl),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: Gap.xs),
      itemBuilder: (context, i) => _ErrorTagCard(
        tag: list[i],
        // 已改正页签里的按钮固定是「恢复为待处理」,用 fixed 标志而不是时刻
        isFixed: _tab == 1,
        // 复发 = 标过已改正之后 last_at 又变晚(见 _fixedAtKey 的说明);
        // 只有待处理页签才可能是复发
        fixedAt: _tab == 0 ? _fixedAt['${list[i].id}'] : null,
        onToggle: () => _setStatus(list[i], toFixed: _tab == 0),
      ),
    );
  }
}

/// 一条错误标签的视图模型(把 Map 的脏值挡在界面之外)
class _ErrorTag {
  final int? id;
  final String source;
  final String tag;
  final int count;
  final DateTime? firstAt;
  final DateTime? lastAt;
  final List<String> evidence;

  const _ErrorTag({
    required this.id,
    required this.source,
    required this.tag,
    required this.count,
    this.firstAt,
    this.lastAt,
    this.evidence = const [],
  });

  static _ErrorTag fromRow(Map<String, Object?> row) {
    return _ErrorTag(
      id: (row['id'] as num?)?.toInt(),
      source: '${row['source'] ?? ''}',
      tag: '${row['tag'] ?? ''}'.isEmpty ? '(未命名)' : '${row['tag']}',
      count: (row['count'] as num?)?.toInt() ?? 0,
      firstAt: DateTime.tryParse('${row['first_at']}'),
      lastAt: DateTime.tryParse('${row['last_at']}'),
      evidence: _parseEvidence(row['evidence']),
    );
  }

  /// evidence 是**单条**文本(表里是一列,写入口一次传一个样例)。
  /// 这里按换行/分隔符切开,兼容将来"多条拼在一个字段"的写法:
  /// 界面显示 2 条样例即可,多了反而看不清。
  static List<String> _parseEvidence(Object? raw) {
    final s = '${raw ?? ''}'.trim();
    if (s.isEmpty || s == 'null') return const [];
    return s
        .split(RegExp(r'[\n;|]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool isRecurring(DateTime? fixedAt) =>
      fixedAt != null && lastAt != null && lastAt!.isAfter(fixedAt);
}

/// 单条错误卡片:tag + 次数 + 时间 + 来源 + 样例 + 操作
class _ErrorTagCard extends StatelessWidget {
  final _ErrorTag tag;

  /// 当前是否在"已改正"页签(决定按钮文案与图标)
  final bool isFixed;

  /// 本机记录的"上次标已改正"时刻(非空 = 曾在待处理页签标过)
  final DateTime? fixedAt;
  final VoidCallback onToggle;

  const _ErrorTagCard({
    required this.tag,
    required this.onToggle,
    this.isFixed = false,
    this.fixedAt,
  });

  String get _sourceLabel => _errorSourceLabel(tag.source);

  /// "9-21 14:30"(不补零:中文界面里 09-21 反而啰嗦)
  static String _fmt(DateTime? t) {
    if (t == null) return '—';
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.month}-${t.day} $hh:$mm';
  }

  /// 过长的样例截断:一条考核证据不该占满整屏(保留足够辨认的上下文)
  static String _clip(String s, [int max = 60]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final recurring = tag.isRecurring(fixedAt);

    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        tag.tag,
                        style: AppFont.subheadStyle,
                      ),
                      // 次数是最重要的信息:做成醒目的徽标(v3 回流后次数会涨,
                      // >=3 次用危险色 —— 这就是"复发/高频"的视觉信号)
                      AppTag(
                        '${tag.count} 次',
                        tone: tag.count >= 3
                            ? AppTagTone.danger
                            : AppTagTone.primary,
                        icon: Icons.repeat,
                      ),
                      AppTag(
                        _sourceLabel,
                        tone: AppTagTone.neutral,
                        icon: Icons.edit_note,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (recurring) ...[
              const SizedBox(height: 6),
              // 复发要显眼:这正是错误档案存在的意义("这个坑你踩了第二次")
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.error.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.replay, size: 14, color: theme.colorScheme.error),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '复发:${_fmt(fixedAt)} 标过已改正,${_fmt(tag.lastAt)} 又错了一次',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '首次 ${_fmt(tag.firstAt)} · 最近 ${_fmt(tag.lastAt)}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            if (tag.evidence.isNotEmpty) ...[
              const SizedBox(height: 6),
              // 最多两条样例:证据是给用户"想起来了"用的,不是错题本全文
              ...tag.evidence.take(2).map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '· ${_clip(e)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onToggle,
                icon: Icon(isFixed ? Icons.undo : Icons.check, size: 16),
                label: Text(isFixed ? '恢复为待处理' : '标记已改正'),
              ),
            ),
          ],
      ),
    );
  }
}
