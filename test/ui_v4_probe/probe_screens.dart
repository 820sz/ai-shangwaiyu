/// 五种视觉基调的"同一批屏"(输入首页 / 输出首页 / 风格板)。
///
/// 这里刻意**共享结构与文案、只变视觉语言**:用户要看的是"同一个 App 的五种
/// 气质",不是"五个不同的信息架构"。所以每屏的信息层次完全一致——
/// 头图 / 题材 / 继续读 / 四个入口 / 列表 / 数据 / 底栏——
/// 但头图版式、卡片材质、标签形状、字体、底栏做法都按 [ProbeFlavor] 分派。
///
/// 纪律:
/// - 只用 [ProbeSpec] 里的令牌，不写裸色值/裸字号;
/// - 每个基调的"炫技点"都只放在一处(杂志的双线、夜读的发光、果冻的软阴影、
///   极简的细线网格、印刷的印章),其余克制 —— 这样才对比得出"基调"而不是"花"。
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:readflow/widgets/graphics/graphics.dart';
import 'package:readflow/widgets/v4/v4_kit.dart';

import 'probe_spec.dart';

const double _pageW = 414;
const double _pageH = 896;
const double _gutter = 20;

// ══════════════════════════════════════════════════════════════════════
// 样张数据(真实内容)
// ══════════════════════════════════════════════════════════════════════

const List<(String, GraphicDomain, IconData)> _topics =
    <(String, GraphicDomain, IconData)>[
  ('科技', GraphicDomain.science, Icons.science_outlined),
  ('商业', GraphicDomain.business, Icons.work_outline),
  ('健康', GraphicDomain.health, Icons.favorite_border),
  ('文化', GraphicDomain.culture, Icons.palette_outlined),
  ('旅行', GraphicDomain.travel, Icons.flight_takeoff),
  ('语言', GraphicDomain.language, Icons.translate),
];

const List<(String, String, GraphicDomain, IconData)> _entries =
    <(String, String, GraphicDomain, IconData)>[
  ('材料中心', '按题材/难度找', GraphicDomain.news, Icons.explore_outlined),
  ('我的书架', '在读 3 本', GraphicDomain.book,
      Icons.collections_bookmark_outlined),
  ('AI 找材料', '说出需求自动找', GraphicDomain.academic, Icons.auto_awesome),
  ('拍照 / 导入', '纸面、网页都行', GraphicDomain.language,
      Icons.add_photo_alternate_outlined),
];

const List<(String, String, String, GraphicDomain, double, bool)> _stages =
    <(String, String, String, GraphicDomain, double, bool)>[
  ('写词', '语境填空 · 按目标词表', '第壹阶', GraphicDomain.exam, 0.72, true),
  ('写句', '改写 · 纠错 · 连词成句', '第贰阶', GraphicDomain.language, 0.35, false),
  ('写段', '材料回译 · 段落成文', '第叁阶', GraphicDomain.news, 0.12, false),
  ('写篇', '作文题 · rubric 批改 · 折算档位', '第肆阶', GraphicDomain.academic, 0.0,
      false),
];

const List<(String, String, GraphicDomain, IconData)> _statItems =
    <(String, String, GraphicDomain, IconData)>[
  ('18', '复习词', GraphicDomain.exam, Icons.refresh),
  ('2', '输出练习', GraphicDomain.language, Icons.edit_outlined),
  ('24', '分钟', GraphicDomain.health, Icons.timer_outlined),
];

const List<(IconData, String)> _navItems = <(IconData, String)>[
  (Icons.auto_stories_outlined, '输入'),
  (Icons.edit_outlined, '输出'),
  (Icons.auto_awesome_outlined, '助理'),
  (Icons.person_outline, '我的'),
];

/// 明亮果冻风的四组「果冻色」:不用域色(域色偏灰会显脏),固定四块
/// 低饱和高亮度的糖果色,保证"明亮"但不刺眼;身份信息交给图标与文字。
const List<List<Color>> _jellyFills = <List<Color>>[
  <Color>[Color(0xFFFFE2CE), Color(0xFFFFC6AB)],
  <Color>[Color(0xFFE4E0FF), Color(0xFFC9C1FF)],
  <Color>[Color(0xFFD7F4E7), Color(0xFFB4E9D4)],
  <Color>[Color(0xFFE3ECFF), Color(0xFFC6D6FF)],
];

// ══════════════════════════════════════════════════════════════════════
// 手机面板 / 状态栏 / 底栏
// ══════════════════════════════════════════════════════════════════════

Widget probePanel(ProbeSpec s, {required Widget body}) {
  final core = Column(
    children: <Widget>[
      _statusBar(s),
      Expanded(child: body),
      _nav(s),
    ],
  );
  return SizedBox(
    width: _pageW,
    height: _pageH,
    child: Stack(
      children: <Widget>[
        Positioned.fill(child: ColoredBox(color: s.bg)),
        Positioned.fill(child: core),
        if (s.grain > 0)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _PaperGrain(color: s.grainColor, opacity: s.grain),
              ),
            ),
          ),
      ],
    ),
  );
}

Widget _statusBar(ProbeSpec s) {
  final c = s.ink.withValues(alpha: 0.78);
  return SizedBox(
    height: 30,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: <Widget>[
          Text(
            '9:41',
            style: s.label(c, size: 10.5, tracking: 0.4, weight: FontWeight.w700),
          ),
          const Spacer(),
          Icon(Icons.signal_cellular_alt, size: 11, color: c),
          const SizedBox(width: 5),
          Icon(Icons.wifi, size: 12, color: c),
          const SizedBox(width: 5),
          Icon(Icons.battery_full, size: 13, color: c),
        ],
      ),
    ),
  );
}

