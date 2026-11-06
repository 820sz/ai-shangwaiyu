import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../config/constants.dart';
import '../services/api_endpoint.dart';
import '../services/doubao_api.dart' show primaryModelChoices;
import '../services/reader_settings.dart';
import 'reader_paper.dart';
import 'reader_progress.dart';

/// 阅读器 C 方案(2026-11-06 用户拍板)的弹层家族。
///
/// 设计文档 §4 的要求是"弹层全部按 C 重排":原来四个弹层是四种视觉语言
/// (裸列表 / 胶囊组 / 卡片网格 / Chip 云),现在全部统一成同一张纸:
/// 纸色底 + 22px 顶部圆角 + 36×4 抓手 + 栏目标签(10/w800/+1.4)+ 紧凑行。
///
/// 为什么独立成文件:控制台(`reader_console.dart`)与设置/目录/模型等弹层
/// 共用同一批原语([ReaderSheetSurface]/[ReaderSheetLabel]/[ReaderSheetRow]),
/// 放在一起才不会又长出第二套视觉。

/// 弹层的统一外壳:纸色底 + 顶部圆角 + 抓手 + 可滚动内容。
class ReaderSheetSurface extends StatelessWidget {
  const ReaderSheetSurface({
    super.key,
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(22, 0, 22, 18),
    this.maxHeight,
    this.handle = true,
  });

  final ReaderPalette palette;
  final Widget child;
  final EdgeInsets padding;

  /// 最高高度;传 null = 由内容决定(短弹层)
  final double? maxHeight;

  /// 是否画抓手(控制台/设置/目录画;行内小弹层可不画)
  final bool handle;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    // 弹层自己也包进"当前纸张"的局部主题:设置里换纸时,弹层内的
    // Material/文字/选中态立刻跟着换,不用等重新打开。
    return Theme(
      data: readerTheme(context, palette),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: palette.sheet,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: palette.hairline)),
          ),
          constraints: maxHeight == null
              ? null
              : BoxConstraints(maxHeight: maxHeight!),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (handle) ...<Widget>[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else
                  const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: body,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹层里的小标题:10 / 1.2 / +1.4 / w800 / 极淡(C 的"栏目标签"语言)
class ReaderSheetLabel extends StatelessWidget {
  const ReaderSheetLabel(this.text, {super.key, required this.palette});

  final String text;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        height: 1.2,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w800,
        color: palette.inkFaint,
      ),
    );
  }
}

/// 弹层主标题:15 / 1.2 / w800(比旧实现的 20 号小 —— 弹层不该抢正文)
class ReaderSheetTitle extends StatelessWidget {
  const ReaderSheetTitle(this.text, {super.key, required this.palette});

  final String text;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        height: 1.2,
        letterSpacing: 0.2,
        fontWeight: FontWeight.w800,
        color: palette.ink,
      ),
    );
  }
}

/// 弹层里的**紧凑行**(控制台目录 3 行 / 材料行 / 设置行都用它)。
class ReaderSheetRow extends StatelessWidget {
  const ReaderSheetRow({
    super.key,
    required this.palette,
    required this.leading,
    required this.title,
    this.trailing = '',
    this.current = false,
    this.onTap,
    this.marginBottom = 6,
  });

  final ReaderPalette palette;

  /// 左侧 24px 宽的小标(`01` / `Aa` / `AI` / `↓`)
  final String leading;
  final String title;
  final String trailing;

