/// v4「视觉基调」探索:把同一个 App 的五种气质渲成 PNG 给用户选。
///
/// 为什么先渲图:用户 2026-11-02 的原话是「别让我装盲盒」。基调定下来之前,
/// 不写任何页面代码 —— 方向错了,逐屏落地全是白工。
///
/// 产物(`build/ui_v4_probe/`,不进 git,重跑即重生成):
/// - `A_magazine_triptych.png` … `E_press_triptych.png`:每个基调三联图
///   「输入首页 | 输出首页 | 风格板」,3762×2150 左右;
/// - `00_overview.png`:五个基调的输入首页并排总览。
///
/// 跑法:`flutter test test/ui_v4_style_probe_test.dart --no-pub`
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';

import 'ui_v4_probe/probe_fonts.dart';
import 'ui_v4_probe/probe_screens.dart';
import 'ui_v4_probe/probe_spec.dart';

void main() {
  testWidgets('v4 基调探索:五种视觉方向渲图', (tester) async {
    await loadProbeFonts();
    await loadProbeIcons();
    addTearDown(tester.view.reset);

    // 每个基调:输入首页 + 输出首页 + 风格板,三联一排
    for (final spec in probeSpecs) {
      tester.view.physicalSize = const Size(1242, 896);
      tester.view.devicePixelRatio = 1.0;
      await _export(
        tester,
        Row(
          children: <Widget>[
            probeInputScreen(spec),
            probeOutputScreen(spec),
            probeStyleBoard(spec),
          ],
        ),
        'build/ui_v4_probe/${spec.code}_${spec.slug}_triptych.png',
        pixelRatio: 2.4,
      );
    }

    // 总览:五个基调的输入首页并排(带标题条,方便对话里指认)
    tester.view.physicalSize = const Size(2070, 956);
    tester.view.devicePixelRatio = 1.0;
    await _export(
      tester,
      Row(children: <Widget>[for (final spec in probeSpecs) _captioned(spec)]),
      'build/ui_v4_probe/00_overview.png',
      pixelRatio: 1.8,
    );
  });
}

Widget _captioned(ProbeSpec spec) {
  return SizedBox(
    width: 414,
    height: 956,
    child: Column(
      children: <Widget>[
        Container(
          height: 60,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          alignment: Alignment.centerLeft,
          color: const Color(0xFF101216),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${spec.code} · 基调',
                style: const TextStyle(
                  fontFamily: kMono,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: Color(0xFF8FB2FF),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      spec.name,
                      style: const TextStyle(
                        fontFamily: kSans,
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      spec.keywords.join(' · '),
                      style: const TextStyle(
                        fontFamily: kSans,
                        fontSize: 9.5,
                        color: Color(0xFF7C8595),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        probeInputScreen(spec),
      ],
    ),
  );
}

Future<void> _export(
  WidgetTester tester,
  Widget child,
  String path, {
  required double pixelRatio,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: const Color(0xFF101216),
          body: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/ui_v4_probe').createSync(recursive: true);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
