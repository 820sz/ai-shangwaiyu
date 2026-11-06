/// 输出链路视觉重做 · 真实渲染预览（2 个方向 + 答题页）。
///
/// 背景：用户 xi283 的硬规矩是「先给方案与真实渲染图，认可后才改生产代码」。
/// 本文件**只画预览**，不 import 任何生产页面、不改 lib/；
/// 写法与 `test/reader_design_previews_test.dart` / `test/material_channel_render_test.dart`
/// 一致：加载 Windows 中文字体 + MaterialIcons，390×844 逻辑屏，
/// `RenderRepaintBoundary.toImage(pixelRatio: 3)` → 1170×2532 PNG。
///
/// 出图（同时写 build/ui_real/ 与 docs/ui-preview/real/）：
/// - `output-preview-A.png`        方向 A · 纸面工作台 —— 四阶设置（出题来源）
/// - `output-preview-B.png`        方向 B · 果冻阶梯 —— 四阶设置（出题来源）
/// - `output-preview-answer-A.png` 方向 A · 答题页（含来源标注 + 等级筛选）
///
/// 三张图都刻意画了用户 2026-11-06 提的两个 P0：
/// ① 材料来源标到「2023 年 12 月 · 第 1 套 · 来源站点」；
/// ② 顶部有考试等级筛选（全部 / CET-4 / CET-6 / 考研 / 雅思）。
///
/// 运行：`flutter test test/output_preview_render_test.dart --no-pub`
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/design_tokens.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/config/v4_theme.dart';
import 'package:readflow/widgets/graphics/graphics.dart';
import 'package:readflow/widgets/v4/v4_kit.dart';

const String _fontFamily = 'PreviewCJK';

Future<void> _loadFont() async {
  for (final path in <String>[
    'C:/Windows/Fonts/NotoSansSC-VF.ttf',
    'C:/Windows/Fonts/Deng.ttf',
  ]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final bytes =
        Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync()));
    await (FontLoader('Roboto')..addFont(bytes)).load();
    await (FontLoader(_fontFamily)..addFont(bytes)).load();
    return;
  }
}

Future<void> _loadIcons() async {
  for (final path in <String>[
    'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
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
              fontSize: 14,
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
  );
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
    // 交付目录：用户直接看图的地方（与 docs/ui-preview/jelly/ 同一约定）
    Directory('docs/ui-preview/real').createSync(recursive: true);
    File('docs/ui-preview/real/$fileName').writeAsBytesSync(data);
    image.dispose();
  });
}

// ═══════════════════════════════════════════════════════════════════
// 假数据（与生产无关，只用于视觉评审）
// ═══════════════════════════════════════════════════════════════════

const String _paperLine = '2023 年 12 月 · 第 1 套';
const String _siteLine = '中国教育考试网 · 公开页面';
const List<String> _levels = <String>['全部', 'CET-4', 'CET-6', '考研', '雅思'];

// ═══════════════════════════════════════════════════════════════════
// 共用小件（两个方向取同一套令牌，形状语言不同）
// ═══════════════════════════════════════════════════════════════════

/// 方向 A 的等级筛选：细边扁平胶囊，选中 = 主色渐充实心。
Widget _chipA(BuildContext context, String label, {bool selected = false}) {
  final skin = V4Skin.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: selected ? null : skin.surface,
      gradient: selected ? skin.accentFill : null,
      borderRadius: BorderRadius.circular(999),
      border: selected ? null : Border.all(color: skin.hairline, width: 1),
    ),
    child: Text(
      label,
      style: AppFont.tagStyle.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: selected ? skin.onAccent : skin.inkSoft,
      ),
    ),
  );
}