  /// 正在读的那一行:砖红底 6% + 砖红边框 + 砖红标题
  final bool current;
  final VoidCallback? onTap;
  final double marginBottom;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: current ? palette.accent.withValues(alpha: 0.06) : palette.page,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: current
              ? palette.accent.withValues(alpha: 0.45)
              : palette.hairline,
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Text(
              leading,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.2,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w800,
                color: current ? palette.accent : palette.inkFaint,
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.2,
                fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                color: current ? palette.accent : palette.ink,
              ),
            ),
          ),
          if (trailing.isNotEmpty) ...<Widget>[
            const SizedBox(width: 8),
            // 值可能很长(模型名/target 文案),限宽 + 省略,不能把标题挤没
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 168),
              child: Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.2,
                  color: palette.inkFaint,
                ),
              ),
            ),
          ],
          if (onTap != null) ...<Widget>[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 15, color: palette.inkFaint),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return Padding(
        padding: EdgeInsets.only(bottom: marginBottom),
        child: row,
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: marginBottom),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: row,
        ),
      ),
    );
  }
}

/// 控制台/设置里的**方块**(学习三块、色卡上面的文字块)。
class ReaderSheetTile extends StatelessWidget {
  const ReaderSheetTile({
    super.key,
    required this.palette,
    required this.icon,
    required this.title,
    required this.sub,
    this.active = false,
    this.onTap,
  });

  final ReaderPalette palette;
  final IconData icon;
  final String title;
  final String sub;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: active
            ? palette.accent.withValues(alpha: 0.06)
            : palette.page,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? palette.accent.withValues(alpha: 0.45)
              : palette.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: active ? palette.accent : palette.inkSoft),
          const SizedBox(height: 7),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: active ? palette.accent : palette.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              height: 1.2,
              color: palette.inkFaint,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: box,
      ),
    );
  }
}

