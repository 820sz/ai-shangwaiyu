import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/screens/input/material_center_screen.dart'
    show BandAdviceBanner;
import 'package:readflow/services/database.dart';
import 'package:readflow/services/input_prefs.dart';

/// 批 7(P1-2)难度档「软件辅助调整」UI 回归。
///
/// 这条链路的纪律是**"没数据不许猜,有数据才建议,决定权在用户"**:
/// 1. 展示条件收口在 [BandAdvice] —— 没有建议 / 建议档=当前档 → 零占位,
///    不允许界面为了"功能存在感"留空行或弹窗;
/// 2. 建议正文必须带真实依据(读完率/查词密度/测验正确率),数字来自
///    `loadBandSignals` 的 SQLite 聚合,不是编的;
/// 3. 点「调到 i+X」才真的写偏好,且写的是 MaterialPrefs.band(全 App 同一份);
/// 4. 建议条 widget 在 320 宽下不溢出(低端机/大字号是项目已有的坑)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BandSuggestion suggestionTo(DifficultyBand band) => BandSuggestion(
        band: band,
        text: '读完率 92%、查词 2.1 次/100 词 —— 现在这档偏轻松,'
            '建议升到「${band.label}」,给自己加一点难度',
      );

  group('BandAdvice 展示条件:只在"有建议且不等于当前档"时显示', () {
    test('没有建议(suggestion=null)→ 不显示、不占位', () {
      const advice = BandAdvice(current: DifficultyBand.challenge);
      expect(advice.shouldShow, isFalse);
      expect(advice.line, isNull);
      expect(advice.actionLabel, isNull);
    });

    test('建议档 == 当前档(防御性判断)→ 也不显示(同档建议是白占一行)', () {
      final advice = BandAdvice(
        current: DifficultyBand.challenge,
        suggestion: suggestionTo(DifficultyBand.challenge),
      );
      expect(advice.shouldShow, isFalse);
      expect(advice.line, isNull);
      expect(advice.actionLabel, isNull);
    });

    test('建议档 ≠ 当前档 → 显示文案 + 一键按钮,窗口天数不写死', () {
      final advice = BandAdvice(
        current: DifficultyBand.challenge,
        days: 7,
        suggestion: suggestionTo(DifficultyBand.fastGain),
      );
      expect(advice.shouldShow, isTrue);
      expect(advice.line, contains('按最近 7 天表现'));
      expect(advice.line, contains('读完率 92%'));
      expect(advice.actionLabel, '调到 i+100 快反馈');
    });
  });

  group('suggestBand → 展示条件(只有真信号才给建议)', () {
    test('两个升档信号 → 给出升一档建议,可显示', () {
      final advice = BandAdvice(
        current: DifficultyBand.challenge,
        suggestion: suggestBand(
          finishedRatio: 0.92,
          avgLookupPer100: 2.1,
          quizAccuracy: 0.9,
          current: DifficultyBand.challenge,
        ),
      );
      expect(advice.shouldShow, isTrue);
      expect(advice.suggestion!.band, DifficultyBand.fastGain);
    });

    test('两个降档信号 → 给出降一档建议,可显示', () {
      final advice = BandAdvice(
        current: DifficultyBand.challenge,
        suggestion: suggestBand(
          finishedRatio: 0.2,
          avgLookupPer100: 30,
          quizAccuracy: 0.3,
          current: DifficultyBand.challenge,
        ),
      );
      expect(advice.shouldShow, isTrue);
      expect(advice.suggestion!.band, DifficultyBand.comfortable);
    });

    test('数据不足(只有 1 个指标)→ 不显示', () {
      final advice = BandAdvice(
        current: DifficultyBand.challenge,
        suggestion: suggestBand(
          finishedRatio: 0.95,
          avgLookupPer100: null,
          quizAccuracy: null,
          current: DifficultyBand.challenge,
        ),
      );
      expect(advice.shouldShow, isFalse);
    });

    test('当前档=不限 / 已在升档端点 → 不显示(算法语义,不额外造规则)', () {
      expect(
        BandAdvice(
          current: DifficultyBand.any,
          suggestion: suggestBand(
            finishedRatio: 0.2,
            avgLookupPer100: 30,
            quizAccuracy: 0.2,
            current: DifficultyBand.any,
          ),
        ).shouldShow,
        isFalse,
      );
      expect(
        BandAdvice(
          current: DifficultyBand.fastGain,
          suggestion: suggestBand(
            finishedRatio: 0.95,
            avgLookupPer100: 1,
            quizAccuracy: 0.95,
            current: DifficultyBand.fastGain,
          ),
        ).shouldShow,
        isFalse,
      );
    });
  });

  group('BandAdviceBanner(两个入口共用的建议条)', () {
    Widget host(Widget child, {double width = 320}) => MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(child: SizedBox(width: width, child: child)),
          ),
        );

    testWidgets('没有建议 → 高度 0(卡内不留空行)', (tester) async {
      await tester.pumpWidget(host(BandAdviceBanner(
        advice: const BandAdvice(current: DifficultyBand.challenge),
        onApply: () {},
      )));
      expect(find.byType(Text), findsNothing);
      // 宽度由外层 SizedBox 给,这里要钉的是"没有占任何高度"
      expect(tester.getSize(find.byType(BandAdviceBanner)).height, 0);
    });

    testWidgets('有建议 → 文案带依据、按钮文案是目标档,点一下触发应用', (tester) async {
      var applied = 0;
      await tester.pumpWidget(host(BandAdviceBanner(
        advice: BandAdvice(
          current: DifficultyBand.challenge,
          suggestion: suggestionTo(DifficultyBand.fastGain),
        ),
        onApply: () => applied++,
      )));
      expect(find.textContaining('按最近 30 天表现'), findsOneWidget);
      expect(find.textContaining('读完率 92%'), findsOneWidget);
      final button = find.text('调到 i+100 快反馈');
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(applied, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('320 宽 + 长建议文案不溢出(窄屏真实场景)', (tester) async {
      await tester.pumpWidget(host(BandAdviceBanner(
        advice: BandAdvice(
          current: DifficultyBand.comfortable,
          suggestion: BandSuggestion(
            band: DifficultyBand.challenge,
            text: '读完率 85%、查词 2.4 次/100 词、测验正确率 88% —— '
                '现在这档偏轻松,建议升到「i+10 挑战」,给自己加一点难度',
          ),
        ),
        onApply: () {},
      )));
      expect(tester.takeException(), isNull);
    });
  });

  group('loadBandSignals:真实使用数据口径(真 SQLite)', () {
    late Directory tmp;
    final now = DateTime(2026, 11, 2, 12);

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rf_band_signals_test');
      await databaseFactory.setDatabasesPath(tmp.path);
      await DatabaseService.resetForTest();
    });

    tearDown(() async {
      await DatabaseService.resetForTest();
      try {
        await databaseFactory
            .deleteDatabase(p.join(tmp.path, AppConstants.dbName));
      } catch (_) {}
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    String iso(DateTime t) => t.toIso8601String();

    Future<int> insertMaterial({
      required String title,
      required int wordCount,
      required double? percent,
      required int lookups,
      required DateTime? readAt,
      required bool finished,
    }) async {
      final db = await DatabaseService.database;
      final id = await db.insert('materials', {
        'kind': 'book',
        'source': 'test',
        'title': title,
        'word_count': wordCount,
        'created_at': iso(now.subtract(const Duration(days: 30))),
      });
      if (readAt != null) {
        await db.insert('material_progress', {
          'material_id': id,
          'position': 0,
          'percent': percent ?? 0,
          'minutes': 20,
          'lookups': lookups,
          'picked_words': 0,
          'started_at': iso(readAt.subtract(const Duration(hours: 1))),
          'finished_at': finished ? iso(readAt) : null,
          'updated_at': iso(readAt),
        });
      }
      return id;
    }

    Future<void> insertQuiz(String kind, int correct, int total) async {
      final db = await DatabaseService.database;
      await db.insert('quiz_results', {
        'kind': kind,
        'total': total,
        'correct': correct,
        'created_at': iso(now.subtract(const Duration(days: 2))),
      });
    }

    test('读完率 = 读过的材料里读完的比例;未开始/窗口外的材料不算分母', () async {
      // 读完、读了 100%
      await insertMaterial(
        title: '读完的',
        wordCount: 1000,
        percent: 100,
        lookups: 20,
        readAt: now.subtract(const Duration(days: 1)),
        finished: true,
      );
      // 读了一半、没读完
      await insertMaterial(
        title: '读一半',
        wordCount: 500,
        percent: 50,
        lookups: 10,
        readAt: now.subtract(const Duration(days: 2)),
        finished: false,
      );
      // 入库但从没打开:不该进分母(否则"收藏没读"会被误读成"读不下去")
      await insertMaterial(
        title: '没打开',
        wordCount: 3000,
        percent: null,
        lookups: 0,
        readAt: null,
        finished: false,
      );
      // 窗口外(60 天前)读完的:不计入 30 天口径
      await insertMaterial(
        title: '上个月读完的',
        wordCount: 800,
        percent: 100,
        lookups: 30,
        readAt: now.subtract(const Duration(days: 60)),
        finished: true,
      );

      final signals = await loadBandSignals(now: now, days: 30);
      expect(signals.finishedRatio, closeTo(0.5, 1e-9));
      // 查词密度 = (20+10) / 估算已读词数(1000 + 500*50%) * 100 = 2.4
      expect(signals.avgLookupPer100, closeTo(2.4, 1e-9));
      // 没有测验记录 → null(不把"没做过"当成 0 分)
      expect(signals.quizAccuracy, isNull);
    });

    test('查词样本 <200 词 → 不给查词密度(小样本会算出噪声级别的大数)', () async {
      await insertMaterial(
        title: '很短的一篇',
        wordCount: 100,
        percent: 100,
        lookups: 1,
        readAt: now.subtract(const Duration(days: 1)),
        finished: true,
      );
      final signals = await loadBandSignals(now: now, days: 30);
      expect(signals.finishedRatio, closeTo(1.0, 1e-9));
      expect(signals.avgLookupPer100, isNull);
    });

    test('测验正确率:优先读后测验(而不是把别的测验混进来)', () async {
      await insertQuiz('reading_comprehension', 9, 10);
      await insertQuiz('vocab_placement', 5, 10);
      expect(
        (await loadBandSignals(now: now, days: 30)).quizAccuracy,
        closeTo(0.9, 1e-9),
        reason: '有 reading_comprehension 就只读它',
      );
    });

    test('没有读后测验时,用非词汇量类测验的平均(词汇量测试不代表难度合身)', () async {
      await insertQuiz('cloze', 8, 10); // 0.8
      await insertQuiz('reading', 6, 10); // 0.6
      await insertQuiz('vocab_placement', 5, 10); // 水平测量,不参与
      expect(
        (await loadBandSignals(now: now, days: 30)).quizAccuracy,
        closeTo(0.7, 1e-9),
        reason: '(0.8 + 0.6) / 2',
      );
    });

    test('完全没读过材料 → finishedRatio 为 null(不是 0:没数据≠读不进去)', () async {
      final signals = await loadBandSignals(now: now, days: 30);
      expect(signals.finishedRatio, isNull);
      expect(signals.avgLookupPer100, isNull);
      expect(signals.quizAccuracy, isNull);
    });
  });
}