/// 方向 A 的区块头：编号 + 标题 + 细线 + 右侧计数（杂志内页的秩序感）。
Widget _sectionHeadA(
  BuildContext context,
  String index,
  String title, {
  String? trailing,
}) {
  final skin = V4Skin.of(context);
  return Row(
    children: <Widget>[
      Text(
        index,
        style: AppFont.tagStyle.copyWith(
          color: skin.accent,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        title,
        style: AppFont.subheadStyle.copyWith(
          color: skin.ink,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: skin.hairline)),
      const SizedBox(width: 10),
      if (trailing != null)
        Text(
          trailing,
          style: AppFont.tagStyle.copyWith(
            color: skin.inkFaint,
            fontSize: 10.5,
          ),
        ),
    ],
  );
}

/// 方向 A · 来源行：白面 + 0.9 细边 + 无阴影（纸面工作台不靠浮起分层）。
Widget _paperRowA(
  BuildContext context, {
  required String title,
  required String meta,
  required String level,
  required OutputTierArt art,
  required int tint,
}) {
  final skin = V4Skin.of(context);
  final pastel = skin.pastelAt(tint);
  return Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: skin.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: skin.hairline, width: 1),
    ),
    child: Row(
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: pastel,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: OutputTierGraphic(tier: art, size: 24)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFont.subheadStyle.copyWith(
                  color: skin.ink,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFont.tagStyle.copyWith(
                  color: skin.inkSoft,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: skin.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            level,
            style: AppFont.tagStyle.copyWith(
              color: skin.inkSoft,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 18, color: skin.inkFaint),
      ],
    ),
  );
}

/// 方向 A 的"我的题库"行：只有细线，不给卡片（低干扰清单）。
Widget _flatRowA(
  BuildContext context, {
  required String title,
  required String meta,
  bool last = false,
}) {
  final skin = V4Skin.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: last
          ? null
          : Border(bottom: BorderSide(color: skin.hairline, width: 1)),
    ),
    child: Row(
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: skin.inkFaint,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFont.bodyStyle.copyWith(
                  color: skin.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFont.tagStyle.copyWith(
                  color: skin.inkFaint,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 17, color: skin.inkFaint),
      ],
    ),
  );
}

/// 主行动胶囊（两个方向共用，保证"主行动唯一且明显"）。
Widget _primaryPill(
  BuildContext context,
  String label, {
  IconData? icon,
  bool expand = false,
}) {
  final skin = V4Skin.of(context);
  final content = Container(
    height: 50,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      gradient: skin.accentFill,
      borderRadius: BorderRadius.circular(999),
      boxShadow: skin.heroShadow,
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 17, color: skin.onAccent),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: AppFont.tagStyle.copyWith(
            color: skin.onAccent,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    ),
  );
  return expand ? SizedBox(width: double.infinity, child: content) : content;
}

/// 方向 B 的光斑（头图底子透气，不压文字）。
Widget _blob(Color color, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[color, color.withValues(alpha: 0.0)],
        ),
      ),
    );

