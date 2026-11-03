/// 用**真实生产组件**渲一张 AI 原生件新皮:思考块 + 流式气泡。
/// (上一张 ai-ux-probe 是手绘提案,这张是落地后的实拍,确保没有走样)
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/config/v4_theme.dart';
import 'package:readflow/screens/input/widgets/follow_up_bubble.dart';
import 'package:readflow/screens/input/widgets/follow_up_models.dart';
import 'package:readflow/screens/input/widgets/model_avatars.dart';

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
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
    return;
  }
}

ThemeData _theme() {
  final base = AppTheme.lightTheme;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: _fontFamily),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: _fontFamily),
  );
}

void main() {
  testWidgets('AI 原生件实拍', (tester) async {
    await _loadFont();
    await _loadIcons();
    addTearDown(tester.view.reset);

    tester.view.physicalSize = const Size(440, 760);
    tester.view.devicePixelRatio = 1.0;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: Builder(
            builder: (context) => Scaffold(
              backgroundColor: V4Skin.of(context).pageBg,
              body: ListView(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                children: <Widget>[
                  // 思考中 + 流式正文(真实 AiFollowUpBubble / ThinkingBlock)
                  AiFollowUpBubble(
                    message: const FollowUpMessage(
                      role: 'ai',
                      model: 'doubao-seed-1.6',
                      streaming: true,
                      reasoningText:
                          '先确认用户问的是"普通孩子"这一点…\n'
                          '这篇文章的魔法是比喻,需要把"自信/耐心"和孩子的成长连线…\n'
                          '用原文的三组词回应比较稳。',
                      content:
                          '作者把"魔法"当作一种隐喻:真正的成长来自**耐心、好奇心和勇气**'
                          '这三件"普通孩子也学得会"的事。',
                    ),
                    avatar: aiAvatar(
                      radius: 14,
                      modelName: 'doubao-seed-1.6',
                      context: context,
                    ),
                  ),
                  // 思考完成(非流式)示例:无收藏 Provider 时不渲染星标,安全
                  AiFollowUpBubble(
                    message: const FollowUpMessage(
                      role: 'ai',
                      model: 'deepseek-chat',
                      streaming: true,
                      reasoningText: null,
                      content:
                          '可以这样理解:学院并不筛选"有天赋的人",而是让每个孩子'
                          '在练习里长出自信。',
                    ),
                    avatar: aiAvatar(
                      radius: 14,
                      modelName: 'deepseek-chat',
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(ListView).first);
      await precacheImage(const AssetImage('assets/images/whale_tail.png'), ctx);
      await precacheImage(const AssetImage('assets/icons/doubao-color.png'), ctx);
      await precacheImage(
          const AssetImage('assets/icons/deepseek-color.png'), ctx);
    });
    await tester.pump(const Duration(milliseconds: 400));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/ui_v4_flows').createSync(recursive: true);
      File('build/ui_v4_flows/jelly_ai_actual.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