Widget _nav(ProbeSpec s) {
  final idle = s.inkFaint;
  switch (s.flavor) {
    case ProbeFlavor.magazine:
      return Container(
        decoration: BoxDecoration(
          color: s.surface,
          border: Border(top: BorderSide(color: s.hairline, width: 1)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 9, 20, 11),
        child: SizedBox(
          height: 46,
          child: Row(
            children: <Widget>[
              for (var i = 0; i < _navItems.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(_navItems[i].$1, size: 19, color: i == 0 ? s.ink : idle),
                      const SizedBox(height: 4),
                      Text(
                        _navItems[i].$2,
                        style: s.label(
                          i == 0 ? s.ink : idle,
                          size: 9.5,
                          tracking: 1.4,
                          weight: i == 0 ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    case ProbeFlavor.night:
      return Container(
        decoration: BoxDecoration(
          color: s.surface,
          border: Border(top: BorderSide(color: s.hairline, width: 1)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 9, 20, 10),
        child: SizedBox(
          height: 46,
          child: Row(
            children: <Widget>[
              for (var i = 0; i < _navItems.length; i++)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(_navItems[i].$1,
                          size: 19, color: i == 0 ? s.accent : idle),
                      const SizedBox(height: 4),
                      Text(
                        _navItems[i].$2,
                        style: s.label(
                          i == 0 ? s.accent : idle,
                          size: 8.5,
                          tracking: 1.2,
                          weight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    case ProbeFlavor.jelly:
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                boxShadow: s.cardShadow,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: <Widget>[
                  for (var i = 0; i < _navItems.length; i++)
                    Expanded(
                      child: Center(
                        child: i == 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 13, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: <Color>[
                                      s.accent,
                                      Color.lerp(s.accent, Colors.white, 0.22)!,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: s.accent.withValues(alpha: 0.30),
                                      blurRadius: 12,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(_navItems[i].$1,
                                        size: 16, color: Colors.white),
                                    const SizedBox(width: 5),
                                    Text(
                                      _navItems[i].$2,
                                      style: s.label(Colors.white,
                                          size: 10,
                                          tracking: 0.4,
                                          weight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Icon(_navItems[i].$1,
                                      size: 19, color: s.inkFaint),
                                  const SizedBox(height: 2),
                                  Text(
                                    _navItems[i].$2,
                                    style: s.label(s.inkFaint,
                                        size: 9.5, tracking: 0.4),
                                  ),
                                ],
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    case ProbeFlavor.mono:
      return Container(
        decoration: BoxDecoration(
          color: s.surface,
          border: Border(top: BorderSide(color: s.hairline, width: 1)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 8),
        child: SizedBox(
          height: 45,
          child: Row(
            children: <Widget>[
              for (var i = 0; i < _navItems.length; i++)
                Expanded(
                  child: Column(
                    children: <Widget>[
                      Container(
                        height: 2,
                        width: 14,
                        color: i == 0 ? s.accent : Colors.transparent,
                      ),
                      const SizedBox(height: 6),
                      Icon(_navItems[i].$1,
                          size: 18, color: i == 0 ? s.ink : idle),
                      const SizedBox(height: 3),
                      Text(
                        _navItems[i].$2,
                        style: s.label(
                          i == 0 ? s.ink : idle,
                          size: 8.5,
                          tracking: 1.2,
                          weight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    case ProbeFlavor.press:
      return Column(
        children: <Widget>[
          Container(height: 2, color: s.ink),
          const SizedBox(height: 1.5),
          Container(height: 0.7, color: s.ink),
          const SizedBox(height: 6),
          SizedBox(
            height: 44,
            child: Row(
              children: <Widget>[
                for (var i = 0; i < _navItems.length; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(_navItems[i].$1,
                            size: 18, color: i == 0 ? s.accent : idle),
                        const SizedBox(height: 3),
                        Text(
                          _navItems[i].$2,
                          style: s.label(
                            i == 0 ? s.accent : idle,
                            size: 10,
                            tracking: 2.4,
                            weight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 输入首页
// ══════════════════════════════════════════════════════════════════════

Widget probeInputScreen(ProbeSpec s) {
  return probePanel(
    s,
    body: ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _hero(s, output: false),
        Padding(
          padding: const EdgeInsets.fromLTRB(_gutter, 14, _gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _tabs(s),
              const SizedBox(height: 16),
              _featured(s),
              const SizedBox(height: 16),
              _entryGrid(s),
              const SizedBox(height: 20),
              _section(s,
                  index: '01',
                  cnIndex: '壹',
                  latin: 'MATERIALS',
                  title: '在读材料',
                  subtitle: '按你的难度档 B2 排序'),
              _row(s,
                  title: ProbeCopy.rowTitle,
                  meta: ProbeCopy.rowMeta,
                  domain: GraphicDomain.news,
                  seed: '疫'),
              _row(s,
                  title: ProbeCopy.rowTitle2,
                  meta: ProbeCopy.rowMeta2,
                  domain: GraphicDomain.book,
                  seed: 'E'),
              _section(s,
                  index: '02',
                  cnIndex: '贰',
                  latin: 'TODAY',
                  title: '今日进度',
                  subtitle: '真实数据，不灌水'),
              const SizedBox(height: 4),
              _stats(s),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════
// 输出首页
// ══════════════════════════════════════════════════════════════════════

Widget probeOutputScreen(ProbeSpec s) {
  return probePanel(
    s,
    body: ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _hero(s, output: true),
        Padding(
          padding: const EdgeInsets.fromLTRB(_gutter, 16, _gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var i = 0; i < _stages.length; i++) _stage(s, index: i),
              const SizedBox(height: 18),
              _section(s,
                  index: '02',
                  cnIndex: '贰',
                  latin: 'SUGGEST',
                  title: '今日建议',
                  subtitle: '按真实数据给'),
              _row(s,
                  title: '先清 18 个到期复习词',
                  meta: '昨晚 6 个词忘得快，今天先过一遍',
                  domain: GraphicDomain.exam,
                  seed: '18'),
              _section(s,
                  index: '03',
                  cnIndex: '叁',
                  latin: 'RECORDS',
                  title: '最近记录'),
              _row(s,
                  title: '写篇 · 四六级作文：AI 与学习',
                  meta: '昨天 · 88 分 · 折算 C1',
                  domain: GraphicDomain.academic,
                  seed: '篇'),
              _row(s,
                  title: '写句 · 错句纠错 5/5',
                  meta: '昨天 · 正确率 100%',
                  domain: GraphicDomain.language,
                  seed: '句'),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════
// 风格板
// ══════════════════════════════════════════════════════════════════════

Widget probeStyleBoard(ProbeSpec s) {
  return probePanel(
    s,
    body: ListView(
      padding: const EdgeInsets.fromLTRB(_gutter, 6, _gutter, 4),
      children: <Widget>[
        _boardHeader(s),
        const SizedBox(height: 10),
        _boardLabel(s, 'PALETTE / 色板'),
        const SizedBox(height: 6),
        _paletteRow(s),
        const SizedBox(height: 10),
        _boardLabel(s, 'TYPE / 字阶'),
        const SizedBox(height: 6),
        _typeSpecimen(s),
        const SizedBox(height: 10),
        _boardLabel(s, 'CONTROLS / 控件'),
        const SizedBox(height: 6),
        _controls(s),
        const SizedBox(height: 8),
        _boardLabel(s, 'CARD / 卡片'),
        const SizedBox(height: 6),
        _row(s,
            title: 'The Elements of Style',
            meta: '公版书 · 46 分钟 · 已读 12%',
            domain: GraphicDomain.book,
            seed: 'E',
            dense: true),
        const SizedBox(height: 8),
        _stats(s, dense: true),
        const SizedBox(height: 12),
        _boardLabel(s, 'EMPTY / 空态'),
        const SizedBox(height: 7),
        _empty(s, dense: true),
      ],
    ),
  );
}

Widget _boardHeader(ProbeSpec s) {
  final badgeColor = s.flavor == ProbeFlavor.night ? s.accent : s.ink;
  final radius = switch (s.flavor) {
    ProbeFlavor.jelly => 9.0,
    ProbeFlavor.press => 0.0,
    ProbeFlavor.magazine => 2.0,
    _ => 6.0,
  };
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Center(
              child: Text(
                s.code,
                style: s.label(
                  badgeColor.computeLuminance() > 0.55 ? s.ink : Colors.white,
                  size: 12,
                  tracking: 0.2,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              s.name,
              style: s.display(s.ink,
                  size: 20, weight: FontWeight.w800, height: 1.1),
            ),
          ),
          Text('V4 · 基调', style: s.label(s.inkFaint, size: 8.5, tracking: 1.4)),
        ],
      ),
      const SizedBox(height: 5),
      Text(s.mood, style: s.body(s.inkSoft, size: 10.5, height: 1.5), maxLines: 2),
    ],
  );
}

Widget _boardLabel(ProbeSpec s, String text) {
  return Row(
    children: <Widget>[
      Text(text,
          style:
              s.label(s.inkFaint, size: 8.5, tracking: 1.6, weight: FontWeight.w700)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 0.7, color: s.hairline)),
    ],
  );
}

Widget _paletteRow(ProbeSpec s) {
  String hex(Color c) => '#${c
      .toARGB32()
      .toRadixString(16)
      .padLeft(8, '0')
      .substring(2)
      .toUpperCase()}';
  return Row(
    children: <Widget>[
      for (var i = 0; i < s.palette.length; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == s.palette.length - 1 ? 0 : 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 26,
                  decoration: BoxDecoration(
                    color: s.palette[i],
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                        color: s.hairline.withValues(alpha: 0.9), width: 0.6),
                  ),
                ),
                const SizedBox(height: 3),
                Text(hex(s.palette[i]),
                    style: s.label(s.inkFaint, size: 6.5, tracking: 0.2)),
              ],
            ),
          ),
        ),
    ],
  );
}

Widget _typeSpecimen(ProbeSpec s) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text('Aa', style: s.display(s.ink, size: 26, weight: FontWeight.w700)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '读一本好书',
              style: s.display(s.ink, size: 18, weight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('B2',
              style: s.label(s.accent, size: 8.5, tracking: 0.6, weight: FontWeight.w700)),
        ],
      ),
      const SizedBox(height: 5),
      Text(ProbeCopy.boardBody,
          style: s.body(s.inkSoft, size: 10.5, height: 1.5), maxLines: 2),
      const SizedBox(height: 3),
      Text(ProbeCopy.boardMeta,
          style: s.label(s.inkFaint, size: 8, tracking: 0.4), maxLines: 1),
    ],
  );
}

Widget _controls(ProbeSpec s) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        children: <Widget>[
          _filledPill(s, '开始阅读'),
          const SizedBox(width: 7),
          _outlinePill(s, '稍后'),
          const Spacer(),
          _ring(s, 0.65, 32, label: '65%'),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          _tag(s, '外刊'),
          const SizedBox(width: 5),
          _tag(s, 'B2'),
          const SizedBox(width: 5),
          _tag(s, '8 分钟'),
          const SizedBox(width: 7),
          Text('连续 12 天', style: s.label(s.inkSoft, size: 9, tracking: 0.3)),
        ],
      ),
    ],
  );
}

// ══════════════════════════════════════════════════════════════════════
// 头图(五套版式)
// ══════════════════════════════════════════════════════════════════════

Widget _hero(ProbeSpec s, {required bool output}) {
  final title = output ? ProbeCopy.outputTitle : ProbeCopy.inputTitle;
  final sub = output ? ProbeCopy.outputSub : ProbeCopy.inputSub;
  final chips = output
      ? <String>[ProbeCopy.goal, ProbeCopy.level]
      : <String>[ProbeCopy.streak, ProbeCopy.weekly];
  final actionLabel = output ? '练习中心' : '材料中心';
  final domain = output ? GraphicDomain.exam : GraphicDomain.news;
  switch (s.flavor) {
    case ProbeFlavor.magazine:
      return ClipRect(
        child: Stack(
          children: <Widget>[
            Positioned(
              right: -10,
              bottom: -24,
              child: Text(
                output ? '出' : '输',
                style: s.display(s.ink.withValues(alpha: 0.055),
                    size: 150, weight: FontWeight.w700, height: 1.0),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(_gutter, 10, _gutter, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('READFLOW · ${output ? '写作' : '精读'}',
                          style: s.label(s.inkSoft,
                              size: 9, tracking: 2.4, weight: FontWeight.w700)),
                      const Spacer(),
                      Text(ProbeCopy.dateLatin,
                          style: s.label(s.inkFaint, size: 8.5, tracking: 1.6)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Container(height: 1.6, color: s.ink),
                  const SizedBox(height: 13),
                  Text(title,
                      style: s.display(s.ink,
                          size: s.heroTitleSize, tracking: 2)),
                  const SizedBox(height: 7),
                  Text(sub,
                      style: s.body(s.inkSoft, size: 12.5, height: 1.6),
                      maxLines: 2),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      for (final c in chips) ...<Widget>[
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                              color: s.accent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text(c, style: s.label(s.inkSoft, size: 10, tracking: 0.5)),
                        const SizedBox(width: 12),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        color: s.accent,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(actionLabel,
                                style: s.label(Colors.white,
                                    size: 10.5,
                                    tracking: 1,
                                    weight: FontWeight.w800)),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward,
                                size: 11, color: Colors.white),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Container(height: 1, color: s.hairline),
                ],
              ),
            ),
          ],
        ),
      );
    case ProbeFlavor.night:
      final tone = s.domainTone(domain);
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color.lerp(s.bg, tone, 0.14)!, s.bg],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_gutter, 10, _gutter, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(width: 24, height: 2, color: tone),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Text(ProbeCopy.dateLatin,
                      style: s.label(s.inkFaint, size: 9, tracking: 1.8)),
                  const Spacer(),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: s.hairline, width: 1),
                    ),
                    child: Icon(Icons.explore_outlined,
                        size: 16, color: s.inkSoft),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(title,
                  style: s.display(s.ink,
                      size: s.heroTitleSize,
                      weight: FontWeight.w700,
                      tracking: -1.2)),
              const SizedBox(height: 7),
              Text(sub,
                  style: s.body(s.inkSoft, size: 12.5, height: 1.6),
                  maxLines: 2),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  for (final c in chips) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: s.surfaceAlt.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: s.hairline, width: 1),
                      ),
                      child: Text(c,
                          style: s.label(s.inkSoft, size: 9, tracking: 0.8)),
                    ),
                    const SizedBox(width: 7),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: s.accent,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                            color: s.accent.withValues(alpha: 0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Text(actionLabel,
                        style: s.label(s.onAccent,
                            size: 10, tracking: 0.6, weight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: s.hairline),
            ],
          ),
        ),
      );
    case ProbeFlavor.jelly:
      return ClipRRect(
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(s.heroRadius)),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFFEFEFFF), Color(0xFFFFF2EC)],
                  ),
                ),
              ),
            ),
            Positioned(right: -45, top: -55, child: _blob(s.accent, 190)),
            Positioned(left: -55, top: 75, child: _blob(s.accentAlt, 140)),
            Padding(
              padding: const EdgeInsets.fromLTRB(_gutter, 10, _gutter, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(ProbeCopy.dateLatin,
                          style: s.label(s.inkSoft,
                              size: 9.5, tracking: 2.2, weight: FontWeight.w700)),
                      const Spacer(),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Icon(Icons.explore_outlined,
                            size: 17, color: s.accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(title,
                      style: s.display(s.ink,
                          size: s.heroTitleSize,
                          weight: FontWeight.w900,
                          tracking: -1.4)),
                  const SizedBox(height: 6),
                  Text(sub,
                      style: s.body(s.inkSoft, size: 12.5, height: 1.6),
                      maxLines: 2),
                  const SizedBox(height: 15),
                  Row(
                    children: <Widget>[
                      for (final c in chips) ...<Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: Text(c,
                              style: s.label(s.inkSoft,
                                  size: 9.5,
                                  tracking: 0.3,
                                  weight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              s.accent,
                              Color.lerp(s.accent, Colors.white, 0.20)!,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                                color: s.accent.withValues(alpha: 0.32),
                                blurRadius: 16,
                                offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Text(actionLabel,
                            style: s.label(Colors.white,
                                size: 10.5,
                                tracking: 0.3,
                                weight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      );
    case ProbeFlavor.mono:
      return Container(
        decoration: BoxDecoration(
          color: s.surface,
          border: Border(bottom: BorderSide(color: s.hairline, width: 1)),
        ),
        padding: const EdgeInsets.fromLTRB(_gutter, 10, _gutter, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(output ? 'OUTPUT / 输出' : 'INPUT / 输入',
                    style: s.label(s.inkFaint,
                        size: 9, tracking: 1.8, weight: FontWeight.w700)),
                const Spacer(),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: s.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: s.hairline, width: 1),
                  ),
                  child: Icon(Icons.explore_outlined,
                      size: 15, color: s.inkSoft),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(title,
                    style: s.display(s.ink,
                        size: s.heroTitleSize,
                        weight: FontWeight.w800,
                        tracking: -1.4)),
                const Spacer(),
                Text(output ? '4/4' : '01',
                    style: s.number(22, s.inkFaint, weight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 6),
            Text(sub,
                style: s.body(s.inkSoft, size: 12, height: 1.55),
                maxLines: 2),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                for (final c in chips) ...<Widget>[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: s.hairline, width: 1),
                    ),
                    child: Text(c,
                        style: s.label(s.inkSoft, size: 9, tracking: 0.3)),
                  ),
                  const SizedBox(width: 5),
                ],
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: s.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(actionLabel,
                      style: s.label(Colors.white,
                          size: 10, tracking: 0.4, weight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 13),
          ],
        ),
      );
    case ProbeFlavor.press:
      return Container(
        padding: const EdgeInsets.fromLTRB(22, 9, 22, 12),
        child: Column(
          children: <Widget>[
            Text('R E A D F L O W  ·  日 刊',
                style: s.label(s.ink,
                    size: 9, tracking: 3.4, weight: FontWeight.w700)),
            const SizedBox(height: 7),
            Container(height: 2, color: s.ink),
            const SizedBox(height: 1.6),
            Container(height: 0.7, color: s.ink),
            const SizedBox(height: 6),
            Text('2026 年 11 月 2 日 · 星期日 · 第 12 期',
                style: s.label(s.inkSoft, size: 8.5, tracking: 1.1)),
            const SizedBox(height: 9),
            Text(title,
                style: s.display(s.ink,
                    size: s.heroTitleSize,
                    weight: FontWeight.w700,
                    tracking: 3)),
            const SizedBox(height: 4),
            Text(output ? 'WRITE · PRACTISE · IMPROVE' : 'READ · THINK · REVIEW',
                style: s.label(s.inkFaint, size: 8, tracking: 3.0),
                maxLines: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: s.accent,
                  child: Text(actionLabel,
                      style: s.label(Colors.white,
                          size: 10, tracking: 1.6, weight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Text(chips.join('  ·  '),
                    style: s.label(s.inkSoft, size: 9, tracking: 0.6)),
              ],
            ),
            const SizedBox(height: 10),
            Container(height: 0.7, color: s.hairline),
          ],
        ),
      );
  }
}

Widget _blob(Color color, double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: <Color>[
          color.withValues(alpha: 0.38),
          color.withValues(alpha: 0),
        ],
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════
// 题材 tabs
// ══════════════════════════════════════════════════════════════════════

Widget _tabs(ProbeSpec s) {
  switch (s.flavor) {
    case ProbeFlavor.magazine:
      return Row(
        children: <Widget>[
          for (var i = 0; i < _topics.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 15),
              child: Column(
                children: <Widget>[
                  Text(
                    _topics[i].$1,
                    style: s.label(
                      i == 0 ? s.ink : s.inkFaint,
                      size: 12,
                      tracking: 0.8,
                      weight: i == 0 ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 14,
                    height: 2,
                    color: i == 0 ? s.accent : Colors.transparent,
                  ),
                ],
              ),
            ),
        ],
      );
    case ProbeFlavor.night:
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (var i = 0; i < _topics.length; i++) ...<Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: i == 0 ? s.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: i == 0
                        ? s.accent.withValues(alpha: 0.55)
                        : s.hairline,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(_topics[i].$3,
                        size: 12, color: i == 0 ? s.accent : s.inkSoft),
                    const SizedBox(width: 5),
                    Text(
                      _topics[i].$1,
                      style: s.label(
                        i == 0 ? s.accent : s.inkSoft,
                        size: 9.5,
                        tracking: 0.4,
                        weight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      );
    case ProbeFlavor.jelly:
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (var i = 0; i < _topics.length; i++) ...<Widget>[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: i == 0 ? null : Colors.white,
                  gradient: i == 0
                      ? LinearGradient(colors: <Color>[
                          s.accent,
                          Color.lerp(s.accent, Colors.white, 0.20)!,
                        ])
                      : null,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: i == 0
                      ? <BoxShadow>[
                          BoxShadow(
                              color: s.accent.withValues(alpha: 0.30),
                              blurRadius: 14,
                              offset: const Offset(0, 5)),
                        ]
                      : s.cardShadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(_topics[i].$3,
                        size: 13, color: i == 0 ? Colors.white : s.inkSoft),
                    const SizedBox(width: 5),
                    Text(
                      _topics[i].$1,
                      style: s.label(
                        i == 0 ? Colors.white : s.inkSoft,
                        size: 10,
                        tracking: 0.2,
                        weight: i == 0 ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      );
    case ProbeFlavor.mono:
      return Container(
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(s.controlRadius),
          border: Border.all(color: s.hairline, width: 1),
        ),
        child: Row(
          children: <Widget>[
            for (var i = 0; i < _topics.length; i++)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: i == 0 ? s.accentSoft : Colors.transparent,
                    border: Border(
                        bottom: BorderSide(
                            color: i == 0 ? s.accent : Colors.transparent,
                            width: 2)),
                  ),
                  child: Center(
                    child: Text(
                      _topics[i].$1,
                      style: s.label(
                        i == 0 ? s.ink : s.inkFaint,
                        size: 9.5,
                        tracking: 0.5,
                        weight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    case ProbeFlavor.press:
      return Row(
        children: <Widget>[
          for (var i = 0; i < _topics.length; i++) ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: i == 0 ? s.ink : Colors.transparent,
                border:
                    Border.all(color: i == 0 ? s.ink : s.hairline, width: 0.8),
              ),
              child: Text(
                _topics[i].$1,
                style: s.label(
                  i == 0 ? s.bg : s.inkSoft,
                  size: 9.5,
                  tracking: 1.4,
                  weight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
        ],
      );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 继续读(主角卡)
// ══════════════════════════════════════════════════════════════════════

Widget _featured(ProbeSpec s) {
  const domain = GraphicDomain.language;
  final cover = _cover(s,
      seed: '魔',
      domain: domain,
      w: 76,
      h: 100,
      onDarkPlate: s.flavor == ProbeFlavor.magazine);
  switch (s.flavor) {
    case ProbeFlavor.magazine:
      return Container(
        color: const Color(0xFF221F1A),
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            cover,
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('继续读 / CONTINUED',
                          style: s.label(Colors.white.withValues(alpha: 0.60),
                              size: 8.5,
                              tracking: 1.8,
                              weight: FontWeight.w700)),
                      const Spacer(),
                      Text(ProbeCopy.readProgress,
                          style: s.number(11,
                              Colors.white.withValues(alpha: 0.72))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ProbeCopy.readTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: s.display(Colors.white,
                        size: 16,
                        weight: FontWeight.w600,
                        height: 1.4,
                        tracking: 0.2),
                  ),
                  const SizedBox(height: 5),
                  Text(ProbeCopy.readMeta,
                      style: s.label(Colors.white.withValues(alpha: 0.55),
                          size: 9, tracking: 0.5)),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        color: const Color(0xFFF3EEE4),
                        child: Text('接着读',
                            style: s.label(const Color(0xFF221F1A),
                                size: 9.5,
                                tracking: 0.8,
                                weight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 10),
                      Text('材料中心',
                          style: s.label(Colors.white.withValues(alpha: 0.70),
                              size: 9.5, tracking: 0.8)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    case ProbeFlavor.night:
      final tone = s.domainTone(domain);
      return ClipRRect(
        borderRadius: BorderRadius.circular(s.cardRadius),
        child: Container(
          decoration: BoxDecoration(
            color: s.surface,
            border: Border.all(color: s.hairline, width: 1),
            borderRadius: BorderRadius.circular(s.cardRadius),
          ),
          child: Column(
            children: <Widget>[
              Container(height: 2, color: tone),
              Padding(
                padding: const EdgeInsets.all(13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    cover,
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text('继续读',
                                  style: s.label(s.inkSoft,
                                      size: 9, tracking: 1.4)),
                              const Spacer(),
                              _ring(s, 0.62, 28,
                                  label: ProbeCopy.readProgress, labelSize: 6.5),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            ProbeCopy.readTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: s.body(s.ink,
                                size: 14, weight: FontWeight.w700, height: 1.45),
                          ),
                          const SizedBox(height: 5),
                          Text(ProbeCopy.readMeta,
                              style: s.label(s.inkFaint,
                                  size: 9, tracking: 0.4)),
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 11, vertical: 6),
                                decoration: BoxDecoration(
                                  color: s.accent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('接着读',
                                    style: s.label(s.onAccent,
                                        size: 9.5,
                                        tracking: 0.5,
                                        weight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 10),
                              Text('材料中心',
                                  style: s.label(s.inkSoft,
                                      size: 9.5, tracking: 0.6)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    case ProbeFlavor.jelly:
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFFFE9D8), Color(0xFFFFD2BB)],
          ),
          borderRadius: BorderRadius.circular(s.cardRadius),
          boxShadow: s.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            cover,
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('继续读',
                          style: s.label(s.inkSoft,
                              size: 9.5, tracking: 0.8, weight: FontWeight.w800)),
                      const Spacer(),
                      Text(ProbeCopy.readProgress,
                          style: s.number(11, s.ink, weight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    ProbeCopy.readTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: s.body(s.ink,
                        size: 14.5, weight: FontWeight.w800, height: 1.4),
                  ),
                  const SizedBox(height: 5),
                  Text(ProbeCopy.readMeta,
                      style: s.label(s.inkSoft, size: 9, tracking: 0.3)),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: <Color>[
                            s.accent,
                            Color.lerp(s.accent, Colors.white, 0.20)!,
                          ]),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                                color: s.accent.withValues(alpha: 0.28),
                                blurRadius: 12,
                                offset: const Offset(0, 5)),
                          ],
                        ),
                        child: Text('接着读',
                            style: s.label(Colors.white,
                                size: 9.5,
                                tracking: 0.3,
                                weight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('材料中心',
                            style: s.label(s.inkSoft,
                                size: 9.5,
                                tracking: 0.3,
                                weight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    case ProbeFlavor.mono:
      return Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(s.cardRadius),
          border: Border.all(color: s.hairline, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            cover,
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('CONTINUE / 继续读',
                          style: s.label(s.inkFaint,
                              size: 8.5, tracking: 1.1, weight: FontWeight.w700)),
                      const Spacer(),
                      Text(ProbeCopy.readProgress,
                          style:
                              s.number(10.5, s.ink, weight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    ProbeCopy.readTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: s.body(s.ink,
                        size: 13.5, weight: FontWeight.w700, height: 1.45),
                  ),
                  const SizedBox(height: 5),
                  Text(ProbeCopy.readMeta,
                      style: s.label(s.inkFaint, size: 9, tracking: 0.3)),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 110,
                        height: 3,
                        decoration: BoxDecoration(
                            color: s.surfaceAlt,
                            borderRadius: BorderRadius.circular(2)),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.62,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                                color: s.accent,
                                borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text('接着读 →',
                          style: s.label(s.accent,
                              size: 9.5, tracking: 0.5, weight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    case ProbeFlavor.press:
      return Container(
        decoration: BoxDecoration(border: Border.all(color: s.ink, width: 1.2)),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration:
              BoxDecoration(border: Border.all(color: s.hairline, width: 0.7)),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('继 续 读',
                      style: s.label(s.accent,
                          size: 9, tracking: 2.4, weight: FontWeight.w700)),
                  const Spacer(),
                  Text('已读 ${ProbeCopy.readProgress}',
                      style: s.label(s.inkFaint, size: 8.5, tracking: 0.6)),
                ],
              ),
              const SizedBox(height: 8),
              Container(height: 0.7, color: s.hairline),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  cover,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      ProbeCopy.readTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: s.display(s.ink,
                          size: 15,
                          weight: FontWeight.w600,
                          height: 1.5,
                          tracking: 0.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: <Widget>[
                  Text(ProbeCopy.readMeta,
                      style: s.label(s.inkSoft, size: 8.5, tracking: 0.5)),
                  const Spacer(),
                  Text('接着读  →',
                      style: s.label(s.accent,
                          size: 9.5, tracking: 1.2, weight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 四个入口
// ══════════════════════════════════════════════════════════════════════

Widget _entryGrid(ProbeSpec s) {
  Widget cell(int i) {
    final e = _entries[i];
    switch (s.flavor) {
      case ProbeFlavor.magazine:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: s.hairline, width: 0.8))),
          child: Row(
            children: <Widget>[
              Text('0${i + 1}',
                  style: s.number(10, s.accent, weight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(e.$1,
                        style: s.display(s.ink,
                            size: 13, weight: FontWeight.w700, height: 1.35)),
                    const SizedBox(height: 2),
                    Text(e.$2,
                        style: s.label(s.inkSoft, size: 8.5, tracking: 0.3),
                        maxLines: 1),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 11, color: s.inkFaint),
            ],
          ),
        );
      case ProbeFlavor.night:
        return Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(s.cardRadius),
            border: Border.all(color: s.hairline, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: s.domainWash(e.$3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(e.$4, size: 14, color: s.domainTone(e.$3)),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_outward, size: 12, color: s.inkFaint),
                ],
              ),
              const SizedBox(height: 9),
              Text(e.$1, style: s.body(s.ink, size: 12.5, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(e.$2,
                  style: s.label(s.inkFaint, size: 8.5, tracking: 0.3),
                  maxLines: 1),
            ],
          ),
        );
      case ProbeFlavor.jelly:
        return Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _jellyFills[i % _jellyFills.length],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: s.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 27,
                    height: 27,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        shape: BoxShape.circle),
                    child: Icon(e.$4, size: 14, color: s.domainTone(e.$3)),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_outward, size: 13, color: s.inkSoft),
                ],
              ),
              const SizedBox(height: 9),
              Text(e.$1, style: s.body(s.ink, size: 12.5, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(e.$2,
                  style: s.label(s.inkSoft, size: 8.5, tracking: 0.3),
                  maxLines: 1),
            ],
          ),
        );
      case ProbeFlavor.mono:
        return Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: BorderRadius.circular(s.cardRadius),
            border: Border.all(color: s.hairline, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(width: 6, height: 6, color: s.domainTone(e.$3)),
                  const Spacer(),
                  Icon(Icons.arrow_outward, size: 12, color: s.inkFaint),
                ],
              ),
              const SizedBox(height: 9),
              Text(e.$1, style: s.body(s.ink, size: 12, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(e.$2,
                  style: s.label(s.inkFaint, size: 8.5, tracking: 0.4),
                  maxLines: 1),
            ],
          ),
        );
      case ProbeFlavor.press:
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
          decoration: BoxDecoration(
              border: Border.all(color: s.hairline, width: 0.8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('0${i + 1}',
                      style: s.label(s.accent,
                          size: 8.5, tracking: 1.2, weight: FontWeight.w700)),
                  const Spacer(),
                  Icon(Icons.arrow_forward, size: 11, color: s.inkFaint),
                ],
              ),
              const SizedBox(height: 7),
              Text(e.$1,
                  style: s.display(s.ink,
                      size: 12.5, weight: FontWeight.w700, tracking: 0.5)),
              const SizedBox(height: 2),
              Text(e.$2,
                  style: s.label(s.inkSoft, size: 8.5, tracking: 0.3),
                  maxLines: 1),
            ],
          ),
        );
    }
  }

  return Column(
    children: <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Expanded(child: cell(0)),
        const SizedBox(width: 10),
        Expanded(child: cell(1)),
      ]),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Expanded(child: cell(2)),
        const SizedBox(width: 10),
        Expanded(child: cell(3)),
      ]),
    ],
  );
}

// ══════════════════════════════════════════════════════════════════════
// 区块标题
// ══════════════════════════════════════════════════════════════════════

Widget _section(
  ProbeSpec s, {
  required String index,
  required String cnIndex,
  required String latin,
  required String title,
  String? subtitle,
}) {
  switch (s.flavor) {
    case ProbeFlavor.magazine:
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(index, style: s.number(10, s.accent, weight: FontWeight.w700)),
                const SizedBox(width: 9),
                Text(title,
                    style: s.display(s.ink,
                        size: 18, weight: FontWeight.w700, tracking: 0.5)),
                const SizedBox(width: 10),
                Expanded(child: Container(height: 0.8, color: s.hairline)),
              ],
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Text(subtitle,
                    style: s.label(s.inkSoft, size: 9.5, tracking: 0.4)),
              ),
            ],
          ],
        ),
      );
    case ProbeFlavor.night:
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(width: 14, height: 1.6, color: s.accent),
                const SizedBox(width: 8),
                Text(latin,
                    style: s.label(s.inkFaint,
                        size: 8.5, tracking: 1.4, weight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text(title, style: s.body(s.ink, size: 15, weight: FontWeight.w700)),
              ],
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 3),
              Text(subtitle,
                  style: s.label(s.inkFaint, size: 9, tracking: 0.3)),
            ],
          ],
        ),
      );
    case ProbeFlavor.jelly:
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(
          children: <Widget>[
            Text(title,
                style: s.body(s.ink, size: 16.5, weight: FontWeight.w800)),
            const SizedBox(width: 8),
            if (subtitle != null)
              Expanded(
                child: Text(subtitle,
                    style: s.label(s.inkFaint, size: 9, tracking: 0.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            const Spacer(),
            Text(index, style: s.number(11, s.accent, weight: FontWeight.w800)),
          ],
        ),
      );
    case ProbeFlavor.mono:
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 7),
        child: Row(
          children: <Widget>[
            Text(index,
                style: s.number(10, s.inkFaint, weight: FontWeight.w600)),
            const SizedBox(width: 9),
            Text(title, style: s.body(s.ink, size: 14, weight: FontWeight.w800)),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 0.8, color: s.hairline)),
            const SizedBox(width: 8),
            Text(latin, style: s.label(s.inkFaint, size: 8, tracking: 1.0)),
          ],
        ),
      );
    case ProbeFlavor.press:
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(cnIndex,
                    style: s.display(s.accent, size: 13, weight: FontWeight.w700)),
                const SizedBox(width: 7),
                Container(width: 1, height: 12, color: s.ink),
                const SizedBox(width: 7),
                Text(title,
                    style: s.display(s.ink,
                        size: 16, weight: FontWeight.w700, tracking: 0.8)),
                const SizedBox(width: 10),
                Expanded(child: Container(height: 0.7, color: s.hairline)),
              ],
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 3),
              Text(subtitle,
                  style: s.label(s.inkSoft, size: 8.5, tracking: 0.5)),
            ],
          ],
        ),
      );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 列表卡
// ══════════════════════════════════════════════════════════════════════

Widget _row(
  ProbeSpec s, {
  required String title,
  required String meta,
  required GraphicDomain domain,
  required String seed,
  bool dense = false,
}) {
  final cover = _cover(s,
      seed: seed, domain: domain, w: dense ? 32 : 38, h: dense ? 42 : 50);
  final titleStyle =
      s.body(s.ink, size: dense ? 12.5 : 13.5, weight: FontWeight.w700, height: 1.4);
  final metaStyle = s.label(s.inkSoft, size: 9, tracking: 0.3);
  switch (s.flavor) {
    case ProbeFlavor.magazine:
      return Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? 7 : 9),
            child: Row(
              children: <Widget>[
                cover,
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: s.display(s.ink,
                            size: dense ? 12.5 : 13.5,
                            weight: FontWeight.w600,
                            height: 1.45),
                      ),
                      const SizedBox(height: 3),
                      Text(meta, style: metaStyle, maxLines: 1),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 12, color: s.inkFaint),
              ],
            ),
          ),
          Container(height: 0.8, color: s.hairline),
        ],
      );
    case ProbeFlavor.night:
      return Container(
        margin: EdgeInsets.only(bottom: dense ? 6 : 8),
        padding: EdgeInsets.all(dense ? 9 : 11),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(s.cardRadius),
          border: Border.all(color: s.hairline, width: 1),
        ),
        child: Row(
          children: <Widget>[
            cover,
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle),
                  const SizedBox(height: 4),
                  Text(meta, style: metaStyle, maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 14, color: s.inkFaint),
          ],
        ),
      );
    case ProbeFlavor.jelly:
      return Container(
        margin: EdgeInsets.only(bottom: dense ? 6 : 9),
        padding: EdgeInsets.all(dense ? 9 : 11),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(s.cardRadius),
          boxShadow: s.cardShadow,
        ),
        child: Row(
          children: <Widget>[
            cover,
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: s.body(s.ink,
                          size: dense ? 12.5 : 13.5,
                          weight: FontWeight.w700,
                          height: 1.4)),
                  const SizedBox(height: 4),
                  Text(meta, style: metaStyle, maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 15, color: s.inkFaint),
          ],
        ),
      );
    case ProbeFlavor.mono:
      return Container(
        margin: EdgeInsets.only(bottom: dense ? 6 : 8),
        padding: EdgeInsets.all(dense ? 9 : 11),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(s.cardRadius),
          border: Border.all(color: s.hairline, width: 1),
        ),
        child: Row(
          children: <Widget>[
            cover,
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle),
                  const SizedBox(height: 4),
                  Text(meta,
                      style: s.label(s.inkFaint, size: 9, tracking: 0.3),
                      maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_outward, size: 12, color: s.inkFaint),
          ],
        ),
      );
    case ProbeFlavor.press:
      return Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? 7 : 9),
            child: Row(
              children: <Widget>[
                cover,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: s.display(s.ink,
                            size: dense ? 12.5 : 13.5,
                            weight: FontWeight.w600,
                            height: 1.45,
                            tracking: 0.2),
                      ),
                      const SizedBox(height: 3),
                      Text(meta,
                          style: s.label(s.inkSoft,
                              size: 8.5, tracking: 0.4),
                          maxLines: 1),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 12, color: s.inkFaint),
              ],
            ),
          ),
          Container(height: 0.7, color: s.hairline),
        ],
      );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 数据块
