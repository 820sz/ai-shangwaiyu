/// AI 原生气质试渲(2026-11-03,用户问"思考过程 / 流式输出 / AI 头像 logo
/// 这些设计还有吗,追问抽屉怎么设计")。
///
/// 三屏:① 思考 + 流式输出(保留鲸鱼尾形象)② AI 身份(品牌 logo + 兜底)
/// ③ 追问抽屉新皮。只渲图,不改生产代码。
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
import 'package:readflow/screens/input/widgets/model_avatars.dart';
import 'package:readflow/widgets/v4/v4_kit.dart';
import 'package:readflow/widgets/whale_thinking.dart';

const String _previewFontFamily = 'PreviewCJK';

Future<void> _loadPreviewFont() async {
  const candidates = <String>[
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final bytes = Future<ByteData>.value(
        ByteData.sublistView(file.readAsBytesSync()),
      );
      await (FontLoader('Roboto')..addFont(bytes)).load();
      await (FontLoader(_previewFontFamily)..addFont(bytes)).load();
      return;
    } catch (_) {}
  }
}

Future<void> _loadPreviewIcons() async {
  const candidates = <String>[
    r'D:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(
            ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
      return;
    } catch (_) {}
  }
}

ThemeData _themeData() {
  final base = AppTheme.lightTheme;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _previewFontFamily),
    primaryTextTheme:
        base.primaryTextTheme.apply(fontFamily: _previewFontFamily),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          const TextStyle(
              fontFamily: _previewFontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('AI 原生气质试渲', (tester) async {
    await _loadPreviewFont();
    await _loadPreviewIcons();
    addTearDown(tester.view.reset);

    tester.view.physicalSize = const Size(1242, 896);
    tester.view.devicePixelRatio = 1.0;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _themeData(),
          home: Scaffold(
            backgroundColor: const Color(0xFF101216),
            body: Row(
              children: const <Widget>[
                SizedBox(width: 414, height: 896, child: _ThinkingStreamingPanel()),
                SizedBox(width: 414, height: 896, child: _AiIdentityPanel()),
                SizedBox(width: 414, height: 896, child: _DrawerPanel()),
              ],
            ),
          ),
        ),
      ),
    );
    // 资产图片(鲸鱼尾 / 品牌 logo)异步解码:先 precache 再截屏,
    // 否则静态帧里会出现"空白头像"(真机不会,测试环境特性)。
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(Scaffold).first);
      await precacheImage(const AssetImage('assets/images/whale_tail.png'), ctx);
      for (final icon in <String>[
        'doubao-color.png',
        'deepseek-color.png',
        'openai.png',
        'claude-color.png',
        'kimi-color.png',
        'qwen-color.png',
      ]) {
        await precacheImage(AssetImage('assets/icons/$icon'), ctx);
      }
    });
    await tester.pump(const Duration(milliseconds: 400));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.4);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/ui_v4_flows').createSync(recursive: true);
      File('build/ui_v4_flows/jelly_ai_ux.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}

// ══════════════════════════════════════════════════════════════════
// ① 思考 + 流式输出
// ══════════════════════════════════════════════════════════════════

class _ThinkingStreamingPanel extends StatelessWidget {
  const _ThinkingStreamingPanel();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(
        title: '追问 · 关于这篇文章',
        actions: <Widget>[
          IconButton(
              tooltip: '历史',
              onPressed: () {},
              icon: const Icon(Icons.history, size: 20)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.lg),
        children: <Widget>[
          // 用户气泡(右上)
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                gradient: skin.accentFill,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(6),
                ),
                boxShadow: skin.shadow,
              ),
              child: Text(
                '为什么作者说"普通孩子"也能学会魔法?',
                style: TextStyle(
                    fontSize: 13.5, height: 1.5, color: skin.onAccent),
              ),
            ),
          ),
          const SizedBox(height: Gap.md),
          // AI 气泡:头像 + 白卡
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              aiAvatar(
                radius: 15,
                modelName: 'doubao-seed-1.6',
                context: context,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: skin.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: skin.shadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 模型标签(身份,不是装饰)
                      Row(
                        children: <Widget>[
                          Text('豆包 · Seed 1.6',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: skin.inkFaint)),
                          const Spacer(),
                          Icon(Icons.star_border,
                              size: 15, color: skin.inkFaint),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // ① 思考过程:鲸鱼尾 + 可折叠,不再用 💭 emoji
                      _ThinkingProposal(skin: skin),
                      const SizedBox(height: 10),
                      // ② 流式正文:朴素 markdown + 光标
                      Text.rich(
                        TextSpan(
                          style: TextStyle(
                              fontSize: 13.5, height: 1.7, color: skin.ink),
                          children: <InlineSpan>[
                            const TextSpan(
                                text: '作者把"魔法"当作一种隐喻:真正的成长来自'),
                            TextSpan(
                              text: '耐心、好奇心和勇气',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                backgroundColor: skin.pastelAt(1).first
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            const TextSpan(text: '这三件"普通孩子也学得会"的事。'),
                          ],
                        ),
                      ),
                      // 流式光标 + 停止
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Container(
                            width: 2.5,
                            height: 15,
                            decoration: BoxDecoration(
                              color: skin.accent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('生成中…',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: skin.accent)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: skin.surfaceAlt,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.stop_rounded,
                                    size: 12, color: skin.inkSoft),
                                const SizedBox(width: 3),
                                Text('停止',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: skin.inkSoft)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          // 检索类任务的「流式时间线」(真实步骤,不造假进度)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: skin.shadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('查资料 · 4 个源',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: skin.inkSoft)),
                const SizedBox(height: 8),
                _step(skin, '维基百科 · 已连上,12 条', done: true),
                _step(skin, 'NPR · 没连上(网络问题)', failed: true),
                _step(skin, '豆瓣读书 · 已连上,6 条', done: true),
                _step(skin, '还在查第 4 个源…', running: true),
                const SizedBox(height: 6),
                Text('已查 18 篇 · 用时 6 秒',
                    style: TextStyle(fontSize: 10, color: skin.inkFaint)),
              ],
            ),
          ),
          const SizedBox(height: Gap.sm),
          Text('鲸鱼尾保留:这是用户指定的"思考中"形象',
              style: TextStyle(fontSize: 10, color: skin.inkFaint)),
        ],
      ),
    );
  }

  Widget _step(V4Skin skin, String text,
      {bool done = false, bool failed = false, bool running = false}) {
    final color = failed
        ? const Color(0xFFC46A2E)
        : done
            ? const Color(0xFF2F8A5B)
            : skin.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            failed
                ? Icons.wifi_off_rounded
                : done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_checked,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: failed ? color : skin.inkSoft,
                    fontWeight: done ? FontWeight.w600 : FontWeight.w400)),
          ),
          if (running)
            WhaleThinking(size: 15, color: skin.accent),
        ],
      ),
    );
  }
}

