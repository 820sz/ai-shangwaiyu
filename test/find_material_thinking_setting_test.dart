import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/free_search_screen.dart';
import 'package:readflow/services/input_prefs.dart';
import 'package:readflow/services/material_ai_rewrite.dart';
import 'package:readflow/widgets/material_result_list.dart';

/// 「AI 思考强度」设置(task-22 · 2026-11-08 用户要求"在哪看/调;搜索要发挥满 AI")。
///
/// 这里钉住 4 件事:
/// 1. **三档 × 两类任务的真实映射**(纯函数):快/标准/深入 → 合法 thinkingLevel;
/// 2. **持久化**:保存后能读回(Hive 异常时回落标准,页面照常能开);
/// 3. **4 处调用点都读设置**(源码闸门:规划×2、补救轮、AI 改写各一处);
/// 4. **UI 可切换**:自由搜「筛选」面板底部能看到/切换档位;AI 改写结果卡
///    显示本次实际使用的档位(用户"能看见发挥了什么")。
void main() {
  setUp(() {
    AiThinkingLevel.debugReset();
    AiThinkingLevel.debugStore = <String, Object?>{};
    MaterialCoverProbeCache.debugReset();
    MaterialCoverProbeCache.debugOverride = (_) async => null;
  });

  tearDown(() {
    AiThinkingLevel.debugReset();
    MaterialCoverProbeCache.debugReset();
  });

  group('三档映射(纯函数)', () {
    test('快:规划 disabled / 改写 low', () {
      expect(AiThinkingLevel.fast.levelFor(FindMaterialAiTask.plan), 'disabled');
      expect(AiThinkingLevel.fast.levelFor(FindMaterialAiTask.rewrite), 'low');
    });

    test('标准(默认):规划 low / 改写 high —— 改造前质量基线', () {
      expect(AiThinkingLevel.standard.levelFor(FindMaterialAiTask.plan), 'low');
      expect(
        AiThinkingLevel.standard.levelFor(FindMaterialAiTask.rewrite),
        'high',
      );
      expect(AiThinkingLevel.fallback, AiThinkingLevel.standard);
    });

    test('深入:规划 high / 改写 max —— 用户点名"发挥满 AI"', () {
      expect(AiThinkingLevel.deep.levelFor(FindMaterialAiTask.plan), 'high');
      expect(AiThinkingLevel.deep.levelFor(FindMaterialAiTask.rewrite), 'max');
    });

    test('所有映射值都是 DeepSeek 官方合法档位(非法值会被静默降级成不思考)', () {
      const legal = <String>{'disabled', 'low', 'high', 'max'};
      for (final level in AiThinkingLevel.values) {
        for (final task in FindMaterialAiTask.values) {
          expect(legal, contains(level.levelFor(task)));
        }
      }
    });

    test('parse:认识三个名字,不认识 → 标准(不抛)', () {
      expect(AiThinkingLevel.parse('fast'), AiThinkingLevel.fast);
      expect(AiThinkingLevel.parse('deep'), AiThinkingLevel.deep);
      expect(AiThinkingLevel.parse('standard'), AiThinkingLevel.standard);
      expect(AiThinkingLevel.parse('output'), AiThinkingLevel.standard);
      expect(AiThinkingLevel.parse(null), AiThinkingLevel.standard);
    });
  });

  group('持久化(Hive settings,正式包零迁移)', () {
    test('保存后能读回;hiveKey 稳定', () async {
      expect(AiThinkingLevel.hiveKey, 'find_material_ai_thinking');
      expect(AiThinkingLevel.load(), AiThinkingLevel.standard,
          reason: '默认必须是标准,不能默认"深入"拖慢每次搜索');
      expect(await AiThinkingLevel.save(AiThinkingLevel.deep), isTrue);
      expect(AiThinkingLevel.load(), AiThinkingLevel.deep);
      expect(AiThinkingLevel.debugStore?[AiThinkingLevel.hiveKey], 'deep');
    });

    test('存储不可用(无 Hive box)→ 回落标准,不抛', () async {
      AiThinkingLevel.debugStore = null; // 走真实 Hive:测试环境未打开 → 异常分支
      expect(AiThinkingLevel.load, returnsNormally);
      expect(AiThinkingLevel.load(), AiThinkingLevel.standard);
    });
  });

  group('4 处调用点都读同一份设置(源码闸门)', () {
    String read(String path) => File(path).readAsStringSync();

    test('规划 ×2 + 补救轮 + AI 改写 各有一处读取', () {
      final planner = read('lib/services/search_query_planner.dart');
      final discovery = read('lib/services/material_discovery.dart');
      final rewrite = read('lib/services/material_ai_rewrite.dart');

      // ① 自由搜检索词规划 ② 按需搜意图规划(同一文件两处)
      expect(RegExp(r'AiThinkingLevel\.load\(\)\.planLevel').allMatches(planner).length, 2,
          reason: '两个默认规划 handler 都必须读设置');
      // ③ 补救轮 refine
      expect(RegExp(r'AiThinkingLevel\.load\(\)\.planLevel').allMatches(discovery).length, 1,
          reason: 'defaultMaterialRefine 必须读设置');
      // ④ AI 改写
      expect(RegExp(r'AiThinkingLevel\.load\(\)\.rewriteLevel').allMatches(rewrite).length, 1,
          reason: 'defaultMaterialAiRewriteHandler 必须读设置');
    });

    test('全库不再有非法档位字面量 thinkingLevel: \'output\'', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains("thinkingLevel: 'output'")) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: "'output' 是任务名不是档位值,会被静默降级成不思考:\n"
              '${offenders.join('\n')}');
    });
  });

  group('自由搜 UI:筛选面板底部可看/可调', () {
    void phoneView(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: screen),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('打开筛选 → 看到「AI 思考强度:快/标准/深入」,切到深入即持久化',
        (tester) async {
      phoneView(tester);
      await pumpScreen(tester, const FreeSearchScreen());
      await tester.tap(find.byKey(const ValueKey('free-filter-toggle')));
      await tester.pump();
      expect(find.text('AI 思考强度'), findsOneWidget);
      await tester.ensureVisible(find.text('深入'));
      expect(find.text('快'), findsOneWidget);
      expect(find.text('标准'), findsOneWidget);
      expect(find.text('深入'), findsOneWidget);

      await tester.tap(find.text('深入'));
      await tester.pump();
      expect(AiThinkingLevel.load(), AiThinkingLevel.deep, reason: '切档要落 Hive');
      expect(find.textContaining('质量优先'), findsWidgets,
          reason: '选中档位要有一句作用说明');
    });

    testWidgets('AI 改写结果卡显示本次实际使用的思考强度', (tester) async {
      phoneView(tester);
      final body = List<String>.generate(
        140,
        (i) => i.isEven ? 'habit' : 'change',
      ).join(' ');
      final json = '```json\n'
          '{"topic": "Small Habits, Big Changes", '
          '"title_cn": "微小习惯,巨大改变", '
          '"summary_cn": "基于线索改写的学习版。", '
          '"body": "$body", '
          '"used_sources": [1]}\n```';
      final rewriter = MaterialAiRewriter(
        level: AiThinkingLevel.deep,
        handler: (_, _) async => json,
        measurer: (_) async => const AiRewriteMeasurement(
          wordCount: 140,
          estMinutes: 2,
          coverage: 0.955,
          cefr: 'B1',
        ),
      );
      await pumpScreen(
        tester,
        FreeSearchScreen(
          initialQuery: '原子习惯',
          initialResults: const <MaterialResultItem>[],
          debugSources: const <AiRewriteSource>[
            AiRewriteSource(
              title: 'Atomic Habits — James Clear',
              url: 'https://example.com/atomic-habits',
              site: 'example.com',
              snippet: '习惯养成与微小改变。',
              kind: 'book',
            ),
          ],
          debugNotes: const <String>['Project Gutenberg:没有匹配的原文'],
          aiRewriter: rewriter,
        ),
      );
      final generate = find.text('生成 AI 改写学习版(非原文)');
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 400));
      final confirm = find.text('开始生成 AI 改写学习版（非原文）');
      expect(confirm, findsOneWidget, reason: '生成前先弹改写选项');
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(find.textContaining('思考强度:深入'), findsOneWidget,
          reason: '用户要能看见这次到底发挥了多少 AI 能力');
    });
  });
}