// ══════════════════════════════════════════════════════════════════════

Widget _stats(ProbeSpec s, {bool dense = false}) {
  final h = dense ? 46.0 : 62.0;
  final valueSize = dense ? 17.0 : 21.0;

  Widget plainCell(int i, {Color? valueColor}) {
    final st = _statItems[i];
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: s.flavor == ProbeFlavor.magazine
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: <Widget>[
          Text(st.$1,
              style: s.number(valueSize, valueColor ?? s.ink,
                  weight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(st.$2,
              style: s.label(s.inkSoft, size: dense ? 8 : 9, tracking: 0.3)),
        ],
      ),
    );
  }

  Widget cardCell(int i, {required Color valueColor, required double radius}) {
    final st = _statItems[i];
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: s.softShadow ? s.cardShadow : null,
          border: s.softShadow ? null : Border.all(color: s.hairline, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(st.$1,
                style: s.number(valueSize, valueColor,
                    weight: s.softShadow ? FontWeight.w900 : FontWeight.w600)),
            const SizedBox(height: 4),
            Text(st.$2,
                style: s.label(s.inkSoft, size: 8, tracking: 0.4)),
          ],
        ),
      ),
    );
  }

  switch (s.flavor) {
    case ProbeFlavor.magazine:
      return SizedBox(
        height: h,
        child: Row(
          children: <Widget>[
            plainCell(0),
            Container(width: 0.8, height: h * 0.62, color: s.hairline),
            plainCell(1),
            Container(width: 0.8, height: h * 0.62, color: s.hairline),
            plainCell(2),
          ],
        ),
      );
    case ProbeFlavor.night:
      return SizedBox(
        height: h,
        child: Row(
          children: <Widget>[
            cardCell(0, valueColor: s.ink, radius: 12),
            const SizedBox(width: 7),
            cardCell(1, valueColor: s.accent, radius: 12),
            const SizedBox(width: 7),
            cardCell(2, valueColor: s.ink, radius: 12),
          ],
        ),
      );
    case ProbeFlavor.jelly:
      return SizedBox(
        height: h,
        child: Row(
          children: <Widget>[
            cardCell(0, valueColor: s.domainTone(_statItems[0].$3), radius: 18),
            const SizedBox(width: 7),
            cardCell(1, valueColor: s.domainTone(_statItems[1].$3), radius: 18),
            const SizedBox(width: 7),
            cardCell(2, valueColor: s.domainTone(_statItems[2].$3), radius: 18),
          ],
        ),
      );
    case ProbeFlavor.mono:
      return Container(
        height: h,
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(s.cardRadius),
          border: Border.all(color: s.hairline, width: 1),
        ),
        child: Row(
          children: <Widget>[
            for (var i = 0; i < 3; i++) ...<Widget>[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(left: 11),
                      child: Text(_statItems[i].$1,
                          style: s.number(valueSize,
                              i == 1 ? s.accent : s.ink,
                              weight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 11),
                      child: Text(_statItems[i].$2,
                          style: s.label(s.inkFaint,
                              size: 8, tracking: 0.3)),
                    ),
                  ],
                ),
              ),
              if (i < 2) Container(width: 1, height: h, color: s.hairline),
            ],
          ],
        ),
      );
    case ProbeFlavor.press:
      return Container(
        decoration: BoxDecoration(border: Border.all(color: s.ink, width: 0.8)),
        padding: const EdgeInsets.all(2.5),
        child: Container(
          decoration:
              BoxDecoration(border: Border.all(color: s.hairline, width: 0.6)),
          child: SizedBox(
            height: h,
            child: Row(
              children: <Widget>[
                plainCell(0, valueColor: s.ink),
                Container(width: 0.6, height: h * 0.6, color: s.hairline),
                plainCell(1, valueColor: s.accent),
                Container(width: 0.6, height: h * 0.6, color: s.hairline),
                plainCell(2, valueColor: s.ink),
              ],
            ),
          ),
        ),
      );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 四阶阶段卡