/// C 版**阅读设置**面板:字号 5 档 / 行距 3 档 / 纸张三色 + 实时预览卡。
///
/// 三件事是用户点名要的:
/// 1. 纸张三色可切换(`纸白 / 米黄 / 墨夜`),色卡直接是纸色;
/// 2. 一张**实时预览卡** —— 选完纸/字号/行距立刻看到正文长什么样,
///    不用退出去才知道;
/// 3. 改完立刻生效且落 Hive(由页面的 `onChanged` 负责持久化)。
class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.initialPaper,
    required this.initialFontScale,
    required this.initialLineHeight,
    required this.onChanged,
  });

  final ReaderPaper initialPaper;
  final double initialFontScale;
  final double initialLineHeight;

  /// 每次改动都回调(页面立刻 setState + ReaderSettings 落库)
  final void Function(ReaderPaper paper, double fontScale, double lineHeight)
      onChanged;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderPaper _paper = widget.initialPaper;
  late double _fontScale = widget.initialFontScale;
  late double _lineHeight = widget.initialLineHeight;

  ReaderPalette get _palette => paletteOf(_paper);

  void _apply({ReaderPaper? paper, double? fontScale, double? lineHeight}) {
    setState(() {
      _paper = paper ?? _paper;
      _fontScale = fontScale ?? _fontScale;
      _lineHeight = lineHeight ?? _lineHeight;
    });
    widget.onChanged(_paper, _fontScale, _lineHeight);
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    final scaleIndex = ReaderSettings.scaleIndex(_fontScale);
    final lineIndex = ReaderSettings.lineHeightIndex(_lineHeight);
    final bodySize = ReaderSettings.cFontSizes[scaleIndex];
    final line = ReaderSettings.cLineHeights[lineIndex];
    return ReaderSheetSurface(
      palette: p,
      maxHeight: MediaQuery.of(context).size.height * 0.86,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ReaderSheetTitle('阅读设置', palette: p),
              const Spacer(),
              Text(
                '立即生效',
                style: TextStyle(fontSize: 10, color: p.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ReaderSheetLabel('字号(号数)', palette: p),
          const SizedBox(height: 8),
          _Segmented(
            palette: p,
            labels: [
              for (final s in ReaderSettings.cFontSizes)
                s == s.roundToDouble()
                    ? s.toInt().toString()
                    : s.toString(),
            ],
            selected: scaleIndex,
            onTap: (i) => _apply(
              fontScale: ReaderSettings.fontScales[i],
            ),
          ),
          const SizedBox(height: 16),
          ReaderSheetLabel('行距', palette: p),
          const SizedBox(height: 8),
          _Segmented(
            palette: p,
            labels: ReaderSettings.lineHeightLabels,
            selected: lineIndex,
            onTap: (i) => _apply(lineHeight: ReaderSettings.lineHeights[i]),
          ),
          const SizedBox(height: 16),
          ReaderSheetLabel('纸张', palette: p),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (var i = 0; i < ReaderPaper.values.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _PaperCard(
                    paper: ReaderPaper.values[i],
                    selected:
                        ReaderPaper.values[i] == _paper,
                    onTap: () => _apply(paper: ReaderPaper.values[i]),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          ReaderSheetLabel('预览(正文 ${ReaderSettings.cFontLabel(bodySize)} · 行距 ${line.toStringAsFixed(1)})', palette: p),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.page,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'That is why a quiet hour can feel more productive.',
                  style: TextStyle(
                    fontSize: bodySize,
                    height: line,
                    color: p.ink,
                    letterSpacing: 0.05,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 2,
                      height: bodySize * 13.5 / 18 * 1.7,
                      color: p.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '这就是为什么安静的一小时更有产出。',
                        style: TextStyle(
                          fontSize: bodySize * 13.5 / 18,
                          height: 1.7,
                          color: p.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '纸张与字号存进本机设置,下次打开还是这个样子。',
            style: TextStyle(fontSize: 10, height: 1.4, color: p.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// 分段控件(设置里的字号/行距):选中格是纸面色 + 极轻阴影,不是果冻胶囊
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.palette,
    required this.labels,
    required this.selected,
    required this.onTap,
  });

  final ReaderPalette palette;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.selectedBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  alignment: Alignment.center,
                  decoration: i == selected
                      ? BoxDecoration(
                          color: palette.sheet,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        )
                      : null,
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight:
                          i == selected ? FontWeight.w800 : FontWeight.w500,
                      color:
                          i == selected ? palette.ink : palette.inkFaint,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 纸张色卡:52px 高的纸色块 + 名字。选中 = 砖红 2px 边框 + 砖红名字。
class _PaperCard extends StatelessWidget {
  const _PaperCard({
    required this.paper,
    required this.selected,
    required this.onTap,
  });

  final ReaderPaper paper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final target = paletteOf(paper);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: target.page,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? target.accent : target.hairline,
                width: selected ? 2 : 1,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            paper.label,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? target.accent : target.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

/// 模型 + 思考档弹层(原来挤在底栏最左,现在属于「材料」组)
class ReaderModelSheet extends StatelessWidget {
  const ReaderModelSheet({
    super.key,
    required this.palette,
    required this.model,
    required this.thinking,
    required this.onPick,
  });

  final ReaderPalette palette;

  /// 当前模型与思考档(面板打开时的快照)
  final String model;
  final String thinking;

  /// 当前模型(Hive 实时读;与拍照识图页 / 翻译共用一个设置)
  static String currentModel() {
    final v = Hive.box(AppConstants.hiveBoxSettings)
        .get(AppConstants.keyDoubaoModel);
    return (v is String && v.isNotEmpty) ? v : AppConstants.doubaoVisionModel;
  }

  /// 当前思考档(主槽位)
  static String currentThinking() => ApiEndpointConfig.primary.thinking;

  /// (model, thinking) —— model 为空表示只改思考档
  final void Function(String model, String thinking) onPick;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ReaderSheetSurface(
      palette: p,
      maxHeight: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ReaderSheetTitle('模型与思考档', palette: p),
          const SizedBox(height: 4),
          Text(
            '翻译、点词、追问都走这里选的模型;换完立刻生效。',
            style: TextStyle(fontSize: 10.5, height: 1.4, color: p.inkFaint),
          ),
          const SizedBox(height: 14),
          ReaderSheetLabel('模型', palette: p),
          const SizedBox(height: 6),
          for (final model in primaryModelChoices())
            _PickRow(
              palette: p,
              label: model,
              selected: model == this.model,
              onTap: () {
                Navigator.pop(context);
                onPick(model, thinking);
              },
            ),
          const SizedBox(height: 10),
          ReaderSheetLabel('思考档($model)', palette: p),
          const SizedBox(height: 6),
          for (final e in AppConstants.thinkingOptionsFor(model).entries)
            _PickRow(
              palette: p,
              label: e.value,
              selected: e.key == thinking,
              onTap: () {
                Navigator.pop(context);
                onPick(model, e.key);
              },
            ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ReaderPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.06)
                : palette.page,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? palette.accent.withValues(alpha: 0.45)
                  : palette.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected ? Icons.check : Icons.circle_outlined,
                size: 14,
                color: selected ? palette.accent : palette.inkFaint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? palette.accent : palette.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「导出 / 听写 / 读完 / 原文链接」等材料动作的一行式弹层
class ReaderActionItem {
  const ReaderActionItem({
    required this.icon,
    required this.label,
    this.hint = '',
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
}

class ReaderActionSheet extends StatelessWidget {
  const ReaderActionSheet({
    super.key,
    required this.palette,
    required this.title,
    required this.actions,
    this.note = '',
  });

  final ReaderPalette palette;
  final String title;
  final List<ReaderActionItem> actions;
  final String note;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ReaderSheetSurface(
      palette: p,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ReaderSheetTitle(title, palette: p),
          const SizedBox(height: 12),
          for (final a in actions)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.pop(context);
                  a.onTap();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: p.page,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(a.icon, size: 17, color: p.inkSoft),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          a.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                        ),
                      ),
                      if (a.hint.isNotEmpty)
                        Text(
                          a.hint,
                          style: TextStyle(fontSize: 9.5, color: p.inkFaint),
                        ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 15, color: p.inkFaint),
                    ],
                  ),
                ),
              ),
            ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                note,
                style:
                    TextStyle(fontSize: 10, height: 1.4, color: p.inkFaint),
              ),
            ),
        ],
      ),
    );
  }
}

/// 完整目录弹层(C 版):每行 序号 + 节名 + 本节 % + 词数,正在读的用砖红
class ReaderTocSheet extends StatelessWidget {
  const ReaderTocSheet({
    super.key,
    required this.palette,
    required this.titles,
    required this.wordCounts,
    required this.percents,
    required this.current,
    required this.onPick,
  });

  final ReaderPalette palette;
  final List<String> titles;
  final List<int> wordCounts;
  final List<double> percents;
  final int current;
  final void Function(int index) onPick;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final h = MediaQuery.of(context).size.height;
    return ReaderSheetSurface(
      palette: p,
      maxHeight: h * 0.76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ReaderSheetTitle('目录', palette: p),
              const Spacer(),
              Text(
                '共 ${titles.length} 节',
                style: TextStyle(fontSize: 10, color: p.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (titles.isEmpty)
            Text(
              '这篇材料没有分节信息,先往下读吧',
              style: TextStyle(fontSize: 11.5, color: p.inkFaint),
            )
          else
            for (var i = 0; i < titles.length; i++)
              ReaderSheetRow(
                palette: p,
                leading: '${i + 1}'.padLeft(2, '0'),
                title: titles[i],
                trailing:
                    '${wordCounts.length > i && wordCounts[i] > 0 ? '约 ${wordCounts[i]} 词 · ' : ''}'
                    '${(percents.length > i ? percents[i] : 0).round()}%',
                current: i == current,
                marginBottom: 6,
                onTap: () {
                  Navigator.pop(context);
                  onPick(i);
                },
              ),
        ],
      ),
    );
  }
}