/// 方向 B 的玻璃胶囊（头图上的状态标签）。
Widget _glassChipB(BuildContext context, IconData icon, String label) {
  final skin = V4Skin.of(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.66),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: skin.inkSoft),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppFont.tagStyle.copyWith(
            color: skin.inkSoft,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

/// 方向 B 的等级分段控件（白卡内整颗渐变的选中段）。
Widget _segmentedB(BuildContext context, List<String> labels, int selected) {
  final skin = V4Skin.of(context);
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: skin.surface,
      borderRadius: BorderRadius.circular(999),
      boxShadow: skin.shadow,
    ),
    child: Row(
      children: <Widget>[
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                gradient: i == selected ? skin.accentFill : null,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Center(
                child: Text(
                  labels[i],
                  style: AppFont.tagStyle.copyWith(
                    color: i == selected ? skin.onAccent : skin.inkSoft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// 方向 B 的果冻来源卡：pastel 渐变 + 进度环 + 白色胶囊 CTA。
Widget _jellySourceCardB(
  BuildContext context, {
  required String title,
  required String meta,
  required int tint,
  required double progress,
  String cta = '开始',
  bool recommended = false,
}) {
  final skin = V4Skin.of(context);
  return Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      gradient: skin.pastelFill(tint),
      borderRadius: BorderRadius.circular(skin.cardRadius),
      boxShadow: skin.shadow,
    ),
    child: Row(
      children: <Widget>[
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: V4ProgressRing(
              value: progress,
              size: 30,
              color: skin.ink,
              trackColor: skin.ink.withValues(alpha: 0.14),
              strokeWidth: 3,
              center: Text(
                '${(progress * 100).round()}',
                style: AppFont.tagStyle.copyWith(
                  color: skin.ink,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFont.subheadStyle.copyWith(
                  color: skin.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFont.tagStyle.copyWith(
                  color: skin.inkSoft,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                recommended ? '推荐' : cta,
                style: AppFont.tagStyle.copyWith(
                  color: skin.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.play_arrow_rounded, size: 13, color: skin.ink),
            ],
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════
// 方向 A · 纸面工作台（Editorial）
//
// 主张：输出是「做题 / 写长文 / 看批改」的专注场景，界面必须像一张干净的
// 练习纸 —— 无渐变、无阴影、只有细边与编号；主行动只有一个。
// 视觉语言：白面卡 + 1px 细边 + 16/20 圆角、编号式区块头、扁平等级胶囊。
// ═══════════════════════════════════════════════════════════════════
class _PreviewAHome extends StatelessWidget {
  const _PreviewAHome();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Gap.page, Gap.sm, Gap.page, Gap.md),
              children: <Widget>[
                // ① 极细工具行：返回 / 阶位眉标 / 历史
                Row(
                  children: <Widget>[
                    Icon(Icons.arrow_back_rounded,
                        size: 20, color: skin.ink),
                    const Spacer(),
                    Text(
                      '第 04 阶 · 写篇',
                      style: AppFont.tagStyle.copyWith(
                        color: skin.inkFaint,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: skin.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: skin.hairline, width: 1),
                      ),
                      child: Icon(Icons.history_rounded,
                          size: 17, color: skin.inkSoft),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // ② 标题区：大标题 + 一句说明 + 等级筛选（P0-2 分桶入口）
                Text(
                  '选一份真题',
                  style: AppFont.displayStyle.copyWith(
                    color: skin.ink,
                    fontSize: 30,
                    height: 1.1,
                    letterSpacing: -0.9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '先按考试等级筛，题目都标到年份 / 套数 / 来源站点',
                  style: AppFont.bodyStyle.copyWith(
                    color: skin.inkSoft,
                    fontSize: 13,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    for (var i = 0; i < _levels.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: 8),
                      _chipA(context, _levels[i], selected: i == 1),
                    ],
                  ],
                ),
                const SizedBox(height: 22),
                // ③ 推荐来源（P0-1 来源标注：年份 / 套数 / 站点）
                _sectionHeadA(context, '01', '推荐来源', trailing: '3 份'),
                const SizedBox(height: 12),
                _paperRowA(
                  context,
                  title: '2023 年 12 月 四级真题 · 第 1 套',
                  meta: '写作 · 3 题 · 中国教育考试网 · 待校对',
                  level: 'CET-4',
                  art: OutputTierArt.essay,
                  tint: 3,
                ),
                const SizedBox(height: 8),
                _paperRowA(
                  context,
                  title: '2023 年 6 月 四级真题 · 第 2 套',
                  meta: '翻译 · 2 题 · 中国教育考试网 · 已校对',
                  level: 'CET-4',
                  art: OutputTierArt.essay,
                  tint: 1,
                ),
                const SizedBox(height: 8),
                _paperRowA(
                  context,
                  title: '2022 年 12 月 四级真题 · 第 1 套',
                  meta: '写作 · 2 题 · 新东方公开题库 · 已校对',
                  level: 'CET-4',
                  art: OutputTierArt.essay,
                  tint: 2,
                ),
                const SizedBox(height: 22),
                // ④ 我的题库（历史题组，带等级与来源）
                _sectionHeadA(context, '02', '我的题库', trailing: '18 组'),
                const SizedBox(height: 2),
                _flatRowA(
                  context,
                  title: '2024 年 6 月 四级真题 · 第 1 套',
                  meta: 'CET-4 · 写作 · 做过 2 次 · 8 月 12 日',
                ),
                _flatRowA(
                  context,
                  title: '2023 年 12 月 六级真题 · 第 2 套',
                  meta: 'CET-6 · 翻译 · 做过 1 次 · 7 月 30 日',
                ),
                _flatRowA(
                  context,
                  title: '从《The Four Million》出的题',
                  meta: '我的材料 · 写段 · 做过 3 次 · 7 月 18 日',
                  last: true,
                ),
                const SizedBox(height: Gap.md),
              ],
            ),
          ),
          // ⑤ 底部固定主行动（唯一）
          Container(
            padding: const EdgeInsets.fromLTRB(Gap.page, 10, Gap.page, 24),
            decoration: BoxDecoration(
              color: skin.pageBg,
              border: Border(top: BorderSide(color: skin.hairline, width: 1)),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: skin.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: skin.hairline, width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.auto_stories_outlined,
                            size: 16, color: skin.inkSoft),
                        const SizedBox(width: 6),
                        Text(
                          '从我的材料出题',
                          style: AppFont.tagStyle.copyWith(
                            color: skin.inkSoft,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _primaryPill(context, '开始练习',
                    icon: Icons.edit_note_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 方向 B · 果冻阶梯（Jelly，与输入板块 v5 同语言）
//
// 主张：输出首页是入口，应该和主屏一样「有色彩、有层次」；一进内页再收敛。
// 视觉语言：渐变头图 + 光斑、玻璃胶囊、pastel 渐变来源卡 + 进度环 + 白胶囊 CTA、
// 白卡分段控件；阴影成对（skin.shadow）。
// ═══════════════════════════════════════════════════════════════════
class _PreviewBHome extends StatelessWidget {
  const _PreviewBHome();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    final pastel = skin.pastelAt(3);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          // ① 渐变头图（与输入/我的同款果冻头图关系）
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color.alphaBlend(
                    pastel.first.withValues(alpha: 0.55),
                    skin.heroGradient.first,
                  ),
                  Color.alphaBlend(
                    skin.accentAlt.withValues(alpha: 0.10),
                    skin.heroGradient.last,
                  ),
                ],
              ),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(32)),
              boxShadow: skin.heroShadow,
            ),
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: -70,
                  top: -90,
                  child: _blob(skin.accent.withValues(alpha: 0.26), 220),
                ),
                Positioned(
                  right: -60,
                  top: -40,
                  child: _blob(skin.accentAlt.withValues(alpha: 0.24), 200),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Gap.page, 12, Gap.page, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.75),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.arrow_back_rounded,
                                size: 18, color: skin.ink),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.70),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.tune_rounded,
                                    size: 13, color: skin.inkSoft),
                                const SizedBox(width: 5),
                                Text(
                                  '练习中心',
                                  style: AppFont.tagStyle.copyWith(
                                    color: skin.ink,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '按真题练',
                        style: AppFont.displayStyle.copyWith(
                          color: skin.ink,
                          fontSize: 30,
                          height: 1.12,
                          letterSpacing: -0.9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '$_paperLine · 写作真题',
                        style: AppFont.bodyStyle.copyWith(
                          color: skin.inkSoft,
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _glassChipB(
                              context, Icons.edit_note_rounded, '写作 · 3 题'),
                          _glassChipB(context, Icons.link_rounded, '来源已标注'),
                          _glassChipB(
                              context, Icons.verified_outlined, '待人工校对'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ② 等级分段控件（P0-2：单独练四级 / 六级）
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 18, Gap.page, 0),
            child: _segmentedB(context, const <String>[
              '全部',
              'CET-4',
              'CET-6',
              '考研',
            ], 1),
          ),
          // ③ 果冻来源卡（P0-1：来源 / 年份 / 套数写进卡片）
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 18, Gap.page, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '推荐真题',
                      style: AppFont.subheadStyle.copyWith(
                        color: skin.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '按你的目标（CET-4）排序',
                      style: AppFont.tagStyle.copyWith(
                        color: skin.inkFaint,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _jellySourceCardB(
                  context,
                  title: '2023 年 12 月 四级真题 · 第 1 套',
                  meta: '写作 · 3 题 · 中国教育考试网 · 待校对',
                  tint: 3,
                  progress: 0.66,
                  recommended: true,
                ),
                const SizedBox(height: 10),
                _jellySourceCardB(
                  context,
                  title: '2023 年 6 月 四级真题 · 第 2 套',
                  meta: '翻译 · 2 题 · 中国教育考试网 · 已校对',
                  tint: 2,
                  progress: 0.33,
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          // ④ 我的题库（白卡短列表）
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 22, Gap.page, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '我的题库',
                      style: AppFont.subheadStyle.copyWith(
                        color: skin.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '18 组',
                      style: AppFont.tagStyle.copyWith(
                        color: skin.inkFaint,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: skin.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: skin.shadow,
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  child: Column(
                    children: <Widget>[
                      _flatRowA(
                        context,
                        title: '2024 年 6 月 四级真题 · 第 1 套',
                        meta: 'CET-4 · 写作 · 做过 2 次 · 8 月 12 日',
                      ),
                      _flatRowA(
                        context,
                        title: '2023 年 12 月 六级真题 · 第 2 套',
                        meta: 'CET-6 · 翻译 · 做过 1 次 · 7 月 30 日',
                        last: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ⑤ 底部主行动
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 22, Gap.page, 28),
            child: _primaryPill(context, '开始练习',
                icon: Icons.edit_note_rounded, expand: true),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 方向 A · 答题页（纸面 + 来源标注 + 等级标签）
// ═══════════════════════════════════════════════════════════════════
class _PreviewAAnswer extends StatelessWidget {
  const _PreviewAAnswer();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      body: Column(
        children: <Widget>[
          // ① 顶栏：进度 + 等级标签 + 关闭
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, 0),
            child: Row(
              children: <Widget>[
                Icon(Icons.arrow_back_rounded, size: 20, color: skin.ink),
                const SizedBox(width: 12),
                Text(
                  '第 3 / 6 题',
                  style: AppFont.metaStyle.copyWith(
                    color: skin.inkSoft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: skin.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'CET-4',
                    style: AppFont.tagStyle.copyWith(
                      color: skin.inkSoft,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.close_rounded, size: 20, color: skin.inkSoft),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ② 进度：3px 细线，不用粗进度条抢注意力
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: 0.5,
                minHeight: 3,
                backgroundColor: skin.hairline,
                color: skin.accent,
              ),
            ),
          ),
          // ③ 题面 + 作答（纸面）
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Gap.page, 18, Gap.page, Gap.md),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '写句 · 回译',
                      style: AppFont.tagStyle.copyWith(
                        color: skin.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '来自 2023 年 12 月 第 1 套',
                      style: AppFont.tagStyle.copyWith(
                        color: skin.inkFaint,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 题面纸卡
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: skin.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: skin.hairline, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '把这句话译回英文',
                        style: AppFont.tagStyle.copyWith(
                          color: skin.inkFaint,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '他直到深夜才意识到自己忘了带钥匙。',
                        style: AppFont.titleStyle.copyWith(
                          color: skin.ink,
                          fontSize: 18,
                          height: 1.7,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          _metaTag(context, '≥ 8 词'),
                          const SizedBox(width: 6),
                          _metaTag(context, '语法 · 倒装'),
                          const SizedBox(width: 6),
                          _metaTag(context, '待校对'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // 作答区（白纸，无边框噪声）
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  decoration: BoxDecoration(
                    color: skin.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: skin.hairline, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '你的英文',
                        style: AppFont.tagStyle.copyWith(
                          color: skin.inkFaint,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 112,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            '在这里写出你的英文句子…',
                            style: AppFont.bodyStyle.copyWith(
                              color: skin.inkFaint,
                              fontSize: 15,
                              height: 1.7,
                            ),
                          ),
                        ),
                      ),
                      Container(height: 1, color: skin.hairline),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Icon(Icons.camera_alt_outlined,
                              size: 18, color: skin.inkSoft),
                          const SizedBox(width: 18),
                          Icon(Icons.image_outlined,
                              size: 18, color: skin.inkSoft),
                          const Spacer(),
                          Text(
                            '0 词',
                            style: AppFont.tagStyle.copyWith(
                              color: skin.inkFaint,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // 来源行（P0-1：用户在答题时就能确认"这题哪来的"）
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: skin.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: skin.hairline, width: 1),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.link_rounded, size: 16, color: skin.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '本题来源',
                              style: AppFont.tagStyle.copyWith(
                                color: skin.inkFaint,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$_siteLine · $_paperLine · 写作',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFont.tagStyle.copyWith(
                                color: skin.inkSoft,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.open_in_new_rounded,
                          size: 15, color: skin.inkFaint),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // 批改标准：作答前就能看到"会怎么被打分"，不让人开盲盒
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: skin.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: skin.hairline, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            '批改标准',
                            style: AppFont.tagStyle.copyWith(
                              color: skin.inkFaint,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'CET-4 写作 rubric',
                            style: AppFont.tagStyle.copyWith(
                              color: skin.inkFaint,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          _rubricPart(context, '内容', 40),
                          const SizedBox(width: 12),
                          _rubricPart(context, '语言', 40),
                          const SizedBox(width: 12),
                          _rubricPart(context, '结构', 20),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ④ 底部唯一主行动
          Container(
            padding: const EdgeInsets.fromLTRB(Gap.page, 10, Gap.page, 24),
            decoration: BoxDecoration(
              color: skin.pageBg,
              border: Border(top: BorderSide(color: skin.hairline, width: 1)),
            ),
            child: _primaryPill(context, '提交批改',
                icon: Icons.fact_check_outlined, expand: true),
          ),
        ],
      ),
    );
  }

  Widget _metaTag(BuildContext context, String label) {
    final skin = V4Skin.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: skin.surfaceAlt,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: AppFont.tagStyle.copyWith(
          color: skin.inkSoft,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 一个 rubric 维度：权重数字 + 名称 + 按权重填充的细条
  Widget _rubricPart(BuildContext context, String label, int weight) {
    final skin = V4Skin.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '$weight',
                style: AppFont.subheadStyle.copyWith(
                  color: skin.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppFont.tagStyle.copyWith(
                  color: skin.inkSoft,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (weight / 40).clamp(0.0, 1.0).toDouble(),
              minHeight: 3,
              backgroundColor: skin.hairline,
              color: skin.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 出图
// ═══════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont();
    await _loadIcons();
  });

  Future<void> render(
    WidgetTester tester,
    Widget child,
    String name,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: child,
      ),
    ));
    // 预览是静态屏（无循环动画），两帧足够稳定
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 80));
    await _capture(tester, key, name);
  }

  testWidgets('方向 A · 四阶设置（出题来源）', (tester) async {
    await render(tester, const _PreviewAHome(), 'output-preview-A.png');
  });

  testWidgets('方向 B · 四阶设置（出题来源）', (tester) async {
    await render(tester, const _PreviewBHome(), 'output-preview-B.png');
  });

  testWidgets('方向 A · 答题页（来源标注 + 等级筛选）', (tester) async {
    await render(tester, const _PreviewAAnswer(), 'output-preview-answer-A.png');
  });
}
