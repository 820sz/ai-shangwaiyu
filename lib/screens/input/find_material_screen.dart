import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/design_tokens.dart';
import '../../config/v4_theme.dart';
import '../../services/find_need_context.dart';
import '../../services/material_channel.dart';
import 'free_search_screen.dart';
import 'need_search_screen.dart';

/// 「找材料」入口页(用户 2026-11-06 选型 **A · 并列大卡**)。
///
/// 一屏说清两条路,点哪张卡进哪个独立页面:
/// 1. **自由搜** → [FreeSearchScreen](关键词 + 来源/类型/难度/场景);
/// 2. **按我的情况找** → [NeedSearchScreen](读学习助理的统计:难度档/目标/弱项/最近阅读)。
///
/// 卡内数值全部是真数据(来自 [FindNeedContext] / [FindSearchHistory]):
/// - 自由搜卡:"上次搜过"(`MaterialPrefs` 的搜索历史)+ 能筛什么;
/// - 按情况找卡:难度档 / 学习目标 / 词汇量基线(**没测过就写"待测"**)。
///
/// 右上角 `[历史]`(设计 A 线框)弹出轻量 sheet:列全部搜索历史、点一条回填搜索、
/// 可清空(数据就是 `MaterialPrefs.rememberQuery` 那一份,不新建存储)。
class FindMaterialScreen extends StatefulWidget {
  /// **仅渲染测试用**:注入预置数据后跳过异步读取(生产永不传)。
  final FindNeedContext? initialContext;
  final List<String>? initialHistory;
  final FindMaterialLastRun? initialLastRun;

  const FindMaterialScreen({
    super.key,
    this.initialContext,
    this.initialHistory,
    this.initialLastRun,
  });

  @override
  State<FindMaterialScreen> createState() => _FindMaterialScreenState();
}

/// 入口页"上次结果卡"需要的真实数据(快照条数 + 更新时间)。
class FindMaterialLastRun {
  final int count;
  final DateTime updatedAt;

  const FindMaterialLastRun({required this.count, required this.updatedAt});
}