// ══════════════════════════════════════════════════════════════════════

Widget _stage(ProbeSpec s, {required int index}) {
  final (title, sub, cnLabel, domain, progress, active) = _stages[index];
  final percent = '${(progress * 100).round()}%';
  switch (s.flavor) {
    case ProbeFlavor.magazine:
      final fg = active ? const Color(0xFFF3EEE4) : s.ink;
      final soft =
          active ? const Color(0xFFF3EEE4).withValues(alpha: 0.62) : s.inkSoft;
      return Container(
        color: active ? s.ink : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        margin: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: <Widget>[
            Text(_cnNumeral(index),
                style: s.display(active ? s.accent : s.inkFaint,
                    size: 20, weight: FontWeight.w700)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: s.display(fg,
                          size: 16, weight: FontWeight.w700, tracking: 0.5)),
                  const SizedBox(height: 3),
                  Text(sub,
                      style: s.label(soft, size: 9, tracking: 0.3),
                      maxLines: 1),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(percent,
                    style: s.number(11,
                        active ? const Color(0xFFF3EEE4) : s.ink,
                        weight: FontWeight.w700)),
                const SizedBox(height: 5),
                Container(
                  width: 62,
                  height: 2,
                  color: active
                      ? const Color(0xFFF3EEE4).withValues(alpha: 0.22)
                      : s.hairline,
                ),
              ],
            ),
            const SizedBox(width: 10),
            Text(active ? '继续' : '开始',
                style: s.label(active ? const Color(0xFFF3EEE4) : s.accent,
                    size: 9.5, tracking: 0.8, weight: FontWeight.w800)),
          ],
        ),
      );
    case ProbeFlavor.night:
      final tone = s.domainTone(domain);
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(s.cardRadius),
          border: Border.all(color: s.hairline, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: <Widget>[
            Container(width: 3, height: 74, color: tone),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: Row(
                  children: <Widget>[
                    _ring(s, progress, 34,
                        label: _cnNumeral(index),
                        labelSize: 8,
                        track: s.hairline),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(title,
                              style: s.body(s.ink,
                                  size: 14.5, weight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(sub,
                              style: s.label(s.inkFaint,
                                  size: 8.5, tracking: 0.3),
                              maxLines: 1),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Text(percent,
                            style: s.number(10.5, s.ink,
                                weight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(active ? '继续' : '开始',
                            style: s.label(s.accent,
                                size: 9, tracking: 0.6, weight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    case ProbeFlavor.jelly:
      return Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _jellyFills[index % _jellyFills.length],
          ),
          borderRadius: BorderRadius.circular(s.cardRadius),
          boxShadow: s.cardShadow,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle),
              child: Center(
                child: V4ProgressRing(
                  value: progress,
                  size: 26,
                  color: s.domainTone(domain),
                  trackColor: s.inkFaint.withValues(alpha: 0.20),
                  strokeWidth: 2.5,
                  center: Text(percent,
                      style: s.label(s.ink,
                          size: 6.5, tracking: 0.1, weight: FontWeight.w800)),
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: s.body(s.ink, size: 14, weight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(sub,
                      style: s.label(s.inkSoft, size: 8.5, tracking: 0.2),
                      maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(active ? '继续' : '开始',
                  style: s.label(s.domainTone(domain),
                      size: 9, tracking: 0.2, weight: FontWeight.w800)),
            ),
          ],
        ),
      );
    case ProbeFlavor.mono:
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: s.hairline, width: 1)),
        ),
        child: Row(
          children: <Widget>[
            _ring(s, progress, 18, track: s.hairline),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: s.body(s.ink, size: 13.5, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(sub,
                      style: s.label(s.inkFaint, size: 8.5, tracking: 0.3),
                      maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(percent, style: s.number(10.5, s.ink, weight: FontWeight.w600)),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 14, color: s.inkFaint),
          ],
        ),
      );
    case ProbeFlavor.press:
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: s.hairline, width: 0.8)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 26,
              height: 32,
              color: s.domainWash(domain),
              child: Center(
                child: Text(_cnNumeral(index),
                    style: s.display(s.domainTone(domain),
                        size: 13, weight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: s.display(s.ink,
                          size: 15.5, weight: FontWeight.w700, tracking: 0.8)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: s.label(s.inkSoft, size: 8.5, tracking: 0.3),
                      maxLines: 1),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(percent, style: s.number(11, s.ink, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(active ? '进行中' : '未开始',
                    style: s.label(active ? s.accent : s.inkFaint,
                        size: 8, tracking: 0.8, weight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      );
  }
}

String _cnNumeral(int index) => const <String>['壹', '贰', '叁', '肆'][index % 4];

// ══════════════════════════════════════════════════════════════════════
// 空态
// ══════════════════════════════════════════════════════════════════════

Widget _empty(ProbeSpec s, {bool dense = false}) {
  final pad = dense ? 10.0 : 22.0;
  switch (s.flavor) {
    case ProbeFlavor.magazine:
      return Padding(
        padding: EdgeInsets.symmetric(vertical: pad * 0.7),
        child: Column(
          children: <Widget>[
            Text('空',
                style: s.display(s.ink.withValues(alpha: 0.10),
                    size: 40, weight: FontWeight.w700, height: 1.0)),
            const SizedBox(height: 6),
            Text(ProbeCopy.emptyTitle,
                style: s.display(s.ink, size: 14, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(ProbeCopy.emptyHint,
                textAlign: TextAlign.center,
                style: s.label(s.inkSoft,
                    size: 9, tracking: 0.3, weight: FontWeight.w500),
                maxLines: 2),
            const SizedBox(height: 7),
            Text('去找一篇 →',
                style: s.label(s.accent,
                    size: 9.5, tracking: 0.8, weight: FontWeight.w800)),
          ],
        ),
      );
    case ProbeFlavor.night:
      return Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(s.cardRadius),
          border: Border.all(color: s.hairline, width: 1),
        ),
        child: Column(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration:
                  BoxDecoration(color: s.accentSoft, shape: BoxShape.circle),
              child: Icon(Icons.auto_stories_outlined, size: 20, color: s.accent),
            ),
            const SizedBox(height: 9),
            Text(ProbeCopy.emptyTitle,
                style: s.body(s.ink, size: 13, weight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(ProbeCopy.emptyHint,
                textAlign: TextAlign.center,
                style: s.label(s.inkFaint,
                    size: 8.5, tracking: 0.3, weight: FontWeight.w500),
                maxLines: 2),
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: s.accent.withValues(alpha: 0.6), width: 1),
              ),
              child: Text('去找材料',
                  style: s.label(s.accent,
                      size: 9, tracking: 0.6, weight: FontWeight.w700)),
            ),
          ],
        ),
      );
    case ProbeFlavor.jelly:
      return Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFEAF0FF), Color(0xFFFFEFF4)],
          ),
          borderRadius: BorderRadius.circular(s.cardRadius),
        ),
        child: Column(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  shape: BoxShape.circle),
              child: Icon(Icons.auto_stories_outlined, size: 21, color: s.accent),
            ),
            const SizedBox(height: 9),
            Text(ProbeCopy.emptyTitle,
                style: s.body(s.ink, size: 13, weight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(ProbeCopy.emptyHint,
                textAlign: TextAlign.center,
                style: s.label(s.inkSoft,
                    size: 8.5, tracking: 0.2, weight: FontWeight.w500),
                maxLines: 2),
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: s.accent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: s.accent.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: Text('去找材料',
                  style: s.label(Colors.white,
                      size: 9, tracking: 0.2, weight: FontWeight.w800)),
            ),
          ],
        ),
      );
    case ProbeFlavor.mono:
      return Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(s.cardRadius),
          border: Border.all(color: s.hairline, width: 1),
        ),
        child: Column(
          children: <Widget>[
            Icon(Icons.auto_stories_outlined, size: 18, color: s.inkFaint),
            const SizedBox(height: 8),
            Text(ProbeCopy.emptyTitle,
                style: s.body(s.ink, size: 12.5, weight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(ProbeCopy.emptyHint,
                textAlign: TextAlign.center,
                style: s.label(s.inkFaint,
                    size: 8.5, tracking: 0.3, weight: FontWeight.w500),
                maxLines: 2),
            const SizedBox(height: 8),
            Text('+ 去找一篇',
                style: s.label(s.accent,
                    size: 9, tracking: 0.5, weight: FontWeight.w700)),
          ],
        ),
      );
    case ProbeFlavor.press:
      return Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(border: Border.all(color: s.ink, width: 0.8)),
        child: Column(
          children: <Widget>[
            Text('·  ·  ·', style: s.label(s.inkFaint, size: 10, tracking: 4)),
            const SizedBox(height: 7),
            Text(ProbeCopy.emptyTitle,
                style: s.display(s.ink,
                    size: 14, weight: FontWeight.w700, tracking: 0.8)),
            const SizedBox(height: 4),
            Text(ProbeCopy.emptyHint,
                textAlign: TextAlign.center,
                style: s.label(s.inkSoft,
                    size: 8.5, tracking: 0.4, weight: FontWeight.w500),
                maxLines: 2),
            const SizedBox(height: 7),
            Text('去找一篇  →',
                style: s.label(s.accent,
                    size: 9.5, tracking: 1.0, weight: FontWeight.w700)),
          ],
        ),
      );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 小件：封面 / 胶囊按钮 / 标签 / 进度环