/// 思考块提案:鲸鱼尾 + 淡黄底 → 果冻淡染卡 + 折叠 + 底部渐隐
class _ThinkingProposal extends StatelessWidget {
  final V4Skin skin;

  const _ThinkingProposal({required this.skin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            skin.pastelAt(3).first.withValues(alpha: 0.14), skin.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: skin.pastelAt(3).first.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              WhaleThinking(size: 16, color: skin.accentAlt),
              const SizedBox(width: 5),
              Text('思考中 · 12s',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: skin.accentAlt)),
              const Spacer(),
              Icon(Icons.expand_less_rounded,
                  size: 15, color: skin.accentAlt),
            ],
          ),
          const SizedBox(height: 6),
          ShaderMask(
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black,
                Colors.black.withValues(alpha: 0),
              ],
              stops: const <double>[0.55, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Text(
              '先确认用户问的是"普通孩子"这一点…\n这篇文章的魔法是比喻,\n需要把"自信/耐心"和孩子的成长连线…\n用原文的三组词回应比较稳。',
              maxLines: 4,
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                letterSpacing: 0.1,
                color: skin.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ② AI 身份:品牌 logo + 兜底 + 用户头像
// ══════════════════════════════════════════════════════════════════

class _AiIdentityPanel extends StatelessWidget {
  const _AiIdentityPanel();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    const models = <String>[
      'doubao-seed-1.6',
      'deepseek-chat',
      'kimi-k2',
      'qwen-max',
      'gpt-4o',
      'claude-sonnet-4',
    ];
    Widget row(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 78,
                child: Text(label,
                    style: TextStyle(fontSize: 10.5, color: skin.inkFaint)),
              ),
              child,
            ],
          ),
        );
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(title: 'AI 身份 · 头像与 Logo'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, Gap.lg),
        children: <Widget>[
          Text('品牌 logo 是身份标识,不跟主题走',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: skin.ink)),
          const SizedBox(height: 4),
          Text('深色模式下只提亮,不改品牌色;加载失败退回首字母',
              style: TextStyle(fontSize: 11, color: skin.inkSoft)),
          const SizedBox(height: Gap.md),
          for (final m in models)
            row(
              m,
              aiAvatar(radius: 15, modelName: m, context: context),
            ),
          const Divider(height: Gap.md),
          row('错误态',
              aiAvatar(radius: 15, modelName: 'doubao', error: true, context: context)),
          row('未知模型',
              aiAvatar(radius: 15, modelName: 'mystery-model', context: context)),
          row('用户',
              userAvatar(context: context, radius: 15)),
          const Divider(height: Gap.md),
          Text('追问抽屉里:头像 + 模型名标签并存',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: skin.ink)),
          const SizedBox(height: Gap.sm),
          // 气泡头部:头像 + 名字 + 状态
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: skin.shadow,
            ),
            child: Row(
              children: <Widget>[
                aiAvatar(radius: 14, modelName: 'doubao-seed-1.6', context: context),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('豆包 · Seed 1.6',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: skin.ink)),
                    Text('正在思考',
                        style: TextStyle(fontSize: 9.5, color: skin.inkFaint)),
                  ],
                ),
                const Spacer(),
                Icon(Icons.more_horiz, size: 18, color: skin.inkFaint),
              ],
            ),
          ),
          const SizedBox(height: Gap.md),
          // 追问抽屉顶部模型切换:一排"槽位"胶囊
          Text('模型槽位(追问抽屉顶部)',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: skin.inkSoft)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (var i = 0; i < 3; i++)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: i == 0 ? skin.accent.withValues(alpha: 0.12) : skin.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: i == 0
                            ? skin.accent.withValues(alpha: 0.5)
                            : skin.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      aiAvatar(
                          radius: 8,
                          modelName: const <String>[
                            'doubao',
                            'deepseek',
                            'kimi'
                          ][i],
                          context: context),
                      const SizedBox(width: 5),
                      Text(
                        const <String>['豆包', 'DeepSeek', 'Kimi'][i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: i == 0 ? skin.accent : skin.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ③ 追问抽屉新皮
// ══════════════════════════════════════════════════════════════════

class _DrawerPanel extends StatelessWidget {
  const _DrawerPanel();

  @override
  Widget build(BuildContext context) {
    final skin = V4Skin.of(context);
    return Scaffold(
      backgroundColor: skin.pageBg,
      appBar: V4JellyAppBar(title: '追问抽屉 · 新皮'),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Gap.page),
              child: Text(
                '阅读器 / 识图页里点「追问」升起(可拖 0.3↔0.85)。'
                '下面是新皮的三段结构:身份头 → 可滚动对话 → 快捷提问 + 输入。',
                style: TextStyle(
                    fontSize: 11.5, height: 1.7, color: skin.inkSoft),
              ),
            ),
          ),
          // 抽屉本体(示意)
          Container(
            decoration: BoxDecoration(
              color: skin.surface,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30)),
              boxShadow: skin.heroShadow,
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // 拖拽条
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: skin.hairline,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: Gap.sm),
                // ① 身份头:标题 + 模型槽位 + 历史/新建
                Row(
                  children: <Widget>[
                    Text('追问',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: skin.ink)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: skin.surfaceAlt,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          aiAvatar(
                              radius: 7,
                              modelName: 'doubao',
                              context: context),
                          const SizedBox(width: 4),
                          Text('豆包 ▾',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: skin.inkSoft)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.history, size: 17, color: skin.inkFaint),
                    const SizedBox(width: 10),
                    Text('新建',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: skin.accent)),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                // ② 对话区
                Container(
                  height: 300,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: skin.pageBg,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            gradient: skin.accentFill,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text('这句话的"魔法"指什么?',
                              style: TextStyle(
                                  fontSize: 12.5, color: skin.onAccent)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          aiAvatar(
                              radius: 12,
                              modelName: 'doubao',
                              context: context),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: skin.surface,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: skin.shadow,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  _ThinkingProposal(skin: skin),
                                  const SizedBox(height: 8),
                                  Text(
                                    '这里的"魔法"是比喻:指耐心、好奇心这些'
                                    '普通孩子也能练出来的能力。',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.6,
                                        color: skin.ink),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ③ 快捷提问 chips
                SizedBox(
                  height: 28,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      for (final q in const <String>[
                        '英英词典解释',
                        '梳理全文结构',
                        '出 3 道理解题',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: skin.surfaceAlt,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(q,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: skin.inkSoft)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ④ 输入栏
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: skin.pageBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: skin.hairline),
                        ),
                        child: Text('基于材料提问…',
                            style: TextStyle(
                                fontSize: 12, color: skin.inkFaint)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: skin.accentFill,
                        shape: BoxShape.circle,
                        boxShadow: skin.shadow,
                      ),
                      child: Icon(Icons.arrow_upward_rounded,
                          size: 18, color: skin.onAccent),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
