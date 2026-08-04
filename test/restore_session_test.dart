import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/models/saved_session.dart';
import 'package:readflow/models/vocabulary.dart';
import 'package:readflow/screens/input/process_chat.dart';

/// 复现「继续上次会话」恢复模式渲染问题:
/// 1. 空 imageFiles(photoPath 因 camelCase/snake_case 不匹配读不到)→ 照片区
/// 2. 23 个结果能否正常渲染出 AI 结果区
void main() {
  late Directory hiveDir;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_restore_test');
    Hive.init(hiveDir.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    hiveDir.deleteSync(recursive: true);
  });

  testWidgets('恢复模式:空 imageFiles 且 23 个结果 → 结果区正常渲染', (tester) async {
    final results = List.generate(
      23,
      (i) => Vocabulary(
        word: 'word$i',
        translation: '释义$i',
        wordType: 'word',
      ).toMap(),
    );
    final s = SavedSession(
      id: 't1',
      createdAt: DateTime.now(),
      analysisMode: AppConstants.analysisModeMarked,
      results: results,
      fullTextParagraphs: const [],
      followUpMessages: const [],
    );

    await tester.pumpWidget(MaterialApp(
      home: ProcessChatScreen(
        imageFiles: const [],
        analysisMode: AppConstants.analysisModeMarked,
        restoreSession: s,
      ),
    ));
    await tester.pump();

    // 捕获渲染期间的异常(debug 下 ErrorWidget 会被替换为异常报告)
    final err = tester.takeException();
    if (err != null) {
      // ignore: avoid_print
      print('BUILD EXCEPTION: $err');
    }

    // 结果头部应渲染
    expect(find.textContaining('识别完成 · 共 23 个标记'), findsOneWidget,
        reason: '恢复会话后应显示结果摘要头部');
    // 词汇应渲染
    expect(find.text('word0'), findsOneWidget);
    expect(find.text('word22'), findsOneWidget);
  });
}
