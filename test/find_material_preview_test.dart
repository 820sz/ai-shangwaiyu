import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/design_tokens.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/config/v4_theme.dart';

/// 「找材料」重构方案 · **真实渲染预览**(2026-11-06,待用户选型)。
///
/// 为什么把预览 widget 写在这个 test 文件里而不是 lib/:
/// 本轮只出方案、不改生产代码(任务约束)。三个方向各自是"提案屏",
/// 用 [V4Skin] 明亮果冻取色 + [Gap] 间距,和现有频道页同一套视觉语言,
/// 所以图上看到的就是实现后能长出来的样子(不是手搭示意图)。
///
/// 出图方式照抄 `test/material_channel_render_test.dart`:
/// 加载 Windows 中文字体 + MaterialIcons、`RenderRepaintBoundary.toImage(pixelRatio: 3)`、
/// 手机逻辑尺寸 390×844 → 每张 1170×2532,同时写:
/// - `build/ui_real/find-material-*.png`
/// - `docs/ui-preview/real/find-material-*.png`(交付目录,给用户看图)
///
/// 六张图:
/// - A-entry  并列大卡:两张等宽大卡(自由搜 / 按我的情况找)
/// - A-result 自由搜结果页:搜索条 + 来源筛选 + 类型分组 + 真分页
/// - B-entry  上下分区:整条大搜索框在上,学习助理数据面板在下
/// - B-result 按需找结果页:依据卡 + 每条"为什么推" + 分组 + 真分页
/// - C-entry  工作台式:模式切换 + 三项数据 + 筛选台 + 单一主行动
/// - C-result 工作台结果页:编号密排行 + 底部固定页码/动作条
///
/// 注意:widget 测试里没有网络,所以**结果卡一律走"无封面文字版式"**
/// (标题 + 中文标题 + 来源/难度/词数)。这正是本轮用户定的规则:
/// 只有真实抓到 `imageUrl`/`coverUrl` 才显示封面,没有不许放渐变假封面。
/// 真封面分支不进测试图,由真机验证。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont();
    await _loadIcons();
  });

  testWidgets('A · 并列大卡:找材料首屏', (tester) async {
    _phoneView(tester);
    await _shoot(tester, const _EntryA(), 'find-material-A-entry.png');
  });

  testWidgets('A · 自由搜结果页(分组 + 真分页)', (tester) async {
    _phoneView(tester);
    await _shoot(tester, const _ResultA(), 'find-material-A-result.png');
  });

  testWidgets('B · 上下分区:找材料首屏', (tester) async {
    _phoneView(tester);
    await _shoot(tester, const _EntryB(), 'find-material-B-entry.png');
  });

  testWidgets('B · 按需找结果页(依据 + 为什么推)', (tester) async {
    _phoneView(tester);
    await _shoot(tester, const _ResultB(), 'find-material-B-result.png');
  });

  testWidgets('C · 工作台式:找材料首屏', (tester) async {
    _phoneView(tester);
    await _shoot(tester, const _EntryC(), 'find-material-C-entry.png');
  });

  testWidgets('C · 工作台结果页(密排 + 底部动作条)', (tester) async {
    _phoneView(tester);
    await _shoot(tester, const _ResultC(), 'find-material-C-result.png');
  });
}

// ═══════════════════════════════════════════════════════════════════════
// 渲染管线(与 material_channel_render_test.dart 一致)
// ═══════════════════════════════════════════════════════════════════════

const String _fontFamily = 'PreviewCJK';

Future<void> _loadFont() async {
  for (final path in <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes =
        Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
    // 注册成 Roboto 让 Material 默认字号/按钮也吃到中文字形
    await (FontLoader('Roboto')..addFont(bytes)).load();
    await (FontLoader(_fontFamily)..addFont(bytes)).load();
    return;
  }
}

Future<void> _loadIcons() async {
  for (final path in <String>[
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()))))
        .load();
    return;
  }
}

ThemeData _theme() {
  final base = AppTheme.lightTheme;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _fontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _fontFamily),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(
              fontFamily: _fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w700),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base.textButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(fontFamily: _fontFamily, fontSize: 13),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(fontFamily: _fontFamily, fontSize: 13),
        ),
      ),
    ),
  );
}

void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _shoot(WidgetTester tester, Widget screen, String fileName) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        // ⚠️ 必须显式给默认文字样式:MaterialApp 在没有 Material 祖先时会把
        // [WidgetsApp.textStyle] 设成 Flutter 内部的 `_errorTextStyle`
        // (红字 + 黄色双下划线,`material/app.dart:45-54`,文档原文:
        // "Text widgets that lack a Material ancestor will be rendered with an
        //  ugly red/yellow text style")。预览屏是纯 ColoredBox(不是 Scaffold),
        // 所以上一版 6 张图每行文字底下都带了一条纯黄 (255,255,0) 下划线。
        // 这里给一个无 decoration 的默认样式兜底(不引入 height,避免行高变化)。
        home: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: _fontFamily,
            decoration: TextDecoration.none,
          ),
          child: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _capture(tester, key, fileName);
}