class _FindMaterialScreenState extends State<FindMaterialScreen> {
  FindNeedContext? _ctx;
  List<String> _history = const <String>[];
  FindMaterialLastRun? _lastRun;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialContext != null) {
      // 渲染测试路径:不碰 Hive/DB,直接用注入数据
      _ctx = widget.initialContext;
      _history = widget.initialHistory ?? const <String>[];
      _lastRun = widget.initialLastRun;
      _loading = false;
      return;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    FindNeedContext? ctx;
    try {
      ctx = await FindNeedContext.load();
    } catch (_) {
      ctx = null;
    }
    var history = const <String>[];
    try {
      history = FindSearchHistory.load();
    } catch (_) {
      history = const <String>[];
    }
    FindMaterialLastRun? lastRun;
    try {
      final snapshot = await MaterialChannelStore.loadSnapshot('need:all');
      if (snapshot != null && snapshot.items.isNotEmpty) {
        lastRun = FindMaterialLastRun(
          count: snapshot.items.length,
          updatedAt: snapshot.updatedAt,
        );
      }
    } catch (_) {
      lastRun = null;
    }
    if (!mounted) return;
    setState(() {
      _ctx = ctx;
      _history = history;
      _lastRun = lastRun;
      _loading = false;
    });
  }

  Future<void> _openFreeSearch({String? initialQuery}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FreeSearchScreen(initialQuery: initialQuery),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openNeedSearch() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NeedSearchScreen()),
    );
    if (mounted) await _load();
  }

  /// 设计 A 右上角 `[历史]`:轻量 sheet(列历史 / 点一条回填搜索 / 清空)。
  Future<void> _openHistory() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HistorySheet(
        history: _history,
        onClear: () async {
          await FindSearchHistory.clear();
          if (!mounted) return;
          setState(() => _history = const <String>[]);
        },
      ),
    );
    if (!mounted || picked == null) return;
    await _openFreeSearch(initialQuery: picked);
  }

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final ctx = _ctx;
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            _topBar(skin),
            Expanded(
              child: _loading || ctx == null
                  ? _loadingState(skin)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                            Gap.page, Gap.sm, Gap.page, Gap.xl),
                        children: <Widget>[
                          Text(
                            '找材料',
                            style: TextStyle(
                              fontSize: 34,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.9,
                              color: skin.ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '两条路:自己搜,或者让软件按你的情况找。',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              color: skin.inkSoft,
                            ),
                          ),
                          const SizedBox(height: Gap.md),
                          SizedBox(
                            height: 274,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Expanded(
                                  child: _freeCard(skin),
                                ),
                                const SizedBox(width: Gap.sm),
                                Expanded(
                                  child: _needCard(skin, ctx),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Gap.lg),
                          _recentHeader(skin),
                          const SizedBox(height: Gap.xs),
                          _recentChips(skin),
                          if (_lastRun != null) ...<Widget>[
                            const SizedBox(height: Gap.lg),
                            _lastRunStrip(skin, _lastRun!),
                          ],
                          const SizedBox(height: Gap.lg),
                          _footerNote(skin),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(V4Skin skin) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 2, Gap.page, 0),
      child: Row(
        children: <Widget>[
          _circle(skin, Icons.arrow_back_rounded,
              () => Navigator.maybePop(context)),
          const Spacer(),
          // 设计 A:右上角 [历史]
          InkWell(
            onTap: _openHistory,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: skin.hairline),
                boxShadow: skin.shadow,
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.history_rounded, size: 17, color: skin.ink),
                  const SizedBox(width: 5),
                  Text('历史',
                      style: AppFont.metaStyle.copyWith(
                        color: skin.ink,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(V4Skin skin, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: skin.surface,
          shape: BoxShape.circle,
          border: Border.all(color: skin.hairline),
          boxShadow: skin.shadow,
        ),
        child: Icon(icon, size: 19, color: skin.ink),
      ),
    );
  }

  Widget _loadingState(V4Skin skin) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xl),
      children: <Widget>[
        Text('找材料',
            style: TextStyle(
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.9,
              color: skin.ink,
            )),
        const SizedBox(height: Gap.md),
        Container(
          height: 200,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: skin.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: skin.hairline),
            boxShadow: skin.shadow,
          ),
          child: Text(
            '正在读取你的学习情况…',
            style: AppFont.metaStyle.copyWith(color: skin.inkFaint),
          ),
        ),
      ],
    );
  }

  // ── 两张并列大卡 ────────────────────────────────────────────────────

  Widget _freeCard(V4Skin skin) {
    final lastQuery = _lastFreeKeyword();
    return _bigCard(
      skin,
      tint: skin.pastelAt(3).first,
      icon: Icons.manage_search_rounded,
      title: '自由搜',
      desc: '输关键词,直接搜公开源原文。\n看得到原文、能存到自己库里。',
      chips: <String>['关键词', '来源', '类型', '难度'],
      footLabel: '上次搜过',
      footValue: lastQuery.isEmpty ? '还没搜过' : lastQuery,
      cta: '去搜',
      onTap: () => _openFreeSearch(
        initialQuery: lastQuery.isEmpty ? null : lastQuery,
      ),
    );
  }

  Widget _needCard(V4Skin skin, FindNeedContext ctx) {
    final bandChip = ctx.need.band.isAny ? '未设难度档' : ctx.need.band.label;
    final goalChip = ctx.goals.isEmpty ? '未设目标' : ctx.goals.first;
    final vocab = ctx.vocabEstimate;
    // 弱项 chip 可选(没有错误档案时不显示) —— 用命令式追加,避免列表里的
    // `if (x != null) x` 触发 use_null_aware_elements 风格告警。
    final chips = <String>[bandChip, goalChip];
    if (ctx.weakTags.isNotEmpty) chips.add(ctx.weakTags.first);
    return _bigCard(
      skin,
      tint: skin.pastelAt(0).first,
      icon: Icons.auto_awesome_rounded,
      title: '按我的情况找',
      desc: '读学习助理的统计:\n水平、目标、弱项、阅读。',
      chips: chips,
      footLabel: '基线',
      footValue: vocab == null
          ? '待测(去测一次词汇量)'
          : '已掌握 ${_thousands(vocab)} 词',
      cta: '按情况找',
      onTap: _openNeedSearch,
    );
  }

  Widget _bigCard(
    V4Skin skin, {
    required Color tint,
    required IconData icon,
    required String title,
    required String desc,
    required List<String> chips,
    required String footLabel,
    required String footValue,
    required String cta,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.alphaBlend(tint.withValues(alpha: 0.75), skin.surface),
              skin.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: skin.hairline),
          boxShadow: skin.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: skin.hairline),
              ),
              child: Icon(icon, size: 21, color: skin.ink),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
                color: skin.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.45,
                color: skin.inkSoft,
              ),
            ),
            const Spacer(),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: <Widget>[
                for (final chip in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: skin.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: skin.hairline),
                    ),
                    child: Text(
                      chip,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9.5, color: skin.inkSoft),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: skin.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(footLabel,
                      style: TextStyle(fontSize: 9, color: skin.inkFaint)),
                  const SizedBox(height: 1),
                  Text(
                    footValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: skin.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(cta,
                    style: AppFont.metaStyle.copyWith(
                      color: skin.accent,
                      fontWeight: FontWeight.w800,
                    )),
                const SizedBox(width: 2),
                Icon(Icons.arrow_forward_rounded,
                    size: 14, color: skin.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 最近搜过 / 上次结果 ──────────────────────────────────────────────

  Widget _recentHeader(V4Skin skin) {
    return Row(
      children: <Widget>[
        Text('最近搜过',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: skin.ink,
            )),
        const Spacer(),
        InkWell(
          onTap: _openHistory,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text('搜索历史 · 可清空',
                style: TextStyle(fontSize: 10, color: skin.inkFaint)),
          ),
        ),
      ],
    );
  }

  Widget _recentChips(V4Skin skin) {
    if (_history.isEmpty) {
      return Text(
        '还没有搜索记录 —— 点「自由搜」开始第一次。',
        style: TextStyle(fontSize: 11, color: skin.inkFaint),
      );
    }
    final shown = _history.take(4).toList();
    return Wrap(
      spacing: Gap.xs,
      runSpacing: 6,
      children: <Widget>[
        for (final query in shown)
          InkWell(
            onTap: () => _openFreeSearch(initialQuery: query),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: skin.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: skin.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.history_rounded,
                      size: 12, color: skin.inkFaint),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: skin.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _lastRunStrip(V4Skin skin, FindMaterialLastRun run) {
    return InkWell(
      onTap: _openNeedSearch,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: skin.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: skin.hairline),
          boxShadow: skin.shadow,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: skin.pastelAt(2).first.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.travel_explore_rounded,
                  size: 16, color: skin.ink),
            ),
            const SizedBox(width: Gap.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('上次找的结果还在',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: skin.ink,
                      )),
                  Text(
                    '${run.count} 篇 · ${_ago(run.updatedAt)}',
                    style: TextStyle(fontSize: 10, color: skin.inkFaint),
                  ),
                ],
              ),
            ),
            Text('继续看',
                style: AppFont.tagStyle.copyWith(
                  color: skin.accent,
                  fontWeight: FontWeight.w700,
                )),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: skin.accent),
          ],
        ),
      ),
    );
  }

  Widget _footerNote(V4Skin skin) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: skin.surfaceAlt.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 14, color: skin.inkFaint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '两张卡各进一个独立页面:自由搜只找公开源原文,不花 AI 钱;'
              '按情况找会读学习助理的统计(没数据的地方写「待测」,不编数字)。',
              style: TextStyle(
                fontSize: 10,
                height: 1.45,
                color: skin.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 小工具 ──────────────────────────────────────────────────────────

  String _lastFreeKeyword() {
    for (final item in _history) {
      if (item.trim().isNotEmpty) return item.trim();
    }
    return '';
  }

  static String _thousands(int value) {
    final text = '$value';
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  static String _ago(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

/// 搜索历史 sheet(D6):列全部历史、点一条回填搜索、可清空。
class _HistorySheet extends StatefulWidget {
  final List<String> history;
  final Future<void> Function() onClear;

  const _HistorySheet({required this.history, required this.onClear});

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late List<String> _items = List<String>.of(widget.history);
  bool _clearing = false;

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(Gap.page, 12, Gap.page, 12 + bottom),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: skin.hairline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: <Widget>[
              Text('搜索历史',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: skin.ink,
                  )),
              const Spacer(),
              if (_items.isNotEmpty)
                TextButton(
                  onPressed: _clearing ? null : _clear,
                  child: Text(
                    _clearing ? '清空中…' : '清空',
                    style: AppFont.metaStyle.copyWith(color: skin.accent),
                  ),
                ),
            ],
          ),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.lg),
              child: Center(
                child: Text(
                  '还没有搜索记录',
                  style: AppFont.metaStyle.copyWith(color: skin.inkFaint),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (BuildContext context, int index) =>
                    Divider(height: 1, color: skin.hairline),
                itemBuilder: (context, index) {
                  final query = _items[index];
                  return InkWell(
                    onTap: () => Navigator.pop(context, query),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.history_rounded,
                              size: 16, color: skin.inkFaint),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              query,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: skin.ink,
                              ),
                            ),
                          ),
                          Icon(Icons.north_west_rounded,
                              size: 14, color: skin.inkFaint),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: Gap.xs),
        ],
      ),
    );
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    await widget.onClear();
    if (!mounted) return;
    setState(() {
      _items = const <String>[];
      _clearing = false;
    });
  }
}
