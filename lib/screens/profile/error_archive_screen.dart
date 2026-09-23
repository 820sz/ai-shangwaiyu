import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../config/constants.dart';
import '../../services/database.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_state.dart';

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
      appBar: AppBar(title: const Text('错误档案')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 三态:加载中 / 失败可重试 / 内容(内容里再分空态)
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    final list = _tab == 0 ? _active : _fixed;
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          _buildTabs(),
          Expanded(
            // 空态也套一层可滚动容器:否则空列表时 RefreshIndicator 拉不动,
            // 用户以为"下拉刷新坏了"
            child: list.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.5,
                        child: _buildEmpty(),
                      ),
                    ],
                  )
                : _buildList(list),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final theme = Theme.of(context);
    // 各页签带条数:用户不进页签也知道另一边有没有积压
    Widget chip(String label, int index, int count) {
      final selected = _tab == index;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            label: SizedBox(
              width: double.infinity,
              child: Text('$label($count)', textAlign: TextAlign.center),
            ),
            selected: selected,
            onSelected: (_) => setState(() => _tab = index),
            labelStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );
    }

    final list = _tab == 0 ? _active : _fixed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              chip('待处理', 0, _active.length),
              chip('已改正', 1, _fixed.length),
            ],
          ),
          // 汇总行:一眼看清总量与最该处理的那一类(空的时候不写废话)
          if (list.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSummary(list),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary(List<_ErrorTag> list) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final total = list.fold<int>(0, (sum, t) => sum + t.count);
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
          color: _tab == 0 ? theme.colorScheme.error : Colors.green,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            headline,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }

  /// 空态分两种,文案必须不同:
  /// - 一条记录都没有 = 还没产出数据(引导去做一次会产生数据的动作)
  /// - 这一类清干净了 = 用户的工作成果(是正反馈,不是"没有数据")
  Widget _buildEmpty() {
    if (_tab == 0) {
      final everHad = _fixed.isNotEmpty;
      return EmptyState(
        icon: everHad ? Icons.verified_outlined : Icons.psychology_alt_outlined,
        title: everHad ? '待处理的错误都清干净了' : '还没有错误记录',
        hint: everHad
            ? '共 ${_fixed.length} 类已改正 —— 再错一次会自动回到这里'
            : '去做一次写译批改或读后测验就有了',
      );
    }
    return const EmptyState(
      icon: Icons.check_circle_outline,
      title: '这一类都清干净了',
      hint: '标记为「已改正」的错误会出现在这里',
    );
  }

  Widget _buildList(List<_ErrorTag> list) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
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

  /// source → 中文:用户不认识 'reading_quiz' 这种内部名
  static const Map<String, String> _sourceLabels = {
    'writing': '写译批改',
    'exercise': '回译练习',
    'reading_quiz': '读后测验',
    'review': '复习',
  };

  String get _sourceLabel => _sourceLabels[tag.source] ?? tag.source;

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

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
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
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      // 次数是最重要的信息:做成醒目的徽标
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tag.count >= 3
                              ? theme.colorScheme.error.withAlpha(24)
                              : theme.colorScheme.primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${tag.count} 次',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: tag.count >= 3
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      _Chip(text: _sourceLabel, icon: Icons.edit_note),
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
      ),
    );
  }
}

/// 小的来源标签(用现成的 Chip 会太胖,这里只做个灰底小标记)
class _Chip extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Chip({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: muted),
          const SizedBox(width: 3),
          Text(text, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
        ],
      ),
    );
  }
}