/// 有历史进度时的「继续 / 从头」—— C 版(主按钮是 ink 实心胶囊)
class ReaderResumeSheet extends StatelessWidget {
  const ReaderResumeSheet({
    super.key,
    required this.palette,
    required this.finished,
    required this.percent,
    required this.position,
    required this.minutes,
    required this.onResume,
    required this.onRestart,
  });

  final ReaderPalette palette;
  final bool finished;
  final int percent;

  /// 0 起的块下标(显示时 +1)
  final int position;
  final int minutes;
  final VoidCallback onResume;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ReaderSheetSurface(
      palette: p,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.history, size: 16, color: p.accent),
              const SizedBox(width: 8),
              ReaderSheetTitle(
                finished ? '这篇你读完了' : '上次读到 $percent%',
                palette: p,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            finished
                ? '已经标记读完,已读 $minutes 分钟。要从上次的位置再看一遍吗?'
                : '已读 $minutes 分钟。继续,还是从头开始?',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: p.inkFaint),
          ),
          const SizedBox(height: 16),
          _Cta(
            palette: p,
            label: finished ? '回到第 ${position + 1} 段' : '继续(第 ${position + 1} 段)',
            icon: Icons.play_arrow,
            primary: true,
            onTap: onResume,
          ),
          const SizedBox(height: 8),
          _Cta(
            palette: p,
            label: '从头开始',
            icon: Icons.restart_alt,
            primary: false,
            onTap: onRestart,
          ),
        ],
      ),
    );
  }
}

