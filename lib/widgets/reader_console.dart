import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'reader_paper.dart';
import 'reader_progress.dart';
import 'reader_sheets.dart';

/// 上滑「阅读控制台」(C 方案 §4 的 4 组)。
///
/// C 方案的核心承诺是**底部零常驻按钮**:所有动作收进一次上滑。控制台按
/// 设计稿固定 4 组,顺序也是固定的 ——
///
/// 1. **进度卡**:已读 + 第 N 段 / 共 M 段 + 34px 大数字 + 继续阅读 + 3px 进度线;
/// 2. **学习**:翻译 / 追问 / 收词 三块等宽方块(+ 收词保存位置一行);
/// 3. **目录**:3 行紧凑行(序号 + 节名 + 本节 %),多于 3 节给「全部 N 节」入口;
/// 4. **材料**:字号与行距 / 模型与思考档 / 丰富形式 / 导出·听写·读完。
///
/// 为什么所有字段都由外面传一个 [ReaderConsoleData] 进来:这段 UI 是纯展示,
/// 页面里 3000 行的业务状态不需要知道控制台长什么样;渲染测试也就能用假数据
/// 把生产组件真跑一遍(见 `test/reader_c_render_test.dart`)。
class ReaderConsoleData {
  const ReaderConsoleData({
    required this.palette,
    required this.progress,
    required this.currentUnit,
    required this.totalUnits,
    required this.currentChunk,
    required this.chunkTitles,
    required this.chunkPercents,
    required this.translationDone,
    required this.translationTotal,
    required this.showTranslation,
    required this.pickedCount,
    required this.finished,
    required this.onShelf,
    required this.fontLabel,
    required this.modelLabel,
    required this.saveTargetLabel,
    required this.hasRichForms,
    required this.onContinue,
    required this.onToggleTranslation,
    required this.onFollowUp,
    required this.onSavePicked,
    required this.onChangeSaveTarget,
    required this.onToggleShelf,
    required this.onJumpChunk,
    required this.onOpenFullToc,
    required this.onOpenSettings,
    required this.onOpenModel,
    required this.onOpenRichForms,
    required this.onOpenMaterialActions,
  });

  final ReaderPalette palette;

  /// 阅读进度 0~1(只重建进度卡里的数字与线)
  final ValueListenable<double> progress;

  /// 当前第几段(0 起 -> 显示时 +1)
  final int currentUnit;
  final int totalUnits;

  /// 当前第几节(0 起)
  final int currentChunk;
  final List<String> chunkTitles;
  final List<double> chunkPercents;

  final int translationDone;
  final int translationTotal;
  final bool showTranslation;
  final int pickedCount;
  final bool finished;
  final bool onShelf;

  /// 「18 号 · 标准」
  final String fontLabel;

  /// 「deepseek-chat · 标准」
  final String modelLabel;
  final String saveTargetLabel;
  final bool hasRichForms;

  final VoidCallback onContinue;
  final VoidCallback onToggleTranslation;
  final VoidCallback onFollowUp;
  final VoidCallback onSavePicked;
  final VoidCallback onChangeSaveTarget;
  final VoidCallback onToggleShelf;
  final void Function(int index) onJumpChunk;
  final VoidCallback onOpenFullToc;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenModel;
  final VoidCallback onOpenRichForms;
  final VoidCallback onOpenMaterialActions;
}

class ReaderConsoleSheet extends StatelessWidget {
  const ReaderConsoleSheet({super.key, required this.data});

  final ReaderConsoleData data;

