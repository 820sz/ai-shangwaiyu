import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/screens/input/need_search_screen.dart';
import 'package:readflow/services/material_library.dart';
import 'package:readflow/services/material_need.dart';
import 'package:readflow/services/material_prefs.dart';
import 'package:readflow/widgets/material_result_list.dart';

/// 2026-11-07 用户真机反馈：覆盖率 0% 的卡片还显示「为什么推:难度 0%」。
/// 这里钉住「为什么推」的阈值：没有真实分析 / 覆盖率过低 → 不显示理由。
void main() {
  MaterialResultItem item({double? coverage}) => MaterialResultItem(
        title: 'CET-4 真题 2024 阅读',
        url: 'https://example.com/cet4/2024',
        sourceLabel: 'DeepSeek 搜索',
        kind: 'exam',
        seq: 0,
        analysis: coverage == null
            ? null
            : MaterialAnalysis(
                wordCount: 1000,
                uniqueWords: 400,
                newTypes: 50,
                estMinutes: 6,
                coverage: coverage,
                knownTokenRatio: coverage,
                newWordDensity: 5,
                cefr: 'B1',
                topNewWords: const <String>[],
              ),
      );

  group('needSearchReasonFor — 理由阈值', () {
    test('没有 analysis（没抓正文）→ 不显示理由', () {
      expect(
        needSearchReasonFor(
          item: item(),
          need: const MaterialNeed(),
          goals: const <String>[],
        ),
        isNull,
      );
    });

    test('覆盖率 0% / 5% / 9% → 不显示理由（低于阈值 10%）', () {
      for (final coverage in <double>[0.0, 0.05, 0.09]) {
        expect(
          needSearchReasonFor(
            item: item(coverage: coverage),
            need: const MaterialNeed(band: MaterialBand.i10),
            goals: const <String>['四六级'],
          ),
          isNull,
          reason: '覆盖率 $coverage 低于阈值时不该显示「为什么推」',
        );
      }
    });

    test('覆盖率 ≥ 10% → 显示理由，且带真实数字/难度档/目标', () {
      final reason = needSearchReasonFor(
        item: item(coverage: 0.96),
        need: const MaterialNeed(band: MaterialBand.i10),
        goals: const <String>['四六级'],
      );
      expect(reason, isNotNull);
      expect(reason, contains('为什么推'));
      expect(reason, contains('96%'));
      expect(reason, contains('i+10'));
      expect(reason, contains('四六级'));
    });

    test('阈值常量 = 0.10（与注释口径一致）', () {
      expect(needSearchMinReasonCoverage, 0.10);
      // 恰好等于阈值时应显示（条件用的是 <）
      expect(
        needSearchReasonFor(
          item: item(coverage: needSearchMinReasonCoverage),
          need: const MaterialNeed(),
          goals: const <String>[],
        ),
        isNotNull,
      );
    });
  });
}