class _Cta extends StatelessWidget {
  const _Cta({
    required this.palette,
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final ReaderPalette palette;
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: Material(
        color: primary ? p.ink : p.page,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 17, color: primary ? p.onInk : p.ink),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: primary ? p.onInk : p.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 本次收词确认(C 版):词条是纸面上的小签,不再用 Chip 云
class ReaderPickedSheet extends StatelessWidget {
  const ReaderPickedSheet({
    super.key,
    required this.palette,
    required this.words,
    required this.saveTargetLabel,
    required this.onChangeTarget,
  });

  final ReaderPalette palette;
  final List<String> words;
  final String saveTargetLabel;

  /// 改保存位置(页面负责先弹分类/材料名选择器)
  final VoidCallback onChangeTarget;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ReaderSheetSurface(
      palette: p,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ReaderSheetTitle(
            words.isEmpty ? '还没有收词' : '本次收了 ${words.length} 个词',
            palette: p,
          ),
          const SizedBox(height: 6),
          if (words.isEmpty)
            Text(
              '点正文里的任意英文单词(或长按选中一段),底部会弹出'
              '「询问 AI / 收藏进单词本」。收藏时按下面显示的保存位置入库,'
              '并立刻进入复习队列。',
              style: TextStyle(fontSize: 11.5, height: 1.5, color: p.inkFaint),
            )
          else ...<Widget>[
            Text(
              '存到:$saveTargetLabel',
              style: TextStyle(fontSize: 11, color: p.inkFaint),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final w in words)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: p.page,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Text(
                      w,
                      style: TextStyle(fontSize: 11.5, color: p.ink),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _Cta(
              palette: p,
              label: '改保存位置',
              icon: Icons.drive_file_move_outline,
              primary: false,
              onTap: () {
                Navigator.pop(context);
                onChangeTarget();
              },
            ),
            const SizedBox(height: 8),
            Text(
              '注:收词时已即时入库,这里只是让你确认收到了哪些、存到哪儿。',
              style: TextStyle(fontSize: 10, height: 1.4, color: p.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}

/// 翻译弹层:翻译进度/增量操作从"压在正文上的灰带"收进这里。
///
/// 旧实现把 `ProgressStageBar` + 「继续翻后文 / 整章」摊在正文下方一条
/// 实底灰带上(占屏高 ~93px,还和底栏翻译 chip 状态双写)。C 方案下:
/// - 正文里只留译文本身,没有任何翻译进度条;
/// - 进度与动作全部进这个弹层(控制台「学习 → 翻译」打开);
/// - 顶部还有一条 2px 细线做"正在翻译"的轻提示(见页面 build)。
class ReaderTranslationSheet extends StatelessWidget {
  const ReaderTranslationSheet({
    super.key,
    required this.palette,
    required this.editing,
    required this.done,
    required this.total,
    required this.failed,
    required this.status,
    required this.autoTranslate,
    required this.translateTarget,
    this.progressBar,
    this.lastError,
    required this.onContinueNext,
    required this.onWholeChapter,
    required this.onRetryFailed,
    required this.onToggleOff,
  });

  final ReaderPalette palette;

  /// 译文是否显示中
  final bool editing;
  final int done;
  final int total;
  final int failed;

  /// 一行状态(如「已翻 6/8 段 · 点译文可问 AI」)
  final String status;
  final bool autoTranslate;

  /// 翻译实际走的槽位/模型(`DeepseekApiService.targetSummary`)
  final String translateTarget;

  /// 真实进度条(页面用 ProgressStageBar 传进来;不翻时为 null)
  final Widget? progressBar;
  final String? lastError;

  final VoidCallback onContinueNext;
  final VoidCallback onWholeChapter;
  final VoidCallback onRetryFailed;
  final VoidCallback onToggleOff;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ReaderSheetSurface(
      palette: p,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              ReaderSheetTitle('逐段翻译', palette: p),
              const Spacer(),
              Text(
                editing ? '译文显示中' : '已关闭译文',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: editing ? p.accent : p.inkFaint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '$done',
                style: TextStyle(
                  fontSize: 34,
                  height: 1.0,
                  letterSpacing: -1.5,
                  fontWeight: FontWeight.w900,
                  color: p.accent,
                ),
              ),
              Text(
                ' / $total 段',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  fontWeight: FontWeight.w700,
                  color: p.accent,
                ),
              ),
              const Spacer(),
              Text(
                '${(total == 0 ? 0 : done / total * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: p.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ReaderProgressBar(
            ratio: total == 0 ? 0 : done / total,
            palette: p,
          ),
          if (progressBar != null) ...<Widget>[
            const SizedBox(height: 12),
            progressBar!,
          ],
          const SizedBox(height: 12),
          Text(
            status,
            style: TextStyle(fontSize: 11, height: 1.4, color: p.inkSoft),
          ),
          if (failed > 0) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              lastError == null ? '$failed 段没翻出来' : '最近一次:$lastError',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, height: 1.4, color: p.accent),
            ),
          ],
          if (!autoTranslate) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '随读随翻已暂停(点「继续翻后文」恢复)',
              style: TextStyle(fontSize: 10, color: p.inkFaint),
            ),
          ],
          const SizedBox(height: 12),
          for (final row in <ReaderActionItem>[
            ReaderActionItem(
              icon: Icons.translate,
              label: '继续翻后文',
              hint: '当前屏优先',
              onTap: onContinueNext,
            ),
            ReaderActionItem(
              icon: Icons.menu_book_outlined,
              label: '整章(约 20 段)',
              hint: '批量',
              onTap: onWholeChapter,
            ),
            if (failed > 0)
              ReaderActionItem(
                icon: Icons.refresh,
                label: '重试没翻出来的 $failed 段',
                onTap: onRetryFailed,
              ),
            ReaderActionItem(
              icon: Icons.visibility_off_outlined,
              label: editing ? '关闭译文(已翻的保留)' : '打开译文',
              onTap: onToggleOff,
            ),
          ])
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.pop(context);
                  row.onTap();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: p.page,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.hairline),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(row.icon, size: 17, color: p.inkSoft),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                        ),
                      ),
                      if (row.hint.isNotEmpty)
                        Text(
                          row.hint,
                          style:
                              TextStyle(fontSize: 9.5, color: p.inkFaint),
                        ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 15, color: p.inkFaint),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '翻译使用:$translateTarget',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: p.inkFaint),
          ),
        ],
      ),
    );
  }
}