Future<void> _capture(
    WidgetTester tester, GlobalKey key, String fileName) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final data = bytes!.buffer.asUint8List();
    Directory('build/ui_real').createSync(recursive: true);
    File('build/ui_real/$fileName').writeAsBytesSync(data);
    Directory('docs/ui-preview/real').createSync(recursive: true);
    File('docs/ui-preview/real/$fileName').writeAsBytesSync(data);
    image.dispose();
  });
}

// ═══════════════════════════════════════════════════════════════════════
// 共用视觉零件(全部走 V4Skin / Gap,不写裸色值)
// ═══════════════════════════════════════════════════════════════════════

TextStyle _t({
  double size = 12,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? height,
  double? spacing,
}) =>
    TextStyle(
      fontFamily: _fontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: spacing,
      // 显式 none:防止任何祖先的 DefaultTextStyle 把 decoration 带进来
      // (上一版黄下划线的根因见 _shoot 注释;这里再钉死一次)。
      decoration: TextDecoration.none,
    );

Widget _roundBtn(V4Skin skin, IconData icon, {Color? bg, Color? fg}) {
  return Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: bg ?? skin.surface,
      shape: BoxShape.circle,
      border: Border.all(color: skin.hairline),
      boxShadow: skin.shadow,
    ),
    child: Icon(icon, size: 19, color: fg ?? skin.ink),
  );
}

Widget _appBar(V4Skin skin, {String? title, Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(Gap.page, 6, Gap.page, 0),
    child: Row(
      children: <Widget>[
        _roundBtn(skin, Icons.arrow_back_rounded),
        const SizedBox(width: Gap.xs),
        if (title != null)
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(size: 20, weight: FontWeight.w900, color: skin.ink, spacing: -0.3),
            ),
          )
        else
          const Spacer(),
        if (trailing != null) trailing,
      ],
    ),
  );
}

Widget _tag(V4Skin skin, String label,
    {bool primary = false, bool success = false}) {
  final Color bg;
  final Color fg;
  if (primary) {
    bg = skin.accent.withValues(alpha: 0.12);
    fg = skin.accent;
  } else if (success) {
    bg = skin.pastelAt(2).first.withValues(alpha: 0.65);
    fg = skin.ink;
  } else {
    bg = skin.surfaceAlt;
    fg = skin.inkSoft;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label,
        style: _t(size: 10.5, weight: FontWeight.w600, color: fg, height: 1.2)),
  );
}

Widget _chip(V4Skin skin, String label,
    {bool selected = false, IconData? icon}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: selected ? skin.accent.withValues(alpha: 0.12) : skin.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: selected
            ? skin.accent.withValues(alpha: 0.5)
            : skin.hairline,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon,
              size: 13, color: selected ? skin.accent : skin.inkFaint),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: _t(
            size: 11.5,
            weight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? skin.accent : skin.inkSoft,
          ),
        ),
      ],
    ),
  );
}

Widget _card(V4Skin skin,
    {required Widget child,
    EdgeInsets padding = const EdgeInsets.all(Gap.sm),
    Color? color,
    double radius = 20,
    List<BoxShadow>? shadow}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? skin.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: skin.hairline),
      boxShadow: shadow ?? skin.shadow,
    ),
    child: child,
  );
}

/// 类型分组小标题:3px 强调竖条 + 组名 + 条数(与频道页 _groupHeader 同构)
Widget _groupHeader(V4Skin skin, String label, int count) {
  return Padding(
    padding: const EdgeInsets.only(top: Gap.sm, bottom: 6),
    child: Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: skin.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: _t(size: 12.5, weight: FontWeight.w800, color: skin.ink)),
        const SizedBox(width: 6),
        Text('$count 篇',
            style: _t(size: 10.5, color: skin.inkFaint)),
      ],
    ),
  );
}

/// 页码控件:上一页 / 第 X / Y 页 / 下一页(与升级后频道页同一口径,每页 10 条)
Widget _pager(V4Skin skin, {required int page, required int total}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    decoration: BoxDecoration(
      color: skin.surface,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: skin.hairline),
    ),
    child: Row(
      children: <Widget>[
        _pagerArrow(skin, Icons.chevron_left_rounded, page > 0),
        Expanded(
          child: Center(
            child: Text(
              '第 ${page + 1} / $total 页',
              style: _t(
                  size: 11.5, weight: FontWeight.w700, color: skin.inkSoft),
            ),
          ),
        ),
        _pagerArrow(skin, Icons.chevron_right_rounded, page + 1 < total),
      ],
    ),
  );
}