// ══════════════════════════════════════════════════════════════════════

Widget _cover(
  ProbeSpec s, {
  required String seed,
  required GraphicDomain domain,
  required double w,
  required double h,
  bool onDarkPlate = false,
}) {
  final tone = s.domainTone(domain);
  switch (s.flavor) {
    case ProbeFlavor.magazine:
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: onDarkPlate ? const Color(0xFFF3EEE4) : const Color(0xFFF5EFE2),
          border: Border.all(color: const Color(0xFFD8CFBC), width: 0.8),
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD8CFBC), width: 0.5)),
          child: Stack(
            children: <Widget>[
              Center(
                child: Text(seed,
                    style: s.display(const Color(0xFF1D1A15),
                        size: h * 0.26, weight: FontWeight.w700)),
              ),
              Positioned(
                left: 3,
                bottom: 3,
                child: Text('B2',
                    style: s.label(s.accent,
                        size: 5.5, tracking: 0.2, weight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
    case ProbeFlavor.night:
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: w,
          height: h,
          color: s.surfaceAlt,
          child: Column(
            children: <Widget>[
              Container(height: 1.5, color: tone),
              Expanded(
                child: Center(
                  child: Text(seed,
                      style: s.display(tone,
                          size: h * 0.28, weight: FontWeight.w700)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('B2',
                    style: s.label(s.inkFaint, size: 5, tracking: 0.4)),
              ),
            ],
          ),
        ),
      );
    case ProbeFlavor.jelly:
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          gradient: s.domainGradient(domain),
          borderRadius: BorderRadius.circular(h * 0.18),
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Text(seed,
                  style: s.display(s.ink,
                      size: h * 0.28, weight: FontWeight.w900)),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4)),
                child: Text('B2',
                    style: s.label(s.inkSoft,
                        size: 5, tracking: 0.2, weight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
    case ProbeFlavor.mono:
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: s.hairline, width: 1),
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Text(seed,
                  style: s.label(s.ink,
                      size: h * 0.22, tracking: 0.6, weight: FontWeight.w700)),
            ),
            Positioned(
                left: 3, top: 3, child: Container(width: 4, height: 4, color: tone)),
            Positioned(
              right: 3,
              bottom: 3,
              child: Text('B2', style: s.label(s.inkFaint, size: 5, tracking: 0.2)),
            ),
          ],
        ),
      );
    case ProbeFlavor.press:
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(border: Border.all(color: s.ink, width: 0.8)),
        padding: const EdgeInsets.all(2),
        child: Container(
          decoration:
              BoxDecoration(border: Border.all(color: s.hairline, width: 0.5)),
          child: Stack(
            children: <Widget>[
              Center(
                child: Text(seed,
                    style: s.display(s.accent,
                        size: h * 0.26, weight: FontWeight.w700)),
              ),
              Positioned(
                left: 2,
                bottom: 2,
                child: Text('B2',
                    style: s.label(s.inkSoft,
                        size: 5, tracking: 0.2, weight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
  }
}

Widget _filledPill(ProbeSpec s, String label) {
  final radius = s.flavor == ProbeFlavor.magazine || s.flavor == ProbeFlavor.press
      ? BorderRadius.zero
      : BorderRadius.circular(999);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
    decoration: BoxDecoration(
      color: s.accent,
      borderRadius: radius,
      boxShadow: s.softShadow
          ? <BoxShadow>[
              BoxShadow(
                  color: s.accent.withValues(alpha: 0.30),
                  blurRadius: 14,
                  offset: const Offset(0, 6)),
            ]
          : null,
    ),
    child: Text(label,
        style: s.label(Colors.white,
            size: 9.5, tracking: 0.5, weight: FontWeight.w800)),
  );
}

Widget _outlinePill(ProbeSpec s, String label) {
  final radius = s.flavor == ProbeFlavor.magazine || s.flavor == ProbeFlavor.press
      ? BorderRadius.zero
      : BorderRadius.circular(999);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      borderRadius: radius,
      border: Border.all(
          color: s.flavor == ProbeFlavor.press
              ? s.hairline
              : s.ink.withValues(alpha: 0.25),
          width: 1),
    ),
    child: Text(label,
        style: s.label(s.inkSoft,
            size: 9.5, tracking: 0.5, weight: FontWeight.w600)),
  );
}

Widget _tag(ProbeSpec s, String label) {
  switch (s.flavor) {
    case ProbeFlavor.magazine:
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration:
            BoxDecoration(border: Border.all(color: s.hairline, width: 0.7)),
        child: Text(label, style: s.label(s.inkSoft, size: 7.5, tracking: 0.6)),
      );
    case ProbeFlavor.night:
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: s.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: s.hairline, width: 0.8),
        ),
        child: Text(label, style: s.label(s.inkSoft, size: 7.5, tracking: 0.5)),
      );
    case ProbeFlavor.jelly:
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: s.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: s.label(s.accent,
                size: 8, tracking: 0.2, weight: FontWeight.w700)),
      );
    case ProbeFlavor.mono:
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: s.hairline, width: 1),
        ),
        child: Text(label, style: s.label(s.inkSoft, size: 7.5, tracking: 0.4)),
      );
    case ProbeFlavor.press:
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            border: Border.all(
                color: s.accent.withValues(alpha: 0.55), width: 0.7)),
        child: Text(label,
            style: s.label(s.accent,
                size: 7.5, tracking: 0.8, weight: FontWeight.w600)),
      );
  }
}

Widget _ring(ProbeSpec s, double value, double size,
    {String? label, double labelSize = 7.5, Color? track}) {
  return V4ProgressRing(
    value: value,
    size: size,
    color: s.flavor == ProbeFlavor.magazine || s.flavor == ProbeFlavor.press
        ? s.ink
        : s.accent,
    trackColor: track ?? s.hairline,
    strokeWidth: size > 40 ? 3.5 : 2.6,
    center: label == null
        ? null
        : Text(label,
            style: s.label(s.ink,
                size: labelSize, tracking: 0.2, weight: FontWeight.w700)),
  );
}

// ══════════════════════════════════════════════════════════════════════
// 纸感噪点
// ══════════════════════════════════════════════════════════════════════

class _PaperGrain extends CustomPainter {
  _PaperGrain({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: opacity);
    final rnd = math.Random(20261103);
    final count = (size.width * size.height / 120).clamp(200, 3200).round();
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = 0.35 + rnd.nextDouble() * 0.85;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGrain old) =>
      old.opacity != opacity || old.color != color;
}