  /// 控制台最高高度(设计稿 560~640px)
  static const double maxHeight = 640;

  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final p = data.palette;
    final h = MediaQuery.of(context).size.height;
    return ReaderSheetSurface(
      palette: p,
      maxHeight: math.min(maxHeight, h * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── 头部:标题 + 书架开关 + 收起 ──
          Row(
            children: <Widget>[
              ReaderSheetTitle('阅读控制台', palette: p),
              const Spacer(),
              IconButton(
                key: const ValueKey<String>('reader-console-shelf'),
                tooltip: data.onShelf ? '已在书架上(点一下移出)' : '加入书架',
                onPressed: () => _closeThen(context, data.onToggleShelf),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  data.onShelf
                      ? Icons.collections_bookmark
                      : Icons.collections_bookmark_outlined,
                  size: 19,
                  color: data.onShelf ? p.accent : p.inkSoft,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey<String>('reader-console-close'),
                tooltip: '收起',
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(Icons.keyboard_arrow_down,
                    size: 22, color: p.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _progressGroup(p),
          const SizedBox(height: 16),
          ReaderSheetLabel('学习', palette: p),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ReaderSheetTile(
                  palette: p,
                  icon: Icons.translate,
                  title: '翻译',
                  sub: data.showTranslation
                      ? '已翻 ${data.translationDone}/${data.translationTotal} 段'
                      : '逐段中英对照',
                  active: data.showTranslation,
                  onTap: () => _closeThen(context, data.onToggleTranslation),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ReaderSheetTile(
                  palette: p,
                  icon: Icons.chat_bubble_outline,
                  title: '追问',
                  sub: '带原文追问',
                  onTap: () => _closeThen(context, data.onFollowUp),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ReaderSheetTile(
                  palette: p,
                  icon: Icons.bookmark_add_outlined,
                  title: '收词',
                  sub: data.pickedCount > 0
                      ? '本次 ${data.pickedCount} 个'
                      : '点词即收',
                  onTap: () => _closeThen(context, data.onSavePicked),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ReaderSheetRow(
            palette: p,
            leading: '存',
            title: '收词存到:${data.saveTargetLabel}',
            trailing: '改',
            onTap: () => _closeThen(context, data.onChangeSaveTarget),
          ),
          const SizedBox(height: 6),
          ReaderSheetLabel('目录', palette: p),
          const SizedBox(height: 8),
          ..._tocRows(context, p),
          const SizedBox(height: 10),
          ReaderSheetLabel('材料', palette: p),
          const SizedBox(height: 8),
          ReaderSheetRow(
            palette: p,
            leading: 'Aa',
            title: '字号与行距',
            trailing: data.fontLabel,
            onTap: () => _closeThen(context, data.onOpenSettings),
          ),
          ReaderSheetRow(
            palette: p,
            leading: 'AI',
            title: '模型与思考档',
            trailing: data.modelLabel,
            onTap: () => _closeThen(context, data.onOpenModel),
          ),
          if (data.hasRichForms)
            ReaderSheetRow(
              palette: p,
              leading: 'Fx',
              title: '丰富形式',
              trailing: '表格 / 导图 / 时间线',
              onTap: () => _closeThen(context, data.onOpenRichForms),
            ),
          ReaderSheetRow(
            palette: p,
            leading: '↓',
            title: data.finished ? '导出 / 听写(已读完)' : '导出 / 听写 / 读完',
            trailing: 'Markdown',
            onTap: () => _closeThen(context, data.onOpenMaterialActions),
          ),
        ],
      ),
    );
  }

  /// 组 1 · 进度卡
  Widget _progressGroup(ReaderPalette p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: p.page,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ReaderSheetLabel('已读', palette: p),
              const Spacer(),
              Text(
                '第 ${(data.currentUnit + 1).clamp(1, math.max(1, data.totalUnits))} 段'
                ' / 共 ${data.totalUnits} 段',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  color: p.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<double>(
            valueListenable: data.progress,
            builder: (_, raw, _) {
              final ratio = raw.clamp(0.0, 1.0);
              final pct = (ratio * 100).round();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        '$pct',
                        key: const ValueKey<String>('reader-console-percent'),
                        style: TextStyle(
                          fontSize: 34,
                          height: 1.0,
                          letterSpacing: -1.5,
                          fontWeight: FontWeight.w900,
                          color: p.accent,
                        ),
                      ),
                      Text(
                        '%',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          fontWeight: FontWeight.w800,
                          color: p.accent,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        key: const ValueKey<String>(
                            'reader-console-continue'),
                        onTap: data.onContinue,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: p.ink,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '继续阅读',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: p.onInk,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ReaderProgressBar(ratio: ratio, palette: p),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 组 3 · 目录:固定 3 行紧凑行(多出的走「全部 N 节」)
  List<Widget> _tocRows(BuildContext context, ReaderPalette p) {
    final titles = data.chunkTitles;
    if (titles.isEmpty) {
      return <Widget>[
        Text(
          '这篇材料没有分节信息,先往下读吧',
          style: TextStyle(fontSize: 11, height: 1.4, color: p.inkFaint),
        ),
      ];
    }
    final count = titles.length;
    final start = count <= 3 ? 0 : data.currentChunk.clamp(0, count - 3);
    final end = math.min(start + 3, count);
    return <Widget>[
      for (var i = start; i < end; i++)
        ReaderSheetRow(
          palette: p,
          leading: '${i + 1}'.padLeft(2, '0'),
          title: titles[i],
          trailing:
              '${(i < data.chunkPercents.length ? data.chunkPercents[i] : 0).round()}%',
          current: i == data.currentChunk,
          onTap: () => _closeThen(context, () => data.onJumpChunk(i)),
        ),
      if (count > 3)
        ReaderSheetRow(
          palette: p,
          leading: '⋯',
          title: '全部 $count 节',
          trailing: '完整目录',
          onTap: () => _closeThen(context, data.onOpenFullToc),
        ),
    ];
  }
}