Widget _pagerArrow(V4Skin skin, IconData icon, bool enabled) {
  return Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: enabled ? skin.surfaceAlt : skin.surfaceAlt.withValues(alpha: 0.4),
      shape: BoxShape.circle,
    ),
    child: Icon(icon,
        size: 18, color: enabled ? skin.ink : skin.inkFaint),
  );
}

/// 主行动按钮(全宽)
Widget _primary(V4Skin skin, String label, {IconData? icon}) {
  return Container(
    height: 46,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: skin.accentGradient),
      borderRadius: BorderRadius.circular(16),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: skin.accent.withValues(alpha: 0.28),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 18, color: skin.onAccent),
          const SizedBox(width: 6),
        ],
        Text(label,
            style: _t(
                size: 14.5,
                weight: FontWeight.w800,
                color: skin.onAccent)),
      ],
    ),
  );
}

/// 无封面结果卡(本轮硬规则:没有真实封面 → 标题 + 翻译 + 来源/难度 文字版式)
Widget _resultCard(
  V4Skin skin, {
  required String title,
  required String titleCn,
  required String snippet,
  required List<String> tags,
  required String actions,
  String? reason,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: Gap.xs),
    child: _card(
      skin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _t(
                size: 14.5,
                weight: FontWeight.w800,
                color: skin.ink,
                height: 1.32,
                spacing: -0.2),
          ),
          if (titleCn.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              titleCn,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(size: 11.5, color: skin.inkSoft),
            ),
          ],
          const SizedBox(height: 5),
          Wrap(spacing: 5, runSpacing: 4, children: <Widget>[
            for (final t in tags) _tag(skin, t),
          ]),
          if (snippet.isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _t(
                  size: 11.5, color: skin.inkSoft, height: 1.45),
            ),
          ],
          if (reason != null) ...<Widget>[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: skin.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _t(
                    size: 10.5,
                    color: skin.inkSoft,
                    height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 7),
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: skin.ink,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('开始读',
                    style: _t(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: skin.onAccent)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: skin.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: skin.hairline),
                ),
                child: Text(actions,
                    style: _t(
                        size: 11.5, color: skin.inkSoft)),
              ),
              const Spacer(),
              Text('打开原文',
                  style: _t(
                      size: 10.5,
                      weight: FontWeight.w600,
                      color: skin.accent)),
              const SizedBox(width: 2),
              Icon(Icons.open_in_new_rounded,
                  size: 13, color: skin.accent),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _stat(V4Skin skin, String value, String label, {bool accent = false}) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: accent
            ? skin.accent.withValues(alpha: 0.08)
            : skin.surfaceAlt.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(
                  size: 15.5,
                  weight: FontWeight.w900,
                  color: accent ? skin.accent : skin.ink,
                  spacing: -0.3)),
          const SizedBox(height: 1),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(size: 9.5, color: skin.inkSoft)),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// A · 并列大卡
// ═══════════════════════════════════════════════════════════════════════

class _EntryA extends StatelessWidget {
  const _EntryA();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ColoredBox(
      color: skin.pageBg,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 12),
          _appBar(skin, trailing: _roundBtn(skin, Icons.history_rounded)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('找材料',
                      style: _t(
                          size: 34,
                          weight: FontWeight.w900,
                          color: skin.ink,
                          height: 1.05,
                          spacing: -0.9)),
                  const SizedBox(height: 6),
                  Text('两条路:自己搜,或者让软件按你的情况找。',
                      style: _t(
                          size: 11.5, color: skin.inkSoft, height: 1.5)),
                  const SizedBox(height: Gap.md),
                  SizedBox(
                    height: 274,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _bigEntryCard(
                            skin,
                            tint: skin.pastelAt(3).first,
                            icon: Icons.manage_search_rounded,
                            title: '自由搜',
                            desc: '输关键词,直接搜公开源原文。\n看得到原文、能存到自己库里。',
                            chips: const <String>['关键词', '来源', '类型', '难度'],
                            footLabel: '上次搜过',
                            footValue: 'climate change',
                            cta: '去搜',
                          ),
                        ),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: _bigEntryCard(
                            skin,
                            tint: skin.pastelAt(0).first,
                            icon: Icons.auto_awesome_rounded,
                            title: '按我的情况找',
                            desc: '读学习助理的统计:水平、目标、\n弱项、最近阅读。',
                            chips: const <String>['i+10', '四六级', '时态薄弱'],
                            footLabel: '基线',
                            footValue: '已掌握 4,200 词',
                            cta: '按情况找',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  Row(
                    children: <Widget>[
                      Text('最近搜过',
                          style: _t(
                              size: 12.5,
                              weight: FontWeight.w800,
                              color: skin.ink)),
                      const Spacer(),
                      Text('搜索历史 · 可清空',
                          style: _t(size: 10, color: skin.inkFaint)),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  Wrap(
                    spacing: Gap.xs,
                    runSpacing: 6,
                    children: const <Widget>[
                      _StaticChip('新概念英语'),
                      _StaticChip('climate change'),
                      _StaticChip('四六级真题'),
                      _StaticChip('TED 演讲'),
                    ],
                  ),
                  const SizedBox(height: Gap.lg),
                  _lastRunStrip(skin),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigEntryCard(
    V4Skin skin, {
    required Color tint,
    required IconData icon,
    required String title,
    required String desc,
    required List<String> chips,
    required String footLabel,
    required String footValue,
    required String cta,
  }) {
    return Container(
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
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _t(
                  size: 18,
                  weight: FontWeight.w900,
                  color: skin.ink,
                  spacing: -0.4)),
          const SizedBox(height: 4),
          Text(desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _t(size: 10.5, color: skin.inkSoft, height: 1.45)),
          const Spacer(),
          Wrap(spacing: 4, runSpacing: 4, children: <Widget>[
            for (final c in chips)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: skin.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: skin.hairline),
                ),
                child: Text(c,
                    style: _t(size: 9.5, color: skin.inkSoft)),
              ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: skin.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(footLabel, style: _t(size: 9, color: skin.inkFaint)),
                const SizedBox(height: 1),
                Text(footValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(
                        size: 10,
                        weight: FontWeight.w700,
                        color: skin.ink)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text(cta,
                  style: _t(
                      size: 11.5,
                      weight: FontWeight.w800,
                      color: skin.accent)),
              const SizedBox(width: 2),
              Icon(Icons.arrow_forward_rounded,
                  size: 14, color: skin.accent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lastRunStrip(V4Skin skin) {
    return _card(
      skin,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                    style: _t(
                        size: 12,
                        weight: FontWeight.w700,
                        color: skin.ink)),
                Text('3 组 · 18 篇 · 2 分钟前 · 约 ¥0.015',
                    style: _t(size: 10, color: skin.inkFaint)),
              ],
            ),
          ),
          Text('继续看',
              style: _t(
                  size: 11,
                  weight: FontWeight.w700,
                  color: skin.accent)),
          Icon(Icons.chevron_right_rounded,
              size: 16, color: skin.accent),
        ],
      ),
    );
  }
}

class _StaticChip extends StatelessWidget {
  final String label;
  const _StaticChip(this.label);

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: skin.hairline),
      ),
      child: Text(label,
          style: _t(size: 11, color: skin.inkSoft)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// A · 自由搜结果页
// ═══════════════════════════════════════════════════════════════════════

class _ResultA extends StatelessWidget {
  const _ResultA();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ColoredBox(
      color: skin.pageBg,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 12),
          // 搜索条(独立搜索页:返回 + 关键词 + 清空)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 2, Gap.page, 0),
            child: Row(
              children: <Widget>[
                _roundBtn(skin, Icons.arrow_back_rounded),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: skin.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: skin.accent.withValues(alpha: 0.45)),
                      boxShadow: skin.shadow,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.search_rounded,
                            size: 17, color: skin.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('climate change 城市',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _t(
                                  size: 12.5,
                                  weight: FontWeight.w600,
                                  color: skin.ink)),
                        ),
                        Icon(Icons.close_rounded,
                            size: 15, color: skin.inkFaint),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xs),
          // 来源筛选(真实来源:公版书 / 外刊 / 论文,不是自造分类)
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Gap.page),
              children: <Widget>[
                _chip(skin, '全部来源', selected: true),
                const SizedBox(width: 6),
                _chip(skin, '公版书'),
                const SizedBox(width: 6),
                _chip(skin, '外刊'),
                const SizedBox(width: 6),
                _chip(skin, '论文'),
                const SizedBox(width: 6),
                _chip(skin, '类型', icon: Icons.tune_rounded),
                const SizedBox(width: 6),
                _chip(skin, '难度', icon: Icons.speed_rounded),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text('18 篇 · 3 组 · 分 2 页',
                          style: _t(
                              size: 11,
                              weight: FontWeight.w700,
                              color: skin.inkSoft)),
                      const Spacer(),
                      Text('相关度优先',
                          style: _t(size: 10, color: skin.inkFaint)),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          size: 14, color: skin.inkFaint),
                    ],
                  ),
                  _groupHeader(skin, '外刊 · 新闻', 2),
                  _resultCard(
                    skin,
                    title: 'Climate Change and Coastal Cities',
                    titleCn: '气候变化与沿海城市',
                    snippet: 'NPR 报道:海平面上升正在改变沿海城市的基础设施规划与迁移政策。',
                    tags: const <String>['NPR News', '外刊', '约 6 分钟', '760 词'],
                    actions: '保存到我的',
                  ),
                  _resultCard(
                    skin,
                    title: 'The Future of Language Learning',
                    titleCn: '语言学习的未来',
                    snippet: '教育技术报道:AI 正在如何改变外语学习者的输入方式。',
                    tags: const <String>['NPR News', '外刊', '约 8 分钟'],
                    actions: '保存到我的',
                  ),
                  _groupHeader(skin, '公版书 · 书籍', 1),
                  _resultCard(
                    skin,
                    title: 'A Christmas Carol',
                    titleCn: '圣诞颂歌',
                    snippet: 'Charles Dickens 经典短篇,分级难度低,适合长篇泛读入门。',
                    tags: const <String>[
                      'Project Gutenberg',
                      '公版书',
                      '28,000 词',
                      'Lv4'
                    ],
                    actions: '保存到我的',
                  ),
                  const SizedBox(height: Gap.sm),
                  _pager(skin, page: 0, total: 2),
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: <Widget>[
                      Icon(Icons.expand_more_rounded,
                          size: 16, color: skin.inkFaint),
                      const SizedBox(width: 2),
                      Text('继续找更多(换检索词再搜一轮,新结果追加到后面)',
                          style: _t(size: 10, color: skin.inkFaint)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _bottomBar(skin, '关键词命中 12 条 · 换词可提高命中'),
        ],
      ),
    );
  }

  Widget _bottomBar(V4Skin skin, String note) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.page, 8, Gap.page, 12),
      decoration: BoxDecoration(
        color: skin.surface,
        border: Border(top: BorderSide(color: skin.hairline)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 15, color: skin.inkFaint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(size: 10.5, color: skin.inkSoft)),
          ),
          Text('筛选',
              style: _t(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: skin.accent)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// B · 上下分区
// ═══════════════════════════════════════════════════════════════════════

class _EntryB extends StatelessWidget {
  const _EntryB();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ColoredBox(
      color: skin.pageBg,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 12),
          _appBar(skin, trailing: _roundBtn(skin, Icons.history_rounded)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('找材料',
                      style: _t(
                          size: 32,
                          weight: FontWeight.w900,
                          color: skin.ink,
                          height: 1.05,
                          spacing: -0.9)),
                  const SizedBox(height: 4),
                  Text('先搜,或者按学习助理给的情况找。',
                      style: _t(size: 11.5, color: skin.inkSoft)),
                  const SizedBox(height: Gap.md),
                  // ① 自由搜:整条"看起来能输入"的搜索框(点一下进独立搜索页)
                  _searchEntry(skin),
                  const SizedBox(height: Gap.md),
                  _dividerWithLabel(skin, '或'),
                  const SizedBox(height: Gap.sm),
                  // ② 按需找:学习助理数据面板
                  Row(
                    children: <Widget>[
                      Text('按你的情况找',
                          style: _t(
                              size: 15,
                              weight: FontWeight.w900,
                              color: skin.ink)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: skin.pastelAt(2).first
                              .withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('实时读取',
                            style: _t(
                                size: 9, color: skin.ink)),
                      ),
                      const Spacer(),
                      Text('学习助理',
                          style: _t(
                              size: 10.5, color: skin.accent)),
                      Icon(Icons.chevron_right_rounded,
                          size: 15, color: skin.accent),
                    ],
                  ),
                  const SizedBox(height: Gap.xs),
                  _personaPanel(skin),
                  const SizedBox(height: Gap.sm),
                  _primary(skin, '按这些条件找材料', icon: Icons.auto_awesome_rounded),
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _miniAction(skin, Icons.tune_rounded, '调整需求'),
                      ),
                      const SizedBox(width: Gap.xs),
                      Expanded(
                        child: _miniAction(
                            skin, Icons.insights_rounded, '看数据依据'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchEntry(V4Skin skin) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.accent.withValues(alpha: 0.35)),
        boxShadow: skin.shadow,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, size: 20, color: skin.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text('搜关键词,如 新概念英语 / climate change',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(size: 12.5, color: skin.inkFaint)),
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: skin.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.tune_rounded,
                size: 16, color: skin.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _dividerWithLabel(V4Skin skin, String label) {
    return Row(
      children: <Widget>[
        Expanded(child: Container(height: 1, color: skin.hairline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(label,
              style: _t(size: 10.5, color: skin.inkFaint)),
        ),
        Expanded(child: Container(height: 1, color: skin.hairline)),
      ],
    );
  }

  Widget _personaPanel(V4Skin skin) {
    return _card(
      skin,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _personaRow(
            skin,
            icon: Icons.tune_rounded,
            iconTint: skin.pastelAt(3).first,
            label: '难度档',
            value: 'i+10 · 挑战(每 100 词 2~10 个生词)',
          ),
          _dash(skin),
          _personaRow(
            skin,
            icon: Icons.flag_rounded,
            iconTint: skin.pastelAt(0).first,
            label: '学习目标',
            value: '四六级 · 兴趣阅读',
          ),
          _dash(skin),
          _personaRow(
            skin,
            icon: Icons.error_outline_rounded,
            iconTint: skin.pastelAt(1).first,
            label: '弱项',
            value: '语法:时态 8 次 · 冠词 5 次',
          ),
          _dash(skin),
          _personaRow(
            skin,
            icon: Icons.auto_stories_outlined,
            iconTint: skin.pastelAt(2).first,
            label: '最近阅读',
            value: '近 30 天读完 4 篇 · 180 词/分',
          ),
          const SizedBox(height: 8),
          // 可解释:把"为什么推这些"摆在用户面前,不让人开盲盒
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: skin.accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('为什么推这些',
                    style: _t(
                        size: 10,
                        weight: FontWeight.w800,
                        color: skin.accent)),
                const SizedBox(height: 3),
                Text(
                  '按 i+10 档 + 四六级目标,优先长难句多、题材贴近考试的原文;'
                  '语法弱项「时态」会在阅读里标出来。已避开你屏蔽的:影视娱乐、八卦。',
                  style: _t(
                      size: 10.5, color: skin.inkSoft, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _personaRow(
    V4Skin skin, {
    required IconData icon,
    required Color iconTint,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: iconTint.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: skin.ink),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(label,
                style: _t(size: 10.5, color: skin.inkFaint)),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _t(
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: skin.ink,
                    height: 1.35)),
          ),
        ),
      ],
    );
  }

  Widget _dash(V4Skin skin) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Container(height: 1, color: skin.hairline),
      );

  Widget _miniAction(V4Skin skin, IconData icon, String label) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: skin.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 14, color: skin.inkSoft),
          const SizedBox(width: 5),
          Text(label, style: _t(size: 11, color: skin.inkSoft)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// B · 按需找结果页
// ═══════════════════════════════════════════════════════════════════════

class _ResultB extends StatelessWidget {
  const _ResultB();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ColoredBox(
      color: skin.pageBg,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 12),
          _appBar(
            skin,
            title: '为你挑的材料',
            trailing: _roundBtn(skin, Icons.tune_rounded),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 依据卡:任何一条推荐都能指回真实字段
                  _basisCard(skin),
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: <Widget>[
                      Text('12 篇 · 2 组 · 分 2 页',
                          style: _t(
                              size: 11,
                              weight: FontWeight.w700,
                              color: skin.inkSoft)),
                      const Spacer(),
                      Text('官方搜索约 ¥0.012',
                          style: _t(size: 10, color: skin.inkFaint)),
                    ],
                  ),
                  _groupHeader(skin, '教材 · 课本', 2),
                  _resultCard(
                    skin,
                    title: 'New Concept English 3',
                    titleCn: '新概念英语 第三册',
                    snippet: '经典教材,长难句密度高,适合系统补语法与表达。',
                    reason: '为什么推:难度 96% 落在你选的 i+10 · 命中目标「四六级」',
                    tags: const <String>[
                      '教材',
                      'Lv3',
                      '12,000 词',
                      '覆盖率 96%'
                    ],
                    actions: '保存到我的',
                  ),
                  _resultCard(
                    skin,
                    title: 'English Grammar in Use (Intermediate)',
                    titleCn: '剑桥中级语法在用',
                    snippet: '按语法点分章,正好补你的弱项「时态」。',
                    reason: '为什么推:弱项「时态」8 次 → 优先找时态密集材料',
                    tags: const <String>['教材', 'Lv3', '9,200 词'],
                    actions: '保存到我的',
                  ),
                  _groupHeader(skin, '应试真题', 1),
                  _resultCard(
                    skin,
                    title: 'CET-4 真题 2024 阅读',
                    titleCn: '四级真题 2024 阅读部分',
                    snippet: '含答案解析与高频词表,读前可预热 12 个生词。',
                    reason: '为什么推:目标「四六级」+ 真题原文,官方搜索抓到',
                    tags: const <String>[
                      '真题',
                      'Lv3',
                      '8,000 词',
                      '已存 2 篇'
                    ],
                    actions: '已在我的',
                  ),
                  const SizedBox(height: Gap.xs),
                  _pager(skin, page: 0, total: 2),
                  const SizedBox(height: Gap.xs),
                  _wideAction(skin, Icons.travel_explore_rounded,
                      '继续找更多(追加新结果,页数随之增加)'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _basisCard(V4Skin skin) {
    return _card(
      skin,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.insights_rounded, size: 15, color: skin.accent),
              const SizedBox(width: 5),
              Text('这次按什么找的',
                  style: _t(
                      size: 11.5,
                      weight: FontWeight.w800,
                      color: skin.ink)),
              const Spacer(),
              Text('改条件',
                  style: _t(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: skin.accent)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: const <Widget>[
              _StaticTag('i+10 难度档'),
              _StaticTag('四六级'),
              _StaticTag('语法·时态薄弱'),
              _StaticTag('近 30 天读完 4 篇'),
              _StaticTag('已避开 影视娱乐'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wideAction(V4Skin skin, IconData icon, String label) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: skin.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 15, color: skin.inkSoft),
          const SizedBox(width: 6),
          Text(label, style: _t(size: 11, color: skin.inkSoft)),
        ],
      ),
    );
  }
}

class _StaticTag extends StatelessWidget {
  final String label;
  const _StaticTag(this.label);

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: skin.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: _t(size: 9.5, color: skin.inkSoft)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// C · 工作台式
// ═══════════════════════════════════════════════════════════════════════

class _EntryC extends StatelessWidget {
  const _EntryC();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ColoredBox(
      color: skin.pageBg,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 12),
          _appBar(skin,
              title: '找材料', trailing: _roundBtn(skin, Icons.view_list_rounded)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 模式切换:两个模式各自进独立页面,但共用这个工作台
                  Container(
                    height: 40,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: skin.surfaceAlt,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(child: _segment(skin, '自由搜', false)),
                        Expanded(child: _segment(skin, '按需找', true)),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  // 顶部数据条:学习助理的三项硬数据
                  Row(
                    children: <Widget>[
                      _stat(skin, '4,200', '已掌握词', accent: true),
                      const SizedBox(width: 6),
                      _stat(skin, '4 篇', '近 30 天读完'),
                      const SizedBox(width: 6),
                      _stat(skin, '时态', '最弱语法点'),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  // 筛选台:一行一项,紧凑可扫读
                  _card(
                    skin,
                    padding:
                        const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      children: <Widget>[
                        _filterRow(skin, '难度', const <String>[
                          'i+1',
                          'i+10',
                          'i+100',
                          '不限'
                        ], selected: 1),
                        _filterRow(skin, '来源', const <String>[
                          '全部',
                          '公版书',
                          '外刊',
                          '论文'
                        ], selected: 2),
                        _filterRow(skin, '类型', const <String>[
                          '教材',
                          '真题',
                          '文章'
                        ], selected: -1),
                        _filterRow(skin, '场景', const <String>[
                          '应试',
                          '出国',
                          '生活',
                          '工作'
                        ], selected: 0),
                        _filterRow(skin, '语言', const <String>['英文'],
                            selected: 0),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  _primary(skin, '按这些条件找', icon: Icons.auto_awesome_rounded),
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: <Widget>[
                      Expanded(
                          child: _miniAction(skin, Icons.restart_alt_rounded,
                              '清空筛选')),
                      const SizedBox(width: Gap.xs),
                      Expanded(
                          child: _miniAction(
                              skin, Icons.tune_rounded, '改需求量')),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: skin.surfaceAlt.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.history_rounded,
                            size: 15, color: skin.inkFaint),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '上次结果:3 组 · 18 篇 · 2 分钟前',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                _t(size: 10.5, color: skin.inkSoft),
                          ),
                        ),
                        Text('回到上次',
                            style: _t(
                                size: 10.5,
                                weight: FontWeight.w700,
                                color: skin.accent)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(V4Skin skin, String label, bool active) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? skin.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: active ? skin.shadow : null,
      ),
      child: Text(label,
          style: _t(
              size: 12,
              weight: active ? FontWeight.w800 : FontWeight.w500,
              color: active ? skin.ink : skin.inkSoft)),
    );
  }

  Widget _filterRow(V4Skin skin, String label, List<String> options,
      {required int selected}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 30,
            child: Text(label,
                style: _t(size: 10, color: skin.inkFaint)),
          ),
          Expanded(
            child: Wrap(
              spacing: 5,
              runSpacing: 4,
              children: <Widget>[
                for (var i = 0; i < options.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: i == selected
                          ? skin.accent.withValues(alpha: 0.12)
                          : skin.surfaceAlt,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: i == selected
                            ? skin.accent.withValues(alpha: 0.45)
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      options[i],
                      style: _t(
                        size: 10,
                        weight: i == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i == selected ? skin.accent : skin.inkSoft,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniAction(V4Skin skin, IconData icon, String label) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: skin.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 14, color: skin.inkSoft),
          const SizedBox(width: 5),
          Text(label, style: _t(size: 11, color: skin.inkSoft)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// C · 工作台结果页
// ═══════════════════════════════════════════════════════════════════════

class _ResultC extends StatelessWidget {
  const _ResultC();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return ColoredBox(
      color: skin.pageBg,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 6, Gap.page, 0),
            child: Row(
              children: <Widget>[
                _roundBtn(skin, Icons.arrow_back_rounded),
                const SizedBox(width: Gap.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('找材料 · 结果',
                          style: _t(
                              size: 16,
                              weight: FontWeight.w900,
                              color: skin.ink,
                              spacing: -0.3)),
                      Text('条件:i+10 · 四六级 · 语法弱项 · 英文',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _t(size: 9.5, color: skin.inkFaint)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: skin.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('筛选 3',
                      style: _t(
                          size: 10.5,
                          weight: FontWeight.w700,
                          color: skin.accent)),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            child: Row(
              children: <Widget>[
                Text('12 篇 · 第 1 页(每页 10 条)',
                    style: _t(
                        size: 10.5,
                        weight: FontWeight.w600,
                        color: skin.inkSoft)),
                const Spacer(),
                Text('本次约 ¥0.012',
                    style: _t(size: 9.5, color: skin.inkFaint)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _denseGroupLabel(skin, '教材 · 课本'),
                  _denseRow(
                    skin,
                    index: '01',
                    title: 'New Concept English 3',
                    titleCn: '新概念英语 第三册',
                    meta: 'Lv3 · 12,000 词 · 覆盖率 96%',
                    tag: '命中目标 四六级',
                  ),
                  _denseRow(
                    skin,
                    index: '02',
                    title: 'English Grammar in Use',
                    titleCn: '剑桥中级语法在用',
                    meta: 'Lv3 · 9,200 词 · 时态章节',
                    tag: '补弱项 时态',
                  ),
                  _denseGroupLabel(skin, '应试真题'),
                  _denseRow(
                    skin,
                    index: '03',
                    title: 'CET-4 真题 2024 阅读',
                    titleCn: '四级真题 2024 阅读',
                    meta: 'Lv3 · 8,000 词 · 已存 2 篇',
                    tag: '真题原文',
                  ),
                  _denseGroupLabel(skin, '外刊 · 新闻'),
                  _denseRow(
                    skin,
                    index: '04',
                    title: 'Climate Change and Coastal Cities',
                    titleCn: '气候变化与沿海城市',
                    meta: 'NPR · 760 词 · 约 6 分钟',
                    tag: '难度适配 i+10',
                  ),
                  _denseRow(
                    skin,
                    index: '05',
                    title: 'The Future of Language Learning',
                    titleCn: '语言学习的未来',
                    meta: 'NPR · 约 8 分钟',
                    tag: '难度适配 i+10',
                  ),
                  const SizedBox(height: Gap.sm),
                  _wideNote(skin),
                ],
              ),
            ),
          ),
          // 底部固定动作条:页码 + 保存/继续找 —— 工作台的"控制台"感
          Container(
            padding: const EdgeInsets.fromLTRB(Gap.page, 8, Gap.page, 12),
            decoration: BoxDecoration(
              color: skin.surface,
              border: Border(top: BorderSide(color: skin.hairline)),
              boxShadow: skin.shadow,
            ),
            child: Row(
              children: <Widget>[
                _pagerArrow(skin, Icons.chevron_left_rounded, true),
                const SizedBox(width: 6),
                Text('第 1 / 2 页',
                    style: _t(
                        size: 11,
                        weight: FontWeight.w700,
                        color: skin.inkSoft)),
                const SizedBox(width: 6),
                _pagerArrow(skin, Icons.chevron_right_rounded, true),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: skin.ink,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.travel_explore_rounded,
                          size: 14, color: skin.onAccent),
                      const SizedBox(width: 5),
                      Text('继续找更多',
                          style: _t(
                              size: 11.5,
                              weight: FontWeight.w700,
                              color: skin.onAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _denseGroupLabel(V4Skin skin, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs, bottom: 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: skin.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: _t(
                  size: 11,
                  weight: FontWeight.w800,
                  color: skin.inkSoft)),
        ],
      ),
    );
  }

  Widget _denseRow(
    V4Skin skin, {
    required String index,
    required String title,
    required String titleCn,
    required String meta,
    required String tag,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: skin.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: skin.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 22,
            child: Text(index,
                style: _t(
                    size: 13,
                    weight: FontWeight.w900,
                    color: skin.inkFaint)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(
                        size: 13,
                        weight: FontWeight.w800,
                        color: skin.ink)),
                Text(titleCn,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(size: 10.5, color: skin.inkSoft)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 5,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(meta,
                        style: _t(size: 9.5, color: skin.inkFaint)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: skin.accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(tag,
                          style: _t(
                              size: 9, color: skin.accent)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            children: <Widget>[
              Icon(Icons.bookmark_add_outlined,
                  size: 17, color: skin.inkSoft),
              const SizedBox(height: 8),
              Icon(Icons.open_in_new_rounded,
                  size: 15, color: skin.inkFaint),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wideNote(V4Skin skin) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: skin.surfaceAlt.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded,
              size: 14, color: skin.inkFaint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '每页 10 条 · 类型分组保留 · 切页回顶部;「继续找更多」追加,页数随之增加',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _t(size: 9.5, color: skin.inkSoft, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
